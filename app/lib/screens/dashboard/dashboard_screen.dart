import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/vehiculo.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import '../../widgets/eliminar_vehiculo_dialog.dart';
import '../crear_vehiculo/crear_vehiculo_screen.dart';
import '../detalle_vehiculo/detalle_vehiculo_screen.dart';

/// Pantalla principal de CarMain.
///
/// Muestra la lista de vehículos del usuario con su estado básico,
/// un FAB para crear vehículos nuevos y los estados de carga, error
/// y vacío correspondientes.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiculosAsync = ref.watch(vehiculosProvider);
    // Probe de conexión con el backend: arranca al abrir la app y al
    // tocar el icono se re-prueba.
    final conexionAsync = ref.watch(conexionServidorProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CarMain'),
        actions: [
          IconButton(
            icon: conexionAsync.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    conexionAsync.value == true
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    color: conexionAsync.value == true
                        ? Colors.green
                        : colorScheme.error,
                  ),
            tooltip: conexionAsync.value == true
                ? 'Servidor conectado'
                : 'Sin conexión con el servidor',
            onPressed: () => ref.invalidate(conexionServidorProvider),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configuración',
            onPressed: () => _mostrarAjustes(context),
          ),
        ],
      ),
      body: vehiculosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorState(
          message: _mensajeError(error),
          onReintentar: () => ref.invalidate(vehiculosProvider),
        ),
        data: (vehiculos) {
          if (vehiculos.isEmpty) {
            return _EmptyState(
              onCrear: () => _navegarCrearVehiculo(context),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(vehiculosProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              itemCount: vehiculos.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final vehiculo = vehiculos[index];
                return _VehiculoCard(
                  vehiculo: vehiculo,
                  onTap: () => _navegarDetalle(context, vehiculo.id),
                  onEditar: () => _navegarEditar(context, vehiculo),
                  onEliminar: () async {
                    final eliminado = await confirmarYEliminarVehiculo(
                        context, ref, vehiculo);
                    if (eliminado && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              Text('${vehiculo.nombreCompleto} eliminado'),
                        ),
                      );
                    }
                  },
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navegarCrearVehiculo(context),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo vehículo'),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
    );
  }

  void _navegarCrearVehiculo(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CrearVehiculoScreen()),
    );
  }

  void _navegarEditar(BuildContext context, Vehiculo vehiculo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CrearVehiculoScreen(vehiculoExistente: vehiculo),
      ),
    );
  }

  void _navegarDetalle(BuildContext context, String id) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetalleVehiculoScreen(vehiculoId: id),
      ),
    );
  }

  void _mostrarAjustes(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return const _AjustesSheet();
      },
    );
  }

  String _mensajeError(Object error) {
    return 'No se pudieron cargar los vehículos.\n${error.toString()}';
  }
}

/// Panel de ajustes: muestra la URL del backend configurada y permite
/// editarla (se persiste con shared_preferences).
class _AjustesSheet extends ConsumerWidget {
  const _AjustesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(servidorUrlProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_car, color: Color(0xFFD32F2F)),
                const SizedBox(width: 10),
                Text(
                  'CarMain v1.0.0',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Servidor Backend'),
              subtitle: Text(url),
              trailing: const Icon(Icons.edit_outlined, size: 20),
              onTap: () => _editarUrl(context, ref),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.storage_outlined),
              title: Text('Base de datos'),
              subtitle: Text('Local-first (Drift / SQLite)'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _editarUrl(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => EditarServidorDialog(
        initialUrl: ref.read(servidorUrlProvider),
        initialApiKey: ref.read(servidorApiKeyProvider),
      ),
    );
  }
}

/// Diálogo de edición del servidor: URL + API key + probe de conexión.
/// Interno de la pantalla de ajustes (público para poder testearlo).
///
/// Es un StatefulWidget (no un StatefulBuilder suelto con dispose manual
/// en el futuro del showDialog) para que los controllers vivan exactamente
/// lo que vive el widget: el dispose lo llama el framework cuando la ruta
/// se desmonta de verdad, tras la animación de salida. El probe en vuelo
/// verifica `mounted` antes de tocar el estado — cerrar el diálogo con la
/// prueba pendiente ya no revienta (regresión real en el teléfono).
class EditarServidorDialog extends ConsumerStatefulWidget {
  const EditarServidorDialog({
    super.key,
    required this.initialUrl,
    required this.initialApiKey,
    this.probeOverride,
  });

  final String initialUrl;
  final String initialApiKey;

  /// Seam de tests: sustituye la llamada real a ApiClient.probarConexion.
  /// El binding de widget tests mockea todo HttpClient (responde 400 sin
  /// tocar red), así que la carrera "cerrar con el probe en vuelo" solo
  /// se puede producir inyectando un futuro controlado.
  final Future<Duration> Function()? probeOverride;

  @override
  ConsumerState<EditarServidorDialog> createState() =>
      _EditarServidorDialogState();
}

