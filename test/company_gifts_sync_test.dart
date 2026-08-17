import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/company_gift_model.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Company Gifts Cross-Campaign Linking & Allocation Tests', () {
    test('CompanyGiftModel correctly tracks total, available, and allocatedInOtherCampaigns', () {
      final gift = CompanyGiftModel(
        id: 'gift_mug_1',
        companySlug: 'almarai',
        companyName: 'شركة المراعي',
        giftName: 'مج حراري ستانلس ستيل',
        totalQuantity: 100,
        availableQuantity: 28,
        allocatedInOtherCampaigns: 72,
      );

      expect(gift.totalQuantity, 100);
      expect(gift.availableQuantity, 28);
      expect(gift.allocatedInOtherCampaigns, 72);

      final updated = gift.copyWith(availableQuantity: 40, allocatedInOtherCampaigns: 60);
      expect(updated.availableQuantity, 40);
      expect(updated.allocatedInOtherCampaigns, 60);
      expect(updated.totalQuantity, 100);
    });

    test('Cross-campaign reservation calculation deducts active campaign allocations accurately', () {
      // Scenario: Master Company Gift stock = 100
      const totalMasterStock = 100;
      final giftId = 'gift_backpack_10';

      // Active Campaign 1 (e.g. Carrefour branch event): allocates 60 units
      final event1 = EventModel(
        id: 'event_carrefour',
        eventName: 'حملة كارفور للمراعي',
        targetCompany: 'شركة المراعي',
        companySlug: 'almarai',
        minimumSpend: 100.0,
        isActive: true,
        allocatedPrizes: [
          AllocatedPrize(
            giftId: giftId,
            name: 'شنطة مدرسية فاخرة',
            allocatedQuantity: 60,
            remainingQuantity: 60,
          ),
        ],
      );

      // Active Campaign 2 (e.g. Lulu Hypermarket event): allocates 12 units
      final event2 = EventModel(
        id: 'event_lulu',
        eventName: 'حملة لولو هايبر للمراعي',
        targetCompany: 'شركة المراعي',
        companySlug: 'almarai',
        minimumSpend: 100.0,
        isActive: true,
        allocatedPrizes: [
          AllocatedPrize(
            giftId: giftId,
            name: 'شنطة مدرسية فاخرة',
            allocatedQuantity: 12,
            remainingQuantity: 12,
          ),
        ],
      );

      final activeEvents = [event1, event2];

      // Calculate total allocated across all active campaigns for this gift
      num totalAllocatedInOtherCampaigns = 0;
      for (final event in activeEvents) {
        for (final prize in event.allocatedPrizes) {
          if (prize.giftId == giftId) {
            totalAllocatedInOtherCampaigns += prize.allocatedQuantity;
          }
        }
      }

      final netAvailableForNewCampaign = (totalMasterStock - totalAllocatedInOtherCampaigns).clamp(0, totalMasterStock);

      expect(totalAllocatedInOtherCampaigns, 72);
      expect(netAvailableForNewCampaign, 28);
    });

    test('Editing an existing campaign excludes its own previous allocation from "other campaigns"', () {
      const totalMasterStock = 100;
      final giftId = 'gift_backpack_10';
      const editingEventId = 'event_carrefour';

      final event1 = EventModel(
        id: 'event_carrefour',
        eventName: 'حملة كارفور للمراعي',
        targetCompany: 'شركة المراعي',
        companySlug: 'almarai',
        minimumSpend: 100.0,
        isActive: true,
        allocatedPrizes: [
          AllocatedPrize(
            giftId: giftId,
            name: 'شنطة مدرسية فاخرة',
            allocatedQuantity: 60,
            remainingQuantity: 60,
          ),
        ],
      );

      final event2 = EventModel(
        id: 'event_lulu',
        eventName: 'حملة لولو هايبر للمراعي',
        targetCompany: 'شركة المراعي',
        companySlug: 'almarai',
        minimumSpend: 100.0,
        isActive: true,
        allocatedPrizes: [
          AllocatedPrize(
            giftId: giftId,
            name: 'شنطة مدرسية فاخرة',
            allocatedQuantity: 12,
            remainingQuantity: 12,
          ),
        ],
      );

      final allEvents = [event1, event2];

      // When editing event_carrefour, exclude it:
      num otherCampaignsAllocated = 0;
      for (final event in allEvents) {
        if (event.id == editingEventId) continue;
        for (final prize in event.allocatedPrizes) {
          if (prize.giftId == giftId) {
            otherCampaignsAllocated += prize.allocatedQuantity;
          }
        }
      }

      final availableForEditingCampaign = (totalMasterStock - otherCampaignsAllocated).clamp(0, totalMasterStock);

      // Only event2's 12 units are in "other" campaigns; 88 units are available for this campaign to allocate
      expect(otherCampaignsAllocated, 12);
      expect(availableForEditingCampaign, 88);
    });

    test('Real-time in-form remaining counter dynamically reflects typed/stepped allocations', () {
      final gift = CompanyGiftModel(
        id: 'gift_1',
        companySlug: 'almarai',
        giftName: 'قسيمة مشتريات',
        totalQuantity: 100,
        availableQuantity: 100,
      );

      // Map of allocations across branches: 'all' -> { giftId: enteredQty }
      final Map<String, Map<String, int>> branchAllocations = {
        'all': {'gift_1': 72},
      };

      // In "all branches" mode:
      final currentAllocation = branchAllocations['all']?['gift_1'] ?? 0;
      final totalAllocatedInThisEvent = currentAllocation;
      final remainingInCampaign = gift.availableQuantity - totalAllocatedInThisEvent;
      final maxAllowable = currentAllocation + (remainingInCampaign > 0 ? remainingInCampaign : 0);

      expect(currentAllocation, 72);
      expect(remainingInCampaign, 28);
      expect(maxAllowable, 100);

      // User types 73:
      branchAllocations['all']!['gift_1'] = 73;
      final updatedAllocation = branchAllocations['all']?['gift_1'] ?? 0;
      final updatedRemaining = gift.availableQuantity - updatedAllocation;

      expect(updatedAllocation, 73);
      expect(updatedRemaining, 27);
    });

    test('Multi-branch allocation balances remain within master pool limits', () {
      final gift = CompanyGiftModel(
        id: 'gift_1',
        companySlug: 'almarai',
        giftName: 'شنطة مدرسية',
        totalQuantity: 100,
        availableQuantity: 100,
      );

      final Map<String, Map<String, int>> branchAllocations = {
        'branch_1': {'gift_1': 40},
        'branch_2': {'gift_1': 35},
      };

      int totalAllocatedInThisEvent = 0;
      branchAllocations.forEach((_, gifts) {
        totalAllocatedInThisEvent += gifts['gift_1'] ?? 0;
      });

      final remainingInCampaign = gift.availableQuantity - totalAllocatedInThisEvent;
      expect(totalAllocatedInThisEvent, 75);
      expect(remainingInCampaign, 25);

      // For branch_3:
      final currentForBranch3 = branchAllocations['branch_3']?['gift_1'] ?? 0;
      final maxAllowableForBranch3 = currentForBranch3 + remainingInCampaign;
      expect(maxAllowableForBranch3, 25);
    });
  });
}
