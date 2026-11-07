import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/receipt_deduplication_helper.dart';

void main() {
  test('exactDocExists defaults to false (cross-campaign duplicates stay blocked)', () {
    const r = ReceiptDuplicateCheckResult(isDuplicate: true, receiptNumber: '1');
    expect(r.exactDocExists, isFalse);
  });
  test('exactDocExists can mark a same-campaign doc for replaceReceipt', () {
    const r = ReceiptDuplicateCheckResult(isDuplicate: true, receiptNumber: '1', exactDocExists: true);
    expect(r.exactDocExists, isTrue);
  });
}
