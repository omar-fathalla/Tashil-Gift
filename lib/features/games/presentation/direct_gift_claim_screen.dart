import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/services/company_gifts_service.dart';
import '../../../core/services/game_audio_service.dart';
import '../../../core/widgets/game_sound_controls.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/arabic_numbers_utils.dart';
import '../../../core/animations/m3_motion.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/widgets/switch_point_branding.dart';
import '../../../core/widgets/m3_list_tile.dart';
import '../../admin/domain/event_model.dart';
import 'winner_celebration_dialog.dart';
import 'game_demo_banner.dart';
import '../../company_portal/domain/whatsapp_winner_notification_service.dart';

/// Helper model for individual physical voucher card serial slot
class VoucherSerialSlot {
  final String giftId;
  final String giftName;
  final double unitValue;
  final int indexInBundle;
  final TextEditingController controller;
  final FocusNode focusNode;

  VoucherSerialSlot({
    required this.giftId,
    required this.giftName,
    required this.unitValue,
    required this.indexInBundle,
    required this.controller,
    required this.focusNode,
  });
}

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
  final bool? requireVoucherSerials;
  final String? customerPhone;
  final String? customerName;
  final String? retailChainName;
  final String? branchName;
  final String? companyName;
  final String? receiptNumber;
  final String? companySlug;
  final bool? enableWhatsAppWinnerNotification;

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
    this.requireVoucherSerials,
    this.customerPhone,
    this.customerName,
    this.retailChainName,
    this.branchName,
    this.companyName,
    this.receiptNumber,
    this.companySlug,
    this.enableWhatsAppWinnerNotification,
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
  String? _resolvedBranchName;

  String? _resolvedPrizeName;
  double? _resolvedUnitValue;
  bool? _resolvedIsVoucher;
  List<LinkedGiftAllocation>? _resolvedLinkedGifts;
  bool? _requireVoucherSerials;
  bool? _enableWhatsAppWinnerNotification;

  bool get _isVoucherSerialsRequired => _requireVoucherSerials ?? widget.requireVoucherSerials ?? false;
  bool get _isWhatsAppWinnerNotificationEnabled =>
      _enableWhatsAppWinnerNotification ?? widget.enableWhatsAppWinnerNotification ?? true;

  final List<VoucherSerialSlot> _voucherSlots = [];

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
      final total = _effectiveLinkedGifts.fold<double>(0.0, (acc, g) => acc + g.totalMonetaryValue);
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
    _syncVoucherSlots();
    _fetchRemainingStock();
  }

  @override
  void dispose() {
    _animController.dispose();
    for (final slot in _voucherSlots) {
      slot.controller.dispose();
      slot.focusNode.dispose();
    }
    _voucherSlots.clear();
    super.dispose();
  }

  void _syncVoucherSlots() {
    final List<({String giftId, String giftName, double unitValue})> requiredCards = [];

    if (_effectiveLinkedGifts.isNotEmpty) {
      for (final gift in _effectiveLinkedGifts) {
        if (gift.isVoucher) {
          for (int i = 0; i < gift.quantity; i++) {
            requiredCards.add((
              giftId: gift.giftId,
              giftName: gift.giftName,
              unitValue: gift.unitValue,
            ));
          }
        }
      }
    } else if (_effectiveIsVoucher) {
      final effectiveQty = widget.quantity > 0 ? widget.quantity : 1;
      for (int i = 0; i < effectiveQty; i++) {
        requiredCards.add((
          giftId: '',
          giftName: _effectivePrizeName,
          unitValue: _effectiveUnitValue ?? 0.0,
        ));
      }
    }

    while (_voucherSlots.length < requiredCards.length) {
      final idx = _voucherSlots.length;
      final card = requiredCards[idx];
      _voucherSlots.add(VoucherSerialSlot(
        giftId: card.giftId,
        giftName: card.giftName,
        unitValue: card.unitValue,
        indexInBundle: idx + 1,
        controller: TextEditingController(),
        focusNode: FocusNode(),
      ));
    }
    while (_voucherSlots.length > requiredCards.length) {
      final last = _voucherSlots.removeLast();
      last.controller.dispose();
      last.focusNode.dispose();
    }
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

        String? branchNameFound;
        final branchNamesList = (data['branchNames'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final branchIdsList = (data['branchIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
        if (widget.branchId != null && widget.branchId!.isNotEmpty) {
          final idx = branchIdsList.indexOf(widget.branchId!);
          if (idx != -1 && idx < branchNamesList.length) {
            branchNameFound = branchNamesList[idx];
          } else {
            for (final bn in branchNamesList) {
              if (bn == widget.branchId || bn.contains(widget.branchId!) || widget.branchId!.contains(bn)) {
                branchNameFound = bn;
                break;
              }
            }
          }
        }

        final targetPrizeName = (discoveredName != null && discoveredName.isNotEmpty)
            ? discoveredName
            : widget.prizeName;
        final targetBranch = _resolvedBranchName ?? branchNameFound ?? widget.branchId;

        final matchIdx = CompanyGiftsService.findBestPrizeMatchIndex(
          prizes,
          targetPrizeName,
          branchId: targetBranch,
          unitValue: discoveredUnitVal,
          isVoucher: discoveredIsVoucher,
          preferWithRemaining: true,
        );

        if (matchIdx != -1) {
          foundRemaining = (prizes[matchIdx]['remainingQuantity'] as num?)?.toInt() ?? 0;
          final pBranch = (prizes[matchIdx]['branchName'] ?? '').toString().trim();
          if (pBranch.isNotEmpty) {
            branchNameFound = pBranch;
          }
        } else {
          for (final p in prizes) {
            final matches = p['giftId'] == widget.prizeName ||
                p['name'] == widget.prizeName ||
                (discoveredName != null && p['name'] == discoveredName);
            if (matches) {
              final pBranchId = (p['branchId'] ?? '').toString().trim();
              final pBranchName = (p['branchName'] ?? '').toString().trim();
              final isBranchMatch = (targetBranch != null &&
                  targetBranch.isNotEmpty &&
                  (pBranchId == targetBranch ||
                      pBranchName == targetBranch ||
                      CompanyGiftsService.matchesBranchName(pBranchName, targetBranch)));

              if (isBranchMatch) {
                foundRemaining = (p['remainingQuantity'] as num?)?.toInt() ?? 0;
                if (pBranchName.isNotEmpty) {
                  branchNameFound = pBranchName;
                }
                break;
              } else if (pBranchName.isEmpty && pBranchId.isEmpty && foundRemaining == -1) {
                foundRemaining = (p['remainingQuantity'] as num?)?.toInt() ?? 0;
              }
            }
          }
        }
        branchNameFound ??= widget.branchId;

        if (mounted) {
          setState(() {
            _requireVoucherSerials = data['requireVoucherSerials'] == true || data['require_voucher_serials'] == true;
            _enableWhatsAppWinnerNotification = data['enableWhatsAppWinnerNotification'] != false && data['enable_whatsapp_winner_notification'] != false;
            _remainingStock = foundRemaining >= 0 ? foundRemaining : null;
            _resolvedBranchName = branchNameFound;
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
            _syncVoucherSlots();
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
      final strings = AppStrings.of(ref);
      final branch = _resolvedBranchName ?? widget.branchId ?? '';
      final msg = branch.isNotEmpty
          ? strings.directGiftOutOfStockAtBranch(branch)
          : strings.directGiftOutOfStock;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _syncVoucherSlots();

    // 1. Validate physical voucher serial numbers (mandatory if _isVoucherSerialsRequired, or optional)
    if (_voucherSlots.isNotEmpty) {
      final strings = AppStrings.of(ref);
      final List<String> enteredSerials = [];

      for (int i = 0; i < _voucherSlots.length; i++) {
        final slot = _voucherSlots[i];
        final text = slot.controller.text.toEnglishDigits(convertDecimal: false).trim();
        if (text.isEmpty) {
          if (_isVoucherSerialsRequired) {
            slot.focusNode.requestFocus();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${strings.voucherSerialRequiredError} (${slot.giftName} #${i + 1})'),
                backgroundColor: Theme.of(context).colorScheme.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
          }
          continue;
        }

        if (enteredSerials.contains(text)) {
          slot.focusNode.requestFocus();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${strings.voucherSerialDuplicateInTxError}: $text'),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        enteredSerials.add(text);
      }

      // 2. Check Firestore for duplicate serials in active campaign (for any entered non-empty serials)
      if (!widget.isDemo && widget.eventId.isNotEmpty && enteredSerials.isNotEmpty) {
        setState(() => _isClaiming = true);
        try {
          final firestore = ref.read(firestoreProvider);
          final eventDoc = await firestore.collection('events').doc(widget.eventId).get();
          final eventData = eventDoc.data() ?? {};
          final resetAtRaw = eventData['voucher_serials_reset_at'];
          DateTime? resetAt;
          if (resetAtRaw is Timestamp) {
            resetAt = resetAtRaw.toDate();
          } else if (resetAtRaw is String && resetAtRaw.isNotEmpty) {
            resetAt = DateTime.tryParse(resetAtRaw);
          }

          final conflictQuery = await firestore
              .collection('receipts_transactions')
              .where('event_id', isEqualTo: widget.eventId)
              .where('voucher_serials', arrayContainsAny: enteredSerials)
              .get();

          for (final doc in conflictQuery.docs) {
            if (doc.id == widget.transactionId) continue;
            final docData = doc.data();
            if (docData['status'] == 'rejected' || docData['is_valid'] == false) continue;

            if (resetAt != null) {
              final claimedAtRaw = docData['claimed_at'] ?? docData['created_at'];
              DateTime? docDate;
              if (claimedAtRaw is Timestamp) {
                docDate = claimedAtRaw.toDate();
              } else if (claimedAtRaw is String) {
                docDate = DateTime.tryParse(claimedAtRaw);
              }
              if (docDate != null && docDate.isBefore(resetAt)) continue;
            }

            final existingSerials = List<String>.from(docData['voucher_serials'] ?? []);
            for (final s in enteredSerials) {
              if (existingSerials.contains(s)) {
                if (!mounted) return;
                setState(() => _isClaiming = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${strings.voucherSerialAlreadyClaimedError}: $s'),
                    backgroundColor: Theme.of(context).colorScheme.error,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 4),
                  ),
                );
                return;
              }
            }
          }
        } catch (e) {
          debugPrint('Duplicate serial check error: $e');
        }
      }
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
            ? finalLinkedGifts.map((g) {
                final gSerials = g.isVoucher
                    ? _voucherSlots
                        .where((s) => (s.giftId.isNotEmpty && s.giftId == g.giftId) || s.giftName == g.giftName)
                        .map((s) => s.controller.text.toEnglishDigits(convertDecimal: false).trim())
                        .where((t) => t.isNotEmpty)
                        .toList()
                    : <String>[];

                return {
                  'giftId': g.giftId,
                  'giftName': g.giftName,
                  'quantity': g.quantity,
                  'unitValue': g.unitValue,
                  'isVoucher': g.isVoucher,
                  if (gSerials.isNotEmpty) 'serials': gSerials,
                };
              }).toList()
            : [{
                'giftId': '',
                'giftName': finalPrizeName,
                'quantity': effectiveQuantity,
                'unitValue': finalUnitValue ?? 0.0,
                'isVoucher': finalIsVoucher,
                if (_voucherSlots.isNotEmpty)
                  'serials': _voucherSlots
                      .map((s) => s.controller.text.toEnglishDigits(convertDecimal: false).trim())
                      .where((t) => t.isNotEmpty)
                      .toList(),
              }];

        final allVoucherSerials = _voucherSlots
            .map((s) => s.controller.text.toEnglishDigits(convertDecimal: false).trim())
            .where((t) => t.isNotEmpty)
            .toList();

        // 1. Update receipts_transactions record
        await firestore.collection('receipts_transactions').doc(widget.transactionId).update({
          'game_played': true,
          'game_type': 'directGift',
          'prize_won': displayPrize,
          'prizes_won': List.filled(effectiveQuantity, finalPrizeName),
          'claimed_gifts': claimedGiftsList,
          if (allVoucherSerials.isNotEmpty) 'voucher_serials': allVoucherSerials,
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
                gameType: 'directGift',
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
              gameType: 'directGift',
            );
          }
        }

        // 3. Dispatch automated celebratory WhatsApp message to winner
        unawaited(_dispatchWhatsAppWinnerNotification(
          displayPrize: displayPrize,
          voucherSerials: allVoucherSerials,
        ));
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

      // 4. Trigger celebration modal
      await showWinnerCelebrationDialog(
        context: context,
        prizeName: displayPrize,
        unitValue: finalUnitValue,
        isVoucher: finalIsVoucher,
        linkedGifts: finalLinkedGifts,
        remainingChances: 0,
        recipientPhone: _isWhatsAppWinnerNotificationEnabled ? widget.customerPhone : null,
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

  /// Dispatches celebratory WhatsApp message to winner upon gift handover
  Future<void> _dispatchWhatsAppWinnerNotification({
    required String displayPrize,
    required List<String> voucherSerials,
  }) async {
    if (!_isWhatsAppWinnerNotificationEnabled) {
      debugPrint('WhatsApp winner notification suppressed for disabled campaign: ${widget.eventId}');
      return;
    }
    try {
      String phone = (widget.customerPhone ?? '').trim();
      String name = (widget.customerName ?? '').trim();
      String retailChain = (widget.retailChainName ?? '').trim();
      String branch = _resolvedBranchName ?? (widget.branchName ?? '').trim();
      String company = (widget.companyName ?? '').trim();
      String receipt = (widget.receiptNumber ?? '').trim();
      String? slug = widget.companySlug;

      // Fallback: If phone is missing from widget parameters, fetch from receipts_transactions document
      if (phone.isEmpty && widget.transactionId.isNotEmpty) {
        final doc = await ref.read(firestoreProvider).collection('receipts_transactions').doc(widget.transactionId).get();
        if (doc.exists) {
          final data = doc.data() ?? {};
          phone = (data['customerPhone'] ?? data['phone'] ?? '').toString();
          if (name.isEmpty) name = (data['customerName'] ?? '').toString();
          if (retailChain.isEmpty) retailChain = (data['retail_chain_name'] ?? data['store_chain_detected'] ?? '').toString();
          if (branch.isEmpty) branch = (data['canonical_branch'] ?? data['branch_detected'] ?? '').toString();
          if (company.isEmpty) company = (data['targetCompany'] ?? '').toString();
          if (receipt.isEmpty) receipt = (data['receipt_number'] ?? data['receiptNumber'] ?? '').toString();
          slug ??= data['companySlug']?.toString();
        }
      }

      if (phone.isEmpty) return;

      await ref.read(whatsappWinnerNotificationServiceProvider).sendWinnerNotification(
        toPhone: phone,
        prizeName: displayPrize,
        customerName: name,
        retailChain: retailChain,
        branchName: branch,
        companyName: company,
        voucherSerials: voucherSerials,
        receiptNumber: receipt,
        transactionId: widget.transactionId,
        companySlug: slug,
        isEnabledForCampaign: _isWhatsAppWinnerNotificationEnabled,
      );
    } catch (e) {
      debugPrint('Error dispatching WhatsApp winner notification from DirectGiftClaimScreen: $e');
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

    _syncVoucherSlots();

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
                                             final totalGiftsCount = linkedGifts.fold<int>(0, (acc, g) => acc + g.quantity);
                                             final totalVoucherAmount = linkedGifts.where((g) => g.isVoucher).fold<double>(0.0, (acc, g) => acc + (g.unitValue * g.quantity));

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

                                                 // Itemized Gift Cards (M3ListTile Standard)
                                                 ListView.separated(
                                                   shrinkWrap: true,
                                                   physics: const NeverScrollableScrollPhysics(),
                                                   itemCount: linkedGifts.length,
                                                   separatorBuilder: (context, index) => const M3InsetDivider(),
                                                   itemBuilder: (context, idx) {
                                                     final gift = linkedGifts[idx];
                                                     final totalCount = gift.quantity;
                                                     final isGiftVoucher = gift.isVoucher;

                                                     return Container(
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
                                                       child: M3ListTile.twoLine(
                                                         leading: (gift.imageUrl != null && gift.imageUrl!.trim().isNotEmpty)
                                                             ? ClipRRect(
                                                                 borderRadius: BorderRadius.circular(10),
                                                                 child: Image.network(
                                                                   gift.imageUrl!.trim(),
                                                                   width: 40,
                                                                   height: 40,
                                                                   fit: BoxFit.cover,
                                                                   errorBuilder: (context, error, stackTrace) => Container(
                                                                     width: 40,
                                                                     height: 40,
                                                                     decoration: BoxDecoration(
                                                                       color: isGiftVoucher
                                                                           ? Colors.amber.shade100
                                                                           : colorScheme.primary.withValues(alpha: 0.12),
                                                                       borderRadius: BorderRadius.circular(10),
                                                                     ),
                                                                     child: Icon(
                                                                       isGiftVoucher
                                                                           ? Icons.confirmation_number_rounded
                                                                           : Icons.card_giftcard_rounded,
                                                                       color: isGiftVoucher
                                                                           ? Colors.amber.shade900
                                                                           : colorScheme.primary,
                                                                       size: 22,
                                                                     ),
                                                                   ),
                                                                 ),
                                                               )
                                                             : Container(
                                                                 width: 40,
                                                                 height: 40,
                                                                 decoration: BoxDecoration(
                                                                   color: isGiftVoucher
                                                                       ? Colors.amber.shade100
                                                                       : colorScheme.primary.withValues(alpha: 0.12),
                                                                   borderRadius: BorderRadius.circular(10),
                                                                 ),
                                                                 child: Icon(
                                                                   isGiftVoucher
                                                                       ? Icons.confirmation_number_rounded
                                                                       : Icons.card_giftcard_rounded,
                                                                   color: isGiftVoucher
                                                                       ? Colors.amber.shade900
                                                                       : colorScheme.primary,
                                                                   size: 22,
                                                                 ),
                                                               ),
                                                         headline: Text(
                                                           gift.giftName,
                                                           style: GoogleFonts.cairo(
                                                             fontSize: 15,
                                                             fontWeight: FontWeight.bold,
                                                             color: colorScheme.onSurface,
                                                           ),
                                                           maxLines: 1,
                                                           overflow: TextOverflow.ellipsis,
                                                         ),
                                                         subtitle: (isGiftVoucher && gift.unitValue > 0)
                                                             ? Text(
                                                                 'فواتشر معتمد بقيمة ${gift.unitValue.toInt()} ج.م للقطعة',
                                                                 style: GoogleFonts.cairo(
                                                                   fontSize: 12,
                                                                   fontWeight: FontWeight.w600,
                                                                   color: Colors.amber.shade900,
                                                                 ),
                                                                 maxLines: 1,
                                                                 overflow: TextOverflow.ellipsis,
                                                               )
                                                             : Text(
                                                                 isAr ? 'هدية عينية فورية معتمدة' : 'Certified Physical Gift',
                                                                 style: GoogleFonts.cairo(
                                                                   fontSize: 12,
                                                                   color: colorScheme.onSurfaceVariant,
                                                                 ),
                                                                 maxLines: 1,
                                                                 overflow: TextOverflow.ellipsis,
                                                               ),
                                                         trailing: M3TouchTargetBoundary(
                                                           minSize: 48,
                                                           child: Container(
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
                                                         ),
                                                         semanticsLabel: '${gift.giftName}, ${isGiftVoucher ? "فواتشر" : "هدية"}, الكمية $totalCount',
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
                                                                 if (g.imageUrl != null && g.imageUrl!.trim().isNotEmpty) ...[
                                                                   ClipRRect(
                                                                     borderRadius: BorderRadius.circular(4),
                                                                     child: Image.network(
                                                                       g.imageUrl!.trim(),
                                                                       width: 16,
                                                                       height: 16,
                                                                       fit: BoxFit.cover,
                                                                       errorBuilder: (context, error, stackTrace) => Icon(
                                                                         g.isVoucher
                                                                             ? Icons.confirmation_number_rounded
                                                                             : Icons.card_giftcard_rounded,
                                                                         size: 13,
                                                                         color: Colors.amber.shade900,
                                                                       ),
                                                                     ),
                                                                   ),
                                                                   const SizedBox(width: 4),
                                                                 ] else ...[
                                                                   Icon(
                                                                     g.isVoucher
                                                                         ? Icons.confirmation_number_rounded
                                                                         : Icons.card_giftcard_rounded,
                                                                     size: 13,
                                                                     color: Colors.amber.shade900,
                                                                   ),
                                                                   const SizedBox(width: 4),
                                                                 ],
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

                            // Mandatory Physical Voucher Serial Numbers Input Card
                            _buildVoucherSerialsCard(context, colorScheme, strings, isAr),

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
                                          (_resolvedBranchName != null && _resolvedBranchName!.isNotEmpty)
                                              ? strings.directGiftOutOfStockAtBranch(_resolvedBranchName!)
                                              : ((widget.branchId != null && widget.branchId!.isNotEmpty)
                                                  ? strings.directGiftOutOfStockAtBranch(widget.branchId!)
                                                  : strings.directGiftOutOfStock),
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

  /// Builds the M3 Physical Voucher Serial Numbers Card
  Widget _buildVoucherSerialsCard(
    BuildContext context,
    ColorScheme colorScheme,
    AppStrings strings,
    bool isAr,
  ) {
    if (_voucherSlots.isEmpty) return const SizedBox.shrink();

    final isMandatory = _isVoucherSerialsRequired;
    final sectionTitle = isMandatory
        ? strings.voucherSerialsSectionTitle
        : strings.voucherSerialsSectionTitleOptional;
    final sectionSubtitle = isMandatory
        ? strings.voucherSerialsSectionSubtitle
        : strings.voucherSerialsSectionSubtitleOptional;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.shade400, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.shade200.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Badge & Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade700,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.confirmation_number_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sectionTitle,
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Colors.amber.shade900,
                      ),
                    ),
                    Text(
                      sectionSubtitle,
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Dynamic Voucher Card Input Slots
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _voucherSlots.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final slot = _voucherSlots[index];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    // Badge Number
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '#${index + 1}',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Input Field
                    Expanded(
                      child: TextFormField(
                        controller: slot.controller,
                        focusNode: slot.focusNode,
                        keyboardType: TextInputType.text,
                        inputFormatters: const [
                          ArabicToEnglishDigitsFormatter(),
                        ],
                        onChanged: (val) {
                          setState(() {});
                        },
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                          letterSpacing: 0.5,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          labelText: '${strings.voucherSerialInputLabel} (${slot.giftName})',
                          labelStyle: GoogleFonts.cairo(
                            fontSize: 12,
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                          hintText: strings.voucherSerialInputHint,
                          hintStyle: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade400),
                          border: InputBorder.none,
                          prefixIcon: Icon(Icons.credit_card_rounded, size: 18, color: Colors.amber.shade800),
                          suffixIcon: slot.controller.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 16),
                                  onPressed: () {
                                    slot.controller.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

