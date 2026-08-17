import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/services/company_gifts_service.dart';
import '../../../core/services/game_audio_service.dart';
import '../../../core/widgets/game_sound_controls.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/animations/m3_motion.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/widgets/switch_point_branding.dart';
import 'winner_celebration_dialog.dart';
import 'game_demo_banner.dart';

/// Screen displayed when an event uses the "Direct Instant Gift" (الهدية الفورية المباشرة) game type.
/// The customer is awarded the designated promotional gift immediately upon verified purchase.
class DirectGiftClaimScreen extends ConsumerStatefulWidget {
  final String transactionId;
  final String eventId;
  final String prizeName;
  final int quantity;
  final String? branchId;
  final bool isDemo;

  const DirectGiftClaimScreen({
    super.key,
    this.transactionId = '',
    this.eventId = '',
    required this.prizeName,
    this.quantity = 1,
    this.branchId,
    this.isDemo = false,
  });

  @override
  ConsumerState<DirectGiftClaimScreen> createState() => _DirectGiftClaimScreenState();
}

class _DirectGiftClaimScreenState extends ConsumerState<DirectGiftClaimScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  bool _isClaiming = false;
  bool _isClaimed = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );

    _animController.forward();

    // Play subtle joyful unlock sound effect upon viewing instant gift
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gameAudioServiceProvider).playGiftUnlock();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _resetDemo() {
    setState(() {
      _isClaiming = false;
      _isClaimed = false;
    });
    _animController.reset();
    _animController.forward();
    ref.read(gameAudioServiceProvider).playGiftUnlock();
  }

  Future<void> _claimAndHandoverGift() async {
    if (_isClaiming || _isClaimed) return;

    setState(() => _isClaiming = true);

    try {
      final effectiveQuantity = widget.quantity > 0 ? widget.quantity : 1;
      final displayPrize = effectiveQuantity > 1
          ? '${widget.prizeName} (عدد $effectiveQuantity)'
          : widget.prizeName;

      if (!widget.isDemo && widget.transactionId.isNotEmpty) {
        final firestore = ref.read(firestoreProvider);
        // 1. Update receipts_transactions record
        await firestore.collection('receipts_transactions').doc(widget.transactionId).update({
          'game_played': true,
          'game_type': 'directGift',
          'prize_won': displayPrize,
          'prizes_won': List.filled(effectiveQuantity, widget.prizeName),
          'remaining_chances': 0,
          'claim_status': 'handed_over',
          'claimed_at': DateTime.now().toIso8601String(),
        });

        // 2. Decrement inventory from campaign/branch
        if (widget.eventId.isNotEmpty) {
          final giftsService = ref.read(companyGiftsServiceProvider);
          await giftsService.decrementCampaignPrize(
            widget.eventId,
            widget.prizeName,
            branchId: widget.branchId,
            count: effectiveQuantity,
          );
        }
      } else {
        // Demo simulation pause
        await Future.delayed(const Duration(milliseconds: 600));
      }

      if (!mounted) return;

      setState(() {
        _isClaiming = false;
        _isClaimed = true;
      });

      // 3. Trigger celebration modal
      await showWinnerCelebrationDialog(
        context: context,
        prizeName: displayPrize,
        remainingChances: 0,
        onNextChance: null,
        onNextCustomer: () {
          Navigator.of(context).pop();
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isClaiming = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء تسجيل تسليم الهدية')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isAr = ref.isArabic;
    final strings = AppStrings.of(ref);
    final effectiveQuantity = widget.quantity > 0 ? widget.quantity : 1;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: const SwitchPointHeader(
        subtitle: 'استحقاق الهدية الفورية المباشرة',
        customActions: [
          GameSoundToggleButton(),
        ],
      ),
      body: Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: SafeArea(
          child: Column(
            children: [
              if (widget.isDemo)
                GameDemoBanner(
                  onReset: _resetDemo,
                  onExit: () => Navigator.of(context).pop(),
                ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 580),
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                      // Top Banner / Tag
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified_rounded, color: colorScheme.primary, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                isAr ? 'هدية فورية معتمدة ومضمونة' : 'Guaranteed Instant Gift',
                                style: GoogleFonts.cairo(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Main Gift Presentation Card
                      ScaleTransition(
                        scale: _scaleAnimation,
                        child: Card(
                          elevation: 0,
                          color: colorScheme.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                            side: BorderSide(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                              width: 1.5,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(28.0),
                            child: Column(
                              children: [
                                // Glowing Gift Icon Container
                                Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        colorScheme.primary,
                                        colorScheme.tertiary,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: colorScheme.primary.withValues(alpha: 0.35),
                                        blurRadius: 20,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.redeem_rounded,
                                    size: 54,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Congratulations Header
                                Text(
                                  isAr ? 'مبروك! استحققت الهدية الفورية' : 'Congratulations! Instant Gift Claim',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.cairo(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 8),

                                // Designated Prize Name
                                Text(
                                  widget.prizeName.isNotEmpty
                                      ? widget.prizeName
                                      : (isAr ? 'هدية ترويجية متميزة' : 'Promotional Gift'),
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.cairo(
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Quantity & Multiplier Chip
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: effectiveQuantity > 1
                                        ? colorScheme.secondaryContainer
                                        : colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: effectiveQuantity > 1
                                          ? colorScheme.secondary
                                          : colorScheme.outlineVariant,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        effectiveQuantity > 1 ? Icons.stars_rounded : Icons.inventory_2_rounded,
                                        color: effectiveQuantity > 1
                                            ? colorScheme.secondary
                                            : colorScheme.onSurfaceVariant,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${strings.directGiftQuantity}: $effectiveQuantity ${isAr ? (effectiveQuantity > 1 ? 'قطع' : 'قطعة') : (effectiveQuantity > 1 ? 'Units' : 'Unit')}',
                                        style: GoogleFonts.cairo(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: effectiveQuantity > 1
                                              ? colorScheme.onSecondaryContainer
                                              : colorScheme.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Information details
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.check_circle_outline_rounded, color: Colors.green.shade600, size: 20),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              isAr
                                                  ? 'تم التحقق من الفاتورة بنجاح واستيفاء كافة الشروط.'
                                                  : 'Receipt validated and all campaign conditions met.',
                                              style: GoogleFonts.cairo(fontSize: 13, color: colorScheme.onSurfaceVariant),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Icon(Icons.auto_awesome_rounded, color: colorScheme.primary, size: 20),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              isAr
                                                  ? 'سيتم خصم الهدية وتحديث السجل فور الضغط على زر التسليم.'
                                                  : 'Stock will be deducted and transaction logged upon handover.',
                                              style: GoogleFonts.cairo(fontSize: 13, color: colorScheme.onSurfaceVariant),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Action Button (Handover & Claim)
                      M3ActionButton(
                        onPressed: _isClaiming || _isClaimed ? null : _claimAndHandoverGift,
                        label: _isClaimed
                            ? (isAr ? 'تم تسليم الهدية بنجاح' : 'Gift Handed Over')
                            : strings.claimDirectGift,
                        icon: _isClaimed ? Icons.done_all_rounded : Icons.check_circle_rounded,
                        isLoading: _isClaiming,
                      ),
                      const SizedBox(height: 12),

                      // Back / Cancel text button
                      TextButton.icon(
                        onPressed: _isClaiming ? null : () => Navigator.of(context).pop(),
                        icon: Icon(Icons.arrow_back_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                        label: Text(
                          isAr ? 'العودة لشاشة الفحص' : 'Back to Validation',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
