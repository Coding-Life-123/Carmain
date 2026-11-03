import { fetchSesion, enviarPropuesta, ApiError } from './api';
import {
  SesionPublicaRespuesta,
  SnapshotItemPlan,
  EstadoItem,
  PropuestaItemRealizado,
  CategoriaMantenimiento,
  TipoComponente,
} from './types';
import {
  calcularEstadoItem,
  formatearKm,
  formatearCop,
  formatearNumero,
  intervaloEfectivoKm,
  intervaloEfectivoMeses,
} from './estado';

interface AppState {
  codigoOToken: string | null;
  cargando: boolean;
  error: string | null;
  sesion: SesionPublicaRespuesta | null;
  tab: 'plan' | 'historial' | 'alertas';
  filtroEstado: 'todos' | EstadoItem;
  busqueda: string;
  itemsSeleccionados: Map<string, PropuestaItemRealizado>;
  // Modal de propuesta
  modalAbierto: boolean;
  propuestaEnviando: boolean;
  propuestaExito: boolean;
  propuestaError: string | null;
  // Campos del formulario
  kmServicio: number | '';
  fechaServicio: string;
  taller: string;
  mecanico: string;
  costo: number | null;
  costoTexto: string;
  notas: string;
  // Formulario ítem extra
  mostrarFormExtra: boolean;
  extraCategoria: CategoriaMantenimiento;
  extraComponente: TipoComponente;
  extraDescripcion: string;
}

const state: AppState = {
  codigoOToken: null,
  cargando: false,
  error: null,
  sesion: null,
  tab: 'plan',
  filtroEstado: 'todos',
  busqueda: '',
  itemsSeleccionados: new Map(),
  modalAbierto: false,
  propuestaEnviando: false,
  propuestaExito: false,
  propuestaError: null,
  kmServicio: '',
  fechaServicio: new Date().toISOString().split('T')[0],
  taller: '',
  mecanico: '',
  costo: null,
  costoTexto: '',
  notas: '',
  mostrarFormExtra: false,
  extraCategoria: 'motor',
  extraComponente: 'motor',
  extraDescripcion: '',
};

const appEl = document.getElementById('app')!;

function inicializarDesdeUrl() {
  const params = new URLSearchParams(window.location.search);
  const token = params.get('s') || params.get('token');
  const codigo = params.get('c') || params.get('codigo');

  if (token) {
    state.codigoOToken = token;
    cargarSesion(token);
  } else if (codigo) {
    state.codigoOToken = codigo;
    cargarSesion(codigo);
  } else {
    // Revisar pathname por si viene en formato /m/:codigo
    const pathParts = window.location.pathname.split('/').filter(Boolean);
    const mIdx = pathParts.indexOf('m');
    if (mIdx !== -1 && pathParts[mIdx + 1]) {
      const codeOrTok = pathParts[mIdx + 1];
      state.codigoOToken = codeOrTok;
      cargarSesion(codeOrTok);
    } else {
      render();
    }
  }
}

async function cargarSesion(codigoOToken: string) {
  state.cargando = true;
  state.error = null;
  render();

  try {
    const sesion = await fetchSesion(codigoOToken);
    state.sesion = sesion;
    state.kmServicio = sesion.snapshot.vehiculo.kilometrajeActual;
    state.cargando = false;
    render();
  } catch (err: any) {
    state.cargando = false;
    if (err instanceof ApiError) {
      state.error = err.message;
    } else {
      state.error = 'No se pudo conectar con el servidor. Verifica tu conexión.';
    }
    render();
  }
}

function formatearTiempoRestante(expiraIso: string): string {
  const expira = new Date(expiraIso);
  const diff = expira.getTime() - Date.now();
  if (diff <= 0) return 'Expirada';
  const mins = Math.floor(diff / 60000);
  if (mins < 60) return `Expira en ${mins}m`;
  const horas = Math.floor(mins / 60);
  if (horas < 24) return `Expira en ${horas}h ${mins % 60}m`;
  const dias = Math.floor(horas / 24);
  return `Expira en ${dias}d`;
}

