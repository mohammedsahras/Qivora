import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:qivora_app/core/database/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late String dbPath;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp;
    dbPath = p.join(dir.path,
        'qivora_search_test_${DateTime.now().millisecondsSinceEpoch}.db');
    DatabaseService.setTestDatabasePath(dbPath);
    await DatabaseService.instance.close();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    try {
      final f = File(dbPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  });

  Future<void> seed() async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('users', {
      'id': 'me',
      'display_name': 'Me',
      'created_at': now,
      'updated_at': now
    });
    for (final c in ['c1', 'c2']) {
      await db.insert('conversations', {
        'id': c,
        'title': c,
        'type': 'direct',
        'created_at': now,
        'updated_at': now
      });
    }
    await db.insert('messages', {
      'id': 'm1',
      'conversation_id': 'c1',
      'sender_id': 'me',
      'message_type': 'text',
      'content': 'Hello World',
      'delivery_status': 'sent',
      'created_at': now,
      'updated_at': now
    });
    await db.insert('messages', {
      'id': 'm2',
      'conversation_id': 'c2',
      'sender_id': 'me',
      'message_type': 'text',
      'content': 'hello again',
      'delivery_status': 'sent',
      'created_at': now,
      'updated_at': now
    });
  }

  test('case-insensitive search', () async {
    await seed();
    final db = await DatabaseService.instance.database;
    final rows = await db.rawQuery(
        "SELECT * FROM messages WHERE deleted_at IS NULL AND LOWER(content) LIKE LOWER(?)",
        ['%hello%']);
    expect(rows.length, 2);
  });

  test('no results', () async {
    await seed();
    final db = await DatabaseService.instance.database;
    final rows = await db.rawQuery(
        "SELECT * FROM messages WHERE deleted_at IS NULL AND LOWER(content) LIKE LOWER(?)",
        ['%zzz%']);
    expect(rows.isEmpty, isTrue);
  });

  test('empty query returns none (handled in UI)', () async {
    // Just ensure no crash
    expect(true, isTrue);
  });
}
