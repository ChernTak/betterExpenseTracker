import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/expense_categories.dart';
import '../../../../core/events/category_events.dart';
import '../../../../core/events/expense_events.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/labeled_field.dart';
import '../../../../services/auto_categorization_service.dart';
import '../../../../services/camera_service.dart';
import '../../../../services/category_service.dart';
import '../../../../services/expense_nlp_parser_service.dart';
import '../../../../services/expense_service.dart';
import '../../../../services/ocr_service.dart';
import '../../data/datasources/ocr_datasource.dart';
import '../../data/datasources/voice_datasource.dart';

/// The "Input" tab. Manual, Scan (FR4.2/FR4.3, on-device Google ML Kit text
/// recognition + backend parsing) and Voice (FR4.4, on-device speech
/// transcription + on-device NLP extraction — see ExpenseNlpParserService)
/// are all wired to real capture; Voice here is the tap-to-talk single-shot
/// path that prefills this form. The separate hands-free "Ok App" wake-word
/// flow (VoiceCaptureController) runs app-wide from MainShell and shows its
/// own confirmation sheet instead of routing through this screen.
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
  final _voiceDatasource = VoiceDatasource();
  final _nlpParser = ExpenseNlpParserService();
  final _autoCategorizationService = AutoCategorizationService();

  List<CategoryItem> _categories = CategoryService.cached;
  String _category = CategoryService.cached.isNotEmpty ? CategoryService.cached.first.key : 'other';
  String? _paymentMethod;
  DateTime _transactionDate = DateTime.now();
  bool _isSaving = false;

  // True while the current _category is an auto-suggestion rather than an
  // explicit user pick, so we know whether the next chip tap is a
  // "correction" worth caching (AutoCategorizationService.recordCorrection).
  bool _categorySuggested = false;

  // Set once a scanned receipt is parsed, so _handleSave can link the
  // ocr_receipts audit row to the expense once the user confirms it.
  String? _receiptId;

  // Backend's subtotal+tax+rounding cross-check (FR4.3) on the last scanned
  // receipt. null = not checked, or the receipt didn't itemize enough to
  // validate; false = the printed total didn't reconcile with its own parts,
  // so _MathMismatchBanner prompts the user to double-check before saving.
  bool? _isMathValid;
  double? _computedTotal;

  String _inputMode = 'manual';

  final _categoryService = CategoryService();

  @override
  void initState() {
    super.initState();
    _loadCategories();
    categoriesChanged.addListener(_loadCategories);
  }

  @override
  void dispose() {
    categoriesChanged.removeListener(_loadCategories);
    _amountController.dispose();
    _merchantController.dispose();
    _ocrDatasource.dispose();
    _voiceDatasource.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final categories = await _categoryService.fetchCategories();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      // The previously selected category may no longer exist (e.g. deleted
      // from Manage Categories while this screen was open) — fall back to
      // the first available one rather than leaving a stale chip selected.
      if (categories.isNotEmpty && !categories.any((c) => c.key == _category)) {
        _category = categories.first.key;
      }
    });
  }

  Future<void> _handleScanReceipt() async {
    setState(() => _inputMode = 'scan');
    try {
      // ML Kit's document scanner (bounding-box edge detection, perspective
      // correction, cropping, auto-rotation) only ships an Android
      // implementation — iOS/macOS/etc. fall back to the plain camera
      // capture so Scan still works everywhere, just without those extras.
      final imagePath = Platform.isAndroid
          ? (await _ocrDatasource.scanDocument())?.path
          : await _cameraService.captureReceiptPhoto();
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

      String? scannedMerchant;
      setState(() {
        _receiptId = parsed['receiptId'] as String?;
        final merchant = parsed['merchant'] as String?;
        if (merchant != null && merchant.isNotEmpty) {
          _merchantController.text = merchant;
          scannedMerchant = merchant;
        }
        final amount = parsed['amount'] as num?;
        if (amount != null) _amountController.text = amount.toStringAsFixed(2);
        final date = parsed['date'] as String?;
        final parsedDate = date != null ? DateTime.tryParse(date) : null;
        if (parsedDate != null) _transactionDate = parsedDate;
        _isMathValid = parsed['isMathValid'] as bool?;
        final computedTotal = parsed['computedTotal'];
        _computedTotal = computedTotal is num ? computedTotal.toDouble() : null;
        _inputMode = 'manual';
      });
      if (scannedMerchant != null) {
        _suggestCategory(scannedMerchant!, inputSource: 'ocr');
      }
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

  /// Tap-to-talk voice capture (FR4.4): listens for a single utterance via
  /// the native on-device speech recognizer, extracts amount/merchant/date
  /// with ExpenseNlpParserService (pure on-device regex, no network call),
  /// and prefills this form the same way _handleScanReceipt prefills it
  /// from OCR — the user still reviews and taps Save themselves.
  Future<void> _handleVoiceInput() async {
    setState(() => _inputMode = 'voice');
    try {
      final transcript = await _voiceDatasource.listenOnce();
      if (transcript == null || transcript.trim().isEmpty) {
        throw Exception("Didn't catch that — try again in a quieter spot.");
      }

      final parsed = _nlpParser.parse(transcript);
      if (!mounted) return;

      String? spokenMerchant;
      setState(() {
        if (parsed.amount != null) {
          _amountController.text = parsed.amount!.toStringAsFixed(2);
        }
        if (parsed.merchantName != null) {
          _merchantController.text = parsed.merchantName!;
          spokenMerchant = parsed.merchantName;
        }
        if (parsed.transactionDate != null) {
          _transactionDate = parsed.transactionDate!;
        }
        _inputMode = 'manual';
      });

      final categorizationInput = spokenMerchant ?? transcript;
      _suggestCategory(categorizationInput, inputSource: 'voice');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Heard: "$transcript" — review before saving.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _inputMode = 'manual');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  /// Asks AutoCategorizationService to suggest a category for [merchantText]
  /// (cache-first, keyword-first, embedding-fallback) and, if still on this
  /// screen, updates the selected chip to match.
  Future<void> _suggestCategory(
    String merchantText, {
    required String inputSource,
  }) async {
    if (merchantText.trim().isEmpty) return;
    final suggestion = await _autoCategorizationService.categorize(
      merchantText,
      source: inputSource,
    );
    if (!mounted) return;
    setState(() {
      _category = suggestion.category;
      _categorySuggested = true;
    });
  }

  void _applyComputedTotal() {
    final computedTotal = _computedTotal;
    if (computedTotal == null) return;
    setState(() {
      _amountController.text = computedTotal.toStringAsFixed(2);
      _isMathValid = null;
      _computedTotal = null;
    });
  }

  void _dismissMathMismatch() {
    setState(() {
      _isMathValid = null;
      _computedTotal = null;
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
        _category = _categories.isNotEmpty ? _categories.first.key : 'other';
        _categorySuggested = false;
        _paymentMethod = null;
        _transactionDate = DateTime.now();
        _receiptId = null;
        _isMathValid = null;
        _computedTotal = null;
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
                  ),
                ],
                selected: {_inputMode},
                onSelectionChanged: (selection) {
                  final mode = selection.first;
                  if (mode == 'scan') {
                    _handleScanReceipt();
                  } else if (mode == 'voice') {
                    _handleVoiceInput();
                  } else {
                    setState(() => _inputMode = mode);
                  }
                },
              ),
            ),
            const SizedBox(height: 20),
            if (_inputMode == 'scan' || _inputMode == 'voice')
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: AppColors.primary),
                    const SizedBox(height: 16),
                    Text(
                      _inputMode == 'scan' ? 'Scanning receipt…' : 'Listening… say your expense',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              )
            else ...[
              if (_isMathValid == false && _computedTotal != null) ...[
                _MathMismatchBanner(
                  computedTotal: _computedTotal!,
                  onUseSuggested: _applyComputedTotal,
                  onDismiss: _dismissMathMismatch,
                ),
                const SizedBox(height: 20),
              ],
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
                  children: _categories.map((c) {
                    final selected = c.key == _category;
                    return ChoiceChip(
                      label: Text(c.label),
                      avatar: Icon(
                        c.icon,
                        size: 18,
                        color: selected ? Colors.white : c.color,
                      ),
                      selected: selected,
                      onSelected: (_) {
                        // A tap on a different chip while the current
                        // category is still an unconfirmed suggestion means
                        // the user is fixing it — worth caching so this
                        // merchant categorizes correctly next time.
                        if (_categorySuggested &&
                            c.key != _category &&
                            _merchantController.text.trim().isNotEmpty) {
                          _autoCategorizationService.recordCorrection(
                            _merchantController.text,
                            c.key,
                          );
                        }
                        setState(() {
                          _category = c.key;
                          _categorySuggested = false;
                        });
                      },
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
                  onFieldSubmitted: (value) =>
                      _suggestCategory(value, inputSource: 'manual'),
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

/// Shown after a scan when the backend's subtotal+tax+rounding cross-check
/// (FR4.3) didn't reconcile with the printed total — a misread digit or a
/// missed tax line is a likely cause, so this surfaces the reconciled
/// figure as a one-tap fix rather than silently trusting either number.
class _MathMismatchBanner extends StatelessWidget {
  final double computedTotal;
  final VoidCallback onUseSuggested;
  final VoidCallback onDismiss;

  const _MathMismatchBanner({
    required this.computedTotal,
    required this.onUseSuggested,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.warning,
                size: 20,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "The subtotal, tax and rounding on this receipt don't add "
                  'up to the printed total — double-check the amount before '
                  'saving.',
                  style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onDismiss,
                child: const Text('Keep scanned total'),
              ),
              TextButton(
                onPressed: onUseSuggested,
                child: Text('Use RM ${computedTotal.toStringAsFixed(2)}'),
              ),
            ],
          ),
        ],
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
