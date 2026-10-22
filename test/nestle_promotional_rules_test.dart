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
        triggerProduct: 'منتجات نستله و نستلة و جولد و نسكافيه و نسكافية و اس26 و نسله (23 صنف)',
        conditionType: 'by_spend',
        minSpend: 500,
        requiredBrands: ['نستله', 'نستلة', 'جولد', 'نسكافيه', 'نسكافية', 'اس26', 'نسله'],
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
  });
}
