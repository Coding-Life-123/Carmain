import 'package:car_main/data/vehiculo_repository.dart';
import 'package:car_main/database/database.dart';
import 'package:car_main/models/componente.dart';
import 'package:car_main/models/enums.dart';
import 'package:car_main/models/plan_mantenimiento.dart';
import 'package:car_main/models/registro_mantenimiento.dart';
import 'package:car_main/models/vehiculo.dart';
import 'package:car_main/providers/providers.dart';
import 'package:car_main/utils/analitica_vehiculo.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests CRUD del repositorio contra una base de datos en memoria.
void main() {
  late AppDatabase db;
  late VehiculoRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = VehiculoRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('saveVehiculo es upsert: actualizar no duplica filas', () async {
    final v = _vehiculo();
    await repo.saveVehiculo(v);

    final actualizado =
        v.copyWith(kilometrajeActual: 150000, modelo: 'Supra RZ');
    await repo.saveVehiculo(actualizado);

    final todos = await repo.getAllVehiculos();
    expect(todos, hasLength(1));
    expect(todos.first.id, v.id); // mismo vehículo, no uno nuevo
    expect(todos.first.modelo, 'Supra RZ');
    expect(todos.first.kilometrajeActual, 150000);
    // Los campos anidados (motor) también se persisten completos.
    expect(todos.first.motor.codigo, '2JZ-GTE');
    expect(todos.first.motor.aspiracion, 'Twin-Turbo');
  });

  test('deleteVehiculo elimina en cascade plan, registros y sesiones',
      () async {
    final v = _vehiculo();
    await repo.saveVehiculo(v);
    await repo.savePlan(_plan(v.id));
    await repo.saveRegistro(_registro(v.id));
    await db.into(db.sesionesMecanico).insert(SesionesMecanicoCompanion(
          id: Value('ses-test'),
          vehiculoId: Value(v.id),
          duenoDeviceId: Value('dev-1'),
          expiresAt: Value(DateTime(2026, 12, 31)),
        ));

    await repo.deleteVehiculo(v.id);

    expect(await repo.getVehiculo(v.id), isNull);
    expect(await repo.getPlan(v.id), isNull);
    expect(await repo.getRegistros(v.id), isEmpty);
    expect(await db.sesionesMecanico.all().get(), isEmpty);
    expect(await repo.getAllVehiculos(), isEmpty);
  });

  test('deleteVehiculo de un id inexistente no lanza error', () async {
    await repo.deleteVehiculo('no-existe');
    expect(await repo.getAllVehiculos(), isEmpty);
  });

  test(
      'replacePlan reemplaza el plan anterior — no quedan dos filas por vehículo',
      () async {
    final v = _vehiculo();
    await repo.saveVehiculo(v);
    await repo.savePlan(_plan(v.id));

    // Editar la configuración técnica regenera el plan con id NUEVO.
    // Antes del fix: savePlan dejaba dos filas con el mismo vehiculoId y
    // getPlan (getSingleOrNull) lanzaba StateError para siempre.
    final regenerado = _plan(v.id, id: 'plan-regenerado');
    await repo.replacePlan(regenerado);

    final plan = await repo.getPlan(v.id);
    expect(plan!.id, 'plan-regenerado');
    expect(await db.planesMantenimiento.all().get(), hasLength(1));
  });

  test('replacePlan sin plan previo inserta (flujo de creación)', () async {
    final v = _vehiculo();
    await repo.saveVehiculo(v);

    await repo.replacePlan(_plan(v.id));

    expect((await repo.getPlan(v.id))!.id, 'plan-test');
    expect(await db.planesMantenimiento.all().get(), hasLength(1));
  });

  test('deleteVehiculo no toca otros vehículos ni sus planes', () async {
    final v1 = _vehiculo();
    final v2 = _vehiculo(id: 'v-otro', codigoMotor: '1JZ-GTE');
    await repo.saveVehiculo(v1);
    await repo.saveVehiculo(v2);
    await repo.savePlan(_plan(v1.id));
    await repo.savePlan(_plan(v2.id, id: 'plan-otro'));

    await repo.deleteVehiculo(v1.id);

    expect(await repo.getVehiculo(v2.id), isNotNull);
    expect((await repo.getPlan(v2.id))!.id, 'plan-otro');
    expect(await repo.getPlan(v1.id), isNull);
  });

  group('saveRegistro lógica de negocio y matching exacto', () {
    test('matching exacto por itemId: cambiar aceite no pisa bujías', () async {
      final v = _vehiculo().copyWith(kilometrajeActual: 60000);
      await repo.saveVehiculo(v);

      const itemAceite = ItemMantenimiento(
        id: 'item-aceite',
        categoria: CategoriaMantenimiento.motor,
        descripcion: 'Cambio de aceite sintético',
        componenteAplica: TipoComponente.motor,
        intervaloKm: 10000,
        ultimaVezKm: 50000,
      );
      const itemBujias = ItemMantenimiento(
        id: 'item-bujias',
        categoria: CategoriaMantenimiento.motor,
        descripcion: 'Bujías de iridio',
        componenteAplica: TipoComponente.motor,
        intervaloKm: 40000,
        ultimaVezKm: 40000,
      );

      final plan = PlanMantenimiento(
        id: 'plan-multi',
        vehiculoId: v.id,
        version: 1,
        fechaGeneracion: DateTime(2026, 1, 1),
        items: const [itemAceite, itemBujias],
      );
      await repo.savePlan(plan);

      // Registrar mantenimiento SOLO de aceite a los 60.000 km
      final registro = RegistroMantenimiento(
        id: 'reg-solo-aceite',
        vehiculoId: v.id,
        fecha: DateTime(2026, 3, 20),
        kilometraje: 60000,
        itemsRealizados: const [
          ItemRealizado(
            itemId: 'item-aceite',
            categoria: CategoriaMantenimiento.motor,
            descripcion: 'Cambio de aceite sintético',
            componenteAplica: TipoComponente.motor,
          ),
        ],
      );
      await repo.saveRegistro(registro);

      final planActualizado = await repo.getPlan(v.id);
      expect(planActualizado, isNotNull);

      final aceiteActual =
          planActualizado!.items.firstWhere((i) => i.id == 'item-aceite');
      final bujiasActual =
          planActualizado.items.firstWhere((i) => i.id == 'item-bujias');

      // Aceite se actualizó al nuevo km
      expect(aceiteActual.ultimaVezKm, 60000);
      expect(aceiteActual.ultimaVezFecha, DateTime(2026, 3, 20));

      // Bujías permaneció INTACTO en 40.000 km (no se reinició)
      expect(bujiasActual.ultimaVezKm, 40000);
    });

    test('sincroniza odómetro si el registro tiene mayor km que el vehículo',
        () async {
      final v = _vehiculo().copyWith(kilometrajeActual: 50000);
      await repo.saveVehiculo(v);
      await repo.savePlan(_plan(v.id));

      final registro = RegistroMantenimiento(
        id: 'reg-nuevo-km',
        vehiculoId: v.id,
        fecha: DateTime(2026, 3, 25),
        kilometraje: 58000, // 58.000 > 50.000
        itemsRealizados: const [
          ItemRealizado(
            categoria: CategoriaMantenimiento.motor,
            descripcion: 'Cambio de aceite',
            componenteAplica: TipoComponente.motor,
          ),
        ],
      );
      await repo.saveRegistro(registro);

      final vehiculoActualizado = await repo.getVehiculo(v.id);
      expect(vehiculoActualizado!.kilometrajeActual, 58000);
    });

    test('registro histórico no degrada el odómetro ni pisa ultimaVezKm más reciente',
        () async {
      final v = _vehiculo().copyWith(kilometrajeActual: 100000);
      await repo.saveVehiculo(v);

      final plan = PlanMantenimiento(
        id: 'plan-hist',
        vehiculoId: v.id,
        version: 1,
        fechaGeneracion: DateTime(2026, 1, 1),
        items: [
          ItemMantenimiento(
            id: 'item-aceite',
            categoria: CategoriaMantenimiento.motor,
            descripcion: 'Cambio de aceite',
            componenteAplica: TipoComponente.motor,
            intervaloKm: 10000,
            ultimaVezKm: 98000,
            ultimaVezFecha: DateTime(2026, 3, 1),
          ),
        ],
      );
      await repo.savePlan(plan);

      // Registrar una factura vieja encontrada a los 80.000 km
      final registroHistorico = RegistroMantenimiento(
        id: 'reg-historico',
        vehiculoId: v.id,
        fecha: DateTime(2025, 8, 1),
        kilometraje: 80000,
        itemsRealizados: const [
          ItemRealizado(
            itemId: 'item-aceite',
            categoria: CategoriaMantenimiento.motor,
            descripcion: 'Cambio de aceite',
            componenteAplica: TipoComponente.motor,
          ),
        ],
      );
      await repo.saveRegistro(registroHistorico);

      // El odómetro del vehículo no bajó a 80.000
      final vehiculoActual = await repo.getVehiculo(v.id);
      expect(vehiculoActual!.kilometrajeActual, 100000);

      // El ítem del plan no retrocedió de 98.000 a 80.000
      final planActual = await repo.getPlan(v.id);
      final itemAceite = planActual!.items.first;
      expect(itemAceite.ultimaVezKm, 98000);
      expect(itemAceite.ultimaVezFecha, DateTime(2026, 3, 1));

      // Pero el registro sí se guardó en el historial
      final registros = await repo.getRegistros(v.id);
      expect(registros.any((r) => r.id == 'reg-historico'), isTrue);
    });
  });

  group('migrarProgresoPlan en swaps de componentes', () {
    test('swap de motor reinicia items de motor pero conserva frenos y chasis', () {
      final vViejo = _vehiculo(codigoMotor: '2JZ-GTE');
      final vNuevo = _vehiculo(codigoMotor: 'LS3'); // Swap de motor

      final planViejo = PlanMantenimiento(
        id: 'plan-v1',
        vehiculoId: vViejo.id,
        version: 1,
        fechaGeneracion: DateTime(2026, 1, 1),
        items: [
          ItemMantenimiento(
            id: 'item-aceite',
            categoria: CategoriaMantenimiento.motor,
            descripcion: 'Aceite de motor',
            componenteAplica: TipoComponente.motor,
            intervaloKm: 10000,
            ultimaVezKm: 50000,
            ultimaVezFecha: DateTime(2026, 2, 1),
          ),
          ItemMantenimiento(
            id: 'item-frenos',
            categoria: CategoriaMantenimiento.frenos,
            descripcion: 'Líquido de frenos',
            componenteAplica: TipoComponente.frenos,
            intervaloKm: 30000,
            ultimaVezKm: 45000,
            ultimaVezFecha: DateTime(2026, 1, 15),
          ),
        ],
      );

      final planNuevo = PlanMantenimiento(
        id: 'plan-v2',
        vehiculoId: vNuevo.id,
        version: 2,
        fechaGeneracion: DateTime(2026, 3, 1),
        items: const [
          ItemMantenimiento(
            id: 'item-aceite',
            categoria: CategoriaMantenimiento.motor,
            descripcion: 'Aceite de motor',
            componenteAplica: TipoComponente.motor,
            intervaloKm: 8000,
          ),
          ItemMantenimiento(
            id: 'item-frenos',
            categoria: CategoriaMantenimiento.frenos,
            descripcion: 'Líquido de frenos',
            componenteAplica: TipoComponente.frenos,
            intervaloKm: 30000,
          ),
        ],
      );

      final migrado = repo.migrarProgresoPlan(
        planViejo,
        planNuevo,
        vehiculoAnterior: vViejo,
        vehiculoNuevo: vNuevo,
      );

      final aceiteMigrado =
          migrado.items.firstWhere((i) => i.id == 'item-aceite');
      final frenosMigrado =
          migrado.items.firstWhere((i) => i.id == 'item-frenos');

      // Motor cambió: aceite debe estar limpio para el nuevo motor
      expect(aceiteMigrado.ultimaVezKm, isNull);

      // Frenos no cambiaron: conserva el historial acumulado
      expect(frenosMigrado.ultimaVezKm, 45000);
      expect(frenosMigrado.ultimaVezFecha, DateTime(2026, 1, 15));
    });
  });

  group('crearVehiculoProvider inicializacion baseline al día vs pendiente', () {
    test('inicializarAlDia: true marca items al kilometraje actual y fecha hoy',
        () async {
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final v = _vehiculo(id: 'v-al-dia').copyWith(kilometrajeActual: 75000);
      await container.read(crearVehiculoProvider((v, true)).future);

      final plan = await repo.getPlan(v.id);
      expect(plan, isNotNull);
      expect(plan!.items, isNotEmpty);
      for (final item in plan.items) {
        expect(item.ultimaVezKm, 75000);
        expect(item.ultimaVezFecha, isNotNull);
      }
    });

    test(
        'inicializarAlDia: false deja items pendientes para inspección etapa cero',
        () async {
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final v =
          _vehiculo(id: 'v-desconozco').copyWith(kilometrajeActual: 75000);
      await container.read(crearVehiculoProvider((v, false)).future);

      final plan = await repo.getPlan(v.id);
      expect(plan, isNotNull);
      expect(plan!.items, isNotEmpty);
      for (final item in plan.items) {
        expect(item.ultimaVezKm, isNull);
        expect(item.ultimaVezFecha, isNull);
      }
    });
  });

  group('LecturasKilometraje y calcularKmPorDia (Etapa 3)', () {
    test('saveVehiculo registra lectura inicial si kilometrajeActual > 0',
        () async {
      final v = _vehiculo(id: 'v-lectura').copyWith(kilometrajeActual: 50000);
      await repo.saveVehiculo(v);

      final lecturas = await repo.getLecturasKilometraje(v.id);
      expect(lecturas, hasLength(1));
      expect(lecturas.first.kilometraje, 50000);
      expect(lecturas.first.fuente, 'creacion');
    });

    test('updateKilometraje añade lectura con fuente odometro', () async {
      final v = _vehiculo(id: 'v-upd').copyWith(kilometrajeActual: 50000);
      await repo.saveVehiculo(v);

      await repo.updateKilometraje(v.id, 51000);

      final lecturas = await repo.getLecturasKilometraje(v.id);
      expect(lecturas, hasLength(2));
      expect(lecturas[1].kilometraje, 51000);
      expect(lecturas[1].fuente, 'odometro');
    });

    test('calcularKmPorDia calcula la tasa diaria exacta con lecturas separadas',
        () async {
      final v = _vehiculo(id: 'v-ritmo').copyWith(kilometrajeActual: 0);
      await repo.saveVehiculo(v);

      final baseFecha = DateTime(2026, 1, 1, 10, 0);
      final diezDiasDespues = DateTime(2026, 1, 11, 10, 0);

      await repo.registrarLecturaKilometraje(
        vehiculoId: v.id,
        kilometraje: 100000,
        fecha: baseFecha,
        fuente: 'creacion',
      );
      await repo.registrarLecturaKilometraje(
        vehiculoId: v.id,
        kilometraje: 100500, // 500 km en 10 días = 50 km/día
        fecha: diezDiasDespues,
        fuente: 'odometro',
      );

      final kmDia = await repo.calcularKmPorDia(v.id, ahora: diezDiasDespues);
      expect(kmDia, 50.0);
    });

    test('calcularKmPorDia devuelve null si lecturas tienen menos de 24 horas',
        () async {
      final v = _vehiculo(id: 'v-horas').copyWith(kilometrajeActual: 0);
      await repo.saveVehiculo(v);

      final t1 = DateTime(2026, 1, 1, 10, 0);
      final t2 = DateTime(2026, 1, 1, 18, 0); // 8 horas

      await repo.registrarLecturaKilometraje(
        vehiculoId: v.id,
        kilometraje: 100000,
        fecha: t1,
      );
      await repo.registrarLecturaKilometraje(
        vehiculoId: v.id,
        kilometraje: 100200,
        fecha: t2,
      );

      final kmDia = await repo.calcularKmPorDia(v.id, ahora: t2);
      expect(kmDia, isNull);
    });
  });

  group('Vencimiento Predictivo por Ritmo y Umbrales 35d y 15d (Etapa 3)', () {
    test('diasEstimadosPorRitmo proyecta días según km restantes y km/día', () {
      const item = ItemMantenimiento(
        id: 'aceite',
        categoria: CategoriaMantenimiento.motor,
        descripcion: 'Aceite de motor',
        componenteAplica: TipoComponente.motor,
        intervaloKm: 10000,
        ultimaVezKm: 0,
      );

      // A 9.400 km faltan 600 km. Con ritmo de 50 km/día: ceil(600 / 50) = 12 días
      final dias = item.diasEstimadosPorRitmo(9400, TipoUso.normal, 50.0);
      expect(dias, 12);
    });

    test('diasRestantesEfectivos toma el menor entre meses calendario y ritmo', () {
      final item = ItemMantenimiento(
        id: 'aceite',
        categoria: CategoriaMantenimiento.motor,
        descripcion: 'Aceite de motor',
        componenteAplica: TipoComponente.motor,
        intervaloKm: 10000,
        intervaloMeses: 12,
        ultimaVezKm: 0,
        ultimaVezFecha: DateTime(2026, 1, 1),
      );

      // Ahora es 1 de febrero (pasó 1 mes, quedan ~334 días por calendario).
      // Por kilometraje faltan 600 km y conduce 50 km/día (12 días por ritmo).
      final ahora = DateTime(2026, 2, 1);
      final efectivos = item.diasRestantesEfectivos(
        9400,
        TipoUso.normal,
        kmPorDia: 50.0,
        ahora: ahora,
      );
      expect(efectivos, 12); // Gana el desgaste diario de 12 días
    });

    test('estado pasa a proximo por ritmo <= 35 dias y alerta urgente a <= 15 dias',
        () {
      const item = ItemMantenimiento(
        id: 'filtro',
        categoria: CategoriaMantenimiento.motor,
        descripcion: 'Filtro de aire',
        componenteAplica: TipoComponente.motor,
        intervaloKm: 20000,
        ultimaVezKm: 0,
      );

      // 1. Faltan 1.500 km (> umbral directo de 1000 km), pero a 50 km/día faltan 30 días (<= 35)
      final stProximo = item.estado(18500, TipoUso.normal, kmPorDia: 50.0);
      expect(stProximo, EstadoItem.proximo);

      // 2. Faltan 600 km. A 50 km/día faltan 12 días (<= 15 días)
      final esUrgente =
          item.esRecordatorioUrgente(19400, TipoUso.normal, kmPorDia: 50.0);
      expect(esUrgente, isTrue);
    });
  });

  group('Niveles de Verificación del Historial (Etapa 4)', () {
    test('clasifica Nivel 1 (declarado), Nivel 2 (evidencia) y Nivel 3 (taller)', () {
      final reg1 = _registro('v-1'); // Sin fotos ni sesion taller
      expect(reg1.nivelVerificacion, NivelVerificacionHistorial.declarado);

      final reg2 = _registro('v-1').copyWith(evidencia: ['foto_factura.jpg']);
      expect(reg2.nivelVerificacion, NivelVerificacionHistorial.conEvidencia);

      final reg3 = _registro('v-1').copyWith(sesionTallerId: 'A7F9K2');
      expect(reg3.nivelVerificacion, NivelVerificacionHistorial.selladoTaller);
    });
  });

  group('AnaliticaVehiculo y Presupuesto Estimado (Etapa 4)', () {
    test('calcula costo por km, presupuesto y porcentaje verificado', () {
      final v = _vehiculo(id: 'v-analitica').copyWith(kilometrajeActual: 105000);
      final plan = PlanMantenimiento(
        id: 'p-1',
        vehiculoId: 'v-analitica',
        version: 1,
        fechaGeneracion: DateTime(2025, 1, 1),
        items: const [
          ItemMantenimiento(
            id: 'aceite',
            categoria: CategoriaMantenimiento.motor,
            descripcion: 'Aceite 5W-30',
            componenteAplica: TipoComponente.motor,
            intervaloKm: 10000,
            ultimaVezKm: 95000, // a 105000 está vencido
          ),
        ],
      );

      final registros = [
        RegistroMantenimiento(
          id: 'r-1',
          vehiculoId: 'v-analitica',
          fecha: DateTime(2025, 1, 1),
          kilometraje: 95000,
          costo: 60.0,
          sesionTallerId: 'SES-01',
          itemsRealizados: const [
            ItemRealizado(
              itemId: 'aceite',
              categoria: CategoriaMantenimiento.motor,
              descripcion: 'Aceite 5W-30',
              componenteAplica: TipoComponente.motor,
            ),
          ],
        ),
        RegistroMantenimiento(
          id: 'r-2',
          vehiculoId: 'v-analitica',
          fecha: DateTime(2025, 6, 1),
          kilometraje: 100000,
          costo: 40.0,
          evidencia: const ['recibo.jpg'],
          itemsRealizados: const [
            ItemRealizado(
              categoria: CategoriaMantenimiento.frenos,
              descripcion: 'Pastillas de freno',
              componenteAplica: TipoComponente.frenos,
            ),
          ],
        ),
      ];

      final res = AnaliticaVehiculo.calcular(
        vehiculo: v,
        plan: plan,
        registros: registros,
      );

      expect(res.costoTotal, 100.0);
      expect(res.registrosSelladosTaller, 1);
      expect(res.registrosConEvidencia, 1);
      expect(res.porcentajeHistorialVerificado, 100.0);
      expect(res.itemsVencidosOProximos, 1);
      // El aceite vencido costó $60 en r-1 -> presupuesto próximo estimado = $60
      expect(res.presupuestoProximoServicio, 60.0);
      // Delta km = 105000 - 95000 = 10000 km -> $100 / 10000 = $0.01 / km
      expect(res.costoPorKm, 0.01);
      // Costo anual proyectado con costoPorKm = 0.01 y 12.000 km/año = 120.0
      expect(res.costoAnualEstimado, 120.0);
      expect(res.esEstimadoSegunUso, isFalse);
    });

    test('calcula costo anual estimado segun uso cuando no hay registros', () {
      final vNormal = _vehiculo(id: 'v-sin-datos').copyWith(
        tipoUso: TipoUso.normal,
        kilometrajeActual: 20000,
      );
      final resNormal = AnaliticaVehiculo.calcular(
        vehiculo: vNormal,
        plan: null,
        registros: const [],
      );
      expect(resNormal.esEstimadoSegunUso, isTrue);
      expect(resNormal.costoAnualEstimado, 1200000.0);
      expect(resNormal.explicacionCostoAnual, contains('normal'));

      final vSevero = _vehiculo(id: 'v-severo').copyWith(
        tipoUso: TipoUso.severo,
        kilometrajeActual: 20000,
      );
      final resSevero = AnaliticaVehiculo.calcular(
        vehiculo: vSevero,
        plan: null,
        registros: const [],
      );
      expect(resSevero.esEstimadoSegunUso, isTrue);
      expect(resSevero.costoAnualEstimado, 1800000.0);
      expect(resSevero.explicacionCostoAnual, contains('severo'));
    });
  });
}

