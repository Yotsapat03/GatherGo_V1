-- Verify activity-completion schema and saved data.
-- Run this after applying migrations and restarting the backend.

-- 1) Check required completion columns exist.
SELECT
  table_schema,
  table_name,
  column_name,
  data_type
FROM information_schema.columns
WHERE (table_schema, table_name, column_name) IN (
  ('public', 'spot_events', 'owner_completed_at'),
  ('public', 'spot_events', 'owner_completed_distance_km'),
  ('public', 'spot_event_members', 'completed_at'),
  ('public', 'spot_event_members', 'completed_distance_km'),
  ('public', 'spot_event_bookings', 'completed_at'),
  ('public', 'spot_event_bookings', 'completed_distance_km'),
  ('public', 'bookings', 'completed_at'),
  ('public', 'bookings', 'completed_distance_km')
)
ORDER BY table_name, column_name;

-- 2) Check completion indexes exist.
SELECT
  schemaname,
  tablename,
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN (
    'idx_spot_event_members_completed_at',
    'idx_spot_events_owner_completed_at',
    'idx_bookings_completed_at',
    'idx_spot_event_bookings_completed_at'
  )
ORDER BY tablename, indexname;

-- 3) Spot Created completions saved on spot_events.
SELECT
  se.id AS spot_id,
  COALESCE(NULLIF(TRIM(se.display_code), ''), CONCAT('SP', LPAD(se.id::text, 6, '0'))) AS spot_code,
  se.title,
  se.created_by_user_id AS owner_user_id,
  se.owner_completed_at,
  se.owner_completed_distance_km,
  COALESCE(se.km_per_round, 0) AS km_per_round,
  COALESCE(se.round_count, 0) AS round_count,
  COALESCE(se.owner_completed_distance_km, COALESCE(se.km_per_round, 0) * COALESCE(se.round_count, 0)) AS effective_completed_km
FROM public.spot_events se
WHERE se.owner_completed_at IS NOT NULL
ORDER BY se.owner_completed_at DESC, se.id DESC;

-- 4) Spot Joined completions saved per user.
SELECT
  sem.user_id,
  sem.spot_event_id AS spot_id,
  COALESCE(NULLIF(TRIM(se.display_code), ''), CONCAT('SP', LPAD(se.id::text, 6, '0'))) AS spot_code,
  se.title,
  sem.completed_at,
  sem.completed_distance_km,
  COALESCE(sem.completed_distance_km, COALESCE(se.km_per_round, 0) * COALESCE(se.round_count, 0)) AS effective_completed_km
FROM public.spot_event_members sem
JOIN public.spot_events se ON se.id = sem.spot_event_id
WHERE sem.completed_at IS NOT NULL
ORDER BY sem.completed_at DESC, sem.user_id, sem.spot_event_id;

-- 5) Spot booking-side completion mirror.
SELECT
  seb.user_id,
  seb.spot_event_id AS spot_id,
  seb.booking_reference,
  seb.status,
  seb.completed_at,
  seb.completed_distance_km
FROM public.spot_event_bookings seb
WHERE seb.completed_at IS NOT NULL
   OR LOWER(COALESCE(seb.status, '')) = 'completed'
ORDER BY COALESCE(seb.completed_at, seb.updated_at, seb.created_at) DESC, seb.id DESC;

-- 6) Big Event completions saved per booking.
SELECT
  b.id AS booking_id,
  b.user_id,
  b.event_id,
  e.title,
  b.status,
  b.completed_at,
  b.completed_distance_km,
  COALESCE(b.completed_distance_km, e.total_distance, 0) AS effective_completed_km
FROM public.bookings b
JOIN public.events e ON e.id = b.event_id
WHERE UPPER(COALESCE(e.type::text, '')) = 'BIG_EVENT'
  AND (
    b.completed_at IS NOT NULL
    OR LOWER(COALESCE(b.status::text, '')) = 'completed'
  )
ORDER BY COALESCE(b.completed_at, b.updated_at, b.created_at) DESC, b.id DESC;

