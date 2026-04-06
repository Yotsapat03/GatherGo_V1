CREATE TABLE IF NOT EXISTS public.audit_logs (
  id BIGSERIAL PRIMARY KEY,
  admin_user_id BIGINT NULL,
  user_id BIGINT NULL REFERENCES public.users(id) ON DELETE SET NULL,
  actor_type TEXT NOT NULL DEFAULT 'system',
  action TEXT NOT NULL,
  entity_table TEXT NULL,
  entity_id BIGINT NULL,
  metadata_json JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at
  ON public.audit_logs (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_logs_action_created_at
  ON public.audit_logs (action, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_logs_admin_created_at
  ON public.audit_logs (admin_user_id, created_at DESC);
