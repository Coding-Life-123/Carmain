import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../models/plan_mantenimiento.dart';
import '../models/propuesta_mecanico.dart';
import 'providers.dart';

/// Sesiones de taller activas para un vehículo específico.
final sesionesActivasProvider =
    FutureProvider.family<List<SesionMecanicoRow>, String>((ref, vehiculoId) async {
  return await ref.watch(repositoryProvider).getSesionesActivas(vehiculoId);
});

/// Propuestas pendientes recibidas para un vehículo.
final propuestasPendientesProvider =
    FutureProvider.family<List<PropuestaMecanicoModel>, String>(
        (ref, vehiculoId) async {
  return await ref.watch(repositoryProvider).getPropuestasPendientes(vehiculoId);
});

/// Sincroniza las propuestas pendientes que hayan quedado en el buzón remoto del servidor.
final sincronizarPropuestasRemotasProvider =
    FutureProvider.family<int, String>((ref, vehiculoId) async {
  final repo = ref.read(repositoryProvider);
  final api = ref.read(apiClientProvider);
  final sesiones = await repo.getSesionesActivas(vehiculoId);

  var nuevas = 0;
  for (final s in sesiones) {
    try {
      final propuestasRemotas = await api.obtenerPropuestasPendientes(s.id);
      if (propuestasRemotas.isNotEmpty) {
        for (final pJson in propuestasRemotas) {
          final propuesta = PropuestaMecanicoModel.fromJson(
            pJson,
            sesionId: s.id,
            vehiculoId: vehiculoId,
          );
          await repo.savePropuestaRecibida(propuesta);
          nuevas++;
        }
        // Vaciamos el buzón del servidor para no reimportarlas
        await api.confirmarPropuestas(s.id);
      }
    } catch (_) {
      // Si el servidor no responde o no hay red, continuamos silenciosamente (local-first)
    }
  }

  if (nuevas > 0) {
    ref.invalidate(propuestasPendientesProvider(vehiculoId));
  }
  return nuevas;
});

/// Parámetros para aceptar una propuesta de taller.
class AceptarPropuestaArgs {
  final PropuestaMecanicoModel propuesta;
  final List<ItemMantenimiento> itemsAIncorporar;

  const AceptarPropuestaArgs({
    required this.propuesta,
    this.itemsAIncorporar = const [],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AceptarPropuestaArgs &&
          runtimeType == other.runtimeType &&
          propuesta.id == other.propuesta.id &&
          itemsAIncorporar.length == other.itemsAIncorporar.length;

  @override
  int get hashCode => Object.hash(propuesta.id, itemsAIncorporar.length);
}

/// Acepta una propuesta de taller y genera el registro en el historial.
final aceptarPropuestaProvider =
    FutureProvider.family<void, AceptarPropuestaArgs>((ref, args) async {
  final repo = ref.read(repositoryProvider);
  await repo.aceptarPropuesta(
    args.propuesta,
    itemsAIncorporar: args.itemsAIncorporar,
  );

  ref.invalidate(propuestasPendientesProvider(args.propuesta.vehiculoId));
  ref.invalidate(registrosProvider(args.propuesta.vehiculoId));
  ref.invalidate(planProvider(args.propuesta.vehiculoId));
  ref.invalidate(vehiculoProvider(args.propuesta.vehiculoId));
  ref.invalidate(kmPorDiaProvider(args.propuesta.vehiculoId));
  ref.invalidate(analiticaVehiculoProvider(args.propuesta.vehiculoId));
  ref.invalidate(vehiculosProvider);
});

/// Rechaza una propuesta de taller.
final rechazarPropuestaProvider = FutureProvider.family<void,
    ({String propuestaId, String vehiculoId})>((ref, args) async {
  final repo = ref.read(repositoryProvider);
  await repo.rechazarPropuesta(args.propuestaId);
  ref.invalidate(propuestasPendientesProvider(args.vehiculoId));
});

