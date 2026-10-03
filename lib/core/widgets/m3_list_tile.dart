import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Enumeration representing the standard Material Design 3 List item line heights.
///
/// Material 3 Specification:
/// - One line: 56dp (Mobile) / 44–48dp (Desktop)
/// - Two lines: 72dp (Mobile) / 60dp (Desktop)
/// - Three lines: 88dp (Mobile) / 76dp (Desktop)
enum M3ListTileLines {
  one,
  two,
  three,
}

/// A production-grade Material Design 3 List Item widget built for high-performance
/// rendering, strict accessibility (48x48dp minimum touch targets), standard line
/// heights, directional RTL/LTR support, and 0ms instantaneous selection state visual feedback.
class M3ListTile extends StatelessWidget {
  /// Optional leading widget (e.g. 40x40dp store avatar, product thumbnail, or icon).
  final Widget? leading;

  /// Primary headline text or widget.
  final Widget headline;

  /// Secondary subtitle text or widget (line 2).
  final Widget? subtitle;

  /// Supporting or overline text (line 3 or caption).
  final Widget? supportingText;

  /// Trailing element (e.g. amount badge, status chip, or chevron).
  final Widget? trailing;

  /// List of trailing interactive action buttons.
  /// Each button is guaranteed a minimum 48x48dp touch target for accessibility (WCAG / a11y).
  final List<Widget>? trailingActions;

  /// Explicit number of lines for standard M3 height constraints.
  /// If null, this is automatically deduced from provided fields.
  final M3ListTileLines? lines;

  /// Whether this tile is visually selected.
  /// When true, renders with [ColorScheme.secondaryContainer] and a 12dp rounded border.
  final bool isSelected;

  /// Whether this tile is enabled for user interaction.
  final bool enabled;

  /// Called when the user taps on this tile.
  final VoidCallback? onTap;

  /// Called when the user long-presses this tile.
  final VoidCallback? onLongPress;

  /// Optional semantic label for screen readers.
  final String? semanticsLabel;

  /// Content padding. Defaults to standard M3 directional insets (16dp horizontal, 8dp vertical).
  final EdgeInsetsGeometry? contentPadding;

  /// Outer border radius. Defaults to 12dp.
  final BorderRadius? borderRadius;

  /// Explicit dense mode (forces compact desktop line heights).
  final bool? dense;

  /// Optional custom background color for the unselected state.
  final Color? backgroundColor;

  /// Optional custom border side.
  final BorderSide? border;

  const M3ListTile({
    super.key,
    this.leading,
    required this.headline,
    this.subtitle,
    this.supportingText,
    this.trailing,
    this.trailingActions,
    this.lines,
    this.isSelected = false,
    this.enabled = true,
    this.onTap,
    this.onLongPress,
    this.semanticsLabel,
    this.contentPadding,
    this.borderRadius,
    this.dense,
    this.backgroundColor,
    this.border,
  });

  /// Helper factory for one-line ListTile
  factory M3ListTile.oneLine({
    Key? key,
    Widget? leading,
    required Widget headline,
    Widget? trailing,
    List<Widget>? trailingActions,
    bool isSelected = false,
    bool enabled = true,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    String? semanticsLabel,
    EdgeInsetsGeometry? contentPadding,
    BorderRadius? borderRadius,
    bool? dense,
    Color? backgroundColor,
    BorderSide? border,
  }) {
    return M3ListTile(
      key: key,
      leading: leading,
      headline: headline,
      trailing: trailing,
      trailingActions: trailingActions,
      lines: M3ListTileLines.one,
      isSelected: isSelected,
      enabled: enabled,
      onTap: onTap,
      onLongPress: onLongPress,
      semanticsLabel: semanticsLabel,
      contentPadding: contentPadding,
      borderRadius: borderRadius,
      dense: dense,
      backgroundColor: backgroundColor,
      border: border,
    );
  }

