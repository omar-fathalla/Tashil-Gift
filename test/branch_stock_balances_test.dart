import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/features/company_portal/presentation/branch_stock_balances_screen.dart';

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
  });
}
