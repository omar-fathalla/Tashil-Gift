import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/features/games/presentation/winner_celebration_dialog.dart';

void main() {
  group('AllocatedPrize Self-Healing and Voucher Value Tests', () {
    test('AllocatedPrize.fromMap self-heals raw Firestore document IDs for vouchers', () {
      final rawData = {
        'giftId': '57chsA4F1uCZHvK7VRQ7',
        'name': '57chsA4F1uCZHvK7VRQ7',
        'giftType': 'voucher',
        'unitValue': 50.0,
        'allocatedQuantity': 20,
        'remainingQuantity': 15,
      };

      final prize = AllocatedPrize.fromMap(rawData);
      expect(prize.isVoucher, isTrue);
      expect(prize.unitValue, 50.0);
      expect(prize.name, 'فواتشر 50 جنيه');
      expect(prize.name, isNot(contains('57chsA4F1uCZHvK7VRQ7')));
    });

    test('AllocatedPrize.fromMap self-heals raw Firestore document IDs for physical products', () {
      final rawData = {
        'giftId': '89abcD4F1uCZHvK7VRQ9',
        'name': '89abcD4F1uCZHvK7VRQ9',
        'giftType': 'product',
        'unitValue': 0.0,
        'allocatedQuantity': 10,
        'remainingQuantity': 10,
      };

      final prize = AllocatedPrize.fromMap(rawData);
      expect(prize.isVoucher, isFalse);
      expect(prize.name, 'هدية ترويجية مميزة');
    });

    test('AllocatedPrize.fromMap preserves user-defined friendly names', () {
      final rawData = {
        'giftId': 'g123',
        'name': 'فواتشر 100 جنيه مميز',
        'giftType': 'voucher',
        'unitValue': 100.0,
        'allocatedQuantity': 5,
        'remainingQuantity': 5,
      };

      final prize = AllocatedPrize.fromMap(rawData);
      expect(prize.name, 'فواتشر 100 جنيه مميز');
      expect(prize.unitValue, 100.0);
    });

    test('EventModel.availablePrizeNames includes voucher monetary denomination', () {
      final event = EventModel(
        id: 'event-test-1',
        eventName: 'حملة يونيليفر الصيفية',
        targetCompany: 'يونيليفر',
        companySlug: 'unilever',
        minimumSpend: 100.0,
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 31),
        gameType: 'wheel',
        allocatedPrizes: [
          AllocatedPrize(
            giftId: 'v50',
            name: 'فواتشر',
            allocatedQuantity: 10,
            remainingQuantity: 10,
            giftType: 'voucher',
            unitValue: 50.0,
          ),
          AllocatedPrize(
            giftId: 'p1',
            name: 'شامبو كلير 250 مل',
            allocatedQuantity: 20,
            remainingQuantity: 18,
            giftType: 'product',
            unitValue: 0.0,
          ),
        ],
      );

      final prizeNames = event.availablePrizeNames;
      expect(prizeNames.length, 2);
      expect(prizeNames.first, contains('50 ج.م'));
      expect(prizeNames[1], 'شامبو كلير 250 مل');
    });
  });

  group('Voucher Localization Strings Tests', () {
    test('AppStrings provides trilingual voucher values and labels', () {
      final arStrings = AppStrings('ar');
      expect(arStrings.voucherValueText(50), 'بقيمة 50 ج.م');
      expect(arStrings.certifiedVoucher, contains('قسيمة'));

      final enStrings = AppStrings('en');
      expect(enStrings.voucherValueText(50), 'Value: 50 EGP');
      expect(enStrings.certifiedVoucher, contains('Certified'));

      final hiStrings = AppStrings('hi');
      expect(hiStrings.voucherValueText(50), 'मूल्य: 50 EGP');
    });
  });

  group('WinnerCelebrationDialog Voucher Presentation Widget Tests', () {
    testWidgets('Renders Voucher Value Badge and Certified Ticket details for voucher prize', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: WinnerCelebrationDialog(
                prizeName: 'فواتشر 50 جنيه',
                unitValue: 50.0,
                isVoucher: true,
                onNextCustomer: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('بقيمة 50 ج.م'), findsOneWidget);
      expect(find.text('فواتشر 50 جنيه'), findsOneWidget);
      expect(find.text('كارت فواتشر مشتريات معتمد'), findsOneWidget);
      expect(find.byIcon(Icons.confirmation_number_rounded), findsOneWidget);
      expect(find.byIcon(Icons.payments_rounded), findsOneWidget);
    });

    testWidgets('Renders Physical Gift Box and certified badge for Clear 90ml without false voucher badge', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: WinnerCelebrationDialog(
                prizeName: 'كلير 90 مل هديه',
                unitValue: 0.0,
                isVoucher: false,
                onNextCustomer: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('كلير 90 مل هديه'), findsOneWidget);
      expect(find.text('هدية عينية فورية معتمدة'), findsOneWidget);
      expect(find.text('يرجى استلام هديتك من ممثل الشركة في الفرع'), findsOneWidget);
      expect(find.byIcon(Icons.card_giftcard_rounded), findsOneWidget);

      // Must NEVER display voucher keywords or cash amounts
      expect(find.text('كارت فواتشر مشتريات معتمد'), findsNothing);
      expect(find.text('بقيمة 90 ج.م'), findsNothing);
      expect(find.text('بقيمة 250 ج.م'), findsNothing);
      expect(find.text('صالحة للاستخدام الفوري لدى الكاشير'), findsNothing);
      expect(find.byIcon(Icons.confirmation_number_rounded), findsNothing);
      expect(find.byIcon(Icons.payments_rounded), findsNothing);
    });

    testWidgets('Renders Physical Gift Box for Tresemme 250ml without false 250 EGP voucher value', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: WinnerCelebrationDialog(
                prizeName: 'تريزيمي 250 مل هديه',
                unitValue: 0.0,
                isVoucher: false,
                onNextCustomer: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('تريزيمي 250 مل هديه'), findsOneWidget);
      expect(find.text('هدية عينية فورية معتمدة'), findsOneWidget);
      expect(find.text('بقيمة 250 ج.م'), findsNothing);
      expect(find.text('كارت فواتشر مشتريات معتمد'), findsNothing);
      expect(find.byIcon(Icons.card_giftcard_rounded), findsOneWidget);
    });
  });
}
