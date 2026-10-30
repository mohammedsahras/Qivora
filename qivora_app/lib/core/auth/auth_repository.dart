import '../../core/database/database_service.dart';

abstract class AuthRepository {
  Future<void> register({required String username, required String email, required String phone, required String passwordHash});
  Future<Map<String,dynamic>?> findByIdentifier(String identifier);
  Future<void> updatePassword(String userId, String passwordHash);
}

class LocalAuthRepository implements AuthRepository {
  @override
  Future<void> register({required String username, required String email, required String phone, required String passwordHash}) async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('users', {
      'id': username, // placeholder id
      'username': username,
      'email': email,
      'phone_number': phone,
      'password_hash': passwordHash,
      'display_name': username,
      'created_at': now,
      'updated_at': now,
    });
  }

  @override
  Future<Map<String,dynamic>?> findByIdentifier(String identifier) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query('users', where: 'username = ? OR email = ? OR phone_number = ?', whereArgs: [identifier, identifier, identifier]);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  @override
  Future<void> updatePassword(String userId, String passwordHash) async {
    final db = await DatabaseService.instance.database;
    await db.update('users', {'password_hash': passwordHash, 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [userId]);
  }
}
