import 'package:flutter/material.dart';

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

  /// Parámetro obsoleto conservado por compatibilidad de firma.
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

/// Silueta / imagen vectorial del vehículo para colocar de fondo
/// detrás del nombre de la marca, modelo y año.
class VehiculoSiluetaFondo extends StatelessWidget {
  const VehiculoSiluetaFondo({
    super.key,
    this.width = 140,
    this.height = 70,
    this.color,
    this.opacity = 0.16,
    this.alignment = Alignment.centerRight,
  });

  final double width;
  final double height;
  final Color? color;
  final double opacity;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = (color ?? cs.onSurface).withValues(alpha: opacity);

    return Align(
      alignment: alignment,
      child: SizedBox(
        width: width,
        height: height,
        child: Image.asset(
          'assets/images/auto_generico.png',
          fit: BoxFit.contain,
          color: tint,
          errorBuilder: (_, _, _) => CustomPaint(
            painter: _AutoGenericoPainter(color: tint),
          ),
        ),
      ),
    );
  }
}

/// Fallback elegante cuando el logo no está disponible o no hay red:
/// muestra la inicial de la marca con tipografía estilizada.
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

/// Painter vectorial de respaldo para la silueta del vehículo si no carga el asset.
class _AutoGenericoPainter extends CustomPainter {
  const _AutoGenericoPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    // Silueta simplificada de un automóvil
    final path = Path();
    path.moveTo(w * 0.08, h * 0.72);
    path.lineTo(w * 0.12, h * 0.58);
    path.lineTo(w * 0.30, h * 0.50);
    path.lineTo(w * 0.44, h * 0.28);
    path.lineTo(w * 0.68, h * 0.28);
    path.lineTo(w * 0.84, h * 0.50);
    path.lineTo(w * 0.94, h * 0.58);
    path.lineTo(w * 0.92, h * 0.72);
    path.close();

    canvas.drawPath(path, paint);

    // Ruedas
    final rWheel = h * 0.14;
    canvas.drawCircle(Offset(w * 0.28, h * 0.74), rWheel, paint);
    canvas.drawCircle(Offset(w * 0.74, h * 0.74), rWheel, paint);
  }

  @override
  bool shouldRepaint(covariant _AutoGenericoPainter oldDelegate) =>
      oldDelegate.color != color;
}
