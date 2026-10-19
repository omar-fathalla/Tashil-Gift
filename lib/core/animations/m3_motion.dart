import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// =========================================================================
/// MATERIAL DESIGN 3 MOTION TOKENS & CURVES (Google Android Specifications)
/// =========================================================================

class M3Durations {
  static const Duration short1 = Duration(milliseconds: 50);
  static const Duration short2 = Duration(milliseconds: 100);
  static const Duration short3 = Duration(milliseconds: 150);
  static const Duration short4 = Duration(milliseconds: 200);

  static const Duration medium1 = Duration(milliseconds: 250);
  static const Duration medium2 = Duration(milliseconds: 300);
  static const Duration medium3 = Duration(milliseconds: 350);
  static const Duration medium4 = Duration(milliseconds: 400);

  static const Duration long1 = Duration(milliseconds: 450);
  static const Duration long2 = Duration(milliseconds: 500);
  static const Duration long3 = Duration(milliseconds: 550);
  static const Duration long4 = Duration(milliseconds: 600);

  static const Duration extraLong1 = Duration(milliseconds: 700);
  static const Duration extraLong2 = Duration(milliseconds: 800);
  static const Duration extraLong3 = Duration(milliseconds: 900);
  static const Duration extraLong4 = Duration(milliseconds: 1000);
}

class M3Curves {
  /// Standard easing for subtle movement on/off screen
  static const Curve standard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve standardDecelerate = Cubic(0.0, 0.0, 0.0, 1.0);
  static const Curve standardAccelerate = Cubic(0.3, 0.0, 1.0, 1.0);

  /// Emphasized easing for expressive, noticeable UI transitions (Android 14+)
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);
  static const Curve emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);

  /// Elastic/Spring curves for tactile press feedback
  static const Curve springBounce = Cubic(0.34, 1.56, 0.64, 1.0);
}

/// =========================================================================
/// 1. TACTILE PRESS MICRO-INTERACTION (AnimatedPressable)
/// Adds an Android M3 tactile spring scale response on button/item press.
/// =========================================================================

class AnimatedPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleDownFactor;
  final Duration duration;
  final bool enableHaptic;
  final BorderRadius? borderRadius;
  final HitTestBehavior behavior;

  const AnimatedPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleDownFactor = 0.96,
    this.duration = const Duration(milliseconds: 120),
    this.enableHaptic = true,
    this.borderRadius,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<AnimatedPressable> createState() => _AnimatedPressableState();
}

class _AnimatedPressableState extends State<AnimatedPressable>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      reverseDuration: const Duration(milliseconds: 160),
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.scaleDownFactor,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
        reverseCurve: M3Curves.springBounce,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    _controller.forward();
    if (widget.enableHaptic) {
      HapticFeedback.lightImpact();
    }
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    _controller.reverse();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final hasAction = widget.onTap != null || widget.onLongPress != null;

    return MouseRegion(
      cursor: hasAction ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: widget.behavior,
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: widget.child,
        ),
      ),
    );
  }
}

/// =========================================================================
/// 2. M3 ASYNC ACTION BUTTON (M3ActionButton)
/// Smart M3 Button supporting loading, success, and disabled states smoothly.
/// =========================================================================

enum M3ButtonVariant { filled, tonal, outlined, text }

