import 'package:car_main/models/enums.dart';
import 'package:car_main/models/plan_mantenimiento.dart';
import 'package:car_main/utils/formato.dart';
import 'package:car_main/widgets/estado_plan.dart';
import 'package:flutter_test/flutter_test.dart';

ItemMantenimiento _item({
  required int intervaloKm,
  int? ultimaVezKm,
  int? intervaloSeveroKm,
  int? intervaloMeses,
  DateTime? ultimaVezFecha,
}) =>
    ItemMantenimiento(
      id: 'i-$intervaloKm-${ultimaVezKm ?? 0}',
      categoria: CategoriaMantenimiento.motor,
      descripcion: 'Aceite',
      componenteAplica: TipoComponente.motor,
      intervaloKm: intervaloKm,
      ultimaVezKm: ultimaVezKm,
      intervaloSeveroKm: intervaloSeveroKm,
      intervaloMeses: intervaloMeses,
      ultimaVezFecha: ultimaVezFecha,
    );

void main() {
  group('formato', () {
    test('formatearNumero agrupa miles con punto', () {
      expect(formatearNumero(0), '0');
      expect(formatearNumero(999), '999');
      expect(formatearNumero(1000), '1.000');
      expect(formatearNumero(125000), '125.000');
      expect(formatearNumero(1234567), '1.234.567');
      expect(formatearNumero(-4500), '-4.500');
    });

    test('formatearKm añade la unidad', () {
      expect(formatearKm(125000), '125.000 km');
    });

    test('formatearFecha rellena con ceros', () {
      expect(formatearFecha(DateTime(2026, 3, 5)), '05/03/2026');
    });
  });

  group('vencimiento dual (km y meses - lo que ocurra primero)', () {
    test('vence por tiempo aunque los km no se hayan alcanzado', () {
      final sieteMesesAtras = DateTime.now().subtract(const Duration(days: 215));
      final item = _item(
        intervaloKm: 10000,
        intervaloMeses: 6,
        ultimaVezKm: 0,
        ultimaVezFecha: sieteMesesAtras,
      );
      // Solo 2.000 km recorridos, pero pasaron 7 meses de 6 permitidos
      expect(item.estado(2000, TipoUso.normal), EstadoItem.vencido);
      expect(item.diasRestantes(tipoUso: TipoUso.normal)! < 0, isTrue);
    });

    test('vence por kilometraje aunque los meses no se hayan alcanzado', () {
      final unMesAtras = DateTime.now().subtract(const Duration(days: 30));
      final item = _item(
        intervaloKm: 10000,
        intervaloMeses: 12,
        ultimaVezKm: 0,
        ultimaVezFecha: unMesAtras,
      );
      // Pasó 1 mes, pero ya superó los 10.000 km
      expect(item.estado(10500, TipoUso.normal), EstadoItem.vencido);
    });

    test('umbral proximo se activa con <= 35 dias restantes ("mes larguito")', () {
      // 6 meses = 182.5 días. 182.5 - 160 = ~22.5 días restantes (<= 35)
      final fechaReciente = DateTime.now().subtract(const Duration(days: 160));
      final item = _item(
        intervaloKm: 20000,
        intervaloMeses: 6,
        ultimaVezKm: 0,
        ultimaVezFecha: fechaReciente,
      );
      // Km muy lejos (1.000 km de 20.000), pero faltan menos de 35 días
      expect(item.estado(1000, TipoUso.normal), EstadoItem.proximo);
    });

    test('esRecordatorioUrgente es true cuando faltan <= 15 dias', () {
      // 6 meses ~ 182.5 días. 182.5 - 173 = ~9.5 días restantes
      final fechaUrgente = DateTime.now().subtract(const Duration(days: 173));
      final itemUrgente = _item(
        intervaloKm: 20000,
        intervaloMeses: 6,
        ultimaVezKm: 0,
        ultimaVezFecha: fechaUrgente,
      );
      expect(itemUrgente.esRecordatorioUrgente(1000, TipoUso.normal), isTrue);

      final fechaHolgada = DateTime.now().subtract(const Duration(days: 100));
      final itemHolgado = _item(
        intervaloKm: 20000,
        intervaloMeses: 6,
        ultimaVezKm: 0,
        ultimaVezFecha: fechaHolgada,
      );
      expect(itemHolgado.esRecordatorioUrgente(1000, TipoUso.normal), isFalse);
    });

    test('esRecordatorioUrgente es true cuando faltan <= 300 km', () {
      final item = _item(intervaloKm: 10000, ultimaVezKm: 0);
      expect(item.esRecordatorioUrgente(9750, TipoUso.normal), isTrue); // faltan 250 km
      expect(item.esRecordatorioUrgente(9500, TipoUso.normal), isFalse); // faltan 500 km
    });

    test('progresoIntervalo toma el peor avance entre km y tiempo', () {
      // 50% de km (5.000 de 10.000), pero 90% de tiempo (164 días de 182.5)
      final fechaAvanzada = DateTime.now().subtract(const Duration(days: 164));
      final item = _item(
        intervaloKm: 10000,
        intervaloMeses: 6,
        ultimaVezKm: 0,
        ultimaVezFecha: fechaAvanzada,
      );
      final progreso = item.progresoIntervalo(5000, TipoUso.normal);
      expect(progreso > 0.8, isTrue);
    });

    test('textoEstadoDetalle muestra aviso de urgencia cuando quedan <= 15 dias', () {
      final fechaUrgente = DateTime.now().subtract(const Duration(days: 173));
      final item = _item(
        intervaloKm: 20000,
        intervaloMeses: 6,
        ultimaVezKm: 0,
        ultimaVezFecha: fechaUrgente,
      );
      final texto = textoEstadoDetalle(item, 1000, TipoUso.normal);
      expect(texto.contains('¡Quedan'), isTrue);
    });
  });

  group('progresoIntervalo', () {
    test('es proporcional al km consumido', () {
      final item = _item(intervaloKm: 10000, ultimaVezKm: 0);
      expect(item.progresoIntervalo(2500, TipoUso.normal), closeTo(0.25, 1e-9));
    });

    test('se limita a 1 cuando está vencido', () {
      final item = _item(intervaloKm: 10000, ultimaVezKm: 0);
      expect(item.progresoIntervalo(15000, TipoUso.normal), 1);
    });

    test('usa el intervalo severo si el uso es severo', () {
      final item =
          _item(intervaloKm: 10000, intervaloSeveroKm: 5000, ultimaVezKm: 0);
      expect(item.intervaloEfectivoKm(TipoUso.severo), 5000);
      expect(item.progresoIntervalo(2500, TipoUso.severo), closeTo(0.5, 1e-9));
    });
  });

  group('ResumenPlan', () {
    final plan = PlanMantenimiento(
      id: 'p',
      vehiculoId: 'v',
      version: 1,
      fechaGeneracion: DateTime(2026),
      items: [
        _item(intervaloKm: 5000, ultimaVezKm: 0), // vencido a 6000 km
        _item(intervaloKm: 6500, ultimaVezKm: 0), // próximo (500 restantes)
        _item(intervaloKm: 20000, ultimaVezKm: 0), // al día
      ],
    );

    test('cuenta cada estado y calcula el peor', () {
      final r = ResumenPlan.de(plan, 6000, TipoUso.normal);
      expect(r.vencidos, 1);
      expect(r.proximos, 1);
      expect(r.alDia, 1);
      expect(r.total, 3);
      expect(r.peor, EstadoItem.vencido);
    });

    test('plan nulo da resumen vacío y estado ok', () {
      final r = ResumenPlan.de(null, 6000, TipoUso.normal);
      expect(r.total, 0);
      expect(r.peor, EstadoItem.ok);
    });
  });

  test('textoKmRestantes distingue vencido de pendiente', () {
    expect(textoKmRestantes(1200), 'Faltan 1.200 km');
    expect(textoKmRestantes(-300), 'Vencido hace 300 km');
    expect(textoKmRestantes(0), 'Vencido hace 0 km');
  });
}

