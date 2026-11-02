import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qivora_app/core/theme/app_colors.dart';
import 'package:qivora_app/core/widgets/qivora_back_button.dart';

/// A minimal scaffold that hosts the back button.
class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const QivoraBackButton(),
        title: const Text('Secondary Screen'),
      ),
      body: const Center(child: Text('Body')),
    );
  }
}

GoRouter _routerOf(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Scaffold).first));

void main() {
  late GoRouter router;

  setUp(() {
    router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Center(child: Text('Home'))),
        ),
        GoRoute(
          path: '/secondary',
          builder: (_, __) => const _Host(),
        ),
      ],
    );
  });

  testWidgets('renders a visible rounded-square back button',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    _routerOf(tester).push('/secondary');
    await tester.pumpAndSettle();

    final backButton = find.byType(QivoraBackButton);
    expect(backButton, findsOneWidget);

    // Rounded square: verify the 48x48 Container exists.
    expect(
      find.descendant(
        of: backButton,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.constraints?.maxWidth == 48.0 &&
              widget.constraints?.maxHeight == 48.0,
        ),
      ),
      findsOneWidget,
    );

    // Dark teal arrow icon.
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

    // Light mint / emerald background.
    expect(
      find.descendant(
        of: backButton,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color ==
                  AppColors.primaryLight,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('pops to previous route when one exists',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    _routerOf(tester).push('/secondary');
    await tester.pumpAndSettle();
    expect(_routerOf(tester).canPop(), isTrue);

    await tester.tap(find.byType(QivoraBackButton));
    await tester.pumpAndSettle();
    expect(_routerOf(tester).canPop(), isFalse);
  });

  testWidgets('falls back to /home when no previous route exists',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    _routerOf(tester).go('/secondary');
    await tester.pumpAndSettle();
    expect(_routerOf(tester).canPop(), isFalse);

    await tester.tap(find.byType(QivoraBackButton));
    await tester.pumpAndSettle();

    expect(_routerOf(tester).canPop(), isFalse);
  });

  testWidgets('works in nested navigation (pop returns to immediate parent)',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final nav = _routerOf(tester);
    nav.push('/secondary');
    await tester.pumpAndSettle();
    expect(nav.canPop(), isTrue);

    nav.push('/secondary');
    await tester.pumpAndSettle();
    expect(nav.canPop(), isTrue);

    await tester.tap(find.byType(QivoraBackButton).last);
    await tester.pumpAndSettle();

    expect(nav.canPop(), isTrue);
  });
}
