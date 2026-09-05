const categoryModel = require('../models/category.model');
const { ICON_PRESET_KEYS } = require('../config/categories');

const HEX_COLOR_REGEX = /^#[0-9a-fA-F]{6}$/;

function slugify(label) {
  return label
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 60);
}

function validateCategoryInput({ label, icon, color }) {
  if (!label || typeof label !== 'string' || !label.trim()) {
    return 'label is required';
  }
  if (!icon || !ICON_PRESET_KEYS.includes(icon)) {
    return `icon must be one of: ${ICON_PRESET_KEYS.join(', ')}`;
  }
  if (!color || !HEX_COLOR_REGEX.test(color)) {
    return 'color must be a hex string like #RRGGBB';
  }
  return null;
}

// GET /api/categories
exports.list = async (req, res) => {
  try {
    const result = await categoryModel.listForUser(req.user.userId);
    return res.status(200).json(result.rows);
  } catch (err) {
    console.error('List categories error', err);
    return res.status(500).json({ message: 'Failed to fetch categories', error: err.message });
  }
};

// POST /api/categories
exports.create = async (req, res) => {
  const { label, icon, color, keywords } = req.body;

  const validationError = validateCategoryInput({ label, icon, color });
  if (validationError) {
    return res.status(400).json({ message: validationError });
  }

  try {
    const userId = req.user.userId;
    const baseKey = slugify(label) || 'category';

    // Dedupe against this user's existing keys (e.g. "Food" then "Food!" both
    // slugify to "food") rather than letting the unique constraint 500.
    const existing = await categoryModel.listForUser(userId);
    const existingKeys = new Set(existing.rows.map((c) => c.key));
    let key = baseKey;
    let suffix = 2;
    while (existingKeys.has(key)) {
      key = `${baseKey}_${suffix}`;
      suffix += 1;
    }

    const sortOrder = existing.rows.length;
    const result = await categoryModel.create({
      userId,
      key,
      label: label.trim(),
      icon,
      color,
      keywords: keywords ? String(keywords).trim() : null,
      sortOrder,
    });
    return res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('Create category error', err);
    return res.status(500).json({ message: 'Failed to create category', error: err.message });
  }
};

// PUT /api/categories/:id
exports.update = async (req, res) => {
  const { id } = req.params;
  const { label, icon, color, keywords } = req.body;

  // Only validate fields actually provided; update() is a partial COALESCE so omitted fields shouldn't be rejected.
  if (label !== undefined && !label.trim()) {
    return res.status(400).json({ message: 'label is required' });
  }
  if (icon !== undefined && !ICON_PRESET_KEYS.includes(icon)) {
    return res.status(400).json({ message: `icon must be one of: ${ICON_PRESET_KEYS.join(', ')}` });
  }
  if (color !== undefined && !HEX_COLOR_REGEX.test(color)) {
    return res.status(400).json({ message: 'color must be a hex string like #RRGGBB' });
  }

  try {
    const result = await categoryModel.update(id, req.user.userId, {
      label: label !== undefined ? label.trim() : undefined,
      icon,
      color,
      keywords: keywords !== undefined ? String(keywords).trim() : undefined,
    });
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Category not found' });
    }
    return res.status(200).json(result.rows[0]);
  } catch (err) {
    console.error('Update category error', err);
    return res.status(500).json({ message: 'Failed to update category', error: err.message });
  }
};

// DELETE /api/categories/:id — reassigns expenses/wishlist to 'other' and
// drops budget rows for this category (see category.model.deleteAndReassign).
exports.remove = async (req, res) => {
  const { id } = req.params;

  try {
    const deleted = await categoryModel.deleteAndReassign(id, req.user.userId);
    if (!deleted) {
      const existing = await categoryModel.findById(req.user.userId, id);
      if (existing.rows.length > 0) {
        return res.status(400).json({ message: '"Other" is protected and cannot be deleted' });
      }
      return res.status(404).json({ message: 'Category not found' });
    }
    return res.status(200).json({ message: 'Category deleted successfully' });
  } catch (err) {
    console.error('Delete category error', err);
    return res.status(500).json({ message: 'Failed to delete category', error: err.message });
  }
};

// PUT /api/categories/reorder
exports.reorder = async (req, res) => {
  const { orderedIds } = req.body;
  if (!Array.isArray(orderedIds) || orderedIds.length === 0) {
    return res.status(400).json({ message: 'orderedIds must be a non-empty array' });
  }

  try {
    await categoryModel.reorder(req.user.userId, orderedIds);
    const result = await categoryModel.listForUser(req.user.userId);
    return res.status(200).json(result.rows);
  } catch (err) {
    console.error('Reorder categories error', err);
    return res.status(500).json({ message: 'Failed to reorder categories', error: err.message });
  }
};
