import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:al_mraay/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('AppTheme & M3 Single-Seed Dynamic Color System Tests', () {
    test('Default Seed Color should be M3 Dynamic Olive (0xFF5C631D)', () {
      expect(AppTheme.defaultSeedColor, const Color(0xFF5C631D));
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

    test('getDynamicPalette generates 9 harmonized M3 tonal roles from ColorScheme', () {
      final lightPalette = AppTheme.getDynamicPalette(AppTheme.lightTheme.colorScheme);
      final darkPalette = AppTheme.getDynamicPalette(AppTheme.darkTheme.colorScheme);
      expect(lightPalette.length, 9);
      expect(darkPalette.length, 9);
      expect(lightPalette.first, AppTheme.lightTheme.colorScheme.primary);
      expect(darkPalette.first, AppTheme.darkTheme.colorScheme.primary);
      expect(lightPalette.first, isNot(equals(darkPalette.first)));
    });

    test('Custom Seed Color generates matching dynamic theme', () {
      const customSeed = Color(0xFF5C631D);
      final customTheme = AppTheme.getLightTheme(seedColor: customSeed);
      expect(customTheme.useMaterial3, true);
      expect(customTheme.colorScheme.brightness, Brightness.light);
    });

    test('Codebase Audit: Zero hardcoded Color(0x...) outside AppTheme and zero Material 2 Colors.* swatches in lib/', () {
      final libDir = Directory('lib');
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      final hardcodedHexViolations = <String>[];
      final materialSwatchViolations = <String>[];
      final swatchRegex = RegExp(
        r'\bColors\.(purple|deepPurple|indigo|teal|amber|blue|lightBlue|green|lightGreen|orange|deepOrange|red|pink|cyan|yellow|lime|brown|blueGrey|grey)\b',
      );
      final hexRegex = RegExp(r'Color\(0x[0-9A-Fa-f]+\)');

      for (final file in dartFiles) {
        final normalizedPath = file.path.replaceAll(r'\', '/');
        final content = file.readAsStringSync();

        if (!normalizedPath.endsWith('lib/core/theme/app_theme.dart')) {
          final hexMatches = hexRegex.allMatches(content);
          if (hexMatches.isNotEmpty) {
            hardcodedHexViolations.add('$normalizedPath (${hexMatches.length})');
          }
        }

        final swatchMatches = swatchRegex.allMatches(content);
        if (swatchMatches.isNotEmpty) {
          materialSwatchViolations.add('$normalizedPath (${swatchMatches.length})');
        }
      }

      expect(
        hardcodedHexViolations,
        isEmpty,
        reason: 'All UI colors must be derived dynamically from ColorScheme; found hardcoded Color(0x...) in: $hardcodedHexViolations',
      );
      expect(
        materialSwatchViolations,
        isEmpty,
        reason: 'No arbitrary Material 2 Colors.* swatches allowed in lib/; found in: $materialSwatchViolations',
      );
    });
  });
}
