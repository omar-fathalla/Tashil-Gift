import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/company_products_service.dart';
import 'package:al_mraay/core/services/chain_products_intelligence_service.dart';

void main() {
  group('Company Brand Intelligence & Word-Boundary Safety Tests', () {
    final fineProducts = [
      CompanyProductItem(
        id: 'p1',
        companySlug: 'fine',
        productName: 'ایزى واكس بالجوجوبا لازالة الشعر 17شريحة',
        barcode: '2064150000394',
      ),
      CompanyProductItem(
        id: 'p2',
        companySlug: 'fine',
        productName: 'ایزى واكس كاموميل لازالة الشعر 17 ق',
        barcode: '2064150000400',
      ),
      CompanyProductItem(
        id: 'p3',
        companySlug: 'fine',
        productName: 'فاين تواليت 5+1 رول 3 طبقة ديلوكس',
        barcode: '2002030005534',
      ),
      CompanyProductItem(
        id: 'p4',
        companySlug: 'fine',
        productName: 'فاين مناديل تواليت كمفورت اكس لارج 2رول',
        barcode: '6294018801467',
      ),
      CompanyProductItem(
        id: 'p5',
        companySlug: 'fine',
        productName: 'سندريلا جديد عادى بالاجنحة 8فوطة',
        barcode: '2060030001413',
      ),
      CompanyProductItem(
        id: 'p6',
        companySlug: 'fine',
        productName: 'فاين حفاضات اطفال حماية مزدوجة كبير 58 حفاضة',
        barcode: '6294018807308',
      ),
      CompanyProductItem(
        id: 'p7',
        companySlug: 'fine',
        productName: 'ایزي سويت بعسل النحل 220 جم',
        barcode: '6224000076009',
      ),
    ];

    test('Fine catalog items are classified correctly without false Axe or Lux matches', () {
      expect(ChainProductsIntelligenceService.inferBrand(fineProducts[0].productName), equals('Easy'));
      expect(ChainProductsIntelligenceService.inferBrand(fineProducts[1].productName), equals('Easy'));
      expect(ChainProductsIntelligenceService.inferBrand(fineProducts[2].productName), equals('Fine'));
      expect(ChainProductsIntelligenceService.inferBrand(fineProducts[3].productName), equals('Fine'));
      expect(ChainProductsIntelligenceService.inferBrand(fineProducts[4].productName), equals('Cinderella'));
      expect(ChainProductsIntelligenceService.inferBrand(fineProducts[5].productName), equals('Fine'));
      expect(ChainProductsIntelligenceService.inferBrand(fineProducts[6].productName), equals('Easy'));

      // None of them should be Axe or Lux!
      for (final p in fineProducts) {
        final brand = ChainProductsIntelligenceService.inferBrand(p.productName);
        expect(brand, isNot('Axe'), reason: '${p.productName} must not be Axe');
        expect(brand, isNot('Lux'), reason: '${p.productName} must not be Lux');
      }
    });

    test('Real Unilever Axe and Lux items are recognized correctly', () {
      expect(ChainProductsIntelligenceService.inferBrand('أكس مزيل عرق بخاخ 150 مل'), equals('Axe'));
      expect(ChainProductsIntelligenceService.inferBrand('axe body spray 150ml'), equals('Axe'));
      expect(ChainProductsIntelligenceService.inferBrand('لوكس صابون لمسة ناعمة 120 جم'), equals('Lux'));
      expect(ChainProductsIntelligenceService.inferBrand('lux beauty soap 120g'), equals('Lux'));
    });

    test('Deluxe and Wax do not trigger Lux or Axe', () {
      expect(ChainProductsIntelligenceService.inferBrand('مناديل ديلوكس فاخرة'), isNot('Lux'));
      expect(ChainProductsIntelligenceService.inferBrand('deluxe tissue 3 ply'), isNot('Lux'));
      expect(ChainProductsIntelligenceService.inferBrand('حبيبات واكس بارد لإزالة الشعر'), isNot('Axe'));
      expect(ChainProductsIntelligenceService.inferBrand('cold wax strips'), isNot('Axe'));
      expect(ChainProductsIntelligenceService.inferBrand('قميص اكس لارج قطن'), isNot('Axe'));
    });
  });
}
