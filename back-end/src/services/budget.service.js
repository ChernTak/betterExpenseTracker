const budgetModel = require('../models/budget.model');
const alertModel = require('../models/alert.mode');
const userModel = require('../models/user.model');
const categoryModel = require('../models/category.model');
const incomeModel = require('../models/income.model');
const expenseModel = require('../models/expense.model');
const goalModel = require('../models/goal.model');
const { sendPushNotification } = require('../utils/pushNotifier');

function currentMonthYear() {
  const now = new Date();
  return { month: now.getUTCMonth() + 1, year: now.getUTCFullYear() };
}

// FR3.1 — create or update the spending limit for a category this month
exports.createBudget = async (req, res) => {
  const { category, monthlyLimit, alertThreshold } = req.body;

  if (!category) {
    return res.status(400).json({ message: 'category is required' });
  }
  const limit = Number(monthlyLimit);
  if (!Number.isFinite(limit) || limit <= 0) {
    return res.status(400).json({ message: 'monthlyLimit must be a positive number' });
  }

  const { month, year } = currentMonthYear();
  const targetMonth = Number(req.body.month) || month;
  const targetYear = Number(req.body.year) || year;

  try {
    // category used to be a fixed ENUM the DB validated automatically; it's
    // now a per-user table, so the app layer has to check it belongs to
    // this user before writing a budget for it.
    const categoryExists = await categoryModel.findByUserAndKey(req.user.userId, category);
    if (categoryExists.rows.length === 0) {
      return res.status(400).json({ message: `Unknown category: ${category}` });
    }

    const result = await budgetModel.upsertBudget({
      userId: req.user.userId,
      category,
      monthlyLimit: limit,
      month: targetMonth,
      year: targetYear,
      alertThreshold: alertThreshold !== undefined ? Number(alertThreshold) : undefined,
    });
    return res.status(201).json({ message: 'Budget saved successfully', data: result.rows[0] });
  } catch (err) {
    console.error('Create budget error', err);
    return res.status(500).json({ message: 'Failed to save budget', error: err.message });
  }
};

// FR3.4 — real-time spending per category, plus totals, for the dashboard
exports.listBudgets = async (req, res) => {
  const { month, year } = currentMonthYear();
  const targetMonth = Number(req.query.month) || month;
  const targetYear = Number(req.query.year) || year;

  try {
    const result = await budgetModel.getBudgetsForUser(req.user.userId, targetMonth, targetYear);
    const budgets = result.rows;
    const totals = budgets.reduce(
      (acc, b) => ({
        totalLimit: acc.totalLimit + Number(b.monthly_limit),
        totalSpent: acc.totalSpent + Number(b.current_spend),
      }),
      { totalLimit: 0, totalSpent: 0 },
    );

    // "Available to spend" — income this month minus what's already
    // committed to goals minus real total spend (not the budget-scoped
    // totalSpent above, which silently excludes unbudgeted categories).
    // Ties the "pay yourself first" (Goals) / "spend what's left"
    // (Wishlist) framing to an actual number instead of just UI copy.
    const monthStart = new Date(Date.UTC(targetYear, targetMonth - 1, 1));
    const monthEndExclusive = new Date(Date.UTC(targetYear, targetMonth, 1));
    const [incomeResult, spentResult, contributionsResult] = await Promise.all([
      incomeModel.getTotalIncomeForMonth(req.user.userId, monthStart, monthEndExclusive),
      expenseModel.getTotalSpentForMonth(req.user.userId, monthStart, monthEndExclusive),
      goalModel.getContributionsTotalForMonth(req.user.userId, monthStart, monthEndExclusive),
    ]);
    const totalIncome = Number(incomeResult.rows[0].total);
    const totalSpentThisMonth = Number(spentResult.rows[0].total);
    const goalContributionsThisMonth = Number(contributionsResult.rows[0].total);
    // null (rather than a misleading negative number) when no income has
    // been logged yet this month — the frontend prompts to log income instead.
    const availableToSpend =
      totalIncome > 0 ? totalIncome - goalContributionsThisMonth - totalSpentThisMonth : null;

    return res.status(200).json({
      month: targetMonth,
      year: targetYear,
      totalLimit: totals.totalLimit,
      totalSpent: totals.totalSpent,
      budgets,
      totalIncome,
      goalContributionsThisMonth,
      totalSpentThisMonth,
      availableToSpend,
    });
  } catch (err) {
    console.error('List budgets error', err);
    return res.status(500).json({ message: 'Failed to fetch budgets', error: err.message });
  }
};

