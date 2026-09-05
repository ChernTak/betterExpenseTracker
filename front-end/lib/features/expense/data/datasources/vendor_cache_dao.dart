import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Local cache of merchant text -> category so a repeat merchant resolves instantly offline instead of hitting the backend classifier again.
class VendorCacheDao {
  static const _dbName = 'vendor_cache.db';
  static const _table = 'vendor_cache';
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
          text_key TEXT PRIMARY KEY,
          category TEXT NOT NULL,
          confidence REAL NOT NULL,
          source TEXT NOT NULL,
          updated_at INTEGER NOT NULL
        )
      '''),
    );
  }

  /// Normalizes merchant text (e.g. "Starbucks #4821" -> "starbucks") so different renderings hit the same cache row.
  static String normalize(String text) {
    var normalized = text.toLowerCase().trim();
    normalized = normalized.replaceAll(RegExp(r'[^\w\s]'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\s+\d{2,}$'), '');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  Future<Map<String, dynamic>?> lookup(String text) async {
    final key = normalize(text);
    if (key.isEmpty) return null;

    final db = await _database;
    final rows = await db.query(
      _table,
      where: 'text_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> upsert(
    String text,
    String category,
    double confidence,
    String source,
  ) async {
    final key = normalize(text);
    if (key.isEmpty) return;

    final db = await _database;
    await db.insert(
      _table,
      {
        'text_key': key,
        'category': category,
        'confidence': confidence,
        'source': source,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Overwrites the cached category with a user-confirmed one at full confidence.
  Future<void> overrideCategory(String text, String newCategory) async {
    await upsert(text, newCategory, 1.0, 'user_correction');
  }
}
