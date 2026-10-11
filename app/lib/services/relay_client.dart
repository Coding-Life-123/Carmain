import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Cliente del relay server (WebSocket).
///
/// Se conecta al backend Go por WebSocket para rutar mensajes entre
/// el dispositivo del dueño y el del mecánico. Los payloads van
/// cifrados E2EE — el relay solo los rutea, no puede leerlos.
class RelayClient {
  WebSocket? _socket;
  StreamSubscription? _subscription;
  bool _isConnected = false;

  /// Stream de mensajes entrantes del relay.
  final _incomingController = StreamController<RelayMessage>.broadcast();
  Stream<RelayMessage> get incoming => _incomingController.stream;

  bool get isConnected => _isConnected;

  /// Conecta al relay server con un código de sesión.
  Future<void> connect(String relayUrl) async {
    if (_isConnected) return;

    try {
      _socket = await WebSocket.connect(relayUrl);
      _isConnected = true;

      _subscription = _socket!.listen(
        (data) {
          if (data is String) {
            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              _incomingController.add(RelayMessage.fromJson(json));
            } catch (e) {
              if (kDebugMode) debugPrint('Relay: error parseando mensaje: $e');
            }
          }
        },
        onError: (e) {
          if (kDebugMode) debugPrint('Relay: error: $e');
          _isConnected = false;
        },
        onDone: () {
          _isConnected = false;
          if (kDebugMode) debugPrint('Relay: conexión cerrada');
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Relay: no se pudo conectar: $e');
      rethrow;
    }
  }

  /// Envía un mensaje al relay (que lo rutea al otro dispositivo).
  void send(RelayMessage message) {
    if (!_isConnected || _socket == null) {
      throw StateError('Relay no conectado');
    }
    _socket!.add(jsonEncode(message.toJson()));
  }

  /// Desconecta del relay.
  Future<void> disconnect() async {
    await _subscription?.cancel();
    await _socket?.close();
    _socket = null;
    _subscription = null;
    _isConnected = false;
  }

  void dispose() {
    disconnect();
    _incomingController.close();
  }
}

/// Mensaje que se rutea por el relay.
class RelayMessage {
  final String tipo; // snapshot | registro | revocacion | ack
  final String de; // device ID remitente
  final String para; // device ID destinatario
  final String sesionId;
  final List<int> payload; // blob cifrado E2EE
  final int timestamp;

  RelayMessage({
    required this.tipo,
    required this.de,
    required this.para,
    required this.sesionId,
    required this.payload,
    required this.timestamp,
  });

  factory RelayMessage.fromJson(Map<String, dynamic> json) {
    return RelayMessage(
      tipo: json['tipo'] as String,
      de: json['de'] as String,
      para: json['para'] as String,
      sesionId: json['sesionId'] as String,
      payload: (json['payload'] as List).cast<int>(),
      timestamp: json['timestamp'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'tipo': tipo,
        'de': de,
        'para': para,
        'sesionId': sesionId,
        'payload': payload,
        'timestamp': timestamp,
      };
}
