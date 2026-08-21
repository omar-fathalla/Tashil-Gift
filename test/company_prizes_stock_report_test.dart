import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/core/widgets/m3_button_groups.dart';
import 'package:al_mraay/features/company_portal/presentation/company_prizes_stock_report_screen.dart';

void main() {
  group('Company Prizes & Real-Time Stock Balance System Tests', () {
    test('Section 14.1 Trilingual Localization Strings for Prizes Stock Balance are complete', () {
      final stringsAr = AppStrings.fromLocale('ar');
      expect(stringsAr.prizesStockTitle, contains('رصيد وجرد الهدايا'));
      expect(stringsAr.prizesStockSubtitle, contains('مراقبة لحظية'));
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
      expect(stringsEn.prizesStockTitle, contains('Prizes & Stock Balance'));
      expect(stringsEn.prizesStockSubtitle, contains('real-time'));
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

      final stringsEn = AppStrings.fromLocale('en');
      expect(stringsEn.voucherIntelligenceTitle, contains('Voucher Intelligence'));
      expect(stringsEn.totalVouchersAllocated, contains('Total Vouchers Allocated'));
      expect(stringsEn.totalVouchersBudget, contains('Total Financial Budget'));
      expect(stringsEn.claimedVouchersValue, contains('Disbursed Voucher Value'));
      expect(stringsEn.remainingVouchersValue, contains('Remaining Balance Value'));
      expect(stringsEn.viewBranchVoucherMatrix, contains('Branch Voucher Matrix'));

      final stringsHi = AppStrings.fromLocale('hi');
      expect(stringsHi.voucherIntelligenceTitle, isNotEmpty);
      expect(stringsHi.totalVouchersAllocated, isNotEmpty);
      expect(stringsHi.totalVouchersBudget, isNotEmpty);
      expect(stringsHi.claimedVouchersValue, isNotEmpty);
      expect(stringsHi.remainingVouchersValue, isNotEmpty);
    });

    test('VoucherDenominationStats and AggregatedVoucherMetrics calculate correctly', () {
      final denom25 = VoucherDenominationStats(
        denomination: 25.0,
        label: '25 ج.م',
        allocatedCount: 100,
        claimedCount: 40,
        remainingCount: 60,
      );

      final denom50 = VoucherDenominationStats(
        denomination: 50.0,
        label: '50 ج.م',
        allocatedCount: 50,
        claimedCount: 20,
        remainingCount: 30,
      );

      expect(denom25.totalBudget, equals(2500.0));
      expect(denom25.claimedValue, equals(1000.0));
      expect(denom25.remainingValue, equals(1500.0));

      final metrics = AggregatedVoucherMetrics(
        totalUnitsAllocated: 150,
        totalUnitsClaimed: 60,
        totalUnitsRemaining: 90,
        totalBudgetEgp: 5000.0,
        totalClaimedEgp: 2000.0,
        totalRemainingEgp: 3000.0,
        denominations: [denom25, denom50],
        branchDenominationsMap: {
          'فرع سموحة': {25.0: denom25, 50.0: denom50},
        },
        branchTotalVoucherUnits: {'فرع سموحة': 150},
        branchTotalVoucherBudget: {'فرع سموحة': 5000.0},
        branchClaimedVoucherUnits: {'فرع سموحة': 60},
        branchRemainingVoucherUnits: {'فرع سموحة': 90},
      );

      expect(metrics.totalUnitsAllocated, equals(150));
      expect(metrics.totalUnitsClaimed, equals(60));
      expect(metrics.totalUnitsRemaining, equals(90));
      expect(metrics.totalBudgetEgp, equals(5000.0));
      expect(metrics.totalClaimedEgp, equals(2000.0));
      expect(metrics.totalRemainingEgp, equals(3000.0));
      expect(metrics.depletionRate, closeTo(0.40, 0.001));
      expect(metrics.denominations.length, equals(2));
      expect(metrics.branchTotalVoucherBudget['فرع سموحة'], equals(5000.0));
    });

    testWidgets('CompanyPrizesStockReportScreen renders 4 Voucher KPI cards and matrix action', (tester) async {
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
  });
}

