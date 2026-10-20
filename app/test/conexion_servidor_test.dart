import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_main/providers/providers.dart';

/// Tests del indicador de conexión con el backend (conexionServidorProvider):
/// al abrir la app se prueba /api/health contra la URL configurada —
/// true con servidor vivo, false (sin lanzar) si no responde.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('true con servidor vivo, false sin él — y no lanza', () async {
    // Servidor real de prueba: responde 200 a cualquier ruta.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = 200;
      request.response.write('{"status":"ok"}');
      await request.response.close();
    });

    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    // URL viva → conectado.
    await container
        .read(servidorUrlProvider.notifier)
        .setUrl('http://127.0.0.1:${server.port}');
    var sub = container.listen(conexionServidorProvider, (_, _) {});
    expect(await container.read(conexionServidorProvider.future), isTrue);
    sub.close();

    // URL muerta (nada escucha en el puerto 1) → false, sin excepción.
    await container
        .read(servidorUrlProvider.notifier)
        .setUrl('http://127.0.0.1:1');
    sub = container.listen(conexionServidorProvider, (_, _) {});
    expect(await container.read(conexionServidorProvider.future), isFalse);
    sub.close();
  });
}
