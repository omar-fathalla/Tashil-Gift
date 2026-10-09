import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/animations/m3_motion.dart';
import '../../../core/services/game_audio_service.dart';
import '../../admin/domain/event_model.dart';

/// Shows a world-class, celebratory M3 Winner Dialog with Confetti and Spring Motion
Future<void> showWinnerCelebrationDialog({
  required BuildContext context,
  required String prizeName,
  required VoidCallback onNextCustomer,
  int remainingChances = 0,
  VoidCallback? onNextChance,
  String? nextChanceLabel,
  double? unitValue,
  bool? isVoucher,
  List<LinkedGiftAllocation> linkedGifts = const [],
  String? imageUrl,
  String? recipientPhone,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'WinnerCelebration',
    barrierColor: Colors.black.withValues(alpha: 0.75),
    transitionDuration: const Duration(milliseconds: 600),
    transitionBuilder: (context, anim1, anim2, child) {
      final curved = CurvedAnimation(parent: anim1, curve: Curves.easeOutBack);
      return ScaleTransition(
        scale: curved,
        child: FadeTransition(opacity: anim1, child: child),
      );
    },
    pageBuilder: (context, anim1, anim2) {
      return WinnerCelebrationDialog(
        prizeName: prizeName,
        onNextCustomer: onNextCustomer,
        remainingChances: remainingChances,
        onNextChance: onNextChance,
        nextChanceLabel: nextChanceLabel,
        unitValue: unitValue,
        isVoucher: isVoucher,
        linkedGifts: linkedGifts,
        imageUrl: imageUrl,
        recipientPhone: recipientPhone,
      );
    },
  );
}

class WinnerCelebrationDialog extends ConsumerStatefulWidget {
  final String prizeName;
  final VoidCallback onNextCustomer;
  final int remainingChances;
  final VoidCallback? onNextChance;
  final String? nextChanceLabel;
  final double? unitValue;
  final bool? isVoucher;
  final List<LinkedGiftAllocation> linkedGifts;
  final String? imageUrl;
  final String? recipientPhone;

  const WinnerCelebrationDialog({
    super.key,
    required this.prizeName,
    required this.onNextCustomer,
    this.remainingChances = 0,
    this.onNextChance,
    this.nextChanceLabel,
    this.unitValue,
    this.isVoucher,
    this.linkedGifts = const [],
    this.imageUrl,
    this.recipientPhone,
  });

  @override
  ConsumerState<WinnerCelebrationDialog> createState() => _WinnerCelebrationDialogState();
}

