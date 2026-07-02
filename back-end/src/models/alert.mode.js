const db = require('../config/db');

// FR3.5 — audit trail for every budget/behavioral alert triggered, also used
// to dedupe repeat sends for the same tier (see budget.service.checkAndSendAlerts).
exports.createAlert = ({ userId, expenseId, budgetId, alertType, message, deliveryChannel }) => {
  const query = `
    INSERT INTO behavioral_alerts (user_id, expense_id, budget_id, alert_type, message, delivery_channel)
    VALUES ($1, $2, $3, $4, $5, COALESCE($6, 'push notification'))
    RETURNING *
  `;
  return db.query(query, [userId, expenseId || null, budgetId, alertType, message, deliveryChannel || null]);
};

// Returns any alert already sent for this budget/tier since `since`, so the
// same threshold crossing doesn't re-notify on every subsequent expense.
exports.findRecentAlert = (budgetId, alertType, since) => {
  const query = `
    SELECT alert_id FROM behavioral_alerts
    WHERE budget_id = $1 AND alert_type = $2 AND triggered_at >= $3
    LIMIT 1
  `;
  return db.query(query, [budgetId, alertType, since]);
};

// Recent alerts for the dashboard's "Recent Alerts" panel.
exports.findRecentForUser = (userId, limit) => {
  const query = `
    SELECT alert_id, budget_id, expense_id, alert_type, message, was_acted_upon, triggered_at
    FROM behavioral_alerts
    WHERE user_id = $1
    ORDER BY triggered_at DESC
    LIMIT $2
  `;
  return db.query(query, [userId, limit]);
};