class M3ActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Future<void> Function()? onPressed;
  final bool isLoading;
  final bool isSuccess;
  final M3ButtonVariant variant;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? width;
  final double height;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;

  const M3ActionButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.isSuccess = false,
    this.variant = M3ButtonVariant.filled,
    this.backgroundColor,
    this.foregroundColor,
    this.width,
    this.height = 48,
    this.padding,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color bg;
    Color fg;
    BorderSide? border;

    switch (variant) {
      case M3ButtonVariant.filled:
        bg = backgroundColor ?? colorScheme.primary;
        fg = foregroundColor ?? colorScheme.onPrimary;
        break;
      case M3ButtonVariant.tonal:
        bg = backgroundColor ?? (isSuccess ? colorScheme.primaryContainer : colorScheme.secondaryContainer);
        fg = foregroundColor ?? (isSuccess ? colorScheme.onPrimaryContainer : colorScheme.onSecondaryContainer);
        break;
      case M3ButtonVariant.outlined:
        bg = backgroundColor ?? Colors.transparent;
        fg = foregroundColor ?? colorScheme.primary;
        border = BorderSide(
          color: isSuccess ? colorScheme.primary : colorScheme.outline,
          width: 1.5,
        );
        break;
      case M3ButtonVariant.text:
        bg = Colors.transparent;
        fg = foregroundColor ?? colorScheme.primary;
        break;
    }

    final effectiveRadius = borderRadius ?? BorderRadius.circular(24);

    return AnimatedPressable(
      onTap: (isLoading || isSuccess || onPressed == null)
          ? null
          : () async {
              if (onPressed != null) {
                await onPressed!();
              }
            },
      child: AnimatedContainer(
        duration: M3Durations.medium2,
        curve: M3Curves.emphasizedDecelerate,
        width: width,
        height: height,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: (onPressed == null && !isLoading && !isSuccess)
              ? colorScheme.onSurface.withValues(alpha: 0.12)
              : bg,
          borderRadius: effectiveRadius,
          border: border != null ? Border.all(color: border.color, width: border.width) : null,
          boxShadow: (variant == M3ButtonVariant.filled && onPressed != null && !isLoading)
              ? [
                  BoxShadow(
                    color: bg.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: AnimatedSwitcher(
          duration: M3Durations.medium1,
          switchInCurve: M3Curves.emphasizedDecelerate,
          switchOutCurve: M3Curves.emphasizedAccelerate,
          child: _buildChildContent(context, fg),
        ),
      ),
    );
  }

  Widget _buildChildContent(BuildContext context, Color fg) {
    if (isLoading) {
      return Row(
        key: const ValueKey('loading'),
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'جاري المعالجة...',
            style: GoogleFonts.cairo(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      );
    }

    if (isSuccess) {
      return Row(
        key: const ValueKey('success'),
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded, color: fg, size: 22),
          const SizedBox(width: 8),
          Text(
            'تم بنجاح',
            style: GoogleFonts.cairo(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      );
    }

    return Row(
      key: const ValueKey('normal'),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: GoogleFonts.cairo(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }
}

/// =========================================================================
/// 3. ANIMATED SUCCESS CHECKMARK (M3SuccessCheckmark)
/// Material Design 3 checkmark with expanding circular ring and drawing path.
/// =========================================================================

class M3SuccessCheckmark extends StatefulWidget {
  final double size;
  final Color? color;
  final VoidCallback? onComplete;

  const M3SuccessCheckmark({
    super.key,
    this.size = 80,
    this.color,
    this.onComplete,
  });

  @override
  State<M3SuccessCheckmark> createState() => _M3SuccessCheckmarkState();
}

class _M3SuccessCheckmarkState extends State<M3SuccessCheckmark>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _checkAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: M3Curves.springBounce),
      ),
    );

    _checkAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 1.0, curve: M3Curves.emphasizedDecelerate),
      ),
    );

    _controller.forward().then((_) {
      if (widget.onComplete != null) widget.onComplete!();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor = widget.color ?? Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: effectiveColor.withValues(alpha: 0.15),
              border: Border.all(color: effectiveColor, width: 3),
            ),
            child: Center(
              child: CustomPaint(
                size: Size(widget.size * 0.5, widget.size * 0.5),
                painter: _CheckmarkPainter(
                  progress: _checkAnimation.value,
                  color: effectiveColor,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CheckmarkPainter extends CustomPainter {
  final double progress;
  final Color color;

  _CheckmarkPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size.width * 0.16;

    final path = Path();
    final p1 = Offset(size.width * 0.15, size.height * 0.52);
    final p2 = Offset(size.width * 0.42, size.height * 0.78);
    final p3 = Offset(size.width * 0.85, size.height * 0.25);

    if (progress < 0.5) {
      final t = progress / 0.5;
      path.moveTo(p1.dx, p1.dy);
      path.lineTo(
        p1.dx + (p2.dx - p1.dx) * t,
        p1.dy + (p2.dy - p1.dy) * t,
      );
    } else {
      final t = (progress - 0.5) / 0.5;
      path.moveTo(p1.dx, p1.dy);
      path.lineTo(p2.dx, p2.dy);
      path.lineTo(
        p2.dx + (p3.dx - p2.dx) * t,
        p2.dy + (p3.dy - p2.dy) * t,
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CheckmarkPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

/// =========================================================================
/// 4. ANIMATED ADD ITEM POP & SPARKLE (M3AddedAnimation)
/// Material Design 3 scale-pop bounce for adding items, gifts, or records.
/// =========================================================================

class M3AddedAnimation extends StatefulWidget {
  final double size;
  final IconData icon;
  final Color? color;

  const M3AddedAnimation({
    super.key,
    this.size = 72,
    this.icon = Icons.add_task_rounded,
    this.color,
  });

  @override
  State<M3AddedAnimation> createState() => _M3AddedAnimationState();
}

class _M3AddedAnimationState extends State<M3AddedAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _scaleAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: M3Curves.springBounce),
    );

    _rotationAnimation = Tween<double>(begin: -math.pi / 4, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: M3Curves.emphasizedDecelerate),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _rotationAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.2),
                    color.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: color, width: 2.5),
              ),
              child: Icon(widget.icon, size: widget.size * 0.55, color: color),
            ),
          ),
        );
      },
    );
  }
}

