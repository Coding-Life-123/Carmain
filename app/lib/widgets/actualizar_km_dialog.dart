import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vehiculo.dart';
import '../providers/providers.dart';
import '../utils/formato.dart';

/// Pide el kilometraje actual de [vehiculo] y lo guarda.
///
/// Es la acciÃ³n rÃ¡pida mÃ¡s frecuente: el kilometraje dispara todos los
/// estados del plan (vencido / prÃ³ximo / al dÃ­a), asÃ­ que se puede invocar
/// tanto desde el dashboard como desde el detalle. Devuelve `true` si se
/// guardÃ³ un valor nuevo.
Future<bool> actualizarKilometraje(
  BuildContext context,
  WidgetRef ref,
  Vehiculo vehiculo,
) async {
  final nuevoKm = await showDialog<int>(
    context: context,
    builder: (_) => _ActualizarKmDialog(vehiculo: vehiculo),
  );
  if (nuevoKm == null || nuevoKm == vehiculo.kilometrajeActual) return false;

  await ref.read(repositoryProvider).updateKilometraje(vehiculo.id, nuevoKm);
  ref.invalidate(vehiculosProvider);
  ref.invalidate(vehiculoProvider(vehiculo.id));
  ref.invalidate(planProvider(vehiculo.id));
  ref.invalidate(kmPorDiaProvider(vehiculo.id));
  ref.invalidate(analiticaVehiculoProvider(vehiculo.id));

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Kilometraje actualizado: ${formatearKm(nuevoKm)}')),
    );
  }
  return true;
}

/// DiÃ¡logo con su propio State para que el controller viva lo mismo que la
/// ruta (mismo patrÃ³n que `EditarServidorDialog`).
class _ActualizarKmDialog extends StatefulWidget {
  const _ActualizarKmDialog({required this.vehiculo});

  final Vehiculo vehiculo;

  @override
  State<_ActualizarKmDialog> createState() => _ActualizarKmDialogState();
}

class _ActualizarKmDialogState extends State<_ActualizarKmDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.vehiculo.kilometrajeActual.toString(),
    );
    // Selecciona todo para sobrescribir directamente.
    _controller.selection =
        TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _guardar() {
    final km = int.tryParse(_controller.text.trim());
    final actual = widget.vehiculo.kilometrajeActual;
    if (km == null) {
      setState(() => _error = 'Ingresa un nÃºmero vÃ¡lido');
    } else if (km < actual) {
      setState(() => _error = 'No puede ser menor a ${formatearKm(actual)}');
    } else {
      Navigator.pop(context, km);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Actualizar kilometraje'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: widget.vehiculo.nombreCompleto,
          suffixText: 'km',
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _guardar(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardar,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

