import 'package:json_annotation/json_annotation.dart';

/// Tipo de tracción del vehículo.
enum Drivetrain {
  fwd('FWD'),
  rwd('RWD'),
  awd('AWD'),
  fourWd('4WD');

  const Drivetrain(this.label);
  final String label;
}

/// Tipo de componente principal del vehículo.
enum TipoComponente {
  motor('Motor'),
  transmision('Transmisión'),
  diferencial('Diferencial'),
  transferCase('Transfer Case'),
  frenos('Frenos'),
  suspension('Suspensión'),
  otro('Otro');

  const TipoComponente(this.label);
  final String label;
}

/// Origen del componente (original de fábrica, swap, o personalizado).
enum FuenteComponente {
  oem('OEM'),
  swap('Swap'),
  personalizado('Personalizado');

  const FuenteComponente(this.label);
  final String label;
}

/// Categoría de mantenimiento.
enum CategoriaMantenimiento {
  motor('Motor'),
  transmision('Transmisión'),
  frenos('Frenos'),
  refrigeracion('Refrigeración'),
  diferencial('Diferencial / Transfer'),
  suspension('Suspensión / Dirección'),
  neumaticos('Neumáticos'),
  electrico('Eléctrico'),
  escape('Escape'),
  inspeccion('Inspección General');

  const CategoriaMantenimiento(this.label);
  final String label;
}

/// Nivel de confianza del intervalo de mantenimiento según la fuente.
enum NivelConfianza {
  alta('Alta'),
  media('Media'),
  baja('Baja');

  const NivelConfianza(this.label);
  final String label;
}

/// Tipo de uso del vehículo (afecta los intervalos).
enum TipoUso {
  normal('Normal'),
  severo('Severo');

  const TipoUso(this.label);
  final String label;
}

/// Tipo de combustible del motor.
enum TipoCombustible {
  gasolina('Gasolina'),
  diesel('Diésel'),
  hibrido('Híbrido'),
  electrico('Eléctrico'),
  gas('Gas');

  const TipoCombustible(this.label);
  final String label;
}

/// Tipo de transmisión.
enum TipoTransmision {
  manual('Manual'),
  automatica('Automática'),
  cvt('CVT'),
  dct('DCT'),
  automatedManual('Automatizada');

  const TipoTransmision(this.label);
  final String label;
}

/// Fuente del plan de mantenimiento generado.
enum FuentePlan {
  oem('OEM'),
  web('Web'),

  /// Viaja como 'ia' en JSON — contrato con el backend Go.
  @JsonValue('ia')
  iaInferida('IA');

  const FuentePlan(this.label);
  final String label;
}

/// Tipo de recordatorio.
enum TipoRecordatorio {
  proximoMantenimiento('Próximo mantenimiento'),
  actualizarKilometraje('Actualizar kilometraje');

  const TipoRecordatorio(this.label);
  final String label;
}

/// Severidad de un punto crítico o cuello de botella detectado en swaps.
enum SeveridadIngenieria {
  @JsonValue('alta')
  alta('Riesgo Mecánico Alto'),
  @JsonValue('media')
  media('Atención Térmica / Fluidos'),
  @JsonValue('recomendacion')
  recomendacion('Mejora Recomendada');

  const SeveridadIngenieria(this.label);
  final String label;
}

/// Vector cinemático o térmico de estrés en un swap.
enum VectorEstresSwap {
  @JsonValue('torqueDiferencial')
  torqueDiferencial('Diferencial y Semiejes'),
  @JsonValue('limiteTransmision')
  limiteTransmision('Transmisión y Embrague'),
  @JsonValue('disipacionTermica')
  disipacionTermica('Disipación Térmica'),
  @JsonValue('frenadoMasa')
  frenadoMasa('Frenos y Masa Frontal'),
  @JsonValue('alimentacionCombustible')
  alimentacionCombustible('Alimentación de Combustible'),
  @JsonValue('soportesNvh')
  soportesNvh('Soportes y Subchasis');

  const VectorEstresSwap(this.label);
  final String label;
}

/// Nivel de confianza o verificación de un registro de mantenimiento en el pasaporte digital.
enum NivelVerificacionHistorial {
  @JsonValue('declarado')
  declarado('Nivel 1 · Declarado por usuario'),
  @JsonValue('conEvidencia')
  conEvidencia('Nivel 2 · Documentado con evidencia'),
  @JsonValue('selladoTaller')
  selladoTaller('Nivel 3 · Sellado por taller');

  const NivelVerificacionHistorial(this.label);
  final String label;
}
