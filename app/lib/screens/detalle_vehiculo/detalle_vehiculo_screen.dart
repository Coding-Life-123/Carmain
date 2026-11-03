import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enums.dart';
import '../../models/plan_mantenimiento.dart';
import '../../models/propuesta_mecanico.dart';
import '../../models/registro_mantenimiento.dart';
import '../../models/vehiculo.dart';
import '../../providers/providers.dart';
import '../../providers/sesiones_providers.dart';
import '../../utils/formato.dart';
import '../../widgets/actualizar_km_dialog.dart';
import '../../widgets/asistente_linea_base_dialog.dart';
import '../../widgets/compartir_vehiculo_sheet.dart';
import '../../widgets/eliminar_vehiculo_dialog.dart';
import '../../widgets/estado_plan.dart';
import '../../widgets/vehiculo_avatar.dart';
import '../crear_vehiculo/crear_vehiculo_screen.dart';
import '../registrar_mantenimiento/registrar_mantenimiento_screen.dart';
import '../revisar_propuesta/revisar_propuesta_screen.dart';

/// Pantalla de detalle de un vehículo.
///
/// Muestra la información del vehículo, analítica financiera y pasaporte digital,
/// puntos críticos del swap, plan de mantenimiento (ordenado por urgencia)
/// y el historial de mantenimientos realizados.
class DetalleVehiculoScreen extends ConsumerWidget {
  const DetalleVehiculoScreen({super.key, required this.vehiculoId});

