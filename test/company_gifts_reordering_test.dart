import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/company_gift_model.dart';
import 'package:al_mraay/core/localization/app_strings.dart';

void main() {
  group('Company Gifts Drag & Drop Reordering Tests', () {
    test('CompanyGiftModel correctly serializes and deserializes orderIndex', () {
      final gift = CompanyGiftModel(
        id: 'gift-voucher-50',
        companySlug: 'unilever',
        companyName: 'يونيليفر',
        giftName: 'فواتشر 50 جنيه',
        totalQuantity: 100,
        availableQuantity: 80,
        giftType: 'voucher',
        unitValue: 50.0,
        orderIndex: 3,
        createdAt: DateTime(2026, 8, 19),
      );

      expect(gift.orderIndex, 3);
      expect(gift.isVoucher, true);
      expect(gift.totalMonetaryValue, 5000.0);

      final map = gift.toFirestore();
      expect(map['orderIndex'], 3);
      expect(map['companySlug'], 'unilever');
      expect(map['unitValue'], 50.0);

      final copied = gift.copyWith(orderIndex: 0);
      expect(copied.orderIndex, 0);
      expect(copied.giftName, 'فواتشر 50 جنيه');
    });

    test('CompanyGiftModel list sorts deterministically by orderIndex', () {
      final gift1 = CompanyGiftModel(
        id: 'g1',
        companySlug: 'unilever',
        giftName: 'تريزيمي 250 مل',
        totalQuantity: 200,
        availableQuantity: 160,
        orderIndex: 2,
      );

      final gift2 = CompanyGiftModel(
        id: 'g2',
        companySlug: 'unilever',
        giftName: 'فواتشر 50 جنيه',
        totalQuantity: 100,
        availableQuantity: 100,
        orderIndex: 0,
      );

      final gift3 = CompanyGiftModel(
        id: 'g3',
        companySlug: 'unilever',
        giftName: 'كلير 90 مل هدية',
        totalQuantity: 200,
        availableQuantity: 162,
        orderIndex: 1,
      );

      final list = [gift1, gift2, gift3];
      list.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

      expect(list[0].id, 'g2'); // orderIndex 0
      expect(list[1].id, 'g3'); // orderIndex 1
      expect(list[2].id, 'g1'); // orderIndex 2
    });

    test('AppStrings contains trilingual drag-and-drop reorder strings', () {
      final stringsAr = AppStrings('ar');
      final stringsEn = AppStrings('en');
      final stringsHi = AppStrings('hi');

      expect(stringsAr.dragToReorder, 'اسحب لتغيير الترتيب');
      expect(stringsEn.dragToReorder, 'Drag to reorder');
      expect(stringsHi.dragToReorder, 'पुनः व्यवस्थित करने के लिए खींचें');

      expect(stringsAr.dragToReorderHint, contains('اضغط مطولاً'));
      expect(stringsEn.dragToReorderHint, contains('Long press and drag'));
      expect(stringsHi.dragToReorderHint, contains('दबाकर खींचें'));

      expect(stringsAr.orderUpdatedSuccess, contains('تم حفظ ترتيب الهدايا'));
      expect(stringsEn.orderUpdatedSuccess, contains('Gift and voucher order saved'));
      expect(stringsHi.orderUpdatedSuccess, contains('सफलतापूर्वक'));

      expect(stringsAr.reorderBadge, contains('↕️'));
      expect(stringsEn.reorderBadge, contains('↕️'));
      expect(stringsHi.reorderBadge, contains('↕️'));
    });
  });
}
