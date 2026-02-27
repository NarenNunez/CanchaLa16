// src/lib/supabase.js
// ─────────────────────────────────────────────
//  Cliente Supabase único para toda la app.
//  Lee las credenciales desde window.ENV
//  (inyectadas en el <head> de cada HTML).
// ─────────────────────────────────────────────

import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm'

const URL = window.ENV?.SUPABASE_URL || ''
const KEY = window.ENV?.SUPABASE_ANON_KEY || ''

if (!URL || !KEY) {
  console.error('[Supabase] Faltan SUPABASE_URL o SUPABASE_ANON_KEY en window.ENV')
}

export const supabase = createClient(URL, KEY, {
  auth: { persistSession: true, autoRefreshToken: true }
})

// ─── Auth helpers ──────────────────────────────
export async function getSession() {
  const { data } = await supabase.auth.getSession()
  return data.session
}

export async function getPerfil(userId) {
  const { data } = await supabase
    .from('perfiles')
    .select('*')
    .eq('id', userId)
    .single()
  return data
}

export async function isAdmin() {
  const session = await getSession()
  if (!session) return false
  const perfil = await getPerfil(session.user.id)
  return perfil?.rol === 'admin'
}
