import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_main/providers/providers.dart';
import 'package:car_main/screens/dashboard/dashboard_screen.dart';

/// Tests del diálogo "Servidor Backend" (URL + API key + probe).
///
/// La regresión original (vista en el teléfono): cerrar el diálogo con el
/// probe en vuelo revienta con "TextEditingController used after being
/// disposed" y la aserción _dependents.isEmpty — los controllers se
/// disponían en el futuro del showDialog mientras el probe async aún
/// tocaba estado.
///
/// El probe se inyecta ([EditarServidorDialog.probeOverride]) porque el
/// binding de widget tests mockea todo HttpClient (responde 400 sin tocar
/// red): la carrera solo se produce con un futuro controlado.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Bombea un botón que abre el diálogo; retorna las prefs para afirmar
  /// persistencia.
  Future<SharedPreferences> pumpConDialogo(
    WidgetTester tester, {
    Future<Duration> Function()? probe,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => EditarServidorDialog(
                  initialUrl: 'http://192.168.1.50:8080',
                  initialApiKey: '',
                  probeOverride: probe,
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return prefs;
  }

  testWidgets('cerrar el diálogo con el probe en vuelo no revienta',
      (tester) async {
    final completer = Completer<Duration>();
    await pumpConDialogo(tester, probe: () => completer.future);

    // Lanzar el probe y cerrar de inmediato — la condición exacta del bug.
    await tester.tap(find.text('Probar conexión'));
    await tester.pump(); // el probe queda en vuelo
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle(); // el diálogo se cierra
    expect(find.byType(AlertDialog), findsNothing);

    // La respuesta llega tras el cierre: nada debe lanzar.
    completer.complete(const Duration(milliseconds: 120));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('abrir'), findsOneWidget); // seguimos fuera, vivos
  });

  testWidgets('guardar persiste URL y API key', (tester) async {
    final prefs = await pumpConDialogo(tester);

    await tester.enterText(
        find.byType(TextField).at(0), 'http://10.0.2.2:8080');
    await tester.enterText(find.byType(TextField).at(1), 'llave-secreta');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(prefs.getString('servidor_url'), 'http://10.0.2.2:8080');
    expect(prefs.getString('servidor_api_key'), 'llave-secreta');
  });

  testWidgets('el probe fallido muestra error accionable', (tester) async {
    await pumpConDialogo(
      tester,
      probe: () => Future.error(DioException(
        requestOptions: RequestOptions(path: '/api/health'),
        type: DioExceptionType.connectionError,
      )),
    );

    await tester.tap(find.text('Probar conexión'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No se pudo conectar'), findsOneWidget);
  });

  testWidgets('el probe exitoso muestra la latencia', (tester) async {
    await pumpConDialogo(
      tester,
      probe: () async => const Duration(milliseconds: 87),
    );

    await tester.tap(find.text('Probar conexión'));
    await tester.pumpAndSettle();

    expect(find.text('Conectado — 87 ms'), findsOneWidget);
  });
}