// ─────────────────────────── Fixtures ───────────────────────────

Vehiculo _vehiculo({String id = 'v-test', String codigoMotor = '2JZ-GTE'}) =>
    Vehiculo(
      id: id,
      propietarioId: 'local',
      marca: 'Toyota',
      modelo: 'Supra',
      anio: 1997,
      drivetrain: Drivetrain.rwd,
      motor: Motor(
        codigo: codigoMotor,
        tipoCombustible: TipoCombustible.gasolina,
        cilindrada: 3.0,
        cilindros: 6,
        aspiracion: 'Twin-Turbo',
      ),
      transmision: const Transmision(
        codigo: 'R154',
        tipo: TipoTransmision.manual,
        marchas: 5,
      ),
    );

PlanMantenimiento _plan(String vehiculoId, {String id = 'plan-test'}) =>
    PlanMantenimiento(
      id: id,
      vehiculoId: vehiculoId,
      version: 1,
      fechaGeneracion: DateTime(2026, 1, 1),
      items: const [
        ItemMantenimiento(
          id: 'item-1',
          categoria: CategoriaMantenimiento.motor,
          descripcion: 'Cambio de aceite',
          componenteAplica: TipoComponente.motor,
          intervaloKm: 10000,
        ),
      ],
    );

RegistroMantenimiento _registro(String vehiculoId) => RegistroMantenimiento(
      id: 'reg-test',
      vehiculoId: vehiculoId,
      fecha: DateTime(2026, 3, 15),
      kilometraje: 95000,
      itemsRealizados: const [
        ItemRealizado(
          categoria: CategoriaMantenimiento.motor,
          descripcion: 'Cambio de aceite',
          componenteAplica: TipoComponente.motor,
        ),
      ],
    );
