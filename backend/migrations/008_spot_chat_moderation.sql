CREATE TABLE IF NOT EXISTS public.chat_moderation_logs (
  id BIGSERIAL PRIMARY KEY,
  message_id BIGINT NULL REFERENCES public.spot_chat_messages(id) ON DELETE SET NULL,
  user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  spot_key TEXT NOT NULL,
  spot_event_id BIGINT NULL REFERENCES public.spot_events(id) ON DELETE SET NULL,
  raw_message TEXT NOT NULL,
  normalized_message TEXT NOT NULL,
  detected_categories TEXT[] NOT NULL DEFAULT '{}'::TEXT[],
  severity TEXT NOT NULL DEFAULT 'none',
  action_taken TEXT NOT NULL,
  rule_hits JSONB NOT NULL DEFAULT '[]'::JSONB,
  ai_result_json JSONB NULL,
  suspension_required BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chat_moderation_logs_spot_key_created_at
  ON public.chat_moderation_logs (spot_key, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_chat_moderation_logs_user_id_created_at
  ON public.chat_moderation_logs (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_chat_moderation_logs_action_created_at
  ON public.chat_moderation_logs (action_taken, created_at DESC);

CREATE TABLE IF NOT EXISTS public.chat_moderation_queue (
  id BIGSERIAL PRIMARY KEY,
  moderation_log_id BIGINT NOT NULL REFERENCES public.chat_moderation_logs(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  spot_key TEXT NOT NULL,
  spot_event_id BIGINT NULL REFERENCES public.spot_events(id) ON DELETE SET NULL,
  queue_status TEXT NOT NULL DEFAULT 'open',
  priority TEXT NOT NULL DEFAULT 'normal',
  alert_room BOOLEAN NOT NULL DEFAULT FALSE,
  suspension_required BOOLEAN NOT NULL DEFAULT FALSE,
  review_payload JSONB NOT NULL DEFAULT '{}'::JSONB,
  reviewed_by_admin_id BIGINT NULL,
  reviewed_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chat_moderation_queue_status_created_at
  ON public.chat_moderation_queue (queue_status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_chat_moderation_queue_spot_key_created_at
  ON public.chat_moderation_queue (spot_key, created_at DESC);
