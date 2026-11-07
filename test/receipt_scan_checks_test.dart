import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/services/company_products_service.dart';
import 'package:al_mraay/core/utils/receipt_scan_checks.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/client_portal/presentation/widgets/receipt_issue_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

CompanyProductItem cp(String name, double? ref, {String bc = ''}) => CompanyProductItem(
      id: name, companySlug: '512', productName: name, barcode: bc, referencePrice: ref);

ExtractedProductItem line(String name, double price, {int q = 1, String bc = ''}) =>
    ExtractedProductItem(name: name, price: price, quantity: q, isTargetCompany: true, barcode: bc);

PromotionalRuleItem spendRule(String title, double min, {double tol = 5}) => PromotionalRuleItem(
      id: title, ruleTitle: title, triggerProduct: 'كنور', minQuantity: 1,
      conditionType: 'by_spend', minSpend: min, discountTolerance: tol, matchMode: 'OR',
      requiredBrands: const ['كنور'], rewardType: 'free_product', rewardValue: 'شنطة', rewardAmount: 0);

EventModel ev(String id, List<PromotionalRuleItem> rules, {double minimumSpend = 0}) => EventModel(
      id: id, eventName: id, targetCompany: 'كنور', minimumSpend: minimumSpend,
      retailChainId: 'x', startDate: DateTime(2026, 1, 1), endDate: DateTime(2026, 12, 31),
      branchNames: const [], isAllBranches: true, isActive: true, promotionalRules: rules);

void main() {
  // Shaped like the real Unilever catalog: many generic "كنور خلطة ..." items.
  final catalog = <CompanyProductItem>[
    cp('كنور فيجيتار حار', 30),
    cp('كنور فيجيتار بارد', 30),
    cp('كنور فيجيتار بارد عرض سعر', 5.5),
    for (var i = 0; i < 60; i++) cp('كنور خلطة صنف$i', 14.5),
    for (var i = 0; i < 40; i++) cp('كنور مرقة صنف$i', null),
    cp('كنور خلطة بشاميل', 16, bc: '6221155608109'),
  ];

  group('A) price sanity vs catalog referencePrice', () {
    test('Knorr 139/2/241: Vegetar read at 9.50 (ref ~30) is flagged', () {
      final flags = ReceiptPriceSanity.suspiciousLines(
          [line('كنور فاين فودز خل 1 لتر', 14.5, q: 3), line('كنور خلطة فيجيتار', 9.5)], catalog);
      expect(flags, hasLength(1));
      expect(flags.single.name, 'كنور خلطة فيجيتار');
      expect(flags.single.referencePrice, 30);
    });
    test('a correct read (33) is not flagged; generic words alone never match', () {
      expect(ReceiptPriceSanity.suspiciousLines([line('كنور خلطة فيجيتار', 33)], catalog), isEmpty);
      expect(ReceiptPriceSanity.suspiciousLines([line('كنور خلطة جديدة', 2)], catalog), isEmpty);
    });
    test('barcode match wins and >200% is flagged too', () {
      final f = ReceiptPriceSanity.suspiciousLines([line('اي اسم', 40, bc: '6221155608109')], catalog);
      expect(f.single.matchedBy, 'barcode');
      expect(f.single.referencePrice, 16);
    });
    test('catalog without reference prices -> no check', () {
      expect(ReceiptPriceSanity.suspiciousLines(
          [line('كنور خلطة فيجيتار', 1)], [cp('كنور خلطة فيجيتار', null)]), isEmpty);
    });
    test('re-read used only if it has products and fewer suspicious lines', () {
      const f = PriceSanityFlag('x', 9.5, 30, 'name');
      final good = AiReceiptAnalysisResult(isValid: true, receiptNumber: '1', targetCompanyTotal: 76.5,
          receiptDate: '', extractedProducts: [line('كنور خلطة فيجيتار', 33)], storeChainDetected: '',
          branchDetected: '', isBranchMatched: true, message: '');
      expect(ReceiptPriceSanity.reReadIsBetter(before: [f], after: [], reRead: good), isTrue);
      expect(ReceiptPriceSanity.reReadIsBetter(before: [f], after: [f], reRead: good), isFalse);
      expect(ReceiptPriceSanity.reReadPrompt([f]), contains('نفس السطر'));
    });
  });

  group('B) spend near-miss -> retake', () {
    final knorr = ev('knorr', [spendRule('اشتري بـ ٦٠', 60), spendRule('٩٠', 90)]);
    final hair = ev('hair', [spendRule('شعر 200', 200, tol: 0)]);
    test('53 vs 55 (60-5) is a near-miss in single mode', () {
      final m = ReceiptNearMiss.find(total: 53, campaigns: [knorr]);
      expect(m, isNotNull);
      expect(m!.threshold, 55);
      expect(m.toJson()['gap'], 2);
    });
    test('multi-campaign smart mode uses each campaign\'s own rules', () {
      final m = ReceiptNearMiss.find(total: 53, campaigns: [hair, knorr]);
      expect(m!.campaignId, 'knorr');
    });
    test('more than 10% below, already met, or no spend rules -> no near-miss', () {
      expect(ReceiptNearMiss.find(total: 40, campaigns: [knorr]), isNull);
      expect(ReceiptNearMiss.find(total: 56, campaigns: [knorr]), isNull);
      expect(ReceiptNearMiss.find(total: 53, campaigns: [ev('q', const [])]), isNull);
    });
    test('campaign-level minimumSpend counts too', () {
      expect(ReceiptNearMiss.find(total: 95, campaigns: [ev('m', const [], minimumSpend: 100)])!.threshold, 100);
    });
    test('only spend-type reasons qualify', () {
      expect(onlySpendReasons(['إجمالي منتجات كنور المؤهلة (53.00 ج.م) لم يصل للحد الأدنى المسموح به (55 ج.م)']), isTrue);
      expect(onlySpendReasons(['تاريخ الفاتورة خارج فترة الحملة']), isFalse);
      expect(onlySpendReasons(['صورة الفاتورة غير واضحة']), isFalse);
    });
    test('retake dialog copy', () {
      final s = receiptIssueSpecs[ReceiptIssueKind.nearMissRetake]!;
      expect(s.titleAr, 'صوّر الفاتورة تاني مفرودة وفي نور كويس');
      expect(s.action, ReceiptIssueAction.retake);
    });
  });
}
