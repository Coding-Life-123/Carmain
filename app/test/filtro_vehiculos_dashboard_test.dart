import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_main/models/componente.dart';
import 'package:car_main/models/enums.dart';
import 'package:car_main/models/plan_mantenimiento.dart';
import 'package:car_main/models/vehiculo.dart';
import 'package:car_main/providers/providers.dart';
import 'package:car_main/screens/dashboard/dashboard_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final vehiculo1 = Vehiculo(
    id: 'v-1',
    propietarioId: 'local',
    marca: 'Toyota',
    modelo: 'Supra',
    anio: 1997,
    placa: 'SUP-970',
    drivetrain: Drivetrain.rwd,
    tipoUso: TipoUso.normal,
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

  final vehiculo2 = Vehiculo(
    id: 'v-2',
    propietarioId: 'local',
    marca: 'Ford',
    modelo: 'F-450 Super Duty',
    anio: 2026,
    placa: 'FRD-450',
    drivetrain: Drivetrain.fourWd,
    tipoUso: TipoUso.severo,
    motor: const Motor(
      codigo: 'PowerStroke-6.7',
      tipoCombustible: TipoCombustible.diesel,
    ),
    transmision: const Transmision(
      codigo: 'TorqShift',
      tipo: TipoTransmision.automatica,
    ),
    kilometrajeActual: 15000,
  );

  // Plan para Toyota: ítem vencido
  final planV1 = PlanMantenimiento(
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
        ultimaVezKm: 100000, // Vencido (25.000 km transcurridos > 10.000 km)
      ),
    ],
  );

  // Plan para Ford: ítem al día
  final planV2 = PlanMantenimiento(
    id: 'p-2',
    vehiculoId: 'v-2',
    version: 1,
    fechaGeneracion: DateTime(2026),
    items: const [
      ItemMantenimiento(
        id: 'i-2',
        categoria: CategoriaMantenimiento.motor,
        descripcion: 'Aceite de motor HD',
        componenteAplica: TipoComponente.motor,
        intervaloKm: 10000,
        ultimaVezKm: 14000, // Al día (solo 1.000 km transcurridos)
      ),
    ],
  );

  Widget crearAppPrueba() {
    return ProviderScope(
      overrides: [
        conexionServidorProvider.overrideWith((ref) => Future.value(true)),
        vehiculosProvider.overrideWith((ref) => Future.value([vehiculo1, vehiculo2])),
        planProvider('v-1').overrideWith((ref) => Future.value(planV1)),
        planProvider('v-2').overrideWith((ref) => Future.value(planV2)),
      ],
      child: const MaterialApp(
        home: DashboardScreen(),
      ),
    );
  }

  testWidgets('filtra vehículos por texto de búsqueda en marca o modelo', (tester) async {
    await tester.pumpWidget(crearAppPrueba());
    await tester.pumpAndSettle();

    // Al inicio se ven ambos vehículos
    expect(find.text('Toyota Supra'), findsOneWidget);
    expect(find.text('Ford F-450 Super Duty'), findsOneWidget);

    // Escribir "Ford" en el buscador
    final campoBusqueda = find.byType(TextField);
    expect(campoBusqueda, findsOneWidget);
    await tester.enterText(campoBusqueda, 'Ford');
    await tester.pumpAndSettle();

    // Solo se ve Ford, Toyota desaparece
    expect(find.text('Ford F-450 Super Duty'), findsOneWidget);
    expect(find.text('Toyota Supra'), findsNothing);

    // Escribir "SUP-970" (placa del Toyota)
    await tester.enterText(campoBusqueda, 'SUP-970');
    await tester.pumpAndSettle();

    expect(find.text('Toyota Supra'), findsOneWidget);
    expect(find.text('Ford F-450 Super Duty'), findsNothing);
  });

  testWidgets('filtra vehículos por chips de estado (Con pendientes y Al día)', (tester) async {
    await tester.pumpWidget(crearAppPrueba());
    await tester.pumpAndSettle();

    // Verificar conteo en chips
    expect(find.text('Todos (2)'), findsOneWidget);
    expect(find.text('Con pendientes (1)'), findsOneWidget);
    expect(find.text('Al día (1)'), findsOneWidget);

    // Filtrar por "Con pendientes"
    await tester.tap(find.text('Con pendientes (1)'));
    await tester.pumpAndSettle();

    // Solo el Toyota (tiene 1 vencido) debe aparecer
    expect(find.text('Toyota Supra'), findsOneWidget);
    expect(find.text('Ford F-450 Super Duty'), findsNothing);

    // Filtrar por "Al día"
    await tester.tap(find.text('Al día (1)'));
    await tester.pumpAndSettle();

    // Solo el Ford (está al día) debe aparecer
    expect(find.text('Ford F-450 Super Duty'), findsOneWidget);
    expect(find.text('Toyota Supra'), findsNothing);

    // Volver a "Todos"
    await tester.tap(find.text('Todos (2)'));
    await tester.pumpAndSettle();

    expect(find.text('Toyota Supra'), findsOneWidget);
    expect(find.text('Ford F-450 Super Duty'), findsOneWidget);
  });

  testWidgets('muestra mensaje vacío y botón para restablecer cuando no hay coincidencias',
      (tester) async {
    await tester.pumpWidget(crearAppPrueba());
    await tester.pumpAndSettle();

    final campoBusqueda = find.byType(TextField);
    await tester.enterText(campoBusqueda, 'VehiculoInexistente');
    await tester.pumpAndSettle();

    expect(find.text('No se encontraron vehículos'), findsOneWidget);
    expect(find.text('Restablecer filtros'), findsOneWidget);

    // Tocar restablecer filtros
    await tester.tap(find.text('Restablecer filtros'));
    await tester.pumpAndSettle();

    expect(find.text('Toyota Supra'), findsOneWidget);
    expect(find.text('Ford F-450 Super Duty'), findsOneWidget);
  });
}
