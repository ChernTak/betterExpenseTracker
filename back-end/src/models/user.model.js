const db = require('../config/db');

exports.findByEmail = (email) => {
  return db.query('SELECT * FROM users WHERE email = $1', [email]);
};

exports.findById = (userId) => {
  return db.query('SELECT * FROM users WHERE user_id = $1', [userId]);
};

exports.createUser = ({ email, username, passwordHash, mobileNumber }) => {
  const query = `
    INSERT INTO users (email, username, password_hash, mobile_number)
    VALUES ($1, $2, $3, $4)
    RETURNING user_id, email, username, mobile_number, created_at
  `;
  return db.query(query, [email, username, passwordHash, mobileNumber || null]);
};

// "Continue as Guest" — a real user row with a generated email/password,
// so every existing feature (expenses, budgets, FCM alerts) works unchanged
// without the user creating an account first.
exports.createGuestUser = ({ email, username, passwordHash }) => {
  const query = `
    INSERT INTO users (email, username, password_hash, is_guest)
    VALUES ($1, $2, $3, TRUE)
    RETURNING user_id, email, username, role, is_guest, created_at
  `;
  return db.query(query, [email, username, passwordHash]);
};

// Increments the failed-login counter and locks the account for 30 minutes
// once it reaches 5 (FR1.4).
exports.incrementFailedLogin = (userId) => {
  const query = `
    UPDATE users
    SET fail_count = fail_count + 1,
        is_locked = (fail_count + 1 >= 5),
        locked_until = CASE WHEN (fail_count + 1 >= 5)
                            THEN NOW() + INTERVAL '30 minutes'
                            ELSE locked_until END
    WHERE user_id = $1
    RETURNING fail_count, is_locked, locked_until
  `;
  return db.query(query, [userId]);
};

exports.resetFailedLogin = (userId) => {
  const query = `
    UPDATE users
    SET fail_count = 0, is_locked = FALSE, locked_until = NULL
    WHERE user_id = $1
  `;
  return db.query(query, [userId]);
};

exports.updatePasswordHash = (userId, passwordHash) => {
  return db.query('UPDATE users SET password_hash = $1 WHERE user_id = $2', [passwordHash, userId]);
};

// Lets the Flutter app register its FCM registration token so budget alerts
// (FR3.5) and future behavioral nudges have somewhere to push to.
exports.updateFcmToken = (userId, fcmToken) => {
  return db.query('UPDATE users SET fcm_token = $1 WHERE user_id = $2', [fcmToken, userId]);
};

// Explicit opt-in gate for the GPS-based food recommendation feature —
// nothing reads device location without this being set true first.
exports.updateLocationConsent = (userId, locationConsent) => {
  return db.query('UPDATE users SET location_consent = $1 WHERE user_id = $2', [locationConsent, userId]);
};

// Wraps updateLocationConsent with an append to consent_log so "when did
// this user grant/withdraw consent" survives beyond the current boolean
// state (see 032_consent_log.sql). Used by the self-service consent route;
// any future admin-initiated consent change should also go through this.
exports.recordConsentChange = async (userId, consentType, granted) => {
  const consentLogModel = require('./consentLog.model');
  await exports.updateLocationConsent(userId, granted);
  await consentLogModel.insert(userId, consentType, granted);
};

exports.updateProfile = (userId, { username, mobileNumber, profilePicture, monthlyIncome }) => {
  const query = `
    UPDATE users
    SET username = COALESCE($1, username),
        mobile_number = COALESCE($2, mobile_number),
        profile_picture = COALESCE($3, profile_picture),
        monthly_income = COALESCE($4, monthly_income)
    WHERE user_id = $5
    RETURNING user_id, email, username, mobile_number, profile_picture, monthly_income
  `;
  return db.query(query, [username, mobileNumber, profilePicture, monthlyIncome, userId]);
};

// FR1.7 — admin account management. password_hash is deliberately excluded
// from every query below; the admin dashboard never needs it and it should
// never leave the database.
//
// PDPA data-minimization: the list view masks mobile_number down to its
// last 2 digits — an admin scanning the roster doesn't need the full
// number, only the single-user detail view (findByIdForAdmin) does, and
// that view is audit-logged as a "view_profile" action (admin.service.js).
exports.findAllForAdmin = () => {
  const query = `
    SELECT user_id, email, username,
           regexp_replace(mobile_number, '.(?=.{2})', '*', 'g') AS mobile_number,
           role, is_guest, is_active, is_locked, deactivated_at,
           deletion_requested_at, created_at
    FROM users
    ORDER BY created_at DESC
  `;
  return db.query(query);
};

