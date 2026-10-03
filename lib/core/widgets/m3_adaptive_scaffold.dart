import 'package:flutter/material.dart';

import '../utils/responsive.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Material Design 3 — Adaptive Scaffold Architecture
// ─────────────────────────────────────────────────────────────────────────────
//
// Official M3 Scaffold Reference:
//   • Scaffold Overview : https://m3.material.io/foundations/layout/scaffold/overview
//   • Scaffold Bars     : https://m3.material.io/foundations/layout/scaffold/bars
//   • Scaffold Rails    : https://m3.material.io/foundations/layout/scaffold/rails
//   • Scaffold Panes    : https://m3.material.io/foundations/layout/scaffold/panes
//
// ─── Architectural Principles ────────────────────────────────────────────────
//
//  ┌──────────────────────────────────────────────────────────┐
//  │                      TOP BAR (Bar)                       │  ← Permanent
//  ├──────────┬───────────────────────────────────────────────┤
//  │          │                                               │
//  │   RAIL   │              PANE(S)                          │  ← Rail: Permanent
//  │   or     │         (Mutable Content)                     │     Panes: Mutable
//  │  DRAWER  │                                               │
//  │          │                                               │
//  ├──────────┴───────────────────────────────────────────────┤
//  │                   BOTTOM BAR (Bar)                       │  ← Permanent (Compact only)
//  └──────────────────────────────────────────────────────────┘
//
//  Bars & Rails  = PERMANENT — provide stability, wayfinding, "where am I?"
//  Panes         = MUTABLE   — the actual content that changes on navigation
//
//  Navigation Transformation by Window Size Class:
//    Compact  (< 600dp)  → Bottom Navigation Bar / Modal Drawer
//    Medium   (600-839dp) → Navigation Rail (80dp)
//    Expanded (≥ 840dp)   → Navigation Drawer (256dp+)
//
// ─────────────────────────────────────────────────────────────────────────────

/// A navigation destination for [M3AdaptiveScaffold].
///
/// Carries the visual metadata needed to render as a
/// [BottomNavigationBarItem], a [NavigationRailDestination],
/// or a [NavigationDrawer] tile — depending on the active window class.
class M3NavDestination {
  /// Icon shown when this destination is NOT selected.
  final IconData icon;

  /// Icon shown when this destination IS selected.
  final IconData selectedIcon;

  /// Short label shown beneath the icon (Bottom Bar & Rail) or beside it (Drawer).
  final String label;

  /// Longer description shown in Drawer subtitle rows and hover tooltips.
  final String? subtitle;

  /// Contextual tooltip string for Navigation Rail hover affordance.
  final String? tooltip;

  /// Optional semantic accent color for theming this destination's indicator.
  final Color? accentColor;

  /// Optional leading badge count (e.g. unread notifications).
  final int? badgeCount;

  const M3NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.subtitle,
    this.tooltip,
    this.accentColor,
    this.badgeCount,
  });
}

/// Signature for building individual pane content for a destination index.
///
/// The scaffold calls this lazily — only when a destination is first selected.
typedef M3PaneBuilder = Widget Function(BuildContext context, int index);

/// Signature for building the Drawer header area (logo, company name, etc.).
typedef M3DrawerHeaderBuilder = Widget Function(
  BuildContext context,
  bool isExpanded,
);

/// Signature for building a fully custom persistent drawer/sidebar body.
///
/// Receives the current [selectedIndex], the [isExpanded] state, the
/// computed [targetWidth], and [onSelectIndex] callback.
/// Return a complete `Widget` that fills the drawer column.
typedef M3CustomDrawerBodyBuilder = Widget Function(
  BuildContext context, {
  required int selectedIndex,
  required bool isExpanded,
  required double targetWidth,
  required ValueChanged<int> onSelectIndex,
  required VoidCallback onToggleExpanded,
});

/// Signature for building a fully custom modal drawer (Compact tier).
typedef M3CustomMobileDrawerBuilder = Widget Function(
  BuildContext context, {
  required int selectedIndex,
  required ValueChanged<int> onSelectIndex,
});

/// Signature for building a fully custom navigation rail (Medium tier).
typedef M3CustomRailBuilder = Widget Function(
  BuildContext context, {
  required int selectedIndex,
  required double width,
  required ValueChanged<int> onSelectIndex,
});

