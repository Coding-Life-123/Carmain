import 'enums.dart';

/// Una motorización de fábrica sugerida para un modelo/año.
///
/// Viene de `GET /api/motorizacion` (Gemini + búsqueda web en el backend).
/// El parseo es tolerante: lo que no encaja con los enums de la app se
/// ignora (null) en vez de romper — la sugerencia es un asistente del
/// formulario, no un dato crítico.
class OpcionMotor {
  const OpcionMotor({
    required this.codigo,
    this.descripcion,
    this.combustible,
    this.cilindrada,
    this.cilindros,
    this.aspiracion,
    this.potenciaHp,
    this.torqueNm,
  });

  final String codigo;
  final String? descripcion;
  final TipoCombustible? combustible;
  final double? cilindrada; // litros
  final int? cilindros;
  final String? aspiracion;
  final int? potenciaHp; // caballos de fuerza
  final int? torqueNm; // newton-metro

  factory OpcionMotor.fromJson(Map<String, dynamic> json) => OpcionMotor(
        codigo: (json['codigo'] ?? '').toString().trim(),
        descripcion: _parseString(json['descripcion']),
        combustible: _parseCombustible(json['combustible']),
        cilindrada: _parseDouble(json['cilindrada']),
        cilindros: _parseInt(json['cilindros']),
        aspiracion: _parseString(json['aspiracion']),
        potenciaHp: _parseIntTolerante(json['potenciaHp']),
        torqueNm: _parseIntTolerante(json['torqueNm']),
      );

  static TipoCombustible? _parseCombustible(Object? valor) {
    if (valor is! String) return null;
    for (final e in TipoCombustible.values) {
      if (e.name == valor) return e;
    }
    return null;
  }
}

/// Una caja de fábrica sugerida para un modelo/año.
class OpcionTransmision {
  const OpcionTransmision({
    required this.codigo,
    this.descripcion,
    this.tipo,
    this.marchas,
  });

  final String codigo;
  final String? descripcion;
  final TipoTransmision? tipo;
  final int? marchas;

  factory OpcionTransmision.fromJson(Map<String, dynamic> json) =>
      OpcionTransmision(
        codigo: (json['codigo'] ?? '').toString().trim(),
        descripcion: _parseString(json['descripcion']),
        tipo: _parseTipo(json['tipo']),
        marchas: _parseInt(json['marchas']),
      );

  static TipoTransmision? _parseTipo(Object? valor) {
    if (valor is! String) return null;
    for (final e in TipoTransmision.values) {
      if (e.name == valor) return e;
    }
    return null;
  }
}

/// Respuesta de `GET /api/motorizacion`.
class SugerenciasMotorizacion {
  const SugerenciasMotorizacion({
    required this.motores,
    required this.transmisiones,
    this.drivetrain,
  });

  final List<OpcionMotor> motores;
  final List<OpcionTransmision> transmisiones;

  /// Tracción de fábrica del modelo/año, si el servidor la trae — el
  /// formulario la aplica salvo que el usuario ya haya elegido una.
  final Drivetrain? drivetrain;

  factory SugerenciasMotorizacion.fromJson(Map<String, dynamic> json) =>
      SugerenciasMotorizacion(
        motores: _parseLista(json['motores'], OpcionMotor.fromJson)
            .where((m) => m.codigo.isNotEmpty)
            .toList(),
        transmisiones:
            _parseLista(json['transmisiones'], OpcionTransmision.fromJson)
                .where((t) => t.codigo.isNotEmpty)
                .toList(),
        drivetrain: _parseDrivetrain(json['drivetrain']),
      );

  /// El contrato viaja con las etiquetas canónicas ('FWD'…'4WD'), no con
  /// los nombres del enum Dart — y se acepta en cualquier capitalización.
  static Drivetrain? _parseDrivetrain(Object? valor) {
    if (valor is! String) return null;
    for (final e in Drivetrain.values) {
      if (e.label.toLowerCase() == valor.trim().toLowerCase()) return e;
    }
    return null;
  }
}

/// Parsea una lista cruda de maps, ignorando lo que no sea un map.
List<T> _parseLista<T>(
  Object? raw,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

// Los helpers siguientes devuelven null ante cualquier tipo inesperado —
// un cast (`as num?`) lanzaría TypeError y rompería la tolerancia.

String? _parseString(Object? v) => v is String ? v : null;

double? _parseDouble(Object? v) => v is num ? v.toDouble() : null;

int? _parseInt(Object? v) => v is num ? v.toInt() : null;

/// Potencia/torque: el servidor normaliza a número, pero acepta también
/// strings numéricos puros ("255") por si la respuesta viene cruda.
/// Redondea (Gemini puede devolver 254.79 tras convertir de kW).
int? _parseIntTolerante(Object? v) {
  if (v is num) return v.round();
  if (v is String) return double.tryParse(v.trim())?.round();
  return null;
}
