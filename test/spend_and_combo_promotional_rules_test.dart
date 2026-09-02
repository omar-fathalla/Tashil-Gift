import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Unilever Oral Care Spend-Based & Combo Promotional Rules Tests', () {
    final bundle1_100 = PromotionalRuleItem(
      id: 'rule_oral_100',
      ruleTitle: 'حزمة العناية بالفم 1 (Signal + Closeup معاً بقيمة 100 ج.م) -> فواتشر 25 ج.م',
      triggerProduct: 'معجون أسنان سيجنال، معجون أسنان كلوس اب، Signal Toothpaste, Closeup Toothpaste',
      conditionType: 'combo_spend',
      minSpend: 100.0,
      matchMode: 'AND',
      requiredBrands: ['سيجنال', 'كلوس اب'],
      selectedBarcodes: ['6221155001111', '6221155002222'],
      selectedProductNames: ['معجون أسنان سيجنال 100مل', 'معجون أسنان كلوس اب ديب أكشن 75مل'],
      rewardType: 'voucher',
      rewardValue: 'قسيمة مشتريات بقيمة 25 ج.م',
      rewardAmount: 25.0,
      allowMultipliers: true,
      linkedGifts: [
        LinkedGiftAllocation(giftId: 'gift_v25', giftName: 'قسيمة مشتريات 25 ج.م', quantity: 1, unitValue: 25.0, giftType: 'voucher'),
      ],
    );

    final bundle2_150 = PromotionalRuleItem(
      id: 'rule_oral_150',
      ruleTitle: 'حزمة العناية بالفم 2 (Signal + Closeup معاً بقيمة 150 ج.م) -> فواتشر 50 ج.م',
      triggerProduct: 'معجون أسنان سيجنال، معجون أسنان كلوس اب، Signal Toothpaste, Closeup Toothpaste',
      conditionType: 'combo_spend',
      minSpend: 150.0,
      matchMode: 'AND',
      requiredBrands: ['سيجنال', 'كلوس اب'],
      selectedBarcodes: ['6221155001111', '6221155002222'],
      selectedProductNames: ['معجون أسنان سيجنال 100مل', 'معجون أسنان كلوس اب ديب أكشن 75مل'],
      rewardType: 'voucher',
      rewardValue: 'قسيمة مشتريات بقيمة 50 ج.م',
      rewardAmount: 50.0,
      allowMultipliers: true,
      linkedGifts: [
        LinkedGiftAllocation(giftId: 'gift_v50', giftName: 'قسيمة مشتريات 50 ج.م', quantity: 1, unitValue: 50.0, giftType: 'voucher'),
      ],
    );

    final bundle3_200 = PromotionalRuleItem(
      id: 'rule_oral_200',
      ruleTitle: 'حزمة العناية بالفم 3 (Signal أو Closeup بقيمة 200 ج.م) -> فواتشر 75 ج.م',
      triggerProduct: 'معجون أسنان سيجنال، معجون أسنان كلوس اب، Signal Toothpaste, Closeup Toothpaste',
      conditionType: 'by_spend',
      minSpend: 200.0,
      matchMode: 'OR',
      requiredBrands: ['سيجنال', 'كلوس اب'],
      selectedBarcodes: ['6221155001111', '6221155002222'],
      selectedProductNames: ['معجون أسنان سيجنال 100مل', 'معجون أسنان كلوس اب ديب أكشن 75مل'],
      rewardType: 'voucher',
      rewardValue: 'قسيمة مشتريات بقيمة 75 ج.م',
      rewardAmount: 75.0,
      allowMultipliers: true,
      linkedGifts: [
        LinkedGiftAllocation(giftId: 'gift_v50', giftName: 'قسيمة مشتريات 50 ج.م', quantity: 1, unitValue: 50.0, giftType: 'voucher'),
        LinkedGiftAllocation(giftId: 'gift_v25', giftName: 'قسيمة مشتريات 25 ج.م', quantity: 1, unitValue: 25.0, giftType: 'voucher'),
      ],
    );

    final oralRules = [bundle1_100, bundle2_150, bundle3_200];

    test('Bundle 1: Signal (45 EGP) + Closeup (65 EGP) = 110 EGP -> awards 25 EGP Voucher', () {
      final List<ExtractedProductItem> receiptItems = [
        ExtractedProductItem(name: 'معجون اسنان سيجنال مكافح التسوس 100مل', quantity: 1, price: 45.0, isTargetCompany: true),
        ExtractedProductItem(name: 'معجون كلوس اب انتعاش احمر 75مل', quantity: 1, price: 65.0, isTargetCompany: true),
        ExtractedProductItem(name: 'شيبسي عائلي', quantity: 2, price: 15.0, isTargetCompany: false),
      ];

      final results = PromotionalRuleMatcher.matchAllWithMultipliers(promotionalRules: oralRules, extractedProducts: receiptItems);
      expect(results.length, 1);
      expect(results.first.rule.id, 'rule_oral_100');
      expect(results.first.multiplier, 1);
      expect(results.first.rule.rewardValue, 'قسيمة مشتريات بقيمة 25 ج.م');
      expect(results.first.multipliedLinkedGifts.length, 1);
      expect(results.first.multipliedLinkedGifts.first.unitValue, 25.0);
    });

    test('Bundle 2: Signal (80 EGP) + Closeup (80 EGP) = 160 EGP -> awards 50 EGP Voucher', () {
      final List<ExtractedProductItem> receiptItems = [
        ExtractedProductItem(name: 'سيجنال معجون اسنان 120مل', quantity: 2, price: 40.0, isTargetCompany: true),
        ExtractedProductItem(name: 'closeup toothpaste green 75ml', quantity: 1, price: 80.0, isTargetCompany: true),
      ];

      final results = PromotionalRuleMatcher.matchAllWithMultipliers(promotionalRules: oralRules, extractedProducts: receiptItems);
      expect(results.length, 1);
      expect(results.first.rule.id, 'rule_oral_150');
      expect(results.first.multiplier, 1);
      expect(results.first.rule.rewardValue, 'قسيمة مشتريات بقيمة 50 ج.م');
      expect(results.first.multipliedLinkedGifts.first.unitValue, 50.0);
    });

    test('Bundle 3: Signal alone (210 EGP) >= 200 EGP -> awards 75 EGP Voucher', () {
      final List<ExtractedProductItem> receiptItems = [
        ExtractedProductItem(name: 'معجون سيجنال وايت ناو 75 مل', quantity: 3, price: 70.0, isTargetCompany: true),
      ];

      final results = PromotionalRuleMatcher.matchAllWithMultipliers(promotionalRules: oralRules, extractedProducts: receiptItems);
      expect(results.length, 1);
      expect(results.first.rule.id, 'rule_oral_200');
      expect(results.first.multiplier, 1);
      expect(results.first.rule.rewardValue, 'قسيمة مشتريات بقيمة 75 ج.م');
      expect(results.first.multipliedLinkedGifts.length, 2); // 50 + 25
    });

    test('Combo Rejection: Signal alone (160 EGP) does NOT qualify for Bundle 2 (requires Closeup)', () {
      final List<ExtractedProductItem> receiptItems = [
        ExtractedProductItem(name: 'معجون اسنان سيجنال 100مل', quantity: 4, price: 40.0, isTargetCompany: true),
      ];

      // Does not match Bundle 2 (missing Closeup) and does not match Bundle 1 (missing Closeup),
      // and does not match Bundle 3 (160 < 200).
      final results = PromotionalRuleMatcher.matchAllWithMultipliers(promotionalRules: oralRules, extractedProducts: receiptItems);
      expect(results.isEmpty, true);

      final unfulfilled = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(promotionalRules: oralRules, extractedProducts: receiptItems);
      expect(unfulfilled.isNotEmpty, true);
      expect(unfulfilled.any((msg) => msg.contains('كلوس اب') || msg.contains('العلامات المشتركة')), true);
    });

    test('Catalog Barcode Priority: Matches barcode directly even with abbreviated POS name', () {
      final List<ExtractedProductItem> receiptItems = [
        ExtractedProductItem(name: 'معج سيج 100م', barcode: '6221155001111', quantity: 1, price: 50.0, isTargetCompany: true),
        ExtractedProductItem(name: 'معج كلوس 75م', barcode: '6221155002222', quantity: 1, price: 55.0, isTargetCompany: true),
      ];

      final results = PromotionalRuleMatcher.matchAllWithMultipliers(promotionalRules: oralRules, extractedProducts: receiptItems);
      expect(results.length, 1);
      expect(results.first.rule.id, 'rule_oral_100');
      expect(results.first.rule.rewardValue, 'قسيمة مشتريات بقيمة 25 ج.م');
    });

    test('Multi-Tier Priority: 220 EGP of Signal + Closeup awards highest tier (Bundle 3: 75 EGP)', () {
      final List<ExtractedProductItem> receiptItems = [
        ExtractedProductItem(name: 'معجون سيجنال متكامل', quantity: 2, price: 60.0, isTargetCompany: true),
        ExtractedProductItem(name: 'معجون كلوس اب دايموند', quantity: 1, price: 100.0, isTargetCompany: true),
      ];

      final results = PromotionalRuleMatcher.matchAllWithMultipliers(promotionalRules: oralRules, extractedProducts: receiptItems);
      expect(results.length, 1);
      expect(results.first.rule.id, 'rule_oral_200');
      expect(results.first.rule.rewardValue, 'قسيمة مشتريات بقيمة 75 ج.م');
    });
  });
}
