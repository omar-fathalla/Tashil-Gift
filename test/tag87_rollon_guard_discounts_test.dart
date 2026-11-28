// TAG-87: Unilever receipt 62/12/224/27112026 (Fathalla Ajami Star) was
// rejected: 139 EGP counted against the 200 tier although it holds 245 EGP of
// Unilever roll-ons and soap.
import 'dart:convert';
import 'dart:io';

import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:flutter_test/flutter_test.dart';

final Map<String, dynamic> fx = jsonDecode(
  File('test/fixtures/tag87_unilever_rules.json').readAsStringSync(),
) as Map<String, dynamic>;

List<PromotionalRuleItem> unileverRules() => [
      for (final raw in (fx['rules'] as List))
        PromotionalRuleItem.fromMap({
          ...Map<String, dynamic>.from(raw as Map),
          if (raw['selectedBarcodes'] == r'$ladder') 'selectedBarcodes': fx['ladderBarcodes'],
        }),
    ];

ExtractedProductItem line(String name, String barcode, double price,
        {int qty = 1, bool target = true}) =>
    ExtractedProductItem(
        name: name, barcode: barcode, quantity: qty, price: price, isTargetCompany: target);

AiReceiptAnalysisResult resultOf(List<ExtractedProductItem> products) => AiReceiptAnalysisResult(
      isValid: true,
      receiptNumber: '62/12/224/27112026',
      targetCompanyTotal:
          products.where((p) => p.isTargetCompany).fold<double>(0, (s, p) => s + p.actualLineSpend),
      receiptDate: '2026-11-27',
      extractedProducts: products,
      message: '',
    );

List<MatchedPromotionalRuleResult> match(List<ExtractedProductItem> products,
        [List<PromotionalRuleItem>? rules]) =>
    PromotionalRuleMatcher.matchAllWithMultipliers(
      result: resultOf(products),
      promotionalRules: rules ?? unileverRules(),
      allowCampaignMultipliers: true,
      maxUnitsPerReceipt: 3,
      spendLadderMode: 'exclusive',
    );

Map<String, int> units(List<MatchedPromotionalRuleResult> m) =>
    {for (final r in m) r.rule.id: r.multiplier};

