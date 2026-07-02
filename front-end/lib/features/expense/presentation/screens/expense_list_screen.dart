import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/expense_categories.dart';
import '../../../../core/events/expense_events.dart';
import '../../../../services/expense_service.dart';

/// Read-only full expense history, reached via "View All" from the Guide
/// tab. Adding expenses happens on the persistent Input tab, so this screen
/// has no add button of its own.
class ExpenseListScreen extends StatefulWidget {
  const ExpenseListScreen({super.key});

  @override
  State<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends State<ExpenseListScreen> {
  late Future<List<dynamic>> _expensesFuture;

  @override
  void initState() {
    super.initState();
    _expensesFuture = ExpenseService().fetchAllExpenses();
    expenseDataChanged.addListener(_refresh);
  }

  @override
  void dispose() {
    expenseDataChanged.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _expensesFuture = ExpenseService().fetchAllExpenses();
    });
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

            final data = snapshot.data ?? [];

            if (data.isEmpty) {
              return const Center(child: Text('No expenses found.'));
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: data.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final expense = data[index] as Map<String, dynamic>;
                final category = expense['category'] as String? ?? 'other';
                final amount = (expense['amount'] as num?)?.toDouble() ?? 0;
                final title = (expense['merchant_name'] as String?)?.trim();

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: categoryColor(category).withValues(alpha: 0.15),
                        child: Icon(categoryIcon(category), color: categoryColor(category), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (title != null && title.isNotEmpty) ? title : formatCategoryLabel(category),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${formatCategoryLabel(category)} · ${expense['transaction_date'] ?? ''}',
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
              },
            );
          },
        ),
      ),
    );
  }
}
