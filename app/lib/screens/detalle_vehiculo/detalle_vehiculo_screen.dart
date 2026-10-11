import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enums.dart';
import '../../models/plan_mantenimiento.dart';
import '../../models/registro_mantenimiento.dart';
import '../../models/vehiculo.dart';
import '../../providers/providers.dart';

/// Pantalla de detalle de un vehículo.
///
/// Muestra la información del vehículo, su plan de mantenimiento
/// (ordenado por urgencia) y el historial de mantenimientos realizados.
class DetalleVehiculoScreen extends ConsumerWidget {
  const DetalleVehiculoScreen({super.key, required this.vehiculoId});

  final String vehiculoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiculoAsync = ref.watch(vehiculoProvider(vehiculoId));
    final planAsync = ref.watch(planProvider(vehiculoId));
    final registrosAsync = ref.watch(registrosProvider(vehiculoId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del vehículo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Editar componentes (swap)',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Edición de componentes próximamente'),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const _PlaceholderRegistro(),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Registrar mantenimiento'),
      ),
      body: vehiculoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _EstadoError(mensaje: error.toString()),
        data: (vehiculo) {
          if (vehiculo == null) {
            return const _EstadoError(mensaje: 'No se encontró el vehículo.');
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(vehiculoProvider(vehiculoId));
              ref.invalidate(planProvider(vehiculoId));
              ref.invalidate(registrosProvider(vehiculoId));
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                _SeccionInfoVehiculo(vehiculo: vehiculo),
                const SizedBox(height: 16),
                _SeccionPlan(planAsync: planAsync, vehiculo: vehiculo),
                const SizedBox(height: 16),
                _SeccionHistorial(registrosAsync: registrosAsync),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────── Sección 1: Info del vehículo ───────────────────────────

class _SeccionInfoVehiculo extends StatelessWidget {
  const _SeccionInfoVehiculo({required this.vehiculo});

  final Vehiculo vehiculo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final motor = vehiculo.motor;
    final trans = vehiculo.transmision;

    // Detalle de qué componentes se cambiaron (swap).
    final swapDetalles = <String>[];
    if (!motor.esOriginal) {
      swapDetalles.add('Motor: ${motor.originalCodigo ?? '—'} → ${motor.codigo}');
    }
    if (!trans.esOriginal) {
      swapDetalles.add(
        'Transmisión: ${trans.originalCodigo ?? '—'} → ${trans.codigo}',
      );
    }
    for (final c in vehiculo.componentesExtra) {
      if (!c.esOriginal) {
        swapDetalles.add('${c.tipo.label}: ${c.originalCodigo ?? '—'} → ${c.codigo}');
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              vehiculo.nombreCompleto,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (vehiculo.trim != null) ...[
              const SizedBox(height: 4),
              Text(
                vehiculo.trim!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ChipInfo(
                  icon: Icons.directions_car,
                  label: vehiculo.drivetrain.label,
                ),
                _ChipInfo(
                  icon: Icons.speed,
                  label: '${_formatearNumero(vehiculo.kilometrajeActual)} km',
                ),
                _ChipInfo(
                  icon: Icons.local_gas_station,
                  label: '${motor.codigo} · ${motor.tipoCombustible.label}',
                ),
                _ChipInfo(
                  icon: Icons.settings,
                  label: '${trans.codigo} · ${trans.tipo.label}',
                ),
                if (vehiculo.tieneSwap)
                  Chip(
                    avatar: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Swap'),
                    backgroundColor: cs.errorContainer,
                    labelStyle: TextStyle(
                      color: cs.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                    side: BorderSide.none,
                  ),
              ],
            ),
            if (swapDetalles.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Componentes modificados',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: cs.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              for (final d in swapDetalles)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    d,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Sección 2: Plan de mantenimiento ───────────────────────────

class _SeccionPlan extends StatelessWidget {
  const _SeccionPlan({required this.planAsync, required this.vehiculo});

  final AsyncValue<PlanMantenimiento?> planAsync;
  final Vehiculo vehiculo;

  @override
  Widget build(BuildContext context) {
    final kmActual = vehiculo.kilometrajeActual;
    final tipoUso = vehiculo.tipoUso;

    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: const Text('Plan de mantenimiento'),
        children: [
          planAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: _EstadoError(mensaje: error.toString()),
            ),
            data: (plan) {
              if (plan == null || plan.items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Sin plan de mantenimiento.'),
                );
              }
              // Ordenar por urgencia: vencidos (0) → próximos (1) → ok (2).
              final ordenados = [...plan.items]..sort((a, b) {
                final ea = a.estado(kmActual, tipoUso).index;
                final eb = b.estado(kmActual, tipoUso).index;
                return ea.compareTo(eb);
              });
              return Column(
                children: [
                  for (final item in ordenados)
                    _ItemPlanTile(
                      item: item,
                      kmActual: kmActual,
                      tipoUso: tipoUso,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ItemPlanTile extends StatelessWidget {
  const _ItemPlanTile({
    required this.item,
    required this.kmActual,
    required this.tipoUso,
  });

  final ItemMantenimiento item;
  final int kmActual;
  final TipoUso tipoUso;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final estado = item.estado(kmActual, tipoUso);
    final visual = _estadoVisual(estado);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      title: Text(
        item.descripcion,
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ChipInfo(label: item.categoria.label),
              _ChipInfo(label: '${_formatearNumero(item.intervaloKm)} km'),
              Chip(
                avatar: Icon(visual.icon, size: 16, color: visual.color),
                label: Text(visual.label),
                labelStyle: TextStyle(
                  color: visual.color,
                  fontWeight: FontWeight.w600,
                ),
                side: BorderSide(color: visual.color),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ],
          ),
          if (item.ultimaVezKm != null) ...[
            const SizedBox(height: 4),
            Text(
              'Última vez: ${_formatearNumero(item.ultimaVezKm!)} km',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────── Sección 3: Historial ───────────────────────────

class _SeccionHistorial extends StatelessWidget {
  const _SeccionHistorial({required this.registrosAsync});

  final AsyncValue<List<RegistroMantenimiento>> registrosAsync;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        title: const Text('Historial de mantenimiento'),
        children: [
          registrosAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: _EstadoError(mensaje: error.toString()),
            ),
            data: (registros) {
              if (registros.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Aún no hay mantenimientos registrados.'),
                );
              }
              // Más recientes primero.
              final ordenados = [...registros]
                ..sort((a, b) => b.fecha.compareTo(a.fecha));
              return Column(
                children: [
                  for (final r in ordenados) _RegistroTile(registro: r),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RegistroTile extends StatelessWidget {
  const _RegistroTile({required this.registro});

  final RegistroMantenimiento registro;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: const Icon(Icons.build_circle_outlined),
      title: Text(
        _formatearFecha(registro.fecha),
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            '${_formatearNumero(registro.kilometraje)} km',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          if (registro.itemsRealizados.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final item in registro.itemsRealizados)
                  _ChipInfo(label: item.descripcion),
              ],
            ),
          ],
          if (registro.costo != null) ...[
            const SizedBox(height: 4),
            Text(
              'Costo: \$${registro.costo!.toStringAsFixed(2)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (registro.taller != null) ...[
            const SizedBox(height: 2),
            Text(
              'Taller: ${registro.taller}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      isThreeLine: true,
    );
  }
}

// ─────────────────────────── Widgets auxiliares ───────────────────────────

class _ChipInfo extends StatelessWidget {
  const _ChipInfo({this.icon, required this.label});

  final IconData? icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Chip(
      avatar: icon != null ? Icon(icon, size: 16) : null,
      label: Text(label),
      backgroundColor: cs.surfaceContainerHighest,
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _EstadoError extends StatelessWidget {
  const _EstadoError({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text('Ocurrió un error', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderRegistro extends StatelessWidget {
  const _PlaceholderRegistro();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar mantenimiento')),
      body: const Center(
        child: Text('Pantalla de registro de mantenimiento (próximamente)'),
      ),
    );
  }
}

// ─────────────────────────── Helpers ───────────────────────────

/// Formatea un entero con separador de miles (punto).
String _formatearNumero(int valor) {
  final negativo = valor < 0;
  final str = valor.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buffer.write('.');
    buffer.write(str[i]);
  }
  return negativo ? '-$buffer' : buffer.toString();
}

/// Formatea una fecha como dd/MM/yyyy.
String _formatearFecha(DateTime fecha) {
  final d = fecha.day.toString().padLeft(2, '0');
  final m = fecha.month.toString().padLeft(2, '0');
  return '$d/$m/${fecha.year}';
}

/// Retorna el icono, color y etiqueta para cada estado de un ítem del plan.
({IconData icon, Color color, String label}) _estadoVisual(EstadoItem estado) {
  return switch (estado) {
    EstadoItem.vencido => (
      icon: Icons.warning_amber_rounded,
      color: const Color(0xFFD32F2F),
      label: 'Vencido',
    ),
    EstadoItem.proximo => (
      icon: Icons.schedule,
      color: const Color(0xFFF57C00),
      label: 'Próximo',
    ),
    EstadoItem.ok => (
      icon: Icons.check_circle,
      color: const Color(0xFF388E3C),
      label: 'Al día',
    ),
  };
}
