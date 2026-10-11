import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/vehiculo_repository.dart';
import '../../models/plan_mantenimiento.dart';
import '../../models/registro_mantenimiento.dart';
import '../../models/vehiculo.dart';
import '../../providers/providers.dart';

/// Pantalla para registrar un mantenimiento realizado sobre un vehículo.
///
/// Recibe el [vehiculoId] y permite marcar qué ítems del plan se realizaron,
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

  // ─────────────────────────── Acciones ───────────────────────────

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
          content: Text('Selecciona al menos un ítem realizado.'),
        ),
      );
      return;
    }

    final plan = ref.read(planProvider(widget.vehiculoId)).value;
    if (plan == null) return;

    setState(() => _saving = true);

    final kilometraje =
        int.tryParse(_kilometrajeController.text.trim()) ?? 0;
    final costo = double.tryParse(
      _costoController.text.trim().replaceAll(',', '.'),
    );
    final taller = _tallerController.text.trim();
    final notas = _notasController.text.trim();

    final itemsRealizados = plan.items
        .where((i) => _selectedItemIds.contains(i.id))
        .map((i) => ItemRealizado(
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

    await ref.read(repositoryProvider).saveRegistro(registro);

    // Invalidar providers para refrescar los datos afectados.
    ref.invalidate(planProvider(widget.vehiculoId));
    ref.invalidate(registrosProvider(widget.vehiculoId));
    ref.invalidate(vehiculosProvider);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mantenimiento registrado')),
    );
    Navigator.of(context).pop();
  }

  // ─────────────────────────── Build ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(planProvider(widget.vehiculoId));
    final vehiculoAsync = ref.watch(vehiculoProvider(widget.vehiculoId));

    // Inicializar el kilometraje por defecto con el km actual del vehículo.
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
                  'Crea el vehículo primero para generar el plan.',
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
                  'El plan no tiene ítems de mantenimiento.',
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
          // ── Fecha ──
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
                    '${_fecha.day}/${_fecha.month}/${_fecha.year}',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const Icon(Icons.calendar_today),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Kilometraje ──
          TextFormField(
            controller: _kilometrajeController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Kilometraje *',
              border: OutlineInputBorder(),
              suffixText: 'km',
            ),
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return 'El kilometraje es obligatorio.';
              final km = int.tryParse(v);
              if (km == null) return 'Ingresa un número válido.';
              if (km < kmActual) {
                return 'Debe ser mayor o igual al kilometraje actual ($kmActual km).';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),

          // ── Ítems del plan ──
          Text(
            'Ítems realizados',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...plan.items.map((item) {
            final selected = _selectedItemIds.contains(item.id);
            return CheckboxListTile(
              value: selected,
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
            );
          }),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),

          // ── Costo (opcional) ──
          TextFormField(
            controller: _costoController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Costo (opcional)',
              border: OutlineInputBorder(),
              prefixText: '\$ ',
            ),
          ),
          const SizedBox(height: 16),

          // ── Taller (opcional) ──
          TextFormField(
            controller: _tallerController,
            decoration: const InputDecoration(
              labelText: 'Taller (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // ── Notas (opcional) ──
          TextFormField(
            controller: _notasController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notas (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),

          // ── Botón Guardar ──
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
