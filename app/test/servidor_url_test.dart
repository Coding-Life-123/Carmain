import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_main/providers/providers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('usa la URL por defecto cuando no hay nada guardado', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    // El default es el servidor del PC vía Funnel — instalación limpia
    // funciona sin configurar nada. La normalización añade el :443.
    expect(container.read(servidorUrlProvider),
        'https://desktop-n1r4t4j.tail93c510.ts.net:443');
  });

  test('setUrl persiste y el ApiClient se recrea con la nueva URL', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    await container
        .read(servidorUrlProvider.notifier)
        .setUrl('http://10.0.2.2:8080');

    expect(container.read(servidorUrlProvider), 'http://10.0.2.2:8080');
    // Persistido.
    expect(prefs.getString('servidor_url'), 'http://10.0.2.2:8080');
    // El ApiClient sigue la URL configurada.
    expect(
      container.read(apiClientProvider).relayUrl('abc'),
      'ws://10.0.2.2:8080/relay?sesion=abc',
    );
  });

  test('la URL guardada sobrevive un reinicio (nuevo container)', () async {
    // Primer arranque: guardar.
    var prefs = await SharedPreferences.getInstance();
    var container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    await container
        .read(servidorUrlProvider.notifier)
        .setUrl('http://192.168.1.50:8080');
    container.dispose();

    // "Reinicio": mismo store de prefs (en producción, disco).
    final prefsNuevas = await SharedPreferences.getInstance();
    final container2 = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefsNuevas)],
    );
    addTearDown(container2.dispose);

    expect(container2.read(servidorUrlProvider), 'http://192.168.1.50:8080');
  });

  test('setUrl normaliza: completa puerto, quita path y slash final', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(servidorUrlProvider.notifier);

    // Sin puerto → default del sistema (8080), no el puerto 80.
    await notifier.setUrl('http://192.168.1.50');
    expect(container.read(servidorUrlProvider), 'http://192.168.1.50:8080');

    // Con path → se descarta (evitaría /api/api/plan).
    await notifier.setUrl('http://192.168.1.50:8080/api');
    expect(container.read(servidorUrlProvider), 'http://192.168.1.50:8080');

    // Slash final → se quita.
    await notifier.setUrl('http://192.168.1.50:8080/');
    expect(container.read(servidorUrlProvider), 'http://192.168.1.50:8080');
  });

  test('setUrl con esquema en mayúsculas no rompe el WebSocket del relay',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    // relayUrl hace replaceFirst('http', 'ws') case-sensitive: sin
    // normalizar, 'HTTP://' dejaría un esquema que WebSocket.connect
    // rechaza.
    await container
        .read(servidorUrlProvider.notifier)
        .setUrl('HTTP://192.168.1.50:8080');

    expect(
      container.read(apiClientProvider).relayUrl('abc'),
      'ws://192.168.1.50:8080/relay?sesion=abc',
    );
  });
}
