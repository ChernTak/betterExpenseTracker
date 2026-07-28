-- Server-side cache for Foursquare venue detail lookups (food recommendation
-- feature, see recommendation.service.js#getVenueDetail). Populated lazily —
-- only when a user opens a venue's detail screen, not for every search
-- result — so it saves a Foursquare call on repeat views of the same venue
-- across all users, not just one user's own repeat visits. No user_id: venue
-- data (name/address/phone/website) isn't user-specific.
CREATE TABLE venue_cache (
  fsq_place_id  TEXT PRIMARY KEY,
  name          VARCHAR(255) NOT NULL,
  address       TEXT,
  lat           DOUBLE PRECISION,
  lng           DOUBLE PRECISION,
  price_tier    SMALLINT,
  tel           VARCHAR(50),
  website       TEXT,
  categories    TEXT[],
  cached_at     TIMESTAMP NOT NULL DEFAULT NOW()
);
