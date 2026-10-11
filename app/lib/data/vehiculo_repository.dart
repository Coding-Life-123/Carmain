import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../models/componente.dart';
import '../models/enums.dart';
import '../models/plan_mantenimiento.dart';
import '../models/registro_mantenimiento.dart';
import '../models/vehiculo.dart';

/// Repositorio que converte entre filas Drift (persistencia) y modelos
/// de dominio (freezed). Es la única capa que toca la DB directamente.
class VehiculoRepository {
  final AppDatabase _db;
  static const _uuid = Uuid();

  VehiculoRepository(this._db);

  // ─────────────────────────── Vehículos ───────────────────────────

  Future<List<Vehiculo>> getAllVehiculos() async {
    final rows = await _db.vehiculos.all().get();
    return rows.map(_rowToVehiculo).toList();
  }

  Future<Vehiculo?> getVehiculo(String id) async {
    final row = await (_db.vehiculos.select()
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _rowToVehiculo(row);
  }

  Future<String> saveVehiculo(Vehiculo vehiculo) async {
    await _db.vehiculos.insertOnConflictUpdate(_vehiculoToRow(vehiculo));
    return vehiculo.id;
  }

  Future<void> deleteVehiculo(String id) async {
    await _db.vehiculos.deleteWhere((t) => t.id.equals(id));
  }

  Future<void> updateKilometraje(String id, int km) async {
    await (_db.vehiculos.update()..where((t) => t.id.equals(id))).write(
      VehiculosCompanion(
        kilometrajeActual: Value(km),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ─────────────────────── Plan de mantenimiento ───────────────────────

  Future<PlanMantenimiento?> getPlan(String vehiculoId) async {
    final row = await (_db.planesMantenimiento.select()
          ..where((t) => t.vehiculoId.equals(vehiculoId)))
        .getSingleOrNull();
    return row == null ? null : _rowToPlan(row);
  }

  Future<void> savePlan(PlanMantenimiento plan) async {
    await _db.planesMantenimiento.insertOnConflictUpdate(_planToRow(plan));
  }

  // ─────────────────── Registros de mantenimiento ───────────────────

  Future<List<RegistroMantenimiento>> getRegistros(String vehiculoId) async {
    final rows = await (_db.registrosMantenimiento.select()
          ..where((t) => t.vehiculoId.equals(vehiculoId))
          ..orderBy([(t) => OrderingTerm.desc(t.fecha)]))
        .get();
    return rows.map(_rowToRegistro).toList();
  }

  Future<String> saveRegistro(RegistroMantenimiento registro) async {
    await _db.registrosMantenimiento
        .insertOnConflictUpdate(_registroToRow(registro));

    // Actualizar ultimaVezKm/ultimaVezFecha de los items del plan.
    final plan = await getPlan(registro.vehiculoId);
    if (plan != null) {
      final updatedItems = plan.items.map((item) {
        final realizado = registro.itemsRealizados.any(
          (r) =>
              r.categoria == item.categoria &&
              r.componenteAplica == item.componenteAplica,
        );
        if (!realizado) return item;
        return item.copyWith(
          ultimaVezKm: registro.kilometraje,
          ultimaVezFecha: registro.fecha,
        );
      }).toList();
      await savePlan(plan.copyWith(items: updatedItems));
    }
    return registro.id;
  }

  // ─────────────────────────── Mappers ───────────────────────────

  Vehiculo _rowToVehiculo(VehiculoRow r) {
    return Vehiculo(
      id: r.id,
      propietarioId: r.propietarioId,
      marca: r.marca,
      modelo: r.modelo,
      anio: r.anio,
      trim: r.trim,
      vin: r.vin,
      drivetrain: Drivetrain.values[r.drivetrain],
      motor: Motor.fromJson(jsonDecode(r.motorJson) as Map<String, dynamic>),
      transmision: Transmision.fromJson(
          jsonDecode(r.transmisionJson) as Map<String, dynamic>),
      componentesExtra: (jsonDecode(r.componentesExtraJson) as List)
          .map((e) => Componente.fromJson(e as Map<String, dynamic>))
          .toList(),
      kilometrajeActual: r.kilometrajeActual,
      tipoUso: TipoUso.values[r.tipoUso],
      notasUso: r.notasUso,
      planMantenimientoId: r.planMantenimientoId,
    );
  }

  VehiculosCompanion _vehiculoToRow(Vehiculo v) {
    return VehiculosCompanion(
      id: Value(v.id),
      propietarioId: Value(v.propietarioId),
      marca: Value(v.marca),
      modelo: Value(v.modelo),
      anio: Value(v.anio),
      trim: Value(v.trim),
      vin: Value(v.vin),
      drivetrain: Value(v.drivetrain.index),
      motorJson: Value(jsonEncode(v.motor.toJson())),
      transmisionJson: Value(jsonEncode(v.transmision.toJson())),
      componentesExtraJson:
          Value(jsonEncode(v.componentesExtra.map((c) => c.toJson()).toList())),
      kilometrajeActual: Value(v.kilometrajeActual),
      tipoUso: Value(v.tipoUso.index),
      notasUso: Value(v.notasUso),
      planMantenimientoId: Value(v.planMantenimientoId),
      updatedAt: Value(DateTime.now()),
    );
  }

  PlanMantenimiento _rowToPlan(PlanMantenimientoRow r) {
    return PlanMantenimiento(
      id: r.id,
      vehiculoId: r.vehiculoId,
      version: r.version,
      fechaGeneracion: r.fechaGeneracion,
      items: (jsonDecode(r.itemsJson) as List)
          .map((e) => ItemMantenimiento.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  PlanesMantenimientoCompanion _planToRow(PlanMantenimiento p) {
    return PlanesMantenimientoCompanion(
      id: Value(p.id),
      vehiculoId: Value(p.vehiculoId),
      version: Value(p.version),
      fechaGeneracion: Value(p.fechaGeneracion),
      itemsJson: Value(jsonEncode(p.items.map((i) => i.toJson()).toList())),
    );
  }

  RegistroMantenimiento _rowToRegistro(RegistroMantenimientoRow r) {
    return RegistroMantenimiento(
      id: r.id,
      vehiculoId: r.vehiculoId,
      fecha: r.fecha,
      kilometraje: r.kilometraje,
      itemsRealizados: (jsonDecode(r.itemsRealizadosJson) as List)
          .map((e) => ItemRealizado.fromJson(e as Map<String, dynamic>))
          .toList(),
      costo: r.costo,
      taller: r.taller,
      notas: r.notas,
      evidencia: (jsonDecode(r.evidenciaJson) as List)
          .map((e) => e as String)
          .toList(),
      updatedAt: r.updatedAt,
    );
  }

  RegistrosMantenimientoCompanion _registroToRow(RegistroMantenimiento r) {
    return RegistrosMantenimientoCompanion(
      id: Value(r.id),
      vehiculoId: Value(r.vehiculoId),
      fecha: Value(r.fecha),
      kilometraje: Value(r.kilometraje),
      itemsRealizadosJson:
          Value(jsonEncode(r.itemsRealizados.map((i) => i.toJson()).toList())),
      costo: Value(r.costo),
      taller: Value(r.taller),
      notas: Value(r.notas),
      evidenciaJson: Value(jsonEncode(r.evidencia)),
      updatedAt: Value(DateTime.now()),
    );
  }

  /// Genera un UUID v4 para nuevos registros.
  static String newId() => _uuid.v4();
}
