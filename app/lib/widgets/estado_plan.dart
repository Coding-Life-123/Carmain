import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../models/plan_mantenimiento.dart';
import '../utils/formato.dart';

/// Icono, color y etiqueta de cada [EstadoItem]. Los colores salen del
/// [ColorScheme] (y del brillo para el ámbar) para que contrasten bien
/// tanto en tema claro como oscuro.
({IconData icon, Color color, String label}) estadoVisual(
  EstadoItem estado,
  ColorScheme cs,
) {
  final oscuro = cs.brightness == Brightness.dark;
  return switch (estado) {
    EstadoItem.vencido => (
        icon: Icons.warning_amber_rounded,
        color: cs.error,
        label: 'Vencido',
      ),
    EstadoItem.proximo => (
        icon: Icons.schedule,
        color: oscuro ? const Color(0xFFE5A94A) : const Color(0xFFB36B00),
        label: 'Próximo',
      ),
    EstadoItem.ok => (
        icon: Icons.check_circle,
        color: cs.tertiary,
        label: 'Al día',
      ),
    EstadoItem.desconocido => (
        icon: Icons.help_outline_rounded,
        color: oscuro ? const Color(0xFF8A8578) : const Color(0xFF6B665C),
        label: 'Sin registro',
      ),
  };
}

/// Conteo de ítems del plan por estado.
class ResumenPlan {
  const ResumenPlan({
    required this.vencidos,
    required this.proximos,
    required this.alDia,
    this.desconocidos = 0,
  });

  final int vencidos;
  final int proximos;
  final int alDia;
  final int desconocidos;

  int get total => vencidos + proximos + alDia + desconocidos;

  /// Estado más urgente presente en el plan.
  EstadoItem get peor => vencidos > 0
      ? EstadoItem.vencido
      : proximos > 0
          ? EstadoItem.proximo
          : desconocidos > 0
              ? EstadoItem.desconocido
              : EstadoItem.ok;

  factory ResumenPlan.de(
    PlanMantenimiento? plan,
    int kmActual,
    TipoUso tipoUso, {
    double? kmPorDia,
    DateTime? ahora,
  }) {
    var v = 0, p = 0, o = 0, d = 0;
    for (final item in plan?.items ?? const <ItemMantenimiento>[]) {
      switch (item.estado(kmActual, tipoUso, kmPorDia: kmPorDia, ahora: ahora)) {
        case EstadoItem.vencido:
          v++;
        case EstadoItem.proximo:
          p++;
        case EstadoItem.ok:
          o++;
        case EstadoItem.desconocido:
          d++;
      }
    }
    return ResumenPlan(vencidos: v, proximos: p, alDia: o, desconocidos: d);
  }
}

/// Texto legible de los km restantes de un ítem
/// ("Faltan 1.200 km" / "Vencido hace 300 km").
String textoKmRestantes(int restantes) => restantes <= 0
    ? 'Vencido hace ${formatearKm(-restantes)}'
    : 'Faltan ${formatearKm(restantes)}';

/// Texto legible del estado de un ítem considerando distancia, tiempo y ritmo de uso diario.
String textoEstadoDetalle(
  ItemMantenimiento item,
  int kmActual,
  TipoUso tipoUso, {
  double? kmPorDia,
  DateTime? ahora,
}) {
  final st = item.estado(kmActual, tipoUso, kmPorDia: kmPorDia, ahora: ahora);
  if (st == EstadoItem.desconocido) {
    return 'Sin registro — verificar';
  }

  final restKm = item.kmRestantes(kmActual, tipoUso);
  final restDias = item.diasRestantesEfectivos(
    kmActual,
    tipoUso,
    kmPorDia: kmPorDia,
    ahora: ahora,
  );

  if (restKm <= 0) {
    return 'Vencido hace ${formatearKm(-restKm)}';
  }
  if (restDias != null && restDias <= 0) {
    final diasV = -restDias;
    return diasV == 1
        ? 'Vencido por tiempo (hace 1 día)'
        : 'Vencido por tiempo (hace $diasV días)';
  }

  final kmTexto = 'Faltan ${formatearKm(restKm)}';
  if (restDias != null) {
    if (restDias <= 15) {
      return '$kmTexto · ¡Quedan ~$restDias días!';
    }
    if (restDias <= 35) {
      return '$kmTexto · Quedan ~$restDias días';
    }
    final meses = (restDias / 30.4375).round();
    return meses <= 1 ? '$kmTexto · ~1 mes' : '$kmTexto · ~$meses meses';
  }

  return kmTexto;
}

/// Pill compacto con icono + texto coloreado según un estado.
class EstadoPill extends StatelessWidget {
  const EstadoPill({
    super.key,
    required this.estado,
    this.texto,
    this.dense = false,
  });

  final EstadoItem estado;

  /// Si es null se usa la etiqueta por defecto del estado.
  final String? texto;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final visual = estadoVisual(estado, Theme.of(context).colorScheme);
    final labelTexto = texto ?? visual.label;
    return Semantics(
      label: 'Estado de mantenimiento: $labelTexto',
      container: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10,
          vertical: dense ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: visual.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: visual.color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(visual.icon, size: dense ? 13 : 14, color: visual.color),
            const SizedBox(width: 4),
            Text(
              labelTexto,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: visual.color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila de pills con el resumen del plan: "2 vencidos · 1 próximo" o
/// "Al día" si todo está en orden. Pensada para la tarjeta del dashboard.
class ResumenPlanPills extends StatelessWidget {
  const ResumenPlanPills({super.key, required this.resumen});

  final ResumenPlan resumen;

  @override
  Widget build(BuildContext context) {
    if (resumen.total == 0) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (resumen.vencidos > 0)
          EstadoPill(
            estado: EstadoItem.vencido,
            texto: resumen.vencidos == 1
                ? '1 vencido'
                : '${resumen.vencidos} vencidos',
          ),
        if (resumen.proximos > 0)
          EstadoPill(
            estado: EstadoItem.proximo,
            texto: resumen.proximos == 1
                ? '1 próximo'
                : '${resumen.proximos} próximos',
          ),
        if (resumen.desconocidos > 0)
          EstadoPill(
            estado: EstadoItem.desconocido,
            texto: resumen.desconocidos == 1
                ? '1 sin registro'
                : '${resumen.desconocidos} sin registro',
          ),
        if (resumen.vencidos == 0 &&
            resumen.proximos == 0 &&
            resumen.desconocidos == 0 &&
            resumen.alDia > 0)
          const EstadoPill(estado: EstadoItem.ok, texto: 'Todo al día'),
      ],
    );
  }
}
