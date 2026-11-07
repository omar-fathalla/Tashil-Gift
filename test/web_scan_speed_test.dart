import 'dart:typed_data';

import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/utils/receipt_image_calibrator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sniffImageMimeType', () {
    test('jpeg', () {
      expect(sniffImageMimeType(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])), 'image/jpeg');
    });
    test('png', () {
      expect(sniffImageMimeType(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])), 'image/png');
    });
    test('iPhone HEIC', () {
      final b = Uint8List.fromList([0, 0, 0, 0x18, ...'ftypheic'.codeUnits, 0, 0, 0, 0]);
      expect(sniffImageMimeType(b), 'image/heic');
    });
  });
  group('scan dedupe key', () {
    final a = Uint8List.fromList(List.generate(1000, (i) => i % 251));
    final b = Uint8List.fromList(List.generate(1000, (i) => (i + 1) % 251));
    test('same input same key', () {
      expect(AiReceiptService.scanCacheKeyForTest('m', 'p', [a]),
          AiReceiptService.scanCacheKeyForTest('m', 'p', [a]));
    });
    test('different image, prompt or model changes key', () {
      final k = AiReceiptService.scanCacheKeyForTest('m', 'p', [a]);
      expect(AiReceiptService.scanCacheKeyForTest('m', 'p', [b]), isNot(k));
      expect(AiReceiptService.scanCacheKeyForTest('m', 'q', [a]), isNot(k));
      expect(AiReceiptService.scanCacheKeyForTest('n', 'p', [a]), isNot(k));
    });
  });
}
