import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Zahran Market Al-Doha Receipt Reproduction Test', () {
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
        'الضحى ارز مصرى 1ك',
        'الضحى مكرونة مرمرية 400 جم',
      ],
      linkedGifts: [
        LinkedGiftAllocation(giftId: 'g1', giftName: 'كيس مكرونة ايزى باستا هالبينو', quantity: 1),
      ],
    );

    test('Test product matching for Zahran receipt items', () {
      final item1 = ExtractedProductItem(
        name: 'الصحي مكرونة مرمرية 400 جم',
        quantity: 2,
        price: 29.0,
        isTargetCompany: true,
      );
      final item2 = ExtractedProductItem(
        name: 'الصحي أرز 1كجم',
        quantity: 4,
        price: 39.95,
        discountAmount: 1.45,
        isTargetCompany: true,
      );

      final match1 = PromotionalRuleMatcher.matchesProduct(item1, elDohaRule.triggerProduct, elDohaRule);
      final match2 = PromotionalRuleMatcher.matchesProduct(item2, elDohaRule.triggerProduct, elDohaRule);

      final reasons = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
        extractedProducts: [item1, item2],
        promotionalRules: [elDohaRule],
      );

      expect(match1, isTrue);
      expect(match2, isTrue);
      expect(reasons, isEmpty);
    });

    test('Test date parsing for Zahran receipt date 09/10/26', () {
      final startDate = DateTime.utc(2026, 9, 6, 21, 0, 0);
      final endDate = DateTime.utc(2026, 10, 6, 21, 0, 0);

      final parsed = AiReceiptService.parseReceiptDate(
        '09/10/26',
        startDate: startDate,
        endDate: endDate,
      );

      expect(parsed, isNotNull);
      expect(parsed!.year, equals(2026));
      expect(parsed.month, equals(9));
      expect(parsed.day, equals(10));
    });

    test('Full 212 EGP Zahran receipt qualifies for rule_4 with 1 chance and linked gifts', () {
      final item1 = ExtractedProductItem(
        name: 'الصحي مكرونة مرمرية 400 جم',
        quantity: 2,
        price: 29.0,
        isTargetCompany: true,
      );
      final item2 = ExtractedProductItem(
        name: 'الصحي أرز 1كجم',
        quantity: 4,
        price: 39.95,
        discountAmount: 1.45,
        isTargetCompany: true,
      );

      final analysisResult = AiReceiptAnalysisResult(
        isValid: true,
        receiptNumber: '0000P10010000631017',
        targetCompanyTotal: 212.0,
        receiptDate: '09/10/26',
        storeChainDetected: 'زهران ماركت',
        branchDetected: 'فرع سموحة (الإسكندرية)',
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
      expect(match.qualifyingSpend, equals(212.0));
      expect(match.multipliedLinkedGifts, isNotEmpty);

      final unfulfilled = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
        result: analysisResult,
        extractedProducts: [item1, item2],
        promotionalRules: [elDohaRule],
      );
      expect(unfulfilled, isEmpty);
    });
  });
}
