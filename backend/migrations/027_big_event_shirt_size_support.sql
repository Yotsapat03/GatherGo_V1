BEGIN;

ALTER TABLE public.bookings
ADD COLUMN IF NOT EXISTS shirt_size TEXT;

ALTER TABLE public.participants
ADD COLUMN IF NOT EXISTS shirt_size TEXT;

COMMIT;
