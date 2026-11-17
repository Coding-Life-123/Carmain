import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/vehiculo_repository.dart';
import '../../models/enums.dart';
import '../../models/plan_mantenimiento.dart';
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

(int km, int meses) _intervaloRecomendado(CategoriaMantenimiento cat) {
  return switch (cat) {
    CategoriaMantenimiento.motor => (10000, 12),
    CategoriaMantenimiento.frenos => (20000, 24),
    CategoriaMantenimiento.transmision => (40000, 24),
    CategoriaMantenimiento.diferencial => (40000, 24),
    CategoriaMantenimiento.refrigeracion => (40000, 24),
    CategoriaMantenimiento.suspension => (30000, 24),
    CategoriaMantenimiento.neumaticos => (10000, 12),
    CategoriaMantenimiento.electrico => (30000, 24),
    CategoriaMantenimiento.escape => (50000, 36),
    CategoriaMantenimiento.inspeccion => (10000, 12),
  };
}

class _ConfigItemAdicional {
  bool incorporar = false;
  int intervaloKm;
  int intervaloMeses;
  final TextEditingController kmController;
  final TextEditingController mesesController;

  _ConfigItemAdicional({
    required this.intervaloKm,
    required this.intervaloMeses,
  })  : kmController = TextEditingController(text: intervaloKm.toString()),
        mesesController = TextEditingController(text: intervaloMeses.toString());

  void dispose() {
    kmController.dispose();
    mesesController.dispose();
  }
}

class _RevisarPropuestaScreenState extends ConsumerState<RevisarPropuestaScreen> {
  bool _procesando = false;
  final Map<int, _ConfigItemAdicional> _adicionalesConfig = {};

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.propuesta.itemsRealizados.length; i++) {
      final item = widget.propuesta.itemsRealizados[i];
      if (item.itemId == null) {
        final (km, meses) = _intervaloRecomendado(item.categoria);
        _adicionalesConfig[i] = _ConfigItemAdicional(
          intervaloKm: km,
          intervaloMeses: meses,
        );
      }
    }
  }

  @override
  void dispose() {
    for (final cfg in _adicionalesConfig.values) {
      cfg.dispose();
    }
    super.dispose();
  }

  Future<void> _aceptar() async {
    setState(() => _procesando = true);
    try {
      final fechaPropuesta =
          DateTime.tryParse(widget.propuesta.fecha) ?? DateTime.now();
      final nuevosItems = <ItemMantenimiento>[];

      for (var i = 0; i < widget.propuesta.itemsRealizados.length; i++) {
        final cfg = _adicionalesConfig[i];
        if (cfg != null && cfg.incorporar) {
          final itemPropuesta = widget.propuesta.itemsRealizados[i];
          final km = int.tryParse(
                  cfg.kmController.text.replaceAll(RegExp(r'\D'), '')) ??
              cfg.intervaloKm;
          final meses = int.tryParse(
                  cfg.mesesController.text.replaceAll(RegExp(r'\D'), '')) ??
              cfg.intervaloMeses;

          nuevosItems.add(ItemMantenimiento(
            id: VehiculoRepository.newId(),
            categoria: itemPropuesta.categoria,
            descripcion: itemPropuesta.descripcion,
            componenteAplica: itemPropuesta.componenteAplica,
            intervaloKm: km > 0 ? km : 10000,
            intervaloMeses: meses > 0 ? meses : null,
            ultimaVezKm: widget.propuesta.kilometraje,
            ultimaVezFecha: fechaPropuesta,
            fuente: FuentePlan.taller,
            confianza: NivelConfianza.alta,
          ));
        }
      }

      await ref.read(aceptarPropuestaProvider(
        AceptarPropuestaArgs(
          propuesta: widget.propuesta,
          itemsAIncorporar: nuevosItems,
        ),
      ).future);
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
          for (var i = 0; i < propuesta.itemsRealizados.length; i++) ...[
            Builder(builder: (context) {
              final item = propuesta.itemsRealizados[i];
              final esAdicional = item.itemId == null;
              final cfg = _adicionalesConfig[i];

              if (!esAdicional || cfg == null) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      Icons.check_circle_outline,
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
                    trailing: Chip(
                      label: const Text('Del plan'),
                      backgroundColor: cs.tertiary.withValues(alpha: 0.12),
                      labelStyle: TextStyle(color: cs.tertiary, fontSize: 11),
                      side: BorderSide.none,
                    ),
                  ),
                );
              }

              // Ítem adicional propuesto por el taller
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: cfg.incorporar
                        ? cs.primary.withValues(alpha: 0.5)
                        : cs.outlineVariant,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.add_circle_outline,
                            color: cs.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.descripcion,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${item.categoria.label} · ${item.componenteAplica.label}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Chip(
                            label: const Text('Adicional'),
                            backgroundColor: cs.surfaceContainerHighest,
                            labelStyle: const TextStyle(fontSize: 11),
                            side: BorderSide.none,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '¿Incorporar a mantenimientos periódicos?',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          'Se añadirá al plan preventivo permanente para recordar sus próximos servicios.',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        value: cfg.incorporar,
                        onChanged: (val) {
                          setState(() => cfg.incorporar = val);
                        },
                      ),
                      if (cfg.incorporar) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: cfg.kmController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Cada cuántos km',
                                  suffixText: 'km',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: cfg.mesesController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Meses',
                                  suffixText: 'meses',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final km in [10000, 20000, 30000, 40000, 50000])
                              ActionChip(
                                label: Text('${formatearNumero(km)} km'),
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  setState(() {
                                    cfg.kmController.text = km.toString();
                                  });
                                },
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],

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

