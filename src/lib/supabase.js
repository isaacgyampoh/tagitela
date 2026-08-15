import { createClient } from '@supabase/supabase-js'

const SUPABASE_URL = 'https://nyrjuuynklrmyzgsgmwm.supabase.co'
const SUPABASE_ANON_KEY = 'YOUR_TAGITELA_ANON_KEY'

const supabaseInstance = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)

export function getSupabase() {
  return supabaseInstance
}

export function isConfigured() {
  return true
}
