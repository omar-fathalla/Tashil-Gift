import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/utils/receipt_date_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Panda campaign window: Oct 25 00:00 to Nov 3 00:00 Cairo.
  final start = DateTime.utc(2026, 10, 24, 21);
  final end = DateTime.utc(2026, 11, 2, 22);

  group('parseReceiptDate', () {
    for (final s in [
      '2026/10/30',
      '2026-10-30',
      '2026.10.30',
      '2026/10/30 17:37',
      '30/10/2026',
      '30-10-2026',
      '30.10.2026',
      '30/10/26',
      '30/10/2026 17:37',
    ]) {
      test(s, () {
        final d = AiReceiptService.parseReceiptDate(
          s,
          startDate: start,
          endDate: end,
        )!;
        expect([d.year, d.month, d.day], [2026, 10, 30]);
      });
    }
  });

  group('receiptDateWithinCampaign', () {
    test('year-first inside window', () {
      expect(receiptDateWithinCampaign('2026/10/30', start, end), isTrue);
    });
    test('dd/mm/yyyy inside window', () {
      expect(receiptDateWithinCampaign('30/10/2026', start, end), isTrue);
    });
    test('dd/mm/yy inside window', () {
      expect(receiptDateWithinCampaign('30/10/26', start, end), isTrue);
    });
    test('after end', () {
      expect(receiptDateWithinCampaign('2026/11/10', start, end), isFalse);
    });
    test('unknown', () {
      expect(receiptDateWithinCampaign('', start, end), isNull);
      expect(receiptDateWithinCampaign('2026/10/30', null, null), isNull);
    });
  });

  group('fallbackRejectionReason', () {
    test('empty AI message', () {
      expect(fallbackRejectionReason(''), 'الفاتورة غير مطابقة لشروط الحملة');
    });
    test('with AI message', () {
      expect(
        fallbackRejectionReason('x'),
        'الفاتورة غير مطابقة لشروط الحملة: x',
      );
    });
  });
}
