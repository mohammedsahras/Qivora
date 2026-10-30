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
    dbPath = p.join(dir.path, 'qivora_admins_test.db');
    try { final f = File(dbPath); if (await f.exists()) await f.delete(); } catch(_){}
    DatabaseService.setTestDatabasePath(dbPath);
    await DatabaseService.instance.close();
  });
  tearDown(() async {
    await DatabaseService.instance.close();
  });

  test('admin add and remove', () async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('users', {'id':'me','display_name':'Me','created_at':now,'updated_at':now});
    await db.insert('channels', {'id':'c1','name':'Ch','created_at':now,'updated_at':now});
    await db.insert('channel_admins', {'channel_id':'c1','user_id':'me','created_at':now});
    final a1 = await db.query('channel_admins', where: 'channel_id = ? AND user_id = ?', whereArgs: ['c1','me']);
    expect(a1.length, 1);
    await db.delete('channel_admins', where: 'channel_id = ? AND user_id = ?', whereArgs: ['c1','me']);
    final a2 = await db.query('channel_admins', where: 'channel_id = ? AND user_id = ?', whereArgs: ['c1','me']);
    expect(a2.isEmpty, isTrue);
  });
}
