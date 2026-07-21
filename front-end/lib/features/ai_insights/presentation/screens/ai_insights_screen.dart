import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/events/category_events.dart';
import '../../../../core/events/expense_events.dart';
import '../../../../services/category_service.dart';
import '../../../../services/expense_service.dart';
import '../../../../services/forecast_service.dart';
import '../../../../services/tier_b_inference_service.dart';
import '../../../income/presentation/screens/income_history_screen.dart';

/// The "Insights" tab: the end-of-month spend forecast (fixed bills still
/// due, projected variable spend, and today's safe-to-spend allowance).
/// Tier A (recurring bills) and the baseline heuristic come from
/// GET /api/insights/forecast; Tier B's variable-spend projection is then
/// optionally refined on-device via TierBInferenceService, overriding the
/// heuristic when the bundled model succeeds.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final _forecastService = ForecastService();
  final _expenseService = ExpenseService();
  final _tierBInferenceService = TierBInferenceService();
  late Future<Map<String, dynamic>> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadForecast();
    expenseDataChanged.addListener(_refresh);
    categoriesChanged.addListener(_refresh);
  }

  @override
  void dispose() {
    expenseDataChanged.removeListener(_refresh);
    categoriesChanged.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _dataFuture = _loadForecast();
    });
  }

  Future<Map<String, dynamic>> _loadForecast() async {
    final forecast = await _forecastService.fetchForecast();

    final totalBudget = (forecast['totalBudget'] as num?)?.toDouble();
    if (totalBudget == null || totalBudget <= 0) return forecast;

    final expenses = await _expenseService.fetchAllExpenses();
    final prediction = await _tierBInferenceService.predictRemainingMonthSpend(
      expenses: expenses,
      totalBudget: totalBudget,
      today: DateTime.now(),
    );
    if (prediction == null) return forecast;

    final fixedTotal =
        (forecast['fixedPaidSoFar'] as num).toDouble() +
        (forecast['fixedRemaining'] as num).toDouble();
    final variableSpentSoFar = (forecast['variableSpentSoFar'] as num)
        .toDouble();
    final projectedMonthTotal = fixedTotal + variableSpentSoFar + prediction;

    final now = DateTime.now();
    final modelVersion = await _tierBInferenceService.currentModelVersion();
    // Logged as p10=p50=p90 (all equal to the single point estimate) since
    // this is a point-estimate model, not a quantile one — see
    // ai/train_tier_b.py for why. Keeps forecast_predictions_log's schema
    // and evaluate_tier_b.py usable without a migration if quantiles come
    // back later.
    unawaited(
      _forecastService.logPrediction(
        month: now.month,
        year: now.year,
        p10: projectedMonthTotal,
        p50: projectedMonthTotal,
        p90: projectedMonthTotal,
        modelVersion: modelVersion,
      ),
    );

    return {
      ...forecast,
      'projectedVariableTotal': variableSpentSoFar + prediction,
      'projectedMonthTotal': projectedMonthTotal,
      'basis': 'on_device_model',
      'trendFactor': null,
      'isTrendingHigh': false,
    };
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Error: ${snapshot.error}'),
                ),
              ],
            );
          }

          final forecast = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'This Month\'s Forecast',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              _ProjectedTotalCard(forecast: forecast),
              const SizedBox(height: 12),
              _SafeToSpendCard(forecast: forecast),
              const SizedBox(height: 12),
              _FixedBillsCard(forecast: forecast),
              const SizedBox(height: 12),
              _ExpectedIncomeCard(forecast: forecast, onLogged: _refresh),
            ],
          );
        },
      ),
    );
  }
}

Color _budgetStatusColor(double? projected, double? budget) {
  if (budget == null || budget <= 0) return AppColors.textSecondary;
  final pct = projected! / budget * 100;
  if (pct > 100) return AppColors.expense;
  if (pct >= 90) return Colors.deepOrange;
  if (pct >= 75) return AppColors.warning;
  return AppColors.primary;
}

class _ProjectedTotalCard extends StatelessWidget {
  final Map<String, dynamic> forecast;

  const _ProjectedTotalCard({required this.forecast});

