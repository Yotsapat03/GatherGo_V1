-- ========================================
-- Database Migration: Add lap-based distance columns to events
-- ========================================
-- New structure:
--  - distance_per_lap (numeric)
--  - number_of_laps (integer)
--  - total_distance (numeric)
--
-- Backward compatibility:
--  - Existing rows remain unchanged (NULL columns allowed)
--  - Old events can keep using their legacy distance field/value

ALTER TABLE events
ADD COLUMN IF NOT EXISTS distance_per_lap NUMERIC(12, 3);

ALTER TABLE events
ADD COLUMN IF NOT EXISTS number_of_laps INTEGER;

ALTER TABLE events
ADD COLUMN IF NOT EXISTS total_distance NUMERIC(12, 3);

COMMENT ON COLUMN events.distance_per_lap IS 'Distance per lap, admin input';
COMMENT ON COLUMN events.number_of_laps IS 'Number of laps, admin input';
COMMENT ON COLUMN events.total_distance IS 'Server-calculated total distance: distance_per_lap * number_of_laps';

