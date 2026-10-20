import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_main/main.dart';
import 'package:car_main/providers/providers.dart';

void main() {
  testWidgets('App renders dashboard', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // El indicador de conexión probea /api/health contra la URL
        // configurada — en el test no debe tocar la red.
        conexionServidorProvider.overrideWith((ref) => Future.value(true)),
      ],
      child: const CarMainApp(),
    ));

    // Debe mostrar el título CarMain en la AppBar.
    expect(find.text('CarMain'), findsOneWidget);
  });
}
