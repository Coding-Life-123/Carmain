import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/vehiculo_repository.dart';
import '../database/database.dart';
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
  final plan = await api.solicitarPlan(vehiculo);
  if (plan != null) {
    await repo.savePlan(plan);
    await repo.saveVehiculo(vehiculo.copyWith(
      planMantenimientoId: plan.id,
    ));
  }

  // Invalidar la lista de vehículos.
  ref.invalidate(vehiculosProvider);
  return vehiculo;
});
