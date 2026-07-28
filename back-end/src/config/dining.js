// Tunable constants for the location-based food recommendation feature.
// Kept in one place (same idea as config/categories.js) so the numbers can
// be adjusted without hunting through the service files that use them.
//
// Every value below is env-overridable with a fallback literal — this file
// is the ONLY place a fallback number/string is allowed to live. maps.js and
// location.service.js never read process.env or inline a default themselves;
// they only receive these as explicit function parameters (see
// recommendation.service.js, which assembles `query`/`options` from this
// module once per request and threads them down).

function envInt(name, fallback) {
  const v = Number(process.env[name]);
  return Number.isFinite(v) ? v : fallback;
}

// C_meal = remaining food_dining budget / (days left in month * meals/day)
const DEFAULT_MEALS_PER_DAY = envInt('FOOD_MEALS_PER_DAY', 3);

// "Walking radius" hard spatial filter, per the feature spec (500-800m).
const DEFAULT_RADIUS_M = envInt('FOOD_SEARCH_RADIUS_M', 800);

// Max venues a single provider tier returns.
const FOOD_RESULT_LIMIT = envInt('FOOD_RESULT_LIMIT', 50);

// Provider pipeline stops trying further tiers once accumulated results
// reach this count (see maps.js#searchVenues's merge-and-accumulate loop).
const FOOD_MIN_RESULT_THRESHOLD = envInt('FOOD_MIN_RESULT_THRESHOLD', 5);

// Per-provider request timeouts (ms) — Overpass's public instance is
// noticeably slower than Geoapify/Foursquare, so it gets a longer default.
const PROVIDER_TIMEOUT_MS = envInt('PROVIDER_TIMEOUT_MS', 6000);
const OVERPASS_TIMEOUT_MS = envInt('OVERPASS_TIMEOUT_MS', 10000);
const GEOAPIFY_TIMEOUT_MS = envInt('GEOAPIFY_TIMEOUT_MS', PROVIDER_TIMEOUT_MS);
const FSQ_TIMEOUT_MS = envInt('FSQ_TIMEOUT_MS', PROVIDER_TIMEOUT_MS);

// Public Overpass instance — override for a private/mirror instance without
// touching maps.js.
const OVERPASS_API_URL = process.env.OVERPASS_API_URL || 'https://overpass-api.de/api/interpreter';

// "Food" isn't a single portable category code across providers, so this
// stays a structured per-provider map rather than one env var — but it's
// still data handed down as a parameter, never referenced ad hoc inside a
// provider function in maps.js.
const FOOD_CATEGORIES = {
  // OSM `amenity` tag values (Overpass QL regex alternation)
  overpass: ['restaurant', 'fast_food', 'cafe', 'food_court', 'bar', 'pub'],
  // Geoapify Places API v2 category taxonomy (`catering.*` group)
  geoapify: ['catering.restaurant', 'catering.fast_food', 'catering.cafe', 'catering.bar', 'catering.pub'],
  // Foursquare's root category ID for "Food" (restaurants, cafes, fast food,
  // bars) — the old v3 numeric IDs (e.g. '13000') 400 on the current Places
  // API; this legacy hex-style ID is what the migrated API still accepts.
  // Confirmed by live query against places-api.foursquare.com on 2026-07-22.
  foursquare: ['4d4b7105d754a06374d81259'],
};

// Foursquare's `price` field is a categorical 1-4 tier, not an actual
// expected-bill amount. These bands are a rough MYR approximation used only
// for the hard price filter (eliminate a venue whose tier floor already
// exceeds C_meal) — adjust freely as real usage shows they're off.
const PRICE_TIER_MYR_BANDS = {
  1: { min: 0, max: 15 },
  2: { min: 15, max: 30 },
  3: { min: 30, max: 60 },
  4: { min: 60, max: Infinity },
};
// Venues Foursquare returns with no `price` field at all (common for hawker
// stalls/kopitiam that aren't formally listed) are treated as this tier for
// the hard filter, so they aren't wrongly excluded for lacking price data.
const DEFAULT_PRICE_TIER = 1;

// Loss-aversion nudge only fires if the cheapest nearby alternative saves at
// least this much versus C_meal — otherwise everything "under budget" would
// trigger a notification.
const NUDGE_SAVINGS_THRESHOLD_MYR = 5;

// Meal-time windows (Asia/Kuala_Lumpur, matches users.timezone default) the
// loss-aversion nudge is allowed to fire in — no point nudging at 3am.
const MEAL_TIME_WINDOWS = [
  { label: 'breakfast', startHour: 7, endHour: 10 },
  { label: 'lunch', startHour: 12, endHour: 14 },
  { label: 'dinner', startHour: 18, endHour: 21 },
];

// venue_cache rows (025_venue_cache.sql) older than this are treated as
// stale and refetched from Foursquare — address/phone/website drift slowly,
// so a long TTL is fine and keeps repeat detail-screen opens free.
const VENUE_CACHE_TTL_DAYS = 30;

module.exports = {
  DEFAULT_MEALS_PER_DAY,
  DEFAULT_RADIUS_M,
  FOOD_RESULT_LIMIT,
  FOOD_MIN_RESULT_THRESHOLD,
  PROVIDER_TIMEOUT_MS,
  OVERPASS_TIMEOUT_MS,
  GEOAPIFY_TIMEOUT_MS,
  FSQ_TIMEOUT_MS,
  OVERPASS_API_URL,
  FOOD_CATEGORIES,
  PRICE_TIER_MYR_BANDS,
  DEFAULT_PRICE_TIER,
  NUDGE_SAVINGS_THRESHOLD_MYR,
  MEAL_TIME_WINDOWS,
  VENUE_CACHE_TTL_DAYS,
};
