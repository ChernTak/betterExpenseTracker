const contextService = require('./context.service');
const locationService = require('./location.service');
const nudgeService = require('./nudge.service');
const mapsConfig = require('../config/maps');
const googlePhotosService = require('./googlePhotos.service');
const recommendationModel = require('../models/recommendation.model');
const venueModel = require('../models/venue.model');
const photoCacheModel = require('../models/photoCache.model');
const expenseModel = require('../models/expense.model');
const { normalizeMerchantText } = require('./categorization.service');
const {
  DEFAULT_RADIUS_M,
  FOOD_RESULT_LIMIT,
  FOOD_MIN_RESULT_THRESHOLD,
  OVERPASS_TIMEOUT_MS,
  GEOAPIFY_TIMEOUT_MS,
  FSQ_TIMEOUT_MS,
  GOOGLE_PHOTO_TIMEOUT_MS,
  OVERPASS_API_URL,
  FOOD_CATEGORIES,
  PRICE_TIER_MYR_BANDS,
  DEFAULT_PRICE_TIER,
  VENUE_CACHE_TTL_DAYS,
} = require('../config/dining');

const GOOGLE_PHOTO_MAX_WIDTH = 400;

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

// Soft utility ranking: proximity + price margin below cap + cuisine
// preference + personal visit history + optional halal boost. Weighted
// 0.25/0.25/0.1/0.25/0.15 — visitScore keeps real weight (comparable to
// price fit) since it's the one signal Google Maps structurally can't have
// (a real financial commitment, not a click/rating), but proximity+price
// together still outweigh it so a budget/distance mismatch isn't overridden
// by "you've eaten here before". No ML, just a composite score so cold-start
// (no purchase history, no filters set) users still get a sensible order —
// every optional term is simply 0 then.
function scoreVenue(venue, { mealCap, radiusM, preferredCuisines, visitHistory, halalPreferred }) {
  const proximityScore = 1 - Math.min(venue.distanceM / radiusM, 1);

  let priceScore = 0.5; // neutral when there's no budget cap to score against
  if (mealCap != null && mealCap > 0) {
    const margin = (mealCap - estimatedPriceMYR(venue.priceTier)) / mealCap;
    priceScore = Math.max(0, Math.min(margin, 1));
  }

  // Substring, not exact match — Overpass/Geoapify categories are generic
  // type strings ("restaurant") but Foursquare's are specific cuisine names
  // ("Tempura Restaurant"); exact match would silently never match
  // Foursquare-sourced venues at all.
  const prefScore =
    preferredCuisines.length > 0 &&
    venue.categories.some((c) => preferredCuisines.some((pref) => c.toLowerCase().includes(pref)))
      ? 1
      : 0;

  // Full weight at 3+ prior logged visits, partial credit below that — so
  // one single long-ago expense doesn't permanently dominate the ranking.
  const visitCount = visitHistory.get(normalizeMerchantText(venue.name || '')) ?? 0;
  const visitScore = Math.min(visitCount / 3, 1);

  // Only non-zero when the user opted in AND the venue is confirmed halal —
  // never penalizes unconfirmed venues (dietary tagging is sparse; absence
  // means "unknown", not "not halal" — see plan). Zero for everyone when
  // the preference isn't set, same no-op shape as prefScore.
  const halalScore = halalPreferred && venue.dietary?.halal === true ? 1 : 0;

  return 0.25 * proximityScore + 0.25 * priceScore + 0.1 * prefScore + 0.25 * visitScore + 0.15 * halalScore;
}

function photoUrlFor(photoReference, photoApi) {
  return photoReference && photoApi
    ? `/api/recommendations/food/photo/${photoApi}/${encodeURIComponent(photoReference)}`
    : null;
}