  final String vehiculoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiculoAsync = ref.watch(vehiculoProvider(vehiculoId));
    final planAsync = ref.watch(planProvider(vehiculoId));
    final registrosAsync = ref.watch(registrosProvider(vehiculoId));
    final propuestasAsync = ref.watch(propuestasPendientesProvider(vehiculoId));
    final vehiculo = vehiculoAsync.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del vehículo'),
        actions: [
          if (vehiculo != null) ...[
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Compartir con taller',
              onPressed: () =>
                  CompartirVehiculoSheet.mostrar(context, vehiculo),
            ),
            IconButton(
              icon: const Icon(Icons.speed),
              tooltip: 'Actualizar kilometraje',
              onPressed: () => actualizarKilometraje(context, ref, vehiculo),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar vehículo',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CrearVehiculoScreen(vehiculoExistente: vehiculo),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Eliminar vehículo',
              onPressed: () async {
                final eliminado =
                    await confirmarYEliminarVehiculo(context, ref, vehiculo);
                if (eliminado && context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RegistrarMantenimientoScreen(vehiculoId: vehiculoId),
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
              ref.invalidate(kmPorDiaProvider(vehiculoId));
              ref.invalidate(analiticaVehiculoProvider(vehiculoId));
              ref.invalidate(propuestasPendientesProvider(vehiculoId));
              ref.invalidate(sesionesActivasProvider(vehiculoId));
              try {
                await ref.read(sincronizarPropuestasRemotasProvider(vehiculoId).future);
              } catch (_) {}
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                if (propuestasAsync.value != null &&
                    propuestasAsync.value!.isNotEmpty) ...[
                  for (final propuesta in propuestasAsync.value!) ...[
                    _BannerPropuesta(
                      vehiculo: vehiculo,
                      propuesta: propuesta,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
                _SeccionInfoVehiculo(vehiculo: vehiculo),
                const SizedBox(height: 16),
                _SeccionAnaliticaFinanciera(vehiculoId: vehiculoId),
                const SizedBox(height: 16),
                _SeccionPuntosFragilesSwap(planAsync: planAsync, vehiculo: vehiculo),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Visual del vehículo: silueta genérica de fondo + logo de la marca al frente.
                Hero(
                  tag: 'vehiculo-icono-${vehiculo.id}',
                  child: VehiculoAvatar(
                    marca: vehiculo.marca,
                    size: 58,
                    backgroundColor: cs.primaryContainer.withValues(alpha: 0.5),
                    colorFondoAuto:
                        cs.onPrimaryContainer.withValues(alpha: 0.28),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
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
                        const SizedBox(height: 2),
                        Text(
                          vehiculo.trim!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ChipInfo(
                  icon: Icons.directions_car,
                  label: vehiculo.drivetrain.label,
                ),
                if (vehiculo.placa != null && vehiculo.placa!.isNotEmpty)
                  _ChipInfo(
                    icon: Icons.badge_outlined,
                    label: vehiculo.placa!,
                  ),
                _ChipInfo(
                  icon: Icons.speed,
                  label: '${formatearNumero(vehiculo.kilometrajeActual)} km',
                ),
                _ChipInfo(
                  icon: Icons.local_gas_station,
                  label: '${motor.codigo} · ${motor.tipoCombustible.label}',
                ),
                if (motor.potenciaHp != null || motor.torqueNm != null)
                  _ChipInfo(
                    icon: Icons.bolt,
                    label: [
                      if (motor.potenciaHp != null) '${motor.potenciaHp} HP',
                      if (motor.torqueNm != null) '${motor.torqueNm} Nm',
                    ].join(' · '),
                  ),
                _ChipInfo(
                  icon: Icons.settings,
                  label: '${trans.codigo} · ${trans.tipo.label}',
                ),
                if (vehiculo.tieneSwap)
                  Chip(
                    avatar: Icon(Icons.swap_horiz, size: 18, color: cs.tertiary),
                    label: const Text('Swap'),
                    backgroundColor: cs.tertiary.withValues(alpha: 0.12),
                    labelStyle: TextStyle(
                      color: cs.tertiary,
                      fontWeight: FontWeight.w600,
                    ),
                    side: BorderSide(color: cs.tertiary.withValues(alpha: 0.3)),
                  ),
              ],
            ),
            if (swapDetalles.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Componentes modificados',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: cs.tertiary,
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

// ─────────────────────────── Sección Analítica Financiera y Pasaporte ───────────────────────────

class _SeccionAnaliticaFinanciera extends ConsumerWidget {
  const _SeccionAnaliticaFinanciera({required this.vehiculoId});

  final String vehiculoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analiticaAsync = ref.watch(analiticaVehiculoProvider(vehiculoId));
    final kmPorDiaAsync = ref.watch(kmPorDiaProvider(vehiculoId));
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return analiticaAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, _) => const SizedBox.shrink(),
      data: (analitica) {
        final kmPorDia = kmPorDiaAsync.value;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: Icon(Icons.analytics_outlined, color: cs.primary),
            title: Text(
              'Finanzas y Pasaporte Digital',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              analitica.costoPorKm != null
                  ? '${formatearCop(analitica.costoPorKm!)} / km · ${analitica.porcentajeHistorialVerificado.toStringAsFixed(0)}% verificado'
                  : (kmPorDia != null
                      ? 'Ritmo: ~${kmPorDia.toStringAsFixed(0)} km/día'
                      : 'Sin lecturas de ritmo aún'),
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _MetricaCard(
                            label: 'Costo por Km',
                            valor: analitica.costoPorKm != null
                                ? formatearCop(analitica.costoPorKm!)
                                : '—',
                            icono: Icons.speed,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MetricaCard(
                            label: 'Próx. Servicio',
                            valor: analitica.presupuestoProximoServicio != null
                                ? formatearCop(analitica.presupuestoProximoServicio!)
                                : '—',
                            icono: Icons.receipt_long_outlined,
                            color: cs.secondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MetricaCard(
                            label: 'Ritmo Promedio',
                            valor: kmPorDia != null
                                ? '${kmPorDia.toStringAsFixed(0)} km/d'
                                : '—',
                            icono: Icons.timeline,
                            color: cs.tertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.verified_outlined, size: 28, color: cs.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Pasaporte Digital',
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${analitica.porcentajeHistorialVerificado.toStringAsFixed(0)}% verificado',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: analitica.totalRegistros > 0
                                        ? analitica.porcentajeHistorialVerificado / 100.0
                                        : 0.0,
                                    color: cs.primary,
                                    backgroundColor: cs.outlineVariant.withValues(alpha: 0.3),
                                    minHeight: 6,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${analitica.registrosSelladosTaller} sellados taller · ${analitica.registrosConEvidencia} con evidencia · Total ${formatearCop(analitica.costoTotal)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MetricaCard extends StatelessWidget {
  const _MetricaCard({
    required this.label,
    required this.valor,
    required this.icono,
    required this.color,
  });

  final String label;
  final String valor;
  final IconData icono;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Sección Swaps: Puntos Críticos y Cuellos de Botella ───────────────────────────

class _SeccionPuntosFragilesSwap extends StatelessWidget {
  const _SeccionPuntosFragilesSwap({
    required this.planAsync,
    required this.vehiculo,
  });

  final AsyncValue<PlanMantenimiento?> planAsync;
  final Vehiculo vehiculo;

  @override
  Widget build(BuildContext context) {
    final plan = planAsync.value;
    final alertas = plan?.alertasIngenieria ?? const [];

    if (!vehiculo.tieneSwap && alertas.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final altas =
        alertas.where((a) => a.severidad == SeveridadIngenieria.alta).length;
    final medias =
        alertas.where((a) => a.severidad == SeveridadIngenieria.media).length;
    final recomendaciones = alertas
        .where((a) => a.severidad == SeveridadIngenieria.recomendacion)
        .length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(Icons.engineering_rounded, color: cs.tertiary),
        title: Text(
          'Ingeniería del Swap y Puntos Críticos',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (altas > 0)
                _AlertaCountBadge(
                  color: cs.error,
                  label: '$altas riesgo alto',
                ),
              if (medias > 0)
                _AlertaCountBadge(
                  color: Colors.amber.shade800,
                  label: '$medias atención media',
                ),
              if (recomendaciones > 0)
                _AlertaCountBadge(
                  color: cs.primary,
                  label: '$recomendaciones upgrade',
                ),
              if (alertas.isEmpty)
                Text(
                  'Monitoreando asimetría de tren motriz',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),
        children: [
          if (alertas.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Sin cuellos de botella detectados para esta configuración técnica.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  for (final alerta in alertas) ...[
                    _AlertaCard(alerta: alerta),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AlertaCountBadge extends StatelessWidget {
  const _AlertaCountBadge({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

class _AlertaCard extends StatelessWidget {
  const _AlertaCard({required this.alerta});
  final AlertaIngenieria alerta;

  Color _colorSeveridad(ColorScheme cs) {
    switch (alerta.severidad) {
      case SeveridadIngenieria.alta:
        return cs.error;
      case SeveridadIngenieria.media:
        return Colors.amber.shade800;
      case SeveridadIngenieria.recomendacion:
        return cs.primary;
    }
  }

  IconData _iconoSeveridad() {
    switch (alerta.severidad) {
      case SeveridadIngenieria.alta:
        return Icons.warning_rounded;
      case SeveridadIngenieria.media:
        return Icons.info_outline_rounded;
      case SeveridadIngenieria.recomendacion:
        return Icons.trending_up_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = _colorSeveridad(cs);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconoSeveridad(), size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                alerta.severidad.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  alerta.componenteAfectado,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            alerta.titulo,
            style:
                theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            alerta.diagnostico,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (alerta.recomendacionUpgrade != null &&
              alerta.recomendacionUpgrade!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.build_circle_outlined, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Upgrade sugerido: ${alerta.recomendacionUpgrade!}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────── Sección 2: Plan de mantenimiento ───────────────────────────

class _SeccionPlan extends ConsumerWidget {
  const _SeccionPlan({required this.planAsync, required this.vehiculo});

  final AsyncValue<PlanMantenimiento?> planAsync;
  final Vehiculo vehiculo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kmActual = vehiculo.kilometrajeActual;
    final tipoUso = vehiculo.tipoUso;
    final kmPorDia = ref.watch(kmPorDiaProvider(vehiculo.id)).value;

    final resumen = ResumenPlan.de(
      planAsync.value,
      kmActual,
      tipoUso,
      kmPorDia: kmPorDia,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: const Text('Plan de mantenimiento'),
        subtitle: resumen.total == 0
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ResumenPlanPills(resumen: resumen),
                ),
              ),
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
              // Ordenar por urgencia: vencidos -> próximos -> desconocidos -> ok.
              int prioridad(EstadoItem e) => switch (e) {
                    EstadoItem.vencido => 0,
                    EstadoItem.proximo => 1,
                    EstadoItem.desconocido => 2,
                    EstadoItem.ok => 3,
                  };

              final ordenados = [...plan.items]..sort((a, b) {
                final ea = prioridad(a.estado(kmActual, tipoUso, kmPorDia: kmPorDia));
                final eb = prioridad(b.estado(kmActual, tipoUso, kmPorDia: kmPorDia));
                return ea.compareTo(eb);
              });
              return Column(
                children: [
                  if (resumen.desconocidos > 0)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.help_outline_rounded,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${resumen.desconocidos} ítems sin registro',
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Configura cuándo se hicieron por última vez.',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => AsistenteLineaBaseDialog.mostrar(
                              context,
                              vehiculo: vehiculo,
                              plan: plan,
                            ),
                            child: const Text('Configurar'),
                          ),
                        ],
                      ),
                    ),
                  for (final item in ordenados) ...[
                    const Divider(indent: 16, endIndent: 16),
                    _ItemPlanTile(
                      item: item,
                      kmActual: kmActual,
                      tipoUso: tipoUso,
                      kmPorDia: kmPorDia,
                    ),
                  ],
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
    this.kmPorDia,
  });

  final ItemMantenimiento item;
  final int kmActual;
  final TipoUso tipoUso;
  final double? kmPorDia;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final estado = item.estado(kmActual, tipoUso, kmPorDia: kmPorDia);
    final visual = estadoVisual(estado, cs);
    final urgente = item.esRecordatorioUrgente(kmActual, tipoUso, kmPorDia: kmPorDia);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Row(
        children: [
          Expanded(
            child: Text(
              item.descripcion,
              style:
                  theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (item.esVigilanciaSwap) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.tertiary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: cs.tertiary.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined, size: 11, color: cs.tertiary),
                  const SizedBox(width: 3),
                  Text(
                    'Swap',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: cs.tertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (urgente) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: cs.error.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notification_important, size: 11, color: cs.error),
                  const SizedBox(width: 3),
                  Text(
                    'Urgente',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: cs.error,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(width: 8),
          EstadoPill(estado: estado, dense: true),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            tween: Tween<double>(
              begin: 0.0,
              end: item.progresoIntervalo(kmActual, tipoUso),
            ),
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              color: visual.color,
              backgroundColor: visual.color.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  textoEstadoDetalle(item, kmActual, tipoUso, kmPorDia: kmPorDia),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: visual.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                'cada ${formatearKm(item.intervaloEfectivoKm(tipoUso))}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ChipInfo(label: item.categoria.label),
              if (item.ultimaVezKm != null)
                _ChipInfo(
                  icon: Icons.history,
                  label: 'Última vez: ${formatearKm(item.ultimaVezKm!)}',
                ),
            ],
          ),
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

class _RegistroTile extends ConsumerWidget {
  const _RegistroTile({required this.registro});

  final RegistroMantenimiento registro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: const Icon(Icons.build_circle_outlined),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        tooltip: 'Eliminar registro',
        onPressed: () async {
          final confirmar = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Eliminar registro'),
              content: const Text(
                '¿Deseas eliminar este registro de mantenimiento? El plan y las estadísticas se recalcularán automáticamente.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: cs.onError,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Eliminar'),
                ),
              ],
            ),
          );
          if (confirmar == true) {
            await ref.read(eliminarRegistroProvider((
              registroId: registro.id,
              vehiculoId: registro.vehiculoId,
            )).future);
          }
        },
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              formatearFecha(registro.fecha),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          _NivelVerificacionBadge(nivel: registro.nivelVerificacion),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            '${formatearNumero(registro.kilometraje)} km',
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
              'Costo: ${formatearCop(registro.costo!)}',
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

class _NivelVerificacionBadge extends StatelessWidget {
  const _NivelVerificacionBadge({required this.nivel});

  final NivelVerificacionHistorial nivel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, color, label) = switch (nivel) {
      NivelVerificacionHistorial.selladoTaller => (
          Icons.verified,
          const Color(0xFF10B981),
          'Sellado Taller'
        ),
      NivelVerificacionHistorial.conEvidencia => (
          Icons.attach_file,
          cs.primary,
          'Documentado'
        ),
      NivelVerificacionHistorial.declarado => (
          Icons.person_outline,
          cs.outline,
          'Declarado'
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
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

class _BannerPropuesta extends StatelessWidget {
  const _BannerPropuesta({
    required this.vehiculo,
    required this.propuesta,
  });

  final Vehiculo vehiculo;
  final PropuestaMecanicoModel propuesta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: const Color(0xFF10B981).withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(
          color: Color(0xFF10B981),
          width: 1.2,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.mark_email_unread_rounded,
              color: Color(0xFF10B981)),
        ),
        title: Text(
          'Propuesta de taller recibida',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${propuesta.taller ?? 'Taller'} · ${formatearNumero(propuesta.kilometraje)} km · ${propuesta.itemsRealizados.length} trabajos',
          style: theme.textTheme.bodySmall,
        ),
        trailing: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RevisarPropuestaScreen(
                  vehiculo: vehiculo,
                  propuesta: propuesta,
                ),
              ),
            );
          },
          child: const Text('Revisar'),
        ),
      ),
    );
  }
}

