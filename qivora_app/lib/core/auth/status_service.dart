import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import 'status_privacy.dart';

/// Data-access layer for statuses. All reads and view recordings are
/// permission-checked here so privacy selection actually restricts access,
/// not just the UI.
class StatusService {
  const StatusService._();

  static const Uuid _uuid = Uuid();
  static const String _defaultPrivacy = 'all';

  static Set<String> _decodeSet(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Contact ids of [ownerId] (rows in `contacts` where owner_user_id matches).
  static Future<Set<String>> contactsOf(Database db, String ownerId) async {
    final rows = await db.query('contacts',
        where: 'owner_user_id = ?', whereArgs: [ownerId]);
    return rows.map((r) => r['contact_user_id'].toString()).toSet();
  }

  /// Creates a status with its privacy configuration persisted on the row so
  /// every later access check uses the settings captured at post time.
  static Future<String> createStatus(
    Database db,
    String ownerId,
    String content,
    String privacy, {
    String? backgroundColor,
    Set<String> except = const {},
    Set<String> only = const {},
    Duration lifetime = const Duration(hours: 24),
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    await db.insert('statuses', {
      'id': id,
      'user_id': ownerId,
      'content': content,
      'background_color': backgroundColor ?? '#00A878',
      'created_at': now.toIso8601String(),
      'expires_at': now.add(lifetime).toIso8601String(),
      'privacy': privacy,
      'except_list': except.isEmpty ? null : jsonEncode(except.toList()),
      'only_list': only.isEmpty ? null : jsonEncode(only.toList()),
    });
    return id;
  }

  /// Returns statuses [viewerId] is allowed to see, enforcing the privacy
  /// rules stored on each status row. Legacy rows without privacy metadata
  /// are treated as 'all' (existing records preserved).
  static Future<List<Map<String, dynamic>>> visibleStatuses(
      Database db, String viewerId) async {
    final now = DateTime.now().toIso8601String();
    final rows = await db.query('statuses',
        where: 'expires_at > ?', whereArgs: [now], orderBy: 'created_at DESC');
    final result = <Map<String, dynamic>>[];
    final contactsCache = <String, Set<String>>{};
    for (final row in rows) {
      final ownerId = row['user_id'].toString();
      final contacts = contactsCache[ownerId] ??= await contactsOf(db, ownerId);
      final allowed = canViewStatus(
        ownerId: ownerId,
        viewerId: viewerId,
        privacy: (row['privacy'] as String?) ?? _defaultPrivacy,
        contacts: contacts,
        except: _decodeSet(row['except_list'] as String?),
        only: _decodeSet(row['only_list'] as String?),
      );
      if (allowed) result.add(row);
    }
    return result;
  }

  /// Records a view for [viewerId] only when the privacy rules allow it.
  /// Returns false for unauthorized viewers without touching status_views.
  static Future<bool> recordStatusView(
      Database db, String statusId, String viewerId) async {
    final rows = await db
        .query('statuses', where: 'id = ?', whereArgs: [statusId], limit: 1);
    if (rows.isEmpty) return false;
    final row = rows.first;
    final ownerId = row['user_id'].toString();
    final allowed = canViewStatus(
      ownerId: ownerId,
      viewerId: viewerId,
      privacy: (row['privacy'] as String?) ?? _defaultPrivacy,
      contacts: await contactsOf(db, ownerId),
      except: _decodeSet(row['except_list'] as String?),
      only: _decodeSet(row['only_list'] as String?),
    );
    if (!allowed) return false;
    await db.insert(
        'status_views',
        {
          'status_id': statusId,
          'viewer_id': viewerId,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    return true;
  }

  /// Viewer list for an own status; unauthorized (filtered-out) viewers can
  /// never appear because they were never recorded.
  static Future<List<Map<String, dynamic>>> viewsOf(
      Database db, String statusId) async {
    return db.rawQuery('''
      SELECT sv.viewer_id, sv.created_at, u.display_name
      FROM status_views sv
      LEFT JOIN users u ON u.id = sv.viewer_id
      WHERE sv.status_id = ?
      ORDER BY sv.created_at DESC
    ''', [statusId]);
  }
}
