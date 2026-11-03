import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enums.dart';
import '../../models/propuesta_mecanico.dart';
import '../../models/vehiculo.dart';
import '../../providers/sesiones_providers.dart';
import '../../utils/formato.dart';

/// Pantalla para que el dueño revise y apruebe una propuesta enviada por el taller mecánico.
///
/// Al ser aprobada, se integra al historial del vehículo con nivel
/// `NivelVerificacionHistorial.selladoTaller` (Nivel 3).
class RevisarPropuestaScreen extends ConsumerStatefulWidget {
  final Vehiculo vehiculo;
  final PropuestaMecanicoModel propuesta;

  const RevisarPropuestaScreen({
    super.key,
    required this.vehiculo,
    required this.propuesta,
  });

  @override
  ConsumerState<RevisarPropuestaScreen> createState() =>
      _RevisarPropuestaScreenState();
}

class _RevisarPropuestaScreenState extends ConsumerState<RevisarPropuestaScreen> {
  bool _procesando = false;

  Future<void> _aceptar() async {
    setState(() => _procesando = true);
    try {
      await ref.read(aceptarPropuestaProvider(widget.propuesta).future);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '¡Mantenimiento integrado con sello de taller Nivel 3!',
            ),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _procesando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al aceptar la propuesta: $e')),
        );
      }
    }
  }

  Future<void> _rechazar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar propuesta'),
        content: const Text(
          '¿Deseas descartar esta propuesta del taller? No se añadirá al historial.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      setState(() => _procesando = true);
      try {
        await ref.read(rechazarPropuestaProvider((
          propuestaId: widget.propuesta.id,
          vehiculoId: widget.vehiculo.id,
        )).future);
        if (mounted) {
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          setState(() => _procesando = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final propuesta = widget.propuesta;
    final vehiculo = widget.vehiculo;

    final saltoKm = propuesta.kilometraje - vehiculo.kilometrajeActual;
    final kmAnormal = propuesta.kilometraje < vehiculo.kilometrajeActual;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisar servicio de taller'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Banner de procedencia del taller
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified, color: Color(0xFF10B981), size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        propuesta.taller ?? 'Taller automotriz',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (propuesta.mecanicoNombre != null &&
                          propuesta.mecanicoNombre!.isNotEmpty)
                        Text(
                          'Mecánico: ${propuesta.mecanicoNombre}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      Text(
                        'Recibido: ${formatearFecha(propuesta.recibidaEn)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tarjeta de datos principales
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lectura de kilometraje',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${formatearNumero(propuesta.kilometraje)} km',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (saltoKm > 0)
                        Chip(
                          label: Text('+${formatearNumero(saltoKm)} km'),
                          backgroundColor: cs.surfaceContainerHighest,
                          padding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                  if (kmAnormal) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.errorContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: cs.error, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'El odómetro propuesto (${formatearNumero(propuesta.kilometraje)} km) es menor que el registrado actualmente (${formatearNumero(vehiculo.kilometrajeActual)} km).',
                              style: TextStyle(color: cs.error, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Divider(),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Fecha del servicio',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            propuesta.fecha,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (propuesta.costo != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Costo facturado',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formatearCop(propuesta.costo!),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: cs.primary,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Ítems realizados
          Text(
            'Trabajos realizados (${propuesta.itemsRealizados.length})',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in propuesta.itemsRealizados)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  item.itemId != null
                      ? Icons.check_circle_outline
                      : Icons.add_circle_outline,
                  color: cs.primary,
                ),
                title: Text(
                  item.descripcion,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${item.categoria.label} · ${item.componenteAplica.label}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                trailing: item.itemId != null
                    ? Chip(
                        label: const Text('Del plan'),
                        backgroundColor: cs.tertiary.withValues(alpha: 0.12),
                        labelStyle: TextStyle(color: cs.tertiary, fontSize: 11),
                        side: BorderSide.none,
                      )
                    : Chip(
                        label: const Text('Adicional'),
                        backgroundColor: cs.surfaceContainerHighest,
                        labelStyle: const TextStyle(fontSize: 11),
                        side: BorderSide.none,
                      ),
              ),
            ),

          if (propuesta.notas != null && propuesta.notas!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Notas del mecánico',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Text(
                propuesta.notas!,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Botones de acción
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _procesando ? null : _rechazar,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.error,
                    side: BorderSide(color: cs.error),
                  ),
                  child: const Text('Rechazar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _procesando ? null : _aceptar,
                  icon: _procesando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: const Text('Aceptar y sellar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

