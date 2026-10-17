import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/vehiculo_repository.dart';
import '../database/database.dart';
import '../models/enums.dart';
import '../models/plan_mantenimiento.dart';
import '../models/registro_mantenimiento.dart';
import '../models/vehiculo.dart';
import '../services/api_client.dart';

// ─────────────────────────── Infraestructura ───────────────────────────

/// Base de datos local (singleton). Vive en el dispositivo del dueño.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Repositorio de vehículos (capa de acceso a datos).
final repositoryProvider = Provider<VehiculoRepository>((ref) {
  return VehiculoRepository(ref.watch(databaseProvider));
});

/// Cliente HTTP del backend Go.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

// ─────────────────────────── Vehículos ───────────────────────────

/// Lista de todos los vehículos del dueño.
final vehiculosProvider =
    FutureProvider<List<Vehiculo>>((ref) async {
  return ref.watch(repositoryProvider).getAllVehiculos();
});

/// Un vehículo por ID.
final vehiculoProvider =
    FutureProvider.family<Vehiculo?, String>((ref, id) async {
  return ref.watch(repositoryProvider).getVehiculo(id);
});

// ─────────────────────────── Mantenimiento ───────────────────────────

/// Plan de mantenimiento de un vehículo.
final planProvider =
    FutureProvider.family<PlanMantenimiento?, String>((ref, vehiculoId) async {
  return ref.watch(repositoryProvider).getPlan(vehiculoId);
});

/// Registros de mantenimiento realizados de un vehículo.
final registrosProvider =
    FutureProvider.family<List<RegistroMantenimiento>, String>(
        (ref, vehiculoId) async {
  return ref.watch(repositoryProvider).getRegistros(vehiculoId);
});

// ─────────────────────────── Acciones ───────────────────────────

/// Crea un vehículo nuevo y solicita su plan al backend.
final crearVehiculoProvider =
    FutureProvider.family<Vehiculo, Vehiculo>((ref, vehiculo) async {
  final repo = ref.watch(repositoryProvider);
  final api = ref.watch(apiClientProvider);

  // 1. Guardar el vehículo localmente.
  await repo.saveVehiculo(vehiculo);

  // 2. Solicitar el plan al backend (biblioteca central + IA).
  PlanMantenimiento? plan;
  try {
    plan = await api.solicitarPlan(vehiculo);
  } catch (e) {
    debugPrint('[crearVehiculoProvider] Backend no disponible ($e). Generando plan base local.');
  }

  // 3. Fallback: Si el backend no está disponible o no respondió, usar plan base local.
  plan ??= _generarPlanBaseLocal(vehiculo);

  await repo.savePlan(plan);
  await repo.saveVehiculo(vehiculo.copyWith(
    planMantenimientoId: plan.id,
  ));

  // Invalidar la lista de vehículos.
  ref.invalidate(vehiculosProvider);
  return vehiculo;
});

PlanMantenimiento _generarPlanBaseLocal(Vehiculo vehiculo) {
  final planId = const Uuid().v4();
  return PlanMantenimiento(
    id: planId,
    vehiculoId: vehiculo.id,
    version: 1,
    fechaGeneracion: DateTime.now(),
    items: [
      ItemMantenimiento(
        id: const Uuid().v4(),
        categoria: CategoriaMantenimiento.motor,
        descripcion: 'Cambio de aceite de motor y filtro',
        componenteAplica: TipoComponente.motor,
        intervaloKm: 7500,
        intervaloMeses: 6,
        intervaloSeveroKm: 5000,
        fuente: FuentePlan.oem,
        confianza: NivelConfianza.alta,
      ),
      ItemMantenimiento(
        id: const Uuid().v4(),
        categoria: CategoriaMantenimiento.motor,
        descripcion: 'Cambio de filtro de aire de motor',
        componenteAplica: TipoComponente.motor,
        intervaloKm: 15000,
        intervaloMeses: 12,
        intervaloSeveroKm: 10000,
        fuente: FuentePlan.oem,
        confianza: NivelConfianza.alta,
      ),
      ItemMantenimiento(
        id: const Uuid().v4(),
        categoria: CategoriaMantenimiento.frenos,
        descripcion: 'Inspección de pastillas y discos de freno',
        componenteAplica: TipoComponente.frenos,
        intervaloKm: 10000,
        intervaloMeses: 6,
        intervaloSeveroKm: 7500,
        fuente: FuentePlan.oem,
        confianza: NivelConfianza.alta,
      ),
      ItemMantenimiento(
        id: const Uuid().v4(),
        categoria: CategoriaMantenimiento.frenos,
        descripcion: 'Cambio de líquido de frenos',
        componenteAplica: TipoComponente.frenos,
        intervaloKm: 30000,
        intervaloMeses: 24,
        intervaloSeveroKm: 20000,
        fuente: FuentePlan.oem,
        confianza: NivelConfianza.media,
      ),
      ItemMantenimiento(
        id: const Uuid().v4(),
        categoria: CategoriaMantenimiento.refrigeracion,
        descripcion: 'Inspección y purga de refrigerante',
        componenteAplica: TipoComponente.motor,
        intervaloKm: 40000,
        intervaloMeses: 24,
        intervaloSeveroKm: 30000,
        fuente: FuentePlan.oem,
        confianza: NivelConfianza.media,
      ),
      ItemMantenimiento(
        id: const Uuid().v4(),
        categoria: CategoriaMantenimiento.transmision,
        descripcion: 'Inspección de aceite de transmisión',
        componenteAplica: TipoComponente.transmision,
        intervaloKm: 40000,
        intervaloMeses: 24,
        intervaloSeveroKm: 25000,
        fuente: FuentePlan.oem,
        confianza: NivelConfianza.media,
      ),
      ItemMantenimiento(
        id: const Uuid().v4(),
        categoria: CategoriaMantenimiento.motor,
        descripcion: 'Cambio de bujías de encendido',
        componenteAplica: TipoComponente.motor,
        intervaloKm: 40000,
        intervaloMeses: 24,
        intervaloSeveroKm: 25000,
        fuente: FuentePlan.oem,
        confianza: NivelConfianza.media,
      ),
    ],
  );
}
