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
import 'package:al_mraay/features/company_portal/presentation/branch_stock_balances_screen.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Dual Link Architecture & Company Manager Portal Tests', () {
    test('Localization strings for Dual Links & Vouchers are present in AR, EN, and HI', () {
      final stringsAr = AppStrings.fromLocale('ar');
      expect(stringsAr.copyPromoterLink, contains('المندوب'));
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

    testWidgets('CompanyManagerPortalScreen renders M3 Navigation Rail with 80dp slim width and zero overflow exceptions', (tester) async {
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

      // Verify sidebar is M3 Navigation Rail with 80dp fixed width
      final sidebarRect = tester.getRect(find.byType(AnimatedContainer).first);
      expect(sidebarRect.width, equals(80.0));

      // Verify NavigationRail is rendered with all concise labels visible
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('المؤشرات والتحاليل'), findsWidgets);
      expect(find.text('مقارنة التحاليل'), findsWidgets);
      expect(find.text('الأرصدة'), findsWidgets);
      expect(find.text('Voucher'), findsWidgets);
      expect(find.text('Promoter'), findsWidgets);

      // Verify that navigation starts at the top and company logo is at the bottom
      final firstDestRect = tester.getRect(find.text('المؤشرات والتحاليل').first);
      final logoFinder = find.byIcon(Icons.business_rounded);
      if (logoFinder.evaluate().isNotEmpty) {
        final logoRect = tester.getRect(logoFinder.first);
        expect(logoRect.top, greaterThan(firstDestRect.bottom));
        expect(logoRect.bottom, greaterThan(800.0));
      }
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

      // Verify squished bottom navigation bar is removed
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(CampaignReportsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Verify mobile menu button is present in header
      final menuBtn = find.byIcon(Icons.menu_rounded);
      expect(menuBtn, findsOneWidget);

      // Tap on menu button to open drawer
      await tester.tap(menuBtn);
      await tester.pumpAndSettle();

      // Verify Drawer is opened with zero layout overflow
      expect(find.byType(Drawer), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Verify pinned bottom section: 3 quick share icon buttons are present
      expect(find.byIcon(Icons.qr_code_scanner_rounded), findsOneWidget);
      expect(find.byIcon(Icons.store_mall_directory_rounded), findsOneWidget);
      expect(find.byIcon(Icons.business_center_rounded), findsOneWidget);

      // Verify Tashil Gift version info is at the bottom
      expect(find.textContaining('Build #'), findsOneWidget);

      // Verify Settings section is titled 'الإعدادات' and is collapsed by default in pinned section
      expect(find.text('الإعدادات'), findsOneWidget);
      expect(find.text('الإعدادات والمظهر (Settings)'), findsNothing);

      // Tap on Settings to expand it
      await tester.tap(find.text('الإعدادات'));
      await tester.pumpAndSettle();

      // Verify language and country settings are revealed upon expansion with zero overflow as Dropdown menus
      expect(find.text('لغة الواجهة'), findsOneWidget);
      expect(find.text('الدولة والعملة المعتمدة'), findsOneWidget);
      expect(find.descendant(of: find.byType(ExpansionTile), matching: find.byType(DropdownButton<String>)), findsNWidgets(2));
      expect(find.byType(ChoiceChip), findsNothing);
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

    testWidgets('CompanyManagerPortalScreen with empty slug and null event never renders AuthScreen or triggers admin redirect', (tester) async {
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
      // On frame 0 without events, it shows a clean loading indicator or suspended screen, never AuthScreen
      expect(find.byType(AuthScreen), findsNothing);
      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
      );
    });

    test('BranchStockBalancesScreen accepts lockedCompanySlug and initialEventId parameters for secure data scoping', () {
      const balances = BranchStockBalancesScreen(
        lockedCompanySlug: 'adco',
        lockedCompanyName: 'أدكو',
        initialEventId: 'event_adco_123',
        isEmbedded: true,
      );

      expect(balances.lockedCompanySlug, equals('adco'));
      expect(balances.lockedCompanyName, equals('أدكو'));
      expect(balances.initialEventId, equals('event_adco_123'));
      expect(balances.isEmbedded, isTrue);
    });

    test('BranchStockBalancesScreen action buttons and shortened headers are correctly supported', () {
      final stringsAr = AppStrings.fromLocale('ar');
      expect(stringsAr.branchBalancesNavTitle, equals('الأرصدة'));
      expect(stringsAr.saveAllBalancesBtn, isNotEmpty);
      expect(stringsAr.bulkDistributeTitle, contains('التوزيع الموحد'));
      expect(stringsAr.applyToAllBranchesBtn, contains('تطبيق موحد'));
      expect(stringsAr.matrixGridView, isNotEmpty);
      expect(stringsAr.branchCardsView, isNotEmpty);

      final stringsEn = AppStrings.fromLocale('en');
      expect(stringsEn.branchBalancesNavTitle, equals('Branch Balances'));
      expect(stringsEn.saveAllBalancesBtn, isNotEmpty);
      expect(stringsEn.applyToAllBranchesBtn, isNotEmpty);
    });

    test('managerPortalArchiveNotice string is localized across AR, EN, and HI', () {
      final stringsAr = AppStrings.fromLocale('ar');
      expect(stringsAr.managerPortalArchiveNotice, contains('المراجعة'));
      expect(stringsAr.managerPortalArchiveNotice, contains('متوقفة'));

      final stringsEn = AppStrings.fromLocale('en');
      expect(stringsEn.managerPortalArchiveNotice, contains('Audit'));
      expect(stringsEn.managerPortalArchiveNotice, contains('paused'));

      final stringsHi = AppStrings.fromLocale('hi');
      expect(stringsHi.managerPortalArchiveNotice, isNotEmpty);
    });

    test('EventModel portal access rules decouple Manager from isActive while keeping Promoter and Agency strictly gated', () {
      // 1. Inactive Campaign (isActive: false), but Manager and Promoter active flags are true
      final inactiveEvent = EventModel(
        id: 'evt_inactive_1',
        eventName: 'حملة شومان المتوقفة',
        targetCompany: 'شومان',
        companySlug: 'shoman',
        minimumSpend: 100.0,
        startDate: DateTime.now().subtract(const Duration(days: 10)),
        endDate: DateTime.now().add(const Duration(days: 10)),
        isActive: false, // PAUSED CAMPAIGN
        isPromoterActive: true,
        isAgencyActive: true,
        isManagerActive: true,
      );

      // Promoter MUST be BLOCKED when campaign is inactive
      expect(inactiveEvent.canPromoterAccess, isFalse, reason: 'Promoters must be strictly blocked from scanning inactive campaigns');

      // Agency Ops MUST be BLOCKED when campaign is inactive
      expect(inactiveEvent.canAgencyAccess, isFalse, reason: 'Agency field ops must be blocked from auditing inactive campaigns');

      // Company Manager MUST REMAIN PERMANENTLY OPEN for analytics and reporting review
      expect(inactiveEvent.canManagerAccess, isTrue, reason: 'Company Manager link must remain permanently active even when campaign is paused');

      // 2. Explicit Manager Access Revocation (isManagerActive: false)
      final revokedManagerEvent = inactiveEvent.copyWith(isManagerActive: false);
      expect(revokedManagerEvent.canManagerAccess, isFalse, reason: 'Manager access should only be blocked if explicitly revoked via isManagerActive');

      // 3. Fully Active Campaign
      final activeEvent = inactiveEvent.copyWith(isActive: true);
      expect(activeEvent.canPromoterAccess, isTrue);
      expect(activeEvent.canAgencyAccess, isTrue);
      expect(activeEvent.canManagerAccess, isTrue);
    });
  });
}
