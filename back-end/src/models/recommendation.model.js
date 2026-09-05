const db = require('../config/db');

// context_snapshot captures query inputs/outputs so "was this acted on" can be analysed later without re-deriving from raw expense data.
exports.logRecommendation = ({ userId, title, body, contextSnapshot }) => {
  const query = `
    INSERT INTO recommendation_log (user_id, rec_type, rec_title, rec_body, context_snapshot)
    VALUES ($1, 'food_recommendation', $2, $3, $4)
    RETURNING rec_id
  `;
  return db.query(query, [userId, title, body, JSON.stringify(contextSnapshot || {})]);
};

// PDPA data-minimization: context_snapshot carries raw GPS coordinates with no reason to be retained indefinitely; admin-triggered since there's no job scheduler.
exports.purgeOlderThan = (days) => {
  const query = `
    DELETE FROM recommendation_log
    WHERE generated_at < NOW() - ($1 || ' days')::INTERVAL
    RETURNING rec_id
  `;
  return db.query(query, [days]);
};
