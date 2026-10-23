import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_main/providers/providers.dart';
import 'package:car_main/services/api_client.dart';

/// Tests de la API key del servidor (header X-Api-Key) y del probe de
/// conexión (GET /api/health). El adapter falso captura los requests sin
/// tocar la red.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('setApiKey persiste en servidor_api_key y sobrevive un reinicio',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    await container
        .read(servidorApiKeyProvider.notifier)
        .setApiKey('secreta-123');
    container.dispose();

    // "Reinicio": mismo store de prefs (en producción, disco).
    final prefsNuevas = await SharedPreferences.getInstance();
    final container2 = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefsNuevas)],
    );
    addTearDown(container2.dispose);

    expect(container2.read(servidorApiKeyProvider), 'secreta-123');
  });

  test('setApiKey vacía limpia la preferencia (modo LAN)', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(servidorApiKeyProvider.notifier);

    await notifier.setApiKey('secreta');
    expect(prefs.getString('servidor_api_key'), 'secreta');

    await notifier.setApiKey('');
    expect(prefs.getString('servidor_api_key'), isNull);
    expect(container.read(servidorApiKeyProvider), '');
  });

  test('apiClientProvider se recrea cuando cambia la key', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    expect(container.read(apiClientProvider).apiKey, isNull);

    await container.read(servidorApiKeyProvider.notifier).setApiKey('nueva');
    expect(container.read(apiClientProvider).apiKey, 'nueva');
  });

  test('la key efectiva prefiere la manual y cae a la del build', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    // Sin key manual → la horneada en el build (vacía en tests, que no
    // usan --dart-define).
    expect(container.read(apiKeyEfectivaProvider), '');

    // La manual (override de desarrollo) manda.
    await container.read(servidorApiKeyProvider.notifier).setApiKey('manual');
    expect(container.read(apiKeyEfectivaProvider), 'manual');

    // Vaciar la manual vuelve a la del build.
    await container.read(servidorApiKeyProvider.notifier).setApiKey('');
    expect(container.read(apiKeyEfectivaProvider), '');
  });

  test('ApiClient envía X-Api-Key cuando hay key', () async {
    final grabador = _AdapterGrabador();
    final client = ApiClient(
      baseUrl: 'http://servidor',
      apiKey: 'secreta',
      adapter: grabador,
    );

    await client.buscarMotorizacion(
        marca: 'Toyota', modelo: 'Supra', anio: 1997);

    expect(grabador.requests, hasLength(1));
    expect(grabador.requests.first.headers['X-Api-Key'], 'secreta');
  });

  test('ApiClient sin key no envía la cabecera', () async {
    final grabador = _AdapterGrabador();
    final client =
        ApiClient(baseUrl: 'http://servidor', adapter: grabador);

    await client.buscarMotorizacion(
        marca: 'Toyota', modelo: 'Supra', anio: 1997);

    expect(grabador.requests.first.headers.containsKey('X-Api-Key'), isFalse);
  });

  test('relayHeaders incluye la key para el handshake del WebSocket',
      () async {
    expect(ApiClient(apiKey: 'k').relayHeaders(), {'X-Api-Key': 'k'});
    expect(ApiClient().relayHeaders(), isEmpty);
  });

  test('probarConexion envía la key y retorna la latencia', () async {
    final grabador = _AdapterGrabador(
      demora: const Duration(milliseconds: 50),
    );

    final latencia = await ApiClient.probarConexion(
      baseUrl: 'http://servidor',
      apiKey: 'secreta',
      adapter: grabador,
    );

    expect(grabador.requests.single.path, contains('/api/health'));
    expect(grabador.requests.single.headers['X-Api-Key'], 'secreta');
    expect(latencia.inMilliseconds, greaterThanOrEqualTo(50));
  });

  test('probarConexion lanza con respuesta de error', () async {
    final grabador = _AdapterGrabador(statusCode: 500);

    await expectLater(
      ApiClient.probarConexion(baseUrl: 'http://servidor', adapter: grabador),
      throwsA(isA<DioException>()),
    );
  });
}

/// Adapter de Dio que responde 200 con un JSON fijo sin tocar la red,
/// grabando cada request. [demora] simula latencia; [statusCode] simula
/// errores.
class _AdapterGrabador implements HttpClientAdapter {
  _AdapterGrabador({this.demora, this.statusCode = 200});

  final Duration? demora;
  final int statusCode;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (demora != null) await Future<void>.delayed(demora!);
    final cuerpo =
        Uint8List.fromList(utf8.encode('{"motores": [], "transmisiones": [], "status": "ok"}'));
    return ResponseBody(Stream.value(cuerpo), statusCode);
  }

  @override
  void close({bool force = false}) {}
}
