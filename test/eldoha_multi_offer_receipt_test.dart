import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Al-Doha Receipt Multi-Offer Tests', () {
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
        'الضحى لوبيا 500جم',
        'الضحى ذرة فيشار 500جم',
        'الضحى سكر 1ك',
      ],
      linkedGifts: [
        LinkedGiftAllocation(giftId: 'g1', giftName: 'كيس مكرونة ايزى باستا هالبينو', quantity: 1),
        LinkedGiftAllocation(giftId: 'g2', giftName: 'كيس مكرونة ايزى باستا مبكبكة', quantity: 1),
        LinkedGiftAllocation(giftId: 'g3', giftName: 'كيس مكرونة ايزى باستا ترافيل', quantity: 1),
        LinkedGiftAllocation(giftId: 'g4', giftName: 'مقلمة', quantity: 1),
        LinkedGiftAllocation(giftId: 'g5', giftName: 'زجاجة مياه', quantity: 1),
        LinkedGiftAllocation(giftId: 'g6', giftName: 'لانش بوكس', quantity: 1),
      ],
    );

    final extractedProducts = [
      ExtractedProductItem(
        name: 'الضحى ارز مصري 1ك',
        quantity: 4,
        price: 42.0,
        isTargetCompany: true,
      ),
      ExtractedProductItem(
        name: 'الضحى لوبيا 500جم',
        quantity: 1,
        price: 107.0,
        isTargetCompany: true,
      ),
      ExtractedProductItem(
        name: 'الضحى ذرة فشار 5',
        quantity: 1,
        price: 91.0,
        isTargetCompany: true,
      ),
      ExtractedProductItem(
        name: 'الضحى سكر 1ك',
        quantity: 1,
        price: 39.0,
        isTargetCompany: true,
      ),
    ];

    test('Each product from Al-Doha receipt matches the promotional rule', () {
      for (final p in extractedProducts) {
        final matches = PromotionalRuleMatcher.matchesProduct(p, elDohaRule.triggerProduct, elDohaRule);
        expect(matches, isTrue, reason: '${p.name} must match Al-Doha rule');
      }
    });

    test('405 EGP of Al-Doha products must qualify for multiplier = 2 (2 offers / chances)', () {
      final analysisResult = AiReceiptAnalysisResult(
        isValid: true,
        receiptNumber: '203/4/211/100926',
        targetCompanyTotal: 405.0,
        storeChainDetected: 'أسواق فتح الله',
        branchDetected: 'فرع سموحة',
        extractedProducts: extractedProducts,
        matchedRuleId: 'rule_4',
        matchedRewardValue: 'أشتري بقيمة 200 جنية من منتجات الضحى واكسب هدية من الهدايا الاتية',
        chancesEarned: 2,
        message: 'الفاتورة صحيحة',
      );

      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        result: analysisResult,
        extractedProducts: extractedProducts,
        promotionalRules: [elDohaRule],
        allowCampaignMultipliers: true,
      );

      expect(matches, isNotEmpty);
      final match = matches.first;
      expect(match.multiplier, equals(2), reason: 'Total spend 405 EGP >= 2 * 190 EGP should yield 2 offers');
      expect(match.qualifyingSpend, equals(405.0), reason: 'All 4 items including ذرة فشار must qualify');

      final bundle = CompositePromotionalBundle.fromMatchedRules(matches);
      expect(bundle.totalChances, equals(2));
    });
  });
}
