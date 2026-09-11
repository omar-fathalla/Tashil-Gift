import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/services/multi_campaign_receipt_evaluator.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Unilever Recheck & Auto-Qualification Multi-Campaign Tests', () {
    late EventModel oralCareCampaign;
    late EventModel hairBackToSchoolCampaign;

    setUp(() {
      // 1. Oral Care Campaign (Signal & Closeup)
      oralCareCampaign = EventModel(
        id: 'event_oral_care_123',
        eventName: 'Back to School Oral Care Event',
        targetCompany: 'Unilever',
        companySlug: 'unilever',
        minimumSpend: 0,
        startDate: DateTime.now().subtract(const Duration(days: 10)),
        endDate: DateTime.now().add(const Duration(days: 30)),
        branchNames: ['جملة ماركت - المنتزه (الإسكندرية)', 'فرع سموحة'],
        promotionalRules: [
          PromotionalRuleItem(
            id: 'rule_oral_1',
            ruleTitle: 'شراء معجون أسنان سيجنال أو كلوس اب بقيمة 200 ج.م -> فواتشر 75 ج.م',
            triggerProduct: 'معجون أسنان سيجنال، معجون أسنان كلوس اب',
            conditionType: 'by_spend',
            matchMode: 'OR',
            minQuantity: 1,
            minSpend: 195.0,
            rewardType: 'voucher',
            rewardValue: 'قسيمة مشتريات بقيمة 75 ج.م',
            rewardAmount: 75.0,
            requiredBrands: ['سيجنال', 'كلوس اب'],
            selectedProductNames: ['معجون أسنان سيجنال', 'معجون أسنان كلوس اب'],
            linkedGifts: [
              LinkedGiftAllocation(giftId: 'v75', giftName: 'فواتشر 75 جنيه', quantity: 1, giftType: 'voucher', unitValue: 75.0),
            ],
          ),
        ],
      );

      // 2. Hair Back to School Campaign (Tresemme & Dove)
      hairBackToSchoolCampaign = EventModel(
        id: 'event_hair_care_456',
        eventName: 'Hair back to school',
        targetCompany: 'Unilever',
        companySlug: 'unilever',
        minimumSpend: 0,
        startDate: DateTime.now().subtract(const Duration(days: 10)),
        endDate: DateTime.now().add(const Duration(days: 30)),
        branchNames: ['جملة ماركت - المنتزه (الإسكندرية)', 'فرع سموحة'],
        promotionalRules: [
          PromotionalRuleItem(
            id: 'rule_tresemme_1',
            ruleTitle: 'شراء عبوة شامبو تريزيمي 600 مل -> بلسم تريزيمي هدية مجانية',
            triggerProduct: 'تريزيمي شامبو، Tresemme Shampoo',
            conditionType: 'by_quantity',
            matchMode: 'OR',
            minQuantity: 1,
            minSpend: 0.0,
            rewardType: 'gift',
            rewardValue: 'Tresemme Cond Botanix Curl 400Ml',
            rewardAmount: 1.0,
            requiredBrands: ['تريزيمي', 'Tresemme'],
            selectedProductNames: [
              'تريزيمي شامبو كيراتين وزيت الارجان 600 مل',
              'تريزيمي شامبو كيراتين وزيت الارجان 600مل',
              'Tresemme Shampoo Keratin 600ml',
            ],
            linkedGifts: [
              LinkedGiftAllocation(
                giftId: 'gift_tresemme_cond',
                giftName: 'Tresemme Cond Botanix Curl 400Ml',
                quantity: 1,
                giftType: 'physical',
                unitValue: 200.0,
              ),
            ],
          ),
        ],
      );
    });

    test('Receipt #23/16/418/110926 fails Oral Care but qualifies for Hair back to school upon Multi-Campaign Recheck', () {
      // Products extracted from user receipt #23/16/418/110926:
      final extractedProducts = [
        ExtractedProductItem(
          name: 'تريزيمي شامبو كيراتين وزيت الارجان 600مل',
          price: 210.0,
          quantity: 1,
          isTargetCompany: true,
          barcode: '6221155211712',
        ),
        ExtractedProductItem(
          name: 'لوكس هاند ووش زهرة الاوركيد وزيت اللوز 50',
          price: 88.0,
          quantity: 1,
          isTargetCompany: true,
          barcode: '6221155611666',
        ),
        ExtractedProductItem(
          name: 'لوكس صابون بالاوركيد الاسود 165جم',
          price: 152.0,
          quantity: 1,
          isTargetCompany: true,
          barcode: '6221155200716',
        ),
        ExtractedProductItem(
          name: 'بامبرز بريميوم حفاضات أطفال',
          price: 477.0,
          quantity: 2,
          isTargetCompany: false,
          barcode: '8006540726341',
        ),
      ];

      final analysisResult = AiReceiptAnalysisResult(
        isValid: true,
        receiptNumber: '23/16/418/110926',
        targetCompanyTotal: 450.0,
        receiptDate: '11/09/2026',
        extractedProducts: extractedProducts,
        storeChainDetected: 'جملة ماركت',
        branchDetected: 'جملة ماركت - المنتزه',
        isBranchMatched: true,
        message: 'Receipt items analyzed successfully',
        unfulfilledConditions: const [],
        durationMs: 400,
        durationSeconds: 0.4,
        kpiRating: 'A+',
        kpiColorHex: '#4CAF50',
        chancesEarned: 1,
        matchedRuleId: '',
        matchedRuleIds: const [],
        matchedRuleTitle: '',
        matchedRewardValue: '',
        matchedRewardAmount: 0.0,
        matchedRewardType: '',
        isHandwritten: false,
      );

      // Single Campaign evaluation against Oral Care (Old behavior):
      final singleOralEval = MultiCampaignReceiptEvaluator.evaluateCampaign(
        result: analysisResult,
        campaign: oralCareCampaign,
      );
      expect(singleOralEval.isQualified, isFalse, reason: 'Oral care must reject because receipt has no Signal/Closeup');
      expect(singleOralEval.rejectionReason, isNotEmpty);

      // Unified Multi-Campaign Recheck (New behavior):
      final orderedCampaigns = [oralCareCampaign, hairBackToSchoolCampaign];
      final summary = MultiCampaignReceiptEvaluator.evaluateAll(
        result: analysisResult,
        campaigns: orderedCampaigns,
      );

      expect(summary.qualifiedCampaigns.isNotEmpty, isTrue, reason: 'Must qualify across Unilever active campaigns');
      expect(summary.qualifiedCampaigns.length, equals(1));

      final winningEval = summary.qualifiedCampaigns.first;
      expect(winningEval.campaign.id, equals('event_hair_care_456'));
      expect(winningEval.campaign.eventName, equals('Hair back to school'));
      expect(winningEval.designatedPrize, equals('Tresemme Cond Botanix Curl 400Ml'));
      expect(winningEval.resolvedLinkedGifts.length, equals(1));
      expect(winningEval.resolvedLinkedGifts.first.giftName, equals('Tresemme Cond Botanix Curl 400Ml'));
      expect(winningEval.resolvedLinkedGifts.first.quantity, equals(1));

      // Simulate Firestore document update payload:
      final firestoreUpdatePayload = {
        'is_valid': true,
        'status': 'accepted',
        'campaignId': winningEval.campaign.id,
        'campaign_name': winningEval.campaign.eventName,
        'eventName': winningEval.campaign.eventName,
        'claimed_gifts': winningEval.resolvedLinkedGifts.map((g) => {
          'giftId': g.giftId,
          'giftName': g.giftName,
          'quantity': g.quantity,
          'unitValue': g.unitValue,
          'isVoucher': g.isVoucher,
        }).toList(),
        'unfulfilled_conditions': <String>[],
      };

      expect(firestoreUpdatePayload['status'], equals('accepted'));
      expect(firestoreUpdatePayload['is_valid'], isTrue);
      expect(firestoreUpdatePayload['campaignId'], equals('event_hair_care_456'));
      expect((firestoreUpdatePayload['unfulfilled_conditions'] as List).isEmpty, isTrue);

      // Verify UI filtering condition in InvoicesLogScreen:
      // When _statusFilter == 'rejected':
      // if (_statusFilter == 'rejected' && isValid) return false; (invoice disappears from rejected list)
      final bool isExplicitlyValid = firestoreUpdatePayload['is_valid'] == true || firestoreUpdatePayload['status'] == 'accepted';
      final bool isExplicitlyRejected = firestoreUpdatePayload['is_valid'] == false || firestoreUpdatePayload['status'] == 'rejected';
      final bool isValid = isExplicitlyValid || (!isExplicitlyRejected);

      expect(isValid, isTrue);
      // In rejected tab:
      final showInRejected = !isValid;
      expect(showInRejected, isFalse, reason: 'Invoice MUST disappear from the rejected tab');
      // In accepted tab:
      final showInAccepted = isValid;
      expect(showInAccepted, isTrue, reason: 'Invoice MUST appear in the accepted tab');
    });
  });
}
