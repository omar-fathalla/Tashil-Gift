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

    test('Customer buying 1 Axe spray alongside other Unilever products (Dove) gets exactly 1x 50 EGP voucher', () {
      final extractedProducts = [
        ExtractedProductItem(name: 'دوف هاند ووش بجوز الهند 500 مل', price: 85.0, quantity: 1, isTargetCompany: true, barcode: '6221155152268'),
        ExtractedProductItem(name: 'اكس اسبراى ايس شيل 150 مل (خصم 15%)', price: 140.0, quantity: 1, isTargetCompany: true, barcode: '6221155611819'),
        ExtractedProductItem(name: 'دوف اسبراي برائحة الخيار 150مل', price: 90.0, quantity: 1, isTargetCompany: true, barcode: '6221155652553'),
      ];

      final matchResult = PromotionalRuleMatcher.matchWithMultiplier(
        extractedProducts: extractedProducts,
        promotionalRules: rules,
        allowCampaignMultipliers: true,
      );

      expect(matchResult, isNotNull);
      expect(matchResult!.rule.id, 'rule_1');
      expect(matchResult.totalTriggerQuantity, 1);
      expect(matchResult.multiplier, 1);
      expect(matchResult.totalRewardAmount, 50.0);
      expect(matchResult.formattedPrizeSummary, 'فواتشر بقيمة 50 جنيه');
      expect(matchResult.multipliedLinkedGifts.first.quantity, 1);
    });
  });

  group('Multi-Offer Basket & Cross-Condition Bundling Engine Tests', () {
    final unileverCampaignRules = [
      PromotionalRuleItem(
        id: 'rule_axe',
        ruleTitle: 'شراء 2 اسبراي أكس -> فواتشر 50 ج.م',
        triggerProduct: 'اسبراي أكس، axe',
        minQuantity: 2,
        rewardType: 'voucher',
        rewardValue: 'فواتشر بقيمة 50 جنيه',
        rewardAmount: 50.0,
        allowMultipliers: true,
        linkedGifts: [
          LinkedGiftAllocation(giftId: 'v_50', giftName: 'فواتشر مشتريات 50 ج.م', quantity: 1, unitValue: 50.0, giftType: 'voucher'),
        ],
      ),
      PromotionalRuleItem(
        id: 'rule_clear',
        ruleTitle: 'شراء 1 شامبو كلير -> كلير 90 مل هدية',
        triggerProduct: 'شامبو كلير، clear',
        minQuantity: 1,
        rewardType: 'free_product',
        rewardValue: 'كلير 90 مل هدية',
        rewardAmount: 0.0,
        allowMultipliers: true,
        linkedGifts: [
          LinkedGiftAllocation(giftId: 'p_clear', giftName: 'شامبو كلير 90 مل هدية', quantity: 1, unitValue: 0.0, giftType: 'product'),
        ],
      ),
      PromotionalRuleItem(
        id: 'rule_tresemme',
        ruleTitle: 'شراء 1 شامبو أو بلسم تريزيمي -> تريزيمي 250 مل هدية',
        triggerProduct: 'تريزيمي، tresemme',
        minQuantity: 1,
        rewardType: 'free_product',
        rewardValue: 'تريزيمي 250 مل هدية',
        rewardAmount: 0.0,
        allowMultipliers: true,
        linkedGifts: [
          LinkedGiftAllocation(giftId: 'p_tresemme', giftName: 'تريزيمي 250 مل هدية', quantity: 1, unitValue: 0.0, giftType: 'product'),
        ],
      ),
    ];

    test('Single receipt qualifying for both Axe and Clear offers produces a 2-gift Multi-Offer Bundle', () {
      final basketProducts = [
        ExtractedProductItem(name: 'اكس اسبراى بلاك 150 مل', price: 140.0, quantity: 1, isTargetCompany: true),
        ExtractedProductItem(name: 'اكس اسبراى ايس شيل 150 مل', price: 140.0, quantity: 1, isTargetCompany: true),
        ExtractedProductItem(name: 'شامبو كلير للرجال ضد القشرة 400 مل', price: 110.0, quantity: 1, isTargetCompany: true),
      ];

      final matchedRulesList = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: basketProducts,
        promotionalRules: unileverCampaignRules,
        allowCampaignMultipliers: true,
      );

      expect(matchedRulesList.length, 2);
      expect(matchedRulesList.any((r) => r.rule.id == 'rule_axe'), isTrue);
      expect(matchedRulesList.any((r) => r.rule.id == 'rule_clear'), isTrue);

      final bundle = CompositePromotionalBundle.fromMatchedRules(matchedRulesList);
      expect(bundle.matchedRules.length, 2);
      expect(bundle.combinedLinkedGifts.length, 2);
      expect(bundle.totalVoucherValue, 50.0);
      expect(bundle.compositePrizeTitle, contains('فواتشر بقيمة 50 جنيه + كلير 90 مل هدية'));
    });

    test('Single receipt qualifying for 4 Axe (2x) + 1 Clear (1x) + 1 Tresemme (1x) generates 3-offer composite bundle with multipliers', () {
      final basketProducts = [
        ExtractedProductItem(name: 'اكس اسبراى بلاك 150 مل', price: 140.0, quantity: 2, isTargetCompany: true),
        ExtractedProductItem(name: 'اكس اسبراى دارك شوكليت 150 مل', price: 140.0, quantity: 2, isTargetCompany: true),
        ExtractedProductItem(name: 'شامبو كلير ضد القشرة 400 مل', price: 110.0, quantity: 1, isTargetCompany: true),
        ExtractedProductItem(name: 'بلسم تريزيمي نعومة الكيراتين 400 مل', price: 135.0, quantity: 1, isTargetCompany: true),
      ];

      final matchedRulesList = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: basketProducts,
        promotionalRules: unileverCampaignRules,
        allowCampaignMultipliers: true,
      );

      expect(matchedRulesList.length, 3);
      final axeMatch = matchedRulesList.firstWhere((r) => r.rule.id == 'rule_axe');
      expect(axeMatch.multiplier, 2); // 4 / 2 = 2
      expect(axeMatch.totalRewardAmount, 100.0); // 50 * 2 = 100

      final bundle = CompositePromotionalBundle.fromMatchedRules(matchedRulesList);
      expect(bundle.totalVoucherValue, 100.0);
      expect(bundle.totalChances, 4); // 2 + 1 + 1 = 4
      expect(bundle.combinedLinkedGifts.length, 3);

      final axeGifts = bundle.combinedLinkedGifts.firstWhere((g) => g.giftId == 'v_50');
      expect(axeGifts.quantity, 2);
    });

    test('Greedy Tiered Waterfall: Customer buying 3 Axe sprays gets 1x (2-pcs tier @ 125 EGP) + 1x (1-pc tier @ 50 EGP) = 175 EGP total', () {
      final tieredRules = [
        PromotionalRuleItem(
          id: 'rule_axe_2',
          ruleTitle: 'عرض اسبراي أكس قطعتين -> فواتشر 125 ج.م',
          triggerProduct: 'اسبراي أكس، axe',
          minQuantity: 2,
          rewardType: 'voucher',
          rewardValue: 'فواتشر بقيمة 125 جنيه',
          rewardAmount: 125.0,
          allowMultipliers: true,
          linkedGifts: [
            LinkedGiftAllocation(giftId: 'v_50', giftName: 'فواتشر 50 جنيه', quantity: 2, unitValue: 50.0, giftType: 'voucher'),
            LinkedGiftAllocation(giftId: 'v_25', giftName: 'فواتشر 25 جنيه', quantity: 1, unitValue: 25.0, giftType: 'voucher'),
          ],
        ),
        PromotionalRuleItem(
          id: 'rule_axe_1',
          ruleTitle: 'عرض اسبراي أكس قطعة واحدة -> فواتشر 50 ج.م',
          triggerProduct: 'اسبراي أكس، axe',
          minQuantity: 1,
          rewardType: 'voucher',
          rewardValue: 'فواتشر بقيمة 50 جنيه',
          rewardAmount: 50.0,
          allowMultipliers: true,
          linkedGifts: [
            LinkedGiftAllocation(giftId: 'v_50', giftName: 'فواتشر 50 جنيه', quantity: 1, unitValue: 50.0, giftType: 'voucher'),
          ],
        ),
      ];

      final basket = [
        ExtractedProductItem(name: 'اكس اسبراى 150 مل', price: 170.0, quantity: 2, isTargetCompany: true),
        ExtractedProductItem(name: 'اكس اسبراى 150 مل', price: 170.0, quantity: 1, isTargetCompany: true),
      ];

      final matched = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: basket,
        promotionalRules: tieredRules,
        allowCampaignMultipliers: true,
      );

      // Expect both tiers to trigger: 1x rule_axe_2 (for 2 pcs) + 1x rule_axe_1 (for 1 pc)
      expect(matched.length, 2);
      expect(matched.any((r) => r.rule.id == 'rule_axe_2' && r.multiplier == 1 && r.totalRewardAmount == 125.0), isTrue);
      expect(matched.any((r) => r.rule.id == 'rule_axe_1' && r.multiplier == 1 && r.totalRewardAmount == 50.0), isTrue);

      final bundle = CompositePromotionalBundle.fromMatchedRules(matched);
      expect(bundle.totalVoucherValue, 175.0); // 125 + 50 = 175 EGP

      // Verify gifts breakdown: 3x 50 EGP + 1x 25 EGP
      final v50 = bundle.combinedLinkedGifts.firstWhere((g) => g.giftId == 'v_50');
      final v25 = bundle.combinedLinkedGifts.firstWhere((g) => g.giftId == 'v_25');
      expect(v50.quantity, 3);
      expect(v25.quantity, 1);
    });
  });
}

