import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/events/expense_events.dart';
import '../../../../core/widgets/labeled_field.dart';
import '../../../../services/category_service.dart';
import 'voice_capture_controller.dart';

/// Shown once VoiceCaptureController finishes parsing an utterance; a human veto point since misheard amounts are the biggest failure mode of ASR+regex entry. Fields are pre-filled but editable, nothing saves until Save is tapped.
class VoiceConfirmationSheet extends StatefulWidget {
  final VoiceCaptureController controller;

  const VoiceConfirmationSheet({super.key, required this.controller});

  static Future<void> show(
    BuildContext context,
    VoiceCaptureController controller,
  ) {
    // Dismissible/draggable; swipe-away or backdrop tap is treated as Discard (see dispose()).
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => VoiceConfirmationSheet(controller: controller),
    );
  }

  @override
  State<VoiceConfirmationSheet> createState() => _VoiceConfirmationSheetState();
}

class _VoiceConfirmationSheetState extends State<VoiceConfirmationSheet> {
  late final TextEditingController _amountController;
  late final TextEditingController _merchantController;
  late String _category;
  late DateTime _transactionDate;
  bool _isSaving = false;

  // Set right before Save/Discard pop the sheet; if it closes any other way (swipe, backdrop tap), dispose() treats it as an implicit Discard so hands-free listening still resumes.
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    final parsed = widget.controller.lastParsed;
    final suggestion = widget.controller.lastCategorySuggestion;
    _amountController = TextEditingController(
      text: parsed?.amount?.toStringAsFixed(2) ?? '',
    );
    _merchantController = TextEditingController(text: parsed?.merchantName ?? '');
    _category = suggestion?.category ?? 'other';
    _transactionDate = parsed?.transactionDate ?? DateTime.now();
  }

  @override
  void dispose() {
    if (!_resolved) {
      // Dismissed via swipe/backdrop rather than Save/Discard; still needs to clear state and resume hands-free listening.
      unawaited(widget.controller.cancelPending());
    }
    _amountController.dispose();
    _merchantController.dispose();
    super.dispose();
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
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) return;

    setState(() => _isSaving = true);
    try {
      await widget.controller.confirmSave(
        amount: amount,
        category: _category,
        merchantName: _merchantController.text.trim().isEmpty
            ? null
            : _merchantController.text.trim(),
        transactionDate: _transactionDate,
      );
    } catch (e) {
      // Leave _resolved false so dispose()'s implicit-cancel still fires if the user swipes away instead of retrying.
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save expense: $e')),
        );
      }
      return;
    }

    _resolved = true;
    notifyExpenseDataChanged();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _handleCancel() async {
    _resolved = true;
    await widget.controller.cancelPending();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories = CategoryService.cached;
    final rawTranscript = widget.controller.lastParsed?.rawTranscript ?? '';

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.mic, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Confirm voice expense',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '"$rawTranscript"',
              style: const TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            LabeledField(
              label: 'Transaction Amount',
              child: TextField(
                controller: _amountController,
                autofocus: !(widget.controller.lastParsed?.hasAmount ?? false),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(prefixText: 'RM ', border: InputBorder.none),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(height: 20),
            LabeledField(
              label: 'Choose Category',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: categories.map((c) {
                  final selected = c.key == _category;
                  return ChoiceChip(
                    label: Text(c.label),
                    avatar: Icon(c.icon, size: 18, color: selected ? Colors.white : c.color),
                    selected: selected,
                    onSelected: (_) => setState(() => _category = c.key),
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
              label: 'Merchant',
              child: TextField(
                controller: _merchantController,
                decoration: const InputDecoration(hintText: 'Where did you spend?'),
              ),
            ),
            const SizedBox(height: 20),
            LabeledField(
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
                      Text(
                        '${_transactionDate.year}-${_transactionDate.month.toString().padLeft(2, '0')}-${_transactionDate.day.toString().padLeft(2, '0')}',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : _handleCancel,
                    child: const Text('Discard'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _handleSave,
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save Expense'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
