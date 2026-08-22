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
import '../../admin/domain/event_model.dart';
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
  final double? unitValue;
  final bool? isVoucher;
  final List<LinkedGiftAllocation> linkedGifts;

  const DirectGiftClaimScreen({
    super.key,
    this.transactionId = '',
    this.eventId = '',
    required this.prizeName,
    this.quantity = 1,
    this.branchId,
    this.isDemo = false,
    this.unitValue,
    this.isVoucher,
    this.linkedGifts = const [],
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

  String? _resolvedPrizeName;
  double? _resolvedUnitValue;
  bool? _resolvedIsVoucher;
  List<LinkedGiftAllocation>? _resolvedLinkedGifts;

  List<LinkedGiftAllocation> get _effectiveLinkedGifts =>
      (_resolvedLinkedGifts != null && _resolvedLinkedGifts!.isNotEmpty)
          ? _resolvedLinkedGifts!
          : widget.linkedGifts;

  bool get _effectiveIsVoucher {
    if (_resolvedIsVoucher != null) return _resolvedIsVoucher!;
    if (widget.isVoucher != null) return widget.isVoucher!;
    if (_effectiveLinkedGifts.isNotEmpty) {
      return _effectiveLinkedGifts.any((g) => g.isVoucher);
    }
    final name = _effectivePrizeName.toLowerCase();
    if (name.contains('فواتشر') || name.contains('voucher') || name.contains('قسيمة')) {
      return true;
    }
    // Explicit physical product indicators
    if (name.contains('مل') ||
        name.contains('ml') ||
        name.contains('جم') ||
        name.contains('gm') ||
        name.contains('شامبو') ||
        name.contains('بلسم') ||
        name.contains('قطعة')) {
      return false;
    }
    return false;
  }

  double? get _effectiveUnitValue {
    if (!_effectiveIsVoucher) return null;
    if (_resolvedUnitValue != null && _resolvedUnitValue! > 0) {
      return _resolvedUnitValue;
    }
    if (widget.unitValue != null && widget.unitValue! > 0) {
      return widget.unitValue;
    }
    if (_effectiveLinkedGifts.isNotEmpty) {
      final total = _effectiveLinkedGifts.fold<double>(0.0, (sum, g) => sum + g.totalMonetaryValue);
      if (total > 0) return total;
    }
    final match = RegExp(r'(\d+)').firstMatch(widget.prizeName);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    return null;
  }

  String get _effectivePrizeName {
    if (_resolvedPrizeName != null &&
        _resolvedPrizeName!.isNotEmpty &&
        _resolvedPrizeName != 'هدية ترويجية مميزة' &&
        _resolvedPrizeName != 'هدية فورية مميزة') {
      return _resolvedPrizeName!;
    }
    String name = widget.prizeName.trim();
    if (name.isEmpty ||
        name == 'هدية ترويجية مميزة' ||
        name == 'هدية فورية مميزة' ||
        RegExp(r'^[a-zA-Z0-9_-]{15,35}$').hasMatch(name)) {
      if (_effectiveLinkedGifts.isNotEmpty) {
        return _effectiveLinkedGifts.map((g) => g.quantity > 1 ? '${g.quantity} × ${g.giftName}' : g.giftName).join(' + ');
      }
      if (_effectiveIsVoucher && _effectiveUnitValue != null && _effectiveUnitValue! > 0) {
        final val = _effectiveUnitValue == _effectiveUnitValue!.roundToDouble() ? _effectiveUnitValue!.toInt() : _effectiveUnitValue;
        return 'فواتشر بقيمة $val جنيه';
      }
      if (_effectiveIsVoucher) {
        return 'كارت فواتشر مشتريات';
      }
    }
    return name.isNotEmpty ? name : 'هدية فورية معتمدة';
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.elasticOut,
      ),
    );
    _animController.forward();
    _fetchRemainingStock();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _fetchRemainingStock() async {
    if (widget.eventId.isEmpty) return;
    try {
      final doc = await ref
          .read(firestoreProvider)
          .collection('events')
          .doc(widget.eventId)
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final promoRulesRaw = data['promotionalRules'] as List?;
        final prizesRaw = data['allocatedPrizes'] as List?;

        String? discoveredName;
        List<LinkedGiftAllocation>? discoveredLinkedGifts;
        double? discoveredUnitVal;
        bool? discoveredIsVoucher;

        PromotionalRuleItem? matchedRuleItem;
        if (promoRulesRaw != null && promoRulesRaw.isNotEmpty) {
          final rules = promoRulesRaw
              .map((r) => PromotionalRuleItem.fromMap(Map<String, dynamic>.from(r as Map)))
              .toList();

          final target = widget.prizeName.trim();
          if (target.isNotEmpty &&
              target != 'هدية ترويجية مميزة' &&
              target != 'هدية فورية مميزة' &&
              !RegExp(r'^[a-zA-Z0-9_-]{15,35}$').hasMatch(target)) {
            matchedRuleItem = rules.cast<PromotionalRuleItem?>().firstWhere(
              (r) => r != null && (
                     r.rewardValue == target ||
                     r.linkedGiftsSummary == target ||
                     r.ruleTitle == target ||
                     r.linkedGifts.any((g) => g.giftName == target)),
              orElse: () => null,
            );
          }
        }

        if (matchedRuleItem != null) {
          discoveredName = matchedRuleItem.rewardValue.isNotEmpty
              ? matchedRuleItem.rewardValue
              : matchedRuleItem.linkedGiftsSummary;
          discoveredLinkedGifts = matchedRuleItem.linkedGifts.isNotEmpty
              ? matchedRuleItem.linkedGifts
              : null;
          discoveredIsVoucher = matchedRuleItem.rewardType == 'voucher' ||
              matchedRuleItem.totalVoucherValue > 0 ||
              (discoveredName.contains('فواتشر') || discoveredName.contains('قسيمة'));
          discoveredUnitVal = discoveredIsVoucher
              ? (matchedRuleItem.totalVoucherValue > 0
                  ? matchedRuleItem.totalVoucherValue
                  : (matchedRuleItem.rewardAmount > 0 ? matchedRuleItem.rewardAmount : null))
              : null;
        }

        final prizes = List<Map<String, dynamic>>.from(prizesRaw ?? []);
        int foundRemaining = -1;

        for (final p in prizes) {
          final matches = p['giftId'] == widget.prizeName ||
              p['name'] == widget.prizeName ||
              (discoveredName != null && p['name'] == discoveredName);
          if (matches) {
            if (widget.branchId != null &&
                widget.branchId!.isNotEmpty &&
                p['branchId'] == widget.branchId) {
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
            final isPlaceholder = widget.prizeName.isEmpty ||
                widget.prizeName == 'هدية ترويجية مميزة' ||
                widget.prizeName == 'هدية فورية مميزة' ||
                RegExp(r'^[a-zA-Z0-9_-]{15,35}$').hasMatch(widget.prizeName);

            if (isPlaceholder) {
              if (discoveredName != null && discoveredName.isNotEmpty) {
                _resolvedPrizeName = discoveredName;
              }
              if (discoveredLinkedGifts != null && discoveredLinkedGifts.isNotEmpty) {
                _resolvedLinkedGifts = discoveredLinkedGifts;
              }
              if (discoveredUnitVal != null && discoveredUnitVal > 0) {
                _resolvedUnitValue = discoveredUnitVal;
              }
              if (discoveredIsVoucher != null) {
                _resolvedIsVoucher = discoveredIsVoucher;
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching remaining prize stock: $e');
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
      final finalPrizeName = _effectivePrizeName;
      final finalUnitValue = _effectiveUnitValue;
      final finalIsVoucher = _effectiveIsVoucher;
      final finalLinkedGifts = _effectiveLinkedGifts;

      final displayPrize = effectiveQuantity > 1
          ? '$finalPrizeName (عدد $effectiveQuantity)'
          : finalPrizeName;

      if (!widget.isDemo && widget.transactionId.isNotEmpty) {
        final firestore = ref.read(firestoreProvider);
        final claimedGiftsList = finalLinkedGifts.isNotEmpty
            ? finalLinkedGifts.map((g) => {
                'giftId': g.giftId,
                'giftName': g.giftName,
                'quantity': g.quantity * effectiveQuantity,
                'unitValue': g.unitValue,
                'isVoucher': g.isVoucher,
              }).toList()
            : [{
                'giftId': '',
                'giftName': finalPrizeName,
                'quantity': effectiveQuantity,
                'unitValue': finalUnitValue ?? 0.0,
                'isVoucher': finalIsVoucher,
              }];

        // 1. Update receipts_transactions record
        await firestore.collection('receipts_transactions').doc(widget.transactionId).update({
          'game_played': true,
          'game_type': 'directGift',
          'prize_won': displayPrize,
          'prizes_won': List.filled(effectiveQuantity, finalPrizeName),
          'claimed_gifts': claimedGiftsList,
          'event_id': widget.eventId,
          'branch_id': widget.branchId ?? '',
          'remaining_chances': 0,
          'claim_status': 'handed_over',
          'claimed_at': DateTime.now().toIso8601String(),
        });

        // 2. Decrement inventory from campaign/branch
        if (widget.eventId.isNotEmpty) {
          final giftsService = ref.read(companyGiftsServiceProvider);
          if (finalLinkedGifts.isNotEmpty) {
            for (final giftAlloc in finalLinkedGifts) {
              await giftsService.decrementCampaignPrize(
                widget.eventId,
                giftAlloc.giftId.isNotEmpty ? giftAlloc.giftId : giftAlloc.giftName,
                branchId: widget.branchId,
                count: giftAlloc.quantity,
                unitValue: giftAlloc.unitValue,
                isVoucher: giftAlloc.isVoucher,
              );
            }
          } else {
            await giftsService.decrementCampaignPrize(
              widget.eventId,
              finalPrizeName,
              branchId: widget.branchId,
              count: effectiveQuantity,
              unitValue: finalUnitValue,
              isVoucher: finalIsVoucher,
            );
          }
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
        unitValue: finalUnitValue,
        isVoucher: finalIsVoucher,
        linkedGifts: finalLinkedGifts,
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

                                      // Designated Prize Name / Multi-Offer Bundle List
                                       Builder(
                                         builder: (context) {
                                           final cleanPrizeName = _effectivePrizeName;
                                           final resolvedUnitValue = _effectiveUnitValue;
                                           final resolvedIsVoucher = _effectiveIsVoucher;
                                           final linkedGifts = _effectiveLinkedGifts;

                                           final formattedVal = resolvedUnitValue != null && resolvedUnitValue > 0
                                               ? (resolvedUnitValue == resolvedUnitValue.roundToDouble()
                                                   ? resolvedUnitValue.toInt().toString()
                                                   : resolvedUnitValue.toString())
                                               : '';

                                           final isMultiBundle = cleanPrizeName.contains('+') ||
                                               (linkedGifts.length > 1 && linkedGifts.any((g) => !g.isVoucher) && linkedGifts.any((g) => g.isVoucher));

                                           if (isMultiBundle) {
                                             final totalGiftsCount = linkedGifts.fold<int>(0, (sum, g) => sum + g.quantity);
                                             final totalVoucherAmount = linkedGifts.where((g) => g.isVoucher).fold<double>(0.0, (sum, g) => sum + (g.unitValue * g.quantity));

                                             return Column(
                                               children: [
                                                 // Multi-Bundle Header Badge
                                                 Container(
                                                   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                                   decoration: BoxDecoration(
                                                     color: colorScheme.primaryContainer,
                                                     borderRadius: BorderRadius.circular(20),
                                                   ),
                                                   child: Row(
                                                     mainAxisSize: MainAxisSize.min,
                                                     children: [
                                                       Icon(Icons.inventory_2_rounded, size: 16, color: colorScheme.onPrimaryContainer),
                                                       const SizedBox(width: 6),
                                                       Text(
                                                         isAr
                                                             ? 'سلة هدايا مجمعة ($totalGiftsCount هدايا مستحقة)'
                                                             : 'Multi-Gift Bundle ($totalGiftsCount Items)',
                                                         style: GoogleFonts.cairo(
                                                           fontSize: 13,
                                                           fontWeight: FontWeight.bold,
                                                           color: colorScheme.onPrimaryContainer,
                                                         ),
                                                       ),
                                                     ],
                                                   ),
                                                 ),
                                                 const SizedBox(height: 10),

                                                 Text(
                                                   isAr ? 'ألف مبروك! استوفيت شروط العرض' : 'Congratulations! Multiple Offers Unlocked',
                                                   textAlign: TextAlign.center,
                                                   style: GoogleFonts.cairo(
                                                     fontSize: 22,
                                                     fontWeight: FontWeight.bold,
                                                     color: colorScheme.onSurface,
                                                   ),
                                                 ),
                                                 const SizedBox(height: 12),

                                                 if (totalVoucherAmount > 0) ...[
                                                   Container(
                                                     padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                                     margin: const EdgeInsets.only(bottom: 14),
                                                     decoration: BoxDecoration(
                                                       gradient: const LinearGradient(
                                                         colors: [Color(0xFFFFB300), Color(0xFFFF6D00)],
                                                         begin: Alignment.topLeft,
                                                         end: Alignment.bottomRight,
                                                       ),
                                                       borderRadius: BorderRadius.circular(14),
                                                       boxShadow: [
                                                         BoxShadow(
                                                           color: const Color(0xFFFF8F00).withValues(alpha: 0.35),
                                                           blurRadius: 10,
                                                           offset: const Offset(0, 3),
                                                         ),
                                                       ],
                                                     ),
                                                     child: Row(
                                                       mainAxisSize: MainAxisSize.min,
                                                       children: [
                                                         const Icon(Icons.payments_rounded, color: Colors.white, size: 20),
                                                         const SizedBox(width: 8),
                                                         Text(
                                                           isAr
                                                               ? 'إجمالي قيمة الفواتشرات: ${totalVoucherAmount == totalVoucherAmount.roundToDouble() ? totalVoucherAmount.toInt() : totalVoucherAmount} ج.م'
                                                               : 'Total Vouchers: ${totalVoucherAmount.toInt()} EGP',
                                                           style: GoogleFonts.cairo(
                                                             fontSize: 15,
                                                             fontWeight: FontWeight.bold,
                                                             color: Colors.white,
                                                           ),
                                                         ),
                                                       ],
                                                     ),
                                                   ),
                                                 ],

                                                 // Itemized Gift Cards
                                                 ListView.separated(
                                                   shrinkWrap: true,
                                                   physics: const NeverScrollableScrollPhysics(),
                                                   itemCount: linkedGifts.length,
                                                   separatorBuilder: (context, index) => const SizedBox(height: 10),
                                                   itemBuilder: (context, idx) {
                                                     final gift = linkedGifts[idx];
                                                     final totalCount = gift.quantity;
                                                     final isGiftVoucher = gift.isVoucher;

                                                     return Container(
                                                       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                                       decoration: BoxDecoration(
                                                         color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                                                         borderRadius: BorderRadius.circular(16),
                                                         border: Border.all(
                                                           color: isGiftVoucher
                                                               ? Colors.amber.shade400
                                                               : colorScheme.outlineVariant.withValues(alpha: 0.6),
                                                           width: isGiftVoucher ? 1.5 : 1.0,
                                                         ),
                                                       ),
                                                       child: Row(
                                                         children: [
                                                           Container(
                                                             width: 44,
                                                             height: 44,
                                                             decoration: BoxDecoration(
                                                               color: isGiftVoucher
                                                                   ? Colors.amber.shade100
                                                                   : colorScheme.primary.withValues(alpha: 0.12),
                                                               shape: BoxShape.circle,
                                                             ),
                                                             child: Icon(
                                                               isGiftVoucher
                                                                   ? Icons.confirmation_number_rounded
                                                                   : Icons.card_giftcard_rounded,
                                                               color: isGiftVoucher
                                                                   ? Colors.amber.shade900
                                                                   : colorScheme.primary,
                                                               size: 24,
                                                             ),
                                                           ),
                                                           const SizedBox(width: 14),
                                                           Expanded(
                                                             child: Column(
                                                               crossAxisAlignment: CrossAxisAlignment.start,
                                                               children: [
                                                                 Text(
                                                                   gift.giftName,
                                                                   style: GoogleFonts.cairo(
                                                                     fontSize: 16,
                                                                     fontWeight: FontWeight.bold,
                                                                     color: colorScheme.onSurface,
                                                                   ),
                                                                 ),
                                                                 if (isGiftVoucher && gift.unitValue > 0)
                                                                   Text(
                                                                     'فواتشر معتمد بقيمة ${gift.unitValue.toInt()} ج.م للقطعة',
                                                                     style: GoogleFonts.cairo(
                                                                       fontSize: 12,
                                                                       fontWeight: FontWeight.w600,
                                                                       color: Colors.amber.shade900,
                                                                     ),
                                                                   )
                                                                 else
                                                                   Text(
                                                                     isAr ? 'هدية عينية فورية معتمدة' : 'Certified Physical Gift',
                                                                     style: GoogleFonts.cairo(
                                                                       fontSize: 12,
                                                                       color: colorScheme.onSurfaceVariant,
                                                                     ),
                                                                   ),
                                                               ],
                                                             ),
                                                           ),
                                                           Container(
                                                             padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                             decoration: BoxDecoration(
                                                               color: isGiftVoucher
                                                                   ? Colors.amber.shade600
                                                                   : colorScheme.primary,
                                                               borderRadius: BorderRadius.circular(12),
                                                             ),
                                                             child: Text(
                                                               '$totalCount ×',
                                                               style: GoogleFonts.cairo(
                                                                 fontSize: 14,
                                                                 fontWeight: FontWeight.w900,
                                                                 color: Colors.white,
                                                               ),
                                                             ),
                                                           ),
                                                         ],
                                                       ),
                                                     );
                                                   },
                                                 ),
                                               ],
                                             );
                                           }

                                           // Single Gift / Uniform Multi-Quantity Display
                                           return Column(
                                             children: [
                                               Text(
                                                 cleanPrizeName.isNotEmpty
                                                     ? cleanPrizeName
                                                     : (isAr ? 'هدية ترويجية متميزة' : 'Promotional Gift'),
                                                 textAlign: TextAlign.center,
                                                 style: GoogleFonts.cairo(
                                                   fontSize: 26,
                                                   fontWeight: FontWeight.bold,
                                                   color: colorScheme.onSurface,
                                                   height: 1.3,
                                                 ),
                                               ),
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
                                                         color: const Color(0xFFFF8F00).withValues(alpha: 0.4),
                                                         blurRadius: 14,
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
                                                         ),
                                                       ),
                                                     ],
                                                   ),
                                                 ),
                                               ],
                                               // Multi-Gift Breakdown Display
                                               if (linkedGifts.length > 1 ||
                                                   (linkedGifts.length == 1 && linkedGifts.first.quantity > 1)) ...[
                                                 const SizedBox(height: 12),
                                                 Container(
                                                   padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                   decoration: BoxDecoration(
                                                     color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                                                     borderRadius: BorderRadius.circular(12),
                                                     border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                                                   ),
                                                   child: Column(
                                                     children: [
                                                       Text(
                                                         strings.cardsBreakdownTitle,
                                                         style: GoogleFonts.cairo(
                                                           fontSize: 11,
                                                           fontWeight: FontWeight.bold,
                                                           color: colorScheme.primary,
                                                         ),
                                                       ),
                                                       const SizedBox(height: 4),
                                                       Wrap(
                                                         spacing: 6,
                                                         runSpacing: 4,
                                                         alignment: WrapAlignment.center,
                                                         children: linkedGifts.map((g) {
                                                           final totalCount = g.quantity;
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
                                                                   '$totalCount × ${g.giftName}',
                                                                   style: GoogleFonts.cairo(
                                                                     fontSize: 11.5,
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
                                                   ),
                                                 ),
                                               ],
                                             ],
                                           );
                                         },
                                       ),
                                      const SizedBox(height: 16),

                                      // Multiplier Badge (Only shown if customer earned >1 gifts and no linked gifts)
                                      if (effectiveQuantity > 1 && _effectiveLinkedGifts.isEmpty)
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
