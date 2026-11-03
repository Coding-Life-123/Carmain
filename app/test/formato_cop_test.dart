import 'package:flutter_test/flutter_test.dart';
import 'package:car_main/utils/formato.dart';

void main() {
  group('formatearCop', () {
    test('formatea enteros con separador de miles y prefijo \$', () {
      expect(formatearCop(0), '\$ 0');
      expect(formatearCop(500), '\$ 500');
      expect(formatearCop(1500), '\$ 1.500');
      expect(formatearCop(150000), '\$ 150.000');
      expect(formatearCop(12500000), '\$ 12.500.000');
    });

    test('redondea decimales al entero más cercano sin mostrar centavos', () {
      expect(formatearCop(1500.4), '\$ 1.500');
      expect(formatearCop(1500.6), '\$ 1.501');
    });

    test('soporta valores negativos', () {
      expect(formatearCop(-25000), '-\$ 25.000');
    });
  });

  group('parsearCop', () {
    test('parsea cadenas limpias y con separador de miles', () {
      expect(parsearCop('150000'), 150000);
      expect(parsearCop('150.000'), 150000);
      expect(parsearCop('\$ 150.000'), 150000);
      expect(parsearCop('  \$ 1.250.000  '), 1250000);
    });

    test('retorna null para cadenas vacías o inválidas', () {
      expect(parsearCop(null), isNull);
      expect(parsearCop(''), isNull);
      expect(parsearCop('   '), isNull);
      expect(parsearCop('abc'), isNull);
    });

    test('soporta decimales tras la coma', () {
      expect(parsearCop('150.000,50'), 150000.5);
    });

    test('rechaza valores fuera de rango o negativos', () {
      expect(parsearCop('-5000'), isNull);
      expect(parsearCop('1.000.000.000'), isNull); // > 999M
    });
  });
}
