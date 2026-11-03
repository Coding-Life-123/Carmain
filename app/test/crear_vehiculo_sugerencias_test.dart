import 'dart:async';

import 'package:car_main/data/vehiculo_repository.dart';
import 'package:car_main/database/database.dart';
import 'package:car_main/models/componente.dart';
import 'package:car_main/models/enums.dart';
import 'package:car_main/models/motorizacion.dart';
import 'package:car_main/models/vehiculo.dart';
import 'package:car_main/providers/providers.dart';
import 'package:car_main/screens/crear_vehiculo/crear_vehiculo_screen.dart';
import 'package:car_main/services/api_client.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresiones del autollenado y del modo edición de CrearVehiculoScreen.
///
/// 1. Buscar OTRO vehículo debe rellenar motor/caja aunque el anterior se
///    hubiera llenado por autollenado o chip (bug: la elección del vehículo
///    anterior bloqueaba los campos para siempre).
/// 2. Un código tecleado a mano (motor swap) SÍ sobrevive el cambio de
///    vehículo — es intención del usuario, no un dato del chasis.
/// 3. Abrir el modo edición no debe disparar una búsqueda de motorización
///    (llamada a Gemini desperdiciada + fila de estado en un formulario ya
///    completo), y guardar debe conservar los campos de swap que el
///    formulario no edita.
void main() {
  /// Avanza el debounce de búsqueda (800ms) y las notificaciones del
  /// provider hasta que las sugerencias se aplican a los campos.
  Future<void> pumpBusqueda(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// El campo de código de motor (0) o de transmisión (1).
  TextFormField campoCodigo(WidgetTester tester, int index) =>
      tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Código *').at(index));

  /// Campo de texto por su label exacto.
  TextFormField campoConLabel(WidgetTester tester, String label) =>
      tester.widget<TextFormField>(find.widgetWithText(TextFormField, label));

  testWidgets(
      'chip del vehículo anterior no bloquea el autollenado del nuevo',
      (tester) async {
    final api = _ApiClientFake();
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: const MaterialApp(home: CrearVehiculoScreen()),
    ));

    // Vehículo A: dos motores → el autollenado toma el primero y los
    // chips de alternativas quedan visibles.
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Marca *'), 'Toyota');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Modelo *'), 'Corolla');
    await tester.enterText(find.widgetWithText(TextFormField, 'Año *'), '2020');
    await pumpBusqueda(tester);
    expect(campoCodigo(tester, 0).controller?.text, 'MOTOR-A1');
    expect(campoCodigo(tester, 1).controller?.text, 'CAJA-A');
    expect(campoConLabel(tester, 'Potencia (HP, opcional)').controller?.text,
        '200');
    expect(campoConLabel(tester, 'Torque (Nm, opcional)').controller?.text,
        '300');

    // Elección explícita por chip — lo que antes bloqueaba para siempre.
    // MOTOR-A2 no trae potencia: el campo debe quedar LIMPIO, no conservar
    // los 200 HP de MOTOR-A1 (regresión del dato de otro motor).
    await tester.ensureVisible(find.text('MOTOR-A2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MOTOR-A2'));
    await tester.pump();
    expect(campoCodigo(tester, 0).controller?.text, 'MOTOR-A2');
    expect(campoConLabel(tester, 'Potencia (HP, opcional)').controller?.text,
        '');

    // Vehículo B: debe rellenar motor y caja con lo suyo.
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Modelo *'), 'Supra');
    await pumpBusqueda(tester);
    expect(campoCodigo(tester, 0).controller?.text, 'MOTOR-B');
    expect(campoCodigo(tester, 1).controller?.text, 'CAJA-B');
    expect(campoConLabel(tester, 'Potencia (HP, opcional)').controller?.text,
        '260');
    expect(campoConLabel(tester, 'Torque (Nm, opcional)').controller?.text,
        '400');
  });

  testWidgets(
      'respuesta en vuelo del código tecleado no pisa la elección por chip',
      (tester) async {
    final api = _ApiClientFake();
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: const MaterialApp(home: CrearVehiculoScreen()),
    ));

    // Vehículo A: dos motores → chips visibles; A1 autollena 200 HP.
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Marca *'), 'Toyota');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Modelo *'), 'Corolla');
    await tester.enterText(find.widgetWithText(TextFormField, 'Año *'), '2020');
    await pumpBusqueda(tester);

    // El usuario teclea un código y su búsqueda queda en vuelo.
    final motorEnVuelo = Completer<OpcionMotor?>();
    api.motorPendiente = motorEnVuelo;
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Código *').at(0), '1JZ-GTE');
    await tester.pump(
        const Duration(milliseconds: 900)); // dispara la búsqueda por código

    // Elige el chip del segundo motor ANTES de que responda el código.
    await tester.ensureVisible(find.text('MOTOR-A2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MOTOR-A2'));
    await tester.pump();

    // La respuesta del código llega tarde: no debe pisar la elección.
    motorEnVuelo.complete(OpcionMotor(
      codigo: '1JZ-GTE',
      descripcion: '3.0L I6 biturbo',
      potenciaHp: 500,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(campoCodigo(tester, 0).controller?.text, 'MOTOR-A2');
    expect(
        campoConLabel(tester, 'Potencia (HP, opcional)').controller?.text, '');
  });

  testWidgets('código tecleado a mano sobrevive el cambio de vehículo',
      (tester) async {
    final api = _ApiClientFake();
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: const MaterialApp(home: CrearVehiculoScreen()),
    ));

    // Vehículo A autollena.
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Marca *'), 'Toyota');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Modelo *'), 'Corolla');
    await tester.enterText(find.widgetWithText(TextFormField, 'Año *'), '2020');
    await pumpBusqueda(tester);
    expect(campoCodigo(tester, 0).controller?.text, 'MOTOR-A1');

    // El usuario teclea su propio código (motor swap).
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Código *').at(0), '1JZ-GTE');
    await tester.pump(
        const Duration(milliseconds: 900)); // debounce de info por código

    // Vehículo B: el código tecleado se conserva; la caja sí se actualiza.
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Modelo *'), 'Supra');
    await pumpBusqueda(tester);
    expect(campoCodigo(tester, 0).controller?.text, '1JZ-GTE');
    expect(campoCodigo(tester, 1).controller?.text, 'CAJA-B');
  });

  testWidgets(
      'modo edición: sin búsqueda espuria y conserva los campos de swap',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = VehiculoRepository(db);
    final existente = _vehiculoConSwap();
    await repo.saveVehiculo(existente);

    final api = _ApiClientFake();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        apiClientProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    CrearVehiculoScreen(vehiculoExistente: existente),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // Ventana completa del debounce: si el prefill disparara la búsqueda
    // (bug), la llamada al backend ocurriría aquí.
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.llamadasMotorizacion, 0,
        reason: 'abrir el modo edición no debe buscar motorizaciones');

    // Guardar sin cambiar nada (configCambio=false).
    await tester.ensureVisible(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    // Los campos de swap que el formulario no edita sobreviven la edición.
    final guardado = await repo.getVehiculo(existente.id);
    expect(guardado, isNotNull);
    expect(guardado!.motor.esOriginal, isFalse);
    expect(guardado.motor.originalCodigo, '2JZ-GE');
    expect(guardado.motor.fuente, FuenteComponente.swap);
    expect(guardado.motor.potenciaHp, 276);
    expect(guardado.motor.torqueNm, 451);
    expect(guardado.transmision.esOriginal, isFalse);
    expect(guardado.transmision.originalCodigo, 'W58');
    expect(guardado.transmision.fuente, FuenteComponente.swap);
  });

  testWidgets('detección automática de swap al escribir motor no OEM',
      (tester) async {
    final api = _ApiClientFake();
    final db = AppDatabase(NativeDatabase.memory());
    final repo = VehiculoRepository(db);
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        repositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: CrearVehiculoScreen()),
    ));

    // Llenar datos de chasis para disparar sugerencias de Corolla
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Marca *'), 'Toyota');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Modelo *'), 'Corolla');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Año *'), '2020');
    await pumpBusqueda(tester);

    // Por defecto se autollena MOTOR-A1 y el badge dice Motor original / OEM
    expect(find.text('Motor original / OEM'), findsOneWidget);

    // Escribir un motor no listado en sugerencias: 2JZ-GTE
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Código *').first, '2JZ-GTE');
    await tester.pumpAndSettle();

    // Se detecta automáticamente como swap
    expect(find.text('Motor Swap detectado'), findsOneWidget);
    expect(find.text('Original de fábrica: MOTOR-A1'), findsOneWidget);

    // El selector de "Mantenimientos al día" está presente en creación
    expect(find.text('Mantenimientos al día'), findsOneWidget);
  });

  testWidgets(
      'modo edición de vehículo OEM: cambiar código de motor detecta swap y guarda código original',
      (tester) async {
    final api = _ApiClientFake();
    final db = AppDatabase(NativeDatabase.memory());
    final repo = VehiculoRepository(db);
    addTearDown(db.close);

    final vehiculoOem = Vehiculo(
      id: 'v-oem-evolucion',
      propietarioId: 'local',
      marca: 'Honda',
      modelo: 'Civic',
      anio: 1998,
      drivetrain: Drivetrain.fwd,
      motor: const Motor(
        codigo: 'D16Y8',
        esOriginal: true,
        fuente: FuenteComponente.oem,
        tipoCombustible: TipoCombustible.gasolina,
      ),
      transmision: const Transmision(
        codigo: 'S40',
        esOriginal: true,
        fuente: FuenteComponente.oem,
        tipo: TipoTransmision.manual,
      ),
      kilometrajeActual: 140000,
    );
    await repo.saveVehiculo(vehiculoOem);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        repositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        home: CrearVehiculoScreen(vehiculoExistente: vehiculoOem),
      ),
    ));
    await tester.pumpAndSettle();

    // Arranca como OEM
    expect(find.text('Motor original / OEM'), findsOneWidget);

    // El dueño instala un B18C1 y actualiza el código en modo edición
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Código *').first, 'B18C1');
    await tester.pumpAndSettle();

    // Se detecta el swap comparando contra el motor OEM que tenía antes
    expect(find.text('Motor Swap detectado'), findsOneWidget);
    expect(find.text('Original de fábrica: D16Y8'), findsOneWidget);
  });
}

