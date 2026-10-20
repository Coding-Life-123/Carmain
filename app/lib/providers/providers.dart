import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/vehiculo_repository.dart';
import '../database/database.dart';
import '../models/enums.dart';
import '../models/motorizacion.dart';
import '../models/plan_mantenimiento.dart';
import '../models/registro_mantenimiento.dart';
import '../models/vehiculo.dart';
import '../services/api_client.dart';

// ─────────────────────────── Infraestructura ───────────────────────────

/// SharedPreferences, inicializados en `main()` antes de `runApp` y
/// sobre-escritos en el ProviderScope. Es **nullable**: si el plugin falla
/// en el dispositivo, la app arranca sin persistencia (ajustes solo en
/// memoria). En tests, sobre-escribir con
/// `SharedPreferences.setMockInitialValues`.
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) {
  return null;
});

/// URL del backend Go, persistida en el dispositivo.
///
/// Por defecto apunta a localhost (desarrollo con la app en desktop).
/// Para probar contra el servidor real:
/// - Emulador Android: `http://10.0.2.2:8080` (10.0.2.2 es el host desde el emulador)
/// - Dispositivo físico: la IP LAN del PC (ej. `http://192.168.1.50:8080`)
final servidorUrlProvider =
    NotifierProvider<ServidorUrlNotifier, String>(ServidorUrlNotifier.new);

class ServidorUrlNotifier extends Notifier<String> {
  static const _prefKey = 'servidor_url';
  static const urlPorDefecto = 'http://localhost:8080';

  @override
  String build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return normalizar(prefs?.getString(_prefKey) ?? urlPorDefecto);
  }

  /// Guarda la URL del backend y la persiste (si hay persistencia).
  Future<void> setUrl(String url) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final normalizada = normalizar(url);
    state = normalizada;
    if (prefs == null) return; // sin persistencia — queda solo en memoria
    await prefs.setString(_prefKey, normalizada);
  }

  /// Normaliza la URL a `scheme://host:puerto`:
  /// - esquema en minúsculas (el relay construye la URL del WebSocket con
  ///   `replaceFirst('http', 'ws')`, que es case-sensitive — 'HTTP://'
  ///   rompería el compartido con el mecánico),
  /// - sin path ('http://host:8080/api' produciría `/api/api/plan`),
  /// - puerto explícito: sin puerto se asume el default del sistema (8080
  ///   en http, 443 en https) — sin esto, 'http://host' moriría contra el
  ///   puerto 80.
  ///
  /// Si no parsea como URL http(s) se devuelve tal cual (sin slashes
  /// finales) — el diálogo de ajustes valida el esquema antes de llamar
  /// a setUrl. Es pública: el botón "Probar conexión" normaliza lo
  /// escrito antes de probarlo, sin esperar a Guardar.
  static String normalizar(String url) {
    final cruda = url.trim();
    final uri = Uri.tryParse(cruda);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final puerto =
          uri.hasPort ? uri.authority : '${uri.authority}:${uri.scheme == 'https' ? 443 : 8080}';
      return '${uri.scheme}://$puerto';
    }
    return cruda.replaceAll(RegExp(r'/+$'), '');
  }
}

/// API key del backend (header X-Api-Key), persistida en el dispositivo.
///
/// Vacía = el servidor no exige auth (modo LAN de desarrollo). En
/// producción (VPS) el servidor se levanta con API_KEY configurada y
/// solo acepta peticiones que la presenten.
final servidorApiKeyProvider =
    NotifierProvider<ServidorApiKeyNotifier, String>(ServidorApiKeyNotifier.new);

class ServidorApiKeyNotifier extends Notifier<String> {
  static const _prefKey = 'servidor_api_key';

  @override
  String build() =>
      ref.watch(sharedPreferencesProvider)?.getString(_prefKey) ?? '';

  /// Guarda la API key y la persiste. Vaciarla limpia la preferencia:
  /// sin key no se persiste nada (modo LAN).
  Future<void> setApiKey(String key) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final limpia = key.trim();
    state = limpia;
    if (prefs == null) return; // sin persistencia — queda solo en memoria
    if (limpia.isEmpty) {
      await prefs.remove(_prefKey);
    } else {
      await prefs.setString(_prefKey, limpia);
    }
  }
}

