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
  if (s.contains('rolls')) return 'rolls-royce';
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

  // 6. SUV / Crossover / 4x4 Cerrado (Prado, Fortuner, CX-30, Tracker, Duster, Tucson, etc.)
  final esSuv = norm.contains('prado') ||
      norm.contains('fortuner') ||
      norm.contains('4runner') ||
      norm.contains('landcruiser') ||
      norm.contains('fjcruiser') ||
      norm.contains('rav4') ||
      norm.contains('corollacross') ||
      norm.contains('yariscross') ||
      norm.contains('rush') ||
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
      norm.contains('montero') ||
      norm.contains('nativa') ||
      norm.contains('outlander') ||
      norm.contains('asx') ||
      norm.contains('eclipsecross') ||
      norm.contains('duster') ||
      norm.contains('koleos') ||
      norm.contains('captur') ||
      norm.contains('cx3') ||
      norm.contains('cx30') ||
      norm.contains('cx5') ||
      norm.contains('cx50') ||
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
      norm.contains('x1') ||
      norm.contains('x3') ||
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
      norm.contains('crossover');

  if (esSuv) {
    return TipoSiluetaVehiculo.suv;
  }

  // 7. Por defecto: Automóvil / Sedán / Coupé / Hatchback (Spark, Supra, Corolla Sedán, etc.)
  return TipoSiluetaVehiculo.automovil;
}

/// Avatar de marca del vehículo: muestra exclusivamente el logo oficial
/// de la marca (o su inicial estilizada como fallback).
class VehiculoAvatar extends StatelessWidget {
  const VehiculoAvatar({
    super.key,
    required this.marca,
    this.size = 56,
    this.width,
    this.height,
    this.borderRadius = 16,
    this.backgroundColor,
    this.colorFondoAuto,
  });

  final String marca;
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
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: slug.isNotEmpty
          ? Padding(
              padding: EdgeInsets.all(w * 0.12),
              child: Image.network(
                logoUrl,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => _FallbackMarca(
                  marca: marca,
                  color: cs.primary,
                  size: w * 0.40,
                ),
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return _FallbackMarca(
                    marca: marca,
                    color: cs.primary.withValues(alpha: 0.5),
                    size: w * 0.36,
                  );
                },
              ),
            )
          : _FallbackMarca(
              marca: marca,
              color: cs.primary,
              size: w * 0.40,
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
// PAINTERS VECTORIALES POR CATEGORÍA
// ─────────────────────────────────────────────────────────────────────────────

/// 1. Automóvil / Sedán / Coupé / Compacto
class _PainterAutomovil extends CustomPainter {
  const _PainterAutomovil({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    final p = Path();
    p.moveTo(w * 0.04, h * 0.72);
    p.lineTo(w * 0.10, h * 0.58);
    p.lineTo(w * 0.28, h * 0.50);
    p.lineTo(w * 0.42, h * 0.26);
    p.lineTo(w * 0.68, h * 0.26);
    p.lineTo(w * 0.82, h * 0.50);
    p.lineTo(w * 0.96, h * 0.58);
    p.lineTo(w * 0.94, h * 0.72);
    p.close();

    canvas.drawPath(p, paint);

    final rw = h * 0.14;
    canvas.drawCircle(Offset(w * 0.24, h * 0.74), rw, paint);
    canvas.drawCircle(Offset(w * 0.76, h * 0.74), rw, paint);
  }

  @override
  bool shouldRepaint(covariant _PainterAutomovil old) => old.color != color;
}

/// 2. SUV / Crossover / 4x4 Cerrado
class _PainterSuv extends CustomPainter {
  const _PainterSuv({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    final p = Path();
    p.moveTo(w * 0.04, h * 0.74);
    p.lineTo(w * 0.08, h * 0.52);
    p.lineTo(w * 0.26, h * 0.44);
    p.lineTo(w * 0.40, h * 0.20);
    p.lineTo(w * 0.84, h * 0.20);
    p.lineTo(w * 0.88, h * 0.30);
    p.lineTo(w * 0.88, h * 0.60);
    p.lineTo(w * 0.94, h * 0.64);
    p.lineTo(w * 0.94, h * 0.74);
    p.close();

    canvas.drawPath(p, paint);

    // Barras de techo
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.44, h * 0.13, w * 0.36, h * 0.04),
        const Radius.circular(2),
      ),
      paint,
    );

    final rw = h * 0.15;
    canvas.drawCircle(Offset(w * 0.22, h * 0.76), rw, paint);
    canvas.drawCircle(Offset(w * 0.78, h * 0.76), rw, paint);
  }

  @override
  bool shouldRepaint(covariant _PainterSuv old) => old.color != color;
}

