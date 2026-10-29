import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

/// Real Galaxy (Fathalla) receipts from 29/10/2026 against the live rules
/// snapshot (150 Snickers / 350 choice / 450 voucher 100, exclusive tiers).
void main() {
  final rules = (jsonDecode(File('test/fixtures/galaxy_rules_20261029.json').readAsStringSync()) as List)
      .map((e) => PromotionalRuleItem.fromMap(Map<String, dynamic>.from(e)))
      .toList();

  ExtractedProductItem item(String name, String barcode, double price, int qty, {double original = 0, double discount = 0, bool target = true}) =>
      ExtractedProductItem(name: name, price: price, quantity: qty, isTargetCompany: target, barcode: barcode,
          originalPrice: original > 0 ? original : price, discountAmount: discount);

  ({Map<String, int> award, double spend}) run(List<ExtractedProductItem> items) {
    final m = PromotionalRuleMatcher.matchAllWithMultipliers(extractedProducts: items, promotionalRules: rules, allowCampaignMultipliers: true);
    return (award: {for (final r in m) r.rule.id: r.multiplier}, spend: qualifyingSpendFromMatches(m));
  }

  test('Tanta 90/2/243: Bounty 126-47=79 + multipack 3x125 -> 454 -> rule_3 x1 (AI said 79)', () {
    final r = run([
      item('باونتى توين ويفر', '6221134013610', 79, 1, original: 126, discount: 47),
      item('مالتى باك شوكولات', '6221134032789', 125, 3),
    ]);
    expect(r.award, {'rule_3': 1});
    expect(r.spend, closeTo(454, 0.01));
    expect(r.spend > 79, isTrue, reason: 'matcher spend must override the AI total of 79');
  });

  test('City Square A: Snickers 177 + Galaxy 3x149 -> 624 -> rule_3 x1', () {
    final r = run([
      item('سنيكرز', '5000159558914', 177, 1),
      item('جلاكسى جواهر', '6221134031478', 149, 3),
    ]);
    expect(r.award, {'rule_3': 1});
    expect(r.spend, closeTo(624, 0.01));
  });

  test('City Square B: Galaxy/Snickers mix ~411 plus non-Mars items -> rule_2', () {
    final r = run([
      item('جلاكسي شيكولاته', '6221134030419', 85, 2),
      item('جلاكسي شيكولاته', '6221134030372', 37, 4),
      item('جلاكسى فلوتس ويفر', '6221134000108', 9.5, 5),
      item('سنيكرز ويفر رولز', '6221134010473', 11.5, 4),
      item('بيبسي 1 لتر', '6223001360070', 30, 2, target: false),
      item('شيبسي', '', 15, 1, target: false),
    ]);
    expect(r.award, {'rule_2': 1});
    expect(r.spend, closeTo(411.5, 0.01));
  });

  test('City Square C: Galaxy 5x85=425 -140 disc = 285 + Flutes 220 -> 505 -> rule_3 x1', () {
    final r = run([
      item('جلاكسي شيكولاته', '6221134005394', 57, 5, original: 85, discount: 28),
      item('جلاكسى فلوتس 4اصابع', '6221134002621', 220, 1),
    ]);
    expect(r.award, {'rule_3': 1});
    expect(r.spend, closeTo(505, 0.01));
  });

  test('competitor product is not counted (no loosening)', () {
    final r = run([item('كادبوري ديري ميلك', '6223000000000', 400, 1, target: false)]);
    expect(r.award, isEmpty);
    expect(r.spend, 0);
  });
}
