// TAG-77: the matcher speed-ups must not change any result.
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/services/multi_campaign_receipt_evaluator.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:flutter_test/flutter_test.dart';

PromotionalRuleItem _rule(String id, String title, {
  String trigger = '',
  double minSpend = 0,
  List<String> names = const [],
  List<String> barcodes = const [],
  List<String> brands = const [],
}) =>
    PromotionalRuleItem.fromMap({
      'id': id,
      'ruleTitle': title,
      'triggerProduct': trigger,
      'conditionType': minSpend > 0 ? 'by_spend' : 'by_quantity',
      'minQuantity': 1,
      'minSpend': minSpend,
      'selectedProductNames': names,
      'selectedBarcodes': barcodes,
      'requiredBrands': brands,
      'rewardType': 'voucher',
      'rewardValue': 'فواتشر $id',
      'rewardAmount': 50,
      'allowMultipliers': true,
    });

ExtractedProductItem _p(String name, double price, {int qty = 1, String barcode = '', bool target = true}) =>
    ExtractedProductItem(name: name, price: price, quantity: qty, barcode: barcode, isTargetCompany: target);

// A Unilever-shaped catalog: many names, POS spelling variants, descriptors.
final List<String> _catalog = [
  for (var i = 0; i < 400; i++) 'صانسيلك شامبو ${200 + i} مل بزيت جوز الهند',
  'ريكسونا رول اون 50مل*2ق رجالي',
  'اكس اسبراى 150 مل افريكان',
  'الضحى ارز مصرى 1ك',
  'تريزيمى كريم الترطيب الفعال بالحرارة 120مل',
  'كلير شامبو رجالى 360مل',
  'دوف صابون 135 جم',
  'لايف بوي صابون ابيض 160جم',
];

final _products = <List<ExtractedProductItem>>[
  [_p('ريكسونا رول أون 50 مل *2 رجالى', 135, barcode: '6221155652119'), _p('ريكسونا 150مل حريمي', 69)],
  [_p('كس اسبراي افريكان 150ml', 120, qty: 2), _p('شيبسي', 10, target: false)],
  [_p('الضحى أرز 1كجم', 40), _p('كلير شامبو 360 ملى رجالي', 134)],
  [_p('صا نسيلك شامبوزيت 250مل', 95, qty: 3), _p('دوف صابون 135g', 30)],
  [_p('منتج غير معروف', 300)],
];

