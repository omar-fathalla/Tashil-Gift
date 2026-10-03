import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/m3_spacing_tokens.dart';

/// Official Material Design 3 (M3) Action Menu & Cascading Submenus component.
///
/// Implements Google's Material Design 3 Menus Specification:
/// - Built on Flutter's official [MenuAnchor], [MenuItemButton], and [SubmenuButton]
/// - Container styling: [ColorScheme.surfaceContainer], 8dp Corner Radius, Level 2 elevation
/// - Adaptive density: 48dp on Mobile/Touch, 36–40dp on Desktop/Compact
/// - Strict 48x48dp touch target safety for anchor button on mobile
/// - Bidirectional Cascading Submenus: Directional arrows mirror automatically
///   (points LEFT in RTL / Arabic, points RIGHT in LTR / English & Hindi)
/// - Visual hierarchy: Functional logical grouping with dividers and highlighted
///   destructive actions styled in [ColorScheme.error]
/// - Full keyboard accessibility: Arrow navigation, Looping, Enter, Escape, Typeahead
class M3ActionMenu extends StatelessWidget {
  /// Custom anchor icon or widget. Defaults to [Icons.more_vert_rounded].
  final Widget? anchorIcon;

  /// Custom anchor builder allowing any widget (e.g. TextButton, FilledButton, Chip)
  /// to trigger the M3 Action Menu.
  final Widget Function(BuildContext context, MenuController controller, Widget? child)? anchorBuilder;

  /// Tooltip text displayed on hover or long press on the anchor button.
  final String? tooltip;

  /// List of menu items ([MenuItemButton], [SubmenuButton], or [M3ActionMenu.divider]).
  final List<Widget> children;

  /// Optional external [MenuController] to control the menu programmatically.
  final MenuController? controller;

  /// Optional menu alignment offset relative to the anchor widget.
  final Offset? alignmentOffset;

  /// Whether the anchor button is enabled. Defaults to true.
  final bool enabled;

