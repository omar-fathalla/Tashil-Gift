// TAG-79: gift stock report as a read-only portal tab, scoped for /ep/ sessions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/core/widgets/portal_screen_header_card.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/company_portal/presentation/company_manager_portal_screen.dart';
import 'package:al_mraay/features/company_portal/presentation/company_prizes_stock_report_screen.dart';

EventModel _event(String id) => EventModel(
      id: id,
      eventName: 'Campaign $id',
      targetCompany: 'Adco',
      companySlug: 'adco',
      minimumSpend: 100,
      requiredProducts: const ['x'],
      customPrompt: 'p',
      startDate: DateTime(2026, 11, 1),
    );

Widget _app(Widget home) => ProviderScope(
      child: MaterialApp(locale: const Locale('ar'), home: home),
    );

Future<void> _desktop(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Gift stock tab (TAG-79)', () {
    test('report is read-only by default', () {
      const screen = CompanyPrizesStockReportScreen(
        lockedCompanySlug: 'adco',
        lockedCompanyName: 'Adco',
      );
      expect(screen.isReadOnly, isTrue);
      expect(screen.lockedEventId, isNull);
    });

    test('new nav strings are Arabic and English only (hi falls back to English)', () {
      final ar = AppStrings.fromLocale('ar');
      final en = AppStrings.fromLocale('en');
      final hi = AppStrings.fromLocale('hi');
      expect(ar.partnerNavGiftStock, 'مخزون الهدايا');
      expect(en.partnerNavGiftStock, 'Gift Stock');
      expect(hi.partnerNavGiftStock, en.partnerNavGiftStock);
      expect(hi.giftStockNavSubtitle, en.giftStockNavSubtitle);
      expect(hi.giftStockNavTooltip, en.giftStockNavTooltip);
    });

    test('scopeEventsToLock keeps only the locked campaign', () {
      final events = [_event('e1'), _event('e2'), _event('e3')];
      expect(CompanyPrizesStockReportScreen.scopeEventsToLock(events, null), hasLength(3));
      expect(CompanyPrizesStockReportScreen.scopeEventsToLock(events, ''), hasLength(3));
      final scoped = CompanyPrizesStockReportScreen.scopeEventsToLock(events, ' e2 ');
      expect(scoped.map((e) => e.id), ['e2']);
      expect(CompanyPrizesStockReportScreen.scopeEventsToLock(events, 'other'), isEmpty);
    });

    testWidgets('brand portal has 8 tabs, gift stock is index 7 and read-only', (tester) async {
      await _desktop(tester);
      await tester.pumpWidget(_app(const CompanyManagerPortalScreen(companySlug: 'adco')));
      await tester.pump();

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.destinations, hasLength(8));
      expect(find.text('مخزون الهدايا'), findsWidgets);

      await tester.tap(find.byIcon(Icons.inventory_2_outlined).first);
      await tester.pump();

      expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex, 7);
      final stock = tester.widget<CompanyPrizesStockReportScreen>(find.byType(CompanyPrizesStockReportScreen));
      expect(stock.isReadOnly, isTrue);
      expect(stock.isEmbedded, isTrue);
      expect(stock.lockedCompanySlug, 'adco');
    });

    testWidgets('ops portal has 5 tabs, gift stock is index 4 and read-only', (tester) async {
      await _desktop(tester);
      await tester.pumpWidget(_app(const CompanyManagerPortalScreen(companySlug: 'adco', isAgencyOpsMode: true)));
      await tester.pump();

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.destinations, hasLength(5));

      await tester.tap(find.byIcon(Icons.inventory_2_outlined).first);
      await tester.pump();

      expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex, 4);
      final stock = tester.widget<CompanyPrizesStockReportScreen>(find.byType(CompanyPrizesStockReportScreen));
      expect(stock.isReadOnly, isTrue);
    });

    testWidgets('unlocked report offers "all campaigns" and the movements ledger', (tester) async {
      await _desktop(tester);
      await tester.pumpWidget(_app(const Scaffold(
        body: CompanyPrizesStockReportScreen(
          lockedCompanySlug: 'adco',
          lockedCompanyName: 'Adco',
          isEmbedded: true,
        ),
      )));
      await tester.pump();

      expect(tester.widget<PortalScreenHeaderCard>(find.byType(PortalScreenHeaderCard)).showEventSelector, isTrue);
      expect(find.text(AppStrings.fromLocale('ar').allCampaignsOption), findsWidgets);
      expect(find.byIcon(Icons.history_edu_rounded), findsWidgets);
    });

    testWidgets('campaign-locked (/ep/) report hides other campaigns, "all campaigns" and movements', (tester) async {
      await _desktop(tester);
      await tester.pumpWidget(_app(const Scaffold(
        body: CompanyPrizesStockReportScreen(
          lockedCompanySlug: 'adco',
          lockedCompanyName: 'Adco',
          initialEventId: 'e1',
          lockedEventId: 'e1',
          isEmbedded: true,
        ),
      )));
      await tester.pump();

      expect(tester.widget<PortalScreenHeaderCard>(find.byType(PortalScreenHeaderCard)).showEventSelector, isFalse);
      expect(find.text(AppStrings.fromLocale('ar').allCampaignsOption), findsNothing);
      expect(find.text(AppStrings.fromLocale('ar').companyAllCampaigns), findsNothing);
      // Movements ledger segment and its entry points are gone.
      expect(find.byIcon(Icons.history_edu_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
