import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/expense_categories.dart';
import '../../../../core/events/expense_events.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/labeled_field.dart';
import '../../../../services/camera_service.dart';
import '../../../../services/expense_service.dart';
import '../../../../services/ocr_service.dart';
import '../../data/datasources/ocr_datasource.dart';

/// The "Input" tab. Manual and Scan (FR4.2/FR4.3, on-device Google ML Kit
/// text recognition + backend parsing) are wired to the real backend; Voice
/// capture (FR4.4) is part of the not-yet-built AI module, so it stays
/// visible per the design spec but disabled rather than faking input.
class AddExpenseScreen extends StatefulWidget {
  /// Invoked after a successful save so the shell can switch back to the
  /// Guide tab. Optional so this screen can still be used standalone.
  final VoidCallback? onSaved;

  const AddExpenseScreen({super.key, this.onSaved});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  final _expenseService = ExpenseService();
  final _cameraService = CameraService();
  final _ocrDatasource = OcrDatasource();
  final _ocrService = OcrService();

  String _category = kExpenseCategories.first;
  String? _paymentMethod;
  DateTime _transactionDate = DateTime.now();
  bool _isSaving = false;

  // Set once a scanned receipt is parsed, so _handleSave can link the
  // ocr_receipts audit row to the expense once the user confirms it.
  String? _receiptId;

  String _inputMode = 'manual';

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _ocrDatasource.dispose();
    super.dispose();
  }

  Future<void> _handleScanReceipt() async {
    setState(() => _inputMode = 'scan');
    try {
      final imagePath = await _cameraService.captureReceiptPhoto();
      if (imagePath == null) {
        if (mounted) setState(() => _inputMode = 'manual');
        return;
      }

      final rawText = await _ocrDatasource.recognizeText(imagePath);
      if (rawText.trim().isEmpty) {
        throw Exception(
          'No text detected in that photo — try a clearer, well-lit shot.',
        );
      }

      final parsed = await _ocrService.parseReceipt(rawText);
      if (!mounted) return;

      setState(() {
        _receiptId = parsed['receiptId'] as String?;
        final merchant = parsed['merchant'] as String?;
        if (merchant != null && merchant.isNotEmpty) {
          _merchantController.text = merchant;
        }
        final amount = parsed['amount'] as num?;
        if (amount != null) _amountController.text = amount.toStringAsFixed(2);
        final date = parsed['date'] as String?;
        final parsedDate = date != null ? DateTime.tryParse(date) : null;
        if (parsedDate != null) _transactionDate = parsedDate;
        _inputMode = 'manual';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Receipt scanned — review the details before saving.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _inputMode = 'manual');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
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
        if (_merchantController.text.trim().isNotEmpty)
          'merchant_name': _merchantController.text.trim(),
        if (_paymentMethod != null) 'payment_method': _paymentMethod,
        if (_receiptId != null) 'receipt_id': _receiptId,
        'transaction_date':
            '${_transactionDate.year.toString().padLeft(4, '0')}-'
            '${_transactionDate.month.toString().padLeft(2, '0')}-'
            '${_transactionDate.day.toString().padLeft(2, '0')}',
      });
      if (!mounted) return;
      notifyExpenseDataChanged();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Expense saved')));
      setState(() {
        _amountController.clear();
        _merchantController.clear();
        _category = kExpenseCategories.first;
        _paymentMethod = null;
        _transactionDate = DateTime.now();
        _receiptId = null;
      });
      widget.onSaved?.call();
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
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: ListView(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'manual',
                    label: Text('Manual'),
                    icon: Icon(Icons.edit),
                  ),
                  ButtonSegment(
                    value: 'scan',
                    label: Text('Scan'),
                    icon: Icon(Icons.document_scanner_outlined),
                  ),
                  ButtonSegment(
                    value: 'voice',
                    label: Text('Voice'),
                    icon: Icon(Icons.mic_none),
                    enabled: false,
                  ),
                ],
                selected: {_inputMode},
                onSelectionChanged: (selection) {
                  final mode = selection.first;
                  if (mode == 'scan') {
                    _handleScanReceipt();
                  } else {
                    setState(() => _inputMode = mode);
                  }
                },
              ),
            ),
            const SizedBox(height: 20),
            if (_inputMode == 'scan')
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Column(
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text(
                      'Scanning receipt…',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              )
            else ...[
              LabeledField(
                label: 'Transaction Amount',
                child: TextFormField(
                  controller: _amountController,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    prefixText: 'RM ',
                    border: InputBorder.none,
                    filled: false,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: Validators.validateAmount,
                ),
              ),
              const SizedBox(height: 20),
              LabeledField(
                label: 'Choose Category',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kExpenseCategories.map((c) {
                    final selected = c == _category;
                    return ChoiceChip(
                      label: Text(formatCategoryLabel(c)),
                      avatar: Icon(
                        categoryIcon(c),
                        size: 18,
                        color: selected ? Colors.white : categoryColor(c),
                      ),
                      selected: selected,
                      onSelected: (_) => setState(() => _category = c),
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.surface,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : AppColors.textPrimary,
                      ),
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
                  decoration: const InputDecoration(
                    hintText: 'Where did you spend?',
                  ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                size: 16,
                                color: AppColors.textSecondary,
                              ),
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
                                child: Text(
                                  formatCategoryLabel(m),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _paymentMethod = value),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SmartSuggestionBanner(category: _category),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSaving ? null : _handleSave,
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save Expense'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A general reminder banner in the expense input screen's "smart
/// suggestion" slot. It is deliberately generic rather than pretending to be
/// personalized — real spending-pattern suggestions are Module 2 (AI
/// Insights), which isn't built yet.
class _SmartSuggestionBanner extends StatelessWidget {
  final String category;

  const _SmartSuggestionBanner({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lightbulb_outline,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Tip: recording the merchant and payment method helps you spot patterns later on the dashboard.',
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
