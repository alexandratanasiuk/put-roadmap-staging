-- Снимок функций и представлений public из put_roadmap_staging.
-- Файл для просмотра и восстановления. Применение изменений схемы — через roadmap_logic.sql.
-- На момент снимка roadmap_task_file_* в put_roadmap_main отличались и этим скриптом не перезаписывались.

CREATE OR REPLACE VIEW public.v_block_computed AS
SELECT block_id,
    project_id,
    tasks_total,
    tasks_todo,
    tasks_progress,
    tasks_done,
    progress_percent,
    stage_status,
    release_date IS NOT NULL AND release_date < CURRENT_DATE AND progress_percent < 100 AS is_overdue
   FROM ( SELECT b.id AS block_id,
            b."projectId" AS project_id,
                CASE
                    WHEN b."releaseDate"::text ~ '^\d{4}-\d{2}-\d{2}$'::text THEN b."releaseDate"::date
                    ELSE NULL::date
                END AS release_date,
            count(t.id)::integer AS tasks_total,
            count(*) FILTER (WHERE t.status = 'todo'::text)::integer AS tasks_todo,
            count(*) FILTER (WHERE t.status = 'progress'::text)::integer AS tasks_progress,
            count(*) FILTER (WHERE t.status = 'done'::text)::integer AS tasks_done,
                CASE
                    WHEN count(t.id) = 0 THEN 0
                    ELSE round(100.0 * count(*) FILTER (WHERE t.status = 'done'::text)::numeric / count(t.id)::numeric)::integer
                END AS progress_percent,
                CASE
                    WHEN count(t.id) = 0 THEN 'idle'::text
                    WHEN count(*) FILTER (WHERE t.status = 'done'::text) = count(t.id) THEN 'done'::text
                    WHEN count(*) FILTER (WHERE t.status = ANY (ARRAY['progress'::text, 'done'::text])) > 0 THEN 'started'::text
                    ELSE 'idle'::text
                END AS stage_status
           FROM "Blocks" b
             LEFT JOIN roadmap_tasks t ON t.block_id = b.id::text
          GROUP BY b.id, b."projectId", b."releaseDate") base;

CREATE OR REPLACE VIEW public.v_project_stats AS
SELECT c.project_id,
    count(*)::integer AS blocks_total,
    count(*) FILTER (WHERE c.stage_status = 'done'::text)::integer AS completed_releases_count,
    count(*) FILTER (WHERE c.tasks_total > 0 AND c.stage_status IS DISTINCT FROM 'done'::text)::integer AS in_progress_releases_count,
    COALESCE(sum(c.tasks_total), 0::bigint)::integer AS total_tasks_count,
    COALESCE(sum(c.tasks_done), 0::bigint)::integer AS completed_tasks_count,
        CASE
            WHEN COALESCE(sum(c.tasks_total), 0::bigint) = 0 THEN 0
            ELSE round(100.0 * sum(c.tasks_done)::numeric / sum(c.tasks_total)::numeric)::integer
        END AS overall_progress,
    COALESCE(sum(b.effort), 0::bigint)::numeric AS total_effort,
    COALESCE(sum(
        CASE
            WHEN c.stage_status = 'done'::text THEN COALESCE(b.effort, 0)
            ELSE 0
        END), 0::bigint)::numeric AS completed_effort,
        CASE
            WHEN COALESCE(sum(b.effort), 0::bigint) = 0 THEN 0
            ELSE round(100.0 * sum(
            CASE
                WHEN c.stage_status = 'done'::text THEN COALESCE(b.effort, 0)
                ELSE 0
            END)::numeric / sum(COALESCE(b.effort, 0))::numeric)::integer
        END AS completed_effort_percent
   FROM v_block_computed c
     JOIN "Blocks" b ON b.id::text = c.block_id::text
  GROUP BY c.project_id;

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

CREATE OR REPLACE FUNCTION public.roadmap_create_block(p_project_id text, p_owner_username text, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text)
 RETURNS TABLE(block_id text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_id text;
    v_title text;
    v_owner text;
    v_last_end date;
    v_start date;
    v_end date;
BEGIN
    IF p_project_id IS NULL OR btrim(p_project_id) = '' THEN
        RAISE EXCEPTION 'project_required' USING ERRCODE = '22023';
    END IF;
    v_owner := NULLIF(btrim(COALESCE(p_owner_username, '')), '');
    IF v_owner IS NULL THEN
        RAISE EXCEPTION 'owner_required' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public."Projects" p WHERE p.id = p_project_id) THEN
        RAISE EXCEPTION 'project_not_found' USING ERRCODE = 'P0002';
    END IF;

    SELECT MAX(public.roadmap_try_date(b."releaseDate"))
    INTO v_last_end
    FROM public."Blocks" b
    WHERE b."projectId" = p_project_id;

    IF v_last_end IS NULL THEN
        v_start := date_trunc('month', CURRENT_DATE)::date;
        v_end := (v_start + INTERVAL '1 month' - INTERVAL '1 day')::date;
    ELSE
        v_start := v_last_end;
        v_end := (v_last_end + INTERVAL '1 month')::date;
    END IF;

    v_title := COALESCE(
        NULLIF(btrim(COALESCE(p_title, '')), ''),
        'Новый этап ' || to_char(clock_timestamp(), 'DD.MM.YYYY, HH24:MI:SS')
    );
    v_id := to_char((extract(epoch FROM clock_timestamp()) * 1000)::bigint, 'FM999999999999999')
        || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 9);

    INSERT INTO public."Blocks" (
        id, title, description, "startDate", "releaseDate", effort, completed,
        "createdAt", "updatedAt", "ownerUsername", "projectId"
    ) VALUES (
        v_id,
        v_title,
        COALESCE(p_description, ''),
        to_char(v_start, 'YYYY-MM-DD'),
        to_char(v_end, 'YYYY-MM-DD'),
        40,
        false,
        now(),
        now(),
        v_owner,
        p_project_id
    );

    block_id := v_id;
    RETURN NEXT;