  /// Helper factory for two-line ListTile
  factory M3ListTile.twoLine({
    Key? key,
    Widget? leading,
    required Widget headline,
    required Widget subtitle,
    Widget? trailing,
    List<Widget>? trailingActions,
    bool isSelected = false,
    bool enabled = true,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    String? semanticsLabel,
    EdgeInsetsGeometry? contentPadding,
    BorderRadius? borderRadius,
    bool? dense,
    Color? backgroundColor,
    BorderSide? border,
  }) {
    return M3ListTile(
      key: key,
      leading: leading,
      headline: headline,
      subtitle: subtitle,
      trailing: trailing,
      trailingActions: trailingActions,
      lines: M3ListTileLines.two,
      isSelected: isSelected,
      enabled: enabled,
      onTap: onTap,
      onLongPress: onLongPress,
      semanticsLabel: semanticsLabel,
      contentPadding: contentPadding,
      borderRadius: borderRadius,
      dense: dense,
      backgroundColor: backgroundColor,
      border: border,
    );
  }

  /// Helper factory for three-line ListTile
  factory M3ListTile.threeLine({
    Key? key,
    Widget? leading,
    required Widget headline,
    required Widget subtitle,
    required Widget supportingText,
    Widget? trailing,
    List<Widget>? trailingActions,
    bool isSelected = false,
    bool enabled = true,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    String? semanticsLabel,
    EdgeInsetsGeometry? contentPadding,
    BorderRadius? borderRadius,
    bool? dense,
    Color? backgroundColor,
    BorderSide? border,
  }) {
    return M3ListTile(
      key: key,
      leading: leading,
      headline: headline,
      subtitle: subtitle,
      supportingText: supportingText,
      trailing: trailing,
      trailingActions: trailingActions,
      lines: M3ListTileLines.three,
      isSelected: isSelected,
      enabled: enabled,
      onTap: onTap,
      onLongPress: onLongPress,
      semanticsLabel: semanticsLabel,
      contentPadding: contentPadding,
      borderRadius: borderRadius,
      dense: dense,
      backgroundColor: backgroundColor,
      border: border,
    );
  }

  /// Automatically deduces the line count based on non-null text components.
  M3ListTileLines _deduceLines() {
    if (lines != null) return lines!;
    if (supportingText != null) return M3ListTileLines.three;
    if (subtitle != null) return M3ListTileLines.two;
    return M3ListTileLines.one;
  }

  /// Returns the official M3 standard height based on device class and lines count.
  double getStandardHeight({required bool isMobile}) {
    final effectiveLines = _deduceLines();
    switch (effectiveLines) {
      case M3ListTileLines.one:
        return isMobile ? 56.0 : 48.0;
      case M3ListTileLines.two:
        return isMobile ? 72.0 : 60.0;
      case M3ListTileLines.three:
        return isMobile ? 88.0 : 76.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = dense != null ? !dense! : screenWidth < 840;
    final effectiveRadius = borderRadius ?? BorderRadius.circular(12);

    final standardMinHeight = getStandardHeight(isMobile: isMobile);

    // M3 Color & Border Selection logic
    final Color effectiveBgColor;
    final Border? effectiveBorder;

    if (isSelected) {
      effectiveBgColor = colorScheme.secondaryContainer;
      effectiveBorder = Border.all(
        color: colorScheme.primary.withValues(alpha: 0.6),
        width: 1.5,
      );
    } else {
      effectiveBgColor = backgroundColor ?? Colors.transparent;
      effectiveBorder = border != null ? Border.fromBorderSide(border!) : null;
    }

    final defaultPadding = EdgeInsetsDirectional.symmetric(
      horizontal: 16,
      vertical: isMobile ? 8 : 4,
    );
    final effectivePadding = contentPadding ?? defaultPadding;

    Widget content = InkWell(
      onTap: enabled ? onTap : null,
      onLongPress: enabled ? onLongPress : null,
      borderRadius: effectiveRadius,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: standardMinHeight),
        child: Padding(
          padding: effectivePadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Leading Element (Avatar / Image / Icon)
              if (leading != null) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                    maxWidth: 56,
                    maxHeight: 56,
                  ),
                  child: Center(child: leading),
                ),
                const SizedBox(width: 16),
              ],

              // 2. Middle Content: Headline, Subtitle, Supporting Text
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Headline (Line 1)
                    DefaultTextStyle(
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 14 : 14.5,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? colorScheme.onSecondaryContainer
                            : colorScheme.onSurface,
                        letterSpacing: 0.15,
                        height: 1.25,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: headline,
                    ),

