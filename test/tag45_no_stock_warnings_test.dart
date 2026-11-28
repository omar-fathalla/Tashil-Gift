import 'dart:io';

import 'package:al_mraay/features/admin/domain/campaign_activation_review.dart';
import 'package:al_mraay/features/admin/domain/campaign_stock_integrity.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:flutter_test/flutter_test.dart';

// TAG-43 / TAG-45 (Knorr, 25 Nov): tiers 60/170/250 give vouchers 25/50/75
// while the campaign's stock rows are spice bags. 2.0.185 (TG-2) blocked the
// save, 2.0.189 made it a review warning, and TAG-45 (Mohamed) removes every
// stock warning from creating/editing a campaign. The helper itself stays.
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

  bool stockLine(ReviewWarning w) =>
      w.message.contains('رصيد') || w.message.contains('صف رصيد') || w.message.contains('خلص');

  test('the review shows no stock warnings for the Knorr mismatch', () {
    final review = CampaignActivationReview.of(_knorr(), isNew: false, willBeActive: true, now: DateTime(2026, 11, 25));
    expect(review.warnings.where(stockLine), isEmpty);
    expect(review.hasDanger, isFalse);
  });

  test('no stock at all, sold-out rows and branches without stock: no warnings', () {
    final base = _knorr();
    final none = EventModel.fromFirestoreMap('x', {...base.toFirestore()..remove('createdAt'), 'allocatedPrizes': []});
    final r1 = CampaignActivationReview.of(none, isNew: true, now: DateTime(2026, 11, 25));
    expect(r1.warnings.where(stockLine), isEmpty);
    expect(r1.hasDanger, isFalse);

    final soldOut = EventModel.fromFirestoreMap('x', {
      ...base.toFirestore()..remove('createdAt'),
      'isAllBranches': false,
      'branchIds': ['fathalla_241', 'b2'],
      'branchNames': ['فرع المحلة', 'فرع الدقي'],
      'allocatedPrizes': [
        AllocatedPrize(giftId: 'bagL', name: 'شنطه بهارات كبيره', allocatedQuantity: 10, remainingQuantity: 0, branchId: 'fathalla_241', branchName: 'فرع المحلة').toMap(),
      ],
    });
    final r2 = CampaignActivationReview.of(soldOut, isNew: false, now: DateTime(2026, 11, 25));
    expect(r2.warnings.where(stockLine), isEmpty);
  });

  test('non-stock info lines stay (WhatsApp, supplementary receipts, activates now)', () {
    final e = EventModel.fromFirestoreMap('x', {
      ..._knorr().toFirestore()..remove('createdAt'),
      'enableWhatsAppWinnerNotification': true,
      'allowComplementaryReceipts': true,
      'allocatedPrizes': [],
    });
    final r = CampaignActivationReview.of(e, isNew: true, now: DateTime(2026, 11, 25));
    final info = r.warnings.where((w) => w.level == ReviewLevel.info).map((w) => w.message).join('\n');
    expect(info, contains('واتساب'));
    expect(info, contains('الفواتير التكميلية'));
    expect(info, contains('هتتفعّل'));
  });

  test('the editor runs no stock check on save', () {
    final src = File('lib/features/admin/presentation/create_event_screen.dart').readAsStringSync();
    final save = src.substring(src.indexOf('Future<void> _saveEvent() async {'), src.indexOf('setState(() => _isLoading = true);', src.indexOf('Future<void> _saveEvent() async {')));
    expect(save.contains('tierOptionStockError('), isFalse);
    expect(save.contains('tierOptionStockIssues('), isFalse);
    expect(save.contains('CampaignActivationSummaryDialog.show('), isTrue);
  });

  test('the review dialog has no red empty-stock line', () {
    final src = File('lib/features/admin/presentation/widgets/campaign_activation_summary_dialog.dart').readAsStringSync();
    expect(src.contains('لا يوجد رصيد'), isFalse);
  });
}
