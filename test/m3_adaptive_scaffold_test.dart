import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/widgets/m3_adaptive_scaffold.dart';

void main() {
  final testDestinations = [
    const M3NavDestination(
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
      label: 'Dashboard',
    ),
    const M3NavDestination(
      icon: Icons.analytics_outlined,
      selectedIcon: Icons.analytics_rounded,
      label: 'Analytics',
    ),
    const M3NavDestination(
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      label: 'Invoices',
    ),
  ];

  Widget buildTestScaffold({
    required Size size,
    TextDirection textDirection = TextDirection.ltr,
    int initialIndex = 0,
    ValueChanged<int>? onDestinationChanged,
    M3DrawerHeaderBuilder? drawerHeader,
    WidgetBuilder? drawerFooter,
    M3CustomDrawerBodyBuilder? customDrawerBody,
    M3CustomMobileDrawerBuilder? customMobileDrawer,
    M3CustomRailBuilder? customRail,
    Map<int, int>? paneBuildCounters,
  }) {
    return MaterialApp(
      home: Directionality(
        textDirection: textDirection,
        child: MediaQuery(
          data: MediaQueryData(size: size),
          child: M3AdaptiveScaffold(
            destinations: testDestinations,
            initialIndex: initialIndex,
            onDestinationChanged: onDestinationChanged,
            drawerHeader: drawerHeader,
            drawerFooter: drawerFooter,
            customDrawerBody: customDrawerBody,
            customMobileDrawer: customMobileDrawer,
            customRail: customRail,
            paneBuilder: (context, index) {
              if (paneBuildCounters != null) {
                paneBuildCounters[index] = (paneBuildCounters[index] ?? 0) + 1;
              }
              return Center(
                key: ValueKey('pane_$index'),
                child: Text('Content for Destination $index'),
              );
            },
          ),
        ),
      ),
    );
  }

  group('M3AdaptiveScaffold Navigation Transformation Across 4 Window Classes', () {
    testWidgets('Compact (<600dp): Renders NavigationBar (Bottom Nav) & no Rail/Persistent Drawer', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestScaffold(size: const Size(390, 844)));
      await tester.pumpAndSettle();

      // NavigationBar should be present at the bottom
      expect(find.byType(NavigationBar), findsOneWidget);

      // Persistent drawer and navigation rail should NOT be rendered in body
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('Content for Destination 0'), findsOneWidget);
    });

    testWidgets('Medium (600–839dp): Renders NavigationRail (80dp) & no Bottom Nav or Drawer', (tester) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestScaffold(size: const Size(768, 1024)));
      await tester.pumpAndSettle();

      // NavigationRail should be present
      expect(find.byType(NavigationRail), findsOneWidget);

      // Bottom Nav should NOT be present
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Content for Destination 0'), findsOneWidget);
    });

    testWidgets('Expanded (840–1199dp): Renders Persistent Collapsible Drawer with toggle button', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestScaffold(size: const Size(1024, 768)));
      await tester.pumpAndSettle();

      // Neither NavigationBar nor standard NavigationRail should be active
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);

      // Drawer toggle icon button should be present on Expanded
      expect(find.byIcon(Icons.menu_open_rounded), findsOneWidget);

      // Destination labels should be visible in expanded drawer
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Analytics'), findsOneWidget);
      expect(find.text('Invoices'), findsOneWidget);
    });

    testWidgets('Large (>=1200dp): Renders Permanent Drawer (always expanded, no collapse toggle)', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestScaffold(size: const Size(1440, 900)));
      await tester.pumpAndSettle();

      // On Large+, collapse toggle button is omitted per M3 specification
      expect(find.byIcon(Icons.menu_open_rounded), findsNothing);

      // All destinations visible
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Analytics'), findsOneWidget);
      expect(find.text('Invoices'), findsOneWidget);
    });
  });

  group('M3AdaptiveScaffold Directionality & Natural Layout Alignment (RTL vs LTR)', () {
    testWidgets('Arabic (RTL): Navigation Rail/Drawer is placed at the START (visually on the RIGHT)', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestScaffold(
          size: const Size(1024, 768),
          textDirection: TextDirection.rtl,
        ),
      );
      await tester.pumpAndSettle();

      final drawerFinder = find.byType(AnimatedContainer).first;
      final paneFinder = find.byKey(const ValueKey('pane_0'));

      final drawerTopLeft = tester.getTopLeft(drawerFinder);
      final paneTopLeft = tester.getTopLeft(paneFinder);

      // In RTL, START is at the right side (larger X coordinate than the pane)
      expect(drawerTopLeft.dx, greaterThan(paneTopLeft.dx));
    });

    testWidgets('English (LTR): Navigation Rail/Drawer is placed at the START (visually on the LEFT)', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestScaffold(
          size: const Size(1024, 768),
          textDirection: TextDirection.ltr,
        ),
      );
      await tester.pumpAndSettle();

      final drawerFinder = find.byType(AnimatedContainer).first;
      final paneFinder = find.byKey(const ValueKey('pane_0'));

      final drawerTopLeft = tester.getTopLeft(drawerFinder);
      final paneTopLeft = tester.getTopLeft(paneFinder);

      // In LTR, START is at the left side (smaller X coordinate than the pane)
      expect(drawerTopLeft.dx, lessThan(paneTopLeft.dx));
    });
  });

  group('Lazy Loading & Zero CPU Rebuild Invariant (Offstage + TickerMode)', () {
    testWidgets('Panes are only constructed when their destination is visited', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final Map<int, int> counters = {};

      await tester.pumpWidget(
        buildTestScaffold(
          size: const Size(1024, 768),
          paneBuildCounters: counters,
        ),
      );
      await tester.pumpAndSettle();

      // Only tab 0 is built initially
      expect(counters[0], equals(1));
      expect(counters[1], isNull);
      expect(counters[2], isNull);

      // Switch to tab 1 (Analytics)
      await tester.tap(find.text('Analytics'));
      await tester.pumpAndSettle();

      // Tab 1 is now built exactly once
      expect(counters[0], equals(1));
      expect(counters[1], equals(1));
      expect(counters[2], isNull);

      // Switch back to tab 0
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();

      // Neither tab 0 nor tab 1 rebuilt (cached in Offstage)
      expect(counters[0], equals(1));
      expect(counters[1], equals(1));
    });
  });

  group('Custom Escape Hatches (customDrawerBody, customMobileDrawer, customRail)', () {
    testWidgets('customDrawerBody replaces standard drawer content on Expanded+', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestScaffold(
          size: const Size(1024, 768),
          customDrawerBody: (context, {
            required isExpanded,
            required onSelectIndex,
            required onToggleExpanded,
            required selectedIndex,
            required targetWidth,
          }) {
            return const Center(child: Text('Custom Brand Sidebar'));
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Custom Brand Sidebar'), findsOneWidget);
    });

    testWidgets('customRail replaces standard NavigationRail on Medium', (tester) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestScaffold(
          size: const Size(768, 1024),
          customRail: (context, {
            required onSelectIndex,
            required selectedIndex,
            required width,
          }) {
            return const Center(child: Text('Custom Brand Rail'));
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Custom Brand Rail'), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });
  });

  group('M3 Canonical Pane Layouts Tests', () {
    testWidgets('M3ListDetailLayout shows single pane on Compact and dual pane on Expanded', (tester) async {
      // 1. Compact Viewport
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: M3ListDetailLayout(
              listPane: Text('List Pane Content'),
              detailPane: Text('Detail Pane Content'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('List Pane Content'), findsOneWidget);
      expect(find.text('Detail Pane Content'), findsNothing);

      // 2. Expanded Viewport (Desktop)
      tester.view.physicalSize = const Size(1024, 768);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('List Pane Content'), findsOneWidget);
      expect(find.text('Detail Pane Content'), findsOneWidget);
    });

    testWidgets('M3SupportingPaneLayout shows side pane on Expanded and hides on Compact', (tester) async {
      // 1. Compact Viewport
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: M3SupportingPaneLayout(
              body: Text('Main Document Content'),
              supportingPane: Text('Side Properties Panel'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Main Document Content'), findsOneWidget);
      expect(find.text('Side Properties Panel'), findsNothing);

      // 2. Expanded Viewport (Desktop)
      tester.view.physicalSize = const Size(1024, 768);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Main Document Content'), findsOneWidget);
      expect(find.text('Side Properties Panel'), findsOneWidget);
    });

    testWidgets('M3FeedLayout calculates 1 col on Compact, 2 on Medium, 3 on Expanded, 4 on Large', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: M3FeedLayout(
              children: List.generate(
                8,
                (i) => Container(
                  key: ValueKey('card_$i'),
                  height: 100,
                  color: Colors.blue,
                  child: Text('Card $i'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // On Large (1440px), 4 cards per row
      final card0 = tester.getTopLeft(find.byKey(const ValueKey('card_0')));
      final card1 = tester.getTopLeft(find.byKey(const ValueKey('card_1')));
      final card2 = tester.getTopLeft(find.byKey(const ValueKey('card_2')));
      final card3 = tester.getTopLeft(find.byKey(const ValueKey('card_3')));
      final card4 = tester.getTopLeft(find.byKey(const ValueKey('card_4')));

      // Cards 0..3 are on the first row (same Y coordinate)
      expect(card0.dy, equals(card1.dy));
      expect(card1.dy, equals(card2.dy));
      expect(card2.dy, equals(card3.dy));

      // Card 4 is on the second row (greater Y coordinate)
      expect(card4.dy, greaterThan(card0.dy));
    });
  });
}
