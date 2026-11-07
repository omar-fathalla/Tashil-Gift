import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const gift500 = '4QDy4H8psECEP4AnJSON';
  const gift350 = 'beGiYXcMAsW78OGevW5d';
  const gift200 = 'gift-200';

  PromotionalRuleItem tier(String id, double min, String giftId, double amount) {
    return PromotionalRuleItem(
      id: id,
      ruleTitle: 'شريحة ${min.toInt()}',
      triggerProduct: 'كادبري',
      conditionType: 'by_spend',
      minSpend: min,
      rewardType: 'voucher',
      rewardValue: 'قسيمة شراء ${amount.toInt()} جنيه',
      rewardAmount: amount,
      requiredBrands: const ['كادبري'],
      selectedBarcodes: const ['6220000000011'],
      rewardOptions: [
        RewardOption(
          id: 'opt-$id',
          kind: 'voucher',
          giftId: giftId,
          giftType: 'voucher',
          voucherAmount: amount,
          label: 'قسيمة شراء ${amount.toInt()} جنيه',
        ),
      ],
    );
  }

  final rules = [
    tier('tier-200', 200, gift200, 50),
    tier('tier-350', 350, gift350, 100),
    tier('tier-500', 500, gift500, 150),
  ];

  ExtractedProductItem line(double net, {String name = 'كادبري بوبل', String barcode = '6220000000011', int quantity = 1, double discount = 0, double? original, bool target = true}) {
    return ExtractedProductItem(
      name: name,
      price: net,
      quantity: quantity,
      isTargetCompany: target,
      barcode: barcode,
      originalPrice: original,
      discountAmount: discount,
    );
  }

  Map<String, int> award(List<ExtractedProductItem> products, {String mode = 'consuming', bool multiples = true, int? cap}) {
    final matched = PromotionalRuleMatcher.matchAllWithMultipliers(
      extractedProducts: products,
      promotionalRules: rules,
      allowCampaignMultipliers: multiples,
      spendLadderMode: mode,
      maxUnitsPerReceipt: cap,
    );
    return {for (final row in matched) row.rule.id: row.multiplier};
  }

  List<double> roundTiers(List<ExtractedProductItem> products, {int? cap}) {
    final matched = PromotionalRuleMatcher.matchAllWithMultipliers(
      extractedProducts: products,
      promotionalRules: rules,
      allowCampaignMultipliers: true,
      spendLadderMode: 'consuming',
      maxUnitsPerReceipt: cap,
    );
    return SpendAwardRound.expand(matched).map((round) => round.tierMinSpend).toList();
  }

  test('1402 net brand spend consumes 500 twice then 350', () {
    final products = [
      line(492),
      line(240),
      line(294),
      line(294),
      line(82),
    ];
    expect(award(products), {'tier-500': 2, 'tier-350': 1});
    final rounds = SpendAwardRound.expand(PromotionalRuleMatcher.matchAllWithMultipliers(
      extractedProducts: products,
      promotionalRules: rules,
      spendLadderMode: 'consuming',
    ));
    expect(rounds.map((round) => round.tierMinSpend).toList(), [500, 500, 350]);
    expect(rounds.map((round) => round.giftIds.single).toList(), [gift500, gift500, gift350]);
    expect(rounds.map((round) => round.unitValues.single).toList(), [150, 150, 100]);
  });

  test('thresholds around the ladder keep their own gifts', () {
    expect(roundTiers([line(1000)]), [500, 500]);
    expect(roundTiers([line(1350)]), [500, 500, 350]);
    expect(roundTiers([line(1499)]), [500, 500, 350]);
    expect(roundTiers([line(1500)]), [500, 500, 500]);
    expect(award([line(300)]), {'tier-200': 1});
    expect(award([line(100)]), isEmpty);
  });

  test('1528 is three 500 tiers only when the extra line is eligible', () {
    final eligibleExtra = line(126, name: 'كادبري ميلت', barcode: '6220000000011');
    expect(roundTiers([line(1402), eligibleExtra]), [500, 500, 500]);
    final ambiguous = line(
      64,
      name: 'لارش كيك ميلت شوك',
      barcode: '',
      quantity: 3,
      discount: 22,
      target: true,
    );
    expect(ambiguous.netEligibleLineSpend, 126);
    expect(PromotionalRuleMatcher.hasExplicitSpendMembership(ambiguous, rules.first), isFalse);
    expect(roundTiers([line(492), line(240), line(294), line(294), line(82), ambiguous]), [500, 500, 350]);
  });

  test('cap 2 keeps the two higher tiers and exclusive mode does not consume downward', () {
    final products = [line(1402)];
    expect(roundTiers(products, cap: 2), [500, 500]);
    expect(award(products, mode: 'exclusive'), {'tier-500': 2});
  });

  test('a net price is not discounted twice and quantity stays on one pool', () {
    final alreadyNet = line(57, original: 85, discount: 28);
    expect(alreadyNet.netEligibleLineSpend, 57);
    expect(award([line(250, quantity: 2)]), {'tier-500': 1});
  });

  test('a product eligible only for the 350 tier does not fund the 500 tier', () {
    final separate = [
      PromotionalRuleItem(
        id: 'only-500',
        ruleTitle: '500',
        triggerProduct: 'فاخر',
        conditionType: 'by_spend',
        minSpend: 500,
        rewardType: 'voucher',
        rewardValue: '150',
        rewardAmount: 150,
        requiredBrands: const ['فاخر'],
        selectedBarcodes: const ['5005005005005'],
        rewardOptions: const [
          RewardOption(id: 'o500', kind: 'voucher', giftId: gift500, giftType: 'voucher', voucherAmount: 150, label: 'قسيمة شراء 150 جنيه'),
        ],
      ),
      PromotionalRuleItem(
        id: 'only-350',
        ruleTitle: '350',
        triggerProduct: 'حليب',
        conditionType: 'by_spend',
        minSpend: 350,
        rewardType: 'voucher',
        rewardValue: '100',
        rewardAmount: 100,
        requiredBrands: const ['حليب'],
        selectedBarcodes: const ['3503503503503'],
        rewardOptions: const [
          RewardOption(id: 'o350', kind: 'voucher', giftId: gift350, giftType: 'voucher', voucherAmount: 100, label: 'قسيمة شراء 100 جنيه'),
        ],
      ),
    ];
    final matched = PromotionalRuleMatcher.matchAllWithMultipliers(
      extractedProducts: [
        line(1402, name: 'حليب محلى', barcode: '3503503503503'),
      ],
      promotionalRules: separate,
      spendLadderMode: 'consuming',
    );
    expect(matched.map((row) => row.rule.id).toList(), ['only-350']);
    expect(matched.single.multiplier, 4);
    expect(SpendAwardRound.expand(matched).every((round) => round.giftIds.single == gift350), isTrue);
  });

  test('default mode stays exclusive for an unrelated ladder', () {
    expect(EventModel.normalizeSpendLadderMode(null), 'exclusive');
    expect(EventModel.normalizeSpendLadderMode('consuming'), 'consuming');
    expect(EventModel.normalizeSpendLadderMode('other'), 'exclusive');
  });
}
