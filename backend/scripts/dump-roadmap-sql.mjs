import dotenv from 'dotenv'
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'
import pg from 'pg'

dotenv.config({ quiet: true })

const dbName = process.argv[2] || 'put_roadmap_staging'
const url = new URL(process.env.DATABASE_URL.replace(/^postgres:/, 'postgresql:'))
url.pathname = `/${dbName}`
const client = new pg.Client({ connectionString: url.toString() })
await client.connect()

const views = await client.query(`
  SELECT c.relname, pg_get_viewdef(c.oid, true) AS def
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'v'
  ORDER BY c.relname
`)
const fns = await client.query(`
  SELECT pg_get_functiondef(p.oid) AS def
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
  ORDER BY p.proname, pg_get_function_identity_arguments(p.oid)
`)
await client.end()

let out = `-- Снимок функций и представлений public из ${dbName}.
-- Файл для просмотра и восстановления. Применение изменений схемы — через roadmap_logic.sql.
-- На момент снимка roadmap_task_file_* в put_roadmap_main отличались и этим скриптом не перезаписывались.

`
for (const row of views.rows) {
  const body = String(row.def || '').trim().replace(/;+\s*$/, '')
  out += `CREATE OR REPLACE VIEW public.${row.relname} AS\n${body};\n\n`
}
for (const row of fns.rows) {
  out += `${String(row.def || '').trim()};\n\n`
}

const target = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'sql', 'roadmap_catalog.sql')
fs.writeFileSync(target, out)
console.log(`wrote ${target} (${out.length} bytes, ${fns.rows.length} functions, ${views.rows.length} views)`)
