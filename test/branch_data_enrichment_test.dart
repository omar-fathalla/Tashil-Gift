import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/retail_chain_model.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';

void main() {
  group('Branch Data Harvesting & Enrichment Standard (AIR-51)', () {
    test('BranchPendingEnrichment correctly detects actionable data', () {
      final emptyEnrichment = BranchPendingEnrichment();
      expect(emptyEnrichment.hasActionableData, isFalse);

      final withStoreId = BranchPendingEnrichment(storeId: '1');
      expect(withStoreId.hasActionableData, isTrue);

      final withPos = BranchPendingEnrichment(posNumber: '9');
      expect(withPos.hasActionableData, isTrue);

      final withAddress = BranchPendingEnrichment(branchAddress: 'مدخل 2 الشيخ زايد');
      expect(withAddress.hasActionableData, isTrue);

      final fullEnrichment = BranchPendingEnrichment(
        storeId: '1',
        posNumber: '9',
        taxNumber: '100-200-300',
        commercialReg: '12345',
        hotline: '16404',
        branchAddress: 'مدخل 2، محور 26 يوليو، الشيخ زايد',
        receiptNumber: '858/9/1/100926',
        receiptDate: '10/09/2026',
      );

      expect(fullEnrichment.hasActionableData, isTrue);
      expect(fullEnrichment.storeId, '1');
      expect(fullEnrichment.posNumber, '9');
      expect(fullEnrichment.taxNumber, '100-200-300');
      expect(fullEnrichment.commercialReg, '12345');
      expect(fullEnrichment.hotline, '16404');
      expect(fullEnrichment.branchAddress, 'مدخل 2، محور 26 يوليو، الشيخ زايد');
    });

    test('BranchPendingEnrichment serialization and deserialization preserves all fields', () {
      final original = BranchPendingEnrichment(
        storeId: '1',
        posNumber: '9',
        taxNumber: '100-200-300',
        commercialReg: '12345',
        hotline: '16404',
        branchAddress: 'هايبر وان الشيخ زايد',
        receiptNumber: '858/9/1/100926',
        receiptDate: '10/09/2026',
        sourceReceiptUrl: 'https://storage.example.com/receipts/r1.jpg',
      );

      final map = original.toMap();
      final reconstructed = BranchPendingEnrichment.fromMap(map);

      expect(reconstructed.storeId, original.storeId);
      expect(reconstructed.posNumber, original.posNumber);
      expect(reconstructed.taxNumber, original.taxNumber);
      expect(reconstructed.commercialReg, original.commercialReg);
      expect(reconstructed.hotline, original.hotline);
      expect(reconstructed.branchAddress, original.branchAddress);
      expect(reconstructed.receiptNumber, original.receiptNumber);
      expect(reconstructed.receiptDate, original.receiptDate);
      expect(reconstructed.sourceReceiptUrl, original.sourceReceiptUrl);
    });

    test('BranchModel integrates pendingEnrichment and clears on merge', () {
      final initialBranch = BranchModel(
        id: 'branch-zayed',
        retailChainId: 'hyper-one',
        retailChainName: 'هايبر وان',
        branchName: 'الشيخ زايد (الجيزة)',
        branchCode: '',
        address: '',
      );

      expect(initialBranch.pendingEnrichment, isNull);

      final enrichment = BranchPendingEnrichment(
        storeId: '1',
        posNumber: '9',
        branchAddress: 'مدخل 2 الشيخ زايد',
        receiptNumber: '858/9/1/100926',
      );

      // Staged enrichment
      final stagedBranch = initialBranch.copyWith(
        pendingEnrichment: enrichment,
      );

      expect(stagedBranch.pendingEnrichment, isNotNull);
      expect(stagedBranch.pendingEnrichment!.storeId, '1');
      expect(stagedBranch.pendingEnrichment!.posNumber, '9');
      expect(stagedBranch.branchCode, isEmpty); // not merged yet

      // After admin approves and merges:
      final mergedBranch = stagedBranch.copyWith(
        branchCode: enrichment.storeId,
        address: enrichment.branchAddress,
        receiptSignature: BranchReceiptSignature(
          storeId: enrichment.storeId,
          posNumberPattern: enrichment.posNumber,
          receiptPattern: '',
          headerKeywords: [],
          footerKeywords: [],
          taxNumber: '',
          commercialReg: '',
          hotline: '',
          sampleReceiptUrl: '',
          extractedSummary: '',
        ),
        clearPendingEnrichment: true,
      );

      expect(mergedBranch.branchCode, '1');
      expect(mergedBranch.address, 'مدخل 2 الشيخ زايد');
      expect(mergedBranch.receiptSignature?.storeId, '1');
      expect(mergedBranch.receiptSignature?.posNumberPattern, '9');
      expect(mergedBranch.pendingEnrichment, isNull); // cleared
    });

    test('AiReceiptAnalysisResult extracts auxiliary store & pos metadata', () {
      final json = {
        'is_valid': true,
        'message': 'فاتورة صحيحة',
        'store_chain_detected': 'هايبر وان',
        'branch_detected': 'فرع الشيخ زايد',
        'receipt_number': '858/9/1/100926',
        'receipt_date': '10/09/2026',
        'store_id': '1',
        'pos_number': '9',
        'tax_number': '100-200-300',
        'commercial_reg': '778899',
        'hotline': '16404',
        'branch_address': 'مدخل 2 الشيخ زايد',
        'extracted_products': [],
      };

      final result = AiReceiptAnalysisResult.fromJson(json);

      expect(result.storeChainDetected, 'هايبر وان');
      expect(result.branchDetected, 'فرع الشيخ زايد');
      expect(result.storeId, '1');
      expect(result.posNumber, '9');
      expect(result.taxNumber, '100-200-300');
      expect(result.commercialReg, '778899');
      expect(result.hotline, '16404');
      expect(result.branchAddress, 'مدخل 2 الشيخ زايد');
    });
  });
}
