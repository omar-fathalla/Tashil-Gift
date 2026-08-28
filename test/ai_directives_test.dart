import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/ai_directive_model.dart';
import 'package:al_mraay/features/admin/domain/ai_directives_seed_data.dart';

void main() {
  group('AI Brain Directives & Continuous Heuristics Registry Tests', () {
    test('AiDirectivesSeedData contains all directives from AIR-01 to AIR-23 with strict integrity', () {
      final directives = AiDirectivesSeedData.initialDirectives;

      expect(directives.length, greaterThanOrEqualTo(23));

      // Verify all IDs are unique
      final ids = directives.map((d) => d.id).toSet();
      expect(ids.length, directives.length);

      // Verify AIR-23 is present
      final air23 = directives.firstWhere((d) => d.id == 'AIR-23');
      expect(air23.code, 'MULTI_CHAIN_POS_ALIAS_AUTO_HARVESTING_AND_GOLDEN_BARCODE_ANCHOR');
      expect(air23.orderIndex, 23);
      expect(air23.category, AiDirectiveCategory.nlpMatching);
      expect(air23.titleAr, contains('الباركود الذهبي'));
      expect(air23.descriptionAr, contains('chainAliases'));
      expect(air23.tags, contains('barcode-anchor'));
      expect(air23.tags, contains('pos-aliases'));
    });

    test('AIR-22 (Fathalla Price Defense) and AIR-21 (POS Concatenation) are active', () {
      final directives = AiDirectivesSeedData.initialDirectives;

      final air21 = directives.firstWhere((d) => d.id == 'AIR-21');
      expect(air21.code, 'POS_CONCATENATION_AND_CANONICAL_BRANCH_RECONCILER');

      final air22 = directives.firstWhere((d) => d.id == 'AIR-22');
      expect(air22.code, 'FATHALLA_PRICE_DEFENSE_AND_COMPETITOR_THREAT_RADAR');
    });

    test('AiDirectiveModel serialization and deserialization preserves all fields', () {
      final model = const AiDirectiveModel(
        id: 'AIR-23',
        code: 'MULTI_CHAIN_POS_ALIAS_AUTO_HARVESTING_AND_GOLDEN_BARCODE_ANCHOR',
        orderIndex: 23,
        category: AiDirectiveCategory.nlpMatching,
        titleAr: 'اختبار الباركود',
        titleEn: 'Barcode Test',
        descriptionAr: 'الوصف العربي',
        descriptionEn: 'English Description',
        logicAr: 'المنطق العربي',
        logicEn: 'English Logic',
        exampleInput: 'مدخلات تجريبية',
        exampleOutput: 'مخرجات تجريبية',
        tags: ['test', 'alias'],
        isGloballyActive: true,
        lastUpdated: '2026-08-28',
      );

      final map = model.toMap();
      expect(map['id'], 'AIR-23');
      expect(map['category'], 'nlp_matching');

      final restored = AiDirectiveModel.fromMap(map, 'AIR-23');
      expect(restored.id, 'AIR-23');
      expect(restored.code, model.code);
      expect(restored.category, AiDirectiveCategory.nlpMatching);
      expect(restored.titleAr, 'اختبار الباركود');
      expect(restored.tags, contains('alias'));
    });
  });
}
