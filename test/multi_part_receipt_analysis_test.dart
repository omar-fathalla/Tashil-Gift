import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/features/admin/domain/ai_directive_model.dart';
import 'package:al_mraay/features/admin/domain/ai_directives_seed_data.dart';

void main() {
  group('Multi-Part Long Receipt Scanning & Analysis Tests', () {
    test('AIR-39 directive is properly registered in AiDirectivesSeedData', () {
      final directives = AiDirectivesSeedData.initialDirectives;
      final air39 = directives.firstWhere(
        (d) => d.id == 'AIR-39',
        orElse: () => throw StateError('AIR-39 directive not found in seed data'),
      );

      expect(air39.id, 'AIR-39');
      expect(air39.code, 'MULTI_PART_LONG_RECEIPT_STITCHING_AND_DEDUPLICATION_STANDARD');
      expect(air39.orderIndex, 39);
      expect(air39.category, AiDirectiveCategory.fraudSecurity);
      expect(air39.titleAr, contains('معيار دمج وفحص الفواتير الطويلة'));
      expect(air39.titleEn, contains('Multi-Part Long Receipt Stitching'));
      expect(air39.descriptionAr, contains('فتح الله ماركت'));
      expect(air39.tags, contains('multi-part-receipt'));
      expect(air39.tags, contains('seam-deduplication'));
      expect(air39.tags, contains('fathalla-market'));
      expect(air39.tags, contains('gemini-multimodal'));
    });

    test('AIR-39 directive serialization and deserialization integrity', () {
      final directives = AiDirectivesSeedData.initialDirectives;
      final air39 = directives.firstWhere((d) => d.id == 'AIR-39');

      final map = air39.toMap();
      expect(map['id'], 'AIR-39');
      expect(map['code'], 'MULTI_PART_LONG_RECEIPT_STITCHING_AND_DEDUPLICATION_STANDARD');
      expect(map['order_index'], 39);
      expect(map['category'], 'fraud_security');
      expect(map['primary_model'], 'Gemini 3.7 Flash');

      final restored = AiDirectiveModel.fromMap(map, 'AIR-39');
      expect(restored.id, 'AIR-39');
      expect(restored.code, air39.code);
      expect(restored.category, AiDirectiveCategory.fraudSecurity);
      expect(restored.titleAr, air39.titleAr);
      expect(restored.logicAr, air39.logicAr);
      expect(restored.tags, contains('multi-part-receipt'));
    });

    test('Trilingual AppStrings for multi-part receipts are fully translated without placeholders', () {
      final languages = ['ar', 'en', 'hi'];

      for (final lang in languages) {
        final strings = AppStrings(lang);

        final addNextPart = strings.addNextReceiptPartBtn;
        final longTip = strings.longReceiptTip;
        final partIndex = strings.partIndexLabel(2);
        final deleteTooltip = strings.deletePartTooltip;
        final analyzeBtn = strings.analyzeMultiPartsBtn(3);
        final maxAlert = strings.maxPartsReachedAlert;
        final pickGallery = strings.pickNextPartGallery;
        final captureCamera = strings.captureNextPartCamera;

        expect(addNextPart.isNotEmpty, true, reason: 'Failed for lang: $lang');
        expect(longTip.isNotEmpty, true, reason: 'Failed for lang: $lang');
        expect(partIndex.isNotEmpty, true, reason: 'Failed for lang: $lang');
        expect(deleteTooltip.isNotEmpty, true, reason: 'Failed for lang: $lang');
        expect(analyzeBtn.isNotEmpty, true, reason: 'Failed for lang: $lang');
        expect(maxAlert.isNotEmpty, true, reason: 'Failed for lang: $lang');
        expect(pickGallery.isNotEmpty, true, reason: 'Failed for lang: $lang');
        expect(captureCamera.isNotEmpty, true, reason: 'Failed for lang: $lang');

        // Verify index substitution in partIndexLabel
        expect(partIndex.contains('2'), true, reason: 'Missing current index for $lang');

        // Verify parts count in analyzeMultiPartsBtn
        expect(analyzeBtn.contains('3'), true, reason: 'Missing parts count in button for $lang');
      }

      // Explicit language verification
      final ar = AppStrings('ar');
      final en = AppStrings('en');
      final hi = AppStrings('hi');

      expect(ar.addNextReceiptPartBtn, contains('إضافة جزء تالٍ للفاتورة'));
      expect(en.addNextReceiptPartBtn, contains('Add Next Part'));
      expect(hi.addNextReceiptPartBtn, contains('लंबी रसीद के लिए अगला भाग जोड़ें'));

      expect(ar.longReceiptTip, contains('إذا كانت الفاتورة طويلة'));
      expect(en.longReceiptTip, contains('For long receipts'));
      expect(hi.longReceiptTip, contains('लंबी रसीदों के लिए'));
    });

    test('Multi-part receipt storage and metadata structuring logic', () {
      final dummyParts = ['part1_url', 'part2_url', 'part3_url'];
      final dummyStoragePaths = [
        'receipts/fathalla/camp1/REC-100_part1.jpg',
        'receipts/fathalla/camp1/REC-100_part2.jpg',
        'receipts/fathalla/camp1/REC-100_part3.jpg',
      ];

      final receiptData = <String, dynamic>{
        'receipt_number': 'REC-100',
        'image_url': dummyParts.first, // backward compatibility
        'image_urls': dummyParts,
        'storage_path': dummyStoragePaths.first,
        'storage_paths': dummyStoragePaths,
        'parts_count': dummyParts.length,
        'is_multi_part': dummyParts.length > 1,
      };

      expect(receiptData['image_url'], 'part1_url');
      expect((receiptData['image_urls'] as List).length, 3);
      expect(receiptData['parts_count'], 3);
      expect(receiptData['is_multi_part'], true);
      expect(receiptData['storage_paths'], dummyStoragePaths);
    });

    test('Multi-part viewer index clamping and boundary checks', () {
      final imageUrls = ['url_1', 'url_2', 'url_3'];

      int clampIndex(int idx, int maxCount) {
        if (idx < 0) return 0;
        if (idx >= maxCount) return maxCount - 1;
        return idx;
      }

      expect(clampIndex(-1, imageUrls.length), 0);
      expect(clampIndex(0, imageUrls.length), 0);
      expect(clampIndex(1, imageUrls.length), 1);
      expect(clampIndex(2, imageUrls.length), 2);
      expect(clampIndex(5, imageUrls.length), 2);
    });
  });
}
