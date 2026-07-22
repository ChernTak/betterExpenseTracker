// Tunable constants for the location-based food recommendation feature.
// Kept in one place (same idea as config/categories.js) so the numbers can
// be adjusted without hunting through the service files that use them.

// C_meal = remaining food_dining budget / (days left in month * meals/day)
const DEFAULT_MEALS_PER_DAY = 3;

// "Walking radius" hard spatial filter, per the feature spec (500-800m).
const DEFAULT_RADIUS_M = 800;

// Foursquare's root category ID for "Food" (restaurants, cafes, fast food,
// bars) — the old v3 numeric IDs (e.g. '13000') 400 on the current Places
// API; this legacy hex-style ID is what the migrated API still accepts.
// Confirmed by live query against places-api.foursquare.com on 2026-07-22.
const FSQ_FOOD_CATEGORY_ID = '4d4b7105d754a06374d81259';

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

module.exports = {
  DEFAULT_MEALS_PER_DAY,
  DEFAULT_RADIUS_M,
  FSQ_FOOD_CATEGORY_ID,
  PRICE_TIER_MYR_BANDS,
  DEFAULT_PRICE_TIER,
  NUDGE_SAVINGS_THRESHOLD_MYR,
  MEAL_TIME_WINDOWS,
};
