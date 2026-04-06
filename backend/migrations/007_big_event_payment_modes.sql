BEGIN;

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS payment_mode TEXT DEFAULT 'manual_qr',
  ADD COLUMN IF NOT EXISTS manual_promptpay_qr_url TEXT,
  ADD COLUMN IF NOT EXISTS manual_alipay_qr_url TEXT,
  ADD COLUMN IF NOT EXISTS enable_promptpay BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS enable_alipay BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS stripe_enabled BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE public.events
SET
  payment_mode = COALESCE(payment_mode, 'manual_qr'),
  enable_promptpay = COALESCE(enable_promptpay, promptpay_enabled, TRUE),
  enable_alipay = COALESCE(enable_alipay, alipay_enabled, FALSE),
  manual_promptpay_qr_url = COALESCE(manual_promptpay_qr_url, qr_url),
  manual_alipay_qr_url = COALESCE(manual_alipay_qr_url, alipay_qr_url)
WHERE type = 'BIG_EVENT';

ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS provider TEXT,
  ADD COLUMN IF NOT EXISTS payment_method_type TEXT,
  ADD COLUMN IF NOT EXISTS provider_payment_intent_id TEXT,
  ADD COLUMN IF NOT EXISTS provider_charge_id TEXT,
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS raw_gateway_payload JSONB;

UPDATE public.payments
SET payment_method_type = LOWER(COALESCE(payment_method_type, method::text))
WHERE payment_method_type IS NULL
  AND method IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_provider_payment_intent_id_unique
  ON public.payments (provider_payment_intent_id)
  WHERE provider_payment_intent_id IS NOT NULL;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'participants'
  ) THEN
    CREATE UNIQUE INDEX IF NOT EXISTS idx_participants_event_user_unique
      ON public.participants (event_id, user_id);
  END IF;
END
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'receipts'
  ) THEN
    CREATE UNIQUE INDEX IF NOT EXISTS idx_receipts_receipt_no_unique
      ON public.receipts (receipt_no);
  END IF;
END
$$;

COMMIT;
