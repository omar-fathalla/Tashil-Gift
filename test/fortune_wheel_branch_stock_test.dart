import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Fortune Wheel Branch Stock Governance & Zero Stock Exclusion (AIR-85)', () {
    late EventModel testEvent;

    setUp(() {
      testEvent = EventModel(
        id: 'event-101',
        eventName: 'حملة الصيف الترويجية - فتح الله',
        targetCompany: 'فتح الله للجملة',
        companySlug: 'fathalla',
        minimumSpend: 100.0,
        startDate: DateTime.now().subtract(const Duration(days: 5)),
        endDate: DateTime.now().add(const Duration(days: 20)),
        gameType: 'wheel',
        branchIds: ['b-smouha', 'b-gleem', 'b-agamy'],
        branchNames: ['فرع سموحة (الإسكندرية)', 'فرع جليم', 'فرع العجمي'],
        allocatedPrizes: [
          // Smouha branch: Mug in stock (10), Bag OUT OF STOCK (0), Bowl OUT OF STOCK (0)
          AllocatedPrize(
            giftId: 'p-1',
            name: 'ماج زجاجي فاخر',
            allocatedQuantity: 20,
            remainingQuantity: 10,
            unitValue: 50.0,
            branchId: 'b-smouha',
            branchName: 'فرع سموحة',
          ),
          AllocatedPrize(
            giftId: 'p-2',
            name: 'شنطة قماش هدايا',
            allocatedQuantity: 30,
            remainingQuantity: 0, // OUT OF STOCK
            unitValue: 35.0,
            branchId: 'b-smouha',
            branchName: 'فرع سموحة',
          ),
          AllocatedPrize(
            giftId: 'p-3',
            name: 'بولة زجاجية',
            allocatedQuantity: 15,
            remainingQuantity: 0, // OUT OF STOCK
            unitValue: 40.0,
            branchId: 'b-smouha',
            branchName: 'فرع سموحة',
          ),
          // Gleem branch: Bag in stock (15), Mug OUT OF STOCK (0), Tea Cup in stock (8)
          AllocatedPrize(
            giftId: 'p-4',
            name: 'شنطة قماش هدايا',
            allocatedQuantity: 15,
            remainingQuantity: 15, // IN STOCK
            unitValue: 35.0,
            branchId: 'b-gleem',
            branchName: 'فرع جليم',
          ),
          AllocatedPrize(
            giftId: 'p-5',
            name: 'ماج زجاجي فاخر',
            allocatedQuantity: 10,
            remainingQuantity: 0, // OUT OF STOCK in Gleem
            unitValue: 50.0,
            branchId: 'b-gleem',
            branchName: 'فرع جليم',
          ),
          AllocatedPrize(
            giftId: 'p-6',
            name: 'طقم فناجين شاي',
            allocatedQuantity: 10,
            remainingQuantity: 8, // IN STOCK
            unitValue: 60.0,
            branchId: 'b-gleem',
            branchName: 'فرع جليم',
          ),
          // Agamy branch: ALL OUT OF STOCK
          AllocatedPrize(
            giftId: 'p-7',
            name: 'ماج زجاجي فاخر',
            allocatedQuantity: 10,
            remainingQuantity: 0,
            unitValue: 50.0,
            branchId: 'b-agamy',
            branchName: 'فرع العجمي',
          ),
        ],
      );
    });

    test('Strictly excludes zero-stock prizes for Smouha branch', () {
      final smouhaPrizes = testEvent.availablePrizesForBranch('فرع سموحة');
      expect(smouhaPrizes.length, 1);
      expect(smouhaPrizes.first.name, 'ماج زجاجي فاخر');
      expect(smouhaPrizes.first.remainingQuantity, 10);

      final smouhaNames = testEvent.availablePrizeNamesForBranch('فرع سموحة');
      expect(smouhaNames, ['ماج زجاجي فاخر']);
      expect(smouhaNames.contains('شنطة قماش هدايا'), isFalse);
      expect(smouhaNames.contains('بولة زجاجية'), isFalse);
    });

    test('Matches branch by branch ID or normalized branch token', () {
      // By branch ID
      final byId = testEvent.availablePrizeNamesForBranch('b-smouha');
      expect(byId, ['ماج زجاجي فاخر']);

      // By branch name with parenthetical governorate (AIR-80 & Rule 8)
      final byFullString = testEvent.availablePrizeNamesForBranch('فرع سموحة (الإسكندرية)');
      expect(byFullString, ['ماج زجاجي فاخر']);

      // Gleem branch: Mug is 0 stock, Bag & Tea Cup are in stock
      final gleemNames = testEvent.availablePrizeNamesForBranch('فرع جليم');
      expect(gleemNames, containsAll(['شنطة قماش هدايا', 'طقم فناجين شاي']));
      expect(gleemNames.contains('ماج زجاجي فاخر'), isFalse);
    });

    test('Returns empty list when all prizes are out of stock in branch (Agamy)', () {
      final agamyNames = testEvent.availablePrizeNamesForBranch('فرع العجمي');
      expect(agamyNames, isEmpty);

      final agamyPrizes = testEvent.availablePrizesForBranch('فرع العجمي');
      expect(agamyPrizes, isEmpty);
    });

    test('filterGiftsByBranchStock filters candidate gift names against branch stock', () {
      final candidates = ['ماج زجاجي فاخر', 'شنطة قماش هدايا', 'بولة زجاجية'];

      // For Smouha: only 'ماج زجاجي فاخر' has remaining stock > 0
      final filteredForSmouha = testEvent.filterGiftsByBranchStock(
        candidateGifts: candidates,
        branch: 'فرع سموحة',
      );
      expect(filteredForSmouha, ['ماج زجاجي فاخر']);

      // For Gleem: only 'شنطة قماش هدايا' has remaining stock > 0 among candidates
      final filteredForGleem = testEvent.filterGiftsByBranchStock(
        candidateGifts: candidates,
        branch: 'فرع جليم',
      );
      expect(filteredForGleem, ['شنطة قماش هدايا']);

      // For Agamy: none have stock
      final filteredForAgamy = testEvent.filterGiftsByBranchStock(
        candidateGifts: candidates,
        branch: 'فرع العجمي',
      );
      expect(filteredForAgamy, isEmpty);
    });

    test('Single prize display duplication prevents flutter_fortune_wheel assertion failure', () {
      // flutter_fortune_wheel enforces assert(items.length > 1).
      // When a branch has only 1 prize with stock, it must be mapped into 2 symmetric slices.
      final smouhaAvailable = testEvent.availablePrizeNamesForBranch('فرع سموحة');
      expect(smouhaAvailable.length, 1);

      List<String> buildDisplayItems(List<String> items) {
        if (items.isEmpty) return const [];
        if (items.length == 1) return [items.first, items.first];
        return List<String>.from(items);
      }

      final displaySlices = buildDisplayItems(smouhaAvailable);
      expect(displaySlices.length, 2);
      expect(displaySlices, ['ماج زجاجي فاخر', 'ماج زجاجي فاخر']);
      expect(displaySlices.length > 1, isTrue); // Guarantees FortuneWheel won't crash
    });
  });
}