/// =========================================================================
/// 5. LIST & CARD ENTRY ANIMATION (M3AnimatedListItem)
/// Smooth Slide & Fade in animation when items/cards mount or are added.
/// =========================================================================

class M3AnimatedListItem extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration delay;
  final Axis direction;

  const M3AnimatedListItem({
    super.key,
    required this.child,
    this.index = 0,
    this.delay = const Duration(milliseconds: 40),
    this.direction = Axis.vertical,
  });

  @override
  State<M3AnimatedListItem> createState() => _M3AnimatedListItemState();
}

class _M3AnimatedListItemState extends State<M3AnimatedListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: M3Durations.medium3,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: M3Curves.standardDecelerate,
    );

    final offsetBegin = widget.direction == Axis.vertical
        ? const Offset(0.0, 0.15)
        : const Offset(0.15, 0.0);

    _slideAnimation = Tween<Offset>(
      begin: offsetBegin,
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: M3Curves.emphasizedDecelerate,
      ),
    );

    final itemDelay = Duration(milliseconds: widget.index * widget.delay.inMilliseconds);
    Future.delayed(itemDelay, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}

/// =========================================================================
/// 6. GLOBAL M3 ACTION FEEDBACK SYSTEM (M3Feedback)
/// Pre-built Animated Dialogs, Bottom Sheets & Toasts for Actions & Requests.
/// =========================================================================

