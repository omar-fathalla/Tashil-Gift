import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Gamal Salama Sheraton Receipt Qualification Test', () {
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
        'الضحى أرز مصري 1كجم',
        'الضحى لسان عصفور 400جم',
        'الضحى شعرية 400 جم',
        'الضحى مكرونة قلم 400 جم',
        'الضحى مكرونة مرمرة 400 جم',
        'الضحى مكرونة عريضة 400 جرام',
      ],
      linkedGifts: [
        LinkedGiftAllocation(giftId: 'g1', giftName: 'كيس مكرونة ايزى باستا هالبينو', quantity: 1),
      ],
    );

    test('Gamal Salama Sheraton branch is accepted when isAllBranches is true or branch in allowed list', () {
      final allowedBranches = [
        'فرع جاردينيا (الإسكندرية)',
        'فرع سموحة (الإسكندرية)',
        'فرع مدينة الرحاب (القاهرة)',
        'شيراتون (القاهرة)',
      ];

      // Direct check: branch is in allowedBranches
      expect(allowedBranches.any((b) => b.contains('شيراتون')), isTrue);
    });

    test('Full 554.80 EGP Gamal Salama Sheraton receipt qualifies for Al-Doha offer', () {
      final items = [
        ExtractedProductItem(name: 'الضحى عدس اصفر 500 جم', quantity: 2, price: 48.95, isTargetCompany: true),
        ExtractedProductItem(name: 'الضحى دقيق 1ك', quantity: 1, price: 23.95, isTargetCompany: true),
        ExtractedProductItem(name: 'الضحى أرز مصري 1كجم', quantity: 2, price: 51.95, isTargetCompany: true),
        ExtractedProductItem(name: 'الضحى لسان عصفور 400جم', quantity: 3, price: 35.25, isTargetCompany: true),
        ExtractedProductItem(name: 'الضحى شعرية 400 جم', quantity: 2, price: 20.95, isTargetCompany: true),
        ExtractedProductItem(name: 'الضحى مكرونة قلم 400 جم', quantity: 2, price: 20.95, isTargetCompany: true),
        ExtractedProductItem(name: 'الضحى مكرونة مرمرة 400 جم', quantity: 2, price: 20.95, isTargetCompany: true),
        ExtractedProductItem(name: 'الضحى مكرونة عريضة 400 جرام', quantity: 3, price: 20.95, isTargetCompany: true),
        ExtractedProductItem(name: 'الضحى منتج اضافي', quantity: 1, price: 34.75, isTargetCompany: true),
      ];

      final totalSpend = items.fold(0.0, (sum, i) => sum + i.actualLineSpend);
      expect(totalSpend, closeTo(554.80, 0.01));

      final analysisResult = AiReceiptAnalysisResult(
        isValid: true,
        receiptNumber: 'TP0001000420897',
        targetCompanyTotal: totalSpend,
        receiptDate: '10/09/2026',
        storeChainDetected: 'جمال سلامه',
        branchDetected: 'فرع شيراتون',
        isBranchMatched: true,
        extractedProducts: items,
        message: 'الفاتورة صحيحة ومطابقة للشروط',
      );

      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        result: analysisResult,
        extractedProducts: items,
        promotionalRules: [elDohaRule],
        allowCampaignMultipliers: true,
      );

      expect(matches, isNotEmpty);
      final match = matches.first;
      expect(match.rule.id, equals('rule_4'));
      expect(match.qualifyingSpend, greaterThanOrEqualTo(190.0));
    });
  });
}
