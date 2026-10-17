import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/vehiculo.dart';
import '../../providers/providers.dart';
import '../crear_vehiculo/crear_vehiculo_screen.dart';
import '../detalle_vehiculo/detalle_vehiculo_screen.dart';

/// Pantalla principal de CarMain.
///
/// Muestra la lista de vehículos del usuario con su estado básico,
/// un FAB para crear vehículos nuevos y los estados de carga, error
/// y vacío correspondientes.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiculosAsync = ref.watch(vehiculosProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CarMain'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configuración',
            onPressed: () => _mostrarAjustes(context),
          ),
        ],
      ),
      body: vehiculosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorState(
          message: _mensajeError(error),
          onReintentar: () => ref.invalidate(vehiculosProvider),
        ),
        data: (vehiculos) {
          if (vehiculos.isEmpty) {
            return _EmptyState(
              onCrear: () => _navegarCrearVehiculo(context),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(vehiculosProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              itemCount: vehiculos.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final vehiculo = vehiculos[index];
                return _VehiculoCard(
                  vehiculo: vehiculo,
                  onTap: () => _navegarDetalle(context, vehiculo.id),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navegarCrearVehiculo(context),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo vehículo'),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
    );
  }

  void _navegarCrearVehiculo(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CrearVehiculoScreen()),
    );
  }

  void _navegarDetalle(BuildContext context, String id) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetalleVehiculoScreen(vehiculoId: id),
      ),
    );
  }

  void _mostrarAjustes(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.directions_car, color: Color(0xFFD32F2F)),
                    const SizedBox(width: 10),
                    Text(
                      'CarMain v1.0.0',
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.dns_outlined),
                  title: Text('Servidor Backend'),
                  subtitle: Text('http://localhost:8080 (Go)'),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.storage_outlined),
                  title: Text('Base de datos'),
                  subtitle: Text('Local-first (Drift / SQLite)'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _mensajeError(Object error) {
    return 'No se pudieron cargar los vehículos.\n${error.toString()}';
  }
}

/// Tarjeta individual de un vehículo.
class _VehiculoCard extends StatelessWidget {
  const _VehiculoCard({required this.vehiculo, required this.onTap});

  final Vehiculo vehiculo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Icono de vehículo.
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.directions_car_rounded,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              // Información principal.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehiculo.nombreCompleto,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatearKm(vehiculo.kilometrajeActual)} · '
                      '${vehiculo.drivetrain.label}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Chip de swap si aplica.
              if (vehiculo.tieneSwap) ...[
                const SizedBox(width: 8),
                _SwapChip(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Formatea un kilometraje con separador de miles (ej: 125000 -> "125,000 km").
  String _formatearKm(int km) {
    final grupos = <String>[];
    var restante = km.abs();
    if (restante == 0) return '0 km';
    while (restante > 0) {
      grupos.insert(0, (restante % 1000).toString().padLeft(3, '0'));
      restante ~/= 1000;
    }
    // El primer grupo no lleva ceros a la izquierda.
    grupos[0] = int.parse(grupos[0]).toString();
    final signo = km < 0 ? '-' : '';
    return '$signo${grupos.join(',')} km';
  }
}

/// Chip rojo que indica que el vehículo tiene componentes swap.
class _SwapChip extends StatelessWidget {
  const _SwapChip();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Swap',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onErrorContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Estado vacío: no hay vehículos registrados.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCrear});

  final VoidCallback onCrear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.directions_car_rounded,
              size: 96,
              color: colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'No tienes vehículos registrados',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Agrega tu primer vehículo para empezar a llevar su mantenimiento.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCrear,
              icon: const Icon(Icons.add),
              label: const Text('Crear vehículo'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Estado de error con botón de reintentar.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onReintentar});

  final String message;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onReintentar,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
