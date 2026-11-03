import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';

part 'plan_mantenimiento.freezed.dart';
part 'plan_mantenimiento.g.dart';

/// Un ítem individual del plan de mantenimiento preventivo.
@freezed
abstract class ItemMantenimiento with _$ItemMantenimiento {
  const factory ItemMantenimiento({
    required String id,
    required CategoriaMantenimiento categoria,
    required String descripcion,
    required TipoComponente componenteAplica,
    required int intervaloKm,
    int? intervaloMeses,
    int? intervaloSeveroKm,
    int? ultimaVezKm,
    DateTime? ultimaVezFecha,
    @Default(FuentePlan.iaInferida) FuentePlan fuente,
    @Default(NivelConfianza.media) NivelConfianza confianza,
    @Default(false) bool esVigilanciaSwap,
  }) = _ItemMantenimiento;

  factory ItemMantenimiento.fromJson(Map<String, dynamic> json) =>
      _$ItemMantenimientoFromJson(json);
}

/// Alerta de ingeniería sobre puntos frágiles y cuellos de botella en swaps.
@freezed
abstract class AlertaIngenieria with _$AlertaIngenieria {
  const factory AlertaIngenieria({
    required String id,
    required VectorEstresSwap vector,
    required SeveridadIngenieria severidad,
    required String componenteAfectado,
    required String titulo,
    required String diagnostico,
    String? recomendacionUpgrade,
  }) = _AlertaIngenieria;

  factory AlertaIngenieria.fromJson(Map<String, dynamic> json) =>
      _$AlertaIngenieriaFromJson(json);
}

/// Plan de mantenimiento completo de un vehículo.
@freezed
abstract class PlanMantenimiento with _$PlanMantenimiento {
  const factory PlanMantenimiento({
    required String id,
    required String vehiculoId,
    required int version,
    required DateTime fechaGeneracion,
    @Default([]) List<ItemMantenimiento> items,
    @Default([]) List<AlertaIngenieria> alertasIngenieria,
  }) = _PlanMantenimiento;

  factory PlanMantenimiento.fromJson(Map<String, dynamic> json) =>
      _$PlanMantenimientoFromJson(json);
}

/// Estado calculado de un ítem respecto al kilometraje actual.
enum EstadoItem { vencido, proximo, ok, desconocido }

/// Suma meses a una fecha asegurando que el día no desborde al mes siguiente
/// (ej. 31 de enero + 1 mes -> 28 o 29 de febrero, no 3 de marzo).
DateTime _sumarMeses(DateTime fecha, int meses) {
  final nuevoMesTotal = fecha.month + meses;
  final nuevoAnio = fecha.year + ((nuevoMesTotal - 1) ~/ 12);
  final mesNormalizado = ((nuevoMesTotal - 1) % 12) + 1;
  final diasEnMes = DateTime(nuevoAnio, mesNormalizado + 1, 0).day;
  final diaNormalizado = fecha.day > diasEnMes ? diasEnMes : fecha.day;
  return DateTime(nuevoAnio, mesNormalizado, diaNormalizado);
}

/// Extensión con cálculos de próximo mantenimiento por distancia y tiempo.
extension ItemMantenimientoX on ItemMantenimiento {
  /// Intervalo en km aplicable según el tipo de uso (severo si existe).
  int intervaloEfectivoKm(TipoUso tipoUso) =>
      tipoUso == TipoUso.severo && intervaloSeveroKm != null
          ? intervaloSeveroKm!
          : intervaloKm;

  /// Intervalo en meses aplicable según el tipo de uso (escalado en uso severo).
  int? intervaloEfectivoMeses(TipoUso tipoUso) {
    if (intervaloMeses == null) return null;
    if (tipoUso == TipoUso.severo) {
      if (intervaloSeveroKm != null && intervaloKm > 0) {
        final escalado =
            ((intervaloMeses! * intervaloSeveroKm!) / intervaloKm).round();
        return escalado < 1 ? 1 : escalado;
      }
      final escalado = (intervaloMeses! * 0.75).round();
      return escalado < 1 ? 1 : escalado;
    }
    return intervaloMeses;
  }

  /// Días que faltan para el vencimiento por tiempo (negativo si ya venció).
  int? diasRestantes({DateTime? ahora, TipoUso tipoUso = TipoUso.normal}) {
    if (ultimaVezFecha == null || intervaloMeses == null) return null;
    final meses = intervaloEfectivoMeses(tipoUso);
    if (meses == null) return null;
    final ref = ultimaVezFecha!;
    final fechaVencimiento = _sumarMeses(ref, meses);
    final hoy = ahora ?? DateTime.now();
    final fechaVencDate =
        DateTime(fechaVencimiento.year, fechaVencimiento.month, fechaVencimiento.day);
    final hoyDate = DateTime(hoy.year, hoy.month, hoy.day);
    return fechaVencDate.difference(hoyDate).inDays;
  }

