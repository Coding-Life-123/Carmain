import '../models/enums.dart';
import '../models/plan_mantenimiento.dart';
import '../models/registro_mantenimiento.dart';
import '../models/vehiculo.dart';

/// Métricas financieras y de confianza para el pasaporte digital y detalle de vehículo.
class ResumenAnaliticaVehiculo {
  final double costoTotal;
  final double? costoPorKm;
  final double? presupuestoProximoServicio;
  final int itemsVencidosOProximos;
  final double porcentajeHistorialVerificado;
  final int totalRegistros;
  final int registrosSelladosTaller;
  final int registrosConEvidencia;

  const ResumenAnaliticaVehiculo({
    required this.costoTotal,
    this.costoPorKm,
    this.presupuestoProximoServicio,
    required this.itemsVencidosOProximos,
    required this.porcentajeHistorialVerificado,
    required this.totalRegistros,
    required this.registrosSelladosTaller,
    required this.registrosConEvidencia,
  });
}

class AnaliticaVehiculo {
  /// Calcula el resumen financiero y de confianza del vehículo.
  static ResumenAnaliticaVehiculo calcular({
    required Vehiculo vehiculo,
    required PlanMantenimiento? plan,
    required List<RegistroMantenimiento> registros,
    double? kmPorDia,
    DateTime? ahora,
  }) {
    if (registros.isEmpty) {
      final itemsCriticos = plan?.items.where((i) {
            final st = i.estado(
              vehiculo.kilometrajeActual,
              vehiculo.tipoUso,
              kmPorDia: kmPorDia,
              ahora: ahora,
            );
            return st == EstadoItem.vencido || st == EstadoItem.proximo;
          }).length ??
          0;

      return ResumenAnaliticaVehiculo(
        costoTotal: 0.0,
        costoPorKm: null,
        presupuestoProximoServicio: null,
        itemsVencidosOProximos: itemsCriticos,
        porcentajeHistorialVerificado: 0.0,
        totalRegistros: 0,
        registrosSelladosTaller: 0,
        registrosConEvidencia: 0,
      );
    }

    // 1. Costos acumulados
    double totalGasto = 0.0;
    final Map<CategoriaMantenimiento, List<double>> costosPorCategoria = {};
    final Map<String, List<double>> costosPorItem = {};

    int sellados = 0;
    int conEvidencia = 0;

    int minKm = vehiculo.kilometrajeActual;
    int maxKm = vehiculo.kilometrajeActual;

    for (final reg in registros) {
      if (reg.kilometraje < minKm) minKm = reg.kilometraje;
      if (reg.kilometraje > maxKm) maxKm = reg.kilometraje;

      if (reg.nivelVerificacion == NivelVerificacionHistorial.selladoTaller) {
        sellados++;
      } else if (reg.nivelVerificacion == NivelVerificacionHistorial.conEvidencia) {
        conEvidencia++;
      }

      if (reg.costo != null && reg.costo! > 0) {
        totalGasto += reg.costo!;
        final costoRepartido = reg.itemsRealizados.isNotEmpty
            ? reg.costo! / reg.itemsRealizados.length
            : reg.costo!;

        for (final item in reg.itemsRealizados) {
          costosPorCategoria
              .putIfAbsent(item.categoria, () => [])
              .add(costoRepartido);
          if (item.itemId != null) {
            costosPorItem
                .putIfAbsent(item.itemId!, () => [])
                .add(costoRepartido);
          }
        }
      }
    }

    // 2. Costo por km ($/km)
    double? costoPorKm;
    final deltaKm = maxKm - minKm;
    if (deltaKm >= 500 && totalGasto > 0) {
      costoPorKm = double.parse((totalGasto / deltaKm).toStringAsFixed(3));
    } else if (vehiculo.kilometrajeActual > 1000 && totalGasto > 0) {
      costoPorKm = double.parse((totalGasto / vehiculo.kilometrajeActual).toStringAsFixed(3));
    }

    // 3. Presupuesto estimado del próximo servicio
    double? presupuestoEstimado;
    int itemsCriticosCount = 0;

    if (plan != null) {
      final itemsProximosOVencidos = plan.items.where((i) {
        final st = i.estado(
          vehiculo.kilometrajeActual,
          vehiculo.tipoUso,
          kmPorDia: kmPorDia,
          ahora: ahora,
        );
        return st == EstadoItem.vencido || st == EstadoItem.proximo;
      }).toList();

      itemsCriticosCount = itemsProximosOVencidos.length;

      if (itemsProximosOVencidos.isNotEmpty) {
        double sumaEstimada = 0.0;
        int itemsConEstimacion = 0;

        for (final item in itemsProximosOVencidos) {
          if (costosPorItem.containsKey(item.id)) {
            final historial = costosPorItem[item.id]!;
            final promedio = historial.reduce((a, b) => a + b) / historial.length;
            sumaEstimada += promedio;
            itemsConEstimacion++;
          } else if (costosPorCategoria.containsKey(item.categoria)) {
            final historial = costosPorCategoria[item.categoria]!;
            final promedio = historial.reduce((a, b) => a + b) / historial.length;
            sumaEstimada += promedio;
            itemsConEstimacion++;
          }
        }

        if (itemsConEstimacion > 0) {
          presupuestoEstimado = double.parse(sumaEstimada.toStringAsFixed(2));
        }
      }
    }

    // 4. Porcentaje verificado
    final verificadoTotal = sellados + conEvidencia;
    final pctVerificado = (verificadoTotal / registros.length) * 100.0;

    return ResumenAnaliticaVehiculo(
      costoTotal: double.parse(totalGasto.toStringAsFixed(2)),
      costoPorKm: costoPorKm,
      presupuestoProximoServicio: presupuestoEstimado,
      itemsVencidosOProximos: itemsCriticosCount,
      porcentajeHistorialVerificado: double.parse(pctVerificado.toStringAsFixed(1)),
      totalRegistros: registros.length,
      registrosSelladosTaller: sellados,
      registrosConEvidencia: conEvidencia,
    );
  }
}

