BEGIN;

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS base_currency TEXT,
  ADD COLUMN IF NOT EXISTS base_amount NUMERIC(12, 2),
  ADD COLUMN IF NOT EXISTS exchange_rate_thb_per_cny NUMERIC(12, 6),
  ADD COLUMN IF NOT EXISTS promptpay_amount_thb NUMERIC(12, 2),
  ADD COLUMN IF NOT EXISTS alipay_amount_cny NUMERIC(12, 2),
  ADD COLUMN IF NOT EXISTS fx_locked_at TIMESTAMPTZ;

UPDATE public.events
SET
  base_currency = COALESCE(base_currency, currency, 'THB'),
  base_amount = COALESCE(base_amount, fee, 0),
  exchange_rate_thb_per_cny = COALESCE(exchange_rate_thb_per_cny, 1),
  promptpay_amount_thb = COALESCE(promptpay_amount_thb, fee, 0),
  promptpay_enabled = TRUE,
  enable_promptpay = TRUE,
  alipay_enabled = COALESCE(alipay_enabled, FALSE),
  enable_alipay = COALESCE(enable_alipay, alipay_enabled, FALSE)
WHERE UPPER(COALESCE(type::text, 'BIG_EVENT')) = 'BIG_EVENT';

ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS fx_rate_used NUMERIC(12, 6),
  ADD COLUMN IF NOT EXISTS provider_txn_id TEXT,
  ADD COLUMN IF NOT EXISTS currency TEXT;

UPDATE public.payments p
SET
  currency = COALESCE(p.currency, b.currency, e.currency, 'THB'),
  fx_rate_used = COALESCE(p.fx_rate_used, e.exchange_rate_thb_per_cny)
FROM public.bookings b
LEFT JOIN public.events e ON e.id = b.event_id
WHERE p.booking_id = b.id
  AND (p.currency IS NULL OR p.fx_rate_used IS NULL);

COMMIT;
