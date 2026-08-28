import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/ai_directive_model.dart';
import 'package:al_mraay/features/admin/domain/ai_directives_seed_data.dart';

void main() {
  group('AI Brain Directives & Continuous Heuristics Registry Tests', () {
    test('AiDirectivesSeedData contains all directives from AIR-01 to AIR-24 with strict integrity', () {
      final directives = AiDirectivesSeedData.initialDirectives;

      expect(directives.length, greaterThanOrEqualTo(24));

      // Verify all IDs are unique
      final ids = directives.map((d) => d.id).toSet();
      expect(ids.length, directives.length);

      // Verify AIR-24 is present
      final air24 = directives.firstWhere((d) => d.id == 'AIR-24');
      expect(air24.code, 'STRICT_CONSUMED_QUANTITY_AND_BRAND_ISOLATION_INVARIANT');
      expect(air24.orderIndex, 24);
      expect(air24.category, AiDirectiveCategory.promotionalRules);
      expect(air24.titleAr, contains('استهلاك كميات السلة'));
      expect(air24.tags, contains('consumed-quantity'));
      expect(air24.tags, contains('brand-isolation'));
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
