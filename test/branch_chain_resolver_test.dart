import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/utils/branch_chain_resolver.dart';
import 'package:al_mraay/features/admin/domain/retail_chain_model.dart';

BranchModel b(String id, String chainId, String chainName, String name, {String city = ''}) =>
    BranchModel(id: id, retailChainId: chainId, retailChainName: chainName, branchName: name, city: city, branchCode: '');

void main() {
  const fName = 'أسواق فتح الله';
  const gName = 'جملة ماركت';
  // Sorted by branchName like the service does: panda's Rehab sorts first.
  final db = [
    b('panda_pnd-rehab', 'panda', 'بنده', 'فرع الرحاب (Rehab Super)'),
    b('fathalla_211', 'fathalla', fName, 'فرع سموحة'),
    b('fathalla_250', 'fathalla', fName, 'فرع مدينة الرحاب', city: 'القاهرة'),
    b('gomla-market_gml-413', 'gomla-market', gName, 'جناكليس'),
    b('gomla-market_gml-418', 'gomla-market', gName, 'المنتزه'),
  ];

  test('Rehab (fathalla_250) is only under فتح الله, never جملة ماركت', () {
    final g = BranchChainResolver.groupBranchesByChain(
      retailChainId: 'fathalla,gomla-market',
      retailChainName: '$fName • $gName',
      branchIds: ['fathalla_211', 'fathalla_250', 'gomla-market_gml-418', 'gomla-market_gml-413'],
      branchNames: ['سموحة', 'فرع مدينة الرحاب (القاهرة)', 'المنتزه (الإسكندرية)', 'جناكليس (الإسكندرية)'],
      dbBranches: db,
    );
    expect(g[fName], ['سموحة', 'فرع مدينة الرحاب (القاهرة)']);
    expect(g[gName], ['المنتزه (الإسكندرية)', 'جناكليس (الإسكندرية)']);
  });

  test('legacy event without ids: name match prefers event chains over outside chains', () {
    final g = BranchChainResolver.groupBranchesByChain(
      retailChainId: 'fathalla,gomla-market',
      retailChainName: '$fName • $gName',
      branchIds: const [],
      branchNames: ['فرع مدينة الرحاب (القاهرة)', 'المنتزه'],
      dbBranches: db,
    );
    expect(g[fName], ['فرع مدينة الرحاب (القاهرة)']);
    expect(g[gName], ['المنتزه']);
  });

  test('name match only to a chain outside the event is attributed to no event chain', () {
    final g = BranchChainResolver.groupBranchesByChain(
      retailChainId: 'fathalla,gomla-market',
      retailChainName: '$fName • $gName',
      branchIds: const [],
      branchNames: ['فرع الرحاب'],
      dbBranches: [db.first, db[3]],
    );
    expect(g[fName], isEmpty);
    expect(g[gName], isEmpty);
  });

  test('id of a branch from an outside chain is not attributed', () {
    final g = BranchChainResolver.groupBranchesByChain(
      retailChainId: 'fathalla,gomla-market',
      retailChainName: '$fName • $gName',
      branchIds: ['panda_pnd-rehab'],
      branchNames: ['فرع الرحاب'],
      dbBranches: db,
    );
    expect(g.values.every((l) => l.isEmpty), isTrue);
  });

  test('single chain gets all branches; unknown legacy fallback configurable', () {
    final one = BranchChainResolver.groupBranchesByChain(
      retailChainId: 'fathalla', retailChainName: fName,
      branchIds: const [], branchNames: ['x', 'y'], dbBranches: const []);
    expect(one[fName], ['x', 'y']);
    final first = BranchChainResolver.groupBranchesByChain(
      retailChainId: 'fathalla,gomla-market', retailChainName: '$fName • $gName',
      branchIds: const [], branchNames: ['مجهول'], dbBranches: const [], unknownToAllChains: false);
    expect(first[fName], ['مجهول']);
    expect(first[gName], isEmpty);
  });
}
