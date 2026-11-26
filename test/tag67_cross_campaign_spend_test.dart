// TAG-67: a Knorr campaign gave vouchers on receipts with no Knorr products,
// because other products of the same company (Unilever) were counted toward
// Knorr's spend rules through the company flag. Fixtures are the real rules
// and the product lines of two saved receipts (no customer data).
import 'dart:convert';
import 'dart:io';

import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/services/multi_campaign_receipt_evaluator.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:flutter_test/flutter_test.dart';

final Map<String, dynamic> fx = jsonDecode(
  File('test/fixtures/tag67_knorr_unilever_receipts.json').readAsStringSync(),
) as Map<String, dynamic>;

List<PromotionalRuleItem> rulesOf(String key) => [
      for (final r in (fx[key]['rules'] as List))
        PromotionalRuleItem.fromMap(Map<String, dynamic>.from(r as Map)),
    ];

List<ExtractedProductItem> productsOf(String receipt) => [
      for (final p in (fx['receipts'][receipt]['products'] as List))
        ExtractedProductItem.fromJson(Map<String, dynamic>.from(p as Map)),
    ];

EventModel campaignOf(String key, String id, String name) {
  final meta = Map<String, dynamic>.from(fx[key]['meta'] as Map);
  return EventModel(
    id: id,
    eventName: name,
    targetCompany: meta['targetCompany'] as String,
    companySlug: '512',
    minimumSpend: (meta['minimumSpend'] as num).toDouble(),
    allowMultipleChances: meta['allowMultipleChances'] as bool,
    maxChancesPerReceipt: meta['maxChancesPerReceipt'] as int,
    spendLadderMode: meta['spendLadderMode'] as String,
    gameType: 'directGift',
    promotionalRules: rulesOf(key),
  );
}

AiReceiptAnalysisResult receipt(String number, List<ExtractedProductItem> products) {
  final companyTotal = products
      .where((p) => p.isTargetCompany)
      .fold<double>(0, (sum, p) => sum + p.actualLineSpend);
  return AiReceiptAnalysisResult(
    isValid: true,
    receiptNumber: number,
    targetCompanyTotal: companyTotal,
    receiptDate: '2026-11-25',
    extractedProducts: products,
    message: '',
  );
}

int voucherTotal(List<MatchedPromotionalRuleResult> matches) => matches.fold<int>(
      0,
      (sum, m) => sum +
          m.multipliedLinkedGifts.fold<int>(
            0,
            (s, g) => s + (g.unitValue * g.quantity).round(),
          ),
    );

List<MatchedPromotionalRuleResult> matchKnorr(AiReceiptAnalysisResult result) =>
    PromotionalRuleMatcher.matchAllWithMultipliers(
      result: result,
      promotionalRules: rulesOf('knorr'),
      allowCampaignMultipliers: true,
      maxUnitsPerReceipt: 3,
      spendLadderMode: 'exclusive',
    );

