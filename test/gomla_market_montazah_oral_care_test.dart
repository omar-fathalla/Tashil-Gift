import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Gomla Market Montazah Oral Care Standalone (OR) Matching Tests', () {
    // Exact updated Back to School Oral Care Event promotional rules
    final oralCareRules = [
      PromotionalRuleItem(
        id: 'rule_4',
        ruleTitle: 'حزمة العناية بالفم 3 (Signal أو Closeup بقيمة 200 ج.م) -> فواتشر 75 ج.م',
        triggerProduct: 'معجون أسنان سيجنال، معجون أسنان كلوس اب، Signal Toothpaste, Closeup Toothpaste',
        conditionType: 'by_spend',
        minSpend: 195.0,
        discountTolerance: 5.0,
        matchMode: 'OR',
        requiredBrands: ['سيجنال', 'كلوس اب'],
        selectedProductNames: ['معجون أسنان سيجنال', 'معجون أسنان كلوس اب'],
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات بقيمة 75 ج.م',
        rewardAmount: 75.0,
        allowMultipliers: true,
        linkedGifts: [
          LinkedGiftAllocation(
            giftId: 'xQ6QzEhvtgtCazyEgl2k',
            giftName: 'فواتشر 50 جنيه',
            giftType: 'voucher',
            unitValue: 50.0,
            quantity: 1,
          ),
          LinkedGiftAllocation(
            giftId: 'GKASlOvS0KsUsdJxj35S',
            giftName: 'فواتشر 25 جنيه',
            giftType: 'voucher',
            unitValue: 25.0,
            quantity: 1,
          ),
        ],
      ),
      PromotionalRuleItem(
        id: 'rule_5',
        ruleTitle: 'حزمة العناية بالفم 1 (Signal أو Closeup بقيمة 100 ج.م) -> فواتشر 25 ج.م',
        triggerProduct: 'معجون أسنان سيجنال، معجون أسنان كلوس اب، Signal Toothpaste, Closeup Toothpaste',
        conditionType: 'by_spend',
        minSpend: 95.0,
        discountTolerance: 5.0,
        matchMode: 'OR',
        requiredBrands: ['سيجنال', 'كلوس اب'],
        selectedProductNames: ['معجون أسنان سيجنال', 'معجون أسنان كلوس اب'],
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات بقيمة 25 ج.م',
        rewardAmount: 25.0,
        allowMultipliers: true,
        linkedGifts: [
          LinkedGiftAllocation(
            giftId: 'GKASlOvS0KsUsdJxj35S',
            giftName: 'فواتشر 25 جنيه',
            giftType: 'voucher',
            unitValue: 25.0,
            quantity: 1,
          ),
        ],
      ),
      PromotionalRuleItem(
        id: 'rule_6',
        ruleTitle: 'حزمة العناية بالفم 2 (Signal أو Closeup بقيمة 150 ج.م) -> فواتشر 50 ج.م',
        triggerProduct: 'معجون أسنان سيجنال، معجون أسنان كلوس اب، Signal Toothpaste, Closeup Toothpaste',
        conditionType: 'by_spend',
        minSpend: 145.0,
        discountTolerance: 5.0,
        matchMode: 'OR',
        requiredBrands: ['سيجنال', 'كلوس اب'],
        selectedProductNames: ['معجون أسنان سيجنال', 'معجون أسنان كلوس اب'],
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات بقيمة 50 ج.م',
        rewardAmount: 50.0,
        allowMultipliers: true,
        linkedGifts: [
          LinkedGiftAllocation(
            giftId: 'xQ6QzEhvtgtCazyEgl2k',
            giftName: 'فواتشر 50 جنيه',
            giftType: 'voucher',
            unitValue: 50.0,
            quantity: 1,
          ),
        ],
      ),
    ];

    test('Customer purchasing 3x Signal only for 159 EGP qualifies for Tier 2 (50 EGP Voucher) without requiring Closeup', () {
      // Gomla Market (فرع المنتزه - الإسكندرية) receipt:
      // Store 418, PoS 9, Trans 21, Date 10/09/2026
      final products = [
        ExtractedProductItem(
          name: 'سيجنال معجون مكافح 120مل + سيجنال فحم 20مل',
          price: 53.0,
          quantity: 3,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'كلوركس مبيض ملابس 950مل',
          price: 32.0,
          quantity: 1,
          isTargetCompany: false,
        ),
      ];

      final matched = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: products,
        promotionalRules: oralCareRules,
      );

      expect(matched.length, 1);
      final result = matched.first;
      expect(result.rule.id, 'rule_6');
      expect(result.rule.ruleTitle, contains('بقيمة 150 ج.م'));
      expect(result.totalRewardAmount, 50.0);
      expect(result.multiplier, 1);
      expect(result.multipliedLinkedGifts.length, 1);
      expect(result.multipliedLinkedGifts.first.giftName, 'فواتشر 50 جنيه');
      expect(result.multipliedLinkedGifts.first.quantity, 1);

      // Verify zero unfulfilled reasons
      final unfulfilled = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
        extractedProducts: products,
        promotionalRules: oralCareRules,
      );
      expect(unfulfilled, isEmpty);
    });

    test('Customer purchasing Closeup only for 100 EGP qualifies for Tier 1 (25 EGP Voucher)', () {
      final products = [
        ExtractedProductItem(
          name: 'معجون أسنان كلوس اب أحمر حار 100مل',
          price: 50.0,
          quantity: 2,
          isTargetCompany: true,
        ),
      ];

      final matched = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: products,
        promotionalRules: oralCareRules,
      );

      expect(matched.length, 1);
      final result = matched.first;
      expect(result.rule.id, 'rule_5');
      expect(result.totalRewardAmount, 25.0);
      expect(result.multipliedLinkedGifts.first.giftName, 'فواتشر 25 جنيه');
    });

    test('Customer purchasing Signal only for 212 EGP qualifies for Tier 3 (75 EGP Voucher)', () {
      final products = [
        ExtractedProductItem(
          name: 'سيجنال معجون مكافح 120مل + سيجنال فحم 20مل',
          price: 53.0,
          quantity: 4,
          isTargetCompany: true,
        ),
      ];

      final matched = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: products,
        promotionalRules: oralCareRules,
      );

      expect(matched.length, 1);
      final result = matched.first;
      expect(result.rule.id, 'rule_4');
      expect(result.totalRewardAmount, 75.0);
      expect(result.multipliedLinkedGifts.length, 2);
      expect(result.multipliedLinkedGifts.map((g) => g.giftName), containsAll(['فواتشر 50 جنيه', 'فواتشر 25 جنيه']));
    });
  });
}
