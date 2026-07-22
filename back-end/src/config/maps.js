const { FSQ_FOOD_CATEGORY_ID } = require('./dining');

const FSQ_API_KEY = process.env.FSQ_API_KEY;
// Foursquare retired the old api.foursquare.com/v3/places/search endpoint
// (returns 410 Gone as of 2026-07-22, pointing at their migration guide) in
// favour of this host. The Places API also requires a dated version header
// on every request — confirmed live: omitting it 400s with "Please provide
// a valid version.".
const FSQ_SEARCH_URL = 'https://places-api.foursquare.com/places/search';
const FSQ_API_VERSION = '2025-06-17';

// Optional in dev, same pattern as config/firebase.js — if unset,
// recommendation.service.js logs instead of calling out to Foursquare.
const isConfigured = Boolean(FSQ_API_KEY);

if (!isConfigured) {
  console.log('[DEV] FSQ_API_KEY not set — food recommendations will be logged, not fetched.');
}

// Nearby food venue search via Foursquare's Places API. Returns a plain
// array (never throws for a normal "no results" response — only for a
// genuine request/auth failure) so the caller can filter/rank without
// special-casing the transport layer.
exports.searchNearbyFood = async ({ lat, lng, radiusM }) => {
  if (!isConfigured) return [];

  const params = new URLSearchParams({
    ll: `${lat},${lng}`,
    radius: String(radiusM),
    fsq_category_ids: FSQ_FOOD_CATEGORY_ID,
    sort: 'DISTANCE',
    limit: '50',
  });

  const response = await fetch(`${FSQ_SEARCH_URL}?${params.toString()}`, {
    headers: {
      Authorization: `Bearer ${FSQ_API_KEY}`,
      Accept: 'application/json',
      'X-Places-Api-Version': FSQ_API_VERSION,
    },
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Foursquare search failed (${response.status}): ${body}`);
  }

  const data = await response.json();
  const results = data.results || [];

  return results.map((venue) => ({
    id: venue.fsq_place_id,
    name: venue.name,
    distanceM: venue.distance ?? null,
    address: venue.location?.formatted_address ?? null,
    lat: venue.latitude ?? null,
    lng: venue.longitude ?? null,
    priceTier: venue.price ?? null,
    categories: (venue.categories || []).map((c) => c.name),
  }));
};

exports.isConfigured = isConfigured;
