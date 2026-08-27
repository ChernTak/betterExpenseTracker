import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Local-only event log for FR4.4's voice pipeline (wake detections, no-speech
/// timeouts, parse failures, STT errors, sync failures) — the "zero
/// observability" gap for a feature that's otherwise flying blind in
/// production. Never transmitted automatically; a user has to explicitly
/// copy it via Profile > Support > Send Diagnostic Report
/// (see profile_screen.dart) before any of it leaves the device, so this
/// doesn't compromise the on-device/offline-first premise the whole feature
/// is built on.
class VoiceDiagnosticLogDao {
  static const _dbName = 'voice_diagnostics.db';
  static const _table = 'voice_diagnostic_events';
  static const _dbVersion = 1;
  static const _maxRows = 200;

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
          event TEXT NOT NULL,
          detail TEXT,
          created_at INTEGER NOT NULL
        )
      '''),
    );
  }

  Future<void> log(String event, {String? detail}) async {
    final db = await _database;
    await db.insert(_table, {
      'event': event,
      'detail': detail,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    // Cheap rolling cap so this never grows unbounded on a device that's
    // been installed for months — exact-200 isn't important, just "small".
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $_table'),
    );
    if (count != null && count > _maxRows) {
      await db.rawDelete(
        'DELETE FROM $_table WHERE id NOT IN '
        '(SELECT id FROM $_table ORDER BY created_at DESC LIMIT $_maxRows)',
      );
    }
  }

  Future<List<Map<String, dynamic>>> recentEvents({int limit = 200}) async {
    final db = await _database;
    return db.query(_table, orderBy: 'created_at DESC', limit: limit);
  }
}
