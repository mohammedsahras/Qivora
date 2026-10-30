import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qivora_app/main.dart';

void main() {
  testWidgets('Qivora app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: QivoraApp()));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Qivora'), findsWidgets);
  });
}