END;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_cycle_task_status(p_task_id text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_block_id text;
BEGIN
    UPDATE public.roadmap_tasks
    SET
        status = CASE status
            WHEN 'todo' THEN 'progress'
            WHEN 'progress' THEN 'done'
            ELSE 'todo'
        END,
        updated_at = now()
    WHERE id = p_task_id
    RETURNING block_id INTO v_block_id;

    IF v_block_id IS NULL THEN
        RAISE EXCEPTION 'task_not_found' USING ERRCODE = 'P0002';
    END IF;

    PERFORM public.roadmap_write_json_from_tables(v_block_id);
    RETURN v_block_id;
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

CREATE OR REPLACE FUNCTION public.roadmap_delete_task(p_task_id text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_block_id text;
BEGIN
    SELECT t.block_id INTO v_block_id
    FROM public.roadmap_tasks t
    WHERE t.id = p_task_id;

    IF v_block_id IS NULL THEN
        RAISE EXCEPTION 'task_not_found' USING ERRCODE = 'P0002';
    END IF;

    DELETE FROM public.roadmap_tasks WHERE id = p_task_id;
    PERFORM public.roadmap_densify_task_order(v_block_id);
    PERFORM public.roadmap_write_json_from_tables(v_block_id);
    RETURN v_block_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_densify_task_order(p_block_id text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    UPDATE public.roadmap_tasks t
    SET sort_order = -1000000 - t.sort_order
    WHERE t.block_id = p_block_id;

    UPDATE public.roadmap_tasks t
    SET sort_order = x.rn - 1
    FROM (
        SELECT id, row_number() OVER (ORDER BY sort_order DESC, id) AS rn
        FROM public.roadmap_tasks
        WHERE block_id = p_block_id
    ) x
    WHERE t.id = x.id
      AND t.block_id = p_block_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_hydrate_blocks(p_block_ids text[])
 RETURNS TABLE(block_id text, tasks jsonb, progress_percent integer, stage_status text, tasks_total integer, tasks_todo integer, tasks_progress integer, tasks_done integer, is_overdue boolean, stage_predecessor_ids jsonb, stage_dependencies jsonb)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT
        c.block_id,
        COALESCE(j.tasks, '[]'::jsonb) AS tasks,
        c.progress_percent,
        c.stage_status,
        c.tasks_total,
        c.tasks_todo,
        c.tasks_progress,
        c.tasks_done,
        c.is_overdue,
        COALESCE(sd.stage_predecessor_ids, '[]'::jsonb) AS stage_predecessor_ids,
        COALESCE(sd.stage_dependencies, '[]'::jsonb) AS stage_dependencies
    FROM public.v_block_computed c
    LEFT JOIN public.roadmap_tasks_as_json(p_block_ids) j ON j.block_id = c.block_id
    LEFT JOIN (
        SELECT
            d.block_id,
            COALESCE(
                jsonb_agg(to_jsonb(d.predecessor_block_id) ORDER BY d.predecessor_block_id),
                '[]'::jsonb
            ) AS stage_predecessor_ids,
            COALESCE(
                jsonb_agg(
                    jsonb_build_object(
                        'predecessorId', d.predecessor_block_id,
                        'depType', d.dep_type,
                        'lagDays', d.lag_days,
                        'labelText', d.label_text,
                        'labelKind', d.label_kind,
                        'labelDate', COALESCE(to_char(d.label_date, 'YYYY-MM-DD'), '')
                    )
                    ORDER BY d.predecessor_block_id
                ),
                '[]'::jsonb
            ) AS stage_dependencies
        FROM public.roadmap_stage_deps d
        WHERE d.block_id = ANY (p_block_ids)
        GROUP BY d.block_id
    ) sd ON sd.block_id = c.block_id
    WHERE c.block_id = ANY(p_block_ids);
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_insert_task(p_block_id text, p_title text DEFAULT 'Новая задача'::text)
 RETURNS TABLE(block_id text, task_id text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_id text;
    v_order integer;
    v_title text;
BEGIN
    IF p_block_id IS NULL OR btrim(p_block_id) = '' THEN
        RAISE EXCEPTION 'block_required' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public."Blocks" b WHERE b.id = p_block_id) THEN
        RAISE EXCEPTION 'block_not_found' USING ERRCODE = 'P0002';
    END IF;

    v_title := COALESCE(NULLIF(btrim(p_title), ''), 'Новая задача');
    SELECT COALESCE(MAX(t.sort_order), -1) + 1
    INTO v_order
    FROM public.roadmap_tasks t
    WHERE t.block_id = p_block_id;

    v_id := to_char((extract(epoch FROM clock_timestamp()) * 1000)::bigint, 'FM999999999999999')
        || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 9);

    INSERT INTO public.roadmap_tasks (
        id, block_id, title, status, sort_order, effort, owner, description,
        start_date, end_date, link_url, link_note
    ) VALUES (
        v_id, p_block_id, v_title, 'todo', v_order, 0, '', '',
        NULL, NULL, '', ''
    );

    PERFORM public.roadmap_write_json_from_tables(p_block_id);
    block_id := p_block_id;
    task_id := v_id;
    RETURN NEXT;
END;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_list_blocks(p_project_id text, p_owners text[], p_extra_project_ids text[], p_owner_filter boolean)
 RETURNS TABLE(block jsonb)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT public.roadmap_block_payload(b.id) AS block
    FROM public.roadmap_visible_block_ids(p_project_id, p_owners, p_extra_project_ids, p_owner_filter) v
    JOIN public."Blocks" b ON b.id::text = v.block_id
    ORDER BY b."releaseDate" ASC NULLS LAST, b.id
$function$;

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

CREATE OR REPLACE FUNCTION public.roadmap_move_task(p_task_id text, p_to_block_id text, p_before_task_id text DEFAULT NULL::text)
 RETURNS TABLE(from_block_id text, to_block_id text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_from text;
BEGIN
    SELECT t.block_id INTO v_from
    FROM public.roadmap_tasks t
    WHERE t.id = p_task_id;

    IF v_from IS NULL THEN
        RAISE EXCEPTION 'task_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF p_to_block_id IS NULL OR btrim(p_to_block_id) = '' THEN
        RAISE EXCEPTION 'block_required' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public."Blocks" b WHERE b.id = p_to_block_id) THEN
        RAISE EXCEPTION 'block_not_found' USING ERRCODE = 'P0002';
    END IF;

    IF p_before_task_id IS NOT NULL AND btrim(p_before_task_id) <> '' THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.roadmap_tasks t
            WHERE t.id = p_before_task_id
              AND t.block_id = p_to_block_id
        ) THEN
            RAISE EXCEPTION 'before_task_not_in_block' USING ERRCODE = '22023';
        END IF;
    END IF;

    UPDATE public.roadmap_tasks
    SET
        block_id = p_to_block_id,
        sort_order = 1000000,
        updated_at = now()
    WHERE id = p_task_id;

    DELETE FROM public.roadmap_task_deps d
    WHERE d.task_id = p_task_id
      AND d.predecessor_id NOT IN (
          SELECT t.id FROM public.roadmap_tasks t WHERE t.block_id = p_to_block_id
      );

    DELETE FROM public.roadmap_task_deps d
    WHERE d.predecessor_id = p_task_id
      AND d.task_id NOT IN (
          SELECT t.id FROM public.roadmap_tasks t WHERE t.block_id = p_to_block_id
      );

    PERFORM public.roadmap_densify_task_order(v_from);
    PERFORM public.roadmap_reorder_tasks(
        p_to_block_id,
        (
            SELECT COALESCE(array_agg(x.id ORDER BY x.ord), ARRAY[p_task_id])
            FROM (
                SELECT t.id, t.sort_order AS ord
                FROM public.roadmap_tasks t
                WHERE t.block_id = p_to_block_id
                  AND t.id <> p_task_id
                  AND (
                      p_before_task_id IS NULL
                      OR btrim(p_before_task_id) = ''
                      OR t.sort_order < (
                          SELECT b.sort_order
                          FROM public.roadmap_tasks b
                          WHERE b.id = p_before_task_id
                      )
                  )
                UNION ALL
                SELECT p_task_id, 1000000
                UNION ALL
                SELECT t.id, t.sort_order + 2000000
                FROM public.roadmap_tasks t
                WHERE t.block_id = p_to_block_id
                  AND t.id <> p_task_id
                  AND p_before_task_id IS NOT NULL
                  AND btrim(p_before_task_id) <> ''
                  AND t.sort_order >= (
                      SELECT b.sort_order
                      FROM public.roadmap_tasks b
                      WHERE b.id = p_before_task_id
                  )
            ) x
        )
    );

    IF v_from IS DISTINCT FROM p_to_block_id THEN
        PERFORM public.roadmap_write_json_from_tables(v_from);
    END IF;

    from_block_id := v_from;
    to_block_id := p_to_block_id;
    RETURN NEXT;
END;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_normalize_stage_dates(p_start text, p_end text, p_changed text)
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

CREATE OR REPLACE FUNCTION public.roadmap_patch_task(p_task_id text, p_patch jsonb)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_block_id text;
    v_start date;
    v_end date;
    v_status text;
    v_effort numeric;
BEGIN
    SELECT t.block_id INTO v_block_id
    FROM public.roadmap_tasks t
    WHERE t.id = p_task_id;

    IF v_block_id IS NULL THEN
        RAISE EXCEPTION 'task_not_found' USING ERRCODE = 'P0002';
    END IF;

    IF p_patch IS NULL OR jsonb_typeof(p_patch) IS DISTINCT FROM 'object' THEN
        PERFORM public.roadmap_write_json_from_tables(v_block_id);
        RETURN v_block_id;
    END IF;

    IF p_patch ? 'startDate' THEN
        v_start := public.roadmap_try_date(p_patch ->> 'startDate');
    END IF;
    IF p_patch ? 'releaseDate' THEN
        v_end := public.roadmap_try_date(p_patch ->> 'releaseDate');
    END IF;
    IF p_patch ? 'startDate' AND p_patch ? 'releaseDate'
       AND v_start IS NOT NULL AND v_end IS NOT NULL AND v_start > v_end THEN
        v_end := v_start;
    END IF;

    IF p_patch ? 'status' THEN
        v_status := lower(btrim(COALESCE(p_patch ->> 'status', '')));
        IF v_status NOT IN ('todo', 'progress', 'done') THEN
            v_status := 'todo';
        END IF;
    END IF;

    IF p_patch ? 'effort' THEN
        v_effort := GREATEST(0, COALESCE(public.roadmap_try_numeric(p_patch ->> 'effort'), 0));
    END IF;

    UPDATE public.roadmap_tasks t
    SET
        title = CASE
            WHEN p_patch ? 'title' THEN COALESCE(NULLIF(btrim(p_patch ->> 'title'), ''), t.title, 'Новая задача')
            ELSE t.title
        END,
        status = COALESCE(v_status, t.status),
        effort = COALESCE(v_effort, t.effort),
        owner = CASE WHEN p_patch ? 'owner' THEN COALESCE(p_patch ->> 'owner', '') ELSE t.owner END,
        description = CASE WHEN p_patch ? 'description' THEN COALESCE(p_patch ->> 'description', '') ELSE t.description END,
        start_date = CASE WHEN p_patch ? 'startDate' THEN v_start ELSE t.start_date END,
        end_date = CASE WHEN p_patch ? 'releaseDate' THEN v_end ELSE t.end_date END,
        link_url = CASE WHEN p_patch ? 'linkUrl' THEN COALESCE(p_patch ->> 'linkUrl', '') ELSE t.link_url END,
        link_note = CASE WHEN p_patch ? 'linkNote' THEN COALESCE(p_patch ->> 'linkNote', '') ELSE t.link_note END,
        updated_at = now()
    WHERE t.id = p_task_id;

    PERFORM public.roadmap_write_json_from_tables(v_block_id);
    RETURN v_block_id;
END;
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

CREATE OR REPLACE FUNCTION public.roadmap_reorder_tasks(p_block_id text, p_ids text[])
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_missing integer;
    v_count integer;
BEGIN
    IF p_block_id IS NULL OR btrim(p_block_id) = '' THEN
        RAISE EXCEPTION 'block_required' USING ERRCODE = '22023';
    END IF;
    IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'ids_required' USING ERRCODE = '22023';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM public.roadmap_tasks
    WHERE block_id = p_block_id;

    SELECT COUNT(*) INTO v_missing
    FROM unnest(p_ids) AS x(id)
    WHERE NOT EXISTS (
        SELECT 1 FROM public.roadmap_tasks t
        WHERE t.id = x.id AND t.block_id = p_block_id
    );

    IF v_missing > 0 THEN
        RAISE EXCEPTION 'task_not_in_block' USING ERRCODE = '22023';
    END IF;

    UPDATE public.roadmap_tasks t
    SET sort_order = -1000000 - x.ord
    FROM unnest(p_ids) WITH ORDINALITY AS x(id, ord)
    WHERE t.id = x.id
      AND t.block_id = p_block_id;

    UPDATE public.roadmap_tasks t
    SET sort_order = x.ord - 1
    FROM unnest(p_ids) WITH ORDINALITY AS x(id, ord)
    WHERE t.id = x.id
      AND t.block_id = p_block_id;

    IF v_count > COALESCE(array_length(p_ids, 1), 0) THEN
        PERFORM public.roadmap_densify_task_order(p_block_id);
    END IF;

    PERFORM public.roadmap_write_json_from_tables(p_block_id);
    RETURN p_block_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_replace_block_tasks(p_block_id text, p_tasks jsonb)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_tasks jsonb;
BEGIN
    IF p_block_id IS NULL OR btrim(p_block_id) = '' THEN
        RETURN;
    END IF;

    v_tasks := p_tasks;
    IF v_tasks IS NULL OR jsonb_typeof(v_tasks) IS DISTINCT FROM 'array' THEN
        RAISE NOTICE 'roadmap_replace_block_tasks: skip invalid JSON for %', p_block_id;
        RETURN;
    END IF;

    DROP TABLE IF EXISTS tmp_roadmap_sync_src;
    DROP TABLE IF EXISTS tmp_roadmap_sync_deps;
    CREATE TEMP TABLE tmp_roadmap_sync_src AS
    WITH elems AS (
        SELECT e.elem, e.elem_idx
        FROM jsonb_array_elements(v_tasks) WITH ORDINALITY AS e(elem, elem_idx)
        WHERE jsonb_typeof(e.elem) = 'object'
    ),
    raw_ids AS (
        SELECT
            elem,
            elem_idx,
            NULLIF(btrim(COALESCE(elem ->> 'id', '')), '') AS raw_id
        FROM elems
    ),
    filled AS (
        SELECT
            elem,
            elem_idx,
            raw_id,
            COALESCE(raw_id, 'task-mig-' || p_block_id || '-' || elem_idx::text) AS filled_id
        FROM raw_ids
    ),
    block_unique AS (
        SELECT
            elem,
            elem_idx,
            raw_id,
            filled_id,
            CASE
                WHEN ROW_NUMBER() OVER (PARTITION BY filled_id ORDER BY elem_idx) > 1
                THEN filled_id || '-dup-' || elem_idx::text
                ELSE filled_id
            END AS block_unique_id
        FROM filled
    ),
    against_existing AS (
        SELECT
            bu.*,
            CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM public.roadmap_tasks t
                    WHERE t.id = bu.block_unique_id
                      AND t.block_id IS DISTINCT FROM p_block_id
                )
                THEN bu.block_unique_id || '-' || p_block_id
                ELSE bu.block_unique_id
            END AS global_try_id
        FROM block_unique bu
    ),
    final_ids AS (
        SELECT
            ae.*,
            CASE
                WHEN ROW_NUMBER() OVER (PARTITION BY global_try_id ORDER BY elem_idx) > 1
                THEN global_try_id || '-g' || elem_idx::text
                ELSE global_try_id
            END AS task_id
        FROM against_existing ae
    ),
    dated AS (
        SELECT
            final_ids.*,
            public.roadmap_try_date(elem ->> 'startDate') AS start_date_raw,
            public.roadmap_try_date(elem ->> 'releaseDate') AS end_date_raw,
            COALESCE(trunc(public.roadmap_try_numeric(elem ->> 'order')), elem_idx)::integer AS raw_order
        FROM final_ids
    )
    SELECT
        task_id,
        elem,
        elem_idx,
        raw_id,
        filled_id,
        block_unique_id,
        COALESCE(elem ->> 'title', '') AS title,
        CASE lower(btrim(COALESCE(elem ->> 'status', '')))
            WHEN 'todo' THEN 'todo'
            WHEN 'progress' THEN 'progress'
            WHEN 'done' THEN 'done'
            ELSE 'todo'
        END AS status,
        (ROW_NUMBER() OVER (ORDER BY raw_order, elem_idx) - 1)::integer AS sort_order,
        GREATEST(0, COALESCE(public.roadmap_try_numeric(elem ->> 'effort'), 0)) AS effort,
        COALESCE(elem ->> 'owner', '') AS owner,
        COALESCE(elem ->> 'description', '') AS description,
        start_date_raw AS start_date,
        CASE
            WHEN start_date_raw IS NOT NULL AND end_date_raw IS NOT NULL AND start_date_raw > end_date_raw
            THEN start_date_raw
            ELSE end_date_raw
        END AS end_date,
        btrim(COALESCE(
            NULLIF(btrim(COALESCE(elem ->> 'linkUrl', '')), ''),
            NULLIF(btrim(COALESCE(elem ->> 'link', '')), ''),
            NULLIF(btrim(COALESCE(elem ->> 'url', '')), ''),
            ''
        )) AS link_url,
        COALESCE(elem ->> 'linkNote', '') AS link_note
    FROM dated;

    CREATE TEMP TABLE tmp_roadmap_sync_deps AS
    SELECT DISTINCT
        r.task_id,
        m.task_id AS predecessor_id,
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
            FROM tmp_roadmap_sync_src s
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
            FROM tmp_roadmap_sync_src s
        ) c
        CROSS JOIN LATERAL jsonb_array_elements(c.ids_json) AS id_el
        WHERE c.links_json IS NULL
          AND c.ids_json IS NOT NULL
    ) r
    JOIN (
        SELECT DISTINCT ON (alias_id)
            alias_id,
            task_id
        FROM (
            SELECT raw_id AS alias_id, task_id, elem_idx FROM tmp_roadmap_sync_src WHERE raw_id IS NOT NULL
            UNION ALL
            SELECT filled_id, task_id, elem_idx FROM tmp_roadmap_sync_src
            UNION ALL
            SELECT block_unique_id, task_id, elem_idx FROM tmp_roadmap_sync_src
            UNION ALL
            SELECT task_id, task_id, elem_idx FROM tmp_roadmap_sync_src
        ) aliases
        WHERE alias_id IS NOT NULL AND alias_id <> ''
        ORDER BY alias_id, elem_idx
    ) m ON m.alias_id = r.pred_alias
    WHERE r.pred_alias IS NOT NULL
      AND m.task_id <> r.task_id;

    IF EXISTS (
        WITH RECURSIVE walk AS (
            SELECT d.task_id AS node, ARRAY[d.predecessor_id] AS seen
            FROM tmp_roadmap_sync_deps d
            UNION ALL
            SELECT e.task_id, w.seen || w.node
            FROM walk w
            JOIN tmp_roadmap_sync_deps e ON e.predecessor_id = w.node
            WHERE NOT w.node = ANY (w.seen)
        )
        SELECT 1 FROM walk WHERE node = ANY (seen)
    ) THEN
        RAISE EXCEPTION 'task_dep_cycle' USING ERRCODE = '22023';
    END IF;

    DELETE FROM public.roadmap_tasks WHERE block_id = p_block_id;

    INSERT INTO public.roadmap_tasks (
        id, block_id, title, status, sort_order, effort, owner, description,
        start_date, end_date, link_url, link_note
    )
    SELECT
        task_id, p_block_id, title, status, sort_order, effort, owner, description,
        start_date, end_date, link_url, link_note
    FROM tmp_roadmap_sync_src;

    INSERT INTO public.roadmap_task_deps (task_id, predecessor_id, dep_type, lag_days)
    SELECT task_id, predecessor_id, dep_type, lag_days
    FROM tmp_roadmap_sync_deps;

    DROP TABLE IF EXISTS tmp_roadmap_sync_deps;
    DROP TABLE IF EXISTS tmp_roadmap_sync_src;
