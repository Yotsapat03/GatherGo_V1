ALTER TABLE public.spot_chat_messages
  ADD COLUMN IF NOT EXISTS decision_priority INTEGER NOT NULL DEFAULT 0;
