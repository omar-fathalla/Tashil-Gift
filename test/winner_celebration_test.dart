import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/features/games/presentation/winner_celebration_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WinnerCelebrationDialog Tests', () {
    testWidgets('Renders celebratory winner dialog with prize name and action button', (WidgetTester tester) async {
      bool nextCustomerTapped = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: WinnerCelebrationDialog(
                prizeName: 'شاشة سامسونج 55 بوصة',
                onNextCustomer: () {
                  nextCustomerTapped = true;
                },
              ),
            ),
          ),
        ),
      );

      // Verify header / congratulations text
      expect(find.text('تهانينا! ألف مبروك'), findsOneWidget);
      expect(find.text('لقد فزت بـ:'), findsOneWidget);
      expect(find.text('شاشة سامسونج 55 بوصة'), findsOneWidget);

      // Verify action button
      expect(find.text('تم (العميل التالي)'), findsOneWidget);

      // Tap action button
      await tester.tap(find.text('تم (العميل التالي)'));
      await tester.pump();

      expect(nextCustomerTapped, isTrue);
    });

    testWidgets('Renders remaining chances badge and next chance button when remainingChances > 0', (WidgetTester tester) async {
      bool nextChanceTapped = false;
      bool nextCustomerTapped = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: WinnerCelebrationDialog(
                prizeName: 'ماكينة قهوة تورنيدو',
                remainingChances: 2,
                onNextChance: () {
                  nextChanceTapped = true;
                },
                onNextCustomer: () {
                  nextCustomerTapped = true;
                },
              ),
            ),
          ),
        ),
      );

      // Verify remaining chances badge
      expect(find.text('✨ متبقي لديك 2 فرص سحب إضافية!'), findsOneWidget);

      // Verify next chance button
      expect(find.text('سحب الفرصة التالية (متبقي 2)'), findsOneWidget);
      expect(find.text('إنهاء واستلام الجوائز'), findsOneWidget);

      // Tap next chance button
      await tester.tap(find.text('سحب الفرصة التالية (متبقي 2)'));
      await tester.pump();

      expect(nextChanceTapped, isTrue);
      expect(nextCustomerTapped, isFalse);
    });
  });
}
