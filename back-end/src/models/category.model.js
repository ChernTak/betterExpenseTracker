const db = require('../config/db');
const { DEFAULT_CATEGORIES } = require('../config/categories');

exports.listForUser = (userId) => {
  return db.query('SELECT * FROM categories WHERE user_id = $1 ORDER BY sort_order', [userId]);
};

// Category is now a plain VARCHAR (no more DB-level ENUM), so the app layer must validate the key belongs to this user.
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

// Reassigns expenses/wishlist to 'other' (preserves history) but drops budget limit rows outright (a forward-looking setting, not history, so there's nothing to merge).
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

    // Budgets must be deleted before expenses are reassigned, or the sync trigger could underflow current_spend below its >= 0 check when subtracting reassigned expenses.
    await client.query('DELETE FROM budgets WHERE user_id = $1 AND category = $2', [userId, category.key]);
    await client.query(
      "UPDATE expenses SET category = 'other', updated_at = NOW() WHERE user_id = $1 AND category = $2",
      [userId, category.key],
    );
    await client.query(
      "UPDATE wishlist SET category = 'other', updated_at = NOW() WHERE user_id = $1 AND category = $2",
      [userId, category.key],
    );
    // ml_model_output also references the key and must be reassigned too, or the fk constraints block this delete.
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

// Seeds a new account with the default categories (fully editable afterward).
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
