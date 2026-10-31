import 'dart:math' as math;

import '../../features/admin/domain/event_model.dart';
import 'ai_receipt_service.dart';

/// Result of evaluating a receipt against a single campaign.
class CampaignQualificationResult {
  final EventModel campaign;
  final bool isQualified;
  final List<MatchedPromotionalRuleResult> matchedRules;
  final CompositePromotionalBundle? compositeBundle;
  final String designatedPrize;
  final List<LinkedGiftAllocation> resolvedLinkedGifts;
  final double? resolvedUnitValue;
  final bool resolvedIsVoucher;
  final int promoQuantity;
  final int totalChances;
  final String? resolvedBranchId;
  final String? resolvedBranchName;
  final double qualifyingSpend;
  final String? rejectionReason;
  final List<String> unfulfilledConditions;

  const CampaignQualificationResult({
    required this.campaign,
    required this.isQualified,
    this.matchedRules = const [],
    this.compositeBundle,
    this.designatedPrize = '',
    this.resolvedLinkedGifts = const [],
    this.resolvedUnitValue,
    this.resolvedIsVoucher = false,
    this.promoQuantity = 1,
    this.totalChances = 1,
    this.resolvedBranchId,
    this.resolvedBranchName,
    this.qualifyingSpend = 0.0,
    this.rejectionReason,
    this.unfulfilledConditions = const [],
  });

  /// Total count of physical items or vouchers awarded for this campaign
  int get totalAwardedItemsCount {
    if (resolvedLinkedGifts.isNotEmpty) {
      return resolvedLinkedGifts.fold<int>(0, (acc, g) => acc + g.quantity);
    }
    return promoQuantity;
  }
}

/// Consolidated summary of evaluating a receipt against all active company campaigns.
class MultiCampaignEvaluationSummary {
  final AiReceiptAnalysisResult aiResult;
  final List<CampaignQualificationResult> allEvaluations;
  final List<CampaignQualificationResult> qualifiedCampaigns;
  final List<CampaignQualificationResult> unfulfilledCampaigns;

  const MultiCampaignEvaluationSummary({
    required this.aiResult,
    required this.allEvaluations,
    required this.qualifiedCampaigns,
    required this.unfulfilledCampaigns,
  });

  bool get hasAnyQualified => qualifiedCampaigns.isNotEmpty;
  bool get isSingleMatch => qualifiedCampaigns.length == 1;
  bool get isMultiMatch => qualifiedCampaigns.length > 1;

  /// Sum of all distinct physical gifts and vouchers across all qualified campaigns
  int get grandTotalAwardedPrizes {
    return qualifiedCampaigns.fold<int>(0, (sum, q) => sum + q.totalAwardedItemsCount);
  }

  /// Total voucher monetary value across all qualified campaigns
  double get grandTotalVoucherValue {
    return qualifiedCampaigns.fold<double>(0.0, (sum, q) {
      if (q.resolvedLinkedGifts.isNotEmpty) {
        return sum + q.resolvedLinkedGifts
            .where((g) => g.isVoucher)
            .fold<double>(0.0, (acc, g) => acc + g.totalMonetaryValue);
      }
      if (q.resolvedIsVoucher && q.resolvedUnitValue != null) {
        return sum + (q.resolvedUnitValue! * q.promoQuantity);
      }
      return sum;
    });
  }
}

/// Deterministic in-memory multi-campaign evaluator.
class MultiCampaignReceiptEvaluator {
  /// Evaluates an AI receipt analysis result against a list of active campaigns.
  static MultiCampaignEvaluationSummary evaluateAll({
    required AiReceiptAnalysisResult result,
    required List<EventModel> campaigns,
  }) {
    final List<CampaignQualificationResult> all = [];
    final List<CampaignQualificationResult> qualified = [];
    final List<CampaignQualificationResult> unfulfilled = [];

    for (final campaign in campaigns) {
      final eval = evaluateCampaign(result: result, campaign: campaign);
      all.add(eval);
      if (eval.isQualified) {
        qualified.add(eval);
      } else {
        unfulfilled.add(eval);
      }
    }

    return MultiCampaignEvaluationSummary(
      aiResult: result,
      allEvaluations: all,
      qualifiedCampaigns: qualified,
      unfulfilledCampaigns: unfulfilled,
    );
  }