/// ApiClient falso con sugerencias distintas por modelo, para verificar
/// qué vehículo llenó los campos. Cuenta las búsquedas de motorización
/// (regresión del modo edición).
class _ApiClientFake extends ApiClient {
  int llamadasMotorizacion = 0;

  /// Cuando está seteado, la próxima búsqueda por código de motor queda
  /// pendiente hasta que el test la complete (para probar respuestas
  /// que llegan tarde).
  Completer<OpcionMotor?>? motorPendiente;

  @override
  Future<SugerenciasMotorizacion?> buscarMotorizacion({
    required String marca,
    required String modelo,
    required int anio,
    String? trim,
  }) async {
    llamadasMotorizacion++;
    switch (modelo) {
      case 'Corolla':
        return SugerenciasMotorizacion(
          motores: const [
            OpcionMotor(codigo: 'MOTOR-A1', potenciaHp: 200, torqueNm: 300),
            OpcionMotor(codigo: 'MOTOR-A2'),
          ],
          transmisiones: const [OpcionTransmision(codigo: 'CAJA-A')],
        );
      case 'Supra':
        return SugerenciasMotorizacion(
          motores: const [
            OpcionMotor(codigo: 'MOTOR-B', potenciaHp: 260, torqueNm: 400),
          ],
          transmisiones: const [OpcionTransmision(codigo: 'CAJA-B')],
        );
      default:
        return null;
    }
  }

