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

// Promise-based (unlike rest of file) since its only caller is async/await throughout.
exports.getFoodDiningMerchantHistory = (userId) => {
  const query = `
    SELECT merchant_name, COUNT(*) AS visit_count
    FROM expenses
    WHERE user_id = $1 AND category = 'food_dining' AND merchant_name IS NOT NULL
    GROUP BY merchant_name
  `;
  return db.query(query, [userId]);
};

// Deliberately not derived from budgets.current_spend, since that only updates for categories with a budget set and would undercount unbudgeted spending.
exports.getTotalSpentForMonth = (userId, monthStart, monthEndExclusive) => {
  const query = `
    SELECT COALESCE(SUM(amount), 0) AS total
    FROM expenses
    WHERE user_id = $1 AND transaction_date >= $2 AND transaction_date < $3
  `;
  return db.query(query, [userId, monthStart, monthEndExclusive]);
};

// Per-category spend regardless of whether a budget exists, so unbudgeted categories still show up on the dashboard.
exports.getSpendByCategoryForMonth = (userId, monthStart, monthEndExclusive) => {
  const query = `
    SELECT category, SUM(amount) AS spent
    FROM expenses
    WHERE user_id = $1 AND transaction_date >= $2 AND transaction_date < $3
    GROUP BY category
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
