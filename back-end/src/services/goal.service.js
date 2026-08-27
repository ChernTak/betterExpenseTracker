const goalModel = require('../models/goal.model');

// POST /api/goals — a proactive savings target the user sets up themselves
// (goal-gradient effect: name it, give it a number and a deadline to work
// toward). Distinct from Wishlist, which is reactive/nudge-triggered.
exports.createGoal = async (req, res) => {
  const { goalName, targetAmount, deadlineDate, priority, icon, notes } = req.body;

  if (!goalName || !goalName.trim()) {
    return res.status(400).json({ message: 'goalName is required' });
  }
  const parsedTarget = Number(targetAmount);
  if (!Number.isFinite(parsedTarget) || parsedTarget <= 0) {
    return res.status(400).json({ message: 'targetAmount must be a positive number' });
  }

  try {
    const result = await goalModel.createGoal({
      userId: req.user.userId,
      goalName: goalName.trim(),
      targetAmount: parsedTarget,
      deadlineDate,
      priority,
      icon,
      notes,
    });
    return res.status(201).json({ message: 'Goal created successfully', data: result.rows[0] });
  } catch (err) {
    console.error('Create goal error', err);
    return res.status(500).json({ message: 'Failed to create goal', error: err.message });
  }
};

// GET /api/goals
exports.listGoals = async (req, res) => {
  try {
    const result = await goalModel.listGoalsForUser(req.user.userId);
    return res.status(200).json(result.rows);
  } catch (err) {
    console.error('List goals error', err);
    return res.status(500).json({ message: 'Failed to fetch goals', error: err.message });
  }
};

// PUT /api/goals/:id
exports.updateGoal = async (req, res) => {
  const { id } = req.params;
  const { goalName, targetAmount, deadlineDate, status, priority, icon, notes } = req.body;

  if (targetAmount !== undefined && (!Number.isFinite(Number(targetAmount)) || Number(targetAmount) <= 0)) {
    return res.status(400).json({ message: 'targetAmount must be a positive number' });
  }
  if (status !== undefined && !['active', 'completed', 'cancelled'].includes(status)) {
    return res.status(400).json({ message: 'Invalid status' });
  }

  try {
    const result = await goalModel.updateGoal(id, req.user.userId, {
      goalName: goalName?.trim(),
      targetAmount: targetAmount !== undefined ? Number(targetAmount) : undefined,
      deadlineDate,
      status,
      priority,
      icon,
      notes,
    });
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Goal not found' });
    }
    return res.status(200).json({ message: 'Goal updated successfully', data: result.rows[0] });
  } catch (err) {
    console.error('Update goal error', err);
    return res.status(500).json({ message: 'Failed to update goal', error: err.message });
  }
};

// DELETE /api/goals/:id
exports.deleteGoal = async (req, res) => {
  const { id } = req.params;

  try {
    const result = await goalModel.deleteGoal(id, req.user.userId);
    if (result.rowCount === 0) {
      return res.status(404).json({ message: 'Goal not found' });
    }
    return res.status(200).json({ message: 'Goal deleted successfully' });
  } catch (err) {
    console.error('Delete goal error', err);
    return res.status(500).json({ message: 'Failed to delete goal', error: err.message });
  }
};

// GET /api/goals/:id/contributions
exports.listContributions = async (req, res) => {
  const { id } = req.params;

  try {
    const result = await goalModel.listContributions(id, req.user.userId);
    return res.status(200).json(result.rows);
  } catch (err) {
    console.error('List goal contributions error', err);
    return res.status(500).json({ message: 'Failed to fetch contributions', error: err.message });
  }
};

// POST /api/goals/:id/contributions — logs a contribution and bumps the
// goal's current_saved, auto-completing it once the target is reached.
exports.addContribution = async (req, res) => {
  const { id } = req.params;
  const { amount, note } = req.body;

  const parsedAmount = Number(amount);
  if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) {
    return res.status(400).json({ message: 'amount must be a positive number' });
  }

  try {
    const result = await goalModel.addContribution(id, req.user.userId, { amount: parsedAmount, note });
    if (!result) {
      return res.status(404).json({ message: 'Goal not found' });
    }
    return res.status(201).json({ message: 'Contribution added successfully', data: result });
  } catch (err) {
    console.error('Add goal contribution error', err);
    return res.status(500).json({ message: 'Failed to add contribution', error: err.message });
  }
};
