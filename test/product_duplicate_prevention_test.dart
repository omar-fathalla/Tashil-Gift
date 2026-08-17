import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/company_products_service.dart';

void main() {
  group('Company Products & Deduplication Logic Tests', () {
    test('CompanyProductItem model parsing and mapping', () {
      final map = {
        'companySlug': 'almarai',
        'companyName': 'شركة المراعي',
        'productName': 'حليب المراعي كامل الدسم 1 لتر',
        'barcode': '6281007001001',
        'category': 'ألبان',
        'unitSize': '1 لتر',
      };

      final item = CompanyProductItem.fromMap(map, 'prod_123');

      expect(item.id, 'prod_123');
      expect(item.companySlug, 'almarai');
      expect(item.productName, 'حليب المراعي كامل الدسم 1 لتر');
      expect(item.barcode, '6281007001001');
      expect(item.category, 'ألبان');
      expect(item.unitSize, '1 لتر');
    });

    test('Deduplication logic detects duplicate barcodes and product names correctly', () {
      final existingItems = [
        CompanyProductItem.fromMap({
          'companySlug': 'almarai',
          'productName': 'حليب المراعي 1 لتر',
          'barcode': '6281007001001',
        }, '1'),
        CompanyProductItem.fromMap({
          'companySlug': 'almarai',
          'productName': 'زبادي المراعي 170 جم',
          'barcode': '6281007002001',
        }, '2'),
      ];

      final existingBarcodes = existingItems.map((p) => p.barcode.trim()).toSet();
      final existingNames = existingItems.map((p) => p.productName.trim().toLowerCase()).toSet();

      // Test cases
      final testDuplicateBarcode = '6281007001001';
      final testDuplicateName = 'حليب المراعي 1 لتر';
      final testUniqueItem = {'productName': 'عصير تفاح 1 لتر', 'barcode': '6281007003001'};

      expect(existingBarcodes.contains(testDuplicateBarcode), isTrue);
      expect(existingNames.contains(testDuplicateName.toLowerCase()), isTrue);
      expect(existingBarcodes.contains(testUniqueItem['barcode']), isFalse);
      expect(existingNames.contains(testUniqueItem['productName']!.toLowerCase()), isFalse);
    });
  });
}
