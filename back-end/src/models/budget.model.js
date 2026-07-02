const db = require('../config/db');

// FR3.1 — creates the category's monthly limit, or updates it if the user
// already set one for this category/month/year (unique constraint in
// 003_budgets.sql). current_spend is never written here — it's maintained
// by the trg_sync_budget_spend trigger (012_triggers.sql) whenever an
// expense is inserted, updated or deleted.
exports.upsertBudget = ({ userId, category, monthlyLimit, month, year, alertThreshold }) => {
  const query = `
    INSERT INTO budgets (user_id, category, monthly_limit, month, year, alert_threshold)
    VALUES ($1, $2, $3, $4, $5, COALESCE($6, 75.00))
    ON CONFLICT (user_id, category, month, year)
    DO UPDATE SET
      monthly_limit = EXCLUDED.monthly_limit,
      alert_threshold = COALESCE($6, budgets.alert_threshold),
      updated_at = NOW()
    RETURNING *
  `;
  return db.query(query, [userId, category, monthlyLimit, month, year, alertThreshold ?? null]);
};

// FR3.4 — real-time spend vs. limit per category, for the dashboard
exports.getBudgetsForUser = (userId, month, year) => {
  const query = `
    SELECT
      budget_id, category, monthly_limit, current_spend, alert_threshold,
      month, year, rollover_amount,
      ROUND((current_spend / NULLIF(monthly_limit, 0)) * 100, 2) AS utilization_pct
    FROM budgets
    WHERE user_id = $1 AND month = $2 AND year = $3
    ORDER BY category
  `;
  return db.query(query, [userId, month, year]);
};

exports.getBudgetById = (budgetId, userId) => {
  return db.query('SELECT * FROM budgets WHERE budget_id = $1 AND user_id = $2', [budgetId, userId]);
};

// Used by budget.service.checkAndSendAlerts right after an expense is saved.
exports.getBudgetByCategoryMonth = (userId, category, month, year) => {
  const query = `
    SELECT * FROM budgets
    WHERE user_id = $1 AND category = $2 AND month = $3 AND year = $4
  `;
  return db.query(query, [userId, category, month, year]);
};

exports.updateBudget = (budgetId, userId, { monthlyLimit, alertThreshold }) => {
  const query = `
    UPDATE budgets
    SET monthly_limit = COALESCE($1, monthly_limit),
        alert_threshold = COALESCE($2, alert_threshold),
        updated_at = NOW()
    WHERE budget_id = $3 AND user_id = $4
    RETURNING *
  `;
  return db.query(query, [monthlyLimit ?? null, alertThreshold ?? null, budgetId, userId]);
};

exports.deleteBudget = (budgetId, userId) => {
  return db.query('DELETE FROM budgets WHERE budget_id = $1 AND user_id = $2', [budgetId, userId]);
};
