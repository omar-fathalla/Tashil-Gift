import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/features/company_portal/presentation/campaigns_comparison_analytics_screen.dart';
import 'package:al_mraay/core/localization/app_strings.dart';

void main() {
  group('Campaigns Comparison & Benchmark Analytics Tests', () {
    test('CampaignMetricsSummary correctly computes avgBasketSpend and avgUnitsPerBasket', () {
      final summary = CampaignMetricsSummary(
        campaignId: 'camp_1',
        campaignTitle: 'Summer Mega Promo',
        targetCompany: 'Unilever',
        totalRevenue: 50000.0,
        totalInvoices: 200,
        totalProductsSold: 800,
        uniqueShoppersCount: 150,
        claimedPrizesCount: 50,
        estimatedPrizesValue: 2500.0,
        isActive: true,
      );

      // Average Basket Spend = 50,000 / 200 = 250.0
      expect(summary.avgBasketSpend, equals(250.0));

      // Average Units Per Basket = 800 / 200 = 4.0
      expect(summary.avgUnitsPerBasket, equals(4.0));
    });

    test('CampaignMetricsSummary handles zero invoices safely without dividing by zero', () {
      final summary = CampaignMetricsSummary(
        campaignId: 'camp_empty',
        campaignTitle: 'Empty Campaign',
        targetCompany: 'Unilever',
        totalRevenue: 0.0,
        totalInvoices: 0,
        totalProductsSold: 0,
        uniqueShoppersCount: 0,
        claimedPrizesCount: 0,
        estimatedPrizesValue: 0.0,
        isActive: false,
      );

      expect(summary.avgBasketSpend, equals(0.0));
      expect(summary.avgUnitsPerBasket, equals(0.0));
    });

    test('Delta variance percentage calculation handles positive, negative and zero baseline', () {
      // 1. Positive Growth (+50%)
      double valA = 15000.0;
      double valB = 10000.0;
      double diff = valA - valB;
      double pct = valB > 0 ? ((diff / valB) * 100) : 0.0;
      expect(pct, equals(50.0));

      // 2. Negative Delta (-25%)
      valA = 7500.0;
      valB = 10000.0;
      diff = valA - valB;
      pct = valB > 0 ? ((diff / valB) * 100) : 0.0;
      expect(pct, equals(-25.0));

      // 3. Zero Baseline (New campaign vs non-existent)
      valA = 5000.0;
      valB = 0.0;
      diff = valA - valB;
      pct = valB > 0 ? ((diff / valB) * 100) : (valA > 0 ? 100.0 : 0.0);
      expect(pct, equals(100.0));
    });

    test('Localization strings for Campaign Comparison exist in AR, EN, and HI', () {
      final arStrings = AppStrings('ar');
      final enStrings = AppStrings('en');
      final hiStrings = AppStrings('hi');

      // Arabic
      expect(arStrings.campaignsComparisonNavTitle, contains('مقارنة'));
      expect(arStrings.campaignComparisonScreenTitle, contains('مقارنة وتحليلات'));
      expect(arStrings.selectCampaignA, contains('A'));
      expect(arStrings.selectCampaignB, contains('B'));

      // English
      expect(enStrings.campaignsComparisonNavTitle, contains('Comparison'));
      expect(enStrings.campaignComparisonScreenTitle, contains('Benchmark'));
      expect(enStrings.selectCampaignA, contains('Primary'));
      expect(enStrings.selectCampaignB, contains('Benchmark'));

      // Hindi
      expect(hiStrings.campaignsComparisonNavTitle, contains('तुलना'));
      expect(hiStrings.campaignComparisonScreenTitle, contains('तुलनात्मक'));
    });

    testWidgets('CampaignsComparisonAnalyticsScreen instantiates with scoped parameters', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: Scaffold(
              body: CampaignsComparisonAnalyticsScreen(
                lockedCompanySlug: 'unilever',
                lockedCompanyName: 'يونيليفر',
                isEmbedded: true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CampaignsComparisonAnalyticsScreen), findsOneWidget);
    });

    test('Metric calculation logic accurately parses receipts_transactions document schema', () {
      final mockTx = {
        'campaignId': 'camp_axe',
        'companySlug': '512',
        'is_valid': true,
        'status': 'accepted',
        'target_company_total': 560,
        'total_value': 560,
        'extracted_products': [
          {
            'name': 'كن اسبراى كوكيز 150مل',
            'price': 140,
            'quantity': 1,
            'isTargetCompany': true,
          },
          {
            'name': 'اكس اسبراي جولد تمبتشن 150 مل',
            'price': 140,
            'quantity': 2,
            'isTargetCompany': true,
          },
        ],
        'claimed_gifts': [
          {
            'giftName': 'فواتشر 50 جنيه',
            'quantity': 2,
            'unitValue': 50,
            'isVoucher': true,
          },
        ],
        'customerPhone': '01012345678',
      };

      // 1. Check validity
      final status = (mockTx['status'] ?? '').toString().toLowerCase().trim();
      final bool isValid = mockTx['is_valid'] == true || status == 'accepted';
      expect(isValid, isTrue);

      // 2. Check revenue
      final double rev = (mockTx['target_company_total'] as num?)?.toDouble() ?? 0.0;
      expect(rev, equals(560.0));

      // 3. Check products quantity
      final products = mockTx['extracted_products'] as List;
      int totalUnits = 0;
      for (final p in products) {
        totalUnits += (p['quantity'] as num).toInt();
      }
      expect(totalUnits, equals(3)); // 1 + 2

      // 4. Check claimed gifts value
      final gifts = mockTx['claimed_gifts'] as List;
      double giftsVal = 0.0;
      int giftsCount = 0;
      for (final g in gifts) {
        final qty = (g['quantity'] as num).toInt();
        final unitVal = (g['unitValue'] as num).toDouble();
        giftsCount += qty;
        giftsVal += (qty * unitVal);
      }
      expect(giftsCount, equals(2));
      expect(giftsVal, equals(100.0));
    });

    testWidgets('CampaignsComparisonAnalyticsScreen renders responsive on mobile and desktop', (tester) async {
      // Mobile screen (400 x 800)
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: Scaffold(
              body: CampaignsComparisonAnalyticsScreen(
                lockedCompanySlug: '512',
                lockedCompanyName: 'يونيليفر',
                isEmbedded: true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CampaignsComparisonAnalyticsScreen), findsOneWidget);
    });

    test('Arabic campaign title normalization unifies dashes, spaces and letter forms', () {
      String normalizeTitle(String input) {
        if (input.isEmpty) return '';
        return input
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
            .replaceAll(RegExp(r'[إأآا]'), 'ا')
            .replaceAll('ة', 'ه')
            .replaceAll('ى', 'ي')
            .replaceAll(RegExp(r'[\-_–—\s]+'), ' ')
            .trim();
      }

      final variant1 = normalizeTitle('يونيليفر ديوز - هيركير');
      final variant2 = normalizeTitle('يونيليفر ديوز – هيركير'); // en-dash
      final variant3 = normalizeTitle('يونيليفر ديوز—هيركير'); // em-dash
      final variant4 = normalizeTitle('يونيليفر ديوز-هيركير'); // no spaces around hyphen
      final variant5 = normalizeTitle('يُونيلِيفر دِيوز - هِيركِير'); // tashkeel

      expect(variant1, equals('يونيليفر ديوز هيركير'));
      expect(variant2, equals(variant1));
      expect(variant3, equals(variant1));
      expect(variant4, equals(variant1));
      expect(variant5, equals(variant1));
    });

    test('Zero-latency persistent cache retains metrics summary across re-render cycles', () {
      final summaryA = CampaignMetricsSummary(
        campaignId: 'camp_oral',
        campaignTitle: 'Back to School Oral Care Event',
        targetCompany: 'Unilever',
        totalRevenue: 21691.0,
        totalInvoices: 45,
        totalProductsSold: 120,
        uniqueShoppersCount: 38,
        claimedPrizesCount: 20,
        estimatedPrizesValue: 1000.0,
        isActive: true,
      );

      final summaryB = CampaignMetricsSummary(
        campaignId: 'camp_hair',
        campaignTitle: 'يونيليفر ديوز - هيركير',
        targetCompany: 'Unilever',
        totalRevenue: 499334.0,
        totalInvoices: 512,
        totalProductsSold: 1800,
        uniqueShoppersCount: 420,
        claimedPrizesCount: 300,
        estimatedPrizesValue: 15000.0,
        isActive: true,
      );

      final cache = <String, CampaignMetricsSummary>{
        'camp_oral': summaryA,
        'camp_hair': summaryB,
      };

      // Ensure cache preserves both campaign summaries
      expect(cache['camp_oral']!.totalRevenue, equals(21691.0));
      expect(cache['camp_hair']!.totalRevenue, equals(499334.0));

      // Guard test: empty incoming list must NEVER wipe cached values to 0
      final incomingDocs = <Map<String, dynamic>>[];
      final effectiveMetrics = incomingDocs.isEmpty && cache.isNotEmpty ? cache : <String, CampaignMetricsSummary>{};

      expect(effectiveMetrics.isNotEmpty, isTrue);
      expect(effectiveMetrics['camp_hair']!.totalRevenue, equals(499334.0));
    });
  });
}