class _EditarServidorDialogState extends ConsumerState<EditarServidorDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _keyController;
  String? _error;
  _EstadoProbe _probe = _EstadoProbe.inactivo;
  int? _probeMs;
  String? _probeError;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl);
    _keyController = TextEditingController(text: widget.initialApiKey);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _probar() async {
    final url = _urlController.text.trim();
    final err = _validarUrl(url);
    if (err != null) {
      if (!mounted) return;
      setState(() {
        _error = err;
        _probe = _EstadoProbe.inactivo;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _probe = _EstadoProbe.probando;
      _probeError = null;
    });
    final probe = widget.probeOverride ??
        () => ApiClient.probarConexion(
              baseUrl: ServidorUrlNotifier.normalizar(url),
              apiKey: _keyController.text.trim(),
            );
    try {
      final latencia = await probe();
      if (!mounted) return; // el diálogo cerró mientras probaba
      setState(() {
        _probe = _EstadoProbe.ok;
        _probeMs = latencia.inMilliseconds;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _probe = _EstadoProbe.error;
        _probeError = _mensajeProbe(e);
      });
    }
  }

  Future<void> _guardar() async {
    final url = _urlController.text.trim();
    final err = _validarUrl(url);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    await ref.read(servidorUrlProvider.notifier).setUrl(url);
    await ref
        .read(servidorApiKeyProvider.notifier)
        .setApiKey(_keyController.text);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Servidor Backend'),
      // Con el teclado abierto el contenido puede exceder la altura
      // disponible — scrollable evita el overflow.
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _urlController,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: 'http://192.168.1.50:8080',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyController,
            decoration: const InputDecoration(
              labelText: 'API Key (opcional)',
              hintText: 'solo si el servidor la exige',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          // Prueba contra /api/health (público): valida URL/TLS/
          // alcanzabilidad con lo escrito, antes de Guardar.
          OutlinedButton.icon(
            onPressed: _probe == _EstadoProbe.probando ? null : _probar,
            icon: _probe == _EstadoProbe.probando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering),
            label: Text(_probe == _EstadoProbe.probando
                ? 'Probando…'
                : 'Probar conexión'),
          ),
          if (_probe == _EstadoProbe.ok)
            Text(
              'Conectado — $_probeMs ms',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            )
          else if (_probe == _EstadoProbe.error)
            Text(
              _probeError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Emulador Android: http://10.0.2.2:8080\n'
            'Dispositivo físico: IP LAN de este PC\n'
            'Desde cualquier red: IP de Tailscale (http://100.x.y.z:8080)\n'
            'Producción (VPS): https://<subdominio>.duckdns.org',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardar,
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  /// Valida que la URL tenga esquema http/https y host. Retorna el mensaje
  /// de error o null si es válida.
  String? _validarUrl(String valor) {
    final uri = Uri.tryParse(valor);
    if (uri == null || uri.host.isEmpty) return 'URL inválida';
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Debe iniciar con http:// o https://';
    }
    return null;
  }

  /// Traduce un fallo del probe a un mensaje accionable.
  String _mensajeProbe(Object e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
          return 'Sin respuesta en 5 s (timeout)';
        case DioExceptionType.connectionError:
          return 'No se pudo conectar — revisa la URL o la red';
        case DioExceptionType.receiveTimeout:
          return 'El servidor tardó demasiado en responder';
        case DioExceptionType.badResponse:
          return 'El servidor respondió HTTP ${e.response?.statusCode}';
        default:
          return e.message ?? 'Error de conexión';
      }
    }
    return e.toString();
  }
}

/// Estado del botón "Probar conexión".
enum _EstadoProbe { inactivo, probando, ok, error }

/// Tarjeta individual de un vehículo.
class _VehiculoCard extends StatelessWidget {
  const _VehiculoCard({
    required this.vehiculo,
    required this.onTap,
    required this.onEditar,
    required this.onEliminar,
  });

  final Vehiculo vehiculo;
  final VoidCallback onTap;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Icono de vehículo.
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.directions_car_rounded,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              // Información principal.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehiculo.nombreCompleto,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatearKm(vehiculo.kilometrajeActual)} · '
                      '${vehiculo.drivetrain.label}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Chip de swap si aplica.
              if (vehiculo.tieneSwap) ...[
                const SizedBox(width: 8),
                _SwapChip(),
              ],
              // Menú de acciones: editar / eliminar (CRUD).
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'Acciones',
                onSelected: (accion) {
                  switch (accion) {
                    case 'editar':
                      onEditar();
                    case 'eliminar':
                      onEliminar();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'editar', child: Text('Editar')),
                  PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Formatea un kilometraje con separador de miles (ej: 125000 -> "125,000 km").
  String _formatearKm(int km) {
    final grupos = <String>[];
    var restante = km.abs();
    if (restante == 0) return '0 km';
    while (restante > 0) {
      grupos.insert(0, (restante % 1000).toString().padLeft(3, '0'));
      restante ~/= 1000;
    }
    // El primer grupo no lleva ceros a la izquierda.
    grupos[0] = int.parse(grupos[0]).toString();
    final signo = km < 0 ? '-' : '';
    return '$signo${grupos.join(',')} km';
  }
}

/// Chip rojo que indica que el vehículo tiene componentes swap.
class _SwapChip extends StatelessWidget {
  const _SwapChip();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Swap',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onErrorContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Estado vacío: no hay vehículos registrados.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCrear});

  final VoidCallback onCrear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.directions_car_rounded,
              size: 96,
              color: colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'No tienes vehículos registrados',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Agrega tu primer vehículo para empezar a llevar su mantenimiento.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCrear,
              icon: const Icon(Icons.add),
              label: const Text('Crear vehículo'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Estado de error con botón de reintentar.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onReintentar});

  final String message;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onReintentar,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