  @override
  Widget build(BuildContext context) {
    final projected =
        (forecast['projectedMonthTotal'] as num?)?.toDouble() ?? 0;
    final budget = (forecast['totalBudget'] as num?)?.toDouble();
    final basis = forecast['basis'] as String? ?? 'cold_start';
    final isTrendingHigh = forecast['isTrendingHigh'] as bool? ?? false;
    final color = _budgetStatusColor(projected, budget);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surface, width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Projected month-end total',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            'RM ${projected.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            budget != null
                ? 'of RM ${budget.toStringAsFixed(2)} total budget'
                : 'Set category budgets to compare against a limit',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          if (budget != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: budget > 0 ? (projected / budget).clamp(0, 1) : 0,
                minHeight: 8,
                backgroundColor: AppColors.surface,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            basis == 'cold_start'
                ? 'Still learning your spending habits — this estimate will get sharper as you log more expenses.'
                : basis == 'on_device_model'
                ? 'Powered by a trained model of your spending patterns, running on this device.'
                : isTrendingHigh
                ? 'Your recent spending has picked up — this projection has been adjusted upward.'
                : 'Based on your recent spending trend.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SafeToSpendCard extends StatelessWidget {
  final Map<String, dynamic> forecast;

  const _SafeToSpendCard({required this.forecast});

  @override
  Widget build(BuildContext context) {
    final dailySafeToSpend = (forecast['dailySafeToSpend'] as num?)?.toDouble();
    final daysRemaining = (forecast['daysRemaining'] as num?)?.toInt() ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.tips_and_updates, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dailySafeToSpend != null
                      ? 'Safe to spend today: RM ${dailySafeToSpend.toStringAsFixed(2)}'
                      : 'Set category budgets to unlock a daily safe-to-spend amount',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (dailySafeToSpend != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$daysRemaining day${daysRemaining == 1 ? '' : 's'} left this month, after fixed bills',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FixedBillsCard extends StatelessWidget {
  final Map<String, dynamic> forecast;

  const _FixedBillsCard({required this.forecast});

  @override
  Widget build(BuildContext context) {
    final fixedItems = (forecast['fixedItems'] as List<dynamic>? ?? []);
    final fixedRemaining =
        (forecast['fixedRemaining'] as num?)?.toDouble() ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surface, width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Fixed bills still due',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'RM ${fixedRemaining.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (fixedItems.isEmpty)
            const Text(
              'No recurring bills detected yet from your expense history.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            )
          else
            ...fixedItems.map(
              (item) => _FixedBillTile(item: item as Map<String, dynamic>),
            ),
        ],
      ),
    );
  }
}

/// Tier C — probabilistic income/payday prediction
/// (back-end/src/ml/income_forecaster.js). Additive/informational only: it
/// does not feed into _SafeToSpendCard's number above. Shows one tile per
/// detected recurring income source (e.g. "Salary"), or a prompt to log a
/// paycheck if nothing recurring has been detected yet.
class _ExpectedIncomeCard extends StatelessWidget {
  final Map<String, dynamic> forecast;
  final VoidCallback onLogged;

  const _ExpectedIncomeCard({required this.forecast, required this.onLogged});

  Future<void> _openLogIncomeDialog(BuildContext context) async {
    final logged = await showDialog<bool>(
      context: context,
      builder: (_) => const LogIncomeDialog(),
    );
    if (logged == true) onLogged();
  }

  Future<void> _openHistory(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const IncomeHistoryScreen()),
    );
    onLogged(); // edits/deletes made in history should refresh this prediction too
  }

  @override
  Widget build(BuildContext context) {
    final expectedIncome = forecast['expectedIncome'] as List<dynamic>? ?? [];
    final totalExpected = expectedIncome.fold<double>(
      0,
      (sum, item) =>
          sum +
          ((item as Map<String, dynamic>)['expectedAmount'] as num? ?? 0)
              .toDouble(),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surface, width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Expected income',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.history,
                      color: AppColors.textSecondary,
                    ),
                    tooltip: 'Income history',
                    onPressed: () => _openHistory(context),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.add_circle_outline,
                      color: AppColors.primary,
                    ),
                    tooltip: 'Log income',
                    onPressed: () => _openLogIncomeDialog(context),
                  ),
                ],
              ),
            ],
          ),
          if (expectedIncome.isEmpty)
            const Text(
              'Log a paycheck to start predicting your next income.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            )
          else ...[
            if (expectedIncome.length > 1) ...[
              Text(
                'Total expected: RM ${totalExpected.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
            ],
            ...expectedIncome.map(
              (item) => _ExpectedIncomeTile(item: item as Map<String, dynamic>),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExpectedIncomeTile extends StatelessWidget {
  final Map<String, dynamic> item;

  const _ExpectedIncomeTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final source = item['source'] as String? ?? 'unlabeled';
    final label = source == 'unlabeled'
        ? 'Income'
        : source[0].toUpperCase() + source.substring(1);
    final expectedAmount = (item['expectedAmount'] as num?)?.toDouble() ?? 0;
    final windowStart = item['windowStart'] as String? ?? '';
    final windowEnd = item['windowEnd'] as String? ?? '';
    final confidence = (item['confidence'] as num?)?.toDouble() ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(
                '~RM ${expectedAmount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          Text(
            'Expected $windowStart – $windowEnd (${(confidence * 100).toStringAsFixed(0)}% confidence)',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _FixedBillTile extends StatelessWidget {
  final Map<String, dynamic> item;

  const _FixedBillTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final category = item['category'] as String? ?? '';
    final categoryItem = CategoryService.lookup(category);
    final merchantName = item['merchantName'] as String?;
    final expectedAmount = (item['expectedAmount'] as num?)?.toDouble() ?? 0;
    final expectedDate = item['expectedDate'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: categoryItem.color.withValues(alpha: 0.15),
            child: Icon(categoryItem.icon, color: categoryItem.color, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              merchantName ?? categoryItem.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'RM ${expectedAmount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                'due $expectedDate',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
