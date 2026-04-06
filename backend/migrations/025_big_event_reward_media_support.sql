BEGIN;

CREATE INDEX IF NOT EXISTS idx_event_media_event_kind_sort
  ON public.event_media (event_id, kind, sort_order, id);

COMMIT;
