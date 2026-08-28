import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_KEY

export const configured = Boolean(url && key)

if (!configured) {
  console.error('缺少 VITE_SUPABASE_URL / VITE_SUPABASE_KEY，請參考 .env.example 建立 .env')
}

export const supabase = configured
  ? createClient(url, key, { auth: { persistSession: true, autoRefreshToken: true } })
  : null
