import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';

void main() {
  test('Test Sunsilk and Dove matching in rule_5 with different requiredBrands', () {
    final sunsilkItem = ExtractedProductItem(
      name: 'صانسيلك شامبو 350',
      price: 75.0,
      quantity: 1,
      isTargetCompany: true,
    );

    final doveItem = ExtractedProductItem(
      name: 'دوف شامبو 600 ملي',
      price: 170.0,
      quantity: 1,
      isTargetCompany: true,
    );

    // Scenario 1: requiredBrands only has Sunsilk
    final ruleSunsilkOnly = PromotionalRuleItem(
      id: 'rule_5',
      ruleTitle: 'اشترى ب ١٧٠ جنيه من صانسيلك او دوف  او الاثين مع بعض  تاخد فاوتشر ب ٥٠ جنيه',
      triggerProduct: 'صانسيلك او دوف',
      minQuantity: 1,
      conditionType: 'by_spend',
      minSpend: 170.0,
      discountTolerance: 5.0,
      matchMode: 'OR',
      requiredBrands: ['صانسيلك'],
      rewardType: 'voucher',
      rewardValue: 'فواتشر 50 جنيه',
      rewardAmount: 50.0,
    );

    final check1 = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
      extractedProducts: [sunsilkItem, doveItem],
      promotionalRules: [ruleSunsilkOnly],
    );
    final matches1 = PromotionalRuleMatcher.matchAllWithMultipliers(
      extractedProducts: [sunsilkItem, doveItem],
      promotionalRules: [ruleSunsilkOnly],
    );

    // Scenario 2: requiredBrands has both Sunsilk and Dove
    final ruleBoth = PromotionalRuleItem(
      id: 'rule_5',
      ruleTitle: 'اشترى ب ١٧٠ جنيه من صانسيلك او دوف  او الاثين مع بعض  تاخد فاوتشر ب ٥٠ جنيه',
      triggerProduct: 'صانسيلك او دوف',
      minQuantity: 1,
      conditionType: 'by_spend',
      minSpend: 170.0,
      discountTolerance: 5.0,
      matchMode: 'OR',
      requiredBrands: ['صانسيلك', 'دوف'],
      rewardType: 'voucher',
      rewardValue: 'فواتشر 50 جنيه',
      rewardAmount: 50.0,
    );

    final check2 = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
      extractedProducts: [sunsilkItem, doveItem],
      promotionalRules: [ruleBoth],
    );

    final matches2 = PromotionalRuleMatcher.matchAllWithMultipliers(
      extractedProducts: [sunsilkItem, doveItem],
      promotionalRules: [ruleBoth],
    );

    // Scenario 3: The 921-item rule currently in Firestore
    final rule921 = PromotionalRuleItem(
      id: 'rule_5',
      ruleTitle: 'اشترى ب ١٧٠ جنيه من صانسيلك او دوف  او الاثين مع بعض  تاخد فاوتشر ب ٥٠ جنيه',
      triggerProduct: 'منتجات صانسيلك و شامبو و صنسيلك و دوف و اسبراي و لوكس و كريم و صابون و جود و ريكسونا150مل+25%زيادة و (ريكسونا و Rexona و ريكسوناv8 و كامى و كامي و مزيل و لايف و سيجنال و معجون (921 صنف)',
      minQuantity: 1,
      conditionType: 'by_spend',
      minSpend: 170.0,
      discountTolerance: 5.0,
      matchMode: 'OR',
      requiredBrands: [
        'صانسيلك',
        'شامبو',
        'صنسيلك',
        'دوف',
        'اسبراي',
        'لوكس',
        'كريم',
        'صابون',
        'جود',
        'ريكسونا150مل+25%زيادة',
        '(ريكسونا',
        'Rexona',
        'ريكسوناv8',
        'كامى',
        'كامي',
        'مزيل',
        'لايف',
        'سيجنال',
        'معجون',
      ],
      selectedProductNames: [
        'صانسيلك شامبو 350 ملى بزيت جوز الهند المرطب خصم25%',
        'دوف شامبو للشعر العادى 600مل',
      ],
      rewardType: 'voucher',
      rewardValue: 'فواتشر 50 جنيه',
      rewardAmount: 50.0,
    );

    final check3 = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
      extractedProducts: [sunsilkItem, doveItem],
      promotionalRules: [rule921],
    );
    final matches3 = PromotionalRuleMatcher.matchAllWithMultipliers(
      extractedProducts: [sunsilkItem, doveItem],
      promotionalRules: [rule921],
    );
    // TAG-67: a brand-scoped rule counts only its own brands. Dove is not in
    // this rule's requiredBrands, so the company flag no longer adds it; only
    // Sunsilk (75) counts, which is below 170. The live rule (scenario 4)
    // lists Dove explicitly and still earns the voucher.
    expect(matches1, isEmpty);
    expect(check1, isNotEmpty);

    expect(matches2.length, equals(1));
    expect(matches2.first.qualifyingSpend, equals(245.0));
    expect(check2, isEmpty);

    expect(matches3.length, equals(1));
    expect(matches3.first.qualifyingSpend, equals(245.0));
    expect(check3, isEmpty);

    // Scenario 4: The cleaned rule now live in Firestore
    final liveCleanedRule = PromotionalRuleItem(
      id: 'rule_5',
      ruleTitle: 'اشترى ب ١٧٠ جنيه من صانسيلك او دوف  او الاثين مع بعض  تاخد فاوتشر ب ٥٠ جنيه',
      triggerProduct: 'منتجات صانسيلك ودوف (شامبو وبلسم) (921 صنف)',
      minQuantity: 1,
      conditionType: 'by_spend',
      minSpend: 170.0,
      discountTolerance: 5.0,
      matchMode: 'OR',
      requiredBrands: ['صانسيلك', 'صنسيلك', 'دوف', 'Dove', 'Sunsilk'],
      selectedProductNames: [
        'صانسيلك شامبو 350 ملى بزيت جوز الهند المرطب خصم25%',
        'دوف شامبو للشعر العادى 600مل',
      ],
      rewardType: 'voucher',
      rewardValue: 'فواتشر 50 جنيه',
      rewardAmount: 50.0,
    );

    final check4 = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
      extractedProducts: [sunsilkItem, doveItem],
      promotionalRules: [liveCleanedRule],
    );
    final matches4 = PromotionalRuleMatcher.matchAllWithMultipliers(
      extractedProducts: [sunsilkItem, doveItem],
      promotionalRules: [liveCleanedRule],
    );
    expect(matches4.length, equals(1));
    expect(matches4.first.rule.id, equals('rule_5'));
    expect(matches4.first.qualifyingSpend, equals(245.0));
    expect(matches4.first.formattedPrizeSummary, contains('50'));
    expect(check4, isEmpty);
  });
}



