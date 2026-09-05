// Tunable, env-overridable constants for food recommendations; this is the only file allowed fallback defaults — maps.js/location.service.js only receive these as parameters.

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
const GOOGLE_PHOTO_TIMEOUT_MS = envInt('GOOGLE_PHOTO_TIMEOUT_MS', PROVIDER_TIMEOUT_MS);

// Public Overpass instance — override for a private/mirror instance without
// touching maps.js.
const OVERPASS_API_URL = process.env.OVERPASS_API_URL || 'https://overpass-api.de/api/interpreter';

// No portable "food" category code across providers, so this stays a structured map, still passed down as a parameter rather than referenced ad hoc in maps.js.
const FOOD_CATEGORIES = {
  // OSM `amenity` tag values (Overpass QL regex alternation)
  overpass: ['restaurant', 'fast_food', 'cafe', 'food_court', 'bar', 'pub'],
  // Geoapify Places API v2 category taxonomy (`catering.*` group)
  geoapify: ['catering.restaurant', 'catering.fast_food', 'catering.cafe', 'catering.bar', 'catering.pub'],
  // Foursquare's Food root category ID; old v3 numeric IDs 400 on the current Places API, this legacy hex-style ID still works (confirmed 2026-07-22).
  foursquare: ['4d4b7105d754a06374d81259'],
};

// Foursquare's price field is a categorical 1-4 tier, not a bill amount; these are rough MYR bands for the hard price filter.
const PRICE_TIER_MYR_BANDS = {
  1: { min: 0, max: 15 },
  2: { min: 15, max: 30 },
  3: { min: 30, max: 60 },
  4: { min: 60, max: Infinity },
};
// Venues with no price field (common for unlisted hawker stalls) default to this tier so they aren't wrongly excluded.
const DEFAULT_PRICE_TIER = 1;

// Nudge only fires if the cheapest alternative saves at least this much vs C_meal, otherwise every under-budget venue would trigger one.
const NUDGE_SAVINGS_THRESHOLD_MYR = 5;

// Meal-time windows (Asia/Kuala_Lumpur, matches users.timezone default) the
// loss-aversion nudge is allowed to fire in — no point nudging at 3am.
const MEAL_TIME_WINDOWS = [
  { label: 'breakfast', startHour: 7, endHour: 10 },
  { label: 'lunch', startHour: 12, endHour: 14 },
  { label: 'dinner', startHour: 18, endHour: 21 },
];

// venue_cache rows older than this are refetched from Foursquare; venue details drift slowly so a long TTL keeps repeat opens free.
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
  GOOGLE_PHOTO_TIMEOUT_MS,
  OVERPASS_API_URL,
  FOOD_CATEGORIES,
  PRICE_TIER_MYR_BANDS,
  DEFAULT_PRICE_TIER,
  NUDGE_SAVINGS_THRESHOLD_MYR,
  MEAL_TIME_WINDOWS,
  VENUE_CACHE_TTL_DAYS,
};
