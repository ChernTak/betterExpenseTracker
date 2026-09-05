import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/expense_categories.dart';
import '../../../../core/events/expense_events.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/labeled_field.dart';
import '../../../../services/category_service.dart';
import '../../../../services/expense_service.dart';

/// Logs an expense pre-filled from a food recommendation venue; the "close the loop" action on VenueDetailScreen. Separate from AddExpenseScreen for the same reasons as EditExpenseScreen. Amount is left blank since the venue's price band is only a coarse guess, not what was actually paid.
class LogVenueExpenseScreen extends StatefulWidget {
  final String? initialMerchantName;
  final String? initialCategory;

  const LogVenueExpenseScreen({super.key, this.initialMerchantName, this.initialCategory});

  @override
  State<LogVenueExpenseScreen> createState() => _LogVenueExpenseScreenState();
}

class _LogVenueExpenseScreenState extends State<LogVenueExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _expenseService = ExpenseService();
  final _categoryService = CategoryService();

  final _amountController = TextEditingController();
  late final TextEditingController _merchantController;
  late String _category;
  String? _paymentMethod;
  DateTime _transactionDate = DateTime.now();
  List<CategoryItem> _categories = CategoryService.cached;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _merchantController = TextEditingController(text: widget.initialMerchantName ?? '');
    _category = widget.initialCategory ?? (CategoryService.cached.isNotEmpty ? CategoryService.cached.first.key : 'other');
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
      // fall back if the venue's default category was ever missing/deleted
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
      await _expenseService.createExpense({
        'amount': double.parse(_amountController.text),
        'category': _category,
        if (_merchantController.text.trim().isNotEmpty) 'merchant_name': _merchantController.text.trim(),
        if (_paymentMethod != null) 'payment_method': _paymentMethod,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log Expense')),
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
                  autofocus: true,
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
                onPressed: _isSaving ? null : _handleSave,
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save Expense'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
