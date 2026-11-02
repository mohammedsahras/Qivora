import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';

/// Business logic for the Communities module. Kept free of Flutter UI so it
/// can be unit tested directly against the test database.
class CommunityService {
  const CommunityService._();

  static const Uuid _uuid = Uuid();

  /// Creates a community. The creator becomes owner/admin. Returns null for
  /// empty names or a duplicate community name.
  static Future<String?> createCommunity(
    Database db,
    String name,
    String? description,
    String ownerId,
    String? avatarPath,
  ) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final dup = await db.query('communities',
        where: 'LOWER(name) = ?', whereArgs: [trimmed.toLowerCase()]);
    if (dup.isNotEmpty) return null;
    final now = DateTime.now().toIso8601String();
    final id = _uuid.v4();
    await db.transaction((txn) async {
      await txn.insert('communities', {
        'id': id,
        'name': trimmed,
        'description': description,
        'avatar_path': avatarPath,
        'owner_user_id': ownerId,
        'created_at': now,
        'updated_at': now,
      });
      await txn.insert('community_members', {
        'community_id': id,
        'user_id': ownerId,
        'role': 'owner',
        'joined_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
    return id;
  }

  static Future<Map<String, dynamic>?> getMember(
      Database db, String communityId, String userId) async {
    final rows = await db.query('community_members',
        where: 'community_id = ? AND user_id = ?',
        whereArgs: [communityId, userId]);
    return rows.isEmpty ? null : rows.first;
  }

  static Future<bool> isManager(
      Database db, String communityId, String userId) async {
    final c = await db.query('communities',
        where: 'id = ?', whereArgs: [communityId]);
    if (c.isEmpty) return false;
    final m = await getMember(db, communityId, userId);
    if (m == null) return false;
    final role = m['role'] as String? ?? 'member';
    return role == 'admin' || role == 'owner';
  }

  /// Adds a member. Only owner/admin may add; duplicates are rejected.
  static Future<bool> addMember(
      Database db, String communityId, String userId, String actorId) async {
    if (!await isManager(db, communityId, actorId)) return false;
    final user = await db.query('users', where: 'id = ?', whereArgs: [userId]);
    if (user.isEmpty) return false;
    if (await getMember(db, communityId, userId) != null) return false;
    await db.insert('community_members', {
      'community_id': communityId,
      'user_id': userId,
      'role': 'member',
      'joined_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return true;
  }

  /// Removes a member. Owner and self-removal (use leaveCommunity) are not
  /// allowed through this path.
  static Future<bool> removeMember(
      Database db, String communityId, String userId, String actorId) async {
    if (!await isManager(db, communityId, actorId)) return false;
    if (userId == actorId) return false;
    final c = await db.query('communities',
        where: 'id = ?', whereArgs: [communityId]);
    if (c.isEmpty) return false;
    if (c.first['owner_user_id'] == userId) return false; // owner protected
    final deleted = await db.delete('community_members',
        where: 'community_id = ? AND user_id = ?',
        whereArgs: [communityId, userId]);
    return deleted > 0;
  }

  /// Leaves a community. When the owner leaves, the earliest remaining member
  /// is promoted to owner; if nobody remains, the community is deleted.
  static Future<bool> leaveCommunity(
      Database db, String communityId, String userId) async {
    final member = await getMember(db, communityId, userId);
    if (member == null) return false;
    await db.transaction((txn) async {
      await txn.delete('community_members',
          where: 'community_id = ? AND user_id = ?',
          whereArgs: [communityId, userId]);
      final c = await txn.query('communities',
          where: 'id = ?', whereArgs: [communityId]);
      if (c.isEmpty) return;
      if (c.first['owner_user_id'] == userId) {
        final remaining = await txn.query('community_members',
            where: 'community_id = ?',
            whereArgs: [communityId],
            orderBy: 'joined_at ASC, user_id ASC');
        if (remaining.isEmpty) {
          await txn.delete('communities',
              where: 'id = ?', whereArgs: [communityId]);
        } else {
          final newOwner = remaining.first['user_id'] as String;
          await txn.update('community_members', {'role': 'owner'},
              where: 'community_id = ? AND user_id = ?',
              whereArgs: [communityId, newOwner]);
          await txn.update('communities', {
            'owner_user_id': newOwner,
            'updated_at': DateTime.now().toIso8601String(),
          }, where: 'id = ?', whereArgs: [communityId]);
        }
      }
    });
    return true;
  }

  /// Associates an existing group (conversation) with a community. The group,
  /// its participants and messages are NOT copied or moved.
  static Future<bool> addGroup(Database db, String communityId,
      String conversationId, String actorId) async {
    if (!await isManager(db, communityId, actorId)) return false;
    final conv = await db.query('conversations',
        where: 'id = ? AND type = ?', whereArgs: [conversationId, 'group']);
    if (conv.isEmpty) return false;
    final existing = await db.query('community_groups',
        where: 'community_id = ? AND conversation_id = ?',
        whereArgs: [communityId, conversationId]);
    if (existing.isNotEmpty) return false;
    await db.insert('community_groups', {
      'community_id': communityId,
      'conversation_id': conversationId,
      'added_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return true;
  }

  /// Changes a member's role. Only the community **owner** may promote or
  /// demote (an admin cannot change another admin without explicit owner
  /// authorization). Runs in a transaction; idempotent no-ops are rejected so
  /// duplicate operations fail fast.
  static Future<bool> setMemberRole(Database db, String communityId,
      String targetId, String actorId, bool promote) async {
    final c = await db.query('communities',
        where: 'id = ?', whereArgs: [communityId]);
    if (c.isEmpty) return false;
    if (c.first['owner_user_id'] != actorId) return false; // owner-only
    if (targetId == actorId) return false;
    if (c.first['owner_user_id'] == targetId) return false; // owner protected
    final target = await getMember(db, communityId, targetId);
    if (target == null) return false; // must be an existing member
    final currentRole = target['role'] as String? ?? 'member';
    final newRole = promote ? 'admin' : 'member';
    if (currentRole == newRole) return false; // duplicate/invalid change
    await db.transaction((txn) async {
      await txn.update(
          'community_members',
          {'role': newRole},
          where: 'community_id = ? AND user_id = ?',
          whereArgs: [communityId, targetId]);
      await txn.update('communities',
          {'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [communityId]);
    });
    return true;
  }

  /// Removes only the association. The group conversation and its messages
  /// remain intact.
  static Future<bool> removeGroup(Database db, String communityId,
      String conversationId, String actorId) async {
    if (!await isManager(db, communityId, actorId)) return false;
    final deleted = await db.delete('community_groups',
        where: 'community_id = ? AND conversation_id = ?',
        whereArgs: [communityId, conversationId]);
    return deleted > 0;
  }
}
