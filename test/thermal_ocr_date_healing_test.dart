import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';

void main() {
  group('Thermal Print OCR Year Auto-Healing Tests (AIR-86)', () {
    final campaignStart = DateTime(2026, 10, 1);
    final campaignEnd = DateTime(2026, 11, 29);

    test('heals 23/10/2024 to 2026 when digit 6 was misread as 4 on thermal receipt', () {
      final parsed = AiReceiptService.parseReceiptDate(
        '23/10/2024',
        startDate: campaignStart,
        endDate: campaignEnd,
      );

      expect(parsed, isNotNull);
      expect(parsed!.year, equals(2026));
      expect(parsed.month, equals(10));
      expect(parsed.day, equals(23));
    });

    test('heals hyphen-separated 23-10-2024 to 2026 within campaign window', () {
      final parsed = AiReceiptService.parseReceiptDate(
        '23-10-2024',
        startDate: campaignStart,
        endDate: campaignEnd,
      );

      expect(parsed, isNotNull);
      expect(parsed!.year, equals(2026));
      expect(parsed.month, equals(10));
      expect(parsed.day, equals(23));
    });

    test('does NOT heal genuine out-of-bounds date (e.g. 15/05/2024) outside campaign window', () {
      final parsed = AiReceiptService.parseReceiptDate(
        '15/05/2024',
        startDate: campaignStart,
        endDate: campaignEnd,
      );

      expect(parsed, isNotNull);
      // May is not in [October, November], so year stays 2024 and receipt will be rejected
      expect(parsed!.year, equals(2024));
      expect(parsed.month, equals(5));
      expect(parsed.day, equals(15));
    });

    test('keeps genuine 2026 date intact without alteration', () {
      final parsed = AiReceiptService.parseReceiptDate(
        '23/10/2026',
        startDate: campaignStart,
        endDate: campaignEnd,
      );

      expect(parsed, isNotNull);
      expect(parsed!.year, equals(2026));
      expect(parsed.month, equals(10));
      expect(parsed.day, equals(23));
    });

    test('handles 2-digit years correctly (23/10/26 -> 2026)', () {
      final parsed = AiReceiptService.parseReceiptDate(
        '23/10/26',
        startDate: campaignStart,
        endDate: campaignEnd,
      );

      expect(parsed, isNotNull);
      expect(parsed!.year, equals(2026));
      expect(parsed.month, equals(10));
      expect(parsed.day, equals(23));
    });
  });
}
