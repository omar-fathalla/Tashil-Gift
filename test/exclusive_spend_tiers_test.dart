import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

PromotionalRuleItem spend(String id, double min, List<String> barcodes,
        {String reward = 'gift', double amount = 0, List<RewardOption> options = const [], List<String> brands = const []}) =>
    PromotionalRuleItem(
      id: id,
      ruleTitle: id,
      triggerProduct: 'x',
      conditionType: 'by_spend',
      minSpend: min,
      rewardType: amount > 0 ? 'voucher' : 'free_product',
      rewardValue: reward,
      rewardAmount: amount,
      allowMultipliers: true,
      selectedBarcodes: barcodes,
      requiredBrands: brands,
      matchMode: 'OR',
      rewardOptions: options,
      linkedGifts: [
        LinkedGiftAllocation(giftId: 'g_$id', giftName: reward, quantity: 1, unitValue: amount, giftType: amount > 0 ? 'voucher' : 'product'),
      ],
    );

Map<String, int> award(List<PromotionalRuleItem> rules, List<ExtractedProductItem> items) {
  final m = PromotionalRuleMatcher.matchAllWithMultipliers(
      extractedProducts: items, promotionalRules: rules, allowCampaignMultipliers: true);
  return {for (final r in m) r.rule.id: r.multiplier};
}

void main() {
  const gb = ['6221134031478', '6221134030914'];
  final galaxy = [
    spend('rule_1', 150, gb, reward: 'Snickers coffee'),
    spend('rule_2', 350, gb, reward: 'Voucher 50', amount: 50, options: const [
      RewardOption(id: 'v50', kind: 'gift', giftId: 'qcBqg28PizbNrmxNAXFz', giftName: 'فواتشر 50 جنيه', giftType: 'voucher', unitValue: 50),
      RewardOption(id: 'choc2', kind: 'gift', giftId: 'M36PULG3IFS4E2BwKRFe', giftName: 'شيكولاته سنيكرز كوفي', giftType: 'product', quantity: 2),
    ]),
    spend('rule_3', 450, gb, reward: 'Voucher 100', amount: 100),
  ];
  List<ExtractedProductItem> g(double total) =>
      [ExtractedProductItem(name: 'جلاكسي', price: total, quantity: 1, isTargetCompany: true, barcode: gb[0])];

  group('Galaxy exclusive tiers', () {
    for (final c in <List<dynamic>>[
      [149.0, <String, int>{}],
      [150.0, {'rule_1': 1}],
      [349.0, {'rule_1': 1}],
      [350.0, {'rule_2': 1}],
      [449.0, {'rule_2': 1}],
      [450.0, {'rule_3': 1}],
      [899.0, {'rule_3': 1}],
      [900.0, {'rule_3': 2}],
    ]) {
      test('${c[0]} EGP -> ${c[1]}', () => expect(award(galaxy, g(c[0] as double)), c[1]));
    }
  });

  test('rule_2 choice: 2x chocolate option deducts 2 units, voucher option 1', () {
    final r2 = galaxy[1];
    expect(r2.hasRewardChoice, isTrue);
    final choc = r2.rewardOptions[1];
    expect(choc.toAllocation().quantity, 2);
    expect(choc.toAllocation().giftId, 'M36PULG3IFS4E2BwKRFe');
    expect(choc.toChosenRecord(ruleId: 'rule_2')['quantity'], 2);
    expect(r2.rewardOptions[0].toAllocation().quantity, 1);
    final back = RewardOption.fromMap(choc.toMap());
    expect(back.quantity, 2);
    expect(RewardOption.fromMap(const {'id': 'a', 'kind': 'gift', 'giftId': 'x'}).quantity, 1);
  });

  test('Cadbury: Oreo and Dairy Milk scoped pools stay independent', () {
    final rules = [
      spend('oreo', 100, ['111', '112'], reward: 'Oreo gift'),
      spend('dairy', 100, ['221', '222'], reward: 'Dairy gift'),
    ];
    expect(
        award(rules, [
          ExtractedProductItem(name: 'اوريو', price: 120, quantity: 1, isTargetCompany: true, barcode: '111'),
          ExtractedProductItem(name: 'ديري ميلك', price: 130, quantity: 1, isTargetCompany: true, barcode: '221'),
        ]),
        {'oreo': 1, 'dairy': 1});
  });

  test('Unilever: by_quantity rule unaffected next to a spend ladder', () {
    final rules = [
      spend('s1', 100, ['901'], reward: 'small', brands: const ['سيجنال']),
      spend('s2', 200, ['901'], reward: 'big', amount: 25, brands: const ['سيجنال']),
      PromotionalRuleItem(
        id: 'q1', ruleTitle: 'Buy 2 Dove', triggerProduct: 'دوف', conditionType: 'by_quantity', matchMode: 'OR',
        minQuantity: 2, rewardType: 'voucher', rewardValue: 'v', rewardAmount: 10, allowMultipliers: true,
        requiredBrands: const ['دوف'], selectedBarcodes: const ['777'],
        linkedGifts: [LinkedGiftAllocation(giftId: 'v10', giftName: 'v10', quantity: 1, unitValue: 10, giftType: 'voucher')],
      ),
    ];
    final r = award(rules, [
      ExtractedProductItem(name: 'سيجنال', price: 250, quantity: 1, isTargetCompany: true, barcode: '901'),
      ExtractedProductItem(name: 'دوف', price: 40, quantity: 4, isTargetCompany: true, barcode: '777'),
    ]);
    expect(r["s2"], 1);
    expect(r.containsKey('s1'), isFalse);
    expect(r['q1'], 2);
  });
}
