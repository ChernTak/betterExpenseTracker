require('dotenv').config();
const request = require('supertest');
const app = require('../app');
const db = require('../src/config/db');
const { uniqueTestUser } = require('./helpers/testUser');

let token;
let userId;

beforeAll(async () => {
  const user = uniqueTestUser('wishlist');
  await request(app).post('/api/auth/register').send(user);
  const loginRes = await request(app)
    .post('/api/auth/login')
    .send({ email: user.email, password: user.password });
  token = loginRes.body.token;
  userId = loginRes.body.user.userId;
});

afterAll(async () => {
  await db.query('DELETE FROM users WHERE user_id = $1', [userId]);
  await db.end();
});

function auth(req) {
  return req.set('Authorization', `Bearer ${token}`);
}

describe('POST /api/wishlist/:id/convert-to-goal', () => {
  test('converts a pending item with a known cost into a funded goal', async () => {
    const createRes = await auth(request(app).post('/api/wishlist')).send({
      itemName: 'Gaming chair',
      estimatedCost: 899,
      category: 'shopping',
    });
    expect(createRes.status).toBe(201);
    const wishlistId = createRes.body.data.wishlist_id;

    const convertRes = await auth(
      request(app).post(`/api/wishlist/${wishlistId}/convert-to-goal`)
    ).send({ priority: 2 });

    expect(convertRes.status).toBe(201);
    expect(convertRes.body.data.wishlistItem.status).toBe('converted_to_goal');
    expect(convertRes.body.data.wishlistItem.goal_id).toBe(convertRes.body.data.goal.goal_id);
    expect(Number(convertRes.body.data.goal.target_amount)).toBe(899);
    expect(convertRes.body.data.goal.goal_name).toBe('Gaming chair');
    expect(Number(convertRes.body.data.goal.current_saved)).toBe(0);
    expect(convertRes.body.data.goal.status).toBe('active');
    expect(convertRes.body.data.goal.priority).toBe(2);

    // The goal must actually be queryable via the normal goals endpoint too.
    const goalsRes = await auth(request(app).get('/api/goals'));
    expect(goalsRes.body.some((g) => g.goal_id === convertRes.body.data.goal.goal_id)).toBe(true);
  });

  test('rejects converting an item with no cost and no targetAmount override', async () => {
    const createRes = await auth(request(app).post('/api/wishlist')).send({
      itemName: 'Mystery item',
    });
    const wishlistId = createRes.body.data.wishlist_id;

    const convertRes = await auth(
      request(app).post(`/api/wishlist/${wishlistId}/convert-to-goal`)
    ).send({});

    expect(convertRes.status).toBe(400);
    expect(convertRes.body.message).toMatch(/estimated cost|targetAmount/i);
  });

  test('accepts a targetAmount override for an item with no cost', async () => {
    const createRes = await auth(request(app).post('/api/wishlist')).send({
      itemName: 'Mystery item 2',
    });
    const wishlistId = createRes.body.data.wishlist_id;

    const convertRes = await auth(
      request(app).post(`/api/wishlist/${wishlistId}/convert-to-goal`)
    ).send({ targetAmount: 250 });

    expect(convertRes.status).toBe(201);
    expect(Number(convertRes.body.data.goal.target_amount)).toBe(250);
  });

  test('rejects a non-positive targetAmount', async () => {
    const createRes = await auth(request(app).post('/api/wishlist')).send({
      itemName: 'Bad amount item',
    });
    const wishlistId = createRes.body.data.wishlist_id;

    const convertRes = await auth(
      request(app).post(`/api/wishlist/${wishlistId}/convert-to-goal`)
    ).send({ targetAmount: -5 });

    expect(convertRes.status).toBe(400);
  });

  test('returns 409 when converting an already-resolved item', async () => {
    const createRes = await auth(request(app).post('/api/wishlist')).send({
      itemName: 'Double convert test',
      estimatedCost: 100,
    });
    const wishlistId = createRes.body.data.wishlist_id;

    const first = await auth(request(app).post(`/api/wishlist/${wishlistId}/convert-to-goal`)).send({});
    expect(first.status).toBe(201);

    const second = await auth(request(app).post(`/api/wishlist/${wishlistId}/convert-to-goal`)).send({});
    expect(second.status).toBe(409);
  });

  test('returns 404 for a nonexistent wishlist item', async () => {
    const res = await auth(
      request(app).post('/api/wishlist/00000000-0000-0000-0000-000000000000/convert-to-goal')
    ).send({});
    expect(res.status).toBe(404);
  });

  test('rejects setting status=converted_to_goal directly through the plain update endpoint', async () => {
    const createRes = await auth(request(app).post('/api/wishlist')).send({
      itemName: 'Bypass attempt',
      estimatedCost: 50,
    });
    const wishlistId = createRes.body.data.wishlist_id;

    const res = await auth(request(app).put(`/api/wishlist/${wishlistId}`)).send({
      status: 'converted_to_goal',
    });
    expect(res.status).toBe(400);
  });

  test('converted items are still visible via GET /api/wishlist?status=converted_to_goal', async () => {
    const createRes = await auth(request(app).post('/api/wishlist')).send({
      itemName: 'Listable after conversion',
      estimatedCost: 60,
    });
    const wishlistId = createRes.body.data.wishlist_id;
    await auth(request(app).post(`/api/wishlist/${wishlistId}/convert-to-goal`)).send({});

    const listRes = await auth(request(app).get('/api/wishlist?status=converted_to_goal'));
    expect(listRes.status).toBe(200);
    expect(listRes.body.some((item) => item.wishlist_id === wishlistId)).toBe(true);
  });
});

