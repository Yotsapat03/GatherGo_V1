BEGIN;

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS alipay_qr_url TEXT,
  ADD COLUMN IF NOT EXISTS promptpay_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS alipay_enabled BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS user_id BIGINT,
  ADD COLUMN IF NOT EXISTS event_id BIGINT,
  ADD COLUMN IF NOT EXISTS method_type TEXT,
  ADD COLUMN IF NOT EXISTS currency TEXT,
  ADD COLUMN IF NOT EXISTS stripe_checkout_session_id TEXT,
  ADD COLUMN IF NOT EXISTS stripe_payment_intent_id TEXT,
  ADD COLUMN IF NOT EXISTS stripe_charge_id TEXT,
  ADD COLUMN IF NOT EXISTS receipt_url TEXT,
  ADD COLUMN IF NOT EXISTS external_reference TEXT,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

UPDATE public.payments p
SET
  user_id = b.user_id,
  event_id = b.event_id,
  currency = COALESCE(p.currency, b.currency, 'THB')
FROM public.bookings b
WHERE p.booking_id = b.id
  AND (p.user_id IS NULL OR p.event_id IS NULL OR p.currency IS NULL);

CREATE TABLE IF NOT EXISTS public.event_payment_methods (
  id BIGSERIAL PRIMARY KEY,
  event_id BIGINT NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  method_type TEXT NOT NULL,
  provider TEXT NOT NULL,
  qr_image_url TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (event_id, method_type)
);

CREATE INDEX IF NOT EXISTS idx_event_payment_methods_event_active
  ON public.event_payment_methods (event_id, is_active);

CREATE TABLE IF NOT EXISTS public.stripe_webhook_events (
  id BIGSERIAL PRIMARY KEY,
  stripe_event_id TEXT NOT NULL UNIQUE,
  event_type TEXT NOT NULL,
  payload_json JSONB NOT NULL,
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMIT;
