import 'ai_receipt_service.dart';

/// Fields both the customer upload and the validation desk write after analysis.
/// Image URLs, customer names, and timestamps stay with the screen that saved them.
Map<String, dynamic> acceptedReceiptCore({
  required AiReceiptAnalysisResult result,
  required String campaignId,
  required String companySlug,
  required String targetCompany,
  required String retailChainName,
  required int chancesEarned,
  required bool allowMultipleChances,
  required String submittedByUid,
  required Map<String, dynamic> branchFields,
  String spendLadderMode = 'exclusive',
}) {
  final totals = PromotionalRuleMatcher.spendTotals(
    products: result.extractedProducts,
    rules: const [],
    spendLadderMode: spendLadderMode,
  );
  // target_company_total is the brand-eligible net. total_value on a consuming
  // receipt is the net of every printed line, including lines that do not qualify.
  final eligible = spendLadderMode == 'consuming' ? totals.eligibleNet : result.targetCompanyTotal;
  final invoiceNet = spendLadderMode == 'consuming' ? totals.invoiceNet : result.targetCompanyTotal;
  return {
    'receipt_number': result.receiptNumber.trim(),
    'is_valid': true,
    'status': 'accepted',
    'rejection_reason': null,
    'unfulfilled_conditions': const <String>[],
    'total_value': invoiceNet,
    'target_company_total': eligible,
    'receipt_date': result.receiptDate,
    'extracted_products': result.extractedProducts.map((item) => item.toJson()).toList(),
    'store_chain_detected': result.storeChainDetected,
    ...branchFields,
    'is_branch_matched': result.isBranchMatched,
    'is_handwritten': result.isHandwritten,
    'is_thermal_pos_receipt': result.isThermalPosReceipt,
    'is_tampered': result.isTampered,
    'is_screen_capture': result.isScreenCapture,
    'fraud_risk_score': result.fraudRiskScore,
    'fraud_reasons': result.fraudReasons,
    'retail_chain_name': retailChainName,
    'campaignId': campaignId,
    'submittedByUid': submittedByUid,
    'companySlug': companySlug,
    'targetCompany': targetCompany,
    'analysis_duration_seconds': result.durationSeconds,
    'analysis_duration_ms': result.durationMs,
    'ai_kpi_rating': result.kpiRating,
    'chances_earned': chancesEarned,
    'allow_multiple_chances': allowMultipleChances,
    if (result.matchedRuleId.isNotEmpty) 'matched_rule_id': result.matchedRuleId,
    if (result.matchedRewardValue.isNotEmpty) 'matched_reward_value': result.matchedRewardValue,
    'aiMessage': result.message,
  };
}
