import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

const _barcodes = ['6221134031478', '6221134030914'];

PromotionalRuleItem _tier(String id, double min, double value, {double tolerance = 5}) => PromotionalRuleItem(
      id: id,
      ruleTitle: id,
      triggerProduct: 'x',
      conditionType: 'by_spend',
      minSpend: min,
      discountTolerance: tolerance,
      rewardType: 'voucher',
      rewardValue: 'Voucher $value',
      rewardAmount: value,
      selectedBarcodes: _barcodes,
      linkedGifts: [
        LinkedGiftAllocation(giftId: 'g_$id', giftName: id, quantity: 1, unitValue: value, giftType: 'voucher'),
      ],
    );

final _ladder = [_tier('t150', 150, 25), _tier('t350', 350, 50), _tier('t450', 450, 100)];

List<ExtractedProductItem> _lines(double eligible, {double other = 0}) => [
      ExtractedProductItem(name: 'جلاكسي', price: eligible, quantity: 1, isTargetCompany: true, barcode: _barcodes[0]),
      if (other > 0) ExtractedProductItem(name: 'سكر', price: other, quantity: 1, isTargetCompany: false, barcode: '999'),
    ];

Map<String, int> _award(double eligible, {bool multipliers = true, int? cap, double other = 0}) {
  final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
    extractedProducts: _lines(eligible, other: other),
    promotionalRules: _ladder,
    allowCampaignMultipliers: multipliers,
    maxUnitsPerReceipt: cap,
  );
  return {for (final m in matches) m.rule.id: m.multiplier};
}

int _units(Map<String, int> award) => award.values.fold(0, (a, b) => a + b);

void main() {
  group('Exclusive ladder remainder (150/350/450, tolerance 5)', () {
    test('618 -> 450 + 150', () => expect(_award(618), {'t450': 1, 't150': 1}));
    test('309.5 -> exactly one 150', () => expect(_award(309.5), {'t150': 1}));
    test('308.5 -> exactly one 150', () => expect(_award(308.5), {'t150': 1}));

    test('exact thresholds and tolerance edges', () {
      expect(_award(450), {'t450': 1});
      expect(_award(445), {'t450': 1});
      expect(_award(444.99), {'t350': 1});
      expect(_award(145), {'t150': 1});
      expect(_award(144.99), isEmpty);
      expect(_award(600), {'t450': 1, 't150': 1});
      expect(_award(595), {'t450': 1, 't150': 1});
      expect(_award(594.99), {'t450': 1});
    });

    test('remainder is a single step, not a cascade', () {
      // 2 x 450 = 900, remainder 350 -> one 350 tier, nothing below it.
      expect(_award(1250), {'t450': 2, 't350': 1});
      // A remainder never re-buys the tier that was just awarded.
      expect(_award(1000), {'t450': 2});
      // Remainder from a lower tier has no lower tier to reach.
      expect(_award(440), {'t350': 1});
    });

    test('only campaign products count', () {
      expect(_award(470, other: 300), {'t450': 1});
    });

    test('per-receipt cap keeps the highest-value offers', () {
      expect(_award(1500), {'t450': 3, 't150': 1});
      final capped = _award(1500, cap: 3);
      expect(_units(capped), 3);
      expect(capped, {'t450': 3});
      expect(_award(618, cap: 3), {'t450': 1, 't150': 1});
    });

    test('Smart Multipliers OFF still gives 450 + 150, and 309.5 stays one gift', () {
      expect(_award(618, multipliers: false), {'t450': 1, 't150': 1});
      expect(_award(309.5, multipliers: false), {'t150': 1});
      expect(_units(_award(618, multipliers: false)), 2);
    });

    test('a cap of 1 does not drop the remainder; a cap above 1 still trims', () {
      expect(_award(618, multipliers: false, cap: 1), {'t450': 1, 't150': 1});
      expect(_units(_award(1500, multipliers: true, cap: 3)), 3);
      expect(
        settleCampaignChances(2, allowMultipleChances: false, exclusiveLadder: true),
        2,
      );
      expect(
        settleCampaignChances(1, allowMultipleChances: false, exclusiveLadder: true),
        1,
      );
      expect(settleCampaignChances(5, allowMultipleChances: false), 1);
    });
  });
}
