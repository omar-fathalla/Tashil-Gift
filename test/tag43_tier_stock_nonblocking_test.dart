import 'dart:io';

import 'package:al_mraay/features/admin/domain/campaign_activation_review.dart';
import 'package:al_mraay/features/admin/domain/campaign_stock_integrity.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:flutter_test/flutter_test.dart';

// TAG-43 (Knorr, 25 Nov): tiers 60/170/250 give vouchers 25/50/75 while the
// campaign's stock rows are spice bags. Since 2.0.185 (TG-2) the editor
// refused to save. Now the mismatch is a warning in the review dialog only.
PromotionalRuleItem _tier(double minSpend, String giftId, String name, double value) => PromotionalRuleItem(
      id: 't$minSpend',
      ruleTitle: 'شريحة $minSpend',
      triggerProduct: 'كنور',
      conditionType: 'by_spend',
      minSpend: minSpend,
      rewardValue: name,
      linkedGifts: [LinkedGiftAllocation(giftId: giftId, giftName: name, unitValue: value, giftType: 'voucher')],
    );

EventModel _knorr() => EventModel(
      id: 'lgSK6',
      eventName: 'منتجات كنور',
      targetCompany: 'يونيليفر',
      companySlug: '512',
      minimumSpend: 60,
      requiredProducts: const ['كنور'],
      customPrompt: 'p',
      startDate: DateTime(2026, 11, 25),
      endDate: DateTime(2026, 12, 14),
      promotionalRules: [
        _tier(60, 'v25', 'فواتشر 25 جنيه', 25),
        _tier(170, 'v50', 'فواتشر 50 جنيه', 50),
        _tier(250, 'v75', 'فواتشر 75 جنيه', 75),
      ],
      allocatedPrizes: [
        AllocatedPrize(giftId: 'bagL', name: 'شنطه بهارات كبيره', allocatedQuantity: 100, remainingQuantity: 95, branchId: 'fathalla_241', branchName: 'فرع المحلة'),
        AllocatedPrize(giftId: 'bagS', name: 'شنطه بهارات صغيره', allocatedQuantity: 100, remainingQuantity: 90, branchId: 'fathalla_241', branchName: 'فرع المحلة'),
      ],
    );

void main() {
  test('the Knorr mismatch is still detected (3 tiers)', () {
    final e = _knorr();
    final issues = CampaignStockIntegrity.tierOptionStockIssues(rules: e.promotionalRules, prizes: e.allocatedPrizes);
    expect(issues.length, 3);
    expect(issues.first, contains('شريحة 60 جنيه'));
  });

  test('it shows as non-blocking warnings in the review, not as danger', () {
    final e = _knorr();
    final issues = CampaignStockIntegrity.tierOptionStockIssues(rules: e.promotionalRules, prizes: e.allocatedPrizes);
    final review = CampaignActivationReview.of(e, isNew: false, willBeActive: true, now: DateTime(2026, 11, 25), tierStockIssues: issues);
    final tierWarnings = review.warnings.where((w) => w.message.contains(CampaignActivationReview.tierStockHint)).toList();
    expect(tierWarnings.length, 3);
    expect(tierWarnings.every((w) => w.level == ReviewLevel.warning), isTrue);
    final without = CampaignActivationReview.of(e, isNew: false, willBeActive: true, now: DateTime(2026, 11, 25));
    expect(review.hasDanger, without.hasDanger, reason: 'the mismatch alone never turns the review into danger');
  });

  test('no issues -> no extra warnings (default)', () {
    final e = _knorr();
    final a = CampaignActivationReview.of(e, isNew: false, now: DateTime(2026, 11, 25));
    expect(a.warnings.any((w) => w.message.contains(CampaignActivationReview.tierStockHint)), isFalse);
  });

  test('the editor no longer blocks the save on the tier stock check', () {
    final src = File('lib/features/admin/presentation/create_event_screen.dart').readAsStringSync();
    expect(src.contains('tierOptionStockError('), isFalse, reason: 'the blocking snackbar + return is gone');
    expect(src.contains('tierStockIssues: stockIssues'), isTrue);
    final save = src.substring(src.indexOf('Future<void> _saveEvent() async {'));
    final check = save.indexOf('tierOptionStockIssues(');
    final review = save.indexOf('CampaignActivationSummaryDialog.show(');
    expect(check, greaterThan(0));
    expect(check < review, isTrue, reason: 'issues feed the review dialog, which comes after');
  });
}