/// 3. Pick-up / Camioneta con Platón
class _PainterPickup extends CustomPainter {
  const _PainterPickup({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    final p = Path();
    p.moveTo(w * 0.04, h * 0.74);
    p.lineTo(w * 0.08, h * 0.52);
    p.lineTo(w * 0.28, h * 0.46);
    p.lineTo(w * 0.42, h * 0.22);
    p.lineTo(w * 0.64, h * 0.22);
    p.lineTo(w * 0.64, h * 0.48); // Caída vertical de cabina hacia el platón
    p.lineTo(w * 0.94, h * 0.48); // Borde superior del platón abierto
    p.lineTo(w * 0.94, h * 0.74); // Compuerta trasera
    p.close();

    canvas.drawPath(p, paint);

    final rw = h * 0.15;
    canvas.drawCircle(Offset(w * 0.24, h * 0.76), rw, paint);
    canvas.drawCircle(Offset(w * 0.78, h * 0.76), rw, paint);
  }

  @override
  bool shouldRepaint(covariant _PainterPickup old) => old.color != color;
}

/// 4. Camión Pesado / Heavy Duty Dually (F-450, F-350, Silverado 3500 HD)
class _PainterCamionPesado extends CustomPainter {
  const _PainterCamionPesado({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    // Frente masivo y cabina grande Heavy Duty
    final p = Path();
    p.moveTo(w * 0.02, h * 0.76);
    p.lineTo(w * 0.05, h * 0.38);
    p.lineTo(w * 0.30, h * 0.38);
    p.lineTo(w * 0.44, h * 0.16);
    p.lineTo(w * 0.66, h * 0.16);
    p.lineTo(w * 0.66, h * 0.42);
    p.lineTo(w * 0.96, h * 0.42);
    p.lineTo(w * 0.96, h * 0.76);
    p.close();

    canvas.drawPath(p, paint);

    // Guardabarro ensanchado dually sobre el platón trasero
    final pFender = Path();
    pFender.moveTo(w * 0.66, h * 0.42);
    pFender.quadraticBezierTo(w * 0.80, h * 0.32, w * 0.96, h * 0.42);
    pFender.lineTo(w * 0.96, h * 0.58);
    pFender.lineTo(w * 0.66, h * 0.58);
    pFender.close();
    canvas.drawPath(pFender, paint);

    // Rueda delantera + doble rueda trasera dually
    final rw = h * 0.16;
    canvas.drawCircle(Offset(w * 0.22, h * 0.76), rw, paint);
    canvas.drawCircle(Offset(w * 0.74, h * 0.76), rw, paint);
    canvas.drawCircle(Offset(w * 0.86, h * 0.76), rw, paint);
  }

  @override
  bool shouldRepaint(covariant _PainterCamionPesado old) => old.color != color;
}

/// 5. Camión Ligero / Cabover / Furgón Urbano (NPR, Hino, Fuso)
class _PainterCamionLigero extends CustomPainter {
  const _PainterCamionLigero({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    // Cabina chata vertical al frente + furgón de carga alto
    final p = Path();
    p.moveTo(w * 0.06, h * 0.76);
    p.lineTo(w * 0.06, h * 0.26);
    p.lineTo(w * 0.28, h * 0.26);
    p.lineTo(w * 0.28, h * 0.12);
    p.lineTo(w * 0.96, h * 0.12);
    p.lineTo(w * 0.96, h * 0.76);
    p.close();

    canvas.drawPath(p, paint);

    // Parabrisas vertical característico de cabina chata
    final pWin = Path();
    pWin.moveTo(w * 0.08, h * 0.30);
    pWin.lineTo(w * 0.08, h * 0.48);
    pWin.lineTo(w * 0.26, h * 0.48);
    pWin.lineTo(w * 0.26, h * 0.30);
    pWin.close();
    canvas.drawPath(pWin, Paint()..color = color.withValues(alpha: 0.45));

    final rw = h * 0.15;
    canvas.drawCircle(Offset(w * 0.20, h * 0.76), rw, paint);
    canvas.drawCircle(Offset(w * 0.78, h * 0.76), rw, paint);
  }

  @override
  bool shouldRepaint(covariant _PainterCamionLigero old) => old.color != color;
}

/// 6. Tractomula / Tractocamión americano (Kenworth, Mack, Cascadia)
class _PainterTractomula extends CustomPainter {
  const _PainterTractomula({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    // Capó trompudo largo + cabina con camarote + chasis tándem
    final p = Path();
    p.moveTo(w * 0.04, h * 0.76);
    p.lineTo(w * 0.04, h * 0.42);
    p.lineTo(w * 0.36, h * 0.42);
    p.lineTo(w * 0.48, h * 0.20);
    p.lineTo(w * 0.68, h * 0.20);
    p.lineTo(w * 0.68, h * 0.58);
    p.lineTo(w * 0.96, h * 0.58);
    p.lineTo(w * 0.96, h * 0.76);
    p.close();

    canvas.drawPath(p, paint);

    // Chimeneas de escape verticales
    canvas.drawRect(Rect.fromLTWH(w * 0.47, h * 0.06, w * 0.03, h * 0.36), paint);
    canvas.drawRect(Rect.fromLTWH(w * 0.66, h * 0.06, w * 0.03, h * 0.52), paint);

    // Eje direccional delantero + dos ejes tándem traseros (3 ejes)
    final rw = h * 0.15;
    canvas.drawCircle(Offset(w * 0.18, h * 0.76), rw, paint);
    canvas.drawCircle(Offset(w * 0.74, h * 0.76), rw, paint);
    canvas.drawCircle(Offset(w * 0.88, h * 0.76), rw, paint);
  }

  @override
  bool shouldRepaint(covariant _PainterTractomula old) => old.color != color;
}

/// 7. Van / Minivan / Furgón de Pasajeros (HiAce, Sprinter, Transit)
class _PainterVan extends CustomPainter {
  const _PainterVan({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    // Carrocería monovolumen continua
    final p = Path();
    p.moveTo(w * 0.04, h * 0.74);
    p.lineTo(w * 0.06, h * 0.54);
    p.lineTo(w * 0.20, h * 0.24);
    p.lineTo(w * 0.92, h * 0.24);
    p.lineTo(w * 0.92, h * 0.74);
    p.close();

    canvas.drawPath(p, paint);

    final rw = h * 0.15;
    canvas.drawCircle(Offset(w * 0.22, h * 0.76), rw, paint);
    canvas.drawCircle(Offset(w * 0.76, h * 0.76), rw, paint);
  }

  @override
  bool shouldRepaint(covariant _PainterVan old) => old.color != color;
}
