import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/retail_chain_model.dart';

void main() {
  group('Retail Chains & Branches Deduplication Engine Tests', () {
    test('Deduplication correctly detects duplicate branch codes under the same chain', () {
      final branches = [
        BranchModel(
          id: 'b1',
          retailChainId: 'beit-elgomla',
          retailChainName: 'بيت الجملة',
          branchName: 'المنشية',
          city: 'الإسكندرية',
          branchCode: 'BGM-502',
        ),
        BranchModel(
          id: 'b2',
          retailChainId: 'beit-elgomla',
          retailChainName: 'بيت الجملة',
          branchName: 'المنشية',
          city: 'الإسكندرية',
          branchCode: 'BGM-502',
        ),
        BranchModel(
          id: 'b3',
          retailChainId: 'beit-elgomla',
          retailChainName: 'بيت الجملة',
          branchName: 'العصافرة',
          city: 'الإسكندرية',
          branchCode: 'BGM-ASF',
        ),
      ];

      final Map<String, BranchModel> uniqueMap = {};
      for (final branch in branches) {
        final chainId = branch.retailChainId.trim().toLowerCase();
        final cleanCode = branch.branchCode.trim().toLowerCase();
        final cleanName = branch.branchName.trim().toLowerCase();
        final storeId = branch.receiptSignature?.storeId.trim().toLowerCase() ?? '';

        String primaryKey;
        if (cleanCode.isNotEmpty && cleanCode != 'def' && cleanCode != '0') {
          primaryKey = '$chainId:code:$cleanCode';
        } else if (storeId.isNotEmpty) {
          primaryKey = '$chainId:store:$storeId';
        } else {
          primaryKey = '$chainId:name:$cleanName';
        }

        if (!uniqueMap.containsKey(primaryKey)) {
          uniqueMap[primaryKey] = branch;
        }
      }

      expect(uniqueMap.length, 2);
      expect(uniqueMap.containsKey('beit-elgomla:code:bgm-502'), isTrue);
      expect(uniqueMap.containsKey('beit-elgomla:code:bgm-asf'), isTrue);
    });

    test('Deduplication favors records with Smart POS Receipt Signature over bare records', () {
      final bareBranch = BranchModel(
        id: 'b1',
        retailChainId: 'beit-elgomla',
        retailChainName: 'بيت الجملة',
        branchName: 'المنشية',
        city: 'الإسكندرية',
        branchCode: 'BGM-502',
      );

      final richBranch = BranchModel(
        id: 'b2',
        retailChainId: 'beit-elgomla',
        retailChainName: 'بيت الجملة',
        branchName: 'المنشية',
        city: 'الإسكندرية',
        branchCode: 'BGM-502',
        receiptSignature: BranchReceiptSignature(
          storeId: '502',
          posNumberPattern: 'PoS: 1',
          receiptPattern: '6650201',
          headerKeywords: ['بيت الجملة'],
          confidenceScore: 0.98,
        ),
      );

      final list = [bareBranch, richBranch];
      final Map<String, BranchModel> uniqueMap = {};

      for (final branch in list) {
        final chainId = branch.retailChainId.trim().toLowerCase();
        final cleanCode = branch.branchCode.trim().toLowerCase();
        final key = '$chainId:code:$cleanCode';

        if (!uniqueMap.containsKey(key)) {
          uniqueMap[key] = branch;
        } else {
          final existing = uniqueMap[key]!;
          if (existing.receiptSignature == null && branch.receiptSignature != null) {
            uniqueMap[key] = branch;
          }
        }
      }

      expect(uniqueMap.length, 1);
      final retained = uniqueMap['beit-elgomla:code:bgm-502']!;
      expect(retained.id, 'b2');
      expect(retained.receiptSignature, isNotNull);
      expect(retained.receiptSignature?.storeId, '502');
    });

    test('RetailChainModel deduplication by slug and name', () {
      final chains = [
        RetailChainModel(id: 'c1', name: 'أسواق فتح الله', slug: 'fathalla'),
        RetailChainModel(id: 'c2', name: 'أسواق فتح الله', slug: 'fathalla'),
        RetailChainModel(id: 'c3', name: 'كارفور مصر', slug: 'carrefour'),
      ];

      final Map<String, RetailChainModel> uniqueMap = {};
      for (final c in chains) {
        final key = c.slug.isNotEmpty ? c.slug.toLowerCase() : c.name.toLowerCase();
        if (!uniqueMap.containsKey(key)) {
          uniqueMap[key] = c;
        }
      }

      expect(uniqueMap.length, 2);
      expect(uniqueMap.containsKey('fathalla'), isTrue);
      expect(uniqueMap.containsKey('carrefour'), isTrue);
    });
  });
}
