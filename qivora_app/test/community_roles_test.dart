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
    dbPath = p.join(Directory.systemTemp.path,
        'qivora_community_roles_${DateTime.now().millisecondsSinceEpoch}.db');
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
    for (final id in ['owner', 'admin1', 'admin2', 'member1', 'stranger']) {
      await db.insert('users', {'id': id, 'display_name': id, 'created_at': now, 'updated_at': now});
    }
    final cid = await CommunityService.createCommunity(db, 'Community', null, 'owner', null);
    await CommunityService.addMember(db, cid!, 'admin1', 'owner');
    await CommunityService.addMember(db, cid, 'admin2', 'owner');
    await CommunityService.addMember(db, cid, 'member1', 'owner');
    await db.update('community_members', {'role': 'admin'},
        where: 'community_id = ? AND user_id = ?', whereArgs: [cid, 'admin1']);
    await db.update('community_members', {'role': 'admin'},
        where: 'community_id = ? AND user_id = ?', whereArgs: [cid, 'admin2']);
    return db;
  }

  test('owner can promote member to admin', () async {
    final db = await seed();
    final cid = (await db.query('communities')).first['id'] as String;
    expect(await CommunityService.setMemberRole(db, cid, 'member1', 'owner', true), isTrue);
    final m = await CommunityService.getMember(db, cid, 'member1');
    expect(m!['role'], 'admin');
  });

  test('owner can demote admin to member', () async {
    final db = await seed();
    final cid = (await db.query('communities')).first['id'] as String;
    expect(await CommunityService.setMemberRole(db, cid, 'admin1', 'owner', false), isTrue);
    final m = await CommunityService.getMember(db, cid, 'admin1');
    expect(m!['role'], 'member');
  });

  test('admin cannot promote or demote another admin', () async {
    final db = await seed();
    final cid = (await db.query('communities')).first['id'] as String;
    expect(await CommunityService.setMemberRole(db, cid, 'admin2', 'admin1', false), isFalse);
    expect(await CommunityService.setMemberRole(db, cid, 'member1', 'admin1', true), isFalse);
    final a2 = await CommunityService.getMember(db, cid, 'admin2');
    expect(a2!['role'], 'admin');
  });

  test('owner protected: cannot demote or remove owner, even by owner self', () async {
    final db = await seed();
    final cid = (await db.query('communities')).first['id'] as String;
    expect(await CommunityService.setMemberRole(db, cid, 'owner', 'owner', false), isFalse);
    expect(await CommunityService.removeMember(db, cid, 'owner', 'owner'), isFalse);
    // after transfer of ownership, new owner can demote the previous owner (role admin)
    await CommunityService.addMember(db, cid, 'stranger', 'owner');
    await CommunityService.setMemberRole(db, cid, 'stranger', 'owner', true);
    // transfer is out of scope here; previous-owner demotion checked via group flow
    final o = await CommunityService.getMember(db, cid, 'owner');
    expect(o!['role'], 'owner');
  });

  test('duplicate and invalid role changes rejected', () async {
    final db = await seed();
    final cid = (await db.query('communities')).first['id'] as String;
    expect(await CommunityService.setMemberRole(db, cid, 'admin1', 'owner', true), isFalse); // already admin
    expect(await CommunityService.setMemberRole(db, cid, 'member1', 'owner', false), isFalse); // already member
    expect(await CommunityService.setMemberRole(db, cid, 'stranger', 'owner', true), isFalse); // not a member
    // duplicate admin removal after failing removal: idempotent no-op returns false
    expect(await CommunityService.setMemberRole(db, cid, 'admin1', 'owner', false), isTrue);
    expect(await CommunityService.setMemberRole(db, cid, 'admin1', 'owner', false), isFalse);
  });

  test('stranger cannot perform any role changes', () async {
    final db = await seed();
    final cid = (await db.query('communities')).first['id'] as String;
    expect(await CommunityService.setMemberRole(db, cid, 'admin1', 'stranger', false), isFalse);
    expect(await CommunityService.setMemberRole(db, cid, 'member1', 'stranger', true), isFalse);
  });
}
