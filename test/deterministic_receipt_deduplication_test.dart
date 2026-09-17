import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/receipt_deduplication_helper.dart';

void main() {
  group('ReceiptDeduplicationHelper Tests', () {
    test('normalizeReceiptNumber cleans whitespace and handles nulls', () {
      expect(ReceiptDeduplicationHelper.normalizeReceiptNumber(null), '');
      expect(ReceiptDeduplicationHelper.normalizeReceiptNumber(''), '');
      expect(ReceiptDeduplicationHelper.normalizeReceiptNumber('  194/5/224/110926  '), '194/5/224/110926');
      expect(ReceiptDeduplicationHelper.normalizeReceiptNumber('194 / 5 / 224 / 110926'), '194/5/224/110926');
    });

    test('sanitizeForDocId produces Firestore-safe document keys', () {
      expect(ReceiptDeduplicationHelper.sanitizeForDocId('194/5/224/110926'), '194_5_224_110926');
      expect(ReceiptDeduplicationHelper.sanitizeForDocId('INV#70-5-224'), 'INV#70-5-224');
      expect(ReceiptDeduplicationHelper.sanitizeForDocId('194:5*224?'), '194_5_224_');
    });

    test('getDeterministicDocId generates consistent and unique IDs per campaign', () {
      final docId1 = ReceiptDeduplicationHelper.getDeterministicDocId(
        campaignId: 'i6pEub9R78LWCcAdQwO8',
        receiptNumber: '194/5/224/110926',
      );
      final docId2 = ReceiptDeduplicationHelper.getDeterministicDocId(
        campaignId: 'i6pEub9R78LWCcAdQwO8',
        receiptNumber: ' 194 / 5 / 224 / 110926 ',
      );
      final docIdAnotherCampaign = ReceiptDeduplicationHelper.getDeterministicDocId(
        campaignId: 'TQOt1oXvflaD5amHarRl',
        receiptNumber: '194/5/224/110926',
      );

      expect(docId1, 'rcpt_i6pEub9R78LWCcAdQwO8_194_5_224_110926');
      expect(docId1, equals(docId2), reason: 'Must be identical regardless of surrounding spaces');
      expect(docId1, isNot(equals(docIdAnotherCampaign)), reason: 'Must differ across different campaigns');
    });

    test('isTransactionClaimed accurately identifies claimed transactions', () {
      // 1. Rejected receipt is NOT claimed
      expect(
        ReceiptDeduplicationHelper.isTransactionClaimed({
          'status': 'rejected',
          'is_valid': false,
          'game_played': false,
        }),
        isFalse,
      );

      // 2. Unfulfilled receipt is NOT claimed
      expect(
        ReceiptDeduplicationHelper.isTransactionClaimed({
          'status': 'unfulfilled',
          'is_valid': true,
          'game_played': false,
          'prize_won': null,
        }),
        isFalse,
      );

      // 3. Played game is claimed
      expect(
        ReceiptDeduplicationHelper.isTransactionClaimed({
          'status': 'accepted',
          'game_played': true,
        }),
        isTrue,
      );

      // 4. Handed over claim status is claimed
      expect(
        ReceiptDeduplicationHelper.isTransactionClaimed({
          'status': 'accepted',
          'claim_status': 'handed_over',
        }),
        isTrue,
      );

      // 5. Prize won is claimed
      expect(
        ReceiptDeduplicationHelper.isTransactionClaimed({
          'status': 'accepted',
          'prize_won': 'قسيمة مشتريات بقيمة 125 ج.م',
        }),
        isTrue,
      );

      // 6. Claimed gifts list is claimed
      expect(
        ReceiptDeduplicationHelper.isTransactionClaimed({
          'status': 'accepted',
          'claimed_gifts': [
            {'gift_name': 'فواتشر 50 جنيه', 'quantity': 2}
          ],
        }),
        isTrue,
      );
    });
  });
}
