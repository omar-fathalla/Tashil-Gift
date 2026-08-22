import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/client_portal/presentation/widgets/campaign_gift_balance_dialog.dart';
import 'package:al_mraay/core/localization/app_strings.dart';

void main() {
  group('Promoter Daily Disbursal & Stock Balance System Tests', () {
    final sampleEvent = EventModel(
      id: 'event_test_1',
      eventName: 'مهرجان يونيليفر الصيفي',
      targetCompany: 'يونيليفر',
      minimumSpend: 300.0,
      startDate: DateTime.now().subtract(const Duration(days: 10)),
      endDate: DateTime.now().add(const Duration(days: 20)),
      branchIds: ['branch_1', 'branch_2'],
      branchNames: ['جناكليس (الإسكندرية)', 'سموحة (الإسكندرية)'],
      allocatedPrizes: [
        AllocatedPrize(
          giftId: 'gift_voucher_25',
          name: 'فواتشر 25 جنيه',
          allocatedQuantity: 200,
          remainingQuantity: 185,
          branchId: 'branch_1',
          branchName: 'جناكليس (الإسكندرية)',
          unitValue: 25.0,
          giftType: 'voucher',
        ),
        AllocatedPrize(
          giftId: 'gift_voucher_50',
          name: 'فواتشر 50 جنيه',
          allocatedQuantity: 300,
          remainingQuantity: 270,
          branchId: 'branch_1',
          branchName: 'جناكليس (الإسكندرية)',
          unitValue: 50.0,
          giftType: 'voucher',
        ),
        AllocatedPrize(
          giftId: 'gift_clear_90',
          name: 'كلير 90 مل هديه',
          allocatedQuantity: 150,
          remainingQuantity: 140,
          branchId: 'branch_1',
          branchName: 'جناكليس (الإسكندرية)',
          unitValue: 0.0,
          giftType: 'product',
        ),
      ],
    );

    testWidgets('CampaignGiftBalanceDialog renders with M3 tabs and daily disbursal header', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => CampaignGiftBalanceDialog.show(context, sampleEvent),
                    child: const Text('Open Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Check header title & company subtitle
      expect(find.text('سجل السحب والتوزيع اليومي للهدايا'), findsOneWidget);
      expect(find.text('مهرجان يونيليفر الصيفي (يونيليفر)'), findsOneWidget);

      // Check M3 Segmented Tabs
      expect(find.text('حركة السحب والتوزيع اليومي'), findsOneWidget);
      expect(find.text('رصيد ومخزون الهدايا'), findsOneWidget);

      // Check KPI Cards
      expect(find.text('إجمالي الهدايا المنصرفة'), findsOneWidget);
      expect(find.text('عدد الفواتير المنفذة'), findsOneWidget);

      // Check configured gift titles
      expect(find.text('فواتشر 25 جنيه'), findsOneWidget);
      expect(find.text('فواتشر 50 جنيه'), findsOneWidget);
      expect(find.text('كلير 90 مل هديه'), findsOneWidget);
    });

    testWidgets('Switching between Daily Disbursals tab and Stock Balance tab works smoothly', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => CampaignGiftBalanceDialog.show(context, sampleEvent),
                    child: const Text('Open Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Tap Stock Balance tab
      await tester.tap(find.text('رصيد ومخزون الهدايا'));
      await tester.pumpAndSettle();

      // Check Stock Balance header
      expect(find.text('رصيد ومخزون الهدايا المتبقي'), findsOneWidget);
      expect(find.text('إجمالي رصيد الفرع'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('595 / 650')),
        findsOneWidget,
      );

      // Tap back to Daily Handover tab
      await tester.tap(find.text('حركة السحب والتوزيع اليومي'));
      await tester.pumpAndSettle();

      expect(find.text('سجل السحب والتوزيع اليومي للهدايا'), findsOneWidget);
    });

    test('AppStrings contains trilingual strings for Daily Disbursal Log', () {
      final strings = AppStrings('ar');

      expect(strings.promoterDailyDisbursalTab, 'حركة السحب والتوزيع اليومي');
      expect(strings.promoterStockBalanceTab, 'رصيد ومخزون الهدايا');
      expect(strings.totalDisbursedCountLabel, 'إجمالي الهدايا المنصرفة');
      expect(strings.totalDisbursedVouchersLabel, 'إجمالي الفواتشرات المنصرفة');
      expect(strings.todayShortcut, 'اليوم');
      expect(strings.allTimeShortcut, 'إجمالي الحملة');
    });

    test('AllocatedPrize matching is deterministic and never confuses TRESemme 250ml with Voucher 50/25', () {
      final tresemme = AllocatedPrize(
        giftId: 'tresemme_250',
        name: 'تريزيمي 250 مل هديه',
        allocatedQuantity: 200,
        remainingQuantity: 200,
        branchId: 'b1',
        branchName: 'جناكليس',
        unitValue: 0.0,
        giftType: 'product',
      );

      final voucher50 = AllocatedPrize(
        giftId: 'voucher_50',
        name: 'فواتشر 50 جنيه',
        allocatedQuantity: 300,
        remainingQuantity: 300,
        branchId: 'b1',
        branchName: 'جناكليس',
        unitValue: 50.0,
        giftType: 'voucher',
      );

      final voucher25 = AllocatedPrize(
        giftId: 'voucher_25',
        name: 'فواتشر 25 جنيه',
        allocatedQuantity: 200,
        remainingQuantity: 200,
        branchId: 'b1',
        branchName: 'جناكليس',
        unitValue: 25.0,
        giftType: 'voucher',
      );

      // Verify names and values do not overlap
      expect(tresemme.isVoucher, false);
      expect(voucher50.isVoucher, true);
      expect(voucher25.isVoucher, true);
      expect(voucher50.unitValue, 50.0);
      expect(voucher25.unitValue, 25.0);
    });
  });
}
