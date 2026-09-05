import 'dart:io';

import 'package:flutter/foundation.dart';
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
import '../../../../services/receipt_ner/receipt_field_extractor.dart';
import '../../../../services/receipt_ner/receipt_field_normalizer.dart';
import '../../../../services/receipt_ner/receipt_ner_service.dart';
import '../../data/datasources/ocr_datasource.dart';
import '../../data/datasources/voice_datasource.dart';
import '../voice/voice_capture_controller.dart';

/// The "Input" tab: Manual, Scan and Voice all prefill this form. Voice here is tap-to-talk single-shot; the separate hands-free wake-word flow (VoiceCaptureController) runs its own confirmation sheet but is passed in as [voiceController] since both share the mic.
class AddExpenseScreen extends StatefulWidget {
  /// Invoked after a successful save so the shell can switch back to the
  /// Guide tab. Optional so this screen can still be used standalone.
  final VoidCallback? onSaved;

  /// MainShell's hands-free controller, so tap-to-talk can pause wake-word listening — otherwise Vosk keeps holding the mic and speech_to_text silently never gets anything. Optional for standalone use.
  final VoiceCaptureController? voiceController;

  const AddExpenseScreen({super.key, this.onSaved, this.voiceController});

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

  // True while _category is an auto-suggestion, so the next chip tap can be cached as a correction.
  bool _categorySuggested = false;

  // Set once a scanned receipt is parsed, so _handleSave can link the
  // ocr_receipts audit row to the expense once the user confirms it.
  String? _receiptId;

  // Backend's subtotal+tax+rounding cross-check: null = not checked/insufficient data, false = mismatch (triggers _MathMismatchBanner).
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
      // Previously selected category may have been deleted elsewhere; fall back to the first available one.
      if (categories.isNotEmpty && !categories.any((c) => c.key == _category)) {
        _category = categories.first.key;
      }
    });
  }

  Future<void> _handleScanReceipt() async {
    setState(() => _inputMode = 'scan');
    try {
      // ML Kit's document scanner is Android-only; other platforms fall back to a plain camera capture.
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

      // Backend regex parser: still the only source for math validation, and the per-field fallback for the on-device model below.
      final parsed = await _ocrService.parseReceipt(rawText);

      // On-device LayoutLMv3 extraction, primary source when available; any failure here just leaves the regex result as-is.
      ReceiptNerFields? v3Fields;
      RecognizedPage? page;
      try {
        page = await _ocrDatasource.recognizeWords(imagePath);
        final imageBytes = await File(imagePath).readAsBytes();
        final nerService = await ReceiptNerService.create();
        v3Fields = nerService?.extractFields(page: page, imageBytes: imageBytes);
      } catch (_) {
        v3Fields = null;
      }

      if (kDebugMode) {
        // Logged separately from the words list so the summary stays short and grep-able even for a busy receipt.
        debugPrint(
          'receipt scan — v3: '
          '${v3Fields == null ? 'unavailable' : 'company="${v3Fields.company}" date="${v3Fields.date}" total="${v3Fields.total}" address="${v3Fields.address}"'}'
          ' | regex: merchant="${parsed['merchant']}" date="${parsed['date']}" amount="${parsed['amount']}"',
        );
        if (page != null) {
          debugPrint(
            'receipt scan — ML Kit words (${page.words.length}, ${page.imageWidth}x${page.imageHeight}): '
            '${page.words.map((w) => w.text).join(' | ')}',
          );
        }
      }

      if (!mounted) return;

      String? scannedMerchant;
      setState(() {
        _receiptId = parsed['receiptId'] as String?;

        final regexMerchant = parsed['merchant'] as String?;
        final merchant = (v3Fields != null && v3Fields.company.isNotEmpty)
            ? v3Fields.company
            : regexMerchant;
        if (merchant != null && merchant.isNotEmpty) {
          _merchantController.text = merchant;
          scannedMerchant = merchant;
        }

        final regexAmount = (parsed['amount'] as num?)?.toDouble();
        final v3Amount = (v3Fields != null && v3Fields.total.isNotEmpty)
            ? ReceiptFieldNormalizer.parseAmount(v3Fields.total)
            : null;
        final amount = v3Amount ?? regexAmount;
        if (amount != null) _amountController.text = amount.toStringAsFixed(2);

        final regexDate = parsed['date'] as String?;
        final v3Date = (v3Fields != null && v3Fields.date.isNotEmpty)
            ? ReceiptFieldNormalizer.parseDateToIso(v3Fields.date)
            : null;
        final date = v3Date ?? regexDate;
        final parsedDate = date != null ? DateTime.tryParse(date) : null;
        if (parsedDate != null) _transactionDate = parsedDate;

        // ADDRESS is extracted by the model but has no form field yet — left
        // unused here deliberately (see plan).
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

  Future<String?> _listenOnce() => _voiceDatasource.listenOnce();

  Future<void> _stopListening() => _voiceDatasource.stop();

  /// Tap-to-talk voice capture: listens once, extracts fields on-device via ExpenseNlpParserService, and prefills the form for the user to review and save.
  Future<void> _handleVoiceInput() async {
    setState(() => _inputMode = 'voice');

    // Hands-free and tap-to-talk share one mic, so pause hands-free during this capture and only resume it if it was already running.
    final voiceController = widget.voiceController;
    final wasHandsFreeActive = voiceController?.isHandsFreeActive ?? false;
    if (wasHandsFreeActive) await voiceController!.stopHandsFree();

    try {
      final transcript = await _listenOnce();
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
    } finally {
      if (wasHandsFreeActive) await voiceController!.startHandsFree();
    }
  }

  /// Asks AutoCategorizationService to suggest a category for [merchantText] and updates the selected chip.
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
                    // Scan has no equivalent (single OCR call); voice needs it so users can skip waiting out the full listen timeout.
                    if (_inputMode == 'voice') ...[
                      const SizedBox(height: 8),
                      const Text(
                        "Done talking? Tap Stop instead of waiting.",
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _stopListening,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Stop'),
                      ),
                    ],
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
                        // Tapping a different chip while the category is still a suggestion means the user is correcting it; cache that.
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

/// Shown when the receipt's math cross-check doesn't reconcile with the printed total, offering the reconciled figure as a one-tap fix.
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

/// Generic reminder banner; deliberately not personalized since real spending-pattern suggestions (Module 2) aren't built yet.
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
