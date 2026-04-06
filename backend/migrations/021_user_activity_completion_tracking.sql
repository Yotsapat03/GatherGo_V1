ALTER TABLE public.spot_event_members
ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

ALTER TABLE public.spot_event_members
ADD COLUMN IF NOT EXISTS completed_distance_km NUMERIC(12, 3);

ALTER TABLE public.spot_events
ADD COLUMN IF NOT EXISTS owner_completed_at TIMESTAMPTZ;

ALTER TABLE public.spot_events
ADD COLUMN IF NOT EXISTS owner_completed_distance_km NUMERIC(12, 3);

ALTER TABLE public.bookings
ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

ALTER TABLE public.bookings
ADD COLUMN IF NOT EXISTS completed_distance_km NUMERIC(12, 3);

ALTER TABLE public.spot_event_bookings
ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

ALTER TABLE public.spot_event_bookings
ADD COLUMN IF NOT EXISTS completed_distance_km NUMERIC(12, 3);

CREATE INDEX IF NOT EXISTS idx_spot_event_members_completed_at
ON public.spot_event_members (user_id, completed_at DESC);

CREATE INDEX IF NOT EXISTS idx_spot_events_owner_completed_at
ON public.spot_events (created_by_user_id, owner_completed_at DESC);

CREATE INDEX IF NOT EXISTS idx_bookings_completed_at
ON public.bookings (user_id, completed_at DESC);

CREATE INDEX IF NOT EXISTS idx_spot_event_bookings_completed_at
ON public.spot_event_bookings (user_id, completed_at DESC);
