import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';

void main() {
  group('Sunsilk POS Receipt & Orthographic Normalization Tests', () {
    final sunsilkRule = PromotionalRuleItem(
      id: 'rule_4',
      ruleTitle: 'Buy Sunsilk any item',
      triggerProduct: 'منتجات صنسيلك (23 صنف - 19 باركود)',
      requiredBrands: ['صنسيلك'],
      minQuantity: 1,
      rewardType: 'free_product',
      rewardValue: 'Sunsilk e Hair Msk 220Ml',
      selectedProductNames: [
        'صنسيلك شامبو 350 ملى التالف خصم20%',
        'صنسيلك شامبو 600 مل',
        'صنسيلك شامبو 1 لتر',
      ],
      linkedGifts: [
        LinkedGiftAllocation(
          giftId: 'ZwKQbb0KuypXZG4Kxunf',
          giftName: 'Sunsilk e Hair Msk 220Ml',
          giftType: 'product',
          quantity: 1,
        )
      ],
    );

    test('Case 1: صانسيلك شامبو 600132.00 matches Sunsilk rule and produces Sunsilk hair mask', () {
      final item = ExtractedProductItem(
        name: 'صانسيلك شامبو 600132.00',
        price: 110.0,
        quantity: 1,
        isTargetCompany: true,
      );

      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: [item],
        promotionalRules: [sunsilkRule],
        allowCampaignMultipliers: true,
      );

      expect(matches.length, equals(1));
      expect(matches.first.rule.id, equals('rule_4'));
      expect(matches.first.rule.rewardValue, equals('Sunsilk e Hair Msk 220Ml'));
      expect(matches.first.multiplier, equals(1));
      expect(matches.first.multipliedLinkedGifts.first.giftName, equals('Sunsilk e Hair Msk 220Ml'));
      expect(matches.first.multipliedLinkedGifts.first.quantity, equals(1));
    });

    test('Case 2: Standard صانسيلك شامبو 600 with Alef matches flawlessly', () {
      final item = ExtractedProductItem(
        name: 'صانسيلك شامبو 600',
        price: 110.0,
        quantity: 1,
        isTargetCompany: true,
      );

      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: [item],
        promotionalRules: [sunsilkRule],
        allowCampaignMultipliers: true,
      );

      expect(matches.length, equals(1));
      expect(matches.first.rule.id, equals('rule_4'));
      expect(matches.first.rule.rewardValue, equals('Sunsilk e Hair Msk 220Ml'));
    });

    test('Case 3: Full receipt with Sunsilk matches Sunsilk Rule 4', () {
      final products = [
        ExtractedProductItem(name: 'صانسيلك شامبو 600132.00', price: 110.0, quantity: 1, isTargetCompany: true),
        ExtractedProductItem(name: 'كلوس اب 75 ملل نظا', price: 63.0, quantity: 1, isTargetCompany: true),
        ExtractedProductItem(name: 'سيجنال معجون مكاف', price: 52.5, quantity: 1, isTargetCompany: true),
        ExtractedProductItem(name: 'ريكسونا روول اون', price: 69.0, quantity: 1, isTargetCompany: true),
        ExtractedProductItem(name: 'ريكسونا روول اون', price: 69.0, quantity: 1, isTargetCompany: true),
        ExtractedProductItem(name: 'اكس اسبراي 150 مل', price: 218.0, quantity: 1, isTargetCompany: true),
      ];

      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: products,
        promotionalRules: [sunsilkRule],
        allowCampaignMultipliers: true,
      );

      expect(matches.length, equals(1));
      expect(matches.first.rule.id, equals('rule_4'));
      expect(matches.first.rule.rewardValue, equals('Sunsilk e Hair Msk 220Ml'));
    });
  });
}
