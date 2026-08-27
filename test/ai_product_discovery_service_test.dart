import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_product_discovery_service.dart';

void main() {
  group('AI Product Discovery Service & Model Tests', () {
    test('DiscoveredProductDocument serialization, deserialization, and copyWith', () {
      final doc = DiscoveredProductDocument(
        id: 'unilever_6221155612168',
        companySlug: 'unilever',
        companyName: 'يونيليفر',
        rawProductName: 'تريزيمى شامبو + بلسم 400 ملى لشعر املس ك',
        canonicalName: 'تريزيمي شامبو وبلسم 400 مل',
        brand: 'تريزيمي',
        category: 'العناية بالشعر',
        unitSize: '400 مل',
        barcode: '6221155612168',
        averagePrice: 299.0,
        retailChains: ['أسواق فتح الله'],
        invoiceFrequency: 3,
        status: 'pending',
        confidenceScore: 0.98,
        relevanceReason: 'تم رصده في فواتير معتمدة لشركة يونيليفر',
      );

      final map = doc.toMap();
      expect(map['companySlug'], 'unilever');
      expect(map['barcode'], '6221155612168');
      expect(map['brand'], 'تريزيمي');
      expect(map['category'], 'العناية بالشعر');
      expect(map['averagePrice'], 299.0);
      expect(map['invoiceFrequency'], 3);
      expect(map['status'], 'pending');

      final updated = doc.copyWith(
        canonicalName: 'تريزيمي شامبو 400 مل كيراتين سموث',
        status: 'approved',
        averagePrice: 310.0,
      );

      expect(updated.canonicalName, 'تريزيمي شامبو 400 مل كيراتين سموث');
      expect(updated.status, 'approved');
      expect(updated.averagePrice, 310.0);
      expect(updated.barcode, '6221155612168');
    });

    test('DiscoveredProductItem legacy compatibility model', () {
      final item = DiscoveredProductItem(
        productName: 'اكس اسبراى 150مل',
        barcode: '6221155001234',
        category: 'مزيلات العرق',
        unitSize: '150 مل',
        referencePrice: 135.0,
        invoiceFrequency: 5,
        relevanceReason: 'تم رصده في فواتير',
        confidence: 'high',
        isSelected: true,
      );

      expect(item.productName, 'اكس اسبراى 150مل');
      expect(item.barcode, '6221155001234');
      expect(item.referencePrice, 135.0);
      expect(item.isSelected, true);
    });
  });
}
