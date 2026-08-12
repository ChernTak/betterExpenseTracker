const db = require('../config/db');

// PDPA consent-evidence trail (see 032_consent_log.sql) — every grant/withdraw
// is appended here in addition to the current-state boolean on users.
exports.insert = (userId, consentType, granted) => {
  const query = `
    INSERT INTO consent_log (user_id, consent_type, granted)
    VALUES ($1, $2, $3)
    RETURNING *
  `;
  return db.query(query, [userId, consentType, granted]);
};

exports.findForUser = (userId) => {
  const query = `
    SELECT consent_id, user_id, consent_type, granted, changed_at
    FROM consent_log
    WHERE user_id = $1
    ORDER BY changed_at DESC
  `;
  return db.query(query, [userId]);
};