describe('PUT /api/wishlist/:id (mark as bought)', () => {
  test('blocks marking bought before the cooling-off delay has passed', async () => {
    const createRes = await auth(request(app).post('/api/wishlist')).send({
      itemName: 'Gaming chair',
      estimatedCost: 899,
      category: 'shopping',
      delayDays: 3,
    });
    const wishlistId = createRes.body.data.wishlist_id;

    const res = await auth(request(app).put(`/api/wishlist/${wishlistId}`)).send({
      status: 'purchased',
    });

    expect(res.status).toBe(409);
    expect(res.body.message).toMatch(/delayed until/i);

    const stillPendingRes = await auth(request(app).get('/api/wishlist?status=pending'));
    expect(stillPendingRes.body.some((item) => item.wishlist_id === wishlistId)).toBe(true);
  });

  test('creates a matching expense and links it once the delay has passed', async () => {
    const createRes = await auth(request(app).post('/api/wishlist')).send({
      itemName: 'Wireless earbuds',
      estimatedCost: 249,
      category: 'shopping',
      merchantName: 'Tech Store',
      delayDays: 3,
    });
    const wishlistId = createRes.body.data.wishlist_id;

    // Backdate the delay so it's already elapsed, same as if the 3 days had
    // actually passed — there's no test hook to fast-forward server time.
    await db.query('UPDATE wishlist SET delay_until_date = CURRENT_DATE - 1 WHERE wishlist_id = $1', [
      wishlistId,
    ]);

    const res = await auth(request(app).put(`/api/wishlist/${wishlistId}`)).send({
      status: 'purchased',
    });

    expect(res.status).toBe(200);
    expect(res.body.data.wishlistItem.status).toBe('purchased');
    expect(res.body.data.wishlistItem.expense_id).toBe(res.body.data.expense.expense_id);
    expect(Number(res.body.data.expense.amount)).toBe(249);
    expect(res.body.data.expense.category).toBe('shopping');
    expect(res.body.data.expense.merchant_name).toBe('Tech Store');
  });

  test('marking bought with no delay set at all succeeds immediately', async () => {
    const createRes = await auth(request(app).post('/api/wishlist')).send({
      itemName: 'Impulse-free buy',
      estimatedCost: 40,
      category: 'shopping',
    });
    const wishlistId = createRes.body.data.wishlist_id;

    const res = await auth(request(app).put(`/api/wishlist/${wishlistId}`)).send({
      status: 'purchased',
    });

    expect(res.status).toBe(200);
    expect(res.body.data.wishlistItem.status).toBe('purchased');
  });

  test('rejects marking bought when the item has no estimated cost or category', async () => {
    const createRes = await auth(request(app).post('/api/wishlist')).send({
      itemName: 'Mystery item 3',
    });
    const wishlistId = createRes.body.data.wishlist_id;

    const res = await auth(request(app).put(`/api/wishlist/${wishlistId}`)).send({
      status: 'purchased',
    });

    expect(res.status).toBe(400);
    expect(res.body.message).toMatch(/cost|category/i);
  });

  test('rejects marking bought when the item has a cost but no category', async () => {
    const createRes = await auth(request(app).post('/api/wishlist')).send({
      itemName: 'Cost but no category',
      estimatedCost: 30,
    });
    const wishlistId = createRes.body.data.wishlist_id;

    const res = await auth(request(app).put(`/api/wishlist/${wishlistId}`)).send({
      status: 'purchased',
    });

    expect(res.status).toBe(400);
  });

  test('returns 409 when marking an already-resolved item as bought', async () => {
    const createRes = await auth(request(app).post('/api/wishlist')).send({
      itemName: 'Double purchase test',
      estimatedCost: 20,
      category: 'shopping',
    });
    const wishlistId = createRes.body.data.wishlist_id;

    const first = await auth(request(app).put(`/api/wishlist/${wishlistId}`)).send({ status: 'purchased' });
    expect(first.status).toBe(200);

    const second = await auth(request(app).put(`/api/wishlist/${wishlistId}`)).send({ status: 'purchased' });
    expect(second.status).toBe(409);
  });

  test('returns 404 when marking a nonexistent wishlist item as bought', async () => {
    const res = await auth(
      request(app).put('/api/wishlist/00000000-0000-0000-0000-000000000000')
    ).send({ status: 'purchased' });
    expect(res.status).toBe(404);
  });
});
