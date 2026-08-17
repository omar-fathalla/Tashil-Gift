import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:al_mraay/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('AppTheme & M3 Single-Seed Tests', () {
    test('Default Seed Color should be Royal Purple', () {
      expect(AppTheme.defaultSeedColor, const Color(0xFF6750A4));
    });

    test('Light Theme should have useMaterial3 true and valid ColorScheme', () {
      final lightTheme = AppTheme.lightTheme;
      expect(lightTheme.useMaterial3, true);
      expect(lightTheme.brightness, Brightness.light);
      expect(lightTheme.colorScheme.primary, isNotNull);
      expect(lightTheme.colorScheme.surface, isNotNull);
      expect(lightTheme.colorScheme.primaryContainer, isNotNull);
    });

    test('Dark Theme should have useMaterial3 true and dark brightness', () {
      final darkTheme = AppTheme.darkTheme;
      expect(darkTheme.useMaterial3, true);
      expect(darkTheme.brightness, Brightness.dark);
      expect(darkTheme.colorScheme.primary, isNotNull);
      expect(darkTheme.colorScheme.surface, isNotNull);
    });

    test('Custom Seed Color generates matching dynamic theme', () {
      const customPurple = Color(0xFF7C3AED);
      final customTheme = AppTheme.getLightTheme(seedColor: customPurple);
      expect(customTheme.useMaterial3, true);
      expect(customTheme.colorScheme.brightness, Brightness.light);
    });
  });
}
