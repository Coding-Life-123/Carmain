import 'package:flutter_test/flutter_test.dart';
import 'package:car_main/models/enums.dart';
import 'package:car_main/models/plan_mantenimiento.dart';
import 'package:car_main/widgets/estado_plan.dart';

void main() {
  group('EstadoItem y PlanMantenimiento - Fase 0b', () {
    test('retorna desconocido si kmActual > 0 y no hay registro previo', () {
      final item = ItemMantenimiento(
        id: 'aceite',
        categoria: CategoriaMantenimiento.motor,
        descripcion: 'Cambio de aceite y filtro',
        componenteAplica: TipoComponente.motor,
        intervaloKm: 5000,
        intervaloMeses: 6,
        ultimaVezKm: null,
        ultimaVezFecha: null,
      );

      expect(item.estado(50000, TipoUso.normal), EstadoItem.desconocido);
      expect(item.esRecordatorioUrgente(50000, TipoUso.normal), isFalse);
    });

    test('retorna ok si kmActual == 0 aunque no haya registro previo', () {
      final item = ItemMantenimiento(
        id: 'aceite',
        categoria: CategoriaMantenimiento.motor,
        descripcion: 'Cambio de aceite y filtro',
        componenteAplica: TipoComponente.motor,
        intervaloKm: 5000,
        intervaloMeses: 6,
        ultimaVezKm: null,
        ultimaVezFecha: null,
      );

      expect(item.estado(0, TipoUso.normal), EstadoItem.ok);
    });

    test('retorna ok / proximo / vencido cuando hay registro previo', () {
      final item = ItemMantenimiento(
        id: 'aceite',
        categoria: CategoriaMantenimiento.motor,
        descripcion: 'Cambio de aceite y filtro',
        componenteAplica: TipoComponente.motor,
        intervaloKm: 10000,
        intervaloMeses: 12,
        ultimaVezKm: 40000,
        ultimaVezFecha: DateTime(2026, 1, 1),
      );

      // A los 45.000 km (recorridos 5.000 de 10.000) -> OK
      expect(item.estado(45000, TipoUso.normal), EstadoItem.ok);

      // A los 49.000 km (restan 1.000 km <= umbral 1200 km) -> Próximo
      expect(item.estado(49000, TipoUso.normal), EstadoItem.proximo);

      // A los 50.500 km -> Vencido
      expect(item.estado(50500, TipoUso.normal), EstadoItem.vencido);
    });

    test('ResumenPlan contabiliza desconocidos correctamente', () {
      final plan = PlanMantenimiento(
        id: 'p1',
        vehiculoId: 'v1',
        version: 1,
        fechaGeneracion: DateTime(2026, 1, 1),
        items: const [
          ItemMantenimiento(
            id: '1',
            categoria: CategoriaMantenimiento.motor,
            descripcion: 'Aceite',
            componenteAplica: TipoComponente.motor,
            intervaloKm: 5000,
            ultimaVezKm: null,
          ),
          ItemMantenimiento(
            id: '2',
            categoria: CategoriaMantenimiento.frenos,
            descripcion: 'Pastillas',
            componenteAplica: TipoComponente.frenos,
            intervaloKm: 20000,
            ultimaVezKm: 10000,
          ),
        ],
      );

      final resumen = ResumenPlan.de(plan, 15000, TipoUso.normal);
      expect(resumen.total, 2);
      expect(resumen.desconocidos, 1);
      expect(resumen.alDia, 1);
      expect(resumen.vencidos, 0);
      expect(resumen.proximos, 0);
    });
  });
}
