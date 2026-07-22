// Creates (or promotes) the administrator account described in the
// stakeholder analysis (Chapter 3.4.1) and used by FR1.7's admin-only
// endpoints (see src/routes/admin.routes.js).
//
// Credentials are never hardcoded in application logic — this script reads
// them from environment variables (see back-end/.env, which is gitignored)
// and stores only a bcrypt hash, exactly like a normal user registration
// (auth.service.js). There is no special-cased "if username === 'admin'"
// check anywhere; the account authenticates through the same login path as
// everyone else and is distinguished purely by its `role` column.
//
// Idempotent — safe to re-run. If the account already exists it is
// promoted to role='admin' and re-activated rather than duplicated.
//
// Usage:
//   cd back-end && npm run seed:admin
//   (optionally override ADMIN_USERNAME / ADMIN_EMAIL / ADMIN_PASSWORD
//   in .env first — see .env.example)

require('dotenv').config();
const bcrypt = require('bcrypt');
const db = require('../../src/config/db');

const SALT_ROUNDS = 12;

// FR1.1 — same password policy enforced at registration time.
function isValidPassword(password) {
  return (
    typeof password === 'string' &&
    password.length >= 8 &&
    /[A-Z]/.test(password) &&
    /[a-z]/.test(password) &&
    /[0-9]/.test(password)
  );
}

async function seedAdmin() {
  const username = process.env.ADMIN_USERNAME || 'admin';
  const email = process.env.ADMIN_EMAIL || 'admin@ai-expense-tracker.local';
  const password = process.env.ADMIN_PASSWORD || 'admin123';

  if (!isValidPassword(password)) {
    throw new Error(
      'ADMIN_PASSWORD must be at least 8 characters and include an uppercase letter, a lowercase letter and a number'
    );
  }

  const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);

  const existing = await db.query('SELECT user_id, role FROM users WHERE email = $1', [email]);

  if (existing.rows.length > 0) {
    const { user_id: userId, role } = existing.rows[0];
    await db.query(
      `UPDATE users
       SET username = $1, password_hash = $2, role = 'admin', is_active = TRUE,
           deactivated_at = NULL, fail_count = 0, is_locked = FALSE, locked_until = NULL
       WHERE user_id = $3`,
      [username, passwordHash, userId]
    );
    console.log(
      role === 'admin'
        ? `Admin account already existed (${email}) — credentials refreshed.`
        : `Existing account (${email}) promoted to role='admin'.`
    );
    return;
  }

  const result = await db.query(
    `INSERT INTO users (email, username, password_hash, role, is_active)
     VALUES ($1, $2, $3, 'admin', TRUE)
     RETURNING user_id, email, username, role`,
    [email, username, passwordHash]
  );
  console.log('Admin account created:', result.rows[0]);
}

// `require.main === module` — only auto-run (and exit the process) when
// invoked directly via `npm run seed:admin`. The test suite instead imports
// { seedAdmin } and awaits it in a beforeAll, so tests don't depend on that
// CLI command having been run manually first, and reseeding also resets any
// fail_count/is_locked/is_active state a previous test run may have left on
// the admin account.
if (require.main === module) {
  seedAdmin()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('Failed to seed admin account:', err.message);
      process.exit(1);
    });
}

module.exports = { seedAdmin };
