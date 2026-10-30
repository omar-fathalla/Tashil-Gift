// 2.0.152+213: rep scan prompt shrink. Company scoping, kept rules, and the
// unchanged response schema shape.
import 'dart:convert';

import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/admin/domain/retail_chain_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _schemaShape = r'{"type":"OBJECT","properties":{"isValid":{"type":"BOOLEAN"},"receiptNumber":{"type":"STRING"},"targetCompanyTotal":{"type":"NUMBER"},"receiptDate":{"type":"STRING"},"storeChainDetected":{"type":"STRING"},"branchDetected":{"type":"STRING"},"isBranchMatched":{"type":"BOOLEAN"},"storeId":{"type":"STRING"},"posNumber":{"type":"STRING"},"taxNumber":{"type":"STRING"},"commercialReg":{"type":"STRING"},"hotline":{"type":"STRING"},"branchAddress":{"type":"STRING"},"isHandwritten":{"type":"BOOLEAN"},"isThermalPosReceipt":{"type":"BOOLEAN"},"isTampered":{"type":"BOOLEAN"},"isScreenCapture":{"type":"BOOLEAN"},"fraudRiskScore":{"type":"INTEGER"},"fraudReasons":{"type":"ARRAY","items":{"type":"STRING"}},"extractedProducts":{"type":"ARRAY","items":{"type":"OBJECT","properties":{"name":{"type":"STRING"},"price":{"type":"NUMBER"},"quantity":{"type":"INTEGER"},"isTargetCompany":{"type":"BOOLEAN"},"barcode":{"type":"STRING"},"originalPrice":{"type":"NUMBER"},"discountAmount":{"type":"NUMBER"},"discountPercent":{"type":"NUMBER"},"totalLinePrice":{"type":"NUMBER"}},"required":["name","price","quantity","isTargetCompany"]}},"message":{"type":"STRING"},"unfulfilledConditions":{"type":"ARRAY","items":{"type":"STRING"}}},"required":["isValid","receiptNumber","targetCompanyTotal","receiptDate","storeChainDetected","branchDetected","isBranchMatched","isHandwritten","isThermalPosReceipt","extractedProducts","message"]}';

dynamic _strip(dynamic v) {
  if (v is Map) {
    return {
      for (final e in v.entries)
        if (e.key != 'description') e.key: _strip(e.value),
    };
  }
  if (v is List) return v.map(_strip).toList();
  return v;
}

String _prompt(
  String company, {
  String customPrompt = '',
  bool complementary = false,
  List<PromotionalRuleItem> rules = const [],
  List<BranchModel> branches = const [],
  String chain = '',
  List<String> allowed = const [],
}) =>
    AiReceiptService.buildScanPrompt(
      targetCompany: company,
      minimumSpend: 250,
      resolvedRequiredProducts: const [],
      customPrompt: customPrompt,
      allowComplementaryReceipts: complementary,
      promotionalRules: rules,
      registeredBranches: branches,
      retailChainName: chain,
      allowedBranches: allowed,
      isAllBranches: allowed.isEmpty,
    );

BranchModel _branch(String name, String code) => BranchModel(
      id: 'c_$code',
      retailChainId: 'c',
      retailChainName: 'أسواق فتح الله',
      branchName: name,
      branchCode: code,
      address: 'عنوان $name',
      receiptSignature: BranchReceiptSignature(
        storeId: code,
        receiptPattern: '$code/YYMMDD',
        posNumberPattern: 'POS: $code',
        taxNumber: '334-871-552',
        hotline: '15118',
        headerKeywords: ['أسواق فتح الله', name, 'KH-$code'],
      ),
    );

