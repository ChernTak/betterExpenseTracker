const db = require('../config/db');
const { DEFAULT_CATEGORIES } = require('../config/categories');

exports.listForUser = (userId) => {
  return db.query('SELECT * FROM categories WHERE user_id = $1 ORDER BY sort_order', [userId]);
};

// Reused by expense/budget validation — the expense_category ENUM used to
// enforce this at the DB level; now that category is a plain VARCHAR, the
// app layer has to check the key actually belongs to one of this user's
// categories.
exports.findByUserAndKey = (userId, key) => {
  return db.query('SELECT * FROM categories WHERE user_id = $1 AND key = $2', [userId, key]);
};

exports.findById = (userId, categoryId) => {
  return db.query('SELECT * FROM categories WHERE user_id = $1 AND category_id = $2', [userId, categoryId]);
};

exports.create = ({ userId, key, label, icon, color, keywords, sortOrder }) => {
  const query = `
    INSERT INTO categories (user_id, key, label, icon, color, keywords, sort_order)
    VALUES ($1, $2, $3, $4, $5, $6, $7)
    RETURNING *
  `;
  return db.query(query, [userId, key, label, icon, color, keywords || null, sortOrder]);
};

// key is intentionally not editable — expenses/budgets reference it, so
// renaming it would orphan every historical row that used the old key.
exports.update = (categoryId, userId, { label, icon, color, keywords }) => {
  const query = `
    UPDATE categories
    SET label = COALESCE($1, label),
        icon = COALESCE($2, icon),
        color = COALESCE($3, color),
        keywords = COALESCE($4, keywords)
    WHERE category_id = $5 AND user_id = $6
    RETURNING *
  `;
  return db.query(query, [label ?? null, icon ?? null, color ?? null, keywords ?? null, categoryId, userId]);
};

exports.reorder = async (userId, orderedIds) => {
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    for (let i = 0; i < orderedIds.length; i += 1) {
      await client.query(
        'UPDATE categories SET sort_order = $1 WHERE category_id = $2 AND user_id = $3',
        [i, orderedIds[i], userId],
      );
    }
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
};

// Deletes the category and reassigns anything that referenced it: existing
// expenses/wishlist items move to 'other' (preserves the historical record,
// just recategorized); budget limit rows for the deleted category are
// dropped outright (a forward-looking setting, not historical data, so
// there's no sensible way to "merge" it into other's own limit). Returns
// the deleted row, or null if it didn't exist or is protected (caller
// treats that as a 404/400).
exports.deleteAndReassign = async (categoryId, userId) => {
  const client = await db.connect();
  try {
    await client.query('BEGIN');

    const existing = await client.query(
      'SELECT * FROM categories WHERE category_id = $1 AND user_id = $2 FOR UPDATE',
      [categoryId, userId],
    );
    const category = existing.rows[0];
    if (!category || category.is_protected) {
      await client.query('ROLLBACK');
      return null;
    }

    // Budgets are deleted BEFORE expenses are reassigned: trg_sync_budget_spend
    // (012_triggers.sql) fires on the expenses UPDATE below and tries to
    // subtract each reassigned expense's amount from the old category's
    // budget — if that budget row (and its current_spend) still existed,
    // this could underflow current_spend below the table's >= 0 check
    // (e.g. a budget created after its expenses already existed never had
    // current_spend backfilled for them). Deleting the budget first means
    // the trigger's UPDATE simply matches zero rows for the old category.
    await client.query('DELETE FROM budgets WHERE user_id = $1 AND category = $2', [userId, category.key]);
    await client.query(
      "UPDATE expenses SET category = 'other', updated_at = NOW() WHERE user_id = $1 AND category = $2",
      [userId, category.key],
    );
    await client.query(
      "UPDATE wishlist SET category = 'other', updated_at = NOW() WHERE user_id = $1 AND category = $2",
      [userId, category.key],
    );
    // ml_model_output rows are a historical prediction record, not a
    // user-facing categorization the way expenses/wishlist are — but they
    // still hold the now-deleted key, so they need the same reassignment or
    // the fk_ml_predicted_category / fk_ml_corrected_category constraints
    // (037_category_referential_integrity.sql) block this delete.
    await client.query(
      "UPDATE ml_model_output SET predicted_category = 'other' WHERE user_id = $1 AND predicted_category = $2",
      [userId, category.key],
    );
    await client.query(
      "UPDATE ml_model_output SET corrected_category = 'other' WHERE user_id = $1 AND corrected_category = $2",
      [userId, category.key],
    );
    await client.query('DELETE FROM categories WHERE category_id = $1 AND user_id = $2', [categoryId, userId]);

    await client.query('COMMIT');
    return category;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
};

// Called once right after a new user/guest account is created (see
// auth.service.js) so every account starts with the same 13 categories
// today's hardcoded list had, fully editable from that point on.
exports.seedDefaultsForUser = async (userId) => {
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    for (let i = 0; i < DEFAULT_CATEGORIES.length; i += 1) {
      const def = DEFAULT_CATEGORIES[i];
      await client.query(
        `INSERT INTO categories (user_id, key, label, icon, color, sort_order, is_protected)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (user_id, key) DO NOTHING`,
        [userId, def.key, def.label, def.icon, def.color, i, Boolean(def.isProtected)],
      );
    }
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
};
