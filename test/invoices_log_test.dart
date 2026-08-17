import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/localization/app_strings.dart';

void main() {
  group('Invoices Log & Barcode Extraction Tests', () {
    test('ExtractedProductItem properly handles barcode and totalPrice', () {
      final item = ExtractedProductItem(
        name: 'حليب المراعي كامل الدسم 1 لتر',
        price: 45.0,
        quantity: 2,
        isTargetCompany: true,
        barcode: '6281007000012',
      );

      expect(item.name, 'حليب المراعي كامل الدسم 1 لتر');
      expect(item.price, 45.0);
      expect(item.quantity, 2);
      expect(item.barcode, '6281007000012');
      expect(item.totalPrice, 90.0);
      expect(item.isTargetCompany, true);

      final json = item.toJson();
      expect(json['barcode'], '6281007000012');
      expect(json['totalPrice'], 90.0);

      final fromJson = ExtractedProductItem.fromJson(json);
      expect(fromJson.barcode, '6281007000012');
      expect(fromJson.totalPrice, 90.0);
      expect(fromJson.name, item.name);
    });

    test('ExtractedProductItem handles missing barcode gracefully with fallback', () {
      final json = {
        'name': 'عصير برتقال المراعي 1 لتر',
        'price': 30.0,
        'quantity': 3,
        'isTargetCompany': true,
      };

      final item = ExtractedProductItem.fromJson(json);
      expect(item.barcode, '');
      expect(item.totalPrice, 90.0);
    });

    test('AiReceiptAnalysisResult correctly serializes and deserializes products with barcodes', () {
      final jsonMap = {
        'isValid': true,
        'receiptNumber': 'REC-998822',
        'targetCompanyTotal': 180.0,
        'receiptDate': '2026-08-16',
        'storeChainDetected': 'كارفور',
        'branchDetected': 'فرع سيتي سنتر',
        'isBranchMatched': true,
        'extractedProducts': [
          {
            'name': 'جبنة مثلثات المراعي 8 قطع',
            'barcode': '6281007000036',
            'price': 25.0,
            'quantity': 4,
            'totalPrice': 100.0,
            'isTargetCompany': true,
          },
          {
            'name': 'خبز توست أبيض',
            'barcode': '6221008000055',
            'price': 35.0,
            'quantity': 1,
            'totalPrice': 35.0,
            'isTargetCompany': false,
          }
        ],
        'message': 'الفاتورة مطابقة لكافة الشروط.',
      };

      final result = AiReceiptAnalysisResult.fromJson(jsonMap);
      expect(result.isValid, true);
      expect(result.receiptNumber, 'REC-998822');
      expect(result.extractedProducts.length, 2);
      expect(result.extractedProducts[0].barcode, '6281007000036');
      expect(result.extractedProducts[0].totalPrice, 100.0);
      expect(result.extractedProducts[0].isTargetCompany, true);
      expect(result.extractedProducts[1].barcode, '6221008000055');
      expect(result.extractedProducts[1].isTargetCompany, false);

      final outputJson = result.toJson();
      expect(outputJson['extractedProducts'][0]['barcode'], '6281007000036');
    });

    test('Trilingual AppStrings for Invoices Log & Barcode extraction exist and are populated', () {
      final ar = AppStrings('ar');
      final en = AppStrings('en');
      final hi = AppStrings('hi');

      // Check key audit getters
      expect(ar.invoicesAuditTitle.isNotEmpty, true);
      expect(en.invoicesAuditTitle.isNotEmpty, true);
      expect(hi.invoicesAuditTitle.isNotEmpty, true);

      expect(ar.allCampaigns.isNotEmpty, true);
      expect(en.allCampaigns.isNotEmpty, true);
      expect(hi.allCampaigns.isNotEmpty, true);

      expect(ar.barcodeCol.isNotEmpty, true);
      expect(en.barcodeCol.isNotEmpty, true);
      expect(hi.barcodeCol.isNotEmpty, true);

      expect(ar.productNameCol.isNotEmpty, true);
      expect(en.productNameCol.isNotEmpty, true);
      expect(hi.productNameCol.isNotEmpty, true);

      expect(ar.unitPriceCol.isNotEmpty, true);
      expect(en.unitPriceCol.isNotEmpty, true);
      expect(hi.unitPriceCol.isNotEmpty, true);

      expect(ar.totalPriceCol.isNotEmpty, true);
      expect(en.totalPriceCol.isNotEmpty, true);
      expect(hi.totalPriceCol.isNotEmpty, true);

      expect(ar.exportCsvBtn.isNotEmpty, true);
      expect(en.exportCsvBtn.isNotEmpty, true);
      expect(hi.exportCsvBtn.isNotEmpty, true);

      expect(ar.searchReceiptPlaceholder.isNotEmpty, true);
      expect(en.searchReceiptPlaceholder.isNotEmpty, true);
      expect(hi.searchReceiptPlaceholder.isNotEmpty, true);
    });

    test('Base64 and HTTPS Receipt Image URLs validation', () {
      const sampleBase64 = 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP...';
      const sampleStorageUrl = 'https://firebasestorage.googleapis.com/v0/b/tashil-gift.firebasestorage.app/o/receipts%2Falmarai%2FINV_123.jpg?alt=media';

      expect(sampleBase64.startsWith('data:image'), true);
      expect(sampleStorageUrl.startsWith('https://'), true);

      // Verify base64 extraction logic
      final extracted = sampleBase64.contains(',') ? sampleBase64.split(',').last : sampleBase64;
      expect(extracted, '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP...');
    });
  });
}
