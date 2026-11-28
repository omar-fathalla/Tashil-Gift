import 'dart:io';

import 'package:al_mraay/features/admin/domain/company_gift_model.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/admin/domain/linked_gift_cleanup.dart';
import 'package:flutter_test/flutter_test.dart';

CompanyGiftModel _gift(String id, String name) => CompanyGiftModel(
      id: id,
      companySlug: 'knorr',
      companyName: 'Knorr',
      giftName: name,
      totalQuantity: 10,
      availableQuantity: 10,
      allocatedInOtherCampaigns: 0,
      giftType: 'voucher',
      unitValue: 25,
    );

PromotionalRuleItem _rule(String id, List<LinkedGiftAllocation> links, {String? legacyId, String? legacyName}) => PromotionalRuleItem(
      id: id,
      ruleTitle: id,
      triggerProduct: 'كنور',
      conditionType: 'by_spend',
      minSpend: 60,
      rewardValue: 'x',
      linkedGifts: links,
      linkedGiftId: legacyId,
      linkedGiftName: legacyName,
    );

LinkedGiftAllocation _link(String id, String name) => LinkedGiftAllocation(giftId: id, giftName: name, unitValue: 25, giftType: 'voucher');

void main() {
  final gifts = [_gift('v25', 'فواتشر 25 جنيه'), _gift('v50new', 'فواتشر 50 جنيه')];

  test('keeps live links, re-points links found by name, drops dead ones', () {
    final rules = [
      _rule('r1', [_link('v25', 'فواتشر 25 جنيه'), _link('gone', 'شنطة قديمة'), _link('v50old', 'فواتشر 50 جنيه')]),
    ];
    final out = LinkedGiftCleanup.reconcile(rules, gifts);
    expect(out.single.linkedGifts.map((l) => l.giftId), ['v25', 'v50new']);
    expect(LinkedGiftCleanup.deadLinks(rules, gifts), 2);
    expect(LinkedGiftCleanup.deadLinks(out, gifts), 0);
  });

  test('a rule whose legacy single gift was deleted is dropped; one found by name stays', () {
    final out = LinkedGiftCleanup.reconcile([
      _rule('dead', const [], legacyId: 'gone', legacyName: 'شنطة قديمة'),
      _rule('renamed', const [], legacyId: 'old', legacyName: 'فواتشر 25 جنيه'),
    ], gifts);
    expect(out.map((r) => r.id), ['renamed']);
  });

  test('an ambiguous name is not guessed', () {
    final dup = [...gifts, _gift('v25b', 'فواتشر 25 جنيه')];
    final out = LinkedGiftCleanup.reconcile([_rule('r', [_link('old', 'فواتشر 25 جنيه')])], dup);
    expect(out.single.linkedGifts, isEmpty);
  });

  test('gifts not loaded (empty list): nothing is cleaned', () {
    final rules = [_rule('r', [_link('gone', 'x')], legacyId: 'gone', legacyName: 'x')];
    final out = LinkedGiftCleanup.reconcile(rules, const []);
    expect(out.single.linkedGifts.single.giftId, 'gone');
  });

  test('the editor cleans on gift load and on save', () {
    final src = File('lib/features/admin/presentation/create_event_screen.dart').readAsStringSync();
    expect(RegExp(r'LinkedGiftCleanup\.reconcile\(').allMatches(src).length, 2);
    expect(src.contains('promotionalRules: LinkedGiftCleanup.reconcile(_promotionalRules, _companyGifts)'), isTrue);
  });
}
