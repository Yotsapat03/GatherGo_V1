ALTER TABLE public.chat_moderation_logs
  ADD COLUMN IF NOT EXISTS ai_used BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.chat_moderation_logs
  ADD COLUMN IF NOT EXISTS ai_confidence DOUBLE PRECISION NULL;
