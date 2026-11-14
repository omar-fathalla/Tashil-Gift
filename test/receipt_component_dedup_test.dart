import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/receipt_deduplication_helper.dart';

void main() {
  group('Combined-upload component receipt numbers', () {
    test('splits a combined upload and strips spaces', () {
      expect(
        ReceiptDeduplicationHelper.componentReceiptNumbers('64/6/241/250926 + 109/8/241/250926'),
        ['64/6/241/250926', '109/8/241/250926'],
      );
      expect(ReceiptDeduplicationHelper.componentReceiptNumbers(' 64/6/241/250926 '), ['64/6/241/250926']);
      expect(ReceiptDeduplicationHelper.componentReceiptNumbers(''), isEmpty);
      expect(ReceiptDeduplicationHelper.componentReceiptNumbers(null), isEmpty);
    });

    test('componentFields writes the array for single and combined receipts', () {
      expect(ReceiptDeduplicationHelper.componentFields('A + B'), {
        'component_receipt_numbers': ['A', 'B'],
      });
      expect(ReceiptDeduplicationHelper.componentFields('A'), {
        'component_receipt_numbers': ['A'],
      });
      expect(ReceiptDeduplicationHelper.componentFields(''), isEmpty);
    });

    test('combined then single: the single shares a component', () {
      final combined = {
        'receipt_number': '64/6/241 + 109/8/241',
        ...ReceiptDeduplicationHelper.componentFields('64/6/241 + 109/8/241'),
      };
      expect(ReceiptDeduplicationHelper.sharedComponent('109/8/241', combined), '109/8/241');
    });

    test('single then combined: the combined shares a component', () {
      final single = {'receipt_number': '64/6/241', ...ReceiptDeduplicationHelper.componentFields('64/6/241')};
      expect(ReceiptDeduplicationHelper.sharedComponent('77/1/241 + 64/6/241', single), '64/6/241');
    });

    test('legacy record with only the joined string is split', () {
      final legacy = {'receipt_number': '64/6/241 + 109/8/241'};
      expect(ReceiptDeduplicationHelper.storedComponents(legacy), ['64/6/241', '109/8/241']);
      expect(ReceiptDeduplicationHelper.sharedComponent('64/6/241', legacy), '64/6/241');
      expect(ReceiptDeduplicationHelper.sharedComponent('5/5/241', legacy), isNull);
    });

    test('empty array falls back to receipt_number', () {
      expect(
        ReceiptDeduplicationHelper.storedComponents({'receipt_number': 'A + B', 'component_receipt_numbers': <String>[]}),
        ['A', 'B'],
      );
    });
  });
}
