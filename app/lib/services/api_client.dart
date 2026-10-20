import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/motorizacion.dart';
import '../models/plan_mantenimiento.dart';
import '../models/vehiculo.dart';
import 'plan_parser.dart';

/// Cliente HTTP que habla con el backend Go.
///
/// Responsabilidades del backend:
/// - `GET /api/plan` — biblioteca de planes (cache compartido o investiga con IA)
/// - `POST /api/sesion` — crear sesión de compartido con mecánico
/// - WebSocket `/relay` — ruteo de mensajes dueño ↔ mecánico
class ApiClient {
  final Dio _dio;
  final String? _apiKey;

  /// [apiKey] se envía como X-Api-Key en cada petición (el servidor la
  /// exige cuando está expuesto a internet). [adapter] es un seam de
  /// tests: permite capturar los requests sin tocar la red.
  ApiClient({
    String baseUrl = 'http://localhost:8080',
    String? apiKey,
    HttpClientAdapter? adapter,
  })  : _apiKey = (apiKey == null || apiKey.isEmpty) ? null : apiKey,
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          // El servidor puede tardar hasta 60s investigando con Gemini +
          // búsqueda web (su propio timeout). Si esto fuera menor, la app
          // abortaría la conexión mientras el servidor completa la
          // investigación — la cachea igual, pero el usuario nunca la
          // recibe y el vehículo queda con el plan base local.
          receiveTimeout: const Duration(seconds: 90),
        )) {
    if (_apiKey != null) {
      _dio.options.headers['X-Api-Key'] = _apiKey;
    }
    if (adapter != null) _dio.httpClientAdapter = adapter;
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(responseBody: true));
    }
  }

  /// URL base configurada — útil para diagnósticos en logs.
  String get baseUrl => _dio.options.baseUrl;

  /// La API key configurada (null si no hay) — tests y diagnósticos.
  String? get apiKey => _apiKey;

  /// Headers del handshake del WebSocket del relay: el middleware de
  /// auth del servidor los valida durante el upgrade.
  Map<String, String> relayHeaders() =>
      _apiKey == null ? const {} : {'X-Api-Key': _apiKey};

  /// Prueba de conexión: GET /api/health con timeout corto. Retorna la
  /// latencia; lanza DioException si falla.
  ///
  /// Nota: /api/health es público — el probe valida URL/TLS/alcanzabilidad,
  /// no la validez de la API key (esa se confirma en el primer uso real).
  static Future<Duration> probarConexion({
    required String baseUrl,
    String? apiKey,
    Duration timeout = const Duration(seconds: 5),
    HttpClientAdapter? adapter,
  }) async {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: timeout,
      receiveTimeout: timeout,
      sendTimeout: timeout,
      headers: {
        if (apiKey != null && apiKey.isNotEmpty) 'X-Api-Key': apiKey,
      },
    ));
    if (adapter != null) dio.httpClientAdapter = adapter;
    final inicio = DateTime.now();
    try {
      await dio.get('/api/health');
      return DateTime.now().difference(inicio);
    } finally {
      dio.close();
    }
  }

  /// Solicita el plan de mantenimiento para una configuración de vehículo.
  ///
  /// El backend busca en su cache (biblioteca central). Si no existe,
  /// investiga con Claude API + web search, guarda en cache, y devuelve.
  /// Si el vehículo tiene swaps, marca `requiereReview: true`.
  ///
  /// El plan del servidor viene indexado por configuración (sin
  /// `vehiculoId`); se asocia al vehículo acá, al parsear.
  Future<PlanMantenimiento?> solicitarPlan(Vehiculo vehiculo) async {
    final response = await _dio.get('/api/plan', queryParameters: {
      'marca': vehiculo.marca,
      'modelo': vehiculo.modelo,
      'anio': vehiculo.anio,
      'trim': vehiculo.trim,
      // El contrato con Go usa las etiquetas canónicas (FWD|RWD|AWD|4WD),
      // no el nombre del enum Dart ('fourWd').
      'drivetrain': vehiculo.drivetrain.label,
      'motorCodigo': vehiculo.motor.codigo,
      'transCodigo': vehiculo.transmision.codigo,
    });

    final data = response.data['plan'] as Map<String, dynamic>?;
    if (data == null) return null;
    return parsearPlanDelServidor(data, vehiculoId: vehiculo.id);
  }

  /// Busca las motorizaciones de fábrica de un modelo/año.
  ///
  /// El backend usa Gemini + Google Search. La respuesta se parsea de
  /// forma tolerante: opciones sin código o con valores fuera de los
  /// enums de la app se descartan/ignoran.
  Future<SugerenciasMotorizacion?> buscarMotorizacion({
    required String marca,
    required String modelo,
    required int anio,
    String? trim,
  }) async {
    final response = await _dio.get('/api/motorizacion', queryParameters: {
      'marca': marca,
      'modelo': modelo,
      'anio': anio,
      if (trim != null && trim.isNotEmpty) 'trim': trim,
    });

    final data = response.data;
    if (data is! Map<String, dynamic>) return null;
    return SugerenciasMotorizacion.fromJson(data);
  }

  /// Busca la información de un código de motor concreto — el usuario puede
  /// escribir el código a mano en el formulario y la app auto-rellena los
  /// detalles. Devuelve null si el servidor no lo encuentra.
  Future<OpcionMotor?> buscarComponenteMotor(String codigo) =>
      _buscarComponente('motor', codigo, OpcionMotor.fromJson);

  /// Igual que [buscarComponenteMotor] para un código de transmisión.
  Future<OpcionTransmision?> buscarComponenteTransmision(String codigo) =>
      _buscarComponente('transmision', codigo, OpcionTransmision.fromJson);

  Future<T?> _buscarComponente<T>(
    String tipo,
    String codigo,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final response = await _dio.get('/api/componente', queryParameters: {
      'tipo': tipo,
      'codigo': codigo,
    });

    final data = response.data;
    if (data is! Map<String, dynamic>) return null;
    if (data['encontrado'] != true) return null;
    final opcion = data['opcion'];
    if (opcion is! Map) return null;
    return fromJson(Map<String, dynamic>.from(opcion));
  }

  /// Crea una sesión de compartido con un mecánico (para relay remoto).
  /// Retorna el código/invite que el mecánico usa para conectarse.
  Future<String> crearSesion({
    required String vehiculoId,
    required Duration duracion,
  }) async {
    final response = await _dio.post('/api/sesion', data: {
      'vehiculoId': vehiculoId,
      'duracionSegundos': duracion.inSeconds,
    });
    return response.data['codigo'] as String;
  }

  /// Revoca una sesión de compartido activa.
  Future<void> revocarSesion(String codigo) async {
    await _dio.delete('/api/sesion/$codigo');
  }

  /// URL del WebSocket para el relay.
  String relayUrl(String sesionCodigo) {
    final base = _dio.options.baseUrl.replaceFirst('http', 'ws');
    return '$base/relay?sesion=$sesionCodigo';
  }
}
