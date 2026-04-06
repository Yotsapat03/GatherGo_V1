CREATE TABLE IF NOT EXISTS public.spot_chat_room_alerts (
  id BIGSERIAL PRIMARY KEY,
  spot_key TEXT NOT NULL,
  spot_event_id BIGINT NULL REFERENCES public.spot_events(id) ON DELETE SET NULL,
  alert_type TEXT NOT NULL,
  message TEXT NOT NULL,
  triggered_by_user_id BIGINT NULL REFERENCES public.users(id) ON DELETE SET NULL,
  source_queue_id BIGINT NULL,
  source_log_id BIGINT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NULL
);

CREATE INDEX IF NOT EXISTS idx_spot_chat_room_alerts_spot_key_created_at
  ON public.spot_chat_room_alerts (spot_key, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_spot_chat_room_alerts_active
  ON public.spot_chat_room_alerts (spot_key, is_active, created_at DESC);
