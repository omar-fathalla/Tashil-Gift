import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Almarai & Dove Dynamic Tenant-Isolated Promotional Rule Matching Tests', () {
    test('Almarai 400 EGP spend rule matches receipt products dynamically (642 EGP)', () {
      final List<ExtractedProductItem> products = [
        ExtractedProductItem(
          name: 'المراعي حليب كامل الدسم 1.5لتر',
          price: 63.0,
          quantity: 9,
          isTargetCompany: true,
          barcode: '6223001878018',
        ),
        ExtractedProductItem(
          name: 'المراعي زبادي طبيعي 105جم باندل 9+3 هدية',
          price: 75.0,
          quantity: 1,
          isTargetCompany: true,
          barcode: '6223001875413',
        ),
        ExtractedProductItem(
          name: 'بامبرز بانتس بريميوم 56 حفاضة مقاس 3',
          price: 461.0,
          quantity: 1,
          isTargetCompany: false,
        ),
      ];

      final rule = PromotionalRuleItem(
        id: 'rule_1',
        ruleTitle: 'اشتري منتجات من المراعي بقيمة 400 ج.م',
        triggerProduct: 'منتجات المراعي (ألبان، عصائر، أجبان، زبادي)',
        conditionType: 'by_spend',
        minSpend: 390.0,
        discountTolerance: 5.0,
        requiredBrands: ['المراعي', 'Almarai'],
        rewardType: 'voucher',
        rewardValue: 'فرصة لعب عجلة الحظ أو كارت خربش واكسب',
        linkedGifts: [
          LinkedGiftAllocation(giftId: '1', giftName: 'خربش كارت', quantity: 2, giftType: 'product'),
          LinkedGiftAllocation(giftId: '2', giftName: 'زجاجة مياة', quantity: 1, giftType: 'product'),
          LinkedGiftAllocation(giftId: '3', giftName: 'فواتشر 100 جنيه', quantity: 1, unitValue: 100.0, giftType: 'voucher'),
          LinkedGiftAllocation(giftId: '4', giftName: 'لانش بوكس', quantity: 1, giftType: 'product'),
          LinkedGiftAllocation(giftId: '5', giftName: 'زمزمية', quantity: 1, giftType: 'product'),
        ],
      );

      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: products,
        promotionalRules: [rule],
      );

      expect(matches, isNotEmpty, reason: 'Almarai spend rule MUST match the 642 EGP of Almarai products');
      final match = matches.first;
      expect(match.rule.id, 'rule_1');
      expect(match.qualifyingSpend, 642.0);
      expect(match.multiplier, 1);
      expect(match.qualifyingProductNames.length, 2);
      expect(match.multipliedLinkedGifts.length, 5);

      final unfulfilled = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
        extractedProducts: products,
        promotionalRules: [rule],
      );
      expect(unfulfilled, isEmpty, reason: 'There should be zero unfulfilled reasons when receipt qualifies');
    });

    test('Dove Shampoo 3 pcs matches Hair Back to School rule_5 and awards 3x Clear Men 180ml', () {
      final List<ExtractedProductItem> products = [
        ExtractedProductItem(
          name: '(دوف شامبو ضد التساقط 600مل (وفر',
          price: 170.0,
          quantity: 3,
          isTargetCompany: true,
          barcode: '6221155652829',
        ),
        ExtractedProductItem(
          name: 'باونتي شيكولاته جوزهند 50جم شرنك * 3قطع',
          price: 112.0,
          quantity: 7,
          isTargetCompany: false,
        ),
      ];

      final rule = PromotionalRuleItem(
        id: 'rule_5',
        ruleTitle: 'اشتري اي منتج من منتجات دوف',
        triggerProduct: 'اشتري اي منتج من منتجات دوف (451 صنف)',
        conditionType: 'by_quantity',
        minQuantity: 1,
        allowMultipliers: true,
        requiredBrands: ['دوف'],
        rewardType: 'free_product',
        rewardValue: 'Clear Men Sh 180Ml',
      );

      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: products,
        promotionalRules: [rule],
      );

      expect(matches, isNotEmpty, reason: 'Dove shampoo MUST match rule_5');
      final match = matches.first;
      expect(match.rule.id, 'rule_5');
      expect(match.multiplier, 3, reason: '3 bottles of Dove 600ml must award 3x multiplier');
      expect(match.totalTriggerQuantity, 3);
      expect(match.formattedPrizeSummary, '3 × Clear Men Sh 180Ml');

      final unfulfilled = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
        extractedProducts: products,
        promotionalRules: [rule],
      );
      expect(unfulfilled, isEmpty);
    });

    test('Strict Cross-Tenant Rejection: Unilever receipt items (Rexona/Dove) evaluated against Almarai rules -> 0 matches', () {
      final List<ExtractedProductItem> unileverReceiptItems = [
        ExtractedProductItem(
          name: 'ريكسونا اسبراي دراي للرجال 150 مل',
          price: 140.0,
          quantity: 2,
          isTargetCompany: false, // Competitor on Almarai campaign
          barcode: '8712561845182',
        ),
        ExtractedProductItem(
          name: 'دوف صابون سائل اليدين 250 مل',
          price: 85.0,
          quantity: 2,
          isTargetCompany: false, // Competitor on Almarai campaign
          barcode: '8717163531234',
        ),
      ];

      final almaraiRule = PromotionalRuleItem(
        id: 'almarai_spend_400',
        ruleTitle: 'اشتري منتجات من المراعي بقيمة 400 ج.م',
        triggerProduct: 'منتجات المراعي (ألبان، عصائر، أجبان، زبادي)',
        conditionType: 'by_spend',
        minSpend: 390.0,
        requiredBrands: ['المراعي', 'Almarai'],
        rewardType: 'voucher',
        rewardValue: 'كارت خربش واكسب',
      );

      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: unileverReceiptItems,
        promotionalRules: [almaraiRule],
      );

      expect(matches, isEmpty, reason: 'Unilever items must NEVER match Almarai promotional rules');

      final reasons = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
        extractedProducts: unileverReceiptItems,
        promotionalRules: [almaraiRule],
      );
      expect(reasons, isNotEmpty);
      expect(reasons.first, contains('لا تحتوي على أي من المنتجات المؤهلة'));
    });

    test('Strict Cross-Tenant Rejection: Almarai dairy items evaluated against Unilever promotional rules -> 0 matches', () {
      final List<ExtractedProductItem> almaraiReceiptItems = [
        ExtractedProductItem(
          name: 'المراعي حليب كامل الدسم 1.5 لتر',
          price: 63.0,
          quantity: 4,
          isTargetCompany: false, // Competitor on Unilever campaign
          barcode: '6223001878018',
        ),
        ExtractedProductItem(
          name: 'المراعي زبادي طبيعي 105جم باندل',
          price: 75.0,
          quantity: 2,
          isTargetCompany: false, // Competitor on Unilever campaign
          barcode: '6223001875413',
        ),
      ];

      final unileverRule = PromotionalRuleItem(
        id: 'unilever_rule_3',
        ruleTitle: 'عرض اسبراي ريكسونا أو أكس (قطعة واحدة) -> فواتشر 50 ج.م',
        triggerProduct: 'اسبراي ريكسونا، اسبراي أكس، ريكسونا 150 مل، اكس 150 مل',
        minQuantity: 1,
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات 50 ج.م',
        rewardAmount: 50.0,
      );

      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: almaraiReceiptItems,
        promotionalRules: [unileverRule],
      );

      expect(matches, isEmpty, reason: 'Almarai items must NEVER match Unilever promotional rules');
    });

    test('100% Dynamic Arbitrary Brand Matching: Juhayna (جهينة) campaign with zero pre-existing hardcoding matches seamlessly', () {
      final List<ExtractedProductItem> juhaynaReceiptItems = [
        ExtractedProductItem(
          name: 'جهينة حليب كامل الدسم 1 لتر تتراباك',
          price: 48.0,
          quantity: 5,
          isTargetCompany: true,
          barcode: '6221007010012',
        ),
        ExtractedProductItem(
          name: 'جهينة رايب طبيعي 440 مل',
          price: 22.0,
          quantity: 3,
          isTargetCompany: true,
          barcode: '6221007020028',
        ),
        ExtractedProductItem(
          name: 'مولتو ميني كرواسون شيكولاتة',
          price: 25.0,
          quantity: 2,
          isTargetCompany: false, // Competitor/other item
        ),
      ];

      final juhaynaSpendRule = PromotionalRuleItem(
        id: 'juhayna_promo_300',
        ruleTitle: 'اشتري منتجات من جهينة بقيمة 300 ج.م واكسب فواتشر 50 ج.م',
        triggerProduct: 'منتجات جهينة (حليب، رايب، زبادي، عصائر)',
        conditionType: 'by_spend',
        minSpend: 300.0,
        requiredBrands: ['جهينة', 'Juhayna'],
        rewardType: 'voucher',
        rewardValue: 'فواتشر مشتريات بقيمة 50 ج.م',
        rewardAmount: 50.0,
        linkedGifts: [
          LinkedGiftAllocation(giftId: 'j_v50', giftName: 'فواتشر 50 جنيه جهينة', quantity: 1, unitValue: 50.0, giftType: 'voucher'),
        ],
      );

      // Total Juhayna spend = (48 * 5 = 240) + (22 * 3 = 66) = 306 EGP (Molto 50 EGP is excluded)
      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: juhaynaReceiptItems,
        promotionalRules: [juhaynaSpendRule],
      );

      expect(matches, isNotEmpty, reason: 'Juhayna products must match the 300 EGP spend rule dynamically');
      final match = matches.first;
      expect(match.rule.id, 'juhayna_promo_300');
      expect(match.qualifyingSpend, 306.0);
      expect(match.multiplier, 1);
      expect(match.qualifyingProductNames.length, 2);
      expect(match.qualifyingProductNames, contains('جهينة حليب كامل الدسم 1 لتر تتراباك'));
      expect(match.qualifyingProductNames, contains('جهينة رايب طبيعي 440 مل'));

      final unfulfilled = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
        extractedProducts: juhaynaReceiptItems,
        promotionalRules: [juhaynaSpendRule],
      );
      expect(unfulfilled, isEmpty);
    });
  });
}
