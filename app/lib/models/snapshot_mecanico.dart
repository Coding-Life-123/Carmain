import '../models/plan_mantenimiento.dart';
import '../models/registro_mantenimiento.dart';
import '../models/vehiculo.dart';
import '../utils/formato.dart';

/// Generador del snapshot serializable según el contrato `SnapshotV1`.
class SnapshotMecanico {
  static Map<String, dynamic> generar({
    required Vehiculo vehiculo,
    required PlanMantenimiento? plan,
    required List<RegistroMantenimiento> registros,
    bool incluirVin = false,
    bool incluirNotasUso = false,
    bool incluirHistorial = true,
  }) {
    final motor = vehiculo.motor;
    final transmision = vehiculo.transmision;

    return {
      'schema': 1,
      'generadoEn': DateTime.now().toUtc().toIso8601String(),
      'vehiculo': {
        'marca': vehiculo.marca,
        'modelo': vehiculo.modelo,
        'anio': vehiculo.anio,
        'trim': vehiculo.trim,
        'placa': vehiculo.placa,
        'vin': incluirVin ? vehiculo.vin : null,
        'drivetrain': vehiculo.drivetrain.name.toUpperCase(),
        'kilometrajeActual': vehiculo.kilometrajeActual,
        'tipoUso': vehiculo.tipoUso.name,
        'notasUso': incluirNotasUso ? vehiculo.notasUso : null,
        'motor': {
          'codigo': motor.codigo,
          'esSwap': !motor.esOriginal,
          'original': motor.originalCodigo,
          'combustible': motor.tipoCombustible.name,
          'cilindrada': motor.cilindrada,
          'cilindros': motor.cilindros,
          'aspiracion': motor.aspiracion,
          'potenciaHp': motor.potenciaHp,
          'torqueNm': motor.torqueNm,
        },
        'transmision': {
          'codigo': transmision.codigo,
          'esSwap': !transmision.esOriginal,
          'original': transmision.originalCodigo,
          'tipo': transmision.tipo.name,
          'marchas': transmision.marchas,
        },
        'componentesExtra': vehiculo.componentesExtra.map((c) => {
          'tipo': c.tipo.name,
          'codigo': c.codigo,
          'esSwap': !c.esOriginal,
          'original': c.originalCodigo,
          'descripcion': c.descripcion,
        }).toList(),
      },
      'plan': {
        'version': plan?.version ?? 1,
        'items': (plan?.items ?? []).map((item) => {
          'id': item.id,
          'categoria': item.categoria.name,
          'descripcion': item.descripcion,
          'componenteAplica': item.componenteAplica.name,
          'intervaloKm': item.intervaloKm,
          'intervaloMeses': item.intervaloMeses,
          'intervaloSeveroKm': item.intervaloSeveroKm,
          'ultimaVezKm': item.ultimaVezKm,
          'ultimaVezFecha': item.ultimaVezFecha != null
              ? formatearFecha(item.ultimaVezFecha!)
              : null,
          'fuente': item.fuente.name,
          'confianza': item.confianza.name,
          'esVigilanciaSwap': item.esVigilanciaSwap,
        }).toList(),
        'alertasIngenieria': (plan?.alertasIngenieria ?? []).map((alerta) => {
          'id': alerta.id,
          'vector': alerta.vector.name,
          'severidad': alerta.severidad.name,
          'componenteAfectado': alerta.componenteAfectado,
          'titulo': alerta.titulo,
          'diagnostico': alerta.diagnostico,
          'recomendacionUpgrade': alerta.recomendacionUpgrade,
        }).toList(),
      },
      'historial': incluirHistorial
          ? registros.map((reg) => {
              'id': reg.id,
              'fecha': formatearFecha(reg.fecha),
              'kilometraje': reg.kilometraje,
              'items': reg.itemsRealizados.map((item) => {
                'categoria': item.categoria.name,
                'descripcion': item.descripcion,
                'componenteAplica': item.componenteAplica.name,
              }).toList(),
              'costo': reg.costo,
              'moneda': reg.moneda,
              'taller': reg.taller,
              'nivelVerificacion': reg.nivelVerificacion.name,
              'evidencia': reg.evidencia.length,
            }).toList()
          : <Map<String, dynamic>>[],
    };
  }
}