                    // Subtitle (Line 2)
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      DefaultTextStyle(
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 12 : 12.5,
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? colorScheme.onSecondaryContainer.withValues(alpha: 0.85)
                              : colorScheme.onSurfaceVariant,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        child: subtitle!,
                      ),
                    ],

                    // Supporting / Overline Text (Line 3)
                    if (supportingText != null) ...[
                      const SizedBox(height: 2),
                      DefaultTextStyle(
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 10.5 : 11,
                          fontWeight: FontWeight.w400,
                          color: isSelected
                              ? colorScheme.onSecondaryContainer.withValues(alpha: 0.75)
                              : colorScheme.outline,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        child: supportingText!,
                      ),
                    ],
                  ],
                ),
              ),

              // 3. Trailing Element / Actions
              if (trailing != null || (trailingActions != null && trailingActions!.isNotEmpty)) ...[
                const SizedBox(width: 12),
                ?trailing,
                if (trailingActions != null && trailingActions!.isNotEmpty) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: trailingActions!
                        .map((action) => M3TouchTargetBoundary(child: action))
                        .toList(),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );

    return Semantics(
      button: onTap != null,
      selected: isSelected,
      enabled: enabled,
      label: semanticsLabel,
      child: Material(
        color: effectiveBgColor,
        shape: RoundedRectangleBorder(
          borderRadius: effectiveRadius,
          side: effectiveBorder != null
              ? effectiveBorder.top
              : BorderSide.none,
        ),
        child: content,
      ),
    );
  }
}

/// A directional Material Design 3 Inset Divider.
///
/// Material 3 Inset Dividers start with a directional indent of 72dp (16dp margin + 40dp avatar + 16dp gap)
/// to align precisely with list tile headline and subtitle text.
///
/// In RTL (Arabic), the 72dp indent starts from the right edge.
/// In LTR (English/Hindi), the 72dp indent starts from the left edge.
class M3InsetDivider extends StatelessWidget {
  /// The directional indent at the leading/start edge. Defaults to 72dp.
  final double indent;

  /// The directional indent at the trailing/end edge. Defaults to 0dp.
  final double endIndent;

  /// The divider line thickness. Defaults to 1.0dp.
  final double thickness;

  /// Total height allocated for the divider widget. Defaults to 1.0dp.
  final double height;

  /// Optional custom divider color. Defaults to [ColorScheme.outlineVariant].
  final Color? color;

  const M3InsetDivider({
    super.key,
    this.indent = 72.0,
    this.endIndent = 0.0,
    this.thickness = 1.0,
    this.height = 1.0,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Divider(
      indent: indent,
      endIndent: endIndent,
      thickness: thickness,
      height: height,
      color: color ?? colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
  }
}

/// A Material Design 3 List Subheader widget.
///
/// Strictly maintains the official 48dp standard height, bold title typography,
/// directional padding, and optional trailing status or action element.
class M3Subheader extends StatelessWidget {
  /// Subheader title text or widget.
  final Widget title;

  /// Standard height constraint. Defaults to official 48dp.
  final double height;

  /// Directional content insets. Defaults to 16dp horizontal.
  final EdgeInsetsDirectional padding;

  /// Optional trailing element (e.g. items count pill, filter chip).
  final Widget? trailing;

  /// Optional leading icon.
  final IconData? icon;

  const M3Subheader({
    super.key,
    required this.title,
    this.height = 48.0,
    this.padding = const EdgeInsetsDirectional.symmetric(horizontal: 16),
    this.trailing,
    this.icon,
  });

  factory M3Subheader.text(
    String titleText, {
    Key? key,
    double height = 48.0,
    EdgeInsetsDirectional padding = const EdgeInsetsDirectional.symmetric(horizontal: 16),
    Widget? trailing,
    IconData? icon,
  }) {
    return M3Subheader(
      key: key,
      title: Text(titleText),
      height: height,
      padding: padding,
      trailing: trailing,
      icon: icon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: height,
      child: Padding(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: colorScheme.primary),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: DefaultTextStyle(
                style: GoogleFonts.cairo(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                  letterSpacing: 0.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: title,
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Enforces the official Material Design 3 accessibility touch target standard
/// of at least 48dp x 48dp on any child button or interactive icon.
class M3TouchTargetBoundary extends StatelessWidget {
  final Widget child;
  final double minSize;

  const M3TouchTargetBoundary({
    super.key,
    required this.child,
    this.minSize = 48.0,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minSize,
        minHeight: minSize,
      ),
      child: Center(child: child),
    );
  }
}
