import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Nestle Promotional Rules Test', () {
    final nestleRules = [
      PromotionalRuleItem(
        id: 'rule_1',
        ruleTitle: 'كيت كات (الشريحة الأولى - فاوتشر 50)',
        triggerProduct: 'منتجات كيت و نستله و نستلة (29 صنف)',
        conditionType: 'by_spend',
        minSpend: 200,
        requiredBrands: ['كيت', 'نستله', 'نستلة'],
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات بقيمة 50 ج.م',
        rewardAmount: 50.0,
        allowMultipliers: true,
        linkedGifts: [
          LinkedGiftAllocation(giftId: 'g_50', giftName: 'فواتشر 50 جنيه', quantity: 1, unitValue: 50.0, giftType: 'voucher'),
        ],
      ),
      PromotionalRuleItem(
        id: 'rule_2',
        ruleTitle: 'كيت كات (الشريحة الثانية - فاوتشر 100)',
        triggerProduct: 'منتجات كيت و نستله و نستلة (29 صنف)',
        conditionType: 'by_spend',
        minSpend: 350,
        requiredBrands: ['كيت', 'نستله', 'نستلة'],
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات بقيمة 100 ج.م',
        rewardAmount: 100.0,
        allowMultipliers: true,
        linkedGifts: [
          LinkedGiftAllocation(giftId: 'g_100', giftName: 'فواتشر 100 جنيه', quantity: 1, unitValue: 100.0, giftType: 'voucher'),
        ],
      ),
      PromotionalRuleItem(
        id: 'rule_3',
        ruleTitle: 'نسكافيه جولد (فاوتشر 75)',
        triggerProduct: 'منتجات نسكافيه جولد (16 صنف)',
        conditionType: 'by_spend',
        minSpend: 500,
        requiredBrands: ['نسكافيه جولد', 'نسكافية جولد'],
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات بقيمة 75 ج.م',
        rewardAmount: 75.0,
        allowMultipliers: true,
        linkedGifts: [
          LinkedGiftAllocation(giftId: 'g_75', giftName: 'فواتشر 75 جنيه', quantity: 1, unitValue: 75.0, giftType: 'voucher'),
        ],
      ),
    ];

    test('Customer buying 4 Nescafe Gold for 1328 EGP net should match rule_3 (Nescafe Gold 75 EGP voucher x2)', () {
      final extractedProducts = [
        ExtractedProductItem(
          name: 'نسكافيه جولد بارو',
          price: 332.0,
          originalPrice: 414.0,
          quantity: 4,
          isTargetCompany: true,
          barcode: '',
        ),
      ];

      final matched = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: extractedProducts,
        promotionalRules: nestleRules,
        allowCampaignMultipliers: true,
      );

      expect(matched.length, 1);
      expect(matched.first.rule.id, 'rule_3');
      expect(matched.first.multiplier, 2);
      expect(matched.first.totalRewardAmount, 150.0);
    });

    test('Customer buying regular Nescafe (Classic / Red Mug / 3in1) must NOT match rule_3 (Nescafe Gold)', () {
      final extractedProducts = [
        ExtractedProductItem(
          name: 'نسكافيه كلاسيك 200جم',
          price: 300.0,
          originalPrice: 350.0,
          quantity: 2,
          isTargetCompany: true,
          barcode: '',
        ),
        ExtractedProductItem(
          name: 'نسكافيه 3*1 كلاسيك 24 ظرف',
          price: 150.0,
          originalPrice: 160.0,
          quantity: 1,
          isTargetCompany: true,
          barcode: '',
        ),
      ];

      final matched = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: extractedProducts,
        promotionalRules: nestleRules,
        allowCampaignMultipliers: true,
      );

      // Total spend is 750 EGP, but none are Nescafe Gold -> zero matches
      expect(matched, isEmpty);

      // Verify unfulfilled reasons accurately point out that products are not covered
      final reasons = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
        extractedProducts: extractedProducts,
        promotionalRules: nestleRules,
      );
      expect(reasons, isNotEmpty);
    });

    test('Customer buying S-26 infant formula or corn flakes must NOT match rule_3 (Nescafe Gold)', () {
      final extractedProducts = [
        ExtractedProductItem(
          name: 'اس-26 جولد بروجروس 3 900 جم',
          price: 600.0,
          originalPrice: 600.0,
          quantity: 1,
          isTargetCompany: true,
          barcode: '8886472105977',
        ),
        ExtractedProductItem(
          name: 'جولد كورن فليكس سادة 375جم',
          price: 120.0,
          originalPrice: 120.0,
          quantity: 1,
          isTargetCompany: true,
          barcode: '5900020039316',
        ),
      ];

      final matched = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: extractedProducts,
        promotionalRules: nestleRules,
        allowCampaignMultipliers: true,
      );

      expect(matched, isEmpty);
    });
  });
}
