import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/events/category_events.dart';
import '../../../../core/events/expense_events.dart';
import '../../../../services/budget_service.dart';
import '../../../../services/category_service.dart';
import '../../../../services/expense_service.dart';
import '../../../expense/presentation/screens/expense_list_screen.dart';

/// The "Guide" home tab: this month's spend-vs-budget ring, a real (not
/// simulated) insight computed from this month's budgets, and a feed of the
/// most recent expenses. Net worth and AI-generated tips from the mockup
/// aren't backed by any endpoint yet, so this only shows real data.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  final _budgetService = BudgetService();
  final _expenseService = ExpenseService();
  late Future<_GuideData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
    expenseDataChanged.addListener(_refresh);
    categoriesChanged.addListener(_refresh);
  }

  @override
  void dispose() {
    expenseDataChanged.removeListener(_refresh);
    categoriesChanged.removeListener(_refresh);
    super.dispose();
  }

  Future<_GuideData> _loadData() async {
    final results = await Future.wait([
      _budgetService.fetchDashboard(),
      _expenseService.fetchAllExpenses(),
    ]);
    return _GuideData(
      dashboard: results[0] as Map<String, dynamic>,
      recentExpenses: (results[1] as List<dynamic>).take(5).toList(),
    );
  }

  void _refresh() {
    setState(() {
      _dataFuture = _loadData();
    });
  }

  Future<void> _openExpenseList() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseListScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: FutureBuilder<_GuideData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [Padding(padding: const EdgeInsets.all(24), child: Text('Error: ${snapshot.error}'))],
            );
          }

          final data = snapshot.data!;
          final dashboard = data.dashboard;
          final budgets = (dashboard['budgets'] as List<dynamic>? ?? []);
          final totalLimit = (dashboard['totalLimit'] as num?)?.toDouble() ?? 0;
          final totalSpent = (dashboard['totalSpent'] as num?)?.toDouble() ?? 0;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (budgets.isNotEmpty) _InsightCard(budgets: budgets),
              if (budgets.isNotEmpty) const SizedBox(height: 16),
              _MonthlyBudgetCard(totalLimit: totalLimit, totalSpent: totalSpent),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Recent Activity', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  TextButton(onPressed: _openExpenseList, child: const Text('View All')),
                ],
              ),
              if (data.recentExpenses.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No expenses yet. Use the Input tab to add your first one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              else
                ...data.recentExpenses.map((e) => _ActivityTile(expense: e as Map<String, dynamic>)),
            ],
          );
        },
      ),
    );
  }
}

class _GuideData {
  final Map<String, dynamic> dashboard;
  final List<dynamic> recentExpenses;

  _GuideData({required this.dashboard, required this.recentExpenses});
}

class _MonthlyBudgetCard extends StatelessWidget {
  final double totalLimit;
  final double totalSpent;

  const _MonthlyBudgetCard({required this.totalLimit, required this.totalSpent});

  @override
  Widget build(BuildContext context) {
    final pct = totalLimit > 0 ? ((totalSpent / totalLimit) * 100).clamp(0, 999).toDouble() : 0.0;
    final remaining = (totalLimit - totalSpent).clamp(0, double.infinity);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surface, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Monthly Budget', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: 140,
              height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: CircularProgressIndicator(
                      value: totalLimit > 0 ? (totalSpent / totalLimit).clamp(0, 1) : 0,
                      strokeWidth: 10,
                      backgroundColor: AppColors.surface,
                      valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${pct.toStringAsFixed(0)}%',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primary),
                      ),
                      const Text(
                        'SPENT',
                        style: TextStyle(fontSize: 11, letterSpacing: 0.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Remaining', style: TextStyle(color: AppColors.textSecondary)),
              Flexible(
                child: Text(
                  'RM ${remaining.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: totalLimit > 0 ? (totalSpent / totalLimit).clamp(0, 1) : 0,
              minHeight: 8,
              backgroundColor: AppColors.surface,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final List<dynamic> budgets;

  const _InsightCard({required this.budgets});

  @override
  Widget build(BuildContext context) {
    final sorted = [...budgets]..sort(
      (a, b) => ((b as Map<String, dynamic>)['current_spend'] as num)
          .compareTo((a as Map<String, dynamic>)['current_spend'] as num),
    );
    final top = sorted.first as Map<String, dynamic>;
    final spent = (top['current_spend'] as num).toDouble();
    if (spent <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.primaryMuted, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Biggest category this month: ${CategoryService.lookup(top['category'] as String).label} '
              '— RM ${spent.toStringAsFixed(2)} spent.',
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final Map<String, dynamic> expense;

  const _ActivityTile({required this.expense});

  @override
  Widget build(BuildContext context) {
    final category = expense['category'] as String? ?? 'other';
    final categoryItem = CategoryService.lookup(category);
    final amount = (expense['amount'] as num?)?.toDouble() ?? 0;
    final title = (expense['merchant_name'] as String?)?.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: categoryItem.color.withValues(alpha: 0.15),
            child: Icon(categoryItem.icon, color: categoryItem.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (title != null && title.isNotEmpty) ? title : categoryItem.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${expense['transaction_date'] ?? ''}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '-RM ${amount.toStringAsFixed(2)}',
            style: const TextStyle(color: AppColors.expense, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
