import 'package:flutter_test/flutter_test.dart';

import 'package:car_main/models/enums.dart';
import 'package:car_main/services/plan_parser.dart';

/// Fixture que replica exactamente la forma que emite el backend Go
/// (`shared.RespuestaPlan.plan`): indexado por configuración, **sin**
/// `vehiculoId`, con `config` incluido y `intervaloMeses` omitido cuando
/// no aplica (omitempty en los `*int`).
Map<String, dynamic> _respuestaGo() => {
      'id': 'b7f3c2a1-0000-4a2b-9c3d-000000000001',
      'config': {
        'marca': 'Toyota',
        'modelo': 'Supra',
        'anio': 1997,
        'trim': '',
        'drivetrain': 'RWD',
        'motorCodigo': '2JZ-GTE',
        'transCodigo': 'R154',
      },
      'version': 1,
      'fechaGeneracion': '2026-10-18T23:20:00.123456789-06:00',
      'items': [
        {
          'id': 'aceite-motor',
          'categoria': 'motor',
          'descripcion': 'Cambio de aceite de motor y filtro',
          'componenteAplica': 'motor',
          'intervaloKm': 10000,
          'intervaloMeses': 12,
          'intervaloSeveroKm': 5000,
          'fuente': 'ia',
          'confianza': 'alta',
        },
        {
          'id': 'transfer-case',
          'categoria': 'diferencial',
          'descripcion': 'Cambio de fluido de transfer case',
          'componenteAplica': 'transferCase',
          'intervaloKm': 60000,
          'fuente': 'ia',
          'confianza': 'media',
        },
      ],
    };

void main() {
  test('parsea una respuesta fiel del servidor Go inyectando vehiculoId', () {
    final plan = parsearPlanDelServidor(_respuestaGo(), vehiculoId: 'v-123');

    expect(plan, isNotNull);
    expect(plan!.id, 'b7f3c2a1-0000-4a2b-9c3d-000000000001');
    expect(plan.vehiculoId, 'v-123');
    expect(plan.version, 1);
    expect(plan.items, hasLength(2));

    final aceite = plan.items.first;
    expect(aceite.categoria, CategoriaMantenimiento.motor);
    expect(aceite.componenteAplica, TipoComponente.motor);
    expect(aceite.fuente, FuentePlan.iaInferida); // 'ia' en el wire
    expect(aceite.confianza, NivelConfianza.alta);
    expect(aceite.intervaloMeses, 12);
    expect(aceite.intervaloSeveroKm, 5000);

    final transfer = plan.items[1];
    expect(transfer.categoria, CategoriaMantenimiento.diferencial);
    expect(transfer.componenteAplica, TipoComponente.transferCase);
    expect(transfer.intervaloMeses, isNull); // omitido por omitempty
  });

  test('rescata valores fuera de vocabulario en vez de tumbar el plan', () {
    final data = _respuestaGo();
    (data['items'] as List)[0] = {
      'id': 'item-raro',
      'categoria': 'fluidos', // retirado del vocabulario
      'descripcion': 'Líquido de frenos',
      'componenteAplica': 'sistema-enfriamiento', // free-form del servidor viejo
      'intervaloKm': 40000,
      'fuente': 'IA-generada', // fuera de vocabulario
      'confianza': 'media',
    };

    final plan = parsearPlanDelServidor(data, vehiculoId: 'v-123');

    expect(plan, isNotNull);
    final item = plan!.items.first;
    expect(item.categoria, CategoriaMantenimiento.inspeccion);
    expect(item.componenteAplica, TipoComponente.otro);
    expect(item.fuente, FuentePlan.iaInferida);
    expect(item.confianza, NivelConfianza.media);
    // El segundo item del fixture sobrevive intacto.
    expect(plan.items, hasLength(2));
  });

  test('descarta items irrecuperables', () {
    final data = _respuestaGo();
    // Se reemplaza la lista completa: la original tiene tipo runtime
    // List<Map<String, Object>> y no acepta elementos heterogéneos.
    data['items'] = [
      ...(data['items'] as List),
      {
        'id': 'sin-km',
        'categoria': 'motor',
        'descripcion': 'x',
        'componenteAplica': 'motor',
        'intervaloKm': '10000 km', // string, no numérico
      },
      {
        'id': 'sin-desc',
        'categoria': 'motor',
        'descripcion': '', // vacía
        'componenteAplica': 'motor',
        'intervaloKm': 100,
      },
      'no-soy-un-mapa',
    ];

    final plan = parsearPlanDelServidor(data, vehiculoId: 'v-123');

    // Solo sobreviven los dos items buenos del fixture.
    expect(plan!.items, hasLength(2));
    expect(plan.items.map((i) => i.id), containsAll(['aceite-motor', 'transfer-case']));
  });

  test('retorna null si ningún item sobrevive', () {
    final data = _respuestaGo();
    data['items'] = [
      {
        'id': 'malo',
        'categoria': 'motor',
        'descripcion': 'x',
        'componenteAplica': 'motor',
        // sin intervaloKm
      },
    ];

    expect(parsearPlanDelServidor(data, vehiculoId: 'v-123'), isNull);
  });

  test('rescata plan con id, versión o fecha dañados', () {
    final data = _respuestaGo();
    data['id'] = '';
    data['version'] = 'uno';
    data['fechaGeneracion'] = 'no-fecha';

    final plan = parsearPlanDelServidor(data, vehiculoId: 'v-123');

    expect(plan, isNotNull);
    expect(plan!.id, isNotEmpty); // uuid generado
    expect(plan.version, 1);
    expect(plan.fechaGeneracion, isNotNull);
  });

  test('parsea alertasIngenieria y esVigilanciaSwap correctamente', () {
    final data = _respuestaGo();
    data['items'] = [
      {
        'id': 'swap-tapon',
        'categoria': 'transmision',
        'descripcion': 'Inspección de tapón magnético',
        'componenteAplica': 'transmision',
        'intervaloKm': 15000,
        'esVigilanciaSwap': true,
        'fuente': 'ia',
        'confianza': 'alta',
      },
    ];
    data['alertasIngenieria'] = [
      {
        'id': 'alerta-diff',
        'vector': 'torqueDiferencial',
        'severidad': 'alta',
        'componenteAfectado': 'Diferencial y Semiejes',
        'titulo': 'Sobrecarga de par torsional',
        'diagnostico': 'El torque supera la capacidad OEM del diferencial.',
        'recomendacionUpgrade': 'Instalar diferencial LSD reforzado.',
      },
    ];

    final plan = parsearPlanDelServidor(data, vehiculoId: 'v-123');
    expect(plan, isNotNull);
    expect(plan!.items.first.esVigilanciaSwap, isTrue);
    expect(plan.alertasIngenieria, hasLength(1));

    final alerta = plan.alertasIngenieria.first;
    expect(alerta.vector, VectorEstresSwap.torqueDiferencial);
    expect(alerta.severidad, SeveridadIngenieria.alta);
    expect(alerta.componenteAfectado, 'Diferencial y Semiejes');
    expect(alerta.titulo, 'Sobrecarga de par torsional');
    expect(alerta.recomendacionUpgrade, 'Instalar diferencial LSD reforzado.');
  });
}
