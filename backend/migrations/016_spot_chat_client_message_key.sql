-- Add client_message_key to support optimistic message reconciliation
-- between Flutter local UI state and backend-confirmed spot chat messages.

ALTER TABLE public.spot_chat_messages
ADD COLUMN IF NOT EXISTS client_message_key TEXT;

CREATE INDEX IF NOT EXISTS idx_spot_chat_messages_client_message_key
ON public.spot_chat_messages (client_message_key);
