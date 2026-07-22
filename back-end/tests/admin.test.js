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

  test('permanently deletes a user (PDPA data-deletion)', async () => {
    const deleteRes = await request(app)
      .delete(`/api/admin/users/${targetUserId}`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(deleteRes.status).toBe(200);

    const listRes = await request(app).get('/api/admin/users').set('Authorization', `Bearer ${adminToken}`);
    expect(listRes.body.users.map((u) => u.email)).not.toContain(targetUser.email);

    const secondDelete = await request(app)
      .delete(`/api/admin/users/${targetUserId}`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(secondDelete.status).toBe(404);
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

    // Confirm the guard actually left the admin account untouched.
    const stillWorks = await request(app)
      .post('/api/auth/login')
      .send({ email: process.env.ADMIN_EMAIL, password: process.env.ADMIN_PASSWORD });
    expect(stillWorks.status).toBe(200);
  });
});
