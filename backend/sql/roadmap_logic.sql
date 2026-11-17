-- Логика роадмапа в Postgres.
-- Новые функции поверх уже существующих roadmap_* (их снимок — roadmap_catalog.sql).
-- Базовый год шкалы совпадает с фронтом: 2026.

CREATE OR REPLACE FUNCTION public.roadmap_month_index(p_date date)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT CASE
        WHEN p_date IS NULL THEN NULL::integer
        ELSE (EXTRACT(YEAR FROM p_date)::integer - 2026) * 12
             + (EXTRACT(MONTH FROM p_date)::integer - 1)
    END
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_quarter_index(p_date date)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT CASE
        WHEN p_date IS NULL THEN NULL::integer
        ELSE (EXTRACT(YEAR FROM p_date)::integer - 2026) * 4
             + ((EXTRACT(MONTH FROM p_date)::integer - 1) / 3)
    END
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_normalize_stage_dates(
    p_start text,
    p_end text,
    p_changed text
)
RETURNS TABLE(start_date text, release_date text)
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
    v_start date;
    v_end date;
    v_swap date;
BEGIN
    v_start := public.roadmap_try_date(p_start);
    v_end := public.roadmap_try_date(p_end);
    IF v_start IS NOT NULL AND v_end IS NOT NULL AND v_start > v_end THEN
        IF p_changed = 'startDate' THEN
            v_end := v_start;
        ELSIF p_changed = 'releaseDate' THEN
            v_start := v_end;
        ELSE
            v_swap := v_start;
            v_start := v_end;
            v_end := v_swap;
        END IF;
    END IF;
    start_date := COALESCE(to_char(v_start, 'YYYY-MM-DD'), '');
    release_date := COALESCE(to_char(v_end, 'YYYY-MM-DD'), '');
    RETURN NEXT;
END;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_update_block(p_block_id text, p_patch jsonb)
RETURNS text
LANGUAGE plpgsql
AS $function$
DECLARE
    v_start text;
    v_end text;
    v_norm_start text;
    v_norm_end text;
    v_effort integer;
    v_project text;
