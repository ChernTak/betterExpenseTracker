require('dotenv').config();
const request = require('supertest');
const app = require('../app');
const db = require('../src/config/db');
const { uniqueTestUser } = require('./helpers/testUser');

let token;
let userId;

beforeAll(async () => {
  const user = uniqueTestUser('dashboard');
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

describe('GET /api/budgets — Available to spend', () => {
  test('is null when no income has been logged this month', async () => {
    const res = await auth(request(app).get('/api/budgets'));
    expect(res.status).toBe(200);
    expect(res.body.totalIncome).toBe(0);
    expect(res.body.availableToSpend).toBeNull();
  });

  test('reflects real income, goal contributions, and spending — including an unbudgeted category', async () => {
    // Income this month
    await auth(request(app).post('/api/income')).send({ amount: 3000, source: 'Salary' });

    // A goal contribution — money that should no longer read as spendable
    const goalRes = await auth(request(app).post('/api/goals')).send({
      goalName: 'Emergency Fund',
      targetAmount: 5000,
    });
    const goalId = goalRes.body.data.goal_id;
    await auth(request(app).post(`/api/goals/${goalId}/contributions`)).send({ amount: 500 });

    // An expense in 'shopping' — deliberately NOT setting a budget for this
    // category, to prove totalSpentThisMonth (unlike the old budget-scoped
    // totalSpent) still counts it.
    const expenseRes = await auth(request(app).post('/api/expenses/post')).send({
      amount: 200,
      category: 'shopping',
    });
    expect(expenseRes.status).toBe(201);

    const res = await auth(request(app).get('/api/budgets'));
    expect(res.status).toBe(200);
    expect(res.body.totalIncome).toBe(3000);
    expect(res.body.goalContributionsThisMonth).toBe(500);
    expect(res.body.totalSpentThisMonth).toBe(200);
    // The old budget-scoped totalSpent should NOT include this expense,
    // since 'shopping' has no budget row set for this user this month —
    // confirming totalSpentThisMonth is a genuinely different, more complete figure.
    expect(res.body.totalSpent).toBe(0);
    expect(res.body.availableToSpend).toBe(3000 - 500 - 200);
  });
});
