import 'package:drift/drift.dart';

/// Tabla de vehículos. Los campos complejos anidados (motor, transmisión,
/// componentes extra) se guardan como JSON porque se cargan completos
/// y no se consultan por subcampo.
@DataClassName('VehiculoRow')
class Vehiculos extends Table {
  TextColumn get id => text()();
  TextColumn get propietarioId => text()();
  TextColumn get marca => text()();
  TextColumn get modelo => text()();
  IntColumn get anio => integer()();
  TextColumn get trim => text().nullable()();
  TextColumn get vin => text().nullable()();
  IntColumn get drivetrain => integer()(); // Drivetrain.index
  TextColumn get motorJson => text()(); // JSON serializado
  TextColumn get transmisionJson => text()(); // JSON serializado
  TextColumn get componentesExtraJson => text().withDefault(const Constant('[]'))();
  IntColumn get kilometrajeActual => integer().withDefault(const Constant(0))();
  IntColumn get tipoUso => integer().withDefault(const Constant(0))();
  TextColumn get notasUso => text().nullable()();
  TextColumn get planMantenimientoId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Tabla de planes de mantenimiento. Los items se guardan como JSON.
@DataClassName('PlanMantenimientoRow')
class PlanesMantenimiento extends Table {
  TextColumn get id => text()();
  TextColumn get vehiculoId => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get fechaGeneracion => dateTime()();
  TextColumn get itemsJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Tabla de registros de mantenimiento realizado.
@DataClassName('RegistroMantenimientoRow')
class RegistrosMantenimiento extends Table {
  TextColumn get id => text()();
  TextColumn get vehiculoId => text()();
  DateTimeColumn get fecha => dateTime()();
  IntColumn get kilometraje => integer()();
  TextColumn get itemsRealizadosJson => text().withDefault(const Constant('[]'))();
  RealColumn get costo => real().nullable()();
  TextColumn get taller => text().nullable()();
  TextColumn get notas => text().nullable()();
  TextColumn get evidenciaJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Tabla de sesiones de compartido con mecánico.
@DataClassName('SesionMecanicoRow')
class SesionesMecanico extends Table {
  TextColumn get id => text()(); // código/invite de sesión
  TextColumn get vehiculoId => text()();
  TextColumn get duenoDeviceId => text()();
  TextColumn get mecanicoDeviceId => text().nullable()();
  BoolColumn get activa => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get expiresAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
