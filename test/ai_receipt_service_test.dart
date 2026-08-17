import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';

void main() {
  group('AiReceiptAnalysisResult Tests', () {
    test('Should parse valid JSON with storeChainDetected, branchDetected, and isBranchMatched', () {
      final jsonMap = {
        'isValid': true,
        'receiptNumber': '295/8/211/220726',
        'targetCompanyTotal': 250.0,
        'receiptDate': '22/07/2026',
        'storeChainDetected': 'أسواق فتح الله',
        'branchDetected': 'فرع الهانوفيل',
        'isBranchMatched': true,
        'extractedProducts': [
          {
            'name': 'حليب المراعي كامل الدسم 1 لتر',
            'price': 45.0,
            'quantity': 2,
            'isTargetCompany': true,
          }
        ],
        'message': 'الفاتورة مطابقة لكافة الشروط.',
      };

      final result = AiReceiptAnalysisResult.fromJson(jsonMap);

      expect(result.isValid, true);
      expect(result.receiptNumber, '295/8/211/220726');
      expect(result.targetCompanyTotal, 250.0);
      expect(result.storeChainDetected, 'أسواق فتح الله');
      expect(result.branchDetected, 'فرع الهانوفيل');
      expect(result.isBranchMatched, true);
      expect(result.extractedProducts.length, 1);
      expect(result.extractedProducts.first.isTargetCompany, true);
    });

    test('Should parse invalid branch JSON with isBranchMatched false', () {
      final jsonMap = {
        'isValid': false,
        'receiptNumber': '104/3/88',
        'targetCompanyTotal': 180.0,
        'receiptDate': '2026-08-10',
        'storeChainDetected': 'كارفور',
        'branchDetected': 'سيتي سنتر المعادي',
        'isBranchMatched': false,
        'extractedProducts': [],
        'message': 'الفاتورة صادرة من فرع غير مشمول بالعرض.',
      };

      final result = AiReceiptAnalysisResult.fromJson(jsonMap);

      expect(result.isValid, false);
      expect(result.storeChainDetected, 'كارفور');
      expect(result.branchDetected, 'سيتي سنتر المعادي');
      expect(result.isBranchMatched, false);
      expect(result.message, contains('غير مشمول'));
    });

    test('toJson serialization correctly preserves store and branch fields', () {
      final item = ExtractedProductItem(
        name: 'زبادي المراعي طبيعي 105 جم',
        price: 12.5,
        quantity: 4,
        isTargetCompany: true,
      );

      final result = AiReceiptAnalysisResult(
        isValid: true,
        receiptNumber: '554321',
        targetCompanyTotal: 50.0,
        receiptDate: '2026-08-15',
        extractedProducts: [item],
        storeChainDetected: 'أسواق فتح الله',
        branchDetected: 'فرع سموحة',
        isBranchMatched: true,
        message: 'تم التحقق بنجاح',
      );

      final json = result.toJson();

      expect(json['storeChainDetected'], 'أسواق فتح الله');
      expect(json['branchDetected'], 'فرع سموحة');
      expect(json['isBranchMatched'], true);
      expect(json['targetCompanyTotal'], 50.0);
      expect(json['chancesEarned'], 1);
    });

    test('Should parse and serialize chancesEarned correctly for multiple chances', () {
      final jsonMap = {
        'isValid': true,
        'receiptNumber': '998877',
        'targetCompanyTotal': 900.0,
        'receiptDate': '2026-08-16',
        'storeChainDetected': 'أسواق فتح الله',
        'branchDetected': 'فرع سموحة',
        'isBranchMatched': true,
        'chancesEarned': 3,
        'extractedProducts': [],
        'message': 'مبروك! مؤهل لـ 3 فرص سحب.',
      };

      final result = AiReceiptAnalysisResult.fromJson(jsonMap);
      expect(result.chancesEarned, 3);

      final outJson = result.toJson();
      expect(outJson['chancesEarned'], 3);

      final copy = result.copyWith(chancesEarned: 5);
      expect(copy.chancesEarned, 5);
    });
  });
}
