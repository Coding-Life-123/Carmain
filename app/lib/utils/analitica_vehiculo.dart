import '../models/enums.dart';
import '../models/plan_mantenimiento.dart';
import '../models/registro_mantenimiento.dart';
import '../models/vehiculo.dart';

/// Segmentos de vehículos para estimación de costos de mantenimiento en Colombia.
enum SegmentoVehiculo {
  pesadoHeavyDuty,
  pickup4x4Grande,
  premiumDeportivo,
  suvMedianaSedan,
  compactoEconomico,
  electrico,
}

/// Parámetros de costo base y distancias de referencia por segmento.
class EstimacionSegmento {
  final SegmentoVehiculo segmento;
  final String nombreSegmento;
  final double costoAnualNormal;
  final double costoAnualSevero;
  final double kmReferenciaNormal;
  final double kmReferenciaSevero;

  const EstimacionSegmento({
    required this.segmento,
    required this.nombreSegmento,
    required this.costoAnualNormal,
    required this.costoAnualSevero,
    this.kmReferenciaNormal = 12000.0,
    this.kmReferenciaSevero = 15000.0,
  });

  double costoBase(bool esSevero) =>
      esSevero ? costoAnualSevero : costoAnualNormal;

  double kmReferencia(bool esSevero) =>
      esSevero ? kmReferenciaSevero : kmReferenciaNormal;
}

/// Métricas financieras y de confianza para el pasaporte digital y detalle de vehículo.
class ResumenAnaliticaVehiculo {
  final double costoTotal;
  final double? costoPorKm;
  final double? presupuestoProximoServicio;
  final double? costoAnualEstimado;
  final bool esEstimadoSegunUso;
  final String? explicacionCostoAnual;
  final SegmentoVehiculo? segmentoVehiculo;
  final int itemsVencidosOProximos;
  final double porcentajeHistorialVerificado;
  final int totalRegistros;
  final int registrosSelladosTaller;
  final int registrosConEvidencia;

  const ResumenAnaliticaVehiculo({
    required this.costoTotal,
    this.costoPorKm,
    this.presupuestoProximoServicio,
    this.costoAnualEstimado,
    this.esEstimadoSegunUso = false,
    this.explicacionCostoAnual,
    this.segmentoVehiculo,
    required this.itemsVencidosOProximos,
    required this.porcentajeHistorialVerificado,
    required this.totalRegistros,
    required this.registrosSelladosTaller,
    required this.registrosConEvidencia,
  });
}

class AnaliticaVehiculo {
  static String _formatearKm(int km) {
    final s = km.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return s.replaceAllMapped(reg, (m) => '${m[1]}.');
  }

