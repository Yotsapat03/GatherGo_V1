CREATE TABLE IF NOT EXISTS public.spot_leave_feedback (
  id BIGSERIAL PRIMARY KEY,
  event_id BIGINT NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  leaver_user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reason_code VARCHAR(64) NOT NULL,
  reason_text TEXT NOT NULL,
  category VARCHAR(32) NOT NULL CHECK (category IN ('NON_BEHAVIOR','BEHAVIOR_SAFETY')),
  reported_target_type VARCHAR(16) NOT NULL CHECK (reported_target_type IN ('creator','participant','none')),
  reported_target_user_id BIGINT NULL REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_spot_leave_feedback_event_id
  ON public.spot_leave_feedback(event_id);

CREATE INDEX IF NOT EXISTS idx_spot_leave_feedback_leaver
  ON public.spot_leave_feedback(leaver_user_id);

CREATE INDEX IF NOT EXISTS idx_spot_leave_feedback_category
  ON public.spot_leave_feedback(category);

CREATE INDEX IF NOT EXISTS idx_spot_leave_feedback_target
  ON public.spot_leave_feedback(reported_target_user_id);
