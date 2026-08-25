import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/core/widgets/m3_button_groups.dart';
import 'package:al_mraay/features/company_portal/presentation/company_prizes_stock_report_screen.dart';
import 'package:al_mraay/features/company_portal/presentation/company_vouchers_report_screen.dart';
import 'package:al_mraay/features/admin/domain/company_gift_model.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Company Prizes & Real-Time Stock Balance System Tests', () {
    test('Section 14.1 Trilingual Localization Strings for Prizes Stock Balance are complete', () {
      final stringsAr = AppStrings.fromLocale('ar');
      expect(stringsAr.prizesStockTitle, contains('الهدايا'));
      expect(stringsAr.prizesStockSubtitle, contains('الهدايا'));
      expect(stringsAr.totalAllocatedGifts, contains('الهدايا المخصصة'));
      expect(stringsAr.awardedGiftsCount, contains('الهدايا المصروفة'));
      expect(stringsAr.remainingStockBalance, contains('الرصيد المتبقي'));
      expect(stringsAr.coveredOutletsCount, contains('الفروع والمنافذ'));
      expect(stringsAr.depletionRateLabel, contains('نسبة السحب'));
      expect(stringsAr.itemizedGiftsTab, contains('جرد الأصناف'));
      expect(stringsAr.branchBreakdownTab, contains('الأرصدة حسب الفروع'));
      expect(stringsAr.campaignBreakdownTab, contains('الأرصدة حسب الفعاليات'));
      expect(stringsAr.filterAllStock, contains('كافة الحالات'));
      expect(stringsAr.filterAvailableStock, contains('متوفر'));
      expect(stringsAr.filterLowStock, contains('منخفض'));
      expect(stringsAr.filterOutOfStock, contains('نفد'));
      expect(stringsAr.exportStockReportCsv, contains('تصدير تقرير'));

      final stringsEn = AppStrings.fromLocale('en');
      expect(stringsEn.prizesStockTitle, contains('Gifts'));
      expect(stringsEn.prizesStockSubtitle, contains('branch gift stock'));
      expect(stringsEn.totalAllocatedGifts, contains('Total Allocated'));
      expect(stringsEn.awardedGiftsCount, contains('Awarded'));
      expect(stringsEn.remainingStockBalance, contains('Remaining Stock'));
      expect(stringsEn.coveredOutletsCount, contains('Covered Outlets'));
      expect(stringsEn.depletionRateLabel, contains('Depletion Rate'));
      expect(stringsEn.itemizedGiftsTab, contains('Itemized'));
      expect(stringsEn.branchBreakdownTab, contains('Branch'));
      expect(stringsEn.campaignBreakdownTab, contains('Campaign'));
      expect(stringsEn.exportStockReportCsv, contains('Export Stock Report'));

      final stringsHi = AppStrings.fromLocale('hi');
      expect(stringsHi.prizesStockTitle, isNotEmpty);
      expect(stringsHi.prizesStockSubtitle, isNotEmpty);
      expect(stringsHi.totalAllocatedGifts, isNotEmpty);
      expect(stringsHi.awardedGiftsCount, isNotEmpty);
      expect(stringsHi.remainingStockBalance, isNotEmpty);
      expect(stringsHi.coveredOutletsCount, isNotEmpty);
    });

    test('AggregatedGiftStock computation and status properties work correctly', () {
      final stockHealthy = AggregatedGiftStock(
        giftId: 'gift_1',
        giftName: 'Smart Watch',
        sku: 'SW-101',
        totalAllocated: 100,
        totalRemaining: 80,
        totalClaimed: 20,
        branchRemainingMap: {'Branch 1': 40, 'Branch 2': 40},
        branchAllocatedMap: {'Branch 1': 50, 'Branch 2': 50},
        eventNames: ['Campaign 2026'],
      );

      expect(stockHealthy.depletionRate, closeTo(0.20, 0.001));
      expect(stockHealthy.isOutOfStock, isFalse);
      expect(stockHealthy.isLowStock, isFalse);

      final stockLow = AggregatedGiftStock(
        giftId: 'gift_2',
        giftName: 'Wireless Earbuds',
        sku: 'WE-202',
        totalAllocated: 100,
        totalRemaining: 15,
        totalClaimed: 85,
        branchRemainingMap: {'Branch 1': 15},
        branchAllocatedMap: {'Branch 1': 100},
        eventNames: ['Campaign 2026'],
      );

      expect(stockLow.depletionRate, closeTo(0.85, 0.001));
      expect(stockLow.isOutOfStock, isFalse);
      expect(stockLow.isLowStock, isTrue);

      final stockDepleted = AggregatedGiftStock(
        giftId: 'gift_3',
        giftName: 'Shopping Voucher',
        sku: 'SV-303',
        totalAllocated: 50,
        totalRemaining: 0,
        totalClaimed: 50,
        branchRemainingMap: {'Branch 1': 0},
        branchAllocatedMap: {'Branch 1': 50},
        eventNames: ['Campaign 2026'],
      );

      expect(stockDepleted.depletionRate, equals(1.0));
      expect(stockDepleted.isOutOfStock, isTrue);
      expect(stockDepleted.isLowStock, isFalse);
    });

    test('Physical gifts with volume/weight (e.g. 250 ml, 90 ml) are strictly NOT treated as vouchers', () {
      final tresemmeProduct = AggregatedGiftStock(
        giftId: 'tresemme_250',
        giftName: 'تريزيمي 250 مل هديه',
        totalAllocated: 2551,
        totalRemaining: 1940,
        totalClaimed: 611,
        branchRemainingMap: {},
        branchAllocatedMap: {},
        eventNames: ['فعالية يونيليفر'],
        giftType: 'product',
        unitValue: 0.0,
      );

      expect(tresemmeProduct.isVoucher, isFalse);
      expect(tresemmeProduct.totalMonetaryBudget, equals(0.0));
      expect(tresemmeProduct.claimedMonetaryValue, equals(0.0));
      expect(tresemmeProduct.remainingMonetaryValue, equals(0.0));

      final clearProduct = AggregatedGiftStock(
        giftId: 'clear_90',
        giftName: 'كلير 90 مل هديه',
        totalAllocated: 2001,
        totalRemaining: 1728,
        totalClaimed: 273,
        branchRemainingMap: {},
        branchAllocatedMap: {},
        eventNames: ['فعالية يونيليفر'],
        giftType: 'product',
        unitValue: 0.0,
      );

      expect(clearProduct.isVoucher, isFalse);
      expect(clearProduct.totalMonetaryBudget, equals(0.0));

      final realVoucher25 = AggregatedGiftStock(
        giftId: 'voucher_25',
        giftName: 'قسيمة مشتريات 25 ج.م',
        totalAllocated: 4393,
        totalRemaining: 3866,
        totalClaimed: 527,
        branchRemainingMap: {},
        branchAllocatedMap: {},
        eventNames: ['فعالية يونيليفر'],
        giftType: 'voucher',
        unitValue: 25.0,
      );

      expect(realVoucher25.isVoucher, isTrue);
      expect(realVoucher25.totalMonetaryBudget, equals(4393 * 25.0));
      expect(realVoucher25.claimedMonetaryValue, equals(527 * 25.0));
      expect(realVoucher25.remainingMonetaryValue, equals(3866 * 25.0));
    });

    testWidgets('CompanyPrizesStockReportScreen renders 4 KPI cards and 3-segment switcher', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: CompanyPrizesStockReportScreen(
                lockedCompanySlug: 'unilever',
                lockedCompanyName: 'يونيليفر مصر',
                isEmbedded: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify KPI Hero Cards icons
      expect(find.byIcon(Icons.inventory_2_rounded), findsWidgets);
      expect(find.byIcon(Icons.card_giftcard_rounded), findsWidgets);
      expect(find.byIcon(Icons.verified_rounded), findsWidgets);
      expect(find.byIcon(Icons.storefront_rounded), findsWidgets);

      // Verify M3ConnectedButtonGroup view mode switcher
      expect(find.byType(M3ConnectedButtonGroup<int>), findsWidgets);

      // Verify Search TextField and CSV Export button
      expect(find.byType(TextField), findsWidgets);
      expect(find.byIcon(Icons.file_download_rounded), findsWidgets);
    });

    test('Voucher Intelligence Trilingual Localization strings are complete', () {
      final stringsAr = AppStrings.fromLocale('ar');
      expect(stringsAr.voucherIntelligenceTitle, contains('قسائم المشتريات'));
      expect(stringsAr.totalVouchersAllocated, contains('قسائم المشتريات'));
      expect(stringsAr.totalVouchersBudget, contains('الميزانية'));
      expect(stringsAr.claimedVouchersValue, contains('المصروفة'));
      expect(stringsAr.remainingVouchersValue, contains('المتبقي'));
      expect(stringsAr.viewBranchVoucherMatrix, contains('الفروع'));
      expect(stringsAr.voucherMatrixDialogTitle, contains('توزيع'));
      expect(stringsAr.allVoucherDenominations, contains('كافة الفئات'));
      expect(stringsAr.denominationBreakdownSection, contains('بطاقات التحليل'));
      expect(stringsAr.denominationMasterStock, contains('المخزون'));

      final stringsEn = AppStrings.fromLocale('en');
      expect(stringsEn.voucherIntelligenceTitle, contains('Voucher Intelligence'));
      expect(stringsEn.totalVouchersAllocated, contains('Total Vouchers Allocated'));
      expect(stringsEn.totalVouchersBudget, contains('Total Financial Budget'));
      expect(stringsEn.claimedVouchersValue, contains('Disbursed Voucher Value'));
      expect(stringsEn.remainingVouchersValue, contains('Remaining Balance Value'));
      expect(stringsEn.viewBranchVoucherMatrix, contains('Branch Voucher Matrix'));
      expect(stringsEn.allVoucherDenominations, contains('All Denominations'));
      expect(stringsEn.denominationBreakdownSection, contains('Detailed Breakdown'));

      final stringsHi = AppStrings.fromLocale('hi');
      expect(stringsHi.voucherIntelligenceTitle, isNotEmpty);
      expect(stringsHi.totalVouchersAllocated, isNotEmpty);
      expect(stringsHi.totalVouchersBudget, isNotEmpty);
      expect(stringsHi.claimedVouchersValue, isNotEmpty);
      expect(stringsHi.remainingVouchersValue, isNotEmpty);
      expect(stringsHi.allVoucherDenominations, isNotEmpty);
    });

    test('VoucherDenominationStats and AggregatedVoucherMetrics calculate correctly with master stock and branch mappings', () {
      final denom25 = VoucherDenominationStats(
        denomination: 25.0,
        label: '25 ج.م',
        masterTotalCount: 5000,
        masterAvailableCount: 607,
        allocatedCount: 4393,
        claimedCount: 527,
        remainingCount: 3866,
        branchAllocatedMap: {'فرع سموحة': 500},
        branchClaimedMap: {'فرع سموحة': 50},
        branchRemainingMap: {'فرع سموحة': 450},
      );

      final denom50 = VoucherDenominationStats(
        denomination: 50.0,
        label: '50 ج.م',
        masterTotalCount: 2000,
        masterAvailableCount: 0,
        allocatedCount: 2000,
        claimedCount: 200,
        remainingCount: 1800,
        branchAllocatedMap: {'فرع سموحة': 300},
        branchClaimedMap: {'فرع سموحة': 30},
        branchRemainingMap: {'فرع سموحة': 270},
      );

      expect(denom25.totalBudget, equals(4393 * 25.0));
      expect(denom25.claimedValue, equals(527 * 25.0));
      expect(denom25.remainingValue, equals(3866 * 25.0));
      expect(denom25.masterTotalBudget, equals(5000 * 25.0));
      expect(denom25.branchAllocatedMap['فرع سموحة'], equals(500));

      expect(denom50.totalBudget, equals(2000 * 50.0));
      expect(denom50.claimedValue, equals(200 * 50.0));
      expect(denom50.remainingValue, equals(1800 * 50.0));
      expect(denom50.masterTotalBudget, equals(2000 * 50.0));

      final metrics = AggregatedVoucherMetrics(
        totalUnitsAllocated: 6393,
        totalUnitsClaimed: 727,
        totalUnitsRemaining: 5666,
        totalBudgetEgp: (4393 * 25.0) + (2000 * 50.0),
        totalClaimedEgp: (527 * 25.0) + (200 * 50.0),
        totalRemainingEgp: (3866 * 25.0) + (1800 * 50.0),
        denominations: [denom25, denom50],
        branchDenominationsMap: {
          'فرع سموحة': {25.0: denom25, 50.0: denom50},
        },
        branchTotalVoucherUnits: {'فرع سموحة': 800},
        branchTotalVoucherBudget: {'فرع سموحة': (500 * 25.0) + (300 * 50.0)},
        branchClaimedVoucherUnits: {'فرع سموحة': 80},
        branchRemainingVoucherUnits: {'فرع سموحة': 720},
      );

      expect(metrics.totalUnitsAllocated, equals(6393));
      expect(metrics.totalUnitsClaimed, equals(727));
      expect(metrics.totalUnitsRemaining, equals(5666));
      expect(metrics.totalBudgetEgp, equals(109825.0 + 100000.0));
      expect(metrics.denominations.length, equals(2));
      expect(metrics.denominations[0].denomination, equals(25.0));
      expect(metrics.denominations[1].denomination, equals(50.0));
      expect(metrics.branchTotalVoucherBudget['فرع سموحة'], equals(27500.0));
    });

    testWidgets('CompanyVouchersReportScreen renders 4 Voucher KPI cards and matrix action', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: CompanyVouchersReportScreen(
                lockedCompanySlug: 'unilever',
                lockedCompanyName: 'يونيليفر مصر',
                isEmbedded: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify Voucher Section Title and Icons
      expect(find.byIcon(Icons.confirmation_number_rounded), findsWidgets);
      expect(find.byIcon(Icons.account_balance_wallet_rounded), findsWidgets);
      expect(find.byIcon(Icons.shopping_bag_rounded), findsWidgets);
      expect(find.byIcon(Icons.savings_rounded), findsWidgets);
      expect(find.byIcon(Icons.table_chart_rounded), findsWidgets);
    });

    testWidgets('Switching view modes between SKU, Branch, and Campaign updates UI smoothly', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: CompanyPrizesStockReportScreen(
                lockedCompanySlug: 'unilever',
                lockedCompanyName: 'يونيليفر مصر',
                isEmbedded: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Switch to Branch Breakdown view (segment index 1 - storefront icon in switcher)
      final branchSegment = find.byIcon(Icons.storefront_rounded).first;
      await tester.tap(branchSegment);
      await tester.pump();

      expect(tester.takeException(), isNull);

      // Switch to Campaign Breakdown view (segment index 2 - campaign icon in switcher)
      final campaignSegment = find.byIcon(Icons.campaign_rounded).first;
      await tester.tap(campaignSegment);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    test('Strict Master Gift Matching cleanly isolates different voucher denominations and products', () {
      final masterGifts = [
        CompanyGiftModel(
          id: 'gift_voucher_25',
          companySlug: 'unilever',
          giftName: 'فواتشر 25 جنيه',
          giftType: 'voucher',
          unitValue: 25.0,
          totalQuantity: 5000,
          availableQuantity: 607,
          createdAt: DateTime.now(),
        ),
        CompanyGiftModel(
          id: 'gift_voucher_50',
          companySlug: 'unilever',
          giftName: 'فواتشر 50 جنيه',
          giftType: 'voucher',
          unitValue: 50.0,
          totalQuantity: 2000,
          availableQuantity: 0,
          createdAt: DateTime.now(),
        ),
        CompanyGiftModel(
          id: 'gift_tresemme_250',
          companySlug: 'unilever',
          giftName: 'تريزيمي 250 مل هديه',
          giftType: 'product',
          unitValue: 0.0,
          totalQuantity: 3000,
          availableQuantity: 449,
          createdAt: DateTime.now(),
        ),
        CompanyGiftModel(
          id: 'gift_clear_90',
          companySlug: 'unilever',
          giftName: 'كلير 90 مل هديه',
          giftType: 'product',
          unitValue: 0.0,
          totalQuantity: 1000,
          availableQuantity: 200,
          createdAt: DateTime.now(),
        ),
      ];

      final prizeVoucher50 = AllocatedPrize(
        giftId: '',
        name: 'فواتشر 50 جنيه',
        allocatedQuantity: 200,
        remainingQuantity: 181,
        giftType: 'voucher',
        unitValue: 50.0,
      );

      final prizeVoucher25 = AllocatedPrize(
        giftId: '',
        name: 'فواتشر 25 جنيه',
        allocatedQuantity: 200,
        remainingQuantity: 181,
        giftType: 'voucher',
        unitValue: 25.0,
      );

      final prizeTresemme = AllocatedPrize(
        giftId: '',
        name: 'تريزيمي 250 مل هديه',
        allocatedQuantity: 200,
        remainingQuantity: 181,
        giftType: 'product',
      );

      final match50 = CompanyPrizesStockReportScreen.findMatchingMasterGift(prizeVoucher50, masterGifts);
      final match25 = CompanyPrizesStockReportScreen.findMatchingMasterGift(prizeVoucher25, masterGifts);
      final matchTresemme = CompanyPrizesStockReportScreen.findMatchingMasterGift(prizeTresemme, masterGifts);

      expect(match50?.id, equals('gift_voucher_50'));
      expect(match50?.giftName, equals('فواتشر 50 جنيه'));
      expect(match25?.id, equals('gift_voucher_25'));
      expect(match25?.giftName, equals('فواتشر 25 جنيه'));
      expect(matchTresemme?.id, equals('gift_tresemme_250'));
      expect(matchTresemme?.giftName, equals('تريزيمي 250 مل هديه'));
    });
  });
}

