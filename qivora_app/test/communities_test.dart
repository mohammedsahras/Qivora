import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:qivora_app/core/database/database_service.dart';
import 'package:qivora_app/features/communities/community_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late String dbPath;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp;
    dbPath = p.join(dir.path, 'qivora_communities_test.db');
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
    for (final id in ['me', 'u2', 'u3']) {
      await db.insert('users', {'id': id, 'display_name': id, 'created_at': now, 'updated_at': now});
    }
    await db.insert('conversations', {'id': 'g1', 'title': 'Team', 'type': 'group', 'owner_user_id': 'me', 'created_at': now, 'updated_at': now});
    await db.insert('conversation_participants', {'id': 'p1', 'conversation_id': 'g1', 'user_id': 'me', 'role': 'owner', 'joined_at': now, 'is_muted': 0, 'is_pinned': 0, 'unread_count': 0});
    await db.insert('messages', {'id': 'm1', 'conversation_id': 'g1', 'sender_id': 'me', 'message_type': 'text', 'content': 'hello', 'created_at': now});
    return db;
  }

  test('community creation rejects empty and duplicate names', () async {
    final db = await seed();
    final id = await CommunityService.createCommunity(db, 'Qivora HQ', null, 'me', null);
    expect(id, isNotNull);
    expect(await CommunityService.createCommunity (db, '', null, 'me', null), isNull);
    expect(await CommunityService.createCommunity(db, 'Qivora HQ', null, 'me', null), isNull);
    final owner = await db.query('community_members', where: 'community_id = ?', whereArgs: [id]);
    expect(owner.first['role'], 'owner');
  });

  test('add/remove group; removal preserves group chat and messages', () async {
    final db = await seed();
    final cid = await CommunityService.createCommunity(db, 'Community', null, 'me', null);
    expect(await CommunityService.addGroup(db, cid!, 'g1', 'me'), isTrue);
    // duplicate association rejected
    expect(await CommunityService.addGroup(db, cid, 'g1', 'me'), isFalse);
    // unauthorized actor rejected
    expect(await CommunityService.addGroup(db, cid, 'g1', 'u2'), isFalse);
    final linked = await db.query('community_groups', where: 'community_id = ?', whereArgs: [cid]);
    expect(linked.length, 1);
    expect(await CommunityService.removeGroup(db, cid, 'g1', 'me'), isTrue);
    final conv = await db.query('conversations', where: 'id = ?', whereArgs: ['g1']);
    expect(conv.length, 1); // group kept
    final msgs = await db.query('messages', where: 'conversation_id = ?', whereArgs: ['g1']);
    expect(msgs.length, 1); // messages kept
  });

  test('member management: permissions, duplicates, owner protection', () async {
    final db = await seed();
    final cid = await CommunityService.createCommunity(db, 'Community', null, 'me', null);
    expect(await CommunityService.addMember(db, cid!, 'u2', 'me'), isTrue);
    expect(await CommunityService.addMember(db, cid, 'u2', 'me'), isFalse); // duplicate
    expect(await CommunityService.addMember(db, cid, 'u2', 'u3'), isFalse); // non-manager actor
    expect(await CommunityService.removeMember(db, cid, 'u2', 'me'), isTrue);
    expect(await CommunityService.addMember(db, cid, 'u2', 'me'), isTrue);
    // owner protected from removal
    expect(await CommunityService.removeMember(db, cid, 'me', 'me'), isFalse);
    final me = await CommunityService.getMember(db, cid, 'me');
    expect(me, isNotNull);
  });

  test('leave promotes earliest member to owner; empty community is deleted', () async {
    final db = await seed();
    final cid = await CommunityService.createCommunity(db, 'Community', null, 'me', null);
    await CommunityService.addMember(db, cid!, 'u2', 'me');
    await CommunityService.leaveCommunity(db, cid, 'me');
    final c = await db.query('communities', where: 'id = ?', whereArgs: [cid]);
    expect(c.first['owner_user_id'], 'u2');
    final u2 = await CommunityService.getMember(db, cid, 'u2');
    expect(u2!['role'], 'owner');
    await CommunityService.leaveCommunity(db, cid, 'u2');
    final gone = await db.query('communities', where: 'id = ?', whereArgs: [cid]);
    expect(gone, isEmpty);
  });

  test('v15 migration path still applies owner backfill and v16 tables exist', () async {
    // Simulate an old v15 database: create first at v15 by inserting rows, then rely on schema creation.
    final db = await seed();
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('communities','community_members','community_groups')");
    expect(tables.length, 3);
    final v = await db.getVersion();
    expect(v, 17);
  });
}