END;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_replace_stage_deps(p_block_id text, p_deps jsonb)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_project text;
    v_pred text;
    v_has_cycle boolean;
BEGIN
    IF p_block_id IS NULL OR btrim(p_block_id) = '' THEN
        RAISE EXCEPTION 'block_required' USING ERRCODE = '22023';
    END IF;
    SELECT b."projectId" INTO v_project
    FROM public."Blocks" b
    WHERE b.id = p_block_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'block_not_found' USING ERRCODE = 'P0002';
    END IF;

    IF p_deps IS NULL OR jsonb_typeof(p_deps) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'deps_array_required' USING ERRCODE = '22023';
    END IF;

    DROP TABLE IF EXISTS tmp_roadmap_stage_deps_src;
    CREATE TEMP TABLE tmp_roadmap_stage_deps_src AS
    SELECT DISTINCT ON (pred_id)
        pred_id,
        dep_type,
        lag_days,
        label_text,
        label_kind,
        label_date
    FROM (
        SELECT
            NULLIF(btrim(COALESCE(elem ->> 'predecessorId', elem ->> 'predId', '')), '') AS pred_id,
            CASE upper(btrim(COALESCE(elem ->> 'depType', elem ->> 'type', 'FS')))
                WHEN 'SS' THEN 'SS'
                WHEN 'FF' THEN 'FF'
                WHEN 'SF' THEN 'SF'
                ELSE 'FS'
            END AS dep_type,
            COALESCE(trunc(public.roadmap_try_numeric(elem ->> 'lagDays')), 0)::integer AS lag_days,
            COALESCE(elem ->> 'labelText', elem ->> 'text', '') AS label_text,
            CASE lower(btrim(COALESCE(elem ->> 'labelKind', elem ->> 'kind', 'comment')))
                WHEN 'checkpoint' THEN 'checkpoint'
                WHEN 'date' THEN 'date'
                ELSE 'comment'
            END AS label_kind,
            public.roadmap_try_date(COALESCE(elem ->> 'labelDate', elem ->> 'dateStr')) AS label_date
        FROM jsonb_array_elements(p_deps) AS elem
        WHERE jsonb_typeof(elem) = 'object'
    ) x
    WHERE pred_id IS NOT NULL
    ORDER BY pred_id;

    IF EXISTS (SELECT 1 FROM tmp_roadmap_stage_deps_src s WHERE s.pred_id = p_block_id) THEN
        RAISE EXCEPTION 'stage_dep_self' USING ERRCODE = '22023';
    END IF;

    FOR v_pred IN SELECT s.pred_id FROM tmp_roadmap_stage_deps_src s
    LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM public."Blocks" b
            WHERE b.id = v_pred
              AND b."projectId" IS NOT DISTINCT FROM v_project
        ) THEN
            RAISE EXCEPTION 'stage_dep_pred_not_found' USING ERRCODE = 'P0002';
        END IF;
    END LOOP;

    WITH RECURSIVE candidate AS (
        SELECT d.predecessor_block_id, d.block_id
        FROM public.roadmap_stage_deps d
        WHERE d.block_id IS DISTINCT FROM p_block_id
        UNION ALL
        SELECT s.pred_id, p_block_id
        FROM tmp_roadmap_stage_deps_src s
    ),
    walk AS (
        SELECT c.block_id AS node, ARRAY[p_block_id, c.block_id] AS path
        FROM candidate c
        WHERE c.predecessor_block_id = p_block_id
        UNION ALL
        SELECT c.block_id, w.path || c.block_id
        FROM walk w
        JOIN candidate c ON c.predecessor_block_id = w.node
        WHERE NOT c.block_id = ANY (w.path)
    )
    SELECT EXISTS (
        SELECT 1
        FROM walk w
        JOIN tmp_roadmap_stage_deps_src s ON s.pred_id = w.node
    )
    INTO v_has_cycle;

    IF v_has_cycle THEN
        RAISE EXCEPTION 'stage_dep_cycle' USING ERRCODE = '22023';
    END IF;

    DELETE FROM public.roadmap_stage_deps WHERE block_id = p_block_id;

    INSERT INTO public.roadmap_stage_deps (
        block_id, predecessor_block_id, dep_type, lag_days, label_text, label_kind, label_date
    )
    SELECT
        p_block_id, s.pred_id, s.dep_type, s.lag_days, s.label_text, s.label_kind, s.label_date
    FROM tmp_roadmap_stage_deps_src s;

    DROP TABLE IF EXISTS tmp_roadmap_stage_deps_src;
