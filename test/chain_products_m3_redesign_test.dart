import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/localization/app_strings.dart';

void main() {
  group('Chain Products Intelligence M3 Redesign & Zero Emoji Compliance', () {
    final emojiRegex = RegExp(r'[🚨💡🏷️⚡⚔️🏆🌟🗄️🧾]');

    test('All Arabic AppStrings for top controls are free of raw emojis', () {
      final strings = AppStrings('ar');

      // Baseline & Header
      expect(strings.fathallaBaselineTag.contains(emojiRegex), isFalse);
      expect(strings.fathallaMarketPositionLabel.contains(emojiRegex), isFalse);

      // Mode Switchers
      expect(strings.omniRadarModeLabel.contains(emojiRegex), isFalse);
      expect(strings.headToHeadModeLabel.contains(emojiRegex), isFalse);

      // Hero Metrics & Defense Modes
      expect(strings.metricPriceThreats.contains(emojiRegex), isFalse);
      expect(strings.metricCompetitorPromosNotAtFathalla.contains(emojiRegex), isFalse);
      expect(strings.metricCompetitorPromosNotAtFathallaSubtitle.contains(emojiRegex), isFalse);
      expect(strings.metricAllCompetitorPromotions.contains(emojiRegex), isFalse);
      expect(strings.metricThreatsWithPromo.contains(emojiRegex), isFalse);
      expect(strings.filterSegmentThreatsOnly.contains(emojiRegex), isFalse);
      expect(strings.filterSegmentAllArchive.contains(emojiRegex), isFalse);
      expect(strings.proofOfReceiptLabel.contains(emojiRegex), isFalse);
    });

    test('All English AppStrings for top controls are free of raw emojis', () {
      final strings = AppStrings('en');

      expect(strings.fathallaBaselineTag.contains(emojiRegex), isFalse);
      expect(strings.omniRadarModeLabel.contains(emojiRegex), isFalse);
      expect(strings.headToHeadModeLabel.contains(emojiRegex), isFalse);
      expect(strings.metricPriceThreats.contains(emojiRegex), isFalse);
      expect(strings.metricCompetitorPromosNotAtFathalla.contains(emojiRegex), isFalse);
      expect(strings.metricAllCompetitorPromotions.contains(emojiRegex), isFalse);
      expect(strings.metricThreatsWithPromo.contains(emojiRegex), isFalse);
      expect(strings.filterSegmentThreatsOnly.contains(emojiRegex), isFalse);
      expect(strings.filterSegmentAllArchive.contains(emojiRegex), isFalse);
    });

    test('All Hindi AppStrings for top controls are free of raw emojis', () {
      final strings = AppStrings('hi');

      expect(strings.fathallaBaselineTag.contains(emojiRegex), isFalse);
      expect(strings.omniRadarModeLabel.contains(emojiRegex), isFalse);
      expect(strings.headToHeadModeLabel.contains(emojiRegex), isFalse);
      expect(strings.metricPriceThreats.contains(emojiRegex), isFalse);
      expect(strings.metricCompetitorPromosNotAtFathalla.contains(emojiRegex), isFalse);
      expect(strings.metricAllCompetitorPromotions.contains(emojiRegex), isFalse);
      expect(strings.metricThreatsWithPromo.contains(emojiRegex), isFalse);
      expect(strings.filterSegmentThreatsOnly.contains(emojiRegex), isFalse);
      expect(strings.filterSegmentAllArchive.contains(emojiRegex), isFalse);
    });

    test('Source code audit: Chain intelligence files are free of raw emojis and hardcoded palette colors', () {
      final filePaths = [
        'lib/features/admin/presentation/chain_products_intelligence_screen.dart',
        'lib/features/admin/presentation/widgets/chain_products_matrix_table.dart',
        'lib/features/admin/presentation/widgets/chain_product_card.dart',
        'lib/features/admin/presentation/widgets/product_price_history_dialog.dart',
      ];

      for (final path in filePaths) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'File must exist: $path');
        final content = file.readAsStringSync();

        // 1. Zero raw emoji rule
        final matchedEmojis = emojiRegex.allMatches(content).map((m) => m.group(0)).toSet();
        expect(
          matchedEmojis,
          isEmpty,
          reason: 'File $path must not contain raw emojis, found: $matchedEmojis',
        );

        // 2. No arbitrary pastel Colors.* (e.g. Colors.red.shade*, Colors.green.shade*, Colors.purple.*)
        if (path.contains('chain_products_intelligence_screen.dart') ||
            path.contains('chain_products_matrix_table.dart') ||
            path.contains('chain_product_card.dart')) {
          final colorMatches = RegExp(r'Colors\.(red|green|purple|indigo|amber|teal|blue)\b')
              .allMatches(content)
              .map((m) => m.group(0))
              .toSet();
          expect(
            colorMatches,
            isEmpty,
            reason: 'File $path must derive colors from ColorScheme instead of static Colors, found: $colorMatches',
          );
        }
      }
    });
  });
}
