import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/events/category_events.dart';
import '../../../../core/events/expense_events.dart';
import '../../../../core/utils/validators.dart';
import '../../../../services/budget_service.dart';
import '../../../../services/category_service.dart';
import '../../../ai_insights/presentation/screens/ai_insights_screen.dart';
import '../../../categories/presentation/screens/manage_categories_screen.dart';
import '../../../wishlist/presentation/screens/wishlist_screen.dart';

/// The "Budgets" tab: a segmented toggle between the category limits view
/// (progress tiles, FR3.1-FR3.4, and 60/75/90% alerts, FR3.5) and the
/// Insights forecast (see ai_insights_screen.dart) — both are views onto the
/// same current-month budget data, so they share this one nav slot.
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: _BudgetTabToggle(
            index: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: const [_BudgetLimitsView(), InsightsScreen()],
          ),
        ),
      ],
    );
  }
}

class _BudgetTabToggle extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const _BudgetTabToggle({required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          _segment(
            label: 'Limits',
            selected: index == 0,
            onTap: () => onChanged(0),
          ),
          _segment(
            label: 'Forecast',
            selected: index == 1,
            onTap: () => onChanged(1),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _BudgetLimitsView extends StatefulWidget {
  const _BudgetLimitsView();

  @override
  State<_BudgetLimitsView> createState() => _BudgetLimitsViewState();
}

class _BudgetLimitsViewState extends State<_BudgetLimitsView> {
  final _budgetService = BudgetService();
  late Future<_BudgetsData> _dataFuture;

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

  Future<_BudgetsData> _loadData() async {
    final results = await Future.wait([
      _budgetService.fetchDashboard(),
      _budgetService.fetchRecentAlerts(limit: 5),
    ]);
    return _BudgetsData(
      dashboard: results[0] as Map<String, dynamic>,
      alerts: results[1] as List<dynamic>,
    );
  }

  void _refresh() {
    setState(() {
      _dataFuture = _loadData();
    });
  }

  Future<void> _openCreateBudgetDialog() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const _BudgetFormDialog(),
    );
    if (saved == true) {
      _refresh();
      notifyExpenseDataChanged();
    }
  }

  Future<void> _openEditBudgetDialog(Map<String, dynamic> budget) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BudgetFormDialog(
        budgetId: budget['budget_id'] as String,
        category: budget['category'] as String,
        initialLimit: (budget['monthly_limit'] as num).toDouble(),
      ),
    );
    if (saved == true) {
      _refresh();
      notifyExpenseDataChanged();
    }
  }

  Future<void> _openManageCategories() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ManageCategoriesScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: FutureBuilder<_BudgetsData>(
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

          final data = snapshot.data!;
          final budgets = (data.dashboard['budgets'] as List<dynamic>? ?? []);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (data.alerts.isNotEmpty) ...[
                const Text(
                  'Recent Alerts',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                ...data.alerts.map(
                  (a) => _AlertCard(
                    alert: a as Map<String, dynamic>,
                    budgets: budgets,
                  ),
                ),
                const SizedBox(height: 20),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Category Budgets',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.tune,
                      color: AppColors.textSecondary,
                    ),
                    tooltip: 'Manage Categories',
                    onPressed: _openManageCategories,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.add_circle_outline,
                      color: AppColors.primary,
                    ),
                    tooltip: 'Set a new budget',
                    onPressed: _openCreateBudgetDialog,
                  ),
                ],
              ),
              if (budgets.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No budgets set for this month yet. Tap + to set your first category limit.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              else
                ...budgets.map(
                  (b) => _CategoryBudgetTile(
                    budget: b as Map<String, dynamic>,
                    onTap: () => _openEditBudgetDialog(b),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BudgetsData {
  final Map<String, dynamic> dashboard;
  final List<dynamic> alerts;

  _BudgetsData({required this.dashboard, required this.alerts});
}

// Shared tiering so tiles/alerts agree on colour: <60% green, 60-75% amber,
// 75-90% orange, >90% red (mirrors budget.service.js).
Color _utilizationColor(double pct) {
  if (pct > 90) return AppColors.expense;
  if (pct >= 75) return Colors.deepOrange;
  if (pct >= 60) return AppColors.warning;
  return AppColors.primary;
}

class _CategoryBudgetTile extends StatelessWidget {
  final Map<String, dynamic> budget;
  final VoidCallback onTap;

  const _CategoryBudgetTile({required this.budget, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final category = budget['category'] as String? ?? '';
    final categoryItem = CategoryService.lookup(category);
    final limit = (budget['monthly_limit'] as num?)?.toDouble() ?? 0;
    final spent = (budget['current_spend'] as num?)?.toDouble() ?? 0;
    final pct = (budget['utilization_pct'] as num?)?.toDouble() ?? 0;
    final color = _utilizationColor(pct);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surface, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: categoryItem.color.withValues(alpha: 0.15),
                    child: Icon(
                      categoryItem.icon,
                      color: categoryItem.color,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      categoryItem.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${pct.toStringAsFixed(0)}%',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: limit > 0 ? (spent / limit).clamp(0, 1) : 0,
                  minHeight: 8,
                  backgroundColor: AppColors.surface,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'RM ${spent.toStringAsFixed(2)} of RM ${limit.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final Map<String, dynamic> alert;
  final List<dynamic> budgets;

  const _AlertCard({required this.alert, required this.budgets});

  // Wishlist is meant to hang off a real spending nudge rather than a
  // standalone add button (see AddToWishlistDialog's doc comment) — tapping
  // an alert opens it prefilled with whatever category that alert's budget
  // was for, since the alert row itself doesn't carry the category.
  void _openAddToWishlist(BuildContext context) {
    final budgetId = alert['budget_id'] as String?;
    final matchingBudget = budgets.cast<Map<String, dynamic>?>().firstWhere(
      (b) => b?['budget_id'] == budgetId,
      orElse: () => null,
    );

    showDialog<bool>(
      context: context,
      builder: (_) => AddToWishlistDialog(
        alertId: alert['alert_id'] as String?,
        initialCategory: matchingBudget?['category'] as String?,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final type = alert['alert_type'] as String? ?? '';
    final icon = switch (type) {
      'critical_alert' => Icons.error,
      'budget_warning' => Icons.warning_amber,
      _ => Icons.info_outline,
    };
    final color = switch (type) {
      'critical_alert' => AppColors.expense,
      'budget_warning' => Colors.deepOrange,
      _ => AppColors.warning,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(icon, color: color),
        title: Text(
          alert['message'] as String? ?? '',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: AppColors.textSecondary,
        ),
        onTap: () => _openAddToWishlist(context),
      ),
    );
  }
}

/// Handles both creating a new category budget and editing an existing
/// one's limit. In edit mode (budgetId supplied) the category is fixed.
class _BudgetFormDialog extends StatefulWidget {
  final String? budgetId;
  final String? category;
  final double? initialLimit;

  const _BudgetFormDialog({this.budgetId, this.category, this.initialLimit});

  @override
  State<_BudgetFormDialog> createState() => _BudgetFormDialogState();
}

class _BudgetFormDialogState extends State<_BudgetFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _limitController;
  final _budgetService = BudgetService();

  late String _category;
  bool _isSaving = false;

  bool get _isEditing => widget.budgetId != null;

  @override
  void initState() {
    super.initState();
    final cachedCategories = CategoryService.cached;
    _category =
        widget.category ??
        (cachedCategories.isNotEmpty ? cachedCategories.first.key : 'other');
    _limitController = TextEditingController(
      text: widget.initialLimit != null
          ? widget.initialLimit!.toStringAsFixed(2)
          : '',
    );
  }

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final limit = double.parse(_limitController.text);
      if (_isEditing) {
        await _budgetService.updateBudget(
          widget.budgetId!,
          monthlyLimit: limit,
        );
      } else {
        await _budgetService.saveBudget(
          category: _category,
          monthlyLimit: limit,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEditing
            ? 'Edit ${CategoryService.lookup(_category).label} Budget'
            : 'Set Monthly Budget',
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isEditing)
              DropdownButtonFormField<String>(
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: CategoryService.cached
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.key,
                        child: Text(
                          c.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _category = value!),
              ),
            if (!_isEditing) const SizedBox(height: 16),
            TextFormField(
              controller: _limitController,
              autofocus: _isEditing,
              decoration: const InputDecoration(
                labelText: 'Monthly Limit (RM)',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: Validators.validateAmount,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _handleSave,
          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40)),
          child: _isSaving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
