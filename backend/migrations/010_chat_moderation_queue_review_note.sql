ALTER TABLE public.chat_moderation_queue
  ADD COLUMN IF NOT EXISTS review_note TEXT NULL;
