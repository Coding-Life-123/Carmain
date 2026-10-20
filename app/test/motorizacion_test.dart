import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_main/models/enums.dart';
import 'package:car_main/models/motorizacion.dart';
import 'package:car_main/providers/providers.dart';
import 'package:car_main/services/api_client.dart';

void main() {
  group('SugerenciasMotorizacion.fromJson (tolerante)', () {
    test('parsea una respuesta fiel del servidor', () {
      final s = SugerenciasMotorizacion.fromJson({
        'motores': [
          {
            'codigo': '2JZ-GTE',
            'descripcion': '3.0L I6 biturbo',
            'combustible': 'gasolina',
            'cilindrada': 3.0,
            'cilindros': 6,
            'aspiracion': 'Twin-Turbo',
            'potenciaHp': 280,
            'torqueNm': 451,
          },
          {
            'codigo': '2JZ-GE',
            'combustible': 'gasolina',
            'cilindrada': 3.0,
          },
        ],
        'transmisiones': [
          {
            'codigo': 'R154',
            'descripcion': 'manual 5 velocidades',
            'tipo': 'manual',
            'marchas': 5,
          },
        ],
        'desdeCache': false,
      });

      expect(s.motores, hasLength(2));
      final gte = s.motores.first;
      expect(gte.codigo, '2JZ-GTE');
      expect(gte.combustible, TipoCombustible.gasolina);
      expect(gte.cilindrada, 3.0);
      expect(gte.cilindros, 6);
      expect(gte.aspiracion, 'Twin-Turbo');
      expect(gte.potenciaHp, 280);
      expect(gte.torqueNm, 451);

      expect(s.transmisiones, hasLength(1));
      expect(s.transmisiones.first.tipo, TipoTransmision.manual);
      expect(s.transmisiones.first.marchas, 5);
    });

    test('ignora valores fuera de vocabulario y opciones sin código', () {
      final s = SugerenciasMotorizacion.fromJson({
        'motores': [
          {
            'codigo': 'FE-DOHC',
            'combustible': 'electrico-hibrido', // fuera del enum → null
            'cilindros': 'seis', // no numérico → null
            'potenciaHp': '254.79', // string decimal → redondea a 255
            'torqueNm': 'no numérico', // → null
          },
          {'codigo': ''}, // sin código → descartada
          'no soy un mapa', // basura → ignorada
        ],
        'transmisiones': [
          {'codigo': 'F4A51', 'tipo': 'automatic'}, // inglés, fuera del enum
        ],
      });

      expect(s.motores, hasLength(1));
      expect(s.motores.first.combustible, isNull);
      expect(s.motores.first.cilindros, isNull);
      expect(s.motores.first.potenciaHp, 255);
      expect(s.motores.first.torqueNm, isNull);
      expect(s.transmisiones.first.tipo, isNull);
    });

    test('listas ausentes o con tipo incorrecto → vacías', () {
      final s = SugerenciasMotorizacion.fromJson({});
      expect(s.motores, isEmpty);
      expect(s.transmisiones, isEmpty);

      final s2 = SugerenciasMotorizacion.fromJson({
        'motores': 'no una lista',
        'transmisiones': 42,
      });
      expect(s2.motores, isEmpty);
      expect(s2.transmisiones, isEmpty);
    });

    test('drivetrain: etiqueta canónica, case-insensitive, o null', () {
      expect(SugerenciasMotorizacion.fromJson({'drivetrain': 'RWD'}).drivetrain,
          Drivetrain.rwd);
      expect(
          SugerenciasMotorizacion.fromJson({'drivetrain': 'awd'}).drivetrain,
          Drivetrain.awd);
      expect(
          SugerenciasMotorizacion.fromJson({'drivetrain': '4wd'}).drivetrain,
          Drivetrain.fourWd);
      // Fuera del vocabulario o tipo incorrecto → null (el usuario elige).
      expect(
          SugerenciasMotorizacion.fromJson({'drivetrain': 'traction'})
              .drivetrain,
          isNull);
      expect(SugerenciasMotorizacion.fromJson({'drivetrain': 4}).drivetrain,
          isNull);
      expect(SugerenciasMotorizacion.fromJson({}).drivetrain, isNull);
    });
  });

  group('motorizacionBusquedaProvider', () {
    test('clave inválida → null sin llamar al backend', () async {
      final container = ProviderContainer(overrides: [
        apiClientProvider
            .overrideWithValue(_ApiClientFake(null, llamada: () => fail(
                'no debe llamar al backend con clave inválida'))),
      ]);
      addTearDown(container.dispose);

      expect(await container.read(motorizacionBusquedaProvider('|').future),
          isNull);
    });

    test('devuelve las sugerencias del backend', () async {
      final sugerencias = SugerenciasMotorizacion.fromJson({
        'motores': [
          {'codigo': 'FE-DOHC', 'combustible': 'gasolina'},
        ],
        'transmisiones': [
          {'codigo': 'F4A51', 'tipo': 'automatica'},
        ],
      });
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(_ApiClientFake(sugerencias)),
      ]);
      addTearDown(container.dispose);

      final resultado =
          await container.read(motorizacionBusquedaProvider('Kia|Sportage|2002|').future);
      expect(resultado, isNotNull);
      expect(resultado!.motores.first.codigo, 'FE-DOHC');
      expect(resultado.transmisiones.first.tipo, TipoTransmision.automatica);
    });

    test('backend caído → error (la UI muestra "sin conexión")', () async {
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(
            _ApiClientFake(null, error: Exception('connection refused'))),
      ]);
      addTearDown(container.dispose);

      final provider = motorizacionBusquedaProvider('Kia|Sportage|2002|');
      // listen mantiene vivo al autoDispose mientras el futuro está en
      // vuelo — sin él, el container lo dispone y `.future` lanza StateError.
      final sub = container.listen(provider, (_, _) {});
      await expectLater(
        container.read(provider.future),
        throwsA(isA<Exception>()),
      );
      sub.close();
    });
  });

  group('infoCodigoMotorProvider / infoCodigoTransmisionProvider', () {
    test('código corto → null sin llamar al backend', () async {
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(_ApiClientFake(null,
            llamadaComponente: () =>
                fail('no debe llamar al backend con código corto'))),
      ]);
      addTearDown(container.dispose);

      expect(await container.read(infoCodigoMotorProvider('K').future),
          isNull);
    });

    test('devuelve la info del código de motor desde el backend', () async {
      final opcion = OpcionMotor.fromJson({
        'codigo': 'K4J',
        'combustible': 'gasolina',
        'cilindrada': 1.4,
      });
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(
            _ApiClientFake(null, resultadoMotorCodigo: opcion)),
      ]);
      addTearDown(container.dispose);

      final provider = infoCodigoMotorProvider('K4J');
      final sub = container.listen(provider, (_, _) {});
      final resultado = await container.read(provider.future);
      sub.close();

      expect(resultado, isNotNull);
      expect(resultado!.combustible, TipoCombustible.gasolina);
      expect(resultado.cilindrada, 1.4);
    });

    test('devuelve la info del código de transmisión desde el backend',
        () async {
      final opcion = OpcionTransmision.fromJson({
        'codigo': 'JR5',
        'tipo': 'manual',
        'marchas': 5,
      });
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(
            _ApiClientFake(null, resultadoTransCodigo: opcion)),
      ]);
      addTearDown(container.dispose);

      final provider = infoCodigoTransmisionProvider('JR5');
      final sub = container.listen(provider, (_, _) {});
      final resultado = await container.read(provider.future);
      sub.close();

      expect(resultado, isNotNull);
      expect(resultado!.tipo, TipoTransmision.manual);
      expect(resultado.marchas, 5);
    });

    test('backend caído → null en silencio (asistente, no paso crítico)',
        () async {
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(_ApiClientFake(null,
            errorComponente: Exception('connection refused'))),
      ]);
      addTearDown(container.dispose);

      final provider = infoCodigoMotorProvider('K4J');
      final sub = container.listen(provider, (_, _) {});
      expect(await container.read(provider.future), isNull);
      sub.close();
    });
  });
}

