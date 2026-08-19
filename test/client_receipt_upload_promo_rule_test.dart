import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/games/presentation/direct_gift_claim_screen.dart';
import 'package:al_mraay/features/games/presentation/winner_celebration_dialog.dart';

void main() {
  group('Promotional Rules & Voucher Naming Resolution Tests', () {
    testWidgets('DirectGiftClaimScreen displays exact voucher name without generic placeholder',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DirectGiftClaimScreen(
              transactionId: 'tx_123',
              eventId: '',
              prizeName: 'فوتشر 50 جنيه',
              quantity: 1,
              unitValue: 50.0,
              isVoucher: true,
              isDemo: true,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('فوتشر 50 جنيه'), findsOneWidget);
      expect(find.text('هدية ترويجية مميزة'), findsNothing);
      expect(find.text('هدية فورية مميزة'), findsNothing);
      expect(find.text('بقيمة 50 ج.م'), findsOneWidget);
    });

    testWidgets('DirectGiftClaimScreen self-heals from linked gifts when prizeName is placeholder',
        (WidgetTester tester) async {
      final List<LinkedGiftAllocation> linkedGifts = [
        LinkedGiftAllocation(
          giftId: 'g_50',
          giftName: 'فواتشر 50 جنيه',
          quantity: 1,
          unitValue: 50.0,
          giftType: 'voucher',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DirectGiftClaimScreen(
              transactionId: 'tx_123',
              eventId: '',
              prizeName: 'هدية ترويجية مميزة',
              quantity: 1,
              unitValue: 50.0,
              isVoucher: true,
              linkedGifts: linkedGifts,
              isDemo: true,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('فواتشر 50 جنيه'), findsWidgets);
      expect(find.text('هدية ترويجية مميزة'), findsNothing);
    });

    testWidgets('WinnerCelebrationDialog renders exact prize name and denomination',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showWinnerCelebrationDialog(
                      context: context,
                      prizeName: 'فوتشر 50 جنيه',
                      unitValue: 50.0,
                      isVoucher: true,
                      remainingChances: 0,
                      onNextCustomer: () {},
                    );
                  },
                  child: const Text('Show Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('فوتشر 50 جنيه'), findsOneWidget);
      expect(find.text('بقيمة 50 ج.م'), findsOneWidget);
      expect(find.text('هدية ترويجية مميزة'), findsNothing);
    });
  });
}
