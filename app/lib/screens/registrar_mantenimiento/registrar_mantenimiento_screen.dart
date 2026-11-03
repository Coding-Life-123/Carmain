import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/vehiculo_repository.dart';
import '../../models/plan_mantenimiento.dart';
import '../../models/registro_mantenimiento.dart';
import '../../models/vehiculo.dart';
import '../../providers/providers.dart';
import '../../utils/formato.dart';
import '../../widgets/estado_plan.dart';

/// Pantalla para registrar un mantenimiento realizado sobre un vehÃ­culo.
///
/// Recibe el [vehiculoId] y permite marcar quÃ© Ã­tems del plan se realizaron,
/// junto con fecha, kilometraje, costo, taller y notas opcionales.
class RegistrarMantenimientoScreen extends ConsumerStatefulWidget {
  final String vehiculoId;

  const RegistrarMantenimientoScreen({
    super.key,
    required this.vehiculoId,
  });

  @override
  ConsumerState<RegistrarMantenimientoScreen> createState() =>
      _RegistrarMantenimientoScreenState();
}

class _RegistrarMantenimientoScreenState
    extends ConsumerState<RegistrarMantenimientoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _kilometrajeController = TextEditingController();
  final _costoController = TextEditingController();
  final _tallerController = TextEditingController();
  final _notasController = TextEditingController();

  DateTime _fecha = DateTime.now();
  final Set<String> _selectedItemIds = {};
  bool _saving = false;
  bool _kmInitialized = false;

  @override
  void dispose() {
    _kilometrajeController.dispose();
    _costoController.dispose();
    _tallerController.dispose();
    _notasController.dispose();
    super.dispose();
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ Acciones â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _selectFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _fecha) {
      setState(() => _fecha = picked);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedItemIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona al menos un Ã­tem realizado.'),
        ),
      );
      return;
    }

    final plan = ref.read(planProvider(widget.vehiculoId)).value;
    if (plan == null) return;

    setState(() => _saving = true);

    final kilometraje =
        int.tryParse(_kilometrajeController.text.trim()) ?? 0;
    final costo = parsearCop(_costoController.text);
    final taller = _tallerController.text.trim();
    final notas = _notasController.text.trim();

    final itemsRealizados = plan.items
        .where((i) => _selectedItemIds.contains(i.id))
        .map((i) => ItemRealizado(
              itemId: i.id,
              categoria: i.categoria,
              descripcion: i.descripcion,
              componenteAplica: i.componenteAplica,
            ))
        .toList();

    final registro = RegistroMantenimiento(
      id: VehiculoRepository.newId(),
      vehiculoId: widget.vehiculoId,
      fecha: _fecha,
      kilometraje: kilometraje,
      itemsRealizados: itemsRealizados,
      costo: costo,
      taller: taller.isEmpty ? null : taller,
      notas: notas.isEmpty ? null : notas,
      updatedAt: DateTime.now(),
    );

    try {
      await ref.read(repositoryProvider).saveRegistro(registro);
    } catch (e) {
      // Sin esto el botÃ³n quedaba bloqueado en "guardando" para siempre.
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
      return;
    }

    // Invalidar providers para refrescar los datos afectados.
    ref.invalidate(vehiculoProvider(widget.vehiculoId));
    ref.invalidate(planProvider(widget.vehiculoId));
    ref.invalidate(registrosProvider(widget.vehiculoId));
    ref.invalidate(kmPorDiaProvider(widget.vehiculoId));
    ref.invalidate(analiticaVehiculoProvider(widget.vehiculoId));
    ref.invalidate(vehiculosProvider);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mantenimiento registrado')),
    );
    Navigator.of(context).pop();
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Ãtems vencidos primero, luego prÃ³ximos y al final los al dÃ­a, para que
  /// lo mÃ¡s probable de registrar quede arriba.
  List<ItemMantenimiento> _ordenarPorUrgencia(
    List<ItemMantenimiento> items,
    Vehiculo? vehiculo,
  ) {
    if (vehiculo == null) return items;
    final km = vehiculo.kilometrajeActual;
    return [...items]..sort((a, b) => a
        .estado(km, vehiculo.tipoUso)
        .index
        .compareTo(b.estado(km, vehiculo.tipoUso).index));
  }

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(planProvider(widget.vehiculoId));
    final vehiculoAsync = ref.watch(vehiculoProvider(widget.vehiculoId));

    // Inicializar el kilometraje por defecto con el km actual del vehÃ­culo.
    final vehiculo = vehiculoAsync.value;
    if (vehiculo != null && !_kmInitialized) {
      _kilometrajeController.text = vehiculo.kilometrajeActual.toString();
      _kmInitialized = true;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Registrar Mantenimiento')),
      body: planAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error al cargar el plan: $error')),
        data: (plan) {
          if (plan == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No hay plan de mantenimiento. '
                  'Crea el vehÃ­culo primero para generar el plan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
              ),
            );
          }
          if (plan.items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'El plan no tiene Ã­tems de mantenimiento.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
              ),
            );
          }
          return _buildForm(context, plan, vehiculo);
        },
      ),
    );
  }

  Widget _buildForm(
    BuildContext context,
    PlanMantenimiento plan,
    Vehiculo? vehiculo,
  ) {
    final kmActual = vehiculo?.kilometrajeActual ?? 0;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // â”€â”€ Fecha â”€â”€
          InkWell(
            onTap: _selectFecha,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Fecha',
                border: OutlineInputBorder(),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatearFecha(_fecha),
                    style: const TextStyle(fontSize: 16),
                  ),
                  const Icon(Icons.calendar_today),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── Kilometraje ───
          TextFormField(
            controller: _kilometrajeController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Kilometraje *',
              border: const OutlineInputBorder(),
              suffixText: 'km',
              helperText: (_kilometrajeController.text.isNotEmpty &&
                      (int.tryParse(_kilometrajeController.text) ?? 0) <
                          kmActual)
                  ? 'Servicio histórico anterior al odómetro actual ($kmActual km)'
                  : null,
            ),
            onChanged: (_) => setState(() {}),
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return 'El kilometraje es obligatorio.';
              final km = int.tryParse(v);
              if (km == null) return 'Ingresa un número válido.';
              if (km < 0) return 'El kilometraje no puede ser negativo.';
              return null;
            },
          ),
          const SizedBox(height: 24),

          // â”€â”€ Ãtems del plan (mÃ¡s urgentes primero) â”€â”€
          Text(
            'Ãtems realizados',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _selectedItemIds.isEmpty
                ? 'Marca lo que se hizo en este servicio.'
                : '${_selectedItemIds.length} seleccionado(s)',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          ..._ordenarPorUrgencia(plan.items, vehiculo).map((item) {
            final selected = _selectedItemIds.contains(item.id);
            final estado = vehiculo == null
                ? null
                : item.estado(kmActual, vehiculo.tipoUso);
            return CheckboxListTile(
              value: selected,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedItemIds.add(item.id);
                  } else {
                    _selectedItemIds.remove(item.id);
                  }
                });
              },
              title: Text(item.descripcion),
              subtitle: Text(item.categoria.label),
              secondary: estado == null || estado == EstadoItem.ok
                  ? null
                  : EstadoPill(estado: estado, dense: true),
            );
          }),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),

          // ─── Costo (opcional) ───
          TextFormField(
            controller: _costoController,
            keyboardType: TextInputType.number,
            inputFormatters: [CopInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'Costo COP (opcional)',
              hintText: 'ej. 85.000',
              border: OutlineInputBorder(),
              prefixText: r'$ ',
            ),
            validator: (v) {
              if (v != null && v.trim().isNotEmpty && parsearCop(v) == null) {
                return 'Ingresa un valor válido en COP';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // â”€â”€ Taller (opcional) â”€â”€
          TextFormField(
            controller: _tallerController,
            decoration: const InputDecoration(
              labelText: 'Taller (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // â”€â”€ Notas (opcional) â”€â”€
          TextFormField(
            controller: _notasController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notas (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),

          // â”€â”€ BotÃ³n Guardar â”€â”€
          FilledButton(
            onPressed: _saving ? null : _guardar,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
