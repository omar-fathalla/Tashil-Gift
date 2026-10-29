import 'package:al_mraay/core/services/rep_device_id.dart';
import 'package:al_mraay/core/constants/app_version_config.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/firebase_service.dart';
import '../../../../core/services/company_gifts_service.dart';
import '../../../../core/services/game_audio_service.dart';
import '../../../../core/services/multi_campaign_receipt_evaluator.dart';
import '../../../../core/services/receipt_deduplication_helper.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/utils/arabic_numbers_utils.dart';
import '../../../../core/animations/m3_motion.dart';
import '../../../../core/constants/country_currency_config.dart';
import '../../../games/presentation/winner_celebration_dialog.dart';
import '../../../company_portal/domain/whatsapp_gateway_service.dart';
import '../../../company_portal/domain/whatsapp_winner_notification_service.dart';

/// Helper for individual voucher serial input in multi-campaign view
class MultiCampaignVoucherSlot {
  final String campaignId;
  final String giftId;
  final String giftName;
  final double unitValue;
  final int indexInBundle;
  final TextEditingController controller;
  final FocusNode focusNode;

  MultiCampaignVoucherSlot({
    required this.campaignId,
    required this.giftId,
    required this.giftName,
    required this.unitValue,
    required this.indexInBundle,
    required this.controller,
    required this.focusNode,
  });
}

/// Unified screen to disburse rewards when a single receipt qualifies for
/// multiple concurrent company campaigns (e.g. Hair Care + Oral Care + Deos).
class UnifiedMultiCampaignClaimScreen extends ConsumerStatefulWidget {
  final String bundleGroupId;
  final String receiptNumber;
  final String customerPhone;
  final String customerName;
  final List<CampaignQualificationResult> qualifiedCampaigns;
  final List<String> imageUrls;
  final Map<String, dynamic>? initialAiMetadata;
  final VoidCallback? onDisbursalCompleted;

  const UnifiedMultiCampaignClaimScreen({
    super.key,
    required this.bundleGroupId,
    required this.receiptNumber,
    required this.customerPhone,
    required this.customerName,
    required this.qualifiedCampaigns,
    this.imageUrls = const [],
    this.initialAiMetadata,
    this.onDisbursalCompleted,
  });

  @override
  ConsumerState<UnifiedMultiCampaignClaimScreen> createState() =>
      _UnifiedMultiCampaignClaimScreenState();
}