class M3Feedback {
  /// Displays an animated Error / Warning Modal for duplicates or invalid actions
  static Future<void> showError(
    BuildContext context, {
    required String title,
    String? message,
    String buttonText = 'حسناً',
    IconData icon = Icons.warning_amber_rounded,
    VoidCallback? onDismiss,
  }) async {
    HapticFeedback.heavyImpact();

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Error Modal',
      barrierColor: Colors.black54,
      transitionDuration: M3Durations.medium3,
      transitionBuilder: (context, anim1, anim2, child) {
        final curveValue = M3Curves.emphasizedDecelerate.transform(anim1.value);
        return Transform.scale(
          scale: 0.85 + (0.15 * curveValue),
          child: Opacity(
            opacity: anim1.value,
            child: child,
          ),
        );
      },
      pageBuilder: (context, anim1, anim2) {
        final colorScheme = Theme.of(context).colorScheme;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: colorScheme.surfaceContainerHigh,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 44,
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              if (message != null && message.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    if (onDismiss != null) onDismiss();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    buttonText,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Displays an animated Duplicate Rejection / Warning Modal
  static Future<void> showDuplicateWarning(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'حسناً، فهمت',
    IconData icon = Icons.warning_amber_rounded,
    VoidCallback? onDismiss,
  }) async {
    HapticFeedback.heavyImpact();

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Duplicate Warning Modal',
      barrierColor: Colors.black54,
      transitionDuration: M3Durations.medium3,
      transitionBuilder: (context, anim1, anim2, child) {
        final curveValue = M3Curves.emphasizedDecelerate.transform(anim1.value);
        return Transform.scale(
          scale: 0.85 + (0.15 * curveValue),
          child: Opacity(
            opacity: anim1.value,
            child: child,
          ),
        );
      },
      pageBuilder: (context, anim1, anim2) {
        final colorScheme = Theme.of(context).colorScheme;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: colorScheme.surfaceContainerHigh,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 44,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              if (message.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    if (onDismiss != null) onDismiss();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.secondary,
                    foregroundColor: colorScheme.onSecondary,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    buttonText,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Displays an animated Success / Approval Modal
  static Future<void> showSuccess(
    BuildContext context, {
    required String title,
    String? message,
    String buttonText = 'حسناً',
    VoidCallback? onDismiss,
  }) async {
    HapticFeedback.mediumImpact();

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Success Modal',
      barrierColor: Colors.black54,
      transitionDuration: M3Durations.medium3,
      transitionBuilder: (context, anim1, anim2, child) {
        final curveValue = M3Curves.emphasizedDecelerate.transform(anim1.value);
        return Transform.scale(
          scale: 0.85 + (0.15 * curveValue),
          child: Opacity(
            opacity: anim1.value,
            child: child,
          ),
        );
      },
      pageBuilder: (context, anim1, anim2) {
        final colorScheme = Theme.of(context).colorScheme;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: colorScheme.surfaceContainerHigh,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              M3SuccessCheckmark(
                size: 76,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              if (message != null && message.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    if (onDismiss != null) onDismiss();
                  },
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    buttonText,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Displays an animated Item Added Confirmation Modal
  static Future<void> showAdded(
    BuildContext context, {
    required String itemName,
    String? message,
    IconData icon = Icons.add_circle_outline_rounded,
    VoidCallback? onDismiss,
  }) async {
    HapticFeedback.lightImpact();

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Added Modal',
      barrierColor: Colors.black54,
      transitionDuration: M3Durations.medium3,
      transitionBuilder: (context, anim1, anim2, child) {
        final curveValue = M3Curves.springBounce.transform(anim1.value);
        return Transform.scale(
          scale: 0.8 + (0.2 * curveValue),
          child: Opacity(opacity: anim1.value, child: child),
        );
      },
      pageBuilder: (context, anim1, anim2) {
        final colorScheme = Theme.of(context).colorScheme;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: colorScheme.surfaceContainerHigh,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              M3AddedAnimation(
                size: 76,
                icon: icon,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                'تمت الإضافة بنجاح',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message ?? 'تمت إضافة "$itemName" إلى المنظومة بنجاح.',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    if (onDismiss != null) onDismiss();
                  },
                  child: Text(
                    'تم',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Displays an interactive Approval / Confirmation Dialog
  static Future<bool?> showApprovalDialog(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'موافقة واعتماد',
    String cancelText = 'إلغاء',
    IconData icon = Icons.verified_user_rounded,
  }) async {
    final colorScheme = Theme.of(context).colorScheme;

    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Approval Dialog',
      barrierColor: Colors.black54,
      transitionDuration: M3Durations.medium3,
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: anim1,
            curve: M3Curves.emphasizedDecelerate,
          ),
          child: child,
        );
      },
      pageBuilder: (context, anim1, anim2) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: colorScheme.surfaceContainerHigh,
          icon: Icon(icon, color: colorScheme.primary, size: 40),
          title: Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 15,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                cancelText,
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.of(context).pop(true);
              },
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(
                confirmText,
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Displays an animated M3 Loading Dialog with message
  static void showLoading(
    BuildContext context, {
    String message = 'جاري التحميل...',
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return PopScope(
          canPop: false,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Text(
                    message,
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Dismisses any open dialog / modal
  static void dismiss(BuildContext context) {
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  /// Shows an M3 Animated Floating Toast / Banner
  static void showToast(
    BuildContext context, {
    required String message,
    IconData? icon,
    bool isSuccess = true,
    Duration duration = const Duration(seconds: 3),
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final bg = isSuccess ? colorScheme.primaryContainer : colorScheme.errorContainer;
    final fg = isSuccess ? colorScheme.onPrimaryContainer : colorScheme.onErrorContainer;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        duration: duration,
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: fg.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: fg, size: 22),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.cairo(
                    color: fg,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// =========================================================================
/// 7. M3 PAGE ROUTE & TRANSITIONS (M3PageRoute & PageTransitionsBuilder)
/// Smooth Shared Axis & Fade Through page transitions.
/// =========================================================================

class M3PageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  M3PageRoute({
    required this.page,
    super.settings,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: M3Durations.medium3,
          reverseTransitionDuration: M3Durations.medium2,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final fadeIn = CurvedAnimation(
              parent: animation,
              curve: const Interval(0.0, 0.7, curve: M3Curves.standardDecelerate),
            );

            final scaleIn = Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: M3Curves.emphasizedDecelerate,
              ),
            );

            final slideIn = Tween<Offset>(
              begin: const Offset(0.05, 0.0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: M3Curves.emphasizedDecelerate,
              ),
            );

            return FadeTransition(
              opacity: fadeIn,
              child: ScaleTransition(
                scale: scaleIn,
                child: SlideTransition(
                  position: slideIn,
                  child: child,
                ),
              ),
            );
          },
        );
}

/// M3 Page Transitions Builder for Theme integration
class M3PageTransitionsBuilder extends PageTransitionsBuilder {
  const M3PageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final fadeIn = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.7, curve: M3Curves.standardDecelerate),
    );

    final scaleIn = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: M3Curves.emphasizedDecelerate,
      ),
    );

    final slideIn = Tween<Offset>(
      begin: const Offset(0.04, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: animation,
        curve: M3Curves.emphasizedDecelerate,
      ),
    );

    return FadeTransition(
      opacity: fadeIn,
      child: ScaleTransition(
        scale: scaleIn,
        child: SlideTransition(
          position: slideIn,
          child: child,
        ),
      ),
    );
  }
}
