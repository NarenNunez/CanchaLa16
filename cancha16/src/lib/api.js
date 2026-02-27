// src/lib/api.js
// ─────────────────────────────────────────────
//  Capa de datos. Todas las queries a Supabase
//  están aquí. Los componentes solo llaman funciones
//  de este archivo — nunca llaman supabase directo.
// ─────────────────────────────────────────────

import { supabase } from './supabase.js'

// ════════════════════════════════════════════
//  DISPONIBILIDAD
// ════════════════════════════════════════════

/**
 * Retorna los slots ocupados para una fecha.
 * Incluye reservas normales + clientes fijos del día.
 */
export async function getSlotsOcupados(fecha) {
  const dow = new Date(fecha + 'T12:00:00').getDay()

  const [{ data: reservas }, { data: fijos }] = await Promise.all([
    supabase
      .from('reservas')
      .select('hora_inicio, hora_fin, tipo, estado')
      .eq('fecha', fecha)
      .not('estado', 'eq', 'cancelado'),

    supabase
      .from('clientes_fijos')
      .select('hora_inicio, hora_fin')
      .eq('dia_semana', dow)
      .eq('estado', 'activo'),
  ])

  return {
    reservas: reservas || [],
    fijos: fijos || [],
  }
}

/**
 * Retorna la tabla de precios vigente.
 */
export async function getFranjasPrecio() {
  const { data, error } = await supabase
    .from('franjas_precio')
    .select('*')
    .eq('activo', true)
    .order('hora_inicio')
  if (error) throw error
  return data
}

/**
 * Calcula el precio para una hora y día de semana
 * usando la función SQL del backend.
 */
export async function calcularPrecio(hora, dow) {
  const { data, error } = await supabase.rpc('calcular_precio', {
    p_hora: hora,
    p_dow: dow,
  })
  if (error) throw error
  return data
}

// ════════════════════════════════════════════
//  RESERVAS (CLIENTE)
// ════════════════════════════════════════════

/**
 * Crea una nueva reserva (estado: pendiente).
 * Sube el comprobante si viene adjunto.
 */
export async function crearReserva({ nombre, telefono, fecha, horaInicio, horaFin, precio, metodoPago, comprobante }) {
  let comprobante_url = null

  // Upload comprobante si existe
  if (comprobante) {
    const ext = comprobante.name.split('.').pop()
    const path = `${fecha}/${Date.now()}.${ext}`
    const { error: upErr } = await supabase.storage
      .from('comprobantes')
      .upload(path, comprobante)
    if (upErr) throw upErr
    comprobante_url = path
  }

  const { data, error } = await supabase
    .from('reservas')
    .insert({
      cliente_nombre: nombre,
      cliente_tel: telefono,
      fecha,
      hora_inicio: horaInicio,
      hora_fin: horaFin,
      precio,
      metodo_pago: metodoPago,
      estado: 'pendiente',
      comprobante_url,
    })
    .select()
    .single()

  if (error) throw error
  return data
}

/**
 * Solicitud de cupo fijo (estado: solicitud).
 */
export async function solicitarCupoFijo({ nombre, telefono, diaSemana, horaInicio, horaFin, personas }) {
  const { data, error } = await supabase
    .from('clientes_fijos')
    .insert({
      nombre,
      telefono,
      dia_semana: diaSemana,
      hora_inicio: horaInicio,
      hora_fin: horaFin,
      personas,
      estado: 'solicitud',
    })
    .select()
    .single()

  if (error) throw error
  return data
}

// ════════════════════════════════════════════
//  RESERVAS (ADMIN)
// ════════════════════════════════════════════

/**
 * Obtiene todas las reservas (con filtros opcionales).
 */
export async function getReservas({ fecha, estado, tipo } = {}) {
  let q = supabase
    .from('reservas')
    .select('*')
    .order('fecha', { ascending: false })
    .order('hora_inicio')

  if (fecha) q = q.eq('fecha', fecha)
  if (estado && estado !== 'all') q = q.eq('estado', estado)
  if (tipo && tipo !== 'all') q = q.eq('tipo', tipo)

  const { data, error } = await q
  if (error) throw error
  return data
}

/**
 * Actualiza el estado de una reserva.
 */
export async function actualizarEstadoReserva(id, estado) {
  const { error } = await supabase
    .from('reservas')
    .update({ estado })
    .eq('id', id)
  if (error) throw error
}

/**
 * Crea una reserva desde el admin (puede ser cualquier tipo/estado).
 */
export async function crearReservaAdmin(payload) {
  const { data, error } = await supabase
    .from('reservas')
    .insert(payload)
    .select()
    .single()
  if (error) throw error
  return data
}

/**
 * Elimina (libera) una reserva.
 */
export async function eliminarReserva(id) {
  const { error } = await supabase
    .from('reservas')
    .delete()
    .eq('id', id)
  if (error) throw error
}

