import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Unilever 5 Promotional Mechanisms & Pack Size Isolation Tests (AIR-55)', () {
    late List<PromotionalRuleItem> unileverRules;

    setUp(() {
      unileverRules = [
        // 1. اشترى قطعة كلير ٦٠٠ واحصل على قطعة كلير ٣٦٠
        PromotionalRuleItem(
          id: 'rule_clear_600',
          ruleTitle: 'اشترى قطعة كلير ٦٠٠ واحصل على قطعة كلير ٣٦٠',
          triggerProduct: 'منتجات كلير (52 صنف)',
          minQuantity: 1,
          rewardType: 'free_product',
          rewardValue: 'قطعة كلير ٣٦٠ هدية',
          rewardAmount: 0.0,
          allowMultipliers: true,
          requiredBrands: ['كلير'],
          linkedGifts: [
            LinkedGiftAllocation(
              giftId: 'g_clear_360',
              giftName: 'Clear Cool Sport 360Ml',
              quantity: 1,
              giftType: 'product',
              unitValue: 0.0,
            ),
          ],
        ),

        // 2. اشترى قطعة كلير ٥٥٠ واحصل على قطعة كلير ١٨٠
        PromotionalRuleItem(
          id: 'rule_clear_550',
          ruleTitle: 'اشترى قطعة كلير ٥٥٠ واحصل على قطعة كلير ١٨٠',
          triggerProduct: 'شامبو كلير 550 مل',
          minQuantity: 1,
          rewardType: 'free_product',
          rewardValue: 'قطعة كلير ١٨٠',
          rewardAmount: 0.0,
          allowMultipliers: true,
          requiredBrands: ['كلير'],
          linkedGifts: [
            LinkedGiftAllocation(
              giftId: 'g_clear_180',
              giftName: 'Clear Men Sh 180Ml',
              quantity: 1,
              giftType: 'product',
              unitValue: 0.0,
            ),
          ],
        ),

        // 3. اشترى قطعة شامبو تريسمى ٦٠٠ واحصل على قطعة تريسمى ٤٠٠ ملل
        PromotionalRuleItem(
          id: 'rule_tresemme_600',
          ruleTitle: 'اشترى قطعة شامبو تريسمى ٦٠٠ واحصل على قطعة تريسمى ٤٠٠ ملل',
          triggerProduct: 'منتجات تريزيمي (17 صنف)',
          minQuantity: 1,
          rewardType: 'free_product',
          rewardValue: 'قطعة تريزيمي ٤٠٠ ملل',
          rewardAmount: 0.0,
          allowMultipliers: true,
          requiredBrands: ['تريزيمي'],
          linkedGifts: [
            LinkedGiftAllocation(
              giftId: 'g_tresemme_400',
              giftName: 'Tresemme Cond Botanix Curl 400Ml',
              quantity: 1,
              giftType: 'product',
              unitValue: 0.0,
            ),
          ],
        ),

        // 4. اشترى قطعتين صانسيلك اى حجم واحصل معادا ال١٨٠مل على فاوتشر 50ج
        PromotionalRuleItem(
          id: 'rule_sunsilk_voucher_50',
          ruleTitle: 'اشترى قطعتين صانسيلك اى حجم واحصل معادا ال١٨٠مل على فاوتشر 50ج',
          triggerProduct: 'منتجات صنسيلك (412 صنف)',
          minQuantity: 2,
          rewardType: 'voucher',
          rewardValue: 'فوتشر بقيمة 50 جنيه',
          rewardAmount: 50.0,
          allowMultipliers: true,
          requiredBrands: ['صنسيلك'],
          linkedGifts: [
            LinkedGiftAllocation(
              giftId: 'v_50',
              giftName: 'فواتشر 50 جنيه',
              quantity: 1,
              giftType: 'voucher',
              unitValue: 50.0,
            ),
          ],
        ),

        // 5. اشترى قطعة دوف اى حجم واحصل على كلير ١٨٠ ملل
        PromotionalRuleItem(
          id: 'rule_dove_any',
          ruleTitle: 'اشترى قطعة دوف اى حجم واحصل على كلير ١٨٠ ملل',
          triggerProduct: 'اشتري اي منتج من منتجات دوف (451 صنف)',
          minQuantity: 1,
          rewardType: 'free_product',
          rewardValue: 'احصل على كلير ١٨٠ ملل',
          rewardAmount: 0.0,
          allowMultipliers: true,
          requiredBrands: ['دوف'],
          linkedGifts: [
            LinkedGiftAllocation(
              giftId: 'g_clear_180',
              giftName: 'Clear Men Sh 180Ml',
              quantity: 1,
              giftType: 'product',
              unitValue: 0.0,
            ),
          ],
        ),
      ];
    });

    test('Customer buying 2 bottles of Clear 550ml MUST strictly receive 2 x Clear 180ml, NEVER Clear 360ml', () {
      final receipt = AiReceiptAnalysisResult(
        isValid: true,
        message: 'Valid receipt',
        receiptNumber: '241/8/100/011026',
        targetCompanyTotal: 310.0,
        storeChainDetected: 'أسواق فتح الله',
        branchDetected: 'فرع مدينة الرحاب (القاهرة)',
        isBranchMatched: true,
        extractedProducts: [
          ExtractedProductItem(
            name: 'شامبو كلير 550مل',
            price: 155.0,
            quantity: 2,
            isTargetCompany: true,
          ),
        ],
      );

      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        result: receipt,
        promotionalRules: unileverRules,
      );

      // Must match exactly 1 rule
      expect(matches.length, 1);
      final match = matches.first;

      // Must be rule_clear_550, NOT rule_clear_600!
      expect(match.rule.id, 'rule_clear_550');
      expect(match.multiplier, 2);
      expect(match.multipliedLinkedGifts.first.giftName, 'Clear Men Sh 180Ml');
      expect(match.multipliedLinkedGifts.first.quantity, 2);
      expect(match.formattedPrizeSummary, '2 × قطعة كلير ١٨٠');
    });

    test('Customer buying 2 bottles of Clear 600ml MUST receive 2 x Clear 360ml', () {
      final receipt = AiReceiptAnalysisResult(
        isValid: true,
        message: 'Valid receipt',
        receiptNumber: '241/8/101/011026',
        targetCompanyTotal: 400.0,
        storeChainDetected: 'أسواق فتح الله',
        branchDetected: 'فرع سموحة (الإسكندرية)',
        isBranchMatched: true,
        extractedProducts: [
          ExtractedProductItem(
            name: 'كلير شامبو رجالي كول سبورت 600مل',
            price: 200.0,
            quantity: 2,
            isTargetCompany: true,
          ),
        ],
      );

      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        result: receipt,
        promotionalRules: unileverRules,
      );

      expect(matches.length, 1);
      final match = matches.first;
      expect(match.rule.id, 'rule_clear_600');
      expect(match.multiplier, 2);
      expect(match.multipliedLinkedGifts.first.giftName, 'Clear Cool Sport 360Ml');
      expect(match.multipliedLinkedGifts.first.quantity, 2);
    });

    test('Customer buying 1 Clear 600ml AND 1 Clear 550ml MUST receive BOTH 1 x Clear 360ml AND 1 x Clear 180ml', () {
      final receipt = AiReceiptAnalysisResult(
        isValid: true,
        message: 'Valid receipt',
        receiptNumber: '241/8/102/011026',
        targetCompanyTotal: 355.0,
        storeChainDetected: 'أسواق فتح الله',
        branchDetected: 'فرع سموحة (الإسكندرية)',
        isBranchMatched: true,
        extractedProducts: [
          ExtractedProductItem(
            name: 'كلير شامبو رجالي كول سبورت 600مل',
            price: 200.0,
            quantity: 1,
            isTargetCompany: true,
          ),
          ExtractedProductItem(
            name: 'شامبو كلير 550مل',
            price: 155.0,
            quantity: 1,
            isTargetCompany: true,
          ),
        ],
      );

      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        result: receipt,
        promotionalRules: unileverRules,
      );

      expect(matches.length, 2);

      final match600 = matches.firstWhere((m) => m.rule.id == 'rule_clear_600');
      final match550 = matches.firstWhere((m) => m.rule.id == 'rule_clear_550');

      expect(match600.multiplier, 1);
      expect(match600.multipliedLinkedGifts.first.giftName, 'Clear Cool Sport 360Ml');
      expect(match600.multipliedLinkedGifts.first.quantity, 1);

      expect(match550.multiplier, 1);
      expect(match550.multipliedLinkedGifts.first.giftName, 'Clear Men Sh 180Ml');
      expect(match550.multipliedLinkedGifts.first.quantity, 1);
    });

    test('Customer buying Sunsilk 350ml qualifies for 50 EGP voucher, but Sunsilk 180ml is rejected', () {
      // 1. Sunsilk 180ml must be rejected due to "معادا ال١٨٠مل"
      final receipt180 = AiReceiptAnalysisResult(
        isValid: true,
        message: 'Valid receipt',
        receiptNumber: '241/8/103/011026',
        targetCompanyTotal: 120.0,
        storeChainDetected: 'أسواق فتح الله',
        branchDetected: 'فرع سموحة (الإسكندرية)',
        isBranchMatched: true,
        extractedProducts: [
          ExtractedProductItem(
            name: 'صانسيلك شامبو 180مل',
            price: 60.0,
            quantity: 2,
            isTargetCompany: true,
          ),
        ],
      );

      final matches180 = PromotionalRuleMatcher.matchAllWithMultipliers(
        result: receipt180,
        promotionalRules: unileverRules,
      );
      expect(matches180, isEmpty, reason: 'Sunsilk 180ml is explicitly excluded by the rule');

      // 2. Sunsilk 350ml must qualify for 50 EGP voucher
      final receipt350 = AiReceiptAnalysisResult(
        isValid: true,
        message: 'Valid receipt',
        receiptNumber: '241/8/104/011026',
        targetCompanyTotal: 220.0,
        storeChainDetected: 'أسواق فتح الله',
        branchDetected: 'فرع سموحة (الإسكندرية)',
        isBranchMatched: true,
        extractedProducts: [
          ExtractedProductItem(
            name: 'صانسيلك شامبو لمعان ساحر 350 مل',
            price: 110.0,
            quantity: 2,
            isTargetCompany: true,
          ),
        ],
      );

      final matches350 = PromotionalRuleMatcher.matchAllWithMultipliers(
        result: receipt350,
        promotionalRules: unileverRules,
      );
      expect(matches350.length, 1);
      expect(matches350.first.rule.id, 'rule_sunsilk_voucher_50');
      expect(matches350.first.multiplier, 1);
      expect(matches350.first.multipliedLinkedGifts.first.giftName, 'فواتشر 50 جنيه');
    });

    test('Customer buying Tresemme 600ml gets Tresemme 400ml', () {
      final receipt = AiReceiptAnalysisResult(
        isValid: true,
        message: 'Valid receipt',
        receiptNumber: '241/8/105/011026',
        targetCompanyTotal: 260.0,
        storeChainDetected: 'أسواق فتح الله',
        branchDetected: 'فرع سموحة (الإسكندرية)',
        isBranchMatched: true,
        extractedProducts: [
          ExtractedProductItem(
            name: 'تريزيمي شامبو 600 مل',
            price: 260.0,
            quantity: 1,
            isTargetCompany: true,
          ),
        ],
      );

      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        result: receipt,
        promotionalRules: unileverRules,
      );
      expect(matches.length, 1);
      expect(matches.first.rule.id, 'rule_tresemme_600');
      expect(matches.first.multipliedLinkedGifts.first.giftName, 'Tresemme Cond Botanix Curl 400Ml');
    });

    test('Customer buying Dove any size gets Clear 180ml', () {
      final receipt = AiReceiptAnalysisResult(
        isValid: true,
        message: 'Valid receipt',
        receiptNumber: '241/8/106/011026',
        targetCompanyTotal: 90.0,
        storeChainDetected: 'أسواق فتح الله',
        branchDetected: 'فرع سموحة (الإسكندرية)',
        isBranchMatched: true,
        extractedProducts: [
          ExtractedProductItem(
            name: 'دوف صابون الجمال الأصلي 135جم',
            price: 45.0,
            quantity: 2,
            isTargetCompany: true,
          ),
        ],
      );

      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        result: receipt,
        promotionalRules: unileverRules,
      );
      expect(matches.length, 1);
      expect(matches.first.rule.id, 'rule_dove_any');
      expect(matches.first.multiplier, 2);
      expect(matches.first.multipliedLinkedGifts.first.giftName, 'Clear Men Sh 180Ml');
      expect(matches.first.multipliedLinkedGifts.first.quantity, 2);
    });
  });
}
