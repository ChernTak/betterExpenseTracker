// New Places API is primary; legacy API stays as an automatic fallback since New API's `photos` field has intermittently come back empty (likely a Google billing-SKU delay), and each reference is tagged with which API produced it since the two use incompatible formats.

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

// Never throws — a photo lookup failing shouldn't break the recommendation list it's enriching.
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

// Returns { buffer, contentType } or null so the route can 404 cleanly instead of proxying an error page.
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
