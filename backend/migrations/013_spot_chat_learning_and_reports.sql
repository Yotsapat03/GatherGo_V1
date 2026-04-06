CREATE TABLE IF NOT EXISTS public.moderation_vocabulary (
  id BIGSERIAL PRIMARY KEY,
  term TEXT NOT NULL,
  normalized_term TEXT NOT NULL,
  language TEXT NOT NULL DEFAULT 'mixed',
  category TEXT NOT NULL,
  severity TEXT NOT NULL DEFAULT 'medium',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  source TEXT NOT NULL DEFAULT 'seed',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_moderation_vocabulary_unique_term
  ON public.moderation_vocabulary (normalized_term, category, language);

CREATE INDEX IF NOT EXISTS idx_moderation_vocabulary_active
  ON public.moderation_vocabulary (is_active, updated_at DESC);

CREATE TABLE IF NOT EXISTS public.moderation_vocabulary_suggestions (
  id BIGSERIAL PRIMARY KEY,
  raw_message TEXT NOT NULL,
  suggested_term TEXT NOT NULL,
  normalized_term TEXT NOT NULL,
  language TEXT NOT NULL DEFAULT 'mixed',
  category TEXT NOT NULL,
  confidence DOUBLE PRECISION NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ NULL,
  reviewed_by_admin_id BIGINT NULL
);

CREATE INDEX IF NOT EXISTS idx_moderation_vocab_suggestions_status_created_at
  ON public.moderation_vocabulary_suggestions (status, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_moderation_vocab_suggestions_pending_unique
  ON public.moderation_vocabulary_suggestions (normalized_term, category, status);

CREATE TABLE IF NOT EXISTS public.spot_chat_user_reports (
  id BIGSERIAL PRIMARY KEY,
  reporter_user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reported_user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  spot_key TEXT NOT NULL,
  message_id BIGINT NULL REFERENCES public.spot_chat_messages(id) ON DELETE SET NULL,
  reason_code TEXT NOT NULL DEFAULT 'INAPPROPRIATE_LANGUAGE',
  note TEXT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_spot_chat_user_reports_spot_key_created_at
  ON public.spot_chat_user_reports (spot_key, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_spot_chat_user_reports_reporter_created_at
  ON public.spot_chat_user_reports (reporter_user_id, created_at DESC);
