import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/core/services/campaign_ai_assistant_service.dart';

void main() {
  group('PromotionalRuleItem Domain Model Tests', () {
    test('PromotionalRuleItem serializes and deserializes correctly', () {
      final rule = PromotionalRuleItem(
        id: 'rule_rexona_1',
        ruleTitle: 'عرض اسبراي ريكسونا أو أكس',
        triggerProduct: 'اسبراي ريكسونا أو أكس',
        minQuantity: 1,
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات بقيمة 50 جنيه',
        rewardAmount: 50.0,
        allowMultipliers: true,
      );

      final map = rule.toMap();
      expect(map['id'], 'rule_rexona_1');
      expect(map['ruleTitle'], 'عرض اسبراي ريكسونا أو أكس');
      expect(map['minQuantity'], 1);
      expect(map['rewardType'], 'voucher');
      expect(map['rewardAmount'], 50.0);
      expect(map['allowMultipliers'], isTrue);

      final reconstructed = PromotionalRuleItem.fromMap(map);
      expect(reconstructed.id, rule.id);
      expect(reconstructed.ruleTitle, rule.ruleTitle);
      expect(reconstructed.triggerProduct, rule.triggerProduct);
      expect(reconstructed.minQuantity, 1);
      expect(reconstructed.rewardType, 'voucher');
      expect(reconstructed.rewardValue, rule.rewardValue);
      expect(reconstructed.rewardAmount, 50.0);
      expect(reconstructed.allowMultipliers, isTrue);
    });

    test('PromotionalRuleItem handles default fallbacks for missing keys', () {
      final emptyMap = <String, dynamic>{};
      final rule = PromotionalRuleItem.fromMap(emptyMap);

      expect(rule.id, isEmpty);
      expect(rule.ruleTitle, isEmpty);
      expect(rule.triggerProduct, isEmpty);
      expect(rule.minQuantity, 1);
      expect(rule.rewardType, 'free_product');
      expect(rule.rewardValue, isEmpty);
      expect(rule.rewardAmount, 0.0);
      expect(rule.allowMultipliers, isTrue);
    });
  });

  group('EventModel with Promotional Rules Tests', () {
    test('EventModel serializes promotional rules to and from Firestore map', () {
      final rules = [
        PromotionalRuleItem(
          id: 'r1',
          ruleTitle: 'عرض كلير 360 مل',
          triggerProduct: 'كلير 360 مل',
          minQuantity: 1,
          rewardType: 'free_product',
          rewardValue: 'عبوة كلير 90 مل هدية',
          rewardAmount: 0.0,
          allowMultipliers: false,
        ),
        PromotionalRuleItem(
          id: 'r2',
          ruleTitle: 'عرض تريزمي قطعتين',
          triggerProduct: 'تريزمي',
          minQuantity: 2,
          rewardType: 'free_product',
          rewardValue: 'تريزمي 250 مل مجاناً',
          rewardAmount: 0.0,
          allowMultipliers: true,
        ),
      ];

      final event = EventModel(
        id: 'event_test_fmcg',
        eventName: 'مهرجان يونيليفر الصيفي',
        targetCompany: 'يونيليفر',
        companySlug: 'unilever',
        minimumSpend: 200.0,
        promotionalIdea: 'عند شراء كلير 360 مل احصل على كلير 90 مل هدية، وعند شراء قطعتين تريزمي احصل على تريزمي 250 مل هدية.',
        aiValidationSummary: 'ملخص التحقق من فواتير يونيليفر',
        promotionalRules: rules,
      );

      final map = event.toFirestore();
      expect(map['promotionalIdea'], event.promotionalIdea);
      expect(map['aiValidationSummary'], event.aiValidationSummary);
      expect(map['promotionalRules'], isA<List>());
      expect((map['promotionalRules'] as List).length, 2);

      final restored = EventModel.fromFirestoreMap('event_test_fmcg', map);
      expect(restored.id, 'event_test_fmcg');
      expect(restored.promotionalIdea, event.promotionalIdea);
      expect(restored.aiValidationSummary, event.aiValidationSummary);
      expect(restored.promotionalRules.length, 2);
      expect(restored.promotionalRules[0].ruleTitle, 'عرض كلير 360 مل');
      expect(restored.promotionalRules[1].minQuantity, 2);
      expect(restored.promotionalRules[1].allowMultipliers, isTrue);
    });
  });

  group('CampaignAiAssistantService Analysis Result Parsing Tests', () {
    test('CampaignAiAnalysisResult parses json accurately', () {
      final json = {
        'formattedSystemPrompt': 'برومبت فحص فواتير يونيليفر المحترف',
        'aiValidationSummary': '• الشرط: شراء اسبراي ريكسونا\n• الجائزة: قسيمة 50 ج.م',
        'suggestedRequiredProducts': ['ريكسونا', 'أكس', 'كلير', 'تريزمي'],
        'rules': [
          {
            'id': 'rule_1',
            'ruleTitle': 'قسيمة مشتريات 50 ج.م',
            'triggerProduct': 'اسبراي ريكسونا أو أكس',
            'minQuantity': 1,
            'rewardType': 'voucher',
            'rewardValue': 'قسيمة 50 ج.م',
            'rewardAmount': 50.0,
            'allowMultipliers': true,
          }
        ]
      };

      final result = CampaignAiAnalysisResult.fromJson(json);
      expect(result.formattedSystemPrompt, 'برومبت فحص فواتير يونيليفر المحترف');
      expect(result.aiValidationSummary, contains('ريكسونا'));
      expect(result.suggestedRequiredProducts, ['ريكسونا', 'أكس', 'كلير', 'تريزمي']);
      expect(result.rules.length, 1);
      expect(result.rules.first.rewardAmount, 50.0);
      expect(result.rules.first.allowMultipliers, isTrue);
    });
  });
}