/// ApiClient falso que devuelve un resultado fijo o lanza un error.
class _ApiClientFake extends ApiClient {
  _ApiClientFake(
    this.resultado, {
    this.error,
    this.llamada,
    this.resultadoMotorCodigo,
    this.resultadoTransCodigo,
    this.errorComponente,
    this.llamadaComponente,
  });

  final SugerenciasMotorizacion? resultado;
  final Object? error;
  final void Function()? llamada;
  final OpcionMotor? resultadoMotorCodigo;
  final OpcionTransmision? resultadoTransCodigo;
  final Object? errorComponente;
  final void Function()? llamadaComponente;

  @override
  Future<SugerenciasMotorizacion?> buscarMotorizacion({
    required String marca,
    required String modelo,
    required int anio,
    String? trim,
  }) async {
    llamada?.call();
    if (error != null) throw error!;
    return resultado;
  }

  @override
  Future<OpcionMotor?> buscarComponenteMotor(String codigo) async {
    llamadaComponente?.call();
    if (errorComponente != null) throw errorComponente!;
    return resultadoMotorCodigo;
  }

  @override
  Future<OpcionTransmision?> buscarComponenteTransmision(String codigo) async {
    llamadaComponente?.call();
    if (errorComponente != null) throw errorComponente!;
    return resultadoTransCodigo;
  }
}
