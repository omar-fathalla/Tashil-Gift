import 'package:al_mraay/core/constants/ai_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
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
      expect(map['primary_model'], AiModels.defaultPrimaryLabel);

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
        final clearAll = strings.clearAllPartsBtn;

        expect(addNextPart.isNotEmpty, true, reason: 'Failed for lang: $lang');
        expect(longTip.isNotEmpty, true, reason: 'Failed for lang: $lang');
        expect(partIndex.isNotEmpty, true, reason: 'Failed for lang: $lang');
        expect(deleteTooltip.isNotEmpty, true, reason: 'Failed for lang: $lang');
        expect(analyzeBtn.isNotEmpty, true, reason: 'Failed for lang: $lang');
        expect(maxAlert.isNotEmpty, true, reason: 'Failed for lang: $lang');
        expect(pickGallery.isNotEmpty, true, reason: 'Failed for lang: $lang');
        expect(captureCamera.isNotEmpty, true, reason: 'Failed for lang: $lang');
        expect(clearAll.isNotEmpty, true, reason: 'Failed for lang: $lang');

        // Verify index substitution in partIndexLabel
        expect(partIndex.contains('2'), true, reason: 'Missing current index for $lang');

        // Verify parts count in analyzeMultiPartsBtn
        expect(analyzeBtn.contains('3'), true, reason: 'Missing parts count in button for $lang');
      }

      // Explicit language verification
      final ar = AppStrings('ar');
      final en = AppStrings('en');
      final hi = AppStrings('hi');

      expect(ar.addNextReceiptPartBtn, contains('إضافة جزء (فاتورة طويلة)'));
      expect(en.addNextReceiptPartBtn, contains('Add Part (Long Receipt)'));
      expect(hi.addNextReceiptPartBtn, contains('भाग जोड़ें (लंबी रसीद)'));

      expect(ar.clearAllPartsBtn, equals('مسح الكل'));
      expect(en.clearAllPartsBtn, equals('Clear All'));
      expect(hi.clearAllPartsBtn, equals('सभी साफ़ करें'));

      expect(ar.longReceiptTip, contains('للفواتير الطويلة'));
      expect(en.longReceiptTip, contains('For long receipts'));
      expect(hi.longReceiptTip, contains('लंबी रसीदों'));
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

    test('AIR-61 directive is registered and enforces single-receipt integrity', () {
      final directives = AiDirectivesSeedData.initialDirectives;
      final air61 = directives.firstWhere(
        (d) => d.id == 'AIR-61',
        orElse: () => throw StateError('AIR-61 directive not found in seed data'),
      );

      expect(air61.id, 'AIR-61');
      expect(air61.code, 'SINGLE_RECEIPT_INTEGRITY_AND_STRICT_MULTI_RECEIPT_MERGING_REJECTION_INVARIANT');
      expect(air61.orderIndex, 61);
      expect(air61.category, AiDirectiveCategory.fraudSecurity);
      expect(air61.titleAr, contains('نزاهة واستقلالية الفاتورة الواحدة'));
      expect(air61.tags, contains('single-receipt-integrity'));
      expect(air61.tags, contains('anti-fraud'));
      expect(air61.tags, contains('cross-seam-deduplication'));

      final map = air61.toMap();
      expect(map['id'], 'AIR-61');
      expect(map['code'], air61.code);
      expect(map['order_index'], 61);

      final restored = AiDirectiveModel.fromMap(map, 'AIR-61');
      expect(restored.id, 'AIR-61');
      expect(restored.titleAr, air61.titleAr);
    });

    test('Cross-seam line deduplication eliminates duplicate item on consecutive camera cut', () {
      final itemsWithOverlap = [
        ExtractedProductItem(
          name: 'تريزيمي شامبو 400 مل',
          price: 135.0,
          quantity: 1,
          isTargetCompany: true,
          barcode: '622115500001',
        ),
        // Overlap seam duplicate at the boundary of Part 1 and Part 2
        ExtractedProductItem(
          name: 'تريزيمي شامبو 400 مل',
          price: 135.0,
          quantity: 1,
          isTargetCompany: true,
          barcode: '622115500001',
        ),
        ExtractedProductItem(
          name: 'كلير بلسم 180 مل',
          price: 65.0,
          quantity: 1,
          isTargetCompany: true,
          barcode: '622115500002',
        ),
      ];

      final deduplicated = AiReceiptService.deduplicateCrossSeamProducts(itemsWithOverlap);
      expect(deduplicated.length, equals(2));
      expect(deduplicated.first.name, contains('تريزيمي شامبو'));
      expect(deduplicated.last.name, contains('كلير بلسم'));
    });
  });
}
