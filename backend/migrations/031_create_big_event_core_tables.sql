CREATE TABLE IF NOT EXISTS public.organizations (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.events (
  id BIGSERIAL PRIMARY KEY,
  type TEXT NOT NULL DEFAULT 'BIG_EVENT',
  created_by BIGINT,
  title TEXT,
  description TEXT,
  meeting_point TEXT,
  location_name TEXT,
  meeting_point_note TEXT,
  location_link TEXT,
  title_i18n JSONB,
  description_i18n JSONB,
  meeting_point_i18n JSONB,
  location_name_i18n JSONB,
  meeting_point_note_i18n JSONB,
  city TEXT,
  province TEXT,
  district TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  location_lat DOUBLE PRECISION,
  location_lng DOUBLE PRECISION,
  start_at TIMESTAMPTZ,
  end_at TIMESTAMPTZ,
  max_participants INTEGER,
  visibility TEXT DEFAULT 'public',
  status TEXT DEFAULT 'draft',
  organization_id BIGINT REFERENCES public.organizations(id) ON DELETE SET NULL,
  fee NUMERIC(12, 2) NOT NULL DEFAULT 0,
  currency TEXT DEFAULT 'THB',
  qr_url TEXT,
  qr_payment_method TEXT,
  payment_mode TEXT DEFAULT 'manual_qr',
  manual_promptpay_qr_url TEXT,
  manual_alipay_qr_url TEXT,
  alipay_qr_url TEXT,
  enable_promptpay BOOLEAN NOT NULL DEFAULT TRUE,
  enable_alipay BOOLEAN NOT NULL DEFAULT FALSE,
  stripe_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  promptpay_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  alipay_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  base_currency TEXT,
  base_amount NUMERIC(12, 2),
  exchange_rate_thb_per_cny NUMERIC(12, 6),
  promptpay_amount_thb NUMERIC(12, 2),
  alipay_amount_cny NUMERIC(12, 2),
  fx_locked_at TIMESTAMPTZ,
  distance_per_lap NUMERIC(12, 3),
  number_of_laps INTEGER,
  total_distance NUMERIC(12, 3),
  display_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_events_display_code_unique
  ON public.events (display_code)
  WHERE display_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_events_org_status_start
  ON public.events (organization_id, status, start_at DESC);

CREATE TABLE IF NOT EXISTS public.event_media (
  id BIGSERIAL PRIMARY KEY,
  event_id BIGINT NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  kind TEXT NOT NULL DEFAULT 'gallery',
  item_type TEXT,
  file_url TEXT NOT NULL,
  alt_text TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_event_media_event_kind_sort
  ON public.event_media (event_id, kind, sort_order, id);

CREATE TABLE IF NOT EXISTS public.bookings (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  event_id BIGINT NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  quantity INTEGER NOT NULL DEFAULT 1,
  total_amount NUMERIC(12, 2) NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'THB',
  status TEXT NOT NULL DEFAULT 'pending',
  shirt_size TEXT,
  booking_reference TEXT,
  completed_at TIMESTAMPTZ,
  completed_distance_km NUMERIC(12, 3),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_bookings_booking_reference_unique
  ON public.bookings (booking_reference)
  WHERE booking_reference IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bookings_user_event_created
  ON public.bookings (user_id, event_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.participants (
  id BIGSERIAL PRIMARY KEY,
  event_id BIGINT NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  booking_id BIGINT REFERENCES public.bookings(id) ON DELETE SET NULL,
  source TEXT DEFAULT 'booking',
  status TEXT DEFAULT 'joined',
  shirt_size TEXT,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (event_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_participants_booking_id
  ON public.participants (booking_id);

CREATE TABLE IF NOT EXISTS public.payments (
  id BIGSERIAL PRIMARY KEY,
  booking_id BIGINT REFERENCES public.bookings(id) ON DELETE SET NULL,
  event_id BIGINT REFERENCES public.events(id) ON DELETE SET NULL,
  method TEXT,
  method_type TEXT,
  payment_method_type TEXT,
  provider TEXT,
  provider_txn_id TEXT,
  provider_payment_intent_id TEXT,
  provider_charge_id TEXT,
  stripe_payment_intent_id TEXT,
  amount NUMERIC(12, 2) NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'THB',
  fx_rate_used NUMERIC(12, 6),
  raw_gateway_payload JSONB,
  status TEXT NOT NULL DEFAULT 'pending',
  failure_code TEXT,
  failure_reason TEXT,
  slip_url TEXT,
  paid_at TIMESTAMPTZ,
  payment_reference TEXT,
  receipt_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_payment_reference_unique
  ON public.payments (payment_reference)
  WHERE payment_reference IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_payments_booking_status_created
  ON public.payments (booking_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS public.receipts (
  id BIGSERIAL PRIMARY KEY,
  payment_id BIGINT NOT NULL REFERENCES public.payments(id) ON DELETE CASCADE,
  receipt_no TEXT NOT NULL,
  amount NUMERIC(12, 2) NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'THB',
  issue_date TIMESTAMPTZ,
  pdf_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (receipt_no)
);

CREATE INDEX IF NOT EXISTS idx_receipts_payment_id
  ON public.receipts (payment_id);