END;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_scope_stats(p_project_id text, p_owners text[], p_extra_project_ids text[], p_owner_filter boolean)
 RETURNS TABLE(completed_releases_count integer, in_progress_releases_count integer, total_tasks_count integer, completed_tasks_count integer, overall_progress integer, total_effort numeric, completed_effort numeric, completed_effort_percent integer)
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

CREATE OR REPLACE FUNCTION public.roadmap_set_block_dates(p_block_id text, p_start text, p_end text, p_changed text)
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

CREATE OR REPLACE FUNCTION public.roadmap_set_stage_dep_label(p_block_id text, p_predecessor_id text, p_label jsonb)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_text text;
    v_kind text;
    v_date date;
    v_updated integer;
BEGIN
    IF p_block_id IS NULL OR btrim(p_block_id) = '' OR p_predecessor_id IS NULL OR btrim(p_predecessor_id) = '' THEN
        RAISE EXCEPTION 'stage_dep_required' USING ERRCODE = '22023';
    END IF;

    v_text := COALESCE(p_label ->> 'labelText', p_label ->> 'text', '');
    v_kind := lower(btrim(COALESCE(p_label ->> 'labelKind', p_label ->> 'kind', 'comment')));
    IF v_kind NOT IN ('comment', 'checkpoint', 'date') THEN
        v_kind := 'comment';
    END IF;
    v_date := public.roadmap_try_date(COALESCE(p_label ->> 'labelDate', p_label ->> 'dateStr'));

    UPDATE public.roadmap_stage_deps
    SET
        label_text = v_text,
        label_kind = v_kind,
        label_date = v_date
    WHERE block_id = p_block_id
      AND predecessor_block_id = p_predecessor_id;

    GET DIAGNOSTICS v_updated = ROW_COUNT;
    IF v_updated = 0 THEN
        RAISE EXCEPTION 'stage_dep_not_found' USING ERRCODE = 'P0002';
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_sync_block_from_json(p_block_id text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- JSON больше не источник правды.
    RETURN;
END;
$function$;

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

CREATE OR REPLACE FUNCTION public.roadmap_task_file_add(p_block_id text, p_task_id text, p_file_name text, p_mime text, p_content bytea)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_id text;
    v_name text;
    v_mime text;
    v_size integer;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.roadmap_tasks t
        WHERE t.id = p_task_id AND t.block_id = p_block_id
    ) THEN
        RAISE EXCEPTION 'task_not_found' USING ERRCODE = 'P0002';
    END IF;

    v_name := left(btrim(COALESCE(p_file_name, '')), 180);
    IF v_name = '' THEN
        v_name := 'file';
    END IF;
    v_mime := left(btrim(COALESCE(NULLIF(p_mime, ''), 'application/octet-stream')), 120);
    v_size := COALESCE(octet_length(p_content), 0);
    IF v_size <= 0 THEN
        RAISE EXCEPTION 'file_empty' USING ERRCODE = '22023';
    END IF;
    IF v_size > 52428800 THEN
        RAISE EXCEPTION 'file_too_large' USING ERRCODE = '22023';
    END IF;

    v_id := 'file-' || substr(md5(random()::text || clock_timestamp()::text || v_name), 1, 24);

    INSERT INTO public.roadmap_task_files (id, task_id, file_name, mime, byte_size, content)
    VALUES (v_id, p_task_id, v_name, v_mime, v_size, p_content);

    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_task_file_delete(p_block_id text, p_task_id text, p_file_id text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_id text;
BEGIN
    DELETE FROM public.roadmap_task_files f
    USING public.roadmap_tasks t
    WHERE f.id = p_file_id
      AND f.task_id = p_task_id
      AND t.id = f.task_id
      AND t.block_id = p_block_id
    RETURNING f.id INTO v_id;

    IF v_id IS NULL THEN
        RAISE EXCEPTION 'file_not_found' USING ERRCODE = 'P0002';
    END IF;

    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_task_file_get(p_block_id text, p_task_id text, p_file_id text)
 RETURNS TABLE(file_name text, mime text, content bytea)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN QUERY
    SELECT f.file_name, f.mime, f.content
    FROM public.roadmap_task_files f
    JOIN public.roadmap_tasks t ON t.id = f.task_id
    WHERE f.id = p_file_id
      AND f.task_id = p_task_id
      AND t.block_id = p_block_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'file_not_found' USING ERRCODE = 'P0002';
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_task_file_list(p_block_id text, p_task_id text)
 RETURNS TABLE(id text, file_name text, mime text, byte_size integer, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.roadmap_tasks t
        WHERE t.id = p_task_id AND t.block_id = p_block_id
    ) THEN
        RAISE EXCEPTION 'task_not_found' USING ERRCODE = 'P0002';
    END IF;

    RETURN QUERY
    SELECT f.id, f.file_name, f.mime, f.byte_size, f.created_at
    FROM public.roadmap_task_files f
    WHERE f.task_id = p_task_id
    ORDER BY f.created_at, f.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_tasks_as_json(p_block_ids text[])
 RETURNS TABLE(block_id text, tasks jsonb)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT
        t.block_id,
        COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'id', t.id,
                    'title', t.title,
                    'status', t.status,
                    'order', t.sort_order,
                    'effort', t.effort,
                    'owner', t.owner,
                    'description', t.description,
                    'startDate', COALESCE(to_char(t.start_date, 'YYYY-MM-DD'), ''),
                    'releaseDate', COALESCE(to_char(t.end_date, 'YYYY-MM-DD'), ''),
                    'linkUrl', t.link_url,
                    'linkNote', t.link_note,
                    'predecessorIds', COALESCE(d.pred_ids, '[]'::jsonb),
                    'predecessorLinks', COALESCE(d.links, '[]'::jsonb)
                )
                ORDER BY t.sort_order
            ),
            '[]'::jsonb
        ) AS tasks
    FROM public.roadmap_tasks t
    LEFT JOIN LATERAL (
        SELECT
            COALESCE(
                jsonb_agg(
                    jsonb_build_object(
                        'predId', dep.predecessor_id,
                        'type', dep.dep_type,
                        'lagDays', dep.lag_days
                    )
                    ORDER BY dep.predecessor_id, dep.dep_type, dep.lag_days
                ),
                '[]'::jsonb
            ) AS links,
            COALESCE(
                jsonb_agg(to_jsonb(dep.predecessor_id) ORDER BY dep.predecessor_id, dep.dep_type, dep.lag_days),
                '[]'::jsonb
            ) AS pred_ids
        FROM public.roadmap_task_deps dep
        WHERE dep.task_id = t.id
    ) d ON TRUE
    WHERE t.block_id = ANY(p_block_ids)
    GROUP BY t.block_id;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_try_date(p_text text)
 RETURNS date
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
    IF p_text IS NULL OR btrim(p_text) !~ '^\d{4}-\d{2}-\d{2}$' THEN
        RETURN NULL;
    END IF;
    RETURN btrim(p_text)::date;