function generarUuidV4(): string {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

function toggleItemPlan(item: SnapshotItemPlan) {
  if (state.itemsSeleccionados.has(item.id)) {
    state.itemsSeleccionados.delete(item.id);
  } else {
    state.itemsSeleccionados.set(item.id, {
      itemId: item.id,
      categoria: item.categoria,
      componenteAplica: item.componenteAplica,
      descripcion: item.descripcion,
    });
  }
  render();
}

function eliminarItemSeleccionado(id: string) {
  state.itemsSeleccionados.delete(id);
  render();
}

function agregarItemExtra() {
  const desc = state.extraDescripcion.trim();
  if (!desc) return;
  const extraId = `extra-${Date.now()}`;
  state.itemsSeleccionados.set(extraId, {
    categoria: state.extraCategoria,
    componenteAplica: state.extraComponente,
    descripcion: desc,
  });
  state.extraDescripcion = '';
  state.mostrarFormExtra = false;
  render();
}

async function enviarReporteServicio() {
  if (!state.sesion || !state.codigoOToken) return;

  const km = typeof state.kmServicio === 'number' ? state.kmServicio : Number(state.kmServicio);
  if (isNaN(km) || km < 0) {
    state.propuestaError = 'Ingresa un kilometraje válido.';
    render();
    return;
  }

  const kmActualSnapshot = state.sesion.snapshot.vehiculo.kilometrajeActual;
  if (km < kmActualSnapshot) {
    state.propuestaError = `El kilometraje (${formatearKm(km)}) no puede ser menor al actual (${formatearKm(kmActualSnapshot)}).`;
    render();
    return;
  }

  if (state.itemsSeleccionados.size === 0) {
    state.propuestaError = 'Debes marcar o agregar al menos un trabajo realizado.';
    render();
    return;
  }

  state.propuestaEnviando = true;
  state.propuestaError = null;
  render();

  try {
    const itemsRealizados = Array.from(state.itemsSeleccionados.values());
    const payload = {
      schema: 1,
      id: generarUuidV4(),
      creadaEn: new Date().toISOString(),
      mecanico: {
        taller: state.taller.trim() || undefined,
        nombre: state.mecanico.trim() || undefined,
      },
      kilometraje: km,
      fecha: state.fechaServicio,
      costo: state.costo ?? undefined,
      moneda: 'COP',
      notas: state.notas.trim() || undefined,
      itemsRealizados,
    };

    await enviarPropuesta(state.codigoOToken, payload);
    state.propuestaEnviando = false;
    state.propuestaExito = true;
    render();
  } catch (err: any) {
    state.propuestaEnviando = false;
    if (err instanceof ApiError) {
      state.propuestaError = err.message;
    } else {
      state.propuestaError = 'Error al enviar el reporte. Verifica tu conexión e inténtalo de nuevo.';
    }
    render();
  }
}

// ----------------------------------------------------
// Componentes de Renderizado HTML
// ----------------------------------------------------

function renderIngreso(): string {
  return `
    <div class="container">
      <header class="top-bar">
        <div class="brand">
          <div class="brand-logo">C</div>
          <div>
            <div class="brand-title">CarMain</div>
            <div style="font-size: 11px; color: var(--text-muted);">Portal de Taller</div>
          </div>
        </div>
      </header>

      <div class="card ingreso-box">
        <h2 style="font-family: var(--font-heading); font-size: 24px; margin-bottom: 8px;">Ficha del Vehículo</h2>
        <p style="color: var(--text-muted); font-size: 14px; max-width: 400px; margin: 0 auto;">
          Ingresa el código de 6 caracteres compartido por el propietario del vehículo.
        </p>

        <form id="form-ingreso" style="margin-top: 10px;">
          <input
            id="input-codigo"
            type="text"
            maxlength="6"
            placeholder="7X9K2A"
            class="codigo-input"
            autocomplete="off"
            autocapitalize="characters"
            spellcheck="false"
            required
          />

          <button type="submit" class="btn btn-primary btn-block" style="max-width: 280px; margin: 0 auto;">
            Ver Ficha Técnica
          </button>
        </form>

        <div style="margin-top: 32px; font-size: 13px; color: var(--text-muted);">
          ¿No tienes un código? Pídeselo al dueño desde su app CarMain en "Compartir con taller" (no es la placa del auto).
        </div>
      </div>
    </div>
  `;
}

function renderCargando(): string {
  return `
    <div class="container" style="text-align: center; padding-top: 80px;">
      <div class="brand-logo" style="margin: 0 auto 20px auto; width: 44px; height: 44px; font-size: 22px;">C</div>
      <div class="spinner"></div>
      <p style="color: var(--text-muted); font-size: 14px; margin-top: 16px;">Cargando ficha del vehículo...</p>
    </div>
  `;
}

function renderError(): string {
  return `
    <div class="container" style="padding-top: 40px;">
      <div class="card ingreso-box">
        <div style="font-size: 40px; margin-bottom: 12px;">⚠</div>
        <h2 style="font-family: var(--font-heading); font-size: 22px; margin-bottom: 8px;">No se pudo abrir la ficha</h2>
        <p style="color: var(--text-muted); font-size: 14px; margin-bottom: 24px;">
          ${state.error || 'La sesión no existe o ha expirado.'}
        </p>

        <button id="btn-reintentar" class="btn btn-primary" style="margin-right: 8px;">
          Reintentar
        </button>
        <button id="btn-otro-codigo" class="btn btn-outline">
          Ingresar otro código
        </button>
      </div>
    </div>
  `;
}

function renderFicha(): string {
  const s = state.sesion!;
  const v = s.snapshot.vehiculo;
  const p = s.snapshot.plan;
  const h = s.snapshot.historial || [];

  // Calcular estados de los ítems
  const itemsConEstado = p.items.map((item) => ({
    item,
    estado: calcularEstadoItem(item, v.kilometrajeActual, v.tipoUso),
    intKm: intervaloEfectivoKm(item, v.tipoUso),
    intMeses: intervaloEfectivoMeses(item, v.tipoUso),
  }));

  const conteoVencidos = itemsConEstado.filter((x) => x.estado === 'vencido').length;
  const conteoProximos = itemsConEstado.filter((x) => x.estado === 'proximo').length;
  const conteoOk = itemsConEstado.filter((x) => x.estado === 'ok').length;
  const conteoDesconocidos = itemsConEstado.filter((x) => x.estado === 'desconocido').length;

  const alertas = p.alertasIngenieria || [];

  // Filtrado de ítems
  const q = state.busqueda.toLowerCase().trim();
  const itemsFiltrados = itemsConEstado
    .filter((x) => {
      if (state.filtroEstado !== 'todos' && x.estado !== state.filtroEstado) return false;
      if (q) {
        return (
          x.item.descripcion.toLowerCase().includes(q) ||
          x.item.categoria.toLowerCase().includes(q)
        );
      }
      return true;
    })
    .sort((a, b) => {
      const orden: Record<EstadoItem, number> = { vencido: 0, proximo: 1, desconocido: 2, ok: 3 };
      return orden[a.estado] - orden[b.estado];
    });

  const tiempoRestante = formatearTiempoRestante(s.expiraEn);

  return `
    <div class="container">
      <!-- Top Bar -->
      <header class="top-bar">
        <div class="brand">
          <div class="brand-logo">C</div>
          <div>
            <div class="brand-title">CarMain · Taller</div>
            <div style="font-size: 11px; color: var(--text-muted);">${tiempoRestante}</div>
          </div>
        </div>
        <div class="badge-readonly">
          <span>🔒 Solo lectura</span>
        </div>
      </header>

      <!-- Vehículo Header -->
      <div class="card vehiculo-header">
        <div class="vehiculo-nombre">
          ${v.marca} ${v.modelo} ${v.anio}
        </div>
        ${v.trim ? `<div style="font-size: 14px; color: var(--text-muted);">${v.trim}</div>` : ''}

        <div class="vehiculo-meta">
          ${v.placa ? `<span class="chip" style="font-weight: 700; border-color: rgba(201,169,110,0.4);">${v.placa}</span>` : ''}
          <span class="chip">📍 ${formatearKm(v.kilometrajeActual)}</span>
          <span class="chip">⚙ ${v.drivetrain.toUpperCase()}</span>
          <span class="chip">${v.tipoUso === 'severo' ? '🚨 Uso Severo' : '🌱 Uso Normal'}</span>
          ${v.vin ? `<span class="chip" style="font-size: 11px;">VIN: ${v.vin}</span>` : ''}
        </div>

        ${v.notasUso ? `
          <div style="margin-top: 8px; font-size: 13px; color: var(--text-muted); background: var(--surface-card); padding: 8px 12px; border-radius: 8px;">
            💬 <i>${v.notasUso}</i>
          </div>
        ` : ''}
      </div>

      <!-- Motor y Transmisión -->
      <div class="card">
        <div class="card-title">
          <span>Componentes Mecánicos</span>
          ${v.motor.esSwap || v.transmision.esSwap ? '<span class="chip chip-swap">Modificado / Swap</span>' : ''}
        </div>

        <div style="display: flex; flex-direction: column; gap: 12px;">
          <!-- Motor -->
          <div style="background: var(--surface-card); padding: 12px; border-radius: var(--radius-sm);">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
              <span style="font-weight: 700; font-size: 15px;">Motor: ${v.motor.codigo}</span>
              ${v.motor.esSwap ? `<span class="chip chip-swap" style="font-size: 11px;">SWAP (Orig: ${v.motor.original || 'OEM'})</span>` : ''}
            </div>
            <div class="specs-grid">
              ${v.motor.cilindrada ? `<div class="spec-cell"><div class="spec-label">Cilindrada</div><div class="spec-value">${v.motor.cilindrada}L ${v.motor.cilindros ? `(${v.motor.cilindros} cyl)` : ''}</div></div>` : ''}
              ${v.motor.aspiracion ? `<div class="spec-cell"><div class="spec-label">Aspiración</div><div class="spec-value">${v.motor.aspiracion}</div></div>` : ''}
              ${v.motor.potenciaHp ? `<div class="spec-cell"><div class="spec-label">Potencia</div><div class="spec-value">${v.motor.potenciaHp} HP</div></div>` : ''}
              ${v.motor.torqueNm ? `<div class="spec-cell"><div class="spec-label">Torque</div><div class="spec-value">${v.motor.torqueNm} Nm</div></div>` : ''}
              ${v.motor.combustible ? `<div class="spec-cell"><div class="spec-label">Combustible</div><div class="spec-value">${v.motor.combustible}</div></div>` : ''}
            </div>
          </div>

          <!-- Transmisión -->
          <div style="background: var(--surface-card); padding: 12px; border-radius: var(--radius-sm);">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
              <span style="font-weight: 700; font-size: 15px;">Transmisión: ${v.transmision.codigo}</span>
              ${v.transmision.esSwap ? `<span class="chip chip-swap" style="font-size: 11px;">SWAP (Orig: ${v.transmision.original || 'OEM'})</span>` : ''}
            </div>
            <div class="specs-grid">
              ${v.transmision.tipo ? `<div class="spec-cell"><div class="spec-label">Tipo</div><div class="spec-value">${v.transmision.tipo}</div></div>` : ''}
              ${v.transmision.marchas ? `<div class="spec-cell"><div class="spec-label">Marchas</div><div class="spec-value">${v.transmision.marchas} vel</div></div>` : ''}
            </div>
          </div>
        </div>
      </div>

      <!-- Alertas de Ingeniería (si existen) -->
      ${alertas.length > 0 ? `
        <div class="card" style="border-color: rgba(245, 158, 11, 0.4);">
          <div class="card-title" style="color: var(--warning);">
            <span>⚠ Alertas de Swap / Vigilancia Técnica</span>
            <span class="count-badge proximo">${alertas.length}</span>
          </div>
          ${alertas.map((a) => `
            <div class="alerta-box ${a.severidad}">
              <div class="alerta-titulo">${a.titulo}</div>
              <div class="alerta-desc"><strong>Vector:</strong> ${a.vector} · <strong>Componente:</strong> ${a.componenteAfectado}</div>
              <div class="alerta-desc" style="margin-top: 4px;">${a.diagnostico}</div>
              ${a.recomendacionUpgrade ? `<div class="alerta-desc" style="margin-top: 4px; color: var(--primary);"><strong>Recomendación:</strong> ${a.recomendacionUpgrade}</div>` : ''}
            </div>
          `).join('')}
        </div>
      ` : ''}

      <!-- Pestañas Principales -->
      <div class="filtro-tabs" style="margin-top: 8px;">
        <button class="tab-btn ${state.tab === 'plan' ? 'activo' : ''}" data-tab="plan">
          Plan de Mantenimiento
        </button>
        ${h.length > 0 ? `
          <button class="tab-btn ${state.tab === 'historial' ? 'activo' : ''}" data-tab="historial">
            Historial Previo (${h.length})
          </button>
        ` : ''}
      </div>

      ${state.tab === 'plan' ? renderTabPlan(itemsFiltrados, conteoVencidos, conteoProximos, conteoOk, conteoDesconocidos) : ''}
      ${state.tab === 'historial' ? renderTabHistorial(h) : ''}

      <!-- Barra Flotante Inferior -->
      <div class="bottom-bar">
        <div class="bottom-bar-inner">
          <button id="btn-abrir-propuesta" class="btn btn-primary btn-block">
            🛠 Registrar Servicio Realizado
            ${state.itemsSeleccionados.size > 0 ? `(${state.itemsSeleccionados.size} seleccionados)` : ''}
          </button>
        </div>
      </div>

      <!-- Modal de Propuesta -->
      ${state.modalAbierto ? renderModalPropuesta() : ''}
    </div>
  `;
}

function renderTabPlan(
  items: Array<{
    item: SnapshotItemPlan;
    estado: EstadoItem;
    intKm: number;
    intMeses: number | undefined;
  }>,
  vencidos: number,
  proximos: number,
  ok: number,
  desconocidos: number
): string {
  return `
    <!-- Filtros de Urgencia -->
    <div class="filtro-tabs">
      <button class="tab-btn ${state.filtroEstado === 'todos' ? 'activo' : ''}" data-filtro="todos">
        Todos (${vencidos + proximos + ok + desconocidos})
      </button>
      <button class="tab-btn ${state.filtroEstado === 'vencido' ? 'activo' : ''}" data-filtro="vencido">
        ⚠ Vencidos <span class="count-badge vencido">${vencidos}</span>
      </button>
      <button class="tab-btn ${state.filtroEstado === 'proximo' ? 'activo' : ''}" data-filtro="proximo">
        ⏱ Próximos <span class="count-badge proximo">${proximos}</span>
      </button>
      <button class="tab-btn ${state.filtroEstado === 'ok' ? 'activo' : ''}" data-filtro="ok">
        ✔ Al día <span class="count-badge ok">${ok}</span>
      </button>
      <button class="tab-btn ${state.filtroEstado === 'desconocido' ? 'activo' : ''}" data-filtro="desconocido">
        ❔ Sin registro <span class="count-badge desconocido">${desconocidos}</span>
      </button>
    </div>

    <!-- Buscador -->
    <div class="search-box">
      <input
        type="search"
        id="input-busqueda"
        placeholder="Buscar tarea o repuesto..."
        class="search-input"
        value="${state.busqueda}"
      />
    </div>

    <!-- Lista de Ítems del Plan -->
    <div style="margin-top: 10px;">
      ${items.length === 0 ? `
        <div class="card empty-state">
          No se encontraron ítems de mantenimiento para este filtro.
        </div>
      ` : items.map(({ item, estado, intKm, intMeses }) => {
        const seleccionado = state.itemsSeleccionados.has(item.id);
        const kmRestantes = item.ultimaVezKm !== undefined && item.ultimaVezKm !== null
          ? intKm - (state.sesion!.snapshot.vehiculo.kilometrajeActual - item.ultimaVezKm)
          : null;

        let etiquetaKm = `Cada ${formatearNumero(intKm)} km`;
        if (intMeses) etiquetaKm += ` o ${intMeses} meses`;

        let textoDetalle = '';
        if (estado === 'vencido' && kmRestantes !== null && kmRestantes < 0) {
          textoDetalle = `Vencido hace ${formatearNumero(Math.abs(kmRestantes))} km`;
        } else if (estado === 'proximo' && kmRestantes !== null) {
          textoDetalle = `Faltan ${formatearNumero(kmRestantes)} km`;
        } else if (estado === 'ok') {
          textoDetalle = kmRestantes !== null ? `Al día (faltan ${formatearNumero(kmRestantes)} km)` : 'Al día';
        } else {
          textoDetalle = 'Sin registro previo de cambio';
        }

        return `
          <div class="checklist-item ${seleccionado ? 'seleccionado' : ''}" data-item-id="${item.id}">
            <div class="checkbox-custom">
              ${seleccionado ? '✔' : ''}
            </div>
            <div style="flex: 1; min-width: 0;">
              <div style="display: flex; justify-content: space-between; align-items: flex-start; gap: 8px;">
                <span class="item-desc">${item.descripcion}</span>
                <span class="estado-pill estado-${estado}">
                  ${estado === 'vencido' ? '⚠ Vencido' : estado === 'proximo' ? '⏱ Próximo' : estado === 'ok' ? '✔ Al día' : '❔ Sin registro'}
                </span>
              </div>
              <div class="item-meta" style="margin-top: 4px;">
                <span>${etiquetaKm}</span>
                <span style="font-weight: 600; color: ${estado === 'vencido' ? '#FCA5A5' : estado === 'proximo' ? '#FCD34D' : 'inherit'};">
                  ${textoDetalle}
                </span>
              </div>
              ${item.esVigilanciaSwap ? `
                <div style="margin-top: 4px;">
                  <span class="chip chip-swap" style="font-size: 11px; padding: 2px 8px;">Vigilancia Swap</span>
                </div>
              ` : ''}
            </div>
          </div>
        `;
      }).join('')}
    </div>
  `;
}

function renderTabHistorial(historial: any[]): string {
  return `
    <div style="display: flex; flex-direction: column; gap: 12px; margin-top: 10px;">
      ${historial.map((reg) => `
        <div class="card" style="margin-bottom: 0;">
          <div style="display: flex; justify-content: space-between; align-items: flex-start;">
            <div>
              <div style="font-weight: 700; font-size: 16px;">${formatearKm(reg.kilometraje)}</div>
              <div style="font-size: 12px; color: var(--text-muted);">${reg.fecha} ${reg.taller ? `· ${reg.taller}` : ''}</div>
            </div>
            <span class="estado-pill estado-ok" style="font-size: 10px;">
              ${reg.nivelVerificacion === 'selladoTaller' ? 'Nivel 3 · Sellado Taller' : 'Nivel 1 · Propietario'}
            </span>
          </div>

          <div style="margin-top: 10px; border-top: 1px solid var(--border); padding-top: 8px;">
            <div style="font-size: 12px; font-weight: 600; color: var(--text-muted); margin-bottom: 4px;">Trabajos realizados:</div>
            <ul style="padding-left: 18px; font-size: 13px;">
              ${reg.items.map((it: any) => `<li>${it.descripcion}</li>`).join('')}
            </ul>
          </div>

          ${reg.costo ? `
            <div style="margin-top: 8px; font-size: 13px; font-weight: 600; color: var(--primary);">
              Costo: ${formatearCop(reg.costo)}
            </div>
          ` : ''}
        </div>
      `).join('')}
    </div>
  `;
}

function renderModalPropuesta(): string {
  if (state.propuestaExito) {
    return `
      <div class="modal-overlay">
        <div class="modal-content">
          <div class="success-card">
            <div class="success-icon">✔</div>
            <h2 class="success-title">¡Propuesta Enviada!</h2>
            <p class="success-desc">
              Tu propuesta de servicio fue enviada con éxito. El dueño del vehículo recibirá la notificación en su app para revisarla y sellarla como <strong>Nivel 3 (Sellado por taller)</strong>.
            </p>
            <button id="btn-cerrar-exito" class="btn btn-primary btn-block">
              Volver a la Ficha Técnica
            </button>
          </div>
        </div>
      </div>
    `;
  }

  const vehiculoKm = state.sesion!.snapshot.vehiculo.kilometrajeActual;
  const kmActualNum = typeof state.kmServicio === 'number' ? state.kmServicio : Number(state.kmServicio);
  const esSaltoMayor = kmActualNum > vehiculoKm * 1.2 || kmActualNum - vehiculoKm > 50000;
  const itemsArray = Array.from(state.itemsSeleccionados.entries());

  return `
    <div class="modal-overlay">
      <div class="modal-content">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px;">
          <h2 style="font-family: var(--font-heading); font-size: 20px;">Registrar Servicio Realizado</h2>
          <button id="btn-cerrar-modal" class="btn btn-outline btn-sm" style="padding: 4px 10px; font-size: 18px;">✕</button>
        </div>

        <p style="font-size: 13px; color: var(--text-muted); margin-bottom: 18px;">
          Esta información se enviará al dueño del vehículo para sellar el mantenimiento en el historial técnico.
        </p>

        ${state.propuestaError ? `
          <div class="error-box">
            ${state.propuestaError}
          </div>
        ` : ''}

        <!-- Kilometraje y Fecha -->
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px;">
          <div class="form-group">
            <label class="form-label">Odómetro del servicio (km)*</label>
            <input
              type="number"
              id="input-propuesta-km"
              class="form-input"
              value="${state.kmServicio}"
              min="${vehiculoKm}"
              step="1"
              required
            />
          </div>

          <div class="form-group">
            <label class="form-label">Fecha del servicio*</label>
            <input
              type="date"
              id="input-propuesta-fecha"
              class="form-input"
              value="${state.fechaServicio}"
              max="${new Date().toISOString().split('T')[0]}"
              required
            />
          </div>
        </div>

        ${esSaltoMayor ? `
          <div class="warn-box" style="margin-bottom: 14px;">
            ⚠ <strong>Aviso:</strong> El kilometraje ingresado (${formatearKm(kmActualNum)}) es significativamente superior al odómetro previo (${formatearKm(vehiculoKm)}). Verifica el tablero.
          </div>
        ` : ''}

        <!-- Trabajos incluidos -->
        <div class="form-group">
          <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
            <label class="form-label" style="margin-bottom: 0;">Trabajos realizados (${itemsArray.length})*</label>
            <button id="btn-toggle-extra" class="btn btn-outline btn-sm" type="button">
              ＋ Otro trabajo
            </button>
          </div>

          ${state.mostrarFormExtra ? `
            <div class="extra-item-form">
              <div style="font-weight: 700; font-size: 13px; margin-bottom: 8px;">Agregar trabajo adicional:</div>
              <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-bottom: 8px;">
                <select id="select-extra-cat" class="form-select">
                  <option value="motor">Motor</option>
                  <option value="transmision">Transmisión</option>
                  <option value="frenos">Frenos</option>
                  <option value="refrigeracion">Refrigeración</option>
                  <option value="suspension">Suspensión</option>
                  <option value="electrico">Eléctrico</option>
                  <option value="escape">Escape</option>
                  <option value="inspeccion">Inspección</option>
                </select>
                <select id="select-extra-comp" class="form-select">
                  <option value="motor">Aplica a: Motor</option>
                  <option value="transmision">Aplica a: Transmisión</option>
                  <option value="frenos">Aplica a: Frenos</option>
                  <option value="suspension">Aplica a: Suspensión</option>
                  <option value="otro">Aplica a: Otro</option>
                </select>
              </div>
              <input
                type="text"
                id="input-extra-desc"
                placeholder="Descripción del trabajo (ej: Cambio de correa accesoria)..."
                class="form-input"
                style="margin-bottom: 8px;"
                value="${state.extraDescripcion}"
              />
              <div style="display: flex; gap: 8px; justify-content: flex-end;">
                <button id="btn-cancelar-extra" class="btn btn-outline btn-sm" type="button">Cancelar</button>
                <button id="btn-guardar-extra" class="btn btn-primary btn-sm" type="button">Agregar</button>
              </div>
            </div>
          ` : ''}

          ${itemsArray.length === 0 ? `
            <div style="background: var(--surface-card); border: 1px dashed var(--border); padding: 14px; border-radius: var(--radius-sm); text-align: center; color: var(--text-muted); font-size: 13px;">
              No has seleccionado ningún trabajo del plan ni agregado trabajos adicionales.
            </div>
          ` : `
            <div style="display: flex; flex-direction: column; gap: 6px; max-height: 200px; overflow-y: auto;">
              ${itemsArray.map(([id, it]) => `
                <div style="display: flex; justify-content: space-between; align-items: center; background: var(--surface-card); padding: 8px 12px; border-radius: var(--radius-sm); font-size: 13px; border: 1px solid var(--border);">
                  <div>
                    <span style="font-weight: 600;">${it.descripcion}</span>
                    <span style="font-size: 11px; color: var(--text-muted); margin-left: 6px;">[${it.categoria}]</span>
                  </div>
                  <button class="btn-eliminar-item" data-id="${id}" style="background: none; border: none; color: var(--danger); cursor: pointer; font-size: 15px; padding: 2px 6px;">✕</button>
                </div>
              `).join('')}
            </div>
          `}
        </div>

        <!-- Taller y Mecánico -->
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px;">
          <div class="form-group">
            <label class="form-label">Nombre del taller</label>
            <input
              type="text"
              id="input-propuesta-taller"
              placeholder="Ej: AutoMotors Bogotá"
              class="form-input"
              value="${state.taller}"
            />
          </div>

          <div class="form-group">
            <label class="form-label">Mecánico responsable</label>
            <input
              type="text"
              id="input-propuesta-mecanico"
              placeholder="Ej: Juan Pérez"
              class="form-input"
              value="${state.mecanico}"
            />
          </div>
        </div>

        <!-- Costo COP -->
        <div class="form-group">
          <label class="form-label">Costo total del servicio (COP opcional)</label>
          <input
            type="text"
            id="input-propuesta-costo"
            placeholder="$ 0"
            class="form-input"
            value="${state.costoTexto}"
            inputmode="numeric"
          />
        </div>

        <!-- Notas -->
        <div class="form-group">
          <label class="form-label">Observaciones y recomendaciones técnicas</label>
          <textarea
            id="input-propuesta-notas"
            class="form-textarea"
            placeholder="Especificaciones de fluidos usados, estado general o recomendaciones para la próxima visita..."
          >${state.notas}</textarea>
        </div>

        <!-- Acciones -->
        <div style="display: flex; gap: 10px; margin-top: 20px;">
          <button id="btn-cancelar-modal" class="btn btn-outline" style="flex: 1;">
            Cancelar
          </button>
          <button
            id="btn-enviar-propuesta"
            class="btn btn-success"
            style="flex: 2;"
            ${state.propuestaEnviando || itemsArray.length === 0 ? 'disabled' : ''}
          >
            ${state.propuestaEnviando ? 'Enviando...' : 'Enviar al Dueño'}
          </button>
        </div>
      </div>
    </div>
  `;
}

// ----------------------------------------------------
// Render Principal y Binding de Eventos
// ----------------------------------------------------

function render() {
  if (state.cargando) {
    appEl.innerHTML = renderCargando();
    return;
  }

  if (state.error) {
    appEl.innerHTML = renderError();
    vincularEventosError();
    return;
  }

  if (!state.sesion) {
    appEl.innerHTML = renderIngreso();
    vincularEventosIngreso();
    return;
  }

  appEl.innerHTML = renderFicha();
  vincularEventosFicha();
}

function vincularEventosIngreso() {
  const form = document.getElementById('form-ingreso');
  const input = document.getElementById('input-codigo') as HTMLInputElement | null;

  if (input) {
    input.focus();
    input.addEventListener('input', () => {
      input.value = input.value.toUpperCase().trim();
    });
  }

  form?.addEventListener('submit', (e) => {
    e.preventDefault();
    if (input && input.value.trim().length === 6) {
      const codigo = input.value.trim();
      state.codigoOToken = codigo;
      const url = new URL(window.location.href);
      url.searchParams.set('c', codigo);
      window.history.pushState({}, '', url.toString());
      cargarSesion(codigo);
    }
  });
}

function vincularEventosError() {
  document.getElementById('btn-reintentar')?.addEventListener('click', () => {
    if (state.codigoOToken) {
      cargarSesion(state.codigoOToken);
    } else {
      state.error = null;
      render();
    }
  });

  document.getElementById('btn-otro-codigo')?.addEventListener('click', () => {
    state.error = null;
    state.codigoOToken = null;
    const url = new URL(window.location.href);
    url.search = '';
    window.history.pushState({}, '', url.toString());
    render();
  });
}

function vincularEventosFicha() {
  // Pestañas principales
  document.querySelectorAll<HTMLButtonElement>('.tab-btn[data-tab]').forEach((btn) => {
    btn.addEventListener('click', () => {
      state.tab = btn.dataset.tab as any;
      render();
    });
  });

  // Filtros de estado en plan
  document.querySelectorAll<HTMLButtonElement>('.tab-btn[data-filtro]').forEach((btn) => {
    btn.addEventListener('click', () => {
      state.filtroEstado = btn.dataset.filtro as any;
      render();
    });
  });

  // Buscador
  const inputBusqueda = document.getElementById('input-busqueda') as HTMLInputElement | null;
  if (inputBusqueda) {
    inputBusqueda.addEventListener('input', () => {
      state.busqueda = inputBusqueda.value;
      render();
    });
  }

  // Toggle ítem de checklist
  document.querySelectorAll<HTMLDivElement>('.checklist-item[data-item-id]').forEach((el) => {
    el.addEventListener('click', () => {
      const itemId = el.dataset.itemId;
      if (!itemId || !state.sesion) return;
      const item = state.sesion.snapshot.plan.items.find((x) => x.id === itemId);
      if (item) {
        toggleItemPlan(item);
      }
    });
  });

  // Botón abrir propuesta
  document.getElementById('btn-abrir-propuesta')?.addEventListener('click', () => {
    state.modalAbierto = true;
    state.propuestaExito = false;
    state.propuestaError = null;
    render();
  });

  // Eventos del modal
  if (state.modalAbierto) {
    vincularEventosModal();
  }
}

function vincularEventosModal() {
  document.getElementById('btn-cerrar-modal')?.addEventListener('click', () => {
    state.modalAbierto = false;
    render();
  });

  document.getElementById('btn-cancelar-modal')?.addEventListener('click', () => {
    state.modalAbierto = false;
    render();
  });

  document.getElementById('btn-cerrar-exito')?.addEventListener('click', () => {
    state.modalAbierto = false;
    state.propuestaExito = false;
    state.itemsSeleccionados.clear();
    render();
  });

  // Inputs del formulario
  const kmInput = document.getElementById('input-propuesta-km') as HTMLInputElement | null;
  kmInput?.addEventListener('input', () => {
    state.kmServicio = kmInput.value ? Number(kmInput.value) : '';
  });

  const fechaInput = document.getElementById('input-propuesta-fecha') as HTMLInputElement | null;
  fechaInput?.addEventListener('change', () => {
    state.fechaServicio = fechaInput.value;
  });

  const tallerInput = document.getElementById('input-propuesta-taller') as HTMLInputElement | null;
  tallerInput?.addEventListener('input', () => {
    state.taller = tallerInput.value;
  });

  const mecanicoInput = document.getElementById('input-propuesta-mecanico') as HTMLInputElement | null;
  mecanicoInput?.addEventListener('input', () => {
    state.mecanico = mecanicoInput.value;
  });

  const costoInput = document.getElementById('input-propuesta-costo') as HTMLInputElement | null;
  costoInput?.addEventListener('input', () => {
    const digitos = costoInput.value.replace(/\D/g, '');
    if (digitos) {
      const num = parseInt(digitos, 10);
      state.costo = num;
      state.costoTexto = formatearCop(num);
      costoInput.value = state.costoTexto;
    } else {
      state.costo = null;
      state.costoTexto = '';
      costoInput.value = '';
    }
  });

  const notasInput = document.getElementById('input-propuesta-notas') as HTMLTextAreaElement | null;
  notasInput?.addEventListener('input', () => {
    state.notas = notasInput.value;
  });

  // Eliminar ítem seleccionado
  document.querySelectorAll<HTMLButtonElement>('.btn-eliminar-item').forEach((btn) => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const id = btn.dataset.id;
      if (id) {
        eliminarItemSeleccionado(id);
      }
    });
  });

  // Formulario ítem extra
  document.getElementById('btn-toggle-extra')?.addEventListener('click', () => {
    state.mostrarFormExtra = !state.mostrarFormExtra;
    render();
  });

  document.getElementById('btn-cancelar-extra')?.addEventListener('click', () => {
    state.mostrarFormExtra = false;
    render();
  });

  document.getElementById('btn-guardar-extra')?.addEventListener('click', () => {
    const descInput = document.getElementById('input-extra-desc') as HTMLInputElement | null;
    const catSelect = document.getElementById('select-extra-cat') as HTMLSelectElement | null;
    const compSelect = document.getElementById('select-extra-comp') as HTMLSelectElement | null;

    if (descInput && catSelect && compSelect) {
      state.extraDescripcion = descInput.value;
      state.extraCategoria = catSelect.value as CategoriaMantenimiento;
      state.extraComponente = compSelect.value as TipoComponente;
      agregarItemExtra();
    }
  });

  // Enviar propuesta
  document.getElementById('btn-enviar-propuesta')?.addEventListener('click', () => {
    enviarReporteServicio();
  });
}

// Inicializar la aplicación
inicializarDesdeUrl();