exports.findByIdForAdmin = (userId) => {
  const query = `
    SELECT user_id, email, username, mobile_number, role, is_guest,
           is_active, is_locked, deactivated_at, deletion_requested_at, created_at
    FROM users
    WHERE user_id = $1
  `;
  return db.query(query, [userId]);
};

// Deactivation is reversible and does not touch the login-lockout counters
// (FR1.4) — it is a separate, admin-only switch (see 024_admin_user_management.sql).
exports.setActiveStatus = (userId, isActive) => {
  const query = `
    UPDATE users
    SET is_active = $1,
        deactivated_at = CASE WHEN $1 THEN NULL ELSE NOW() END
    WHERE user_id = $2
    RETURNING user_id, email, username, role, is_active, deactivated_at
  `;
  return db.query(query, [isActive, userId]);
};

// Hard delete to satisfy PDPA data-deletion requests (FR1.7), only ever
// called after requestDeletion's grace period has elapsed (see
// admin.service.js purgeUser). Every other table's user_id FK is ON DELETE
// CASCADE (see migrations 002-023), so this also removes the user's
// expenses, budgets, goals, alerts, wishlist items and OCR receipts in one
// transaction-safe statement.
exports.deleteUser = (userId) => {
  return db.query('DELETE FROM users WHERE user_id = $1 RETURNING user_id, email', [userId]);
};

// PDPA erasure with a recoverability window (033_user_deletion_request.sql)
// — the admin "delete" action soft-deletes first: deactivates the account
// and timestamps the request. The row itself is untouched until purgeUser
// hard-deletes it once the grace period has passed.
exports.requestDeletion = (userId) => {
  const query = `
    UPDATE users
    SET is_active = FALSE, deactivated_at = NOW(), deletion_requested_at = NOW()
    WHERE user_id = $1
    RETURNING user_id, email, username, role, is_active, deactivated_at, deletion_requested_at
  `;
  return db.query(query, [userId]);
};

// Reverses requestDeletion within the grace window — restores login access
// and clears the pending-deletion marker.
exports.cancelDeletionRequest = (userId) => {
  const query = `
    UPDATE users
    SET is_active = TRUE, deactivated_at = NULL, deletion_requested_at = NULL
    WHERE user_id = $1
    RETURNING user_id, email, username, role, is_active, deactivated_at, deletion_requested_at
  `;
  return db.query(query, [userId]);
};

// PDPA storage-limitation — "Continue as Guest" (auth.service.js guestLogin)
// mints a brand-new users row on every tap, never reused, and the app never
// auto-resumes a previous guest session on cold start — so an abandoned
// guest row has no further purpose once the sitting that created it ends.
// users.created_at alone is a false signal (the guest could keep adding
// data for days after), so "last active" is the latest activity across
// every table a guest can actually write to, falling back to created_at for
// guests with none. Scoped to is_guest = TRUE — real accounts are never
// touched here regardless of inactivity.
exports.purgeStaleGuests = (days) => {
  const query = `
    WITH last_activity AS (
      SELECT u.user_id, u.email,
             GREATEST(
               u.created_at,
               COALESCE(e.last, u.created_at), COALESCE(b.last, u.created_at),
               COALESCE(sg.last, u.created_at), COALESCE(w.last, u.created_at),
               COALESCE(o.last, u.created_at), COALESCE(rl.last, u.created_at),
               COALESCE(il.last, u.created_at)
             ) AS last_active
      FROM users u
      LEFT JOIN (SELECT user_id, MAX(created_at) last FROM expenses GROUP BY user_id) e ON e.user_id = u.user_id
      LEFT JOIN (SELECT user_id, MAX(updated_at) last FROM budgets GROUP BY user_id) b ON b.user_id = u.user_id
      LEFT JOIN (SELECT user_id, MAX(created_at) last FROM saving_goals GROUP BY user_id) sg ON sg.user_id = u.user_id
      LEFT JOIN (SELECT user_id, MAX(added_at) last FROM wishlist GROUP BY user_id) w ON w.user_id = u.user_id
      LEFT JOIN (SELECT user_id, MAX(processed_at) last FROM ocr_receipts GROUP BY user_id) o ON o.user_id = u.user_id
      LEFT JOIN (SELECT user_id, MAX(generated_at) last FROM recommendation_log GROUP BY user_id) rl ON rl.user_id = u.user_id
      LEFT JOIN (SELECT user_id, MAX(created_at) last FROM income_log GROUP BY user_id) il ON il.user_id = u.user_id
      WHERE u.is_guest = TRUE
    )
    DELETE FROM users
    WHERE user_id IN (SELECT user_id FROM last_activity WHERE last_active < NOW() - ($1 || ' days')::INTERVAL)
    RETURNING user_id, email
  `;
  return db.query(query, [days]);
};
