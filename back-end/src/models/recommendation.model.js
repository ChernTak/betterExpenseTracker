const db = require('../config/db');

// Audit trail for each food-recommendation batch shown to a user — mirrors
// alert.mode.js's role for behavioral_alerts. context_snapshot captures the
// query inputs/outputs so "was this recommendation acted on" can be
// analysed later without re-deriving it from raw expense data.
exports.logRecommendation = ({ userId, title, body, contextSnapshot }) => {
  const query = `
    INSERT INTO recommendation_log (user_id, rec_type, rec_title, rec_body, context_snapshot)
    VALUES ($1, 'food_recommendation', $2, $3, $4)
    RETURNING rec_id
  `;
  return db.query(query, [userId, title, body, JSON.stringify(contextSnapshot || {})]);
};

// PDPA data-minimization — context_snapshot carries raw GPS coordinates
// (see recommendation.service.js), which have no business reason to be
// retained indefinitely. Admin-triggered since this app has no job
// scheduler to run it automatically.
exports.purgeOlderThan = (days) => {
  const query = `
    DELETE FROM recommendation_log
    WHERE generated_at < NOW() - ($1 || ' days')::INTERVAL
    RETURNING rec_id
  `;
  return db.query(query, [days]);
};