-- 7) Per-user completion totals from DB only.
WITH created_spots AS (
  SELECT
    se.created_by_user_id AS user_id,
    COUNT(*)::int AS created_spot_completed_count,
    COALESCE(
      SUM(
        COALESCE(
          se.owner_completed_distance_km,
          COALESCE(se.km_per_round, 0) * COALESCE(se.round_count, 0)
        )
      ),
      0
    )::numeric AS created_spot_completed_km
  FROM public.spot_events se
  WHERE se.creator_role = 'user'
    AND se.owner_completed_at IS NOT NULL
  GROUP BY se.created_by_user_id
),
joined_spots AS (
  SELECT
    sem.user_id,
    COUNT(*)::int AS joined_spot_completed_count,
    COALESCE(
      SUM(
        COALESCE(
          sem.completed_distance_km,
          COALESCE(se.km_per_round, 0) * COALESCE(se.round_count, 0)
        )
      ),
      0
    )::numeric AS joined_spot_completed_km
  FROM public.spot_event_members sem
  JOIN public.spot_events se ON se.id = sem.spot_event_id
  WHERE sem.completed_at IS NOT NULL
  GROUP BY sem.user_id
),
joined_big_events AS (
  SELECT
    b.user_id,
    COUNT(*)::int AS joined_big_event_completed_count,
    COALESCE(
      SUM(COALESCE(b.completed_distance_km, e.total_distance, 0)),
      0
    )::numeric AS joined_big_event_completed_km
  FROM public.bookings b
  JOIN public.events e ON e.id = b.event_id
  WHERE UPPER(COALESCE(e.type::text, '')) = 'BIG_EVENT'
    AND (
      b.completed_at IS NOT NULL
      OR LOWER(COALESCE(b.status::text, '')) = 'completed'
    )
  GROUP BY b.user_id
)
SELECT
  u.id AS user_id,
  COALESCE(NULLIF(TRIM(u.name), ''), NULLIF(TRIM(CONCAT_WS(' ', u.first_name, u.last_name)), ''), u.email, CONCAT('User ', u.id::text)) AS user_name,
  COALESCE(cs.created_spot_completed_count, 0) AS created_spot_completed_count,
  COALESCE(js.joined_spot_completed_count, 0) AS joined_spot_completed_count,
  COALESCE(jbe.joined_big_event_completed_count, 0) AS joined_big_event_completed_count,
  (
    COALESCE(cs.created_spot_completed_count, 0)
    + COALESCE(js.joined_spot_completed_count, 0)
    + COALESCE(jbe.joined_big_event_completed_count, 0)
  ) AS total_completed_count,
  COALESCE(cs.created_spot_completed_km, 0) AS created_spot_completed_km,
  COALESCE(js.joined_spot_completed_km, 0) AS joined_spot_completed_km,
  COALESCE(jbe.joined_big_event_completed_km, 0) AS joined_big_event_completed_km,
  (
    COALESCE(cs.created_spot_completed_km, 0)
    + COALESCE(js.joined_spot_completed_km, 0)
    + COALESCE(jbe.joined_big_event_completed_km, 0)
  ) AS total_completed_km
FROM public.users u
LEFT JOIN created_spots cs ON cs.user_id = u.id
LEFT JOIN joined_spots js ON js.user_id = u.id
LEFT JOIN joined_big_events jbe ON jbe.user_id = u.id
WHERE
  COALESCE(cs.created_spot_completed_count, 0) > 0
  OR COALESCE(js.joined_spot_completed_count, 0) > 0
  OR COALESCE(jbe.joined_big_event_completed_count, 0) > 0
ORDER BY total_completed_km DESC, total_completed_count DESC, u.id DESC;

-- 8) Optional: filter a single user quickly.
-- Replace 123 with the user id you want to inspect.
SELECT
  u.id AS user_id,
  COALESCE(NULLIF(TRIM(u.name), ''), NULLIF(TRIM(CONCAT_WS(' ', u.first_name, u.last_name)), ''), u.email) AS user_name,
  se.id AS spot_id,
  se.title,
  se.owner_completed_at,
  se.owner_completed_distance_km
FROM public.users u
LEFT JOIN public.spot_events se
  ON se.created_by_user_id = u.id
 AND se.creator_role = 'user'
WHERE u.id = 123
ORDER BY se.owner_completed_at DESC NULLS LAST, se.id DESC;
