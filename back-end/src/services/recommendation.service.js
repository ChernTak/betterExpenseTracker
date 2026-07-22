const contextService = require('./context.service');
const locationService = require('./location.service');
const nudgeService = require('./nudge.service');
const mapsConfig = require('../config/maps');
const recommendationModel = require('../models/recommendation.model');
const { DEFAULT_RADIUS_M, PRICE_TIER_MYR_BANDS, DEFAULT_PRICE_TIER } = require('../config/dining');

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

  try {
    const context = await contextService.getDiningContext(req.user.userId);

    const rawVenues = await mapsConfig.searchNearbyFood({ lat, lng, radiusM });
    const inRadius = locationService.filterWithinRadius(rawVenues, { lat, lng }, radiusM);
    const affordable = inRadius.filter((v) => withinMealCap(v, context.mealCap));

    const ranked = affordable
      .map((v) => ({ ...v, score: scoreVenue(v, { mealCap: context.mealCap, radiusM, preferredCuisines }) }))
      .sort((a, b) => b.score - a.score)
      .slice(0, 20);

    await recommendationModel.logRecommendation({
      userId: req.user.userId,
      title: 'Nearby food recommendations',
      body: `${ranked.length} venue(s) within ${radiusM}m under a RM${context.mealCap?.toFixed(2) ?? 'n/a'} meal cap`,
      contextSnapshot: { lat, lng, radiusM, mealCap: context.mealCap, venueCount: ranked.length },
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
    });
  } catch (err) {
    console.error('Get food recommendations error', err);
    return res.status(500).json({ message: 'Failed to fetch food recommendations', error: err.message });
  }
};
