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
/// The customer is presented with an elegant, celebratory gift screen showing only customer-relevant
/// information, while the promoter receives smart real-time stock alerts for low inventory.
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
  int? _remainingStock;
  bool _isLoadingStock = true;

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

    // Fetch remaining stock for promoter awareness
    _fetchRemainingStock();

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

  Future<void> _fetchRemainingStock() async {
    if (widget.isDemo || widget.eventId.isEmpty) {
      if (mounted) setState(() => _isLoadingStock = false);
      return;
    }

    try {
      final doc = await ref
          .read(firestoreProvider)
          .collection('events')
          .doc(widget.eventId)
          .get();

      if (doc.exists && doc.data() != null) {
        final prizes = List<Map<String, dynamic>>.from(doc.data()!['allocatedPrizes'] ?? []);
        int foundRemaining = -1;

        for (final p in prizes) {
          final matches = p['giftId'] == widget.prizeName || p['name'] == widget.prizeName;
          if (matches) {
            if (widget.branchId != null && widget.branchId!.isNotEmpty && p['branchId'] == widget.branchId) {
              foundRemaining = (p['remainingQuantity'] as num?)?.toInt() ?? 0;
              break;
            } else if (foundRemaining == -1) {
              foundRemaining = (p['remainingQuantity'] as num?)?.toInt() ?? 0;
            }
          }
        }

        if (mounted) {
          setState(() {
            _remainingStock = foundRemaining >= 0 ? foundRemaining : null;
            _isLoadingStock = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingStock = false);
      }
    } catch (e) {
      debugPrint('Error fetching remaining prize stock: $e');
      if (mounted) setState(() => _isLoadingStock = false);
    }
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

    if (_remainingStock != null && _remainingStock! <= 0 && !widget.isDemo) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(ref).directGiftOutOfStock),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

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
        if (_remainingStock != null) {
          _remainingStock = (_remainingStock! - effectiveQuantity).clamp(0, double.infinity).toInt();
        }
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
          behavior: SnackBarBehavior.floating,
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
    final isOutOfStock = _remainingStock != null && _remainingStock! <= 0 && !widget.isDemo;

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
                            // Top Banner / Tag (Customer-facing certified badge)
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

                            // Main Gift Presentation Card (Celebratory Customer View)
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
                                        strings.directGiftCustomerCongrats,
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

                                      // Multiplier Badge (Only shown if customer earned >1 gifts)
                                      if (effectiveQuantity > 1)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 16),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: colorScheme.secondaryContainer,
                                              borderRadius: BorderRadius.circular(16),
                                              border: Border.all(color: colorScheme.secondary),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.stars_rounded, color: colorScheme.secondary, size: 20),
                                                const SizedBox(width: 8),
                                                Text(
                                                  '${isAr ? 'عدد الهدايا المستحقة' : 'Gifts Earned'}: $effectiveQuantity ${isAr ? 'قطع' : 'Units'}',
                                                  style: GoogleFonts.cairo(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.bold,
                                                    color: colorScheme.onSecondaryContainer,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),

                                      // Information details (Refined, strictly customer-facing)
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
                                                    strings.directGiftCustomerVerified,
                                                    style: GoogleFonts.cairo(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w500,
                                                      color: colorScheme.onSurface,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 10),
                                            Row(
                                              children: [
                                                Icon(Icons.card_giftcard_rounded, color: colorScheme.primary, size: 20),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    strings.directGiftCustomerHandoverNote,
                                                    style: GoogleFonts.cairo(
                                                      fontSize: 13,
                                                      color: colorScheme.onSurfaceVariant,
                                                    ),
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

                            // Promoter Smart Low Stock Alert (Only visible when stock is 1 or 2 units)
                            if (_remainingStock != null && _remainingStock! > 0 && _remainingStock! <= 2 && !widget.isDemo)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.amber.shade400, width: 1.5),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 22),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _remainingStock == 1
                                              ? strings.promoterLowStockWarningSingle
                                              : strings.promoterLowStockWarningDouble,
                                          style: GoogleFonts.cairo(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.amber.shade900,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // Out of stock warning (if 0 units left)
                            if (isOutOfStock)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: colorScheme.errorContainer,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: colorScheme.error, width: 1.5),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.block_rounded, color: colorScheme.error, size: 22),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          strings.directGiftOutOfStock,
                                          style: GoogleFonts.cairo(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onErrorContainer,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            const SizedBox(height: 28),

                            // Action Button (Handover & Claim)
                            M3ActionButton(
                              onPressed: (_isClaiming || _isClaimed || isOutOfStock) ? null : _claimAndHandoverGift,
                              label: _isClaimed
                                  ? (isAr ? 'تم تسليم الهدية بنجاح' : 'Gift Handed Over')
                                  : (isOutOfStock ? (isAr ? 'المخزون نافد' : 'Out of Stock') : strings.claimDirectGift),
                              icon: _isClaimed
                                  ? Icons.done_all_rounded
                                  : (isOutOfStock ? Icons.block_rounded : Icons.check_circle_rounded),
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
