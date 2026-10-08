import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Segment item descriptor for [M3ConnectedButtonGroup]
class M3ButtonSegment<T> {
  final T value;
  final String label;
  final IconData? icon;
  final IconData? selectedIcon;
  final String? badgeText;
  final String? tooltip;

  const M3ButtonSegment({
    required this.value,
    required this.label,
    this.icon,
    this.selectedIcon,
    this.badgeText,
    this.tooltip,
  });
}

/// M3 Connected Button Group (Segmented Button Group)
/// Adheres directly to Material Design 3 specification:
/// https://m3.material.io/components/button-groups/overview
class M3ConnectedButtonGroup<T> extends StatelessWidget {
  final List<M3ButtonSegment<T>> segments;
  final T selectedValue;
  final ValueChanged<T> onSelected;
  final bool showCheckmark;
  final double height;
  final double borderRadius;
  final bool isExpanded;
  final EdgeInsetsGeometry? padding;
  final double? fontSize;
  final double? iconSize;

  const M3ConnectedButtonGroup({
    super.key,
    required this.segments,
    required this.selectedValue,
    required this.onSelected,
    this.showCheckmark = true,
    this.height = 48,
    this.borderRadius = 24,
    this.isExpanded = false,
    this.padding,
    this.fontSize,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveFontSize = fontSize ?? (height <= 32 ? 11.5 : 13.0);
    final effectiveIconSize = iconSize ?? (height <= 32 ? 15.0 : 18.0);

    Widget buildSegment(int index) {
      final segment = segments[index];
      final isSelected = segment.value == selectedValue;
      final isFirst = index == 0;
      final isLast = index == segments.length - 1;

      // Compute individual corner radiuses
      BorderRadius itemBorderRadius;
      if (Directionality.of(context) == TextDirection.rtl) {
        itemBorderRadius = BorderRadius.horizontal(
          right: isFirst ? Radius.circular(borderRadius - 2) : Radius.zero,
          left: isLast ? Radius.circular(borderRadius - 2) : Radius.zero,
        );
      } else {
        itemBorderRadius = BorderRadius.horizontal(
          left: isFirst ? Radius.circular(borderRadius - 2) : Radius.zero,
          right: isLast ? Radius.circular(borderRadius - 2) : Radius.zero,
        );
      }

      final content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelected(segment.value),
          borderRadius: itemBorderRadius,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            height: double.infinity,
            decoration: BoxDecoration(
              color: isSelected ? colorScheme.primary : Colors.transparent,
              borderRadius: itemBorderRadius,
            ),
            padding: padding ?? EdgeInsets.symmetric(horizontal: isExpanded ? 6 : (height <= 32 ? 8 : 14)),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isSelected && showCheckmark) ...[
                  Icon(
                    Icons.check,
                    size: effectiveIconSize,
                    color: colorScheme.onPrimary,
                  ),
                  const SizedBox(width: 5),
                ] else if (segment.icon != null) ...[
                  Icon(
                    isSelected && segment.selectedIcon != null
                        ? segment.selectedIcon
                        : segment.icon,
                    size: effectiveIconSize,
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    segment.label,
                    style: GoogleFonts.cairo(
                      fontSize: effectiveFontSize,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                if (segment.badgeText != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.onPrimary.withValues(alpha: 0.25)
                          : colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      segment.badgeText!,
                      style: GoogleFonts.cairo(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? colorScheme.onPrimary
                            : colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );

      Widget itemWidget = content;
      if (segment.tooltip != null) {
        itemWidget = Tooltip(
          message: segment.tooltip!,
          waitDuration: const Duration(milliseconds: 400),
          child: content,
        );
      }

      if (isExpanded) {
        return Expanded(child: itemWidget);
      }
      return itemWidget;
    }

    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.8),
          width: 1.2,
        ),
      ),
      child: IntrinsicHeight(
        child: isExpanded
            ? Row(
                mainAxisSize: MainAxisSize.max,
                children: List.generate(segments.length, (index) => buildSegment(index)),
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(segments.length, (index) => buildSegment(index)),
                ),
              ),
      ),
    );
  }
}

/// Morphing / Dynamic Shape M3 Button Group
/// Provides circle, squircle, and capsule action buttons
class M3MorphingActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String? label;
  final bool isSelected;
  final bool isDestructive;
  final Color? customColor;
  final String? tooltip;

  const M3MorphingActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.label,
    this.isSelected = false,
    this.isDestructive = false,
    this.customColor,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Color bg;
    Color fg;

    if (isDestructive) {
      bg = colorScheme.errorContainer;
      fg = colorScheme.onErrorContainer;
    } else if (isSelected) {
      bg = customColor ?? colorScheme.primary;
      fg = colorScheme.onPrimary;
    } else {
      bg = colorScheme.surfaceContainerHigh;
      fg = colorScheme.onSurfaceVariant;
    }

    final buttonWidget = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 44,
      padding: EdgeInsets.symmetric(
        horizontal: label != null ? 18 : 12,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(label != null ? 22 : 16),
        border: Border.all(
          color: isSelected
              ? Colors.transparent
              : colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(label != null ? 22 : 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: fg),
            if (label != null) ...[
              const SizedBox(width: 8),
              Text(
                label!,
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: fg,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: buttonWidget);
    }
    return buttonWidget;
  }
}
