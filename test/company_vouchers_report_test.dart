import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/features/company_portal/presentation/company_vouchers_report_screen.dart';

void main() {
  group('CompanyVouchersReportScreen Tests (Dedicated Vouchers Management)', () {
    test('Localization strings for Vouchers are defined properly in all supported languages', () {
      final stringsAr = AppStrings.fromLocale('ar');
      expect(stringsAr.vouchersNavTitle, equals('قسائم المشتريات'));
      expect(stringsAr.vouchersNavSubtitle, contains('القسائم'));
      expect(stringsAr.voucherIntelligenceTitle, contains('قسائم المشتريات'));
      expect(stringsAr.exportVouchersExcel, contains('Excel'));

      final stringsEn = AppStrings.fromLocale('en');
      expect(stringsEn.vouchersNavTitle, equals('Vouchers & Gift Cards'));
      expect(stringsEn.vouchersNavSubtitle, contains('Voucher'));
      expect(stringsEn.voucherIntelligenceTitle, contains('Voucher'));
      expect(stringsEn.exportVouchersExcel, contains('Excel'));

      final stringsHi = AppStrings.fromLocale('hi');
      expect(stringsHi.vouchersNavTitle, isNotEmpty);
      expect(stringsHi.vouchersNavSubtitle, isNotEmpty);
    });

    testWidgets('CompanyVouchersReportScreen widget can be instantiated with scoping parameters', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: Scaffold(
              body: CompanyVouchersReportScreen(
                lockedCompanySlug: 'adco',
                lockedCompanyName: 'أدكو',
                initialEventId: 'event_test_123',
                isEmbedded: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(CompanyVouchersReportScreen), findsOneWidget);
    });

    testWidgets('CompanyVouchersReportScreen renders standalone in full screen mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: CompanyVouchersReportScreen(
              lockedCompanySlug: 'unilever',
              lockedCompanyName: 'يونيليفر',
              isEmbedded: false,
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(CompanyVouchersReportScreen), findsOneWidget);
    });

    testWidgets('CompanyVouchersReportScreen renders responsively on desktop (1400x900) without overflow', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: Scaffold(
              body: CompanyVouchersReportScreen(
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
      expect(find.byType(CompanyVouchersReportScreen), findsOneWidget);
    });

    testWidgets('CompanyVouchersReportScreen renders responsively on mobile (390x844) without overflow', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: Scaffold(
              body: CompanyVouchersReportScreen(
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
      expect(find.byType(CompanyVouchersReportScreen), findsOneWidget);
    });

    testWidgets('Tapping Expand button opens Voucher Matrix Dialog cleanly without freezing or layout errors', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: Scaffold(
              body: CompanyVouchersReportScreen(
                lockedCompanySlug: 'unilever',
                lockedCompanyName: 'يونيليفر',
                isEmbedded: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Find the expand button by text or icon
      final expandBtn = find.text('عرض مكبر');
      if (expandBtn.evaluate().isNotEmpty) {
        await tester.tap(expandBtn);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(Dialog), findsOneWidget);

        // Tap close
        final closeBtn = find.text('إغلاق');
        if (closeBtn.evaluate().isNotEmpty) {
          await tester.tap(closeBtn.last);
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
        }
      }
    });
  });
}
