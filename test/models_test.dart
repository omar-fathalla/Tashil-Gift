import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/admin/domain/company_model.dart';

void main() {
  group('EventModel Tests', () {
    test('Should create and serialize EventModel correctly', () {
      final now = DateTime(2026, 8, 13);
      final event = EventModel(
        id: 'event_123',
        eventName: 'حملة العودة للمدارس',
        targetCompany: 'شركة المراعي',
        companySlug: 'almarai',
        minimumSpend: 50.0,
        welcomeTitle: 'أهلاً بكم في مهرجان المراعي',
        welcomeMessage: 'اربح جوائز فورية عند الشراء',
        startDate: now,
        endDate: now.add(const Duration(days: 7)),
        isActive: true,
      );

      expect(event.id, 'event_123');
      expect(event.eventName, 'حملة العودة للمدارس');
      expect(event.targetCompany, 'شركة المراعي');
      expect(event.minimumSpend, 50.0);
      expect(event.isActive, true);

      final firestoreData = event.toFirestore();
      expect(firestoreData['eventName'], 'حملة العودة للمدارس');
      expect(firestoreData['targetCompany'], 'شركة المراعي');
      expect(firestoreData['minimumSpend'], 50.0);
      expect(firestoreData['isActive'], true);
    });

    test('Should properly serialize and deserialize requiredProducts for targeted product campaigns', () {
      final targetProducts = [
        'زبادي سادة 170 جم',
        'حليب كامل الدسم 1 لتر',
        'جبنة مثلثات 8 قطع',
        'عصير برتقال 1 لتر',
      ];

      final event = EventModel(
        id: 'event_subset_10',
        eventName: 'عرض 4 منتجات محددة فقط من المراعي',
        targetCompany: 'شركة المراعي',
        companySlug: 'almarai',
        minimumSpend: 80.0,
        requiredProducts: targetProducts,
      );

      expect(event.requiredProducts.length, 4);
      expect(event.requiredProducts, contains('زبادي سادة 170 جم'));
      expect(event.requiredProducts, contains('عصير برتقال 1 لتر'));

      final firestoreMap = event.toFirestore();
      expect(firestoreMap['requiredProducts'], targetProducts);
      expect((firestoreMap['requiredProducts'] as List).length, 4);
    });

    test('Should properly serialize and deserialize branch-specific allocated prizes', () {
      final prizes = [
        AllocatedPrize(
          giftId: 'gift_umbrella_01',
          name: 'شمسية شاطئ فاخرة',
          allocatedQuantity: 15,
          remainingQuantity: 12,
          branchId: 'branch_seyouf',
          branchName: 'فرع السيوف (الإسكندرية)',
        ),
        AllocatedPrize(
          giftId: 'gift_mug_02',
          name: 'مج حراري ستانلس',
          allocatedQuantity: 20,
          remainingQuantity: 20,
          branchId: 'branch_smouha',
          branchName: 'فرع سموحة (الإسكندرية)',
        ),
      ];

      final event = EventModel(
        id: 'event_branches_99',
        eventName: 'عروض المراعي بالإسكندرية',
        targetCompany: 'شركة المراعي',
        companySlug: 'almarai',
        minimumSpend: 100.0,
        retailChainId: 'chain_fathalla',
        retailChainName: 'أسواق فتح الله للجملة',
        isAllBranches: false,
        branchIds: ['branch_seyouf', 'branch_smouha'],
        branchNames: ['فرع السيوف', 'فرع سموحة'],
        allocatedPrizes: prizes,
      );

      final map = event.toFirestore();
      expect(map['retailChainId'], 'chain_fathalla');
      expect(map['isAllBranches'], false);
      expect((map['branchIds'] as List).length, 2);

      final prizeList = map['allocatedPrizes'] as List<dynamic>;
      expect(prizeList.length, 2);
      expect(prizeList[0]['branchId'], 'branch_seyouf');
      expect(prizeList[0]['branchName'], 'فرع السيوف (الإسكندرية)');
      expect(prizeList[1]['branchId'], 'branch_smouha');

      // Test deserialization from map
      final p1 = AllocatedPrize.fromMap(prizeList[0] as Map<String, dynamic>);
      expect(p1.giftId, 'gift_umbrella_01');
      expect(p1.name, 'شمسية شاطئ فاخرة');
      expect(p1.branchId, 'branch_seyouf');
      expect(p1.branchName, 'فرع السيوف (الإسكندرية)');
    });

    test('Should properly calculate chances earned and handle multiple chances multipliers', () {
      final eventSingleChance = EventModel(
        id: 'event_single',
        eventName: 'حملة بدون مضاعفة',
        targetCompany: 'شركة المراعي',
        minimumSpend: 300.0,
        allowMultipleChances: false,
      );

      // Single chance campaign always returns 1 when spend meets minimum
      expect(eventSingleChance.calculateChancesEarned(200.0), 0);
      expect(eventSingleChance.calculateChancesEarned(300.0), 1);
      expect(eventSingleChance.calculateChancesEarned(600.0), 1);
      expect(eventSingleChance.calculateChancesEarned(1200.0), 1);

      final eventMultiChances = EventModel(
        id: 'event_multi',
        eventName: 'حملة مضاعفة الفرص',
        targetCompany: 'شركة المراعي',
        minimumSpend: 300.0,
        allowMultipleChances: true,
      );

      // Multiple chances campaign calculates floor multiplier
      expect(eventMultiChances.calculateChancesEarned(150.0), 0);
      expect(eventMultiChances.calculateChancesEarned(300.0), 1);
      expect(eventMultiChances.calculateChancesEarned(599.0), 1);
      expect(eventMultiChances.calculateChancesEarned(600.0), 2);
      expect(eventMultiChances.calculateChancesEarned(899.0), 2);
      expect(eventMultiChances.calculateChancesEarned(900.0), 3);
      expect(eventMultiChances.calculateChancesEarned(1500.0), 5);

      final eventCappedChances = EventModel(
        id: 'event_capped',
        eventName: 'حملة بحد أقصى 3 فرص',
        targetCompany: 'شركة المراعي',
        minimumSpend: 200.0,
        allowMultipleChances: true,
        maxChancesPerReceipt: 3,
      );

      // Capped at 3 chances
      expect(eventCappedChances.calculateChancesEarned(200.0), 1);
      expect(eventCappedChances.calculateChancesEarned(400.0), 2);
      expect(eventCappedChances.calculateChancesEarned(600.0), 3);
      expect(eventCappedChances.calculateChancesEarned(1000.0), 3);
      expect(eventCappedChances.calculateChancesEarned(2000.0), 3);

      final map = eventMultiChances.toFirestore();
      expect(map['allowMultipleChances'], true);
      expect(map['maxChancesPerReceipt'], 0);
    });

    test('AllocatedPrize.fromMap should safely parse null, int, double values', () {
      final pNull = AllocatedPrize.fromMap({});
      expect(pNull.allocatedQuantity, 0);
      expect(pNull.remainingQuantity, 0);

      final pDouble = AllocatedPrize.fromMap({
        'allocatedQuantity': 15.0,
        'remainingQuantity': 12.0,
      });
      expect(pDouble.allocatedQuantity, 15);
      expect(pDouble.remainingQuantity, 12);
    });
  });

  group('CompanyModel & CompanyProductModel Tests', () {
    test('Should handle CompanyModel serialization', () {
      final company = CompanyModel(
        id: 'almarai',
        name: 'شركة المراعي',
        slug: 'almarai',
        productsCount: 12,
      );

      expect(company.id, 'almarai');
      expect(company.name, 'شركة المراعي');
      expect(company.slug, 'almarai');
      expect(company.productsCount, 12);

      final map = company.toFirestore();
      expect(map['name'], 'شركة المراعي');
      expect(map['slug'], 'almarai');
      expect(map['productsCount'], 12);
    });

    test('Should handle CompanyProductModel serialization', () {
      final product = CompanyProductModel(
        id: 'prod_99',
        companySlug: 'almarai',
        companyName: 'شركة المراعي',
        productName: 'حليب كامل الدسم 1 لتر',
        barcode: '6281007001001',
      );

      expect(product.id, 'prod_99');
      expect(product.productName, 'حليب كامل الدسم 1 لتر');
      expect(product.barcode, '6281007001001');

      final map = product.toFirestore();
      expect(map['companySlug'], 'almarai');
      expect(map['companyName'], 'شركة المراعي');
      expect(map['productName'], 'حليب كامل الدسم 1 لتر');
      expect(map['barcode'], '6281007001001');
    });

    test('Should handle numeric company codes correctly (e.g., 2450)', () {
      final company = CompanyModel(
        id: '2450',
        name: 'شركة جهينة',
        slug: '2450',
        productsCount: 5,
      );

      expect(company.id, '2450');
      expect(company.slug, '2450');

      final product = CompanyProductModel(
        id: 'prod_2450_1',
        companySlug: '2450',
        companyName: 'شركة جهينة',
        productName: 'حليب جهينة 1 لتر',
        barcode: '6221001002003',
      );

      expect(product.companySlug, '2450');
      expect(product.companyName, 'شركة جهينة');
    });
  });
}
