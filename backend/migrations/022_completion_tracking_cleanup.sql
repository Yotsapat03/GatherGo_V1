-- Normalize explicit completion fields from legacy status-only rows.
UPDATE public.bookings b
SET
  completed_at = COALESCE(b.completed_at, b.updated_at, b.created_at, NOW()),
  completed_distance_km = COALESCE(b.completed_distance_km, e.total_distance, 0)
FROM public.events e
WHERE e.id = b.event_id
  AND LOWER(COALESCE(b.status::text, '')) = 'completed'
  AND b.completed_at IS NULL;

UPDATE public.spot_event_members sem
SET
  completed_at = COALESCE(sem.completed_at, sem.joined_at, NOW()),
  completed_distance_km = COALESCE(
    sem.completed_distance_km,
    COALESCE(se.km_per_round, 0) * COALESCE(se.round_count, 0)
  )
FROM public.spot_events se
WHERE se.id = sem.spot_event_id
  AND sem.completed_at IS NULL
  AND EXISTS (
    SELECT 1
    FROM public.spot_event_bookings seb
    WHERE seb.spot_event_id = sem.spot_event_id
      AND seb.user_id = sem.user_id
      AND LOWER(COALESCE(seb.status::text, '')) = 'completed'
  );

-- Do not backfill spot owner completion from spot_events.status.
-- In this schema status is not a reliable signal of explicit owner completion.

-- Remove creator self-joins so one activity cannot count as both created and joined.
DELETE FROM public.spot_event_members sem
USING public.spot_events se
WHERE se.id = sem.spot_event_id
  AND se.creator_role = 'user'
  AND se.created_by_user_id = sem.user_id;

DELETE FROM public.spot_event_bookings seb
USING public.spot_events se
WHERE se.id = seb.spot_event_id
  AND se.creator_role = 'user'
  AND se.created_by_user_id = seb.user_id;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'bookings_completed_distance_km_non_negative'
  ) THEN
    ALTER TABLE public.bookings
      ADD CONSTRAINT bookings_completed_distance_km_non_negative
      CHECK (completed_distance_km IS NULL OR completed_distance_km >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'spot_event_members_completed_distance_km_non_negative'
  ) THEN
    ALTER TABLE public.spot_event_members
      ADD CONSTRAINT spot_event_members_completed_distance_km_non_negative
      CHECK (completed_distance_km IS NULL OR completed_distance_km >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'spot_events_owner_completed_distance_km_non_negative'
  ) THEN
    ALTER TABLE public.spot_events
      ADD CONSTRAINT spot_events_owner_completed_distance_km_non_negative
      CHECK (owner_completed_distance_km IS NULL OR owner_completed_distance_km >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'spot_event_bookings_completed_distance_km_non_negative'
  ) THEN
    ALTER TABLE public.spot_event_bookings
      ADD CONSTRAINT spot_event_bookings_completed_distance_km_non_negative
      CHECK (completed_distance_km IS NULL OR completed_distance_km >= 0);
  END IF;
END
$$;