// ─────────────────────────────────────────────────────────────────────────────
// M3AdaptiveScaffold
// ─────────────────────────────────────────────────────────────────────────────

/// The canonical Material Design 3 Adaptive Scaffold.
///
/// Implements the full M3 Scaffold architecture with:
///  - **Bars**: Top App Bar (always present) + Bottom Navigation Bar (Compact only).
///  - **Rails**: Navigation Rail (Medium) / Navigation Drawer (Expanded+).
///  - **Panes**: Lazily-loaded mutable content that fills the remaining space.
///
/// Navigation automatically transforms across the three tiers:
///
/// ```
/// Compact (< 600dp)  ──→  Bottom Nav Bar + Modal Drawer
/// Medium (600–839dp) ──→  Navigation Rail (80dp)
/// Expanded (≥ 840dp) ──→  Persistent Navigation Drawer (256dp–280dp)
/// ```
///
/// Directionality is handled automatically:
///  - **Arabic (RTL)**: Rail/Drawer appears on the RIGHT.
///  - **English/Hindi (LTR)**: Rail/Drawer appears on the LEFT.
///
/// The Rail/Drawer is always the **first child** of the parent [Row],
/// so Flutter's ambient [Directionality] handles mirroring automatically.
class M3AdaptiveScaffold extends StatefulWidget {
  /// The navigation destinations shown in Bar / Rail / Drawer.
  ///
  /// Must contain between 3 and 7 destinations (M3 guideline).
  final List<M3NavDestination> destinations;

  /// Builder that lazily creates pane content for each destination index.
  ///
  /// Called only once per destination. The result is cached and
  /// shown/hidden via [Offstage] + [TickerMode] for instant switching.
  final M3PaneBuilder paneBuilder;

  /// Optional builder for the Drawer header section (logo, title, etc.).
  /// Receives `isExpanded` — true for full drawer, false for slim rail icon.
  final M3DrawerHeaderBuilder? drawerHeader;

  /// Optional builder for the Drawer footer section (settings, help, logout).
  final WidgetBuilder? drawerFooter;

  /// Optional **fully custom** persistent drawer body builder.
  ///
  /// When provided, replaces the default `NavigationDrawer` destinations list
  /// with fully custom content. Use this for rich, domain-specific sidebars
  /// (e.g. CompanyManagerPortalScreen's gradient tiles, campaign badges, etc.)
  /// while still benefiting from the scaffold's navigation transformation.
  final M3CustomDrawerBodyBuilder? customDrawerBody;

  /// Optional **fully custom** modal drawer widget for Compact tier.
  ///
  /// When provided, replaces the default `NavigationDrawer` with a custom
  /// `Drawer` widget. The builder receives selection state and callbacks.
  final M3CustomMobileDrawerBuilder? customMobileDrawer;

  /// Optional **fully custom** navigation rail widget for Medium tier.
  ///
  /// When provided, replaces the default `NavigationRail` with a custom
  /// widget. The builder receives selection state, rail width, and callbacks.
  final M3CustomRailBuilder? customRail;

  /// The initial destination index. Defaults to 0.
  final int initialIndex;

  /// The app bar to display at the top. If null, no app bar is shown.
  final PreferredSizeWidget? appBar;

  /// Optional FAB, placed in Rail (above destinations) or Scaffold.
  final Widget? floatingActionButton;

  /// FAB location for Compact tier. Defaults to [FloatingActionButtonLocation.endFloat].
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  /// Width of the expanded Navigation Drawer. Must be 256dp–360dp per M3.
  /// Defaults to 264dp.
  final double drawerWidth;

  /// Width of the Navigation Rail. Must be 72dp–80dp per M3.
  /// Defaults to 80dp.
  final double railWidth;

  /// Duration for the Drawer expand/collapse animation.
  /// Defaults to 200ms (M3 standard).
  final Duration animationDuration;

  /// Curve for the Drawer expand/collapse animation.
  /// Defaults to [Curves.fastOutSlowIn] (M3 standard).
  final Curve animationCurve;

  /// Background color. Defaults to [ColorScheme.surface].
  final Color? backgroundColor;

  /// Called whenever the selected destination changes.
  final ValueChanged<int>? onDestinationChanged;

  /// Optional scaffold key for accessing drawer programmatically.
  final GlobalKey<ScaffoldState>? scaffoldKey;

