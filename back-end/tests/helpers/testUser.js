const crypto = require('crypto');

// Same disposable-account pattern as authService.guestLogin (see
// src/services/auth.service.js) — a unique email per call so repeated test
// runs never collide with a previous run's leftover data, and each test
// gets an isolated user to mutate.
function uniqueTestUser(prefix = 'test') {
  const suffix = crypto.randomBytes(6).toString('hex');
  return {
    email: `${prefix}_${suffix}@jest.local`,
    username: `${prefix}${suffix.slice(0, 6)}`,
    // Meets FR1.1: 8+ chars, upper, lower, number
    password: 'Testpass1',
  };
}

module.exports = { uniqueTestUser };
