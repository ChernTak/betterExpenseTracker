import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Offline-first outbox for voice-logged expenses (FR4.4). A confirmed
/// voice expense is written here immediately, then VoiceExpenseSyncService
/// flushes rows to POST /api/expenses/post whenever connectivity allows —
/// so a save always succeeds locally even if the device is offline at the
/// moment the user confirms it.
class PendingVoiceExpenseDao {
  static const _dbName = 'pending_voice_expenses.db';
  static const _table = 'pending_voice_expenses';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = join(await getDatabasesPath(), _dbName);
    return openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE $_table (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          amount REAL NOT NULL,
          category TEXT NOT NULL,
          merchant_name TEXT,
          transaction_date TEXT,
          raw_transcript TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      '''),
    );
  }

  Future<int> insert({
    required double amount,
    required String category,
    String? merchantName,
    String? transactionDate,
    required String rawTranscript,
  }) async {
    final db = await _database;
    return db.insert(_table, {
      'amount': amount,
      'category': category,
      'merchant_name': merchantName,
      'transaction_date': transactionDate,
      'raw_transcript': rawTranscript,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> listPending() async {
    final db = await _database;
    return db.query(_table, orderBy: 'created_at ASC');
  }

  Future<void> delete(int id) async {
    final db = await _database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}
