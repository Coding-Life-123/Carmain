import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:json_annotation/json_annotation.dart';

import 'enums.dart';

part 'componente.freezed.dart';
part 'componente.g.dart';

/// Componente genérico del vehículo (diferencial, transfer case, frenos, etc.).
@freezed
abstract class Componente with _$Componente {
  const factory Componente({
    required TipoComponente tipo,
    required String codigo,
    String? descripcion,
    String? fabricante,
    @Default(true) bool esOriginal,
    String? originalCodigo,
    @Default(FuenteComponente.oem) FuenteComponente fuente,
  }) = _Componente;

  factory Componente.fromJson(Map<String, dynamic> json) =>
      _$ComponenteFromJson(json);
}

/// Motor del vehículo. Puede ser original (OEM) o un swap.
@freezed
abstract class Motor with _$Motor {
  const factory Motor({
    required String codigo,
    String? descripcion,
    String? fabricante,
    @Default(true) bool esOriginal,
    String? originalCodigo,
    @Default(FuenteComponente.oem) FuenteComponente fuente,
    required TipoCombustible tipoCombustible,
    double? cilindrada,
    int? cilindros,
    String? aspiracion, // ej. "NA", "Turbo", "Twin-Turbo", "Supercharger"
  }) = _Motor;

  factory Motor.fromJson(Map<String, dynamic> json) => _$MotorFromJson(json);
}

/// Transmisión / caja de cambios. Puede ser original (OEM) o un swap.
@freezed
abstract class Transmision with _$Transmision {
  const factory Transmision({
    required String codigo,
    String? descripcion,
    String? fabricante,
    @Default(true) bool esOriginal,
    String? originalCodigo,
    @Default(FuenteComponente.oem) FuenteComponente fuente,
    required TipoTransmision tipo,
    int? marchas,
  }) = _Transmision;

  factory Transmision.fromJson(Map<String, dynamic> json) =>
      _$TransmisionFromJson(json);
}
