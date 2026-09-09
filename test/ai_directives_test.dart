import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/ai_directive_model.dart';
import 'package:al_mraay/features/admin/domain/ai_directives_seed_data.dart';

void main() {
  group('AI Brain Directives & Continuous Heuristics Registry Tests', () {
    test('AiDirectivesSeedData contains all directives from AIR-01 to AIR-29 with strict integrity', () {
      final directives = AiDirectivesSeedData.initialDirectives;

      expect(directives.length, greaterThanOrEqualTo(29));

      // Verify all IDs are unique
      final ids = directives.map((d) => d.id).toSet();
      expect(ids.length, directives.length);

      // Verify AIR-27 is present
      final air27 = directives.firstWhere((d) => d.id == 'AIR-27');
      expect(air27.code, 'POS_TRUNCATED_BRAND_NORMALIZATION_AND_BIDIRECTIONAL_CATALOG_BARCODE_ENRICHMENT');
      expect(air27.orderIndex, 27);
      expect(air27.category, AiDirectiveCategory.promotionalRules);
      expect(air27.titleAr, contains('معالجة الحروف المقطوعة'));
      expect(air27.tags, contains('axe-pos-clipping'));
      expect(air27.tags, contains('barcode-catalog-enrichment'));

      // Verify AIR-28 is present
      final air28 = directives.firstWhere((d) => d.id == 'AIR-28');
      expect(air28.code, 'HIGH_CONFIDENCE_AUTO_CATALOG_ENRICHMENT_WITH_PROMOTIONAL_GOVERNANCE');
      expect(air28.orderIndex, 28);
      expect(air28.category, AiDirectiveCategory.nlpMatching);
      expect(air28.titleAr, contains('الحقن التلقائي الذكي للأصناف'));
      expect(air28.tags, contains('auto-catalog-injection'));
      expect(air28.tags, contains('promotional-governance'));

      // Verify AIR-29 is present
      final air29 = directives.firstWhere((d) => d.id == 'AIR-29');
      expect(air29.code, 'DUAL_COLUMN_POS_UNIT_PRICE_GOVERNANCE_AND_REVERSE_DOUBLE_DIVISION_HEALING');
      expect(air29.orderIndex, 29);
      expect(air29.category, AiDirectiveCategory.unitEconomics);
      expect(air29.titleAr, contains('أعمدة الكاشير المزدوجة'));
      expect(air29.tags, contains('gomla-market'));
      expect(air29.tags, contains('dual-column-pos'));

      // Verify AIR-37 is present
      final air37 = directives.firstWhere((d) => d.id == 'AIR-37');
      expect(air37.code, 'PHYSICAL_PACK_PIECE_COUNT_VS_MONETARY_SPEND_ISOLATION_STANDARD');
      expect(air37.orderIndex, 37);
      expect(air37.category, AiDirectiveCategory.promotionalRules);
      expect(air37.titleAr, contains('الفصل الصارم بين حصر القطع الفيزيائية'));
      expect(air37.tags, contains('multiplier-isolation'));

      // Verify AIR-40 is present
      final air40 = directives.firstWhere((d) => d.id == 'AIR-40');
      expect(air40.code, 'PROMOTIONAL_RULE_CONDITION_TYPE_INTEGRITY_AND_SPEND_SANITATION_STANDARD');
      expect(air40.orderIndex, 40);
      expect(air40.category, AiDirectiveCategory.promotionalRules);
      expect(air40.titleAr, contains('معيار الفصل الصارم لشروط العروض بين الكميات والإنفاق المالي'));
      expect(air40.tags, contains('quantity-vs-spend'));
      expect(air40.tags, contains('min-spend-sanitation'));

      // Verify AIR-41 is present
      final air41 = directives.firstWhere((d) => d.id == 'AIR-41');
      expect(air41.code, 'RETAIL_CHAIN_CANONICAL_GOVERNORATE_GROUPING_AND_PHONETIC_BRANCH_SEARCH_STANDARD');
      expect(air41.orderIndex, 41);
      expect(air41.category, AiDirectiveCategory.branchGovernance);
      expect(air41.titleAr, contains('معيار التجميع الجغرافي لفروع السلاسل بالمحافظات'));
      expect(air41.tags, contains('retail-chains'));
      expect(air41.tags, contains('governorate-grouping'));
      expect(air41.tags, contains('branch-search'));
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
