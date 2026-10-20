import 'package:car_main/data/vehiculo_repository.dart';
import 'package:car_main/database/database.dart';
import 'package:car_main/models/componente.dart';
import 'package:car_main/models/enums.dart';
import 'package:car_main/models/plan_mantenimiento.dart';
import 'package:car_main/models/registro_mantenimiento.dart';
import 'package:car_main/models/vehiculo.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
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
