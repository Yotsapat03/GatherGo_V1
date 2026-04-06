-- Revert false owner-completion rows introduced by status-based backfill.
-- Business truth for owner completion must come from explicit owner completion,
-- not from spot_events.status.
UPDATE public.spot_events se
SET
  owner_completed_at = NULL,
  owner_completed_distance_km = NULL
WHERE se.creator_role = 'user'
  AND se.owner_completed_at IS NOT NULL
  AND se.created_at IS NOT NULL
  AND se.updated_at IS NOT NULL
  AND se.owner_completed_at = COALESCE(se.updated_at, se.created_at)
  AND se.owner_completed_at = se.created_at
  AND COALESCE(se.owner_completed_distance_km, -1) = (
    COALESCE(se.km_per_round, 0) * COALESCE(se.round_count, 0)
  )
  AND NOT EXISTS (
    SELECT 1
    FROM public.spot_event_members sem
    WHERE sem.spot_event_id = se.id
      AND sem.completed_at IS NOT NULL
  )
  AND NOT EXISTS (
    SELECT 1
    FROM public.spot_event_bookings seb
    WHERE seb.spot_event_id = se.id
      AND seb.completed_at IS NOT NULL
  );
