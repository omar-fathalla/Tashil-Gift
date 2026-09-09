import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/company_products_service.dart';

void main() {
  group('Promotional Rule Brand Deletion Tests', () {
    test('Removing Rexona & Signal from a multi-brand selection leaves only Dove', () {
      final mockProducts = [
        CompanyProductItem(id: '1', companySlug: 'unilever', productName: 'دوف شامبو 600مل', barcode: '62210001'),
        CompanyProductItem(id: '2', companySlug: 'unilever', productName: 'دوف صابون 100جم', barcode: '62210002'),
        CompanyProductItem(id: '3', companySlug: 'unilever', productName: 'ريكسونا رول اون 50مل', barcode: '62210003'),
        CompanyProductItem(id: '4', companySlug: 'unilever', productName: 'ريكسونا اسبراي 150مل', barcode: '62210004'),
        CompanyProductItem(id: '5', companySlug: 'unilever', productName: 'سيجنال معجون مكافح التسوس 75مل', barcode: '62210005'),
      ];

      List<String> selectedProductIds = ['1', '2', '3', '4', '5'];
      List<String> selectedBarcodes = ['62210001', '62210002', '62210003', '62210004', '62210005'];
      List<String> selectedProductNames = mockProducts.map((p) => p.productName).toList();
      List<String> requiredBrands = ['دوف', 'ريكسونا', 'سيجنال'];

      bool productMatchesBrandName(String productName, String brand) {
        final pNorm = productName.toLowerCase();
        if (brand == 'ريكسونا') return pNorm.contains('ريكسونا') || pNorm.contains('rexona');
        if (brand == 'سيجنال') return pNorm.contains('سيجنال') || pNorm.contains('signal');
        if (brand == 'دوف') return pNorm.contains('دوف') || pNorm.contains('dove');
        return false;
      }

      void deleteBrand(String brandToDelete) {
        final Set<String> idsToRemove = {};
        final Set<String> barcodesToRemove = {};
        final Set<String> namesToRemove = {};

        for (final p in mockProducts) {
          if (productMatchesBrandName(p.productName, brandToDelete)) {
            idsToRemove.add(p.id);
            if (p.barcode.isNotEmpty) barcodesToRemove.add(p.barcode);
            namesToRemove.add(p.productName);
          }
        }

        selectedProductIds.removeWhere((id) => idsToRemove.contains(id));
        selectedBarcodes.removeWhere((bc) => barcodesToRemove.contains(bc));
        selectedProductNames.removeWhere((name) => namesToRemove.contains(name));
        requiredBrands.remove(brandToDelete);
      }

      // Step 1: Delete Rexona
      deleteBrand('ريكسونا');
      expect(requiredBrands, equals(['دوف', 'سيجنال']));
      expect(selectedProductIds, equals(['1', '2', '5']));
      expect(selectedBarcodes, equals(['62210001', '62210002', '62210005']));
      expect(selectedProductNames.any((n) => n.contains('ريكسونا')), isFalse);

      // Step 2: Delete Signal
      deleteBrand('سيجنال');
      expect(requiredBrands, equals(['دوف']));
      expect(selectedProductIds, equals(['1', '2']));
      expect(selectedBarcodes, equals(['62210001', '62210002']));
      expect(selectedProductNames.every((n) => n.contains('دوف')), isTrue);
    });
  });
}