void main() {
  const otherCompanyMarkers = [
    'AIR-87', 'الفراعنة', 'أم شوشة', 'الدرة', // Dorra / rice
    'AIR-71', 'كادبوري', 'مونديليز', // Cadbury multipack
    'AIR-63', 'ريكسونا', 'تريزيمي', // Unilever packaging guard
    'أدكو', 'كلوركس', 'شومان', 'المراعي', 'جهينة', 'هاينز', // other tenants
  ];

  group('company filtering (no cross-company leak)', () {
    for (final custom in ['', 'برومبت حملة {TARGET_COMPANY}']) {
      test('Edita prompt has no other company rules (custom="${custom.isEmpty ? 'none' : 'set'}")', () {
        final p = _prompt('ايديتا', customPrompt: custom);
        for (final m in otherCompanyMarkers) {
          expect(p.contains(m), isFalse, reason: 'leaked: $m');
        }
        expect(p, contains('"ايديتا"'));
      });
    }

    test('Cadbury still gets AIR-71 multipack rule; not Dorra rule', () {
      final p = _prompt('كادبوري');
      expect(p, contains('AIR-71'));
      expect(p, contains('مالتي باك'));
      expect(p.contains('AIR-87'), isFalse);
      expect(p.contains('الفراعنة'), isFalse);
    });

    test('Dorra / Shoman still get AIR-87 Dorra and rice rules; not AIR-71', () {
      for (final c in ['الدرة', 'شومان']) {
        final p = _prompt(c);
        expect(p, contains('AIR-87'), reason: c);
        expect(p, contains('أم شوشة'), reason: c);
        expect(p, contains('الفراعنة'), reason: c);
        expect(p.contains('AIR-71'), isFalse, reason: c);
      }
    });

    test('Unilever packaging guard stays Unilever-only', () {
      final rule = PromotionalRuleItem.fromMap({
        'id': 'rule_1',
        'ruleTitle': 'عرض',
        'triggerProduct': 'منتج',
        'minQuantity': 1,
        'rewardValue': 'هدية',
        'rewardType': 'gift',
      });
      expect(_prompt('يونيليفر', rules: [rule]), contains('AIR-63'));
      expect(_prompt('ايديتا', rules: [rule]).contains('AIR-63'), isFalse);
    });

    test('isDorraTargetCompany scoping', () {
      expect(isDorraTargetCompany('الدرة'), isTrue);
      expect(isDorraTargetCompany('Dorra'), isTrue);
      expect(isDorraTargetCompany('شومان'), isTrue);
      expect(isDorraTargetCompany('ايديتا'), isFalse);
      expect(isDorraTargetCompany('كادبوري'), isFalse);
    });
  });

  group('kept rules', () {
    test('anti-fraud flags and messages kept', () {
      final p = _prompt('ايديتا');
      for (final s in [
        'isHandwritten = true',
        'isThermalPosReceipt = false',
        'isTampered = true',
        'isScreenCapture = true',
        'عذراً، تم رفض الفاتورة لأنها محررة بخط اليد',
        'تم تسليم الهدية',
        'AIR-26',
        'totalLinePrice = 198',
      ]) {
        expect(p, contains(s));
      }
    });

    test('single-receipt rule (AIR-61) vs complementary receipts', () {
      expect(_prompt('ايديتا'), contains('AIR-61'));
      expect(_prompt('ايديتا'), contains('مخالفة معايير الأهلية'));
      final c = _prompt('ايديتا', complementary: true);
      expect(c, contains('" + "'));
      expect(c.contains('مخالفة معايير الأهلية'), isFalse);
    });

    test('branch directory: every branch code kept, chain fields listed once', () {
      final bs = [_branch('فرع ستانلي', '218'), _branch('فرع سموحة', '211')];
      final p = _prompt('ايديتا',
          branches: bs, chain: 'أسواق فتح الله', allowed: ['فرع ستانلي']);
      expect(p, contains('فرع ستانلي: كود 218'));
      expect(p, contains('فرع سموحة: كود 211'));
      expect(p, contains('رأس: KH-218'));
      expect('334-871-552'.allMatches(p).length, 1);
      expect('15118'.allMatches(p).length, 1);
      expect(p, contains('"{S}/YYMMDD"'));
      expect(p, contains('الفروع المعتمدة حصراً: [فرع ستانلي]'));
      expect('أسواق فتح الله'.allMatches(p).length, lessThanOrEqualTo(2));
    });
  });

  group('response schema / parser unchanged', () {
    test('fast-tier schema field names, types and required list unchanged', () {
      final shape = _strip(AiReceiptService.fastTierSchemaForTest.toJson());
      expect(jsonEncode(shape), _schemaShape);
    });

    test('parser accepts a schema-shaped response', () {
      final r = AiReceiptAnalysisResult.fromJson({
        'isValid': true,
        'receiptNumber': '134/5/218/301026',
        'targetCompanyTotal': 300.0,
        'receiptDate': '30/10/2026',
        'storeChainDetected': 'أسواق فتح الله',
        'branchDetected': 'فرع ستانلي',
        'isBranchMatched': true,
        'storeId': '218',
        'posNumber': '5',
        'taxNumber': '',
        'commercialReg': '',
        'hotline': '',
        'branchAddress': '',
        'isHandwritten': false,
        'isThermalPosReceipt': true,
        'isTampered': false,
        'isScreenCapture': false,
        'fraudRiskScore': 0,
        'fraudReasons': <String>[],
        'extractedProducts': [
          {
            'name': 'مولتو',
            'price': 30.0,
            'quantity': 10,
            'isTargetCompany': true,
            'barcode': '6223000000000',
            'originalPrice': 0,
            'discountAmount': 0,
            'discountPercent': 0,
            'totalLinePrice': 300.0,
          }
        ],
        'message': 'ok',
        'unfulfilledConditions': <String>[],
      }, durationMs: 0, targetCompany: 'ايديتا');
      expect(r.receiptNumber, '134/5/218/301026');
      expect(r.isThermalPosReceipt, isTrue);
      expect(r.isBranchMatched, isTrue);
      expect(r.extractedProducts.single.quantity, 10);
      expect(r.extractedProducts.single.isTargetCompany, isTrue);
    });
  });
}
