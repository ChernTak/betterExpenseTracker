require('dotenv').config();
const request = require('supertest');
const app = require('../app');
const db = require('../src/config/db');
const { uniqueTestUser } = require('./helpers/testUser');

let token;
let userId;
let locationId;

beforeAll(async () => {
  const user = uniqueTestUser('nudge');
  await request(app).post('/api/auth/register').send(user);
  const loginRes = await request(app)
    .post('/api/auth/login')
    .send({ email: user.email, password: user.password });
  token = loginRes.body.token;
  userId = loginRes.body.user.userId;

  // high_risk_locations is shared reference data normally populated by
  // seed_high_risk_locations.js — inserted directly here so this test suite
  // doesn't depend on that (network-dependent) seed having been run.
  const locationRes = await db.query(
    `INSERT INTO high_risk_locations (name, latitude, longitude, radius_meters, source)
     VALUES ('Test Mall', 3.146, 101.711, 150, 'test')
     RETURNING location_id`,
  );
  locationId = locationRes.rows[0].location_id;
});

afterAll(async () => {
  await db.query('DELETE FROM high_risk_locations WHERE location_id = $1', [locationId]);
  await db.query('DELETE FROM users WHERE user_id = $1', [userId]);
  await db.end();
});

function auth(req) {
  return req.set('Authorization', `Bearer ${token}`);
}

describe('GET /api/nudge/high-risk-locations', () => {
  test('returns the seeded location', async () => {
    const res = await auth(request(app).get('/api/nudge/high-risk-locations'));
    expect(res.status).toBe(200);
    expect(res.body.some((loc) => loc.location_id === locationId)).toBe(true);
  });

  test('rejects unauthenticated requests', async () => {
    const res = await request(app).get('/api/nudge/high-risk-locations');
    expect(res.status).toBe(401);
  });
});

describe('POST /api/nudge/location-entered', () => {
  test('requires locationId', async () => {
    const res = await auth(request(app).post('/api/nudge/location-entered')).send({});
    expect(res.status).toBe(400);
  });

  test('returns a no-op response for an unknown locationId', async () => {
    const res = await auth(request(app).post('/api/nudge/location-entered')).send({
      locationId: '00000000-0000-0000-0000-000000000000',
    });
    expect(res.status).toBe(200);
  });

  test('creates a location_nudge alert on first entry, then dedupes same-day repeats', async () => {
    const first = await auth(request(app).post('/api/nudge/location-entered')).send({ locationId });
    expect(first.status).toBe(201);
    expect(first.body.data.location.location_id).toBe(locationId);

    const alertRes = await db.query(
      "SELECT * FROM behavioral_alerts WHERE user_id = $1 AND location_id = $2 AND alert_type = 'location_nudge'",
      [userId, locationId],
    );
    expect(alertRes.rows.length).toBe(1);
    expect(alertRes.rows[0].message).toMatch(/Test Mall/);

    const second = await auth(request(app).post('/api/nudge/location-entered')).send({ locationId });
    expect(second.status).toBe(200);
    expect(second.body.message).toMatch(/no nudge sent/i);

    const alertResAfter = await db.query(
      "SELECT * FROM behavioral_alerts WHERE user_id = $1 AND location_id = $2 AND alert_type = 'location_nudge'",
      [userId, locationId],
    );
    expect(alertResAfter.rows.length).toBe(1); // still just the one from the first call
  });
});