/**
 * Stats del día para el dashboard.
 */
export async function getStatsDia(fecha) {
  const { data, error } = await supabase.rpc('stats_dia', { p_fecha: fecha })
  if (error) throw error
  return data
}

// ════════════════════════════════════════════
//  CLIENTES FIJOS (ADMIN)
// ════════════════════════════════════════════

export async function getClientesFijos(estado) {
  let q = supabase.from('clientes_fijos').select('*').order('created_at', { ascending: false })
  if (estado) q = q.eq('estado', estado)
  const { data, error } = await q
  if (error) throw error
  return data
}

export async function actualizarClienteFijo(id, payload) {
  const { error } = await supabase.from('clientes_fijos').update(payload).eq('id', id)
  if (error) throw error
}

// ════════════════════════════════════════════
//  EVENTOS
// ════════════════════════════════════════════

export async function getEventos(soloActivos = false) {
  let q = supabase.from('eventos').select('*').order('fecha_inicio')
  if (soloActivos) q = q.eq('estado', 'activo')
  const { data, error } = await q
  if (error) throw error
  return data
}

export async function crearEvento(payload) {
  const { data, error } = await supabase.from('eventos').insert(payload).select().single()
  if (error) throw error
  return data
}

export async function actualizarEvento(id, payload) {
  const { error } = await supabase.from('eventos').update(payload).eq('id', id)
  if (error) throw error
}

// ════════════════════════════════════════════
//  FINANZAS
// ════════════════════════════════════════════

/**
 * Ingresos por día para los últimos N días.
 */
export async function getIngresosPorDia(dias = 7) {
  const desde = new Date()
  desde.setDate(desde.getDate() - dias + 1)
  const desdeStr = desde.toISOString().split('T')[0]

  const { data, error } = await supabase
    .from('reservas')
    .select('fecha, precio')
    .gte('fecha', desdeStr)
    .eq('estado', 'confirmado')

  if (error) throw error

  // Agrupar por fecha
  const map = {}
  for (const r of data || []) {
    map[r.fecha] = (map[r.fecha] || 0) + r.precio
  }
  return map
}

/**
 * Total del mes actual: cancha + tienda.
 */
export async function getTotalMes() {
  const hoy = new Date()
  const inicio = `${hoy.getFullYear()}-${String(hoy.getMonth()+1).padStart(2,'0')}-01`
  const fin = hoy.toISOString().split('T')[0]

  const [{ data: resData }, { data: ventasData }] = await Promise.all([
    supabase
      .from('reservas')
      .select('precio')
      .gte('fecha', inicio)
      .lte('fecha', fin)
      .eq('estado', 'confirmado'),
    supabase
      .from('ventas_productos')
      .select('total')
      .gte('created_at', inicio + 'T00:00:00'),
  ])

  const cancha = (resData || []).reduce((s, r) => s + r.precio, 0)
  const tienda = (ventasData || []).reduce((s, v) => s + v.total, 0)
  return { cancha, tienda, total: cancha + tienda }
}

// ════════════════════════════════════════════
//  PRODUCTOS / TIENDA
// ════════════════════════════════════════════

export async function getProductos() {
  const { data, error } = await supabase
    .from('productos')
    .select('*')
    .eq('activo', true)
    .order('nombre')
  if (error) throw error
  return data
}

export async function registrarVenta(productoId, cantidad, precioUnit) {
  const { error } = await supabase.from('ventas_productos').insert({
    producto_id: productoId,
    cantidad,
    precio_unit: precioUnit,
  })
  if (error) throw error
}

export async function crearProducto(payload) {
  const { data, error } = await supabase.from('productos').insert(payload).select().single()
  if (error) throw error
  return data
}

export async function actualizarProducto(id, payload) {
  const { error } = await supabase.from('productos').update(payload).eq('id', id)
  if (error) throw error
}

// ════════════════════════════════════════════
//  CONFIGURACIÓN
// ════════════════════════════════════════════

export async function getConfigPago() {
  const { data } = await supabase.from('config_pago').select('*').single()
  return data
}

export async function updateConfigPago(payload) {
  const { error } = await supabase.from('config_pago').update(payload).eq('id', 1)
  if (error) throw error
}

export async function getFranjasConfig() {
  const { data, error } = await supabase
    .from('franjas_precio')
    .select('*')
    .order('hora_inicio')
  if (error) throw error
  return data
}

export async function updateFranja(id, payload) {
  const { error } = await supabase.from('franjas_precio').update(payload).eq('id', id)
  if (error) throw error
}

export async function getHorarios() {
  const { data, error } = await supabase
    .from('horarios_operativos')
    .select('*')
    .order('dia_semana')
  if (error) throw error
  return data
}

export async function updateHorario(id, payload) {
  const { error } = await supabase.from('horarios_operativos').update(payload).eq('id', id)
  if (error) throw error
}