  /// Evaluates a receipt against a single campaign.
  static CampaignQualificationResult evaluateCampaign({
    required AiReceiptAnalysisResult result,
    required EventModel campaign,
  }) {
    // 1. Check basic AI validity
    if (!result.isValid) {
      final unfulfilled = result.unfulfilledConditions.isNotEmpty
          ? result.unfulfilledConditions
          : [result.message.trim().isNotEmpty ? result.message.trim() : 'الفاتورة غير مقروءة أو غير واضحة'];
      return CampaignQualificationResult(
        campaign: campaign,
        isQualified: false,
        rejectionReason: unfulfilled.join(' • '),
        unfulfilledConditions: unfulfilled,
      );
    }

    // 2. Date check
    if (campaign.isExpired) {
      final endStr = campaign.endDate != null
          ? "${campaign.endDate!.day}/${campaign.endDate!.month}/${campaign.endDate!.year}"
          : "تاريخ الانتهاء";
      final msg = 'انتهت سريان فترة هذه الحملة بتاريخ $endStr.';
      return CampaignQualificationResult(
        campaign: campaign,
        isQualified: false,
        rejectionReason: msg,
        unfulfilledConditions: [msg],
      );
    }
    if (campaign.isNotStartedYet) {
      final startStr = campaign.startDate != null
          ? "${campaign.startDate!.day}/${campaign.startDate!.month}/${campaign.startDate!.year}"
          : "تاريخ البدء";
      final msg = 'تبدأ هذه الحملة بتاريخ $startStr.';
      return CampaignQualificationResult(
        campaign: campaign,
        isQualified: false,
        rejectionReason: msg,
        unfulfilledConditions: [msg],
      );
    }

    // 3. Resolve canonical branch
    final branchResolution = _resolveBranch(
      detectedBranch: result.branchDetected,
      detectedChain: result.storeChainDetected,
      campaign: campaign,
    );

    if (!campaign.isAllBranches && campaign.branchNames.isNotEmpty && !branchResolution.isMatched) {
      final msg = 'الفرع المستخرج من الفاتورة (${result.branchDetected.isNotEmpty ? result.branchDetected : "غير محدد"}) ليس ضمن الفروع المعتمدة لهذه الحملة.';
      return CampaignQualificationResult(
        campaign: campaign,
        isQualified: false,
        rejectionReason: msg,
        unfulfilledConditions: [msg],
        resolvedBranchId: branchResolution.branchId,
        resolvedBranchName: branchResolution.branchName,
      );
    }

    // 4. Evaluate promotional rules
    final matchedRulesList = PromotionalRuleMatcher.matchAllWithMultipliers(
      result: result,
      promotionalRules: campaign.promotionalRules,
      allowCampaignMultipliers: campaign.allowMultipleChances,
    );

    // If campaign mandates promotional rules and none match -> Reject
    if (campaign.promotionalRules.isNotEmpty && matchedRulesList.isEmpty) {
      final unfulfilledList = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
        result: result,
        promotionalRules: campaign.promotionalRules,
      );
      final reason = unfulfilledList.isNotEmpty
          ? unfulfilledList.join(' • ')
          : 'شروط العروض الترويجية لحملة (${campaign.eventName}) غير مستوفاة في الفاتورة.';
      return CampaignQualificationResult(
        campaign: campaign,
        isQualified: false,
        rejectionReason: reason,
        unfulfilledConditions: unfulfilledList.isNotEmpty ? unfulfilledList : [reason],
        resolvedBranchId: branchResolution.branchId,
        resolvedBranchName: branchResolution.branchName,
      );
    }

    // 5. Spend evaluation if no promotional rules
    double targetSpend = result.targetCompanyTotal;
    if (campaign.promotionalRules.isEmpty && campaign.minimumSpend > 0 && targetSpend < campaign.minimumSpend) {
      final msg = 'إجمالي المشتريات (${targetSpend.toStringAsFixed(1)} ج.م) أقل من الحد الأدنى المطلوب للعرض (${campaign.minimumSpend.toStringAsFixed(1)} ج.م).';
      return CampaignQualificationResult(
        campaign: campaign,
        isQualified: false,
        rejectionReason: msg,
        unfulfilledConditions: [msg],
        resolvedBranchId: branchResolution.branchId,
        resolvedBranchName: branchResolution.branchName,
      );
    }

