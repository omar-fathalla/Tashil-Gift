// TAG-85: a Unilever receipt (Fathalla Badr, 202/7/272/271126, 1,496 EGP of
// Unilever lines) was paid 3 x 50 EGP instead of 2 x 200 EGP. rule_1
// («300 -> 50, from the following items only») has its own 250-barcode list,
// none of the receipt's barcodes is on it, but its brand words (شامبو, صابون,
// كلوس ...) matched every line by name, so rule_1 took the whole receipt before
// the 200 / 400 / 700 ladder (rule_2/3/4, another barcode list) could count it.
//
// A spend rule scoped to its own barcode list must not count a line whose
// barcode belongs to another spend rule of the campaign. Lines with no barcode,
// or with a barcode no rule lists, keep the name / brand match.
import 'dart:convert';
import 'dart:io';

import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:flutter_test/flutter_test.dart';

final Map<String, dynamic> fx = jsonDecode(
  File('test/fixtures/tag85_unilever_rule_scope.json').readAsStringSync(),
) as Map<String, dynamic>;

List<PromotionalRuleItem> unileverRules() => [
      for (final raw in (fx['rules'] as List))
        PromotionalRuleItem.fromMap({
          ...Map<String, dynamic>.from(raw as Map),
          if (raw['selectedBarcodes'] == r'$ladder') 'selectedBarcodes': fx['ladderBarcodes'],
        }),
    ];

List<ExtractedProductItem> receiptLines() => [
      for (final p in (fx['receipt']['products'] as List))
        ExtractedProductItem.fromJson(Map<String, dynamic>.from(p as Map)),
    ];

AiReceiptAnalysisResult resultOf(List<ExtractedProductItem> products, {double? total}) =>
    AiReceiptAnalysisResult(
      isValid: true,
      receiptNumber: '202/7/272/271126',
      targetCompanyTotal: total ??
          products.where((p) => p.isTargetCompany).fold<double>(0, (s, p) => s + p.actualLineSpend),
      receiptDate: '2026-11-27',
      extractedProducts: products,
      message: '',
    );

List<MatchedPromotionalRuleResult> match(
  List<ExtractedProductItem> products,
  List<PromotionalRuleItem> rules, {
  int maxUnits = 3,
  double? total,
}) =>
    PromotionalRuleMatcher.matchAllWithMultipliers(
      result: resultOf(products, total: total),
      promotionalRules: rules,
      allowCampaignMultipliers: true,
      maxUnitsPerReceipt: maxUnits,
      spendLadderMode: 'exclusive',
    );

Map<String, int> unitsByRule(List<MatchedPromotionalRuleResult> m) =>
    {for (final r in m) r.rule.id: r.multiplier};

int vouchers(List<MatchedPromotionalRuleResult> m) => m.fold<int>(
    0, (s, r) => s + (r.rule.rewardAmount * r.multiplier).round());

ExtractedProductItem line(String name, String barcode, double price,
        {int qty = 1, bool target = true}) =>
    ExtractedProductItem(
      name: name,
      barcode: barcode,
      quantity: qty,
      price: price,
      isTargetCompany: target,
    );

