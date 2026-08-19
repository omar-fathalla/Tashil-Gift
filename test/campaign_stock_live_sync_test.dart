import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/company_gifts_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Campaign Stock Live Sync & Real-Time Balance Tests', () {
    test('findBestPrizeMatchIndex accurately matches voucher rule string to allocated prizes', () {
      final allocatedPrizes = [
        {
          'giftId': 'g_v50',
          'name': 'فواتشر 50 جنيه',
          'allocatedQuantity': 100,
          'remainingQuantity': 100,
          'giftType': 'voucher',
          'unitValue': 50.0,
          'branchId': 'fathalla_smouha',
        },
        {
          'giftId': 'g_clear90',
          'name': 'كلير 90 مل هديه',
          'allocatedQuantity': 50,
          'remainingQuantity': 50,
          'giftType': 'product',
          'unitValue': 0.0,
          'branchId': 'fathalla_smouha',
        },
        {
          'giftId': 'g_tresemme250',
          'name': 'تريزيمي 250 مل هدية',
          'allocatedQuantity': 40,
          'remainingQuantity': 40,
          'giftType': 'product',
          'unitValue': 0.0,
          'branchId': 'fathalla_smouha',
        },
      ];

      // 1. Voucher match with different wording 'قسيمة مشتريات بقيمة 50 ج.م'
      final vMatch = CompanyGiftsService.findBestPrizeMatchIndex(
        allocatedPrizes,
        'قسيمة مشتريات بقيمة 50 ج.م',
        branchId: 'fathalla_smouha',
        unitValue: 50.0,
        isVoucher: true,
      );
      expect(vMatch, equals(0));
      expect(allocatedPrizes[vMatch]['name'], equals('فواتشر 50 جنيه'));

      // 2. Physical Shampoo match with differing taa marbuta 'كلير 90 مل هدية'
      final clearMatch = CompanyGiftsService.findBestPrizeMatchIndex(
        allocatedPrizes,
        'كلير 90 مل هدية',
        branchId: 'fathalla_smouha',
        isVoucher: false,
      );
      expect(clearMatch, equals(1));
      expect(allocatedPrizes[clearMatch]['name'], equals('كلير 90 مل هديه'));

      // 3. Tresemme match by size and product name
      final tresemmeMatch = CompanyGiftsService.findBestPrizeMatchIndex(
        allocatedPrizes,
        'تريزيمي 250 مل هديه',
        branchId: 'fathalla_smouha',
        isVoucher: false,
      );
      expect(tresemmeMatch, equals(2));
      expect(allocatedPrizes[tresemmeMatch]['name'], equals('تريزيمي 250 مل هدية'));

      // 4. Exact giftId match
      final idMatch = CompanyGiftsService.findBestPrizeMatchIndex(
        allocatedPrizes,
        'g_v50',
        branchId: 'fathalla_smouha',
      );
      expect(idMatch, equals(0));
    });

    test('Multi-card voucher split (125 EGP -> 2x50 + 1x25) matches both card buckets properly', () {
      final allocatedPrizes = [
        {
          'giftId': 'card_50',
          'name': 'فواتشر 50 جنيه',
          'allocatedQuantity': 50,
          'remainingQuantity': 50,
          'giftType': 'voucher',
          'unitValue': 50.0,
          'branchId': '',
        },
        {
          'giftId': 'card_25',
          'name': 'فواتشر 25 جنيه',
          'allocatedQuantity': 50,
          'remainingQuantity': 50,
          'giftType': 'voucher',
          'unitValue': 25.0,
          'branchId': '',
        },
      ];

      final linkedGifts = [
        LinkedGiftAllocation(giftId: 'card_50', giftName: 'فواتشر 50 جنيه', quantity: 2, unitValue: 50.0, giftType: 'voucher'),
        LinkedGiftAllocation(giftId: 'card_25', giftName: 'فواتشر 25 جنيه', quantity: 1, unitValue: 25.0, giftType: 'voucher'),
      ];

      final idx0 = CompanyGiftsService.findBestPrizeMatchIndex(
        allocatedPrizes,
        linkedGifts[0].giftId,
        unitValue: linkedGifts[0].unitValue,
        isVoucher: linkedGifts[0].isVoucher,
      );
      expect(idx0, equals(0));

      final idx1 = CompanyGiftsService.findBestPrizeMatchIndex(
        allocatedPrizes,
        linkedGifts[1].giftId,
        unitValue: linkedGifts[1].unitValue,
        isVoucher: linkedGifts[1].isVoucher,
      );
      expect(idx1, equals(1));
    });
  });
}

