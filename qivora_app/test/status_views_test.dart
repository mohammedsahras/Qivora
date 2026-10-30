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
    dbPath = p.join(dir.path, 'qivora_status_views_test.db');
    try { final f = File(dbPath); if (await f.exists()) await f.delete(); } catch(_){}
    DatabaseService.setTestDatabasePath(dbPath);
    await DatabaseService.instance.close();
  });
  tearDown(() async {
    await DatabaseService.instance.close();
  });

  test('status viewer uniqueness and count', () async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('users', {'id':'me','display_name':'Me','created_at':now,'updated_at':now});
    await db.insert('statuses', {'id':'s1','user_id':'me','content':'hi','created_at':now,'expires_at':DateTime.now().add(const Duration(hours:1)).toIso8601String()});
    await db.insert('status_views', {'status_id':'s1','viewer_id':'me','created_at':now}, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('status_views', {'status_id':'s1','viewer_id':'me','created_at':now}, conflictAlgorithm: ConflictAlgorithm.ignore);
    final count = (await db.query('status_views', where: 'status_id = ?', whereArgs: ['s1'])).length;
    expect(count, 1);
  });
}