import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

/// Real Galaxy receipt 94/5/241/291026: rules share identical barcodes but
/// have different trigger wording/brand families. They must share one spend
/// pool so the 100 voucher wins instead of 3x Snickers.
void main() {
  const barcodes = ['6221134030433', '6221134031478', '6221134000108'];
  const brands = ['مارس', 'جالكسي', 'تويكس', 'سنيكرز', 'جلاكسى', 'جلاكسي', 'مالتيزرس'];
  PromotionalRuleItem rule(String id, String trig, double min, String type, double amt, double unit) =>
      PromotionalRuleItem(
        id: id,
        ruleTitle: 'اشتري ب ${min.toInt()} جنيه من منتجات $trig',
        triggerProduct: trig,
        conditionType: 'by_spend',
        minSpend: min,
        rewardType: type,
        rewardValue: id,
        rewardAmount: amt,
        allowMultipliers: true,
        selectedBarcodes: barcodes,
        requiredBrands: brands,
        linkedGifts: [LinkedGiftAllocation(giftId: 'g_$id', giftName: id, quantity: 1, unitValue: unit, giftType: type == 'voucher' ? 'voucher' : 'product')],
      );
  final rules = [
    rule('rule_1', 'منتجات مارس و شيكولاته و جالكسي و تويكس و سنيكرز و جلاكسى و جلاكسي و مالتيزرس', 150, 'free_product', 0, 0),
    rule('rule_2', 'جلاكسي', 350, 'voucher', 50, 50),
    rule('rule_3', 'جلاكسي', 450, 'voucher', 100, 100),
  ];
  Map<String, int> award(List<Map<String, dynamic>> raw) {
    final m = PromotionalRuleMatcher.matchAllWithMultipliers(
      extractedProducts: [for (final r in raw) ExtractedProductItem.fromJson(r)],
      promotionalRules: rules,
      allowCampaignMultipliers: true,
    );
    return {for (final x in m) x.rule.id: x.multiplier};
  }

  test('receipt 474 net (no barcodes) -> one 100 voucher, not 3 Snickers', () {
    expect(award([
      {'name': 'جلاكسي شوكولاته ب', 'price': 57, 'quantity': 1, 'isTargetCompany': true, 'barcode': '', 'originalPrice': 85, 'discountAmount': 28, 'totalPrice': 57},
      {'name': 'جلاكسى ميني كرامي', 'price': 139, 'quantity': 3, 'isTargetCompany': true, 'barcode': '', 'originalPrice': 250, 'discountAmount': 111, 'totalPrice': 417},
    ]), {'rule_3': 1});
  });

  test('1100 -> two 100 vouchers + one Snickers from remainder 200', () {
    expect(award([
      {'name': 'جلاكسى جواهر شوكو', 'price': 1100, 'quantity': 1, 'isTargetCompany': true, 'barcode': '6221134031478', 'totalPrice': 1100},
    ]), {'rule_3': 2, 'rule_1': 1});
  });
}
