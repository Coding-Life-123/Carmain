import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vehiculo.dart';
import '../providers/providers.dart';

/// Confirmación + eliminación de un vehículo, compartido por el dashboard
/// y la pantalla de detalle. Retorna `true` si se eliminó.
///
/// La eliminación es en cascade (plan, registros, sesiones — ver
/// VehiculoRepository.deleteVehiculo): el diálogo lo deja explícito para
/// que el usuario sepa exactamente qué pierde.
Future<bool> confirmarYEliminarVehiculo(
    BuildContext context, WidgetRef ref, Vehiculo vehiculo) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('¿Eliminar vehículo?'),
      content: Text(
        '${vehiculo.nombreCompleto} se eliminará junto con su plan y su '
        'historial de mantenimiento.\n\nEsta acción no se puede deshacer.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
  if (confirmado != true) return false;

  try {
    // invalidate antes del read: el provider de acción no es autoDispose y
    // un miembro del family que ya quedó en error devolvería el mismo
    // futuro fallido — reintentar la eliminación debe re-ejecutarla.
    ref.invalidate(eliminarVehiculoProvider(vehiculo.id));
    await ref.read(eliminarVehiculoProvider(vehiculo.id).future);
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar el vehículo: $e')),
      );
    }
    return false;
  }
}
