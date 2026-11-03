import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/vehiculo.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import '../../utils/formato.dart';
import '../../widgets/actualizar_km_dialog.dart';
import '../../widgets/eliminar_vehiculo_dialog.dart';
import '../../widgets/estado_plan.dart';
import '../../widgets/vehiculo_avatar.dart';
import '../crear_vehiculo/crear_vehiculo_screen.dart';
import '../detalle_vehiculo/detalle_vehiculo_screen.dart';

/// Pantalla principal de CarMain.
///
/// Muestra la lista de vehículos del usuario con su estado básico,
/// un FAB para crear vehículos nuevos y los estados de carga, error
/// y vacío correspondientes.
enum FiltroEstadoDashboard { todos, pendientes, alDia }

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _busquedaController = TextEditingController();
  FiltroEstadoDashboard _filtroEstado = FiltroEstadoDashboard.todos;

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vehiculosAsync = ref.watch(vehiculosProvider);
    // Probe de conexión con el backend: arranca al abrir la app y al
    // tocar el icono se re-prueba.
    final conexionAsync = ref.watch(conexionServidorProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_car_rounded, color: colorScheme.secondary),
            const SizedBox(width: 10),
            const Text('CarMain'),
          ],
        ),
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
                        ? colorScheme.tertiary // verde racing del tema
                        : colorScheme.error,
                  ),
            tooltip: conexionAsync.value == true
                ? 'Servidor conectado'
                : 'Sin conexión con el servidor',
            onPressed: () => ref.invalidate(conexionServidorProvider),
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

          // Resumen de mantenimientos para ordenar y filtrar por urgencia.
          final resumenes = <String, ResumenPlan>{
            for (final v in vehiculos)
              v.id: ResumenPlan.de(
                ref.watch(planProvider(v.id)).value,
                v.kilometrajeActual,
                v.tipoUso,
              ),
          };
          final orden = {
            for (var i = 0; i < vehiculos.length; i++) vehiculos[i].id: i,
          };
          vehiculos = [...vehiculos]..sort((a, b) {
              final c = resumenes[a.id]!.peor.index.compareTo(resumenes[b.id]!.peor.index);
              return c != 0 ? c : orden[a.id]!.compareTo(orden[b.id]!);
            });

          final totalPendientes = vehiculos
              .where((v) =>
                  (resumenes[v.id]?.vencidos ?? 0) > 0 ||
                  (resumenes[v.id]?.proximos ?? 0) > 0)
              .length;
          final totalAlDia = vehiculos.length - totalPendientes;

          final query = _busquedaController.text.trim().toLowerCase();
          final filtrados = vehiculos.where((v) {
            if (query.isNotEmpty) {
              final textoVehiculo =
                  '${v.marca} ${v.modelo} ${v.anio} ${v.placa ?? ''} ${v.vin ?? ''} ${v.trim ?? ''}'
                      .toLowerCase();
              if (!textoVehiculo.contains(query)) {
                return false;
              }
            }

            final r = resumenes[v.id];
            final tienePendientes = (r?.vencidos ?? 0) > 0 || (r?.proximos ?? 0) > 0;

            if (_filtroEstado == FiltroEstadoDashboard.pendientes) {
              return tienePendientes;
            } else if (_filtroEstado == FiltroEstadoDashboard.alDia) {
              return !tienePendientes;
            }

            return true;
          }).toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(vehiculosProvider),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Campo de búsqueda en vivo
                        TextField(
                          controller: _busquedaController,
                          decoration: InputDecoration(
                            hintText: 'Buscar marca, modelo, placa, año...',
                            hintStyle: TextStyle(
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                              fontSize: 14,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: colorScheme.primary,
                            ),
                            suffixIcon: _busquedaController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _busquedaController.clear();
                                      });
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: colorScheme.primary,
                                width: 1.5,
                              ),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                        // Chips de filtrado rápido
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              FilterChip(
                                label: Text('Todos (${vehiculos.length})'),
                                selected: _filtroEstado == FiltroEstadoDashboard.todos,
                                onSelected: (_) => setState(() =>
                                    _filtroEstado = FiltroEstadoDashboard.todos),
                              ),
                              const SizedBox(width: 8),
                              FilterChip(
                                label: Text('Con pendientes ($totalPendientes)'),
                                selected: _filtroEstado == FiltroEstadoDashboard.pendientes,
                                avatar: totalPendientes > 0
                                    ? Icon(Icons.warning_amber_rounded,
                                        size: 16, color: colorScheme.error)
                                    : null,
                                onSelected: (_) => setState(() =>
                                    _filtroEstado = FiltroEstadoDashboard.pendientes),
                              ),
                              const SizedBox(width: 8),
                              FilterChip(
                                label: Text('Al día ($totalAlDia)'),
                                selected: _filtroEstado == FiltroEstadoDashboard.alDia,
                                avatar: totalAlDia > 0
                                    ? Icon(Icons.check_circle_outline,
                                        size: 16, color: colorScheme.primary)
                                    : null,
                                onSelected: (_) => setState(() =>
                                    _filtroEstado = FiltroEstadoDashboard.alDia),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
                if (filtrados.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 56,
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'No se encontraron vehículos',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              query.isNotEmpty
                                  ? 'Ningún vehículo coincide con "$query".'
                                  : 'No hay vehículos con el filtro seleccionado.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _busquedaController.clear();
                                  _filtroEstado = FiltroEstadoDashboard.todos;
                                });
                              },
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Restablecer filtros'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                    sliver: SliverList.separated(
                      itemCount: filtrados.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final vehiculo = filtrados[index];
                        return _VehiculoCard(
                          vehiculo: vehiculo,
                          onTap: () => _navegarDetalle(context, vehiculo.id),
                          onEditar: () => _navegarEditar(context, vehiculo),
                          onActualizarKm: () =>
                              actualizarKilometraje(context, ref, vehiculo),
                          onEliminar: () async {
                            final eliminado = await confirmarYEliminarVehiculo(
                                context, ref, vehiculo);
                            if (eliminado && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '${vehiculo.nombreCompleto} eliminado'),
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
              ],
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

  String _mensajeError(Object error) {
    return 'No se pudieron cargar los vehículos.\n${error.toString()}';
  }
}

