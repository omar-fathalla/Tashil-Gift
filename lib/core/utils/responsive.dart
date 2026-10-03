import 'package:flutter/material.dart';

export '../theme/m3_spacing_tokens.dart';
import '../theme/m3_spacing_tokens.dart';

/// Official Material Design 3 Window Size Classes.
///
/// Ref: https://m3.material.io/foundations/layout/applying-layout/window-size-classes
enum M3WindowSizeClass {
  /// Width < 600dp (Standard smartphones in portrait, small foldables closed).
  ///
  /// Columns: 4 | Margins: 16dp | Gutters: 16dp | Navigation: Bottom Navigation Bar / Drawer.
  compact,

  /// 600dp <= Width < 840dp (Small tablets, unfolded foldables, large phones in landscape).
  ///
  /// Columns: 8 | Margins: 24dp | Gutters: 24dp | Navigation: Navigation Rail.
  medium,

  /// 840dp <= Width < 1200dp (Laptops, large tablets in landscape).
  ///
  /// Columns: 12 | Margins: 24dp | Gutters: 24dp | Navigation: Navigation Drawer / Persistent Sidebar.
  expanded,

  /// 1200dp <= Width < 1600dp (Desktop displays, external monitors).
  ///
  /// Columns: 12 | Margins: Dynamic (Centering) | Navigation: Persistent Navigation Drawer.
  large,

  /// Width >= 1600dp (Ultra-wide displays, 4K monitors).
  ///
  /// Columns: 12 | Max-Width Containment (1280-1440dp) with generous symmetric margins.
  extraLarge,
}

/// Recommended Material Design 3 Navigation Presentation by screen tier.
enum M3NavigationType {
  /// Bottom Navigation Bar (Compact < 600dp).
  bottomNavigationBar,

  /// Slim Navigation Rail with icon + tooltips (Medium 600 - 839dp).
  navigationRail,

  /// Dismissible / Modal Navigation Drawer (Expanded 840 - 1199dp).
  navigationDrawer,

  /// Permanent, always-visible Navigation Drawer (Large / Extra Large >= 1200dp).
  persistentDrawer,
}

/// Spacing system constants strictly adhering to Material Design 3 8dp baseline grid.
///
/// Ref: https://m3.material.io/foundations/layout/understanding-layout/spacing
abstract class M3Spacing {
  /// Micro-spacing (4dp) - reserved exclusively for tight icon-label alignment or badge offsets.
  static const double xxs = M3SpacingTokens.space1;

  /// Baseline unit (8dp) - fundamental M3 grid multiplier.
  static const double xs = M3SpacingTokens.space2;

  /// Standard compact margin/gutter (16dp = 2 * 8dp).
  static const double sm = M3SpacingTokens.space4;

  /// Standard expanded margin/gutter (24dp = 3 * 8dp).
  static const double md = M3SpacingTokens.space6;

  /// Large container padding or section spacing (32dp = 4 * 8dp).
  static const double lg = M3SpacingTokens.space8;

  /// Hero section spacing (40dp = 5 * 8dp).
  static const double xl = M3SpacingTokens.space10;

  /// Dialog and prominent card padding (48dp = 6 * 8dp).
  static const double xxl = M3SpacingTokens.space12;

  /// Extra generous layout margin (64dp = 8 * 8dp).
  static const double xxxl = M3SpacingTokens.space16;

  // Reusable EdgeInsets based on 8dp grid:
  static const EdgeInsets allXs = EdgeInsets.all(xs);
  static const EdgeInsets allSm = EdgeInsets.all(sm);
  static const EdgeInsets allMd = EdgeInsets.all(md);
  static const EdgeInsets allLg = EdgeInsets.all(lg);

  static const EdgeInsets horizontalSm = EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets horizontalMd = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets horizontalLg = EdgeInsets.symmetric(horizontal: lg);

  static const EdgeInsets verticalXs = EdgeInsets.symmetric(vertical: xs);
  static const EdgeInsets verticalSm = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets verticalMd = EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets verticalLg = EdgeInsets.symmetric(vertical: lg);
}

/// Comprehensive layout calculation metrics resolved for a given width and height.
class M3LayoutMetrics {
  final double width;
  final double height;
  final M3WindowSizeClass windowClass;

