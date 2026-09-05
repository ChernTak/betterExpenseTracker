import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/events/category_events.dart';
import '../../../../core/events/expense_events.dart';
import '../../../../services/budget_service.dart';
import '../../../../services/category_service.dart';
import '../../../../services/expense_service.dart';
import '../../../expense/presentation/screens/edit_expense_screen.dart';
import '../../../expense/presentation/screens/expense_list_screen.dart';
import '../../../income/presentation/screens/income_history_screen.dart';
import '../../../wishlist/presentation/screens/wishlist_screen.dart';

/// Guide home tab: spend-vs-budget ring, real insight, recent-expenses feed, paged by month via PageView (no upper bound going forward).
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

// How far back page index 0 reaches — effectively unbounded for any real
// account. Forward has no such cap (see PageView's itemCount: null below).
const _currentPageIndex = 1200;

class _GuideScreenState extends State<GuideScreen> {
  late final PageController _pageController;
  late final DateTime _thisMonth;
  late DateTime _selectedMonth;
  int _refreshTick = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _thisMonth = DateTime(now.year, now.month);
    _selectedMonth = _thisMonth;
    _pageController = PageController(initialPage: _currentPageIndex);
    expenseDataChanged.addListener(_refresh);
    categoriesChanged.addListener(_refresh);
  }

  @override
  void dispose() {
    expenseDataChanged.removeListener(_refresh);
    categoriesChanged.removeListener(_refresh);
    _pageController.dispose();
    super.dispose();
  }

  DateTime _monthForPage(int page) =>
      DateTime(_thisMonth.year, _thisMonth.month - (_currentPageIndex - page));

  int _pageForMonth(DateTime month) =>
      _currentPageIndex +
      (month.year - _thisMonth.year) * 12 +
      (month.month - _thisMonth.month);

  // Each _MonthPage is keyed by (page, tick); bumping tick forces a fresh fetch when data changes elsewhere.
  void _refresh() => setState(() => _refreshTick++);

  void _goToPreviousMonth() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _goToNextMonth() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openMonthPicker() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => _MonthYearPickerDialog(initialMonth: _selectedMonth),
    );
    if (picked == null) return;

    final page = _pageForMonth(picked);
    if (page < 0) return; // outside the ~100-year backward range
    _pageController.jumpToPage(page);
  }

  Future<void> _openExpenseList() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExpenseListScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _MonthSelector(
            month: _selectedMonth,
            onPrevious: _goToPreviousMonth,
            onNext: _goToNextMonth,
            onTapMonth: _openMonthPicker,
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (page) =>
                setState(() => _selectedMonth = _monthForPage(page)),
            itemBuilder: (context, page) {
              if (page < 0) return const SizedBox.shrink();
              final month = _monthForPage(page);
              return _MonthPage(
                key: ValueKey('$page-$_refreshTick'),
                month: month,
                isCurrentMonth: month == _thisMonth,
                onOpenExpenseList: _openExpenseList,
              );
            },
          ),
        ),
      ],
    );
  }
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Lets Guide browse any month — chevrons step by one, tapping the label opens [_MonthYearPickerDialog] to jump directly.
class _MonthSelector extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onTapMonth;

  const _MonthSelector({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onTapMonth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            color: AppColors.textPrimary,
            onPressed: onPrevious,
            tooltip: 'Previous month',
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onTapMonth,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  '${_monthNames[month.month - 1]} ${month.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            color: AppColors.textPrimary,
            onPressed: onNext,
            tooltip: 'Next month',
          ),
        ],
      ),
    );
  }
}

/// Modal opened by tapping the month label — pick a year with the arrows,
/// then tap a month to jump straight there (pops that DateTime).
class _MonthYearPickerDialog extends StatefulWidget {
  final DateTime initialMonth;

  const _MonthYearPickerDialog({required this.initialMonth});

  @override
  State<_MonthYearPickerDialog> createState() => _MonthYearPickerDialogState();
}

