// 3-tier venue-search fallback pipeline: OSM/Overpass (free) -> Geoapify
// (free tier) -> Foursquare (existing, metered). Every radius/limit/
// timeout/category/price-tier value used below arrives as an explicit
// function parameter — config/dining.js is the only place a fallback
// literal is allowed to live (see its header comment). recommendation.
// service.js assembles `query`/`options` once per request and passes them
// down through location.service.js#findNearbyVenues into searchVenues here.

const FSQ_API_KEY = process.env.FSQ_API_KEY;
const GEOAPIFY_API_KEY = process.env.GEOAPIFY_API_KEY;

// Foursquare retired api.foursquare.com/v3/places/search (410 Gone as of
// 2026-07-22, pointing at their migration guide) in favour of this host.
// The Places API also requires a dated version header on every request —
// confirmed live: omitting it 400s with "Please provide a valid version.".
const FSQ_BASE_URL = 'https://places-api.foursquare.com/places';
const FSQ_API_VERSION = '2025-06-17';
const GEOAPIFY_BASE_URL = 'https://api.geoapify.com/v2/places';

const fsqIsConfigured = Boolean(FSQ_API_KEY);
const geoapifyIsConfigured = Boolean(GEOAPIFY_API_KEY);

if (!fsqIsConfigured) {
  console.log('[DEV] FSQ_API_KEY not set — Foursquare tier will be skipped.');
}
if (!geoapifyIsConfigured) {
  console.log('[DEV] GEOAPIFY_API_KEY not set — Geoapify tier will be skipped.');
}

function fsqHeaders() {
  return {
    Authorization: `Bearer ${FSQ_API_KEY}`,
    Accept: 'application/json',
    'X-Places-Api-Version': FSQ_API_VERSION,
  };
}

// Every provider fetch is timeout-bounded so one slow/unreachable tier
// (Overpass's public instance especially) can't hang the whole pipeline —
// caught by searchVenues same as any other per-tier failure.
async function fetchWithTimeout(url, fetchOptions, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...fetchOptions, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

// Maps every provider's field names onto one unified shape. `defaultPriceTier`
// is a parameter (never a literal) — the spec's requirement that a missing
// price falls back to a configurable value, not a hardcoded number.
function normalizeVenue(raw, provider, { defaultPriceTier }) {
  return {
    id: raw.id,
    provider,
    name: raw.name ?? null,
    distanceM: raw.distanceM ?? null,
    address: raw.address ?? null,
    lat: raw.lat ?? null,
    lng: raw.lng ?? null,
    priceTier: raw.priceTier ?? defaultPriceTier,
    tel: raw.tel ?? null,
    website: raw.website ?? null,
    hours: raw.hours ?? null,
    categories: raw.categories ?? [],
  };
}

// ---------------------------------------------------------------------
// Tier 1: OSM / Overpass — free, no API key, no price data, no native
// distance (both are filled in later by location.service.js's Haversine
// fallback / normalizeVenue's defaultPriceTier).
// ---------------------------------------------------------------------
async function searchOverpass(query, options) {
  const { lat, lng, radiusM, categories, resultLimit } = query;
  const { overpassApiUrl, overpassTimeoutMs, defaultPriceTier } = options;

  const amenityRegex = categories.overpass.join('|');
  const ql = `[out:json][timeout:${Math.ceil(overpassTimeoutMs / 1000)}];
(
  node["amenity"~"^(${amenityRegex})$"](around:${radiusM},${lat},${lng});
);
out body ${resultLimit};`;

  const response = await fetchWithTimeout(
    overpassApiUrl,
    {
      method: 'POST',
      body: `data=${encodeURIComponent(ql)}`,
      // Overpass's public instance 406s without both of these — confirmed
      // live. Accept: Node's fetch sends none by default. User-Agent:
      // Overpass's Apache config appears to bot-block Node's default/empty
      // one; a descriptive UA is also Overpass's own usage-policy etiquette,
      // not just a technical workaround.
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        Accept: 'application/json',
        'User-Agent': 'expenseTracker-food-recommendation/1.0 (dev)',
      },
    },
    overpassTimeoutMs,
  );

  if (!response.ok) {
    throw new Error(`Overpass search failed (${response.status}): ${await response.text()}`);
  }

  const data = await response.json();
  const elements = data.elements || [];

  return elements.map((el) => {
    const tags = el.tags || {};
    const address =
      tags['addr:full'] ||
      [tags['addr:housenumber'], tags['addr:street'], tags['addr:city']].filter(Boolean).join(' ') ||
      null;

    return normalizeVenue(
      {
        // Overpass IDs aren't unique across element types (node/way/relation),
        // so the type prefix is baked into the id for a later detail re-lookup.
        id: `${el.type}/${el.id}`,
        name: tags.name || null,
        address,
        lat: el.lat ?? el.center?.lat ?? null,
        lng: el.lon ?? el.center?.lon ?? null,
        tel: tags.phone || tags['contact:phone'] || null,
        website: tags.website || tags['contact:website'] || null,
        hours: tags.opening_hours || null,
        categories: tags.amenity ? [tags.amenity] : [],
        // OSM has no price field, ever — always falls back to defaultPriceTier.
        priceTier: null,
      },
      'overpass',
      { defaultPriceTier },
    );
  });
}

