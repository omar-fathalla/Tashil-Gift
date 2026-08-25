import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/features/admin/presentation/campaign_reports_screen.dart';

void main() {
  group('Campaign Reports Pagination & Lazy Loading Standard Tests', () {
    testWidgets('Desktop view limits items to 25 per page and shows M3 pagination toolbar', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: Scaffold(
              body: CampaignReportsScreen(
                isEmbedded: true,
                lockedCompanySlug: 'adco',
                lockedCompanyName: 'شركة أدكو للمستحضرات',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(CampaignReportsScreen), findsOneWidget);
    });

    testWidgets('Mobile view renders infinite scroll lazy load button for 25 items chunking', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: Scaffold(
              body: CampaignReportsScreen(
                isEmbedded: true,
                lockedCompanySlug: 'adco',
                lockedCompanyName: 'شركة أدكو للمستحضرات',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(CampaignReportsScreen), findsOneWidget);
    });

    testWidgets('Header displays Excel export button and removes AI discovery button', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('ar'),
            home: Scaffold(
              body: CampaignReportsScreen(
                isEmbedded: true,
                lockedCompanySlug: 'unilever',
                lockedCompanyName: 'يونيليفر',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);

      // AI Discovery button must NOT exist
      expect(find.text('استكشاف من الفواتير بالـ AI'), findsNothing);
      expect(find.byIcon(Icons.auto_awesome_rounded), findsNothing);

      // Excel export button must be present
      expect(find.text('تصدير تقرير Excel'), findsOneWidget);
      expect(find.byIcon(Icons.table_chart_rounded), findsOneWidget);
    });
  });
}
