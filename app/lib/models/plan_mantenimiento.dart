import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:json_annotation/json_annotation.dart';

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
  }) = _ItemMantenimiento;

  factory ItemMantenimiento.fromJson(Map<String, dynamic> json) =>
      _$ItemMantenimientoFromJson(json);
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
  }) = _PlanMantenimiento;

  factory PlanMantenimiento.fromJson(Map<String, dynamic> json) =>
      _$PlanMantenimientoFromJson(json);
}

/// Estado calculado de un ítem respecto al kilometraje actual.
enum EstadoItem { vencido, proximo, ok }

/// Extensión con cálculos de próximo mantenimiento.
extension ItemMantenimientoX on ItemMantenimiento {
  /// Kilómetros desde la última vez que se hizo este mantenimiento.
  /// Si nunca se hizo, retorna null.
  int? get kmDesdeUltimaVez => ultimaVezKm == null ? null : null;

  /// Calcula cuántos km faltan para el próximo mantenimiento,
  /// dado el kilometraje actual del vehículo.
  int kmRestantes(int kilometrajeActual, TipoUso tipoUso) {
    final intervalo = tipoUso == TipoUso.severo && intervaloSeveroKm != null
        ? intervaloSeveroKm!
        : intervaloKm;
    final referencia = ultimaVezKm ?? 0;
    final kmDesdeUltima = kilometrajeActual - referencia;
    return intervalo - kmDesdeUltima;
  }

  /// Determina el estado del ítem según el kilometraje actual.
  EstadoItem estado(int kilometrajeActual, TipoUso tipoUso,
      {int umbralProximo = 1000}) {
    final restantes = kmRestantes(kilometrajeActual, tipoUso);
    if (restantes <= 0) return EstadoItem.vencido;
    if (restantes <= umbralProximo) return EstadoItem.proximo;
    return EstadoItem.ok;
  }
}
