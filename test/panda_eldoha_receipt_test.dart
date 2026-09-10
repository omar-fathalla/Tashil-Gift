import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Panda Market Al-Doha Receipt Reproduction Test', () {
    final elDohaRule = PromotionalRuleItem(
      id: 'rule_4',
      ruleTitle: 'أشتري بقيمة 200 جنية من منتجات الضحى واكسب هدية من الهدايا الاتية',
      triggerProduct: '138 صنف محدد من الكتالوج',
      conditionType: 'by_spend',
      minSpend: 190,
      discountTolerance: 5,
      allowMultipliers: true,
      rewardType: 'free_product',
      rewardValue: 'أشتري بقيمة 200 جنية من منتجات الضحى واكسب هدية من الهدايا الاتية',
      selectedProductNames: [
        'الضحى عدس اصفر 500جم',
        'الضحى دقيق ابيض 1ك',
      ],
      linkedGifts: [
        LinkedGiftAllocation(giftId: 'g1', giftName: 'كيس مكرونة ايزى باستا هالبينو', quantity: 1),
      ],
    );

    test('Test date parsing for Panda receipt date 09/10/2026', () {
      final startDate = DateTime.utc(2026, 9, 6, 21, 0, 0);
      final endDate = DateTime.utc(2026, 10, 6, 21, 0, 0);

      final parsed = AiReceiptService.parseReceiptDate(
        '09/10/2026',
        startDate: startDate,
        endDate: endDate,
      );

      expect(parsed, isNotNull);
      expect(parsed!.year, equals(2026));
      expect(parsed.month, equals(9));
      expect(parsed.day, equals(10));
    });

    test('Test product matching for Panda receipt items (عدس اصفر + دقيق 1ك)', () {
      final item1 = ExtractedProductItem(
        name: 'الضحى عدس اصفر 500 جم',
        quantity: 2,
        price: 68.95,
        isTargetCompany: true,
      );
      final item2 = ExtractedProductItem(
        name: 'الضحى دقيق 1ك',
        quantity: 3,
        price: 38.50,
        isTargetCompany: true,
      );

      final match1 = PromotionalRuleMatcher.matchesProduct(item1, elDohaRule.triggerProduct, elDohaRule);
      final match2 = PromotionalRuleMatcher.matchesProduct(item2, elDohaRule.triggerProduct, elDohaRule);

      print('Match 1 (عدس اصفر 500 جم): $match1');
      print('Match 2 (دقيق 1ك): $match2');

      final reasons = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
        extractedProducts: [item1, item2],
        promotionalRules: [elDohaRule],
      );
      print('Reasons: $reasons');

      expect(match1, isTrue);
      expect(match2, isTrue);
      expect(reasons, isEmpty);
    });

    test('Full 253.40 EGP Panda receipt qualifies for rule_4 with 1 chance', () {
      final item1 = ExtractedProductItem(
        name: 'الضحى عدس اصفر 500 جم',
        quantity: 2,
        price: 68.95,
        isTargetCompany: true,
      );
      final item2 = ExtractedProductItem(
        name: 'الضحى دقيق 1ك',
        quantity: 3,
        price: 38.50,
        isTargetCompany: true,
      );

      final analysisResult = AiReceiptAnalysisResult(
        isValid: true,
        receiptNumber: '07611-019260005484',
        targetCompanyTotal: 253.4,
        receiptDate: '09/10/2026',
        storeChainDetected: 'بنده',
        branchDetected: 'العبور (Obour Super) (العبور)',
        extractedProducts: [item1, item2],
        message: 'الفاتورة صحيحة ومطابقة للشروط',
      );

      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        result: analysisResult,
        extractedProducts: [item1, item2],
        promotionalRules: [elDohaRule],
        allowCampaignMultipliers: true,
      );

      expect(matches, isNotEmpty);
      final match = matches.first;
      expect(match.rule.id, equals('rule_4'));
      expect(match.multiplier, equals(1));
      expect(match.qualifyingSpend, equals(253.4));
      expect(match.multipliedLinkedGifts, isNotEmpty);
    });
  });
}
