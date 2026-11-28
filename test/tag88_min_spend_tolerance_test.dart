import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/client_portal/domain/campaign_min_spend.dart';
import 'package:flutter_test/flutter_test.dart';

PromotionalRuleItem rule(double min, {double tol = 0, String type = 'by_spend'}) => PromotionalRuleItem(
      id: 'r$min',
      ruleTitle: 'rule $min',
      triggerProduct: '',
      conditionType: type,
      minSpend: min,
      discountTolerance: tol,
      rewardValue: '50',
    );

void main() {
  group('TAG-88 campaign min-spend gate honours rule tolerance', () {
    test('Unilever: campaign 200, rules 200/300 with tolerance 5 -> 195', () {
      final gate = campaignMinSpendGate(200, [rule(200, tol: 5), rule(300, tol: 5)]);
      expect(gate, 195);
      expect(199 < gate, isFalse, reason: 'a 199 EGP receipt passes the gate');
      expect(194 < gate, isTrue, reason: 'below the tolerance it is still rejected');
    });

    test('no tolerance keeps the campaign minimum', () {
      expect(campaignMinSpendGate(200, [rule(200), rule(350)]), 200);
    });

    test('a higher rule never raises the campaign gate', () {
      expect(campaignMinSpendGate(200, [rule(300, tol: 5)]), 200);
    });

    test('quantity rules are ignored', () {
      expect(campaignMinSpendGate(200, [rule(0, type: 'by_quantity')]), 200);
    });

    test('no campaign minimum means no gate', () {
      expect(campaignMinSpendGate(0, [rule(200, tol: 5)]), 0);
    });
  });
}
