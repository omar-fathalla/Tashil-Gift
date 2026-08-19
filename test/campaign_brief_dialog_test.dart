import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/client_portal/presentation/widgets/campaign_brief_dialog.dart';

void main() {
  group('Campaign Brief & Offer Rules Dialog Tests', () {
    test('Trilingual localization strings for Campaign Brief are present and complete', () {
      final stringsAr = AppStrings.fromLocale('ar');
      expect(stringsAr.promoterCampaignBriefTooltip, contains('فكرة وشروط'));
      expect(stringsAr.campaignBriefTitle, contains('فكرة وشروط'));
      expect(stringsAr.promotionalConditionsListTitle, contains('بنود وشروط'));
      expect(stringsAr.ruleConditionBuy, contains('الشرط: شراء'));
      expect(stringsAr.ruleConditionGet, contains('المكافأة المستحقة'));
      expect(stringsAr.campaignGeneralConditions, contains('الشروط العامة'));
      expect(stringsAr.closeBriefDialog, contains('إغلاق الدليل'));

      final stringsEn = AppStrings.fromLocale('en');
      expect(stringsEn.promoterCampaignBriefTooltip, contains('Campaign Brief'));
      expect(stringsEn.campaignBriefTitle, contains('Campaign Brief'));
      expect(stringsEn.promotionalConditionsListTitle, contains('Promotional Conditions'));
      expect(stringsEn.closeBriefDialog, contains('Close Guide'));

      final stringsHi = AppStrings.fromLocale('hi');
      expect(stringsHi.promoterCampaignBriefTooltip, isNotEmpty);
      expect(stringsHi.campaignBriefTitle, isNotEmpty);
      expect(stringsHi.promotionalConditionsListTitle, isNotEmpty);
    });

    testWidgets('CampaignBriefDialog renders company info, structured rules, and badges cleanly', (tester) async {
      final testEvent = EventModel(
        id: 'unilever_summer_2026',
        eventName: 'مهرجان الصيف الترويجي',
        targetCompany: 'يونيليفر',
        companySlug: 'unilever',
        companyLogoUrl: '',
        minimumSpend: 100.0,
        requiredProducts: ['كلير', 'تريزيمي', 'ريكسونا', 'أكس'],
        customPrompt: 'فحص الفواتير',
        welcomeTitle: 'أهلاً بكم',
        welcomeMessage: 'مرحباً',
        termsAndConditions: 'الشروط والأحكام',
        isPromoterActive: true,
        isManagerActive: true,
        promotionalIdea: 'شراء منتجات يونيليفر للحصول على هدايا وفواتشر',
        aiValidationSummary: 'ملخص: 4 عروض ترويجية معتمدة على منتجات يونيليفر.',
        retailChainName: 'أسواق فتح الله',
        branchNames: ['فرع سموحة'],
        promotionalRules: [
          PromotionalRuleItem(
            id: 'rule_1',
            ruleTitle: 'عرض كلير 360 مل -> هدية كلير 90 مل',
            triggerProduct: 'كلير 360 مل',
            minQuantity: 1,
            rewardType: 'free_product',
            rewardValue: 'كلير 90 مل هدية',
            rewardAmount: 0.0,
            allowMultipliers: true,
          ),
          PromotionalRuleItem(
            id: 'rule_2',
            ruleTitle: 'عرض اسبراي ريكسونا أو أكس (قطعتين) -> فواتشر 125 ج.م',
            triggerProduct: 'اسبراي ريكسونا، اسبراي أكس',
            minQuantity: 2,
            rewardType: 'voucher',
            rewardValue: 'قسيمة مشتريات بقيمة 125 ج.م',
            rewardAmount: 125.0,
            allowMultipliers: true,
            linkedGifts: [
              LinkedGiftAllocation(giftId: 'g_50', giftName: 'فواتشر 50 جنيه', quantity: 2, unitValue: 50.0, giftType: 'voucher'),
              LinkedGiftAllocation(giftId: 'g_25', giftName: 'فواتشر 25 جنيه', quantity: 1, unitValue: 25.0, giftType: 'voucher'),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: CampaignBriefDialog(event: testEvent),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify header and company title
      expect(find.text('فكرة وشروط العرض الترويجي'), findsOneWidget);
      expect(find.textContaining('يونيليفر'), findsWidgets);
      expect(find.textContaining('مهرجان الصيف الترويجي'), findsWidgets);

      // Verify rules titles and conditions
      expect(find.text('عرض كلير 360 مل -> هدية كلير 90 مل'), findsOneWidget);
      expect(find.textContaining('كلير 360 مل'), findsWidgets);
      expect(find.text('كلير 90 مل هدية'), findsOneWidget);

      expect(find.text('عرض اسبراي ريكسونا أو أكس (قطعتين) -> فواتشر 125 ج.م'), findsOneWidget);
      expect(find.textContaining('اسبراي ريكسونا'), findsWidgets);
      expect(find.text('قسيمة مشتريات بقيمة 125 ج.م'), findsOneWidget);

      // Verify linked gifts breakdown badges
      expect(find.text('2 × فواتشر 50 جنيه'), findsOneWidget);
      expect(find.text('1 × فواتشر 25 جنيه'), findsOneWidget);

      // Verify close button
      expect(find.text('إغلاق الدليل'), findsOneWidget);
    });
  });
}
