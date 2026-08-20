import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Branch & Prize Allocation Deduplication Tests', () {
    test('EventModel.fromFirestoreMap deduplicates branchIds, branchNames, and allocatedPrizes', () {
      final rawData = {
        'eventName': 'حملة يونيليفر',
        'targetCompany': 'يونيليفر',
        'companySlug': 'unilever',
        'minimumSpend': 100.0,
        'retailChainId': 'gomla_market, gomla_market',
        'retailChainName': 'جملة ماركت • جملة ماركت',
        'branchIds': [
          'branch_ajami',
          'branch_smouha',
          'branch_ajami', // duplicate
          'branch_smouha', // duplicate
          'branch_october',
        ],
        'branchNames': [
          'فرع عجمي ستار',
          'فرع سموحة',
          'فرع عجمي ستار', // duplicate
          'فرع سموحة', // duplicate
          'فرع أكتوبر',
        ],
        'allocatedPrizes': [
          {
            'giftId': 'voucher_50',
            'name': 'فواتشر 50 جنيه',
            'allocatedQuantity': 14,
            'remainingQuantity': 14,
            'giftType': 'voucher',
            'unitValue': 50.0,
            'branchId': 'branch_ajami',
            'branchName': 'فرع عجمي ستار',
          },
          {
            'giftId': 'voucher_50',
            'name': 'فواتشر 50 جنيه',
            'allocatedQuantity': 14,
            'remainingQuantity': 14,
            'giftType': 'voucher',
            'unitValue': 50.0,
            'branchId': 'branch_ajami', // duplicate prize
            'branchName': 'فرع عجمي ستار',
          },
          {
            'giftId': 'voucher_50',
            'name': 'فواتشر 50 جنيه',
            'allocatedQuantity': 14,
            'remainingQuantity': 14,
            'giftType': 'voucher',
            'unitValue': 50.0,
            'branchId': 'branch_smouha',
            'branchName': 'فرع سموحة',
          },
        ],
        'isAllBranches': false,
      };

      final event = EventModel.fromFirestoreMap('event_123', rawData);

      // Verify branchIds and branchNames are deduplicated
      expect(event.branchIds.length, 3);
      expect(event.branchIds, ['branch_ajami', 'branch_smouha', 'branch_october']);

      expect(event.branchNames.length, 3);
      expect(event.branchNames, ['فرع عجمي ستار', 'فرع سموحة', 'فرع أكتوبر']);

      // Verify allocatedPrizes deduplicated
      expect(event.allocatedPrizes.length, 2);
      expect(event.allocatedPrizes.map((p) => p.branchId).toList(), ['branch_ajami', 'branch_smouha']);

      // Verify toFirestore maintains deduplicated state
      final serialized = event.toFirestore();
      expect(serialized['branchIds'], ['branch_ajami', 'branch_smouha', 'branch_october']);
      expect(serialized['branchNames'], ['فرع عجمي ستار', 'فرع سموحة', 'فرع أكتوبر']);
      expect((serialized['allocatedPrizes'] as List).length, 2);
    });
  });
}
