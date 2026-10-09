// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  test('Investigate Edco receipt matching with actual rule from Firestore', () {
    final file = File('/tmp/edco_rule.json');
    if (!file.existsSync()) return;
    final Map<String, dynamic> ruleJson = jsonDecode(file.readAsStringSync());

    final rule = PromotionalRuleItem(
      id: ruleJson['id'] ?? 'rule_1',
      ruleTitle: ruleJson['ruleTitle'] ?? '',
      triggerProduct: ruleJson['triggerProduct'] ?? '',
      minQuantity: ruleJson['minQuantity'] ?? 1,
      conditionType: ruleJson['conditionType'] ?? 'by_spend',
      minSpend: (ruleJson['minSpend'] as num?)?.toDouble() ?? 340.0,
      maxSpend: (ruleJson['maxSpend'] as num?)?.toDouble(),
      discountTolerance: (ruleJson['discountTolerance'] as num?)?.toDouble() ?? 10.0,
      matchMode: ruleJson['matchMode'] ?? 'OR',
      requiredBrands: List<String>.from(ruleJson['requiredBrands'] ?? []),
      selectedBarcodes: List<String>.from(ruleJson['selectedBarcodes'] ?? []),
      selectedProductNames: List<String>.from(ruleJson['selectedProductNames'] ?? []),
      rewardType: ruleJson['rewardType'] ?? 'free_product',
      rewardValue: ruleJson['rewardValue'] ?? '',
      rewardAmount: (ruleJson['rewardAmount'] as num?)?.toDouble() ?? 0.0,
      allowMultipliers: ruleJson['allowMultipliers'] ?? true,
      linkedGifts: (ruleJson['linkedGifts'] as List? ?? []).map((g) {
        return LinkedGiftAllocation(
          giftId: g['giftId'] ?? '',
          giftName: g['giftName'] ?? '',
          quantity: g['quantity'] ?? 1,
          unitValue: (g['unitValue'] as num?)?.toDouble() ?? 50.0,
          giftType: g['giftType'] ?? 'voucher',
        );
      }).toList(),
    );

    final List<ExtractedProductItem> extractedProducts = [
      ExtractedProductItem(
        name: 'فلفيتا منعم ملابس',
        quantity: 1,
        price: 169.0,
        isTargetCompany: true,
      ),
      ExtractedProductItem(
        name: 'ديفا سائل الاستحم',
        quantity: 1,
        price: 170.0,
        isTargetCompany: true,
      ),
      ExtractedProductItem(
        name: 'كلوريل سوبر 1×4',
        quantity: 1,
        price: 33.0,
        isTargetCompany: true,
      ),
    ];

    print('Rule Title: ${rule.ruleTitle}');
    print('Rule conditionType: ${rule.conditionType}');
    print('Rule triggerProduct: ${rule.triggerProduct}');
    print('Rule minSpend: ${rule.minSpend}');
    print('Rule isSpendBased: ${rule.isSpendBased}');
    print('Rule isCombo: ${rule.isCombo}');
    print('Rule requiredBrands: ${rule.requiredBrands}');

    final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
      promotionalRules: [rule],
      extractedProducts: extractedProducts,
    );

    print('Matches count: ${matches.length}');
    expect(matches.length, 1);
    expect(matches.first.formattedPrizeSummary, contains('50 جنيه'));

    // Test with ONLY Velveta + Diva (339 EGP), omitting Cloril:
    final onlyTwoProducts = extractedProducts.take(2).toList();
    final matches339 = PromotionalRuleMatcher.matchAllWithMultipliers(
      promotionalRules: [rule],
      extractedProducts: onlyTwoProducts,
    );
    print('Matches 339 EGP count: ${matches339.length}');
    expect(matches339.length, 1, reason: '339 EGP should qualify since 339 >= 340 - 10 (330 EGP effective min spend)');
    expect(matches339.first.formattedPrizeSummary, contains('50 جنيه'));
  });

  test(
    'Run full AiReceiptService.analyzeReceiptImage on /tmp/receipt_test.jpg',
    () async {
    final imageFile = File('/tmp/receipt_test.jpg');
    final ruleFile = File('/tmp/edco_rule.json');
    if (!imageFile.existsSync() || !ruleFile.existsSync()) return;
    final bytes = imageFile.readAsBytesSync();
    final Map<String, dynamic> ruleJson = jsonDecode(ruleFile.readAsStringSync());

    final rule = PromotionalRuleItem(
      id: ruleJson['id'] ?? 'rule_1',
      ruleTitle: ruleJson['ruleTitle'] ?? '',
      triggerProduct: ruleJson['triggerProduct'] ?? '',
      minQuantity: ruleJson['minQuantity'] ?? 1,
      conditionType: ruleJson['conditionType'] ?? 'by_spend',
      minSpend: (ruleJson['minSpend'] as num?)?.toDouble() ?? 340.0,
      maxSpend: (ruleJson['maxSpend'] as num?)?.toDouble(),
      discountTolerance: (ruleJson['discountTolerance'] as num?)?.toDouble() ?? 10.0,
      matchMode: ruleJson['matchMode'] ?? 'OR',
      requiredBrands: List<String>.from(ruleJson['requiredBrands'] ?? []),
      selectedBarcodes: List<String>.from(ruleJson['selectedBarcodes'] ?? []),
      selectedProductNames: List<String>.from(ruleJson['selectedProductNames'] ?? []),
      rewardType: ruleJson['rewardType'] ?? 'free_product',
      rewardValue: ruleJson['rewardValue'] ?? '',
      rewardAmount: (ruleJson['rewardAmount'] as num?)?.toDouble() ?? 0.0,
      allowMultipliers: ruleJson['allowMultipliers'] ?? true,
      linkedGifts: (ruleJson['linkedGifts'] as List? ?? []).map((g) {
        return LinkedGiftAllocation(
          giftId: g['giftId'] ?? '',
          giftName: g['giftName'] ?? '',
          quantity: g['quantity'] ?? 1,
          unitValue: (g['unitValue'] as num?)?.toDouble() ?? 50.0,
          giftType: g['giftType'] ?? 'voucher',
        );
      }).toList(),
    );

    final eventJson = jsonDecode(File('/Users/fathalla/.gemini/antigravity-ide/brain/b1963b23-a56a-4366-b580-e96e9f35784a/.system_generated/steps/1215/output.txt').readAsStringSync());
    final customPrompt = eventJson['fields']['customPrompt']['stringValue'];

    final aiService = AiReceiptService();
    final result = await aiService.analyzeReceiptImage(
      bytes,
      'image/jpeg',
      targetCompany: 'ادكو',
      minimumSpend: 350.0,
      retailChainName: 'أسواق فتح الله',
      allowedBranches: ['فرع عجمي ستار (الإسكندرية)'],
      isAllBranches: false,
      promotionalRules: [rule],
      allowMultipleChances: true,
      customPrompt: customPrompt,
    );

    print('=== AiReceiptService Result ===');
    print('isValid: ${result.isValid}');
    print('receiptNumber: ${result.receiptNumber}');
    print('targetCompanyTotal: ${result.targetCompanyTotal}');
    print('storeChainDetected: ${result.storeChainDetected}');
    print('branchDetected: ${result.branchDetected}');
    print('isBranchMatched: ${result.isBranchMatched}');
    print('message: ${result.message}');
    print('unfulfilledConditions: ${result.unfulfilledConditions}');
    print('extractedProducts count: ${result.extractedProducts.length}');
    for (final p in result.extractedProducts) {
      print(' - ${p.name} | qty: ${p.quantity} | price: ${p.price} | isTarget: ${p.isTargetCompany}');
    }

    final matchedRulesList = PromotionalRuleMatcher.matchAllWithMultipliers(
      result: result,
      promotionalRules: [rule],
      allowCampaignMultipliers: true,
    );
    print('matchedRulesList count: ${matchedRulesList.length}');
    if (matchedRulesList.isEmpty) {
      final unfulfilled = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
        result: result,
        promotionalRules: [rule],
      );
      print('PromotionalRuleMatcher unfulfilled: $unfulfilled');
    } else {
      print('PromotionalRuleMatcher matched prize: ${matchedRulesList.first.formattedPrizeSummary}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
