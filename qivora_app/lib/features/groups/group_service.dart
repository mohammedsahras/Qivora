import 'package:sqflite/sqflite.dart';

/// Service holding group ownership/image business logic so it can be unit
/// tested without launching widgets.
class GroupService {
  const GroupService._();

  /// Returns the participant row of [groupId] for [userId], or null.
  static Future<Map<String, dynamic>?> participant(
      Database db, String groupId, String userId) async {
    final rows = await db.query('conversation_participants',
        where: 'conversation_id = ? AND user_id = ?',
        whereArgs: [groupId, userId]);
    return rows.isEmpty ? null : rows.first;
  }

  /// Transfers group ownership from [fromId] to [toId] in a single
  /// transaction. Returns false when [fromId] is not the current owner or
  /// [toId] is not an existing member — no partial updates are made.
  static Future<bool> transferOwnership(
      Database db, String groupId, String fromId, String toId) async {
    if (fromId == toId) return false;
    final conv = await db.query('conversations',
        where: 'id = ? AND type = ?', whereArgs: [groupId, 'group']);
    if (conv.isEmpty) return false;
    if (conv.first['owner_user_id'] != fromId) return false;
    final toParticipant = await participant(db, groupId, toId);
    if (toParticipant == null) return false;

    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      // Previous owner becomes a regular admin; the new owner receives the
      // owner role. Both updates happen atomically.
      await txn.update('conversation_participants', {'role': 'admin'},
          where: 'conversation_id = ? AND user_id = ?',
          whereArgs: [groupId, fromId]);
      await txn.update('conversation_participants', {'role': 'owner'},
          where: 'conversation_id = ? AND user_id = ?',
          whereArgs: [groupId, toId]);
      await txn.update('conversations', {'owner_user_id': toId, 'updated_at': now},
          where: 'id = ?', whereArgs: [groupId]);
    });
    return true;
  }

  /// Stores the group profile image path when the caller is allowed to edit
  /// the group (owner or admin member).
  static Future<bool> setGroupImage(
      Database db, String groupId, String userId, String imagePath) async {
    final conv = await db.query('conversations',
        where: 'id = ? AND type = ?', whereArgs: [groupId, 'group']);
    if (conv.isEmpty) return false;
    final p = await participant(db, groupId, userId);
    if (p == null) return false;
    final role = p['role'] as String? ?? 'member';
    final isOwner = conv.first['owner_user_id'] == userId;
    if (!(isOwner || role == 'admin')) return false;
    await db.update('conversations', {'avatar_path': imagePath},
        where: 'id = ?', whereArgs: [groupId]);
    return true;
  }
}
