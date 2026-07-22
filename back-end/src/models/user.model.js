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
exports.findAllForAdmin = () => {
  const query = `
    SELECT user_id, email, username, mobile_number, role, is_guest,
           is_active, is_locked, deactivated_at, created_at
    FROM users
    ORDER BY created_at DESC
  `;
  return db.query(query);
};

exports.findByIdForAdmin = (userId) => {
  const query = `
    SELECT user_id, email, username, mobile_number, role, is_guest,
           is_active, is_locked, deactivated_at, created_at
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

// Hard delete to satisfy PDPA data-deletion requests (FR1.7). Every other
// table's user_id FK is ON DELETE CASCADE (see migrations 002-023), so this
// also removes the user's expenses, budgets, goals, alerts, wishlist items
// and OCR receipts in one transaction-safe statement.
exports.deleteUser = (userId) => {
  return db.query('DELETE FROM users WHERE user_id = $1 RETURNING user_id, email', [userId]);
};
