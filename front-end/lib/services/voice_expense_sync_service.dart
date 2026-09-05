import '../features/expense/data/datasources/pending_voice_expense_dao.dart';
import 'expense_service.dart';

/// Flushes the offline outbox to POST /api/expenses/post; rows that fail to sync are left queued rather than retried in a loop here.
class VoiceExpenseSyncService {
  final PendingVoiceExpenseDao _outbox;
  final ExpenseService _expenseService;

  VoiceExpenseSyncService({
    PendingVoiceExpenseDao? outbox,
    ExpenseService? expenseService,
  }) : _outbox = outbox ?? PendingVoiceExpenseDao(),
       _expenseService = expenseService ?? ExpenseService();

  /// Safe to call opportunistically (app resume, after a save, connectivity regained) — failures just stay queued.
  Future<void> flushPending() async {
    final pending = await _outbox.listPending();

    for (final row in pending) {
      try {
        await _expenseService.createExpense({
          'amount': row['amount'],
          'category': row['category'],
          if ((row['merchant_name'] as String?)?.isNotEmpty ?? false)
            'merchant_name': row['merchant_name'],
          if ((row['transaction_date'] as String?)?.isNotEmpty ?? false)
            'transaction_date': row['transaction_date'],
          'description': 'Voice: ${row['raw_transcript']}',
        });
        await _outbox.delete(row['id'] as int);
      } catch (_) {
        // Still offline or backend unreachable — leave it queued and move
        // on to the rest rather than aborting the whole flush.
      }
    }
  }
}
