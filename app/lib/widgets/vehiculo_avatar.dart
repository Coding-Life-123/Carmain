import 'dart:io';
import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../models/vehiculo.dart';

/// Tipos de silueta según la morfología del vehículo.
enum TipoSiluetaVehiculo {
  automovil('Automóvil / Sedán'),
  suv('SUV / Crossover'),
  pickup('Pick-up / Camioneta con Platón'),
  camionPesado('Camión Pesado / Heavy Duty'),
  camionLigero('Camión Ligero / Reparto'),
  mula('Tractomula / Tractocamión'),
  van('Van / Furgón');

  const TipoSiluetaVehiculo(this.etiqueta);
  final String etiqueta;
}

/// Convierte el nombre de una marca en el slug estándar de catálogo de logos.
String normalizarMarcaSlug(String marca) {
  var s = marca.trim().toLowerCase();
  if (s == 'vw') return 'volkswagen';
  if (s == 'chevy') return 'chevrolet';
  if (s == 'mercedes' || s.contains('mercedes')) return 'mercedes-benz';
  if (s.contains('alfa')) return 'alfa-romeo';
  if (s.contains('aston')) return 'aston-martin';
  if (s.contains('land rover') || s.contains('land-rover')) return 'land-rover';
  return s
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

/// Detecta inteligentemente la silueta del vehículo analizando marca, modelo, trim y tren motriz.
TipoSiluetaVehiculo detectarTipoSilueta(Vehiculo vehiculo) {
  final marca = vehiculo.marca.toLowerCase().trim();
  final modelo = vehiculo.modelo.toLowerCase().trim();
  final trim = (vehiculo.trim ?? '').toLowerCase().trim();
  final descMotor = (vehiculo.motor.descripcion ?? '').toLowerCase().trim();
  final combustible = vehiculo.motor.tipoCombustible;
  final cilindrada = vehiculo.motor.cilindrada ?? 0.0;

  final texto = '$marca $modelo $trim $descMotor';
  final norm = texto.replaceAll(RegExp(r'[\s\-_]+'), '');

  // 1. Tractomula / Tractocamión pesado (Kenworth, Mack, Freightliner, International, etc.)
  final esMarcaMula = norm.contains('kenworth') ||
      norm.contains('freightliner') ||
      norm.contains('international') ||
      norm.contains('mack') ||
      norm.contains('peterbilt') ||
      norm.contains('scania');

  final esModeloMula = norm.contains('t800') ||
      norm.contains('t680') ||
      norm.contains('t660') ||
      norm.contains('w900') ||
      norm.contains('cascadia') ||
      norm.contains('columbia') ||
      norm.contains('prostar') ||
      norm.contains('lonestar') ||
      norm.contains('anthem') ||
      norm.contains('pinnacle') ||
      norm.contains('granite') ||
      norm.contains('mula') ||
      norm.contains('tractomula') ||
      norm.contains('tractocamion');

  if (esMarcaMula || esModeloMula || cilindrada >= 10.0) {
    return TipoSiluetaVehiculo.mula;
  }

  // 2. Camión Ligero / Cabover / Furgón Comercial Urbano (Chevrolet NPR/NQR/NKR/NHR, Hino, Fuso Canter, Fotón)
  final esCamionLigero = norm.contains('npr') ||
      norm.contains('nqr') ||
      norm.contains('nhr') ||
      norm.contains('nkr') ||
      norm.contains('nnr') ||
      norm.contains('hino') ||
      norm.contains('fusocanter') ||
      norm.contains('canter') ||
      norm.contains('aumark') ||
      norm.contains('foton') ||
      norm.contains('fotón') ||
      norm.contains('dutro') ||
      norm.contains('forland') ||
      norm.contains('jacchasis');

  if (esCamionLigero) {
    return TipoSiluetaVehiculo.camionLigero;
  }

  // 3. Camión Pesado / Heavy Duty / Dually (Ford F-450, F-350, F-550, Silverado 3500 HD, RAM 3500/4500 HD)
  final esFordHD = norm.contains('f450') ||
      norm.contains('f350') ||
      norm.contains('f550') ||
      norm.contains('f250') ||
      norm.contains('superduty');

  final esGmHD = (norm.contains('silverado') || norm.contains('sierra')) &&
      (norm.contains('2500') || norm.contains('3500') || norm.contains('hd')) ||
      norm.contains('kodiak') ||
      norm.contains('topkick');

  final esRamHD = (marca.contains('ram') || marca.contains('dodge')) &&
      (norm.contains('2500') ||
          norm.contains('3500') ||
          norm.contains('4500') ||
          norm.contains('5500') ||
          norm.contains('powerwagon'));

  final esDuallyDesc = norm.contains('dually') || norm.contains('doblerueda');
  final esMotorSuperPesado = cilindrada >= 5.8 ||
      (combustible == TipoCombustible.diesel && cilindrada >= 5.0);

  if (esFordHD || esGmHD || esRamHD || esDuallyDesc || esMotorSuperPesado) {
    return TipoSiluetaVehiculo.camionPesado;
  }

  // 4. Van / Minivan / Furgón cerrado de pasajeros o carga (HiAce, Urvan, Transit, Sprinter, etc.)
  final esVan = norm.contains('hiace') ||
      norm.contains('urvan') ||
      norm.contains('transit') ||
      norm.contains('sprinter') ||
      norm.contains('transporter') ||
      norm.contains('crafter') ||
      norm.contains('expert') ||
      norm.contains('boxer') ||
      norm.contains('ducato') ||
      norm.contains('master') ||
      norm.contains('trafic') ||
      norm.contains('kangoo') ||
      norm.contains('partner') ||
      norm.contains('berlingo') ||
      norm.contains('n300') ||
      norm.contains('minivan') ||
      norm.contains('carnival') ||
      norm.contains('sienna') ||
      norm.contains('odyssey') ||
      norm.contains('van');

  if (esVan) {
    return TipoSiluetaVehiculo.van;
  }

  // 5. Pick-up / Camioneta con Platón (Hilux, Ranger, D-Max, Frontier, F-150, Amarok, etc.)
  final esPickup = norm.contains('hilux') ||
      norm.contains('tacoma') ||
      norm.contains('tundra') ||
      norm.contains('ranger') ||
      norm.contains('f150') ||
      norm.contains('raptor') ||
      norm.contains('dmax') ||
      norm.contains('colorado') ||
      norm.contains('s10') ||
      norm.contains('frontier') ||
      norm.contains('navara') ||
      norm.contains('titan') ||
      norm.contains('l200') ||
      norm.contains('sportero') ||
      norm.contains('amarok') ||
      norm.contains('gladiator') ||
      norm.contains('ram1500') ||
      norm.contains('oroch') ||
      norm.contains('montana') ||
      norm.contains('strada') ||
      norm.contains('saveiro') ||
      norm.contains('platon') ||
      norm.contains('platón') ||
      norm.contains('pickup') ||
      norm.contains('pick-up') ||
      norm.contains('doblecabina') ||
      norm.contains('cabinasimple');

  if (esPickup) {
    return TipoSiluetaVehiculo.pickup;
  }

  // 6. SUV / Crossover / 4x4 Cerrado (Sahara, LC300, Prado, Fortuner, CX-30, Tracker, Duster, Tucson, etc.)
  final esSuv = norm.contains('sahara') ||
      norm.contains('lc300') ||
      norm.contains('lc200') ||
      norm.contains('lc100') ||
      norm.contains('lc80') ||
      norm.contains('lc76') ||
      norm.contains('lc79') ||
      norm.contains('lc70') ||
      norm.contains('landcruiser') ||
      norm.contains('fjcruiser') ||
      (norm.contains('cruiser') && !norm.contains('ptcruiser')) ||
      norm.contains('gxr') ||
      norm.contains('vxr') ||
      norm.contains('txl') ||
      norm.contains('grsport') ||
      norm.contains('burbuja') ||
      norm.contains('autana') ||
      norm.contains('carevaca') ||
      norm.contains('machito') ||
      norm.contains('sequoia') ||
      norm.contains('highlander') ||
      norm.contains('prado') ||
      norm.contains('fortuner') ||
      norm.contains('4runner') ||
      norm.contains('rav4') ||
      norm.contains('corollacross') ||
      norm.contains('yariscross') ||
      norm.contains('rush') ||
      norm.contains('raize') ||
      norm.contains('explorer') ||
      norm.contains('expedition') ||
      norm.contains('edge') ||
      norm.contains('escape') ||
      norm.contains('ecosport') ||
      norm.contains('bronco') ||
      norm.contains('tahoe') ||
      norm.contains('suburban') ||
      norm.contains('trailblazer') ||
      norm.contains('traverse') ||
      norm.contains('tracker') ||
      norm.contains('captiva') ||
      norm.contains('equinox') ||
      norm.contains('patrol') ||
      norm.contains('pathfinder') ||
      norm.contains('xtrail') ||
      norm.contains('qashqai') ||
      norm.contains('kicks') ||
      norm.contains('murano') ||
      norm.contains('safari') ||
      norm.contains('montero') ||
      norm.contains('nativa') ||
      norm.contains('pajero') ||
      norm.contains('outlander') ||
      norm.contains('asx') ||
      norm.contains('eclipsecross') ||
      norm.contains('duster') ||
      norm.contains('koleos') ||
      norm.contains('captur') ||
      norm.contains('kardian') ||
      norm.contains('cx3') ||
      norm.contains('cx30') ||
      norm.contains('cx5') ||
      norm.contains('cx50') ||
      norm.contains('cx60') ||
      norm.contains('cx70') ||
      norm.contains('cx80') ||
      norm.contains('cx9') ||
      norm.contains('cx90') ||
      norm.contains('tucson') ||
      norm.contains('santafe') ||
      norm.contains('creta') ||
      norm.contains('venue') ||
      norm.contains('palisade') ||
      norm.contains('sportage') ||
      norm.contains('sorento') ||
      norm.contains('seltos') ||
      norm.contains('sonet') ||
      norm.contains('mohave') ||
      norm.contains('telluride') ||
      norm.contains('wrangler') ||
      norm.contains('grandcherokee') ||
      norm.contains('cherokee') ||
      norm.contains('compass') ||
      norm.contains('renegade') ||
      norm.contains('rubicon') ||
      norm.contains('tiguan') ||
      norm.contains('taos') ||
      norm.contains('tcross') ||
      norm.contains('nivus') ||
      norm.contains('touareg') ||
      norm.contains('teramont') ||
      norm.contains('crossfox') ||
      norm.contains('jimny') ||
      norm.contains('vitara') ||
      norm.contains('grandvitara') ||
      norm.contains('sidekick') ||
      norm.contains('defender') ||
      norm.contains('discovery') ||
      norm.contains('evoque') ||
      norm.contains('velar') ||
      norm.contains('rangerover') ||
      norm.contains('x1') ||
      norm.contains('x2') ||
      norm.contains('x3') ||
      norm.contains('x4') ||
      norm.contains('x5') ||
      norm.contains('x6') ||
      norm.contains('x7') ||
      norm.contains('gla') ||
      norm.contains('glb') ||
      norm.contains('glc') ||
      norm.contains('gle') ||
      norm.contains('gls') ||
      norm.contains('q3') ||
      norm.contains('q5') ||
      norm.contains('q7') ||
      norm.contains('q8') ||
      norm.contains('macan') ||
      norm.contains('cayenne') ||
      norm.contains('suv') ||
      norm.contains('crossover') ||
      norm.contains('campero') ||
      norm.contains('4x4');

  if (esSuv) {
    return TipoSiluetaVehiculo.suv;
  }

  // 7. Por defecto: Automóvil / Sedán / Coupé / Hatchback (Spark, Supra, Corolla Sedán, etc.)
  return TipoSiluetaVehiculo.automovil;
}

/// Avatar de marca del vehículo: muestra la foto personalizada del vehículo si existe,
/// o el logo oficial de la marca (con inicial estilizada como fallback).
class VehiculoAvatar extends StatelessWidget {
  const VehiculoAvatar({
    super.key,
    required this.marca,
    this.vehiculo,
    this.fotoPath,
    this.size = 56,
    this.width,
    this.height,
    this.borderRadius = 16,
    this.backgroundColor,
    this.colorFondoAuto,
  });

  final String marca;
  final Vehiculo? vehiculo;
  final String? fotoPath;
  final double size;
  final double? width;
  final double? height;
  final double borderRadius;
  final Color? backgroundColor;

  /// Parámetro conservado por compatibilidad de firma.
  final Color? colorFondoAuto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final w = width ?? size;
    final h = height ?? size;

    // 1. Si el vehículo tiene una foto personalizada guardada localmente
    final rutaEfectiva = fotoPath ?? vehiculo?.fotoPath;
    if (rutaEfectiva != null && rutaEfectiva.isNotEmpty) {
      final archivo = File(rutaEfectiva);
      if (archivo.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Image.file(
            archivo,
            width: w,
            height: h,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _buildLogo(context, cs, w, h),
          ),
        );
      }
    }

    return _buildLogo(context, cs, w, h);
  }

  Widget _buildLogo(BuildContext context, ColorScheme cs, double w, double h) {
    final slug = normalizarMarcaSlug(marca);
    final logoUrl =
        'https://raw.githubusercontent.com/filippofilip95/car-logos-dataset/master/logos/thumb/$slug.png';

    final bg = backgroundColor ?? cs.surfaceContainerHighest.withValues(alpha: 0.6);

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius - 1),
        child: slug.isEmpty
            ? _FallbackMarca(marca: marca, color: cs.primary, size: h * 0.45)
            : Image.network(
                logoUrl,
                fit: BoxFit.contain,
                width: w,
                height: h,
                headers: const {'Accept': 'image/png,image/*'},
                errorBuilder: (context, error, stackTrace) {
                  return _FallbackMarca(
                    marca: marca,
                    color: cs.primary,
                    size: h * 0.45,
                  );
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return _FallbackMarca(
                    marca: marca,
                    color: cs.primary.withValues(alpha: 0.4),
                    size: h * 0.45,
                  );
                },
              ),
      ),
    );
  }
}

