-- Google Places photo_reference for venue cards/detail screens. Stores the
-- raw reference (not a pre-built URL) — the API key is never baked into
-- stored data, and the proxy route (recommendation.service.js#getVenuePhoto)
-- can change shape later without a data migration.
ALTER TABLE venue_cache ADD COLUMN photo_reference TEXT;
