import 'dart:convert';
import 'dart:io';

import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// A target-company product that strictly belongs (barcode / name / brand) to
/// one scoped spend rule must not be counted on another scoped spend rule of
/// the same campaign through the company spend bypass. Since TAG-67 the bypass
/// is kept only on rules that cover all company products (unscoped rules or
/// rules that name the company), never on brand-scoped rules.
void main() {
  final cadburyRules = (jsonDecode(
          File('test/fixtures/cadbury_oreo_dairymilk_rules.json')
              .readAsStringSync()) as List)
      .map((e) => PromotionalRuleItem.fromMap(Map<String, dynamic>.from(e)))
      .toList();
  final oreoRule = cadburyRules.firstWhere((r) => r.id == 'rule_1');
  final oreoIdx = oreoRule.selectedProductNames
      .indexWhere((n) => n.contains('اوريو') || n.contains('أوريو'));
  final oreoName = oreoRule.selectedProductNames[oreoIdx];
  final oreoBarcode = oreoRule.selectedBarcodes[oreoIdx];
  const dmName = 'سي دي ام شوكولاته ساده 160جم';
  const dmBarcode = '7622202228353';

  ExtractedProductItem p(String name, String barcode, double price,
          {bool target = true}) =>
      ExtractedProductItem(
          name: name,
          barcode: barcode,
          quantity: 1,
          price: price,
          isTargetCompany: target);

  List<String> match(List<ExtractedProductItem> items,
          [List<PromotionalRuleItem>? rules]) =>
      PromotionalRuleMatcher.matchAllWithMultipliers(
              extractedProducts: items,
              promotionalRules: rules ?? cadburyRules)
          .map((m) => '${m.rule.id}:${m.totalRewardAmount.toInt()}')
          .toList()
        ..sort();

  group('Cadbury live rules (Oreo rule_1/2, Dairy Milk rule_3/4)', () {
    for (final withBarcode in [true, false]) {
      final bc = withBarcode ? dmBarcode : '';
      final suffix = withBarcode ? '(barcode)' : '(name only)';
      test('Dairy Milk 300 -> nothing $suffix',
          () => expect(match([p(dmName, bc, 300)]), isEmpty));
      test('Dairy Milk 350 -> rule_3 100 $suffix',
          () => expect(match([p(dmName, bc, 350)]), ['rule_3:100']));
      test('Dairy Milk 500 -> rule_4 150 only $suffix',
          () => expect(match([p(dmName, bc, 500)]), ['rule_4:150']));
    }
    test('Oreo 350 -> Oreo rule_2 100',
        () => expect(match([p(oreoName, oreoBarcode, 350)]), ['rule_2:100']));
    test('Oreo 350 + Dairy Milk 350 -> rule_2 100 and rule_3 100', () {
      expect(
          match([p(oreoName, oreoBarcode, 350), p(dmName, dmBarcode, 350)]),
          ['rule_2:100', 'rule_3:100']);
    });
    test(
        'company product matching no rule strictly is not counted on '
        'brand-scoped rules (TAG-67)', () {
      // These rules are scoped to Oreo / Dairy Milk. A company-flagged product
      // that matches none of them strictly must not earn their gifts, the
      // same way other Unilever products were leaking into Knorr's rules.
      expect(match([p('منتج عام 1 كجم', '', 600)]), isEmpty);
    });
  });

  group('Unscoped spend rule (no barcodes / names / brands)', () {
    final unscoped = PromotionalRuleItem.fromMap({
      'id': 'u1',
      'ruleTitle': 'اشتري ب 200 جنيه واحصل على هدية',
      'triggerProduct': '',
      'conditionType': 'by_spend',
      'minSpend': 200,
      'rewardType': 'voucher',
      'rewardValue': 'فوتشر 50',
      'rewardAmount': 50,
    });
    test('still accepts any target-company product (bypass kept)', () {
      expect(match([p('منتج عام 1 كجم', '', 250)], [unscoped]), ['u1:50']);
    });
    test('other-company product is rejected (multi-tenant isolation guard)',
        () {
      // Documented current design: a product with isTargetCompany == false
      // only counts when explicitly selected by barcode/name, so an unscoped
      // rule never accepts it.
      expect(
          match([p('منتج منافس 1 كجم', '', 250, target: false)], [unscoped]),
          isEmpty);
    });
  });
}
