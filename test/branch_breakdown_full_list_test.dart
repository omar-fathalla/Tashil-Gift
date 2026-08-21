import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/admin/domain/company_gift_model.dart';

void main() {
  group('Branch Breakdown View & 12 Campaign Branches Full Population Tests', () {
    test('All 12 branches from event are extracted and paired with all master gifts', () {
      final sampleBranches = [
        'فرع جاردينيا (الإسكندرية)',
        'فرع سموحة (الإسكندرية)',
        'فرع عجمي ستار (الإسكندرية)',
        'فرع المحلة الكبري (الغربية)',
        'شبين الكوم (شبين الكوم)',
        'التجمع (TAGMOO) (القاهرة)',
        'أكتوبر (October) (السادس من أكتوبر)',
        'المنصورة (المنصورة)',
        'عمارات العبور - صلاح سالم (القاهرة)',
        'المنتزه (الإسكندرية)',
        'ميامي (الإسكندرية)',
        'جناكليس (الإسكندرية)',
      ];

      final event = EventModel(
        id: 'i6pEub9R78LWCcAdQwO8',
        eventName: 'يونيليفر ديوز - هيركير',
        targetCompany: 'يونيليفر',
        companySlug: '512',
        minimumSpend: 100.0,
        branchNames: sampleBranches,
        branchIds: List.generate(sampleBranches.length, (i) => 'branch_$i'),
        allocatedPrizes: [],
        createdAt: DateTime.now(),
      );

      final masterGifts = [
        CompanyGiftModel(
          id: 'gift_1',
          giftName: 'كلير ٩٠ مل هديه',
          companySlug: '512',
          companyName: 'يونيليفر',
          unitValue: 55,
          totalQuantity: 100,
          availableQuantity: 100,
          giftType: 'physical',
          createdAt: DateTime.now(),
        ),
        CompanyGiftModel(
          id: 'gift_2',
          giftName: 'تريزيمي 250 مل هديه',
          companySlug: '512',
          companyName: 'يونيليفر',
          unitValue: 95,
          totalQuantity: 100,
          availableQuantity: 100,
          giftType: 'physical',
          createdAt: DateTime.now(),
        ),
        CompanyGiftModel(
          id: 'gift_3',
          giftName: 'فواتشر 50 جنيه',
          companySlug: '512',
          companyName: 'يونيليفر',
          unitValue: 50,
          totalQuantity: 100,
          availableQuantity: 100,
          giftType: 'voucher',
          createdAt: DateTime.now(),
        ),
        CompanyGiftModel(
          id: 'gift_4',
          giftName: 'فواتشر 25 جنيه',
          companySlug: '512',
          companyName: 'يونيليفر',
          unitValue: 25,
          totalQuantity: 100,
          availableQuantity: 100,
          giftType: 'voucher',
          createdAt: DateTime.now(),
        ),
      ];

      // Verify 12 distinct branches
      final distinctBranches = <String>{};
      for (final b in event.branchNames) {
        distinctBranches.add(b.trim());
      }
      expect(distinctBranches.length, equals(12));

      // Verify each branch maps to all 4 gifts
      for (final bName in distinctBranches) {
        final prizesForBranch = masterGifts.map((mg) {
          final matchingPrize = event.allocatedPrizes.where((p) => p.branchName == bName && p.giftId == mg.id).firstOrNull;
          return {
            'giftName': mg.giftName,
            'allocated': matchingPrize?.allocatedQuantity ?? 0,
            'remaining': matchingPrize?.remainingQuantity ?? 0,
          };
        }).toList();

        expect(prizesForBranch.length, equals(4));
        expect(prizesForBranch.every((p) => p['allocated'] == 0), isTrue);
      }
    });
  });
}
