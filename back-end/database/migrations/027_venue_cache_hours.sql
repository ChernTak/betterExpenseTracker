-- Raw OSM-style opening_hours string (e.g. "Mo-Fr 08:00-18:00; Sa 08:00-14:00"),
-- shown as-is on the venue detail screen. Free on Overpass/Geoapify (both
-- OSM-derived); Foursquare's `hours` field is Premium-gated so Foursquare-
-- sourced rows just get NULL here, same as their already-missing price data.
ALTER TABLE venue_cache ADD COLUMN hours TEXT;
