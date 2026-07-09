const db = require('../config/db');

exports.findAllUsers = (callback) => {
  db.query('SELECT * FROM users', callback);
};

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
