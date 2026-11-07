import 'package:al_mraay/core/services/chain_products_intelligence_service.dart';
import 'package:al_mraay/core/utils/branch_chain_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const multi = 'جملة ماركت - أسواق فتح الله';

  test('multi-chain strings normalize to empty', () {
    expect(ChainProductsIntelligenceService.normalizeRetailChain(multi), '');
    expect(ChainProductsIntelligenceService.normalizeRetailChain('فتح الله'), 'أسواق فتح الله');
    expect(ChainProductsIntelligenceService.normalizeRetailChain('بيت الجملة'), 'بيت الجملة');
    expect(ChainProductsIntelligenceService.normalizeRetailChain('جملة ماركت'), 'جملة ماركت');
  });

  test('المنتزه / جناكليس resolve to جملة ماركت via branch doc', () {
    for (final _ in ['المنتزه', 'جناكليس']) {
      expect(
        BranchChainResolver.resolveBranchDisplayChain(
            branchDocChain: 'جملة ماركت', receiptChain: multi, campaignChain: multi),
        'جملة ماركت',
      );
    }
  });

  test('الرحاب resolves to أسواق فتح الله', () {
    expect(
      BranchChainResolver.resolveBranchDisplayChain(
          branchDocChain: 'فتح الله', receiptChain: multi, campaignChain: multi),
      'أسواق فتح الله',
    );
    // No branch doc: receipt-detected chain wins.
    expect(
      BranchChainResolver.resolveBranchDisplayChain(receiptChain: 'Fathalla', campaignChain: multi),
      'أسواق فتح الله',
    );
  });

  test('multi-chain campaign name is never used as a fallback', () {
    expect(BranchChainResolver.resolveBranchDisplayChain(campaignChain: multi), '');
    expect(BranchChainResolver.resolveBranchDisplayChain(campaignChain: 'جملة ماركت'), 'جملة ماركت');
  });

  test('badge counts merged branches (20 daily rows -> 7 branches)', () {
    const branches = ['المنتزه', 'جناكليس', 'الرحاب', 'سموحة', 'ميامي', 'العجمي', 'سيدي بشر'];
    final rows = [for (var i = 0; i < 20; i++) branches[i % 7]];
    expect(BranchChainResolver.countMergedBranches(rows), 7);
  });
}
