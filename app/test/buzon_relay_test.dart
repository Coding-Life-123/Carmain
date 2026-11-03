import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_main/services/api_client.dart';

class _FakeAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;
  _FakeAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object? body, {int status = 200}) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  test('crearSesion envía snapshot y deviceId si están presentes', () async {
    RequestOptions? captured;
    final client = ApiClient(
      baseUrl: 'http://localhost:8080',
      adapter: _FakeAdapter((opts) async {
        captured = opts;
        return _json({'codigo': 'A7F9K2', 'expiraEn': '2026-11-03T12:00:00Z'},
            status: 201);
      }),
    );

    final codigo = await client.crearSesion(
      vehiculoId: 'veh-1',
      duracion: const Duration(hours: 12),
      deviceId: 'device-owner',
      snapshot: {'marca': 'Toyota', 'modelo': 'AE86'},
    );

    expect(codigo, 'A7F9K2');
    expect(captured?.method, 'POST');
    expect(captured?.path, '/api/sesion');
    final data = captured?.data as Map<String, dynamic>;
    expect(data['vehiculoId'], 'veh-1');
    expect(data['duracionSegundos'], 43200);
    expect(data['deviceId'], 'device-owner');
    expect(data['snapshot'], {'marca': 'Toyota', 'modelo': 'AE86'});
  });

  test('obtenerSesionPublica consulta /api/sesion/:codigo', () async {
    RequestOptions? captured;
    final client = ApiClient(
      baseUrl: 'http://localhost:8080',
      adapter: _FakeAdapter((opts) async {
        captured = opts;
        return _json({
          'codigo': 'A7F9K2',
          'vehiculoId': 'veh-1',
          'snapshot': {'marca': 'Toyota', 'modelo': 'AE86'},
        });
      }),
    );

    final res = await client.obtenerSesionPublica('A7F9K2');
    expect(captured?.method, 'GET');
    expect(captured?.path, '/api/sesion/A7F9K2');
    expect(res?['codigo'], 'A7F9K2');
    expect(res?['snapshot']['marca'], 'Toyota');
  });

  test('enviarPropuestaMecanico hace POST a /api/sesion/:codigo/propuesta', () async {
    RequestOptions? captured;
    final client = ApiClient(
      baseUrl: 'http://localhost:8080',
      adapter: _FakeAdapter((opts) async {
        captured = opts;
        return _json({'ok': true, 'mensaje': 'guardado'}, status: 201);
      }),
    );

    await client.enviarPropuestaMecanico('A7F9K2', {
      'mecanico': 'Taller Speed',
      'items': [
        {'itemId': 'aceite', 'estado': 'realizado'}
      ]
    });

    expect(captured?.method, 'POST');
    expect(captured?.path, '/api/sesion/A7F9K2/propuesta');
    final body = captured?.data as Map<String, dynamic>;
    expect(body['mecanico'], 'Taller Speed');
  });

  test('obtenerPropuestasPendientes y confirmarPropuestas manejan el buzón', () async {
    final client = ApiClient(
      baseUrl: 'http://localhost:8080',
      adapter: _FakeAdapter((opts) async {
        if (opts.path.endsWith('/propuestas')) {
          return _json({
            'codigo': 'A7F9K2',
            'propuestas': [
              {'mecanico': 'Taller Speed', 'costo': 50.0}
            ]
          });
        }
        if (opts.path.endsWith('/confirmar')) {
          return _json({'ok': true});
        }
        return _json({}, status: 404);
      }),
    );

    final propuestas = await client.obtenerPropuestasPendientes('A7F9K2');
    expect(propuestas.length, 1);
    expect(propuestas.first['mecanico'], 'Taller Speed');

    await client.confirmarPropuestas('A7F9K2');
  });
}