/// Base de datos local (singleton). Vive en el dispositivo del dueño.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Repositorio de vehículos (capa de acceso a datos).
final repositoryProvider = Provider<VehiculoRepository>((ref) {
  return VehiculoRepository(ref.watch(databaseProvider));
});

/// Cliente HTTP del backend Go — se recrea cuando cambia la URL o la
/// API key configurada.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: ref.watch(servidorUrlProvider),
    apiKey: ref.watch(servidorApiKeyProvider),
  );
});

/// Estado de conexión con el backend — el dashboard lo muestra al abrir
/// la app (probe contra /api/health). true = conectado; false = sin
/// conexión, que NO es un error: la app es local-first y sigue 100%
/// funcional, esto es solo una señal para el usuario.
///
/// `retry: null` — un probe de estado no debe reintentar con backoff.
final conexionServidorProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  try {
    await ApiClient.probarConexion(
      baseUrl: ref.watch(servidorUrlProvider),
      apiKey: ref.watch(servidorApiKeyProvider),
      timeout: const Duration(seconds: 4),
    );
    return true;
  } catch (_) {
    return false;
  }
}, retry: (_, _) => null);

/// Busca las motorizaciones de fábrica de una configuración de vehículo.
///
/// La clave es "marca|modelo|anio|trim" — la pantalla de crear vehículo la
/// arma con debounce mientras el usuario escribe. Clave inválida o sin
/// resultados → null (campos manuales). Los errores de red se RELANZAN:
/// la pantalla distingue "sin conexión" de "sin resultados" y muestra el
/// estado en vez de fallar en silencio.
///
/// `retry: null` — Riverpod 3 reintenta por defecto hasta 10 veces con
/// backoff (~34s); para el autollenado de un formulario preferimos que el
/// fallo sea visible al instante.
final motorizacionBusquedaProvider =
    FutureProvider.autoDispose.family<SugerenciasMotorizacion?, String>(
        (ref, clave) async {
  final partes = clave.split('|');
  if (partes.length != 4) return null;

  final marca = partes[0];
  final modelo = partes[1];
  final anio = int.tryParse(partes[2]);
  final trim = partes[3];
  if (marca.isEmpty || modelo.isEmpty || anio == null) return null;

  final api = ref.watch(apiClientProvider);
  try {
    return await api.buscarMotorizacion(
      marca: marca,
      modelo: modelo,
      anio: anio,
      trim: trim.isEmpty ? null : trim,
    );
  } catch (e) {
    debugPrint('[motorizacion] busqueda "$clave" fallo contra ${api.baseUrl}: $e');
    rethrow;
  }
}, retry: (_, _) => null);

// ─────────────────────────── Vehículos ───────────────────────────

/// Lista de todos los vehículos del dueño.
final vehiculosProvider =
    FutureProvider<List<Vehiculo>>((ref) async {
  return ref.watch(repositoryProvider).getAllVehiculos();
});

/// Un vehículo por ID.
final vehiculoProvider =
    FutureProvider.family<Vehiculo?, String>((ref, id) async {
  return ref.watch(repositoryProvider).getVehiculo(id);
});

// ─────────────────────────── Mantenimiento ───────────────────────────

/// Plan de mantenimiento de un vehículo.
final planProvider =
    FutureProvider.family<PlanMantenimiento?, String>((ref, vehiculoId) async {
  return ref.watch(repositoryProvider).getPlan(vehiculoId);
});

/// Registros de mantenimiento realizados de un vehículo.
final registrosProvider =
    FutureProvider.family<List<RegistroMantenimiento>, String>(
        (ref, vehiculoId) async {
  return ref.watch(repositoryProvider).getRegistros(vehiculoId);
});

// ─────────────────────────── Acciones ───────────────────────────

