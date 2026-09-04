import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/core/localization/locale_provider.dart';
import 'package:al_mraay/features/company_portal/presentation/company_manager_portal_screen.dart';
import 'package:al_mraay/features/company_portal/presentation/company_vouchers_report_screen.dart';
import 'package:al_mraay/features/company_portal/presentation/campaigns_comparison_analytics_screen.dart';
import 'package:al_mraay/features/company_portal/presentation/company_prizes_stock_report_screen.dart';
import 'package:al_mraay/features/admin/presentation/campaign_reports_screen.dart';
import 'package:al_mraay/features/validation/presentation/invoices_log_screen.dart';
import 'package:al_mraay/features/auth/presentation/auth_screen.dart';
import 'package:al_mraay/core/utils/slug_utils.dart';

void main() {
  group('Dual Link Architecture & Company Manager Portal Tests', () {
    test('Localization strings for Dual Links & Vouchers are present in AR, EN, and HI', () {
      final stringsAr = AppStrings.fromLocale('ar');
      expect(stringsAr.copyPromoterLink, contains('البروموتر'));
      expect(stringsAr.copyManagerPortalLink, contains('مدير الشركة'));
      expect(stringsAr.previewManagerPortal, contains('معاينة بوابة المدير'));
      expect(stringsAr.companyManagerPortalTitle, contains('بوابة مدير'));
      expect(stringsAr.companyScopeBanner, contains('مخصص ومحصور'));
      expect(stringsAr.companyAllCampaigns, contains('جميع حملات وفعاليات الشركة'));
      expect(stringsAr.vouchersNavTitle, contains('قسائم المشتريات'));

      final stringsEn = AppStrings.fromLocale('en');
      expect(stringsEn.copyPromoterLink, contains('Promoter'));
      expect(stringsEn.copyManagerPortalLink, contains('Manager'));
      expect(stringsEn.previewManagerPortal, contains('Preview Manager Portal'));
      expect(stringsEn.companyAllCampaigns, contains('All Company Campaigns'));
      expect(stringsEn.vouchersNavTitle, contains('Vouchers'));

      final stringsHi = AppStrings.fromLocale('hi');
      expect(stringsHi.copyPromoterLink, isNotEmpty);
      expect(stringsHi.copyManagerPortalLink, isNotEmpty);
      expect(stringsHi.previewManagerPortal, isNotEmpty);
      expect(stringsHi.vouchersNavTitle, isNotEmpty);
    });

    testWidgets('CompanyManagerPortalScreen renders executive header and M3 Dashboard sidebar on desktop with correct RTL positioning in Arabic', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 1. Arabic (RTL): Sidebar must be on the RIGHT (start)
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: CompanyManagerPortalScreen(
              companySlug: 'adco',
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify dashboard navigation items in the sidebar (5 streamlined items)
      expect(find.byIcon(Icons.analytics_rounded), findsWidgets);
      expect(find.byIcon(Icons.receipt_long_outlined), findsWidgets);
      expect(find.byIcon(Icons.account_balance_wallet_outlined), findsWidgets);
      expect(find.byIcon(Icons.confirmation_number_outlined), findsWidgets);

      // Verify sidebar rect in RTL is on the RIGHT side of the screen
      final sidebarInArabic = tester.getRect(find.byType(AnimatedContainer).first);
      expect(sidebarInArabic.right, greaterThanOrEqualTo(1270));

      // Verify embedded CampaignReportsScreen is instantiated initially
      expect(find.byType(CampaignReportsScreen), findsOneWidget);
    });

    testWidgets('CompanyManagerPortalScreen renders M3 Dashboard sidebar on desktop with correct LTR positioning in English', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 2. English (LTR): Sidebar must be on the LEFT (start)
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localeProvider.overrideWith((ref) => const Locale('en')),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            home: CompanyManagerPortalScreen(
              companySlug: 'adco',
            ),
          ),
        ),
      );

      await tester.pump();

      final sidebarInEnglish = tester.getRect(find.byType(AnimatedContainer).first);
      expect(sidebarInEnglish.left, lessThanOrEqualTo(10));
    });

    testWidgets('Toggling sidebar collapse and expand animates smoothly with zero overflow exceptions', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: CompanyManagerPortalScreen(
              companySlug: 'adco',
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);

      // Verify sidebar is initially expanded (275px)
      var sidebarRect = tester.getRect(find.byType(AnimatedContainer).first);
      expect(sidebarRect.width, equals(275.0));

      // Tap collapse button
      final collapseBtn = find.byIcon(Icons.keyboard_double_arrow_right_rounded);
      expect(collapseBtn, findsOneWidget);
      await tester.tap(collapseBtn);

      // Pump frames during animation
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();

      // Verify sidebar is now collapsed (76px)
      sidebarRect = tester.getRect(find.byType(AnimatedContainer).first);
      expect(sidebarRect.width, equals(76.0));
      expect(tester.takeException(), isNull);

      // Tap expand button
      final expandBtn = find.byIcon(Icons.keyboard_double_arrow_left_rounded);
      expect(expandBtn, findsOneWidget);
      await tester.tap(expandBtn);

      // Pump frames during expansion
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();

      // Verify sidebar is expanded again (275px)
      sidebarRect = tester.getRect(find.byType(AnimatedContainer).first);
      expect(sidebarRect.width, equals(275.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tapping Invoices Log tab in CompanyManagerPortalScreen switches view to InvoicesLogScreen', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: CompanyManagerPortalScreen(
              companySlug: 'adco',
            ),
          ),
        ),
      );

      await tester.pump();

      // Find the second item (Invoices Log) in the sidebar
      final invoicesItem = find.byIcon(Icons.receipt_long_outlined).first;
      await tester.tap(invoicesItem);
      await tester.pumpAndSettle();

      // Verify InvoicesLogScreen is rendered
      expect(find.byType(InvoicesLogScreen), findsOneWidget);
    });

    testWidgets('Tapping Campaigns Comparison tab in CompanyManagerPortalScreen switches view to CampaignsComparisonAnalyticsScreen', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: CompanyManagerPortalScreen(
              companySlug: 'adco',
            ),
          ),
        ),
      );

      await tester.pump();

      // Find the comparison item in the sidebar
      final comparisonItem = find.byIcon(Icons.compare_arrows_outlined).first;
      await tester.tap(comparisonItem);
      await tester.pump();

      // Verify CampaignsComparisonAnalyticsScreen is rendered
      expect(find.byType(CampaignsComparisonAnalyticsScreen), findsOneWidget);
    });

    testWidgets('Tapping Vouchers tab in CompanyManagerPortalScreen switches view to CompanyVouchersReportScreen', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: CompanyManagerPortalScreen(
              companySlug: 'adco',
            ),
          ),
        ),
      );

      await tester.pump();

      // Find the Vouchers item in the sidebar
      final vouchersItem = find.byIcon(Icons.confirmation_number_outlined).first;
      await tester.tap(vouchersItem);
      await tester.pumpAndSettle();

      // Verify CompanyVouchersReportScreen is rendered
      expect(find.byType(CompanyVouchersReportScreen), findsOneWidget);
    });

    testWidgets('CompanyManagerPortalScreen renders responsive mobile layout on smartphone (390x844)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: CompanyManagerPortalScreen(
              companySlug: 'adco',
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify mobile bottom navigation bar renders
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(CampaignReportsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Tap on Vouchers tab on mobile navigation bar
      final vouchersSegment = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.confirmation_number_outlined),
      );
      await tester.tap(vouchersSegment);
      await tester.pumpAndSettle();

      // Verify CompanyVouchersReportScreen is rendered
      expect(find.byType(CompanyVouchersReportScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('CompanyVouchersReportScreen accepts lockedCompanySlug and initialEventId parameters for secure data scoping', () {
      const vouchers = CompanyVouchersReportScreen(
        lockedCompanySlug: 'juhayna',
        lockedCompanyName: 'جهينة',
        initialEventId: 'event_vouchers_123',
        isEmbedded: true,
      );

      expect(vouchers.lockedCompanySlug, equals('juhayna'));
      expect(vouchers.lockedCompanyName, equals('جهينة'));
      expect(vouchers.initialEventId, equals('event_vouchers_123'));
      expect(vouchers.isEmbedded, isTrue);
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

    test('InvoicesLogScreen accepts lockedCompanySlug and initialEventId parameters for secure data scoping', () {
      const invoices = InvoicesLogScreen(
        lockedCompanySlug: 'lamar',
        lockedCompanyName: 'لمار',
        initialEventId: 'event_123',
        isEmbedded: true,
      );

      expect(invoices.lockedCompanySlug, equals('lamar'));
      expect(invoices.lockedCompanyName, equals('لمار'));
      expect(invoices.initialEventId, equals('event_123'));
      expect(invoices.isEmbedded, isTrue);
    });

    test('CompanyPrizesStockReportScreen accepts lockedCompanySlug and initialEventId parameters for secure data scoping', () {
      const prizesStock = CompanyPrizesStockReportScreen(
        lockedCompanySlug: 'unilever',
        lockedCompanyName: 'يونيليفر',
        initialEventId: 'unilever_event_456',
        isEmbedded: true,
      );

      expect(prizesStock.lockedCompanySlug, equals('unilever'));
      expect(prizesStock.lockedCompanyName, equals('يونيليفر'));
      expect(prizesStock.initialEventId, equals('unilever_event_456'));
      expect(prizesStock.isEmbedded, isTrue);
    });

    test('SlugUtils translates Unilever and Adco accurately to English slugs', () {
      expect(SlugUtils.toSlug('يونيليفر'), equals('unilever'));
      expect(SlugUtils.toSlug('يوني ليفر'), equals('unilever'));
      expect(SlugUtils.toSlug('ادكو'), equals('adco'));
      expect(SlugUtils.toSlug('أدكو'), equals('adco'));
    });

    testWidgets('CompanyManagerPortalScreen with empty slug and null event renders AuthScreen instead of arbitrary fallback', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: CompanyManagerPortalScreen(
              companySlug: '',
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(AuthScreen), findsOneWidget);
    });
  });
}