async function getOverpassPlaceDetail(providerPlaceId, options) {
  const { overpassApiUrl, overpassTimeoutMs, defaultPriceTier } = options;
  const [type, id] = providerPlaceId.split('/');

  const ql = `[out:json][timeout:${Math.ceil(overpassTimeoutMs / 1000)}];
${type}(${id});
out body;`;

  const response = await fetchWithTimeout(
    overpassApiUrl,
    {
      method: 'POST',
      body: `data=${encodeURIComponent(ql)}`,
      // Overpass's public instance 406s without both of these — confirmed
      // live. Accept: Node's fetch sends none by default. User-Agent:
      // Overpass's Apache config appears to bot-block Node's default/empty
      // one; a descriptive UA is also Overpass's own usage-policy etiquette,
      // not just a technical workaround.
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        Accept: 'application/json',
        'User-Agent': 'expenseTracker-food-recommendation/1.0 (dev)',
      },
    },
    overpassTimeoutMs,
  );

  if (!response.ok) {
    throw new Error(`Overpass place detail failed (${response.status}): ${await response.text()}`);
  }

  const data = await response.json();
  const el = (data.elements || [])[0];
  if (!el) return null;

  const tags = el.tags || {};
  const address =
    tags['addr:full'] ||
    [tags['addr:housenumber'], tags['addr:street'], tags['addr:city']].filter(Boolean).join(' ') ||
    null;

  return normalizeVenue(
    {
      id: providerPlaceId,
      name: tags.name || null,
      address,
      lat: el.lat ?? el.center?.lat ?? null,
      lng: el.lon ?? el.center?.lon ?? null,
      tel: tags.phone || tags['contact:phone'] || null,
      website: tags.website || tags['contact:website'] || null,
      hours: tags.opening_hours || null,
      categories: tags.amenity ? [tags.amenity] : [],
      priceTier: null,
    },
    'overpass',
    { defaultPriceTier },
  );
}

