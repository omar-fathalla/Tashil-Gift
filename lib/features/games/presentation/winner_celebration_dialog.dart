import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/animations/m3_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/game_audio_service.dart';
import '../../admin/domain/event_model.dart';
import '../../company_portal/domain/whatsapp_gateway_service.dart';

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
  Future<WhatsAppGatewayResult?>? whatsappDispatchFuture,
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
        whatsappDispatchFuture: whatsappDispatchFuture,
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
  final Future<WhatsAppGatewayResult?>? whatsappDispatchFuture;

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
    this.whatsappDispatchFuture,
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

    // Listen to WhatsApp dispatch completion to show a floating toast alert for the promoter
    widget.whatsappDispatchFuture?.then((result) {
      if (!mounted || result == null) return;
      final phone = (result.recipientPhone ?? widget.recipientPhone ?? '').trim();
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      if (result.isSuccess) {
        final cs = Theme.of(context).colorScheme;
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: cs.primary,
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                children: [
                  Icon(Icons.mark_chat_read_rounded, color: cs.primaryContainer, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      phone.isNotEmpty
                          ? '✅ تنبيه للمندوبة: تم إرسال تهنئة الهدية للعميل على الواتساب ($phone) 📲'
                          : '✅ تنبيه للمندوبة: تم إرسال تهنئة الهدية للعميل على الواتساب بنجاح 📲',
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: cs.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    });

    // Spawn 75 diverse festive particles from M3 dynamic tonal palette
    final initialPalette = AppTheme.getDynamicPalette(AppTheme.lightTheme.colorScheme);
    for (int i = 0; i < 75; i++) {
      _particles.add(
        _ConfettiParticle(
          x: _random.nextDouble(),
          y: _random.nextDouble() * -1.0,
          speed: 0.15 + _random.nextDouble() * 0.45,
          size: 6.0 + _random.nextDouble() * 10.0,
          rotation: _random.nextDouble() * 2 * pi,
          rotationSpeed: (_random.nextDouble() - 0.5) * 4,
          color: initialPalette[_random.nextInt(initialPalette.length)],
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
                      color: colorScheme.primary.withValues(alpha: 0.6),
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.35),
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
                        // Trophy Icon with Breathing Glow
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                colorScheme.primaryContainer,
                                colorScheme.primary,
                                colorScheme.onPrimaryFixedVariant,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.primary.withValues(alpha: 0.5),
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

                        // 1. Resolve Voucher & Gift Attributes and Render Prize Presentation
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

                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: resolvedIsVoucher
                                          ? [
                                              colorScheme.secondaryContainer.withValues(alpha: 0.7),
                                              colorScheme.primaryContainer.withValues(alpha: 0.55),
                                            ]
                                          : [
                                              colorScheme.tertiaryContainer.withValues(alpha: 0.6),
                                              colorScheme.primaryContainer.withValues(alpha: 0.4),
                                            ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: resolvedIsVoucher
                                          ? colorScheme.primary
                                          : colorScheme.primary.withValues(alpha: 0.3),
                                      width: resolvedIsVoucher ? 2.0 : 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: colorScheme.primary.withValues(alpha: resolvedIsVoucher ? 0.25 : 0.1),
                                        blurRadius: 16,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      // Prominent Product Image / Gift Graphic
                                      Builder(
                                        builder: (context) {
                                          final effectiveImageUrl = (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
                                              ? widget.imageUrl
                                              : (widget.linkedGifts.isNotEmpty && widget.linkedGifts.first.imageUrl != null && widget.linkedGifts.first.imageUrl!.isNotEmpty
                                                  ? widget.linkedGifts.first.imageUrl
                                                  : null);

                                          if (effectiveImageUrl != null && effectiveImageUrl.isNotEmpty) {
                                            return Container(
                                              width: double.infinity,
                                              height: 175,
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(18),
                                                border: Border.all(
                                                  color: colorScheme.primary.withValues(alpha: 0.25),
                                                  width: 1.5,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: colorScheme.primary.withValues(alpha: 0.08),
                                                    blurRadius: 10,
                                                    offset: const Offset(0, 3),
                                                  ),
                                                ],
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(16),
                                                child: Image.network(
                                                  effectiveImageUrl,
                                                  fit: BoxFit.contain,
                                                  errorBuilder: (context, error, stackTrace) => Container(
                                                    color: colorScheme.primary.withValues(alpha: 0.1),
                                                    child: Center(
                                                      child: Icon(
                                                        resolvedIsVoucher
                                                            ? Icons.confirmation_number_rounded
                                                            : Icons.card_giftcard_rounded,
                                                        size: 54,
                                                        color: colorScheme.primary,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          }

                                          return Container(
                                            width: double.infinity,
                                            height: 140,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(18),
                                              border: Border.all(
                                                color: colorScheme.primary.withValues(alpha: 0.25),
                                                width: 1.5,
                                              ),
                                            ),
                                            child: Center(
                                              child: Icon(
                                                resolvedIsVoucher
                                                    ? Icons.confirmation_number_rounded
                                                    : Icons.card_giftcard_rounded,
                                                size: 54,
                                                color: colorScheme.primary,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 14),

                                      // Prize Name Title with "لقد فزت بـ:"
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        child: RichText(
                                          textAlign: TextAlign.center,
                                          text: TextSpan(
                                            style: GoogleFonts.cairo(
                                              fontSize: 20,
                                              height: 1.3,
                                            ),
                                            children: [
                                              TextSpan(
                                                text: 'لقد فزت بـ: ',
                                                style: GoogleFonts.cairo(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w700,
                                                  color: colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                              TextSpan(
                                                text: cleanPrizeName,
                                                style: GoogleFonts.cairo(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w900,
                                                  color: colorScheme.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                      // PROMINENT VOUCHER MONETARY VALUE BADGE (ONLY for vouchers)
                                      if (resolvedIsVoucher && formattedVal.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                colorScheme.primary,
                                                colorScheme.onPrimaryFixedVariant,
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.circular(16),
                                            boxShadow: [
                                              BoxShadow(
                                                color: colorScheme.primary.withValues(alpha: 0.45),
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
                                                color: colorScheme.secondaryContainer,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.4)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    g.isVoucher
                                                        ? Icons.confirmation_number_rounded
                                                        : Icons.card_giftcard_rounded,
                                                    size: 13,
                                                    color: colorScheme.onSecondaryContainer,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '${g.quantity} × ${g.giftName}',
                                                    style: GoogleFonts.cairo(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: colorScheme.onSecondaryContainer,
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
                                ),

                                // Physical gift claim note placed outside the box in small subtle font
                                if (!resolvedIsVoucher) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'يرجى استلام هديتك من ممثل الشركة في الفرع',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.cairo(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),

                        // WhatsApp Status Card (Material Design 3)
                        const SizedBox(height: 12),
                        if (widget.remainingChances > 0) ...[
                          if (widget.recipientPhone != null && widget.recipientPhone!.trim().isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: colorScheme.tertiaryContainer.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: colorScheme.tertiary.withValues(alpha: 0.55),
                                  width: 1.4,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.schedule_rounded, color: colorScheme.onTertiaryContainer, size: 19),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'إرسال الواتساب بعد اكتمال باقي السحوبات',
                                          style: GoogleFonts.cairo(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: colorScheme.onTertiaryContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'سيتم إرسال رسالة التهنئة بكافة الجوائز على الرقم (${widget.recipientPhone!.trim()}) فور استكمال باقي الفرص',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.cairo(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onTertiaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: colorScheme.secondary,
                                  width: 1.4,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.phone_missed_rounded, color: colorScheme.onSecondaryContainer, size: 19),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'لم يتم إدخال رقم هاتف العميل',
                                          style: GoogleFonts.cairo(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: colorScheme.onSecondaryContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'لم يتم تسجيل رقم الهاتف عند إدخال الفاتورة، ولن يتم إرسال رسالة التهنئة بالجوائز',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.cairo(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ] else ...[
                          if (widget.recipientPhone == null || widget.recipientPhone!.trim().isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: colorScheme.secondary,
                                  width: 1.4,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.phone_missed_rounded, color: colorScheme.onSecondaryContainer, size: 19),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'لم يتم إدخال رقم هاتف العميل',
                                          style: GoogleFonts.cairo(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: colorScheme.onSecondaryContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'لم يتم إدخال رقم هاتف العميل — لم يتم إرسال رسالة واتساب للعميل بالجوائز',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.cairo(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (widget.whatsappDispatchFuture != null)
                            FutureBuilder<WhatsAppGatewayResult?>(
                              future: widget.whatsappDispatchFuture,
                              builder: (context, snapshot) {
                                final isWaiting = snapshot.connectionState == ConnectionState.waiting;
                                final result = snapshot.data;
                                final resolvedPhone = (result?.recipientPhone ?? widget.recipientPhone ?? '').trim();

                                final isFailed = !isWaiting && result != null && !result.isSuccess;
                                final bgColor = isFailed
                                    ? colorScheme.secondaryContainer
                                    : colorScheme.tertiaryContainer.withValues(alpha: 0.6);
                                final borderColor = isFailed
                                    ? colorScheme.secondary
                                    : colorScheme.tertiary.withValues(alpha: 0.65);
                                final textColor = isFailed
                                    ? colorScheme.onSecondaryContainer
                                    : colorScheme.onTertiaryContainer;

                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 280),
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: bgColor,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: borderColor,
                                      width: 1.4,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          if (isWaiting)
                                            SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: colorScheme.tertiary,
                                              ),
                                            )
                                          else
                                            Icon(
                                              isFailed
                                                  ? Icons.warning_amber_rounded
                                                  : Icons.check_circle_rounded,
                                              color: textColor,
                                              size: 19,
                                            ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              isWaiting
                                                  ? 'جاري إرسال رسالة الواتساب...'
                                                  : (isFailed
                                                      ? 'تعذر إرسال الواتساب'
                                                      : 'تم إرسال الواتساب بنجاح'),
                                              style: GoogleFonts.cairo(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: textColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        isWaiting
                                            ? (resolvedPhone.isNotEmpty
                                                ? 'يتم الآن إرسال تفاصيل الهدية إلى الرقم ($resolvedPhone)'
                                                : 'يتم الآن إرسال رسالة تهنئة الهدية للعميل عبر الواتساب')
                                            : (isFailed
                                                ? 'تعذر توصيل الرسالة إلى الرقم ($resolvedPhone) — تأكد من تفعيل الرقم على الواتساب'
                                                : (resolvedPhone.isNotEmpty
                                                    ? 'تم إرسال رسالة التهنئة وتفاصيل الهدية للعميل على الرقم ($resolvedPhone)'
                                                    : 'تم إرسال رسالة التهنئة وتفاصيل الهدية للعميل عبر الواتساب')),
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.cairo(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: textColor.withValues(alpha: 0.95),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            )
                          else
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: colorScheme.tertiaryContainer.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: colorScheme.tertiary.withValues(alpha: 0.65),
                                  width: 1.4,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle_rounded, color: colorScheme.onTertiaryContainer, size: 19),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'تم إرسال الواتساب بنجاح',
                                          style: GoogleFonts.cairo(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: colorScheme.onTertiaryContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'تم إرسال رسالة التهنئة وتفاصيل الهدية للعميل على الرقم (${widget.recipientPhone!.trim()})',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.cairo(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onTertiaryContainer,
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

                        // Action Buttons: Mandatory Multi-Chance Draw Enforcement
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
