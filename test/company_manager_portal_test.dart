import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/core/widgets/m3_button_groups.dart';
import 'package:al_mraay/features/company_portal/presentation/company_manager_portal_screen.dart';
import 'package:al_mraay/features/company_portal/presentation/company_prizes_stock_report_screen.dart';
import 'package:al_mraay/features/admin/presentation/campaign_reports_screen.dart';
import 'package:al_mraay/features/validation/presentation/invoices_log_screen.dart';

void main() {
  group('Dual Link Architecture & Company Manager Portal Tests', () {
    test('Localization strings for Dual Links are present in AR, EN, and HI', () {
      final stringsAr = AppStrings.fromLocale('ar');
      expect(stringsAr.copyPromoterLink, contains('البروموتر'));
      expect(stringsAr.copyManagerPortalLink, contains('مدير الشركة'));
      expect(stringsAr.previewManagerPortal, contains('معاينة بوابة المدير'));
      expect(stringsAr.companyManagerPortalTitle, contains('بوابة مدير'));
      expect(stringsAr.companyScopeBanner, contains('مخصص ومحصور'));
      expect(stringsAr.companyAllCampaigns, contains('جميع حملات وفعاليات الشركة'));

      final stringsEn = AppStrings.fromLocale('en');
      expect(stringsEn.copyPromoterLink, contains('Promoter'));
      expect(stringsEn.copyManagerPortalLink, contains('Manager'));
      expect(stringsEn.previewManagerPortal, contains('Preview Manager Portal'));
      expect(stringsEn.companyAllCampaigns, contains('All Company Campaigns'));

      final stringsHi = AppStrings.fromLocale('hi');
      expect(stringsHi.copyPromoterLink, isNotEmpty);
      expect(stringsHi.copyManagerPortalLink, isNotEmpty);
      expect(stringsHi.previewManagerPortal, isNotEmpty);
    });

    testWidgets('CompanyManagerPortalScreen renders executive header and 3 M3 tabs', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: CompanyManagerPortalScreen(
              companySlug: 'adco',
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify partner portal badge & M3ConnectedButtonGroup with tabs in portal header
      expect(find.byType(M3ConnectedButtonGroup<int>), findsWidgets);
      expect(find.byIcon(Icons.analytics_rounded), findsWidgets);
      expect(find.byIcon(Icons.receipt_long_rounded), findsWidgets);
      expect(find.byIcon(Icons.inventory_2_rounded), findsWidgets);

      // Verify embedded CampaignReportsScreen is instantiated initially
      expect(find.byType(CampaignReportsScreen), findsOneWidget);
    });

    testWidgets('Tapping Invoices Log tab in CompanyManagerPortalScreen switches view to InvoicesLogScreen', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: CompanyManagerPortalScreen(
              companySlug: 'adco',
            ),
          ),
        ),
      );

      await tester.pump();

      // Find the second segment (Invoices Log)
      final invoicesSegment = find.byIcon(Icons.receipt_long_rounded).first;
      await tester.tap(invoicesSegment);
      await tester.pump();

      // Verify InvoicesLogScreen is rendered
      expect(find.byType(InvoicesLogScreen), findsOneWidget);
    });

    testWidgets('Tapping Prizes Stock tab in CompanyManagerPortalScreen switches view to CompanyPrizesStockReportScreen', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: CompanyManagerPortalScreen(
              companySlug: 'adco',
            ),
          ),
        ),
      );

      await tester.pump();

      // Find the third segment (Prizes Stock)
      final prizesStockSegment = find.byIcon(Icons.inventory_2_rounded).first;
      await tester.tap(prizesStockSegment);
      await tester.pump();

      // Verify CompanyPrizesStockReportScreen is rendered
      expect(find.byType(CompanyPrizesStockReportScreen), findsOneWidget);
    });

    testWidgets('CompanyManagerPortalScreen renders responsive mobile layout on smartphone (390x844)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: CompanyManagerPortalScreen(
              companySlug: 'adco',
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify portal header renders with full-width M3ConnectedButtonGroup
      expect(find.byType(M3ConnectedButtonGroup<int>), findsWidgets);
      expect(find.byType(CampaignReportsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Tap on Prizes Stock tab on mobile
      final prizesStockSegment = find.byIcon(Icons.inventory_2_rounded).first;
      await tester.tap(prizesStockSegment);
      await tester.pump();

      // Verify CompanyPrizesStockReportScreen is rendered with 0 overflow errors
      expect(find.byType(CompanyPrizesStockReportScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('CampaignReportsScreen accepts lockedCompanySlug parameter for secure data scoping', () {
      const reports = CampaignReportsScreen(
        lockedCompanySlug: 'juhayna',
        lockedCompanyName: 'جهينة',
        isEmbedded: true,
      );

      expect(reports.lockedCompanySlug, equals('juhayna'));
      expect(reports.lockedCompanyName, equals('جهينة'));
      expect(reports.isEmbedded, isTrue);
    });

    test('InvoicesLogScreen accepts lockedCompanySlug parameter for secure data scoping', () {
      const invoices = InvoicesLogScreen(
        lockedCompanySlug: 'lamar',
        lockedCompanyName: 'لمار',
        isEmbedded: true,
      );

      expect(invoices.lockedCompanySlug, equals('lamar'));
      expect(invoices.lockedCompanyName, equals('لمار'));
      expect(invoices.isEmbedded, isTrue);
    });

    test('CompanyPrizesStockReportScreen accepts lockedCompanySlug parameter for secure data scoping', () {
      const prizesStock = CompanyPrizesStockReportScreen(
        lockedCompanySlug: 'unilever',
        lockedCompanyName: 'يونيليفر',
        isEmbedded: true,
      );

      expect(prizesStock.lockedCompanySlug, equals('unilever'));
      expect(prizesStock.lockedCompanyName, equals('يونيليفر'));
      expect(prizesStock.isEmbedded, isTrue);
    });
  });
}
