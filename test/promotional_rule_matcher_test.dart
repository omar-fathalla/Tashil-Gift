import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/services/campaign_ai_assistant_service.dart';

void main() {
  group('PromotionalRuleMatcher & AI Receipt Rules Test Suite', () {
    // 5 Unilever Campaign rules as specified by user
    final unileverRules = [
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
      ),
    ];

    test('Case 1: Direct matchedRuleId from AI returns exact rule', () {
      final aiResult = AiReceiptAnalysisResult(
        isValid: true,
        receiptNumber: 'REC-1001',
        targetCompanyTotal: 250.0,
        message: 'تم شراء 2 اسبراي ريكسونا',
        matchedRuleId: 'rule_4',
        matchedRuleTitle: 'عرض اسبراي ريكسونا أو أكس (قطعتين)',
        matchedRewardValue: 'فواتشر بقيمة 125 جنيه',
        matchedRewardAmount: 125.0,
        matchedRewardType: 'voucher',
      );

      final matched = PromotionalRuleMatcher.match(
        result: aiResult,
        promotionalRules: unileverRules,
      );

      expect(matched, isNotNull);
      expect(matched!.id, equals('rule_4'));
      expect(matched.rewardValue, equals('فواتشر بقيمة 125 جنيه'));
      expect(matched.rewardAmount, equals(125.0));
    });

    test('Case 2: NLP Match for 1pc Rexona Spray -> Matches Rule 3 (50 EGP)', () {
      final matched = PromotionalRuleMatcher.match(
        extractedProducts: [
          ExtractedProductItem(
            name: 'ريكسونا اسبراي دراي للرجال 150 مل',
            price: 110.0,
            quantity: 1,
            isTargetCompany: true,
          ),
        ],
        promotionalRules: unileverRules,
      );

      expect(matched, isNotNull);
      expect(matched!.id, equals('rule_3'));
      expect(matched.rewardValue, equals('فواتشر 50 جنيه'));
      expect(matched.rewardAmount, equals(50.0));
    });

    test('Case 3: NLP Match for 2pcs Rexona/Axe Spray -> Prioritizes Rule 4 (125 EGP) over Rule 3 (50 EGP)', () {
      final matched = PromotionalRuleMatcher.match(
        extractedProducts: [
          ExtractedProductItem(
            name: 'ريكسونا مزيل عرق اسبراي 150 مل',
            price: 110.0,
            quantity: 2,
            isTargetCompany: true,
          ),
        ],
        promotionalRules: unileverRules,
      );

      expect(matched, isNotNull);
      expect(matched!.id, equals('rule_4'));
      expect(matched.rewardValue, equals('فواتشر بقيمة 125 جنيه'));
      expect(matched.rewardAmount, equals(125.0));
    });

    test('Case 4: NLP Match for Tresemme Shrink -> Matches Rule 2 (Tresemme 250ml)', () {
      final matched = PromotionalRuleMatcher.match(
        extractedProducts: [
          ExtractedProductItem(
            name: 'تريزيمي عرض شرنك 2ق شامبو + بلسم',
            price: 240.0,
            quantity: 1,
            isTargetCompany: true,
          ),
        ],
        promotionalRules: unileverRules,
      );

      expect(matched, isNotNull);
      expect(matched!.id, equals('rule_2'));
      expect(matched.rewardValue, equals('تريزيمي 250 مل هدية'));
    });

    test('Case 5: NLP Match for 2pcs Roll-on -> Matches Rule 5 (50 EGP)', () {
      final matched = PromotionalRuleMatcher.match(
        extractedProducts: [
          ExtractedProductItem(
            name: 'رول اون ريكسونا انفيزبل 50 مل',
            price: 65.0,
            quantity: 2,
            isTargetCompany: true,
          ),
        ],
        promotionalRules: unileverRules,
      );

      expect(matched, isNotNull);
      expect(matched!.id, equals('rule_5'));
      expect(matched.rewardValue, equals('فواتشر 50 جنيه'));
    });

    test('Case 6: Unrelated product does NOT match and NEVER blindly returns Rule 1', () {
      final matched = PromotionalRuleMatcher.match(
        extractedProducts: [
          ExtractedProductItem(
            name: 'شاي ليبتون ناعم 250 جم',
            price: 75.0,
            quantity: 1,
            isTargetCompany: true,
          ),
        ],
        promotionalRules: unileverRules,
      );

      // Crucial: Must return null, NOT Rule 1 (Clear 90ml)!
      expect(matched, isNull);
    });

    test('Case 7: System Prompt Auto-Generator formats clear rule rules and instructions', () {
      final prompt = CampaignAiAssistantService.generateFormattedSystemPrompt(
        targetCompany: 'يونيليفر',
        minimumSpend: 0.0,
        requiredProducts: ['كلير', 'تريزيمي', 'ريكسونا', 'أكس'],
        promotionalRules: unileverRules,
      );

      expect(prompt, contains('يونيليفر'));
      expect(prompt, contains('[معرف ID: "rule_1"]'));
      expect(prompt, contains('[معرف ID: "rule_4"]'));
      expect(prompt, contains('كلير 90 مل هدية'));
      expect(prompt, contains('فواتشر بقيمة 125 جنيه'));
      expect(prompt, contains('matchedRuleId'));
    });
  });
}
