import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/services/claim_ledger_resume.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a missing gift quantity still counts as one claimed round', () {
    expect(claimedLedgerUnits([
      {'giftId': 'a'},
      {'giftId': 'a', 'quantity': null},
    ]), 2);
    final resume = resumeFromLedger(
      claimedGifts: [
        {'giftName': '150', 'quantity': 1},
      ],
      totalRounds: 3,
    );
    expect(resume.currentRound, 2);
    expect(resume.remaining, 2);
    expect(resume.wonNames, ['150']);
  });

  test('an empty barcode without a brand token is not eligible spend', () {
    const rule = PromotionalRuleItem(
      id: 'tier-500',
      ruleTitle: '500',
      triggerProduct: 'كادبري',
      conditionType: 'by_spend',
      minSpend: 500,
      rewardType: 'voucher',
      rewardValue: '150',
      rewardAmount: 150,
      requiredBrands: ['كادبري'],
      selectedBarcodes: ['6220000000011'],
    );
    final member = ExtractedProductItem(
      name: 'كادبري بوبل',
      price: 492,
      quantity: 1,
      isTargetCompany: true,
      barcode: '6220000000011',
    );
    final unknown = ExtractedProductItem(
      name: 'سطر بدون باركود',
      price: 64,
      quantity: 3,
      isTargetCompany: true,
      barcode: '',
      discountAmount: 22,
    );
    final totals = PromotionalRuleMatcher.spendTotals(
      products: [member, unknown],
      rules: const [rule],
      spendLadderMode: 'consuming',
    );
    expect(totals.eligibleNet, 492);
    expect(totals.invoiceNet, 492 + ((64 - 22) * 3));
    final cleared = PromotionalRuleMatcher.clearUnprovenCompanyFlags(
      products: [member, unknown],
      rules: const [rule],
    );
    expect(cleared.last.isTargetCompany, isFalse);
  });
}
