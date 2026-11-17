import dotenv from 'dotenv'
import pg from 'pg'

dotenv.config({ quiet: true })

const dbName = process.argv[2]
if (!dbName) {
  console.error('usage: node scripts/check-roadmap-sql.mjs <database>')
  process.exit(1)
}

const url = new URL(process.env.DATABASE_URL.replace(/^postgres:/, 'postgresql:'))
url.pathname = `/${dbName}`
const client = new pg.Client({ connectionString: url.toString() })
await client.connect()

const fail = (message) => {
  throw new Error(message)
}

const assert = (cond, message) => {
  if (!cond) fail(message)
}

try {
  await client.query('BEGIN')
  const project = await client.query('SELECT id, "ownerUsername" FROM public."Projects" ORDER BY "createdAt" ASC LIMIT 1')
  assert(project.rows[0], 'no project')
  const projectId = project.rows[0].id
  const owner = project.rows[0].ownerUsername

  const created = await client.query(
    'SELECT block_id FROM public.roadmap_create_block($1, $2, $3, $4)',
    [projectId, owner, 'sql-check-stage', 'check']
  )
  const blockId = created.rows[0].block_id
  assert(blockId, 'create failed')

  await client.query(
    'SELECT public.roadmap_set_block_dates($1, $2, $3, $4)',
    [blockId, '2026-06-10', '2026-05-01', 'releaseDate']
  )
  let row = (await client.query('SELECT "startDate", "releaseDate" FROM public."Blocks" WHERE id = $1', [blockId])).rows[0]
  assert(row.startDate === '2026-05-01' && row.releaseDate === '2026-05-01', `releaseDate clamp ${row.startDate} ${row.releaseDate}`)

  await client.query(
    'SELECT public.roadmap_set_block_dates($1, $2, $3, $4)',
    [blockId, '2026-08-01', '2026-07-15', 'startDate']
  )
  row = (await client.query('SELECT "startDate", "releaseDate" FROM public."Blocks" WHERE id = $1', [blockId])).rows[0]
  assert(row.startDate === '2026-08-01' && row.releaseDate === '2026-08-01', `startDate clamp ${row.startDate} ${row.releaseDate}`)

  await client.query(
    'SELECT public.roadmap_update_block($1, $2::jsonb)',
    [blockId, JSON.stringify({
      title: 'sql-check-renamed',
      startDate: '2026-09-10',
      releaseDate: '2026-09-01',
      effort: 12
    })]
  )
  row = (await client.query('SELECT title, "startDate", "releaseDate", effort FROM public."Blocks" WHERE id = $1', [blockId])).rows[0]
  assert(row.title === 'sql-check-renamed', 'title')
  assert(row.startDate === '2026-09-01' && row.releaseDate === '2026-09-10', `swap ${row.startDate} ${row.releaseDate}`)
  assert(Number(row.effort) === 12, 'effort')

  const payload = (await client.query('SELECT public.roadmap_block_payload($1) AS block', [blockId])).rows[0].block
  assert(payload.planMonthIndexStart === 8, `month start ${payload.planMonthIndexStart}`)
  assert(payload.planMonthIndexEnd === 8, `month end ${payload.planMonthIndexEnd}`)
  assert(payload.planQuarterIndexStart === 2, `quarter ${payload.planQuarterIndexStart}`)
  assert(String(payload.planSortKey || '').startsWith('2026-09-01|2026-09-10|'), `sort ${payload.planSortKey}`)

  await client.query(
    'SELECT public.roadmap_sync_block_tasks($1, $2::jsonb)',
    [blockId, JSON.stringify([
      { id: 'task-keep', title: 'Keep', status: 'todo', order: 0, effort: 1 },
      { id: 'task-drop', title: 'Drop', status: 'todo', order: 1 }
    ])]
  )
  await client.query(
    `INSERT INTO public.roadmap_task_files (id, task_id, file_name, mime, byte_size, content)
     VALUES ('file-keep', 'task-keep', 'a.txt', 'text/plain', 4, '\\x61626364')`
  )
  await client.query(
    'SELECT public.roadmap_sync_block_tasks($1, $2::jsonb)',
    [blockId, JSON.stringify([
      {
        id: 'task-keep',
        title: 'Keep renamed',
        status: 'progress',
        order: 1,
        predecessorLinks: [{ predId: 'task-other', type: 'FS', lagDays: 0 }]
      },
      { id: 'task-new', title: 'New', status: 'todo', order: 0 }
    ])]
  )

  const tasks = await client.query(
    'SELECT id, title, status FROM public.roadmap_tasks WHERE block_id = $1 ORDER BY sort_order',
    [blockId]
  )
  assert(tasks.rows.map((t) => t.id).join(',') === 'task-new,task-keep', `tasks ${tasks.rows.map((t) => t.id).join(',')}`)
  assert(tasks.rows[1].title === 'Keep renamed' && tasks.rows[1].status === 'progress', 'patch fields')
  const files = await client.query('SELECT id FROM public.roadmap_task_files WHERE task_id = $1', ['task-keep'])
  assert(files.rows.length === 1, 'file kept across sync')
  const dropped = await client.query('SELECT id FROM public.roadmap_tasks WHERE id = $1', ['task-drop'])
  assert(dropped.rows.length === 0, 'dropped task removed')

  const listed = await client.query(
    'SELECT block FROM public.roadmap_list_blocks($1, $2::text[], $3::text[], $4) WHERE (block->>\'id\') = $5',
    [projectId, [owner], [], true, blockId]
  )
  assert(listed.rows.length === 1, 'list miss')
  assert(listed.rows[0].block.tasks.length === 2, 'list tasks')

  const stats = await client.query(
    'SELECT * FROM public.roadmap_scope_stats($1, $2::text[], $3::text[], $4)',
    [projectId, [owner], [], true]
  )
  assert(stats.rows.length === 1, 'stats row')
  assert(Number(stats.rows[0].total_tasks_count) >= 2, 'stats tasks')

  const openStats = await client.query(
    'SELECT * FROM public.roadmap_scope_stats($1, $2::text[], $3::text[], $4)',
    [null, [owner], [], true]
  )
  assert(openStats.rows.length === 1, 'stats without project')
  assert(Number(openStats.rows[0].total_tasks_count) >= 2, 'open stats tasks')

  await client.query('SELECT public.roadmap_delete_block($1)', [blockId])
  const goneBlock = await client.query('SELECT id FROM public."Blocks" WHERE id = $1', [blockId])
  const goneTasks = await client.query('SELECT id FROM public.roadmap_tasks WHERE block_id = $1', [blockId])
  const goneFile = await client.query('SELECT id FROM public.roadmap_task_files WHERE id = $1', ['file-keep'])
  assert(goneBlock.rows.length === 0 && goneTasks.rows.length === 0 && goneFile.rows.length === 0, 'delete cascade')

  await client.query('ROLLBACK')
  console.log(`ok ${dbName}`)
} catch (error) {
  await client.query('ROLLBACK')
  console.error(error)
  process.exitCode = 1
} finally {
  await client.end()
}
