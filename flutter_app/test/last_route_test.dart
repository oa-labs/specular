import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specular/src/ui/specular_app.dart';

void main() {
  group('initialLocationFor', () {
    test('restores the saved route for an ordinary cold launch', () {
      expect(
        initialLocationFor(platformRoute: '/', savedRoute: '/todos'),
        '/todos',
      );
    });

    test('uses an explicit platform route instead of the saved route', () {
      expect(
        initialLocationFor(platformRoute: '/todos', savedRoute: '/note/123'),
        '/todos',
      );
    });

    test('opens home when no route has been saved', () {
      expect(initialLocationFor(platformRoute: '/', savedRoute: null), '/');
    });
  });

  group('theme mode storage', () {
    test('defaults to light mode and restores dark mode', () {
      expect(themeModeFromStorage(null), ThemeMode.light);
      expect(themeModeFromStorage('dark'), ThemeMode.dark);
      expect(themeModeStorageValue(ThemeMode.dark), 'dark');
    });
  });
}
