import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Material Design 3 (M3) Linear Progress Bar
/// Ref: https://m3.material.io/components/progress-indicators/overview
class M3LinearProgress extends StatelessWidget {
  /// The progress value between 0.0 and 1.0.
  /// If null, renders an indeterminate animated progress bar.
  final double? value;

  /// Height of the progress bar track. Defaults to 8.0 for M3 standard prominence.
  final double height;

  /// Custom color for the active indicator. Defaults to [ColorScheme.primary].
  final Color? color;

  /// Custom track color. Defaults to [ColorScheme.surfaceContainerHighest].
  final Color? backgroundColor;

  /// Border radius for track and indicator pill ends. Defaults to pill shape.
  final BorderRadius? borderRadius;

  /// Whether to use a smooth gradient on the active indicator.
  final bool useGradient;

  /// Duration for the smooth tween transition when [value] changes.
  final Duration animationDuration;

  const M3LinearProgress({
    super.key,
    this.value,
    this.height = 8.0,
    this.color,
    this.backgroundColor,
    this.borderRadius,
    this.useGradient = true,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final effectiveTrackColor = backgroundColor ?? colorScheme.surfaceContainerHighest;
    final effectiveIndicatorColor = color ?? colorScheme.primary;
    final effectiveRadius = borderRadius ?? BorderRadius.circular(height / 2);

    if (value == null) {
      // Indeterminate M3 Linear Progress Bar
      return ClipRRect(
        borderRadius: effectiveRadius,
        child: SizedBox(
          height: height,
          child: LinearProgressIndicator(
            backgroundColor: effectiveTrackColor,
            valueColor: AlwaysStoppedAnimation<Color>(effectiveIndicatorColor),
            minHeight: height,
          ),
        ),
      );
    }

    // Clamped determinate value (0.0 to 1.0)
    final clampedValue = (value ?? 0.0).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: effectiveRadius,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: clampedValue),
        duration: animationDuration,
        curve: Curves.fastOutSlowIn,
        builder: (context, animatedValue, _) {
          return Container(
            height: height,
            decoration: BoxDecoration(
              color: effectiveTrackColor,
              borderRadius: effectiveRadius,
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: animatedValue,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: effectiveRadius,
                  gradient: useGradient
                      ? LinearGradient(
                          colors: [
                            effectiveIndicatorColor,
                            colorScheme.tertiary,
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        )
                      : null,
                  color: useGradient ? null : effectiveIndicatorColor,
                  boxShadow: animatedValue > 0
                      ? [
                          BoxShadow(
                            color: effectiveIndicatorColor.withValues(alpha: 0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Material Design 3 (M3) Progress Card for Batch and Download Operations
class M3ProgressCard extends StatelessWidget {
  /// The title of the ongoing operation (e.g. 'جاري حفظ المنتجات في النظام')
  final String title;

  /// Optional subtitle or current item status description (e.g. 'يتم الآن ترحيل الحزمة الثانية...')
  final String? subtitle;

  /// Progress value between 0.0 and 1.0. If null, indeterminate.
  final double? progress;

  /// Number of completed items (e.g. 400)
  final int? currentCount;

  /// Total number of items (e.g. 854)
  final int? totalCount;

  /// Icon to display in the header leading avatar.
  final IconData icon;

  /// Optional cancellation callback.
  final VoidCallback? onCancel;

  /// Optional retry or pause callback.
  final VoidCallback? onAction;
  final String? actionLabel;

  const M3ProgressCard({
    super.key,
    required this.title,
    this.subtitle,
    this.progress,
    this.currentCount,
    this.totalCount,
    this.icon = Icons.cloud_upload_rounded,
    this.onCancel,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final hasProgress = progress != null;
    final normalizedProgress = hasProgress ? progress!.clamp(0.0, 1.0) : 0.0;
    final percentage = (normalizedProgress * 100).toInt();
    final isComplete = hasProgress && normalizedProgress >= 1.0;

    return Card(
      elevation: 2,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isComplete
              ? Colors.green.shade400
              : colorScheme.primary.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header: Icon, Title & Percentage Badge
            Row(
              children: [
                // Animated Icon Container
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isComplete
                        ? Colors.green.withValues(alpha: 0.15)
                        : colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isComplete ? Icons.check_circle_rounded : icon,
                    color: isComplete ? Colors.green.shade700 : colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),

                // Title & Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.cairo(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Percentage Badge
                if (hasProgress)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isComplete
                          ? Colors.green.shade800
                          : colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$percentage%',
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // Material 3 Linear Progress Bar
            M3LinearProgress(
              value: progress,
              height: 10,
              color: isComplete ? Colors.green.shade600 : colorScheme.primary,
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),

            const SizedBox(height: 12),

            // Bottom Footer: Item Counter & Quick Action
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Counter (e.g. تم حفظ 400 من 854 منتج)
                if (currentCount != null && totalCount != null)
                  Text(
                    'تم إنجاز $currentCount من $totalCount عنصر ($percentage%)',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isComplete ? Colors.green.shade700 : colorScheme.primary,
                    ),
                  )
                else if (hasProgress)
                  Text(
                    isComplete ? 'اكتملت العملية بنجاح' : 'جاري المعالجة...',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isComplete ? Colors.green.shade700 : colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Text(
                    'جاري التحميل والمعالجة...',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),

                // Action / Cancel Buttons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onAction != null && actionLabel != null)
                      TextButton.icon(
                        onPressed: onAction,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: Text(actionLabel!, style: GoogleFonts.cairo(fontSize: 12)),
                      ),
                    if (onCancel != null && !isComplete)
                      TextButton(
                        onPressed: onCancel,
                        child: Text(
                          'إلغاء',
                          style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.error),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
