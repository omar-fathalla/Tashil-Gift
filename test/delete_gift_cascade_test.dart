import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/admin/domain/company_gift_model.dart';

void main() {
  group('Cascade Gift Deletion & Orphaned Prize Filtering Tests', () {
    test('Filtering prizes excludes gifts not present in master catalog', () {
      final masterGifts = [
        CompanyGiftModel(
          id: 'voucher_50',
          companySlug: 'unilever',
          giftName: 'فواتشر 50 جنيه',
          totalQuantity: 1000,
          availableQuantity: 950,
          giftType: 'voucher',
          unitValue: 50.0,
        ),
        CompanyGiftModel(
          id: 'tresemme_250',
          companySlug: 'unilever',
          giftName: 'تريزيمي 250 مل',
          totalQuantity: 300,
          availableQuantity: 250,
          giftType: 'product',
        ),
      ];

      // Simulated prizes in event containing deleted gift 'كلير 90 مل هدية'
      final eventPrizes = [
        AllocatedPrize(
          giftId: 'clear_90',
          name: 'كلير 90 مل هدية',
          allocatedQuantity: 100,
          remainingQuantity: 0,
        ),
        AllocatedPrize(
          giftId: 'tresemme_250',
          name: 'تريزيمي 250 مل',
          allocatedQuantity: 50,
          remainingQuantity: 50,
        ),
        AllocatedPrize(
          giftId: 'voucher_50',
          name: 'فواتشر 50 جنيه',
          allocatedQuantity: 50,
          remainingQuantity: 49,
        ),
      ];

      // Filter out orphaned prizes
      final validPrizes = eventPrizes.where((prize) {
        if (masterGifts.isEmpty) return true;
        return masterGifts.any((mg) {
          return mg.id == prize.giftId ||
              mg.giftName == prize.name ||
              (mg.giftName.isNotEmpty && (mg.giftName.contains(prize.name) || prize.name.contains(mg.giftName)));
        });
      }).toList();

      expect(validPrizes.length, equals(2));
      expect(validPrizes.any((p) => p.name.contains('كلير')), isFalse);
      expect(validPrizes.any((p) => p.giftId == 'tresemme_250'), isTrue);
      expect(validPrizes.any((p) => p.giftId == 'voucher_50'), isTrue);
    });

    test('Allocations map cleanup removes keys of deleted gifts', () {
      final masterGifts = [
        CompanyGiftModel(
          id: 'g1',
          companySlug: 'unilever',
          giftName: 'فواتشر 50 جنيه',
          totalQuantity: 100,
          availableQuantity: 100,
        ),
      ];

      final branchAllocationQuantities = {
        'branch_1': {
          'deleted_clear_id': 100,
          'g1': 50,
        }
      };

      for (final branchEntry in branchAllocationQuantities.entries) {
        final bMap = branchEntry.value;
        final updatedMap = <String, int>{};
        for (final giftEntry in bMap.entries) {
          final key = giftEntry.key;
          final qty = giftEntry.value;
          if (qty <= 0) continue;
          final matched = masterGifts.where((g) => g.id == key || g.giftName == key).firstOrNull;
          if (matched != null) {
            updatedMap[matched.id] = (updatedMap[matched.id] ?? 0) + qty;
          }
        }
        bMap
          ..clear()
          ..addAll(updatedMap);
      }

      expect(branchAllocationQuantities['branch_1']!.containsKey('deleted_clear_id'), isFalse);
      expect(branchAllocationQuantities['branch_1']!['g1'], equals(50));
    });
  });
}
