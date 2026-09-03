import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Spend Range & Cashier Discount Tolerance Promotional Tests', () {
    final ruleTier1 = PromotionalRuleItem(
      id: 'rule_tier1',
      ruleTitle:
          'حزمة العناية بالفم 1 (Signal + Closeup: نطاق 95 إلى 139 ج.م) -> فواتشر 25 ج.م',
      triggerProduct: 'معجون أسنان سيجنال، معجون أسنان كلوس اب',
      conditionType: 'combo_spend',
      minSpend: 95.0,
      maxSpend: 139.99,
      discountTolerance: 5.0,
      matchMode: 'AND',
      requiredBrands: ['سيجنال', 'كلوس اب'],
      rewardType: 'voucher',
      rewardValue: 'قسيمة مشتريات بقيمة 25 ج.م',
      rewardAmount: 25.0,
      allowMultipliers: false,
    );

    final ruleTier2 = PromotionalRuleItem(
      id: 'rule_tier2',
      ruleTitle:
          'حزمة العناية بالفم 2 (Signal + Closeup: نطاق 140 إلى 189 ج.م) -> فواتشر 50 ج.م',
      triggerProduct: 'معجون أسنان سيجنال، معجون أسنان كلوس اب',
      conditionType: 'combo_spend',
      minSpend: 140.0,
      maxSpend: 189.99,
      discountTolerance: 5.0,
      matchMode: 'AND',
      requiredBrands: ['سيجنال', 'كلوس اب'],
      rewardType: 'voucher',
      rewardValue: 'قسيمة مشتريات بقيمة 50 ج.م',
      rewardAmount: 50.0,
      allowMultipliers: false,
    );

    final ruleTier3 = PromotionalRuleItem(
      id: 'rule_tier3',
      ruleTitle:
          'حزمة العناية بالفم 3 (Signal أو Closeup: نطاق 190+ ج.م) -> فواتشر 75 ج.م',
      triggerProduct: 'معجون أسنان سيجنال، معجون أسنان كلوس اب',
      conditionType: 'by_spend',
      minSpend: 190.0,
      discountTolerance: 10.0,
      matchMode: 'OR',
      requiredBrands: ['سيجنال', 'كلوس اب'],
      rewardType: 'voucher',
      rewardValue: 'قسيمة مشتريات بقيمة 75 ج.م',
      rewardAmount: 75.0,
      allowMultipliers: true,
    );

    final promoRules = [ruleTier1, ruleTier2, ruleTier3];

    test(
      'Receipt with 99 EGP net spend (50 EGP Closeup + 49 EGP Signal) qualifies for Tier 1 (25 EGP)',
      () {
        final products = [
          ExtractedProductItem(
            name: 'كلوس اب 100 مل اخض',
            quantity: 1,
            price: 50.0,
            originalPrice: 57.0,
            discountAmount: 7.0,
            isTargetCompany: true,
          ),
          ExtractedProductItem(
            name: 'سيجنال معجون اسنا',
            quantity: 1,
            price: 49.0,
            originalPrice: 60.0,
            discountAmount: 11.0,
            isTargetCompany: true,
          ),
        ];

        final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
          extractedProducts: products,
          promotionalRules: promoRules,
        );

        expect(matches.length, equals(1));
        expect(matches.first.rule.id, equals('rule_tier1'));
        expect(matches.first.totalRewardAmount, equals(25.0));
        expect(matches.first.multiplier, equals(1));
      },
    );

    test('Receipt with 150 EGP spend qualifies for Tier 2 (50 EGP)', () {
      final products = [
        ExtractedProductItem(
          name: 'كلوس اب 100 مل اخض',
          quantity: 2,
          price: 50.0,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'سيجنال معجون اسنا',
          quantity: 1,
          price: 50.0,
          isTargetCompany: true,
        ),
      ];

      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: products,
        promotionalRules: promoRules,
      );

      expect(matches.length, equals(1));
      expect(matches.first.rule.id, equals('rule_tier2'));
      expect(matches.first.totalRewardAmount, equals(50.0));
    });

    test(
      'Receipt with 412 EGP spend on Closeup qualifies for Tier 3 with 2 multipliers (150 EGP total)',
      () {
        final products = [
          ExtractedProductItem(
            name: 'كلوس اب 100 ملي ا',
            quantity: 2,
            price: 78.0, // 156 / 2
            isTargetCompany: true,
          ),
          ExtractedProductItem(
            name: 'كلوس اب 100 مل اخض',
            quantity: 1,
            price: 50.0,
            isTargetCompany: true,
          ),
          ExtractedProductItem(
            name: 'كلوس اب 100 مل احم',
            quantity: 1,
            price: 50.0,
            isTargetCompany: true,
          ),
          ExtractedProductItem(
            name: 'كلوس اب 100 ملي ا',
            quantity: 2,
            price: 78.0, // 156 / 2
            isTargetCompany: true,
          ),
        ];

        final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
          extractedProducts: products,
          promotionalRules: promoRules,
        );

        expect(matches.length, equals(1));
        expect(matches.first.rule.id, equals('rule_tier3'));
        // 412 / 190 = 2
        expect(matches.first.multiplier, equals(2));
        expect(matches.first.totalRewardAmount, equals(150.0));
      },
    );

    test(
      'Discount tolerance allows 99 EGP receipt on a strict 100 EGP rule with 5 EGP tolerance',
      () {
        final strictRuleWithTolerance = PromotionalRuleItem(
          id: 'rule_strict_tolerance',
          ruleTitle: 'حزمة سيجنال + كلوس اب بقيمة 100 ج.م -> فواتشر 25 ج.م',
          triggerProduct: 'معجون أسنان سيجنال، معجون أسنان كلوس اب',
          conditionType: 'combo_spend',
          minSpend: 100.0,
          discountTolerance: 5.0,
          matchMode: 'AND',
          requiredBrands: ['سيجنال', 'كلوس اب'],
          rewardType: 'voucher',
          rewardValue: 'قسيمة مشتريات بقيمة 25 ج.م',
          rewardAmount: 25.0,
        );

        final products = [
          ExtractedProductItem(
            name: 'كلوس اب 100 مل',
            quantity: 1,
            price: 50.0,
            isTargetCompany: true,
          ),
          ExtractedProductItem(
            name: 'سيجنال 100 مل',
            quantity: 1,
            price: 49.0,
            isTargetCompany: true,
          ),
        ];

        final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
          extractedProducts: products,
          promotionalRules: [strictRuleWithTolerance],
        );

        expect(matches.length, equals(1));
        expect(matches.first.rule.id, equals('rule_strict_tolerance'));
        expect(matches.first.totalRewardAmount, equals(25.0));
      },
    );
  });
}
