import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Hyper One Al-Doha Receipt Reproduction Test (AIR-49)', () {
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
      selectedBarcodes: [
        '6223000660010', // 13-digit catalog barcode for Al-Doha Egyptian Rice 1kg
      ],
      selectedProductNames: [
        'الضحى ارز مصرى 1ك',
        'الضحى دقيق ابيض 1ك',
      ],
      linkedGifts: [
        LinkedGiftAllocation(giftId: 'g1', giftName: 'كيس مكرونة ايزى باستا هالبينو', quantity: 1),
      ],
    );

    test('Test date parsing for Hyper One receipt date 10/09/2026', () {
      final startDate = DateTime.utc(2026, 9, 6, 21, 0, 0);
      final endDate = DateTime.utc(2026, 10, 6, 21, 0, 0);

      final parsed = AiReceiptService.parseReceiptDate(
        '10/09/2026',
        startDate: startDate,
        endDate: endDate,
      );

      expect(parsed, isNotNull);
      expect(parsed!.year, equals(2026));
      expect(parsed.month, equals(9));
      expect(parsed.day, equals(10));
    });

    test('Test POS edge-clipped rice item matches rule via token & brand spend invariant', () {
      // Printed on Hyper One receipt as "ز مصرى الضحى 1كجم" (the leading "ر" was clipped on receipt margin)
      // Barcode is 12 digits: "622300066001" (catalog has 13 digits "6223000660010")
      final riceItem = ExtractedProductItem(
        name: 'ز مصرى الضحى 1كجم',
        quantity: 20,
        price: 34.95, // 819.00 - 120.00 discount = 699.00 total / 20 = 34.95 unit price
        originalPrice: 40.95,
        discountAmount: 6.0,
        barcode: '622300066001',
        isTargetCompany: true,
      );

      final isMatch = PromotionalRuleMatcher.matchesProduct(riceItem, elDohaRule.triggerProduct, elDohaRule);
      expect(isMatch, isTrue, reason: 'Rice item with clipped "ز" and 12-digit barcode should match 13-digit catalog entry');
    });

    test('Full 699 EGP Hyper One receipt qualifies for rule_4 with 3 chances and linked gifts', () {
      final riceItem = ExtractedProductItem(
        name: 'ز مصرى الضحى 1كجم',
        quantity: 20,
        price: 34.95,
        originalPrice: 40.95,
        discountAmount: 6.0,
        barcode: '622300066001',
        isTargetCompany: true,
      );

      final nonCompanyItem1 = ExtractedProductItem(
        name: 'وجبة ربع فرخة لاين',
        quantity: 1,
        price: 120.00,
        isTargetCompany: false,
      );

      final nonCompanyItem2 = ExtractedProductItem(
        name: 'مياه طبيعية دسانى 600مل',
        quantity: 1,
        price: 7.00,
        isTargetCompany: false,
      );

      final extractedProducts = [riceItem, nonCompanyItem1, nonCompanyItem2];

      final matchedRules = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: extractedProducts,
        promotionalRules: [elDohaRule],
        allowCampaignMultipliers: true,
      );

      expect(matchedRules.isNotEmpty, isTrue, reason: 'Receipt should qualify for rule_4');
      expect(matchedRules.first.rule.id, equals('rule_4'));
      // 699.00 EGP spent on Al-Doha / 200 EGP per chance = 3 chances
      expect(matchedRules.first.multiplier, equals(3));
      expect(matchedRules.first.multipliedLinkedGifts.first.quantity, equals(3));

      final unfulfilledReasons = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
        extractedProducts: extractedProducts,
        promotionalRules: [elDohaRule],
      );

      expect(unfulfilledReasons, isEmpty, reason: 'Receipt should have zero unfulfilled reasons');
    });
  });
}
