import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Campaign Reports & Event Scoping Tests', () {
    test('EventModel properly exposes company, chain, and branch metadata', () {
      final event = EventModel(
        id: 'event-mraay-fathalla-1',
        eventName: 'حملة الصيف الكبرى 2026',
        targetCompany: 'المراعي',
        companySlug: 'almarai',
        minimumSpend: 250.0,
        retailChainId: 'fathalla-chain-1',
        retailChainName: 'أسواق فتح الله',
        branchIds: ['branch-smouha', 'branch-gleem'],
        branchNames: ['فرع سموحة', 'فرع جليم'],
        isAllBranches: false,
        isActive: true,
      );

      expect(event.eventName, 'حملة الصيف الكبرى 2026');
      expect(event.targetCompany, 'المراعي');
      expect(event.retailChainName, 'أسواق فتح الله');
      expect(event.branchNames.length, 2);
      expect(event.branchesDisplaySummary, 'أسواق فتح الله (2 فروع: فرع سموحة، فرع جليم)');
      expect(event.minimumSpend, 250.0);
      expect(event.isActive, true);
    });

    test('EventModel formats all branches summary correctly when isAllBranches is true', () {
      final event = EventModel(
        id: 'event-all-branches',
        eventName: 'مهرجان الجوائز',
        targetCompany: 'جهينة',
        minimumSpend: 150.0,
        retailChainName: 'كارفور',
        isAllBranches: true,
      );

      expect(event.branchesDisplaySummary, 'كارفور (جميع الفروع)');
    });

    test('AllocatedPrize maps correctly for inventory and campaign awards', () {
      final prize = AllocatedPrize(
        giftId: 'gift-airfryer-1',
        name: 'قلاية هوائية فيليبس XXL',
        allocatedQuantity: 10,
        remainingQuantity: 6,
        branchId: 'branch-smouha',
        branchName: 'فرع سموحة',
      );

      expect(prize.giftId, 'gift-airfryer-1');
      expect(prize.allocatedQuantity, 10);
      expect(prize.remainingQuantity, 6);
      expect(prize.branchName, 'فرع سموحة');

      final map = prize.toMap();
      expect(map['giftId'], 'gift-airfryer-1');
      expect(map['remainingQuantity'], 6);

      final fromMap = AllocatedPrize.fromMap(map);
      expect(fromMap.name, prize.name);
      expect(fromMap.remainingQuantity, 6);
    });
  });
}