class _MonthYearPickerDialogState extends State<_MonthYearPickerDialog> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.initialMonth.year;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() => _year--),
                  tooltip: 'Previous year',
                ),
                Text(
                  '$_year',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() => _year++),
                  tooltip: 'Next year',
                ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.8,
              children: [
                for (var m = 1; m <= 12; m++)
                  _MonthCell(
                    label: _monthNames[m - 1].substring(0, 3),
                    selected:
                        _year == widget.initialMonth.year &&
                        m == widget.initialMonth.month,
                    onTap: () => Navigator.pop(context, DateTime(_year, m)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MonthCell({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// One month's worth of Guide content — its own budget-dashboard fetch and
/// recent-activity list, independent of neighbouring pages in the PageView.
class _MonthPage extends StatefulWidget {
  final DateTime month;
  final bool isCurrentMonth;
  final VoidCallback onOpenExpenseList;

  const _MonthPage({
    super.key,
    required this.month,
    required this.isCurrentMonth,
    required this.onOpenExpenseList,
  });

  @override
  State<_MonthPage> createState() => _MonthPageState();
}

class _MonthPageState extends State<_MonthPage> {
  final _budgetService = BudgetService();
  final _expenseService = ExpenseService();
  late Future<_GuideData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<_GuideData> _loadData() async {
    final results = await Future.wait([
      _budgetService.fetchDashboard(
        month: widget.month.month,
        year: widget.month.year,
      ),
      _expenseService.fetchAllExpenses(),
    ]);

    final monthExpenses =
        (results[1] as List<dynamic>)
            .map((e) => e as Map<String, dynamic>)
            .where((e) {
              final date = DateTime.tryParse(
                e['transaction_date'] as String? ?? '',
              );
              return date != null &&
                  date.year == widget.month.year &&
                  date.month == widget.month.month;
            })
            .toList()
          ..sort(
            (a, b) => (b['transaction_date'] as String).compareTo(
              a['transaction_date'] as String,
            ),
          );

    return _GuideData(
      dashboard: results[0] as Map<String, dynamic>,
      recentExpenses: monthExpenses.take(5).toList(),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _dataFuture = _loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<_GuideData>(
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
          final dashboard = data.dashboard;
          final budgets = (dashboard['budgets'] as List<dynamic>? ?? []);
          final unbudgetedSpend =
              (dashboard['unbudgetedSpend'] as List<dynamic>? ?? []);
          final totalLimit = (dashboard['totalLimit'] as num?)?.toDouble() ?? 0;
          final totalSpent = (dashboard['totalSpent'] as num?)?.toDouble() ?? 0;
          final goalContributionsThisMonth =
              (dashboard['goalContributionsThisMonth'] as num?)?.toDouble() ?? 0;
          final availableToSpend =
              (dashboard['availableToSpend'] as num?)?.toDouble();

          // Merged view for the top-category insight only, so unbudgeted spend isn't invisible — NOT used by the Monthly Budget card or the Category Budgets list below.
          final chartEntries = [
            ...budgets,
            ...unbudgetedSpend.map(
              (u) => {
                'category': (u as Map<String, dynamic>)['category'],
                'current_spend': u['spent'],
              },
            ),
          ];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (chartEntries.isNotEmpty) _InsightCard(budgets: chartEntries),
              if (chartEntries.isNotEmpty) const SizedBox(height: 16),
              _MonthlyBudgetCard(
                totalLimit: totalLimit,
                totalSpent: totalSpent,
                budgets: budgets,
                goalContributionsThisMonth: goalContributionsThisMonth,
                availableToSpend: availableToSpend,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent Activity',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  TextButton(
                    onPressed: widget.onOpenExpenseList,
                    child: const Text('View All'),
                  ),
                ],
              ),
              if (data.recentExpenses.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    widget.isCurrentMonth
                        ? 'No expenses yet. Use the Input tab to add your first one.'
                        : 'No expenses logged in ${_monthNames[widget.month.month - 1]}.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                )
              else
                ...data.recentExpenses.map(
                  (e) => _ActivityTile(expense: e as Map<String, dynamic>),
                ),
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
  final List<dynamic> budgets;
  final double goalContributionsThisMonth;
  // null when no income has been logged for this month yet — the card
  // prompts to log it instead of showing a meaningless/misleading figure.
  final double? availableToSpend;

  const _MonthlyBudgetCard({
    required this.totalLimit,
    required this.totalSpent,
    required this.budgets,
    required this.goalContributionsThisMonth,
    required this.availableToSpend,
  });

  @override
  Widget build(BuildContext context) {
    final pct = totalLimit > 0
        ? ((totalSpent / totalLimit) * 100).clamp(0, 999).toDouble()
        : 0.0;
    final remaining = (totalLimit - totalSpent).clamp(0, double.infinity);

    // One slice per category (colour-matched, sized by share of totalSpent) plus a grey remaining slice so it still reads as spent-vs-limit.
    final slices = <_PieSlice>[
      for (final b in budgets)
        if (((b as Map<String, dynamic>)['current_spend'] as num).toDouble() >
            0)
          _PieSlice(
            color: CategoryService.lookup(b['category'] as String).color,
            value: (b['current_spend'] as num).toDouble(),
          ),
    ]..sort((a, b) => b.value.compareTo(a.value));
    if (remaining > 0) {
      slices.add(
        _PieSlice(color: AppColors.surface, value: remaining.toDouble()),
      );
    }

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
          const Text(
            'Monthly Budget',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
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
                    child: slices.isEmpty
                        ? const CircularProgressIndicator(
                            value: 0,
                            strokeWidth: 10,
                            backgroundColor: AppColors.surface,
                            valueColor: AlwaysStoppedAnimation(
                              AppColors.primary,
                            ),
                          )
                        : CustomPaint(
                            painter: _PieChartPainter(
                              slices: slices,
                              strokeWidth: 10,
                            ),
                          ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${pct.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const Text(
                        'SPENT',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.5,
                          color: AppColors.textSecondary,
                        ),
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
              const Text(
                'Remaining',
                style: TextStyle(color: AppColors.textSecondary),
              ),
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
          const Divider(height: 32),
          _AvailableToSpendSection(
            availableToSpend: availableToSpend,
            goalContributionsThisMonth: goalContributionsThisMonth,
          ),
          if (totalSpent > 0) ...[
            const SizedBox(height: 16),
            _CategoryLegend(budgets: budgets, totalSpent: totalSpent),
          ],
        ],
      ),
    );
  }
}

/// Ties Saving Goals / Wishlist framing to an actual number: income minus goal commitments minus real spend.
class _AvailableToSpendSection extends StatelessWidget {
  final double? availableToSpend;
  final double goalContributionsThisMonth;

  const _AvailableToSpendSection({
    required this.availableToSpend,
    required this.goalContributionsThisMonth,
  });

  @override
  Widget build(BuildContext context) {
    final available = availableToSpend;
    if (available == null) {
      return InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const IncomeHistoryScreen()),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Log this month\'s income to see what\'s available to spend',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      );
    }

    final isNegative = available < 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Available to spend',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            Text(
              'RM ${available.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isNegative ? AppColors.expense : AppColors.textPrimary,
              ),
            ),
          ],
        ),
        if (goalContributionsThisMonth > 0) ...[
          const SizedBox(height: 4),
          Text(
            'RM ${goalContributionsThisMonth.toStringAsFixed(2)} already put toward goals this month',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
        if (available > 0) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WishlistScreen()),
            ),
            child: const Row(
              children: [
                Icon(Icons.bookmark_border, size: 16, color: AppColors.primary),
                SizedBox(width: 6),
                Text(
                  'Got room — add something to your Wishlist',
                  style: TextStyle(color: AppColors.primary, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PieSlice {
  final Color color;
  final double value;

  const _PieSlice({required this.color, required this.value});
}

/// Draws each [_PieSlice] as a ring segment, clockwise from top — replaces the old single-colour CircularProgressIndicator.
class _PieChartPainter extends CustomPainter {
  final List<_PieSlice> slices;
  final double strokeWidth;

  _PieChartPainter({required this.slices, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (sum, s) => sum + s.value);
    if (total <= 0) return;

    final rect = Offset.zero & size;
    final inset = rect.deflate(strokeWidth / 2);
    var startAngle = -math.pi / 2;

    for (final slice in slices) {
      final sweepAngle = (slice.value / total) * 2 * math.pi;
      final paint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(inset, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) =>
      oldDelegate.slices != slices || oldDelegate.strokeWidth != strokeWidth;
}

/// Colour-coded key under the pie chart — one row per category with spend,
/// largest first, showing its share of this month's total spend.
class _CategoryLegend extends StatelessWidget {
  final List<dynamic> budgets;
  final double totalSpent;

  const _CategoryLegend({required this.budgets, required this.totalSpent});

  @override
  Widget build(BuildContext context) {
    final entries =
        budgets
            .map((b) => b as Map<String, dynamic>)
            .where((b) => (b['current_spend'] as num).toDouble() > 0)
            .toList()
          ..sort(
            (a, b) => (b['current_spend'] as num).compareTo(
              a['current_spend'] as num,
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Builder(
              builder: (context) {
                final categoryItem = CategoryService.lookup(
                  b['category'] as String,
                );
                final spent = (b['current_spend'] as num).toDouble();
                final share = totalSpent > 0 ? (spent / totalSpent) * 100 : 0.0;

                return Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: categoryItem.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        categoryItem.label,
                        style: const TextStyle(fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${share.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  final List<dynamic> budgets;

  const _InsightCard({required this.budgets});

  @override
  Widget build(BuildContext context) {
    final sorted = [...budgets]
      ..sort(
        (a, b) => ((b as Map<String, dynamic>)['current_spend'] as num)
            .compareTo((a as Map<String, dynamic>)['current_spend'] as num),
      );
    final top = sorted.first as Map<String, dynamic>;
    final spent = (top['current_spend'] as num).toDouble();
    if (spent <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Biggest category this month: ${CategoryService.lookup(top['category'] as String).label} '
              '— RM ${spent.toStringAsFixed(2)} spent.',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
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

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EditExpenseScreen(expense: expense)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: categoryItem.color.withValues(alpha: 0.15),
              child: Icon(
                categoryItem.icon,
                color: categoryItem.color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (title != null && title.isNotEmpty)
                        ? title
                        : categoryItem.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${expense['transaction_date'] ?? ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '-RM ${amount.toStringAsFixed(2)}',
              style: const TextStyle(
                color: AppColors.expense,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