  const M3AdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.paneBuilder,
    this.drawerHeader,
    this.drawerFooter,
    this.customDrawerBody,
    this.customMobileDrawer,
    this.customRail,
    this.initialIndex = 0,
    this.appBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.drawerWidth = 264.0,
    this.railWidth = 80.0,
    this.animationDuration = const Duration(milliseconds: 200),
    this.animationCurve = Curves.fastOutSlowIn,
    this.backgroundColor,
    this.onDestinationChanged,
    this.scaffoldKey,
  })  : assert(destinations.length >= 2 && destinations.length <= 7,
            'M3 requires 2-7 navigation destinations; got ${destinations.length}'),
        assert(drawerWidth >= 256 && drawerWidth <= 360,
            'M3 Navigation Drawer width must be 256dp–360dp; got $drawerWidth'),
        assert(railWidth >= 72 && railWidth <= 80,
            'M3 Navigation Rail width must be 72dp–80dp; got $railWidth');

  @override
  State<M3AdaptiveScaffold> createState() => M3AdaptiveScaffoldState();
}

class M3AdaptiveScaffoldState extends State<M3AdaptiveScaffold>
    with SingleTickerProviderStateMixin {
  late int _selectedIndex;
  late final Set<int> _loadedIndices;
  late final Map<int, Widget> _cachedPanes;
  bool _isDrawerExpanded = true;

  /// Allows external callers to read the current selected index.
  int get selectedIndex => _selectedIndex;

  /// Programmatically switch to a destination.
  void selectDestination(int index) {
    if (index == _selectedIndex) return;
    if (index < 0 || index >= widget.destinations.length) return;
    setState(() {
      _selectedIndex = index;
      _loadedIndices.add(index);
    });
    widget.onDestinationChanged?.call(index);
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _loadedIndices = {_selectedIndex};
    _cachedPanes = {};
  }

  @override
  void didUpdateWidget(covariant M3AdaptiveScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destinations.length != widget.destinations.length) {
      _cachedPanes.clear();
      if (_selectedIndex >= widget.destinations.length) {
        _selectedIndex = 0;
        _loadedIndices
          ..clear()
          ..add(0);
      }
    }
  }

  // ─── Lazy Pane Management ─────────────────────────────────────────────────

  Widget _getOrBuildPane(int index) {
    if (_cachedPanes.containsKey(index)) return _cachedPanes[index]!;
    final pane = widget.paneBuilder(context, index);
    _cachedPanes[index] = pane;
    return pane;
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return M3ResponsiveBuilder(
      builder: (context, layout) {
        final colorScheme = Theme.of(context).colorScheme;
        final navType = layout.navigationType;

        return Scaffold(
          key: widget.scaffoldKey,
          backgroundColor: widget.backgroundColor ?? colorScheme.surface,
          appBar: widget.appBar,

          // ── Bottom Navigation Bar (Compact only) ──
          bottomNavigationBar: navType == M3NavigationType.bottomNavigationBar
              ? _buildBottomNavBar(colorScheme)
              : null,

          // ── Modal Drawer (Compact only) ──
          drawer: navType == M3NavigationType.bottomNavigationBar
              ? (widget.customMobileDrawer != null
                  ? widget.customMobileDrawer!(
                      context,
                      selectedIndex: _selectedIndex,
                      onSelectIndex: selectDestination,
                    )
                  : _buildModalDrawer(colorScheme))
              : null,

          floatingActionButton: navType == M3NavigationType.bottomNavigationBar
              ? widget.floatingActionButton
              : null,
          floatingActionButtonLocation: widget.floatingActionButtonLocation,

          // ── Body: [Rail/Drawer | Pane(s)] ──
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Rail or Drawer — FIRST child for automatic RTL mirroring
              if (navType == M3NavigationType.navigationRail)
                RepaintBoundary(child: _buildNavigationRail(colorScheme, layout)),
              if (navType == M3NavigationType.navigationDrawer ||
                  navType == M3NavigationType.persistentDrawer)
                RepaintBoundary(
                  child: _buildPersistentDrawer(colorScheme, layout),
                ),

              // Panes — lazy loaded, cached, offstage for instant switching
              Expanded(
                child: RepaintBoundary(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      for (int i = 0; i < widget.destinations.length; i++)
                        Offstage(
                          offstage: _selectedIndex != i,
                          child: TickerMode(
                            enabled: _selectedIndex == i,
                            child: _loadedIndices.contains(i)
                                ? _getOrBuildPane(i)
                                : const SizedBox.shrink(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Bottom Navigation Bar (Compact < 600dp) ─────────────────────────────

  Widget _buildBottomNavBar(ColorScheme colorScheme) {
    return NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: selectDestination,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: widget.destinations.map((d) {
        return NavigationDestination(
          icon: d.badgeCount != null && d.badgeCount! > 0
              ? Badge.count(count: d.badgeCount!, child: Icon(d.icon))
              : Icon(d.icon),
          selectedIcon: d.badgeCount != null && d.badgeCount! > 0
              ? Badge.count(count: d.badgeCount!, child: Icon(d.selectedIcon))
              : Icon(d.selectedIcon),
          label: d.label,
          tooltip: d.tooltip ?? d.label,
        );
      }).toList(),
    );
  }

  // ─── Modal Drawer (Compact < 600dp) ───────────────────────────────────────

  Widget _buildModalDrawer(ColorScheme colorScheme) {
    return NavigationDrawer(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) {
        selectDestination(index);
        Navigator.of(context).pop(); // close modal drawer
      },
      children: [
        // Header
        if (widget.drawerHeader != null)
          widget.drawerHeader!(context, true),
        if (widget.drawerHeader != null)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: M3Spacing.sm),
            child: Divider(height: 1),
          ),
        const SizedBox(height: M3Spacing.xs),

        // Destinations
        ...widget.destinations.map((d) {
          return NavigationDrawerDestination(
            icon: d.badgeCount != null && d.badgeCount! > 0
                ? Badge.count(count: d.badgeCount!, child: Icon(d.icon))
                : Icon(d.icon),
            selectedIcon: d.badgeCount != null && d.badgeCount! > 0
                ? Badge.count(count: d.badgeCount!, child: Icon(d.selectedIcon))
                : Icon(d.selectedIcon),
            label: Text(d.label),
          );
        }),

        // Footer
        if (widget.drawerFooter != null) ...[
          const Spacer(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: M3Spacing.sm),
            child: Divider(height: 1),
          ),
          widget.drawerFooter!(context),
        ],
      ],
    );
  }

  // ─── Navigation Rail (Medium 600–839dp) ───────────────────────────────────

  Widget _buildNavigationRail(ColorScheme colorScheme, M3LayoutMetrics layout) {
    if (widget.customRail != null) {
      return widget.customRail!(
        context,
        selectedIndex: _selectedIndex,
        width: widget.railWidth,
        onSelectIndex: selectDestination,
      );
    }

    return Container(
      width: widget.railWidth,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: BorderDirectional(
          end: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
      ),
      child: NavigationRail(
        selectedIndex: _selectedIndex,
        onDestinationSelected: selectDestination,
        labelType: NavigationRailLabelType.all,
        backgroundColor: Colors.transparent,
        indicatorColor: colorScheme.secondaryContainer,
        leading: widget.floatingActionButton != null
            ? Padding(
                padding: const EdgeInsets.only(bottom: M3Spacing.sm),
                child: widget.floatingActionButton,
              )
            : null,
        destinations: widget.destinations.map((d) {
          return NavigationRailDestination(
            icon: Tooltip(
              message: d.tooltip ?? d.label,
              child: d.badgeCount != null && d.badgeCount! > 0
                  ? Badge.count(count: d.badgeCount!, child: Icon(d.icon))
                  : Icon(d.icon),
            ),
            selectedIcon: d.badgeCount != null && d.badgeCount! > 0
                ? Badge.count(count: d.badgeCount!, child: Icon(d.selectedIcon))
                : Icon(d.selectedIcon),
            label: Text(
              d.label,
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Persistent Navigation Drawer (Expanded ≥ 840dp) ─────────────────────

  Widget _buildPersistentDrawer(
    ColorScheme colorScheme,
    M3LayoutMetrics layout,
  ) {
    final bool isLargeOrExtraLarge = layout.isLarge || layout.isExtraLarge;
    // On Large/ExtraLarge, drawer is always expanded.
    // On Expanded (840-1199dp), user can collapse/expand.
    final bool canCollapse = !isLargeOrExtraLarge;
    final bool isExpanded = isLargeOrExtraLarge || _isDrawerExpanded;

    final double targetWidth = isExpanded ? widget.drawerWidth : widget.railWidth;

    // ── Custom Drawer Body (full escape hatch) ──
    if (widget.customDrawerBody != null) {
      return AnimatedContainer(
        duration: widget.animationDuration,
        curve: widget.animationCurve,
        width: targetWidth,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          border: BorderDirectional(
            end: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
        ),
        child: ClipRect(
          child: OverflowBox(
            alignment: AlignmentDirectional.centerStart,
            maxWidth: widget.drawerWidth,
            child: SizedBox(
              width: widget.drawerWidth,
              child: widget.customDrawerBody!(
                context,
                selectedIndex: _selectedIndex,
                isExpanded: isExpanded,
                targetWidth: targetWidth,
                onSelectIndex: selectDestination,
                onToggleExpanded: () {
                  if (canCollapse) {
                    setState(() => _isDrawerExpanded = !_isDrawerExpanded);
                  }
                },
              ),
            ),
          ),
        ),
      );
    }

    // ── Default Drawer Body ──
    return AnimatedContainer(
      duration: widget.animationDuration,
      curve: widget.animationCurve,
      width: targetWidth,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: BorderDirectional(
          end: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: AlignmentDirectional.centerStart,
          maxWidth: widget.drawerWidth,
          child: SizedBox(
            width: widget.drawerWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ──
                if (widget.drawerHeader != null)
                  widget.drawerHeader!(context, isExpanded),

                // ── Collapse/Expand Toggle (Only on Expanded tier) ──
                if (canCollapse)
                  _DrawerCollapseButton(
                    isExpanded: isExpanded,
                    onToggle: () {
                      setState(() => _isDrawerExpanded = !_isDrawerExpanded);
                    },
                  ),

                if (widget.drawerHeader != null || canCollapse)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: M3Spacing.sm),
                    child: Divider(
                      height: 1,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),

                const SizedBox(height: M3Spacing.xs),

                // ── Destinations ──
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: M3Spacing.xs),
                    children: [
                      for (int i = 0; i < widget.destinations.length; i++)
                        _DrawerDestinationTile(
                          destination: widget.destinations[i],
                          isSelected: _selectedIndex == i,
                          isExpanded: isExpanded,
                          onTap: () => selectDestination(i),
                        ),
                    ],
                  ),
                ),

                // ── Footer ──
                if (widget.drawerFooter != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: M3Spacing.sm),
                    child: Divider(
                      height: 1,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  widget.drawerFooter!(context),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private Drawer Sub-Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _DrawerCollapseButton extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;

  const _DrawerCollapseButton({
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: M3Spacing.xs,
        end: M3Spacing.xs,
        top: M3Spacing.xxs,
        bottom: M3Spacing.xxs,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: IconButton(
          icon: AnimatedRotation(
            turns: isExpanded ? 0 : 0.5,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.menu_open_rounded, size: 20),
          ),
          tooltip: isExpanded ? 'Collapse' : 'Expand',
          onPressed: onToggle,
          style: IconButton.styleFrom(
            padding: const EdgeInsets.all(M3Spacing.xs),
          ),
        ),
      ),
    );
  }
}

class _DrawerDestinationTile extends StatelessWidget {
  final M3NavDestination destination;
  final bool isSelected;
  final bool isExpanded;
  final VoidCallback onTap;

  const _DrawerDestinationTile({
    required this.destination,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final effectiveAccent = destination.accentColor ?? colorScheme.primary;
    final bgColor = isSelected
        ? effectiveAccent.withValues(alpha: 0.12)
        : Colors.transparent;
    final iconColor = isSelected ? effectiveAccent : colorScheme.onSurfaceVariant;
    final labelColor = isSelected ? colorScheme.onSurface : colorScheme.onSurfaceVariant;

    final icon = destination.badgeCount != null && destination.badgeCount! > 0
        ? Badge.count(
            count: destination.badgeCount!,
            child: Icon(
              isSelected ? destination.selectedIcon : destination.icon,
              size: 22,
              color: iconColor,
            ),
          )
        : Icon(
            isSelected ? destination.selectedIcon : destination.icon,
            size: 22,
            color: iconColor,
          );

    if (!isExpanded) {
      // Collapsed — icon-only tile (like Rail)
      return Tooltip(
        message: destination.tooltip ?? destination.label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: icon,
          ),
        ),
      );
    }

    // Expanded — full label + subtitle tile
    return Tooltip(
      message: destination.tooltip ?? '',
      waitDuration: const Duration(milliseconds: 800),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: M3Spacing.sm,
              vertical: M3Spacing.xs + M3Spacing.xxs,
            ),
            child: Row(
              children: [
                icon,
                const SizedBox(width: M3Spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        destination.label,
                        style: textTheme.labelLarge?.copyWith(
                          color: labelColor,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (destination.subtitle != null && destination.subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          destination.subtitle!,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// M3 Canonical Pane Layouts
// ─────────────────────────────────────────────────────────────────────────────

/// The canonical M3 **List–Detail** pane layout.
///
/// On **Expanded+** (≥ 840dp): Displays a fixed-width list pane alongside
/// a flexible detail pane, separated by a 1dp divider.
///
/// On **Compact/Medium** (< 840dp): Shows only [listPane]. Tapping an item
/// should push a full-screen detail page using standard navigation.
///
/// ```
/// ┌────────┬─────────────────────┐
/// │  List  │      Detail         │
/// │ (fixed)│    (flexible)       │
/// │ 360dp  │     remaining       │
/// └────────┴─────────────────────┘
/// ```
///
/// Ref: https://m3.material.io/foundations/layout/scaffold/panes
class M3ListDetailLayout extends StatelessWidget {
  /// The list pane content (e.g. a scrollable list of items).
  final Widget listPane;

  /// The detail pane content. Shown only on Expanded+ screens.
  /// On smaller screens, detail should be pushed as a full-screen route.
  final Widget? detailPane;

  /// Placeholder shown in the detail pane when no item is selected.
  final Widget? detailPlaceholder;

  /// Fixed width of the list pane. Defaults to 360dp (M3 standard).
  final double listPaneWidth;

  /// Whether to show the divider between panes. Defaults to true.
  final bool showDivider;

  /// How to align panes vertically. Defaults to [CrossAxisAlignment.stretch]
  /// for independently scrollable full-height panes.
  final CrossAxisAlignment crossAxisAlignment;

  const M3ListDetailLayout({
    super.key,
    required this.listPane,
    this.detailPane,
    this.detailPlaceholder,
    this.listPaneWidth = 360.0,
    this.showDivider = true,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  @override
  Widget build(BuildContext context) {
    return M3ResponsiveBuilder(
      builder: (context, layout) {
        // Single pane on Compact & Medium
        if (layout.isCompact || layout.isMedium) {
          return listPane;
        }

        // Dual pane on Expanded+
        final dividerColor = Theme.of(context)
            .colorScheme
            .outlineVariant
            .withValues(alpha: 0.3);

        return Row(
          crossAxisAlignment: crossAxisAlignment,
          children: [
            SizedBox(
              width: listPaneWidth,
              child: listPane,
            ),
            if (showDivider)
              crossAxisAlignment == CrossAxisAlignment.stretch
                  ? VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: dividerColor,
                    )
                  : Container(
                      width: 1,
                      color: dividerColor,
                    ),
            Expanded(
              child: detailPane ??
                  detailPlaceholder ??
                  _DefaultDetailPlaceholder(),
            ),
          ],
        );
      },
    );
  }
}

/// The canonical M3 **Supporting Pane** layout.
///
/// On **Expanded+** (≥ 840dp): Displays the primary content pane alongside
/// a fixed-width supporting pane (stats, tools, notes, properties).
///
/// On **Compact/Medium** (< 840dp): Shows only [body]. The supporting pane
/// can be accessed via a Bottom Sheet, triggered by [onOpenSupportingPane].
///
/// ```
/// ┌─────────────────────┬────────┐
/// │      Main Content   │  Side  │
/// │     (flexible)      │ Panel  │
/// │                     │ (fixed)│
/// │                     │ 320dp  │
/// └─────────────────────┴────────┘
/// ```
///
/// Ref: https://m3.material.io/foundations/layout/scaffold/panes
class M3SupportingPaneLayout extends StatelessWidget {
  /// Primary content pane (flexible width).
  final Widget body;

  /// Supporting pane content (fixed width, shown on desktop).
  final Widget supportingPane;

  /// Fixed width of the supporting pane. Defaults to 320dp.
  final double supportingPaneWidth;

  /// Whether to show the divider between panes. Defaults to true.
  final bool showDivider;

  /// On Compact/Medium, the supporting pane can be shown as a bottom sheet.
  /// This widget is shown inside the sheet when triggered.
  /// If null, [supportingPane] is used.
  final Widget? sheetContent;

  /// How to align panes vertically. Defaults to [CrossAxisAlignment.stretch]
  /// for independently scrollable full-height panes.
  final CrossAxisAlignment crossAxisAlignment;

  const M3SupportingPaneLayout({
    super.key,
    required this.body,
    required this.supportingPane,
    this.supportingPaneWidth = 320.0,
    this.showDivider = true,
    this.sheetContent,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  /// Opens the supporting pane as a modal bottom sheet (for Compact/Medium).
  static void showAsSheet(BuildContext context, Widget content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(M3Spacing.sm),
            child: content,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return M3ResponsiveBuilder(
      builder: (context, layout) {
        // Single pane on Compact & Medium
        if (layout.isCompact || layout.isMedium) {
          return body;
        }

        final dividerColor = Theme.of(context)
            .colorScheme
            .outlineVariant
            .withValues(alpha: 0.3);

        // Dual pane on Expanded+
        return Row(
          crossAxisAlignment: crossAxisAlignment,
          children: [
            Expanded(child: body),
            if (showDivider)
              crossAxisAlignment == CrossAxisAlignment.stretch
                  ? VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: dividerColor,
                    )
                  : Container(
                      width: 1,
                      color: dividerColor,
                    ),
            SizedBox(
              width: supportingPaneWidth,
              child: supportingPane,
            ),
          ],
        );
      },
    );
  }
}

/// The canonical M3 **Feed** pane layout.
///
/// Displays a grid of cards that reflow dynamically:
///  - **Compact** (< 600dp): 1 column
///  - **Medium** (600–839dp): 2 columns
///  - **Expanded** (840–1199dp): 3 columns
///  - **Large+** (≥ 1200dp): 4 columns
///
/// ```
/// 📱 Compact:           💻 Large:
/// ┌──────────┐          ┌────┬────┬────┬────┐
/// │ ┌──────┐ │          │ C1 │ C2 │ C3 │ C4 │
/// │ │Card 1│ │          ├────┼────┼────┼────┤
/// │ └──────┘ │          │ C5 │ C6 │ C7 │ C8 │
/// │ ┌──────┐ │          └────┴────┴────┴────┘
/// │ │Card 2│ │
/// │ └──────┘ │
/// └──────────┘
/// ```
///
/// Ref: https://m3.material.io/foundations/layout/scaffold/panes
class M3FeedLayout extends StatelessWidget {
  /// The children (cards/tiles) to lay out in a responsive grid.
  final List<Widget> children;

  /// Spacing between cards (horizontal). Defaults to 16dp.
  final double spacing;

  /// Spacing between rows (vertical). Defaults to 16dp.
  final double runSpacing;

  /// Optional override for the number of columns. If null, auto-calculated.
  final int? columnCount;

  /// Optional padding around the entire grid.
  final EdgeInsetsGeometry? padding;

  const M3FeedLayout({
    super.key,
    required this.children,
    this.spacing = M3Spacing.sm,
    this.runSpacing = M3Spacing.sm,
    this.columnCount,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return M3ResponsiveBuilder(
      builder: (context, layout) {
        final int cols = columnCount ?? _resolveColumnCount(layout);
        final effectivePadding = padding ??
            EdgeInsets.symmetric(
              horizontal: layout.margin,
              vertical: M3Spacing.sm,
            );

        return Padding(
          padding: effectivePadding,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalSpacing = spacing * (cols - 1);
              final cardWidth = (constraints.maxWidth - totalSpacing) / cols;

              return Wrap(
                spacing: spacing,
                runSpacing: runSpacing,
                children: children.map((child) {
                  return SizedBox(
                    width: cardWidth,
                    child: child,
                  );
                }).toList(),
              );
            },
          ),
        );
      },
    );
  }

  int _resolveColumnCount(M3LayoutMetrics layout) {
    if (layout.isCompact) return 1;
    if (layout.isMedium) return 2;
    if (layout.isExpanded) return 3;
    return 4; // Large & ExtraLarge
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Default Placeholders
// ─────────────────────────────────────────────────────────────────────────────

class _DefaultDetailPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.touch_app_outlined,
            size: 48,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: M3Spacing.sm),
          Text(
            'Select an item to view details',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
          ),
        ],
      ),
    );
  }
}
