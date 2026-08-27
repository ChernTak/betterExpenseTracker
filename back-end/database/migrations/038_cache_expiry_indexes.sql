-- Phase 4 of DB cleanup. venue_cache and photo_cache (025/030) have no
-- purge mechanism, so they grow unbounded — a venue looked up once and
-- never again just sits there forever past VENUE_CACHE_TTL_DAYS
-- (config/dining.js), unlike actively-viewed venues which self-refresh via
-- upsert. Supports the new admin-triggered purge routes (see
-- admin.service.js#purgeVenueCache / purgePhotoCache), following the same
-- "no job scheduler" pattern already used for recommendation_log
-- (see recommendation.model.js#purgeOlderThan) and stale guests
-- (user.model.js#purgeStaleGuests).

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_venue_cache_cached_at
  ON venue_cache (cached_at);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_photo_cache_cached_at
  ON photo_cache (cached_at);
