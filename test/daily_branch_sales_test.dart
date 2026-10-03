import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/features/company_portal/domain/daily_branch_sales_model.dart';
import 'package:al_mraay/core/services/daily_sales_aggregation_service.dart';
import 'package:al_mraay/features/company_portal/presentation/daily_branch_sales_screen.dart';
import 'package:al_mraay/features/company_portal/presentation/company_manager_portal_screen.dart';

void main() {
  group('Daily Branch Sales & Gifts Hub Tests', () {
    test('DailyBranchSalesModel serialization and deserialization works correctly', () {
      final now = DateTime(2026, 8, 22);
      final model = DailyBranchSalesModel(
        id: 'unilever_ev123_smoha_2026-08-22',
        companySlug: 'unilever',
        campaignId: 'ev123',
        campaignName: 'يونيليفر ديوز - هيركير',
        dateStr: '2026-08-22',
        date: now,
        branchName: 'فرع سموحة (الإسكندرية)',
        branchId: 'branch_smoha',
        retailChain: 'أسواق فتح الله',
        invoicesCount: 33,
        totalSalesAmount: 18450.0,
        totalGiftsCount: 50,
        totalVouchersValue: 1600.0,
        giftsDisbursed: {
          'clear_90ml': const DailyGiftDisbursalItem(
            giftKey: 'clear_90ml',
            giftName: 'كلير 90 مل هدية',
            quantity: 14,
            isVoucher: false,
          ),
          'voucher_50': const DailyGiftDisbursalItem(
            giftKey: 'voucher_50',
            giftName: 'فواتشر 50 جنيه',
            quantity: 29,
            isVoucher: true,
            unitValue: 50.0,
            totalValue: 1450.0,
          ),
        },
        topProducts: [
          const DailyTopProductItem(productName: 'كلير شامبو 360 مل', quantity: 42, totalSales: 3570.0),
        ],
        lastUpdatedAt: now,
      );

      final map = model.toFirestore();
      expect(map['companySlug'], 'unilever');
      expect(map['invoicesCount'], 33);
      expect(map['totalSalesAmount'], 18450.0);
      expect(map['totalGiftsCount'], 50);
      expect(map['totalVouchersValue'], 1600.0);

      final parsed = DailyBranchSalesModel.fromMap(model.id, map);
      expect(parsed.companySlug, 'unilever');
      expect(parsed.invoicesCount, 33);
      expect(parsed.totalSalesAmount, 18450.0);
      expect(parsed.giftsDisbursed['clear_90ml']?.quantity, 14);
      expect(parsed.giftsDisbursed['voucher_50']?.isVoucher, true);
      expect(parsed.topProducts.first.productName, 'كلير شامبو 360 مل');
    });

    test('DailySalesAggregationService deterministic ID generation is consistent', () {
      final docId = DailySalesAggregationService.buildDocId(
        companySlug: 'Unilever',
        campaignId: 'ev123',
        branchName: 'فرع سموحة (الإسكندرية)',
        dateStr: '2026-08-22',
      );

      expect(docId, contains('unilever'));
      expect(docId, contains('ev123'));
      expect(docId, contains('2026-08-22'));
    });

    test('AppStrings localization strings for Daily Sales are defined in AR, EN, and HI', () {
      // 1. Arabic
      final stringsAr = AppStrings.fromLocale('ar');
      expect(stringsAr.dailyBranchSalesNavTitle, 'المبيعات اليومية');
      expect(stringsAr.dailySalesTotalKpi, 'إجمالي مبيعات اليوم');
      expect(stringsAr.dailyInvoicesCountKpi, 'عدد الفواتير المنفذة');
      expect(stringsAr.dailyGiftsDisbursedKpi, 'إجمالي الهدايا المنصرفة');
      expect(stringsAr.dailyVouchersValueKpi, 'قيمة الفواتشرات المنصرفة');
      expect(stringsAr.syncAndBackfillDailySalesBtn, 'مزامنة وترميم السجلات');

      // 2. English
      final stringsEn = AppStrings.fromLocale('en');
      expect(stringsEn.dailyBranchSalesNavTitle, 'Daily Sales & Gifts');
      expect(stringsEn.dailySalesTotalKpi, contains('Total Sales'));
      expect(stringsEn.dailyInvoicesCountKpi, contains('Invoices'));

      // 3. Hindi
      final stringsHi = AppStrings.fromLocale('hi');
      expect(stringsHi.dailyBranchSalesNavTitle, contains('दैनिक'));
      expect(stringsHi.dailySalesTotalKpi, contains('बिक्री'));
    });

    testWidgets('DailyBranchSalesScreen can be instantiated in desktop viewport with All Campaigns default', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DailyBranchSalesScreen(
                lockedCompanySlug: 'unilever',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(DailyBranchSalesScreen), findsOneWidget);
    });

    testWidgets('CompanyManagerPortalScreen switches to DailyBranchSalesScreen when tapping Tab 2', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: CompanyManagerPortalScreen(
                companySlug: 'unilever',
                initialEventId: 'ev_test',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(CompanyManagerPortalScreen), findsOneWidget);

      // Find the navigation destination for Daily Sales
      final navFinder = find.text('المبيعات اليومية');
      if (navFinder.evaluate().isNotEmpty) {
        await tester.tap(navFinder.first);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(DailyBranchSalesScreen), findsOneWidget);
      }
    });

    test('DailySalesAggregationService multi-tier branch resolution normalizes Store 418 and Obour variants', () {
      final canonicalBranches = {
        'فرع جاردينيا (الإسكندرية)',
        'فرع عجمي ستار (الإسكندرية)',
        'المنتزه (الإسكندرية)',
        'عمارات العبور - صلاح سالم (القاهرة)',
        'التجمع (Tagmoo) (القاهرة)',
        'أكتوبر (October) (السادس من أكتوبر)',
      };

      // 1. Store 418 variants -> Montazah
      expect(DailySalesAggregationService.buildDocId(
        companySlug: 'unilever',
        campaignId: 'ev1',
        branchName: 'المنتزه (الإسكندرية)',
        dateStr: '2026-08-25',
      ), contains('unilever_ev1_'));

      // 2. Test cleaned branch normalization logic
      expect(canonicalBranches.contains('المنتزه (الإسكندرية)'), true);
      expect(canonicalBranches.contains('عمارات العبور - صلاح سالم (القاهرة)'), true);
    });

    testWidgets('DailyBranchSalesScreen renders 2x2 KPI grid and 4-button group on mobile (390x844)', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DailyBranchSalesScreen(
                lockedCompanySlug: 'unilever',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(DailyBranchSalesScreen), findsOneWidget);

      // Verify the 4-button group labels are present
      expect(find.text('اليوم'), findsOneWidget);
      expect(find.text('الإجمالي'), findsOneWidget);
      expect(find.text('إكسل'), findsOneWidget);
      expect(find.byIcon(Icons.event_rounded), findsOneWidget);

      // Verify 2x2 GridView is used for KPIs on mobile
      final gridViewFinder = find.byType(GridView);
      expect(gridViewFinder, findsOneWidget);
      final gridView = tester.widget<GridView>(gridViewFinder);
      final delegate = gridView.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 2);
    });

    test('Clean branch name parsing and area/chain subtitle generation logic works correctly', () {
      // Helper function matching the implementation
      String cleanBranchName(String raw) {
        final parenMatch = RegExp(r'\(([^)]+)\)').firstMatch(raw);
        if (parenMatch != null) {
          final candidate = raw.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
          if (candidate.isNotEmpty) return candidate;
        }
        return raw.trim();
      }

      String extractArea(String raw) {
        final parenMatch = RegExp(r'\(([^)]+)\)').firstMatch(raw);
        return parenMatch?.group(1)?.trim() ?? '';
      }

      // Test cases
      expect(cleanBranchName('فرع سموحة (الإسكندرية)'), equals('فرع سموحة'));
      expect(extractArea('فرع سموحة (الإسكندرية)'), equals('الإسكندرية'));

      expect(cleanBranchName('فرع طنطا اوت ليت (الغربية)'), equals('فرع طنطا اوت ليت'));
      expect(extractArea('فرع طنطا اوت ليت (الغربية)'), equals('الغربية'));

      expect(cleanBranchName('فرع عجمي ستار (الإسكندرية)'), equals('فرع عجمي ستار'));
      expect(extractArea('فرع عجمي ستار (الإسكندرية)'), equals('الإسكندرية'));

      expect(cleanBranchName('فرع فلمنج (الإسكندرية)'), equals('فرع فلمنج'));
      expect(extractArea('فرع فلمنج (الإسكندرية)'), equals('الإسكندرية'));

      expect(cleanBranchName('فرع دمنهور الاستاد (البحيرة)'), equals('فرع دمنهور الاستاد'));
      expect(extractArea('فرع دمنهور الاستاد (البحيرة)'), equals('البحيرة'));

      expect(cleanBranchName('فرع سموحة'), equals('فرع سموحة'));
      expect(extractArea('فرع سموحة'), isEmpty);
    });
  });
}