/// Crea un vehículo nuevo y solicita su plan al backend.
///
/// `retry: null` — como en motorizacionBusquedaProvider: un fallo de
/// escritura en SQLite debe ser visible al instante (snackbar de error),
/// no congelar el botón "Guardando…" ~38s mientras Riverpod reintenta la
/// escritura completa hasta 10 veces (cada reintento genera además un
/// plan con UUID nuevo — filas huérfanas si falla a mitad).
final crearVehiculoProvider =
    FutureProvider.family<Vehiculo, Vehiculo>((ref, vehiculo) async {
  final repo = ref.watch(repositoryProvider);
  final api = ref.watch(apiClientProvider);

  // 1. Guardar el vehículo localmente.
  await repo.saveVehiculo(vehiculo);

  // 2. Solicitar el plan al backend (biblioteca central + IA).
  PlanMantenimiento? plan;
  try {
    plan = await api.solicitarPlan(vehiculo);
  } catch (e) {
    debugPrint('[crearVehiculoProvider] Backend no disponible ($e). Generando plan base local.');
  }

  // 3. Fallback: Si el backend no está disponible o no respondió, usar plan base local.
  plan ??= _generarPlanBaseLocal(vehiculo);

  // replacePlan (no savePlan): un reintento tras error generaría otro plan
  // con UUID nuevo y dejaría dos filas para el mismo vehiculoId.
  await repo.replacePlan(plan);
  await repo.saveVehiculo(vehiculo.copyWith(
    planMantenimientoId: plan.id,
  ));

  // Invalidar la lista de vehículos.
  ref.invalidate(vehiculosProvider);
  return vehiculo;
}, retry: (_, _) => null);

// ─────────────────────────── Actualizar / Eliminar ───────────────────────────

/// Actualiza un vehículo existente (upsert por id).
///
/// El parámetro es el registro `(vehiculo, configCambio)`: la pantalla
/// compara contra el vehículo original y decide si la configuración
/// técnica cambió (chasis/motor/caja). Solo entonces se re-solicita el
/// plan al backend — actualizar kilometraje o uso no debe pisar el
/// progreso (ultimaVezKm/ultimaVezFecha) que los registros van marcando
/// en los ítems del plan vigente.
final actualizarVehiculoProvider =
    FutureProvider.family<Vehiculo, (Vehiculo, bool)>((ref, args) async {
  final (vehiculo, configCambio) = args;
  final repo = ref.watch(repositoryProvider);
  final api = ref.watch(apiClientProvider);

  // 1. Persistir el vehículo (upsert por id).
  await repo.saveVehiculo(vehiculo);

  // 2. Re-solicitar el plan solo si la configuración técnica cambió.
  if (configCambio) {
    PlanMantenimiento? plan;
    try {
      plan = await api.solicitarPlan(vehiculo);
    } catch (e) {
      debugPrint(
          '[actualizarVehiculoProvider] Backend no disponible ($e). Generando plan base local.');
    }
    plan ??= _generarPlanBaseLocal(vehiculo);

    // replacePlan (no savePlan): el plan regenerado trae id nuevo — sin el
    // reemplazo quedarían dos planes para el vehiculoId y getPlan lanzaría
    // StateError (ver VehiculoRepository.replacePlan).
    await repo.replacePlan(plan);
    await repo.saveVehiculo(vehiculo.copyWith(planMantenimientoId: plan.id));
  }

  ref.invalidate(vehiculosProvider);
  ref.invalidate(vehiculoProvider(vehiculo.id));
  if (configCambio) ref.invalidate(planProvider(vehiculo.id));
  return vehiculo;
}, retry: (_, _) => null);

/// Elimina un vehículo con todo lo asociado (plan, registros, sesiones —
/// el cascade vive en el repositorio).
final eliminarVehiculoProvider =
    FutureProvider.family<void, String>((ref, id) async {
  await ref.watch(repositoryProvider).deleteVehiculo(id);
  ref.invalidate(vehiculosProvider);
  ref.invalidate(vehiculoProvider(id));
  ref.invalidate(planProvider(id));
  ref.invalidate(registrosProvider(id));
}, retry: (_, _) => null);

// ─────────────────────────── Búsqueda por código ───────────────────────────

/// Información de un código de motor escrito a mano en el formulario.
///
/// La clave es el código en mayúsculas (normalizado por la pantalla). Los
/// errores de red se tragan CON LOG pero sin relanzar: es un asistente
/// silencioso del campo de código — la fila de estado de la búsqueda del
/// chasis ya informa la salud del servidor, y un segundo aviso de error
/// por campo sería ruido.
final infoCodigoMotorProvider =
    FutureProvider.autoDispose.family<OpcionMotor?, String>(
        (ref, codigo) async {
  if (codigo.length < 2) return null;
  final api = ref.watch(apiClientProvider);
  try {
    return await api.buscarComponenteMotor(codigo);
  } catch (e) {
    debugPrint(
        '[motorizacion] info de motor "$codigo" fallo contra ${api.baseUrl}: $e');
    return null;
  }
}, retry: (_, _) => null);

