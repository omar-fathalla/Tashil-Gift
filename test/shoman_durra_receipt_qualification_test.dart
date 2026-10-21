import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/services/company_gifts_service.dart';
import 'package:al_mraay/core/services/campaign_ai_assistant_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Shoman & Al-Durra Campaign Qualification & Competitor Sauce Isolation (AIR-80)', () {
    test('Sub-brands resolver accurately links Al-Durra and Seyidoglu under Shoman', () {
      final shomanSubBrands = CampaignAiAssistantService.resolveCompanySubBrands('شومان');
      expect(shomanSubBrands, contains('الدرة (Al-Durra)'));
      expect(shomanSubBrands, contains('دره (Dorra)'));
      expect(shomanSubBrands, contains('سيد اوغلو (Seyidoglu)'));
      expect(shomanSubBrands, contains('كاتشب الدرة'));
      expect(shomanSubBrands, contains('شيلي صوص الدرة'));
    });

    test('ExtractedProductItem qualifies spaced and standard Al-Durra products for Shoman', () {
      // 1. Spaced Al-Durra ketchup line from Fathalla POS (Store 211): "د ر ه عرض كاتشب 300160.00"
      final spacedDorraItem = ExtractedProductItem.fromJson(
        {
          'name': 'د ر ه عرض كاتشب 300',
          'price': 135.0,
          'originalPrice': 160.0,
          'discountAmount': 25.0,
          'quantity': 1,
          'isTargetCompany': true,
        },
        targetCompany: 'شومان',
      );

      // 2. Al-Durra chili sauce line from Fathalla POS: "الدرة شيلي صوص 41 59.00"
      final dorraChiliItem = ExtractedProductItem.fromJson(
        {
          'name': 'الدرة شيلي صوص 41',
          'price': 59.0,
          'quantity': 1,
          'isTargetCompany': true,
        },
        targetCompany: 'شومان',
      );

      // 3. Seyidoglu item
      final seyidogluItem = ExtractedProductItem.fromJson(
        {
          'name': 'سيد اوغلو مربى مشمش',
          'price': 45.0,
          'quantity': 1,
          'isTargetCompany': true,
        },
        targetCompany: 'شومان',
      );

      // 4. Competitor Heinz ketchup
      final competitorHeinz = ExtractedProductItem.fromJson(
        {
          'name': 'هاينز كاتشب 300 جرام',
          'price': 42.0,
          'quantity': 1,
          'isTargetCompany': true,
        },
        targetCompany: 'شومان',
      );

      // 5. Competitor Harvest sauce
      final competitorHarvest = ExtractedProductItem.fromJson(
        {
          'name': 'صلصة هارفست 320 جم',
          'price': 22.0,
          'quantity': 1,
          'isTargetCompany': true,
        },
        targetCompany: 'شومان',
      );

      expect(spacedDorraItem.isTargetCompany, isTrue);
      expect(dorraChiliItem.isTargetCompany, isTrue);
      expect(seyidogluItem.isTargetCompany, isTrue);
      expect(competitorHeinz.isTargetCompany, isFalse);
      expect(competitorHarvest.isTargetCompany, isFalse);
    });

    test('PromotionalRuleMatcher matches 150 EGP Durra rule for Shoman campaign with receipt 121/1/211/211026', () {
      final promotionalRules = [
        PromotionalRuleItem(
          id: 'rule_1',
          ruleTitle: 'اشتري من منتجات الدرة بقيمة 150 جنيهًا واحصل على قطعه كاتشب هديه',
          triggerProduct: 'منتجات درة و الدرة و الدره و سيد و اوغلو (53 صنف)',
          minSpend: 150.0,
          conditionType: 'by_spend',
          rewardType: 'free_product',
          rewardValue: 'قطعه كاتشب 250 ملي هديه',
          requiredBrands: ['درة', 'الدرة', 'الدره', 'سيد', 'اوغلو'],
        ),
      ];

      final extractedItems = [
        ExtractedProductItem(
          name: 'د ر ه عرض كاتشب 300',
          price: 135.0,
          originalPrice: 160.0,
          discountAmount: 25.0,
          quantity: 1,
          isTargetCompany: true,
        ),
        ExtractedProductItem(
          name: 'الدرة شيلي صوص 41',
          price: 59.0,
          quantity: 1,
          isTargetCompany: true,
        ),
      ];

      final matchedRules = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: extractedItems,
        promotionalRules: promotionalRules,
        allowCampaignMultipliers: false,
      );

      expect(matchedRules.isNotEmpty, isTrue);
      expect(matchedRules.first.rule.id, 'rule_1');
      expect(matchedRules.first.rule.rewardValue, 'قطعه كاتشب 250 ملي هديه');
    });

    test('Smouha branch code 211 resolves to canonical campaign branch', () {
      final allowedBranchNames = [
        'فرع ستانلي (الإسكندرية)',
        'فرع سموحة (الإسكندرية)',
      ];

      final detectedBranch = CompanyGiftsService.normalizeBranchToken('أسواق فتح الله للجملة - سموحة');
      final smouhaApproved = CompanyGiftsService.normalizeBranchToken(allowedBranchNames[1]);

      expect(detectedBranch, smouhaApproved);
      expect(
        CompanyGiftsService.matchesBranchName('أسواق فتح الله للجملة - سموحة', allowedBranchNames[1]),
        isTrue,
      );
    });
  });
}
