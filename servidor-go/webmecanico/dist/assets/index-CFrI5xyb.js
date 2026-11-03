var A=Object.defineProperty;var M=(o,e,a)=>e in o?A(o,e,{enumerable:!0,configurable:!0,writable:!0,value:a}):o[e]=a;var k=(o,e,a)=>M(o,typeof e!="symbol"?e+"":e,a);(function(){const e=document.createElement("link").relList;if(e&&e.supports&&e.supports("modulepreload"))return;for(const s of document.querySelectorAll('link[rel="modulepreload"]'))i(s);new MutationObserver(s=>{for(const r of s)if(r.type==="childList")for(const c of r.addedNodes)c.tagName==="LINK"&&c.rel==="modulepreload"&&i(c)}).observe(document,{childList:!0,subtree:!0});function a(s){const r={};return s.integrity&&(r.integrity=s.integrity),s.referrerPolicy&&(r.referrerPolicy=s.referrerPolicy),s.crossOrigin==="use-credentials"?r.credentials="include":s.crossOrigin==="anonymous"?r.credentials="omit":r.credentials="same-origin",r}function i(s){if(s.ep)return;s.ep=!0;const r=a(s);fetch(s.href,r)}})();class x extends Error{constructor(a,i){super(a);k(this,"status");this.status=i,this.name="ApiError"}}async function I(o){const e=await fetch(`/api/sesion/${encodeURIComponent(o)}`,{headers:{Accept:"application/json"}});if(!e.ok)throw e.status===404?new x("La sesión no existe o ya ha expirado.",404):e.status===429?new x("Demasiadas solicitudes. Por favor espera un momento.",429):new x(`Error del servidor (${e.status})`,e.status);return e.json()}async function j(o,e){const a=await fetch(`/api/sesion/${encodeURIComponent(o)}/propuesta`,{method:"POST",headers:{"Content-Type":"application/json",Accept:"application/json"},body:JSON.stringify(e)});if(!a.ok){if(a.status===413)throw new x("El tamaño del reporte excede el límite permitido (64 KB).",413);if(a.status===404)throw new x("La sesión ya no está activa para recibir propuestas.",404);const i=await a.json().catch(()=>({}));throw new x(i.error||`Error enviando propuesta (${a.status})`,a.status)}return a.json()}function S(o,e){return e==="severo"?o.intervaloSeveroKm??Math.round(o.intervaloKm*.7):o.intervaloKm}function z(o,e){if(!(o.intervaloMeses===void 0||o.intervaloMeses===null))return e==="severo"?Math.floor(o.intervaloMeses/2):o.intervaloMeses}function L(o,e){const a=new Date(o.getTime()),i=a.getDate();a.setDate(1),a.setMonth(a.getMonth()+e);const s=new Date(a.getFullYear(),a.getMonth()+1,0).getDate();return a.setDate(Math.min(i,s)),a}function C(o,e,a){if(e>0&&(o.ultimaVezKm===void 0||o.ultimaVezKm===null)&&(o.ultimaVezFecha===void 0||o.ultimaVezFecha===null))return"desconocido";const i=S(o,a),s=z(o,a),r=o.ultimaVezKm??0,c=e-r,v=i-c,b=Math.min(Math.max(Math.round(i*.12),500),1e4);let p=!1,d=!1;v<=0?p=!0:v<=b&&(d=!0);let f=!1,u=!1;if(s!==void 0&&o.ultimaVezFecha){const n=new Date(o.ultimaVezFecha);if(!isNaN(n.getTime())){const m=L(n,s),g=new Date,w=Math.floor((m.getTime()-g.getTime())/(1e3*60*60*24));w<=0?f=!0:w<=35&&(u=!0)}}return p||f?"vencido":d||u?"proximo":"ok"}function h(o){const e=Math.round(o).toString().split("");let a="";for(let i=0;i<e.length;i++)i>0&&(e.length-i)%3===0&&(a+="."),a+=e[i];return a}function T(o){return o<0?`-$ ${h(Math.abs(o))}`:`$ ${h(o)}`}function y(o){return`${h(o)} km`}const t={codigoOToken:null,cargando:!1,error:null,sesion:null,tab:"plan",filtroEstado:"todos",busqueda:"",itemsSeleccionados:new Map,modalAbierto:!1,propuestaEnviando:!1,propuestaExito:!1,propuestaError:null,kmServicio:"",fechaServicio:new Date().toISOString().split("T")[0],taller:"",mecanico:"",costo:null,costoTexto:"",notas:"",mostrarFormExtra:!1,extraCategoria:"motor",extraComponente:"motor",extraDescripcion:""},E=document.getElementById("app");function P(){const o=new URLSearchParams(window.location.search),e=o.get("s")||o.get("token"),a=o.get("c")||o.get("codigo");if(e)t.codigoOToken=e,$(e);else if(a)t.codigoOToken=a,$(a);else{const i=window.location.pathname.split("/").filter(Boolean),s=i.indexOf("m");if(s!==-1&&i[s+1]){const r=i[s+1];t.codigoOToken=r,$(r)}else l()}}async function $(o){t.cargando=!0,t.error=null,l();try{const e=await I(o);t.sesion=e,t.kmServicio=e.snapshot.vehiculo.kilometrajeActual,t.cargando=!1,l()}catch(e){t.cargando=!1,e instanceof x?t.error=e.message:t.error="No se pudo conectar con el servidor. Verifica tu conexión.",l()}}function D(o){const a=new Date(o).getTime()-Date.now();if(a<=0)return"Expirada";const i=Math.floor(a/6e4);if(i<60)return`Expira en ${i}m`;const s=Math.floor(i/60);return s<24?`Expira en ${s}h ${i%60}m`:`Expira en ${Math.floor(s/24)}d`}function O(){return typeof crypto<"u"&&crypto.randomUUID?crypto.randomUUID():"xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g,o=>{const e=Math.random()*16|0;return(o==="x"?e:e&3|8).toString(16)})}function B(o){t.itemsSeleccionados.has(o.id)?t.itemsSeleccionados.delete(o.id):t.itemsSeleccionados.set(o.id,{itemId:o.id,categoria:o.categoria,componenteAplica:o.componenteAplica,descripcion:o.descripcion}),l()}function F(o){t.itemsSeleccionados.delete(o),l()}function V(){const o=t.extraDescripcion.trim();if(!o)return;const e=`extra-${Date.now()}`;t.itemsSeleccionados.set(e,{categoria:t.extraCategoria,componenteAplica:t.extraComponente,descripcion:o}),t.extraDescripcion="",t.mostrarFormExtra=!1,l()}async function N(){if(!t.sesion||!t.codigoOToken)return;const o=typeof t.kmServicio=="number"?t.kmServicio:Number(t.kmServicio);if(isNaN(o)||o<0){t.propuestaError="Ingresa un kilometraje válido.",l();return}const e=t.sesion.snapshot.vehiculo.kilometrajeActual;if(o<e){t.propuestaError=`El kilometraje (${y(o)}) no puede ser menor al actual (${y(e)}).`,l();return}if(t.itemsSeleccionados.size===0){t.propuestaError="Debes marcar o agregar al menos un trabajo realizado.",l();return}t.propuestaEnviando=!0,t.propuestaError=null,l();try{const a=Array.from(t.itemsSeleccionados.values()),i={schema:1,id:O(),creadaEn:new Date().toISOString(),mecanico:{taller:t.taller.trim()||void 0,nombre:t.mecanico.trim()||void 0},kilometraje:o,fecha:t.fechaServicio,costo:t.costo??void 0,moneda:"COP",notas:t.notas.trim()||void 0,itemsRealizados:a};await j(t.codigoOToken,i),t.propuestaEnviando=!1,t.propuestaExito=!0,l()}catch(a){t.propuestaEnviando=!1,a instanceof x?t.propuestaError=a.message:t.propuestaError="Error al enviar el reporte. Verifica tu conexión e inténtalo de nuevo.",l()}}function U(){return`
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
  `}function K(){return`
    <div class="container" style="text-align: center; padding-top: 80px;">
      <div class="brand-logo" style="margin: 0 auto 20px auto; width: 44px; height: 44px; font-size: 22px;">C</div>
      <div class="spinner"></div>
      <p style="color: var(--text-muted); font-size: 14px; margin-top: 16px;">Cargando ficha del vehículo...</p>
    </div>
  `}function q(){return`
    <div class="container" style="padding-top: 40px;">
      <div class="card ingreso-box">
        <div style="font-size: 40px; margin-bottom: 12px;">⚠</div>
        <h2 style="font-family: var(--font-heading); font-size: 22px; margin-bottom: 8px;">No se pudo abrir la ficha</h2>
        <p style="color: var(--text-muted); font-size: 14px; margin-bottom: 24px;">
          ${t.error||"La sesión no existe o ha expirado."}
        </p>

        <button id="btn-reintentar" class="btn btn-primary" style="margin-right: 8px;">
          Reintentar
        </button>
        <button id="btn-otro-codigo" class="btn btn-outline">
          Ingresar otro código
        </button>
      </div>
    </div>
  `}function R(){const o=t.sesion,e=o.snapshot.vehiculo,a=o.snapshot.plan,i=o.snapshot.historial||[],s=a.items.map(n=>({item:n,estado:C(n,e.kilometrajeActual,e.tipoUso),intKm:S(n,e.tipoUso),intMeses:z(n,e.tipoUso)})),r=s.filter(n=>n.estado==="vencido").length,c=s.filter(n=>n.estado==="proximo").length,v=s.filter(n=>n.estado==="ok").length,b=s.filter(n=>n.estado==="desconocido").length,p=a.alertasIngenieria||[],d=t.busqueda.toLowerCase().trim(),f=s.filter(n=>t.filtroEstado!=="todos"&&n.estado!==t.filtroEstado?!1:d?n.item.descripcion.toLowerCase().includes(d)||n.item.categoria.toLowerCase().includes(d):!0).sort((n,m)=>{const g={vencido:0,proximo:1,desconocido:2,ok:3};return g[n.estado]-g[m.estado]});return`
    <div class="container">
      <!-- Top Bar -->
      <header class="top-bar">
        <div class="brand">
          <div class="brand-logo">C</div>
          <div>
            <div class="brand-title">CarMain · Taller</div>
            <div style="font-size: 11px; color: var(--text-muted);">${D(o.expiraEn)}</div>
          </div>
        </div>
        <div class="badge-readonly">
          <span>🔒 Solo lectura</span>
        </div>
      </header>

      <!-- Vehículo Header -->
      <div class="card vehiculo-header">
        <div class="vehiculo-nombre">
          ${e.marca} ${e.modelo} ${e.anio}
        </div>
        ${e.trim?`<div style="font-size: 14px; color: var(--text-muted);">${e.trim}</div>`:""}

        <div class="vehiculo-meta">
          ${e.placa?`<span class="chip" style="font-weight: 700; border-color: rgba(201,169,110,0.4);">${e.placa}</span>`:""}
          <span class="chip">📍 ${y(e.kilometrajeActual)}</span>
          <span class="chip">⚙ ${e.drivetrain.toUpperCase()}</span>
          <span class="chip">${e.tipoUso==="severo"?"🚨 Uso Severo":"🌱 Uso Normal"}</span>
          ${e.vin?`<span class="chip" style="font-size: 11px;">VIN: ${e.vin}</span>`:""}
        </div>

        ${e.notasUso?`
          <div style="margin-top: 8px; font-size: 13px; color: var(--text-muted); background: var(--surface-card); padding: 8px 12px; border-radius: 8px;">
            💬 <i>${e.notasUso}</i>
          </div>
        `:""}
      </div>

      <!-- Motor y Transmisión -->
      <div class="card">
        <div class="card-title">
          <span>Componentes Mecánicos</span>
          ${e.motor.esSwap||e.transmision.esSwap?'<span class="chip chip-swap">Modificado / Swap</span>':""}
        </div>

        <div style="display: flex; flex-direction: column; gap: 12px;">
          <!-- Motor -->
          <div style="background: var(--surface-card); padding: 12px; border-radius: var(--radius-sm);">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
              <span style="font-weight: 700; font-size: 15px;">Motor: ${e.motor.codigo}</span>
              ${e.motor.esSwap?`<span class="chip chip-swap" style="font-size: 11px;">SWAP (Orig: ${e.motor.original||"OEM"})</span>`:""}
            </div>
            <div class="specs-grid">
              ${e.motor.cilindrada?`<div class="spec-cell"><div class="spec-label">Cilindrada</div><div class="spec-value">${e.motor.cilindrada}L ${e.motor.cilindros?`(${e.motor.cilindros} cyl)`:""}</div></div>`:""}
              ${e.motor.aspiracion?`<div class="spec-cell"><div class="spec-label">Aspiración</div><div class="spec-value">${e.motor.aspiracion}</div></div>`:""}
              ${e.motor.potenciaHp?`<div class="spec-cell"><div class="spec-label">Potencia</div><div class="spec-value">${e.motor.potenciaHp} HP</div></div>`:""}
              ${e.motor.torqueNm?`<div class="spec-cell"><div class="spec-label">Torque</div><div class="spec-value">${e.motor.torqueNm} Nm</div></div>`:""}
              ${e.motor.combustible?`<div class="spec-cell"><div class="spec-label">Combustible</div><div class="spec-value">${e.motor.combustible}</div></div>`:""}
            </div>
          </div>

          <!-- Transmisión -->
          <div style="background: var(--surface-card); padding: 12px; border-radius: var(--radius-sm);">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
              <span style="font-weight: 700; font-size: 15px;">Transmisión: ${e.transmision.codigo}</span>
              ${e.transmision.esSwap?`<span class="chip chip-swap" style="font-size: 11px;">SWAP (Orig: ${e.transmision.original||"OEM"})</span>`:""}
            </div>
            <div class="specs-grid">
              ${e.transmision.tipo?`<div class="spec-cell"><div class="spec-label">Tipo</div><div class="spec-value">${e.transmision.tipo}</div></div>`:""}
              ${e.transmision.marchas?`<div class="spec-cell"><div class="spec-label">Marchas</div><div class="spec-value">${e.transmision.marchas} vel</div></div>`:""}
            </div>
          </div>
        </div>
      </div>

      <!-- Alertas de Ingeniería (si existen) -->
      ${p.length>0?`
        <div class="card" style="border-color: rgba(245, 158, 11, 0.4);">
          <div class="card-title" style="color: var(--warning);">
            <span>⚠ Alertas de Swap / Vigilancia Técnica</span>
            <span class="count-badge proximo">${p.length}</span>
          </div>
          ${p.map(n=>`
            <div class="alerta-box ${n.severidad}">
              <div class="alerta-titulo">${n.titulo}</div>
              <div class="alerta-desc"><strong>Vector:</strong> ${n.vector} · <strong>Componente:</strong> ${n.componenteAfectado}</div>
              <div class="alerta-desc" style="margin-top: 4px;">${n.diagnostico}</div>
              ${n.recomendacionUpgrade?`<div class="alerta-desc" style="margin-top: 4px; color: var(--primary);"><strong>Recomendación:</strong> ${n.recomendacionUpgrade}</div>`:""}
            </div>
          `).join("")}
        </div>
      `:""}

      <!-- Pestañas Principales -->
      <div class="filtro-tabs" style="margin-top: 8px;">
        <button class="tab-btn ${t.tab==="plan"?"activo":""}" data-tab="plan">
          Plan de Mantenimiento
        </button>
        ${i.length>0?`
          <button class="tab-btn ${t.tab==="historial"?"activo":""}" data-tab="historial">
            Historial Previo (${i.length})
          </button>
        `:""}
      </div>

      ${t.tab==="plan"?H(f,r,c,v,b):""}
      ${t.tab==="historial"?J(i):""}

      <!-- Barra Flotante Inferior -->
      <div class="bottom-bar">
        <div class="bottom-bar-inner">
          <button id="btn-abrir-propuesta" class="btn btn-primary btn-block">
            🛠 Registrar Servicio Realizado
            ${t.itemsSeleccionados.size>0?`(${t.itemsSeleccionados.size} seleccionados)`:""}
          </button>
        </div>
      </div>

      <!-- Modal de Propuesta -->
      ${t.modalAbierto?W():""}
    </div>
  `}function H(o,e,a,i,s){return`
    <!-- Filtros de Urgencia -->
    <div class="filtro-tabs">
      <button class="tab-btn ${t.filtroEstado==="todos"?"activo":""}" data-filtro="todos">
        Todos (${e+a+i+s})
      </button>
      <button class="tab-btn ${t.filtroEstado==="vencido"?"activo":""}" data-filtro="vencido">
        ⚠ Vencidos <span class="count-badge vencido">${e}</span>
      </button>
      <button class="tab-btn ${t.filtroEstado==="proximo"?"activo":""}" data-filtro="proximo">
        ⏱ Próximos <span class="count-badge proximo">${a}</span>
      </button>
      <button class="tab-btn ${t.filtroEstado==="ok"?"activo":""}" data-filtro="ok">
        ✔ Al día <span class="count-badge ok">${i}</span>
      </button>
      <button class="tab-btn ${t.filtroEstado==="desconocido"?"activo":""}" data-filtro="desconocido">
        ❔ Sin registro <span class="count-badge desconocido">${s}</span>
      </button>
    </div>

    <!-- Buscador -->
    <div class="search-box">
      <input
        type="search"
        id="input-busqueda"
        placeholder="Buscar tarea o repuesto..."
        class="search-input"
        value="${t.busqueda}"
      />
    </div>

    <!-- Lista de Ítems del Plan -->
    <div style="margin-top: 10px;">
      ${o.length===0?`
        <div class="card empty-state">
          No se encontraron ítems de mantenimiento para este filtro.
        </div>
      `:o.map(({item:r,estado:c,intKm:v,intMeses:b})=>{const p=t.itemsSeleccionados.has(r.id),d=r.ultimaVezKm!==void 0&&r.ultimaVezKm!==null?v-(t.sesion.snapshot.vehiculo.kilometrajeActual-r.ultimaVezKm):null;let f=`Cada ${h(v)} km`;b&&(f+=` o ${b} meses`);let u="";return c==="vencido"&&d!==null&&d<0?u=`Vencido hace ${h(Math.abs(d))} km`:c==="proximo"&&d!==null?u=`Faltan ${h(d)} km`:c==="ok"?u=d!==null?`Al día (faltan ${h(d)} km)`:"Al día":u="Sin registro previo de cambio",`
          <div class="checklist-item ${p?"seleccionado":""}" data-item-id="${r.id}">
            <div class="checkbox-custom">
              ${p?"✔":""}
            </div>
            <div style="flex: 1; min-width: 0;">
              <div style="display: flex; justify-content: space-between; align-items: flex-start; gap: 8px;">
                <span class="item-desc">${r.descripcion}</span>
                <span class="estado-pill estado-${c}">
                  ${c==="vencido"?"⚠ Vencido":c==="proximo"?"⏱ Próximo":c==="ok"?"✔ Al día":"❔ Sin registro"}
                </span>
              </div>
              <div class="item-meta" style="margin-top: 4px;">
                <span>${f}</span>
                <span style="font-weight: 600; color: ${c==="vencido"?"#FCA5A5":c==="proximo"?"#FCD34D":"inherit"};">
                  ${u}
                </span>
              </div>
              ${r.esVigilanciaSwap?`
                <div style="margin-top: 4px;">
                  <span class="chip chip-swap" style="font-size: 11px; padding: 2px 8px;">Vigilancia Swap</span>
                </div>
              `:""}
            </div>
          </div>
        `}).join("")}
    </div>
  `}function J(o){return`
    <div style="display: flex; flex-direction: column; gap: 12px; margin-top: 10px;">
      ${o.map(e=>`
        <div class="card" style="margin-bottom: 0;">
          <div style="display: flex; justify-content: space-between; align-items: flex-start;">
            <div>
              <div style="font-weight: 700; font-size: 16px;">${y(e.kilometraje)}</div>
              <div style="font-size: 12px; color: var(--text-muted);">${e.fecha} ${e.taller?`· ${e.taller}`:""}</div>
            </div>
            <span class="estado-pill estado-ok" style="font-size: 10px;">
              ${e.nivelVerificacion==="selladoTaller"?"Nivel 3 · Sellado Taller":"Nivel 1 · Propietario"}
            </span>
          </div>

          <div style="margin-top: 10px; border-top: 1px solid var(--border); padding-top: 8px;">
            <div style="font-size: 12px; font-weight: 600; color: var(--text-muted); margin-bottom: 4px;">Trabajos realizados:</div>
            <ul style="padding-left: 18px; font-size: 13px;">
              ${e.items.map(a=>`<li>${a.descripcion}</li>`).join("")}
            </ul>
          </div>

          ${e.costo?`
            <div style="margin-top: 8px; font-size: 13px; font-weight: 600; color: var(--primary);">
              Costo: ${T(e.costo)}
            </div>
          `:""}
        </div>
      `).join("")}
    </div>
  `}function W(){if(t.propuestaExito)return`
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
    `;const o=t.sesion.snapshot.vehiculo.kilometrajeActual,e=typeof t.kmServicio=="number"?t.kmServicio:Number(t.kmServicio),a=e>o*1.2||e-o>5e4,i=Array.from(t.itemsSeleccionados.entries());return`
    <div class="modal-overlay">
      <div class="modal-content">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px;">
          <h2 style="font-family: var(--font-heading); font-size: 20px;">Registrar Servicio Realizado</h2>
          <button id="btn-cerrar-modal" class="btn btn-outline btn-sm" style="padding: 4px 10px; font-size: 18px;">✕</button>
        </div>

        <p style="font-size: 13px; color: var(--text-muted); margin-bottom: 18px;">
          Esta información se enviará al dueño del vehículo para sellar el mantenimiento en el historial técnico.
        </p>

        ${t.propuestaError?`
          <div class="error-box">
            ${t.propuestaError}
          </div>
        `:""}

        <!-- Kilometraje y Fecha -->
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px;">
          <div class="form-group">
            <label class="form-label">Odómetro del servicio (km)*</label>
            <input
              type="number"
              id="input-propuesta-km"
              class="form-input"
              value="${t.kmServicio}"
              min="${o}"
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
              value="${t.fechaServicio}"
              max="${new Date().toISOString().split("T")[0]}"
              required
            />
          </div>
        </div>

        ${a?`
          <div class="warn-box" style="margin-bottom: 14px;">
            ⚠ <strong>Aviso:</strong> El kilometraje ingresado (${y(e)}) es significativamente superior al odómetro previo (${y(o)}). Verifica el tablero.
          </div>
        `:""}

        <!-- Trabajos incluidos -->
        <div class="form-group">
          <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
            <label class="form-label" style="margin-bottom: 0;">Trabajos realizados (${i.length})*</label>
            <button id="btn-toggle-extra" class="btn btn-outline btn-sm" type="button">
              ＋ Otro trabajo
            </button>
          </div>

          ${t.mostrarFormExtra?`
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
                value="${t.extraDescripcion}"
              />
              <div style="display: flex; gap: 8px; justify-content: flex-end;">
                <button id="btn-cancelar-extra" class="btn btn-outline btn-sm" type="button">Cancelar</button>
                <button id="btn-guardar-extra" class="btn btn-primary btn-sm" type="button">Agregar</button>
              </div>
            </div>
          `:""}

          ${i.length===0?`
            <div style="background: var(--surface-card); border: 1px dashed var(--border); padding: 14px; border-radius: var(--radius-sm); text-align: center; color: var(--text-muted); font-size: 13px;">
              No has seleccionado ningún trabajo del plan ni agregado trabajos adicionales.
            </div>
          `:`
            <div style="display: flex; flex-direction: column; gap: 6px; max-height: 200px; overflow-y: auto;">
              ${i.map(([s,r])=>`
                <div style="display: flex; justify-content: space-between; align-items: center; background: var(--surface-card); padding: 8px 12px; border-radius: var(--radius-sm); font-size: 13px; border: 1px solid var(--border);">
                  <div>
                    <span style="font-weight: 600;">${r.descripcion}</span>
                    <span style="font-size: 11px; color: var(--text-muted); margin-left: 6px;">[${r.categoria}]</span>
                  </div>
                  <button class="btn-eliminar-item" data-id="${s}" style="background: none; border: none; color: var(--danger); cursor: pointer; font-size: 15px; padding: 2px 6px;">✕</button>
                </div>
              `).join("")}
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
              value="${t.taller}"
            />
          </div>

          <div class="form-group">
            <label class="form-label">Mecánico responsable</label>
            <input
              type="text"
              id="input-propuesta-mecanico"
              placeholder="Ej: Juan Pérez"
              class="form-input"
              value="${t.mecanico}"
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
            value="${t.costoTexto}"
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
          >${t.notas}</textarea>
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
            ${t.propuestaEnviando||i.length===0?"disabled":""}
          >
            ${t.propuestaEnviando?"Enviando...":"Enviar al Dueño"}
          </button>
        </div>
      </div>
    </div>
  `}function l(){if(t.cargando){E.innerHTML=K();return}if(t.error){E.innerHTML=q(),Y();return}if(!t.sesion){E.innerHTML=U(),X();return}E.innerHTML=R(),G()}function X(){const o=document.getElementById("form-ingreso"),e=document.getElementById("input-codigo");e&&(e.focus(),e.addEventListener("input",()=>{e.value=e.value.toUpperCase().trim()})),o==null||o.addEventListener("submit",a=>{if(a.preventDefault(),e&&e.value.trim().length===6){const i=e.value.trim();t.codigoOToken=i;const s=new URL(window.location.href);s.searchParams.set("c",i),window.history.pushState({},"",s.toString()),$(i)}})}function Y(){var o,e;(o=document.getElementById("btn-reintentar"))==null||o.addEventListener("click",()=>{t.codigoOToken?$(t.codigoOToken):(t.error=null,l())}),(e=document.getElementById("btn-otro-codigo"))==null||e.addEventListener("click",()=>{t.error=null,t.codigoOToken=null;const a=new URL(window.location.href);a.search="",window.history.pushState({},"",a.toString()),l()})}function G(){var e;document.querySelectorAll(".tab-btn[data-tab]").forEach(a=>{a.addEventListener("click",()=>{t.tab=a.dataset.tab,l()})}),document.querySelectorAll(".tab-btn[data-filtro]").forEach(a=>{a.addEventListener("click",()=>{t.filtroEstado=a.dataset.filtro,l()})});const o=document.getElementById("input-busqueda");o&&o.addEventListener("input",()=>{t.busqueda=o.value,l()}),document.querySelectorAll(".checklist-item[data-item-id]").forEach(a=>{a.addEventListener("click",()=>{const i=a.dataset.itemId;if(!i||!t.sesion)return;const s=t.sesion.snapshot.plan.items.find(r=>r.id===i);s&&B(s)})}),(e=document.getElementById("btn-abrir-propuesta"))==null||e.addEventListener("click",()=>{t.modalAbierto=!0,t.propuestaExito=!1,t.propuestaError=null,l()}),t.modalAbierto&&Q()}function Q(){var c,v,b,p,d,f,u;(c=document.getElementById("btn-cerrar-modal"))==null||c.addEventListener("click",()=>{t.modalAbierto=!1,l()}),(v=document.getElementById("btn-cancelar-modal"))==null||v.addEventListener("click",()=>{t.modalAbierto=!1,l()}),(b=document.getElementById("btn-cerrar-exito"))==null||b.addEventListener("click",()=>{t.modalAbierto=!1,t.propuestaExito=!1,t.itemsSeleccionados.clear(),l()});const o=document.getElementById("input-propuesta-km");o==null||o.addEventListener("input",()=>{t.kmServicio=o.value?Number(o.value):""});const e=document.getElementById("input-propuesta-fecha");e==null||e.addEventListener("change",()=>{t.fechaServicio=e.value});const a=document.getElementById("input-propuesta-taller");a==null||a.addEventListener("input",()=>{t.taller=a.value});const i=document.getElementById("input-propuesta-mecanico");i==null||i.addEventListener("input",()=>{t.mecanico=i.value});const s=document.getElementById("input-propuesta-costo");s==null||s.addEventListener("input",()=>{const n=s.value.replace(/\D/g,"");if(n){const m=parseInt(n,10);t.costo=m,t.costoTexto=T(m),s.value=t.costoTexto}else t.costo=null,t.costoTexto="",s.value=""});const r=document.getElementById("input-propuesta-notas");r==null||r.addEventListener("input",()=>{t.notas=r.value}),document.querySelectorAll(".btn-eliminar-item").forEach(n=>{n.addEventListener("click",m=>{m.stopPropagation();const g=n.dataset.id;g&&F(g)})}),(p=document.getElementById("btn-toggle-extra"))==null||p.addEventListener("click",()=>{t.mostrarFormExtra=!t.mostrarFormExtra,l()}),(d=document.getElementById("btn-cancelar-extra"))==null||d.addEventListener("click",()=>{t.mostrarFormExtra=!1,l()}),(f=document.getElementById("btn-guardar-extra"))==null||f.addEventListener("click",()=>{const n=document.getElementById("input-extra-desc"),m=document.getElementById("select-extra-cat"),g=document.getElementById("select-extra-comp");n&&m&&g&&(t.extraDescripcion=n.value,t.extraCategoria=m.value,t.extraComponente=g.value,V())}),(u=document.getElementById("btn-enviar-propuesta"))==null||u.addEventListener("click",()=>{N()})}P();
