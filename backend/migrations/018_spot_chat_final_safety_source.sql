ALTER TABLE public.spot_chat_messages
  ADD COLUMN IF NOT EXISTS final_safety_source TEXT NOT NULL DEFAULT 'safe';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'spot_chat_messages_final_safety_source_chk'
  ) THEN
    ALTER TABLE public.spot_chat_messages
      ADD CONSTRAINT spot_chat_messages_final_safety_source_chk
      CHECK (
        final_safety_source IN (
          'safe',
          'language_moderation',
          'phishing_indicator',
          'ai_scam_suspicion'
        )
      );
  END IF;
END
$$;