void main() {
  final knorr = campaignOf('knorr', 'lgSK6JscCHHoQp9jpPAM', 'منتجات كنور');
  final unilever = campaignOf('unilever', 'i76jVPk2cJkHLoLOlnR0', 'حمله منتجات شركه يونيلفر');

  group('TAG-67 rule scope', () {
    test('Knorr rules are brand-scoped, Unilever company rules are company-wide', () {
      for (final r in rulesOf('knorr')) {
        expect(PromotionalRuleMatcher.isCompanyWideSpendRule(r), isFalse, reason: r.ruleTitle);
      }
      final u = {for (final r in rulesOf('unilever')) r.id: PromotionalRuleMatcher.isCompanyWideSpendRule(r)};
      // rule_1 is «من الاصناف التالية فقط», a named list, not the whole company.
      expect(u['rule_1'], isFalse);
      expect(u['rule_2'], isTrue);
      expect(u['rule_3'], isTrue);
      expect(u['rule_4'], isTrue);
    });
    test('a barcode outside the rule catalog never gets the company bypass', () {
      final rule = rulesOf('unilever').firstWhere((r) => r.id == 'rule_2');
      final known = ExtractedProductItem(
        name: 'شامبو', price: 10, quantity: 1, isTargetCompany: true,
        barcode: '6221155609038',
      );
      final unknown = ExtractedProductItem(
        name: 'شامبو', price: 10, quantity: 1, isTargetCompany: true,
        barcode: '1234567890123',
      );
      expect(PromotionalRuleMatcher.companySpendBypassAllowed(known, rule), isTrue);
      expect(PromotionalRuleMatcher.companySpendBypassAllowed(unknown, rule), isFalse);
      final knorrRule = rulesOf('knorr').first;
      expect(PromotionalRuleMatcher.companySpendBypassAllowed(known, knorrRule), isFalse);
    });
  });

  group('TAG-67 Knorr rules on the saved receipts', () {
    test('113/6: Clear shampoo + Lipton (no Knorr) gives nothing from Knorr', () {
      final r = receipt('113/6/211/251126', productsOf('113/6/211/251126'));
      final matches = matchKnorr(r);
      expect(matches, isEmpty);
    });

    test('207/9: 168 EGP of Knorr + a Dove spray gives 2 x 25, not 3 x 25', () {
      final r = receipt('207/9/413/251126', productsOf('207/9/413/251126'));
      final matches = matchKnorr(r);
      expect(matches, hasLength(1));
      expect(matches.single.rule.id, 'rule_1');
      expect(matches.single.multiplier, 2);
      expect(matches.single.qualifyingSpend, closeTo(168, 0.01));
      expect(voucherTotal(matches), 50);
      expect(matches.single.qualifyingProductNames.any((n) => n.contains('دوف')), isFalse);
    });

    test('a company-flagged non-Knorr product without barcode does not leak into Knorr', () {
      final p = ExtractedProductItem(
        name: 'ليبتون شاى 100 فتلة',
        price: 120,
        quantity: 1,
        isTargetCompany: true,
      );
      expect(PromotionalRuleMatcher.matchesProduct(p, rulesOf('knorr').first.triggerProduct, rulesOf('knorr').first), isFalse);
    });
  });

  group('TAG-67 multi-campaign evaluation (Unilever + Knorr)', () {
    test('113/6 qualifies Unilever only', () {
      final summary = MultiCampaignReceiptEvaluator.evaluateAll(
        result: receipt('113/6/211/251126', productsOf('113/6/211/251126')),
        campaigns: [unilever, knorr],
      );
      final ids = summary.qualifiedCampaigns.map((q) => q.campaign.id).toList();
      expect(ids, ['i76jVPk2cJkHLoLOlnR0']);
      final knorrEval = summary.allEvaluations.firstWhere((e) => e.campaign.id == knorr.id);
      expect(knorrEval.isQualified, isFalse);
    });

    test('207/9: Knorr counts only its own 168 EGP', () {
      final summary = MultiCampaignReceiptEvaluator.evaluateAll(
        result: receipt('207/9/413/251126', productsOf('207/9/413/251126')),
        campaigns: [unilever, knorr],
      );
      final k = summary.qualifiedCampaigns.firstWhere((q) => q.campaign.id == knorr.id);
      expect(k.qualifyingSpend, closeTo(168, 0.01));
      expect(k.matchedRules.single.multiplier, 2);
    });

    test('scopeResultToCampaign keeps AI flags for a company-wide campaign', () {
      final r = receipt('113/6/211/251126', productsOf('113/6/211/251126'));
      final scoped = MultiCampaignReceiptEvaluator.scopeResultToCampaign(r, unilever);
      expect(identical(scoped, r), isTrue);
      final knorrScoped = MultiCampaignReceiptEvaluator.scopeResultToCampaign(r, knorr);
      expect(knorrScoped.extractedProducts.any((p) => p.isTargetCompany), isFalse);
      expect(knorrScoped.targetCompanyTotal, 0);
    });
  });

  group('TAG-67 regression: Unilever all-company rules still match', () {
    test('an OCR-misspelled company product with no barcode still counts on a company-wide rule', () {
      final rule = rulesOf('unilever').firstWhere((r) => r.id == 'rule_2');
      final p = ExtractedProductItem(
        name: 'شامبو كلبر رجالي 360 مل',
        price: 210,
        quantity: 1,
        isTargetCompany: true,
      );
      expect(PromotionalRuleMatcher.companySpendBypassAllowed(p, rule), isTrue);
      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        result: receipt('x/1', [p]),
        promotionalRules: [rule],
        allowCampaignMultipliers: true,
        spendLadderMode: 'exclusive',
      );
      expect(matches, hasLength(1));
      expect(matches.single.qualifyingSpend, closeTo(210, 0.01));
    });

    test('207/9 on Unilever: same award as before the fix', () {
      // Pinned to the pre-fix result on dev (same rule, multiplier and spend).
      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        result: receipt('207/9/413/251126', productsOf('207/9/413/251126')),
        promotionalRules: rulesOf('unilever'),
        allowCampaignMultipliers: true,
        maxUnitsPerReceipt: 3,
        spendLadderMode: 'exclusive',
      );
      expect(matches, hasLength(1));
      expect(matches.single.rule.id, 'rule_1');
      expect(matches.single.multiplier, 1);
      expect(matches.single.qualifyingSpend, closeTo(297, 0.01));
    });

    test('113/6 on Unilever: same award as before the fix', () {
      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        result: receipt('113/6/211/251126', productsOf('113/6/211/251126')),
        promotionalRules: rulesOf('unilever'),
        allowCampaignMultipliers: true,
        maxUnitsPerReceipt: 3,
        spendLadderMode: 'exclusive',
      );
      expect(matches, hasLength(1));
      expect(matches.single.rule.id, 'rule_2');
      expect(matches.single.multiplier, 1);
      expect(voucherTotal(matches), 50);
    });
  });
}
