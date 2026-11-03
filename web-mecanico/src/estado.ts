import type { SnapshotItemPlan, TipoUso, EstadoItem } from './types.ts';

export function intervaloEfectivoKm(item: SnapshotItemPlan, tipoUso: TipoUso): number {
  if (tipoUso === 'severo') {
    return item.intervaloSeveroKm ?? Math.round(item.intervaloKm * 0.7);
  }
  return item.intervaloKm;
}

export function intervaloEfectivoMeses(item: SnapshotItemPlan, tipoUso: TipoUso): number | undefined {
  if (item.intervaloMeses === undefined || item.intervaloMeses === null) return undefined;
  if (tipoUso === 'severo') {
    return Math.floor(item.intervaloMeses / 2);
  }
  return item.intervaloMeses;
}

function sumarMeses(base: Date, meses: number): Date {
  const d = new Date(base.getTime());
  const diaDeseado = d.getDate();
  d.setDate(1);
  d.setMonth(d.getMonth() + meses);
  // Clamping de fin de mes
  const maxDiasEnMes = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
  d.setDate(Math.min(diaDeseado, maxDiasEnMes));
  return d;
}

export function calcularEstadoItem(
  item: SnapshotItemPlan,
  kmActual: number,
  tipoUso: TipoUso
): EstadoItem {
  // Sin registro previo y odómetro > 0 -> desconocido
  if (
    kmActual > 0 &&
    (item.ultimaVezKm === undefined || item.ultimaVezKm === null) &&
    (item.ultimaVezFecha === undefined || item.ultimaVezFecha === null)
  ) {
    return 'desconocido';
  }

  const intKm = intervaloEfectivoKm(item, tipoUso);
  const intMeses = intervaloEfectivoMeses(item, tipoUso);

  const ultimaKm = item.ultimaVezKm ?? 0;
  const kmTranscurridos = kmActual - ultimaKm;
  const kmRestantes = intKm - kmTranscurridos;

  // Umbral relativo: 12% del intervalo, clamp [500, 10000]
  const umbralKm = Math.min(Math.max(Math.round(intKm * 0.12), 500), 10000);

  let vencidoPorKm = false;
  let proximoPorKm = false;

  if (kmRestantes <= 0) {
    vencidoPorKm = true;
  } else if (kmRestantes <= umbralKm) {
    proximoPorKm = true;
  }

  let vencidoPorFecha = false;
  let proximoPorFecha = false;

  if (intMeses !== undefined && item.ultimaVezFecha) {
    const baseFecha = new Date(item.ultimaVezFecha);
    if (!isNaN(baseFecha.getTime())) {
      const fechaVencimiento = sumarMeses(baseFecha, intMeses);
      const ahora = new Date();
      const diffDias = Math.floor(
        (fechaVencimiento.getTime() - ahora.getTime()) / (1000 * 60 * 60 * 24)
      );

      if (diffDias <= 0) {
        vencidoPorFecha = true;
      } else if (diffDias <= 35) {
        proximoPorFecha = true;
      }
    }
  }

  if (vencidoPorKm || vencidoPorFecha) return 'vencido';
  if (proximoPorKm || proximoPorFecha) return 'proximo';
  return 'ok';
}

export function formatearNumero(valor: number): string {
  const parts = Math.round(valor).toString().split('');
  let result = '';
  for (let i = 0; i < parts.length; i++) {
    if (i > 0 && (parts.length - i) % 3 === 0) {
      result += '.';
    }
    result += parts[i];
  }
  return result;
}

export function formatearCop(valor: number): string {
  if (valor < 0) {
    return `-$ ${formatearNumero(Math.abs(valor))}`;
  }
  return `$ ${formatearNumero(valor)}`;
}

export function formatearKm(km: number): string {
  return `${formatearNumero(km)} km`;
}

