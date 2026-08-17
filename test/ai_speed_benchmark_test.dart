import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';

void main() {
  group('AI Receipt Analysis Speed & KPI Benchmark Tests', () {
    test('AiReceiptAnalysisResult correctly categorizes KPI ratings', () {
      expect(AiReceiptAnalysisResult.calculateKpiRating(1.2), '⚡ فائق السرعة (Ultra Fast)');
      expect(AiReceiptAnalysisResult.calculateKpiRating(1.99), '⚡ فائق السرعة (Ultra Fast)');
      expect(AiReceiptAnalysisResult.calculateKpiRating(2.5), '🟢 ممتاز (Excellent)');
      expect(AiReceiptAnalysisResult.calculateKpiRating(3.5), '🟢 ممتاز (Excellent)');
      expect(AiReceiptAnalysisResult.calculateKpiRating(4.2), '🟡 مقبول (Acceptable)');
      expect(AiReceiptAnalysisResult.calculateKpiRating(5.0), '🟡 مقبول (Acceptable)');
      expect(AiReceiptAnalysisResult.calculateKpiRating(6.5), '🔴 بطيء (Slow)');
    });

    test('AiReceiptAnalysisResult correctly assigns KPI colors', () {
      expect(AiReceiptAnalysisResult.calculateKpiColor(1.5), '#00C853');
      expect(AiReceiptAnalysisResult.calculateKpiColor(2.8), '#2E7D32');
      expect(AiReceiptAnalysisResult.calculateKpiColor(4.5), '#F57F17');
      expect(AiReceiptAnalysisResult.calculateKpiColor(7.0), '#D50000');
    });

    test('AiReceiptAnalysisResult serialization includes duration and KPI info', () {
      final result = AiReceiptAnalysisResult(
        isValid: true,
        receiptNumber: '295/8/211/220726',
        targetCompanyTotal: 265.0,
        receiptDate: '22/07/2026',
        storeChainDetected: 'أسواق فتح الله',
        branchDetected: 'فرع سموحة',
        isBranchMatched: true,
        message: 'تم فحص الفاتورة بنجاح.',
        durationMs: 1450,
        durationSeconds: 1.45,
      );

      expect(result.durationMs, 1450);
      expect(result.durationSeconds, 1.45);
      expect(result.kpiRating, '⚡ فائق السرعة (Ultra Fast)');
      expect(result.kpiColorHex, '#00C853');

      final json = result.toJson();
      expect(json['durationMs'], 1450);
      expect(json['durationSeconds'], 1.45);
      expect(json['kpiRating'], '⚡ فائق السرعة (Ultra Fast)');

      final parsed = AiReceiptAnalysisResult.fromJson(json);
      expect(parsed.durationMs, 1450);
      expect(parsed.durationSeconds, 1.45);
      expect(parsed.receiptNumber, '295/8/211/220726');
      expect(parsed.targetCompanyTotal, 265.0);
    });

    test('AiReceiptAnalysisResult copyWith updates duration and retains data', () {
      final original = AiReceiptAnalysisResult(
        isValid: true,
        receiptNumber: 'INV-100',
        targetCompanyTotal: 150.0,
        message: 'Original message',
        durationMs: 3200,
        durationSeconds: 3.2,
      );

      final updated = original.copyWith(
        isValid: false,
        message: 'Updated message',
        durationMs: 1800,
        durationSeconds: 1.8,
      );

      expect(updated.isValid, false);
      expect(updated.message, 'Updated message');
      expect(updated.receiptNumber, 'INV-100');
      expect(updated.durationMs, 1800);
      expect(updated.durationSeconds, 1.8);
      expect(updated.kpiRating, '⚡ فائق السرعة (Ultra Fast)');
    });
  });
}
