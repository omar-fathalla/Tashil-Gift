import 'package:al_mraay/features/admin/domain/campaign_activation_review.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:flutter_test/flutter_test.dart';

// TAG-78 (Knorr, 26 Nov): rule_1 (60) had 28 barcodes, rules 170/250 had 31.
// Different lists are not one ladder, so the 60 rule repeated 6 times on a
// 390 EGP receipt. The review now warns about overlapping but different lists.
PromotionalRuleItem _rule(String id, double min, List<String> codes, {String type = 'by_spend'}) => PromotionalRuleItem(
      id: id,
      ruleTitle: 'شريحة ${min.toInt()}',
      triggerProduct: 'كنور',
      conditionType: type,
      minSpend: min,
      selectedBarcodes: codes,
      rewardValue: 'فواتشر',
    );

EventModel _event(List<PromotionalRuleItem> rules, {String mode = 'exclusive'}) => EventModel(
      id: 'e',
      eventName: 'منتجات كنور',
      targetCompany: 'يونيليفر',
      companySlug: '512',
      minimumSpend: 60,
      startDate: DateTime(2026, 11, 25),
      endDate: DateTime(2026, 12, 14),
      promotionalRules: rules,
      spendLadderMode: mode,
      allocatedPrizes: const [],
    );

List<String> _ladderWarnings(EventModel e) => CampaignActivationReview.of(e, isNew: false, willBeActive: true, now: DateTime(2026, 11, 26))
    .warnings
    .map((w) => w.message)
    .where((m) => m.contains('سلم شرائح واحد'))
    .toList();

void main() {
  final common = List.generate(28, (i) => '62211550${i.toString().padLeft(5, '0')}');
  final extra = ['6221155146656', '6221155607836', '6223001946081'];

  test('Knorr: 60 rule missing 3 barcodes of the 170/250 rules -> warned', () {
    final w = _ladderWarnings(_event([
      _rule('rule_1', 60, common),
      _rule('rule_2', 170, [...common, ...extra]),
      _rule('rule_3', 250, [...common, ...extra]),
    ]));
    expect(w, hasLength(2)); // rule_1 vs rule_2, rule_1 vs rule_3
    expect(w.first, contains('"شريحة 60"'));
    expect(w.first, contains('0 صنف في الأولى بس، و3 في التانية بس'));
  });

  test('identical lists (in any order) -> no warning', () {
    final all = [...common, ...extra];
    expect(_ladderWarnings(_event([
      _rule('rule_1', 60, all),
      _rule('rule_2', 170, all.reversed.toList()),
    ])), isEmpty);
  });

  test('disjoint lists are separate offers on purpose -> no warning', () {
    expect(_ladderWarnings(_event([
      _rule('a', 60, ['1111111111111']),
      _rule('b', 170, ['2222222222222']),
    ])), isEmpty);
  });

  test('consuming ladders and quantity/combo rules are not checked', () {
    final rules = [_rule('rule_1', 60, common), _rule('rule_2', 170, [...common, ...extra])];
    expect(_ladderWarnings(_event(rules, mode: 'consuming')), isEmpty);
    expect(_ladderWarnings(_event([
      _rule('q', 2, common, type: 'by_quantity'),
      _rule('c', 170, [...common, ...extra], type: 'combo_spend'),
    ])), isEmpty);
  });
}
