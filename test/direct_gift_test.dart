import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/features/games/presentation/direct_gift_claim_screen.dart';
import 'package:al_mraay/core/localization/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DirectGiftClaimScreen Tests', () {
    testWidgets('Renders clean DirectGiftClaimScreen for customer with prize name without confusing stock badge', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DirectGiftClaimScreen(
              transactionId: 'test_tx_123',
              eventId: 'event_456',
              prizeName: 'زمزمية مياه رياضية فاخرة',
              quantity: 1,
              isDemo: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify header & celebratory texts
      expect(find.text('استحقاق الهدية الفورية المباشرة'), findsOneWidget);
      expect(find.text('مبروك! استحققت الهدية الفورية'), findsOneWidget);
      expect(find.text('زمزمية مياه رياضية فاخرة'), findsOneWidget);
      expect(find.text('هدية فورية معتمدة ومضمونة'), findsOneWidget);

      // Verify customer-facing instructions
      expect(find.text('تم التحقق من الفاتورة بنجاح واستيفاء شروط العرض الترويجي.'), findsOneWidget);
      expect(find.text('يرجى استلام هديتك المعتمدة من ممثل الشركة في الفرع.'), findsOneWidget);

      // Ensure internal backend text is NOT present
      expect(find.textContaining('سيتم خصم الهدية'), findsNothing);
      expect(find.textContaining('الكمية المستحقة: 1'), findsNothing);

      // Verify claim action button
      expect(find.text('تسليم الهدية للعميل'), findsOneWidget);
    });

    testWidgets('Renders DirectGiftClaimScreen with multiplied quantity when customer earned multiples (e.g. 3 units)', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DirectGiftClaimScreen(
              transactionId: 'test_tx_multi',
              eventId: 'event_789',
              prizeName: 'كوب حراري ستانلس ستيل',
              quantity: 3,
              isDemo: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('كوب حراري ستانلس ستيل'), findsOneWidget);
      expect(find.textContaining('عدد الهدايا المستحقة: 3 قطع'), findsOneWidget);
      expect(find.byIcon(Icons.stars_rounded), findsOneWidget);
    });

    test('AppStrings contains valid Direct Gift & Promoter Alert keys for all supported languages', () {
      final stringsAr = AppStrings('ar');
      final stringsEn = AppStrings('en');
      final stringsHi = AppStrings('hi');

      // Arabic
      expect(stringsAr.gameDirectGiftTitle, contains('الهدية الفورية المباشرة'));
      expect(stringsAr.claimDirectGift, contains('تسليم الهدية للعميل'));
      expect(stringsAr.directGiftCustomerCongrats, contains('مبروك'));
      expect(stringsAr.promoterLowStockWarningSingle, contains('تنبيه للبروموتر'));
      expect(stringsAr.promoterLowStockWarningDouble, contains('تنبيه للبروموتر'));

      // English
      expect(stringsEn.gameDirectGiftTitle, contains('Direct Instant Gift'));
      expect(stringsEn.claimDirectGift, contains('Handover Gift to Customer'));
      expect(stringsEn.directGiftCustomerCongrats, contains('Congratulations'));
      expect(stringsEn.promoterLowStockWarningSingle, contains('Promoter Alert'));

      // Hindi
      expect(stringsHi.gameDirectGiftTitle, contains('प्रत्यक्ष'));
      expect(stringsHi.claimDirectGift, contains('उपहार'));
      expect(stringsHi.directGiftCustomerCongrats, contains('बधाई'));
      expect(stringsHi.promoterLowStockWarningSingle, contains('प्रमोटर चेतावनी'));
    });
  });
}
