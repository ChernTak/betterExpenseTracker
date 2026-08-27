-- Shared (not user-specific) reference data for the real-time high-spend-area
-- nudge: shopping malls/department stores the Android app registers as
-- geofences, so entering one can trigger a 'location_nudge' alert before a
-- purchase happens, instead of the existing budget alerts which only fire
-- retrospectively after an expense is already saved. Populated via
-- database/seeds/seed_high_risk_locations.js (Overpass API), not at request
-- time, so GET /api/nudge/high-risk-locations stays fast and dependency-free.
CREATE TABLE high_risk_locations (
  location_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name              VARCHAR(255) NOT NULL,
  latitude          DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude         DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  radius_meters     INTEGER NOT NULL DEFAULT 150 CHECK (radius_meters > 0),
  source            VARCHAR(50) NOT NULL DEFAULT 'overpass',
  created_at        TIMESTAMP DEFAULT NOW()
);
