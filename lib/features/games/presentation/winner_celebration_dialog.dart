import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/animations/m3_motion.dart';
import '../../../core/services/game_audio_service.dart';

/// Shows a world-class, celebratory M3 Winner Dialog with Confetti and Spring Motion
Future<void> showWinnerCelebrationDialog({
  required BuildContext context,
  required String prizeName,
  required VoidCallback onNextCustomer,
  int remainingChances = 0,
  VoidCallback? onNextChance,
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
      );
    },
  );
}

class WinnerCelebrationDialog extends ConsumerStatefulWidget {
  final String prizeName;
  final VoidCallback onNextCustomer;
  final int remainingChances;
  final VoidCallback? onNextChance;

  const WinnerCelebrationDialog({
    super.key,
    required this.prizeName,
    required this.onNextCustomer,
    this.remainingChances = 0,
    this.onNextChance,
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

                        // Prize Card with Golden Rim
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFFFFD700).withValues(alpha: 0.15),
                                colorScheme.primaryContainer.withValues(alpha: 0.4),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: colorScheme.primary.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.card_giftcard_rounded,
                                size: 36,
                                color: Color(0xFFFF8F00),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                widget.prizeName,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.cairo(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: colorScheme.primary,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),

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
                            label: 'سحب الفرصة التالية (متبقي ${widget.remainingChances})',
                            icon: Icons.casino_rounded,
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
