import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/features/company_portal/presentation/company_manager_portal_screen.dart';
import 'package:al_mraay/features/admin/presentation/campaign_reports_screen.dart';
import 'package:al_mraay/features/validation/presentation/invoices_log_screen.dart';

void main() {
  group('Company Manager Portal Smartphone & Responsive Viewport Tests', () {
    const viewports = [
      {'name': 'Compact Mobile (360x640)', 'size': Size(360, 640)},
      {'name': 'Standard Smartphone (390x844)', 'size': Size(390, 844)},
      {'name': 'Large Phone (428x926)', 'size': Size(428, 926)},
      {'name': 'Tablet Portrait (768x1024)', 'size': Size(768, 1024)},
      {'name': 'Desktop (1280x800)', 'size': Size(1280, 800)},
    ];

    for (final vp in viewports) {
      final name = vp['name'] as String;
      final size = vp['size'] as Size;

      testWidgets('Renders $name without RenderFlex overflow in Arabic', (tester) async {
        tester.view.physicalSize = size;
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

        // 1. Verify Reports tab renders smoothly
        expect(find.byType(CompanyManagerPortalScreen), findsOneWidget);
        expect(find.byType(CampaignReportsScreen), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 2. Switch to Invoices Log & Audit Tab
        final invoicesTab = find.byIcon(Icons.receipt_long_rounded).first;
        await tester.tap(invoicesTab);
        await tester.pump();

        // 3. Verify InvoicesLogScreen renders smoothly
        expect(find.byType(InvoicesLogScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Renders $name without RenderFlex overflow in English', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              locale: Locale('en'),
              home: CompanyManagerPortalScreen(
                companySlug: 'adco',
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.byType(CompanyManagerPortalScreen), findsOneWidget);
        expect(tester.takeException(), isNull);

        final invoicesTab = find.byIcon(Icons.receipt_long_rounded).first;
        await tester.tap(invoicesTab);
        await tester.pump();

        expect(find.byType(InvoicesLogScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