// ---------------------------------------------------------------------
// Tier 2: Geoapify — free tier, no-ops gracefully if unconfigured.
// ---------------------------------------------------------------------
async function searchGeoapify(query, options) {
  if (!geoapifyIsConfigured) return { venues: [], status: 'unconfigured' };

  const { lat, lng, radiusM, categories, resultLimit } = query;
  const { geoapifyTimeoutMs, defaultPriceTier } = options;

  const params = new URLSearchParams({
    categories: categories.geoapify.join(','),
    filter: `circle:${lng},${lat},${radiusM}`,
    bias: `proximity:${lng},${lat}`,
    limit: String(resultLimit),
    apiKey: GEOAPIFY_API_KEY,
  });

  const response = await fetchWithTimeout(`${GEOAPIFY_BASE_URL}?${params.toString()}`, {}, geoapifyTimeoutMs);

  if (!response.ok) {
    throw new Error(`Geoapify search failed (${response.status}): ${await response.text()}`);
  }

  const data = await response.json();
  const features = data.features || [];

  const venues = features.map((f) => {
    const p = f.properties || {};
    return normalizeVenue(
      {
        id: p.place_id,
        name: p.name || null,
        distanceM: p.distance ?? null,
        address: p.formatted || null,
        lat: p.lat ?? null,
        lng: p.lon ?? null,
        tel: p.contact?.phone || p.phone || null,
        website: p.website || p.contact?.website || null,
        hours: p.opening_hours ?? null,
        categories: p.categories || [],
        // Geoapify's OSM-derived data has no standard price field either.
        priceTier: null,
      },
      'geoapify',
      { defaultPriceTier },
    );
  });

  return { venues, status: 'ok' };
}

async function getGeoapifyPlaceDetail(providerPlaceId, options) {
  if (!geoapifyIsConfigured) return null;
  const { geoapifyTimeoutMs, defaultPriceTier } = options;

  const params = new URLSearchParams({ id: providerPlaceId, apiKey: GEOAPIFY_API_KEY });
  const response = await fetchWithTimeout(`https://api.geoapify.com/v2/place-details?${params.toString()}`, {}, geoapifyTimeoutMs);

  if (!response.ok) {
    throw new Error(`Geoapify place detail failed (${response.status}): ${await response.text()}`);
  }

  const data = await response.json();
  const feature = (data.features || [])[0];
  if (!feature) return null;
  const p = feature.properties || {};

  return normalizeVenue(
    {
      id: providerPlaceId,
      name: p.name || null,
      address: p.formatted || null,
      lat: p.lat ?? null,
      lng: p.lon ?? null,
      tel: p.contact?.phone || p.phone || null,
      website: p.website || p.contact?.website || null,
      hours: p.opening_hours ?? null,
      categories: p.categories || [],
      priceTier: null,
    },
    'geoapify',
    { defaultPriceTier },
  );
}

// ---------------------------------------------------------------------
// Tier 3: Foursquare — existing integration, now taking radius/categories/
// limit/timeout as explicit fields off query/options instead of inline
// literals. Deliberately requests no extra `fields` on the detail lookup —
// the default response already includes name/location/tel/website/
// categories/price on the free tier; hours/rating/photos are Premium
// fields and are not requested (confirmed live: 402s without paid credits).
// ---------------------------------------------------------------------
async function searchFoursquare(query, options) {
  if (!fsqIsConfigured) return { venues: [], status: 'unconfigured' };

  const { lat, lng, radiusM, categories, resultLimit } = query;
  const { fsqTimeoutMs, defaultPriceTier } = options;

  const params = new URLSearchParams({
    ll: `${lat},${lng}`,
    radius: String(radiusM),
    fsq_category_ids: categories.foursquare.join(','),
    sort: 'DISTANCE',
    limit: String(resultLimit),
  });

  const response = await fetchWithTimeout(`${FSQ_BASE_URL}/search?${params.toString()}`, { headers: fsqHeaders() }, fsqTimeoutMs);

  if (!response.ok) {
    throw new Error(`Foursquare search failed (${response.status}): ${await response.text()}`);
  }

  const data = await response.json();
  const results = data.results || [];

  const venues = results.map((venue) =>
    normalizeVenue(
      {
        id: venue.fsq_place_id,
        name: venue.name,
        distanceM: venue.distance ?? null,
        address: venue.location?.formatted_address ?? null,
        lat: venue.latitude ?? null,
        lng: venue.longitude ?? null,
        priceTier: venue.price ?? null,
        tel: venue.tel ?? null,
        website: venue.website ?? null,
        categories: (venue.categories || []).map((c) => c.name),
      },
      'foursquare',
      { defaultPriceTier },
    ),
  );

  return { venues, status: 'ok' };
}

