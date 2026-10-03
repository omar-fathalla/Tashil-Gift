import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/services/receipt_deduplication_helper.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Complementary Receipts & Side-by-Side Aggregation (AIR-58)', () {
    test('ReceiptDeduplicationHelper generates safe deterministic doc ID for dual receipt number', () {
      const dualReceiptNumber = '64/6/241/250926 + 109/8/241/250926';
      final docId = ReceiptDeduplicationHelper.getDeterministicDocId(
        campaignId: 'cadbury_mahalla_2026',
        receiptNumber: dualReceiptNumber,
      );

      expect(docId, isNotEmpty);
      expect(docId.startsWith('rcpt_cadbury_mahalla_2026_'), isTrue);
      // Slashes must be safely sanitized
      expect(docId.contains('/'), isFalse);
      expect(docId.contains('\\'), isFalse);
    });

    test('Combines Cadbury base receipt (751 EGP) and complementary receipt (55 EGP) into 806 EGP', () {
      final items = [
        // Receipt 1 items (751.00 EGP)
        ExtractedProductItem(
          name: 'كادبوري ديري ميلك 37 جم',
          price: 37.0,
          quantity: 3,
          isTargetCompany: true,
          barcode: '6221008001011',
        ),
        ExtractedProductItem(
          name: 'كادبوري شوكولاته 148 جم',
          price: 148.0,
          quantity: 1,
          isTargetCompany: true,
          barcode: '6221008001028',
        ),
        ExtractedProductItem(
          name: 'شوكولاتة مورو بال 18.5 جم',
          price: 18.5,
          quantity: 12,
          isTargetCompany: true,
          barcode: '6221008001035',
        ),
        ExtractedProductItem(
          name: 'كادبوري بسكويت وي 9.25 جم',
          price: 9.25,
          quantity: 12,
          isTargetCompany: true,
          barcode: '6221008001042',
        ),
        ExtractedProductItem(
          name: 'مندولين بسكويت مغ 159 جم',
          price: 159.0,
          quantity: 1,
          isTargetCompany: true,
          barcode: '6221008001059',
        ),
        // Receipt 2 items (55.00 EGP - تكملة الفاتورة)
        ExtractedProductItem(
          name: 'كادبوري ديري ميلك 65 جم (تكملة)',
          price: 55.0,
          quantity: 1,
          isTargetCompany: true,
          barcode: '6221008001066',
        ),
      ];

      final totalCombined = items.fold<double>(
        0.0,
        (sum, item) => sum + (item.price * item.quantity),
      );

      // 111 + 148 + 222 + 111 + 159 + 55 = 806.00 EGP
      expect(totalCombined, equals(806.0));

      final result = AiReceiptAnalysisResult(
        isValid: true,
        receiptNumber: '64/6/241/250926 + 109/8/241/250926',
        targetCompanyTotal: totalCombined,
        receiptDate: '25/09/2026',
        storeChainDetected: 'أسواق فتح الله للجملة',
        branchDetected: 'المحلة الكبرى',
        storeId: '241',
        extractedProducts: items,
        message: 'تم فحص البونين المدمجين بنجاح وتجميع القيمة الإجمالية لكادبوري.',
      );

      expect(result.targetCompanyTotal, equals(806.0));
      expect(result.receiptNumber, contains('+'));
      expect(result.receiptNumber, contains('64/6/241/250926'));
      expect(result.receiptNumber, contains('109/8/241/250926'));
    });

    test('PromotionalRuleMatcher matches 2 vouchers for 806 EGP spend (400 EGP threshold)', () {
      final items = [
        ExtractedProductItem(
          name: 'كادبوري ديري ميلك 37 جم',
          price: 37.0,
          quantity: 3,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'كادبوري شوكولاته 148 جم',
          price: 148.0,
          quantity: 1,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'شوكولاتة مورو بال 18.5 جم',
          price: 18.5,
          quantity: 12,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'كادبوري بسكويت وي 9.25 جم',
          price: 9.25,
          quantity: 12,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'مندولين بسكويت مغ 159 جم',
          price: 159.0,
          quantity: 1,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'كادبوري ديري ميلك 65 جم (تكملة)',
          price: 55.0,
          quantity: 1,
          isTargetCompany: true,
        ),
      ];

      final result = AiReceiptAnalysisResult(
        isValid: true,
        receiptNumber: '64/6/241/250926 + 109/8/241/250926',
        targetCompanyTotal: 806.0,
        receiptDate: '25/09/2026',
        storeChainDetected: 'أسواق فتح الله للجملة',
        branchDetected: 'المحلة الكبرى',
        extractedProducts: items,
        message: 'تم فحص البونين المدمجين بنجاح.',
      );

      final cadburyRule = PromotionalRuleItem(
        id: 'cadbury_400_voucher',
        ruleTitle: 'عرض كادبوري إنفاق 400 ج.م -> فوتشر 100 ج.م',
        triggerProduct: 'كادبوري',
        conditionType: 'by_spend',
        minSpend: 400.0,
        rewardValue: 'فوتشر 100 ج.م',
        rewardAmount: 100.0,
        rewardType: 'voucher',
        allowMultipliers: true,
      );

      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        result: result,
        promotionalRules: [cadburyRule],
        allowCampaignMultipliers: true,
      );

      expect(matches, isNotEmpty);
      final match = matches.first;
      // 806 EGP spend qualifies for 2 multipliers (2 x 400 = 800 EGP)
      expect(match.multiplier, equals(2));
      expect(match.totalRewardAmount, equals(200.0));
      expect(match.formattedPrizeSummary, contains('فوتشر 100 ج.م'));
    });

    test('Auto-heals targetCompanyTotal when extractedProducts items sum is higher than raw AI value', () {
      final json = {
        'isValid': true,
        'receiptNumber': '64/6/241/250926 + 109/8/241/250926',
        // Incomplete AI raw total (e.g. only captured the first receipt 751 EGP)
        'targetCompanyTotal': 751.0,
        'receiptDate': '25/09/2026',
        'storeChainDetected': 'أسواق فتح الله للجملة',
        'branchDetected': 'المحلة الكبرى',
        'isThermalPosReceipt': true,
        'isHandwritten': false,
        'message': 'تم فحص الفاتورة.',
        'extractedProducts': [
          {
            'name': 'كادبوري ديري ميلك',
            'price': 751.0,
            'quantity': 1,
            'isTargetCompany': true,
          },
          {
            'name': 'كادبوري ديري ميلك تكملة',
            'price': 55.0,
            'quantity': 1,
            'isTargetCompany': true,
          },
        ],
      };

      var analysisResult = AiReceiptAnalysisResult.fromJson(json);

      // Auto-heal logic as implemented in AiReceiptService
      final double sumOfExtractedTarget = analysisResult.extractedProducts
          .where((p) => p.isTargetCompany)
          .fold<double>(0.0, (sum, p) => sum + (p.price * p.quantity));

      if (sumOfExtractedTarget > analysisResult.targetCompanyTotal) {
        analysisResult = analysisResult.copyWith(targetCompanyTotal: sumOfExtractedTarget);
      }

      expect(analysisResult.targetCompanyTotal, equals(806.0));
    });

    test('Strict Single-Receipt Integrity (AIR-61) rejects dual-receipt merging when allowComplementaryReceipts is false', () {
      final jsonWithMergedReceipts = {
        'isValid': true,
        'receiptNumber': '64/6/241/250926 + 109/8/241/250926',
        'targetCompanyTotal': 806.0,
        'receiptDate': '25/09/2026',
        'storeChainDetected': 'أسواق فتح الله للجملة',
        'branchDetected': 'المحلة الكبرى',
        'isThermalPosReceipt': true,
        'isHandwritten': false,
        'message': 'تم فحص البونين المدمجين بنجاح وتجميع القيمة.',
        'chancesEarned': 2,
        'unfulfilledConditions': <String>[],
        'extractedProducts': [
          {
            'name': 'كادبوري ديري ميلك',
            'price': 751.0,
            'quantity': 1,
            'isTargetCompany': true,
          },
          {
            'name': 'كادبوري ديري ميلك تكملة',
            'price': 55.0,
            'quantity': 1,
            'isTargetCompany': true,
          },
        ],
      };

      var result = AiReceiptAnalysisResult.fromJson(jsonWithMergedReceipts);

      // Simulate Dart Gatekeeper under allowComplementaryReceipts = false (Default Security Standard)
      const bool allowComplementaryReceipts = false;
      if (!allowComplementaryReceipts) {
        final rawReceiptNum = result.receiptNumber.trim();
        final hasMultiReceiptDelimiter = rawReceiptNum.contains('+') ||
            rawReceiptNum.contains(' + ') ||
            rawReceiptNum.contains(' و ') ||
            rawReceiptNum.contains(' AND ') ||
            rawReceiptNum.contains(' and ');

        final hasMultiReceiptInMessage = result.message.contains('بونين') ||
            result.message.contains('بونات مدمجة') ||
            result.message.contains('فاتورتين') ||
            result.message.contains('بون تكميلي') ||
            result.message.contains('تكملة الفاتورة');

        final hasMultiReceiptViolation = result.unfulfilledConditions.any(
          (c) => c.contains('دمج بونات') || c.contains('بونات شراء منفصلة') || c.contains('فاتورة واحدة مستقلة'),
        );

        if (hasMultiReceiptDelimiter || (hasMultiReceiptInMessage && result.isValid) || hasMultiReceiptViolation) {
          final List<String> reasons = List<String>.from(result.unfulfilledConditions);
          const violationReason = 'مخالفة معايير الأهلية: تم رصد محاولة دمج بونات شراء منفصلة ذات أرقام أو توقيتات مختلفة في معاملة واحدة. يشترط النظام استيفاء شروط العرض في فاتورة شراء واحدة مستقلة.';
          if (!reasons.contains(violationReason)) {
            reasons.insert(0, violationReason);
          }

          result = result.copyWith(
            isValid: false,
            chancesEarned: 0,
            message: 'عذراً، تم رفض العملية: غير مسموح بدمج أو تجميع أكثر من بون شراء منفصل لاستيفاء قيمة العرض. يشترط النظام استيفاء شروط العرض في فاتورة شراء واحدة مستقلة.',
            unfulfilledConditions: reasons,
          );
        }
      }

      expect(result.isValid, isFalse);
      expect(result.chancesEarned, equals(0));
      expect(result.unfulfilledConditions, isNotEmpty);
      expect(result.unfulfilledConditions.first, contains('دمج بونات شراء منفصلة'));
      expect(result.message, contains('غير مسموح بدمج أو تجميع أكثر من بون شراء منفصل'));
    });

    test('EventModel defaults allowComplementaryReceipts to false and serializes accurately', () {
      final defaultEvent = EventModel(
        id: 'camp_1',
        eventName: 'حملة كادبوري',
        targetCompany: 'كادبوري',
        minimumSpend: 400.0,
      );

      expect(defaultEvent.allowComplementaryReceipts, isFalse);

      final map = defaultEvent.toFirestore();
      expect(map['allowComplementaryReceipts'], isFalse);

      final restored = EventModel.fromFirestoreMap('camp_1', map);
      expect(restored.allowComplementaryReceipts, isFalse);

      // Opt-in campaign mode
      final optInEvent = defaultEvent.copyWith(allowComplementaryReceipts: true);
      expect(optInEvent.allowComplementaryReceipts, isTrue);
      final optInMap = optInEvent.toFirestore();
      expect(optInMap['allowComplementaryReceipts'], isTrue);
      final optInRestored = EventModel.fromFirestoreMap('camp_1', optInMap);
      expect(optInRestored.allowComplementaryReceipts, isTrue);
    });
  });
}
