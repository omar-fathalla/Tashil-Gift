import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

/// Galaxy-style campaign: three spend tiers on the same 92-barcode product set,
/// worded differently. The highest-value gift must win and only the remainder
/// may qualify lower tiers (no stacking 4x the lowest tier).
void main() {
  const barcodes = ['6221000000001', '6221000000002', '6221000000003'];

  final rules = [
    PromotionalRuleItem(
      id: 'rule_1',
      ruleTitle: 'Buy 150 EGP of Mars, Galaxy, Twix, Snickers get Snickers coffee',
      triggerProduct: 'Mars, Galaxy, Twix, Bounty, Snickers, Maltesers (92 items)',
      conditionType: 'by_spend',
      minSpend: 150,
      rewardType: 'free_product',
      rewardValue: 'Snickers coffee',
      rewardAmount: 0,
      allowMultipliers: true,
      selectedBarcodes: barcodes,
      linkedGifts: [
        LinkedGiftAllocation(giftId: 'snickers', giftName: 'Snickers coffee', quantity: 1, unitValue: 0, giftType: 'product'),
      ],
    ),
    PromotionalRuleItem(
      id: 'rule_2',
      ruleTitle: 'Buy 350 EGP of Galaxy get 50 EGP voucher',
      triggerProduct: 'Galaxy',
      conditionType: 'by_spend',
      minSpend: 350,
      rewardType: 'voucher',
      rewardValue: 'Voucher 50',
      rewardAmount: 50,
      allowMultipliers: true,
      selectedBarcodes: barcodes,
      linkedGifts: [
        LinkedGiftAllocation(giftId: 'v50', giftName: 'Voucher 50', quantity: 1, unitValue: 50, giftType: 'voucher'),
      ],
    ),
    PromotionalRuleItem(
      id: 'rule_3',
      ruleTitle: 'Buy 450 EGP of Galaxy get 100 EGP voucher',
      triggerProduct: 'Galaxy',
      conditionType: 'by_spend',
      minSpend: 450,
      rewardType: 'voucher',
      rewardValue: 'Voucher 100',
      rewardAmount: 100,
      allowMultipliers: true,
      selectedBarcodes: barcodes,
      linkedGifts: [
        LinkedGiftAllocation(giftId: 'v100', giftName: 'Voucher 100', quantity: 1, unitValue: 100, giftType: 'voucher'),
      ],
    ),
  ];

  List<ExtractedProductItem> basket(double total) => [
        ExtractedProductItem(name: 'Galaxy smooth', price: total / 2, quantity: 1, isTargetCompany: true, barcode: barcodes[0]),
        ExtractedProductItem(name: 'Snickers', price: total / 2, quantity: 1, isTargetCompany: true, barcode: barcodes[1]),
      ];

  Map<String, int> award(double total) {
    final matched = PromotionalRuleMatcher.matchAllWithMultipliers(
      extractedProducts: basket(total),
      promotionalRules: rules,
      allowCampaignMultipliers: true,
    );
    return {for (final m in matched) m.rule.id: m.multiplier};
  }

  test('627 EGP -> one 100 voucher + one Snickers from the 177 remainder (not 4 Snickers)', () {
    expect(award(627), {'rule_3': 1, 'rule_1': 1});
  });

  test('600 EGP -> one 100 voucher + one Snickers from the 150 remainder', () {
    expect(award(600), {'rule_3': 1, 'rule_1': 1});
  });

  test('599 EGP -> one 100 voucher only (149 remainder reaches no tier)', () {
    expect(award(599), {'rule_3': 1});
  });

  test('900 EGP -> two 100 vouchers', () {
    expect(award(900), {'rule_3': 2});
  });

  test('400 EGP -> one 50 voucher only', () {
    expect(award(400), {'rule_2': 1});
  });

  test('300 EGP -> one Snickers (150 tier implicitly capped at next tier 350)', () {
    expect(award(300), {'rule_1': 1});
  });

  test('gift value ranking: known values first, then spend tier', () {
    final sorted = List<PromotionalRuleItem>.from(rules)..sort(PromotionalRuleMatcher.compareRulesByGiftValue);
    expect(sorted.map((r) => r.id).toList(), ['rule_3', 'rule_2', 'rule_1']);
  });
}
