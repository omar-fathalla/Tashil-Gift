import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/utils/error_handler.dart';
import 'package:al_mraay/features/admin/domain/campaign_stock_integrity.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

// TG-2 (Cadbury): the 500 tier offers "voucher 150"; the table showed 51 left
// but every claim failed because the option pointed at the voucher-25 row.
const v150 = 'gift-voucher-150';
const v25 = 'gift-voucher-25';

AllocatedPrize _row(String giftId, double value, String branch, int remaining) => AllocatedPrize(
      giftId: giftId,
      name: 'فواتشر ${value.toInt()}',
      allocatedQuantity: 100,
      remainingQuantity: remaining,
      branchId: branch,
      branchName: 'فرع $branch',
      giftType: 'voucher',
      unitValue: value,
    );

PromotionalRuleItem _tier(String optionGiftId, {double amount = 150}) => PromotionalRuleItem(
      id: 't500',
      ruleTitle: 'شريحة 500',
      triggerProduct: 'كادبري',
      conditionType: 'by_spend',
      minSpend: 500,
      rewardValue: 'فواتشر 150',
      rewardOptions: [
        RewardOption(id: 'o1', kind: 'voucher', giftId: optionGiftId, voucherAmount: amount, label: 'فواتشر 150'),
      ],
    );

final _rows = [_row(v150, 150, 'b1', 51), _row(v25, 25, 'b1', 0)];

void main() {
  group('tier option stock check (campaign save)', () {
    test('option bound to the voucher-25 id is rejected with an Arabic message', () {
      final msg = CampaignStockIntegrity.tierOptionStockError(rules: [_tier(v25)], prizes: _rows);
      expect(msg, isNotNull);
      expect(msg, contains('لا يمكن حفظ الحملة'));
      expect(msg, contains('فواتشر 150'));
      expect(msg, contains('فواتشر 25'));
    });

    test('correct id passes', () {
      expect(CampaignStockIntegrity.tierOptionStockError(rules: [_tier(v150)], prizes: _rows), isNull);
    });

    test('option with no stock row of the same gift is rejected', () {
      final msg = CampaignStockIntegrity.tierOptionStockError(rules: [_tier('gift-unknown')], prizes: _rows);
      expect(msg, contains('ليس لها صف رصيد'));
    });

    test('a campaign with no stock rows yet is not blocked', () {
      expect(CampaignStockIntegrity.tierOptionStockError(rules: [_tier('gift-unknown')], prizes: const []), isNull);
    });

    test('quantity rules and options without giftId are not checked', () {
      final qty = PromotionalRuleItem(
        id: 'q', ruleTitle: 'q', triggerProduct: 'x', rewardValue: 'x',
        linkedGifts: [LinkedGiftAllocation(giftId: 'missing', giftName: 'x')],
      );
      expect(CampaignStockIntegrity.tierOptionStockError(rules: [qty, _tier('')], prizes: _rows), isNull);
    });

    test('a value-agreeing row among duplicates passes', () {
      final rows = [_row(v150, 100, 'b1', 1), _row(v150, 150, 'b2', 1)];
      expect(CampaignStockIntegrity.tierOptionStockError(rules: [_tier(v150)], prizes: rows), isNull);
    });
  });

  group('branch table stored vs computed remaining', () {
    test('stored remaining is read per gift and branch', () {
      final stored = CampaignStockIntegrity.storedRemaining(
        prizes: _rows, giftId: v150, giftName: 'فواتشر 150', branchMatches: (p) => p.branchId == 'b1');
      expect(stored, 51);
      expect(CampaignStockIntegrity.storedRemaining(
          prizes: _rows, giftId: 'none', giftName: 'none', branchMatches: (_) => true), isNull);
    });

    test('mismatch is flagged only when a stored row disagrees', () {
      expect(CampaignStockIntegrity.remainingMismatch(computed: 51, stored: 0), isTrue);
      expect(CampaignStockIntegrity.remainingMismatch(computed: 51, stored: 51), isFalse);
      expect(CampaignStockIntegrity.remainingMismatch(computed: 51, stored: null), isFalse);
    });
  });

  group('claim error messages', () {
    test('insufficient stock names gift, branch and stored remaining', () {
      final text = AppErrorHandler.claimFailureMessage(FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Not enough prize stock remaining for "فواتشر 150" at branch "فرع b1" (stored remaining 0, requested 1).',
        details: {'reason': 'insufficient_stock', 'giftName': 'فواتشر 150', 'branch': 'فرع b1', 'remaining': 0},
      ));
      expect(text, contains('فواتشر 150'));
      expect(text, contains('فرع b1'));
      expect(text, contains('الرصيد المحفوظ: 0'));
    });

    test('legacy insufficient stock message keeps its Arabic mapping', () {
      final text = AppErrorHandler.claimFailureMessage(FirebaseFunctionsException(
        code: 'failed-precondition', message: 'Not enough prize stock remaining.'));
      expect(text, 'رصيد الهدايا في هذا الفرع لا يكفي. يرجى تغذية الرصيد ثم إعادة المحاولة.');
    });

    test('misconfigured campaign has an Arabic message', () {
      final text = AppErrorHandler.claimFailureMessage(FirebaseFunctionsException(
        code: 'failed-precondition', message: 'misconfigured', details: {'reason': 'campaign_misconfigured'}));
      expect(text, contains('إعداد الحملة غير صحيح'));
    });
  });
}