async function getFoursquarePlaceDetail(providerPlaceId, options) {
  if (!fsqIsConfigured) return null;
  const { fsqTimeoutMs, defaultPriceTier } = options;

  const response = await fetchWithTimeout(`${FSQ_BASE_URL}/${encodeURIComponent(providerPlaceId)}`, { headers: fsqHeaders() }, fsqTimeoutMs);

  if (!response.ok) {
    throw new Error(`Foursquare place details failed (${response.status}): ${await response.text()}`);
  }

  const venue = await response.json();
  return normalizeVenue(
    {
      id: venue.fsq_place_id,
      name: venue.name,
      address: venue.location?.formatted_address ?? null,
      lat: venue.latitude ?? null,
      lng: venue.longitude ?? null,
      priceTier: venue.price ?? null,
      tel: venue.tel ?? null,
      website: venue.website ?? null,
      categories: (venue.categories || []).map((c) => c.name),
    },
    'foursquare',
    { defaultPriceTier },
  );
}

// Merge-and-accumulate dedup: cross-provider IDs never collide meaningfully
// (different ID formats entirely), so "the same real venue" is detected by
// name + proximity instead. Keeps the first (higher-priority-tier) copy.
function mergeUnique(existing, incoming) {
  const merged = [...existing];
  for (const candidate of incoming) {
    const isDuplicate = existing.some(
      (v) =>
        v.name &&
        candidate.name &&
        v.name.trim().toLowerCase() === candidate.name.trim().toLowerCase() &&
        v.lat != null &&
        v.lng != null &&
        candidate.lat != null &&
        candidate.lng != null &&
        haversineQuick(v.lat, v.lng, candidate.lat, candidate.lng) < 30,
    );
    if (!isDuplicate) merged.push(candidate);
  }
  return merged;
}

// Local Haversine (rather than importing location.service.js here) keeps
// maps.js's only dependency direction downward from location.service.js,
// not circular — this is purely for de-dup distance, not the authoritative
// distanceM used for ranking/radius filtering.
function haversineQuick(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// Pipeline entrypoint: tries each tier in order, merging results into the
// running total, stopping once options.minResultThreshold is met. A
// provider that throws or is unconfigured never aborts the pipeline — it's
// recorded in providerStatus and the next tier is tried. Returns whatever
// was collected, best-available, even if no tier alone met the threshold.
exports.searchVenues = async (query, options) => {
  const tiers = [
    { name: 'overpass', run: () => searchOverpass(query, options).then((venues) => ({ venues, status: 'ok' })) },
    { name: 'geoapify', run: () => searchGeoapify(query, options) },
    { name: 'foursquare', run: () => searchFoursquare(query, options) },
  ];

  let venues = [];
  const providerStatus = {};

  for (const tier of tiers) {
    if (venues.length >= options.minResultThreshold) {
      providerStatus[tier.name] = 'skipped (threshold already met)';
      continue;
    }
    try {
      const { venues: tierVenues, status } = await tier.run();
      providerStatus[tier.name] = status;
      venues = mergeUnique(venues, tierVenues);
    } catch (err) {
      providerStatus[tier.name] = `error: ${err.message}`;
    }
  }

  return { venues, providerStatus };
};

// Single-venue lookup for the detail screen, provider-aware — dispatches to
// whichever provider originally sourced the venue.
exports.getPlaceDetails = async ({ provider, providerPlaceId }, options) => {
  switch (provider) {
    case 'overpass':
      return getOverpassPlaceDetail(providerPlaceId, options);
    case 'geoapify':
      return getGeoapifyPlaceDetail(providerPlaceId, options);
    case 'foursquare':
      return getFoursquarePlaceDetail(providerPlaceId, options);
    default:
      throw new Error(`Unknown provider: ${provider}`);
  }
};

exports.fsqIsConfigured = fsqIsConfigured;
exports.geoapifyIsConfigured = geoapifyIsConfigured;
