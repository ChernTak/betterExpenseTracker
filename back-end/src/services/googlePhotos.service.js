// Photo enrichment for food recommendation venues. New Places API (v1) is
// primary; the legacy Find Place/Place Photo API is an automatic fallback.
//
// Why both exist: the New API's `photos` field came back completely empty
// on every request tried during initial implementation (confirmed 4
// different ways — Place Details and Search, header and query-param field
// masks), even though every other requested field worked fine. It started
// working again later the same session with no code change on our side —
// almost certainly a billing-SKU propagation delay on Google's end, not
// anything actually wrong with the request. Since that failure mode is
// outside our control and could recur, the legacy path (proven working
// throughout) stays as a live fallback rather than being deleted.
//
// The two APIs use incompatible photo reference formats and different
// media endpoints, so every reference this module hands back is tagged
// with which API produced it — callers (recommendation.service.js) must
// carry that tag alongside the reference (see venue_cache.photo_api) so
// fetchPhotoBytes later knows which endpoint to call.

const GOOGLE_MAPS_API_KEY = process.env.GOOGLE_MAPS_API_KEY;
const NEW_API_SEARCH_URL = 'https://places.googleapis.com/v1/places:searchText';
const NEW_API_MEDIA_BASE = 'https://places.googleapis.com/v1';
const LEGACY_FIND_PLACE_URL = 'https://maps.googleapis.com/maps/api/place/findplacefromtext/json';
const LEGACY_PHOTO_URL = 'https://maps.googleapis.com/maps/api/place/photo';

const isConfigured = Boolean(GOOGLE_MAPS_API_KEY);

if (!isConfigured) {
  console.log('[DEV] GOOGLE_MAPS_API_KEY not set — venue photo enrichment will be skipped.');
}

async function fetchWithTimeout(url, fetchOptions, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...fetchOptions, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

async function findPhotoReferenceNewApi({ name, lat, lng }, { radiusM, timeoutMs }) {
  const response = await fetchWithTimeout(
    NEW_API_SEARCH_URL,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': GOOGLE_MAPS_API_KEY,
        'X-Goog-FieldMask': 'places.photos',
      },
      body: JSON.stringify({
        textQuery: name,
        locationBias: { circle: { center: { latitude: lat, longitude: lng }, radius: radiusM } },
      }),
    },
    timeoutMs,
  );

  if (!response.ok) return null;

  const data = await response.json();
  const photoName = data.places?.[0]?.photos?.[0]?.name;
  return photoName ?? null;
}

async function findPhotoReferenceLegacy({ name, lat, lng }, { radiusM, timeoutMs }) {
  const params = new URLSearchParams({
    input: name,
    inputtype: 'textquery',
    locationbias: `circle:${radiusM}@${lat},${lng}`,
    fields: 'photos',
    key: GOOGLE_MAPS_API_KEY,
  });

  const response = await fetchWithTimeout(`${LEGACY_FIND_PLACE_URL}?${params.toString()}`, {}, timeoutMs);
  if (!response.ok) return null;

  const data = await response.json();
  if (data.status !== 'OK') return null;

  return data.candidates?.[0]?.photos?.[0]?.photo_reference ?? null;
}

// Looks up a venue by name near a point and returns { reference, api }, or
// null if unconfigured, no match anywhere, or the match has no photos.
// Never throws — a photo lookup failing shouldn't break the recommendation
// list it's enriching. Tries the New API first, falls back to the legacy
// API on any failure (network error, timeout, or a "200 OK but no photo"
// response — the exact symptom seen when the New API's field was empty).
exports.findPhotoReference = async ({ name, lat, lng }, options) => {
  if (!isConfigured || !name) return null;

  try {
    const reference = await findPhotoReferenceNewApi({ name, lat, lng }, options);
    if (reference) return { reference, api: 'new' };
  } catch (err) {
    console.error(`Google photo lookup (New API) failed for "${name}"`, err.message);
  }

  try {
    const reference = await findPhotoReferenceLegacy({ name, lat, lng }, options);
    if (reference) return { reference, api: 'legacy' };
  } catch (err) {
    console.error(`Google photo lookup (legacy API) failed for "${name}"`, err.message);
  }

  return null;
};

// Fetches the actual photo bytes for a { reference, api } pair, dispatched
// to whichever media endpoint matches. `fetch` follows both APIs'
// redirects automatically. Returns { buffer, contentType } or null so the
// route can 404 cleanly instead of proxying an error page.
exports.fetchPhotoBytes = async ({ reference, api }, { maxWidth, timeoutMs }) => {
  if (!isConfigured) return null;

  try {
    const url =
      api === 'new'
        ? `${NEW_API_MEDIA_BASE}/${reference}/media?${new URLSearchParams({ maxWidthPx: String(maxWidth), key: GOOGLE_MAPS_API_KEY }).toString()}`
        : `${LEGACY_PHOTO_URL}?${new URLSearchParams({ maxwidth: String(maxWidth), photo_reference: reference, key: GOOGLE_MAPS_API_KEY }).toString()}`;

    const response = await fetchWithTimeout(url, {}, timeoutMs);
    if (!response.ok) return null;

    const contentType = response.headers.get('content-type') || 'image/jpeg';
    const buffer = Buffer.from(await response.arrayBuffer());
    return { buffer, contentType };
  } catch (err) {
    console.error('Google photo fetch failed', err.message);
    return null;
  }
};

exports.isConfigured = isConfigured;
