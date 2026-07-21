const forecastModel = require('../models/forecast.model');
const budgetModel = require('../models/budget.model');
const incomeModel = require('../models/income.model');
const forecaster = require('../ml/forecaster');
const incomeForecaster = require('../ml/income_forecaster');

function currentMonthYear() {
  const now = new Date();
  return { month: now.getUTCMonth() + 1, year: now.getUTCFullYear() };
}

// GET /api/insights/forecast — end-of-month spend projection, fixed-bill
// breakdown and daily safe-to-spend, computed on demand from this user's
// expense history and current-month budgets (see forecaster.js for the
// Tier A/B model).
exports.getForecast = async (req, res) => {
  try {
    const { month, year } = currentMonthYear();

    const [expenseResult, budgetResult, incomeResult] = await Promise.all([
      forecastModel.getExpenseHistoryForUser(req.user.userId),
      budgetModel.getBudgetsForUser(req.user.userId, month, year),
      incomeModel.listIncomeForUser(req.user.userId),
    ]);

    const forecast = forecaster.buildForecast({
      expenses: expenseResult.rows,
      budgetRows: budgetResult.rows,
      today: new Date(),
    });

    // Tier C — additive/informational only (see income_forecaster.js and
    // the plan's scope note): does not feed into dailySafeToSpend above.
    const expectedIncome = incomeForecaster.buildIncomeForecast(incomeResult.rows);

    // Tier B's trained-model prediction runs on-device (see
    // front-end/lib/services/tier_b_inference_service.dart) and overrides
    // this heuristic projection client-side when it succeeds.
    return res.status(200).json({ month, year, ...forecast, expectedIncome });
  } catch (err) {
    console.error('Get forecast error', err);
    return res.status(500).json({ message: 'Failed to compute forecast', error: err.message });
  }
};

// POST /api/insights/predictions — logs an on-device Tier B prediction for
// later accuracy evaluation (ai/evaluate_tier_b.py). Fire-and-forget from
// the app's perspective; failures here shouldn't affect what the user sees.
exports.logPrediction = async (req, res) => {
  const { month, year, p10, p50, p90, modelVersion } = req.body;

  if ([month, year, p10, p50, p90, modelVersion].some((v) => v === undefined)) {
    return res.status(400).json({ message: 'month, year, p10, p50, p90 and modelVersion are all required' });
  }

  try {
    await forecastModel.logPrediction({
      userId: req.user.userId,
      month: Number(month),
      year: Number(year),
      p10: Number(p10),
      p50: Number(p50),
      p90: Number(p90),
      modelVersion,
    });
    return res.status(201).json({ message: 'Prediction logged' });
  } catch (err) {
    console.error('Log prediction error', err);
    return res.status(500).json({ message: 'Failed to log prediction', error: err.message });
  }
};