exports.updateBudget = async (req, res) => {
  const { id } = req.params;
  const { monthlyLimit, alertThreshold } = req.body;

  if (monthlyLimit !== undefined && (!Number.isFinite(Number(monthlyLimit)) || Number(monthlyLimit) <= 0)) {
    return res.status(400).json({ message: 'monthlyLimit must be a positive number' });
  }

  try {
    const result = await budgetModel.updateBudget(id, req.user.userId, {
      monthlyLimit: monthlyLimit !== undefined ? Number(monthlyLimit) : undefined,
      alertThreshold: alertThreshold !== undefined ? Number(alertThreshold) : undefined,
    });

    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Budget not found' });
    }

    return res.status(200).json({ message: 'Budget updated successfully', data: result.rows[0] });
  } catch (err) {
    console.error('Update budget error', err);
    return res.status(500).json({ message: 'Failed to update budget', error: err.message });
  }
};

exports.deleteBudget = async (req, res) => {
  const { id } = req.params;

  try {
    const result = await budgetModel.deleteBudget(id, req.user.userId);
    if (result.rowCount === 0) {
      return res.status(404).json({ message: 'Budget not found' });
    }
    return res.status(200).json({ message: 'Budget deleted successfully' });
  } catch (err) {
    console.error('Delete budget error', err);
    return res.status(500).json({ message: 'Failed to delete budget', error: err.message });
  }
};

// FR3.5 — recent alert history, shown on the dashboard as a fallback/companion
// to the push notification (useful in dev when Firebase isn't configured).
exports.listRecentAlerts = async (req, res) => {
  const limit = Math.min(Number(req.query.limit) || 20, 100);

  try {
    const result = await alertModel.findRecentForUser(req.user.userId, limit);
    return res.status(200).json(result.rows);
  } catch (err) {
    console.error('List alerts error', err);
    return res.status(500).json({ message: 'Failed to fetch alerts', error: err.message });
  }
};

// Section 2.4.3 — loss-framed messaging: emphasise what's at stake rather
// than just restating the spend total.
function buildAlertMessage(category, alertType, remaining, utilizationPct) {
  const label = category.replace(/_/g, ' ');
  const pct = utilizationPct.toFixed(0);

  if (alertType === 'critical_alert') {
    return `You've used ${pct}% of your ${label} budget — only RM${remaining.toFixed(2)} left before you're over.`;
  }
  if (alertType === 'budget_warning') {
    return `Heads up — you're at ${pct}% of your ${label} budget. RM${remaining.toFixed(2)} remaining this month.`;
  }
  return `You're at ${pct}% of your ${label} budget. RM${remaining.toFixed(2)} left to stay on track.`;
}

// FR3.5 — three-tier threshold check: 60-75% gentle, 75-90% warning, >90%
// critical (matches the alert_type enum comments in 000_extensions_enums.sql).
// Not a route handler — called directly by expense.service.js right after an
// expense is saved, once the trg_sync_budget_spend trigger has already
// updated current_spend for that category/month.
exports.checkAndSendAlerts = async ({ userId, category, month, year, expenseId }) => {
  const result = await budgetModel.getBudgetByCategoryMonth(userId, category, month, year);
  const budget = result.rows[0];
  if (!budget || Number(budget.monthly_limit) <= 0) return; // no budget set for this category

  const utilizationPct = (Number(budget.current_spend) / Number(budget.monthly_limit)) * 100;

  let alertType = null;
  if (utilizationPct > 90) alertType = 'critical_alert';
  else if (utilizationPct >= 75) alertType = 'budget_warning';
  else if (utilizationPct >= 60) alertType = 'gentle_suggestion';
  if (!alertType) return;

  // Dedupe: only send each tier once per budget per month, not on every expense
  const startOfMonth = new Date(Date.UTC(year, month - 1, 1));
  const alreadySent = await alertModel.findRecentAlert(budget.budget_id, alertType, startOfMonth);
  if (alreadySent.rows.length > 0) return;

  const remaining = Math.max(Number(budget.monthly_limit) - Number(budget.current_spend), 0);
  const message = buildAlertMessage(category, alertType, remaining, utilizationPct);

  const alertResult = await alertModel.createAlert({
    userId,
    expenseId,
    budgetId: budget.budget_id,
    alertType,
    message,
  });
  const alertId = alertResult.rows[0].alert_id;

  const userResult = await userModel.findById(userId);
  const fcmToken = userResult.rows[0]?.fcm_token;

  await sendPushNotification(fcmToken, {
    title: 'Budget Alert',
    body: message,
    data: { type: 'budget_alert', category, alertType, budgetId: budget.budget_id, alertId },
  });
};
