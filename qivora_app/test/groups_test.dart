import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:qivora_app/core/database/database_service.dart';
import 'package:qivora_app/features/groups/group_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late String dbPath;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp;
    dbPath = p.join(dir.path, 'qivora_groups_test.db');
    try {
      final f = File(dbPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    DatabaseService.setTestDatabasePath(dbPath);
    await DatabaseService.instance.close();
  });
  tearDown(() async {
    await DatabaseService.instance.close();
  });

  Future<Database> seed() async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('users', {'id': 'me', 'display_name': 'Me', 'created_at': now, 'updated_at': now});
    await db.insert('users', {'id': 'u2', 'display_name': 'Two', 'created_at': now, 'updated_at': now});
    await db.insert('users', {'id': 'u3', 'display_name': 'Three', 'created_at': now, 'updated_at': now});
    await db.insert('conversations', {'id': 'g1', 'title': 'Team', 'type': 'group', 'owner_user_id': 'me', 'created_at': now, 'updated_at': now});
    await db.insert('conversation_participants', {'id': 'p_g1', 'conversation_id': 'g1', 'user_id': 'me', 'role': 'owner', 'joined_at': now, 'is_muted': 0, 'is_pinned': 0, 'unread_count': 0});
    await db.insert('conversation_participants', {'id': 'p_g1_u2', 'conversation_id': 'g1', 'user_id': 'u2', 'role': 'member', 'joined_at': now, 'is_muted': 0, 'is_pinned': 0, 'unread_count': 0});
    return db;
  }

  test('successful ownership transfer', () async {
    final db = await seed();
    final ok = await GroupService.transferOwnership(db, 'g1', 'me', 'u2');
    expect(ok, isTrue);
    final conv = await db.query('conversations', where: 'id = ?', whereArgs: ['g1']);
    expect(conv.first['owner_user_id'], 'u2');
    final meRow = await db.query('conversation_participants', where: 'conversation_id = ? AND user_id = ?', whereArgs: ['g1', 'me']);
    expect(meRow.first['role'], 'admin');
    final u2Row = await db.query('conversation_participants', where: 'conversation_id = ? AND user_id = ?', whereArgs: ['g1', 'u2']);
    expect(u2Row.first['role'], 'owner');
  });

  test('transfer rejected for non-owner', () async {
    final db = await seed();
    final ok = await GroupService.transferOwnership(db, 'g1', 'u2', 'me');
    expect(ok, isFalse);
    final owner = (await db.query('conversations', where: 'id = ?', whereArgs: ['g1'])).first['owner_user_id'];
    expect(owner, 'me');
  });

  test('transfer rejected to non-member', () async {
    final db = await seed();
    final ok = await GroupService.transferOwnership(db, 'g1', 'me', 'u3');
    expect(ok, isFalse);
  });

  test('duplicate participant prevented', () async {
    final db = await seed();
    final now = DateTime.now().toIso8601String();
    await db.insert('conversation_participants', {'id': 'p_g1_dup', 'conversation_id': 'g1', 'user_id': 'u2', 'role': 'member', 'joined_at': now, 'is_muted': 0, 'is_pinned': 0, 'unread_count': 0}, conflictAlgorithm: ConflictAlgorithm.ignore);
    final rows = await db.query('conversation_participants', where: 'conversation_id = ? AND user_id = ?', whereArgs: ['g1', 'u2']);
    expect(rows.length, 1);
  });

  test('group image set by owner only', () async {
    final db = await seed();
    final byOwner = await GroupService.setGroupImage(db, 'g1', 'me', 'C:/tmp.png');
    expect(byOwner, isTrue);
    final byNonMember = await GroupService.setGroupImage(db, 'g1', 'u3', 'C:/tmp2.png');
    expect(byNonMember, isFalse);
    final path = (await db.query('conversations', where: 'id = ?', whereArgs: ['g1'])).first['avatar_path'];
    expect(path, 'C:/tmp.png');
  });
}
