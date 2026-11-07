import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/receipt_deduplication_helper.dart';

void main() {
  group('2.0.152 approved receipt lock', () {
    test('server locked error is recognised', () {
      expect(ReceiptDeduplicationHelper.isLockedError('failed-precondition', {'locked': true}), isTrue);
      expect(ReceiptDeduplicationHelper.isLockedError('failed-precondition', {'locked': false}), isFalse);
      expect(ReceiptDeduplicationHelper.isLockedError('permission-denied', {'locked': true}), isFalse);
      expect(ReceiptDeduplicationHelper.isLockedError('failed-precondition', null), isFalse);
    });
    test('locked message is the agreed Arabic text with receipt number', () {
      final m = ReceiptDeduplicationHelper.lockedMessage(' 88/2/243/301026 ');
      expect(m, startsWith('الفاتورة دي اتعمدت قبل كده'));
      expect(m, contains('88/2/243/301026'));
    });
    test('result defaults to not locked', () {
      expect(ReceiptDuplicateCheckResult.notDuplicate.locked, isFalse);
    });
  });
}
