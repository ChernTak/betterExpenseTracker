const contextService = require('./context.service');
const locationService = require('./location.service');
const nudgeService = require('./nudge.service');
const mapsConfig = require('../config/maps');
const recommendationModel = require('../models/recommendation.model');
const venueModel = require('../models/venue.model');
const {
  DEFAULT_RADIUS_M,
  FOOD_RESULT_LIMIT,
  FOOD_MIN_RESULT_THRESHOLD,
  OVERPASS_TIMEOUT_MS,
  GEOAPIFY_TIMEOUT_MS,
  FSQ_TIMEOUT_MS,
  OVERPASS_API_URL,
  FOOD_CATEGORIES,
  PRICE_TIER_MYR_BANDS,
  DEFAULT_PRICE_TIER,
  VENUE_CACHE_TTL_DAYS,
} = require('../config/dining');

function venueCacheRowToResponse(row) {
  return {
    id: row.provider_place_id,
    provider: row.provider,
    name: row.name,
    address: row.address,
    lat: row.lat,
    lng: row.lng,
    priceTier: row.price_tier,
    tel: row.tel,
    website: row.website,
    hours: row.hours,
    categories: row.categories || [],
  };
}

function isFresh(cachedAt) {
  const ageMs = Date.now() - new Date(cachedAt).getTime();
  return ageMs < VENUE_CACHE_TTL_DAYS * 24 * 60 * 60 * 1000;
}

function estimatedPriceMYR(priceTier) {
  const band = PRICE_TIER_MYR_BANDS[priceTier ?? DEFAULT_PRICE_TIER] || PRICE_TIER_MYR_BANDS[DEFAULT_PRICE_TIER];
  return band.max === Infinity ? band.min : (band.min + band.max) / 2;
}

// Hard price filter: a venue survives if its price tier's cheapest end
// doesn't already exceed C_meal. No budget set -> no cap -> nothing filtered.
function withinMealCap(venue, mealCap) {
  if (mealCap == null) return true;
  const band = PRICE_TIER_MYR_BANDS[venue.priceTier ?? DEFAULT_PRICE_TIER] || PRICE_TIER_MYR_BANDS[DEFAULT_PRICE_TIER];
  return band.min <= mealCap;
}

// Soft utility ranking: proximity + price margin below cap + optional
// cuisine-preference match. Weighted 0.4/0.4/0.2 — no ML, just a composite
// score so cold-start (no purchase history) users still get a sensible order.
function scoreVenue(venue, { mealCap, radiusM, preferredCuisines }) {
  const proximityScore = 1 - Math.min(venue.distanceM / radiusM, 1);

  let priceScore = 0.5; // neutral when there's no budget cap to score against
  if (mealCap != null && mealCap > 0) {
    const margin = (mealCap - estimatedPriceMYR(venue.priceTier)) / mealCap;
    priceScore = Math.max(0, Math.min(margin, 1));
  }

  const prefScore =
    preferredCuisines.length > 0 &&
    venue.categories.some((c) => preferredCuisines.includes(c.toLowerCase()))
      ? 1
      : 0;

  return 0.4 * proximityScore + 0.4 * priceScore + 0.2 * prefScore;
}

