import { PGlite } from '@electric-sql/pglite'
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto'
import fs from 'node:fs'
import path from 'node:path'

const DIR = new URL('../supabase/migrations', import.meta.url).pathname

export async function boot () {
  const db = await new PGlite({ extensions: { pgcrypto } })
  // Supabase 環境的替身：角色 + auth.uid()
  await db.exec(`
    create role anon;
    create role authenticated;
    create schema if not exists auth;
    create table if not exists auth._who (uid uuid);
    create or replace function auth.uid() returns uuid
      language sql stable as $$ select uid from auth._who limit 1 $$;
  `)
  for (const f of fs.readdirSync(DIR).sort()) {
    const sql = fs.readFileSync(path.join(DIR, f), 'utf8')
    try { await db.exec(sql) }
    catch (e) { console.error(`\n✗ ${f}\n  ${e.message}\n`); throw e }
    console.log(`✓ ${f}`)
  }
  return db
}
