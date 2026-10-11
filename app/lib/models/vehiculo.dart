import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:json_annotation/json_annotation.dart';

import 'componente.dart';
import 'enums.dart';

part 'vehiculo.freezed.dart';
part 'vehiculo.g.dart';

/// Vehículo modelado como compuesto de componentes.
///
/// La clave para soportar swaps: el vehículo no es monolítico, sino que
/// se compone de chasis (marca/modelo/año) + motor + transmisión + componentes
/// extra. Cada componente se puede reemplazar independientemente.
@freezed
abstract class Vehiculo with _$Vehiculo {
  const factory Vehiculo({
    required String id,
    required String propietarioId,
    required String marca,
    required String modelo,
    required int anio,
    String? trim,
    String? vin,
    required Drivetrain drivetrain,
    required Motor motor,
    required Transmision transmision,
    @Default([]) List<Componente> componentesExtra,
    @Default(0) int kilometrajeActual,
    @Default(TipoUso.normal) TipoUso tipoUso,
    String? notasUso,
    String? planMantenimientoId,
  }) = _Vehiculo;

  factory Vehiculo.fromJson(Map<String, dynamic> json) =>
      _$VehiculoFromJson(json);
}

/// Extensión con utilidades para el vehículo.
extension VehiculoX on Vehiculo {
  /// `true` si el vehículo tiene algún componente que no es original (swap).
  bool get tieneSwap =>
      !motor.esOriginal ||
      !transmision.esOriginal ||
      componentesExtra.any((c) => !c.esOriginal);

  /// Nombre legible: "Toyota Supra 1995".
  String get nombreCompleto => '$marca $modelo $anio';
}
