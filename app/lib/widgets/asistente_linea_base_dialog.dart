import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enums.dart';
import '../models/plan_mantenimiento.dart';
import '../models/vehiculo.dart';
import '../providers/providers.dart';
import '../utils/formato.dart';

/// Modal para configurar la línea base inicial de los ítems críticos de mantenimiento.
///
/// Permite al dueño indicar para cada ítem crítico:
/// - "Hecho hace poco" (al día al km actual)
/// - "Hace ~X km" (estimación del último servicio)
/// - "No sé / Sin registro" (queda en estado desconocido para inspección)
class AsistenteLineaBaseDialog extends ConsumerStatefulWidget {
  final Vehiculo vehiculo;
  final PlanMantenimiento plan;

  const AsistenteLineaBaseDialog({
    super.key,
    required this.vehiculo,
    required this.plan,
  });

  static Future<void> mostrar(
    BuildContext context, {
    required Vehiculo vehiculo,
    required PlanMantenimiento plan,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AsistenteLineaBaseDialog(
        vehiculo: vehiculo,
        plan: plan,
      ),
    );
  }

  @override
  ConsumerState<AsistenteLineaBaseDialog> createState() =>
      _AsistenteLineaBaseDialogState();
}

enum _OpcionLineaBase { alDia, haceKm, noSe }

class _EstadoItemConfig {
  _OpcionLineaBase opcion;
  int? kmAtras;

  _EstadoItemConfig({this.opcion = _OpcionLineaBase.noSe, this.kmAtras});
}

class _AsistenteLineaBaseDialogState
    extends ConsumerState<AsistenteLineaBaseDialog> {
  final Map<String, _EstadoItemConfig> _configs = {};
  bool _guardando = false;

  static const _categoriasCriticas = {
    CategoriaMantenimiento.motor,
    CategoriaMantenimiento.frenos,
    CategoriaMantenimiento.transmision,
    CategoriaMantenimiento.refrigeracion,
    CategoriaMantenimiento.diferencial,
  };

  late final List<ItemMantenimiento> _itemsACancelar;

  @override
  void initState() {
    super.initState();
    // Priorizar ítems críticos o que no tengan registro previo
    _itemsACancelar = widget.plan.items.where((i) {
      return _categoriasCriticas.contains(i.categoria) ||
          i.ultimaVezKm == null;
    }).toList();

    for (final item in _itemsACancelar) {
      if (item.ultimaVezKm != null) {
        final diff = widget.vehiculo.kilometrajeActual - item.ultimaVezKm!;
        if (diff <= 1000) {
          _configs[item.id] =
              _EstadoItemConfig(opcion: _OpcionLineaBase.alDia);
        } else {
          _configs[item.id] = _EstadoItemConfig(
              opcion: _OpcionLineaBase.haceKm, kmAtras: diff);
        }
      } else {
        _configs[item.id] = _EstadoItemConfig(opcion: _OpcionLineaBase.noSe);
      }
    }
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    final ahora = DateTime.now();
    final kmActual = widget.vehiculo.kilometrajeActual;

    final itemsActualizados = widget.plan.items.map((item) {
      final config = _configs[item.id];
      if (config == null) return item;

      switch (config.opcion) {
        case _OpcionLineaBase.alDia:
          return item.copyWith(
            ultimaVezKm: kmActual,
            ultimaVezFecha: ahora,
          );
        case _OpcionLineaBase.haceKm:
          final kmRef = (kmActual - (config.kmAtras ?? 0)).clamp(0, kmActual);
          return item.copyWith(
            ultimaVezKm: kmRef,
            ultimaVezFecha: ahora.subtract(const Duration(days: 30)),
          );
        case _OpcionLineaBase.noSe:
          return item.copyWith(
            ultimaVezKm: null,
            ultimaVezFecha: null,
          );
      }
    }).toList();

    final nuevoPlan = widget.plan.copyWith(items: itemsActualizados);
    await ref.read(repositoryProvider).savePlan(nuevoPlan);

    ref.invalidate(planProvider(widget.vehiculo.id));
    ref.invalidate(analiticaVehiculoProvider(widget.vehiculo.id));
    ref.invalidate(vehiculosProvider);

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Línea base de mantenimiento guardada')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Icon(Icons.tune, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Asistente de Línea Base',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Indica qué tan recientes están los servicios de tu vehículo para que los recordatorios sean exactos y no falsamente vencidos.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _itemsACancelar.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = _itemsACancelar[index];
                final config = _configs[item.id]!;

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.descripcion,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Chip(
                              label: Text('Cada ${formatearKm(item.intervaloKm)}'),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Lo hice hace poco'),
                              selected:
                                  config.opcion == _OpcionLineaBase.alDia,
                              onSelected: (val) {
                                if (val) {
                                  setState(() => config.opcion =
                                      _OpcionLineaBase.alDia);
                                }
                              },
                            ),
                            ChoiceChip(
                              label: const Text('Hace ~X km'),
                              selected:
                                  config.opcion == _OpcionLineaBase.haceKm,
                              onSelected: (val) {
                                if (val) {
                                  setState(() {
                                    config.opcion = _OpcionLineaBase.haceKm;
                                    config.kmAtras ??= 2000;
                                  });
                                }
                              },
                            ),
                            ChoiceChip(
                              label: const Text('No sé / Sin registro'),
                              selected: config.opcion == _OpcionLineaBase.noSe,
                              onSelected: (val) {
                                if (val) {
                                  setState(() => config.opcion =
                                      _OpcionLineaBase.noSe);
                                }
                              },
                            ),
                          ],
                        ),
                        if (config.opcion == _OpcionLineaBase.haceKm) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('¿Hace cuántos km aprox.? '),
                              SizedBox(
                                width: 110,
                                child: TextFormField(
                                  initialValue: config.kmAtras?.toString() ?? '2000',
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    suffixText: 'km',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (val) {
                                    config.kmAtras = int.tryParse(val) ?? 0;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guardar línea base'),
            ),
          ),
        ],
      ),
    );
  }
}

