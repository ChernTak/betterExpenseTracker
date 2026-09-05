const incomeModel = require('../models/income.model');

// POST /api/income — logs a single income event; manual entry since there's no bank integration to auto-detect it.
exports.logIncome = async (req, res) => {
  const { amount, source, receivedDate } = req.body;

  const parsedAmount = Number(amount);
  if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) {
    return res.status(400).json({ message: 'amount must be a positive number' });
  }

  try {
    const result = await incomeModel.createIncome({
      userId: req.user.userId,
      amount: parsedAmount,
      source,
      receivedDate,
    });
    return res.status(201).json({ message: 'Income logged successfully', data: result.rows[0] });
  } catch (err) {
    console.error('Log income error', err);
    return res.status(500).json({ message: 'Failed to log income', error: err.message });
  }
};

// GET /api/income — last 6 months of logged income, for display/editing.
exports.listIncome = async (req, res) => {
  try {
    const result = await incomeModel.listIncomeForUser(req.user.userId);
    return res.status(200).json(result.rows);
  } catch (err) {
    console.error('List income error', err);
    return res.status(500).json({ message: 'Failed to fetch income', error: err.message });
  }
};

exports.updateIncome = async (req, res) => {
  const { id } = req.params;
  const { amount, source, receivedDate } = req.body;

  if (amount !== undefined && (!Number.isFinite(Number(amount)) || Number(amount) <= 0)) {
    return res.status(400).json({ message: 'amount must be a positive number' });
  }

  try {
    const result = await incomeModel.updateIncome(id, req.user.userId, {
      amount: amount !== undefined ? Number(amount) : undefined,
      source,
      receivedDate,
    });
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Income entry not found' });
    }
    return res.status(200).json({ message: 'Income entry updated successfully', data: result.rows[0] });
  } catch (err) {
    console.error('Update income error', err);
    return res.status(500).json({ message: 'Failed to update income entry', error: err.message });
  }
};

exports.deleteIncome = async (req, res) => {
  const { id } = req.params;

  try {
    const result = await incomeModel.deleteIncome(id, req.user.userId);
    if (result.rowCount === 0) {
      return res.status(404).json({ message: 'Income entry not found' });
    }
    return res.status(200).json({ message: 'Income entry deleted successfully' });
  } catch (err) {
    console.error('Delete income error', err);
    return res.status(500).json({ message: 'Failed to delete income entry', error: err.message });
  }
};
