import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/services/multi_campaign_receipt_evaluator.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Unilever Multi-Offer Receipt Strict Isolation Tests', () {
    late EventModel oralCareCampaign;
    late EventModel deosCampaign;
    late EventModel hairCareCampaign;

    setUp(() {
      // 1. Oral Care Event
      oralCareCampaign = EventModel(
        id: 'event_oral_care',
        eventName: 'Back to School Oral Care Event',
        targetCompany: 'Unilever',
        companySlug: 'unilever',
        minimumSpend: 0,
        startDate: DateTime.now().subtract(const Duration(days: 5)),
        endDate: DateTime.now().add(const Duration(days: 20)),
        branchNames: ['فرع سموحة (الإسكندرية)'],
        promotionalRules: [
          PromotionalRuleItem(
            id: 'rule_4',
            ruleTitle: 'حزمة العناية بالفم 3 (Signal أو Closeup بقيمة 200 ج.م) -> فواتشر 75 ج.م',
            triggerProduct: 'معجون أسنان سيجنال، معجون أسنان كلوس اب، Signal Toothpaste, Closeup Toothpaste',
            conditionType: 'by_spend',
            matchMode: 'OR',
            minQuantity: 1,
            minSpend: 195.0,
            rewardType: 'voucher',
            rewardValue: 'قسيمة مشتريات بقيمة 75 ج.م',
            rewardAmount: 75.0,
            requiredBrands: ['سيجنال', 'كلوس اب'],
            selectedProductNames: [
              'اكس اسبراى 150مل + كلوس اب 25مل 2ق هدية', // Catalog promo pack contains both words
              'كلوس اب 75 ملل لظا',
              'سيجنال معجون مكاف',
            ],
            linkedGifts: [
              LinkedGiftAllocation(giftId: 'v50', giftName: 'فواتشر 50 جنيه', quantity: 1, giftType: 'voucher', unitValue: 50.0),
              LinkedGiftAllocation(giftId: 'v25', giftName: 'فواتشر 25 جنيه', quantity: 1, giftType: 'voucher', unitValue: 25.0),
            ],
          ),
          PromotionalRuleItem(
            id: 'rule_5',
            ruleTitle: 'حزمة العناية بالفم 1 (Signal + Closeup معاً بقيمة 100 ج.م) -> فواتشر 25 ج.م',
            triggerProduct: 'معجون أسنان سيجنال، معجون أسنان كلوس اب',
            conditionType: 'combo_spend',
            matchMode: 'AND',
            minQuantity: 1,
            minSpend: 95.0,
            rewardType: 'voucher',
            rewardValue: 'قسيمة مشتريات بقيمة 25 ج.م',
            rewardAmount: 25.0,
            requiredBrands: ['سيجنال', 'كلوس اب'],
            linkedGifts: [
              LinkedGiftAllocation(giftId: 'v25', giftName: 'فواتشر 25 جنيه', quantity: 1, giftType: 'voucher', unitValue: 25.0),
            ],
          ),
        ],
      );

      // 2. Deos & Hair Care Event
      deosCampaign = EventModel(
        id: 'event_deos',
        eventName: 'يونيليفر  ديوز - هيركير',
        targetCompany: 'Unilever',
        companySlug: 'unilever',
        minimumSpend: 0,
        startDate: DateTime.now().subtract(const Duration(days: 5)),
        endDate: DateTime.now().add(const Duration(days: 20)),
        branchNames: ['فرع سموحة (الإسكندرية)'],
        promotionalRules: [
          PromotionalRuleItem(
            id: 'rule_3',
            ruleTitle: 'عرض اسبراي ريكسونا أو أكس (قطعة واحدة) -> فواتشر 50 ج.م',
            triggerProduct: 'منتجات أكس و ريكسونا (383 صنف)',
            conditionType: 'by_quantity',
            matchMode: 'OR',
            minQuantity: 1,
            rewardType: 'voucher',
            rewardValue: 'قسيمة مشتريات بقيمة 50 ج.م',
            rewardAmount: 50.0,
            requiredBrands: ['أكس', 'ريكسونا'],
            linkedGifts: [
              LinkedGiftAllocation(giftId: 'v50', giftName: 'فواتشر 50 جنيه', quantity: 1, giftType: 'voucher', unitValue: 50.0),
            ],
          ),
          PromotionalRuleItem(
            id: 'rule_4',
            ruleTitle: 'عرض اسبراي ريكسونا أو أكس (قطعتين أو شرنك مزدوج) -> فواتشر 125 ج.م',
            triggerProduct: 'منتجات أكس و ريكسونا (370 صنف)',
            conditionType: 'by_quantity',
            matchMode: 'OR',
            minQuantity: 2,
            rewardType: 'voucher',
            rewardValue: 'قسيمة مشتريات بقيمة 125 ج.م',
            rewardAmount: 125.0,
            requiredBrands: ['أكس', 'ريكسونا'],
            linkedGifts: [
              LinkedGiftAllocation(giftId: 'v50', giftName: 'فواتشر 50 جنيه', quantity: 2, giftType: 'voucher', unitValue: 50.0),
              LinkedGiftAllocation(giftId: 'v25', giftName: 'فواتشر 25 جنيه', quantity: 1, giftType: 'voucher', unitValue: 25.0),
            ],
          ),
          PromotionalRuleItem(
            id: 'rule_5',
            ruleTitle: 'عرض رول أون ريكسونا أو أكس (قطعتين) -> فواتشر 50 ج.م',
            triggerProduct: 'منتجات ريكسونا و أكس (155 صنف)',
            conditionType: 'by_quantity',
            matchMode: 'OR',
            minQuantity: 2,
            rewardType: 'voucher',
            rewardValue: 'قسيمة مشتريات بقيمة 50 ج.م',
            rewardAmount: 50.0,
            requiredBrands: ['ريكسونا', 'أكس'],
            linkedGifts: [
              LinkedGiftAllocation(giftId: 'v50', giftName: 'فواتشر 50 جنيه', quantity: 1, giftType: 'voucher', unitValue: 50.0),
            ],
          ),
        ],
      );

      // 3. Sunsilk & Tresemme Hair Care Event
      hairCareCampaign = EventModel(
        id: 'event_hair_care',
        eventName: 'Hair back to school',
        targetCompany: 'Unilever',
        companySlug: 'unilever',
        minimumSpend: 0,
        startDate: DateTime.now().subtract(const Duration(days: 5)),
        endDate: DateTime.now().add(const Duration(days: 20)),
        branchNames: ['فرع سموحة (الإسكندرية)'],
        promotionalRules: [
          PromotionalRuleItem(
            id: 'rule_1',
            ruleTitle: 'Buy Tresemme 600ml SH',
            triggerProduct: 'منتجات تريزيمي و كلير و أكس و ريكسونا و سيجنال و كلوس اب و لوكس (497 صنف)',
            conditionType: 'by_quantity',
            matchMode: 'OR',
            minQuantity: 1,
            rewardType: 'free_product',
            rewardValue: 'Tresemme Cond Botanix Curl 400Ml',
            rewardAmount: 0.0,
            requiredBrands: ['تريزيمي'],
            linkedGifts: [
              LinkedGiftAllocation(giftId: 'g_tresemme', giftName: 'Tresemme Cond Botanix Curl 400Ml', quantity: 1, giftType: 'product', unitValue: 0.0),
            ],
          ),
          PromotionalRuleItem(
            id: 'rule_4',
            ruleTitle: 'Buy Sunsilk any item',
            triggerProduct: 'منتجات صنسيلك (23 صنف)',
            conditionType: 'by_quantity',
            matchMode: 'OR',
            minQuantity: 1,
            rewardType: 'free_product',
            rewardValue: 'Sunsilk e Hair Msk 220Ml',
            rewardAmount: 0.0,
            requiredBrands: ['صنسيلك'],
            linkedGifts: [
              LinkedGiftAllocation(giftId: 'g_sunsilk', giftName: 'Sunsilk e Hair Msk 220Ml', quantity: 1, giftType: 'product', unitValue: 0.0),
            ],
          ),
        ],
      );
    });

    test('Receipt correctly qualifies for exact prizes without cross-category leakage or roll-on/spray blending', () {
      final receiptResult = AiReceiptAnalysisResult(
        isValid: true,
        message: 'Valid receipt',
        receiptNumber: '269/8/211/090926',
        targetCompanyTotal: 581.5,
        storeChainDetected: 'أسواق فتح الله',
        branchDetected: 'فرع سموحة (الإسكندرية)',
        isBranchMatched: true,
        extractedProducts: [
          ExtractedProductItem(name: 'صا نسيلك شا مبو 600132.00', price: 110.0, originalPrice: 132.0, discountAmount: 22.0, quantity: 1, isTargetCompany: true),
          ExtractedProductItem(name: 'كلوس اب 75 ملل لظا', price: 63.0, quantity: 1, isTargetCompany: true),
          ExtractedProductItem(name: 'سيجنال معجون مكاف', price: 52.5, quantity: 1, isTargetCompany: true),
          ExtractedProductItem(name: 'ريكسونا روول اون', price: 69.0, quantity: 1, isTargetCompany: true),
          ExtractedProductItem(name: 'ريكسونا روول اون', price: 69.0, quantity: 1, isTargetCompany: true),
          ExtractedProductItem(name: 'اكس اسبراى 150 مل', price: 218.0, quantity: 1, isTargetCompany: true),
        ],
      );

      final summary = MultiCampaignReceiptEvaluator.evaluateAll(
        result: receiptResult,
        campaigns: [oralCareCampaign, deosCampaign, hairCareCampaign],
      );

      // 1. All 3 campaigns must qualify
      expect(summary.qualifiedCampaigns.length, 3);

      // 2. Oral Care Campaign must qualify for 25 EGP voucher (Rule 5), NOT 75 EGP (Rule 4)
      final oralEval = summary.qualifiedCampaigns.firstWhere((q) => q.campaign.id == 'event_oral_care');
      expect(oralEval.matchedRules.length, 1);
      expect(oralEval.matchedRules.first.rule.id, 'rule_5');
      expect(oralEval.totalAwardedItemsCount, 1);
      expect(oralEval.resolvedLinkedGifts.first.giftName, 'فواتشر 25 جنيه');
      expect(oralEval.resolvedLinkedGifts.first.quantity, 1);
      expect(oralEval.matchedRules.first.qualifyingReasonText, contains('استحقاق لمشتريات بقيمة'));

      // 3. Hair Care Campaign must qualify for Sunsilk Hair Mask, and NEVER Tresemme!
      final hairEval = summary.qualifiedCampaigns.firstWhere((q) => q.campaign.id == 'event_hair_care');
      expect(hairEval.matchedRules.length, 1);
      expect(hairEval.matchedRules.first.rule.id, 'rule_4');
      expect(hairEval.matchedRules.any((m) => m.rule.id == 'rule_1'), isFalse);
      expect(hairEval.totalAwardedItemsCount, 1);
      expect(hairEval.designatedPrize, 'Sunsilk e Hair Msk 220Ml');
      expect(hairEval.matchedRules.first.qualifyingReasonText, contains('صا نسيلك شا مبو'));

      // 4. Deos Campaign must qualify for 2 vouchers of 50 EGP:
      // - 1x 50 EGP for 1 Axe Spray (rule_3)
      // - 1x 50 EGP for 2 Rexona Roll-ons (rule_5)
      // Total 2 vouchers of 50 EGP (100 EGP total), NOT 3 vouchers (150 EGP)!
      final deosEval = summary.qualifiedCampaigns.firstWhere((q) => q.campaign.id == 'event_deos');
      expect(deosEval.matchedRules.length, 2);
      final rule3Match = deosEval.matchedRules.firstWhere((m) => m.rule.id == 'rule_3');
      final rule5Match = deosEval.matchedRules.firstWhere((m) => m.rule.id == 'rule_5');
      expect(rule3Match.multiplier, 1);
      expect(rule5Match.multiplier, 1);
      expect(deosEval.totalAwardedItemsCount, 2);
      expect(deosEval.resolvedLinkedGifts.fold<double>(0.0, (acc, g) => acc + g.totalMonetaryValue), 100.0);
      expect(rule3Match.qualifyingReasonText, contains('اكس اسبراى 150 مل'));
      expect(rule5Match.qualifyingReasonText, contains('ريكسونا روول اون'));
    });
  });
}
