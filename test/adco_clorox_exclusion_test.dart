import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';

void main() {
  group('AIR-79: ADCO Clorox Competitor Exclusion & Clorel Disambiguation Test', () {
    test('ExtractedProductItem.fromJson strictly marks Clorox items as isTargetCompany=false for ADCO', () {
      final cloroxItemJson = {
        'name': 'كلوركس الوان لافندر 950مل',
        'price': 129.0,
        'quantity': 1,
        'isTargetCompany': true, // Even if Gemini or POS erroneously returned true
      };

      final parsed = ExtractedProductItem.fromJson(
        cloroxItemJson,
        targetCompany: 'ادكو',
      );

      // Invariant: For ADCO, Clorox items MUST be false
      expect(parsed.isTargetCompany, isFalse);
    });

    test('ADCO genuine products like Clorel, Feba, Diva, Velveta remain isTargetCompany=true', () {
      final adcoProducts = [
        {'name': 'كلوريل مبيض ملابس 1050جم', 'price': 33.0, 'quantity': 1, 'isTargetCompany': true},
        {'name': 'فلفيتا منعم ملابس 3كجم', 'price': 169.0, 'quantity': 1, 'isTargetCompany': true},
        {'name': 'فيبا 3 كجم ارواى', 'price': 345.0, 'quantity': 1, 'isTargetCompany': true},
        {'name': 'ديفا سائل الاستحمام 2 لتر', 'price': 80.0, 'quantity': 1, 'isTargetCompany': true},
        {'name': 'ماكسيل ماجيك 500جم', 'price': 53.0, 'quantity': 1, 'isTargetCompany': true},
      ];

      for (final json in adcoProducts) {
        final parsed = ExtractedProductItem.fromJson(
          json,
          targetCompany: 'ادكو',
        );
        expect(parsed.isTargetCompany, isTrue, reason: 'Failed for ${json['name']}');
      }
    });
  });
}
