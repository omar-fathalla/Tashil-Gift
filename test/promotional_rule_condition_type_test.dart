import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';

void main() {
  group('Promotional Rule Condition Type Integrity & Spend Sanitation Tests (AIR-40)', () {
    test('by_quantity rule strictly enforces isSpendBased = false even if minSpend > 0 was set', () {
      final rule = PromotionalRuleItem(
        id: 'rule_tresemme_1pc',
        ruleTitle: 'Buy Tresemme 600ml SH',
        triggerProduct: 'تريزيمي 600 مل',
        minQuantity: 1,
        conditionType: 'by_quantity',
        minSpend: 100.0, // Lingering or default spend value
        rewardType: 'free_product',
        rewardValue: 'Tresemme Cond Botanix Curl 400Ml',
      );

      expect(rule.isSpendBased, false, reason: 'by_quantity rules must NEVER be isSpendBased');
      expect(rule.hasSpendRange, false);
      expect(rule.effectiveMinSpend, 0.0);
      expect(rule.conditionSummaryText, contains('شراء كمية (1) قطعة أو أكثر من [تريزيمي 600 مل]'));
      expect(rule.conditionSummaryText, isNot(contains('100')));
      expect(rule.conditionSummaryText, isNot(contains('ج.م')));
    });

    test('PromotionalRuleItem.fromMap sanitizes by_quantity rules by zeroing minSpend and clearing ranges', () {
      final rawMap = {
        'id': 'rule_tresemme_1pc',
        'ruleTitle': 'Buy Tresemme 600ml SH',
        'triggerProduct': 'تريزيمي 600 مل',
        'minQuantity': 1,
        'conditionType': 'by_quantity',
        'minSpend': 100.0,
        'maxSpend': 150.0,
        'discountTolerance': 5.0,
        'rewardType': 'free_product',
        'rewardValue': 'Tresemme Cond Botanix Curl 400Ml',
      };

      final parsed = PromotionalRuleItem.fromMap(rawMap);
      expect(parsed.conditionType, 'by_quantity');
      expect(parsed.minSpend, 0.0, reason: 'fromMap must sanitize minSpend to 0.0 for by_quantity');
      expect(parsed.maxSpend, isNull);
      expect(parsed.discountTolerance, 0.0);
      expect(parsed.isSpendBased, false);
    });

    test('PromotionalRuleItem.toMap sanitizes by_quantity rules when serializing', () {
      final rule = PromotionalRuleItem(
        id: 'rule_tresemme_1pc',
        ruleTitle: 'Buy Tresemme 600ml SH',
        triggerProduct: 'تريزيمي 600 مل',
        minQuantity: 1,
        conditionType: 'by_quantity',
        minSpend: 100.0,
        maxSpend: 150.0,
        discountTolerance: 5.0,
        rewardType: 'free_product',
        rewardValue: 'Tresemme Cond Botanix Curl 400Ml',
      );

      final map = rule.toMap();
      expect(map['conditionType'], 'by_quantity');
      expect(map['minSpend'], 0.0, reason: 'toMap must serialize minSpend as 0.0 for by_quantity');
      expect(map.containsKey('maxSpend'), false);
      expect(map.containsKey('discountTolerance'), false);
    });

    test('by_spend and combo_spend rules preserve spend settings correctly', () {
      final spendRule = PromotionalRuleItem(
        id: 'rule_spend_100',
        ruleTitle: 'عرض إنفاق 100 ج.م',
        triggerProduct: 'منتجات تريزيمي',
        minQuantity: 1,
        conditionType: 'by_spend',
        minSpend: 100.0,
        maxSpend: 140.0,
        discountTolerance: 5.0,
        rewardType: 'voucher',
        rewardValue: 'قسيمة 25 ج.م',
      );

      expect(spendRule.isSpendBased, true);
      expect(spendRule.hasSpendRange, true);
      expect(spendRule.effectiveMinSpend, 95.0);
      expect(spendRule.conditionSummaryText, contains('100'));
      expect(spendRule.conditionSummaryText, contains('140'));
    });

    test('PromotionalRuleMatcher evaluates by_quantity strictly by piece count and ignores spend', () {
      final quantityRule = PromotionalRuleItem(
        id: 'rule_tresemme_1pc',
        ruleTitle: 'Buy Tresemme 600ml SH',
        triggerProduct: 'تريزيمي 600 مل',
        minQuantity: 1,
        conditionType: 'by_quantity',
        minSpend: 100.0, // Even if lingering
        rewardType: 'free_product',
        rewardValue: 'Tresemme Cond Botanix Curl 400Ml',
        selectedBarcodes: ['6221155009999'],
      );

      // Customer bought 1 piece for 75 EGP (less than 100 EGP)
      final receiptItems = [
        ExtractedProductItem(
          name: 'شامبو تريزيمي بوتانكس 600 مل',
          quantity: 1,
          price: 75.0,
          barcode: '6221155009999',
          isTargetCompany: true,
        ),
      ];

      final results = PromotionalRuleMatcher.matchAllWithMultipliers(
        promotionalRules: [quantityRule],
        extractedProducts: receiptItems,
      );

      expect(results.length, 1, reason: 'Customer bought 1 piece, so 1pc quantity rule MUST match regardless of spend');
      expect(results.first.rule.id, 'rule_tresemme_1pc');
      expect(results.first.multiplier, 1);
    });
  });
}
