const db = require('../config/db');

// 4 months back covers a full quarter of history for Tier A/B pattern
// detection in forecaster.js while keeping the row count small per request.
exports.getExpenseHistoryForUser = (userId) => {
  const query = `
    SELECT expense_id, amount, category, merchant_name, transaction_date
    FROM expenses
    WHERE user_id = $1 AND transaction_date >= NOW() - INTERVAL '4 months'
    ORDER BY transaction_date
  `;
  return db.query(query, [userId]);
};

// Monitoring only — see ai/evaluate_tier_b.py. Nothing in this app reads
// this table back to serve a forecast.
exports.logPrediction = ({ userId, month, year, p10, p50, p90, modelVersion }) => {
  const query = `
    INSERT INTO forecast_predictions_log (user_id, month, year, predicted_p10, predicted_p50, predicted_p90, model_version)
    VALUES ($1, $2, $3, $4, $5, $6, $7)
    RETURNING prediction_id
  `;
  return db.query(query, [userId, month, year, p10, p50, p90, modelVersion]);
};
