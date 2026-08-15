import { createClient } from '@supabase/supabase-js'

const SUPABASE_URL = 'https://nyrjuuynklrmyzgsgmwm.supabase.co'
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im55cmp1dXlua2xybXl6Z3NnbXdtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY3NTI1MTAsImV4cCI6MjEwMjMyODUxMH0.HWGdsOJWcC2JlVS7vczT9SGw954mIJcSmlc5MJCQZm0'

const supabaseInstance = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)

export function getSupabase() {
  return supabaseInstance
}

export function isConfigured() {
  return true
}
