import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/utils/receipt_branch_resolver.dart';
import 'package:al_mraay/core/utils/store_code_branch_resolver.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/admin/domain/retail_chain_model.dart';

BranchModel _g(String id, String code, String storeId, String name, {String pattern = ''}) =>
    BranchModel(
      id: id,
      retailChainId: 'gomla-market',
      retailChainName: 'جملة ماركت',
      branchName: name,
      branchCode: code,
      receiptSignature: BranchReceiptSignature(storeId: storeId, receiptPattern: pattern),
    );

void main() {
  // Real 2026-11-01 case: Gomla branches have branchCode GML-418, storeId 418.
  final gomla = [
    _g('gomla-market_gml-418', 'GML-418', '418', 'المنتزه',
        pattern: 'Trans/PoS/Store/Date (DDMMYY)'),
    _g('gomla-market_gml-413', 'GML-413', '413', 'جناكليس',
        pattern: 'Trans: {Trans} / Store: {Store} / PoS: {PoS}'),
  ];

  test('codes() yields branchCode, storeId and digits', () {
    expect(StoreCodeBranchResolver.codes(gomla.first), containsAll(['GML-418', '418']));
  });

  test('104/14/418/011126 resolves to GML-418 (letters in branchCode)', () {
    expect(StoreCodeBranchResolver.resolve('104/14/418/011126', gomla)?.id,
        'gomla-market_gml-418');
    expect(StoreCodeBranchResolver.resolve('121/1/413/011126', gomla)?.id,
        'gomla-market_gml-413');
  });

  test('lower-case code in pattern still matches', () {
    final b = [_g('x_gml-418', 'gml-418', '', 'المنتزه')];
    expect(StoreCodeBranchResolver.resolve('104/14/418/011126', b)?.id, 'x_gml-418');
  });

  test('unknown store code stays null', () {
    expect(StoreCodeBranchResolver.resolve('104/14/999/011126', gomla), isNull);
  });

  final ids = ['fathalla_241', 'fathalla_211', 'gomla-market_gml-418', 'gomla-market_gml-413'];
  final names = ['فرع المحلة الكبري (الغربية)', 'فرع سموحة (الإسكندرية)', 'المنتزه (الإسكندرية)', 'جناكليس (الإسكندرية)'];

  test('campaignBranchIndex accepts ..._gml-418 for 418 and keeps _211', () {
    expect(StoreCodeBranchResolver.campaignBranchIndex('104/14/418/011126', ids), 2);
    expect(StoreCodeBranchResolver.campaignBranchIndex('123/14/211/011126', ids), 1);
    expect(StoreCodeBranchResolver.campaignBranchIndex('1/1/999/011126', ids), isNull);
  });

  test('campaignBranchName works with no branch docs', () {
    expect(StoreCodeBranchResolver.campaignBranchName('104/14/418/011126', ids, names),
        'المنتزه (الإسكندرية)');
    expect(StoreCodeBranchResolver.campaignBranchName('104/14/418/011126', ids, const []), isNull);
  });

  test('ReceiptBranchResolver gives branch_id for a bare "418" detection', () {
    final ev = EventModel.fromFirestoreMap('e1', {'branchIds': ids, 'branchNames': names});
    final r = ReceiptBranchResolver.resolve(ev, '418', receiptNumber: '104/14/418/011126');
    expect(r.id, 'gomla-market_gml-418');
    expect(r.name, 'المنتزه (الإسكندرية)');
  });
}
