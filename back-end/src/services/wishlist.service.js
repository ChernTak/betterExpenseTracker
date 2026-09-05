const wishlistModel = require('../models/wishlist.model');

// 'converted_to_goal' is excluded here since it's only reachable via convertToGoal, which creates the goal atomically with the status flip.
const MANUAL_STATUSES = ['pending', 'purchased', 'dismissed', 'expired'];
// Full set, for validating the GET ?status= filter — converted items should
// still be listable/visible even though they can't be *set* this way.
const LISTABLE_STATUSES = [...MANUAL_STATUSES, 'converted_to_goal'];

// POST /api/wishlist — meant to be created from a real-time behavioral alert, but alertId stays optional so manual add isn't blocked.
exports.createWishlistItem = async (req, res) => {
  const { alertId, itemName, estimatedCost, merchantName, category, delayDays, notes } = req.body;

  if (!itemName || !itemName.trim()) {
    return res.status(400).json({ message: 'itemName is required' });
  }
  if (estimatedCost !== undefined && estimatedCost !== null) {
    const parsedCost = Number(estimatedCost);
    if (!Number.isFinite(parsedCost) || parsedCost <= 0) {
      return res.status(400).json({ message: 'estimatedCost must be a positive number' });
    }
  }
  if (delayDays !== undefined && delayDays !== null && (!Number.isInteger(delayDays) || delayDays < 0)) {
    return res.status(400).json({ message: 'delayDays must be a non-negative integer' });
  }

  try {
    const result = await wishlistModel.createWishlistItem({
      userId: req.user.userId,
      alertId,
      itemName: itemName.trim(),
      estimatedCost: estimatedCost !== undefined ? Number(estimatedCost) : undefined,
      merchantName,
      category,
      delayDays,
      notes,
    });
    if (alertId) {
      await wishlistModel.markAlertActedUpon(alertId);
    }
    return res.status(201).json({ message: 'Wishlist item added successfully', data: result.rows[0] });
  } catch (err) {
    console.error('Create wishlist item error', err);
    return res.status(500).json({ message: 'Failed to add wishlist item', error: err.message });
  }
};

// GET /api/wishlist?status=pending — status filter is optional (all items
// if omitted), backing the Pending/Purchased/Dismissed segments in the UI.
exports.listWishlist = async (req, res) => {
  const { status } = req.query;
  if (status !== undefined && !LISTABLE_STATUSES.includes(status)) {
    return res.status(400).json({ message: 'Invalid status filter' });
  }

  try {
    const result = await wishlistModel.listWishlistForUser(req.user.userId, status);
    return res.status(200).json(result.rows);
  } catch (err) {
    console.error('List wishlist error', err);
    return res.status(500).json({ message: 'Failed to fetch wishlist', error: err.message });
  }
};

// PUT /api/wishlist/:id — status: 'purchased' is routed to resolvePurchaseStatus below since it needs its own gating and creates a real expense row.
exports.updateWishlistItem = async (req, res) => {
  const { id } = req.params;
  const { itemName, estimatedCost, merchantName, category, status, purchasedOn, notes } = req.body;

  if (status !== undefined && !MANUAL_STATUSES.includes(status)) {
    return res.status(400).json({ message: 'Invalid status' });
  }
  if (estimatedCost !== undefined && (!Number.isFinite(Number(estimatedCost)) || Number(estimatedCost) <= 0)) {
    return res.status(400).json({ message: 'estimatedCost must be a positive number' });
  }

  if (status === 'purchased') {
    return resolvePurchaseStatus(req, res);
  }

  try {
    const result = await wishlistModel.updateWishlistItem(id, req.user.userId, {
      itemName: itemName?.trim(),
      estimatedCost: estimatedCost !== undefined ? Number(estimatedCost) : undefined,
      merchantName,
      category,
      status,
      purchasedOn,
      notes,
    });
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Wishlist item not found' });
    }
    return res.status(200).json({ message: 'Wishlist item updated successfully', data: result.rows[0] });
  } catch (err) {
    console.error('Update wishlist item error', err);
    return res.status(500).json({ message: 'Failed to update wishlist item', error: err.message });
  }
};

