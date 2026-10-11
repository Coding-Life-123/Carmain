import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:json_annotation/json_annotation.dart';

import 'enums.dart';

part 'registro_mantenimiento.freezed.dart';
part 'registro_mantenimiento.g.dart';

/// Un ítem individual que se realizó en un mantenimiento.
@freezed
abstract class ItemRealizado with _$ItemRealizado {
  const factory ItemRealizado({
    required CategoriaMantenimiento categoria,
    required String descripcion,
    required TipoComponente componenteAplica,
  }) = _ItemRealizado;

  factory ItemRealizado.fromJson(Map<String, dynamic> json) =>
      _$ItemRealizadoFromJson(json);
}

/// Registro de un mantenimiento realizado (lo que ya se hizo).
@freezed
abstract class RegistroMantenimiento with _$RegistroMantenimiento {
  const factory RegistroMantenimiento({
    required String id,
    required String vehiculoId,
    required DateTime fecha,
    required int kilometraje,
    @Default([]) List<ItemRealizado> itemsRealizados,
    double? costo,
    String? taller,
    String? notas,
    @Default([]) List<String> evidencia, // rutas a fotos/facturas
    // Para sincronización dueño ↔ mecánico.
    DateTime? updatedAt,
  }) = _RegistroMantenimiento;

  factory RegistroMantenimiento.fromJson(Map<String, dynamic> json) =>
      _$RegistroMantenimientoFromJson(json);
}
