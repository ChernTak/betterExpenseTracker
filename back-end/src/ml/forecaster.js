// End-of-month spend forecast, pure functions, no DB access. No income tracking here, so Safe-to-Spend uses budgets.monthly_limit; no LightGBM, so Tier B is a day-of-week weighted average with a trend multiplier instead of a trained regressor.

const MS_PER_DAY = 24 * 60 * 60 * 1000;
const FIXED_VARIANCE_THRESHOLD = 0.05; // ±5%, per the doc's Tier A rule
const FIXED_INTERVAL_MIN_DAYS = 26;
const FIXED_INTERVAL_MAX_DAYS = 34; // ~30±4, loosened from the doc's ±2 for noisier real data
const COLD_START_TRANSACTION_COUNT = 30; // per the doc's Tier B cold-start rule
const TREND_FACTOR_MIN = 0.5;
const TREND_FACTOR_MAX = 2.0;
const TRENDING_HIGH_THRESHOLD = 1.15;

function normalizeMerchant(merchantName) {
  return (merchantName || '').trim().toLowerCase();
}

// pg's DATE columns are local-midnight JS Dates, which silently shift a day under getUTC*()/toISOString() in a UTC+8 host; normalize to UTC-midnight once here (see buildForecast) so the rest of the module can use them safely.
function toDateOnly(date) {
  const d = new Date(date);
  return new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
}

function daysBetween(a, b) {
  return Math.abs(new Date(b) - new Date(a)) / MS_PER_DAY;
}

function mean(values) {
  return values.reduce((sum, v) => sum + v, 0) / values.length;
}

function stddev(values, avg) {
  return Math.sqrt(mean(values.map((v) => (v - avg) ** 2)));
}