// Marking an item "bought" is hard-gated: blocked until the cooling-off delay passes, and it creates a real expenses row instead of just a status flag.
const resolvePurchaseStatus = async (req, res) => {
  const { id } = req.params;
  const { purchasedOn, notes } = req.body;

  try {
    const itemResult = await wishlistModel.getWishlistItem(id, req.user.userId);
    const item = itemResult.rows[0];
    if (!item) {
      return res.status(404).json({ message: 'Wishlist item not found' });
    }

    // delay_until_date is a raw 'YYYY-MM-DD' string, so plain string comparison avoids the local-midnight shift a JS Date would introduce.
    const today = new Date().toISOString().slice(0, 10);
    if (item.delay_until_date && item.delay_until_date > today) {
      return res.status(409).json({
        message: `This purchase is delayed until ${item.delay_until_date}. Wait it out, or dismiss it instead.`,
      });
    }

    const result = await wishlistModel.resolvePurchase(id, req.user.userId, { purchasedOn, notes });
    if (result === null) {
      return res.status(404).json({ message: 'Wishlist item not found' });
    }
    if (result.error === 'already_resolved') {
      return res.status(409).json({ message: 'This item has already been resolved' });
    }
    if (result.error === 'missing_cost_or_category') {
      return res.status(400).json({ message: 'Add an estimated cost and category before marking this as bought' });
    }
    return res.status(200).json({ message: 'Wishlist item marked as bought', data: result });
  } catch (err) {
    console.error('Resolve wishlist purchase error', err);
    return res.status(500).json({ message: 'Failed to mark wishlist item as bought', error: err.message });
  }
};

// POST /api/wishlist/:id/convert-to-goal — targetAmount defaults to the item's estimated_cost; only supply it to override or when there's no cost set.
exports.convertToGoal = async (req, res) => {
  const { id } = req.params;
  const { targetAmount, deadlineDate, priority } = req.body;

  if (targetAmount !== undefined && targetAmount !== null) {
    const parsedTarget = Number(targetAmount);
    if (!Number.isFinite(parsedTarget) || parsedTarget <= 0) {
      return res.status(400).json({ message: 'targetAmount must be a positive number' });
    }
  }

  try {
    const result = await wishlistModel.convertToGoal(id, req.user.userId, {
      targetAmount: targetAmount !== undefined && targetAmount !== null ? Number(targetAmount) : undefined,
      deadlineDate,
      priority,
    });
    if (result === null) {
      return res.status(404).json({ message: 'Wishlist item not found' });
    }
    if (result.error === 'already_resolved') {
      return res.status(409).json({ message: 'This item has already been resolved' });
    }
    if (result.error === 'missing_cost') {
      return res.status(400).json({ message: 'Add an estimated cost, or provide targetAmount, before converting to a goal' });
    }
    return res.status(201).json({ message: 'Wishlist item converted to a saving goal', data: result });
  } catch (err) {
    console.error('Convert wishlist item to goal error', err);
    return res.status(500).json({ message: 'Failed to convert wishlist item to goal', error: err.message });
  }
};

// DELETE /api/wishlist/:id
exports.deleteWishlistItem = async (req, res) => {
  const { id } = req.params;

  try {
    const result = await wishlistModel.deleteWishlistItem(id, req.user.userId);
    if (result.rowCount === 0) {
      return res.status(404).json({ message: 'Wishlist item not found' });
    }
    return res.status(200).json({ message: 'Wishlist item deleted successfully' });
  } catch (err) {
    console.error('Delete wishlist item error', err);
    return res.status(500).json({ message: 'Failed to delete wishlist item', error: err.message });
  }
};
