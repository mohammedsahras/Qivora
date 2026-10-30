import '../../core/database/database_service.dart';

/// Repository for call history operations.
///
/// Encapsulates all SQLite interactions so UI widgets and services remain
/// decoupled from raw database logic.
class CallRepository {
  CallRepository();

  final DatabaseService _db = DatabaseService.instance;

  /// Insert a new call record into [call_history].
  Future<int> insertCall({
    required String callId,
    required String conversationId,
    required String callerId,
    required String recipientId,
    required String callType,
    required String callStatus,
    required DateTime startTime,
    DateTime? endTime,
    Duration? duration,
  }) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    final startIso = startTime.toIso8601String();
    final endIso = endTime?.toIso8601String();

    final result = await db.insert('call_history', {
      'id': callId,
      'conversation_id': conversationId,
      'caller_id': callerId,
      'recipient_id': recipientId,
      'call_type': callType,
      'call_status': callStatus,
      'start_time': startIso,
      'end_time': endIso,
      'duration': duration?.inMilliseconds,
      'created_at': now,
    });

    return result;
  }

  /// Update a call record when the call ends (set end_time and duration).
  Future<int> updateCall({
    required String callId,
    required DateTime endTime,
    required Duration duration,
  }) async {
    final db = await _db.database;
    final endIso = endTime.toIso8601String();

    final result = await db.update(
      'call_history',
      {
        'end_time': endIso,
        'duration': duration.inMilliseconds,
      },
      where: 'id = ?',
      whereArgs: [callId],
    );

    return result;
  }

  /// Get call history for a given [conversationId].
  Future<List<Map<String, dynamic>>> getCallsByConversation({
    required String conversationId,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      'call_history',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'start_time DESC',
    );
    return rows;
  }

  /// Get all call history records.
  Future<List<Map<String, dynamic>>> getAllCalls() async {
    final db = await _db.database;
    final rows = await db.query(
      'call_history',
      orderBy: 'start_time DESC',
    );
    return rows;
  }

  /// Delete a call record (e.g., when a call is cleared from UI).
  Future<int> deleteCall({required String callId}) async {
    final db = await _db.database;
    final result = await db.delete(
      'call_history',
      where: 'id = ?',
      whereArgs: [callId],
    );
    return result;
  }
}
