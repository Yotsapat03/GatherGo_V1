-- Add phishing scan / moderation fields to spot_chat_messages
-- for backend-driven Spot chat UI states.

ALTER TABLE public.spot_chat_messages
  ADD COLUMN IF NOT EXISTS contains_url BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS moderation_status VARCHAR(20) NOT NULL DEFAULT 'visible',
  ADD COLUMN IF NOT EXISTS risk_level VARCHAR(20) NOT NULL DEFAULT 'safe',
  ADD COLUMN IF NOT EXISTS phishing_scan_status VARCHAR(20) NOT NULL DEFAULT 'not_scanned',
  ADD COLUMN IF NOT EXISTS phishing_scan_reason TEXT,
  ADD COLUMN IF NOT EXISTS blocked_at TIMESTAMPTZ;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'spot_chat_messages_moderation_status_chk'
  ) THEN
    ALTER TABLE public.spot_chat_messages
      ADD CONSTRAINT spot_chat_messages_moderation_status_chk
      CHECK (moderation_status IN ('visible', 'warning', 'hidden', 'blocked'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'spot_chat_messages_risk_level_chk'
  ) THEN
    ALTER TABLE public.spot_chat_messages
      ADD CONSTRAINT spot_chat_messages_risk_level_chk
      CHECK (risk_level IN ('safe', 'suspicious', 'phishing'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'spot_chat_messages_phishing_scan_status_chk'
  ) THEN
    ALTER TABLE public.spot_chat_messages
      ADD CONSTRAINT spot_chat_messages_phishing_scan_status_chk
      CHECK (phishing_scan_status IN ('not_scanned', 'scanning', 'scanned', 'failed'));
  END IF;
END
$$;