class _WinnerCelebrationDialogState extends ConsumerState<WinnerCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _confettiController;
  final List<_ConfettiParticle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    // Trigger triumphant win fanfare sound
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gameAudioServiceProvider).playWinFanfare();
    });

    // Spawn 75 diverse festive particles
    for (int i = 0; i < 75; i++) {
      _particles.add(
        _ConfettiParticle(
          x: _random.nextDouble(),
          y: _random.nextDouble() * -1.0,
          speed: 0.15 + _random.nextDouble() * 0.45,
          size: 6.0 + _random.nextDouble() * 10.0,
          rotation: _random.nextDouble() * 2 * pi,
          rotationSpeed: (_random.nextDouble() - 0.5) * 4,
          color: [
            const Color(0xFFFFD700), // Gold
            const Color(0xFFFF4081), // Pink
            const Color(0xFF7C4DFF), // Purple
            const Color(0xFF00E676), // Green
            const Color(0xFF00B0FF), // Light Blue
            const Color(0xFFFF6D00), // Orange
            const Color(0xFFFFEA00), // Yellow
          ][_random.nextInt(7)],
          shape: _random.nextInt(3), // 0: rect, 1: circle, 2: star
        ),
      );
    }
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Confetti Shower Painter
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _confettiController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _ConfettiPainter(
                      particles: _particles,
                      progress: _confettiController.value,
                    ),
                  );
                },
              ),
            ),
          ),

          // Main Celebratory Card
          Center(
            child: Container(
              width: min(MediaQuery.of(context).size.width * 0.9, 440),
              margin: const EdgeInsets.symmetric(horizontal: 20),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.88,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.6),
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                        blurRadius: 36,
                        spreadRadius: 4,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Golden Trophy Icon with Breathing Glow
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              colors: [
                                Color(0xFFFFEA00),
                                Color(0xFFFFB300),
                                Color(0xFFFF8F00),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFFB300).withValues(alpha: 0.5),
                                blurRadius: 24,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.workspace_premium_rounded,
                            size: 50,
                            color: Colors.white,
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Congratulations Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.celebration_rounded,
                                size: 18,
                                color: colorScheme.onPrimaryContainer,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'تهانينا! ألف مبروك',
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text(
                          'لقد فزت بـ:',
                          style: GoogleFonts.cairo(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),

                        const SizedBox(height: 10),

                        // 1. Resolve Voucher & Gift Attributes
                        Builder(
                          builder: (context) {
                            bool resolvedIsVoucher = widget.isVoucher ?? false;
                            double? resolvedUnitValue = widget.unitValue;
                            String cleanPrizeName = widget.prizeName.trim();

                            final isRawDocId = RegExp(r'^[a-zA-Z0-9_-]{15,35}$').hasMatch(cleanPrizeName);

                            // 1. Resolve from linked gifts bundle if available
                            if (widget.linkedGifts.isNotEmpty &&
                                (cleanPrizeName.isEmpty ||
                                 cleanPrizeName == 'هدية ترويجية مميزة' ||
                                 cleanPrizeName == 'هدية فورية مميزة' ||
                                 isRawDocId)) {
                              cleanPrizeName = widget.linkedGifts.map((g) => g.quantity > 1 ? '${g.quantity} × ${g.giftName}' : g.giftName).join(' + ');
                              resolvedUnitValue ??= widget.linkedGifts.fold<double>(0.0, (sum, g) => sum + g.totalMonetaryValue);
                              resolvedIsVoucher = widget.linkedGifts.any((g) => g.isVoucher);
                            }

                            final lowerName = cleanPrizeName.toLowerCase();
                            final hasVoucherKeyword = lowerName.contains('فواتشر') ||
                                lowerName.contains('voucher') ||
                                lowerName.contains('قسيمة');

                            if (hasVoucherKeyword) {
                              resolvedIsVoucher = true;
                              if (resolvedUnitValue == null || resolvedUnitValue == 0.0) {
                                final match = RegExp(r'(\d+)').firstMatch(cleanPrizeName);
                                if (match != null) {
                                  resolvedUnitValue = double.tryParse(match.group(1)!);
                                }
                              }
                            } else if (widget.isVoucher == false) {
                              resolvedIsVoucher = false;
                              resolvedUnitValue = null;
                            } else if (widget.isVoucher == null) {
                              // If isVoucher was not passed, detect physical product units to prevent false voucher
                              if (lowerName.contains('مل') ||
                                  lowerName.contains('ml') ||
                                  lowerName.contains('جم') ||
                                  lowerName.contains('gm') ||
                                  lowerName.contains('شامبو') ||
                                  lowerName.contains('بلسم') ||
                                  lowerName.contains('قطعة')) {
                                resolvedIsVoucher = false;
                                resolvedUnitValue = null;
                              }
                            }

                            // 3. Fallback naming
                            if (isRawDocId || cleanPrizeName.isEmpty || cleanPrizeName == 'هدية ترويجية مميزة' || cleanPrizeName == 'هدية فورية مميزة') {
                              if (resolvedIsVoucher && resolvedUnitValue != null && resolvedUnitValue > 0) {
                                final val = (resolvedUnitValue == resolvedUnitValue.roundToDouble() ? resolvedUnitValue.toInt() : resolvedUnitValue);
                                cleanPrizeName = 'فواتشر $val جنيه';
                              } else if (resolvedIsVoucher) {
                                cleanPrizeName = 'كارت فواتشر مشتريات';
                              } else {
                                cleanPrizeName = 'هدية فورية معتمدة';
                              }
                            }

                            final formattedVal = (resolvedIsVoucher && resolvedUnitValue != null && resolvedUnitValue > 0)
                                ? (resolvedUnitValue == resolvedUnitValue.roundToDouble()
                                    ? resolvedUnitValue.toInt().toString()
                                    : resolvedUnitValue.toString())
                                : '';

                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: resolvedIsVoucher
                                      ? [
                                          const Color(0xFFFFD700).withValues(alpha: 0.22),
                                          colorScheme.primaryContainer.withValues(alpha: 0.55),
                                        ]
                                      : [
                                          const Color(0xFFE8F5E9).withValues(alpha: 0.6),
                                          colorScheme.primaryContainer.withValues(alpha: 0.4),
                                        ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: resolvedIsVoucher
                                      ? const Color(0xFFFFB300)
                                      : colorScheme.primary.withValues(alpha: 0.3),
                                  width: resolvedIsVoucher ? 2.0 : 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: resolvedIsVoucher
                                        ? const Color(0xFFFFB300).withValues(alpha: 0.25)
                                        : colorScheme.primary.withValues(alpha: 0.1),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  // Icon or Product Image Thumbnail
                                  Builder(
                                    builder: (context) {
                                      final effectiveImageUrl = (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
                                          ? widget.imageUrl
                                          : (widget.linkedGifts.isNotEmpty && widget.linkedGifts.first.imageUrl != null && widget.linkedGifts.first.imageUrl!.isNotEmpty
                                              ? widget.linkedGifts.first.imageUrl
                                              : null);

                                      if (effectiveImageUrl != null && effectiveImageUrl.isNotEmpty) {
                                        return Container(
                                          width: 76,
                                          height: 76,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(
                                              color: resolvedIsVoucher
                                                  ? const Color(0xFFFF8F00).withValues(alpha: 0.5)
                                                  : colorScheme.primary.withValues(alpha: 0.5),
                                              width: 2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: (resolvedIsVoucher ? const Color(0xFFFF8F00) : colorScheme.primary).withValues(alpha: 0.2),
                                                blurRadius: 12,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(18),
                                            child: Image.network(
                                              effectiveImageUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) => Container(
                                                color: resolvedIsVoucher
                                                    ? const Color(0xFFFF8F00).withValues(alpha: 0.15)
                                                    : colorScheme.primary.withValues(alpha: 0.1),
                                                child: Icon(
                                                  resolvedIsVoucher
                                                      ? Icons.confirmation_number_rounded
                                                      : Icons.card_giftcard_rounded,
                                                  size: 40,
                                                  color: resolvedIsVoucher ? const Color(0xFFFF8F00) : colorScheme.primary,
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }

                                      return Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: resolvedIsVoucher
                                              ? const Color(0xFFFF8F00).withValues(alpha: 0.15)
                                              : colorScheme.primary.withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          resolvedIsVoucher
                                              ? Icons.confirmation_number_rounded
                                              : Icons.card_giftcard_rounded,
                                          size: 40,
                                          color: resolvedIsVoucher ? const Color(0xFFFF8F00) : colorScheme.primary,
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 10),

                                  // Voucher or Physical Gift Certified Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          resolvedIsVoucher ? Icons.verified_rounded : Icons.check_circle_rounded,
                                          size: 14,
                                          color: resolvedIsVoucher ? const Color(0xFFFF8F00) : colorScheme.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          resolvedIsVoucher ? 'كارت فواتشر مشتريات معتمد' : 'هدية عينية فورية معتمدة',
                                          style: GoogleFonts.cairo(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // Prize Name Title
                                  Text(
                                    cleanPrizeName,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.cairo(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: colorScheme.onSurface,
                                      height: 1.3,
                                    ),
                                  ),

                                  // PROMINENT VOUCHER MONETARY VALUE BADGE (ONLY for vouchers)
                                  if (resolvedIsVoucher && formattedVal.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFFFFB300),
                                            Color(0xFFFF6D00),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFFF8F00).withValues(alpha: 0.45),
                                            blurRadius: 16,
                                            spreadRadius: 1,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.payments_rounded, color: Colors.white, size: 22),
                                          const SizedBox(width: 8),
                                          Text(
                                            'بقيمة $formattedVal ج.م',
                                            style: GoogleFonts.cairo(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'صالحة للاستخدام الفوري لدى الكاشير',
                                      style: GoogleFonts.cairo(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ] else if (!resolvedIsVoucher) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'يرجى استلام هديتك من ممثل الشركة في الفرع',
                                      style: GoogleFonts.cairo(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],

                                  // Multi-Card Breakdown Display
                                  if (widget.linkedGifts.length > 1 ||
                                      (widget.linkedGifts.length == 1 && widget.linkedGifts.first.quantity > 1)) ...[
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      alignment: WrapAlignment.center,
                                      children: widget.linkedGifts.map((g) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.shade50,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.amber.shade300),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                g.isVoucher
                                                    ? Icons.confirmation_number_rounded
                                                    : Icons.card_giftcard_rounded,
                                                size: 13,
                                                color: Colors.amber.shade900,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${g.quantity} × ${g.giftName}',
                                                style: GoogleFonts.cairo(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.amber.shade900,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),

                        if (widget.recipientPhone != null && widget.recipientPhone!.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF25D366).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF25D366).withValues(alpha: 0.4),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.mark_chat_read_rounded, color: Color(0xFF1E7E34), size: 18),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'تم إرسال إشعار الهدية عبر الواتساب إلى ${widget.recipientPhone!.trim()} 📲',
                                    style: GoogleFonts.cairo(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF1E7E34),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        if (widget.remainingChances > 0) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.stars_rounded, size: 20, color: colorScheme.onTertiaryContainer),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    '✨ متبقي لديك ${widget.remainingChances} ${widget.remainingChances == 1 ? 'فرصة سحب أخرى!' : 'فرص سحب إضافية!'}',
                                    style: GoogleFonts.cairo(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onTertiaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // Action Buttons
                        if (widget.remainingChances > 0) ...[
                          M3ActionButton(
                            label: widget.nextChanceLabel ?? 'سحب الفرصة التالية (متبقي ${widget.remainingChances})',
                            icon: widget.nextChanceLabel != null ? Icons.card_giftcard_rounded : Icons.casino_rounded,
                            variant: M3ButtonVariant.filled,
                            onPressed: () async {
                              Navigator.of(context).pop();
                              widget.onNextChance?.call();
                            },
                          ),
                          const SizedBox(height: 10),
                          M3ActionButton(
                            label: 'إنهاء واستلام الجوائز',
                            icon: Icons.check_circle_outline_rounded,
                            variant: M3ButtonVariant.tonal,
                            onPressed: () async {
                              Navigator.of(context).pop();
                              widget.onNextCustomer();
                            },
                          ),
                        ] else ...[
                          M3ActionButton(
                            label: 'تم (العميل التالي)',
                            icon: Icons.check_circle_rounded,
                            variant: M3ButtonVariant.filled,
                            onPressed: () async {
                              Navigator.of(context).pop();
                              widget.onNextCustomer();
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfettiParticle {
  double x;
  double y;
  double speed;
  double size;
  double rotation;
  double rotationSpeed;
  Color color;
  int shape;

  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.rotation,
    required this.rotationSpeed,
    required this.color,
    required this.shape,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter({
    required this.particles,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (var p in particles) {
      final currentY = ((p.y + progress * p.speed * 4) % 1.2) * size.height;
      final currentX = (p.x * size.width) + sin(progress * 2 * pi + p.x * 10) * 20;
      final currentRotation = p.rotation + progress * p.rotationSpeed * 2 * pi;

      paint.color = p.color;

      canvas.save();
      canvas.translate(currentX, currentY);
      canvas.rotate(currentRotation);

      if (p.shape == 0) {
        // Rectangle ribbon
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
          paint,
        );
      } else if (p.shape == 1) {
        // Circle particle
        canvas.drawCircle(Offset.zero, p.size * 0.4, paint);
      } else {
        // Diamond / Star
        final path = Path()
          ..moveTo(0, -p.size * 0.6)
          ..lineTo(p.size * 0.4, 0)
          ..lineTo(0, p.size * 0.6)
          ..lineTo(-p.size * 0.4, 0)
          ..close();
        canvas.drawPath(path, paint);
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}
