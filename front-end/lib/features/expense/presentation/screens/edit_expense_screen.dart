import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/expense_categories.dart';
import '../../../../core/events/expense_events.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/labeled_field.dart';
import '../../../../services/category_service.dart';
import '../../../../services/expense_service.dart';

/// Lets the user edit or delete a saved expense. A separate, simpler screen rather than an "edit mode" on AddExpenseScreen, since OCR/voice/math-mismatch/suggestion features are create-time-only.
class EditExpenseScreen extends StatefulWidget {
  final Map<String, dynamic> expense;

  const EditExpenseScreen({super.key, required this.expense});

  @override
  State<EditExpenseScreen> createState() => _EditExpenseScreenState();
}

class _EditExpenseScreenState extends State<EditExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _expenseService = ExpenseService();
  final _categoryService = CategoryService();

  late final TextEditingController _amountController;
  late final TextEditingController _merchantController;
  late String _category;
  String? _paymentMethod;
  late DateTime _transactionDate;
  List<CategoryItem> _categories = CategoryService.cached;
  bool _isSaving = false;
  bool _isDeleting = false;

  String get _expenseId => widget.expense['expense_id'] as String;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    _amountController = TextEditingController(
      text: ((e['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
    );
    _merchantController = TextEditingController(text: (e['merchant_name'] as String?) ?? '');
    _category =
        e['category'] as String? ??
        (CategoryService.cached.isNotEmpty ? CategoryService.cached.first.key : 'other');
    _paymentMethod = e['payment_method'] as String?;
    _transactionDate = DateTime.tryParse(e['transaction_date'] as String? ?? '') ?? DateTime.now();
    _loadCategories();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final categories = await _categoryService.fetchCategories();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      // The expense's saved category may no longer exist (deleted since) —
      // fall back rather than leaving no chip selected.
      if (categories.isNotEmpty && !categories.any((c) => c.key == _category)) {
        _category = categories.first.key;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _transactionDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _transactionDate = picked);
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await _expenseService.updateExpense(_expenseId, {
        'amount': double.parse(_amountController.text),
        'category': _category,
        'merchant_name': _merchantController.text.trim(),
        'payment_method': _paymentMethod,
        'transaction_date':
            '${_transactionDate.year.toString().padLeft(4, '0')}-'
            '${_transactionDate.month.toString().padLeft(2, '0')}-'
            '${_transactionDate.day.toString().padLeft(2, '0')}',
      });
      if (!mounted) return;
      notifyExpenseDataChanged();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isDeleting = true);
    try {
      await _expenseService.deleteExpense(_expenseId);
      if (!mounted) return;
      notifyExpenseDataChanged();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isSaving || _isDeleting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Expense'),
        actions: [
          IconButton(
            onPressed: busy ? null : _handleDelete,
            tooltip: 'Delete',
            icon: _isDeleting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline, color: AppColors.expense),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              LabeledField(
                label: 'Transaction Amount',
                child: TextFormField(
                  controller: _amountController,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(prefixText: 'RM ', border: InputBorder.none, filled: false),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: Validators.validateAmount,
                ),
              ),
              const SizedBox(height: 20),
              LabeledField(
                label: 'Choose Category',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _categories.map((c) {
                    final selected = c.key == _category;
                    return ChoiceChip(
                      label: Text(c.label),
                      avatar: Icon(c.icon, size: 18, color: selected ? Colors.white : c.color),
                      selected: selected,
                      onSelected: (_) => setState(() => _category = c.key),
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.surface,
                      labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textPrimary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                        side: BorderSide.none,
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),
              LabeledField(
                label: 'Merchant or Title',
                child: TextFormField(
                  controller: _merchantController,
                  decoration: const InputDecoration(hintText: 'Where did you spend?'),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: LabeledField(
                      label: 'Date',
                      child: InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 16, color: AppColors.textSecondary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${_transactionDate.year}-${_transactionDate.month.toString().padLeft(2, '0')}-${_transactionDate.day.toString().padLeft(2, '0')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledField(
                      label: 'Method',
                      child: DropdownButtonFormField<String>(
                        initialValue: _paymentMethod,
                        isExpanded: true,
                        decoration: const InputDecoration(hintText: 'Optional'),
                        items: kPaymentMethods
                            .map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Text(formatCategoryLabel(m), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => _paymentMethod = value),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: busy ? null : _handleSave,
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save Changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
