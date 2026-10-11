import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/plan_mantenimiento.dart';
import '../models/vehiculo.dart';

/// Cliente HTTP que habla con el backend Go.
///
/// Responsabilidades del backend:
/// - `GET /api/plan` — biblioteca de planes (cache compartido o investiga con IA)
/// - `POST /api/sesion` — crear sesión de compartido con mecánico
/// - WebSocket `/relay` — ruteo de mensajes dueño ↔ mecánico
class ApiClient {
  final Dio _dio;

  ApiClient({String baseUrl = 'http://localhost:8080'})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
        )) {
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(responseBody: true));
    }
  }

  /// Solicita el plan de mantenimiento para una configuración de vehículo.
  ///
  /// El backend busca en su cache (biblioteca central). Si no existe,
  /// investiga con Claude API + web search, guarda en cache, y devuelve.
  /// Si el vehículo tiene swaps, marca `requiereReview: true`.
  Future<PlanMantenimiento?> solicitarPlan(Vehiculo vehiculo) async {
    final response = await _dio.get('/api/plan', queryParameters: {
      'marca': vehiculo.marca,
      'modelo': vehiculo.modelo,
      'anio': vehiculo.anio,
      'trim': vehiculo.trim,
      'drivetrain': vehiculo.drivetrain.name,
      'motorCodigo': vehiculo.motor.codigo,
      'transCodigo': vehiculo.transmision.codigo,
    });

    final data = response.data['plan'] as Map<String, dynamic>?;
    if (data == null) return null;
    return PlanMantenimiento.fromJson(data);
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