void main() {
  setUp(PromotionalRuleMatcher.clearNormalizeCachesForTest);

  test('normalize cache returns exactly the uncached value', () {
    final inputs = [
      ..._catalog,
      for (final r in _products) for (final p in r) p.name,
      '', '  ', 'ROLL ON', 'روول اون', 'د ر ه عرض كاتشب', '600132.00', 'ز مصرى', 'سيد منظف',
    ];
    for (final s in inputs) {
      final first = PromotionalRuleMatcher.normalize(s);
      expect(first, PromotionalRuleMatcher.normalizeUncachedForTest(s), reason: s);
      expect(PromotionalRuleMatcher.normalize(s), first, reason: 'second call: $s');
    }
    expect(PromotionalRuleMatcher.normalizeCacheSizeForTest, greaterThan(0));
  });

  final rules = [
    _rule('rule_1', 'اشتري ب 200 جنيه من منتجات شركه يونيلفر', trigger: 'منتجات يونيليفر', minSpend: 200, names: _catalog, brands: ['ريكسونا', 'اكس', 'كلير', 'صنسيلك', 'دوف']),
    _rule('rule_2', 'اشترى ب300ج من اكس وريكسونا فقط', trigger: 'اكس / ريكسونا', minSpend: 300, names: _catalog.where((n) => n.contains('اكس') || n.contains('ريكسونا')).toList(), brands: ['اكس', 'ريكسونا']),
    _rule('rule_3', 'اشتري 2 كلير', trigger: 'كلير 360 مل', names: ['كلير شامبو رجالى 360مل']),
  ];

  String fingerprint(List<MatchedPromotionalRuleResult> m) => m
      .map((r) => '${r.rule.id}x${r.multiplier}|${r.totalTriggerQuantity}|${r.qualifyingSpend}|${r.totalRewardAmount}|${r.formattedPrizeSummary}|${r.qualifyingProductNames.join("+")}')
      .join(' ; ');

  AiReceiptAnalysisResult res(List<ExtractedProductItem> prods) => AiReceiptAnalysisResult(
        isValid: true,
        receiptNumber: '1',
        message: '',
        extractedProducts: prods,
        targetCompanyTotal: prods.where((p) => p.isTargetCompany).fold<double>(0, (s, p) => s + p.price * p.quantity),
      );

  test('product match is the same with and without the normalize cache', () {
    for (final prods in _products) {
      for (final rule in rules) {
        for (final p in prods) {
          PromotionalRuleMatcher.clearNormalizeCachesForTest();
          final cold = PromotionalRuleMatcher.matchesProduct(p, rule.triggerProduct, rule);
          final warm = PromotionalRuleMatcher.matchesProduct(p, rule.triggerProduct, rule);
          expect(warm, cold, reason: '${p.name} / ${rule.id}');
        }
      }
    }
  });

  test('scan memo returns the same rules and gifts as a fresh match', () async {
    for (final prods in _products) {
      final r = res(prods);
      final outside = PromotionalRuleMatcher.matchAllWithMultipliers(result: r, promotionalRules: rules, maxUnitsPerReceipt: 3);
      final reasonsOutside = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(result: r, promotionalRules: rules);
      await PromotionalMatchScope.run(() async {
        final scope = PromotionalMatchScope.current!;
        final a = PromotionalRuleMatcher.matchAllWithMultipliers(result: r, promotionalRules: rules, maxUnitsPerReceipt: 3);
        final b = PromotionalRuleMatcher.matchAllWithMultipliers(result: r, promotionalRules: rules, maxUnitsPerReceipt: 3);
        final reasons = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(result: r, promotionalRules: rules);
        expect(fingerprint(a), fingerprint(outside));
        expect(fingerprint(b), fingerprint(outside));
        expect(reasons, reasonsOutside);
        expect(identical(a, b), isFalse, reason: 'callers get their own list');
        expect(PromotionalMatchScope.statsOf(scope).hits, greaterThanOrEqualTo(1));
      });
    }
  });

  test('a different line, flag or total is never served from the memo', () async {
    final base = res(_products[0]);
    final cleared = base.copyWith(
      extractedProducts: [for (final p in base.extractedProducts) p.copyWith(isTargetCompany: false)],
      targetCompanyTotal: 0,
    );
    final expectedBase = fingerprint(PromotionalRuleMatcher.matchAllWithMultipliers(result: base, promotionalRules: rules));
    final expectedCleared = fingerprint(PromotionalRuleMatcher.matchAllWithMultipliers(result: cleared, promotionalRules: rules));
    expect(expectedBase == expectedCleared, isFalse, reason: 'fixture must make the flag matter');
    await PromotionalMatchScope.run(() async {
      expect(fingerprint(PromotionalRuleMatcher.matchAllWithMultipliers(result: base, promotionalRules: rules)), expectedBase);
      expect(fingerprint(PromotionalRuleMatcher.matchAllWithMultipliers(result: cleared, promotionalRules: rules)), expectedCleared);
      expect(fingerprint(PromotionalRuleMatcher.matchAllWithMultipliers(result: base, promotionalRules: rules)), expectedBase);
      // Same content but a different rule list object set -> its own entry.
      final copyRules = [for (final r in rules) PromotionalRuleItem.fromMap(r.toMap())];
      expect(fingerprint(PromotionalRuleMatcher.matchAllWithMultipliers(result: base, promotionalRules: copyRules)), expectedBase);
      final stats = PromotionalMatchScope.statsOf(PromotionalMatchScope.current!);
      expect(stats.misses, 3);
      expect(stats.hits, 1);
    });
  });

  test('multi-scan: combined rules and each campaign keep separate answers (TAG-67 scoping intact)', () async {
    final uni = EventModel.fromFirestoreMap('uni', {
      'eventName': 'يونيليفر', 'targetCompany': 'يونيليفر', 'companySlug': '512', 'isActive': true,
      'spendLadderMode': 'exclusive', 'allowMultipleChances': true,
      'promotionalRules': [rules[0].toMap(), rules[1].toMap()],
    });
    final knorr = EventModel.fromFirestoreMap('knorr', {
      'eventName': 'كنور', 'targetCompany': 'يونيليفر', 'companySlug': '512', 'isActive': true,
      'spendLadderMode': 'exclusive', 'allowMultipleChances': true,
      'promotionalRules': [
        _rule('k1', 'اشتري ب90جنية من منتجات كنور', trigger: 'كنور', minSpend: 90, names: ['كنور مرقة دجاج 8 مكعب'], brands: ['كنور']).toMap(),
      ],
    });
    for (final prods in _products) {
      final r = res(prods).copyWith(isBranchMatched: true);
      String summary(MultiCampaignEvaluationSummary s) => s.allEvaluations
          .map((e) => '${e.campaign.id}:${e.isQualified}:${e.matchedRules.map((m) => '${m.rule.id}x${m.multiplier}').join(",")}')
          .join(' | ');
      final outside = summary(MultiCampaignReceiptEvaluator.evaluateAll(result: r, campaigns: [uni, knorr]));
      await PromotionalMatchScope.run(() async {
        // Combined (multi-scan prompt) rules first, as in the real scan.
        PromotionalRuleMatcher.matchAllWithMultipliers(result: r, promotionalRules: [...uni.promotionalRules, ...knorr.promotionalRules]);
        final inside1 = summary(MultiCampaignReceiptEvaluator.evaluateAll(result: r, campaigns: [uni, knorr]));
        final inside2 = summary(MultiCampaignReceiptEvaluator.evaluateAll(result: r, campaigns: [uni, knorr]));
        expect(inside1, outside);
        expect(inside2, outside);
      });
      // Knorr must never pick up Unilever-wide matches through the memo.
      final knorrOnly = PromotionalRuleMatcher.matchAllWithMultipliers(
        result: MultiCampaignReceiptEvaluator.scopeResultToCampaign(r, knorr),
        promotionalRules: knorr.promotionalRules,
      );
      expect(knorrOnly.every((m) => m.rule.id == 'k1'), isTrue);
    }
  });

  test('memo stops serving when the scan ends', () async {
    PromotionalMatchScope? captured;
    await PromotionalMatchScope.run(() async {
      captured = PromotionalMatchScope.current;
      expect(captured, isNotNull);
      await PromotionalMatchScope.run(() async {
        expect(identical(PromotionalMatchScope.current, captured), isTrue, reason: 'nested scan reuses the outer memo');
      });
    });
    expect(PromotionalMatchScope.current, isNull);
    Future<PromotionalMatchScope?>? later;
    await PromotionalMatchScope.run(() async {
      later = Future.delayed(const Duration(milliseconds: 20), () => PromotionalMatchScope.current);
    });
    expect(await later, isNull, reason: 'a callback after the scan has no memo');
  });
}
