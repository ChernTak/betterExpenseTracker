// Populates high_risk_locations (040_high_risk_locations.sql) from the
// public Overpass API (OpenStreetMap) — free, no API key, unlike Google
// Places which would need the existing GOOGLE_MAPS_API_KEY and its billing.
// Run once (or re-run to refresh) rather than querying Overpass at request
// time, so GET /api/nudge/high-risk-locations stays fast and doesn't depend
// on a third-party service being up.
//
// Usage:
//   cd back-end && npm run seed:locations

require('dotenv').config();
const db = require('../../src/config/db');

const OVERPASS_URL = 'https://overpass-api.de/api/interpreter';

// Klang Valley bounding box (south, west, north, east) — covers KL and the
// surrounding shopping districts the thesis's Malaysian user base is drawn
// from (Bukit Bintang, KLCC, Mid Valley, etc.).
const BBOX = '2.95,101.55,3.25,101.80';

const DEFAULT_RADIUS_METERS = 150;

function buildQuery() {
  return `
    [out:json][timeout:25];
    (
      node["shop"="mall"](${BBOX});
      node["shop"="department_store"](${BBOX});
      way["shop"="mall"](${BBOX});
      way["shop"="department_store"](${BBOX});
    );
    out center;
  `;
}

// Overpass returns lat/lon directly on nodes, but only a `center` object on
// ways (a mall is often mapped as a building outline, not a single point).
function extractCoords(element) {
  if (element.type === 'node') return { lat: element.lat, lon: element.lon };
  if (element.center) return { lat: element.center.lat, lon: element.center.lon };
  return null;
}

async function seedHighRiskLocations() {
  // Overpass's server returns 406 for requests without a descriptive
  // User-Agent (Node's default fetch User-Agent gets treated as a bot) —
  // https://wiki.openstreetmap.org/wiki/Overpass_API asks heavy/scripted
  // clients to identify themselves.
  const response = await fetch(OVERPASS_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'text/plain',
      'User-Agent': 'ai-expense-tracker-fyp-seed-script/1.0',
    },
    body: buildQuery(),
  });

  if (!response.ok) {
    throw new Error(`Overpass API request failed: ${response.status} ${response.statusText}`);
  }

  const { elements } = await response.json();
  let inserted = 0;
  let skipped = 0;

  // Safe to re-run: OSM nodes have no stable local key to upsert on, so a
  // refresh just replaces the previous Overpass-sourced batch wholesale
  // rather than risking duplicates. Any manually-added rows (source !=
  // 'overpass') are left untouched.
  await db.query("DELETE FROM high_risk_locations WHERE source = 'overpass'");

  for (const element of elements) {
    const name = element.tags?.name;
    const coords = extractCoords(element);
    if (!name || !coords) {
      skipped += 1;
      continue;
    }

    await db.query(
      `INSERT INTO high_risk_locations (name, latitude, longitude, radius_meters, source)
       VALUES ($1, $2, $3, $4, 'overpass')`,
      [name, coords.lat, coords.lon, DEFAULT_RADIUS_METERS],
    );
    inserted += 1;
  }

  console.log(`Seeded ${inserted} high-risk location(s), skipped ${skipped} unnamed/incomplete result(s).`);
}

if (require.main === module) {
  seedHighRiskLocations()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('Failed to seed high-risk locations:', err.message);
      process.exit(1);
    });
}

module.exports = { seedHighRiskLocations };
