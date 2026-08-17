import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/company_model.dart';

void main() {
  group('Company Directory & On-Demand Pagination Tests', () {
    final sampleCompanies = [
      CompanyModel(id: 'almarai', name: 'شركة المراعي', slug: 'almarai', productsCount: 854),
      CompanyModel(id: 'juhayna', name: 'شركة جهينه', slug: '2450', productsCount: 120),
      CompanyModel(id: 'lamar', name: 'شركة لمار', slug: 'lamar', productsCount: 45),
      CompanyModel(id: 'domty', name: 'شركة دومتي', slug: 'domty', productsCount: 0),
    ];

    test('Directory Mode: Calculates total products and companies correctly with zero product query', () {
      final totalCompanies = sampleCompanies.length;
      final totalProducts = sampleCompanies.fold<int>(0, (acc, c) => acc + c.productsCount);

      expect(totalCompanies, 4);
      expect(totalProducts, 1019);
    });

    test('Directory Mode: Filters companies by Arabic name and numeric company slug', () {
      final queryName = 'جهينه';
      final filteredByName = sampleCompanies.where((c) =>
          c.name.toLowerCase().contains(queryName) || c.slug.toLowerCase().contains(queryName)).toList();
      expect(filteredByName.length, 1);
      expect(filteredByName.first.id, 'juhayna');

      final queryCode = '2450';
      final filteredByCode = sampleCompanies.where((c) =>
          c.name.toLowerCase().contains(queryCode) || c.slug.toLowerCase().contains(queryCode)).toList();
      expect(filteredByCode.length, 1);
      expect(filteredByCode.first.name, 'شركة جهينه');
    });

    test('Paginated View: Handles initial 20 items limit and calculates remaining items', () {
      const initialLimit = 20;
      final totalCompanyProducts = 854; // E.g. Almarai

      final displayedCount = initialLimit.clamp(0, totalCompanyProducts);
      final hasMore = displayedCount < totalCompanyProducts;
      final remaining = totalCompanyProducts - displayedCount;
      final progressRatio = (displayedCount / totalCompanyProducts).clamp(0.0, 1.0);

      expect(displayedCount, 20);
      expect(hasMore, isTrue);
      expect(remaining, 834);
      expect(progressRatio, closeTo(20 / 854, 0.001));
    });

    test('Paginated View: Handles incrementing limit (+20) and shows all items when fully loaded', () {
      int catalogLimit = 20;
      final totalCompanyProducts = 45; // Lamar

      // Page 1
      var displayedCount = catalogLimit.clamp(0, totalCompanyProducts);
      expect(displayedCount, 20);
      expect(totalCompanyProducts - displayedCount, 25);

      // Page 2 (+20)
      catalogLimit += 20;
      displayedCount = catalogLimit.clamp(0, totalCompanyProducts);
      expect(displayedCount, 40);
      expect(totalCompanyProducts - displayedCount, 5);

      // Page 3 (+20)
      catalogLimit += 20;
      displayedCount = catalogLimit.clamp(0, totalCompanyProducts);
      expect(displayedCount, 45);
      expect(displayedCount >= totalCompanyProducts, isTrue);
      expect(totalCompanyProducts - displayedCount, 0);
    });

    test('Paginated View: Product search filters in-memory products list by barcode or name', () {
      final products = [
        CompanyProductModel(id: '1', companySlug: 'almarai', productName: 'زبادي طبيعي 170 جم', barcode: '6281007011000'),
        CompanyProductModel(id: '2', companySlug: 'almarai', productName: 'حليب كامل الدسم 1 لتر', barcode: '6281007001001'),
        CompanyProductModel(id: '3', companySlug: 'almarai', productName: 'عصير برتقال 1 لتر', barcode: '6281007002002'),
      ];

      final searchBarcode = '6281007001001';
      final filteredBarcode = products.where((p) =>
          p.productName.contains(searchBarcode) || p.barcode.contains(searchBarcode)).toList();
      expect(filteredBarcode.length, 1);
      expect(filteredBarcode.first.productName, 'حليب كامل الدسم 1 لتر');

      final searchName = 'زبادي';
      final filteredName = products.where((p) =>
          p.productName.contains(searchName) || p.barcode.contains(searchName)).toList();
      expect(filteredName.length, 1);
      expect(filteredName.first.id, '1');
    });
  });
}
