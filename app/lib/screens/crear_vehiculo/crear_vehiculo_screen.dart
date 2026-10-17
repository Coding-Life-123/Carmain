import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/componente.dart';
import '../../models/enums.dart';
import '../../models/vehiculo.dart';
import '../../providers/providers.dart';

/// Pantalla "Crear Vehículo".
///
/// Formulario guiado para dar de alta un vehículo compuesto por chasis,
/// motor y transmisión. Al guardar, se genera un UUID, se persiste localmente
/// y se solicita el plan de mantenimiento al backend mediante
/// [crearVehiculoProvider].
class CrearVehiculoScreen extends ConsumerStatefulWidget {
  const CrearVehiculoScreen({super.key});

  @override
  ConsumerState<CrearVehiculoScreen> createState() =>
      _CrearVehiculoScreenState();
}

class _CrearVehiculoScreenState extends ConsumerState<CrearVehiculoScreen> {
  final _formKey = GlobalKey<FormState>();

  // ─────────────────────────── Controllers ───────────────────────────
  final _marcaController = TextEditingController();
  final _modeloController = TextEditingController();
  final _anioController = TextEditingController();
  final _trimController = TextEditingController();
  final _vinController = TextEditingController();

  final _motorCodigoController = TextEditingController();
  final _cilindradaController = TextEditingController();
  final _cilindrosController = TextEditingController();
  final _aspiracionController = TextEditingController();

  final _transmisionCodigoController = TextEditingController();
  final _marchasController = TextEditingController();

  final _kilometrajeController = TextEditingController();

  // ─────────────────────────── Estado de selección ───────────────────────────
  Drivetrain _drivetrain = Drivetrain.fwd;
  TipoCombustible _tipoCombustible = TipoCombustible.gasolina;
  TipoTransmision _tipoTransmision = TipoTransmision.manual;
  bool _usoSevero = false;

  bool _guardando = false;

  @override
  void dispose() {
    _marcaController.dispose();
    _modeloController.dispose();
    _anioController.dispose();
    _trimController.dispose();
    _vinController.dispose();
    _motorCodigoController.dispose();
    _cilindradaController.dispose();
    _cilindrosController.dispose();
    _aspiracionController.dispose();
    _transmisionCodigoController.dispose();
    _marchasController.dispose();
    _kilometrajeController.dispose();
    super.dispose();
  }

  // ─────────────────────────── Guardado ───────────────────────────

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    final vehiculo = Vehiculo(
      id: const Uuid().v4(),
      propietarioId: 'local',
      marca: _marcaController.text.trim(),
      modelo: _modeloController.text.trim(),
      anio: int.parse(_anioController.text.trim()),
      trim: _trimController.text.trim().isEmpty
          ? null
          : _trimController.text.trim(),
      vin: _vinController.text.trim().isEmpty
          ? null
          : _vinController.text.trim(),
      drivetrain: _drivetrain,
      motor: Motor(
        codigo: _motorCodigoController.text.trim(),
        tipoCombustible: _tipoCombustible,
        cilindrada: _cilindradaController.text.trim().isEmpty
            ? null
            : double.tryParse(_cilindradaController.text.trim()),
        cilindros: _cilindrosController.text.trim().isEmpty
            ? null
            : int.tryParse(_cilindrosController.text.trim()),
        aspiracion: _aspiracionController.text.trim().isEmpty
            ? null
            : _aspiracionController.text.trim(),
      ),
      transmision: Transmision(
        codigo: _transmisionCodigoController.text.trim(),
        tipo: _tipoTransmision,
        marchas: _marchasController.text.trim().isEmpty
            ? null
            : int.tryParse(_marchasController.text.trim()),
      ),
      kilometrajeActual: _kilometrajeController.text.trim().isEmpty
          ? 0
          : int.tryParse(_kilometrajeController.text.trim()) ?? 0,
      tipoUso: _usoSevero ? TipoUso.severo : TipoUso.normal,
    );

