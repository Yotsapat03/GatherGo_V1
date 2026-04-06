-- Business truth: when an activity is explicitly completed, its recorded
-- completed distance must equal the activity's full configured distance.

UPDATE public.bookings b
SET
  completed_distance_km = COALESCE(e.total_distance, 0),
  updated_at = NOW()
FROM public.events e
WHERE e.id = b.event_id
  AND UPPER(COALESCE(e.type::text, '')) = 'BIG_EVENT'
  AND b.completed_at IS NOT NULL
  AND COALESCE(b.completed_distance_km, -1) IS DISTINCT FROM COALESCE(e.total_distance, 0);

UPDATE public.spot_event_members sem
SET
  completed_distance_km = COALESCE(se.km_per_round, 0) * COALESCE(se.round_count, 0),
  updated_at = NOW()
FROM public.spot_events se
WHERE se.id = sem.spot_event_id
  AND sem.completed_at IS NOT NULL
  AND COALESCE(sem.completed_distance_km, -1) IS DISTINCT FROM (
    COALESCE(se.km_per_round, 0) * COALESCE(se.round_count, 0)
  );

UPDATE public.spot_event_bookings seb
SET
  completed_distance_km = COALESCE(se.km_per_round, 0) * COALESCE(se.round_count, 0),
  updated_at = NOW()
FROM public.spot_events se
WHERE se.id = seb.spot_event_id
  AND seb.completed_at IS NOT NULL
  AND COALESCE(seb.completed_distance_km, -1) IS DISTINCT FROM (
    COALESCE(se.km_per_round, 0) * COALESCE(se.round_count, 0)
  );

UPDATE public.spot_events se
SET
  owner_completed_distance_km = COALESCE(se.km_per_round, 0) * COALESCE(se.round_count, 0),
  updated_at = NOW()
WHERE se.creator_role = 'user'
  AND se.owner_completed_at IS NOT NULL
  AND COALESCE(se.owner_completed_distance_km, -1) IS DISTINCT FROM (
    COALESCE(se.km_per_round, 0) * COALESCE(se.round_count, 0)
  );
