import 'package:car_main/widgets/vehiculo_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizarMarcaSlug', () {
    test('normaliza marcas directas', () {
      expect(normalizarMarcaSlug('BMW'), 'bmw');
      expect(normalizarMarcaSlug('Toyota'), 'toyota');
      expect(normalizarMarcaSlug('Honda'), 'honda');
      expect(normalizarMarcaSlug('Ford'), 'ford');
    });

    test('normaliza alias y variantes compuestas', () {
      expect(normalizarMarcaSlug('VW'), 'volkswagen');
      expect(normalizarMarcaSlug('Chevy'), 'chevrolet');
      expect(normalizarMarcaSlug('Mercedes-Benz'), 'mercedes-benz');
      expect(normalizarMarcaSlug('Mercedes Benz'), 'mercedes-benz');
      expect(normalizarMarcaSlug('Alfa Romeo'), 'alfa-romeo');
      expect(normalizarMarcaSlug('Land Rover'), 'land-rover');
      expect(normalizarMarcaSlug('Aston Martin'), 'aston-martin');
    });

    test('limpia caracteres extraños y espacios', () {
      expect(normalizarMarcaSlug('  Nissan   '), 'nissan');
      expect(normalizarMarcaSlug('Audi!!'), 'audi');
    });
  });

  group('VehiculoAvatar y VehiculoSiluetaFondo widgets', () {
    testWidgets('VehiculoAvatar renderiza exclusivamente el logo de la marca', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VehiculoAvatar(
              marca: 'Toyota',
              size: 60,
            ),
          ),
        ),
      );

      // El avatar se construye sin excepciones
      expect(find.byType(VehiculoAvatar), findsOneWidget);
    });

    testWidgets('VehiculoSiluetaFondo renderiza silueta para fondo de textos', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VehiculoSiluetaFondo(),
          ),
        ),
      );

      expect(find.byType(VehiculoSiluetaFondo), findsOneWidget);
    });

    testWidgets('renderiza fallback de inicial si la marca está vacía o cargando',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VehiculoAvatar(
              marca: '',
              size: 60,
            ),
          ),
        ),
      );

      expect(find.text('?'), findsOneWidget);
    });
  });
}
