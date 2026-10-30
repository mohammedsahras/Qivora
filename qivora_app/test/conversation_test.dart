import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:qivora_app/core/database/database_service.dart';
import 'package:qivora_app/features/chat/conversation_screen.dart';

void main() {
  databaseFactory = databaseFactoryFfi;
  late String dbPath;

  setUp(() async {
    final dir = Directory.systemTemp;
    dbPath = p.join(dir.path,
        'qivora_conv_test_${DateTime.now().millisecondsSinceEpoch}.db');
    DatabaseService.setTestDatabasePath(dbPath);
    await DatabaseService.instance.close();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  Future<void> seedConversation() async {
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
      'title': 'Test Chat',
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
  }

  Future<int> messageCount() async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query('messages',
        where: 'conversation_id = ? AND deleted_at IS NULL',
        whereArgs: ['conv1']);
    return rows.length;
  }

  testWidgets('sends a message, persists it, and displays it immediately',
      (WidgetTester tester) async {
    await seedConversation();
    await tester.pumpWidget(
      const MaterialApp(
        home: ConversationScreen(
          conversationId: 'conv1',
          conversationTitle: 'Test Chat',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.enterText(find.byType(TextField).first, 'Hello world');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Hello world'), findsOneWidget);
    expect(await messageCount(), 1);
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      'messages',
      where: 'conversation_id = ? AND content = ?',
      whereArgs: ['conv1', 'Hello world'],
    );
    expect(rows.length, 1);
    expect(rows.first['sender_id'], 'me');
    expect(rows.first['delivery_status'], 'sent');
  });

  testWidgets('rejects empty messages', (WidgetTester tester) async {
    await seedConversation();
    await tester.pumpWidget(
      const MaterialApp(
        home: ConversationScreen(
          conversationId: 'conv1',
          conversationTitle: 'Test Chat',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(await messageCount(), 0);
  });

  testWidgets('prevents duplicate sends from rapid repeated taps',
      (WidgetTester tester) async {
    await seedConversation();
    await tester.pumpWidget(
      const MaterialApp(
        home: ConversationScreen(
          conversationId: 'conv1',
          conversationTitle: 'Test Chat',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.enterText(find.byType(TextField).first, 'Duplicate?');
    await tester.tap(find.byTooltip('Send'));
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Duplicate?'), findsNWidgets(1));
    expect(await messageCount(), 1);
  });

  testWidgets(
      'loads message history and reads delivery status from the database',
      (WidgetTester tester) async {
    await seedConversation();
    final db = await DatabaseService.instance.database;
    final now = DateTime.now();
    await db.insert('messages', {
      'id': 'msg1',
      'conversation_id': 'conv1',
      'sender_id': 'me',
      'message_type': 'text',
      'content': 'First message',
      'delivery_status': 'read',
      'created_at': now.subtract(const Duration(minutes: 5)).toIso8601String(),
      'updated_at': now.subtract(const Duration(minutes: 5)).toIso8601String(),
    });
    await db.insert('messages', {
      'id': 'msg2',
      'conversation_id': 'conv1',
      'sender_id': 'me',
      'message_type': 'text',
      'content': 'Second message',
      'delivery_status': 'sent',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: ConversationScreen(
          conversationId: 'conv1',
          conversationTitle: 'Test Chat',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('First message'), findsOneWidget);
    expect(find.text('Second message'), findsOneWidget);
    // 'read' is stored in the database and rendered as done_all_rounded.
    expect(find.byIcon(Icons.done_all_rounded), findsWidgets);
  });

  testWidgets('deletes a message with confirmation and soft-deletes it',
      (WidgetTester tester) async {
    await seedConversation();
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('messages', {
      'id': 'msg1',
      'conversation_id': 'conv1',
      'sender_id': 'me',
      'message_type': 'text',
      'content': 'To be deleted',
      'delivery_status': 'sent',
      'created_at': now,
      'updated_at': now,
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: ConversationScreen(
          conversationId: 'conv1',
          conversationTitle: 'Test Chat',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.longPress(find.text('To be deleted'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('To be deleted'), findsNothing);
    final rows =
        await db.query('messages', where: 'id = ?', whereArgs: ['msg1']);
    expect(rows.length, 1);
    expect(rows.first['deleted_at'], isNotNull);
  });
}
