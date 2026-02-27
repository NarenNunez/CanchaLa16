// src/lib/utils.js
// ─────────────────────────────────────────────
//  Helpers sin dependencias externas.
//  Usados tanto en cliente.html como admin.html.
// ─────────────────────────────────────────────

// ════════ FECHAS ══════════════════════════════

export const DIAS_ES   = ['Dom','Lun','Mar','Mié','Jue','Vie','Sáb']
export const DIAS_FULL = ['Domingo','Lunes','Martes','Miércoles','Jueves','Viernes','Sábado']
export const MESES_ES  = ['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre']

export function formatFecha(dateStr) {
  const d = new Date(dateStr + 'T12:00:00')
  return `${DIAS_ES[d.getDay()]} ${d.getDate()} de ${MESES_ES[d.getMonth()]}`
}

export function formatFechaLarga(dateStr) {
  const d = new Date(dateStr + 'T12:00:00')
  return `${DIAS_FULL[d.getDay()]} ${d.getDate()} de ${MESES_ES[d.getMonth()]} ${d.getFullYear()}`
}

export function hoy() {
  return new Date().toISOString().split('T')[0]
}

export function sumarDias(fechaStr, n) {
  const d = new Date(fechaStr + 'T12:00:00')
  d.setDate(d.getDate() + n)
  return d.toISOString().split('T')[0]
}

export function getDow(fechaStr) {
  return new Date(fechaStr + 'T12:00:00').getDay()
}

// ════════ PRECIOS ══════════════════════════════

/**
 * Calcula precio localmente (sin llamar a Supabase).
 * Usa las franjas pasadas como parámetro para no hard-codear.
 *
 * @param {number} hora        - Hora inicio (0-23)
 * @param {number} dow         - Día de semana (0=Dom)
 * @param {Array}  franjas     - Array de franjas_precio de la BD
 * @returns {{ precio: number, tier: string, nombre: string }}
 */
export function calcularPrecioLocal(hora, dow, franjas) {
  const esFSD = dow === 0 || dow === 6
  const esVie = dow === 5

  const franja = franjas.find(f => hora >= f.hora_inicio && hora < f.hora_fin)
  if (!franja) return { precio: 0, tier: 'mid', nombre: '—' }

  const precio = esFSD ? franja.precio_fsd : esVie ? franja.precio_vie : franja.precio_lv
  const tier = franja.hora_inicio < 12 ? 'low' : franja.hora_inicio < 18 ? 'mid' : 'high'
  return { precio, tier, nombre: franja.nombre }
}

// ════════ FORMATO ══════════════════════════════

export function formatCOP(n) {
  return '$' + Number(n).toLocaleString('es-CO')
}

export function formatCOPCorto(n) {
  if (n >= 1000000) return '$' + (n / 1000000).toFixed(1) + 'M'
  if (n >= 1000)    return '$' + (n / 1000).toFixed(0) + 'k'
  return formatCOP(n)
}

// ════════ TIEMPO ══════════════════════════════

export function horaLabel(h) {
  return String(h).padStart(2, '0') + ':00'
}

export function horaFinLabel(h) {
  return String(h + 1).padStart(2, '0') + ':00'
}

// ════════ UI ══════════════════════════════════

/**
 * Muestra un toast en la pantalla.
 * Requiere que exista #toast y #t-msg en el DOM.
 */
export function showToast(msg, duration = 4000) {
  const t = document.getElementById('toast')
  const m = document.getElementById('t-msg')
  if (!t || !m) return
  m.textContent = msg
  t.classList.add('show')
  clearTimeout(t._timer)
  t._timer = setTimeout(() => t.classList.remove('show'), duration)
}

/**
 * Cierra un overlay al hacer clic fuera del modal.
 */
export function setupOverlayClose(overlayId, closeFn) {
  document.getElementById(overlayId)?.addEventListener('click', e => {
    if (e.target.id === overlayId) closeFn()
  })
}

/**
 * Genera las opciones <option> de horas para un <select>.
 */
export function buildHoraOptions(desde = 7, hasta = 22) {
  return Array.from({ length: hasta - desde + 1 }, (_, i) => {
    const h = desde + i
    const v = horaLabel(h)
    return `<option value="${v}">${v}</option>`
  }).join('')
}

// ════════ REALTIME ════════════════════════════

/**
 * Suscribe a cambios en la tabla reservas para una fecha.
 * Llama a callback cuando hay INSERT/UPDATE/DELETE.
 */
export function suscribirReservas(supabase, fecha, callback) {
  return supabase
    .channel(`reservas:${fecha}`)
    .on('postgres_changes', {
      event: '*',
      schema: 'public',
      table: 'reservas',
      filter: `fecha=eq.${fecha}`,
    }, callback)
    .subscribe()
}
