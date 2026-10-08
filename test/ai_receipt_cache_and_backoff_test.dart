import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';

void main() {
  group('AiReceiptService LRU Caching & Fingerprinting Tests (AIR-74)', () {
    setUp(() {
      AiReceiptService.clearReceiptAnalysisCache();
    });

    test('computeBytesFingerprint produces deterministic fingerprint for same byte data', () {
      final bytes1 = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      final bytes2 = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      final diffBytes = Uint8List.fromList([1, 2, 3, 4, 99, 6, 7, 8, 9, 10]);

      final fp1 = AiReceiptService.computeBytesFingerprint([bytes1]);
      final fp2 = AiReceiptService.computeBytesFingerprint([bytes2]);
      final fpDiff = AiReceiptService.computeBytesFingerprint([diffBytes]);

      expect(fp1, isNotEmpty);
      expect(fp1, equals(fp2));
      expect(fp1, isNot(equals(fpDiff)));
    });

    test('cacheReceiptAnalysis stores and retrieves cached analysis accurately', () {
      const fingerprint = 'receipt_test_fp_1001';
      final mockResult = AiReceiptAnalysisResult(
        isValid: true,
        receiptNumber: 'REC-12345',
        targetCompanyTotal: 450.0,
        receiptDate: '2026-10-09',
        storeChainDetected: 'أسواق فتح الله',
        branchDetected: 'سموحة',
        isBranchMatched: true,
        isHandwritten: false,
        isThermalPosReceipt: true,
        extractedProducts: [],
        message: 'تم فحص الفاتورة بنجاح',
        durationMs: 1200,
        durationSeconds: 1.2,
      );

      expect(AiReceiptService.getCachedReceiptAnalysis(fingerprint), isNull);

      AiReceiptService.cacheReceiptAnalysis(fingerprint, mockResult);

      final cached = AiReceiptService.getCachedReceiptAnalysis(fingerprint);
      expect(cached, isNotNull);
      expect(cached!.receiptNumber, equals('REC-12345'));
      expect(cached.targetCompanyTotal, equals(450.0));
      expect(cached.storeChainDetected, equals('أسواق فتح الله'));
    });

    test('clearReceiptAnalysisCache clears all entries from LRU cache', () {
      AiReceiptService.cacheReceiptAnalysis(
        'fp_1',
        AiReceiptAnalysisResult(
          isValid: true,
          receiptNumber: 'R1',
          targetCompanyTotal: 100.0,
          receiptDate: '2026-10-09',
          storeChainDetected: 'كارفور',
          branchDetected: 'سيتي سنتر',
          isBranchMatched: true,
          isHandwritten: false,
          isThermalPosReceipt: true,
          extractedProducts: [],
          message: 'ok',
          durationMs: 500,
          durationSeconds: 0.5,
        ),
      );

      expect(AiReceiptService.getCachedReceiptAnalysis('fp_1'), isNotNull);

      AiReceiptService.clearReceiptAnalysisCache();

      expect(AiReceiptService.getCachedReceiptAnalysis('fp_1'), isNull);
    });

    test('LRU cache maintains eviction bound when exceeding maximum capacity', () {
      for (int i = 0; i < 110; i++) {
        AiReceiptService.cacheReceiptAnalysis(
          'fp_$i',
          AiReceiptAnalysisResult(
            isValid: true,
            receiptNumber: 'R_$i',
            targetCompanyTotal: i.toDouble(),
            receiptDate: '2026-10-09',
            storeChainDetected: 'Chain $i',
            branchDetected: 'Branch $i',
            isBranchMatched: true,
            isHandwritten: false,
            isThermalPosReceipt: true,
            extractedProducts: [],
            message: 'ok',
            durationMs: 100,
            durationSeconds: 0.1,
          ),
        );
      }

      // Oldest entry (fp_0) must have been evicted to make room for newest entries
      expect(AiReceiptService.getCachedReceiptAnalysis('fp_0'), isNull);
      // Recent entries must still exist
      expect(AiReceiptService.getCachedReceiptAnalysis('fp_109'), isNotNull);
    });
  });
}