// Enriches each ranked venue with a photoUrl, cache-first: a venue already
// carrying a fresh photo_reference (from a prior search or detail view)
// skips the Google call entirely. Runs the whole batch in parallel — one
// venue's lookup failing resolves to null rather than rejecting the others
// (same defensive-per-item style as config/maps.js#searchVenues's tiers).
async function enrichWithPhotos(venues, { radiusM }) {
  return Promise.all(
    venues.map(async (venue) => {
      try {
        const cached = await venueModel.findByPlaceId({ provider: venue.provider, providerPlaceId: venue.id });
        const cachedRow = cached.rows[0];
        if (cachedRow?.photo_reference && cachedRow?.photo_api && isFresh(cachedRow.cached_at)) {
          return { ...venue, photoUrl: photoUrlFor(cachedRow.photo_reference, cachedRow.photo_api) };
        }

        // Tries the New Places API first, falls back to the legacy API on
        // any failure — see googlePhotos.service.js's header comment for why.
        const photo = await googlePhotosService.findPhotoReference(
          { name: venue.name, lat: venue.lat, lng: venue.lng },
          { radiusM, timeoutMs: GOOGLE_PHOTO_TIMEOUT_MS },
        );

        if (photo) {
          await venueModel.upsertPhotoReference({
            provider: venue.provider,
            providerPlaceId: venue.id,
            name: venue.name,
            lat: venue.lat,
            lng: venue.lng,
            photoReference: photo.reference,
            photoApi: photo.api,
          });
        }

        return { ...venue, photoUrl: photo ? photoUrlFor(photo.reference, photo.api) : null };
      } catch (err) {
        console.error(`Photo enrichment failed for "${venue.name}"`, err.message);
        return { ...venue, photoUrl: null };
      }
    }),
  );
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
  const halalPreferred = req.query.halal === 'true';
  // 'new' = exclude previously-visited venues, 'visited' = only previously-
  // visited, unset/anything else = no filter (the common case).
  const visitFilter = req.query.visitFilter === 'new' || req.query.visitFilter === 'visited' ? req.query.visitFilter : null;

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

    // "You've been here before" personalization — a Map of normalized
    // merchant name -> how many food_dining expenses were ever logged
    // against it. Built once per request, fed into scoreVenue below.
    const history = await expenseModel.getFoodDiningMerchantHistory(req.user.userId);
    const visitHistory = new Map(
      history.rows.map((row) => [normalizeMerchantText(row.merchant_name), Number(row.visit_count)]),
    );

    const { venues: inRadius, providerStatus } = await locationService.findNearbyVenues(query, options);
    const affordable = inRadius.filter((v) => withinMealCap(v, context.mealCap));

    const scored = affordable.map((v) => {
      const visitCount = visitHistory.get(normalizeMerchantText(v.name || '')) ?? 0;
      return {
        ...v,
        score: scoreVenue(v, { mealCap: context.mealCap, radiusM, preferredCuisines, visitHistory, halalPreferred }),
        previouslyVisited: visitCount > 0,
        visitCount,
      };
    });

    // Applied before the top-20 slice below, not after — so a filtered-out
    // venue never wastes a slot in the capped result set.
    const filtered = visitFilter
      ? scored.filter((v) => (visitFilter === 'new' ? !v.previouslyVisited : v.previouslyVisited))
      : scored;

    const ranked = filtered.sort((a, b) => b.score - a.score).slice(0, 20);

    // A photo lookup failure shouldn't fail the recommendations themselves
    // — enrichWithPhotos already resolves each venue to photoUrl: null on
    // any per-venue error, but guard the whole pass too in case Google is
    // unconfigured/unreachable in a way that throws before that.
    let enriched = ranked;
    try {
      enriched = await enrichWithPhotos(ranked, { radiusM });
    } catch (photoErr) {
      console.error('Photo enrichment pass failed', photoErr);
    }

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
        venues: enriched,
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
      venues: enriched,
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

// GET /api/recommendations/food/photo/:api/:photoReference — proxies the
// actual photo bytes rather than handing the client a Google URL with the
// API key embedded in it (every other provider key in this app stays
// backend-only; this keeps that rule intact — see plan). Cache-or-fetch
// against photo_cache first: the venue_cache/photo_reference lookup is
// already shared across all users, but without this second cache, every
// fresh Image.network() load (different device, or same device after its
// local cache clears) would re-bill Google for bytes we've already fetched
// once. Cache-Control still set for the client-side case this doesn't cover
// (same device, same session, no repeat network request at all).
exports.getVenuePhoto = async (req, res) => {
  const { api, photoReference } = req.params;

  try {
    const cached = await photoCacheModel.findByReference({ api, photoReference });
    if (cached.rows.length > 0 && isFresh(cached.rows[0].cached_at)) {
      const row = cached.rows[0];
      res.set('Content-Type', row.content_type);
      res.set('Cache-Control', 'public, max-age=86400');
      return res.status(200).send(row.bytes);
    }

    const photo = await googlePhotosService.fetchPhotoBytes(
      { reference: photoReference, api },
      { maxWidth: GOOGLE_PHOTO_MAX_WIDTH, timeoutMs: GOOGLE_PHOTO_TIMEOUT_MS },
    );

    if (!photo) {
      return res.status(404).json({ message: 'Photo unavailable' });
    }

    await photoCacheModel.upsertPhoto({
      api,
      photoReference,
      contentType: photo.contentType,
      bytes: photo.buffer,
    });

    res.set('Content-Type', photo.contentType);
    res.set('Cache-Control', 'public, max-age=86400');
    return res.status(200).send(photo.buffer);
  } catch (err) {
    console.error('Get venue photo error', err);
    return res.status(500).json({ message: 'Failed to fetch venue photo', error: err.message });
  }
};
