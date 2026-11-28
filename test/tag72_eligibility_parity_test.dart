// TAG-72: the upload page (PromotionalRuleMatcher) and the server
// (functions/campaign_eligibility.js) must agree on the same fixtures.
// The Node twin is functions/test/tag72_eligibility_parity.test.js.
import 'dart:convert';
import 'dart:io';

import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final data = jsonDecode(File('test/fixtures/eligibility_parity.json').readAsStringSync()) as Map<String, dynamic>;
  for (final c in (data['cases'] as List).cast<Map<String, dynamic>>()) {
    test(c['name'] as String, () {
      final ev = c['event'] as Map<String, dynamic>;
      final rules = (ev['promotionalRules'] as List)
          .map((r) => PromotionalRuleItem.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
      final lines = (c['receipt'] as List).cast<Map<String, dynamic>>().map((l) => ExtractedProductItem(
            name: l['name'] as String,
            price: (l['price'] as num).toDouble(),
            quantity: (l['quantity'] as num).toInt(),
            isTargetCompany: l['isTargetCompany'] as bool,
            barcode: l['barcode'] as String,
          )).toList();
      final matches = PromotionalRuleMatcher.matchAllWithMultipliers(
        extractedProducts: lines,
        promotionalRules: rules,
        allowCampaignMultipliers: ev['allowMultipleChances'] == true,
        capSpendToAiTotal: false,
        spendLadderMode: (ev['spendLadderMode'] as String?) ?? 'exclusive',
      );
      final expected = c['expected'] as Map<String, dynamic>;
      expect(matches.isNotEmpty, expected['eligible'], reason: matches.map((m) => m.rule.id).join(','));
      if (expected['units'] != null) {
        expect(matches.fold<int>(0, (s, m) => s + m.multiplier), expected['units']);
      }
    });
  }
}