  /// Clasifica el vehículo en un segmento automotriz para estimar costos de mantenimiento
  /// realistas para Colombia (en COP).
  static EstimacionSegmento clasificarVehiculo(Vehiculo vehiculo) {
    final marca = vehiculo.marca.toLowerCase().trim();
    final modelo = vehiculo.modelo.toLowerCase().trim();
    final trim = (vehiculo.trim ?? '').toLowerCase().trim();
    final motorDesc = (vehiculo.motor.descripcion ?? '').toLowerCase().trim();
    final combustible = vehiculo.motor.tipoCombustible;
    final cilindrada = vehiculo.motor.cilindrada ?? 0.0;
    final cilindros = vehiculo.motor.cilindros ?? 0;
    final potencia = vehiculo.motor.potenciaHp ?? 0;
    final drivetrain = vehiculo.drivetrain;

    final texto = '$marca $modelo $trim $motorDesc';
    final norm = texto.replaceAll(RegExp(r'[\s\-_]+'), '');

    // 1. Detección Heavy Duty / Comercial Pesado / Camiones / Gran Cilindrada
    // Ejemplos: Ford F-450, F-350, F-250, F-550 Super Duty; Silverado/Sierra 2500/3500 HD;
    // RAM 2500/3500/4500/5500; NPR, NQR, NKR, NHR, Hino, Fuso Canter, Kenworth, Mack, etc.
    final esFordSuperDuty = norm.contains('f450') ||
        norm.contains('f350') ||
        norm.contains('f250') ||
        norm.contains('f550') ||
        norm.contains('superduty');

    final esChevyGmcHd = (norm.contains('silverado') || norm.contains('sierra')) &&
        (norm.contains('2500') || norm.contains('3500') || norm.contains('hd')) ||
        norm.contains('kodiak') ||
        norm.contains('topkick');

    final esRamHd = (marca.contains('ram') || marca.contains('dodge') || norm.contains('ram')) &&
        (norm.contains('2500') ||
            norm.contains('3500') ||
            norm.contains('4500') ||
            norm.contains('5500') ||
            norm.contains('powerwagon'));

    final esCamionComercial = norm.contains('npr') ||
        norm.contains('nqr') ||
        norm.contains('nhr') ||
        norm.contains('nkr') ||
        norm.contains('hino') ||
        norm.contains('fusocanter') ||
        norm.contains('canter') ||
        norm.contains('kenworth') ||
        norm.contains('freightliner') ||
        norm.contains('international') ||
        norm.contains('mack') ||
        norm.contains('aumark') ||
        norm.contains('dutro');

    final esMotorPesado = cilindrada >= 5.8 ||
        (combustible == TipoCombustible.diesel && (cilindrada >= 5.0 || cilindros >= 8)) ||
        (combustible == TipoCombustible.diesel && potencia >= 330);

    if (esFordSuperDuty || esChevyGmcHd || esRamHd || esCamionComercial || esMotorPesado) {
      return const EstimacionSegmento(
        segmento: SegmentoVehiculo.pesadoHeavyDuty,
        nombreSegmento: 'Heavy Duty / Comercial Pesado',
        costoAnualNormal: 9500000.0,
        costoAnualSevero: 14500000.0,
      );
    }

    // 2. 100% Eléctricos (EV)
    if (combustible == TipoCombustible.electrico) {
      final esPremiumEv = marca.contains('tesla') ||
          marca.contains('porsche') ||
          marca.contains('bmw') ||
          marca.contains('audi') ||
          marca.contains('mercedes') ||
          marca.contains('volvo');
      if (esPremiumEv) {
        return const EstimacionSegmento(
          segmento: SegmentoVehiculo.electrico,
          nombreSegmento: 'Eléctrico Premium',
          costoAnualNormal: 2200000.0,
          costoAnualSevero: 3200000.0,
        );
      }
      return const EstimacionSegmento(
        segmento: SegmentoVehiculo.electrico,
        nombreSegmento: '100% Eléctrico',
        costoAnualNormal: 950000.0,
        costoAnualSevero: 1400000.0,
      );
    }

    // 3. Pick-ups Medianas, Camionetas 4x4 y SUVs Grandes
    final esPickupO4x4Conocida = norm.contains('hilux') ||
        norm.contains('fortuner') ||
        norm.contains('prado') ||
        norm.contains('landcruiser') ||
        norm.contains('4runner') ||
        norm.contains('fjcruiser') ||
        norm.contains('tundra') ||
        norm.contains('tacoma') ||
        norm.contains('sequoia') ||
        norm.contains('ranger') ||
        norm.contains('f150') ||
        norm.contains('raptor') ||
        norm.contains('expedition') ||
        norm.contains('explorer') ||
        norm.contains('dmax') ||
        norm.contains('colorado') ||
        norm.contains('trailblazer') ||
        norm.contains('tahoe') ||
        norm.contains('suburban') ||
        norm.contains('s10') ||
        norm.contains('frontier') ||
        norm.contains('navara') ||
        norm.contains('patrol') ||
        norm.contains('pathfinder') ||
        norm.contains('titan') ||
        norm.contains('montero') ||
        norm.contains('l200') ||
        norm.contains('sportero') ||
        norm.contains('nativa') ||
        norm.contains('amarok') ||
        norm.contains('touareg') ||
        norm.contains('wrangler') ||
        norm.contains('gladiator') ||
        norm.contains('grandcherokee') ||
        norm.contains('rubicon');

    final es4x4ODieselGrande = drivetrain == Drivetrain.fourWd ||
        (combustible == TipoCombustible.diesel && cilindrada >= 2.0) ||
        cilindrada >= 3.5;

    if (esPickupO4x4Conocida || es4x4ODieselGrande) {
      final baseNormal = combustible == TipoCombustible.hibrido ? 4600000.0 * 0.85 : 4600000.0;
      final baseSevero = combustible == TipoCombustible.hibrido ? 6900000.0 * 0.85 : 6900000.0;
      return EstimacionSegmento(
        segmento: SegmentoVehiculo.pickup4x4Grande,
        nombreSegmento: combustible == TipoCombustible.hibrido
            ? 'Híbrido (Pick-up / 4x4)'
            : 'Pick-up / Camioneta 4x4',
        costoAnualNormal: baseNormal,
        costoAnualSevero: baseSevero,
      );
    }

    // 4. Gama Alta / Marcas Premium / Deportivos de Alto Rendimiento
    final esMarcaPremium = marca.contains('bmw') ||
        marca.contains('mercedes') ||
        marca.contains('audi') ||
        marca.contains('porsche') ||
        marca.contains('land rover') ||
        marca.contains('range rover') ||
        marca.contains('jaguar') ||
        marca.contains('volvo') ||
        marca.contains('lexus') ||
        marca.contains('maserati') ||
        marca.contains('ferrari') ||
        marca.contains('lamborghini') ||
        marca.contains('alfa romeo');

    final esDeportivoAlto = norm.contains('corvette') ||
        norm.contains('shelby') ||
        (norm.contains('mustang') && (norm.contains('gt') || cilindrada >= 4.6)) ||
        (norm.contains('camaro') && (norm.contains('ss') || cilindrada >= 6.0)) ||
        (norm.contains('supra') && cilindrada >= 2.9) ||
        norm.contains('gtr');

    if (esMarcaPremium || esDeportivoAlto) {
      final baseNormal = combustible == TipoCombustible.hibrido ? 5800000.0 * 0.85 : 5800000.0;
      final baseSevero = combustible == TipoCombustible.hibrido ? 8900000.0 * 0.85 : 8900000.0;
      return EstimacionSegmento(
        segmento: SegmentoVehiculo.premiumDeportivo,
        nombreSegmento: combustible == TipoCombustible.hibrido
            ? 'Híbrido (Gama Alta / Premium)'
            : 'Gama Alta / Premium',
        costoAnualNormal: baseNormal,
        costoAnualSevero: baseSevero,
      );
    }

    // 5. SUV Mediana / Crossover / Sedán Mediano
    final esSuvSedanMediano = norm.contains('corolla') ||
        norm.contains('civic') ||
        norm.contains('mazda3') ||
        norm.contains('cx30') ||
        norm.contains('cx5') ||
        norm.contains('cx50') ||
        norm.contains('duster') ||
        norm.contains('captur') ||
        norm.contains('oroch') ||
        norm.contains('tracker') ||
        norm.contains('captiva') ||
        norm.contains('kicks') ||
        norm.contains('qashqai') ||
        norm.contains('xtrail') ||
        norm.contains('sentra') ||
        norm.contains('versa') ||
        norm.contains('tucson') ||
        norm.contains('creta') ||
        norm.contains('sportage') ||
        norm.contains('seltos') ||
        norm.contains('jetta') ||
        norm.contains('taos') ||
        norm.contains('tcross') ||
        norm.contains('nivus') ||
        norm.contains('ecosport') ||
        norm.contains('escape') ||
        norm.contains('crv') ||
        norm.contains('hrv') ||
        norm.contains('forester') ||
        norm.contains('crosstrek') ||
        norm.contains('compass') ||
        norm.contains('renegade') ||
        norm.contains('asx') ||
        norm.contains('outlander') ||
        norm.contains('koleos') ||
        (cilindrada >= 1.6 && cilindrada <= 2.5);

    if (esSuvSedanMediano) {
      final baseNormal = combustible == TipoCombustible.hibrido ? 2500000.0 * 0.85 : 2500000.0;
      final baseSevero = combustible == TipoCombustible.hibrido ? 3700000.0 * 0.85 : 3700000.0;
      return EstimacionSegmento(
        segmento: SegmentoVehiculo.suvMedianaSedan,
        nombreSegmento: combustible == TipoCombustible.hibrido
            ? 'Híbrido (SUV / Sedán)'
            : 'SUV Mediana / Sedán',
        costoAnualNormal: baseNormal,
        costoAnualSevero: baseSevero,
      );
    }

    // 6. Compacto Urbano / Económico
    final baseNormal = combustible == TipoCombustible.hibrido ? 1300000.0 * 0.85 : 1300000.0;
    final baseSevero = combustible == TipoCombustible.hibrido ? 1900000.0 * 0.85 : 1900000.0;
    return EstimacionSegmento(
      segmento: SegmentoVehiculo.compactoEconomico,
      nombreSegmento: combustible == TipoCombustible.hibrido
          ? 'Híbrido (Compacto Urbano)'
          : 'Compacto Urbano',
      costoAnualNormal: baseNormal,
      costoAnualSevero: baseSevero,
    );
  }

