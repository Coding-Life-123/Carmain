import 'dart:convert';
import 'enums.dart';

class PropuestaItemModel {
  final String? itemId;
  final CategoriaMantenimiento categoria;
  final TipoComponente componenteAplica;
  final String descripcion;

  const PropuestaItemModel({
    this.itemId,
    required this.categoria,
    required this.componenteAplica,
    required this.descripcion,
  });

  factory PropuestaItemModel.fromJson(Map<String, dynamic> json) {
    return PropuestaItemModel(
      itemId: json['itemId'] as String?,
      categoria: CategoriaMantenimiento.values.firstWhere(
        (c) => c.name == json['categoria'],
        orElse: () => CategoriaMantenimiento.inspeccion,
      ),
      componenteAplica: TipoComponente.values.firstWhere(
        (c) => c.name == json['componenteAplica'],
        orElse: () => TipoComponente.otro,
      ),
      descripcion: (json['descripcion'] as String?)?.trim() ?? 'Mantenimiento realizado',
    );
  }

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'categoria': categoria.name,
        'componenteAplica': componenteAplica.name,
        'descripcion': descripcion,
      };
}

class PropuestaAdjuntoModel {
  final String id;
  final String nombre;
  final String mime;
  final int bytes;

  const PropuestaAdjuntoModel({
    required this.id,
    required this.nombre,
    required this.mime,
    required this.bytes,
  });

  factory PropuestaAdjuntoModel.fromJson(Map<String, dynamic> json) {
    return PropuestaAdjuntoModel(
      id: json['id'] as String? ?? '',
      nombre: json['nombre'] as String? ?? 'adjunto',
      mime: json['mime'] as String? ?? 'image/jpeg',
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'mime': mime,
        'bytes': bytes,
      };
}

class PropuestaMecanicoModel {
  final String id;
  final String sesionId;
  final String vehiculoId;
  final DateTime creadaEn;
  final DateTime recibidaEn;
  final String? taller;
  final String? mecanicoNombre;
  final int kilometraje;
  final String fecha;
  final double? costo;
  final String moneda;
  final String? notas;
  final List<PropuestaItemModel> itemsRealizados;
  final List<PropuestaAdjuntoModel> adjuntos;
  final String estado; // 'pendiente' | 'aceptada' | 'rechazada'

  const PropuestaMecanicoModel({
    required this.id,
    required this.sesionId,
    required this.vehiculoId,
    required this.creadaEn,
    required this.recibidaEn,
    this.taller,
    this.mecanicoNombre,
    required this.kilometraje,
    required this.fecha,
    this.costo,
    this.moneda = 'COP',
    this.notas,
    required this.itemsRealizados,
    this.adjuntos = const [],
    this.estado = 'pendiente',
  });

  factory PropuestaMecanicoModel.fromJson(
    Map<String, dynamic> json, {
    required String sesionId,
    required String vehiculoId,
    String estado = 'pendiente',
    DateTime? recibidaEn,
  }) {
    String? taller;
    String? mecanicoNombre;
    final mecanicoRaw = json['mecanico'];
    if (mecanicoRaw is Map<String, dynamic>) {
      taller = mecanicoRaw['taller'] as String?;
      mecanicoNombre = mecanicoRaw['nombre'] as String?;
    } else if (mecanicoRaw is String) {
      taller = mecanicoRaw;
    }

    final itemsRaw = json['itemsRealizados'] as List? ?? json['items'] as List? ?? [];
    final items = itemsRaw
        .map((e) => PropuestaItemModel.fromJson(e as Map<String, dynamic>))
        .toList();

    final adjuntosRaw = json['adjuntos'] as List? ?? [];
    final adjuntos = adjuntosRaw
        .map((e) => PropuestaAdjuntoModel.fromJson(e as Map<String, dynamic>))
        .toList();

    DateTime parsedCreadaEn;
    try {
      parsedCreadaEn = json['creadaEn'] != null
          ? DateTime.parse(json['creadaEn'] as String)
          : DateTime.now();
    } catch (_) {
      parsedCreadaEn = DateTime.now();
    }

    return PropuestaMecanicoModel(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      sesionId: sesionId,
      vehiculoId: vehiculoId,
      creadaEn: parsedCreadaEn,
      recibidaEn: recibidaEn ?? DateTime.now(),
      taller: taller,
      mecanicoNombre: mecanicoNombre,
      kilometraje: (json['kilometraje'] as num?)?.toInt() ?? 0,
      fecha: json['fecha'] as String? ?? '',
      costo: (json['costo'] as num?)?.toDouble(),
      moneda: json['moneda'] as String? ?? 'COP',
      notas: json['notas'] as String?,
      itemsRealizados: items,
      adjuntos: adjuntos,
      estado: estado,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sesionId': sesionId,
        'vehiculoId': vehiculoId,
        'creadaEn': creadaEn.toIso8601String(),
        'recibidaEn': recibidaEn.toIso8601String(),
        'mecanico': {
          'taller': taller,
          'nombre': mecanicoNombre,
        },
        'kilometraje': kilometraje,
        'fecha': fecha,
        'costo': costo,
        'moneda': moneda,
        'notas': notas,
        'itemsRealizados': itemsRealizados.map((e) => e.toJson()).toList(),
        'adjuntos': adjuntos.map((e) => e.toJson()).toList(),
        'estado': estado,
      };

  String get jsonCrudo => jsonEncode(toJson());
}