    // 6. Campaign is QUALIFIED! Resolve prizes and bundles
    final prizeNames = campaign.allocatedPrizes
        .where((p) => p.remainingQuantity > 0)
        .map((p) => p.name)
        .toList();

    final compositeBundle = matchedRulesList.isNotEmpty
        ? CompositePromotionalBundle.fromMatchedRules(
            matchedRulesList,
            fallbackTitle: result.matchedRewardValue.trim().isNotEmpty
                ? result.matchedRewardValue.trim()
                : (prizeNames.isNotEmpty ? prizeNames.first : 'هدية ترويجية مميزة'),
          )
        : null;

    final designatedPrizeObj = campaign.availablePrizes.isNotEmpty
        ? campaign.availablePrizes.first
        : (campaign.allocatedPrizes.isNotEmpty ? campaign.allocatedPrizes.first : null);

    String designatedPrize;
    List<LinkedGiftAllocation> resolvedLinkedGifts = [];
    double? resolvedUnitValue;
    bool resolvedIsVoucher = false;

    if (compositeBundle != null && matchedRulesList.isNotEmpty) {
      resolvedLinkedGifts = compositeBundle.combinedLinkedGifts;
      designatedPrize = compositeBundle.compositePrizeTitle;

      resolvedIsVoucher = compositeBundle.totalVoucherValue > 0 ||
          resolvedLinkedGifts.any((g) => g.isVoucher) ||
          designatedPrize.contains('فواتشر') ||
          designatedPrize.toLowerCase().contains('voucher') ||
          designatedPrize.contains('قسيمة');

      resolvedUnitValue = resolvedIsVoucher
          ? (compositeBundle.totalVoucherValue > 0
              ? compositeBundle.totalVoucherValue
              : designatedPrizeObj?.unitValue)
          : 0.0;
    } else if (result.matchedRewardValue.trim().isNotEmpty) {
      designatedPrize = result.matchedRewardValue.trim();
      resolvedIsVoucher = result.matchedRewardType == 'voucher' ||
          result.matchedRewardAmount > 0 ||
          designatedPrize.contains('فواتشر') ||
          designatedPrize.contains('قسيمة');
      resolvedUnitValue = resolvedIsVoucher
          ? (result.matchedRewardAmount > 0 ? result.matchedRewardAmount : designatedPrizeObj?.unitValue)
          : 0.0;
    } else {
      designatedPrize = designatedPrizeObj?.name ?? (prizeNames.isNotEmpty ? prizeNames.first : 'هدية معتمدة');
      resolvedUnitValue = designatedPrizeObj?.unitValue;
      resolvedIsVoucher = designatedPrizeObj?.isVoucher ?? false;
    }

    // Clean placeholder titles
    if (designatedPrize.isEmpty ||
        designatedPrize == 'هدية فورية مميزة' ||
        designatedPrize == 'هدية ترويجية مميزة' ||
        RegExp(r'^[a-zA-Z0-9_-]{15,35}$').hasMatch(designatedPrize)) {
      if (resolvedLinkedGifts.isNotEmpty) {
        designatedPrize = resolvedLinkedGifts.map((g) => g.quantity > 1 ? '${g.quantity} × ${g.giftName}' : g.giftName).join(' + ');
        resolvedIsVoucher = resolvedLinkedGifts.any((g) => g.isVoucher);
        resolvedUnitValue = resolvedIsVoucher
            ? resolvedLinkedGifts.fold<double>(0.0, (acc, g) => acc + g.totalMonetaryValue)
            : 0.0;
      } else if (resolvedIsVoucher || (resolvedUnitValue != null && resolvedUnitValue > 0)) {
        final val = (resolvedUnitValue != null && resolvedUnitValue > 0)
            ? (resolvedUnitValue == resolvedUnitValue.roundToDouble() ? resolvedUnitValue.toInt() : resolvedUnitValue)
            : 50;
        designatedPrize = 'فواتشر بقيمة $val جنيه';
        resolvedIsVoucher = true;
        resolvedUnitValue ??= 50.0;
      } else {
        designatedPrize = 'هدية فورية معتمدة';
        resolvedIsVoucher = false;
        resolvedUnitValue = 0.0;
      }
    }

    final totalChances = clampCampaignChances(
      math.max(
        result.chancesEarned > 0 ? result.chancesEarned : 1,
        compositeBundle?.totalChances ?? 1,
      ),
      allowMultipleChances: campaign.allowMultipleChances,
      maxChancesPerReceipt: campaign.maxChancesPerReceipt,
    );

