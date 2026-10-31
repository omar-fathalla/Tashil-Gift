import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

/// 2.0.160: the campaign-level Smart Multipliers switch is the ONLY control
/// for multiplying chances/gifts. Rule-level `allowMultipliers` is ignored.
void main() {
  final axe = [
    for (var i = 0; i < 4; i++)
      ExtractedProductItem(
        name: 'اكس اسبراى بلاك 150 مل',
        price: 140.0,
        quantity: 1,
        isTargetCompany: true,
        barcode: '622115561177$i',
      ),
  ];

  PromotionalRuleItem rule({required bool ruleMultipliers}) => PromotionalRuleItem(
        id: 'rule_1',
        ruleTitle: 'شراء 1 اسبراي أكس -> فواتشر 50',
        triggerProduct: 'اسبراي أكس، axe',
        minQuantity: 1,
        rewardType: 'voucher',
        rewardValue: 'فواتشر 50',
        rewardAmount: 50.0,
        allowMultipliers: ruleMultipliers,
      );

  group('clampCampaignChances', () {
    test('switch OFF always yields 1 for any positive count', () {
      expect(clampCampaignChances(5, allowMultipleChances: false), 1);
      expect(clampCampaignChances(1, allowMultipleChances: false), 1);
    });
    test('switch ON caps at maxChancesPerReceipt', () {
      expect(clampCampaignChances(5, allowMultipleChances: true, maxChancesPerReceipt: 3), 3);
      expect(clampCampaignChances(2, allowMultipleChances: true, maxChancesPerReceipt: 3), 2);
      expect(clampCampaignChances(7, allowMultipleChances: true), 7);
    });
    test('zero (rejected / no chance) stays zero', () {
      expect(clampCampaignChances(0, allowMultipleChances: true), 0);
      expect(clampCampaignChances(0, allowMultipleChances: false), 0);
    });
    test('summed chances across several matched rules are capped too', () {
      // e.g. 2 rules matched giving 2 + 3 = 5 chances
      expect(clampCampaignChances(2 + 3, allowMultipleChances: true, maxChancesPerReceipt: 3), 3);
      expect(clampCampaignChances(2 + 3, allowMultipleChances: false, maxChancesPerReceipt: 3), 1);
    });
  });

  group('Rule-level allowMultipliers is ignored', () {
    test('rule says multiply but campaign switch OFF -> multiplier 1', () {
      final m = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: axe,
        promotionalRules: [rule(ruleMultipliers: true)],
        allowCampaignMultipliers: false,
      );
      expect(m, isNotEmpty);
      expect(m.fold<int>(0, (s, r) => s + r.multiplier), 1);
    });
    test('rule says no multiply but campaign switch ON -> multiplies', () {
      final m = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: axe,
        promotionalRules: [rule(ruleMultipliers: false)],
        allowCampaignMultipliers: true,
      );
      expect(m, isNotEmpty);
      expect(m.fold<int>(0, (s, r) => s + r.multiplier), 4);
    });
  });

  test('missing allowMultipleChances on a campaign doc reads as OFF', () {
    final e = EventModel.fromFirestoreMap('x', {'eventName': 'n'});
    expect(e.allowMultipleChances, isFalse);
  });
}
