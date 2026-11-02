import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:qivora_app/core/database/database_service.dart';
import 'package:qivora_app/features/contacts/contacts_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactoryFfiNoIsolate;
  late String dbPath;

  GoRouter buildRouter() => GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, __) => const ContactsScreen()),
          GoRoute(
            path: '/chat/:id',
            builder: (_, __) => const Scaffold(body: SizedBox()),
          ),
        ],
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp;
    dbPath = p.join(dir.path,
        'qivora_contacts_test_${DateTime.now().millisecondsSinceEpoch}.db');
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
      'id': 'u1',
      'display_name': 'Alice Smith',
      'username': 'alice',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('users', {
      'id': 'u2',
      'display_name': 'Bob Jones',
      'username': 'bob',
      'created_at': now,
      'updated_at': now,
    });
  }

  testWidgets('loads contacts, filters by search, and clears search',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await seed();
    });
    await tester.pumpWidget(MaterialApp.router(routerConfig: buildRouter()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Alice Smith'), findsOneWidget);
    expect(find.text('Bob Jones'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Alice');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Alice Smith'), findsOneWidget);
    expect(find.text('Bob Jones'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Alice Smith'), findsOneWidget);
    expect(find.text('Bob Jones'), findsOneWidget);
  });

  testWidgets('opens or creates a conversation when a contact is tapped',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await seed();
    });
    await tester.pumpWidget(MaterialApp.router(routerConfig: buildRouter()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Alice Smith').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final db = (await tester.runAsync<Database>(() => openDb()))!;
    final convs = await db.query('conversations',
        where: 'title = ? AND type = ?', whereArgs: ['Alice Smith', 'direct']);
    expect(convs.length, 1);
    final cid = convs.first['id'] as String;

    final parts = await db.query('conversation_participants',
        where: 'conversation_id = ?', whereArgs: [cid]);
    expect(parts.any((r) => r['user_id'] == 'me'), isTrue);
    expect(parts.any((r) => r['user_id'] == 'u1'), isTrue);
  });

  testWidgets('shows empty state without contacts', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await seed();
    });

    final db = (await tester.runAsync<Database>(() => openDb()))!;
    await tester.runAsync(() async {
      await db.delete('users');
    });

    await tester.pumpWidget(MaterialApp.router(routerConfig: buildRouter()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('No contacts yet'), findsOneWidget);
  });
}

Future<Database> openDb() => DatabaseService.instance.database;