    final promoQuantity = resolvedLinkedGifts.isNotEmpty
        ? 1
        : (campaign.allowMultipleChances ? totalChances : 1);

    return CampaignQualificationResult(
      campaign: campaign,
      isQualified: true,
      matchedRules: matchedRulesList,
      compositeBundle: compositeBundle,
      designatedPrize: designatedPrize,
      resolvedLinkedGifts: resolvedLinkedGifts,
      resolvedUnitValue: resolvedUnitValue,
      resolvedIsVoucher: resolvedIsVoucher,
      promoQuantity: promoQuantity,
      totalChances: totalChances,
      resolvedBranchId: branchResolution.branchId,
      resolvedBranchName: branchResolution.branchName,
      qualifyingSpend: targetSpend,
    );
  }

  /// Helper to resolve canonical branch and check eligibility
  static _BranchResolution _resolveBranch({
    required String detectedBranch,
    required String detectedChain,
    required EventModel campaign,
  }) {
    if (campaign.isAllBranches || campaign.branchNames.isEmpty) {
      return _BranchResolution(
        isMatched: true,
        branchId: campaign.branchIds.isNotEmpty ? campaign.branchIds.first : null,
        branchName: detectedBranch.isNotEmpty ? detectedBranch : (campaign.branchNames.isNotEmpty ? campaign.branchNames.first : null),
      );
    }

    final cleanDetected = _cleanBranchForComparison(detectedBranch);
    if (cleanDetected.isEmpty) {
      return _BranchResolution(
        isMatched: false,
        branchId: campaign.branchIds.isNotEmpty ? campaign.branchIds.first : null,
        branchName: null,
      );
    }

    // 1. Direct or fuzzy match with campaign canonical branches
    for (int i = 0; i < campaign.branchNames.length; i++) {
      final canonName = campaign.branchNames[i];
      final cleanCanon = _cleanBranchForComparison(canonName);
      if (cleanCanon == cleanDetected || cleanCanon.contains(cleanDetected) || cleanDetected.contains(cleanCanon)) {
        final bId = i < campaign.branchIds.length ? campaign.branchIds[i] : null;
        return _BranchResolution(
          isMatched: true,
          branchId: bId,
          branchName: canonName,
        );
      }
    }

    // 2. Specific landmark matching
    for (int i = 0; i < campaign.branchNames.length; i++) {
      final canonName = campaign.branchNames[i];
      final cleanCanon = _cleanBranchForComparison(canonName);

      if ((cleanDetected.contains('سموح') && cleanCanon.contains('سموح')) ||
          (cleanDetected.contains('عجمي') && cleanCanon.contains('عجمي')) ||
          (cleanDetected.contains('جاردينيا') && cleanCanon.contains('جاردينيا')) ||
          (cleanDetected.contains('رحاب') && cleanCanon.contains('رحاب')) ||
          (cleanDetected.contains('محله') && cleanCanon.contains('محله')) ||
          (cleanDetected.contains('منصور') && cleanCanon.contains('منصور')) ||
          (cleanDetected.contains('تجمع') && cleanCanon.contains('تجمع')) ||
          (cleanDetected.contains('اكتوبر') && cleanCanon.contains('اكتوبر')) ||
          (cleanDetected.contains('منتزه') && cleanCanon.contains('منتزه')) ||
          (cleanDetected.contains('ميامي') && cleanCanon.contains('ميامي')) ||
          (cleanDetected.contains('جناكليس') && cleanCanon.contains('جناكليس')) ||
          (cleanDetected.contains('عبور') && cleanCanon.contains('عبور'))) {
        final bId = i < campaign.branchIds.length ? campaign.branchIds[i] : null;
        return _BranchResolution(
          isMatched: true,
          branchId: bId,
          branchName: canonName,
        );
      }
    }

    return _BranchResolution(
      isMatched: false,
      branchId: campaign.branchIds.isNotEmpty ? campaign.branchIds.first : null,
      branchName: detectedBranch,
    );
  }

  static String _cleanBranchForComparison(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '') // remove governorates like (الإسكندرية)
        .replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('فرع', '')
        .trim();
  }
}

class _BranchResolution {
  final bool isMatched;
  final String? branchId;
  final String? branchName;

  _BranchResolution({
    required this.isMatched,
    this.branchId,
    this.branchName,
  });
}
