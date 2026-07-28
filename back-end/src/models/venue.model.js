const db = require('../config/db');

exports.findByPlaceId = ({ provider, providerPlaceId }) => {
  return db.query('SELECT * FROM venue_cache WHERE provider = $1 AND provider_place_id = $2', [provider, providerPlaceId]);
};

// Upsert since a stale row (past VENUE_CACHE_TTL_DAYS) is refreshed in
// place rather than deleted-then-reinserted.
exports.upsertVenue = ({ provider, providerPlaceId, name, address, lat, lng, priceTier, tel, website, hours, categories }) => {
  const query = `
    INSERT INTO venue_cache (provider, provider_place_id, name, address, lat, lng, price_tier, tel, website, hours, categories, cached_at)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW())
    ON CONFLICT (provider, provider_place_id) DO UPDATE SET
      name = EXCLUDED.name,
      address = EXCLUDED.address,
      lat = EXCLUDED.lat,
      lng = EXCLUDED.lng,
      price_tier = EXCLUDED.price_tier,
      tel = EXCLUDED.tel,
      website = EXCLUDED.website,
      hours = EXCLUDED.hours,
      categories = EXCLUDED.categories,
      cached_at = NOW()
    RETURNING *
  `;
  return db.query(query, [
    provider, providerPlaceId, name, address ?? null, lat ?? null, lng ?? null,
    priceTier ?? null, tel ?? null, website ?? null, hours ?? null, categories ?? [],
  ]);
};