  @override
  Future<OpcionMotor?> buscarComponenteMotor(String codigo) async {
    final pendiente = motorPendiente;
    if (pendiente != null) {
      motorPendiente = null; // una sola búsqueda pendiente por test
      return pendiente.future;
    }
    return null;
  }

  @override
  Future<OpcionTransmision?> buscarComponenteTransmision(String codigo) async =>
      null;
}

/// Vehículo con motor y caja swapeados — los campos que el formulario de
/// edición no muestra pero debe conservar al guardar.
Vehiculo _vehiculoConSwap() => Vehiculo(
      id: 'v-edit',
      propietarioId: 'local',
      marca: 'Toyota',
      modelo: 'Supra',
      anio: 1997,
      drivetrain: Drivetrain.rwd,
      motor: Motor(
        codigo: '2JZ-GTE',
        descripcion: '3.0L I6 biturbo (swap)',
        fabricante: 'Toyota',
        esOriginal: false,
        originalCodigo: '2JZ-GE',
        fuente: FuenteComponente.swap,
        tipoCombustible: TipoCombustible.gasolina,
        cilindrada: 3.0,
        cilindros: 6,
        aspiracion: 'Twin-Turbo',
        potenciaHp: 276,
        torqueNm: 451,
      ),
      transmision: Transmision(
        codigo: 'R154',
        fabricante: 'Aisin',
        esOriginal: false,
        originalCodigo: 'W58',
        fuente: FuenteComponente.swap,
        tipo: TipoTransmision.manual,
        marchas: 5,
      ),
      kilometrajeActual: 95000,
    );
