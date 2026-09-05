const budgetModel = require('../models/budget.model');
const { DEFAULT_MEALS_PER_DAY } = require('../config/dining');

const DINING_CATEGORY = 'food_dining';

// Mirrors budget.service.js's currentMonthYear — UTC getters so the bucket
// this resolves to is independent of the host's local timezone offset.
function currentMonthYear() {
  const now = new Date();
  return { month: now.getUTCMonth() + 1, year: now.getUTCFullYear() };
}

function daysLeftInMonth(month, year) {
  const daysInMonth = new Date(Date.UTC(year, month, 0)).getUTCDate();
  const today = new Date().getUTCDate();
  return Math.max(daysInMonth - today + 1, 1); // inclusive of today, never 0
}

// C_meal = remaining food_dining budget / (days left * meals/day); null mealCap means no budget set, not a cap of zero.
exports.getDiningContext = async (userId) => {
  const { month, year } = currentMonthYear();
  const result = await budgetModel.getBudgetByCategoryMonth(userId, DINING_CATEGORY, month, year);
  const budget = result.rows[0];

  if (!budget || Number(budget.monthly_limit) <= 0) {
    return { hasBudget: false, mealCap: null, remainingBudget: null, daysLeft: null };
  }

  const remainingBudget = Math.max(Number(budget.monthly_limit) - Number(budget.current_spend), 0);
  const daysLeft = daysLeftInMonth(month, year);
  const mealCap = remainingBudget / (daysLeft * DEFAULT_MEALS_PER_DAY);

  return { hasBudget: true, mealCap, remainingBudget, daysLeft, budgetId: budget.budget_id };
};
