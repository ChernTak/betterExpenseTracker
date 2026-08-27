const db = require('../config/db');

exports.getAllExpenses = (callback) => {
  const query = 'SELECT * FROM expenses';
  db.query(query, callback);
};

// FR4.1 — scoped to the logged-in user only
exports.getExpensesByUserId = (userId, callback) => {
  const query = 'SELECT * FROM expenses WHERE user_id = $1 ORDER BY transaction_date DESC, created_at DESC';
  db.query(query, [userId], callback);
};

// Promise-based (not callback, unlike the rest of this file) since its only
// caller, recommendation.service.js, is async/await throughout — feeds the
// food recommendation ranking's "you've been here before" personalization.
exports.getFoodDiningMerchantHistory = (userId) => {
  const query = `
    SELECT merchant_name, COUNT(*) AS visit_count
    FROM expenses
    WHERE user_id = $1 AND category = 'food_dining' AND merchant_name IS NOT NULL
    GROUP BY merchant_name
  `;
  return db.query(query, [userId]);
};

// Real total spend in [monthStart, monthEndExclusive) — used by the
// dashboard's "Available to spend" figure (budget.service.js#listBudgets).
// Deliberately not derived from budgets.current_spend: that column only
// updates for categories the user has actually set a budget for
// (trg_sync_budget_spend, 012_triggers.sql, has no upsert fallback), so it
// silently undercounts spending in unbudgeted categories.
exports.getTotalSpentForMonth = (userId, monthStart, monthEndExclusive) => {
  const query = `
    SELECT COALESCE(SUM(amount), 0) AS total
    FROM expenses
    WHERE user_id = $1 AND transaction_date >= $2 AND transaction_date < $3
  `;
  return db.query(query, [userId, monthStart, monthEndExclusive]);
};

exports.getExpenseById = (id, userId, callback) => {
  const query = 'SELECT * FROM expenses WHERE expense_id = $1 AND user_id = $2';
  db.query(query, [id, userId], callback);
};

exports.deleteExpenseById = (id, userId, callback) => {
  const query = 'DELETE FROM expenses WHERE expense_id = $1 AND user_id = $2';
  db.query(query, [id, userId], callback);
};

exports.updateExpenseById = (id, userId, data, callback) => {
  const query = `
    UPDATE expenses
    SET amount = $1,
        category = $2,
        merchant_name = $3,
        description = $4,
        payment_method = $5,
        transaction_date = $6,
        updated_at = NOW()
    WHERE expense_id = $7 AND user_id = $8
    RETURNING *
  `;

  db.query(
    query,
    [
      data.amount,
      data.category,
      data.merchant_name,
      data.description,
      data.payment_method,
      data.transaction_date,
      id,
      userId
    ],
    callback
  );
};

exports.createExpense = (userId, data, callback) => {
  const query = `
    INSERT INTO expenses (
      user_id,
      amount,
      category,
      merchant_name,
      description,
      payment_method,
      transaction_date
    )
    VALUES ($1, $2, $3, $4, $5, $6, COALESCE($7, CURRENT_DATE))
    RETURNING *
  `;

  db.query(
    query,
    [
      userId,
      data.amount,
      data.category,
      data.merchant_name || null,
      data.description || null,
      data.payment_method || null,
      data.transaction_date || null
    ],
    callback
  );
};