EXCEPTION
    WHEN datetime_field_overflow OR invalid_datetime_format THEN
        RETURN NULL;
    WHEN OTHERS THEN
        RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_try_jsonb(p_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
    IF p_text IS NULL OR btrim(p_text) = '' THEN
        RETURN '[]'::jsonb;
    END IF;
    RETURN p_text::jsonb;
EXCEPTION
    WHEN invalid_text_representation OR numeric_value_out_of_range THEN
        RETURN NULL;
    WHEN OTHERS THEN
        RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.roadmap_try_numeric(p_text text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
    IF p_text IS NULL OR btrim(p_text) = '' THEN
        RETURN NULL;
    END IF;
    RETURN btrim(p_text)::numeric;
EXCEPTION
    WHEN invalid_text_representation OR numeric_value_out_of_range THEN
        RETURN NULL;
    WHEN OTHERS THEN
        RETURN NULL;
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

CREATE OR REPLACE FUNCTION public.roadmap_visible_block_ids(p_project_id text, p_owners text[], p_extra_project_ids text[], p_owner_filter boolean)
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

CREATE OR REPLACE FUNCTION public.roadmap_write_json_from_tables(p_block_id text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Таблицы — источник правды. Колонку "Blocks".tasks больше не обновляем.
    RETURN;
END;
$function$;