  /// Calcula el resumen financiero y de confianza del vehículo.
  static ResumenAnaliticaVehiculo calcular({
    required Vehiculo vehiculo,
    required PlanMantenimiento? plan,
    required List<RegistroMantenimiento> registros,
    double? kmPorDia,
    DateTime? ahora,
  }) {
    final esSevero = vehiculo.tipoUso == TipoUso.severo;
    final estimacion = clasificarVehiculo(vehiculo);
    final double costoAnualBase = estimacion.costoBase(esSevero);
    final double kmReferencia = estimacion.kmReferencia(esSevero);

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

      double costoAnualEstimado;
      String explicacion;
      if (kmPorDia != null && kmPorDia > 0) {
        final kmAnualReal = kmPorDia * 365.25;
        costoAnualEstimado =
            ((costoAnualBase / kmReferencia) * kmAnualReal).roundToDouble();
        explicacion =
            "estimado para uso ${esSevero ? 'severo' : 'normal'} (~${_formatearKm(kmReferencia.toInt())} km/año)";
      } else {
        costoAnualEstimado = costoAnualBase;
        explicacion =
            "estimado para uso ${esSevero ? 'severo' : 'normal'} (~${_formatearKm(kmReferencia.toInt())} km/año)";
      }

      return ResumenAnaliticaVehiculo(
        costoTotal: 0.0,
        costoPorKm: null,
        presupuestoProximoServicio: null,
        costoAnualEstimado: costoAnualEstimado,
        esEstimadoSegunUso: true,
        explicacionCostoAnual: explicacion,
        segmentoVehiculo: estimacion.segmento,
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

    // 3. Estimado de costo anual
    double costoAnualEstimado;
    bool esEstimadoSegunUso = false;
    String explicacionCostoAnual;

    final kmAnual = (kmPorDia != null && kmPorDia > 0)
        ? (kmPorDia * 365.25)
        : (esSevero ? kmReferencia : kmReferencia);

    if (costoPorKm != null && costoPorKm > 0) {
      costoAnualEstimado = (costoPorKm * kmAnual).roundToDouble();
      explicacionCostoAnual = kmPorDia != null
          ? 'proyectado según tus gastos y ritmo de ~${kmPorDia.toStringAsFixed(0)} km/día'
          : 'proyectado con tus gastos a ~${_formatearKm(kmAnual.toInt())} km/año';
    } else {
      // Sin costo por km todavía (gastos sin registrar o delta < 500 km)
      costoAnualEstimado =
          ((costoAnualBase / kmReferencia) * kmAnual).roundToDouble();
      esEstimadoSegunUso = true;
      explicacionCostoAnual = kmPorDia != null
          ? 'estimado a un ritmo de ~${kmPorDia.toStringAsFixed(0)} km/día'
          : "estimado para uso ${esSevero ? 'severo' : 'normal'} (~${_formatearKm(kmReferencia.toInt())} km/año)";
    }

    // 4. Presupuesto estimado del próximo servicio
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

    // 5. Porcentaje verificado
    final verificadoTotal = sellados + conEvidencia;
    final pctVerificado = (verificadoTotal / registros.length) * 100.0;

    return ResumenAnaliticaVehiculo(
      costoTotal: double.parse(totalGasto.toStringAsFixed(2)),
      costoPorKm: costoPorKm,
      presupuestoProximoServicio: presupuestoEstimado,
      costoAnualEstimado: costoAnualEstimado,
      esEstimadoSegunUso: esEstimadoSegunUso,
      explicacionCostoAnual: explicacionCostoAnual,
      segmentoVehiculo: estimacion.segmento,
      itemsVencidosOProximos: itemsCriticosCount,
      porcentajeHistorialVerificado: double.parse(pctVerificado.toStringAsFixed(1)),
      totalRegistros: registros.length,
      registrosSelladosTaller: sellados,
      registrosConEvidencia: conEvidencia,
    );
  }
}