  const M3LayoutMetrics({
    required this.width,
    required this.height,
    required this.windowClass,
  });

  /// Factory resolving metrics directly from dimensions.
  factory M3LayoutMetrics.fromDimensions({
    required double width,
    required double height,
  }) {
    final M3WindowSizeClass windowClass;
    if (width < 600.0) {
      windowClass = M3WindowSizeClass.compact;
    } else if (width < 840.0) {
      windowClass = M3WindowSizeClass.medium;
    } else if (width < 1200.0) {
      windowClass = M3WindowSizeClass.expanded;
    } else if (width < 1600.0) {
      windowClass = M3WindowSizeClass.large;
    } else {
      windowClass = M3WindowSizeClass.extraLarge;
    }

    return M3LayoutMetrics(
      width: width,
      height: height,
      windowClass: windowClass,
    );
  }

  // Window Class Boolean Flags:
  bool get isCompact => windowClass == M3WindowSizeClass.compact;
  bool get isMedium => windowClass == M3WindowSizeClass.medium;
  bool get isExpanded => windowClass == M3WindowSizeClass.expanded;
  bool get isLarge => windowClass == M3WindowSizeClass.large;
  bool get isExtraLarge => windowClass == M3WindowSizeClass.extraLarge;

  // High-level Convenience Aliases:
  /// True if device is Compact (< 600dp).
  bool get isMobile => isCompact;

  /// True if device is Medium (600 - 839dp).
  bool get isTablet => isMedium;

  /// True if device is Expanded or larger (>= 840dp).
  bool get isDesktop => isExpanded || isLarge || isExtraLarge;

  /// Recommended M3 responsive column count.
  ///
  /// Compact: 4 columns | Medium: 8 columns | Expanded/Large/ExtraLarge: 12 columns.
  int get columns {
    switch (windowClass) {
      case M3WindowSizeClass.compact:
        return 4;
      case M3WindowSizeClass.medium:
        return 8;
      case M3WindowSizeClass.expanded:
      case M3WindowSizeClass.large:
      case M3WindowSizeClass.extraLarge:
        return 12;
    }
  }

  /// Recommended M3 screen edge margin.
  double get margin {
    switch (windowClass) {
      case M3WindowSizeClass.compact:
        return M3Spacing.sm; // 16dp
      case M3WindowSizeClass.medium:
      case M3WindowSizeClass.expanded:
        return M3Spacing.md; // 24dp
      case M3WindowSizeClass.large:
        return M3Spacing.lg; // 32dp
      case M3WindowSizeClass.extraLarge:
        return M3Spacing.xxxl; // 64dp
    }
  }

  /// Recommended M3 gutter between columns/cards.
  double get gutter {
    switch (windowClass) {
      case M3WindowSizeClass.compact:
        return M3Spacing.sm; // 16dp
      case M3WindowSizeClass.medium:
      case M3WindowSizeClass.expanded:
      case M3WindowSizeClass.large:
      case M3WindowSizeClass.extraLarge:
        return M3Spacing.md; // 24dp
    }
  }

  /// Canonical M3 Navigation Presentation for this screen class.
  M3NavigationType get navigationType {
    switch (windowClass) {
      case M3WindowSizeClass.compact:
        return M3NavigationType.bottomNavigationBar;
      case M3WindowSizeClass.medium:
        return M3NavigationType.navigationRail;
      case M3WindowSizeClass.expanded:
        return M3NavigationType.navigationDrawer;
      case M3WindowSizeClass.large:
      case M3WindowSizeClass.extraLarge:
        return M3NavigationType.persistentDrawer;
    }
  }

  /// Recommended content maximum width to prevent infinite stretching on ultra-wide monitors.
  double get contentMaxWidth => 1360.0;
}

