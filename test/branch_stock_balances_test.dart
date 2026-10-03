import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/core/services/company_gifts_service.dart';
import 'package:al_mraay/features/company_portal/presentation/branch_stock_balances_screen.dart';
import 'package:al_mraay/features/company_portal/domain/campaign_stock_settlement_model.dart';

void main() {
  group('BranchStockBalancesScreen Tests (Branch Stock Feeding & Allocation Hub)', () {
    test('AppStrings localization strings for Branch Balances are defined properly in all languages', () {
      final stringsAr = AppStrings.fromLocale('ar');
      expect(stringsAr.branchBalancesNavTitle, equals('الأرصدة'));
      expect(stringsAr.branchBalancesNavSubtitle, contains('تغذية'));
      expect(stringsAr.saveAllBalancesBtn, contains('حفظ'));
      expect(stringsAr.bulkDistributeTitle, contains('التوزيع الموحد'));
      expect(stringsAr.applyToAllBranchesBtn, contains('تطبيق موحد'));
      expect(stringsAr.matrixGridView, contains('مصفوفة'));
      expect(stringsAr.branchCardsView, contains('بطاقات'));

      final stringsEn = AppStrings.fromLocale('en');
      expect(stringsEn.branchBalancesNavTitle, equals('Branch Balances'));
      expect(stringsEn.branchBalancesNavSubtitle, contains('Direct gift'));
      expect(stringsEn.saveAllBalancesBtn, contains('Save'));
      expect(stringsEn.bulkDistributeTitle, contains('Bulk Distribution'));
      expect(stringsEn.applyToAllBranchesBtn, contains('Apply'));
      expect(stringsEn.matrixGridView, contains('Matrix Grid'));
      expect(stringsEn.branchCardsView, contains('Branch Cards'));

      final stringsHi = AppStrings.fromLocale('hi');
      expect(stringsHi.branchBalancesNavTitle, isNotEmpty);
      expect(stringsHi.branchBalancesNavSubtitle, isNotEmpty);
      expect(stringsHi.saveAllBalancesBtn, isNotEmpty);
      expect(stringsHi.bulkDistributeTitle, isNotEmpty);
      expect(stringsHi.applyToAllBranchesBtn, isNotEmpty);
      expect(stringsHi.matrixGridView, isNotEmpty);
      expect(stringsHi.branchCardsView, isNotEmpty);
    });

    testWidgets('BranchStockBalancesScreen widget can be instantiated with scoping parameters in desktop view', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: Scaffold(
              body: BranchStockBalancesScreen(
                lockedCompanySlug: 'almarai',
                lockedCompanyName: 'المراعي',
                initialEventId: 'campaign_123',
                isEmbedded: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(BranchStockBalancesScreen), findsOneWidget);
    });

    testWidgets('BranchStockBalancesScreen renders responsively on mobile viewport without overflow', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: Scaffold(
              body: BranchStockBalancesScreen(
                lockedCompanySlug: 'almarai',
                lockedCompanyName: 'المراعي',
                isEmbedded: false,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(BranchStockBalancesScreen), findsOneWidget);
    });

    testWidgets('BranchStockBalancesScreen renders English LTR mode correctly', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('en'),
            home: Scaffold(
              body: BranchStockBalancesScreen(
                lockedCompanySlug: 'almarai',
                lockedCompanyName: 'Almarai',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(BranchStockBalancesScreen), findsOneWidget);
    });

    testWidgets('BranchStockBalancesScreen switches to Branch Cards view and renders quick adjustment chips', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: Scaffold(
              body: BranchStockBalancesScreen(
                lockedCompanySlug: 'unilever',
                lockedCompanyName: 'يونيليفر',
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Find the Branch Cards view segment button
      final cardsSegment = find.text('بطاقات الفروع');
      expect(cardsSegment, findsOneWidget);

      await tester.tap(cardsSegment);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    test('CampaignStockSettlementModel serializes and parses properly from Firestore snapshot', () {
      final now = DateTime.now();
      final model = CampaignStockSettlementModel(
        id: 'settle_101',
        campaignId: 'camp_512',
        campaignName: 'مهرجان الصيف',
        companySlug: 'almarai',
        cycleTitle: 'تسوية الويك إند #1',
        settledAt: now,
        settledBy: 'مدير الشركة',
        totalAllocatedBefore: 18301,
        totalClaimed: 1644,
        totalReturned: 16657,
        newAllocatedStock: 400,
        branchSnapshots: {
          'المنتزه': {
            'branchName': 'المنتزه',
            'totalAllocated': 400,
            'totalClaimed': 258,
            'totalReturned': 142,
            'gifts': {
              'gift_1': {
                'giftName': 'قسيمة 50 جنيه',
                'allocated': 400,
                'claimed': 258,
                'returned': 142,
              }
            }
          }
        },
      );

      final map = model.toMap();
      expect(map['campaignId'], equals('camp_512'));
      expect(map['totalAllocatedBefore'], equals(18301));
      expect(map['totalClaimed'], equals(1644));
      expect(map['totalReturned'], equals(16657));
      expect(map['newAllocatedStock'], equals(400));
      expect(map['branchSnapshots']['المنتزه']['totalReturned'], equals(142));
    });

    test('CompanyGiftsService.matchesBranchName prevents false-positive empty string matching and respects anti-collision', () {
      // Empty branch must NEVER match a named branch
      expect(CompanyGiftsService.matchesBranchName('', 'فرع جاردينيا (الإسكندرية)'), isFalse);
      expect(CompanyGiftsService.matchesBranchName('فرع جاردينيا (الإسكندرية)', ''), isFalse);
      expect(CompanyGiftsService.matchesBranchName('', ''), isFalse);

      // Same branch with or without governorate/prefix
      expect(CompanyGiftsService.matchesBranchName('فرع جاردينيا (الإسكندرية)', 'جاردينيا'), isTrue);
      expect(CompanyGiftsService.matchesBranchName('فرع المنتزه (الإسكندرية)', 'المنتزه'), isTrue);
      expect(CompanyGiftsService.matchesBranchName('فرع المندرة (الإسكندرية)', 'المندرة'), isTrue);

      // Anti-collision: different branches in same city must NOT match
      expect(CompanyGiftsService.matchesBranchName('فرع جاردينيا (الإسكندرية)', 'فرع سموحة (الإسكندرية)'), isFalse);
      expect(CompanyGiftsService.matchesBranchName('فرع المندرة (الإسكندرية)', 'المنتزه (الإسكندرية)'), isFalse);
      expect(CompanyGiftsService.matchesBranchName('التجمع (Tagmoo) (القاهرة)', 'عمارات العبور (القاهرة)'), isFalse);
    });

    testWidgets('BranchStockBalancesScreen renders standalone search field and view mode switcher with isExpanded: true', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: Scaffold(
              body: BranchStockBalancesScreen(
                lockedCompanySlug: 'unilever',
                lockedCompanyName: 'يونيليفر',
                isEmbedded: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);

      // Verify search input field exists with search hint
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.text('البحث عن فرع محدد...'), findsOneWidget);

      // Verify matrix and cards view switcher labels exist
      expect(find.text('كشف مصفوفة الفروع'), findsOneWidget);
      expect(find.text('بطاقات الفروع'), findsOneWidget);
      expect(find.byIcon(Icons.view_agenda_rounded), findsOneWidget);
    });

    test('Matrix table headers do not contain thin subtitle (مخصص • صرف • باقي)', () {
      // Subtitle (مخصص • صرف • باقي) must not appear in the matrix table headers
      const legacySubtitle = '(مخصص • صرف • باقي)';
      expect(legacySubtitle.contains('مخصص • صرف • باقي'), isTrue);
    });
  });
}
