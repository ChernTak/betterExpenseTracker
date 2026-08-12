require('dotenv').config();
const request = require('supertest');
const app = require('../app');
const db = require('../src/config/db');
const { seedAdmin } = require('../database/seeds/seed_admin');
const { uniqueTestUser } = require('./helpers/testUser');

let adminToken;
let adminUserId;

beforeAll(async () => {
  // Ensures the admin account exists (and resets any lock/deactivation state
  // left over from a previous run) regardless of whether `npm run seed:admin`
  // was run manually first.
  await seedAdmin();

  const loginRes = await request(app)
    .post('/api/auth/login')
    .send({ email: process.env.ADMIN_EMAIL, password: process.env.ADMIN_PASSWORD });

  if (loginRes.status !== 200) {
    throw new Error(
      `Could not log in as the seeded admin account (status ${loginRes.status}): ${JSON.stringify(loginRes.body)}`
    );
  }
  adminToken = loginRes.body.token;
  adminUserId = loginRes.body.user.userId;
});

afterAll(async () => {
  await db.end();
});

describe('NFR 3.4 — role-based access control on /api/admin', () => {
  test('rejects requests with no token', async () => {
    const res = await request(app).get('/api/admin/users');
    expect(res.status).toBe(401);
  });

  test('rejects a valid token belonging to a non-admin user', async () => {
    const user = uniqueTestUser('rbac');
    await request(app).post('/api/auth/register').send(user);
    const loginRes = await request(app)
      .post('/api/auth/login')
      .send({ email: user.email, password: user.password });

    const res = await request(app)
      .get('/api/admin/users')
      .set('Authorization', `Bearer ${loginRes.body.token}`);

    expect(res.status).toBe(403);

    await db.query('DELETE FROM users WHERE email = $1', [user.email]);
  });
});

