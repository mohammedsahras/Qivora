import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:qivora_app/core/database/database_service.dart';
import 'package:qivora_app/core/auth/auth_service.dart';
import 'package:qivora_app/core/auth/auth_repository.dart';
import 'package:qivora_app/core/auth/password_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late String dbPath;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp;
    dbPath = p.join(dir.path, 'qivora_auth_test.db');
    try { final f = File(dbPath); if (await f.exists()) await f.delete(); } catch(_){}
    DatabaseService.setTestDatabasePath(dbPath);
    await DatabaseService.instance.close();
  });
  tearDown(() async {
    await DatabaseService.instance.close();
  });

  test('registration and login', () async {
    final repo = LocalAuthRepository();
    final svc = AuthService(repo, PasswordService());
    await svc.register('user1', 'a@b.com', '123', 'pass123');
    expect(await svc.login('user1', 'pass123'), isTrue);
    expect(await svc.login('a@b.com', 'pass123'), isTrue);
    expect(await svc.login('123', 'pass123'), isTrue);
    expect(await svc.login('user1', 'wrong'), isFalse);
  });

  test('duplicate username', () async {
    final repo = LocalAuthRepository();
    final svc = AuthService(repo, PasswordService());
    await svc.register('dup', 'd@b.com', '999', 'pass123');
    expect(() => svc.register('dup', 'd2@b.com', '998', 'pass123'), throwsA(anything));
  });

  test('legacy null password login fails', () async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('users', {'id':'legacy','display_name':'L','username':'legacy','created_at':now,'updated_at':now});
    final repo = LocalAuthRepository();
    final svc = AuthService(repo, PasswordService());
    expect(await svc.login('legacy', 'anything'), isFalse);
  });
}
