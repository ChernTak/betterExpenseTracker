import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/events/expense_events.dart';
import '../../../../core/utils/validators.dart';
import '../../../../services/income_service.dart';

/// Full income history (view/edit/delete); mirrors how ManageCategoriesScreen relates to the Budgets tab's quick-add dialog.
class IncomeHistoryScreen extends StatefulWidget {
  const IncomeHistoryScreen({super.key});

  @override
  State<IncomeHistoryScreen> createState() => _IncomeHistoryScreenState();
}

class _IncomeHistoryScreenState extends State<IncomeHistoryScreen> {
  final _incomeService = IncomeService();
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _incomeService.fetchIncomeHistory();
  }

  void _refresh() {
    setState(() {
      _future = _incomeService.fetchIncomeHistory();
    });
  }

  Future<void> _openAddDialog() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const LogIncomeDialog(),
    );
    if (saved == true) {
      _refresh();
      notifyExpenseDataChanged(); // Insights tab listens for this to refresh its own prediction
    }
  }

  Future<void> _openEditDialog(Map<String, dynamic> entry) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => LogIncomeDialog(
        incomeId: entry['income_id'] as String,
        initialAmount: (entry['amount'] as num).toDouble(),
        initialSource: entry['source'] as String?,
        initialDate: DateTime.parse(entry['received_date'] as String),
      ),
    );
    if (saved == true) {
      _refresh();
      notifyExpenseDataChanged();
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this income entry?'),
        content: Text(
          'RM ${(entry['amount'] as num).toDouble().toStringAsFixed(2)} '
          'on ${(entry['received_date'] as String).substring(0, 10)} will be removed '
          'and future predictions will no longer count it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.expense),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _incomeService.deleteIncome(entry['income_id'] as String);
      _refresh();
      notifyExpenseDataChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Income History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Log income',
            onPressed: _openAddDialog,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            final entries = snapshot.data ?? [];
            if (entries.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No income logged yet. Tap + to log your first paycheck.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              );
            }

            // Most recent first — the API returns oldest-first (needed for
            // the forecaster's interval math), reverse just for display.
            final displayEntries = entries.reversed.toList();

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: displayEntries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final entry = displayEntries[index] as Map<String, dynamic>;
                final amount = (entry['amount'] as num).toDouble();
                final source = (entry['source'] as String?)?.trim();
                final date = (entry['received_date'] as String).substring(
                  0,
                  10,
                );

                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.surface),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    title: Text(
                      (source != null && source.isNotEmpty) ? source : 'Income',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(date),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'RM ${amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: 'Edit',
                          onPressed: () => _openEditDialog(entry),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: AppColors.expense,
                          ),
                          tooltip: 'Delete',
                          onPressed: () => _confirmDelete(entry),
                        ),
                      ],
                    ),
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

/// Logs or edits an income event; public because it's shared between IncomeHistoryScreen and the Insights tab's quick-add button.
class LogIncomeDialog extends StatefulWidget {
  final String? incomeId;
  final double? initialAmount;
  final String? initialSource;
  final DateTime? initialDate;

  const LogIncomeDialog({
    super.key,
    this.incomeId,
    this.initialAmount,
    this.initialSource,
    this.initialDate,
  });

  @override
  State<LogIncomeDialog> createState() => _LogIncomeDialogState();
}

class _LogIncomeDialogState extends State<LogIncomeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _sourceController;
  final _incomeService = IncomeService();

  late DateTime _receivedDate;
  bool _isSaving = false;

  bool get _isEditing => widget.incomeId != null;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.initialAmount != null
          ? widget.initialAmount!.toStringAsFixed(2)
          : '',
    );
    _sourceController = TextEditingController(
      text: widget.initialSource ?? 'Salary',
    );
    _receivedDate = widget.initialDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _receivedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _receivedDate = picked);
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final amount = double.parse(_amountController.text);
      if (_isEditing) {
        await _incomeService.updateIncome(
          widget.incomeId!,
          amount: amount,
          source: _sourceController.text,
          receivedDate: _receivedDate,
        );
      } else {
        await _incomeService.logIncome(
          amount: amount,
          source: _sourceController.text,
          receivedDate: _receivedDate,
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
      title: Text(_isEditing ? 'Edit Income' : 'Log Income'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _amountController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Amount (RM)'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: Validators.validateAmount,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _sourceController,
              decoration: const InputDecoration(
                labelText: 'Source (e.g. Salary, Freelance)',
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date received'),
                child: Text(
                  '${_receivedDate.year}-${_receivedDate.month.toString().padLeft(2, '0')}-${_receivedDate.day.toString().padLeft(2, '0')}',
                ),
              ),
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
