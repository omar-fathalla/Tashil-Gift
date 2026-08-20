import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/company_gift_model.dart';

void main() {
  group('Company Gifts Zero Initial Quantity Tests', () {
    test('CompanyGiftModel can be created with 0 total and available quantity', () {
      final gift = CompanyGiftModel(
        id: 'new_gift_zero',
        companySlug: 'unilever',
        giftName: 'فواتشر 50 جنيه',
        totalQuantity: 0,
        availableQuantity: 0,
        giftType: 'voucher',
        unitValue: 50.0,
      );

      expect(gift.totalQuantity, equals(0));
      expect(gift.availableQuantity, equals(0));
      expect(gift.isVoucher, isTrue);
      expect(gift.unitValue, equals(50.0));
      expect(gift.totalMonetaryValue, equals(0.0));
      expect(gift.availableMonetaryValue, equals(0.0));
    });

    test('Parsing empty or zero string quantity defaults to 0 safely', () {
      const String emptyInput = '';
      const String zeroInput = '0';
      const String validNumberInput = '150';

      final qtyEmpty = emptyInput.trim().isEmpty ? 0 : (int.tryParse(emptyInput.trim()) ?? 0);
      final qtyZero = zeroInput.trim().isEmpty ? 0 : (int.tryParse(zeroInput.trim()) ?? 0);
      final qtyValid = validNumberInput.trim().isEmpty ? 0 : (int.tryParse(validNumberInput.trim()) ?? 0);

      expect(qtyEmpty, equals(0));
      expect(qtyZero, equals(0));
      expect(qtyValid, equals(150));
    });
  });
}
