import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/company_products_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Campaign Event Product Selection & Default Mode Tests', () {
    test('Default mode: empty requiredProducts list means all company products are included', () {
      final event = EventModel(
        id: 'event_1',
        eventName: 'حملة منتجات المراعي',
        targetCompany: 'المراعي',
        companySlug: 'almarai',
        requiredProducts: [], // Empty means all company products
        minimumSpend: 100.0,
        startDate: DateTime.now(),
        endDate: DateTime.now().add(const Duration(days: 30)),
        isActive: true,
      );

      expect(event.requiredProducts, isEmpty);
      expect(event.requiredProducts.length, 0);
    });

    test('Custom selection mode: specific requiredProducts list restricts to those products', () {
      final customSelected = ['حليب كامل الدسم 1 لتر', 'زبادي طبيعي 170 جم'];
      final event = EventModel(
        id: 'event_2',
        eventName: 'عرض مخصص',
        targetCompany: 'المراعي',
        companySlug: 'almarai',
        requiredProducts: customSelected,
        minimumSpend: 50.0,
        startDate: DateTime.now(),
        endDate: DateTime.now().add(const Duration(days: 30)),
        isActive: true,
      );

      expect(event.requiredProducts.length, 2);
      expect(event.requiredProducts, contains('حليب كامل الدسم 1 لتر'));
      expect(event.requiredProducts, contains('زبادي طبيعي 170 جم'));
    });

    test('Mapping selected product names to CompanyProductItem for table row details with barcode', () {
      final catalog = [
        CompanyProductItem(
          id: 'p1',
          companySlug: 'almarai',
          productName: 'حليب كامل الدسم 1 لتر',
          barcode: '6281007001001',
        ),
        CompanyProductItem(
          id: 'p2',
          companySlug: 'almarai',
          productName: 'زبادي طبيعي 170 جم',
          barcode: '6281007002002',
        ),
        CompanyProductItem(
          id: 'p3',
          companySlug: 'almarai',
          productName: 'عصير برتقال 1.4 لتر',
          barcode: '6281007003003',
        ),
      ];

      final selectedNames = ['زبادي طبيعي 170 جم', 'عصير برتقال 1.4 لتر'];

      final List<Map<String, String>> tableItems = [];
      for (int i = 0; i < selectedNames.length; i++) {
        final name = selectedNames[i];
        final match = catalog.where((p) => p.productName.trim() == name.trim()).firstOrNull;
        tableItems.add({
          'index': '${i + 1}',
          'name': name,
          'barcode': (match != null && match.barcode.trim().isNotEmpty) ? match.barcode : '—',
        });
      }

      expect(tableItems.length, 2);
      expect(tableItems[0]['index'], '1');
      expect(tableItems[0]['name'], 'زبادي طبيعي 170 جم');
      expect(tableItems[0]['barcode'], '6281007002002');

      expect(tableItems[1]['index'], '2');
      expect(tableItems[1]['name'], 'عصير برتقال 1.4 لتر');
      expect(tableItems[1]['barcode'], '6281007003003');
    });

    test('Manual item fallback without catalog match shows placeholder barcode', () {
      final catalog = [
        CompanyProductItem(
          id: 'p1',
          companySlug: 'almarai',
          productName: 'حليب كامل الدسم',
          barcode: '6281007001001',
        ),
      ];

      final selectedNames = ['منتج غير مسجل بالكتالوج'];

      final List<Map<String, String>> tableItems = [];
      for (int i = 0; i < selectedNames.length; i++) {
        final name = selectedNames[i];
        final match = catalog.where((p) => p.productName.trim() == name.trim()).firstOrNull;
        tableItems.add({
          'index': '${i + 1}',
          'name': name,
          'barcode': (match != null && match.barcode.trim().isNotEmpty) ? match.barcode : '—',
        });
      }

      expect(tableItems.length, 1);
      expect(tableItems[0]['barcode'], '—');
    });
  });
}
