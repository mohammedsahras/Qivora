import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:qivora_app/core/database/database_service.dart';
import 'package:qivora_app/core/auth/status_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late String dbPath;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dbPath = p.join(Directory.systemTemp.path,
        'qivora_status_access_${DateTime.now().millisecondsSinceEpoch}.db');
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
    for (final id in ['me', 'alice', 'bob', 'carol']) {
      await db.insert('users', {'id': id, 'display_name': id, 'created_at': now, 'updated_at': now});
    }
    // me has contacts alice + bob. carol is NOT a contact.
    for (final c in ['alice', 'bob']) {
      await db.insert('contacts', {'id': 'c_$c', 'owner_user_id': 'me', 'contact_user_id': c, 'created_at': now});
    }
    return db;
  }

  test('my contacts privacy: contact sees status, stranger does not', () async {
    final db = await seed();
    final sid = await StatusService.createStatus(db, 'me', 'hello', 'contacts');
    final visibleForAlice = await StatusService.visibleStatuses(db, 'alice');
    expect(visibleForAlice.map((s) => s['id']), contains(sid));
    final visibleForCarol = await StatusService.visibleStatuses(db, 'carol');
    expect(visibleForCarol.map((s) => s['id']), isNot(contains(sid)));
    // view recording blocked for non-contact and allowed for contact
    expect(await StatusService.recordStatusView(db, sid, 'carol'), isFalse);
    final carolViews = await db.query('status_views', where: 'status_id = ? AND viewer_id = ?', whereArgs: [sid, 'carol']);
    expect(carolViews, isEmpty);
    expect(await StatusService.recordStatusView(db, sid, 'alice'), isTrue);
    final aliceViews = await db.query('status_views', where: 'status_id = ? AND viewer_id = ?', whereArgs: [sid, 'alice']);
    expect(aliceViews, hasLength(1));
  });

  test('my contacts except: excluded contact blocked, others still allowed', () async {
    final db = await seed();
    final sid = await StatusService.createStatus(db, 'me', 'hi', 'except', except: {'alice'});
    expect((await StatusService.visibleStatuses(db, 'alice')).map((s) => s['id']), isNot(contains(sid)));
    expect((await StatusService.visibleStatuses(db, 'bob')).map((s) => s['id']), contains(sid));
    expect(await StatusService.recordStatusView(db, sid, 'alice'), isFalse);
    expect(await StatusService.recordStatusView(db, sid, 'bob'), isTrue);
  });

  test('only share with: non-listed contact blocked even if contact', () async {
    final db = await seed();
    final sid = await StatusService.createStatus(db, 'me', 'secret', 'only', only: {'bob'});
    expect((await StatusService.visibleStatuses(db, 'bob')).map((s) => s['id']), contains(sid));
    expect((await StatusService.visibleStatuses(db, 'alice')).map((s) => s['id']), isNot(contains(sid)));
    expect(await StatusService.recordStatusView(db, sid, 'alice'), isFalse);
    expect(await StatusService.recordStatusView(db, sid, 'bob'), isTrue);
  });

  test('owner always sees own status; duplicate view recording is a no-op', () async {
    final db = await seed();
    final sid = await StatusService.createStatus(db, 'me', 'mine', 'only', only: {'bob'});
    expect((await StatusService.visibleStatuses(db, 'me')).map((s) => s['id']), contains(sid));
    expect(await StatusService.recordStatusView(db, sid, 'me'), isTrue);
    expect(await StatusService.recordStatusView(db, sid, 'me'), isTrue);
    final views = await db.query('status_views', where: 'status_id = ?', whereArgs: [sid]);
    expect(views, hasLength(1));
  });

  test('legacy statuses without privacy metadata remain visible to all', () async {
    final db = await seed();
    final now = DateTime.now().toIso8601String();
    await db.insert('statuses', {'id': 'legacy', 'user_id': 'me', 'content': 'old post', 'created_at': now, 'expires_at': now.length > 5 ? DateTime.now().add(const Duration(hours: 1)).toIso8601String() : now});
    expect((await StatusService.visibleStatuses(db, 'carol')).map((s) => s['id']), contains('legacy'));
    expect(await StatusService.recordStatusView(db, 'legacy', 'carol'), isTrue);
  });

  test('unknown status id rejected on view recording', () async {
    final db = await seed();
    expect(await StatusService.recordStatusView(db, 'nope', 'alice'), isFalse);
  });
}