/// Static helper for instant M3 layout resolution anywhere in Flutter widget tree.
abstract class M3Layout {
  /// Resolves [M3LayoutMetrics] from the ambient [BuildContext].
  static M3LayoutMetrics of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return M3LayoutMetrics.fromDimensions(
      width: size.width,
      height: size.height,
    );
  }

  /// Resolves [M3LayoutMetrics] from raw width and optional height.
  static M3LayoutMetrics fromWidth(double width, {double height = 0.0}) {
    return M3LayoutMetrics.fromDimensions(
      width: width,
      height: height,
    );
  }

  /// Resolves [M3LayoutMetrics] from [BoxConstraints].
  static M3LayoutMetrics fromConstraints(BoxConstraints constraints) {
    return M3LayoutMetrics.fromDimensions(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
    );
  }

  /// Returns true if screen width is Compact (< 600dp).
  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600.0;

  /// Returns true if screen width is Medium (600 - 839dp).
  static bool isMedium(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= 600.0 && w < 840.0;
  }

  /// Returns true if screen width is Expanded (840 - 1199dp).
  static bool isExpanded(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= 840.0 && w < 1200.0;
  }

  /// Returns true if screen width is Large (1200 - 1599dp).
  static bool isLarge(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= 1200.0 && w < 1600.0;
  }

  /// Returns true if screen width is Extra-Large (>= 1600dp).
  static bool isExtraLarge(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1600.0;
}

/// Builder widget exposing [M3LayoutMetrics] dynamically to its child.
class M3ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, M3LayoutMetrics layout) builder;

  const M3ResponsiveBuilder({
    super.key,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = constraints.hasBoundedWidth
            ? M3Layout.fromConstraints(constraints)
            : M3Layout.of(context);
        return builder(context, layout);
      },
    );
  }
}

/// Canonical M3 Adaptive Layout switcher (Compact / Medium / Expanded / Large).
class M3AdaptiveLayout extends StatelessWidget {
  /// Widget for Compact tier (< 600dp - smartphones).
  final Widget compact;

  /// Widget for Medium tier (600 - 839dp - tablets/foldables).
  /// Falls back to [expanded] or [compact] if omitted.
  final Widget? medium;

  /// Widget for Expanded tier (840 - 1199dp - laptops).
  final Widget expanded;

  /// Optional widget for Large tier (1200 - 1599dp). Falls back to [expanded].
  final Widget? large;

  /// Optional widget for Extra Large tier (>= 1600dp). Falls back to [large] or [expanded].
  final Widget? extraLarge;

  const M3AdaptiveLayout({
    super.key,
    required this.compact,
    this.medium,
    required this.expanded,
    this.large,
    this.extraLarge,
  });

  @override
  Widget build(BuildContext context) {
    return M3ResponsiveBuilder(
      builder: (context, layout) {
        switch (layout.windowClass) {
          case M3WindowSizeClass.compact:
            return compact;
          case M3WindowSizeClass.medium:
            return medium ?? expanded;
          case M3WindowSizeClass.expanded:
            return expanded;
          case M3WindowSizeClass.large:
            return large ?? expanded;
          case M3WindowSizeClass.extraLarge:
            return extraLarge ?? large ?? expanded;
        }
      },
    );
  }
}

/// Material Design 3 Content Boundary (Max-Width Containment).
///
/// Implements the M3 rule for large/ultra-wide screens:
/// Prevents text lines, charts, and tables from stretching infinitely across 2000px+ displays.
/// Centers content smoothly with symmetric breathing margins.
class M3ContentBoundary extends StatelessWidget {
  final Widget child;

  /// Maximum allowed width for content before symmetrical margins expand.
  /// Defaults to 1360.0dp.
  final double maxWidth;

  /// Optional custom padding. If null, applies automatic M3 window margin.
  final EdgeInsetsGeometry? padding;

  /// Alignment of content inside the boundary. Defaults to top-center.
  final AlignmentGeometry alignment;

  const M3ContentBoundary({
    super.key,
    required this.child,
    this.maxWidth = 1360.0,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    return M3ResponsiveBuilder(
      builder: (context, layout) {
        final effectivePadding = padding ?? EdgeInsets.symmetric(horizontal: layout.margin);

        return Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: effectivePadding,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Backward-compatible [Responsive] widget preserving existing legacy API
/// while internally utilizing the formal M3 responsive engine.
class Responsive extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget desktop;

  const Responsive({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  // Screen breakpoints adhering to M3:
  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600.0;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= 600.0 && w < 840.0;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 840.0;

  @override
  Widget build(BuildContext context) {
    return M3AdaptiveLayout(
      compact: mobile,
      medium: tablet ?? mobile,
      expanded: desktop,
    );
  }
}
