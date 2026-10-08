import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/receipt_image_calibrator.dart';
import 'm3_progress_indicators.dart';

/// Interactive Material Design 3 Optimistic UI card for receipt scanning and AI processing.
///
/// Provides instant 0ms visual feedback with an animated laser scanning beam,
/// real-time calibration telemetry (payload reduction percentage), and progressive
/// 3-stage indicators while Cloud Functions and Gemini operate in the background.
class OptimisticReceiptScannerCard extends StatefulWidget {
  /// Raw or calibrated receipt image bytes for the thumbnail.
  final Uint8List? imageBytes;

  /// Current processing phase (0 = Calibration, 1 = AI Cloud Extraction, 2 = Rules & Prizes, 3 = Complete).
  final int activePhase;

  /// Explanatory status text shown to the user.
  final String statusText;

  /// Optional calibration telemetry output.
  final CalibratedImageResult? calibrationResult;

  /// Whether the entire analysis completed successfully.
  final bool isCompleted;

  /// Optional cancellation callback.
  final VoidCallback? onCancel;

  const OptimisticReceiptScannerCard({
    super.key,
    this.imageBytes,
    required this.activePhase,
    required this.statusText,
    this.calibrationResult,
    this.isCompleted = false,
    this.onCancel,
  });

  @override
  State<OptimisticReceiptScannerCard> createState() =>
      _OptimisticReceiptScannerCardState();
}

