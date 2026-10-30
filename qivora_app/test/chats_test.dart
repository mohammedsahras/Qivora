import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:qivora_app/core/database/database_service.dart';
import 'package:qivora_app/features/chat/chats_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late String dbPath;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp;
    dbPath = p.join(dir.path,
        'qivora_chats_test_${DateTime.now().millisecondsSinceEpoch}.db');
    DatabaseService.setTestDatabasePath(dbPath);
    await DatabaseService.instance.close();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  Future<void> seed() async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('users', {
      'id': 'me',
      'display_name': 'Me',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('users', {
      'id': 'contact',
      'display_name': 'Contact',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('conversations', {
      'id': 'convA',
      'title': 'Alpha Chat',
      'type': 'direct',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('conversations', {
      'id': 'convB',
      'title': 'Beta Chat',
      'type': 'direct',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('messages', {
      'id': 'msgA',
      'conversation_id': 'convA',
      'sender_id': 'me',
      'message_type': 'text',
      'content': 'Hello from Alpha',
      'delivery_status': 'sent',
      'created_at': now,
      'updated_at': now,
    });
    await db.update('conversations', {'last_message_id': 'msgA'},
        where: 'id = ?', whereArgs: ['convA']);
    for (final cid in ['convA', 'convB']) {
      await db.insert('conversation_participants', {
        'id': 'p_$cid',
        'conversation_id': cid,
        'user_id': 'me',
        'role': 'member',
        'joined_at': now,
        'is_muted': 0,
        'is_pinned': 0,
        'unread_count': 0,
      });
    }
  }

  testWidgets('displays conversations from the database',
      (WidgetTester tester) async {
    debugPrint('[HANG-DEBUG] 001 test started');
    debugPrint('[HANG-DEBUG] 002 before seed');
    await seed();
    debugPrint('[HANG-DEBUG] 003 after seed');
    debugPrint('[HANG-DEBUG] 004 before pumpWidget');
    await tester.pumpWidget(const MaterialApp(home: ChatsScreen()));
    debugPrint('[HANG-DEBUG] 005 after pumpWidget');
    debugPrint('[HANG-DEBUG] 006 before pump');
    await tester.pump();
    debugPrint('[HANG-DEBUG] 007 after pump');
    debugPrint('[HANG-DEBUG] 008 before pump 1s');
    await tester.pump(const Duration(seconds: 1));
    debugPrint('[HANG-DEBUG] 009 after pump 1s');

    expect(find.text('Alpha Chat'), findsOneWidget);
    expect(find.text('Beta Chat'), findsOneWidget);
    expect(find.text('Hello from Alpha'), findsOneWidget);
  });

  testWidgets('search filters conversations and clears back',
      (WidgetTester tester) async {
    await seed();
    await tester.pumpWidget(const MaterialApp(home: ChatsScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.enterText(find.byType(TextField).first, 'Alpha');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Alpha Chat'), findsOneWidget);
    expect(find.text('Beta Chat'), findsNothing);

    // Clear the search.
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Alpha Chat'), findsOneWidget);
    expect(find.text('Beta Chat'), findsOneWidget);
  });

  testWidgets('shows unread count badge and bolds unread conversations',
      (WidgetTester tester) async {
    await seed();
    final db = await DatabaseService.instance.database;
    await db.update('conversation_participants', {'unread_count': 2},
        where: 'conversation_id = ? AND user_id = ?',
        whereArgs: ['convA', 'me']);

    await tester.pumpWidget(const MaterialApp(home: ChatsScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('pins and unpins a conversation via long-press menu',
      (WidgetTester tester) async {
    await seed();
    await tester.pumpWidget(const MaterialApp(home: ChatsScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Pin Beta Chat.
    await tester.longPress(find.text('Beta Chat'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Pin'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final db = await DatabaseService.instance.database;
    final row = await db.query('conversation_participants',
        where: 'conversation_id = ? AND user_id = ?',
        whereArgs: ['convB', 'me']);
    expect((row.first['is_pinned'] as int) == 1, isTrue);

    // Pinned conversation sorts to the top.
    expect(find.text('Beta Chat'), findsOneWidget);

    // Unpin it.
    await tester.longPress(find.text('Beta Chat'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Unpin'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final row2 = await db.query('conversation_participants',
        where: 'conversation_id = ? AND user_id = ?',
        whereArgs: ['convB', 'me']);
    expect((row2.first['is_pinned'] as int) == 0, isTrue);
  });

  testWidgets('archives and restores a conversation',
      (WidgetTester tester) async {
    await seed();
    await tester.pumpWidget(const MaterialApp(home: ChatsScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.longPress(find.text('Alpha Chat'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Archive'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Alpha Chat'), findsNothing);
    expect(find.text('Beta Chat'), findsOneWidget);

    final db = await DatabaseService.instance.database;
    final archived = await db.query('conversations',
        where: 'id = ? AND archived = 1', whereArgs: ['convA']);
    expect(archived.length, 1);

    // Show archived conversations.
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Show archived conversations'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Alpha Chat'), findsOneWidget);
    expect(find.text('Beta Chat'), findsNothing);

    // Unarchive.
    await tester.longPress(find.text('Alpha Chat'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Unarchive'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final archivedAgain = await db.query('conversations',
        where: 'id = ? AND archived = 1', whereArgs: ['convA']);
    expect(archivedAgain.isEmpty, isTrue);

    // Back to all conversations.
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Show all conversations'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Alpha Chat'), findsOneWidget);
    expect(find.text('Beta Chat'), findsOneWidget);
  });

  testWidgets('shows empty state when there are no conversations',
      (WidgetTester tester) async {
    await seed();
    final db = await DatabaseService.instance.database;
    await db.delete('conversations');

    await tester.pumpWidget(const MaterialApp(home: ChatsScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('No conversations yet'), findsOneWidget);
    expect(find.text('New Conversation'), findsOneWidget);
  });
}
