import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/core/services/campaign_ai_assistant_service.dart';

void main() {
  group('PromotionalRuleItem Domain Model Tests', () {
    test('PromotionalRuleItem serializes and deserializes correctly with linked gift data', () {
      final rule = PromotionalRuleItem(
        id: 'rule_rexona_1',
        ruleTitle: 'عرض اسبراي ريكسونا أو أكس',
        triggerProduct: 'اسبراي ريكسونا أو أكس',
        minQuantity: 1,
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات بقيمة 50 جنيه',
        rewardAmount: 50.0,
        allowMultipliers: true,
        linkedGiftId: 'gift_voucher_50',
        linkedGiftName: 'فواتشر 50 جنيه',
      );

      final map = rule.toMap();
      expect(map['id'], 'rule_rexona_1');
      expect(map['ruleTitle'], 'عرض اسبراي ريكسونا أو أكس');
      expect(map['minQuantity'], 1);
      expect(map['rewardType'], 'voucher');
      expect(map['rewardAmount'], 50.0);
      expect(map['allowMultipliers'], isTrue);
      expect(map['linkedGiftId'], 'gift_voucher_50');
      expect(map['linkedGiftName'], 'فواتشر 50 جنيه');

      final reconstructed = PromotionalRuleItem.fromMap(map);
      expect(reconstructed.id, rule.id);
      expect(reconstructed.ruleTitle, rule.ruleTitle);
      expect(reconstructed.triggerProduct, rule.triggerProduct);
      expect(reconstructed.minQuantity, 1);
      expect(reconstructed.rewardType, 'voucher');
      expect(reconstructed.rewardValue, rule.rewardValue);
      expect(reconstructed.rewardAmount, 50.0);
      expect(reconstructed.allowMultipliers, isTrue);
      expect(reconstructed.linkedGiftId, 'gift_voucher_50');
      expect(reconstructed.linkedGiftName, 'فواتشر 50 جنيه');
    });

    test('PromotionalRuleItem.copyWith updates fields accurately', () {
      final rule = PromotionalRuleItem(
        id: 'rule_1',
        ruleTitle: 'قاعدة قديمة',
        triggerProduct: 'منتج قديم',
        rewardValue: 'هدية غير محددة',
      );

      final updated = rule.copyWith(
        linkedGiftId: 'gift_clear_90',
        linkedGiftName: 'شامبو كلير 90 مل',
        rewardType: 'free_product',
        rewardValue: 'شامبو كلير 90 مل',
      );

      expect(updated.id, 'rule_1');
      expect(updated.linkedGiftId, 'gift_clear_90');
      expect(updated.linkedGiftName, 'شامبو كلير 90 مل');
      expect(updated.rewardValue, 'شامبو كلير 90 مل');
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
      expect(rule.linkedGiftId, isNull);
      expect(rule.linkedGiftName, isNull);
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
          linkedGiftId: 'gift_clear_90',
          linkedGiftName: 'شامبو كلير 90 مل',
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
          linkedGiftId: 'gift_tresemme_250',
          linkedGiftName: 'تريزمي 250 مل',
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
      expect(restored.promotionalRules[0].linkedGiftId, 'gift_clear_90');
      expect(restored.promotionalRules[1].minQuantity, 2);
      expect(restored.promotionalRules[1].allowMultipliers, isTrue);
      expect(restored.promotionalRules[1].linkedGiftId, 'gift_tresemme_250');
    });
  });

  group('CampaignAiAssistantService Analysis Result Parsing Tests', () {
    test('CampaignAiAnalysisResult parses json accurately with linkedGiftId and linkedGiftName', () {
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
            'linkedGiftId': 'gift_v_50',
            'linkedGiftName': 'فواتشر 50 جنيه',
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
      expect(result.rules.first.linkedGiftId, 'gift_v_50');
      expect(result.rules.first.linkedGiftName, 'فواتشر 50 جنيه');
    });

    test('CampaignAiAnalysisResult parses multi-tiered spray and roll-on promotion accurately', () {
      final json = {
        'formattedSystemPrompt': 'برومبت فحص فواتير يونيليفر (اسبراي ورول أون)',
        'aiValidationSummary': '• شراء قطعة اسبراي ريكسونا أو أكس -> قسيمة 50 جنيه\n• شراء قطعتين اسبراي ريكسونا أو أكس -> قسيمة 125 جنيه\n• شراء قطعتين رول أون -> قسيمة 50 جنيه',
        'suggestedRequiredProducts': ['اسبراي ريكسونا', 'اسبراي أكس', 'ريكسونا رول اون', 'أكس رول اون'],
        'rules': [
          {
            'id': 'rule_spray_1',
            'ruleTitle': 'شراء 1 اسبراي ريكسونا/أكس',
            'triggerProduct': 'اسبراي ريكسونا، اسبراي أكس',
            'minQuantity': 1,
            'rewardType': 'voucher',
            'rewardValue': 'قسيمة مشتريات 50 جنيه',
            'rewardAmount': 50.0,
            'allowMultipliers': false,
            'linkedGiftId': 'gift_voucher_50',
            'linkedGiftName': 'فواتشر 50 جنيه',
          },
          {
            'id': 'rule_spray_2',
            'ruleTitle': 'شراء 2 اسبراي ريكسونا/أكس',
            'triggerProduct': 'اسبراي ريكسونا، اسبراي أكس',
            'minQuantity': 2,
            'rewardType': 'voucher',
            'rewardValue': 'قسيمة مشتريات 125 جنيه',
            'rewardAmount': 125.0,
            'allowMultipliers': true,
            'linkedGiftId': 'gift_voucher_125',
            'linkedGiftName': 'فواتشر 125 جنيه',
          },
          {
            'id': 'rule_rollon_2',
            'ruleTitle': 'شراء 2 ريكسونا/أكس رول اون',
            'triggerProduct': 'ريكسونا رول اون، أكس رول اون',
            'minQuantity': 2,
            'rewardType': 'voucher',
            'rewardValue': 'قسيمة مشتريات 50 جنيه',
            'rewardAmount': 50.0,
            'allowMultipliers': true,
            'linkedGiftId': 'gift_voucher_50',
            'linkedGiftName': 'فواتشر 50 جنيه',
          },
        ]
      };

      final result = CampaignAiAnalysisResult.fromJson(json);
      expect(result.rules.length, 3);
      expect(result.rules[0].rewardAmount, 50.0);
      expect(result.rules[0].linkedGiftId, 'gift_voucher_50');
      expect(result.rules[1].minQuantity, 2);
      expect(result.rules[1].rewardAmount, 125.0);
      expect(result.rules[1].linkedGiftId, 'gift_voucher_125');
      expect(result.rules[2].triggerProduct, contains('رول اون'));
      expect(result.rules[2].rewardAmount, 50.0);
      expect(result.rules[2].linkedGiftId, 'gift_voucher_50');
      expect(result.suggestedRequiredProducts.length, 4);
    });
  });
}

