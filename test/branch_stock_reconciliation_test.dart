import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/admin/domain/company_gift_model.dart';
import 'package:al_mraay/core/utils/arabic_numbers_utils.dart';

void main() {
  group('Branch Stock & Prize Disbursal Reconciliation Tests', () {
    test('Arabic branch names normalize and match correctly across variants', () {
      const fullBranchName = 'فرع سموحة (الإسكندرية)';
      const detectedBranch = 'سموحة';
      const detectedWithPrefix = 'فرع سموحة';

      String normalize(String text) {
        return text
            .toLowerCase()
            .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
            .replaceAll('أ', 'ا')
            .replaceAll('إ', 'ا')
            .replaceAll('آ', 'ا')
            .replaceAll('ة', 'ه')
            .replaceAll('ى', 'ي')
            .toEnglishDigits()
            .replaceAll(RegExp(r'[^\w\s\d]'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }

      final normFull = normalize(fullBranchName);
      final normDetected = normalize(detectedBranch);
      final normWithPrefix = normalize(detectedWithPrefix);

      expect(normFull.contains(normDetected), isTrue);
      expect(normFull.contains(normWithPrefix), isTrue);
    });

    test('Reconciles branch claimed count from transactions and computes accurate remaining', () {
      final allocatedPrizes = [
        AllocatedPrize(
          name: 'كلير 90 مل هديه',
          giftId: 'g_clear_90',
          allocatedQuantity: 200,
          remainingQuantity: 200, // Raw remaining before decrement
          unitValue: 0.0,
          giftType: 'product',
          branchName: 'فرع سموحة (الإسكندرية)',
          branchId: 'b_samouha',
        ),
        AllocatedPrize(
          name: 'فواتشر 25 جنيه',
          giftId: 'g_v25',
          allocatedQuantity: 192,
          remainingQuantity: 192,
          unitValue: 25.0,
          giftType: 'voucher',
          branchName: 'فرع سموحة (الإسكندرية)',
          branchId: 'b_samouha',
        ),
      ];

      // Simulated transaction docs from receipts_transactions
      final transactions = [
        {
          'game_played': true,
          'status': 'accepted',
          'branch_detected': 'سموحة',
          'campaignId': 'ev_unilever_haircare',
          'claimed_gifts': [
            {'giftName': 'كلير 90 مل هديه', 'quantity': 2, 'unitValue': 0.0, 'isVoucher': false},
            {'giftName': 'فواتشر 25 جنيه', 'quantity': 1, 'unitValue': 25.0, 'isVoucher': true},
          ],
        },
        {
          'game_played': true,
          'status': 'accepted',
          'branch_detected': 'فرع سموحة (الإسكندرية)',
          'campaignId': 'ev_unilever_haircare',
          'claimed_gifts': [
            {'giftName': 'كلير 90 مل هديه', 'quantity': 3, 'unitValue': 0.0, 'isVoucher': false},
          ],
        },
      ];

      int countClaimed(String prizeName, String branchName) {
        int count = 0;
        for (final t in transactions) {
          final b = (t['branch_detected'] as String? ?? '').trim();
          if (!branchName.contains(b) && !b.contains(branchName)) continue;
          final gifts = (t['claimed_gifts'] as List?) ?? [];
          for (final g in gifts) {
            if (g['giftName'] == prizeName) {
              count += (g['quantity'] as num).toInt();
            }
          }
        }
        return count;
      }

      final clearClaimed = countClaimed('كلير 90 مل هديه', 'فرع سموحة (الإسكندرية)');
      final clearPrize = allocatedPrizes.firstWhere((p) => p.name == 'كلير 90 مل هديه');
      final clearRemaining = (clearPrize.allocatedQuantity - clearClaimed).clamp(0, clearPrize.allocatedQuantity);

      expect(clearClaimed, equals(5)); // 2 + 3 = 5
      expect(clearRemaining, equals(195)); // 200 - 5 = 195

      final v25Claimed = countClaimed('فواتشر 25 جنيه', 'فرع سموحة (الإسكندرية)');
      final v25Prize = allocatedPrizes.firstWhere((p) => p.name == 'فواتشر 25 جنيه');
      final v25Remaining = (v25Prize.allocatedQuantity - v25Claimed).clamp(0, v25Prize.allocatedQuantity);

      expect(v25Claimed, equals(1));
      expect(v25Remaining, equals(191)); // 192 - 1 = 191
    });

    test('Master gift matching ensures volume numbers (90 vs 250) do not mismatch', () {
      final masterGifts = [
        CompanyGiftModel(
          id: 'clear_90',
          giftName: 'كلير 90 مل هديه',
          companySlug: 'unilever',
          giftType: 'product',
          totalQuantity: 500,
          availableQuantity: 500,
          unitValue: 0.0,
        ),
        CompanyGiftModel(
          id: 'tresemme_250',
          giftName: 'تريزيمي 250 مل هديه',
          companySlug: 'unilever',
          giftType: 'product',
          totalQuantity: 400,
          availableQuantity: 400,
          unitValue: 0.0,
        ),
      ];

      final prize = AllocatedPrize(
        name: 'كلير 90 مل هديه',
        giftId: 'clear_90',
        allocatedQuantity: 200,
        remainingQuantity: 200,
      );

      final matched = masterGifts.firstWhere((mg) => mg.giftName == prize.name);
      expect(matched.id, equals('clear_90'));
      expect(matched.giftName.contains('90'), isTrue);
      expect(matched.giftName.contains('250'), isFalse);
    });
  });
}