class _UnifiedMultiCampaignClaimScreenState
    extends ConsumerState<UnifiedMultiCampaignClaimScreen>
    with SingleTickerProviderStateMixin {
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  bool _isClaiming = false;
  bool _isClaimed = false;

  final List<MultiCampaignVoucherSlot> _voucherSlots = [];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: M3Curves.emphasizedDecelerate,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );
    _animController.forward();

    _setupVoucherSlots();

    // Play winning celebratory sound
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gameAudioServiceProvider).playWinFanfare();
    });
  }

  void _setupVoucherSlots() {
    for (final q in widget.qualifiedCampaigns) {
      if (q.campaign.requireVoucherSerials) {
        if (q.resolvedLinkedGifts.isNotEmpty) {
          int slotIdx = 0;
          for (final gift in q.resolvedLinkedGifts) {
            if (gift.isVoucher) {
              for (int k = 0; k < gift.quantity; k++) {
                _voucherSlots.add(
                  MultiCampaignVoucherSlot(
                    campaignId: q.campaign.id,
                    giftId: gift.giftId,
                    giftName: gift.giftName,
                    unitValue: gift.unitValue,
                    indexInBundle: slotIdx++,
                    controller: TextEditingController(),
                    focusNode: FocusNode(),
                  ),
                );
              }
            }
          }
        } else if (q.resolvedIsVoucher) {
          for (int k = 0; k < q.promoQuantity; k++) {
            _voucherSlots.add(
              MultiCampaignVoucherSlot(
                campaignId: q.campaign.id,
                giftId: q.campaign.id,
                giftName: q.designatedPrize,
                unitValue: q.resolvedUnitValue ?? 50.0,
                indexInBundle: k,
                controller: TextEditingController(),
                focusNode: FocusNode(),
              ),
            );
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    for (final s in _voucherSlots) {
      s.controller.dispose();
      s.focusNode.dispose();
    }
    super.dispose();
  }

  Future<void> _handleConfirmAllDisbursals() {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    // 1. Validate all required voucher serials
    for (final slot in _voucherSlots) {
      final text = slot.controller.text.trim();
      if (text.isEmpty) {
        slot.focusNode.requestFocus();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAr
                  ? 'برجاء إدخال الرقم التسلسلي (السيريال) لكارت: ${slot.giftName}'
                  : 'Please enter voucher serial for: ${slot.giftName}',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return Future.value();
      }
    }

    return _executeDisbursal();
  }

  Future<void> _executeDisbursal() async {
    setState(() => _isClaiming = true);
    final firestore = ref.read(firestoreProvider);
    final giftsService = ref.read(companyGiftsServiceProvider);

    try {
      final primaryCompanySlug = widget.qualifiedCampaigns.isNotEmpty
          ? widget.qualifiedCampaigns.first.campaign.companySlug
          : '';
      if (primaryCompanySlug.isNotEmpty) {
        final dupCheck = await ReceiptDeduplicationHelper.checkReceiptDuplicate(
          firestore: firestore,
          receiptNumber: widget.receiptNumber,
          companySlug: primaryCompanySlug,
          isMultiScan: true,
        );
        if (dupCheck.isDuplicate) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                dupCheck.rejectionMessage,
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
              backgroundColor: colorScheme.onSecondaryContainer,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
          setState(() => _isClaiming = false);
          return;
        }
      }

      final List<String> allAwardedPrizeSummaries = [];

      // Save a linked transaction for EACH qualified campaign
      for (final q in widget.qualifiedCampaigns) {
        final campaign = q.campaign;
        final campaignVoucherSlots = _voucherSlots
            .where((s) => s.campaignId == campaign.id)
            .toList();

        final campaignSerials = campaignVoucherSlots
            .map((s) => s.controller.text.toEnglishDigits(convertDecimal: false).trim())
            .where((t) => t.isNotEmpty)
            .toList();

        final claimedGiftsList = q.resolvedLinkedGifts.isNotEmpty
            ? q.resolvedLinkedGifts.map((g) {
                final relevantSerials = campaignVoucherSlots
                    .where((s) => s.giftId == g.giftId)
                    .map((s) => s.controller.text.toEnglishDigits(convertDecimal: false).trim())
                    .where((t) => t.isNotEmpty)
                    .toList();
                return {
                  'gift_id': g.giftId,
                  'gift_name': g.giftName,
                  'quantity': g.quantity,
                  'unit_value': g.unitValue,
                  'is_voucher': g.isVoucher,
                  'voucher_serials': relevantSerials,
                };
              }).toList()
            : [
                {
                  'gift_id': campaign.id,
                  'gift_name': q.designatedPrize,
                  'quantity': q.promoQuantity,
                  'unit_value': q.resolvedUnitValue,
                  'is_voucher': q.resolvedIsVoucher,
                  'voucher_serials': campaignSerials,
                }
              ];

        allAwardedPrizeSummaries.add('${campaign.eventName}: ${q.designatedPrize}');

        final deterministicDocId = ReceiptDeduplicationHelper.getDeterministicDocId(
          campaignId: campaign.id,
          receiptNumber: widget.receiptNumber,
        );
        final txRef = firestore.collection('receipts_transactions').doc(deterministicDocId);
        final extractedProds = widget.initialAiMetadata?['extracted_products'];

        await txRef.set({
          'bundle_group_id': widget.bundleGroupId,
          'app_version': AppVersionConfig.appVersion,
          if (RepDeviceId.value.isNotEmpty) 'rep_device_id': RepDeviceId.value,
          'receipt_number': widget.receiptNumber,
          'campaignId': campaign.id,
          'submittedByUid': ref.read(firebaseAuthProvider).currentUser?.uid ?? '',
          'companySlug': campaign.companySlug,
          'targetCompany': campaign.targetCompany,
          'retail_chain_name': campaign.retailChainName,
          'branch_detected': q.resolvedBranchName ?? '',
          'canonical_branch': q.resolvedBranchName ?? '',
          'branch_id': q.resolvedBranchId ?? '',
          'customerPhone': widget.customerPhone,
          'customerName': widget.customerName,
          'prize_won': q.designatedPrize,
          'unit_value': q.resolvedUnitValue,
          'is_voucher': q.resolvedIsVoucher,
          'claimed_gifts': claimedGiftsList,
          'linked_gifts': q.resolvedLinkedGifts.map((g) => g.toMap()).toList(),
          if (campaignSerials.isNotEmpty) 'voucher_serials': campaignSerials,
          if (campaignSerials.isNotEmpty) 'voucher_serial': campaignSerials.first,
          'game_played': true,
          'game_type': 'directGift',
          'is_valid': true,
          'status': 'accepted',
          'claim_status': 'handed_over',
          'claimed_at': DateTime.now().toIso8601String(),
          'is_multi_campaign_bundle': true,
          'bundle_campaign_count': widget.qualifiedCampaigns.length,
          'timestamp': FieldValue.serverTimestamp(),
          'total_value': q.qualifyingSpend,
          'extracted_products': extractedProds ?? const [],
          if (widget.imageUrls.isNotEmpty) 'image_url': widget.imageUrls.first,
          if (widget.imageUrls.length > 1) 'image_urls': widget.imageUrls,
          if (widget.initialAiMetadata != null) ...widget.initialAiMetadata!,
        });

        // Decrement branch inventory
        if (q.resolvedLinkedGifts.isNotEmpty) {
          for (final giftAlloc in q.resolvedLinkedGifts) {
            await giftsService.decrementCampaignPrize(
              campaign.id,
              giftAlloc.giftId.isNotEmpty ? giftAlloc.giftId : giftAlloc.giftName,
              branchId: q.resolvedBranchId,
              count: giftAlloc.quantity,
              unitValue: giftAlloc.unitValue,
              isVoucher: giftAlloc.isVoucher,
            );
          }
        } else {
          await giftsService.decrementCampaignPrize(
            campaign.id,
            q.designatedPrize,
            branchId: q.resolvedBranchId,
            count: q.promoQuantity,
            unitValue: q.resolvedUnitValue,
            isVoucher: q.resolvedIsVoucher,
          );
        }
      }

      // Dispatch automated celebratory WhatsApp winner message
      final isAnyCampaignWhatsAppEnabled = widget.qualifiedCampaigns.any((q) => q.campaign.enableWhatsAppWinnerNotification);
      Future<WhatsAppGatewayResult?>? whatsappFuture;
      if (isAnyCampaignWhatsAppEnabled && widget.customerPhone.isNotEmpty && widget.qualifiedCampaigns.isNotEmpty) {
        final firstCampaign = widget.qualifiedCampaigns.first;
        final combinedPrizeName = allAwardedPrizeSummaries.join(' + ');
        whatsappFuture = ref.read(whatsappWinnerNotificationServiceProvider).sendWinnerNotification(
          toPhone: widget.customerPhone,
          prizeName: combinedPrizeName,
          customerName: widget.customerName,
          retailChain: firstCampaign.campaign.retailChainName,
          branchName: firstCampaign.resolvedBranchName,
          companyName: firstCampaign.campaign.targetCompany,
          receiptNumber: widget.receiptNumber,
          companySlug: firstCampaign.campaign.companySlug,
          isEnabledForCampaign: isAnyCampaignWhatsAppEnabled,
        );
      }

      if (!mounted) return;

      setState(() {
        _isClaiming = false;
        _isClaimed = true;
      });

      // Show celebratory completion
      await showWinnerCelebrationDialog(
        context: context,
        prizeName: allAwardedPrizeSummaries.join('\n• '),
        isVoucher: widget.qualifiedCampaigns.any((q) => q.resolvedIsVoucher),
        recipientPhone: isAnyCampaignWhatsAppEnabled ? widget.customerPhone : null,
        whatsappDispatchFuture: whatsappFuture,
        onNextCustomer: () {},
      );

      widget.onDisbursalCompleted?.call();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isClaiming = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء تسليم الجوائز.'),
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final activeCountry = ref.watch(activeCountryProvider);

    final totalGiftsCount = widget.qualifiedCampaigns.fold<int>(
      0,
      (acc, q) => acc + q.totalAwardedItemsCount,
    );

    return PopScope(
      canPop: !_isClaiming,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: Text(
            isAr ? 'سلة الجوائز الشاملة المجمعة' : 'Consolidated Prize Basket',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              isAr ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
            ),
            tooltip: isAr ? 'الرجوع لرفع الفاتورة' : 'Back to Upload',
            onPressed: (_isClaiming || _isClaimed) ? null : () => Navigator.of(context).pop(),
          ),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: TextButton.icon(
                onPressed: (_isClaiming || _isClaimed) ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, size: 20),
                label: Text(
                  isAr ? 'إلغاء' : 'Cancel',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header celebration banner
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              colorScheme.primary,
                              colorScheme.primary.withValues(alpha: 0.8),
                              colorScheme.secondary,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.primary.withValues(alpha: 0.25),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.stars_rounded,
                                size: 44,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              isAr ? 'تهانينا! الفاتورة مؤهلة في عدة عروض' : 'Congratulations! Multi-Campaign Winner',
                              style: GoogleFonts.cairo(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isAr
                                  ? 'استوفت هذه الفاتورة شروط (${widget.qualifiedCampaigns.length}) عروض متزامنة، واستحقت ($totalGiftsCount) جوائز فورية!'
                                  : 'This receipt qualifies for (${widget.qualifiedCampaigns.length}) concurrent campaigns with ($totalGiftsCount) total prizes!',
                              style: GoogleFonts.cairo(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (widget.receiptNumber.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${isAr ? 'رقم الفاتورة' : 'Receipt #'}: ${widget.receiptNumber}',
                                  style: GoogleFonts.robotoMono(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Itemized cards for each qualified campaign
                      ...widget.qualifiedCampaigns.map((q) => _buildCampaignCard(context, q, isAr, activeCountry)),

                      const SizedBox(height: 24),

                      // Grand action button
                      FilledButton.icon(
                        onPressed: (_isClaiming || _isClaimed) ? null : _handleConfirmAllDisbursals,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: colorScheme.tertiary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          elevation: 4,
                        ),
                        icon: _isClaiming
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : const Icon(Icons.check_circle_rounded, size: 24),
                        label: Text(
                          _isClaiming
                              ? (isAr ? 'جاري تسليم الجوائز وخصم المخزون...' : 'Disbursing prizes...')
                              : (isAr
                                  ? 'تأكيد وتسليم كافة الجوائز ($totalGiftsCount جوائز)'
                                  : 'Confirm & Disburse All ($totalGiftsCount Prizes)'),
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Secondary Return / Retake Receipt Button
                      OutlinedButton.icon(
                        onPressed: (_isClaiming || _isClaimed) ? null : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          foregroundColor: colorScheme.onSurfaceVariant,
                          side: BorderSide(
                            color: colorScheme.outline.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        icon: Icon(
                          isAr ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
                          size: 20,
                        ),
                        label: Text(
                          isAr
                              ? 'الرجوع وتصوير / رفع فاتورة أخرى'
                              : 'Back to Upload / Retake Receipt',
                          style: GoogleFonts.cairo(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

  Widget _buildCampaignCard(
    BuildContext context,
    CampaignQualificationResult q,
    bool isAr,
    dynamic activeCountry,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final campaignSlots = _voucherSlots.where((s) => s.campaignId == q.campaign.id).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Campaign title banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.card_giftcard_rounded, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        q.campaign.eventName,
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (q.resolvedBranchName != null && q.resolvedBranchName!.isNotEmpty)
                        Text(
                          '${isAr ? 'الفرع المعتمد' : 'Branch'}: ${q.resolvedBranchName}',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.tertiaryFixedDim),
                  ),
                  child: Text(
                    isAr ? 'مؤهل للفوز' : 'Qualified',
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onTertiaryFixedVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Prize and voucher breakdown
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (q.matchedRules.isNotEmpty)
                  ...q.matchedRules.map((r) {
                    final isVoucher = r.rule.rewardType == 'voucher' || r.totalRewardAmount > 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isVoucher
                            ? colorScheme.secondaryContainer.withValues(alpha: 0.5)
                            : colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isVoucher
                              ? colorScheme.primaryFixedDim
                              : colorScheme.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isVoucher
                                  ? colorScheme.secondaryContainer
                                  : colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isVoucher
                                  ? Icons.confirmation_number_outlined
                                  : Icons.redeem_rounded,
                              size: 22,
                              color: isVoucher ? colorScheme.onSecondaryContainer : colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.formattedPrizeSummary,
                                  style: GoogleFonts.cairo(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Icon(
                                        Icons.check_circle_outline_rounded,
                                        size: 13,
                                        color: colorScheme.tertiary,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        isAr ? r.qualifyingReasonText : r.qualifyingReasonTextEn,
                                        style: GoogleFonts.cairo(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (r.multipliedLinkedGifts.isNotEmpty)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(start: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: r.multipliedLinkedGifts.map((g) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    margin: const EdgeInsets.only(bottom: 2),
                                    decoration: BoxDecoration(
                                      color: g.isVoucher ? colorScheme.secondaryContainer : colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: g.isVoucher ? colorScheme.secondaryFixedDim : colorScheme.outlineVariant,
                                      ),
                                    ),
                                    child: Text(
                                      '${g.quantity} × ${g.giftName}',
                                      style: GoogleFonts.cairo(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: g.isVoucher ? colorScheme.onSecondaryContainer : colorScheme.onSurface,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                        ],
                      ),
                    );
                  })
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: q.resolvedIsVoucher
                          ? colorScheme.secondaryContainer.withValues(alpha: 0.5)
                          : colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: q.resolvedIsVoucher
                            ? colorScheme.primaryFixedDim
                            : colorScheme.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: q.resolvedIsVoucher
                                ? colorScheme.secondaryContainer
                                : colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            q.resolvedIsVoucher
                                ? Icons.confirmation_number_outlined
                                : Icons.redeem_rounded,
                            size: 22,
                            color: q.resolvedIsVoucher ? colorScheme.onSecondaryContainer : colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                q.designatedPrize,
                                style: GoogleFonts.cairo(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Icon(
                                      Icons.check_circle_outline_rounded,
                                      size: 13,
                                      color: colorScheme.tertiary,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      isAr
                                          ? (q.qualifyingSpend > 0
                                              ? 'استحقاق لتجاوز الحد الأدنى للمشتريات (${q.qualifyingSpend.toInt()} ج.م)'
                                              : 'استحقاق استيفاء شروط العرض')
                                          : (q.qualifyingSpend > 0
                                              ? 'Qualified for exceeding min spend (${q.qualifyingSpend.toInt()} EGP)'
                                              : 'Qualified for fulfilling promo criteria'),
                                      style: GoogleFonts.cairo(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (q.resolvedLinkedGifts.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: q.resolvedLinkedGifts.map((g) {
                                    return Chip(
                                      label: Text(
                                        '${g.quantity} × ${g.giftName}',
                                        style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: g.isVoucher ? colorScheme.secondaryContainer : colorScheme.surface,
                                      side: BorderSide(color: colorScheme.outlineVariant),
                                      padding: EdgeInsets.zero,
                                    );
                                  }).toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                // Voucher serial inputs if required
                if (campaignSlots.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Text(
                    isAr ? 'أرقام السيريال لكروت الفواتشر:' : 'Voucher Serial Numbers:',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...campaignSlots.map((slot) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TextFormField(
                          controller: slot.controller,
                          focusNode: slot.focusNode,
                          keyboardType: TextInputType.text,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            labelText: '${slot.giftName} (#${slot.indexInBundle + 1})',
                            hintText: isAr ? 'أدخل رقم السيريال المطبوع على الكارت' : 'Enter voucher serial',
                            prefixIcon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true,
                            fillColor: colorScheme.surface,
                          ),
                        ),
                      )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
