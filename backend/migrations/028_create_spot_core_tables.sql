CREATE TABLE IF NOT EXISTS public.spot_events (
  id BIGSERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  location TEXT NOT NULL DEFAULT '',
  location_link TEXT,
  province TEXT,
  district TEXT,
  event_date TEXT NOT NULL DEFAULT '',
  event_time TEXT NOT NULL DEFAULT '',
  km_per_round NUMERIC(12, 3) NOT NULL DEFAULT 0,
  round_count INTEGER NOT NULL DEFAULT 0,
  max_people INTEGER NOT NULL DEFAULT 0,
  image_base64 TEXT,
  image_url TEXT,
  location_lat DOUBLE PRECISION,
  location_lng DOUBLE PRECISION,
  status TEXT NOT NULL DEFAULT 'completed',
  created_by_user_id BIGINT REFERENCES public.users(id) ON DELETE SET NULL,
  creator_role TEXT NOT NULL DEFAULT 'user',
  owner_completed_at TIMESTAMPTZ,
  owner_completed_distance_km NUMERIC(12, 3),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_spot_events_created_at
  ON public.spot_events (created_at DESC);

CREATE TABLE IF NOT EXISTS public.spot_event_media (
  id BIGSERIAL PRIMARY KEY,
  spot_event_id BIGINT NOT NULL REFERENCES public.spot_events(id) ON DELETE CASCADE,
  kind TEXT NOT NULL DEFAULT 'gallery',
  file_url TEXT NOT NULL,
  alt_text TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_spot_event_media_spot_id
  ON public.spot_event_media (spot_event_id, kind, sort_order, id);

CREATE TABLE IF NOT EXISTS public.spot_event_members (
  id BIGSERIAL PRIMARY KEY,
  spot_event_id BIGINT NOT NULL REFERENCES public.spot_events(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  completed_distance_km NUMERIC(12, 3),
  UNIQUE (spot_event_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_spot_event_members_user_id
  ON public.spot_event_members (user_id, joined_at DESC);

CREATE TABLE IF NOT EXISTS public.spot_event_bookings (
  id BIGSERIAL PRIMARY KEY,
  spot_event_id BIGINT NOT NULL REFERENCES public.spot_events(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  booking_reference TEXT,
  status TEXT NOT NULL DEFAULT 'booked',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  completed_distance_km NUMERIC(12, 3),
  UNIQUE (spot_event_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_spot_event_bookings_completed_at
  ON public.spot_event_bookings (user_id, completed_at DESC);
