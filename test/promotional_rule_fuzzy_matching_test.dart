import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Promotional Rule Fuzzy Matching & Multi-Offer Bundle Tests', () {
    // 5 standard Unilever promotional campaign rules
    final rules = [
      PromotionalRuleItem(
        id: 'rule_1',
        ruleTitle: 'عرض كلير 360 مل -> هدية كلير 90 مل',
        triggerProduct: 'كلير 360 مل',
        minQuantity: 1,
        rewardType: 'free_product',
        rewardValue: 'كلير 90 مل هدية',
        rewardAmount: 0.0,
        allowMultipliers: true,
      ),
      PromotionalRuleItem(
        id: 'rule_2',
        ruleTitle: 'عرض شرنك 2ق تريزيمي -> هدية تريزيمي 250 مل',
        triggerProduct: 'عرض شرنك 2ق تريزيمي، تريزيمي شرنك',
        minQuantity: 1,
        rewardType: 'free_product',
        rewardValue: 'تريزيمي 250 مل هدية',
        rewardAmount: 0.0,
        allowMultipliers: true,
      ),
      PromotionalRuleItem(
        id: 'rule_3',
        ruleTitle: 'عرض اسبراي ريكسونا أو أكس (قطعة واحدة) -> فواتشر 50 ج.م',
        triggerProduct: 'اسبراي ريكسونا، اسبراي أكس',
        minQuantity: 1,
        rewardType: 'voucher',
        rewardValue: 'فواتشر 50 جنيه',
        rewardAmount: 50.0,
        allowMultipliers: true,
        linkedGifts: [
          LinkedGiftAllocation(giftId: 'g_50', giftName: 'فواتشر 50', quantity: 1, unitValue: 50.0, giftType: 'voucher'),
        ],
      ),
      PromotionalRuleItem(
        id: 'rule_4',
        ruleTitle: 'عرض اسبراي ريكسونا أو أكس (قطعتين) -> فواتشر 125 ج.م',
        triggerProduct: 'اسبراي ريكسونا، اسبراي أكس',
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
      PromotionalRuleItem(
        id: 'rule_5',
        ruleTitle: 'عرض رول أون ريكسونا أو أكس (قطعتين) -> فواتشر 50 ج.م',
        triggerProduct: 'رول أون ريكسونا، رول أون أكس',
        minQuantity: 2,
        rewardType: 'voucher',
        rewardValue: 'فواتشر 50 جنيه',
        rewardAmount: 50.0,
        allowMultipliers: true,
        linkedGifts: [
          LinkedGiftAllocation(giftId: 'g_50', giftName: 'فواتشر 50', quantity: 1, unitValue: 50.0, giftType: 'voucher'),
        ],
      ),
    ];

    test('Customer Receipt from Fathalla with Axe Spray + Sunsilk + 2x Rexona Roll-on matches BOTH Rule 3 and Rule 5', () {
      // Exact products extracted from the user's receipt image:
      final extractedProducts = [
        ExtractedProductItem(
          name: 'اكس اسبراى 150مل',
          price: 270.0,
          originalPrice: 335.0,
          discountAmount: 65.0,
          quantity: 1,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'صنسيلك شامبو 1 لتر',
          price: 190.0,
          originalPrice: 233.0,
          discountAmount: 43.0,
          quantity: 1,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'ريكسونا روول اون', // Notice spelling: روول اون with double و
          price: 69.0,
          quantity: 1,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'ريكسونا روول اون', // Second line
          price: 69.0,
          quantity: 1,
          isTargetCompany: true,
        ),
      ];

      final matchedResults = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: extractedProducts,
        promotionalRules: rules,
        allowCampaignMultipliers: true,
      );

      // Verify that exactly 2 distinct promotional rules matched:
      expect(matchedResults.length, 2);

      final matchedRuleIds = matchedResults.map((r) => r.rule.id).toSet();
      expect(matchedRuleIds, contains('rule_3')); // 1x Axe Spray -> 50 EGP voucher
      expect(matchedRuleIds, contains('rule_5')); // 2x Rexona Roll-on (روول اون) -> 50 EGP voucher

      // Synthesize composite bundle
      final bundle = CompositePromotionalBundle.fromMatchedRules(matchedResults);
      expect(bundle.totalVoucherValue, 100.0);
      expect(bundle.matchedRules.length, 2);
      expect(bundle.combinedLinkedGifts.length, 1); // Consolidated into single v_50 allocation
      expect(bundle.combinedLinkedGifts.first.quantity, 2); // 2x 50 EGP = 100 EGP
      expect(bundle.compositePrizeTitle, contains('50'));
    });

    test('Receipt with phonetic spelling variations (رووول، اسبرى، تريزمي، صنسلك) matches seamlessly', () {
      final variedProducts = [
        ExtractedProductItem(
          name: 'اكس اسبرى دارك شوكلت',
          price: 140.0,
          quantity: 1,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'ريكسونا رووول اون انفيزبل',
          price: 70.0,
          quantity: 2,
          isTargetCompany: true,
        ),
      ];

      final matchedResults = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: variedProducts,
        promotionalRules: rules,
        allowCampaignMultipliers: true,
      );

      expect(matchedResults.length, 2);
      expect(matchedResults.any((r) => r.rule.id == 'rule_3'), isTrue);
      expect(matchedResults.any((r) => r.rule.id == 'rule_5'), isTrue);

      final bundle = CompositePromotionalBundle.fromMatchedRules(matchedResults);
      expect(bundle.totalVoucherValue, 100.0);
    });

    test('Multiple chances / multipliers work across multiple matched rules simultaneously', () {
      final multiItems = [
        ExtractedProductItem(
          name: 'شامبو صنسيلك لمعان ساحر 350 مل',
          price: 95.0,
          quantity: 2,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'شامبو كلير 360 مل ضد القشرة رجالي',
          price: 110.0,
          quantity: 2,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'اسبراي اكس دارك تمبتيشن 150 مل',
          price: 140.0,
          quantity: 4,
          isTargetCompany: true,
        ),
      ];

      final matchedResults = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: multiItems,
        promotionalRules: rules,
        allowCampaignMultipliers: true,
      );

      expect(matchedResults.length, 2);

      // Rule 1: Clear 360ml -> 2 bottles bought -> multiplier = 2
      final clearMatch = matchedResults.firstWhere((m) => m.rule.id == 'rule_1');
      expect(clearMatch.multiplier, 2);

      // Rule 4: Axe Spray 2 pcs -> 4 bought -> multiplier = 2 (250 EGP voucher)
      final axeMatch = matchedResults.firstWhere((m) => m.rule.id == 'rule_4');
      expect(axeMatch.multiplier, 2);
      expect(axeMatch.totalRewardAmount, 250.0);

      final bundle = CompositePromotionalBundle.fromMatchedRules(matchedResults);
      expect(bundle.totalVoucherValue, 250.0);
    });

    test('Fathalla Receipt with 3 Clear Shampoo and 3 Axe Spray yields exactly 3 Clear 90ml + 125 EGP Voucher + 50 EGP Voucher (7 gifts total, never 24)', () {
      final fthallaItems = [
        ExtractedProductItem(
          name: 'صانصيلك شا مبو 600 مل',
          price: 112.0,
          originalPrice: 132.0,
          discountAmount: 20.0,
          quantity: 1,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'صانصيلك شا مبو 600 مل',
          price: 112.0,
          originalPrice: 132.0,
          discountAmount: 20.0,
          quantity: 1,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'صانصيلك شا مبو 600 مل',
          price: 112.0,
          originalPrice: 132.0,
          discountAmount: 20.0,
          quantity: 1,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'كلير 360 مل شامبو انتعاش',
          price: 95.0,
          originalPrice: 110.0,
          discountAmount: 15.0,
          quantity: 3,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'اكس اسبراى 150 مل',
          price: 139.0,
          originalPrice: 170.0,
          discountAmount: 31.0,
          quantity: 2,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'اكس اسبراى 150 مل',
          price: 139.0,
          originalPrice: 170.0,
          discountAmount: 31.0,
          quantity: 1,
          isTargetCompany: true,
        ),
      ];

      // Total receipt spend is 1209 EGP
      final matchedResults = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: fthallaItems,
        promotionalRules: rules,
        allowCampaignMultipliers: true,
      );

      // Expect 3 matched rule results: Clear 3x, Axe 2-pcs tier 1x, Axe 1-pc tier 1x
      expect(matchedResults.length, 3);

      // Rule 1: Clear 360ml -> 3 bottles bought -> multiplier = 3
      final clearMatch = matchedResults.firstWhere((m) => m.rule.id == 'rule_1');
      expect(clearMatch.multiplier, 3);
      expect(clearMatch.rule.triggerProduct, contains('كلير 360 مل'));

      // Rule 4: Axe Spray 2 pcs -> 3 bought -> picked Rule 4 with multiplier = 1 (125 EGP voucher)
      final axeMatch2 = matchedResults.firstWhere((m) => m.rule.id == 'rule_4');
      expect(axeMatch2.multiplier, 1);
      expect(axeMatch2.totalRewardAmount, 125.0);

      // Rule 3: Axe Spray 1 pc -> remainder 1 bought -> picked Rule 3 with multiplier = 1 (50 EGP voucher)
      final axeMatch1 = matchedResults.firstWhere((m) => m.rule.id == 'rule_3');
      expect(axeMatch1.multiplier, 1);
      expect(axeMatch1.totalRewardAmount, 50.0);

      // Composite bundle aggregation
      final bundle = CompositePromotionalBundle.fromMatchedRules(matchedResults);
      expect(bundle.totalVoucherValue, 175.0); // 125 + 50 = 175 EGP
      expect(bundle.totalChances, 5); // 3 (Clear) + 1 (Axe 2pc) + 1 (Axe 1pc) = 5

      // Combined linked gifts count
      final totalItemsCount = bundle.combinedLinkedGifts.fold<int>(0, (sum, g) => sum + g.quantity);
      expect(totalItemsCount, 7); // 3 Clear + 3 Voucher 50 + 1 Voucher 25 = 7 gifts!

      final clearGift = bundle.combinedLinkedGifts.firstWhere((g) => g.giftName.contains('كلير'));
      expect(clearGift.quantity, 3);

      final v50Gift = bundle.combinedLinkedGifts.firstWhere((g) => g.giftName.contains('50'));
      expect(v50Gift.quantity, 3); // 2 from rule_4 + 1 from rule_3 = 3 units

      final v25Gift = bundle.combinedLinkedGifts.firstWhere((g) => g.giftName.contains('25'));
      expect(v25Gift.quantity, 1);
    });
  });
}

