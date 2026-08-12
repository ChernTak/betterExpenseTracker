import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/events/category_events.dart';
import '../../../../core/events/expense_events.dart';
import '../../../../services/category_service.dart';
import '../../../../services/expense_service.dart';
import 'edit_expense_screen.dart';

/// Time-range filter for [ExpenseListScreen]: all history, today only, the
/// current calendar week (Monday-based), or the current calendar month.
enum _PeriodFilter { all, daily, weekly, monthly }

/// Full expense history, reached via "View All" from the Guide tab. Adding
/// expenses happens on the persistent Input tab, so this screen has no add
/// button of its own — but tapping an entry opens it for editing/deleting.
class ExpenseListScreen extends StatefulWidget {
  const ExpenseListScreen({super.key});

  @override
  State<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends State<ExpenseListScreen> {
  late Future<List<dynamic>> _expensesFuture;
  _PeriodFilter _filter = _PeriodFilter.all;

  @override
  void initState() {
    super.initState();
    _expensesFuture = ExpenseService().fetchAllExpenses();
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
      _expensesFuture = ExpenseService().fetchAllExpenses();
    });
  }

  // EditExpenseScreen fires expenseDataChanged on save/delete, and this
  // screen already listens for that (above), so no manual refresh needed
  // after the push returns.
  void _openEditExpense(Map<String, dynamic> expense) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => EditExpenseScreen(expense: expense)));
  }

  List<dynamic> _applyFilter(List<dynamic> data) {
    if (_filter == _PeriodFilter.all) return data;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));

    return data.where((item) {
      final expense = item as Map<String, dynamic>;
      final raw = expense['transaction_date'] as String?;
      final parsed = raw == null ? null : DateTime.tryParse(raw);
      if (parsed == null) return false;
      final date = DateTime(parsed.year, parsed.month, parsed.day);

      switch (_filter) {
        case _PeriodFilter.daily:
          return date == today;
        case _PeriodFilter.weekly:
          return !date.isBefore(startOfWeek) && !date.isAfter(today);
        case _PeriodFilter.monthly:
          return date.year == today.year && date.month == today.month;
        case _PeriodFilter.all:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<dynamic>>(
          future: _expensesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            final data = _applyFilter(snapshot.data ?? []);

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SegmentedButton<_PeriodFilter>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    segments: const [
                      ButtonSegment(value: _PeriodFilter.all, label: Text('All')),
                      ButtonSegment(value: _PeriodFilter.daily, label: Text('Daily')),
                      ButtonSegment(value: _PeriodFilter.weekly, label: Text('Weekly')),
                      ButtonSegment(value: _PeriodFilter.monthly, label: Text('Monthly')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (selection) => setState(() => _filter = selection.first),
                  ),
                ),
                Expanded(
                  child: data.isEmpty
                      ? const Center(child: Text('No expenses found.'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: data.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 4),
                          itemBuilder: (context, index) {
                            final expense = data[index] as Map<String, dynamic>;
                            final category = expense['category'] as String? ?? 'other';
                            final categoryItem = CategoryService.lookup(category);
                            final amount = (expense['amount'] as num?)?.toDouble() ?? 0;
                            final title = (expense['merchant_name'] as String?)?.trim();

                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _openEditExpense(expense),
                              child: Padding(
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
                                            '${categoryItem.label} · ${expense['transaction_date'] ?? ''}',
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
                                    const SizedBox(width: 4),
                                    const Icon(Icons.chevron_right, size: 20, color: AppColors.textSecondary),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
