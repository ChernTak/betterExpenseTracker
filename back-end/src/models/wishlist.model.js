const db = require('../config/db');

exports.createWishlistItem = ({
  userId,
  alertId,
  itemName,
  estimatedCost,
  merchantName,
  category,
  delayDays,
  notes,
}) => {
  const query = `
    INSERT INTO wishlist (user_id, alert_id, item_name, estimated_cost, merchant_name, category, delay_days, delay_until_date, notes)
    VALUES ($1, $2, $3, $4, $5, $6, $7, CASE WHEN $7::SMALLINT IS NULL THEN NULL ELSE CURRENT_DATE + ($7 || ' days')::INTERVAL END, $8)
    RETURNING *
  `;
  return db.query(query, [
    userId,
    alertId || null,
    itemName,
    estimatedCost ?? null,
    merchantName || null,
    category || null,
    delayDays ?? null,
    notes || null,
  ]);
};

// Marks the alert that spawned this item as "acted upon" so the alert history
// panel can reflect that the nudge actually led to a behavior change.
exports.markAlertActedUpon = (alertId) => {
  return db.query('UPDATE behavioral_alerts SET was_acted_upon = TRUE WHERE alert_id = $1', [alertId]);
};

// Joins in this month's budget row per item's category so the frontend can show "this would push your budget to X%" without a second round-trip per item.
exports.listWishlistForUser = (userId, status) => {
  const baseSelect = `
    SELECT w.*, b.monthly_limit AS budget_monthly_limit, b.current_spend AS budget_current_spend
    FROM wishlist w
    LEFT JOIN budgets b
      ON b.user_id = w.user_id
      AND b.category = w.category
      AND b.month = EXTRACT(MONTH FROM CURRENT_DATE)
      AND b.year = EXTRACT(YEAR FROM CURRENT_DATE)
    WHERE w.user_id = $1
  `;
  const query = status
    ? `${baseSelect} AND w.status = $2 ORDER BY w.added_at DESC`
    : `${baseSelect} ORDER BY w.added_at DESC`;
  return db.query(query, status ? [userId, status] : [userId]);
};

exports.getWishlistItem = (wishlistId, userId) => {
  return db.query('SELECT * FROM wishlist WHERE wishlist_id = $1 AND user_id = $2', [wishlistId, userId]);
};

exports.updateWishlistItem = (
  wishlistId,
  userId,
  { itemName, estimatedCost, merchantName, category, status, purchasedOn, notes },
) => {
  const query = `
    UPDATE wishlist
    SET item_name = COALESCE($1, item_name),
        estimated_cost = COALESCE($2, estimated_cost),
        merchant_name = COALESCE($3, merchant_name),
        category = COALESCE($4, category),
        status = COALESCE($5, status),
        purchased_on = COALESCE($6, purchased_on),
        notes = COALESCE($7, notes),
        updated_at = NOW()
    WHERE wishlist_id = $8 AND user_id = $9
    RETURNING *
  `;
  return db.query(query, [
    itemName ?? null,
    estimatedCost ?? null,
    merchantName ?? null,
    category ?? null,
    status ?? null,
    purchasedOn ?? null,
    notes ?? null,
    wishlistId,
    userId,
  ]);
};

exports.deleteWishlistItem = (wishlistId, userId) => {
  return db.query('DELETE FROM wishlist WHERE wishlist_id = $1 AND user_id = $2', [wishlistId, userId]);
};

// Goal creation and the wishlist status flip happen in one transaction so a failure never leaves an orphaned goal or a dangling wishlist item.
exports.convertToGoal = async (wishlistId, userId, { targetAmount, deadlineDate, priority } = {}) => {
  const client = await db.connect();
  try {
    await client.query('BEGIN');

    const itemResult = await client.query(
      'SELECT * FROM wishlist WHERE wishlist_id = $1 AND user_id = $2 FOR UPDATE',
      [wishlistId, userId],
    );
    const item = itemResult.rows[0];
    if (!item) {
      await client.query('ROLLBACK');
      return null;
    }
    if (item.status !== 'pending') {
      await client.query('ROLLBACK');
      return { error: 'already_resolved' };
    }

    const effectiveTarget = targetAmount ?? item.estimated_cost;
    if (effectiveTarget === null || effectiveTarget === undefined) {
      await client.query('ROLLBACK');
      return { error: 'missing_cost' };
    }

    const goalResult = await client.query(
      `INSERT INTO saving_goals (user_id, goal_name, target_amount, deadline_date, priority, notes)
       VALUES ($1, $2, $3, $4, COALESCE($5, 1), $6)
       RETURNING *`,
      [userId, item.item_name, effectiveTarget, deadlineDate || null, priority ?? null, item.notes || null],
    );
    const goal = goalResult.rows[0];

    const updatedItemResult = await client.query(
      `UPDATE wishlist
       SET status = 'converted_to_goal', goal_id = $1, updated_at = NOW()
       WHERE wishlist_id = $2
       RETURNING *`,
      [goal.goal_id, wishlistId],
    );

    await client.query('COMMIT');
    return { wishlistItem: updatedItemResult.rows[0], goal };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
};

// Creates the matching expenses row in the same transaction so the purchase lands in spending/budget totals instead of just flipping a status flag; requires estimated_cost and category since expenses.category is NOT NULL.
exports.resolvePurchase = async (wishlistId, userId, { purchasedOn, notes } = {}) => {
  const client = await db.connect();
  try {
    await client.query('BEGIN');

    const itemResult = await client.query(
      'SELECT * FROM wishlist WHERE wishlist_id = $1 AND user_id = $2 FOR UPDATE',
      [wishlistId, userId],
    );
    const item = itemResult.rows[0];
    if (!item) {
      await client.query('ROLLBACK');
      return null;
    }
    if (item.status !== 'pending') {
      await client.query('ROLLBACK');
      return { error: 'already_resolved' };
    }
    if (item.estimated_cost === null || item.category === null) {
      await client.query('ROLLBACK');
      return { error: 'missing_cost_or_category' };
    }

    const expenseResult = await client.query(
      `INSERT INTO expenses (user_id, amount, category, merchant_name, description, transaction_date)
       VALUES ($1, $2, $3, $4, $5, COALESCE($6, CURRENT_DATE))
       RETURNING *`,
      [userId, item.estimated_cost, item.category, item.merchant_name, item.item_name, purchasedOn || null],
    );
    const expense = expenseResult.rows[0];

    const updatedItemResult = await client.query(
      `UPDATE wishlist
       SET status = 'purchased', expense_id = $1, purchased_on = COALESCE($2, CURRENT_DATE),
           notes = COALESCE($3, notes), updated_at = NOW()
       WHERE wishlist_id = $4
       RETURNING *`,
      [expense.expense_id, purchasedOn || null, notes ?? null, wishlistId],
    );

    await client.query('COMMIT');
    return { wishlistItem: updatedItemResult.rows[0], expense };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
};
