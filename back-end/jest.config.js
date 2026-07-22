module.exports = {
  testEnvironment: 'node',
  testMatch: ['**/tests/**/*.test.js'],
  // bcrypt hashing (SALT_ROUNDS=12) and the FR1.4 lockout test's 5 sequential
  // login attempts are each individually fast but add up.
  testTimeout: 20000,
  // These tests hit the real local Postgres instance (see back-end/.env) —
  // there's no separate test DB/mock layer, matching how the rest of this
  // project already runs. --runInBand (see package.json) keeps them
  // sequential so account-lockout/deactivation state doesn't race.
  forceExit: true,
};
