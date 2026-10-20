import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/enums.dart';
import '../models/plan_mantenimiento.dart';

/// Parsea el plan que envía el backend Go (`RespuestaPlan.plan`) al modelo
/// de la app.
///
/// Dos responsabilidades que no puede cumplir el servidor:
///
/// 1. **Inyectar `vehiculoId`**: el servidor cachea planes por *configuración*
///    de vehículo (muchos vehículos comparten un mismo plan), así que no
///    conoce —ni debe conocer— el ID del vehículo del dueño. La asociación
///    plan ↔ vehículo es local.
/// 2. **Sanear los items**: el plan lo puede generar Claude API y, aunque el
///    prompt restringe el vocabulario, un solo valor fuera de rango no debe
///    tumbar el plan completo (el `fromJson` generado lanza con valores de
///    enum desconocidos, y el catch del provider degradaría *todo* al plan
///    genérico local).
///
/// Retorna `null` si el plan es irrecuperable (p. ej. ningún item sobrevive),
/// para que el caller caiga al plan local.
PlanMantenimiento? parsearPlanDelServidor(
  Map<String, dynamic> data, {
  required String vehiculoId,
}) {
  final saneado = Map<String, dynamic>.from(data);

  // Campos requeridos del plan: rescatar si vienen mal.
  if (saneado['id'] is! String || (saneado['id'] as String).isEmpty) {
    saneado['id'] = const Uuid().v4();
  }
  if (saneado['version'] is! num) saneado['version'] = 1;
  final fecha = saneado['fechaGeneracion'];
  if (fecha is! String || DateTime.tryParse(fecha) == null) {
    saneado['fechaGeneracion'] = DateTime.now().toIso8601String();
  }

  final rawItems = saneado['items'];
  final items = <Map<String, dynamic>>[];
  for (final raw in (rawItems is List ? rawItems : const [])) {
    if (raw is! Map) continue;
    final item = _sanearItem(Map<String, dynamic>.from(raw));
    if (item != null) items.add(item);
  }
  if (items.isEmpty) return null;
  saneado['items'] = items;

  // El servidor no conoce el vehículo — la copia local es la que lo asocia.
  saneado['vehiculoId'] = vehiculoId;

  return PlanMantenimiento.fromJson(saneado);
}

// Vocabulario canónico del contrato con el backend — debe coincidir con los
// enums de enums.dart y con lo que el servidor restringe en su prompt
// (servidor-go/biblioteca/investigador.go).
final Set<String> _categoriasValidas =
    CategoriaMantenimiento.values.map((e) => e.name).toSet();
final Set<String> _componentesValidos =
    TipoComponente.values.map((e) => e.name).toSet();
final Set<String> _confianzasValidas =
    NivelConfianza.values.map((e) => e.name).toSet();
// FuentePlan.iaInferida viaja como 'ia' (@JsonValue) — ver enums.dart.
const Set<String> _fuentesValidas = {'oem', 'web', 'ia'};

/// Corrige los campos de un item crudo a valores que la app sabe parsear.
/// Retorna `null` si el item no es rescatable (sin descripción o sin
/// `intervaloKm` numérico positivo no sirve para agendar).
Map<String, dynamic>? _sanearItem(Map<String, dynamic> item) {
  final categoria = item['categoria'];
  if (categoria is! String || !_categoriasValidas.contains(categoria)) {
    item['categoria'] = 'inspeccion';
    _avisar('categoria', categoria);
  }

  final componente = item['componenteAplica'];
  if (componente is! String || !_componentesValidos.contains(componente)) {
    item['componenteAplica'] = 'otro';
    _avisar('componenteAplica', componente);
  }

  final fuente = item['fuente'];
  if (fuente is! String || !_fuentesValidas.contains(fuente)) {
    item['fuente'] = 'ia';
    _avisar('fuente', fuente);
  }

  final confianza = item['confianza'];
  if (confianza is! String || !_confianzasValidas.contains(confianza)) {
    item['confianza'] = 'media';
    _avisar('confianza', confianza);
  }

  final descripcion = item['descripcion'];
  if (descripcion is! String || descripcion.trim().isEmpty) return null;
  final intervaloKm = item['intervaloKm'];
  if (intervaloKm is! num || intervaloKm <= 0) return null;
  item['intervaloKm'] = intervaloKm.toInt();

  // Opcionales: si vienen con tipo incorrecto, fuera.
  if (item['intervaloMeses'] is! num) item.remove('intervaloMeses');
  if (item['intervaloSeveroKm'] is! num) item.remove('intervaloSeveroKm');

  if (item['id'] is! String || (item['id'] as String).isEmpty) {
    item['id'] = const Uuid().v4();
  }

  return item;
}

void _avisar(String campo, Object? valor) {
  if (kDebugMode) {
    debugPrint('[plan_parser] $campo="$valor" fuera de vocabulario — corregido');
  }
}