/// Igual que [infoCodigoMotorProvider] para un código de transmisión.
final infoCodigoTransmisionProvider =
    FutureProvider.autoDispose.family<OpcionTransmision?, String>(
        (ref, codigo) async {
  if (codigo.length < 2) return null;
  final api = ref.watch(apiClientProvider);
  try {
    return await api.buscarComponenteTransmision(codigo);
  } catch (e) {
    debugPrint(
        '[motorizacion] info de transmision "$codigo" fallo contra ${api.baseUrl}: $e');
    return null;
  }
}, retry: (_, _) => null);

PlanMantenimiento _generarPlanBaseLocal(Vehiculo vehiculo) {
  final planId = const Uuid().v4();
  return PlanMantenimiento(
    id: planId,
    vehiculoId: vehiculo.id,
    version: 1,
    fechaGeneracion: DateTime.now(),
    items: [
      ItemMantenimiento(
        id: const Uuid().v4(),
        categoria: CategoriaMantenimiento.motor,
        descripcion: 'Cambio de aceite de motor y filtro',
        componenteAplica: TipoComponente.motor,
        intervaloKm: 7500,
        intervaloMeses: 6,
        intervaloSeveroKm: 5000,
        fuente: FuentePlan.oem,
        confianza: NivelConfianza.alta,
      ),
      ItemMantenimiento(
        id: const Uuid().v4(),
        categoria: CategoriaMantenimiento.motor,
        descripcion: 'Cambio de filtro de aire de motor',
        componenteAplica: TipoComponente.motor,
        intervaloKm: 15000,
        intervaloMeses: 12,
        intervaloSeveroKm: 10000,
        fuente: FuentePlan.oem,
        confianza: NivelConfianza.alta,
      ),
      ItemMantenimiento(
        id: const Uuid().v4(),
        categoria: CategoriaMantenimiento.frenos,
        descripcion: 'Inspección de pastillas y discos de freno',
        componenteAplica: TipoComponente.frenos,
        intervaloKm: 10000,
        intervaloMeses: 6,
        intervaloSeveroKm: 7500,
        fuente: FuentePlan.oem,
        confianza: NivelConfianza.alta,
      ),
      ItemMantenimiento(
        id: const Uuid().v4(),
        categoria: CategoriaMantenimiento.frenos,
        descripcion: 'Cambio de líquido de frenos',
        componenteAplica: TipoComponente.frenos,
        intervaloKm: 30000,
        intervaloMeses: 24,
        intervaloSeveroKm: 20000,
        fuente: FuentePlan.oem,
        confianza: NivelConfianza.media,
      ),
      ItemMantenimiento(
        id: const Uuid().v4(),
        categoria: CategoriaMantenimiento.refrigeracion,
        descripcion: 'Inspección y purga de refrigerante',
        componenteAplica: TipoComponente.motor,
        intervaloKm: 40000,
        intervaloMeses: 24,
        intervaloSeveroKm: 30000,
        fuente: FuentePlan.oem,
        confianza: NivelConfianza.media,
      ),
      ItemMantenimiento(
        id: const Uuid().v4(),
        categoria: CategoriaMantenimiento.transmision,
        descripcion: 'Inspección de aceite de transmisión',
        componenteAplica: TipoComponente.transmision,
        intervaloKm: 40000,
        intervaloMeses: 24,
        intervaloSeveroKm: 25000,
        fuente: FuentePlan.oem,
        confianza: NivelConfianza.media,
      ),
      ItemMantenimiento(
        id: const Uuid().v4(),
        categoria: CategoriaMantenimiento.motor,
        descripcion: 'Cambio de bujías de encendido',
        componenteAplica: TipoComponente.motor,
        intervaloKm: 40000,
        intervaloMeses: 24,
        intervaloSeveroKm: 25000,
        fuente: FuentePlan.oem,
        confianza: NivelConfianza.media,
      ),
    ],
  );
}