/// Silueta vectorial que se adapta al tipo específico de vehículo
/// (automóvil, SUV, pick-up, camión pesado, camión ligero, tractomula, van).
class VehiculoSiluetaFondo extends StatelessWidget {
  const VehiculoSiluetaFondo({
    super.key,
    this.vehiculo,
    this.tipo,
    this.width = 140,
    this.height = 70,
    this.color,
    this.opacity = 0.16,
    this.alignment = Alignment.centerRight,
  });

  final Vehiculo? vehiculo;
  final TipoSiluetaVehiculo? tipo;
  final double width;
  final double height;
  final Color? color;
  final double opacity;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = (color ?? cs.onSurface).withValues(alpha: opacity);
    final tipoEfectivo =
        tipo ?? (vehiculo != null ? detectarTipoSilueta(vehiculo!) : TipoSiluetaVehiculo.automovil);

    return Align(
      alignment: alignment,
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _obtenerPainter(tipoEfectivo, tint),
        ),
      ),
    );
  }

  CustomPainter _obtenerPainter(TipoSiluetaVehiculo tipo, Color color) {
    return switch (tipo) {
      TipoSiluetaVehiculo.automovil => _PainterAutomovil(color: color),
      TipoSiluetaVehiculo.suv => _PainterSuv(color: color),
      TipoSiluetaVehiculo.pickup => _PainterPickup(color: color),
      TipoSiluetaVehiculo.camionPesado => _PainterCamionPesado(color: color),
      TipoSiluetaVehiculo.camionLigero => _PainterCamionLigero(color: color),
      TipoSiluetaVehiculo.mula => _PainterTractomula(color: color),
      TipoSiluetaVehiculo.van => _PainterVan(color: color),
    };
  }
}

