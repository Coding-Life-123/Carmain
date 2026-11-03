import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../models/componente.dart';
import '../models/enums.dart';
import '../models/plan_mantenimiento.dart';
import '../models/propuesta_mecanico.dart';
import '../models/registro_mantenimiento.dart';
import '../models/vehiculo.dart';

/// Repositorio que convierte entre filas Drift (persistencia) y modelos
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
    final anterior = await getVehiculo(vehiculo.id);
    await _db.vehiculos.insertOnConflictUpdate(_vehiculoToRow(vehiculo));

    if (anterior == null && vehiculo.kilometrajeActual > 0) {
      await registrarLecturaKilometraje(
        vehiculoId: vehiculo.id,
        kilometraje: vehiculo.kilometrajeActual,
        fuente: 'creacion',
      );
    }
    return vehiculo.id;
  }

  /// Elimina un vehículo y todo lo asociado (plan, registros, sesiones de
  /// compartido, lecturas de odómetro) en una transacción.
  Future<void> deleteVehiculo(String id) async {
    await _db.transaction(() async {
      await _db.registrosMantenimiento
          .deleteWhere((t) => t.vehiculoId.equals(id));
      await _db.planesMantenimiento.deleteWhere((t) => t.vehiculoId.equals(id));
      await _db.sesionesMecanico.deleteWhere((t) => t.vehiculoId.equals(id));
      await _db.lecturasKilometraje.deleteWhere((t) => t.vehiculoId.equals(id));
      await _db.vehiculos.deleteWhere((t) => t.id.equals(id));
    });
  }

  Future<void> updateKilometraje(String id, int km) async {
    await (_db.vehiculos.update()..where((t) => t.id.equals(id))).write(
      VehiculosCompanion(
        kilometrajeActual: Value(km),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await registrarLecturaKilometraje(
      vehiculoId: id,
      kilometraje: km,
      fuente: 'odometro',
    );
  }

  // ─────────────────────── Lecturas de Kilometraje ───────────────────────

  /// Registra una lectura periódica de kilometraje para proyectar km/día.
  Future<void> registrarLecturaKilometraje({
    required String vehiculoId,
    required int kilometraje,
    DateTime? fecha,
    String fuente = 'odometro',
  }) async {
    final f = fecha ?? DateTime.now();
    await _db.into(_db.lecturasKilometraje).insert(
      LecturasKilometrajeCompanion(
        id: Value(_uuid.v4()),
        vehiculoId: Value(vehiculoId),
        kilometraje: Value(kilometraje),
        fecha: Value(f),
        fuente: Value(fuente),
      ),
    );
  }

  /// Obtiene el historial de lecturas de kilometraje para un vehículo.
  Future<List<LecturaKilometrajeRow>> getLecturasKilometraje(String vehiculoId) async {
    return await (_db.lecturasKilometraje.select()
          ..where((t) => t.vehiculoId.equals(vehiculoId))
          ..orderBy([(t) => OrderingTerm.asc(t.fecha)]))
        .get();
  }

  /// Calcula la tasa estimada de uso diario (km/día) en base a las lecturas
  /// de los últimos 90 días. Requiere al menos dos lecturas separadas por al menos 1 día.
  /// Retorna null si no hay suficientes datos para una estimación confiable.
  Future<double?> calcularKmPorDia(String vehiculoId, {DateTime? ahora}) async {
    final hoy = ahora ?? DateTime.now();
    final limiteVentana = hoy.subtract(const Duration(days: 90));

    final lecturas = await (_db.lecturasKilometraje.select()
          ..where((t) =>
              t.vehiculoId.equals(vehiculoId) &
              t.fecha.isBiggerOrEqualValue(limiteVentana))
          ..orderBy([(t) => OrderingTerm.asc(t.fecha)]))
        .get();

    if (lecturas.length < 2) {
      final todas = await getLecturasKilometraje(vehiculoId);
      if (todas.length < 2) return null;
      return _calcularRitmoEntreLecturas(todas.first, todas.last);
    }

    return _calcularRitmoEntreLecturas(lecturas.first, lecturas.last);
  }

  double? _calcularRitmoEntreLecturas(
    LecturaKilometrajeRow primera,
    LecturaKilometrajeRow ultima,
  ) {
    final diffDias = ultima.fecha.difference(primera.fecha).inHours / 24.0;
    if (diffDias < 1.0) return null;

    final diffKm = ultima.kilometraje - primera.kilometraje;
    if (diffKm <= 0) return null;

    final ritmo = diffKm / diffDias;
    if (ritmo <= 0) return null;
    // Límite de sanidad superior (L6): hasta 800 km/día
    final ritmoAjustado = ritmo > 800.0 ? 800.0 : ritmo;
    return double.parse(ritmoAjustado.toStringAsFixed(1));
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

  /// Reemplaza el plan de un vehículo de forma atómica: borra el plan
  /// anterior (si existe) e inserta el nuevo en la misma transacción.
  Future<void> replacePlan(PlanMantenimiento plan) async {
    await _db.transaction(() async {
      await _db.planesMantenimiento
          .deleteWhere((t) => t.vehiculoId.equals(plan.vehiculoId));
      await _db.planesMantenimiento.insertOnConflictUpdate(_planToRow(plan));
    });
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
    return await _db.transaction(() async {
      await _db.registrosMantenimiento
          .insertOnConflictUpdate(_registroToRow(registro));

      // 1. Sincronizar odómetro del vehículo si el servicio se realizó a un km mayor.
      final vehiculo = await getVehiculo(registro.vehiculoId);
      if (vehiculo != null && registro.kilometraje > vehiculo.kilometrajeActual) {
        await updateKilometraje(vehiculo.id, registro.kilometraje);
      } else {
        await registrarLecturaKilometraje(
          vehiculoId: registro.vehiculoId,
          kilometraje: registro.kilometraje,
          fecha: registro.fecha,
          fuente: 'mantenimiento',
        );
      }

      // 2. Recalcular derivando desde la totalidad de registros históricos (L4).
      await recalcularProgresoPlan(registro.vehiculoId);

      return registro.id;
    });
  }

  /// Recalcula el progreso de los ítems del plan (ultimaVezKm y ultimaVezFecha)
  /// derivándolo directamente de la totalidad de registros históricos (L4).
  Future<void> recalcularProgresoPlan(String vehiculoId) async {
    final plan = await getPlan(vehiculoId);
    if (plan == null) return;
    final registros = await getRegistros(vehiculoId);

    final itemsActualizados = plan.items.map((item) {
      int? maxKm = item.ultimaVezKm;
      DateTime? maxFecha = item.ultimaVezFecha;

      for (final reg in registros) {
        final realizado = reg.itemsRealizados.any((r) {
          if (r.itemId != null) {
            return r.itemId == item.id;
          }
          return r.categoria == item.categoria &&
              r.componenteAplica == item.componenteAplica &&
              r.descripcion.trim().toLowerCase() ==
                  item.descripcion.trim().toLowerCase();
        });

        if (realizado) {
          if (maxKm == null || reg.kilometraje > maxKm) {
            maxKm = reg.kilometraje;
            maxFecha = reg.fecha;
          } else if (reg.kilometraje == maxKm &&
              (maxFecha == null || reg.fecha.isAfter(maxFecha))) {
            maxFecha = reg.fecha;
          }
        }
      }

      return item.copyWith(
        ultimaVezKm: maxKm,
        ultimaVezFecha: maxFecha,
      );
    }).toList();

    await savePlan(plan.copyWith(items: itemsActualizados));
  }

  /// Elimina un registro de mantenimiento y recalcula el plan del vehículo.
  Future<void> deleteRegistro(String id) async {
    final regRow = await (_db.registrosMantenimiento.select()
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (regRow == null) return;
    final vehiculoId = regRow.vehiculoId;

    await _db.transaction(() async {
      await _db.registrosMantenimiento.deleteWhere((t) => t.id.equals(id));
      await recalcularProgresoPlan(vehiculoId);
    });
  }

  /// Actualiza un registro existente y recalcula el odómetro y el plan.
  Future<void> updateRegistro(RegistroMantenimiento registro) async {
    await _db.transaction(() async {
      await _db.registrosMantenimiento
          .insertOnConflictUpdate(_registroToRow(registro));

      final vehiculo = await getVehiculo(registro.vehiculoId);
      if (vehiculo != null && registro.kilometraje > vehiculo.kilometrajeActual) {
        await updateKilometraje(vehiculo.id, registro.kilometraje);
      }
      await recalcularProgresoPlan(registro.vehiculoId);
    });
  }

  // ─────────────────── Sesiones de taller (Web del Mecánico) ───────────────────

  Future<void> saveSesionMecanico({
    required String codigo,
    String? tokenLargo,
    required String vehiculoId,
    required String duenoDeviceId,
    required DateTime expiresAt,
  }) async {
    await _db.sesionesMecanico.insertOnConflictUpdate(
      SesionesMecanicoCompanion(
        id: Value(codigo),
        tokenLargo: Value(tokenLargo),
        vehiculoId: Value(vehiculoId),
        duenoDeviceId: Value(duenoDeviceId),
        expiresAt: Value(expiresAt),
        activa: const Value(true),
      ),
    );
  }

  Future<List<SesionMecanicoRow>> getSesionesActivas(String vehiculoId) async {
    final ahora = DateTime.now();
    return await (_db.sesionesMecanico.select()
          ..where((t) =>
              t.vehiculoId.equals(vehiculoId) &
              t.activa.equals(true) &
              t.expiresAt.isBiggerThanValue(ahora))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<void> revocarSesionMecanico(String codigo) async {
    await (_db.sesionesMecanico.update()..where((t) => t.id.equals(codigo)))
        .write(const SesionesMecanicoCompanion(activa: Value(false)));
  }

  // ─────────────────── Propuestas de mantenimiento ───────────────────

  Future<void> savePropuestaRecibida(PropuestaMecanicoModel propuesta) async {
    await _db.propuestasRecibidas.insertOnConflictUpdate(
      PropuestasRecibidasCompanion(
        id: Value(propuesta.id),
        sesionId: Value(propuesta.sesionId),
        vehiculoId: Value(propuesta.vehiculoId),
        jsonCrudo: Value(propuesta.jsonCrudo),
        estado: Value(propuesta.estado),
        recibidaEn: Value(propuesta.recibidaEn),
      ),
    );
  }

  Future<List<PropuestaMecanicoModel>> getPropuestasPendientes(String vehiculoId) async {
    final rows = await (_db.propuestasRecibidas.select()
          ..where((t) =>
              t.vehiculoId.equals(vehiculoId) &
              t.estado.equals('pendiente'))
          ..orderBy([(t) => OrderingTerm.desc(t.recibidaEn)]))
        .get();

    return rows.map((r) {
      final json = jsonDecode(r.jsonCrudo) as Map<String, dynamic>;
      return PropuestaMecanicoModel.fromJson(
        json,
        sesionId: r.sesionId,
        vehiculoId: r.vehiculoId,
        estado: r.estado,
        recibidaEn: r.recibidaEn,
      );
    }).toList();
  }

  Future<void> actualizarEstadoPropuesta(String id, String nuevoEstado) async {
    await (_db.propuestasRecibidas.update()..where((t) => t.id.equals(id))).write(
      PropuestasRecibidasCompanion(
        estado: Value(nuevoEstado),
        procesadaEn: Value(DateTime.now()),
      ),
    );
  }

  /// Acepta una propuesta de taller: crea un RegistroMantenimiento con nivel
  /// selladoTaller, actualiza el odómetro, recalcula el plan y marca la propuesta como aceptada.
  Future<void> aceptarPropuesta(PropuestaMecanicoModel propuesta) async {
    DateTime fechaRegistro;
    try {
      fechaRegistro = DateTime.parse(propuesta.fecha);
    } catch (_) {
      fechaRegistro = DateTime.now();
    }

    final registro = RegistroMantenimiento(
      id: newId(),
      vehiculoId: propuesta.vehiculoId,
      fecha: fechaRegistro,
      kilometraje: propuesta.kilometraje,
      costo: propuesta.costo,
      moneda: propuesta.moneda,
      taller: propuesta.taller ?? propuesta.mecanicoNombre ?? 'Taller mecánico',
      sesionTallerId: propuesta.sesionId,
      notas: propuesta.notas,
      itemsRealizados: propuesta.itemsRealizados.map((i) {
        return ItemRealizado(
          itemId: i.itemId,
          categoria: i.categoria,
          componenteAplica: i.componenteAplica,
          descripcion: i.descripcion,
        );
      }).toList(),
    );

    await saveRegistro(registro);
    await actualizarEstadoPropuesta(propuesta.id, 'aceptada');
  }

  Future<void> rechazarPropuesta(String propuestaId) async {
    await actualizarEstadoPropuesta(propuestaId, 'rechazada');
  }

  /// Al regenerar el plan de un vehículo (por cambio de motor o caja),
  /// migra los datos de última vez realizada (km y fecha) para aquellos
  /// componentes que NO cambiaron, evitando perder el historial de los demás ítems.
  PlanMantenimiento migrarProgresoPlan(
    PlanMantenimiento planAnterior,
    PlanMantenimiento planNuevo, {
    required Vehiculo vehiculoAnterior,
    required Vehiculo vehiculoNuevo,
  }) {
    final motorCambio =
        vehiculoAnterior.motor.codigo != vehiculoNuevo.motor.codigo;
    final transCambio =
        vehiculoAnterior.transmision.codigo != vehiculoNuevo.transmision.codigo;

    final itemsActualizados = planNuevo.items.map((nuevoItem) {
      if (nuevoItem.componenteAplica == TipoComponente.motor && motorCambio) {
        return nuevoItem;
      }
      if (nuevoItem.componenteAplica == TipoComponente.transmision &&
          transCambio) {
        return nuevoItem;
      }

      final anterior = planAnterior.items.cast<ItemMantenimiento?>().firstWhere(
            (v) =>
                v?.categoria == nuevoItem.categoria &&
                v?.componenteAplica == nuevoItem.componenteAplica &&
                (v?.id == nuevoItem.id ||
                    v?.descripcion.trim().toLowerCase() ==
                        nuevoItem.descripcion.trim().toLowerCase()),
            orElse: () => null,
          );

      if (anterior != null && anterior.ultimaVezKm != null) {
        return nuevoItem.copyWith(
          ultimaVezKm: anterior.ultimaVezKm,
          ultimaVezFecha: anterior.ultimaVezFecha,
        );
      }
      return nuevoItem;
    }).toList();

    return planNuevo.copyWith(items: itemsActualizados);
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
      placa: r.placa,
      fechaMatricula: r.fechaMatricula,
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
      placa: Value(v.placa),
      fechaMatricula: Value(v.fechaMatricula),
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
    final decoded = jsonDecode(r.itemsJson);
    List<ItemMantenimiento> items = [];
    List<AlertaIngenieria> alertas = [];

    if (decoded is List) {
      items = decoded
          .map((e) => ItemMantenimiento.fromJson(e as Map<String, dynamic>))
          .toList();
    } else if (decoded is Map<String, dynamic>) {
      final rawItems = decoded['items'] as List?;
      if (rawItems != null) {
        items = rawItems
            .map((e) => ItemMantenimiento.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      final rawAlertas = decoded['alertasIngenieria'] as List?;
      if (rawAlertas != null) {
        alertas = rawAlertas
            .map((e) => AlertaIngenieria.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }

    return PlanMantenimiento(
      id: r.id,
      vehiculoId: r.vehiculoId,
      version: r.version,
      fechaGeneracion: r.fechaGeneracion,
      items: items,
      alertasIngenieria: alertas,
    );
  }

  PlanesMantenimientoCompanion _planToRow(PlanMantenimiento p) {
    return PlanesMantenimientoCompanion(
      id: Value(p.id),
      vehiculoId: Value(p.vehiculoId),
      version: Value(p.version),
      fechaGeneracion: Value(p.fechaGeneracion),
      itemsJson: Value(jsonEncode({
        'items': p.items.map((i) => i.toJson()).toList(),
        'alertasIngenieria':
            p.alertasIngenieria.map((a) => a.toJson()).toList(),
      })),
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
      moneda: r.moneda,
      taller: r.taller,
      sesionTallerId: r.sesionTallerId,
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
      moneda: Value(r.moneda),
      taller: Value(r.taller),
      sesionTallerId: Value(r.sesionTallerId),
      notas: Value(r.notas),
      evidenciaJson: Value(jsonEncode(r.evidencia)),
      updatedAt: Value(DateTime.now()),
    );
  }

  /// Genera un UUID v4 para nuevos registros.
  static String newId() => _uuid.v4();
}
