import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/config/ai_config.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  test('AiConfig resolves valid Tier 1 paid API key', () {
    expect(AiConfig.geminiApiKey, 'REMOVED_SECRET');
    expect(AiConfig.geminiApiKey.length, greaterThan(20));
  });

  group('Promotional Rule Multiplier & Multi-Voucher Award Tests', () {
    final rules = [
      PromotionalRuleItem(
        id: 'rule_1',
        ruleTitle: 'شراء 1 اسبراي أكس أو ريكسونا -> فواتشر 50 ج.م',
        triggerProduct: 'اسبراي أكس، ريكسونا، axe, rexona',
        minQuantity: 1,
        rewardType: 'voucher',
        rewardValue: 'فواتشر بقيمة 50 جنيه',
        rewardAmount: 50.0,
        allowMultipliers: true,
        linkedGifts: [
          LinkedGiftAllocation(giftId: 'g_50', giftName: 'فواتشر 50', quantity: 1, unitValue: 50.0, giftType: 'voucher'),
        ],
      ),
      PromotionalRuleItem(
        id: 'rule_2',
        ruleTitle: 'شراء 2 اسبراي أكس أو ريكسونا -> فواتشر 125 ج.م',
        triggerProduct: 'اسبراي أكس، ريكسونا، axe, rexona',
        minQuantity: 2,
        rewardType: 'voucher',
        rewardValue: 'فواتشر بقيمة 125 جنيه',
        rewardAmount: 125.0,
        allowMultipliers: true,
        linkedGifts: [
          LinkedGiftAllocation(giftId: 'g_50', giftName: 'فواتشر 50', quantity: 2, unitValue: 50.0, giftType: 'voucher'),
          LinkedGiftAllocation(giftId: 'g_25', giftName: 'فواتشر 25', quantity: 1, unitValue: 25.0, giftType: 'voucher'),
        ],
      ),
    ];

    test('Customer buying 4 Axe sprays gets Multiplier x2 and 250 EGP in total vouchers', () {
      final extractedProducts = [
        ExtractedProductItem(name: 'اكس اسبراى ايس شيل 150 مل', price: 140.0, quantity: 1, isTargetCompany: true, barcode: '6221155611819'),
        ExtractedProductItem(name: 'اكس اسبراى بلاك 150 مل', price: 140.0, quantity: 1, isTargetCompany: true, barcode: '6221155611772'),
        ExtractedProductItem(name: 'اكس اسبراى بلاك نايت 150 مل', price: 140.0, quantity: 1, isTargetCompany: true, barcode: '6221155122926'),
        ExtractedProductItem(name: 'اكس اسبراى دارك شوكليت 150 مل', price: 140.0, quantity: 1, isTargetCompany: true, barcode: '6221155611789'),
      ];

      final matchResult = PromotionalRuleMatcher.matchWithMultiplier(
        extractedProducts: extractedProducts,
        promotionalRules: rules,
        allowCampaignMultipliers: true,
      );

      expect(matchResult, isNotNull);
      expect(matchResult!.rule.id, 'rule_2');
      expect(matchResult.totalTriggerQuantity, 4);
      expect(matchResult.multiplier, 2);
      expect(matchResult.totalRewardAmount, 250.0);
      expect(matchResult.formattedPrizeSummary, contains('2 × فواتشر بقيمة 125 جنيه (إجمالي 250 جنيه)'));

      // Check multiplied linked gifts: 2x 50 EGP + 1x 25 EGP becomes 4x 50 EGP + 2x 25 EGP
      expect(matchResult.multipliedLinkedGifts.length, 2);
      final g50 = matchResult.multipliedLinkedGifts.firstWhere((g) => g.giftId == 'g_50');
      final g25 = matchResult.multipliedLinkedGifts.firstWhere((g) => g.giftId == 'g_25');
      expect(g50.quantity, 4); // 2 * 2
      expect(g25.quantity, 2); // 1 * 2
    });

    test('Customer buying 2 Axe sprays gets 1x 125 EGP voucher', () {
      final extractedProducts = [
        ExtractedProductItem(name: 'اكس اسبراى ايس شيل 150 مل', price: 140.0, quantity: 1, isTargetCompany: true, barcode: '6221155611819'),
        ExtractedProductItem(name: 'اكس اسبراى بلاك 150 مل', price: 140.0, quantity: 1, isTargetCompany: true, barcode: '6221155611772'),
      ];

      final matchResult = PromotionalRuleMatcher.matchWithMultiplier(
        extractedProducts: extractedProducts,
        promotionalRules: rules,
        allowCampaignMultipliers: true,
      );

      expect(matchResult, isNotNull);
      expect(matchResult!.multiplier, 1);
      expect(matchResult.totalRewardAmount, 125.0);
      expect(matchResult.formattedPrizeSummary, 'فواتشر بقيمة 125 جنيه');
    });
  });
}
