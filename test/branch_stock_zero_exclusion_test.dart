import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/core/services/company_gifts_service.dart';

void main() {
  group('Branch Stock & Zero-Stock Exclusion Tests', () {
    late EventModel elRashidiEvent;

    setUp(() {
      elRashidiEvent = EventModel(
        id: 'q1r45sW0bcYNJ2RU2aEI',
        eventName: 'عروض وحملات الرشيدي الميزان',
        targetCompany: 'الرشيدي الميزان',
        minimumSpend: 150.0,
        companySlug: '83',
        retailChainName: 'أسواق فتح الله • جملة ماركت',
        branchIds: [
          'fathalla_224',
          'fathalla_221',
          'fathalla_212',
          'fathalla_211',
        ],
        branchNames: [
          'فرع عجمي ستار (الإسكندرية)',
          'فرع هانوفيل (الإسكندرية)',
          'فرع جاردينيا (الإسكندرية)',
          'فرع سموحة (الإسكندرية)',
        ],
        allocatedPrizes: [
          // Hanoville prizes:
          // 0-stock prize:
          AllocatedPrize(
            giftId: 'g_knife',
            name: 'سكينة',
            branchName: 'فرع هانوفيل (الإسكندرية)',
            allocatedQuantity: 10,
            remainingQuantity: 0, // Out of stock!
          ),
          // Positive-stock prizes:
          AllocatedPrize(
            giftId: 'g_lunch_box',
            name: 'lunch box',
            branchName: 'فرع هانوفيل (الإسكندرية)',
            allocatedQuantity: 10,
            remainingQuantity: 4, // Available!
          ),
          AllocatedPrize(
            giftId: 'g_plate',
            name: 'plate',
            branchName: 'فرع هانوفيل (الإسكندرية)',
            allocatedQuantity: 48,
            remainingQuantity: 35, // Available!
          ),
          AllocatedPrize(
            giftId: 'g_jam',
            name: 'مربي 700 جم',
            branchName: 'فرع هانوفيل (الإسكندرية)',
            allocatedQuantity: 24,
            remainingQuantity: 24, // Available!
          ),
          // Gardenia prizes:
          AllocatedPrize(
            giftId: 'g_knife',
            name: 'سكينة',
            branchName: 'فرع جاردينيا (الإسكندرية)',
            allocatedQuantity: 17,
            remainingQuantity: 7, // Available in Gardenia!
          ),
        ],
      );
    });

    test('resolveBranchAliases resolves technical ID fathalla_221 to Hanoville', () {
      final aliases = elRashidiEvent.resolveBranchAliases('fathalla_221');
      expect(aliases.contains('fathalla_221'), isTrue);
      expect(aliases.any((a) => a.contains('هانوفيل')), isTrue);
    });

    test('Zero-Stock Exclusion: 0-stock knife is strictly excluded from Hanoville', () {
      // Querying available prizes using technical ID fathalla_221
      final availablePrizesById = elRashidiEvent.availablePrizeNamesForBranch('fathalla_221');

      expect(availablePrizesById, isNotEmpty);
      expect(availablePrizesById.contains('سكينة'), isFalse, reason: '0-stock knife must never be available');
      expect(availablePrizesById.contains('lunch box'), isTrue);
      expect(availablePrizesById.contains('plate'), isTrue);
      expect(availablePrizesById.contains('مربي 700 جم'), isTrue);

      // Querying using Arabic branch name
      final availablePrizesByName = elRashidiEvent.availablePrizeNamesForBranch('فرع هانوفيل (الإسكندرية)');
      expect(availablePrizesByName.contains('سكينة'), isFalse);
      expect(availablePrizesByName.contains('lunch box'), isTrue);
    });

    test('filterGiftsByBranchStock strictly drops 0-stock candidates and preserves positive ones', () {
      final candidateGifts = ['سكينة', 'lunch box', 'plate', 'مربي 700 جم'];

      // Filter for Hanoville via fathalla_221
      final filteredForHanoville = elRashidiEvent.filterGiftsByBranchStock(
        candidateGifts: candidateGifts,
        branch: 'fathalla_221',
      );

      // Knife has 0 stock in Hanoville -> must be dropped
      expect(filteredForHanoville.contains('سكينة'), isFalse);
      // Other 3 have > 0 stock -> must be kept
      expect(filteredForHanoville, containsAll(['lunch box', 'plate', 'مربي 700 جم']));

      // Filter for Gardenia -> Knife has 7 remaining in Gardenia, so it is kept!
      final filteredForGardenia = elRashidiEvent.filterGiftsByBranchStock(
        candidateGifts: candidateGifts,
        branch: 'fathalla_212',
      );
      expect(filteredForGardenia.contains('سكينة'), isTrue);
    });

    test('CompanyGiftsService.findBestPrizeMatchIndex matches branch via alias or ID', () {
      final rawPrizes = [
        {
          'giftId': 'g_lunch_box',
          'name': 'lunch box',
          'branchName': 'فرع هانوفيل (الإسكندرية)',
          'branchId': '',
          'allocatedQuantity': 10,
          'remainingQuantity': 4,
          'unitValue': 0,
        },
      ];

      // Matching with branchId = fathalla_221
      final matchIdx = CompanyGiftsService.findBestPrizeMatchIndex(
        rawPrizes,
        'lunch box',
        branchId: 'فرع هانوفيل (الإسكندرية)',
      );

      expect(matchIdx, equals(0));
    });
  });
}