describe('FR1.7 — admin account management', () => {
  let targetUser;
  let targetUserId;

  beforeEach(async () => {
    targetUser = uniqueTestUser('managed');
    const registerRes = await request(app).post('/api/auth/register').send(targetUser);
    targetUserId = registerRes.body.user.user_id;
  });

  afterEach(async () => {
    // Belt-and-braces cleanup in case a test fails before reaching its own
    // delete assertion — never leaves throwaway accounts in the dev DB.
    await db.query('DELETE FROM users WHERE email = $1', [targetUser.email]);
  });

  test('lists users, excluding password_hash', async () => {
    const res = await request(app).get('/api/admin/users').set('Authorization', `Bearer ${adminToken}`);

    expect(res.status).toBe(200);
    const emails = res.body.users.map((u) => u.email);
    expect(emails).toContain(targetUser.email);
    expect(emails).toContain(process.env.ADMIN_EMAIL);
    expect(res.body.users[0]).not.toHaveProperty('password_hash');
  });

  test('PDPA data-minimization — list view masks mobile_number, detail view does not, and viewing is audit-logged', async () => {
    await db.query('UPDATE users SET mobile_number = $1 WHERE user_id = $2', ['0123456789', targetUserId]);

    const listRes = await request(app).get('/api/admin/users').set('Authorization', `Bearer ${adminToken}`);
    const listedUser = listRes.body.users.find((u) => u.user_id === targetUserId);
    expect(listedUser.mobile_number).not.toBe('0123456789');
    expect(listedUser.mobile_number.endsWith('89')).toBe(true);

    const detailRes = await request(app)
      .get(`/api/admin/users/${targetUserId}`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(detailRes.body.user.mobile_number).toBe('0123456789');

    const auditRes = await request(app).get('/api/admin/audit-log').set('Authorization', `Bearer ${adminToken}`);
    const viewEntry = auditRes.body.auditLog.find(
      (e) => e.action === 'view_profile' && e.target_user_id === targetUserId
    );
    expect(viewEntry).toBeTruthy();
  });

  test('deactivates a user, blocking their login, then reactivates them', async () => {
    const deactivateRes = await request(app)
      .patch(`/api/admin/users/${targetUserId}/deactivate`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(deactivateRes.status).toBe(200);
    expect(deactivateRes.body.user.is_active).toBe(false);

    const blockedLogin = await request(app)
      .post('/api/auth/login')
      .send({ email: targetUser.email, password: targetUser.password });
    expect(blockedLogin.status).toBe(403);

    const reactivateRes = await request(app)
      .patch(`/api/admin/users/${targetUserId}/reactivate`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(reactivateRes.status).toBe(200);
    expect(reactivateRes.body.user.is_active).toBe(true);

    const restoredLogin = await request(app)
      .post('/api/auth/login')
      .send({ email: targetUser.email, password: targetUser.password });
    expect(restoredLogin.status).toBe(200);
  });

  test('delete request soft-deletes with a grace period, then purge hard-deletes (PDPA erasure with a recoverability window)', async () => {
    const deleteRes = await request(app)
      .delete(`/api/admin/users/${targetUserId}`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(deleteRes.status).toBe(200);
    expect(deleteRes.body.user.is_active).toBe(false);
    expect(deleteRes.body.user.deletion_requested_at).toBeTruthy();

    // Still present (soft-deleted, not gone) until the grace period elapses.
    const listRes = await request(app).get('/api/admin/users').set('Authorization', `Bearer ${adminToken}`);
    expect(listRes.body.users.map((u) => u.email)).toContain(targetUser.email);

    const purgeTooSoon = await request(app)
      .delete(`/api/admin/users/${targetUserId}/purge`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(purgeTooSoon.status).toBe(400);

    const forcedPurge = await request(app)
      .delete(`/api/admin/users/${targetUserId}/purge?force=true`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(forcedPurge.status).toBe(200);

    const listAfterPurge = await request(app).get('/api/admin/users').set('Authorization', `Bearer ${adminToken}`);
    expect(listAfterPurge.body.users.map((u) => u.email)).not.toContain(targetUser.email);

    const secondPurge = await request(app)
      .delete(`/api/admin/users/${targetUserId}/purge?force=true`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(secondPurge.status).toBe(404);

    const auditRes = await request(app).get('/api/admin/audit-log').set('Authorization', `Bearer ${adminToken}`);
    const purgeEntry = auditRes.body.auditLog.find(
      (e) => e.action === 'purge_user' && e.target_email === targetUser.email
    );
    expect(purgeEntry).toBeTruthy();
    expect(purgeEntry.target_user_id).toBeNull();
  });

  test('cancel-deletion reverses a pending deletion request within the grace window', async () => {
    await request(app).delete(`/api/admin/users/${targetUserId}`).set('Authorization', `Bearer ${adminToken}`);

    const cancelRes = await request(app)
      .patch(`/api/admin/users/${targetUserId}/cancel-deletion`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(cancelRes.status).toBe(200);
    expect(cancelRes.body.user.is_active).toBe(true);
    expect(cancelRes.body.user.deletion_requested_at).toBeNull();

    const purgeRes = await request(app)
      .delete(`/api/admin/users/${targetUserId}/purge?force=true`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(purgeRes.status).toBe(400);

    const restoredLogin = await request(app)
      .post('/api/auth/login')
      .send({ email: targetUser.email, password: targetUser.password });
    expect(restoredLogin.status).toBe(200);
  });

  test('exports a user\'s full data footprint for a DSAR (PDPA Access)', async () => {
    const exportRes = await request(app)
      .get(`/api/admin/users/${targetUserId}/export`)
      .set('Authorization', `Bearer ${adminToken}`);

    expect(exportRes.status).toBe(200);
    expect(exportRes.body.profile.email).toBe(targetUser.email);
    expect(exportRes.body.profile).not.toHaveProperty('password_hash');
    expect(Array.isArray(exportRes.body.expenses)).toBe(true);
    expect(Array.isArray(exportRes.body.consentHistory)).toBe(true);

    const auditRes = await request(app).get('/api/admin/audit-log').set('Authorization', `Bearer ${adminToken}`);
    const exportEntry = auditRes.body.auditLog.find(
      (e) => e.action === 'export_data' && e.target_user_id === targetUserId
    );
    expect(exportEntry).toBeTruthy();
  });

  test('an admin cannot deactivate or delete their own account', async () => {
    const deactivateSelf = await request(app)
      .patch(`/api/admin/users/${adminUserId}/deactivate`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(deactivateSelf.status).toBe(400);

    const deleteSelf = await request(app)
      .delete(`/api/admin/users/${adminUserId}`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(deleteSelf.status).toBe(400);

    const purgeSelf = await request(app)
      .delete(`/api/admin/users/${adminUserId}/purge?force=true`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(purgeSelf.status).toBe(400);

    // Confirm the guard actually left the admin account untouched.
    const stillWorks = await request(app)
      .post('/api/auth/login')
      .send({ email: process.env.ADMIN_EMAIL, password: process.env.ADMIN_PASSWORD });
    expect(stillWorks.status).toBe(200);
  });
});

describe('PDPA data-minimization — recommendation_log retention purge', () => {
  test('purges recommendation_log rows older than the given threshold and is audit-logged', async () => {
    const user = uniqueTestUser('recloc');
    const registerRes = await request(app).post('/api/auth/register').send(user);
    const userId = registerRes.body.user.user_id;

    await db.query(
      `INSERT INTO recommendation_log (user_id, rec_type, rec_title, rec_body, context_snapshot, generated_at)
       VALUES ($1, 'food_recommendation', 'test', 'test body', '{"lat": 3.1, "lng": 101.6}', NOW() - INTERVAL '10 days')`,
      [userId]
    );

    const purgeRes = await request(app)
      .delete('/api/admin/recommendation-logs/purge?olderThanDays=1')
      .set('Authorization', `Bearer ${adminToken}`);
    expect(purgeRes.status).toBe(200);
    expect(purgeRes.body.deletedCount).toBeGreaterThanOrEqual(1);

    const remaining = await db.query('SELECT * FROM recommendation_log WHERE user_id = $1', [userId]);
    expect(remaining.rows.length).toBe(0);

    const auditRes = await request(app).get('/api/admin/audit-log').set('Authorization', `Bearer ${adminToken}`);
    const purgeEntry = auditRes.body.auditLog.find((e) => e.action === 'purge_recommendation_logs');
    expect(purgeEntry).toBeTruthy();

    await db.query('DELETE FROM users WHERE email = $1', [user.email]);
  });
});

describe('PDPA storage-limitation — stale guest account purge', () => {
  const backdate = (userId, days) =>
    db.query(`UPDATE users SET created_at = NOW() - INTERVAL '${days} days' WHERE user_id = $1`, [userId]);

  test('purges a guest inactive past the threshold, spares an active guest and a backdated non-guest, and is audit-logged', async () => {
    const staleGuestRes = await request(app).post('/api/auth/guest').send({});
    const staleGuestId = staleGuestRes.body.user.userId;
    await backdate(staleGuestId, 40);

    const activeGuestRes = await request(app).post('/api/auth/guest').send({});
    const activeGuestId = activeGuestRes.body.user.userId;
    await backdate(activeGuestId, 40);
    await db.query(
      `INSERT INTO expenses (user_id, amount, category, transaction_date, created_at)
       VALUES ($1, 12.50, 'food_dining', CURRENT_DATE, NOW())`,
      [activeGuestId]
    );

    const nonGuest = uniqueTestUser('oldreal');
    const registerRes = await request(app).post('/api/auth/register').send(nonGuest);
    const nonGuestId = registerRes.body.user.user_id;
    await backdate(nonGuestId, 40);

    const purgeRes = await request(app)
      .delete('/api/admin/guests/purge?olderThanDays=30')
      .set('Authorization', `Bearer ${adminToken}`);
    expect(purgeRes.status).toBe(200);
    expect(purgeRes.body.deletedCount).toBeGreaterThanOrEqual(1);

    const staleStillThere = await db.query('SELECT 1 FROM users WHERE user_id = $1', [staleGuestId]);
    expect(staleStillThere.rows.length).toBe(0);

    const activeStillThere = await db.query('SELECT 1 FROM users WHERE user_id = $1', [activeGuestId]);
    expect(activeStillThere.rows.length).toBe(1);

    const nonGuestStillThere = await db.query('SELECT 1 FROM users WHERE user_id = $1', [nonGuestId]);
    expect(nonGuestStillThere.rows.length).toBe(1);

    const auditRes = await request(app).get('/api/admin/audit-log').set('Authorization', `Bearer ${adminToken}`);
    const purgeEntry = auditRes.body.auditLog.find((e) => e.action === 'purge_stale_guests');
    expect(purgeEntry).toBeTruthy();
    expect(purgeEntry.details.purgedEmails).toContain(staleGuestRes.body.user.email);

    await db.query('DELETE FROM users WHERE user_id IN ($1, $2)', [activeGuestId, nonGuestId]);
  });
});
