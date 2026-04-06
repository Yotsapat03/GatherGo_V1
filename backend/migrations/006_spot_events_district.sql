ALTER TABLE public.spot_events
  ADD COLUMN IF NOT EXISTS district TEXT;
