require('dotenv').config();
const request = require('supertest');
const app = require('../app');
const db = require('../src/config/db');
const { uniqueTestUser } = require('./helpers/testUser');

const createdEmails = [];

afterAll(async () => {
  // Direct DB cleanup — keeps this file's cleanup independent of the admin
  // feature under test in admin.test.js.
  if (createdEmails.length > 0) {
    await db.query('DELETE FROM users WHERE email = ANY($1)', [createdEmails]);
  }
  await db.end();
});

describe('POST /api/auth/register — FR1.1', () => {
  test('rejects a password with no uppercase letter', async () => {
    const user = uniqueTestUser('weakpw');
    const res = await request(app)
      .post('/api/auth/register')
      .send({ email: user.email, username: user.username, password: 'testpass1' });

    expect(res.status).toBe(400);
    expect(res.body.message).toMatch(/uppercase/i);
  });

  test('registers a valid account', async () => {
    const user = uniqueTestUser('register');
    const res = await request(app).post('/api/auth/register').send(user);

    expect(res.status).toBe(201);
    expect(res.body.user.email).toBe(user.email);
    createdEmails.push(user.email);
  });

  test('rejects a duplicate email', async () => {
    const user = uniqueTestUser('dup');
    await request(app).post('/api/auth/register').send(user);
    createdEmails.push(user.email);

    const res = await request(app)
      .post('/api/auth/register')
      .send({ ...user, username: 'someoneElse' });

    expect(res.status).toBe(409);
  });
});

describe('POST /api/auth/login', () => {
  test('logs in with correct credentials and returns a JWT + user role', async () => {
    const user = uniqueTestUser('login');
    await request(app).post('/api/auth/register').send(user);
    createdEmails.push(user.email);

    const res = await request(app)
      .post('/api/auth/login')
      .send({ email: user.email, password: user.password });

    expect(res.status).toBe(200);
    expect(res.body.token).toEqual(expect.any(String));
    expect(res.body.user.role).toBe('user');
  });

  test('rejects a wrong password without revealing whether the email exists', async () => {
    const user = uniqueTestUser('wrongpw');
    await request(app).post('/api/auth/register').send(user);
    createdEmails.push(user.email);

    const wrongPw = await request(app)
      .post('/api/auth/login')
      .send({ email: user.email, password: 'WrongPass9' });
    const noSuchEmail = await request(app)
      .post('/api/auth/login')
      .send({ email: 'nobody-here@jest.local', password: 'WrongPass9' });

    expect(wrongPw.status).toBe(401);
    expect(noSuchEmail.status).toBe(401);
    expect(wrongPw.body.message).toBe(noSuchEmail.body.message);
  });

  // FR1.4 — 5 consecutive failed attempts locks the account and switches
  // the response to 423, even on a subsequently-correct password.
  test('locks the account after 5 consecutive failed attempts', async () => {
    const user = uniqueTestUser('lockout');
    await request(app).post('/api/auth/register').send(user);
    createdEmails.push(user.email);

    let lastRes;
    for (let attempt = 0; attempt < 5; attempt += 1) {
      lastRes = await request(app)
        .post('/api/auth/login')
        .send({ email: user.email, password: 'WrongPass9' });
    }
    expect(lastRes.status).toBe(423);

    const correctPwAfterLock = await request(app)
      .post('/api/auth/login')
      .send({ email: user.email, password: user.password });
    expect(correctPwAfterLock.status).toBe(423);
  });
});
