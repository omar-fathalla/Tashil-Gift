import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/chain_product_model.dart';
import 'package:al_mraay/core/services/chain_products_intelligence_service.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';

void main() {
  group('Chain Products & Cross-Chain Price Intelligence Tests', () {
    test('ProductPriceHistoryEntry computes effective discount and original price correctly', () {
      final entryWithDiscount = ProductPriceHistoryEntry(
        price: 119.0,
        originalPrice: 140.0,
        discountAmount: 21.0,
        discountPercent: 15.0,
        receiptDate: '21/08/2026',
        receiptNumber: 'REC-001',
        storeChain: 'جملة ماركت',
        branchName: 'فرع 419',
      );

      expect(entryWithDiscount.hasDiscount, isTrue);
      expect(entryWithDiscount.effectiveOriginalPrice, 140.0);
      expect(entryWithDiscount.calculatedDiscountPercent, 15.0);

      final entryWithoutDiscount = ProductPriceHistoryEntry(
        price: 140.0,
        receiptDate: '15/08/2026',
        receiptNumber: 'REC-002',
        storeChain: 'أسواق فتح الله',
        branchName: 'فرع سموحة',
      );

      expect(entryWithoutDiscount.hasDiscount, isFalse);
      expect(entryWithoutDiscount.effectiveOriginalPrice, 140.0);
      expect(entryWithoutDiscount.calculatedDiscountPercent, 0.0);
    });

    test('ExtractedProductItem auto-heals line total to unit price when quantity > 1', () {
      // Case 1: Receipt has 2 items, line total 198 (gross 230, discount 32)
      final rawItemMap = {
        'name': 'شامبو كلير 360 مل',
        'price': 198.0, // AI returned line total
        'quantity': 2,
        'originalPrice': 230.0, // AI returned line gross
        'discountAmount': 32.0, // AI returned line discount
        'discountPercent': 13.9,
        'isTargetCompany': true,
        'barcode': '6221155612168',
      };

      final item = ExtractedProductItem.fromJson(rawItemMap);

      // Must be converted to per-unit price!
      expect(item.quantity, 2);
      expect(item.price, 99.0); // 198 / 2
      expect(item.originalPrice, 115.0); // 230 / 2
      expect(item.discountAmount, 16.0); // 32 / 2
      expect(item.totalPrice, 198.0); // 99 * 2
    });

    test('normalizeRetailChain consolidates variants into canonical Enterprise Chains', () {
      expect(ChainProductsIntelligenceService.normalizeRetailChain('أسواق فتح الله للجملة'), 'أسواق فتح الله');
      expect(ChainProductsIntelligenceService.normalizeRetailChain('فتح الله ماركت'), 'أسواق فتح الله');
      expect(ChainProductsIntelligenceService.normalizeRetailChain('اسواق جملة ماركت'), 'جملة ماركت');
      expect(ChainProductsIntelligenceService.normalizeRetailChain('Gomla Market'), 'جملة ماركت');
      expect(ChainProductsIntelligenceService.normalizeRetailChain('بيت الجملة'), 'بيت الجملة');
      expect(ChainProductsIntelligenceService.normalizeRetailChain('Carrefour كارفور'), 'كارفور');
    });

    test('ChainProductItem computes cross-chain comparison metrics accurately', () {
      final history = [
        ProductPriceHistoryEntry(
          price: 140.0,
          receiptDate: '21/08/2026',
          receiptNumber: 'REC-001',
          storeChain: 'جملة ماركت',
        ),
        ProductPriceHistoryEntry(
          price: 130.0,
          receiptDate: '18/08/2026',
          receiptNumber: 'REC-002',
          storeChain: 'أسواق فتح الله',
        ),
        ProductPriceHistoryEntry(
          price: 150.0,
          receiptDate: '19/08/2026',
          receiptNumber: 'REC-003',
          storeChain: 'كارفور',
        ),
        ProductPriceHistoryEntry(
          price: 120.0, // older price in Fathalla
          receiptDate: '01/08/2026',
          receiptNumber: 'REC-000',
          storeChain: 'أسواق فتح الله',
        ),
      ];

      final product = ChainProductItem(
        id: '6221155611819',
        name: 'اكس اسبراى ايس شيل 150 مل',
        barcode: '6221155611819',
        companySlug: 'unilever',
        brand: 'Axe',
        category: 'مزيلات عرق',
        latestPricesByChain: {
          'جملة ماركت': 140.0,
          'أسواق فتح الله': 130.0,
          'كارفور': 150.0,
        },
        latestDatesByChain: {
          'جملة ماركت': '21/08/2026',
          'أسواق فتح الله': '18/08/2026',
          'كارفور': '19/08/2026',
        },
        priceHistory: history,
        totalScansCount: 4,
        totalQuantitySold: 4,
      );

      // Verify cross-chain intelligence
      expect(product.minPrice, 130.0);
      expect(product.cheapestChain, 'أسواق فتح الله');
      expect(product.maxPrice, 150.0);
      expect(product.mostExpensiveChain, 'كارفور');

      // Variance = ((150 - 130) / 130) * 100 = 15.38%
      expect(product.priceVariancePercent, closeTo(15.38, 0.05));

      // Fluctuations detected over time (120 vs 130 vs 140 vs 150)
      expect(product.hasPriceFluctuation, isTrue);
    });

    test('ChainProductsIntelligenceService brand and category inference works correctly', () {
      expect(ChainProductsIntelligenceService.inferBrand('اكس اسبراى بلاك 150 مل'), 'Axe');
      expect(ChainProductsIntelligenceService.inferBrand('رول اون ريكسونا انفيزبل 50 مل'), 'Rexona');
      expect(ChainProductsIntelligenceService.inferBrand('دوف هاند ووش بجوز الهند 500 مل'), 'Dove');
      expect(ChainProductsIntelligenceService.inferBrand('شامبو كلير ضد القشرة 360 مل'), 'Clear');
      expect(ChainProductsIntelligenceService.inferBrand('تريزيمي بلسم كيراتين سموث'), 'TRESemmé');

      expect(ChainProductsIntelligenceService.inferCategory('اكس اسبراى دارك تمبتيشن'), 'مزيلات عرق');
      expect(ChainProductsIntelligenceService.inferCategory('شامبو صانسيلك لمعان تألق'), 'العناية بالشعر');
      expect(ChainProductsIntelligenceService.inferCategory('صابون دوف مرطب للبشرة'), 'العناية بالجسم');
    });
  });
}
