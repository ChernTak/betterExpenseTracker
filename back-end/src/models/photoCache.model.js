const db = require('../config/db');

exports.findByReference = ({ api, photoReference }) => {
  return db.query('SELECT * FROM photo_cache WHERE api = $1 AND photo_reference = $2', [api, photoReference]);
};

// Upsert since a stale row (past VENUE_CACHE_TTL_DAYS) is refreshed in
// place rather than deleted-then-reinserted, same pattern as venue.model.js.
exports.upsertPhoto = ({ api, photoReference, contentType, bytes }) => {
  const query = `
    INSERT INTO photo_cache (api, photo_reference, content_type, bytes, cached_at)
    VALUES ($1, $2, $3, $4, NOW())
    ON CONFLICT (api, photo_reference) DO UPDATE SET
      content_type = EXCLUDED.content_type,
      bytes = EXCLUDED.bytes,
      cached_at = NOW()
    RETURNING *
  `;
  return db.query(query, [api, photoReference, contentType, bytes]);
};
