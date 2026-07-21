const db = require('../config/db');

exports.createIncome = ({ userId, amount, source, receivedDate }) => {
  const query = `
    INSERT INTO income_log (user_id, amount, source, received_date)
    VALUES ($1, $2, $3, COALESCE($4, CURRENT_DATE))
    RETURNING *
  `;
  return db.query(query, [userId, amount, source || null, receivedDate || null]);
};

// 6 months back (vs. 4 for expenses in forecast.model.js) since paychecks
// are typically ~monthly — income_forecaster.js needs several occurrences
// to compute meaningful interval statistics.
exports.listIncomeForUser = (userId) => {
  const query = `
    SELECT income_id, amount, source, received_date
    FROM income_log
    WHERE user_id = $1 AND received_date >= NOW() - INTERVAL '6 months'
    ORDER BY received_date
  `;
  return db.query(query, [userId]);
};

exports.updateIncome = (incomeId, userId, { amount, source, receivedDate }) => {
  const query = `
    UPDATE income_log
    SET amount = COALESCE($1, amount),
        source = COALESCE($2, source),
        received_date = COALESCE($3, received_date)
    WHERE income_id = $4 AND user_id = $5
    RETURNING *
  `;
  return db.query(query, [amount ?? null, source ?? null, receivedDate ?? null, incomeId, userId]);
};

exports.deleteIncome = (incomeId, userId) => {
  return db.query('DELETE FROM income_log WHERE income_id = $1 AND user_id = $2', [incomeId, userId]);
};
