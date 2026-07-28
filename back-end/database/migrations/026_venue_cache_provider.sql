-- Makes venue_cache provider-aware (see 025_venue_cache.sql). The search
-- pipeline now sources venues from Overpass/Geoapify/Foursquare, whose IDs
-- aren't cross-compatible, so the cache key becomes (provider,
-- provider_place_id) instead of a bare Foursquare-only ID. Existing rows
-- (all Foursquare-sourced, from before this migration) are backfilled via
-- the column default rather than dropped.
ALTER TABLE venue_cache RENAME COLUMN fsq_place_id TO provider_place_id;
ALTER TABLE venue_cache ADD COLUMN provider TEXT NOT NULL DEFAULT 'foursquare';
ALTER TABLE venue_cache ALTER COLUMN provider DROP DEFAULT;

ALTER TABLE venue_cache DROP CONSTRAINT venue_cache_pkey;
ALTER TABLE venue_cache ADD PRIMARY KEY (provider, provider_place_id);
