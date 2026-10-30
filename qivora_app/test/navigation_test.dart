import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qivora_app/features/splash/splash_screen.dart';

void main() {
  testWidgets('splash to welcome', (t) async {
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, __) => const SplashScreen(duration: Duration(milliseconds: 1))), GoRoute(path: '/welcome', builder: (_, __) => const Text('Welcome'))]);
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.pump(const Duration(milliseconds: 10));
    await t.pump();
    expect(find.text('Welcome'), findsOneWidget);
  });
}