BEGIN
    IF p_block_id IS NULL OR btrim(p_block_id) = '' THEN
        RAISE EXCEPTION 'block_required' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public."Blocks" b WHERE b.id = p_block_id) THEN
        RAISE EXCEPTION 'block_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF p_patch IS NULL OR jsonb_typeof(p_patch) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'patch_object_required' USING ERRCODE = '22023';
    END IF;

    IF p_patch ? 'projectId' THEN
        v_project := NULLIF(btrim(COALESCE(p_patch ->> 'projectId', '')), '');
        IF v_project IS NULL OR NOT EXISTS (SELECT 1 FROM public."Projects" p WHERE p.id = v_project) THEN
            RAISE EXCEPTION 'project_not_found' USING ERRCODE = 'P0002';
        END IF;
    END IF;

    IF (p_patch ? 'startDate') OR (p_patch ? 'releaseDate') THEN
        SELECT b."startDate", b."releaseDate"
        INTO v_start, v_end
        FROM public."Blocks" b
        WHERE b.id = p_block_id;
        IF p_patch ? 'startDate' THEN
            v_start := p_patch ->> 'startDate';
        END IF;
        IF p_patch ? 'releaseDate' THEN
            v_end := p_patch ->> 'releaseDate';
        END IF;
        SELECT n.start_date, n.release_date
        INTO v_norm_start, v_norm_end
        FROM public.roadmap_normalize_stage_dates(v_start, v_end, p_patch ->> 'changedField') n;
    END IF;

    IF p_patch ? 'effort' THEN
        v_effort := GREATEST(0, COALESCE(trunc(public.roadmap_try_numeric(p_patch ->> 'effort')), 0))::integer;
    END IF;

    UPDATE public."Blocks" b
    SET
        title = CASE
            WHEN p_patch ? 'title' THEN COALESCE(NULLIF(btrim(p_patch ->> 'title'), ''), b.title)
            ELSE b.title
        END,
        description = CASE
            WHEN p_patch ? 'description' THEN COALESCE(p_patch ->> 'description', '')
            ELSE b.description
        END,
        "startDate" = CASE
            WHEN (p_patch ? 'startDate') OR (p_patch ? 'releaseDate') THEN v_norm_start
            ELSE b."startDate"
        END,
        "releaseDate" = CASE
            WHEN (p_patch ? 'startDate') OR (p_patch ? 'releaseDate') THEN v_norm_end
            ELSE b."releaseDate"
        END,
        effort = CASE
            WHEN p_patch ? 'effort' THEN v_effort
            ELSE b.effort
        END,
        "projectId" = CASE
            WHEN p_patch ? 'projectId' THEN v_project
            ELSE b."projectId"
        END,
        "ownerUsername" = CASE
            WHEN p_patch ? 'ownerUsername' THEN NULLIF(btrim(COALESCE(p_patch ->> 'ownerUsername', '')), '')
            ELSE b."ownerUsername"
        END,
        "updatedAt" = now()
    WHERE b.id = p_block_id;

    RETURN p_block_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_set_block_dates(
    p_block_id text,
    p_start text,
    p_end text,
    p_changed text
)
RETURNS text
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN public.roadmap_update_block(
        p_block_id,
        jsonb_build_object(
            'startDate', COALESCE(p_start, ''),
            'releaseDate', COALESCE(p_end, ''),
            'changedField', COALESCE(p_changed, '')
        )
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_delete_block(p_block_id text)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    IF p_block_id IS NULL OR btrim(p_block_id) = '' THEN
        RAISE EXCEPTION 'block_required' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public."Blocks" b WHERE b.id = p_block_id) THEN
        RAISE EXCEPTION 'block_not_found' USING ERRCODE = 'P0002';
    END IF;

    DELETE FROM public.roadmap_task_files f
    USING public.roadmap_tasks t
    WHERE f.task_id = t.id
      AND t.block_id = p_block_id;

    DELETE FROM public.roadmap_task_deps d
    WHERE d.task_id IN (SELECT t.id FROM public.roadmap_tasks t WHERE t.block_id = p_block_id)
       OR d.predecessor_id IN (SELECT t.id FROM public.roadmap_tasks t WHERE t.block_id = p_block_id);

    DELETE FROM public.roadmap_tasks t
    WHERE t.block_id = p_block_id;

    DELETE FROM public.roadmap_stage_deps d
    WHERE d.block_id = p_block_id
       OR d.predecessor_block_id = p_block_id;

    DELETE FROM public."Blocks" b
    WHERE b.id = p_block_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_visible_block_ids(
    p_project_id text,
    p_owners text[],
    p_extra_project_ids text[],
    p_owner_filter boolean
)
RETURNS TABLE(block_id text)
LANGUAGE sql
STABLE
AS $function$
    SELECT b.id::text
    FROM public."Blocks" b
    WHERE
        (
            NULLIF(btrim(COALESCE(p_project_id, '')), '') IS NOT NULL
            AND b."projectId" = btrim(p_project_id)
            AND (
                NOT COALESCE(p_owner_filter, false)
                OR lower(btrim(COALESCE(b."ownerUsername", ''))) IN (
                    SELECT lower(btrim(x))
                    FROM unnest(COALESCE(p_owners, ARRAY[]::text[])) AS u(x)
                    WHERE btrim(COALESCE(x, '')) <> ''
                )
            )
        )
        OR
        (
            NULLIF(btrim(COALESCE(p_project_id, '')), '') IS NULL
            AND (
                lower(btrim(COALESCE(b."ownerUsername", ''))) IN (
                    SELECT lower(btrim(x))
                    FROM unnest(COALESCE(p_owners, ARRAY[]::text[])) AS u(x)
                    WHERE btrim(COALESCE(x, '')) <> ''
                )
                OR (
                    COALESCE(cardinality(p_extra_project_ids), 0) > 0
                    AND b."projectId" = ANY (p_extra_project_ids)
                )
            )
        )
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_scope_stats(
    p_project_id text,
    p_owners text[],
    p_extra_project_ids text[],
    p_owner_filter boolean
)
RETURNS TABLE(
    completed_releases_count integer,
    in_progress_releases_count integer,
    total_tasks_count integer,
    completed_tasks_count integer,
    overall_progress integer,
    total_effort numeric,
    completed_effort numeric,
    completed_effort_percent integer
)
LANGUAGE sql
STABLE
AS $function$
    SELECT
        COALESCE(count(*) FILTER (WHERE c.stage_status = 'done'), 0)::integer,
        COALESCE(count(*) FILTER (WHERE c.tasks_total > 0 AND c.stage_status IS DISTINCT FROM 'done'), 0)::integer,
        COALESCE(sum(c.tasks_total), 0)::integer,
        COALESCE(sum(c.tasks_done), 0)::integer,
        CASE
            WHEN COALESCE(sum(c.tasks_total), 0) = 0 THEN 0
            ELSE round(100.0 * sum(c.tasks_done)::numeric / sum(c.tasks_total)::numeric)::integer
        END,
        COALESCE(sum(b.effort), 0)::numeric,
        COALESCE(sum(
            CASE
                WHEN c.stage_status = 'done' THEN COALESCE(b.effort, 0)
                ELSE 0
            END
        ), 0)::numeric,
        CASE
            WHEN COALESCE(sum(b.effort), 0) = 0 THEN 0
            ELSE round(
                100.0 * sum(
                    CASE
                        WHEN c.stage_status = 'done' THEN COALESCE(b.effort, 0)
                        ELSE 0
                    END
                )::numeric / sum(COALESCE(b.effort, 0))::numeric
            )::integer
        END
    FROM public.roadmap_visible_block_ids(p_project_id, p_owners, p_extra_project_ids, p_owner_filter) v
    JOIN public.v_block_computed c ON c.block_id::text = v.block_id
    JOIN public."Blocks" b ON b.id::text = v.block_id
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_block_payload(p_block_id text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_block public."Blocks"%ROWTYPE;
    v_h record;
    v_plan_start date;
    v_plan_end date;
    v_swap date;
BEGIN
    SELECT * INTO v_block
    FROM public."Blocks" b
    WHERE b.id = p_block_id;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    SELECT *
    INTO v_h
    FROM public.roadmap_hydrate_blocks(ARRAY[p_block_id::text]);

    v_plan_start := public.roadmap_try_date(v_block."startDate");
    v_plan_end := public.roadmap_try_date(v_block."releaseDate");
    IF v_plan_start IS NULL THEN
        v_plan_start := v_plan_end;
    END IF;
    IF v_plan_end IS NULL THEN
        v_plan_end := v_plan_start;
    END IF;
    IF v_plan_start IS NOT NULL AND v_plan_end IS NOT NULL AND v_plan_start > v_plan_end THEN
        v_swap := v_plan_start;
        v_plan_start := v_plan_end;
        v_plan_end := v_swap;
    END IF;

    RETURN jsonb_build_object(
        'id', v_block.id,
        'title', v_block.title,
        'description', COALESCE(v_block.description, ''),
        'ownerUsername', v_block."ownerUsername",
        'projectId', v_block."projectId",
        'startDate', v_block."startDate",
        'releaseDate', v_block."releaseDate",
        'effort', v_block.effort,
        'completed', COALESCE(v_h.stage_status, 'idle') = 'done',
        'createdAt', v_block."createdAt",
        'updatedAt', v_block."updatedAt",
        'tasks', COALESCE(v_h.tasks, '[]'::jsonb),
        'progressPercent', COALESCE(v_h.progress_percent, 0),
        'stageStatus', COALESCE(v_h.stage_status, 'idle'),
        'isOverdue', COALESCE(v_h.is_overdue, false),
        'taskCounts', jsonb_build_object(
            'total', COALESCE(v_h.tasks_total, 0),
            'todo', COALESCE(v_h.tasks_todo, 0),
            'progress', COALESCE(v_h.tasks_progress, 0),
            'done', COALESCE(v_h.tasks_done, 0)
        ),
        'stagePredecessorIds', COALESCE(v_h.stage_predecessor_ids, '[]'::jsonb),
        'stageDependencies', COALESCE(v_h.stage_dependencies, '[]'::jsonb),
        'planMonthIndexStart', public.roadmap_month_index(v_plan_start),
        'planMonthIndexEnd', public.roadmap_month_index(v_plan_end),
        'planQuarterIndexStart', public.roadmap_quarter_index(v_plan_start),
        'planQuarterIndexEnd', public.roadmap_quarter_index(v_plan_end),
        'planSortKey',
            COALESCE(to_char(v_plan_start, 'YYYY-MM-DD'), '9999-99-99')
            || '|'
            || COALESCE(to_char(v_plan_end, 'YYYY-MM-DD'), '9999-99-99')
            || '|'
            || v_block.id
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_list_blocks(
    p_project_id text,
    p_owners text[],
    p_extra_project_ids text[],
    p_owner_filter boolean
)
RETURNS TABLE(block jsonb)
LANGUAGE sql
STABLE
AS $function$
    SELECT public.roadmap_block_payload(b.id) AS block
    FROM public.roadmap_visible_block_ids(p_project_id, p_owners, p_extra_project_ids, p_owner_filter) v
    JOIN public."Blocks" b ON b.id::text = v.block_id
    ORDER BY b."releaseDate" ASC NULLS LAST, b.id
$function$;

-- Точечная синхронизация списка задач: правки, вставки и удаления.
-- Полная перезапись roadmap_replace_block_tasks остаётся для импорта.
CREATE OR REPLACE FUNCTION public.roadmap_sync_block_tasks(p_block_id text, p_tasks jsonb)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_elem jsonb;
    v_idx integer;
    v_id text;
    v_ids text[];
    v_start date;
    v_end date;
    v_order integer;
BEGIN
    IF p_block_id IS NULL OR btrim(p_block_id) = '' THEN
        RAISE EXCEPTION 'block_required' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public."Blocks" b WHERE b.id = p_block_id) THEN
        RAISE EXCEPTION 'block_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF p_tasks IS NULL OR jsonb_typeof(p_tasks) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'tasks_array_required' USING ERRCODE = '22023';
    END IF;

    DROP TABLE IF EXISTS tmp_roadmap_diff_src;
    DROP TABLE IF EXISTS tmp_roadmap_diff_deps;
    CREATE TEMP TABLE tmp_roadmap_diff_src (
        task_id text PRIMARY KEY,
        elem jsonb,
        elem_idx integer,
        title text,
        status text,
        sort_order integer,
        effort numeric,
        owner text,
        description text,
        start_date date,
        end_date date,
        link_url text,
        link_note text
    );

    FOR v_elem, v_idx IN
        SELECT e.elem, e.elem_idx::integer
        FROM jsonb_array_elements(p_tasks) WITH ORDINALITY AS e(elem, elem_idx)
        WHERE jsonb_typeof(e.elem) = 'object'
    LOOP
        v_id := NULLIF(btrim(COALESCE(v_elem ->> 'id', '')), '');
        IF v_id IS NULL THEN
            v_id := to_char((extract(epoch FROM clock_timestamp()) * 1000)::bigint, 'FM999999999999999')
                || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 9);
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_roadmap_diff_src s WHERE s.task_id = v_id)
           OR EXISTS (
                SELECT 1
                FROM public.roadmap_tasks t
                WHERE t.id = v_id
                  AND t.block_id IS DISTINCT FROM p_block_id
           )
        THEN
            v_id := v_id || '-' || p_block_id || '-' || v_idx::text;
        END IF;

        v_start := public.roadmap_try_date(v_elem ->> 'startDate');
        v_end := public.roadmap_try_date(v_elem ->> 'releaseDate');
        IF v_start IS NOT NULL AND v_end IS NOT NULL AND v_start > v_end THEN
            v_end := v_start;
        END IF;
        v_order := COALESCE(trunc(public.roadmap_try_numeric(v_elem ->> 'order')), v_idx)::integer;

        INSERT INTO tmp_roadmap_diff_src (
            task_id, elem, elem_idx, title, status, sort_order, effort, owner, description,
            start_date, end_date, link_url, link_note
        ) VALUES (
            v_id,
            v_elem,
            v_idx,
            COALESCE(v_elem ->> 'title', ''),
            CASE lower(btrim(COALESCE(v_elem ->> 'status', '')))
                WHEN 'todo' THEN 'todo'
                WHEN 'progress' THEN 'progress'
                WHEN 'done' THEN 'done'
                ELSE 'todo'
            END,
            v_order,
            GREATEST(0, COALESCE(public.roadmap_try_numeric(v_elem ->> 'effort'), 0)),
            COALESCE(v_elem ->> 'owner', ''),
            COALESCE(v_elem ->> 'description', ''),
            v_start,
            v_end,
            btrim(COALESCE(
                NULLIF(btrim(COALESCE(v_elem ->> 'linkUrl', '')), ''),
                NULLIF(btrim(COALESCE(v_elem ->> 'link', '')), ''),
                ''
            )),
            COALESCE(v_elem ->> 'linkNote', '')
        );
    END LOOP;

    CREATE TEMP TABLE tmp_roadmap_diff_deps AS
    SELECT DISTINCT
        r.task_id,
        COALESCE(m.task_id, ext.id) AS predecessor_id,
        r.dep_type,
        r.lag_days
    FROM (
        SELECT
            c.task_id,
            NULLIF(btrim(COALESCE(link ->> 'predId', '')), '') AS pred_alias,
            CASE upper(btrim(COALESCE(link ->> 'type', '')))
                WHEN 'SS' THEN 'SS'
                WHEN 'FF' THEN 'FF'
                WHEN 'SF' THEN 'SF'
                ELSE 'FS'
            END AS dep_type,
            COALESCE(trunc(public.roadmap_try_numeric(link ->> 'lagDays')), 0)::integer AS lag_days
        FROM (
            SELECT
                s.task_id,
                s.elem,
                CASE
                    WHEN jsonb_typeof(s.elem -> 'predecessorLinks') = 'array'
                         AND EXISTS (
                             SELECT 1
                             FROM jsonb_array_elements(s.elem -> 'predecessorLinks') x
                             WHERE jsonb_typeof(x) = 'object'
                               AND NULLIF(btrim(COALESCE(x ->> 'predId', '')), '') IS NOT NULL
                         )
                    THEN s.elem -> 'predecessorLinks'
                    ELSE NULL
                END AS links_json
            FROM tmp_roadmap_diff_src s
        ) c
        CROSS JOIN LATERAL jsonb_array_elements(c.links_json) AS link
        WHERE c.links_json IS NOT NULL
          AND jsonb_typeof(link) = 'object'
        UNION ALL
        SELECT
            c.task_id,
            NULLIF(btrim(id_el #>> '{}'), '') AS pred_alias,
            'FS'::text,
            0
        FROM (
            SELECT
                s.task_id,
                s.elem,
                CASE
                    WHEN jsonb_typeof(s.elem -> 'predecessorLinks') = 'array'
                         AND EXISTS (
                             SELECT 1
                             FROM jsonb_array_elements(s.elem -> 'predecessorLinks') x
                             WHERE jsonb_typeof(x) = 'object'
                               AND NULLIF(btrim(COALESCE(x ->> 'predId', '')), '') IS NOT NULL
                         )
                    THEN s.elem -> 'predecessorLinks'
                    ELSE NULL
                END AS links_json,
                CASE
                    WHEN jsonb_typeof(s.elem -> 'predecessorIds') = 'array'
                         AND jsonb_array_length(s.elem -> 'predecessorIds') > 0
                    THEN s.elem -> 'predecessorIds'
                    WHEN jsonb_typeof(s.elem -> 'dependencies') = 'array'
                         AND jsonb_array_length(s.elem -> 'dependencies') > 0
                    THEN s.elem -> 'dependencies'
                    ELSE NULL
                END AS ids_json
            FROM tmp_roadmap_diff_src s
        ) c
        CROSS JOIN LATERAL jsonb_array_elements(c.ids_json) AS id_el
        WHERE c.links_json IS NULL
          AND c.ids_json IS NOT NULL
    ) r
    LEFT JOIN (
        SELECT DISTINCT ON (alias_id)
            alias_id,
            task_id
        FROM (
            SELECT NULLIF(btrim(COALESCE(elem ->> 'id', '')), '') AS alias_id, task_id, elem_idx
            FROM tmp_roadmap_diff_src
            UNION ALL
            SELECT task_id, task_id, elem_idx
            FROM tmp_roadmap_diff_src
        ) aliases
        WHERE alias_id IS NOT NULL AND alias_id <> ''
        ORDER BY alias_id, elem_idx
    ) m ON m.alias_id = r.pred_alias
    LEFT JOIN public.roadmap_tasks ext
        ON ext.id = r.pred_alias
       AND m.task_id IS NULL
    WHERE r.pred_alias IS NOT NULL
      AND COALESCE(m.task_id, ext.id) IS NOT NULL
      AND COALESCE(m.task_id, ext.id) <> r.task_id;

    IF EXISTS (
        WITH RECURSIVE walk AS (
            SELECT d.task_id AS node, ARRAY[d.predecessor_id] AS seen
            FROM (
                SELECT task_id, predecessor_id FROM tmp_roadmap_diff_deps
                UNION ALL
                SELECT dep.task_id, dep.predecessor_id
                FROM public.roadmap_task_deps dep
                WHERE dep.task_id NOT IN (SELECT s.task_id FROM tmp_roadmap_diff_src s)
            ) d
            UNION ALL
            SELECT e.task_id, w.seen || w.node
            FROM walk w
            JOIN (
                SELECT task_id, predecessor_id FROM tmp_roadmap_diff_deps
                UNION ALL
                SELECT dep.task_id, dep.predecessor_id
                FROM public.roadmap_task_deps dep
                WHERE dep.task_id NOT IN (SELECT s.task_id FROM tmp_roadmap_diff_src s)
            ) e ON e.predecessor_id = w.node
            WHERE NOT w.node = ANY (w.seen)
        )
        SELECT 1 FROM walk WHERE node = ANY (seen)
    ) THEN
        RAISE EXCEPTION 'task_dep_cycle' USING ERRCODE = '22023';
    END IF;

    DELETE FROM public.roadmap_task_files f
    USING public.roadmap_tasks t
    WHERE f.task_id = t.id
      AND t.block_id = p_block_id
      AND NOT EXISTS (SELECT 1 FROM tmp_roadmap_diff_src s WHERE s.task_id = t.id);

    DELETE FROM public.roadmap_task_deps d
    WHERE d.task_id IN (
            SELECT t.id
            FROM public.roadmap_tasks t
            WHERE t.block_id = p_block_id
              AND NOT EXISTS (SELECT 1 FROM tmp_roadmap_diff_src s WHERE s.task_id = t.id)
        )
       OR d.predecessor_id IN (
            SELECT t.id
            FROM public.roadmap_tasks t
            WHERE t.block_id = p_block_id
              AND NOT EXISTS (SELECT 1 FROM tmp_roadmap_diff_src s WHERE s.task_id = t.id)
        );

    DELETE FROM public.roadmap_tasks t
    WHERE t.block_id = p_block_id
      AND NOT EXISTS (SELECT 1 FROM tmp_roadmap_diff_src s WHERE s.task_id = t.id);

    INSERT INTO public.roadmap_tasks (
        id, block_id, title, status, sort_order, effort, owner, description,
        start_date, end_date, link_url, link_note
    )
    SELECT
        s.task_id,
        p_block_id,
        s.title,
        s.status,
        COALESCE((
            SELECT MAX(t.sort_order)
            FROM public.roadmap_tasks t
            WHERE t.block_id = p_block_id
        ), -1) + s.elem_idx,
        s.effort,
        s.owner,
        s.description,
        s.start_date,
        s.end_date,
        s.link_url,
        s.link_note
    FROM tmp_roadmap_diff_src s
    WHERE NOT EXISTS (SELECT 1 FROM public.roadmap_tasks t WHERE t.id = s.task_id);

    UPDATE public.roadmap_tasks t
    SET
        title = s.title,
        status = s.status,
        effort = s.effort,
        owner = s.owner,
        description = s.description,
        start_date = s.start_date,
        end_date = s.end_date,
        link_url = s.link_url,
        link_note = s.link_note,
        updated_at = now()
    FROM tmp_roadmap_diff_src s
    WHERE t.id = s.task_id
      AND t.block_id = p_block_id;

    DELETE FROM public.roadmap_task_deps d
    WHERE d.task_id IN (SELECT s.task_id FROM tmp_roadmap_diff_src s);

    INSERT INTO public.roadmap_task_deps (task_id, predecessor_id, dep_type, lag_days)
    SELECT d.task_id, d.predecessor_id, d.dep_type, d.lag_days
    FROM tmp_roadmap_diff_deps d;

    SELECT COALESCE(array_agg(s.task_id ORDER BY s.sort_order, s.elem_idx), ARRAY[]::text[])
    INTO v_ids
    FROM tmp_roadmap_diff_src s;

    IF COALESCE(array_length(v_ids, 1), 0) > 0 THEN
        PERFORM public.roadmap_reorder_tasks(p_block_id, v_ids);
    ELSE
        PERFORM public.roadmap_write_json_from_tables(p_block_id);
    END IF;

    DROP TABLE IF EXISTS tmp_roadmap_diff_deps;
    DROP TABLE IF EXISTS tmp_roadmap_diff_src;
END;
$function$;
