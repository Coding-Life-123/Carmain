import 'package:flutter/material.dart';
import 'package:car_main/models/componente.dart';
import 'package:car_main/models/enums.dart';
import 'package:car_main/models/plan_mantenimiento.dart';
import 'package:car_main/models/vehiculo.dart';
import 'package:car_main/screens/detalle_vehiculo/detalle_vehiculo_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_main/main.dart';
import 'package:car_main/providers/providers.dart';

void main() {
  testWidgets('App renders dashboard', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // El indicador de conexión probea /api/health contra la URL
        // configurada — en el test no debe tocar la red.
        conexionServidorProvider.overrideWith((ref) => Future.value(true)),
      ],
      child: const CarMainApp(),
    ));

    // Debe mostrar el título CarMain en la AppBar.
    expect(find.text('CarMain'), findsOneWidget);
  });

  testWidgets('Dashboard renders vehicle card with formatted km and overdue pill',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final vehiculoPrueba = Vehiculo(
      id: 'v-1',
      propietarioId: 'local',
      marca: 'Toyota',
      modelo: 'Supra',
      anio: 1997,
      drivetrain: Drivetrain.rwd,
      motor: const Motor(
        codigo: '2JZ-GTE',
        tipoCombustible: TipoCombustible.gasolina,
      ),
      transmision: const Transmision(
        codigo: 'V160',
        tipo: TipoTransmision.manual,
      ),
      kilometrajeActual: 125000,
    );

    final planPrueba = PlanMantenimiento(
      id: 'p-1',
      vehiculoId: 'v-1',
      version: 1,
      fechaGeneracion: DateTime(2026),
      items: const [
        ItemMantenimiento(
          id: 'i-1',
          categoria: CategoriaMantenimiento.motor,
          descripcion: 'Aceite de motor',
          componenteAplica: TipoComponente.motor,
          intervaloKm: 10000,
          ultimaVezKm: 100000, // 25.000 km transcurridos -> vencido
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        conexionServidorProvider.overrideWith((ref) => Future.value(true)),
        vehiculosProvider.overrideWith((ref) => Future.value([vehiculoPrueba])),
        planProvider('v-1').overrideWith((ref) => Future.value(planPrueba)),
      ],
      child: const CarMainApp(),
    ));

    await tester.pumpAndSettle();

    // Nombre completo del auto
    expect(find.text('Toyota Supra'), findsOneWidget);
    // Kilometraje con formato unificado con punto y unidad
    expect(find.text('125.000 km'), findsOneWidget);
    // Pill de mantenimiento vencido
    expect(find.text('1 vencido'), findsOneWidget);
  });

  testWidgets(
      'DetalleVehiculoScreen muestra seccion de ingenieria del swap y badges de vigilancia',
      (WidgetTester tester) async {
    final vehiculoSwap = Vehiculo(
      id: 'v-swap',
      propietarioId: 'local',
      marca: 'Mazda',
      modelo: 'MX-5',
      anio: 1994,
      drivetrain: Drivetrain.rwd,
      motor: const Motor(
        codigo: 'K24A2',
        esOriginal: false,
        originalCodigo: 'BP-ZE',
        fuente: FuenteComponente.swap,
        tipoCombustible: TipoCombustible.gasolina,
        potenciaHp: 220,
        torqueNm: 250,
      ),
      transmision: const Transmision(
        codigo: 'Y5M-R',
        esOriginal: true,
        fuente: FuenteComponente.oem,
        tipo: TipoTransmision.manual,
      ),
      kilometrajeActual: 110000,
    );

    final planConAlertas = PlanMantenimiento(
      id: 'p-swap',
      vehiculoId: 'v-swap',
      version: 1,
      fechaGeneracion: DateTime(2026, 1, 1),
      items: const [
        ItemMantenimiento(
          id: 'item-vigilancia',
          categoria: CategoriaMantenimiento.transmision,
          descripcion: 'Tapón magnético en caja y diferencial',
          componenteAplica: TipoComponente.transmision,
          intervaloKm: 15000,
          esVigilanciaSwap: true,
        ),
      ],
      alertasIngenieria: const [
        AlertaIngenieria(
          id: 'alerta-1',
          vector: VectorEstresSwap.torqueDiferencial,
          severidad: SeveridadIngenieria.alta,
          componenteAfectado: 'Diferencial y Semiejes',
          titulo: 'Sobrecarga de par torsional',
          diagnostico:
              'El torque del K24A2 excede el límite del diferencial de 6".',
          recomendacionUpgrade: 'Upgrade a diferencial Torsen de 7" o 8".',
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        vehiculoProvider('v-swap')
            .overrideWith((ref) => Future.value(vehiculoSwap)),
        planProvider('v-swap')
            .overrideWith((ref) => Future.value(planConAlertas)),
        registrosProvider('v-swap').overrideWith((ref) => Future.value([])),
        kmPorDiaProvider('v-swap').overrideWith((ref) => Future.value(35.0)),
      ],
      child: const MaterialApp(
        home: DetalleVehiculoScreen(vehiculoId: 'v-swap'),
      ),
    ));

    await tester.pumpAndSettle();

    // Sección de Finanzas y Pasaporte Digital
    expect(find.text('Finanzas y Pasaporte Digital'), findsOneWidget);

    // Scroll para ver la sección de alertas de swap
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    // Título de la tarjeta de alertas
    expect(find.text('Ingeniería del Swap y Puntos Críticos'), findsOneWidget);
    // Badge de conteo
    expect(find.text('1 riesgo alto'), findsOneWidget);
    // Título y diagnóstico de la alerta
    expect(find.text('Sobrecarga de par torsional'), findsOneWidget);
    expect(
        find.text(
            'Upgrade sugerido: Upgrade a diferencial Torsen de 7" o 8".'),
        findsOneWidget);

    // Scroll para ver la sección del plan y sus ítems de vigilancia
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    // Badge "Swap" en el ítem de vigilancia preventiva
    expect(find.text('Tapón magnético en caja y diferencial'), findsOneWidget);
    expect(find.text('Swap'), findsWidgets);
  });
}
