import dotenv from 'dotenv'
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'
import pg from 'pg'

dotenv.config()

const dbName = process.argv[2]
if (!dbName) {
  console.error('usage: node scripts/apply-roadmap-sql.mjs <database>')
  process.exit(1)
}

const databaseUrl = process.env.DATABASE_URL
if (!databaseUrl) {
  console.error('DATABASE_URL is not set')
  process.exit(1)
}

const url = new URL(databaseUrl.replace(/^postgres:/, 'postgresql:'))
url.pathname = `/${dbName}`

const here = dirname(fileURLToPath(import.meta.url))
const sqlPath = path.join(here, '..', 'sql', 'roadmap_logic.sql')
const sql = fs.readFileSync(sqlPath, 'utf8')

const client = new pg.Client({ connectionString: url.toString() })
await client.connect()
await client.query(sql)
await client.end()
console.log(`applied roadmap_logic.sql to ${dbName}`)

function dirname(fileUrlPath) {
  return path.dirname(fileUrlPath)
}
