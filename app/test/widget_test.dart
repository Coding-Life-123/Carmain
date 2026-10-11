import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:car_main/main.dart';

void main() {
  testWidgets('App renders dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: CarMainApp()));

    // Debe mostrar el título CarMain en la AppBar.
    expect(find.text('CarMain'), findsOneWidget);
  });
}
