import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/features/games/presentation/direct_gift_claim_screen.dart';
import 'package:al_mraay/core/localization/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DirectGiftClaimScreen Tests', () {
    testWidgets('Renders DirectGiftClaimScreen with prize name and single unit quantity', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DirectGiftClaimScreen(
              transactionId: 'test_tx_123',
              eventId: 'event_456',
              prizeName: 'زمزمية مياه رياضية فاخرة',
              quantity: 1,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify header & celebratory texts
      expect(find.text('استحقاق الهدية الفورية المباشرة'), findsOneWidget);
      expect(find.text('مبروك! استحققت الهدية الفورية'), findsOneWidget);
      expect(find.text('زمزمية مياه رياضية فاخرة'), findsOneWidget);

      // Verify single unit count
      expect(find.textContaining('1 قطعة'), findsOneWidget);

      // Verify claim action button
      expect(find.text('تسليم الهدية للعميل'), findsOneWidget);
    });

    testWidgets('Renders DirectGiftClaimScreen with multiplied quantity (e.g. 3 units)', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DirectGiftClaimScreen(
              transactionId: 'test_tx_multi',
              eventId: 'event_789',
              prizeName: 'كوب حراري ستانلس ستيل',
              quantity: 3,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('كوب حراري ستانلس ستيل'), findsOneWidget);
      expect(find.textContaining('3 قطع'), findsOneWidget);
      expect(find.byIcon(Icons.stars_rounded), findsOneWidget);
    });

    test('AppStrings contains valid Direct Gift keys for all supported languages', () {
      final stringsAr = AppStrings('ar');
      final stringsEn = AppStrings('en');
      final stringsHi = AppStrings('hi');

      // Arabic
      expect(stringsAr.gameDirectGiftTitle, contains('الهدية الفورية المباشرة'));
      expect(stringsAr.claimDirectGift, contains('تسليم الهدية'));

      // English
      expect(stringsEn.gameDirectGiftTitle, contains('Direct Instant Gift'));
      expect(stringsEn.claimDirectGift, contains('Gift'));

      // Hindi
      expect(stringsHi.gameDirectGiftTitle, contains('प्रत्यक्ष'));
      expect(stringsHi.claimDirectGift, contains('उपहार'));
    });
  });
}
