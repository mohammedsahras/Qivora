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
        'qivora_draft_test_${DateTime.now().millisecondsSinceEpoch}.db');
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

  Future<void> seedConversations() async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('users', {
      'id': 'me',
      'display_name': 'Me',
      'created_at': now,
      'updated_at': now
    });
    for (final id in ['c1', 'c2']) {
      await db.insert('conversations', {
        'id': id,
        'title': id,
        'type': 'direct',
        'created_at': now,
        'updated_at': now
      });
    }
  }

  test('save and retrieve draft', () async {
    await seedConversations();
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('drafts',
        {'conversation_id': 'c1', 'draft_text': 'hello', 'updated_at': now});
    final rows = await db
        .query('drafts', where: 'conversation_id = ?', whereArgs: ['c1']);
    expect(rows.length, 1);
    expect(rows.first['draft_text'], 'hello');
  });

  test('update existing draft', () async {
    await seedConversations();
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('drafts',
        {'conversation_id': 'c1', 'draft_text': 'a', 'updated_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('drafts',
        {'conversation_id': 'c1', 'draft_text': 'b', 'updated_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace);
    final rows = await db
        .query('drafts', where: 'conversation_id = ?', whereArgs: ['c1']);
    expect(rows.length, 1);
    expect(rows.first['draft_text'], 'b');
  });

  test('drafts isolated between conversations', () async {
    await seedConversations();
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('drafts',
        {'conversation_id': 'c1', 'draft_text': 'x', 'updated_at': now});
    await db.insert('drafts',
        {'conversation_id': 'c2', 'draft_text': 'y', 'updated_at': now});
    final r1 = await db
        .query('drafts', where: 'conversation_id = ?', whereArgs: ['c1']);
    final r2 = await db
        .query('drafts', where: 'conversation_id = ?', whereArgs: ['c2']);
    expect(r1.first['draft_text'], 'x');
    expect(r2.first['draft_text'], 'y');
  });

  test('clear draft', () async {
    await seedConversations();
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('drafts',
        {'conversation_id': 'c1', 'draft_text': 'x', 'updated_at': now});
    await db.delete('drafts', where: 'conversation_id = ?', whereArgs: ['c1']);
    final rows = await db
        .query('drafts', where: 'conversation_id = ?', whereArgs: ['c1']);
    expect(rows.isEmpty, isTrue);
  });

  test('preserve draft after reopen', () async {
    await seedConversations();
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('drafts',
        {'conversation_id': 'c1', 'draft_text': 'persist', 'updated_at': now});
    await DatabaseService.instance.close();
    final db2 = await DatabaseService.instance.database;
    final rows = await db2
        .query('drafts', where: 'conversation_id = ?', whereArgs: ['c1']);
    expect(rows.first['draft_text'], 'persist');
  });

  test('empty draft handling (delete)', () async {
    await seedConversations();
    final db = await DatabaseService.instance.database;
    await db.delete('drafts', where: 'conversation_id = ?', whereArgs: ['c1']);
    final rows = await db
        .query('drafts', where: 'conversation_id = ?', whereArgs: ['c1']);
    expect(rows.isEmpty, isTrue);
  });

  test('cascade delete draft on conversation delete', () async {
    await seedConversations();
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('drafts',
        {'conversation_id': 'c1', 'draft_text': 'x', 'updated_at': now});
    await db.delete('conversations', where: 'id = ?', whereArgs: ['c1']);
    final rows = await db
        .query('drafts', where: 'conversation_id = ?', whereArgs: ['c1']);
    expect(rows.isEmpty, isTrue);
  });
}
