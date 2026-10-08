import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/constants/country_currency_config.dart';
import 'package:al_mraay/features/admin/presentation/widgets/branch_chain_analytics_charts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const egyptCurrency = CountryCurrencyConfig.defaultCountry;

  final testItems = [
    BranchChartItem(
      name: 'أسواق فتح الله',
      totalRevenue: 15400.0,
      receiptCount: 120,
      percentageOfTotal: 55.0,
      isChain: true,
      color: Colors.indigo,
    ),
    BranchChartItem(
      name: 'كارفور',
      totalRevenue: 8600.0,
      receiptCount: 65,
      percentageOfTotal: 30.7,
      isChain: true,
      color: Colors.teal,
    ),
    BranchChartItem(
      name: 'خير زمان',
      totalRevenue: 4000.0,
      receiptCount: 35,
      percentageOfTotal: 14.3,
      isChain: true,
      color: Colors.amber,
    ),
  ];

  group('BranchChartItem Unit Tests', () {
    test('Calculates average ticket value accurately', () {
      final item = testItems.first;
      expect(item.avgTicket, closeTo(15400.0 / 120, 0.01));
    });

    test('Handles zero receipt count safely without division by zero', () {
      final item = BranchChartItem(
        name: 'فرع تجريبي',
        totalRevenue: 0.0,
        receiptCount: 0,
        percentageOfTotal: 0.0,
        isChain: false,
        color: Colors.grey,
      );
      expect(item.avgTicket, 0.0);
    });
  });

  group('BranchPerformanceKpiRow Widget Tests', () {
    testWidgets('Renders KPI metrics row correctly in Arabic', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BranchPerformanceKpiRow(
              activeEntitiesCount: 3,
              topEntityName: 'أسواق فتح الله',
              topEntityRevenue: 15400.0,
              avgRevenuePerEntity: 9333.3,
              activeCountry: egyptCurrency,
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
              isChainMode: true,
              isAr: true,
              isHi: false,
              isMobile: false,
            ),
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);
      expect(find.text('أسواق فتح الله'), findsOneWidget);
      expect(find.textContaining('15,400'), findsOneWidget);
    });

    testWidgets('Renders KPI metrics row correctly in English and Hindi', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BranchPerformanceKpiRow(
              activeEntitiesCount: 12,
              topEntityName: 'Smouha Branch',
              topEntityRevenue: 5000.0,
              avgRevenuePerEntity: 2500.0,
              activeCountry: egyptCurrency,
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
              isChainMode: false,
              isAr: false,
              isHi: true,
              isMobile: true,
            ),
          ),
        ),
      );

      expect(find.text('12'), findsOneWidget);
      expect(find.text('Smouha Branch'), findsOneWidget);
      expect(find.text('शीर्ष आउटलेट'), findsOneWidget);
    });
  });

  group('cleanBranchDisplayName Tests', () {
    test('Strips parenthetical governorates and supermarket prefixes', () {
      expect(
        BranchChainBarChart.cleanBranchDisplayName(
          'أسواق فتح الله - فرع المحلة الكبرى (الغربية)',
          isChain: false,
          isAr: true,
        ),
        'فرع المحلة الكبرى',
      );

      expect(
        BranchChainBarChart.cleanBranchDisplayName(
          'أسواق فتح الله - فرع سموحة (الإسكندرية)',
          isChain: false,
          isAr: true,
        ),
        'فرع سموحة',
      );

      expect(
        BranchChainBarChart.cleanBranchDisplayName(
          'أسواق فتح الله - فرع دمنهور (البحيرة)',
          isChain: false,
          isAr: true,
        ),
        'فرع دمنهور',
      );

      expect(
        BranchChainBarChart.cleanBranchDisplayName(
          'المحلة الكبرى (الغربية)',
          isChain: false,
          isAr: true,
        ),
        'فرع المحلة الكبرى',
      );
    });

    test('Preserves retail chain names without adding فرع', () {
      expect(
        BranchChainBarChart.cleanBranchDisplayName(
          'أسواق فتح الله (المركز الرئيسي)',
          isChain: true,
          isAr: true,
        ),
        'أسواق فتح الله',
      );

      expect(
        BranchChainBarChart.cleanBranchDisplayName(
          'كارفور مصر',
          isChain: true,
          isAr: true,
        ),
        'كارفور مصر',
      );
    });
  });

  group('BranchChainLeaderboardList Widget Tests', () {
    testWidgets('Renders top 3 medals (🥇, 🥈, 🥉) and details accurately', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BranchChainLeaderboardList(
                items: testItems,
                maxRevenue: 15400.0,
                activeCountry: egyptCurrency,
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
                isAr: true,
                isHi: false,
                isMobile: false,
              ),
            ),
          ),
        ),
      );

      expect(find.text('🥇'), findsOneWidget);
      expect(find.text('🥈'), findsOneWidget);
      expect(find.text('🥉'), findsOneWidget);
      expect(find.text('أسواق فتح الله'), findsOneWidget);
      expect(find.text('كارفور'), findsOneWidget);
      expect(find.text('خير زمان'), findsOneWidget);
    });
  });

  group('BranchChainDonutChart & BarChart Widget Tests', () {
    testWidgets('Renders Donut Chart container and legend items', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BranchChainDonutChart(
                items: testItems,
                totalSales: 28000.0,
                totalReceipts: 220,
                metricDimension: 'REVENUE',
                activeCountry: egyptCurrency,
                isAr: true,
                isHi: false,
              ),
            ),
          ),
        ),
      );

      expect(find.text('أسواق فتح الله'), findsOneWidget);
      expect(find.text('كارفور'), findsOneWidget);
      expect(find.text('خير زمان'), findsOneWidget);
    });

    testWidgets('Renders Bar Chart container with visible direct values without hover', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BranchChainBarChart(
                items: testItems,
                metricDimension: 'REVENUE',
                activeCountry: egyptCurrency,
                isAr: true,
                isHi: false,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(BranchChainBarChart), findsOneWidget);
      // Top titles visible values
      expect(find.textContaining('15,400'), findsOneWidget);
      expect(find.textContaining('8,600'), findsOneWidget);
      expect(find.textContaining('4,000'), findsOneWidget);
    });
  });
}
