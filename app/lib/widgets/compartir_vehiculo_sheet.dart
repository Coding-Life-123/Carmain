import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/snapshot_mecanico.dart';
import '../models/vehiculo.dart';
import '../providers/providers.dart';
import '../providers/sesiones_providers.dart';
import '../utils/formato.dart';

/// Modal para compartir la ficha técnica y plan de mantenimiento del vehículo
/// con el mecánico o taller mediante enlace web o código QR.
class CompartirVehiculoSheet extends ConsumerStatefulWidget {
  final Vehiculo vehiculo;

  const CompartirVehiculoSheet({super.key, required this.vehiculo});

  static Future<void> mostrar(BuildContext context, Vehiculo vehiculo) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CompartirVehiculoSheet(vehiculo: vehiculo),
    );
  }

  @override
  ConsumerState<CompartirVehiculoSheet> createState() =>
      _CompartirVehiculoSheetState();
}

class _CompartirVehiculoSheetState extends ConsumerState<CompartirVehiculoSheet> {
  Duration _duracion = const Duration(hours: 24);
  bool _incluirVin = false;
  bool _incluirNotas = false;
  bool _incluirHistorial = true;

  bool _generando = false;
  String? _error;
  ({String codigo, String? tokenLargo, DateTime expiraEn})? _sesionGenerada;

  String _construirUrl(String base, String codigo, String? tokenLargo) {
    final token = tokenLargo != null && tokenLargo.isNotEmpty ? tokenLargo : codigo;
    return '$base/m?s=$token';
  }

  Future<void> _generarEnlace() async {
    setState(() {
      _generando = true;
      _error = null;
    });

    try {
      final plan = await ref.read(planProvider(widget.vehiculo.id).future);
      final registros =
          await ref.read(registrosProvider(widget.vehiculo.id).future);

      final snapshot = SnapshotMecanico.generar(
        vehiculo: widget.vehiculo,
        plan: plan,
        registros: registros,
        incluirVin: _incluirVin,
        incluirNotasUso: _incluirNotas,
        incluirHistorial: _incluirHistorial,
      );

      final api = ref.read(apiClientProvider);
      final res = await api.crearSesionDetallada(
        vehiculoId: widget.vehiculo.id,
        duracion: _duracion,
        snapshot: snapshot,
        deviceId: 'app-dueno',
      );

      final repo = ref.read(repositoryProvider);
      await repo.saveSesionMecanico(
        codigo: res.codigo,
        tokenLargo: res.tokenLargo,
        vehiculoId: widget.vehiculo.id,
        duenoDeviceId: 'app-dueno',
        expiresAt: res.expiraEn,
      );

      ref.invalidate(sesionesActivasProvider(widget.vehiculo.id));

      if (mounted) {
        setState(() {
          _sesionGenerada = res;
          _generando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo conectar con el servidor: $e';
          _generando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final serverUrl = ref.watch(servidorUrlProvider);
    final sesionesAsync = ref.watch(sesionesActivasProvider(widget.vehiculo.id));

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Row(
              children: [
                Icon(Icons.share_outlined, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Compartir con taller',
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
            const SizedBox(height: 6),
            Text(
              'El mecánico abrirá la ficha técnica sin instalar nada y te enviará su propuesta de trabajo.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            if (_sesionGenerada != null) ...[
              _buildResultadoSesion(context, serverUrl, _sesionGenerada!),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
            ] else ...[
              _buildConfiguracionPrivacidad(context),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: cs.error, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              FilledButton.icon(
                onPressed: _generando ? null : _generarEnlace,
                icon: _generando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_rounded),
                label: Text(
                  _generando ? 'Generando...' : 'Generar enlace y código QR',
                ),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
            ],

            // Lista de sesiones activas
            Text(
              'Sesiones activas',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            sesionesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Text('Error cargando sesiones: $err'),
              data: (sesiones) {
                if (sesiones.isEmpty) {
                  return Text(
                    'No hay sesiones activas para este vehículo.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final s in sesiones)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            'Código: ${s.id}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            'Vence: ${formatearFecha(s.expiresAt)} ${s.expiresAt.hour.toString().padLeft(2, '0')}:${s.expiresAt.minute.toString().padLeft(2, '0')}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          trailing: TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: cs.error),
                            icon: const Icon(Icons.block, size: 16),
                            label: const Text('Revocar'),
                            onPressed: () async {
                              await ref.read(apiClientProvider).revocarSesion(s.id);
                              await ref.read(repositoryProvider).revocarSesionMecanico(s.id);
                              ref.invalidate(sesionesActivasProvider(widget.vehiculo.id));
                            },
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildConfiguracionPrivacidad(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Duración del enlace',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SegmentedButton<Duration>(
          segments: const [
            ButtonSegment(
              value: Duration(hours: 1),
              label: Text('1 hora'),
            ),
            ButtonSegment(
              value: Duration(hours: 24),
              label: Text('24 horas'),
            ),
            ButtonSegment(
              value: Duration(days: 7),
              label: Text('7 días'),
            ),
          ],
          selected: {_duracion},
          onSelectionChanged: (set) {
            setState(() => _duracion = set.first);
          },
        ),
        const SizedBox(height: 18),
        Text(
          'Privacidad y datos',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Incluir historial previo'),
          subtitle: const Text('Permite al mecánico ver fechas y mantenimientos anteriores'),
          value: _incluirHistorial,
          onChanged: (v) => setState(() => _incluirHistorial = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Incluir VIN / Número de chasis'),
          subtitle: const Text('Útil para compra de repuestos en concesionario'),
          value: _incluirVin,
          onChanged: (v) => setState(() => _incluirVin = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Incluir notas de uso'),
          value: _incluirNotas,
          onChanged: (v) => setState(() => _incluirNotas = v),
        ),
      ],
    );
  }

  Widget _buildResultadoSesion(
    BuildContext context,
    String baseUrl,
    ({String codigo, String? tokenLargo, DateTime expiraEn}) sesion,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final url = _construirUrl(baseUrl, sesion.codigo, sesion.tokenLargo);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: url,
                version: QrVersions.auto,
                size: 170.0,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Código corto para el mecánico',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                sesion.codigo,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  fontFamily: 'monospace',
                  color: cs.primary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 20),
                tooltip: 'Copiar código',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: sesion.codigo));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Código copiado al portapapeles')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    final texto =
                        '¡Hola! Te comparto la ficha técnica y el plan de mantenimiento de mi ${widget.vehiculo.nombreCompleto}:\n\n$url\n\nCódigo de acceso: ${sesion.codigo}';
                    Share.share(texto);
                  },
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Enviar WhatsApp'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                icon: const Icon(Icons.link),
                tooltip: 'Copiar enlace completo',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enlace copiado al portapapeles')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

