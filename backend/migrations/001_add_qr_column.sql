-- ========================================
-- Database Migration: Add QR URL to Events
-- ========================================
-- This migration adds QR code image storage for Big Events
-- allowing admin to upload and users to download payment QR codes

-- ✅ Add qr_url column to events table (if not exists)
ALTER TABLE events
ADD COLUMN IF NOT EXISTS qr_url TEXT;

-- Add comment for clarity
COMMENT ON COLUMN events.qr_url IS 'URL to payment QR code image (e.g., /uploads/qr/event_123.png)';

-- ✅ Optional: Add qr_payment_method to track which method the QR is for
ALTER TABLE events
ADD COLUMN IF NOT EXISTS qr_payment_method VARCHAR(50);

COMMENT ON COLUMN events.qr_payment_method IS 'Payment method for QR code (promptPay, aliPay, etc.)';

-- ✅ Optional: Add index for faster lookups
CREATE INDEX IF NOT EXISTS idx_events_qr_url ON events(qr_url);

-- ========================================
-- Verification Query
-- ========================================
-- Run this to verify the columns exist:
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'events'
-- ORDER BY ordinal_position;
