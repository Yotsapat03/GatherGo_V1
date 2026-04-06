ALTER TABLE public.spot_leave_feedback
  ADD COLUMN IF NOT EXISTS report_detail_text TEXT NULL;