void main() {
  final rules = unileverRules();
  final r1 = rules.firstWhere((r) => r.id == 'rule_1');
  final ladderBarcodes = (fx['ladderBarcodes'] as List).cast<String>();

  group('fixture shape (live Unilever rules)', () {
    test('rule_1 has its own barcode list, rule_2/3/4 share another', () {
      expect(r1.selectedBarcodes.toSet().intersection(ladderBarcodes.toSet()), isEmpty);
      expect(PromotionalRuleMatcher.isBarcodeScopedSpendRule(r1), isTrue);
      for (final id in ['rule_2', 'rule_3', 'rule_4']) {
        final r = rules.firstWhere((x) => x.id == id);
        expect(PromotionalRuleMatcher.isBarcodeScopedSpendRule(r), isFalse, reason: id);
        expect(r.selectedBarcodes.toSet(), ladderBarcodes.toSet());
      }
    });
    test('none of the 8 receipt lines is in rule_1 list; 7 are in the ladder list', () {
      final lines = receiptLines();
      expect(lines, hasLength(8));
      expect(lines.where((l) => r1.selectedBarcodes.contains(l.barcode)), isEmpty);
      expect(lines.where((l) => ladderBarcodes.contains(l.barcode)), hasLength(7));
      // Close-Up 100 ml is on no rule list (catalog gap, name match still counts).
      expect(ladderBarcodes.contains('6221155610669'), isFalse);
    });
  });

  group('receipt 202/7/272/271126 (1,496 EGP)', () {
    for (final cap in [3, 12]) {
      test('rule_1 gets nothing and the ladder pays 2 x 200 (cap $cap)', () {
        final m = match(receiptLines(), rules, maxUnits: cap, total: 1496);
        expect(unitsByRule(m), {'rule_4': 2});
        expect(vouchers(m), 400);
        expect(m.single.qualifyingSpend, closeTo(1496, 0.01));
      });
    }
    test('without the Close-Up line the ladder pays 200 + 100', () {
      final lines = receiptLines().where((l) => l.barcode != '6221155610669').toList();
      final m = match(lines, rules, total: 1277);
      expect(unitsByRule(m), {'rule_4': 1, 'rule_3': 1});
      expect(vouchers(m), 300);
    });
  });

  group('rule_1 still counts its own items', () {
    final a = r1.selectedBarcodes[0];
    final b = r1.selectedBarcodes[1];

    test('two lines on the rule_1 list reaching 300 -> 1 x 50 from rule_1', () {
      final m = match([line('اكس اسبراي', a, 160), line('لوكس شاور جيل', b, 160)], rules);
      expect(unitsByRule(m), {'rule_1': 1});
      expect(vouchers(m), 50);
    });

    test('rule_1 items plus ladder items: each rule only counts its own lines', () {
      final ladderLine = receiptLines().firstWhere((l) => l.barcode == '6221155200716');
      final m = match([
        line('اكس اسبراي', a, 160),
        line('لوكس شاور جيل', b, 160),
        line(ladderLine.name, ladderLine.barcode, 450),
      ], rules);
      final byRule = {for (final r in m) r.rule.id: r};
      expect(byRule['rule_1']!.qualifyingSpend, closeTo(320, 0.01));
      expect(byRule.keys.toSet(), {'rule_1', 'rule_3'});
      expect(byRule['rule_3']!.qualifyingSpend, closeTo(450, 0.01));
      expect(vouchers(m), 150);
    });

    test('ladder lines alone, even with rule_1 brand words, give rule_1 nothing', () {
      final m = match([line('صانسيلك شامبو 600 مل', '6221155611086', 1000)], rules);
      // 700 tier + 300 remainder -> rule_2; never rule_1.
      expect(unitsByRule(m), {'rule_4': 1, 'rule_2': 1});
    });

    test('matchesProduct without sibling rules cannot compare lists and keeps the old answer', () {
      final p = line('صانسيلك شامبو 600 مل', '6221155611086', 300);
      expect(PromotionalRuleMatcher.matchesProduct(p, r1.triggerProduct, r1), isTrue,
          reason: 'standalone call has no sibling rules to compare with');
    });
  });

  group('name match is kept where no rule claims the line', () {
    test('barcode no rule lists: still counts through the brand name', () {
      final m = match([line('كلوس اب معجون اسنان', '6221155610669', 320)], rules);
      expect(m, isNotEmpty);
      expect(vouchers(m), greaterThanOrEqualTo(50));
    });
    test('no readable barcode: still counts through the brand name', () {
      final m = match([line('صانسيلك شامبو 600 مل', '', 420)], rules);
      expect(m, isNotEmpty);
    });
    test('unscoped / company-wide rules are untouched', () {
      final u = PromotionalRuleItem.fromMap({
        'id': 'u1',
        'ruleTitle': 'اشتري ب 200 جنيه',
        'triggerProduct': '',
        'conditionType': 'by_spend',
        'minSpend': 200,
        'rewardType': 'voucher',
        'rewardValue': 'فوتشر 50',
        'rewardAmount': 50,
      });
      expect(PromotionalRuleMatcher.isBarcodeScopedSpendRule(u), isFalse);
      expect(unitsByRule(match([line('منتج', '', 250)], [u])), {'u1': 1});
    });
  });

  group('Knorr ladder regression (TAG-78 / TAG-67 behaviour unchanged)', () {
    final knorrFx = jsonDecode(
      File('test/fixtures/tag67_knorr_unilever_receipts.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final knorr = [
      for (final r in (knorrFx['knorr']['rules'] as List))
        PromotionalRuleItem.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
    List<ExtractedProductItem> knorrLines(String id) => [
          for (final p in (knorrFx['receipts'][id]['products'] as List))
            ExtractedProductItem.fromJson(Map<String, dynamic>.from(p as Map)),
        ];

    test('207/9: 168 EGP of Knorr + a Dove spray is still 2 x 25 from rule_1', () {
      final m = match(knorrLines('207/9/413/251126'), knorr);
      expect(unitsByRule(m), {'rule_1': 2});
      expect(m.single.qualifyingSpend, closeTo(168, 0.01));
      expect(vouchers(m), 50);
    });
    test('113/6: a Unilever-only receipt still gives Knorr nothing', () {
      expect(match(knorrLines('113/6/211/251126'), knorr), isEmpty);
    });
    test('Knorr tiers are equal-scope rules: a line on a sibling tier list is not removed from rule_1', () {
      for (final r in knorr) {
        expect(PromotionalRuleMatcher.isBarcodeScopedSpendRule(r), isTrue, reason: r.id);
        expect(PromotionalRuleMatcher.isCompanyWideSpendRule(r), isFalse, reason: r.id);
      }
      // Vegetale (فيجيتار) line is on rule_2/3 lists only; rule_1 still counts it (name),
      // as before TAG-85, because no company-wide rule owns it.
      final veg = ExtractedProductItem(
          name: 'كنور فيجيتار حار 35 جم', barcode: '6221155146656', price: 11, quantity: 1, isTargetCompany: true);
      expect(knorr.first.selectedBarcodes.contains(veg.barcode), isFalse);
      expect(PromotionalRuleMatcher.matchAllWithMultipliers(
        result: resultOf([veg, ...knorrLines('207/9/413/251126')]),
        promotionalRules: knorr,
        maxUnitsPerReceipt: 3,
      ).single.qualifyingSpend, closeTo(179, 0.01));
    });
  });
}