class _OptimisticReceiptScannerCardState
    extends State<OptimisticReceiptScannerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _laserController;
  late final Animation<double> _laserAnimation;

  @override
  void initState() {
    super.initState();
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _laserAnimation = Tween<double>(begin: 0.05, end: 0.95).animate(
      CurvedAnimation(
        parent: _laserController,
        curve: Curves.easeInOutSine,
      ),
    );

    if (!widget.isCompleted) {
      _laserController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant OptimisticReceiptScannerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCompleted && _laserController.isAnimating) {
      _laserController.stop();
    } else if (!widget.isCompleted && !_laserController.isAnimating) {
      _laserController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _laserController.dispose();
    super.dispose();
  }

  double get _progressFraction {
    if (widget.isCompleted) return 1.0;
    switch (widget.activePhase) {
      case 0:
        return 0.35;
      case 1:
        return 0.70;
      case 2:
        return 0.90;
      default:
        return 0.50;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 3,
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: widget.isCompleted
              ? Colors.green.shade400
              : colorScheme.primary.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Row: Scanning Thumbnail + Live Status Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Animated Viewfinder Preview with Laser Beam
                _buildScanningViewfinder(colorScheme),
                const SizedBox(width: 14),
                // Titles and Live Telemetry
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            widget.isCompleted
                                ? Icons.verified_rounded
                                : Icons.auto_awesome_rounded,
                            size: 18,
                            color: widget.isCompleted
                                ? Colors.green.shade600
                                : colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              widget.isCompleted
                                  ? 'اكتمل التدقيق بنجاح'
                                  : 'المسح والمعالجة الذكية اللحظية',
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                                color: colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.statusText,
                        style: GoogleFonts.cairo(
                          fontSize: 12.5,
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // Payload Reduction Badge if calibrated
                      if (widget.calibrationResult != null &&
                          widget.calibrationResult!.compressionRatio > 5.0) ...[
                        const SizedBox(height: 6),
                        _buildCompressionBadge(
                          widget.calibrationResult!,
                          colorScheme,
                          isDark,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Animated Smooth M3 Progress Bar
            M3LinearProgress(
              value: widget.isCompleted ? 1.0 : _progressFraction,
              height: 6.0,
              color: widget.isCompleted ? Colors.green.shade500 : colorScheme.primary,
            ),

            const SizedBox(height: 14),

            // 3-Stage Optimistic Stepper Row
            _buildPhaseStepper(colorScheme),
          ],
        ),
      ),
    );
  }

  /// Compact viewfinder with laser scanning motion over receipt thumbnail.
  Widget _buildScanningViewfinder(ColorScheme colorScheme) {
    return Container(
      width: 72,
      height: 94,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.2),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10.5),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Receipt image background
            if (widget.imageBytes != null && widget.imageBytes!.isNotEmpty)
              Image.memory(
                widget.imageBytes!,
                fit: BoxFit.cover,
              )
            else
              Container(
                color: Colors.grey.shade900,
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: Colors.white54,
                  size: 32,
                ),
              ),

            // Subtle dark overlay to make laser pop
            Container(color: Colors.black.withValues(alpha: 0.25)),

            // Viewfinder Corner Brackets
            CustomPaint(
              painter: _ViewfinderCornersPainter(colorScheme.primary),
            ),

            // Animated Laser Beam
            if (!widget.isCompleted)
              AnimatedBuilder(
                animation: _laserAnimation,
                builder: (context, _) {
                  return Positioned(
                    top: _laserAnimation.value * 94 - 2,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.primary.withValues(alpha: 0.0),
                            colorScheme.primary,
                            const Color(0xFF67E8F9), // vibrant cyan highlight
                            colorScheme.primary,
                            colorScheme.primary.withValues(alpha: 0.0),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF22D3EE).withValues(alpha: 0.8),
                            blurRadius: 8,
                            spreadRadius: 1.5,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

            // Completed checkmark overlay
            if (widget.isCompleted)
              Container(
                color: Colors.black.withValues(alpha: 0.45),
                child: const Center(
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: Colors.greenAccent,
                    size: 36,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Telemetry badge displaying payload compression stats.
  Widget _buildCompressionBadge(
    CalibratedImageResult result,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.green.shade900.withValues(alpha: 0.35)
            : Colors.green.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.green.shade400.withValues(alpha: 0.5),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.speed_rounded,
            size: 13,
            color: Colors.green.shade700,
          ),
          const SizedBox(width: 4),
          Text(
            'معايرة سريعة: تم تخفيض الحجم بنسبة ${result.compressionRatio.toStringAsFixed(0)}% (${result.sizeSavedKbLabel})',
            style: GoogleFonts.cairo(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade800,
            ),
          ),
        ],
      ),
    );
  }

  /// 3-Stage optimistic progress indicators row.
  Widget _buildPhaseStepper(ColorScheme colorScheme) {
    final stages = [
      {'title': '1. المعايرة محلياً', 'icon': Icons.tune_rounded},
      {'title': '2. الذكاء الاصطناعي', 'icon': Icons.cloud_sync_rounded},
      {'title': '3. استحقاق الجوائز', 'icon': Icons.card_giftcard_rounded},
    ];

    return Row(
      children: List.generate(stages.length, (index) {
        final isDone = widget.isCompleted || widget.activePhase > index;
        final isActive = !widget.isCompleted && widget.activePhase == index;
        final stage = stages[index];

        return Expanded(
          child: Container(
            margin: EdgeInsets.only(
              right: index < stages.length - 1 ? 4 : 0,
              left: index > 0 ? 4 : 0,
            ),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: isDone
                  ? Colors.green.withValues(alpha: 0.12)
                  : (isActive
                      ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                      : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDone
                    ? Colors.green.shade400
                    : (isActive
                        ? colorScheme.primary
                        : colorScheme.outlineVariant.withValues(alpha: 0.4)),
                width: isActive ? 1.2 : 0.8,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isDone)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 13,
                    color: Colors.green,
                  )
                else if (isActive)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: colorScheme.primary,
                    ),
                  )
                else
                  Icon(
                    stage['icon'] as IconData,
                    size: 12,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    stage['title'] as String,
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      fontWeight: isActive || isDone
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: isDone
                          ? Colors.green.shade800
                          : (isActive
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// Custom painter for camera viewfinder corner brackets.
class _ViewfinderCornersPainter extends CustomPainter {
  final Color color;

  _ViewfinderCornersPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    const cornerLength = 8.0;

    // Top-Left
    canvas.drawLine(const Offset(4, 4), const Offset(4 + cornerLength, 4), paint);
    canvas.drawLine(const Offset(4, 4), const Offset(4, 4 + cornerLength), paint);

    // Top-Right
    canvas.drawLine(Offset(size.width - 4, 4), Offset(size.width - 4 - cornerLength, 4), paint);
    canvas.drawLine(Offset(size.width - 4, 4), Offset(size.width - 4, 4 + cornerLength), paint);

    // Bottom-Left
    canvas.drawLine(Offset(4, size.height - 4), Offset(4 + cornerLength, size.height - 4), paint);
    canvas.drawLine(Offset(4, size.height - 4), Offset(4, size.height - 4 - cornerLength), paint);

    // Bottom-Right
    canvas.drawLine(Offset(size.width - 4, size.height - 4), Offset(size.width - 4 - cornerLength, size.height - 4), paint);
    canvas.drawLine(Offset(size.width - 4, size.height - 4), Offset(size.width - 4, size.height - 4 - cornerLength), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
