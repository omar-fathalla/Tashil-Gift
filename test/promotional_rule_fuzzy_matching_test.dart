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
      expect(bundle.combinedLinkedGifts.length, 2);
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

      final matched = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: variedProducts,
        promotionalRules: rules,
      );

      expect(matched.length, 2);
      final bundle = CompositePromotionalBundle.fromMatchedRules(matched);
      expect(bundle.totalVoucherValue, 100.0);
    });

    test('Multiple chances / multipliers work across multiple matched rules simultaneously', () {
      final highVolumeProducts = [
        ExtractedProductItem(
          name: 'اكس اسبراى 150مل',
          price: 270.0,
          quantity: 4, // 4 sprays -> Rule 4 (2 pcs for 125 EGP) x2 = 250 EGP
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'ريكسونا روول اون',
          price: 69.0,
          quantity: 4, // 4 roll-ons -> Rule 5 (2 pcs for 50 EGP) x2 = 100 EGP
          isTargetCompany: true,
        ),
      ];

      final matched = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: highVolumeProducts,
        promotionalRules: rules,
        allowCampaignMultipliers: true,
      );

      expect(matched.length, 2);
      final sprayMatch = matched.firstWhere((m) => m.rule.id == 'rule_4');
      final rollonMatch = matched.firstWhere((m) => m.rule.id == 'rule_5');

      expect(sprayMatch.multiplier, 2);
      expect(sprayMatch.totalRewardAmount, 250.0);

      expect(rollonMatch.multiplier, 2);
      expect(rollonMatch.totalRewardAmount, 100.0);

      final bundle = CompositePromotionalBundle.fromMatchedRules(matched);
      expect(bundle.totalVoucherValue, 350.0); // 250 + 100 = 350 EGP
      expect(bundle.totalChances, 4); // 2 + 2 = 4 chances
    });

    test('Fathalla Receipt with 3 Clear Shampoo and 3 Axe Spray yields exactly 3 Clear 90ml + 125 EGP Voucher (6 gifts total, never 24)', () {
      final fthallaItems = [
        ExtractedProductItem(
          name: 'شامبو كلير 360 ملي',
          price: 198.0,
          originalPrice: 230.0,
          discountAmount: 32.0,
          quantity: 2,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'شامبو كلير 360 مل',
          price: 99.0,
          originalPrice: 115.0,
          discountAmount: 16.0,
          quantity: 1,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'اكس اسبراى 150 مل',
          price: 278.0,
          originalPrice: 340.0,
          discountAmount: 62.0,
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
        ExtractedProductItem(
          name: 'فاين برستيج سحب',
          price: 495.0,
          quantity: 3,
          isTargetCompany: false,
        ),
      ];

      // Total receipt spend is 1209 EGP
      final matchedResults = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: fthallaItems,
        promotionalRules: rules,
        allowCampaignMultipliers: true,
      );

      expect(matchedResults.length, 2);

      // Rule 1: Clear 360ml -> 3 bottles bought -> multiplier = 3
      final clearMatch = matchedResults.firstWhere((m) => m.rule.id == 'rule_1');
      expect(clearMatch.multiplier, 3);
      expect(clearMatch.rule.triggerProduct, contains('كلير 360 مل'));

      // Rule 4: Axe Spray 2 pcs -> 3 bought -> picked Rule 4 with multiplier = 1 (125 EGP voucher)
      final axeMatch = matchedResults.firstWhere((m) => m.rule.id == 'rule_4');
      expect(axeMatch.multiplier, 1);
      expect(axeMatch.totalRewardAmount, 125.0);

      // Composite bundle aggregation
      final bundle = CompositePromotionalBundle.fromMatchedRules(matchedResults);
      expect(bundle.totalVoucherValue, 125.0); // Exactly 125 EGP, NOT 500 EGP!
      expect(bundle.totalChances, 4); // 3 (Clear) + 1 (Axe) = 4

      // Combined linked gifts count
      final totalItemsCount = bundle.combinedLinkedGifts.fold<int>(0, (sum, g) => sum + g.quantity);
      expect(totalItemsCount, 6); // 3 Clear + 2 Voucher 50 + 1 Voucher 25 = 6 gifts, NOT 24!

      final clearGift = bundle.combinedLinkedGifts.firstWhere((g) => g.giftName.contains('كلير'));
      expect(clearGift.quantity, 3); // 3 units, NOT 12!

      final v50Gift = bundle.combinedLinkedGifts.firstWhere((g) => g.giftName.contains('50'));
      expect(v50Gift.quantity, 2); // 2 units, NOT 8!

      final v25Gift = bundle.combinedLinkedGifts.firstWhere((g) => g.giftName.contains('25'));
      expect(v25Gift.quantity, 1); // 1 unit, NOT 4!
    });
  });
}

