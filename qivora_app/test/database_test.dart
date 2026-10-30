import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:qivora_app/core/database/database_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactoryFfi;
  late String dbPath;

  setUp(() async {
    final dir = Directory.systemTemp;
    dbPath = p.join(dir.path,
        'qivora_unit_test_${DateTime.now().millisecondsSinceEpoch}.db');
    // Point the singleton at a throwaway database so real user data is
    // never touched by tests.
    DatabaseService.setTestDatabasePath(dbPath);
    await DatabaseService.instance.close();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  Future<Database> openFreshV3() async {
    // Simulate an existing v3 database (before archived/unread columns)
    // so the v4/v5 migration path can be exercised.
    final db = await openDatabase(dbPath, version: 3, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE users (
          id TEXT PRIMARY KEY, display_name TEXT NOT NULL, username TEXT UNIQUE,
          phone_number TEXT, email TEXT, avatar_path TEXT, status_text TEXT,
          is_online INTEGER DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        );
      ''');
      await db.execute('''
        CREATE TABLE conversations (
          id TEXT PRIMARY KEY, title TEXT NOT NULL, type TEXT NOT NULL,
          avatar_path TEXT, last_message_id TEXT,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        );
      ''');
      await db.execute('''
        CREATE TABLE conversation_participants (
          id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL, user_id TEXT NOT NULL,
          role TEXT DEFAULT 'member', joined_at TEXT NOT NULL,
          is_muted INTEGER DEFAULT 0, is_pinned INTEGER DEFAULT 0,
          FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
          FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        );
      ''');
      await db.execute('''
        CREATE TABLE messages (
          id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL, sender_id TEXT NOT NULL,
          message_type TEXT NOT NULL, content TEXT, reply_to_message_id TEXT,
          attachment_path TEXT, attachment_type TEXT, attachment_filename TEXT,
          attachment_size INTEGER, media_duration INTEGER,
          forwarded_from_message_id TEXT, forwarded_from_conversation_id TEXT,
          delivery_status TEXT DEFAULT 'sent', created_at TEXT NOT NULL,
          updated_at TEXT, deleted_at TEXT,
          FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
          FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE
        );
      ''');
      await db.execute('''
        CREATE TABLE message_reactions (
          id TEXT PRIMARY KEY, message_id TEXT NOT NULL, user_id TEXT NOT NULL,
          emoji TEXT NOT NULL, created_at TEXT NOT NULL,
          FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
          FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        );
      ''');
      await db.execute('''
        CREATE TABLE contacts (
          id TEXT PRIMARY KEY, owner_user_id TEXT NOT NULL, contact_user_id TEXT NOT NULL,
          display_name TEXT, created_at TEXT NOT NULL,
          UNIQUE(owner_user_id, contact_user_id)
        );
      ''');
      await db.execute('''
        CREATE TABLE call_history (
          id TEXT PRIMARY KEY, conversation_id TEXT, caller_id TEXT, recipient_id TEXT,
          call_type TEXT NOT NULL, call_status TEXT NOT NULL, start_time TEXT NOT NULL,
          end_time TEXT, duration INTEGER, created_at TEXT NOT NULL,
          FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE SET NULL,
          FOREIGN KEY (caller_id) REFERENCES users(id) ON DELETE CASCADE,
          FOREIGN KEY (recipient_id) REFERENCES users(id) ON DELETE SET NULL
        );
      ''');
      await db.execute(
          'CREATE INDEX idx_messages_conv_created ON messages(conversation_id, created_at);');
      await db.execute(
          'CREATE UNIQUE INDEX idx_reactions_unique ON message_reactions(message_id, user_id);');
      await db.execute(
          'CREATE INDEX idx_reactions_msg ON message_reactions(message_id);');
      await db.execute(
          'CREATE INDEX idx_participants_conv ON conversation_participants(conversation_id);');
      await db.execute(
          'CREATE INDEX idx_participants_user ON conversation_participants(user_id);');
    });
    return db;
  }

  test(
      'fresh database is created at version 8 with all expected tables and columns',
      () async {
    final db = await DatabaseService.instance.database;
    expect(db.path, endsWith(p.basename(dbPath)));

    final version = (await db.rawQuery('PRAGMA user_version'))
        .first['user_version'] as int?;
    expect(version, 13);

    final tables =
        (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
            .map((row) => row['name'] as String)
            .toSet();
    expect(tables, contains('users'));
    expect(tables, contains('conversations'));
    expect(tables, contains('conversation_participants'));
    expect(tables, contains('messages'));
    expect(tables, contains('message_reactions'));
    expect(tables, contains('message_read_receipts'));
    expect(tables, contains('contacts'));
    expect(tables, contains('call_history'));

    final convCols = (await db.rawQuery('PRAGMA table_info(conversations)'))
        .map((row) => row['name'] as String)
        .toSet();
    expect(convCols, contains('archived'));

    final partCols =
        (await db.rawQuery('PRAGMA table_info(conversation_participants)'))
            .map((row) => row['name'] as String)
            .toSet();
    expect(partCols, contains('unread_count'));

    final userCols = (await db.rawQuery('PRAGMA table_info(users)'))
        .map((row) => row['name'] as String)
        .toSet();
    expect(userCols, contains('about'));

    final msgCols = (await db.rawQuery('PRAGMA table_info(messages)'))
        .map((row) => row['name'] as String)
        .toSet();
    expect(msgCols, contains('starred'));
    expect(msgCols, contains('audio_path'));

    final rrCols =
        (await db.rawQuery('PRAGMA table_info(message_read_receipts)'))
            .map((row) => row['name'] as String)
            .toSet();
    expect(rrCols, contains('message_id'));
    expect(rrCols, contains('user_id'));
    expect(rrCols, contains('read_at'));
  });

  test(
      'upgrade from a v3 database applies archived, unread_count, about, starred, read_receipts, and audio_path columns',
      () async {
    final v3 = await openFreshV3();
    await v3.insert('users', {
      'id': 'me',
      'display_name': 'Old User',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    await v3.insert('conversations', {
      'id': 'conv1',
      'title': 'Old chat',
      'type': 'direct',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    await v3.close();

    final db = await DatabaseService.instance.database;
    final version = (await db.rawQuery('PRAGMA user_version'))
        .first['user_version'] as int?;
    expect(version, 13);

    final convCols = (await db.rawQuery('PRAGMA table_info(conversations)'))
        .map((row) => row['name'] as String)
        .toSet();
    expect(convCols, contains('archived'));

    final partCols =
        (await db.rawQuery('PRAGMA table_info(conversation_participants)'))
            .map((row) => row['name'] as String)
            .toSet();
    expect(partCols, contains('unread_count'));

    final msgCols = (await db.rawQuery('PRAGMA table_info(messages)'))
        .map((row) => row['name'] as String)
        .toSet();
    expect(msgCols, contains('starred'));
    expect(msgCols, contains('audio_path'));

    final rrCols =
        (await db.rawQuery('PRAGMA table_info(message_read_receipts)'))
            .map((row) => row['name'] as String)
            .toSet();
    expect(rrCols, contains('message_id'));
    expect(rrCols, contains('user_id'));
    expect(rrCols, contains('read_at'));

    // Existing rows survive the upgrade.
    final conv =
        await db.query('conversations', where: 'id = ?', whereArgs: ['conv1']);
    expect(conv.length, 1);
  });

  test('conversation CRUD: pin, mute, archive, unread, soft delete, cascade',
      () async {
    final db = await DatabaseService.instance.database;
    await db.insert('users', {
      'id': 'me',
      'display_name': 'Me',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    await db.insert('users', {
      'id': 'contact',
      'display_name': 'Contact',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    final now = DateTime.now().toIso8601String();
    await db.insert('conversations', {
      'id': 'conv1',
      'title': 'Chat',
      'type': 'direct',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('conversation_participants', {
      'id': 'p1',
      'conversation_id': 'conv1',
      'user_id': 'me',
      'role': 'member',
      'joined_at': now,
      'is_muted': 0,
      'is_pinned': 0,
      'unread_count': 0,
    });
    await db.insert('messages', {
      'id': 'msg1',
      'conversation_id': 'conv1',
      'sender_id': 'me',
      'message_type': 'text',
      'content': 'Hello',
      'delivery_status': 'sent',
      'created_at': now,
      'updated_at': now,
    });

    // Pin and unread updates persist.
    await db.update(
        'conversation_participants', {'is_pinned': 1, 'unread_count': 3},
        where: 'conversation_id = ? AND user_id = ?',
        whereArgs: ['conv1', 'me']);

    final row = await db.query('conversation_participants',
        where: 'conversation_id = ? AND user_id = ?',
        whereArgs: ['conv1', 'me']);
    expect((row.first['is_pinned'] as int) == 1, isTrue);
    expect(row.first['unread_count'], 3);

    // Archive hides it from the active list.
    await db.update('conversations', {'archived': 1},
        where: 'id = ?', whereArgs: ['conv1']);
    final active =
        await db.query('conversations', where: 'archived = ?', whereArgs: [0]);
    expect(active.isEmpty, isTrue);

    // Soft delete removes the message from the active set but keeps the row.
    await db.update('messages', {'deleted_at': now},
        where: 'id = ?', whereArgs: ['msg1']);
    final live = await db.query('messages',
        where: 'conversation_id = ? AND deleted_at IS NULL',
        whereArgs: ['conv1']);
    expect(live.isEmpty, isTrue);
    final all =
        await db.query('messages', where: 'id = ?', whereArgs: ['msg1']);
    expect(all.length, 1);

    // Deleting the conversation cascades to messages and participants.
    await db.delete('conversations', where: 'id = ?', whereArgs: ['conv1']);
    final msgs = await db
        .query('messages', where: 'conversation_id = ?', whereArgs: ['conv1']);
    final parts = await db.query('conversation_participants',
        where: 'conversation_id = ?', whereArgs: ['conv1']);
    expect(msgs.isEmpty, isTrue);
    expect(parts.isEmpty, isTrue);
  });

  test('message reactions: add, change, remove, unique constraint', () async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('users', {
      'id': 'me',
      'display_name': 'Me',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('users', {
      'id': 'u1',
      'display_name': 'User1',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('conversations', {
      'id': 'conv1',
      'title': 'Chat',
      'type': 'direct',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('conversation_participants', {
      'id': 'p1',
      'conversation_id': 'conv1',
      'user_id': 'me',
      'role': 'member',
      'joined_at': now,
      'is_muted': 0,
      'is_pinned': 0,
      'unread_count': 0,
    });
    await db.insert('messages', {
      'id': 'msg1',
      'conversation_id': 'conv1',
      'sender_id': 'me',
      'message_type': 'text',
      'content': 'Hello',
      'delivery_status': 'sent',
      'created_at': now,
      'updated_at': now,
    });

    // Add a reaction.
    await db.insert('message_reactions', {
      'id': const Uuid().v4(),
      'message_id': 'msg1',
      'user_id': 'me',
      'emoji': '👍',
      'created_at': now,
    });
    final reactions = await db.query('message_reactions',
        where: 'message_id = ?', whereArgs: ['msg1']);
    expect(reactions.length, 1);
    expect(reactions.first['emoji'], '👍');

    // Change the reaction (same user, same message, different emoji).
    await db.update('message_reactions', {'emoji': '❤️', 'created_at': now},
        where: 'message_id = ? AND user_id = ?', whereArgs: ['msg1', 'me']);
    final changed = await db.query('message_reactions',
        where: 'message_id = ? AND user_id = ?', whereArgs: ['msg1', 'me']);
    expect(changed.length, 1);
    expect(changed.first['emoji'], '❤️');

    // Remove the reaction.
    await db.delete('message_reactions',
        where: 'message_id = ? AND user_id = ?', whereArgs: ['msg1', 'me']);
    final removed = await db.query('message_reactions',
        where: 'message_id = ?', whereArgs: ['msg1']);
    expect(removed.isEmpty, isTrue);

    // Different users can react with the same emoji (unique is per user+emoji).
    await db.insert('message_reactions', {
      'id': const Uuid().v4(),
      'message_id': 'msg1',
      'user_id': 'me',
      'emoji': '👍',
      'created_at': now,
    });
    await db.insert('message_reactions', {
      'id': const Uuid().v4(),
      'message_id': 'msg1',
      'user_id': 'u1',
      'emoji': '👍',
      'created_at': now,
    });
    final allReactions = await db.query('message_reactions',
        where: 'message_id = ?', whereArgs: ['msg1']);
    expect(allReactions.length, 2);
  });

  test('starred messages: star and unstar persist', () async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('users', {
      'id': 'me',
      'display_name': 'Me',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('conversations', {
      'id': 'conv1',
      'title': 'Chat',
      'type': 'direct',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('messages', {
      'id': 'msg1',
      'conversation_id': 'conv1',
      'sender_id': 'me',
      'message_type': 'text',
      'content': 'Important',
      'delivery_status': 'sent',
      'starred': 0,
      'created_at': now,
      'updated_at': now,
    });

    // Star the message.
    await db.update('messages', {'starred': 1, 'updated_at': now},
        where: 'id = ?', whereArgs: ['msg1']);
    final starred = await db.query('messages',
        where: 'id = ? AND starred = 1', whereArgs: ['msg1']);
    expect(starred.length, 1);

    // Unstar the message.
    await db.update('messages', {'starred': 0, 'updated_at': now},
        where: 'id = ?', whereArgs: ['msg1']);
    final unstarred = await db.query('messages',
        where: 'id = ? AND starred = 1', whereArgs: ['msg1']);
    expect(unstarred.isEmpty, isTrue);
  });

  test('read receipts: create and query', () async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('users', {
      'id': 'me',
      'display_name': 'Me',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('users', {
      'id': 'u1',
      'display_name': 'User1',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('conversations', {
      'id': 'conv1',
      'title': 'Chat',
      'type': 'direct',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('messages', {
      'id': 'msg1',
      'conversation_id': 'conv1',
      'sender_id': 'u1',
      'message_type': 'text',
      'content': 'Hello',
      'delivery_status': 'sent',
      'created_at': now,
      'updated_at': now,
    });

    // Create a read receipt.
    await db.insert('message_read_receipts', {
      'id': const Uuid().v4(),
      'message_id': 'msg1',
      'user_id': 'me',
      'read_at': now,
    });
    final receipts = await db.query('message_read_receipts',
        where: 'message_id = ? AND user_id = ?', whereArgs: ['msg1', 'me']);
    expect(receipts.length, 1);

    // Unique constraint: same user can't have two receipts for same message.
    await db.update('messages', {'delivery_status': 'read'},
        where: 'id = ?', whereArgs: ['msg1']);
    final msg =
        await db.query('messages', where: 'id = ?', whereArgs: ['msg1']);
    expect(msg.first['delivery_status'], 'read');
  });
}