// Groups by normalized merchant (falling back to category when merchant_name is null), then flags a group as a recurring fixed bill at >=2 occurrences, <=5% amount variance, and ~30-day cadence.
function detectRecurringGroups(expenses) {
  const groups = new Map();

  for (const expense of expenses) {
    const merchant = normalizeMerchant(expense.merchant_name);
    const key = merchant ? `merchant:${merchant}` : `category:${expense.category}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(expense);
  }

  const fixedGroups = [];
  for (const [key, rows] of groups) {
    if (rows.length < 2) continue;

    const sorted = [...rows].sort((a, b) => new Date(a.transaction_date) - new Date(b.transaction_date));
    const amounts = sorted.map((r) => Number(r.amount));
    const avgAmount = mean(amounts);
    if (avgAmount <= 0) continue;
    const variance = stddev(amounts, avgAmount) / avgAmount;

    const intervals = [];
    for (let i = 1; i < sorted.length; i += 1) {
      intervals.push(daysBetween(sorted[i - 1].transaction_date, sorted[i].transaction_date));
    }
    const avgInterval = mean(intervals);

    if (variance <= FIXED_VARIANCE_THRESHOLD && avgInterval >= FIXED_INTERVAL_MIN_DAYS && avgInterval <= FIXED_INTERVAL_MAX_DAYS) {
      const last = sorted[sorted.length - 1];
      fixedGroups.push({
        key,
        category: last.category,
        merchantName: last.merchant_name || null,
        avgAmount,
        avgIntervalDays: avgInterval,
        lastDate: last.transaction_date,
        occurrences: sorted.length,
        expenseIds: new Set(sorted.map((r) => r.expense_id)),
      });
    }
  }

  return fixedGroups;
}

function startOfMonth(date) {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1));
}

function daysInMonth(date) {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0)).getUTCDate();
}

// Predicts each fixed group's next due date: if due this month and unpaid it counts toward fixedRemaining; if already paid this month it's in spent-so-far and not double counted.
function projectFixedBills(fixedGroups, expensesThisMonth, today) {
  const monthStart = startOfMonth(today);
  const monthEnd = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth() + 1, 0));

  let fixedPaidSoFar = 0;
  let fixedRemaining = 0;
  const fixedItems = [];

  for (const group of fixedGroups) {
    const paidThisMonth = expensesThisMonth.find((e) => group.expenseIds.has(e.expense_id));
    if (paidThisMonth) {
      fixedPaidSoFar += Number(paidThisMonth.amount);
      continue;
    }

    const nextDue = new Date(new Date(group.lastDate).getTime() + group.avgIntervalDays * MS_PER_DAY);
    if (nextDue >= monthStart && nextDue <= monthEnd) {
      fixedRemaining += group.avgAmount;
      fixedItems.push({
        merchantName: group.merchantName,
        category: group.category,
        expectedAmount: Math.round(group.avgAmount * 100) / 100,
        expectedDate: nextDue.toISOString().slice(0, 10),
      });
    }
  }

  return { fixedPaidSoFar, fixedRemaining, fixedItems };
}

// Rest-of-month variable spend: simple run-rate until 30 historical transactions exist, then a day-of-week baseline scaled by a recent-trend multiplier.
function projectVariableSpend(variableExpensesHistory, variableExpensesThisMonth, today) {
  const monthStart = startOfMonth(today);
  const totalDaysInMonth = daysInMonth(today);
  const daysElapsed = today.getUTCDate();
  const daysRemaining = totalDaysInMonth - daysElapsed;

  const variableSpentSoFar = variableExpensesThisMonth.reduce((sum, e) => sum + Number(e.amount), 0);

  if (variableExpensesHistory.length < COLD_START_TRANSACTION_COUNT) {
    const dailyAvg = daysElapsed > 0 ? variableSpentSoFar / daysElapsed : 0;
    return {
      basis: 'cold_start',
      trendFactor: 1,
      isTrendingHigh: false,
      variableSpentSoFar,
      projectedVariableTotal: variableSpentSoFar + dailyAvg * daysRemaining,
    };
  }

  const ninetyDaysAgo = new Date(monthStart.getTime() - 90 * MS_PER_DAY);
  const fourteenDaysAgo = new Date(monthStart.getTime() - 14 * MS_PER_DAY);
  const baselineWindow = variableExpensesHistory.filter((e) => new Date(e.transaction_date) >= ninetyDaysAgo);

  const perDayTotals = new Map(); // dateString -> total, so multiple same-day expenses average correctly
  for (const e of baselineWindow) {
    const dateStr = new Date(e.transaction_date).toISOString().slice(0, 10);
    perDayTotals.set(dateStr, (perDayTotals.get(dateStr) || 0) + Number(e.amount));
  }

  const dayOfWeekTotals = Array(7).fill(0);
  const dayOfWeekCounts = Array(7).fill(0);
  const recentTotals = [];
  const priorTotals = [];

  for (const [dateStr, total] of perDayTotals) {
    const d = new Date(dateStr);
    dayOfWeekTotals[d.getUTCDay()] += total;
    dayOfWeekCounts[d.getUTCDay()] += 1;
    if (d >= fourteenDaysAgo) recentTotals.push(total);
    else priorTotals.push(total);
  }

  const dayOfWeekBaseline = dayOfWeekTotals.map((total, i) => (dayOfWeekCounts[i] > 0 ? total / dayOfWeekCounts[i] : 0));

  const recentAvg = recentTotals.length > 0 ? mean(recentTotals) : 0;
  const priorAvg = priorTotals.length > 0 ? mean(priorTotals) : 0;
  let trendFactor = priorAvg > 0 ? recentAvg / priorAvg : 1;
  trendFactor = Math.min(TREND_FACTOR_MAX, Math.max(TREND_FACTOR_MIN, trendFactor));

  let projectedRemaining = 0;
  for (let i = 1; i <= daysRemaining; i += 1) {
    const futureDate = new Date(today.getTime() + i * MS_PER_DAY);
    projectedRemaining += dayOfWeekBaseline[futureDate.getUTCDay()] * trendFactor;
  }

  return {
    basis: 'trend_model',
    trendFactor,
    isTrendingHigh: trendFactor > TRENDING_HIGH_THRESHOLD,
    variableSpentSoFar,
    projectedVariableTotal: variableSpentSoFar + projectedRemaining,
  };
}

// expenses: last ~4 months (expense_id, amount, category, merchant_name, transaction_date); budgetRows: this month's monthly_limit rows; today: injectable Date for testing.
function buildForecast({ expenses, budgetRows, today = new Date() }) {
  const normalizedToday = toDateOnly(today);
  const normalizedExpenses = expenses.map((e) => ({ ...e, transaction_date: toDateOnly(e.transaction_date) }));

  return computeForecast({ expenses: normalizedExpenses, budgetRows, today: normalizedToday });
}

function computeForecast({ expenses, budgetRows, today }) {
  const monthStart = startOfMonth(today);
  const expensesThisMonth = expenses.filter((e) => new Date(e.transaction_date) >= monthStart);

  const fixedGroups = detectRecurringGroups(expenses);
  const fixedExpenseIds = new Set(fixedGroups.flatMap((g) => [...g.expenseIds]));

  const { fixedPaidSoFar, fixedRemaining, fixedItems } = projectFixedBills(fixedGroups, expensesThisMonth, today);

  const variableExpensesHistory = expenses.filter((e) => !fixedExpenseIds.has(e.expense_id));
  const variableExpensesThisMonth = expensesThisMonth.filter((e) => !fixedExpenseIds.has(e.expense_id));
  const variableForecast = projectVariableSpend(variableExpensesHistory, variableExpensesThisMonth, today);

  const fixedTotal = fixedPaidSoFar + fixedRemaining;
  const projectedMonthTotal = fixedTotal + variableForecast.projectedVariableTotal;

  const totalBudget = budgetRows.length > 0 ? budgetRows.reduce((sum, b) => sum + Number(b.monthly_limit), 0) : null;

  const totalDaysInMonth = daysInMonth(today);
  const daysRemaining = totalDaysInMonth - today.getUTCDate();
  // +1 so today itself is still covered by the daily allowance being computed
  const daysRemainingInclusive = daysRemaining + 1;

  const dailySafeToSpend =
    totalBudget != null
      ? Math.max(0, (totalBudget - fixedTotal - variableForecast.variableSpentSoFar) / daysRemainingInclusive)
      : null;

  return {
    fixedPaidSoFar: Math.round(fixedPaidSoFar * 100) / 100,
    fixedRemaining: Math.round(fixedRemaining * 100) / 100,
    fixedItems,
    variableSpentSoFar: Math.round(variableForecast.variableSpentSoFar * 100) / 100,
    projectedVariableTotal: Math.round(variableForecast.projectedVariableTotal * 100) / 100,
    basis: variableForecast.basis,
    trendFactor: Math.round(variableForecast.trendFactor * 1000) / 1000,
    isTrendingHigh: variableForecast.isTrendingHigh,
    projectedMonthTotal: Math.round(projectedMonthTotal * 100) / 100,
    totalBudget,
    dailySafeToSpend: dailySafeToSpend != null ? Math.round(dailySafeToSpend * 100) / 100 : null,
    daysRemaining: daysRemainingInclusive,
  };
}

module.exports = {
  detectRecurringGroups,
  projectFixedBills,
  projectVariableSpend,
  buildForecast,
};