    try {
      await ref.read(crearVehiculoProvider(vehiculo).future);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehículo creado')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al crear el vehículo: $e')),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ─────────────────────────── UI ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Crear Vehículo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Identidad del chasis ───
              _SectionTitle('Identidad del chasis'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _marcaController,
                decoration: const InputDecoration(
                  labelText: 'Marca *',
                  hintText: 'ej. Toyota',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _modeloController,
                decoration: const InputDecoration(
                  labelText: 'Modelo *',
                  hintText: 'ej. Supra',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _anioController,
                decoration: const InputDecoration(
                  labelText: 'Año *',
                  hintText: 'ej. 1995',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Obligatorio';
                  final anio = int.tryParse(v.trim());
                  if (anio == null) return 'Año inválido';
                  if (anio < 1900 || anio > 2100) return 'Año fuera de rango';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _trimController,
                decoration: const InputDecoration(
                  labelText: 'Trim (opcional)',
                  hintText: 'ej. GR',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _vinController,
                decoration: const InputDecoration(
                  labelText: 'VIN (opcional)',
                  hintText: '17 caracteres',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
              ),

              const SizedBox(height: 28),

              // ─── Drivetrain ───
              _SectionTitle('Tracción'),
              const SizedBox(height: 8),
              Text(
                'Selecciona el tipo de tracción',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: Drivetrain.values.map((dt) {
                  final selected = dt == _drivetrain;
                  return ChoiceChip(
                    label: Text(dt.label),
                    selected: selected,
                    onSelected: (_) => setState(() => _drivetrain = dt),
                  );
                }).toList(),
              ),

              const SizedBox(height: 28),

              // ─── Motor ───
              _SectionTitle('Motor'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _motorCodigoController,
                decoration: const InputDecoration(
                  labelText: 'Código *',
                  hintText: 'ej. 2JZ-GTE',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<TipoCombustible>(
                value: _tipoCombustible,
                decoration: const InputDecoration(
                  labelText: 'Tipo de combustible',
                  border: OutlineInputBorder(),
                ),
                items: TipoCombustible.values
                    .map((tc) => DropdownMenuItem(
                          value: tc,
                          child: Text(tc.label),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _tipoCombustible = v);
                },
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cilindradaController,
                      decoration: const InputDecoration(
                        labelText: 'Cilindrada (L, opcional)',
                        hintText: 'ej. 3.0',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        if (double.tryParse(v.trim()) == null) {
                          return 'Inválido';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _cilindrosController,
                      decoration: const InputDecoration(
                        labelText: 'Cilindros (opcional)',
                        hintText: 'ej. 6',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        if (int.tryParse(v.trim()) == null) {
                          return 'Inválido';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _aspiracionController,
                decoration: const InputDecoration(
                  labelText: 'Aspiración (opcional)',
                  hintText: 'NA / Turbo / Twin-Turbo / Supercharger',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 28),

              // ─── Transmisión ───
              _SectionTitle('Transmisión'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _transmisionCodigoController,
                decoration: const InputDecoration(
                  labelText: 'Código *',
                  hintText: 'ej. R154',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<TipoTransmision>(
                value: _tipoTransmision,
                decoration: const InputDecoration(
                  labelText: 'Tipo',
                  border: OutlineInputBorder(),
                ),
                items: TipoTransmision.values
                    .map((tt) => DropdownMenuItem(
                          value: tt,
                          child: Text(tt.label),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _tipoTransmision = v);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _marchasController,
                decoration: const InputDecoration(
                  labelText: 'Marchas (opcional)',
                  hintText: 'ej. 6',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  if (int.tryParse(v.trim()) == null) return 'Inválido';
                  return null;
                },
              ),

              const SizedBox(height: 28),

              // ─── Kilometraje y uso ───
              _SectionTitle('Kilometraje y uso'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _kilometrajeController,
                decoration: const InputDecoration(
                  labelText: 'Kilometraje actual',
                  hintText: 'ej. 120000',
                  border: OutlineInputBorder(),
                  suffixText: 'km',
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  if (int.tryParse(v.trim()) == null) return 'Inválido';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _usoSevero,
                onChanged: (v) => setState(() => _usoSevero = v ?? false),
                title: const Text('Uso severo'),
                subtitle: const Text(
                  'Ciudad, remolque, polvo — acorta los intervalos',
                ),
                contentPadding: EdgeInsets.zero,
              ),

              const SizedBox(height: 32),

              // ─── Botón guardar ───
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(_guardando ? 'Guardando…' : 'Guardar'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Subtítulo de sección con estilo consistente.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.primary,
      ),
    );
  }
}
