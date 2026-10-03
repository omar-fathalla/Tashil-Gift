import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/utils/responsive.dart';
import 'package:al_mraay/core/widgets/m3_adaptive_scaffold.dart';

void main() {
  group('M3 Layout Engine Unit Tests (Window Size Classes & 8dp Grid)', () {
    test('Compact Window Class (< 600dp) metrics calculation', () {
      final metrics = M3LayoutMetrics.fromDimensions(width: 390.0, height: 844.0);

      expect(metrics.windowClass, equals(M3WindowSizeClass.compact));
      expect(metrics.isCompact, isTrue);
      expect(metrics.isMobile, isTrue);
      expect(metrics.isMedium, isFalse);
      expect(metrics.isTablet, isFalse);
      expect(metrics.isDesktop, isFalse);

      expect(metrics.columns, equals(4));
      expect(metrics.margin, equals(16.0));
      expect(metrics.gutter, equals(16.0));
      expect(metrics.navigationType, equals(M3NavigationType.bottomNavigationBar));
    });

    test('Medium Window Class (600 - 839dp) metrics calculation', () {
      final metrics = M3LayoutMetrics.fromDimensions(width: 768.0, height: 1024.0);

      expect(metrics.windowClass, equals(M3WindowSizeClass.medium));
      expect(metrics.isCompact, isFalse);
      expect(metrics.isMobile, isFalse);
      expect(metrics.isMedium, isTrue);
      expect(metrics.isTablet, isTrue);
      expect(metrics.isDesktop, isFalse);

      expect(metrics.columns, equals(8));
      expect(metrics.margin, equals(24.0));
      expect(metrics.gutter, equals(24.0));
      expect(metrics.navigationType, equals(M3NavigationType.navigationRail));
    });

    test('Expanded Window Class (840 - 1199dp) metrics calculation', () {
      final metrics = M3LayoutMetrics.fromDimensions(width: 1024.0, height: 768.0);

      expect(metrics.windowClass, equals(M3WindowSizeClass.expanded));
      expect(metrics.isCompact, isFalse);
      expect(metrics.isMedium, isFalse);
      expect(metrics.isExpanded, isTrue);
      expect(metrics.isDesktop, isTrue);

      expect(metrics.columns, equals(12));
      expect(metrics.margin, equals(24.0));
      expect(metrics.gutter, equals(24.0));
      expect(metrics.navigationType, equals(M3NavigationType.navigationDrawer));
    });

    test('Large Window Class (1200 - 1599dp) metrics calculation', () {
      final metrics = M3LayoutMetrics.fromDimensions(width: 1440.0, height: 900.0);

      expect(metrics.windowClass, equals(M3WindowSizeClass.large));
      expect(metrics.isLarge, isTrue);
      expect(metrics.isDesktop, isTrue);

      expect(metrics.columns, equals(12));
      expect(metrics.margin, equals(32.0));
      expect(metrics.gutter, equals(24.0));
      expect(metrics.navigationType, equals(M3NavigationType.persistentDrawer));
    });

    test('Extra Large Window Class (>= 1600dp) metrics calculation', () {
      final metrics = M3LayoutMetrics.fromDimensions(width: 1920.0, height: 1080.0);

      expect(metrics.windowClass, equals(M3WindowSizeClass.extraLarge));
      expect(metrics.isExtraLarge, isTrue);
      expect(metrics.isDesktop, isTrue);

      expect(metrics.columns, equals(12));
      expect(metrics.margin, equals(64.0));
      expect(metrics.gutter, equals(24.0));
      expect(metrics.navigationType, equals(M3NavigationType.persistentDrawer));
    });

    test('M3Spacing constants adhere strictly to 8dp baseline grid', () {
      expect(M3Spacing.xxs, equals(4.0));
      expect(M3Spacing.xs, equals(8.0));
      expect(M3Spacing.sm, equals(16.0));
      expect(M3Spacing.md, equals(24.0));
      expect(M3Spacing.lg, equals(32.0));
      expect(M3Spacing.xl, equals(40.0));
      expect(M3Spacing.xxl, equals(48.0));
      expect(M3Spacing.xxxl, equals(64.0));
    });

    test('M3SpacingTokens official scale and semantic tokens adhere to M3 specifications', () {
      expect(M3SpacingTokens.space0, equals(0.0));
      expect(M3SpacingTokens.space1, equals(4.0));
      expect(M3SpacingTokens.space2, equals(8.0));
      expect(M3SpacingTokens.space3, equals(12.0));
      expect(M3SpacingTokens.space4, equals(16.0));
      expect(M3SpacingTokens.space5, equals(20.0));
      expect(M3SpacingTokens.space6, equals(24.0));
      expect(M3SpacingTokens.space7, equals(28.0));
      expect(M3SpacingTokens.space8, equals(32.0));
      expect(M3SpacingTokens.space10, equals(40.0));
      expect(M3SpacingTokens.space12, equals(48.0));
      expect(M3SpacingTokens.space16, equals(64.0));

      // Semantic tokens
      expect(M3SpacingTokens.inlineIconGap, equals(M3SpacingTokens.space1));
      expect(M3SpacingTokens.siblingGap, equals(M3SpacingTokens.space2));
      expect(M3SpacingTokens.cardInternalPadding, equals(M3SpacingTokens.space4));
      expect(M3SpacingTokens.sectionVerticalGap, equals(M3SpacingTokens.space6));
      expect(M3SpacingTokens.minTouchTarget, equals(M3SpacingTokens.space12));

      // M3Spacing bridge verification
      expect(M3Spacing.xxs, equals(M3SpacingTokens.space1));
      expect(M3Spacing.xs, equals(M3SpacingTokens.space2));
      expect(M3Spacing.sm, equals(M3SpacingTokens.space4));
      expect(M3Spacing.md, equals(M3SpacingTokens.space6));
      expect(M3Spacing.lg, equals(M3SpacingTokens.space8));
      expect(M3Spacing.xl, equals(M3SpacingTokens.space10));
      expect(M3Spacing.xxl, equals(M3SpacingTokens.space12));
      expect(M3Spacing.xxxl, equals(M3SpacingTokens.space16));
    });
  });

  group('M3 Layout Widgets Tests', () {
    testWidgets('M3ResponsiveBuilder exposes accurate layout metrics', (tester) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      M3LayoutMetrics? capturedMetrics;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: M3ResponsiveBuilder(
              builder: (context, layout) {
                capturedMetrics = layout;
                return Text('WindowClass: ${layout.windowClass.name}');
              },
            ),
          ),
        ),
      );

      expect(capturedMetrics, isNotNull);
      expect(capturedMetrics!.windowClass, equals(M3WindowSizeClass.medium));
      expect(find.text('WindowClass: medium'), findsOneWidget);
    });

    testWidgets('M3AdaptiveLayout switches between Compact, Medium and Expanded', (tester) async {
      // 1. Compact Viewport
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: M3AdaptiveLayout(
              compact: Text('Compact View'),
              medium: Text('Medium View'),
              expanded: Text('Expanded View'),
            ),
          ),
        ),
      );

      expect(find.text('Compact View'), findsOneWidget);
      expect(find.text('Medium View'), findsNothing);
      expect(find.text('Expanded View'), findsNothing);

      // 2. Medium Viewport (Tablet)
      tester.view.physicalSize = const Size(768, 1024);
      await tester.pump();

      expect(find.text('Medium View'), findsOneWidget);
      expect(find.text('Compact View'), findsNothing);

      // 3. Expanded Viewport (Desktop)
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pump();

      expect(find.text('Expanded View'), findsOneWidget);
      expect(find.text('Medium View'), findsNothing);
    });

    testWidgets('M3ContentBoundary constrains max width on Ultra-wide display', (tester) async {
      tester.view.physicalSize = const Size(2560, 1440);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: M3ContentBoundary(
              maxWidth: 1200.0,
              child: SizedBox(
                key: ValueKey('constrained_child'),
                height: 200,
                child: Text('Bounded Content'),
              ),
            ),
          ),
        ),
      );

      final renderBox = tester.renderObject(find.byKey(const ValueKey('constrained_child'))) as RenderBox;
      // In ultra-wide (2560px), padding is 64dp on each side (total 128dp), max width is 1200.
      expect(renderBox.size.width, lessThanOrEqualTo(1200.0));
      expect(find.text('Bounded Content'), findsOneWidget);
    });

    testWidgets('Responsive backward compatibility preserves legacy calls', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return Text('isMobile: ${Responsive.isMobile(context)}');
              },
            ),
          ),
        ),
      );

      expect(find.text('isMobile: true'), findsOneWidget);
    });

    testWidgets('M3ListDetailLayout renders single pane on Compact and dual pane on Expanded', (tester) async {
      // 1. Compact Viewport (< 840dp)
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: M3ListDetailLayout(
              listPane: Text('Invoices List Pane'),
              detailPane: Text('Invoice Inspection Detail Pane'),
            ),
          ),
        ),
      );

      // Compact only renders listPane
      expect(find.text('Invoices List Pane'), findsOneWidget);
      expect(find.text('Invoice Inspection Detail Pane'), findsNothing);

      // 2. Expanded Viewport (>= 840dp / Desktop)
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pump();

      // Expanded renders both listPane and detailPane simultaneously
      expect(find.text('Invoices List Pane'), findsOneWidget);
      expect(find.text('Invoice Inspection Detail Pane'), findsOneWidget);
    });
  });
}