void main() {
  final rules = unileverRules();

  // The four Unilever lines of the receipt, with the prices printed on it.
  List<ExtractedProductItem> receipt({bool aiDiscounts = false}) => [
        line('دوف روول اون براي', '', 65),
        line('ريكسونا رول اون 5', '6221155210234', 58),
        line('دوف صابون 90جم رو', '6221155137814', aiDiscounts ? 38 : 45),
        line('دوف روول اون 50 م', '6221155214188', aiDiscounts ? 43 : 77),
      ];

  group('receipt 62/12/224/27112026', () {
    test('printed prices: 245 EGP -> rule_2 x1 (50 EGP)', () {
      final m = match(receipt());
      expect(units(m), {'rule_2': 1});
      expect(m.single.qualifyingSpend, closeTo(245, 0.01));
      expect(m.single.totalRewardAmount, 50);
    });
    test('even with the AI discounts (204 EGP) the no-barcode Dove roll-on counts', () {
      final m = match(receipt(aiDiscounts: true));
      expect(units(m), {'rule_2': 1});
      expect(m.single.qualifyingSpend, closeTo(204, 0.01));
    });
    test('the no-barcode Dove roll-on is a member of the company-wide rules', () {
      final p = line('دوف روول اون براي', '', 65);
      for (final id in ['rule_2', 'rule_3', 'rule_4']) {
        final r = rules.firstWhere((x) => x.id == id);
        expect(PromotionalRuleMatcher.isCompanyWideSpendRule(r), isTrue, reason: id);
        expect(PromotionalRuleMatcher.matchesProduct(p, r.triggerProduct, r), isTrue, reason: id);
      }
    });
  });

  group('company-wide rules ignore the spray / roll-on wording', () {
    test('roll-on and spray lines both count on rule_2', () {
      for (final name in ['دوف روول اون', 'ريكسونا رول اون 50 مل', 'ريكسونا اسبراى 150 مل', 'اكس اسبراى 150 مل']) {
        final m = match([line(name, '', 210)]);
        expect(units(m), {'rule_2': 1}, reason: name);
      }
    });
    test('a roll-on never counts on a rule that names spray only (rule_1 is a named list)', () {
      final r1 = rules.firstWhere((r) => r.id == 'rule_1');
      expect(PromotionalRuleMatcher.isCompanyWideSpendRule(r1), isFalse);
      expect(
          PromotionalRuleMatcher.matchesProduct(
              line('دوف روول اون براي', '', 400), r1.triggerProduct, r1),
          isFalse);
    });
  });

  group('narrow rules that name one form keep the guard', () {
    PromotionalRuleItem narrow(String id, String title, String trigger, List<String> brands) =>
        PromotionalRuleItem.fromMap({
          'id': id,
          'ruleTitle': title,
          'triggerProduct': trigger,
          'conditionType': 'by_spend',
          'minSpend': 100,
          'matchMode': 'OR',
          'requiredBrands': brands,
          'rewardType': 'voucher',
          'rewardValue': 'فوتشر 50',
          'rewardAmount': 50,
        });
    final sprayOnly = narrow('s1', 'اشتري ب 100 من اسبراي ريكسونا', 'ريكسونا اسبراي', ['ريكسونا']);
    final rollOnly = narrow('r1', 'اشتري ب 100 من رول اون ريكسونا', 'ريكسونا رول اون', ['ريكسونا']);

    test('roll-on is rejected by a spray-only rule, spray by a roll-on-only rule', () {
      final roll = line('ريكسونا رول اون 50 مل', '', 120);
      final spray = line('ريكسونا اسبراى 150 مل', '', 120);
      expect(PromotionalRuleMatcher.matchesProduct(roll, sprayOnly.triggerProduct, sprayOnly), isFalse);
      expect(PromotionalRuleMatcher.matchesProduct(spray, rollOnly.triggerProduct, rollOnly), isFalse);
      expect(PromotionalRuleMatcher.matchesProduct(spray, sprayOnly.triggerProduct, sprayOnly), isTrue);
      expect(PromotionalRuleMatcher.matchesProduct(roll, rollOnly.triggerProduct, rollOnly), isTrue);
    });

    test('a named (not company-wide) rule with 25 barcodes still rejects the other form', () {
      final r = PromotionalRuleItem.fromMap({
        'id': 'n25',
        'ruleTitle': 'اشتري ب 100 من اسبراي ريكسونا',
        'triggerProduct': 'ريكسونا اسبراي',
        'conditionType': 'by_spend',
        'minSpend': 100,
        'matchMode': 'OR',
        'requiredBrands': ['ريكسونا'],
        'selectedBarcodes': [for (var i = 0; i < 25; i++) '62211552${1000 + i}'],
        'rewardType': 'voucher',
        'rewardValue': 'فوتشر 50',
        'rewardAmount': 50,
      });
      expect(PromotionalRuleMatcher.isBroadCompanyWideSpendRule(r), isFalse);
      expect(
          PromotionalRuleMatcher.matchesProduct(
              line('ريكسونا رول اون 50 مل', '', 120), r.triggerProduct, r),
          isFalse);
    });

    test('a company-wide rule that lists fewer than 20 products keeps the guard', () {
      final base = Map<String, dynamic>.from(
          (fx['rules'] as List).firstWhere((r) => r['id'] == 'rule_2') as Map);
      final small = PromotionalRuleItem.fromMap({
        ...base,
        'selectedBarcodes': [for (var i = 0; i < 5; i++) '62211552${1000 + i}'],
        'selectedProductNames': <String>[],
      });
      expect(PromotionalRuleMatcher.isCompanyWideSpendRule(small), isTrue);
      expect(PromotionalRuleMatcher.isBroadCompanyWideSpendRule(small), isFalse);
      expect(
          PromotionalRuleMatcher.matchesProduct(
              line('دوف روول اون براي', '', 65), small.triggerProduct, small),
          isFalse);
      // «البتروليم» contains «رول» but is not a roll-on: a narrow guard keeps
      // counting Vaseline petroleum jelly on a spray rule (29/9/272/271126).
      expect(
          PromotionalRuleMatcher.matchesProduct(
              line('فازلين جلى البتروليم 50 مل', '', 159), small.triggerProduct, small),
          isTrue);
      // The real rule (3331 barcodes) is broad.
      final real = rules.firstWhere((r) => r.id == 'rule_2');
      expect(PromotionalRuleMatcher.isBroadCompanyWideSpendRule(real), isTrue);
    });
  });

  group('prompt: printed discount only', () {
    const rule = AiReceiptService.posPrintedDiscountRule;

    test('rule says a discount needs a printed line directly below the item', () {
      expect(rule, contains('TAG-87'));
      expect(rule, contains('تحت سطر الصنف مباشرة'));
      expect(rule, contains('discountAmount = 0'));
      expect(rule, contains('ممنوع تخترع خصم'));
    });

    test('rule carries the 62/12/224 examples (45 stays 45, 77 stays 77)', () {
      expect(rule, contains('62/12/224/27112026'));
      expect(rule, contains('price 45'));
      expect(rule, contains('price 77'));
      expect(rule, contains('price 65'));
    });

    test('withPosPrintedDiscountRule appends once and runs before the model call', () {
      final once = AiReceiptService.withPosPrintedDiscountRule('PROMPT');
      expect(once, startsWith('PROMPT'));
      expect(once, endsWith(rule));
      expect(AiReceiptService.withPosPrintedDiscountRule(once), once);

      final src = File('lib/core/services/ai_receipt_service.dart').readAsStringSync();
      final apply = src.indexOf(
          'finalPromptText = AiReceiptService.withPosPrintedDiscountRule(finalPromptText);');
      final call = src.indexOf('final prompt = TextPart(finalPromptText);');
      expect(apply, greaterThan(0));
      expect(call, greaterThan(apply));
    });
  });
}
