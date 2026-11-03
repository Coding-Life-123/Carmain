import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:car_main/models/enums.dart';
import 'package:car_main/models/plan_mantenimiento.dart';

void main() {
  test('Vectores de prueba de contrato estado_items.json', () {
    // Buscar el archivo relativo al directorio de ejecución o a la raíz
    var path = '../contrato/estado_items.json';
    if (!File(path).existsSync()) {
      path = 'contrato/estado_items.json';
    }
    expect(File(path).existsSync(), isTrue, reason: 'Debe existir contrato/estado_items.json');

    final jsonContent = File(path).readAsStringSync();
    final List<dynamic> vectores = jsonDecode(jsonContent);

    for (final v in vectores) {
      final desc = v['descripcion'] as String;
      final kmActual = v['kmActual'] as int;
      final tipoUso = v['tipoUso'] == 'severo' ? TipoUso.severo : TipoUso.normal;
      final intervaloKm = v['intervaloKm'] as int;
      final intervaloMeses = v['intervaloMeses'] as int?;
      final intervaloSeveroKm = v['intervaloSeveroKm'] as int?;
      final ultimaVezKm = v['ultimaVezKm'] as int?;
      final ultimaVezFecha = v['ultimaVezFecha'] != null
          ? DateTime.parse(v['ultimaVezFecha'] as String)
          : null;
      final estadoEsperado = switch (v['estadoEsperado'] as String) {
        'ok' => EstadoItem.ok,
        'proximo' => EstadoItem.proximo,
        'vencido' => EstadoItem.vencido,
        'desconocido' => EstadoItem.desconocido,
        _ => throw ArgumentError('Estado no reconocido'),
      };

      final item = ItemMantenimiento(
        id: 'vector-test',
        categoria: CategoriaMantenimiento.motor,
        descripcion: desc,
        componenteAplica: TipoComponente.motor,
        intervaloKm: intervaloKm,
        intervaloMeses: intervaloMeses,
        intervaloSeveroKm: intervaloSeveroKm,
        ultimaVezKm: ultimaVezKm,
        ultimaVezFecha: ultimaVezFecha,
      );

      final resultado = item.estado(kmActual, tipoUso);
      expect(resultado, estadoEsperado, reason: 'Falla en vector: "$desc"');
    }
  });
}

