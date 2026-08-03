-- Records which Google API generation ('new' | 'legacy') a cached
-- photo_reference belongs to — the two use incompatible reference formats
-- and different media endpoints (see googlePhotos.service.js), so the
-- proxy route needs to know which one to call for a given cached photo.
ALTER TABLE venue_cache ADD COLUMN photo_api TEXT;
