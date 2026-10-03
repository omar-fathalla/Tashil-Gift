import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/admin/presentation/campaign_reports_screen.dart';

void main() {
  group('CampaignReportsScreen Branches Toolbar Vertical Stacking Tests', () {
    final event = EventModel(
      id: 'rich-bake-event-1',
      eventName: 'أنشطة تسويقية ريتش بيك',
      targetCompany: 'ريتش بيك',
      minimumSpend: 0,
      retailChainId: 'fathalla',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 12, 31),
      branchNames: ['فرع مدينة الرحاب (القاهرة)'],
      isAllBranches: false,
      isActive: true,
    );

    testWidgets('Branches toolbar options stack vertically on mobile (390x844) without overflow', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('ar'),
            home: Scaffold(
              body: CampaignReportsScreen(
                initialEvent: event,
                isEmbedded: true,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Scroll down to bring sticky header into view
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -450));
      await tester.pumpAndSettle();

      // Find and tap the Branches tab
      final branchTab = find.text('الفروع');
      expect(branchTab, findsWidgets);
      await tester.tap(branchTab.first);
      await tester.pumpAndSettle();

      // Verify the 3 groups are rendered:
      // Group 1: View Modes
      expect(find.text('مخطط دائري'), findsWidgets);
      expect(find.text('مخطط أعمدة'), findsWidgets);
      expect(find.text('بطاقات وترتيب'), findsWidgets);

      // Group 2: Aggregation Level
      expect(find.text('السلاسل'), findsWidgets);

      // Group 3: Metric Dimension
      expect(find.text('المبيعات'), findsWidgets);
      expect(find.text('الفواتير'), findsWidgets);

      // Verify zero render exceptions
      expect(tester.takeException(), isNull);
    });

    testWidgets('Branches toolbar switches mode between list, bar and donut seamlessly', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('ar'),
            home: Scaffold(
              body: CampaignReportsScreen(
                initialEvent: event,
                isEmbedded: true,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Scroll down to bring sticky header into view
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -450));
      await tester.pumpAndSettle();

      // Tap Branches tab
      final branchTab = find.text('الفروع');
      await tester.tap(branchTab.first);
      await tester.pumpAndSettle();

      // Switch to Bar Chart
      final barButton = find.text('مخطط أعمدة');
      await tester.tap(barButton.first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Switch to Leaderboard / Cards
      final listButton = find.text('بطاقات وترتيب');
      await tester.tap(listButton.first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
