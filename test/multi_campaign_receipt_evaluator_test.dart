import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/services/multi_campaign_receipt_evaluator.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('MultiCampaignReceiptEvaluator Tests', () {
    late EventModel oralCareEvent;
    late EventModel hairCareEvent;
    late EventModel deosEvent;

    setUp(() {
      // 1. Oral Care Event
      oralCareEvent = EventModel(
        id: 'event_oral_care',
        eventName: 'Back to School Oral Care Event',
        targetCompany: 'Unilever',
        companySlug: 'unilever',
        minimumSpend: 0,
        startDate: DateTime.now().subtract(const Duration(days: 5)),
        endDate: DateTime.now().add(const Duration(days: 20)),
        branchNames: ['سلسلة أسواق فتح الله', 'فتح الله - لوران', 'فتح الله - سموحة'],
        requireVoucherSerials: true,
        promotionalRules: [
          PromotionalRuleItem(
            id: 'rule_oral_1',
            ruleTitle: 'عرض معجون سيجنال أو كلوس اب',
            triggerProduct: 'معجون أسنان سيجنال، معجون أسنان كلوس اب، سيجنال، كلوس اب',
            conditionType: 'by_quantity',
            minQuantity: 2,
            rewardType: 'voucher',
            rewardValue: 'فواتشر 50 ج.م',
            rewardAmount: 50.0,
            linkedGifts: [
              LinkedGiftAllocation(
                giftId: 'gift_oral_voucher_50',
                giftName: 'فواتشر 50 ج.م',
                quantity: 1,
                giftType: 'voucher',
                unitValue: 50.0,
              ),
            ],
          ),
        ],
      );

      // 2. Hair Care Event
      hairCareEvent = EventModel(
        id: 'event_hair_care',
        eventName: 'Hair back to school',
        targetCompany: 'Unilever',
        companySlug: 'unilever',
        minimumSpend: 0,
        startDate: DateTime.now().subtract(const Duration(days: 10)),
        endDate: DateTime.now().add(const Duration(days: 15)),
        branchNames: ['سلسلة أسواق فتح الله', 'فتح الله - لوران', 'فتح الله - سموحة'],
        requireVoucherSerials: true,
        promotionalRules: [
          PromotionalRuleItem(
            id: 'rule_hair_1',
            ruleTitle: 'عرض شامبو تريزيمي أو صانسيلك قطعتين',
            triggerProduct: 'شامبو تريزيمي، شامبو صانسيلك، تريزيمي، صانسيلك',
            conditionType: 'by_quantity',
            minQuantity: 2,
            rewardType: 'voucher',
            rewardValue: 'فواتشر 100 ج.م',
            rewardAmount: 100.0,
            linkedGifts: [
              LinkedGiftAllocation(
                giftId: 'gift_hair_voucher_100',
                giftName: 'فواتشر 100 ج.م',
                quantity: 1,
                giftType: 'voucher',
                unitValue: 100.0,
              ),
            ],
          ),
        ],
      );

      // 3. Deos & Haircare Event
      deosEvent = EventModel(
        id: 'event_deos_haircare',
        eventName: 'يونيليفر ديوز - هيركير',
        targetCompany: 'Unilever',
        companySlug: 'unilever',
        minimumSpend: 0,
        startDate: DateTime.now().subtract(const Duration(days: 2)),
        endDate: DateTime.now().add(const Duration(days: 30)),
        branchNames: ['سلسلة أسواق فتح الله', 'فتح الله - لوران', 'فتح الله - سموحة'],
        requireVoucherSerials: false,
        promotionalRules: [
          PromotionalRuleItem(
            id: 'rule_deos_1',
            ruleTitle: 'عرض ريكسونا أو آكس مزيل عرق',
            triggerProduct: 'ريكسونا رول أون، ريكسونا اسبراي، ريكسونا، اكس',
            conditionType: 'by_quantity',
            minQuantity: 1,
            rewardType: 'free_product',
            rewardValue: 'مزيل عرق ريكسونا ميني هدية',
            rewardAmount: 0.0,
            linkedGifts: [
              LinkedGiftAllocation(
                giftId: 'gift_rexona_mini',
                giftName: 'مزيل عرق ريكسونا ميني هدية',
                quantity: 1,
                giftType: 'product',
                unitValue: 0.0,
              ),
            ],
          ),
        ],
      );
    });

    test('Single receipt with items from all 3 campaigns qualifies concurrently', () {
      final receiptData = AiReceiptAnalysisResult(
        isValid: true,
        receiptNumber: 'REC-99881',
        targetCompanyTotal: 480.0,
        message: 'تم تدقيق الفاتورة بنجاح',
        storeChainDetected: 'أسواق فتح الله',
        branchDetected: 'فتح الله - لوران',
        extractedProducts: [
          ExtractedProductItem(
            name: 'معجون أسنان سيجنال مكافح التسوس 100 مل',
            quantity: 2,
            price: 45.0,
            isTargetCompany: true,
          ),
          ExtractedProductItem(
            name: 'شامبو تريزيمي كيراتين سموث 400 مل',
            quantity: 2,
            price: 135.0,
            isTargetCompany: true,
          ),
          ExtractedProductItem(
            name: 'ريكسونا رول أون حماية مضاعفة 50 مل',
            quantity: 1,
            price: 65.0,
            isTargetCompany: true,
          ),
        ],
      );

      final summary = MultiCampaignReceiptEvaluator.evaluateAll(
        result: receiptData,
        campaigns: [oralCareEvent, hairCareEvent, deosEvent],
      );

      expect(summary.hasAnyQualified, isTrue);
      expect(summary.isMultiMatch, isTrue);
      expect(summary.isSingleMatch, isFalse);
      expect(summary.qualifiedCampaigns.length, equals(3));

      // 1. Check Oral Care Qualification
      final oralResult = summary.qualifiedCampaigns.firstWhere((q) => q.campaign.id == oralCareEvent.id);
      expect(oralResult.isQualified, isTrue);
      expect(oralResult.resolvedIsVoucher, isTrue);
      expect(oralResult.resolvedUnitValue, equals(50.0));
      expect(oralResult.designatedPrize, contains('50'));

      // 2. Check Hair Care Qualification
      final hairResult = summary.qualifiedCampaigns.firstWhere((q) => q.campaign.id == hairCareEvent.id);
      expect(hairResult.isQualified, isTrue);
      expect(hairResult.resolvedIsVoucher, isTrue);
      expect(hairResult.resolvedUnitValue, equals(100.0));
      expect(hairResult.designatedPrize, contains('100'));

      // 3. Check Deos Qualification
      final deosResult = summary.qualifiedCampaigns.firstWhere((q) => q.campaign.id == deosEvent.id);
      expect(deosResult.isQualified, isTrue);
      expect(deosResult.resolvedIsVoucher, isFalse);
      expect(deosResult.designatedPrize, contains('ريكسونا'));
    });

    test('Receipt with items qualifying for only 1 campaign matches single campaign', () {
      final receiptData = AiReceiptAnalysisResult(
        isValid: true,
        receiptNumber: 'REC-55441',
        targetCompanyTotal: 270.0,
        message: 'تم تدقيق الفاتورة بنجاح',
        storeChainDetected: 'أسواق فتح الله',
        branchDetected: 'فتح الله - سموحة',
        extractedProducts: [
          ExtractedProductItem(
            name: 'شامبو تريزيمي كيراتين سموث 400 مل',
            quantity: 2,
            price: 135.0,
            isTargetCompany: true,
          ),
          ExtractedProductItem(
            name: 'مناديل ورقية فاين 550 منديل',
            quantity: 3,
            price: 30.0,
            isTargetCompany: false,
          ),
        ],
      );

      final summary = MultiCampaignReceiptEvaluator.evaluateAll(
        result: receiptData,
        campaigns: [oralCareEvent, hairCareEvent, deosEvent],
      );

      expect(summary.hasAnyQualified, isTrue);
      expect(summary.isSingleMatch, isTrue);
      expect(summary.isMultiMatch, isFalse);
      expect(summary.qualifiedCampaigns.length, equals(1));
      expect(summary.qualifiedCampaigns.first.campaign.id, equals(hairCareEvent.id));
      expect(summary.unfulfilledCampaigns.length, equals(2));
    });

    test('Receipt with zero matching items returns unfulfilled report across all campaigns', () {
      final receiptData = AiReceiptAnalysisResult(
        isValid: true,
        receiptNumber: 'REC-11223',
        targetCompanyTotal: 180.0,
        message: 'تم تدقيق الفاتورة بنجاح',
        storeChainDetected: 'أسواق فتح الله',
        branchDetected: 'فتح الله - لوران',
        extractedProducts: [
          ExtractedProductItem(
            name: 'أرز الضحى فاخر 1 كجم',
            quantity: 2,
            price: 45.0,
            isTargetCompany: false,
          ),
          ExtractedProductItem(
            name: 'زيت عباد الشمس كريستال 800 مل',
            quantity: 1,
            price: 90.0,
            isTargetCompany: false,
          ),
        ],
      );

      final summary = MultiCampaignReceiptEvaluator.evaluateAll(
        result: receiptData,
        campaigns: [oralCareEvent, hairCareEvent, deosEvent],
      );

      expect(summary.hasAnyQualified, isFalse);
      expect(summary.qualifiedCampaigns.isEmpty, isTrue);
      expect(summary.unfulfilledCampaigns.length, equals(3));
      for (final disq in summary.unfulfilledCampaigns) {
        expect(disq.unfulfilledConditions, isNotEmpty);
      }
    });

    test('Campaign rejects receipt if outside active date range', () {
      final expiredEvent = EventModel(
        id: 'event_hair_expired',
        eventName: 'Hair back to school (Expired)',
        targetCompany: 'Unilever',
        companySlug: 'unilever',
        minimumSpend: 0,
        startDate: DateTime.now().subtract(const Duration(days: 30)),
        endDate: DateTime.now().subtract(const Duration(days: 2)),
        branchNames: ['سلسلة أسواق فتح الله', 'فتح الله - لوران'],
        promotionalRules: [
          PromotionalRuleItem(
            id: 'rule_hair_1',
            ruleTitle: 'عرض شامبو تريزيمي قطعتين',
            triggerProduct: 'تريزيمي',
            conditionType: 'by_quantity',
            minQuantity: 2,
            rewardType: 'voucher',
            rewardValue: 'فواتشر 100 ج.م',
            rewardAmount: 100.0,
          ),
        ],
      );

      final receiptData = AiReceiptAnalysisResult(
        isValid: true,
        receiptNumber: 'REC-33221',
        targetCompanyTotal: 270.0,
        message: 'تم تدقيق الفاتورة بنجاح',
        storeChainDetected: 'أسواق فتح الله',
        branchDetected: 'فتح الله - لوران',
        extractedProducts: [
          ExtractedProductItem(
            name: 'شامبو تريزيمي كيراتين سموث 400 مل',
            quantity: 2,
            price: 135.0,
            isTargetCompany: true,
          ),
        ],
      );

      final summary = MultiCampaignReceiptEvaluator.evaluateAll(
        result: receiptData,
        campaigns: [expiredEvent],
      );

      expect(summary.hasAnyQualified, isFalse);
      expect(summary.unfulfilledCampaigns.first.rejectionReason, contains('انتهت سريان'));
    });

    test('Campaign rejects receipt if branch is not in authorized campaign branches', () {
      final receiptData = AiReceiptAnalysisResult(
        isValid: true,
        receiptNumber: 'REC-88776',
        targetCompanyTotal: 90.0,
        message: 'تم تدقيق الفاتورة بنجاح',
        storeChainDetected: 'كارفور',
        branchDetected: 'كارفور - سيتي سنتر الإسكندرية',
        extractedProducts: [
          ExtractedProductItem(
            name: 'معجون أسنان سيجنال مكافح التسوس 100 مل',
            quantity: 2,
            price: 45.0,
            isTargetCompany: true,
          ),
        ],
      );

      final summary = MultiCampaignReceiptEvaluator.evaluateAll(
        result: receiptData,
        campaigns: [
          EventModel(
            id: 'event_oral_care_isolated',
            eventName: 'Oral Care Opening',
            targetCompany: 'Unilever',
            companySlug: 'unilever',
            minimumSpend: 0,
            startDate: DateTime.now().subtract(const Duration(days: 5)),
            endDate: DateTime.now().add(const Duration(days: 20)),
            isAllBranches: false,
            branchNames: ['سلسلة أسواق فتح الله', 'فتح الله - لوران'], // Carrefour not allowed
            promotionalRules: [
              PromotionalRuleItem(
                id: 'rule_oral_1',
                ruleTitle: 'عرض سيجنال',
                triggerProduct: 'معجون أسنان سيجنال، سيجنال',
                conditionType: 'by_quantity',
                minQuantity: 2,
                rewardType: 'voucher',
                rewardValue: 'فواتشر 50 ج.م',
                rewardAmount: 50.0,
              ),
            ],
          ),
        ],
      );

      expect(summary.hasAnyQualified, isFalse);
      expect(summary.unfulfilledCampaigns.first.rejectionReason, contains('ليس ضمن الفروع المعتمدة'));
    });
  });
}