  /// Fracción 0..1 del intervalo ya consumida desde la última vez (1 = vencido).
  /// Toma el peor progreso entre distancia y tiempo.
  double progresoIntervalo(int kilometrajeActual, TipoUso tipoUso,
      {DateTime? ahora}) {
    if (kilometrajeActual > 0 && ultimaVezKm == null && ultimaVezFecha == null) {
      return 0.0;
    }
    final intervaloK = intervaloEfectivoKm(tipoUso);
    final pKm = intervaloK <= 0
        ? 1.0
        : ((intervaloK - kmRestantes(kilometrajeActual, tipoUso)) / intervaloK)
            .clamp(0.0, 1.0);

    final meses = intervaloEfectivoMeses(tipoUso);
    if (ultimaVezFecha != null && meses != null && meses > 0) {
      final diasTotales = meses * 30.4375;
      final hoy = ahora ?? DateTime.now();
      final diasPasados = hoy.difference(ultimaVezFecha!).inDays;
      final pDias = diasTotales <= 0
          ? 1.0
          : (diasPasados / diasTotales).clamp(0.0, 1.0);
      return pKm > pDias ? pKm : pDias;
    }

    return pKm;
  }

  /// Calcula cuántos km faltan para el próximo mantenimiento.
  int kmRestantes(int kilometrajeActual, TipoUso tipoUso) {
    final intervalo = intervaloEfectivoKm(tipoUso);
    final referencia = ultimaVezKm ?? 0;
    final kmDesdeUltima = kilometrajeActual - referencia;
    return intervalo - kmDesdeUltima;
  }

  /// Estima los días restantes para que venza el ítem según el ritmo diario de conducción (km/día).
  int? diasEstimadosPorRitmo(
    int kilometrajeActual,
    TipoUso tipoUso,
    double? kmPorDia,
  ) {
    if (kmPorDia == null || kmPorDia <= 0) return null;
    final restKm = kmRestantes(kilometrajeActual, tipoUso);
    if (restKm <= 0) return 0;
    return (restKm / kmPorDia).ceil();
  }

  /// Días restantes efectivos considerando tanto el calendario (meses) como el desgaste diario (km/día).
  /// Devuelve el menor de ambos (el que ocurrirá antes).
  int? diasRestantesEfectivos(
    int kilometrajeActual,
    TipoUso tipoUso, {
    double? kmPorDia,
    DateTime? ahora,
  }) {
    final porMeses = diasRestantes(ahora: ahora, tipoUso: tipoUso);
    final porRitmo = diasEstimadosPorRitmo(kilometrajeActual, tipoUso, kmPorDia);

    if (porMeses == null && porRitmo == null) return null;
    if (porMeses == null) return porRitmo;
    if (porRitmo == null) return porMeses;
    return porMeses < porRitmo ? porMeses : porRitmo;
  }

  /// Alerta de recordatorio urgente al faltar <= 15 días (calendario o ritmo) o <= 300 km.
  bool esRecordatorioUrgente(
    int kilometrajeActual,
    TipoUso tipoUso, {
    double? kmPorDia,
    DateTime? ahora,
  }) {
    if (kilometrajeActual > 0 && ultimaVezKm == null && ultimaVezFecha == null) {
      return false;
    }
    final restKm = kmRestantes(kilometrajeActual, tipoUso);
    if (restKm > 0 && restKm <= 300) return true;
    final restDias = diasRestantesEfectivos(
      kilometrajeActual,
      tipoUso,
      kmPorDia: kmPorDia,
      ahora: ahora,
    );
    if (restDias != null && restDias > 0 && restDias <= 15) return true;
    return false;
  }

  /// Determina el estado del ítem según la regla de lo que ocurra primero:
  /// kilómetros, meses de calendario, o desgaste predictivo (km/día).
  EstadoItem estado(
    int kilometrajeActual,
    TipoUso tipoUso, {
    int? umbralProximo,
    int umbralProximoDias = 35,
    double? kmPorDia,
    DateTime? ahora,
  }) {
    // Si el vehículo tiene kilometraje pero este ítem no tiene ninguna referencia
    // (ni última vez km ni fecha), no está vencido: está 'desconocido' (Sin registro).
    // Excepción: vehículo 0 km nuevo, donde parte de 0.
    if (kilometrajeActual > 0 && ultimaVezKm == null && ultimaVezFecha == null) {
      return EstadoItem.desconocido;
    }

    final intervalo = intervaloEfectivoKm(tipoUso);
    final restKm = kmRestantes(kilometrajeActual, tipoUso);

    // Umbral relativo (L8): max(500 km, 12% del intervalo efectivo)
    final umbralK =
        umbralProximo ?? (intervalo * 0.12).round().clamp(500, 10000);

    final EstadoItem estadoKm;
    if (restKm <= 0) {
      estadoKm = EstadoItem.vencido;
    } else if (restKm <= umbralK) {
      estadoKm = EstadoItem.proximo;
    } else {
      estadoKm = EstadoItem.ok;
    }
    if (estadoKm == EstadoItem.vencido) return EstadoItem.vencido;

    final restDias = diasRestantesEfectivos(
      kilometrajeActual,
      tipoUso,
      kmPorDia: kmPorDia,
      ahora: ahora,
    );
    if (restDias != null) {
      final EstadoItem estadoTiempo;
      if (restDias <= 0) {
        estadoTiempo = EstadoItem.vencido;
      } else if (restDias <= umbralProximoDias) {
        estadoTiempo = EstadoItem.proximo;
      } else {
        estadoTiempo = EstadoItem.ok;
      }

      if (estadoKm == EstadoItem.vencido || estadoTiempo == EstadoItem.vencido) {
        return EstadoItem.vencido;
      }
      if (estadoKm == EstadoItem.proximo || estadoTiempo == EstadoItem.proximo) {
        return EstadoItem.proximo;
      }
      return EstadoItem.ok;
    }
    return estadoKm;
  }
}