  const M3ActionMenu({
    super.key,
    this.anchorIcon,
    this.anchorBuilder,
    this.tooltip,
    required this.children,
    this.controller,
    this.alignmentOffset,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = MediaQuery.sizeOf(context).width >= 840;

    final defaultMenuStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(colorScheme.surfaceContainer),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(2.0),
      shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.18)),
      side: WidgetStatePropertyAll(
        BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1.0,
        ),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(vertical: M3SpacingTokens.space1), // 4dp
      ),
      minimumSize: WidgetStatePropertyAll(
        Size(isDesktop ? 160.0 : 180.0, 0),
      ),
      maximumSize: const WidgetStatePropertyAll(
        Size(320.0, double.infinity),
      ),
    );

    return MenuAnchor(
      controller: controller,
      alignmentOffset: alignmentOffset,
      style: defaultMenuStyle,
      builder: anchorBuilder ??
          (context, menuController, child) {
            return IconButton(
              onPressed: enabled
                  ? () {
                      if (menuController.isOpen) {
                        menuController.close();
                      } else {
                        menuController.open();
                      }
                    }
                  : null,
              icon: anchorIcon ?? const Icon(Icons.more_vert_rounded),
              tooltip: tooltip ?? 'خيارات إضافية',
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48), // WCAG minimum touch target
                padding: const EdgeInsets.all(8),
              ),
            );
          },
      menuChildren: children,
    );
  }

  // ===========================================================================
  // Static Helper Builders
  // ===========================================================================

  /// Builds a standard Material Design 3 Menu Item ([MenuItemButton]).
  static Widget item({
    required BuildContext context,
    required String label,
    IconData? icon,
    VoidCallback? onPressed,
    String? shortcutText,
    bool isDestructive = false,
    bool isSelected = false,
    bool enabled = true,
    Widget? leading,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = MediaQuery.sizeOf(context).width >= 840;

    final Color foregroundColor;
    if (!enabled) {
      foregroundColor = colorScheme.onSurface.withValues(alpha: 0.38);
    } else if (isDestructive) {
      foregroundColor = colorScheme.error;
    } else if (isSelected) {
      foregroundColor = colorScheme.primary;
    } else {
      foregroundColor = colorScheme.onSurface;
    }

    Widget? effectiveLeading = leading;
    if (effectiveLeading == null && icon != null) {
      effectiveLeading = Icon(
        icon,
        size: 20.0,
        color: foregroundColor,
      );
    }

    Widget? effectiveTrailing = trailing;
    if (effectiveTrailing == null) {
      if (isSelected) {
        effectiveTrailing = Icon(
          Icons.check_rounded,
          size: 18.0,
          color: colorScheme.primary,
        );
      } else if (shortcutText != null) {
        effectiveTrailing = Text(
          shortcutText,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontFamily: GoogleFonts.cairo().fontFamily,
          ),
        );
      }
    }

    return MenuItemButton(
      onPressed: enabled ? onPressed : null,
      style: MenuItemButton.styleFrom(
        minimumSize: Size(isDesktop ? 160.0 : 180.0, isDesktop ? 40.0 : 48.0),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: M3SpacingTokens.space3, // 12dp
        ),
        foregroundColor: foregroundColor,
        alignment: AlignmentDirectional.centerStart,
      ),
      leadingIcon: effectiveLeading,
      trailingIcon: effectiveTrailing,
      child: Text(
        label,
        style: GoogleFonts.cairo(
          fontSize: 13.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: foregroundColor,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Builds a Cascading Submenu ([SubmenuButton]) with automatic RTL / LTR
  /// arrow mirroring (Left-pointing arrow in Arabic RTL, Right-pointing arrow in English LTR).
  static Widget submenu({
    required BuildContext context,
    required String label,
    IconData? icon,
    required List<Widget> children,
    Widget? leading,
    bool enabled = true,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = MediaQuery.sizeOf(context).width >= 840;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    final Color foregroundColor = enabled
        ? colorScheme.onSurface
        : colorScheme.onSurface.withValues(alpha: 0.38);

    final defaultSubmenuStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(colorScheme.surfaceContainer),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(2.0),
      shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.18)),
      side: WidgetStatePropertyAll(
        BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1.0,
        ),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(vertical: M3SpacingTokens.space1),
      ),
      minimumSize: WidgetStatePropertyAll(
        Size(isDesktop ? 160.0 : 180.0, 0),
      ),
    );

    Widget? effectiveLeading = leading;
    if (effectiveLeading == null && icon != null) {
      effectiveLeading = Icon(icon, size: 20.0, color: foregroundColor);
    }

    return SubmenuButton(
      menuStyle: defaultSubmenuStyle,
      menuChildren: children,
      style: MenuItemButton.styleFrom(
        minimumSize: Size(isDesktop ? 160.0 : 180.0, isDesktop ? 40.0 : 48.0),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: M3SpacingTokens.space3, // 12dp
        ),
        foregroundColor: foregroundColor,
        alignment: AlignmentDirectional.centerStart,
      ),
      leadingIcon: effectiveLeading,
      // Directional arrow mirroring:
      // RTL: points LEFT (chevron_left)
      // LTR: points RIGHT (chevron_right)
      trailingIcon: Icon(
        isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
        size: 18.0,
        color: colorScheme.onSurfaceVariant,
      ),
      child: Text(
        label,
        style: GoogleFonts.cairo(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: foregroundColor,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Builds a horizontal 1dp divider between logical groups of menu items.
  static Widget divider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 4.0),
      child: Divider(
        height: 1.0,
        thickness: 1.0,
      ),
    );
  }

  /// Builds a non-clickable section subheader for organized categorization.
  static Widget header({
    required BuildContext context,
    required String title,
    IconData? icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: M3SpacingTokens.space3,
        end: M3SpacingTokens.space3,
        top: 6.0,
        bottom: 4.0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14.0, color: colorScheme.primary),
            const SizedBox(width: 6.0),
          ],
          Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 11.0,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
