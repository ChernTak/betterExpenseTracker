-- Server-side cache for actual venue photo bytes (see
-- recommendation.service.js#getVenuePhoto). Separate from venue_cache
-- because the /food/photo/:api/:photoReference route only ever carries
-- api+reference, not provider/providerPlaceId — (api, photo_reference) is
-- the key that's actually available at lookup time. Without this, every
-- Image.network() load that isn't already in that device's local cache
-- re-fetches the same photo from Google, even for a venue whose photo
-- *reference* was already cache-hit from venue_cache.
CREATE TABLE photo_cache (
  api             TEXT NOT NULL,
  photo_reference TEXT NOT NULL,
  content_type    TEXT NOT NULL,
  bytes           BYTEA NOT NULL,
  cached_at       TIMESTAMP NOT NULL DEFAULT NOW(),
  PRIMARY KEY (api, photo_reference)
);
