import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:al_mraay/features/admin/domain/retail_chain_model.dart';
import 'package:al_mraay/core/services/branch_signature_ai_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('BranchReceiptSignature & BranchModel Serialization Tests', () {
    test('BranchReceiptSignature parses and converts to map correctly', () {
      final sig = BranchReceiptSignature(
        storeId: '502',
        posNumberPattern: 'PoS: 1',
        receiptPattern: '399/1/502/170826',
        headerKeywords: ['بيت الجملة', 'فرع المنشية', '15677'],
        footerKeywords: ['شكرا لزيارتكم', 'الاسترجاع خلال 14 يوم'],
        taxNumber: '416-187-382',
        commercialReg: '123456',
        hotline: '15677',
        extractedSummary: 'بصمة فرع المنشية - بيت الجملة (Store ID: 502)',
        confidenceScore: 0.98,
        scannedAt: DateTime(2026, 8, 18),
      );

      expect(sig.hasSignature, true);
      expect(sig.storeId, '502');
      expect(sig.taxNumber, '416-187-382');

      final map = sig.toMap();
      expect(map['storeId'], '502');
      expect(map['posNumberPattern'], 'PoS: 1');
      expect(map['receiptPattern'], '399/1/502/170826');
      expect(map['taxNumber'], '416-187-382');
      expect(map['hotline'], '15677');
      expect(map['confidenceScore'], 0.98);

      final fromMap = BranchReceiptSignature.fromMap(map);
      expect(fromMap.storeId, '502');
      expect(fromMap.headerKeywords.length, 3);
      expect(fromMap.hotline, '15677');
    });

    test('BranchModel embeds and restores receiptSignature accurately', () {
      final signature = BranchReceiptSignature(
        storeId: '440',
        posNumberPattern: 'PoS: 6',
        receiptPattern: '178/6/440/170826',
        headerKeywords: ['KH GOMLA MARKET', 'RAGHEB'],
        taxNumber: '321-654-987',
        hotline: '033630066',
        extractedSummary: 'بصمة فرع راغب - جملة ماركت (Store: 440)',
      );

      final branch = BranchModel(
        id: 'branch-gomla-ragheb',
        retailChainId: 'gomla-market',
        retailChainName: 'جملة ماركت',
        branchName: 'فرع راغب',
        city: 'الإسكندرية',
        branchCode: 'GML-440',
        address: 'شارع راغب باشا - كرموز',
        receiptSignature: signature,
      );

      final firestoreMap = branch.toFirestore();
      expect(firestoreMap['retailChainName'], 'جملة ماركت');
      expect(firestoreMap['branchName'], 'فرع راغب');
      expect(firestoreMap['branchCode'], 'GML-440');
      expect(firestoreMap['receiptSignature'], isNotNull);
      expect(firestoreMap['receiptSignature']['storeId'], '440');
      expect(firestoreMap['receiptSignature']['receiptPattern'], '178/6/440/170826');

      final restored = BranchModel.fromMap(firestoreMap, 'branch-gomla-ragheb');
      expect(restored.id, 'branch-gomla-ragheb');
      expect(restored.receiptSignature, isNotNull);
      expect(restored.receiptSignature!.storeId, '440');
      expect(restored.receiptSignature!.receiptPattern, '178/6/440/170826');
      expect(restored.receiptSignature!.hasSignature, true);
    });
  });

  group('ExtractedBranchSignatureResult JSON Parsing & Matching Tests', () {
    test('Correctly parses Bayt El Gomla receipt signature with Store ID 502', () {
      final json = {
        'chainName': 'بيت الجملة',
        'chainSlug': 'beit-elgomla',
        'branchName': 'المنشية',
        'city': 'الإسكندرية',
        'branchCode': 'BGM-502',
        'storeId': '٥٠٢', // Eastern Arabic digits
        'posNumberPattern': 'PoS: ١',
        'receiptPattern': '399/1/502/170826',
        'sampleReceiptNumber': '399',
        'headerKeywords': ['بيت الجملة', 'المنشية', '15677'],
        'footerKeywords': ['شكرا لزيارتكم'],
        'taxNumber': '٤١٦-١٨٧-٣٨٢',
        'commercialReg': '12345',
        'hotline': '15677',
        'address': 'المنشية - الإسكندرية',
        'extractedSummary': 'تم استخراج بصمة فرع المنشية بسلسلة بيت الجملة بنجاح.',
        'confidenceScore': 0.97,
      };

      final existingChains = [
        RetailChainModel(id: 'chain-1', name: 'بيت الجملة', slug: 'beit-elgomla'),
        RetailChainModel(id: 'chain-2', name: 'كارفور', slug: 'carrefour'),
      ];

      final result = ExtractedBranchSignatureResult.fromJson(json, existingChains: existingChains);

      expect(result.chainName, 'بيت الجملة');
      expect(result.chainSlug, 'beit-elgomla');
      expect(result.branchName, 'المنشية');
      expect(result.city, 'الإسكندرية');
      expect(result.storeId, '502'); // Normalized to Western digits
      expect(result.taxNumber, '416-187-382'); // Normalized
      expect(result.isMatchedWithExistingChain, true);
      expect(result.matchedChainId, 'chain-1');
      expect(result.confidenceScore, 0.97);

      final signature = result.toBranchReceiptSignature();
      expect(signature.storeId, '502');
      expect(signature.posNumberPattern, 'PoS: 1');
      expect(signature.taxNumber, '416-187-382');
    });

    test('Correctly parses LuLu Hypermarket Park Mall receipt signature with Store ID 3912', () {
      final json = {
        'chainName': 'لولو هايبر ماركت',
        'chainSlug': 'lulu',
        'branchName': 'The Park Mall - التجمع الخامس',
        'city': 'القاهرة الجديدة',
        'branchCode': 'LUL-3912',
        'storeId': '3912',
        'posNumberPattern': 'POS: 03',
        'receiptPattern': '663912003064822320260817142247',
        'sampleReceiptNumber': '648223',
        'headerKeywords': ['LuLu Hypermarket', 'The Park Mall', 'Cairo'],
        'footerKeywords': ['Happy Shopping'],
        'taxNumber': '100-200-300',
        'hotline': '16000',
        'extractedSummary': 'بصمة فرع لولو هايبر ماركت - ذا بارك مول التجمع.',
        'confidenceScore': 0.99,
      };

      final result = ExtractedBranchSignatureResult.fromJson(json);

      expect(result.chainName, 'لولو هايبر ماركت');
      expect(result.storeId, '3912');
      expect(result.branchCode, 'LUL-3912');
      expect(result.receiptPattern, '663912003064822320260817142247');
      expect(result.confidenceScore, 0.99);
    });

    test('Correctly parses Hyper One Sphinx branch receipt signature with Store ID 4', () {
      final json = {
        'chainName': 'هايبر وان',
        'chainSlug': 'hyper-one',
        'branchName': 'فرع سفنكس',
        'city': 'الجيزة',
        'branchCode': 'HYP-04',
        'storeId': '4',
        'posNumberPattern': 'POS: 21',
        'receiptPattern': '18/21/4/170826',
        'sampleReceiptNumber': '18',
        'headerKeywords': ['هايبر وان', 'فرع سفنكس', 'طريق القاهرة الإسكندرية الصحراوي'],
        'extractedSummary': 'بصمة فرع سفنكس - هايبر وان (Store ID: 4 / POS: 21).',
        'confidenceScore': 0.96,
      };

      final result = ExtractedBranchSignatureResult.fromJson(json);

      expect(result.chainName, 'هايبر وان');
      expect(result.branchName, 'فرع سفنكس');
      expect(result.storeId, '4');
      expect(result.posNumberPattern, 'POS: 21');
      expect(result.receiptPattern, '18/21/4/170826');
    });
  });
}