// GET /api/recommendations/food?lat=&lng=&radius=&cuisines=
exports.getFoodRecommendations = async (req, res) => {
  const lat = Number(req.query.lat);
  const lng = Number(req.query.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return res.status(400).json({ message: 'lat and lng query params are required and must be numbers' });
  }

  const radiusM = Number(req.query.radius) || DEFAULT_RADIUS_M;
  const preferredCuisines = (req.query.cuisines || '')
    .split(',')
    .map((c) => c.trim().toLowerCase())
    .filter(Boolean);

  // Assembled once per request from config/dining.js (env-overridable
  // defaults) — everything below this point (location.service.js,
  // config/maps.js) only ever sees these as explicit parameters, never
  // reads config/dining.js or process.env itself.
  const query = { lat, lng, radiusM, categories: FOOD_CATEGORIES, resultLimit: FOOD_RESULT_LIMIT };
  const options = {
    minResultThreshold: FOOD_MIN_RESULT_THRESHOLD,
    overpassApiUrl: OVERPASS_API_URL,
    overpassTimeoutMs: OVERPASS_TIMEOUT_MS,
    geoapifyTimeoutMs: GEOAPIFY_TIMEOUT_MS,
    fsqTimeoutMs: FSQ_TIMEOUT_MS,
    defaultPriceTier: DEFAULT_PRICE_TIER,
  };

  try {
    const context = await contextService.getDiningContext(req.user.userId);

    const { venues: inRadius, providerStatus } = await locationService.findNearbyVenues(query, options);
    const affordable = inRadius.filter((v) => withinMealCap(v, context.mealCap));

    const ranked = affordable
      .map((v) => ({ ...v, score: scoreVenue(v, { mealCap: context.mealCap, radiusM, preferredCuisines }) }))
      .sort((a, b) => b.score - a.score)
      .slice(0, 20);

    await recommendationModel.logRecommendation({
      userId: req.user.userId,
      title: 'Nearby food recommendations',
      body: `${ranked.length} venue(s) within ${radiusM}m under a RM${context.mealCap?.toFixed(2) ?? 'n/a'} meal cap`,
      contextSnapshot: { lat, lng, radiusM, mealCap: context.mealCap, venueCount: ranked.length, providerStatus },
    });

    // A push failure here shouldn't fail the recommendations the user asked for
    try {
      await nudgeService.maybeSendLossAversionNudge({
        userId: req.user.userId,
        budgetId: context.budgetId,
        mealCap: context.mealCap,
        venues: ranked,
      });
    } catch (nudgeErr) {
      console.error('Loss-aversion nudge failed', nudgeErr);
    }

    return res.status(200).json({
      hasBudget: context.hasBudget,
      mealCap: context.mealCap,
      remainingBudget: context.remainingBudget,
      daysLeft: context.daysLeft,
      radiusM,
      venues: ranked,
      providersUsed: providerStatus,
    });
  } catch (err) {
    console.error('Get food recommendations error', err);
    return res.status(500).json({ message: 'Failed to fetch food recommendations', error: err.message });
  }
};

// GET /api/recommendations/food/venues/:provider/:providerPlaceId —
// cache-or-fetch detail lookup, dispatched to whichever provider originally
// sourced the venue. Lazy: a cache row only exists for venues someone has
// actually opened before, not every venue a search ever returned.
exports.getVenueDetail = async (req, res) => {
  const { provider, providerPlaceId } = req.params;

  const options = {
    overpassApiUrl: OVERPASS_API_URL,
    overpassTimeoutMs: OVERPASS_TIMEOUT_MS,
    geoapifyTimeoutMs: GEOAPIFY_TIMEOUT_MS,
    fsqTimeoutMs: FSQ_TIMEOUT_MS,
    defaultPriceTier: DEFAULT_PRICE_TIER,
  };

  try {
    const cached = await venueModel.findByPlaceId({ provider, providerPlaceId });
    if (cached.rows.length > 0 && isFresh(cached.rows[0].cached_at)) {
      return res.status(200).json(venueCacheRowToResponse(cached.rows[0]));
    }

    const detail = await mapsConfig.getPlaceDetails({ provider, providerPlaceId }, options);
    if (!detail) {
      // Provider unconfigured/no longer has this place — fall back to a
      // stale cache row if one exists rather than a hard failure.
      if (cached.rows.length > 0) return res.status(200).json(venueCacheRowToResponse(cached.rows[0]));
      return res.status(404).json({ message: 'Venue details unavailable' });
    }

    const saved = await venueModel.upsertVenue({
      provider,
      providerPlaceId,
      name: detail.name,
      address: detail.address,
      lat: detail.lat,
      lng: detail.lng,
      priceTier: detail.priceTier,
      tel: detail.tel,
      website: detail.website,
      hours: detail.hours,
      categories: detail.categories,
    });

    return res.status(200).json(venueCacheRowToResponse(saved.rows[0]));
  } catch (err) {
    console.error('Get venue detail error', err);
    return res.status(500).json({ message: 'Failed to fetch venue detail', error: err.message });
  }
};
