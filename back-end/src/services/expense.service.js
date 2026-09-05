const expenseModel = require('../models/expense.model');
const budgetService = require('./budget.service');
const ocrModel = require('../models/ocr.model');
const categoryModel = require('../models/category.model');

exports.postData = async (req, res) => {
  const userId = req.user.userId;
  const { amount, category, merchant_name, description, payment_method, transaction_date, receipt_id } = req.body;

  if (amount === undefined || !category) {
    return res.status(400).json({
      message: 'amount and category are required'
    });
  }

  // category is now a per-user table, not a DB-validated ENUM, so check ownership here.
  const categoryExists = await categoryModel.findByUserAndKey(userId, category);
  if (categoryExists.rows.length === 0) {
    return res.status(400).json({ message: `Unknown category: ${category}` });
  }

  expenseModel.createExpense(
    userId,
    { amount, category, merchant_name, description, payment_method, transaction_date },
    (err, result) => {
      if (err) {
        console.error('Error executing query', err.stack);
        return res.status(500).json({
          message: 'Database insert failed',
          error: err.message
        });
      }

      const created = result.rows[0];
      res.status(201).json({
        message: 'Expense created successfully',
        data: created
      });

      // FR4.3 — link OCR audit row to the created expense; fire-and-forget, must not block the save.
      if (receipt_id) {
        ocrModel
          .linkExpense(receipt_id, created.expense_id, userId)
          .catch((err) => console.error('Failed to link OCR receipt', err));
      }

      // FR3.5 — check 60/75/90% budget thresholds now that current_spend is updated; fire-and-forget.
      const txDate = new Date(created.transaction_date);
      budgetService
        .checkAndSendAlerts({
          userId,
          category: created.category,
          month: txDate.getUTCMonth() + 1,
          year: txDate.getUTCFullYear(),
          expenseId: created.expense_id,
        })
        .catch((err) => console.error('Budget alert check failed', err));
    }
  );
};

exports.fetchData = (req, res) => {
  expenseModel.getExpensesByUserId(req.user.userId, (err, result) => {
    if (err) {
      console.error('Error executing query', err.stack);
      return res.status(500).json({
        message: 'Database fetch failed',
        error: err.message
      });
    }

    return res.status(200).json(result.rows);
  });
};

exports.fetchById = (req, res) => {
  const { id } = req.params;

  expenseModel.getExpenseById(id, req.user.userId, (err, result) => {
    if (err) {
      console.error('Error executing query', err.stack);
      return res.status(500).json({
        message: 'Database fetch failed',
        error: err.message
      });
    }

    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Expense not found' });
    }

    return res.status(200).json(result.rows[0]);
  });
};

exports.deleteData = (req, res) => {
  const { id } = req.params;

  expenseModel.deleteExpenseById(id, req.user.userId, (err, result) => {
    if (err) {
      console.error('Error executing query', err.stack);
      return res.status(500).json({
        message: 'Database delete failed',
        error: err.message
      });
    }

    if (result.rowCount === 0) {
      return res.status(404).json({ message: 'Expense not found' });
    }

    return res.status(200).json({ message: 'Expense deleted successfully' });
  });
};

exports.updateData = async (req, res) => {
  const { id } = req.params;
  const {
    amount,
    category,
    merchant_name,
    description,
    payment_method,
    transaction_date
  } = req.body;

  if (category) {
    const categoryExists = await categoryModel.findByUserAndKey(req.user.userId, category);
    if (categoryExists.rows.length === 0) {
      return res.status(400).json({ message: `Unknown category: ${category}` });
    }
  }

  expenseModel.updateExpenseById(
    id,
    req.user.userId,
    { amount, category, merchant_name, description, payment_method, transaction_date },
    (err, result) => {
      if (err) {
        console.error('Error executing query', err.stack);
        return res.status(500).json({
          message: 'Database update failed',
          error: err.message
        });
      }

      if (result.rows.length === 0) {
        return res.status(404).json({ message: 'Expense not found' });
      }

      return res.status(200).json({
        message: 'Expense updated successfully',
        data: result.rows[0]
      });
    }
  );
};
