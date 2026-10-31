import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

/// 2.0.163: maxChancesPerReceipt caps gift UNITS per receipt (highest value
/// first); switch OFF => each rule at most one offer (existing behaviour). Chances == capped units.
void main() {
  PromotionalRuleItem rule(String id, double min, String giftId, double value) => PromotionalRuleItem(
        id: id,
        ruleTitle: 'اشتري ب ${min.toInt()} واحصل على فوتشر ${value.toInt()}',
        triggerProduct: 'هوهوز و توينكز و فورني و تودو و فرسكا و بيك',
        conditionType: 'by_spend',
        minSpend: min,
        discountTolerance: 5,
        requiredBrands: const ['هوهوز', 'توينكز', 'فورني', 'تودو', 'فرسكا', 'بيك'],
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات بقيمة ${value.toInt()} ج.م',
        rewardAmount: value,
        linkedGifts: [
          LinkedGiftAllocation(giftId: giftId, giftName: 'فواتشر ${value.toInt()} جنيه', quantity: 1, unitValue: value, giftType: 'voucher'),
        ],
      );
  final rules = [rule('rule_1', 250, 'g50', 50), rule('rule_2', 400, 'g100', 100)];

  // Lines of 5 EGP so pool leftovers can flow to the lower tier like real
  // multi-line receipts (e.g. 62/12/250/291026: 280 + 990 + 990).
  List<ExtractedProductItem> receipt(double total) => total == 2260
      ? [
          // Real lines of 62/12/250/291026.
          ExtractedProductItem(name: 'هوهوز كينج كيك شوكولاته محشو كريمه 1ق', price: 70, quantity: 4, isTargetCompany: true, barcode: '6224008606048'),
          ExtractedProductItem(name: 'توينكز سوبر كيم هوهوزكينج كيك', price: 7.5, quantity: 132, isTargetCompany: true, barcode: '6223000555118'),
          ExtractedProductItem(name: 'فورني بونتر بيتزا قواعد ساده 3ق', price: 7.5, quantity: 132, isTargetCompany: true, barcode: '6223015170368'),
        ]
      : [ExtractedProductItem(name: 'هوهوز كينج كيك', price: total, quantity: 1, isTargetCompany: true, barcode: '')];

  Map<String, int> units(List<MatchedPromotionalRuleResult> m) {
    final out = <String, int>{};
    for (final r in m) {
      for (final g in r.multipliedLinkedGifts) {
        out[g.giftId] = (out[g.giftId] ?? 0) + g.quantity;
      }
    }
    return out;
  }

  List<MatchedPromotionalRuleResult> run(double total, {bool on = true, int cap = 3}) =>
      PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: receipt(total),
        promotionalRules: rules,
        allowCampaignMultipliers: on,
        maxUnitsPerReceipt: cap,
      );

  test('2260 -> 3x100', () => expect(units(run(2260)), {'g100': 3}));
  test('1805 -> 3x100', () => expect(units(run(1805)), {'g100': 3}));
  test('999 -> 2x100 (cap allows)', () => expect(units(run(999)), {'g100': 2}));
  test('switch OFF -> no multiplier: one offer per matched rule', () {
    final u = units(run(2260, on: false));
    expect(u['g100'], 1);
    expect(u.values.every((q) => q == 1), isTrue);
  });
  test('chances == capped units via bundle', () {
    final b = CompositePromotionalBundle.fromMatchedRules(run(2260), fallbackTitle: 'x');
    expect(b.totalChances, 3);
    final b2 = CompositePromotionalBundle.fromMatchedRules(run(999), fallbackTitle: 'x');
    expect(b2.totalChances, 2);
  });
  MatchedPromotionalRuleResult mk(PromotionalRuleItem r, int n) => MatchedPromotionalRuleResult(
        rule: r,
        multiplier: n,
        formattedPrizeSummary: r.rewardValue,
        multipliedLinkedGifts: r.linkedGifts.map((g) => g.copyWith(quantity: g.quantity * n)).toList(),
      );
  // Live 62/12/250/291026 bundle was 5x100 + 1x50 = 6 units vs cap 3.
  final live = [mk(rules[0], 1), mk(rules[1], 5)];
  test('6-unit live bundle capped to 3x100 (highest value first)', () {
    final c = PromotionalRuleMatcher.capMatchedRuleUnits(live, allowMultipleChances: true, maxChancesPerReceipt: 3);
    expect(units(c), {'g100': 3});
  });
  test('cap with room left fills the lower tier', () {
    final c = PromotionalRuleMatcher.capMatchedRuleUnits([mk(rules[0], 2), mk(rules[1], 2)], allowMultipleChances: true, maxChancesPerReceipt: 3);
    expect(units(c), {'g100': 2, 'g50': 1});
  });
  test('switch OFF -> no cross-rule cap (engine already limits each rule to 1)', () {
    final one = [mk(rules[0], 1), mk(rules[1], 1)];
    final c = PromotionalRuleMatcher.capMatchedRuleUnits(one, allowMultipleChances: false, maxChancesPerReceipt: 3);
    expect(units(c), {'g100': 1, 'g50': 1});
  });
  test('cap 0 + switch ON -> unchanged', () {
    final c = PromotionalRuleMatcher.capMatchedRuleUnits(live, allowMultipleChances: true);
    expect(units(c), {'g100': 5, 'g50': 1});
  });
}