/// Diálogo de edición del servidor: URL + API key + probe de conexión.
/// Disponible para tests (@visibleForTesting). No expuesto en la UI del usuario.
@visibleForTesting
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
              labelText: 'API Key (avanzado)',
              hintText: 'déjala vacía — solo para desarrollo',
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
///
/// Es un [ConsumerWidget] porque, además de los datos del vehículo, muestra
/// el estado de su plan (vencidos / próximos / al día): es lo que el dueño
/// quiere saber de un vistazo, sin entrar al detalle.
class _VehiculoCard extends ConsumerWidget {
  const _VehiculoCard({
    required this.vehiculo,
    required this.onTap,
    required this.onEditar,
    required this.onActualizarKm,
    required this.onEliminar,
  });

  final Vehiculo vehiculo;
  final VoidCallback onTap;
  final VoidCallback onEditar;
  final VoidCallback onActualizarKm;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final planAsync = ref.watch(planProvider(vehiculo.id));
    final resumen = ResumenPlan.de(
      planAsync.value,
      vehiculo.kilometrajeActual,
      vehiculo.tipoUso,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header con gradiente ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primary,
                    colorScheme.primary.withValues(alpha: 0.85),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  // Logo oficial de la marca
                  Hero(
                    tag: 'vehiculo-icono-${vehiculo.id}',
                    child: VehiculoAvatar(
                      marca: vehiculo.marca,
                      size: 58,
                      backgroundColor:
                          colorScheme.onPrimary.withValues(alpha: 0.15),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        // Silueta del vehículo en el fondo detrás de la marca, modelo y año
                        Positioned.fill(
                          child: VehiculoSiluetaFondo(
                            vehiculo: vehiculo,
                            color: colorScheme.onPrimary,
                            opacity: 0.18,
                            alignment: Alignment.centerRight,
                            width: 140,
                            height: 70,
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${vehiculo.marca} ${vehiculo.modelo}',
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: colorScheme.onPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${vehiculo.anio}',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: colorScheme.onPrimary.withValues(alpha: 0.7),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Menú de acciones: editar / eliminar (CRUD).
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: colorScheme.onPrimary),
                    tooltip: 'Acciones',
                    onSelected: (accion) {
                      switch (accion) {
                        case 'editar':
                          onEditar();
                        case 'km':
                          onActualizarKm();
                        case 'eliminar':
                          onEliminar();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'km',
                        child: _ItemMenu(
                            icon: Icons.speed, label: 'Actualizar km'),
                      ),
                      PopupMenuItem(
                        value: 'editar',
                        child: _ItemMenu(
                            icon: Icons.edit_outlined, label: 'Editar'),
                      ),
                      PopupMenuItem(
                        value: 'eliminar',
                        child: _ItemMenu(
                          icon: Icons.delete_outline,
                          label: 'Eliminar',
                          color: colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Filete dorado: acento de marca entre cabecera y cuerpo.
            Container(height: 3, color: colorScheme.secondary),
            // ── Body: estado del plan + stats y swap en pills ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (resumen.total > 0) ...[
                    ResumenPlanPills(resumen: resumen),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _StatPill(
                        icon: Icons.speed,
                        label: formatearKm(vehiculo.kilometrajeActual),
                      ),
                      _StatPill(
                        icon: Icons.settings,
                        label: vehiculo.drivetrain.label,
                      ),
                      _StatPill(
                        icon: Icons.local_gas_station,
                        label: vehiculo.motor.codigo,
                      ),
                      if (vehiculo.tieneSwap) const _SwapChip(),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila icono + texto para las entradas del menú de acciones.
class _ItemMenu extends StatelessWidget {
  const _ItemMenu({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}

/// Pill compacto de una estadística del vehículo (km, tracción, motor).
class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip verde racing que indica que el vehículo tiene componentes swap —
/// una modificación de performance, no un error.
class _SwapChip extends StatelessWidget {
  const _SwapChip();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Vehículo con componentes modificados o swap',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.tertiary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz, size: 14, color: colorScheme.tertiary),
            const SizedBox(width: 4),
            Text(
              'Swap',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.tertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
              ),
              child: Icon(
                Icons.directions_car_rounded,
                size: 72,
                color: colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No tienes vehículos registrados',
              style: theme.textTheme.titleLarge,
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