/// Fallback elegante cuando el logo no está disponible o no hay red.
class _FallbackMarca extends StatelessWidget {
  const _FallbackMarca({
    required this.marca,
    required this.color,
    required this.size,
  });

  final String marca;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final inicial =
        marca.trim().isNotEmpty ? marca.trim().substring(0, 1).toUpperCase() : '?';

    return Center(
      child: Text(
        inicial,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w900,
          color: color,
          letterSpacing: -1,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DETALLES Y RUEDAS VECTORIALES REUTILIZABLES
// ─────────────────────────────────────────────────────────────────────────────

void _dibujarRuedaConDetalle(
  Canvas canvas,
  Offset center,
  double radius,
  Color color, {
  bool offroad = false,
  bool dually = false,
}) {
  final tirePaint = Paint()
    ..color = color
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  // 1. Llanta / Neumático exterior
  canvas.drawCircle(center, radius, tirePaint);

  // 2. Aro del Rin (área interna contrastada)
  final rimPaint = Paint()
    ..color = color.withValues(alpha: 0.35)
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  final rRim = radius * 0.65;
  canvas.drawCircle(center, rRim, rimPaint);

  // 3. Reborde del rin
  final rimBorder = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..isAntiAlias = true;
  canvas.drawCircle(center, rRim, rimBorder);

  // 4. Centro / Tapacubo
  canvas.drawCircle(center, radius * 0.22, tirePaint);

  // 5. Pernos / Rayos estilizados
  if (offroad || dually) {
    final pOff = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final rLug = radius * 0.10;
    canvas.drawCircle(Offset(center.dx - rRim * 0.55, center.dy), rLug, pOff);
    canvas.drawCircle(Offset(center.dx + rRim * 0.55, center.dy), rLug, pOff);
    canvas.drawCircle(Offset(center.dx, center.dy - rRim * 0.55), rLug, pOff);
    canvas.drawCircle(Offset(center.dx, center.dy + rRim * 0.55), rLug, pOff);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAINTERS VECTORIALES ENRIQUECIDOS POR CATEGORÍA
// ─────────────────────────────────────────────────────────────────────────────

/// 1. Automóvil / Sedán / Coupé / Deportivo (Detallado con faros, cristales y rines deportivos)
class _PainterAutomovil extends CustomPainter {
  const _PainterAutomovil({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    // Carrocería deportiva aerodinámica
    final p = Path();
    p.moveTo(w * 0.04, h * 0.72);
    p.lineTo(w * 0.10, h * 0.56);
    p.lineTo(w * 0.28, h * 0.50);
    p.lineTo(w * 0.44, h * 0.26);
    p.lineTo(w * 0.70, h * 0.26);
    p.lineTo(w * 0.84, h * 0.50);
    p.lineTo(w * 0.96, h * 0.56);
    p.lineTo(w * 0.95, h * 0.72);
    p.close();
    canvas.drawPath(p, paint);

    // Ventanas laterales aerodinámicas con pilar B
    final pWin1 = Path();
    pWin1.moveTo(w * 0.46, h * 0.30);
    pWin1.lineTo(w * 0.32, h * 0.48);
    pWin1.lineTo(w * 0.55, h * 0.48);
    pWin1.lineTo(w * 0.55, h * 0.30);
    pWin1.close();
    canvas.drawPath(pWin1, Paint()..color = color.withValues(alpha: 0.40));

    final pWin2 = Path();
    pWin2.moveTo(w * 0.57, h * 0.30);
    pWin2.lineTo(w * 0.57, h * 0.48);
    pWin2.lineTo(w * 0.78, h * 0.48);
    pWin2.lineTo(w * 0.68, h * 0.30);
    pWin2.close();
    canvas.drawPath(pWin2, Paint()..color = color.withValues(alpha: 0.40));

    // Línea de cintura / nervadura deportiva
    canvas.drawLine(
      Offset(w * 0.18, h * 0.54),
      Offset(w * 0.88, h * 0.54),
      linePaint,
    );

    // Luces delanteras y traseras estilizadas
    canvas.drawLine(
      Offset(w * 0.06, h * 0.58),
      Offset(w * 0.16, h * 0.54),
      Paint()..color = color.withValues(alpha: 0.8)..strokeWidth = 1.5,
    );
    canvas.drawLine(
      Offset(w * 0.94, h * 0.58),
      Offset(w * 0.88, h * 0.54),
      Paint()..color = color.withValues(alpha: 0.8)..strokeWidth = 1.5,
    );

    // Ruedas con rin deportivo
    final rw = h * 0.14;
    _dibujarRuedaConDetalle(canvas, Offset(w * 0.24, h * 0.74), rw, color);
    _dibujarRuedaConDetalle(canvas, Offset(w * 0.76, h * 0.74), rw, color);
  }

  @override
  bool shouldRepaint(covariant _PainterAutomovil old) => old.color != color;
}

/// 2. SUV / Crossover / 4x4 Cerrado (Sahara, Prado, CX-30, etc. - con barras, compuerta y rines offroad)
class _PainterSuv extends CustomPainter {
  const _PainterSuv({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    // Carrocería SUV robusta y alta
    final p = Path();
    p.moveTo(w * 0.04, h * 0.74);
    p.lineTo(w * 0.08, h * 0.50);
    p.lineTo(w * 0.26, h * 0.42);
    p.lineTo(w * 0.40, h * 0.18);
    p.lineTo(w * 0.84, h * 0.18);
    p.lineTo(w * 0.88, h * 0.28);
    p.lineTo(w * 0.88, h * 0.60);
    p.lineTo(w * 0.94, h * 0.64);
    p.lineTo(w * 0.94, h * 0.74);
    p.close();
    canvas.drawPath(p, paint);

    // Barras de techo longitudinales con anclajes
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.44, h * 0.12, w * 0.38, h * 0.035),
        const Radius.circular(2),
      ),
      paint,
    );
    canvas.drawRect(Rect.fromLTWH(w * 0.47, h * 0.155, w * 0.03, h * 0.025), paint);
    canvas.drawRect(Rect.fromLTWH(w * 0.76, h * 0.155, w * 0.03, h * 0.025), paint);

    // Ventanas laterales SUV (delantera, trasera y custodia posterior)
    final glassPaint = Paint()..color = color.withValues(alpha: 0.40);
    final pWin1 = Path();
    pWin1.moveTo(w * 0.42, h * 0.23);
    pWin1.lineTo(w * 0.30, h * 0.41);
    pWin1.lineTo(w * 0.52, h * 0.41);
    pWin1.lineTo(w * 0.52, h * 0.23);
    pWin1.close();
    canvas.drawPath(pWin1, glassPaint);

    final pWin2 = Path();
    pWin2.moveTo(w * 0.54, h * 0.23);
    pWin2.lineTo(w * 0.54, h * 0.41);
    pWin2.lineTo(w * 0.70, h * 0.41);
    pWin2.lineTo(w * 0.70, h * 0.23);
    pWin2.close();
    canvas.drawPath(pWin2, glassPaint);

    final pWin3 = Path();
    pWin3.moveTo(w * 0.72, h * 0.23);
    pWin3.lineTo(w * 0.72, h * 0.41);
    pWin3.lineTo(w * 0.83, h * 0.41);
    pWin3.lineTo(w * 0.81, h * 0.23);
    pWin3.close();
    canvas.drawPath(pWin3, glassPaint);

    // Nervadura lateral y protector de bajos
    canvas.drawLine(Offset(w * 0.26, h * 0.46), Offset(w * 0.86, h * 0.46), linePaint);
    canvas.drawLine(
      Offset(w * 0.38, h * 0.72),
      Offset(w * 0.64, h * 0.72),
      Paint()..color = color..strokeWidth = 2.0,
    );

    // Ruedas todoterreno con pernos 4x4
    final rw = h * 0.15;
    _dibujarRuedaConDetalle(canvas, Offset(w * 0.22, h * 0.76), rw, color, offroad: true);
    _dibujarRuedaConDetalle(canvas, Offset(w * 0.78, h * 0.76), rw, color, offroad: true);
  }

  @override
  bool shouldRepaint(covariant _PainterSuv old) => old.color != color;
}

/// 3. Pick-up / Camioneta con Platón (Hilux, Ranger - con barra antivuelco, compuerta y platón abierto)
class _PainterPickup extends CustomPainter {
  const _PainterPickup({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    // Cabina + platón de carga
    final p = Path();
    p.moveTo(w * 0.04, h * 0.74);
    p.lineTo(w * 0.08, h * 0.50);
    p.lineTo(w * 0.28, h * 0.44);
    p.lineTo(w * 0.42, h * 0.20);
    p.lineTo(w * 0.64, h * 0.20);
    p.lineTo(w * 0.64, h * 0.48); // Caída hacia platón
    p.lineTo(w * 0.94, h * 0.48); // Borde superior platón
    p.lineTo(w * 0.94, h * 0.74);
    p.close();
    canvas.drawPath(p, paint);

    // Barra antivuelco / Roll-bar en el platón
    final pRoll = Path();
    pRoll.moveTo(w * 0.65, h * 0.22);
    pRoll.lineTo(w * 0.68, h * 0.22);
    pRoll.lineTo(w * 0.76, h * 0.48);
    pRoll.lineTo(w * 0.73, h * 0.48);
    pRoll.close();
    canvas.drawPath(pRoll, paint);

    // Ventanas de cabina
    final glassPaint = Paint()..color = color.withValues(alpha: 0.40);
    final pWin1 = Path();
    pWin1.moveTo(w * 0.44, h * 0.24);
    pWin1.lineTo(w * 0.32, h * 0.43);
    pWin1.lineTo(w * 0.51, h * 0.43);
    pWin1.lineTo(w * 0.51, h * 0.24);
    pWin1.close();
    canvas.drawPath(pWin1, glassPaint);

    final pWin2 = Path();
    pWin2.moveTo(w * 0.53, h * 0.24);
    pWin2.lineTo(w * 0.53, h * 0.43);
    pWin2.lineTo(w * 0.62, h * 0.43);
    pWin2.lineTo(w * 0.62, h * 0.24);
    pWin2.close();
    canvas.drawPath(pWin2, glassPaint);

    // Separación cabina-platón y manija de compuerta
    canvas.drawLine(Offset(w * 0.65, h * 0.48), Offset(w * 0.65, h * 0.72), linePaint);
    canvas.drawCircle(Offset(w * 0.92, h * 0.54), 1.2, Paint()..color = color);

    // Estribo lateral
    canvas.drawLine(
      Offset(w * 0.38, h * 0.74),
      Offset(w * 0.60, h * 0.74),
      Paint()..color = color..strokeWidth = 2.0,
    );

    // Ruedas all-terrain
    final rw = h * 0.15;
    _dibujarRuedaConDetalle(canvas, Offset(w * 0.24, h * 0.76), rw, color, offroad: true);
    _dibujarRuedaConDetalle(canvas, Offset(w * 0.78, h * 0.76), rw, color, offroad: true);
  }

  @override
  bool shouldRepaint(covariant _PainterPickup old) => old.color != color;
}

/// 4. Camión Pesado / Heavy Duty Dually (F-450, Silverado 3500 HD - doble rueda dually y trompa masiva)
class _PainterCamionPesado extends CustomPainter {
  const _PainterCamionPesado({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    // Frente alto imponente y cabina Heavy Duty
    final p = Path();
    p.moveTo(w * 0.02, h * 0.76);
    p.lineTo(w * 0.05, h * 0.36);
    p.lineTo(w * 0.30, h * 0.36);
    p.lineTo(w * 0.44, h * 0.14);
    p.lineTo(w * 0.66, h * 0.14);
    p.lineTo(w * 0.66, h * 0.42);
    p.lineTo(w * 0.96, h * 0.42);
    p.lineTo(w * 0.96, h * 0.76);
    p.close();
    canvas.drawPath(p, paint);

    // Visera / Luces de techo de cabina Heavy Duty
    canvas.drawRect(Rect.fromLTWH(w * 0.42, h * 0.10, w * 0.25, h * 0.035), paint);

    // Guardabarro abombado dually sobre las ruedas traseras
    final pFender = Path();
    pFender.moveTo(w * 0.64, h * 0.42);
    pFender.quadraticBezierTo(w * 0.80, h * 0.30, w * 0.96, h * 0.42);
    pFender.lineTo(w * 0.96, h * 0.58);
    pFender.lineTo(w * 0.64, h * 0.58);
    pFender.close();
    canvas.drawPath(pFender, paint);

    // Ventanas de cabina grande
    final glassPaint = Paint()..color = color.withValues(alpha: 0.40);
    final pWin = Path();
    pWin.moveTo(w * 0.46, h * 0.18);
    pWin.lineTo(w * 0.34, h * 0.36);
    pWin.lineTo(w * 0.64, h * 0.36);
    pWin.lineTo(w * 0.64, h * 0.18);
    pWin.close();
    canvas.drawPath(pWin, glassPaint);

    // Parrilla cromada masiva al frente
    canvas.drawLine(Offset(w * 0.05, h * 0.42), Offset(w * 0.05, h * 0.66), Paint()..color = color..strokeWidth = 2.5);
    canvas.drawLine(Offset(w * 0.10, h * 0.46), Offset(w * 0.10, h * 0.66), linePaint);

    // Rueda delantera + doble rueda trasera Dually (tandem escalonado)
    final rw = h * 0.16;
    _dibujarRuedaConDetalle(canvas, Offset(w * 0.22, h * 0.76), rw, color, dually: true);
    _dibujarRuedaConDetalle(canvas, Offset(w * 0.73, h * 0.76), rw, color, dually: true);
    _dibujarRuedaConDetalle(canvas, Offset(w * 0.86, h * 0.76), rw * 0.95, color, dually: true);
  }

  @override
  bool shouldRepaint(covariant _PainterCamionPesado old) => old.color != color;
}

/// 5. Camión Ligero / Cabover / Furgón Urbano (NPR, Hino - cabina chata y furgón con corrugado)
class _PainterCamionLigero extends CustomPainter {
  const _PainterCamionLigero({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    // Cabina chata vertical al frente + furgón comercial alto
    final p = Path();
    p.moveTo(w * 0.06, h * 0.76);
    p.lineTo(w * 0.06, h * 0.24);
    p.lineTo(w * 0.28, h * 0.24);
    p.lineTo(w * 0.28, h * 0.10);
    p.lineTo(w * 0.96, h * 0.10);
    p.lineTo(w * 0.96, h * 0.76);
    p.close();
    canvas.drawPath(p, paint);

    // Deflector aerodinámico sobre cabina
    final pDeflector = Path();
    pDeflector.moveTo(w * 0.08, h * 0.24);
    pDeflector.lineTo(w * 0.28, h * 0.10);
    pDeflector.lineTo(w * 0.28, h * 0.24);
    pDeflector.close();
    canvas.drawPath(pDeflector, Paint()..color = color.withValues(alpha: 0.60));

    // Gran parabrisas panorámico vertical
    final pWin = Path();
    pWin.moveTo(w * 0.08, h * 0.28);
    pWin.lineTo(w * 0.08, h * 0.46);
    pWin.lineTo(w * 0.26, h * 0.46);
    pWin.lineTo(w * 0.26, h * 0.28);
    pWin.close();
    canvas.drawPath(pWin, Paint()..color = color.withValues(alpha: 0.40));

    // Nervaduras / paneles corrugados del furgón de carga
    canvas.drawLine(Offset(w * 0.32, h * 0.28), Offset(w * 0.92, h * 0.28), linePaint);
    canvas.drawLine(Offset(w * 0.32, h * 0.46), Offset(w * 0.92, h * 0.46), linePaint);
    canvas.drawLine(Offset(w * 0.32, h * 0.62), Offset(w * 0.92, h * 0.62), linePaint);

    // Separación cabina y furgón
    canvas.drawLine(Offset(w * 0.29, h * 0.12), Offset(w * 0.29, h * 0.76), Paint()..color = color..strokeWidth = 1.5);

    final rw = h * 0.15;
    _dibujarRuedaConDetalle(canvas, Offset(w * 0.20, h * 0.76), rw, color, offroad: true);
    _dibujarRuedaConDetalle(canvas, Offset(w * 0.78, h * 0.76), rw, color, offroad: true);
  }

  @override
  bool shouldRepaint(covariant _PainterCamionLigero old) => old.color != color;
}

/// 6. Tractomula / Tractocamión americano (Kenworth, Mack - trompudo, camarote, chimeneas y 3 ejes)
class _PainterTractomula extends CustomPainter {
  const _PainterTractomula({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    // Capó trompudo clásico + camarote alto + chasis tándem
    final p = Path();
    p.moveTo(w * 0.04, h * 0.76);
    p.lineTo(w * 0.04, h * 0.40);
    p.lineTo(w * 0.36, h * 0.40);
    p.lineTo(w * 0.48, h * 0.16);
    p.lineTo(w * 0.68, h * 0.16);
    p.lineTo(w * 0.68, h * 0.58);
    p.lineTo(w * 0.96, h * 0.58);
    p.lineTo(w * 0.96, h * 0.76);
    p.close();
    canvas.drawPath(p, paint);

    // Parrilla cromada vertical clásica
    canvas.drawRect(Rect.fromLTWH(w * 0.04, h * 0.42, w * 0.04, h * 0.28), Paint()..color = color);
    canvas.drawLine(Offset(w * 0.08, h * 0.44), Offset(w * 0.36, h * 0.44), linePaint);

    // Chimeneas de escape cromadas dobles con puntas anguladas
    final pChim1 = Path();
    pChim1.moveTo(w * 0.48, h * 0.46);
    pChim1.lineTo(w * 0.48, h * 0.04);
    pChim1.lineTo(w * 0.51, h * 0.02);
    pChim1.lineTo(w * 0.51, h * 0.46);
    pChim1.close();
    canvas.drawPath(pChim1, paint);

    final pChim2 = Path();
    pChim2.moveTo(w * 0.66, h * 0.56);
    pChim2.lineTo(w * 0.66, h * 0.04);
    pChim2.lineTo(w * 0.69, h * 0.02);
    pChim2.lineTo(w * 0.69, h * 0.56);
    pChim2.close();
    canvas.drawPath(pChim2, paint);

    // Ventana de cabina y ventanilla del camarote sleeper
    final glassPaint = Paint()..color = color.withValues(alpha: 0.40);
    final pWin1 = Path();
    pWin1.moveTo(w * 0.49, h * 0.20);
    pWin1.lineTo(w * 0.38, h * 0.38);
    pWin1.lineTo(w * 0.56, h * 0.38);
    pWin1.lineTo(w * 0.56, h * 0.20);
    pWin1.close();
    canvas.drawPath(pWin1, glassPaint);

    // Ventanilla lateral del camarote
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.58, h * 0.24, w * 0.07, h * 0.10),
        const Radius.circular(2),
      ),
      glassPaint,
    );

    // Tanque de combustible cilíndrico debajo de la cabina
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.34, h * 0.64, w * 0.24, h * 0.08),
        const Radius.circular(3),
      ),
      paint,
    );

    // Quinta rueda (plato de acople) sobre el chasis trasero
    canvas.drawRect(Rect.fromLTWH(w * 0.80, h * 0.54, w * 0.08, h * 0.04), paint);

    // 3 ejes: 1 eje direccional delantero + 2 ejes tándem traseros con rines pesados
    final rw = h * 0.15;
    _dibujarRuedaConDetalle(canvas, Offset(w * 0.18, h * 0.76), rw, color, dually: true);
    _dibujarRuedaConDetalle(canvas, Offset(w * 0.74, h * 0.76), rw, color, dually: true);
    _dibujarRuedaConDetalle(canvas, Offset(w * 0.88, h * 0.76), rw, color, dually: true);
  }

  @override
  bool shouldRepaint(covariant _PainterTractomula old) => old.color != color;
}

/// 7. Van / Minivan / Furgón de Pasajeros (HiAce, Sprinter - monovolumen con ventanas panorámicas)
class _PainterVan extends CustomPainter {
  const _PainterVan({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    // Carrocería monovolumen aerodinámica
    final p = Path();
    p.moveTo(w * 0.04, h * 0.74);
    p.lineTo(w * 0.06, h * 0.52);
    p.lineTo(w * 0.20, h * 0.22);
    p.lineTo(w * 0.92, h * 0.22);
    p.lineTo(w * 0.92, h * 0.74);
    p.close();
    canvas.drawPath(p, paint);

    // 3 ventanales panorámicos de pasajeros
    final glassPaint = Paint()..color = color.withValues(alpha: 0.40);
    final pWin1 = Path();
    pWin1.moveTo(w * 0.22, h * 0.26);
    pWin1.lineTo(w * 0.11, h * 0.48);
    pWin1.lineTo(w * 0.36, h * 0.48);
    pWin1.lineTo(w * 0.36, h * 0.26);
    pWin1.close();
    canvas.drawPath(pWin1, glassPaint);

    final pWin2 = Path();
    pWin2.moveTo(w * 0.38, h * 0.26);
    pWin2.lineTo(w * 0.38, h * 0.48);
    pWin2.lineTo(w * 0.62, h * 0.48);
    pWin2.lineTo(w * 0.62, h * 0.26);
    pWin2.close();
    canvas.drawPath(pWin2, glassPaint);

    final pWin3 = Path();
    pWin3.moveTo(w * 0.64, h * 0.26);
    pWin3.lineTo(w * 0.64, h * 0.48);
    pWin3.lineTo(w * 0.88, h * 0.48);
    pWin3.lineTo(w * 0.88, h * 0.26);
    pWin3.close();
    canvas.drawPath(pWin3, glassPaint);

    // Riel inferior de puerta corrediza lateral
    canvas.drawLine(Offset(w * 0.36, h * 0.60), Offset(w * 0.88, h * 0.60), linePaint);

    final rw = h * 0.15;
    _dibujarRuedaConDetalle(canvas, Offset(w * 0.22, h * 0.76), rw, color);
    _dibujarRuedaConDetalle(canvas, Offset(w * 0.76, h * 0.76), rw, color);
  }

  @override
  bool shouldRepaint(covariant _PainterVan old) => old.color != color;
}
