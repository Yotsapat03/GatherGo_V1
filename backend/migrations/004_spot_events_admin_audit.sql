BEGIN;

ALTER TABLE public.spot_events
ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT,
ADD COLUMN IF NOT EXISTS creator_role TEXT NOT NULL DEFAULT 'user',
ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_spot_events_creator_role_created_at
ON public.spot_events (creator_role, created_at DESC);

COMMIT;
