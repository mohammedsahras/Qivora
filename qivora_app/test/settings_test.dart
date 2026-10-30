import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qivora_app/features/settings/settings_screen.dart';

void main() {
  test('theme mode can be set and read within a provider container', () async {
    SharedPreferences.setMockInitialValues({});

    final container = ProviderContainer();
    final notifier = container.read(themeModeProvider.notifier);

    expect(container.read(themeModeProvider), ThemeMode.light);

    await notifier.set(ThemeMode.dark);
    expect(container.read(themeModeProvider), ThemeMode.dark);

    await notifier.set(ThemeMode.system);
    expect(container.read(themeModeProvider), ThemeMode.system);

    container.dispose();
  });

  test('all three theme modes round-trip through SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    final notifier = container.read(themeModeProvider.notifier);

    for (final mode in ThemeMode.values) {
      await notifier.set(mode);
      expect(container.read(themeModeProvider), mode);
    }
    container.dispose();
  });
}
