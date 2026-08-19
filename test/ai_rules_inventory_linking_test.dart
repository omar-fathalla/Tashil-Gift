import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/admin/domain/company_gift_model.dart';
import 'package:al_mraay/core/localization/app_strings.dart';

void main() {
  group('AI Rules and Company Inventory Linking Integration Tests', () {
    final List<CompanyGiftModel> mockInventoryGifts = [
      CompanyGiftModel(
        id: 'gift_v_125',
        companySlug: 'unilever',
        giftName: 'فواتشر 125 جنيه',
        giftType: 'voucher',
        unitValue: 125.0,
        totalQuantity: 50,
        availableQuantity: 50,
      ),
      CompanyGiftModel(
        id: 'gift_v_50',
        companySlug: 'unilever',
        giftName: 'فواتشر 50 جنيه',
        giftType: 'voucher',
        unitValue: 50.0,
        totalQuantity: 100,
        availableQuantity: 100,
      ),
      CompanyGiftModel(
        id: 'gift_clear_90',
        companySlug: 'unilever',
        giftName: 'شامبو كلير 90 مل',
        giftType: 'product',
        unitValue: 35.0,
        totalQuantity: 40,
        availableQuantity: 40,
      ),
      CompanyGiftModel(
        id: 'gift_tresemme_250',
        companySlug: 'unilever',
        giftName: 'تريزمي 250 مل',
        giftType: 'product',
        unitValue: 60.0,
        totalQuantity: 25,
        availableQuantity: 25,
      ),
    ];

    test('PromotionalRuleItem links and updates correctly when switching inventory gifts', () {
      var rule = PromotionalRuleItem(
        id: 'r1',
        ruleTitle: 'عرض اسبراي ريكسونا',
        triggerProduct: 'اسبراي ريكسونا',
        minQuantity: 1,
        rewardType: 'voucher',
        rewardValue: 'قسيمة 50 جنيه',
        rewardAmount: 50.0,
        linkedGiftId: 'gift_v_50',
        linkedGiftName: 'فواتشر 50 جنيه',
      );

      expect(rule.linkedGiftId, 'gift_v_50');
      expect(rule.linkedGiftName, 'فواتشر 50 جنيه');

      // Admin changes linked gift to 125 voucher
      final gift125 = mockInventoryGifts.firstWhere((g) => g.id == 'gift_v_125');
      rule = rule.copyWith(
        linkedGiftId: gift125.id,
        linkedGiftName: gift125.giftName,
        rewardType: gift125.isVoucher ? 'voucher' : 'free_product',
        rewardAmount: gift125.unitValue,
        rewardValue: gift125.giftName,
      );

      expect(rule.linkedGiftId, 'gift_v_125');
      expect(rule.linkedGiftName, 'فواتشر 125 جنيه');
      expect(rule.rewardAmount, 125.0);
      expect(rule.rewardType, 'voucher');

      // Admin unlinks gift
      rule = rule.copyWith(
        linkedGiftId: '',
        linkedGiftName: '',
      );
      expect(rule.linkedGiftId, '');
      expect(rule.linkedGiftName, '');
    });

    test('AppStrings provides accurate trilingual strings for AI inventory linking', () {
      final stringsAr = AppStrings('ar');
      expect(stringsAr.linkedCompanyGiftLabel, contains('مخزون الشركة'));
      expect(stringsAr.ruleLinkedBadge, 'مربوط بالمخزون');
      expect(stringsAr.ruleUnlinkedBadge, 'بحاجة لاختيار هدية');
      expect(stringsAr.presetIdeasHeader, contains('نماذج مقترحة'));

      final stringsEn = AppStrings('en');
      expect(stringsEn.linkedCompanyGiftLabel, contains('Linked Gift'));
      expect(stringsEn.ruleLinkedBadge, 'Linked to Inventory');
      expect(stringsEn.ruleUnlinkedBadge, 'Gift Unlinked');

      final stringsHi = AppStrings('hi');
      expect(stringsHi.ruleLinkedBadge, 'इन्वेंट्री से जुड़ा हुआ');
      expect(stringsHi.ruleUnlinkedBadge, 'उपहार लिंक नहीं है');
    });
  });
}
