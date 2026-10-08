import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_product_discovery_service.dart';

void main() {
  group('AI Product Discovery Criteria Engine Tests (AIR-72)', () {
    // -------------------------------------------------------------------------
    // Criterion 1: Barcode Integrity
    // -------------------------------------------------------------------------
    group('Criterion 1: isValidRetailBarcode', () {
      test('accepts valid 8, 12, 13, and 14 digit international barcodes', () {
        expect(DiscoveryCriteriaEvaluator.isValidRetailBarcode('01312403'), isTrue); // EAN-8
        expect(DiscoveryCriteriaEvaluator.isValidRetailBarcode('012345678905'), isTrue); // UPC-12
        expect(DiscoveryCriteriaEvaluator.isValidRetailBarcode('622103310127'), isTrue); // 12-digit
        expect(DiscoveryCriteriaEvaluator.isValidRetailBarcode('6223001873413'), isTrue); // EAN-13
        expect(DiscoveryCriteriaEvaluator.isValidRetailBarcode('06223001873413'), isTrue); // ITF-14
      });

      test('rejects short internal POS codes (< 8 digits)', () {
        expect(DiscoveryCriteriaEvaluator.isValidRetailBarcode('0000534'), isFalse);
        expect(DiscoveryCriteriaEvaluator.isValidRetailBarcode('12345'), isFalse);
        expect(DiscoveryCriteriaEvaluator.isValidRetailBarcode('99'), isFalse);
      });

      test('rejects empty, non-numeric, or excessively long barcodes', () {
        expect(DiscoveryCriteriaEvaluator.isValidRetailBarcode(''), isFalse);
        expect(DiscoveryCriteriaEvaluator.isValidRetailBarcode('   '), isFalse);
        expect(DiscoveryCriteriaEvaluator.isValidRetailBarcode('6223001873413A'), isFalse);
        expect(DiscoveryCriteriaEvaluator.isValidRetailBarcode('123456789012345'), isFalse); // 15 digits
      });
    });

    // -------------------------------------------------------------------------
    // Criterion 2: Frequency & Multi-Chain Threshold
    // -------------------------------------------------------------------------
    group('Criterion 2: meetsFrequencyThreshold', () {
      test('passes if frequency is 2 or more', () {
        expect(DiscoveryCriteriaEvaluator.meetsFrequencyThreshold(2, ['أسواق فتح الله']), isTrue);
        expect(DiscoveryCriteriaEvaluator.meetsFrequencyThreshold(5, ['كارفور']), isTrue);
      });

      test('passes if frequency is 1 but observed across 2 or more distinct retail chains', () {
        expect(
          DiscoveryCriteriaEvaluator.meetsFrequencyThreshold(1, ['أسواق فتح الله', 'كارفور']),
          isTrue,
        );
      });

      test('fails if frequency is 1 and observed in only 1 retail chain', () {
        expect(
          DiscoveryCriteriaEvaluator.meetsFrequencyThreshold(1, ['أسواق فتح الله']),
          isFalse,
        );
        expect(
          DiscoveryCriteriaEvaluator.meetsFrequencyThreshold(1, []),
          isFalse,
        );
      });
    });

    // -------------------------------------------------------------------------
    // Criterion 3: Generic & Service Lines Exclusion
    // -------------------------------------------------------------------------
    group('Criterion 3: isGenericOrServiceItem', () {
      test('identifies bags, carrier, and plastic items as generic', () {
        expect(DiscoveryCriteriaEvaluator.isGenericOrServiceItem('كيس بلاستيك كارفور'), isTrue);
        expect(DiscoveryCriteriaEvaluator.isGenericOrServiceItem('شنطة تسوق جملة ماركت'), isTrue);
        expect(DiscoveryCriteriaEvaluator.isGenericOrServiceItem('shopping carrier bag'), isTrue);
      });

      test('identifies delivery, tips, and service items as generic', () {
        expect(DiscoveryCriteriaEvaluator.isGenericOrServiceItem('خدمة توصيل منازل'), isTrue);
        expect(DiscoveryCriteriaEvaluator.isGenericOrServiceItem('إكرامية كاشير'), isTrue);
        expect(DiscoveryCriteriaEvaluator.isGenericOrServiceItem('delivery fees'), isTrue);
      });

      test('identifies discounts, refunds, and vouchers as generic', () {
        expect(DiscoveryCriteriaEvaluator.isGenericOrServiceItem('خصم أصناف ترويجية'), isTrue);
        expect(DiscoveryCriteriaEvaluator.isGenericOrServiceItem('مرتجع بضاعة'), isTrue);
        expect(DiscoveryCriteriaEvaluator.isGenericOrServiceItem('بونص مبيعات'), isTrue);
      });

      test('allows legitimate products', () {
        expect(DiscoveryCriteriaEvaluator.isGenericOrServiceItem('شامبو تريزيمي بوتنكس 400مل'), isFalse);
        expect(DiscoveryCriteriaEvaluator.isGenericOrServiceItem('شيكولاتة كادبوري ديري ميلك 90جم'), isFalse);
        expect(DiscoveryCriteriaEvaluator.isGenericOrServiceItem('صلصة هاينز بيوريه 300جم'), isFalse);
      });
    });

    // -------------------------------------------------------------------------
    // Criterion 4: Price Sanity Check
    // -------------------------------------------------------------------------
    group('Criterion 4: hasValidPrice', () {
      test('accepts realistic retail prices (1.0 to 15,000 EGP)', () {
        expect(DiscoveryCriteriaEvaluator.hasValidPrice(1.0), isTrue);
        expect(DiscoveryCriteriaEvaluator.hasValidPrice(45.5), isTrue);
        expect(DiscoveryCriteriaEvaluator.hasValidPrice(1250.0), isTrue);
      });

      test('rejects zero or negative prices', () {
        expect(DiscoveryCriteriaEvaluator.hasValidPrice(0.0), isFalse);
        expect(DiscoveryCriteriaEvaluator.hasValidPrice(-15.0), isFalse);
        expect(DiscoveryCriteriaEvaluator.hasValidPrice(0.5), isFalse);
      });

      test('rejects extreme unrealistic prices', () {
        expect(DiscoveryCriteriaEvaluator.hasValidPrice(50000.0), isFalse);
      });
    });

    // -------------------------------------------------------------------------
    // Criterion 5: Company Brand Portfolio Whitelist
    // -------------------------------------------------------------------------
    group('Criterion 5: isProbableCompanyProduct', () {
      test('matches Unilever brands with slug or numeric doc_id 512', () {
        expect(DiscoveryCriteriaEvaluator.isProbableCompanyProduct('شامبو تريزيمي كيراتين', 'unilever'), isTrue);
        expect(DiscoveryCriteriaEvaluator.isProbableCompanyProduct('كريم دوف لترطيب البشرة', '512'), isTrue);
        expect(DiscoveryCriteriaEvaluator.isProbableCompanyProduct('مزيل عرق ريكسونا رول', '512'), isTrue);
        expect(DiscoveryCriteriaEvaluator.isProbableCompanyProduct('مرقة دجاج كنور فوري', 'unilever'), isTrue);
        expect(DiscoveryCriteriaEvaluator.isProbableCompanyProduct('شاي ليبتون ناعم', '512'), isTrue);

        // Reject non-unilever brand for unilever company
        expect(DiscoveryCriteriaEvaluator.isProbableCompanyProduct('شيبسي بالجبنة', '512'), isFalse);
      });

      test('matches Cadbury / Mondelez brands with slug or numeric doc_id 4', () {
        expect(DiscoveryCriteriaEvaluator.isProbableCompanyProduct('كادبوري ديري ميلك بندق 90جم', 'cadbury'), isTrue);
        expect(DiscoveryCriteriaEvaluator.isProbableCompanyProduct('شيكولاتة مورو كلاسيك', '4'), isTrue);
        expect(DiscoveryCriteriaEvaluator.isProbableCompanyProduct('بسكويت اوريو فانيليا 6 قطع', '4'), isTrue);
        expect(DiscoveryCriteriaEvaluator.isProbableCompanyProduct('شيكولاتة فليك كادبوري', 'mondelez'), isTrue);
      });

      test('matches El Doha (1434), Heinz (2884), and Almarai (2452)', () {
        expect(DiscoveryCriteriaEvaluator.isProbableCompanyProduct('الضحى ارز فاخر 5كجم', '1434'), isTrue);
        expect(DiscoveryCriteriaEvaluator.isProbableCompanyProduct('هاينز كاتشب حار 300جم', '2884'), isTrue);
        expect(DiscoveryCriteriaEvaluator.isProbableCompanyProduct('المراعي حليب كامل الدسم', '2452'), isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // Full Evaluation Pipeline
    // -------------------------------------------------------------------------
    group('Full Evaluation Pipeline: evaluateProduct', () {
      test('passes a completely compliant product with all 5 criteria satisfied', () {
        final result = DiscoveryCriteriaEvaluator.evaluateProduct(
          productName: 'شامبو تريزيمي كيراتين سموث 400مل',
          barcode: '622103310127',
          price: 185.0,
          frequency: 3,
          retailChains: ['أسواق فتح الله', 'كارفور'],
          companySlug: '512',
          brand: 'تريزيمي',
          enforceFrequency: true,
        );

        expect(result.isEligible, isTrue);
        expect(result.hasValidBarcode, isTrue);
        expect(result.meetsFrequency, isTrue);
        expect(result.isNotGeneric, isTrue);
        expect(result.hasValidPrice, isTrue);
        expect(result.matchesCompanyBrand, isTrue);
        expect(result.rejectionReason, isEmpty);
      });

      test('rejects a product with an invalid short POS code', () {
        final result = DiscoveryCriteriaEvaluator.evaluateProduct(
          productName: 'الضحى سكر 1 كيلو',
          barcode: '0000534',
          price: 35.0,
          frequency: 1,
          retailChains: ['كارفور'],
          companySlug: '1434',
          brand: 'الضحى',
          enforceFrequency: true,
        );

        expect(result.isEligible, isFalse);
        expect(result.hasValidBarcode, isFalse);
        expect(result.rejectionReason, contains('الباركود مفقود أو غير مطابق'));
        expect(result.rejectionReason, contains('تكرار الرصد أقل من مرتين'));
      });

      test('rejects a generic grocery bag line item', () {
        final result = DiscoveryCriteriaEvaluator.evaluateProduct(
          productName: 'كيس تسوق بلاستيك كارفور',
          barcode: '622103310128',
          price: 2.5,
          frequency: 10,
          retailChains: ['كارفور'],
          companySlug: '512',
          brand: '',
          enforceFrequency: true,
        );

        expect(result.isEligible, isFalse);
        expect(result.isNotGeneric, isFalse);
        expect(result.rejectionReason, contains('صنف عام أو خدمة غير سلعية'));
      });
    });
  });
}
