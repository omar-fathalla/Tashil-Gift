import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/core/utils/arabic_numbers_utils.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/games/presentation/direct_gift_claim_screen.dart';

void main() {
  group('Voucher Serial Numbers Tracking & Formatting Tests', () {
    test('ArabicNumbersUtils normalizes voucher serials with Eastern digits & slash', () {
      const easternSerial = '٢٧٨٩٢٤١/١';
      final normalized = easternSerial.toEnglishDigits(convertDecimal: false);
      expect(normalized, equals('2789241/1'));

      const mixedSerial = '١٠٠٢٣٤-٥';
      final normMixed = mixedSerial.toEnglishDigits(convertDecimal: false);
      expect(normMixed, equals('100234-5'));
    });

    test('AppStrings contains trilingual localization getters for Voucher Serials', () {
      final strings = AppStrings('ar');

      expect(strings.voucherSerialsSectionTitle.isNotEmpty, isTrue);
      expect(strings.voucherSerialsSectionSubtitle.isNotEmpty, isTrue);
      expect(strings.voucherSerialInputLabel.isNotEmpty, isTrue);
      expect(strings.voucherSerialInputHint.isNotEmpty, isTrue);
      expect(strings.voucherSerialRequiredError.isNotEmpty, isTrue);
      expect(strings.voucherSerialDuplicateInTxError.isNotEmpty, isTrue);
      expect(strings.voucherSerialAlreadyClaimedError.isNotEmpty, isTrue);
      expect(strings.voucherSerialsManagementTitle.isNotEmpty, isTrue);
      expect(strings.resetVoucherSerialsBtn.isNotEmpty, isTrue);
      expect(strings.resetVoucherSerialsConfirmTitle.isNotEmpty, isTrue);
      expect(strings.resetVoucherSerialsConfirmMsg.isNotEmpty, isTrue);
      expect(strings.voucherSerialsResetSuccess.isNotEmpty, isTrue);
      expect(strings.totalClaimedVoucherCards.isNotEmpty, isTrue);
    });

    test('Voucher slots count calculates accurately for multi-offer bundles', () {
      final linkedGifts = [
        LinkedGiftAllocation(
          giftId: 'voucher_50',
          giftName: 'فواتشر 50 جنيه',
          quantity: 2,
          unitValue: 50.0,
          giftType: 'voucher',
        ),
        LinkedGiftAllocation(
          giftId: 'voucher_25',
          giftName: 'فواتشر 25 جنيه',
          quantity: 1,
          unitValue: 25.0,
          giftType: 'voucher',
        ),
        LinkedGiftAllocation(
          giftId: 'clear_90',
          giftName: 'كلير 90 مل هديه',
          quantity: 2,
          unitValue: 0.0,
          giftType: 'product',
        ),
      ];

      // Total vouchers count must be 2 + 1 = 3 (physical shampoo clear_90 is excluded)
      final totalVoucherCards = linkedGifts
          .where((g) => g.isVoucher)
          .fold<int>(0, (sum, g) => sum + g.quantity.toInt());

      expect(totalVoucherCards, equals(3));
    });
  });

  group('DirectGiftClaimScreen Voucher Serial Input Card Widget Tests', () {
    testWidgets('Renders Voucher Serial Input Card when prize is a voucher', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final linkedGifts = [
        LinkedGiftAllocation(
          giftId: 'v50',
          giftName: 'فواتشر 50 جنيه',
          quantity: 2,
          unitValue: 50.0,
          giftType: 'voucher',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DirectGiftClaimScreen(
              transactionId: 'tx_test_123',
              eventId: 'event_test_123',
              prizeName: 'فواتشر 50 جنيه',
              quantity: 2,
              unitValue: 50.0,
              isVoucher: true,
              linkedGifts: linkedGifts,
              isDemo: true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify the voucher serials title is displayed
      expect(find.textContaining('أرقام بطاقات الفواتشرات'), findsOneWidget);
      // Verify 2 slots (#1 and #2) are generated
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
    });

    testWidgets('Does not render Voucher Serial Card when prize is purely physical without vouchers', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final linkedGifts = [
        LinkedGiftAllocation(
          giftId: 'clear90',
          giftName: 'كلير 90 مل هديه',
          quantity: 2,
          unitValue: 0.0,
          giftType: 'product',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DirectGiftClaimScreen(
              transactionId: 'tx_test_123',
              eventId: 'event_test_123',
              prizeName: 'كلير 90 مل هديه',
              quantity: 2,
              isVoucher: false,
              linkedGifts: linkedGifts,
              isDemo: true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Voucher section must NOT appear for purely physical gifts
      expect(find.textContaining('أرقام بطاقات الفواتشرات'), findsNothing);
    });
  });
}
