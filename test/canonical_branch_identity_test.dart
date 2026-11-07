import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/utils/canonical_branch_resolver.dart';
import 'package:al_mraay/core/utils/receipt_branch_resolver.dart';
import 'package:al_mraay/core/utils/store_code_branch_resolver.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/admin/domain/retail_chain_model.dart';

const shortName = 'فرع طنطا (الغربية)';
const outletName = 'فرع طنطا اوت ليت (الغربية)';
const receipt243 = '137/4/243/061126';

EventModel _event({
  required List<String> ids,
  required List<String> names,
}) =>
    EventModel(
      id: 'e3',
      eventName: 'إيجيبت جلاكسي',
      targetCompany: 'جالاكسي',
      minimumSpend: 140,
      branchIds: ids,
      branchNames: names,
      isAllBranches: false,
    );

BranchModel _branch(String chainId, String code, String name) => BranchModel(
      id: '${chainId}_$code',
      retailChainId: chainId,
      retailChainName: chainId,
      branchName: name,
      branchCode: code,
      receiptSignature: BranchReceiptSignature(storeId: code),
    );

void main() {
  const ids231First = ['fathalla_231', 'fathalla_243'];
  const names231First = [shortName, outletName];
  const ids243First = ['fathalla_243', 'fathalla_231'];
  const names243First = [outletName, shortName];

  test('store 243 beats the short sibling in both campaign orders', () {
    for (final spec in [
      (ids231First, names231First),
      (ids243First, names243First),
    ]) {
      final saved = ReceiptBranchResolver.resolve(
        _event(ids: spec.$1, names: spec.$2),
        shortName,
        receiptNumber: receipt243,
      );
      expect(saved.certain, isTrue);
      expect(saved.id, 'fathalla_243');
      expect(saved.name, outletName);

      final fields = ReceiptBranchResolver.firestoreFields(
        _event(ids: spec.$1, names: spec.$2),
        detectedName: shortName,
        receiptNumber: receipt243,
      );
      expect(fields['branch_id'], 'fathalla_243');
      expect(fields['branch_detected'], outletName);
      expect(fields['canonical_branch'], outletName);
    }
  });

  test('exact short name is kept when there is no store code', () {
    final saved = ReceiptBranchResolver.resolve(
      _event(ids: ids231First, names: names231First),
      shortName,
    );
    expect(saved.certain, isTrue);
    expect(saved.id, 'fathalla_231');
    expect(saved.name, shortName);
  });

  test('exact outlet name is kept when the short sibling is listed first', () {
    final picked = CanonicalBranchResolver.pickCampaignName(
      'فرع طنطا اوت ليت',
      names231First,
    );
    expect(picked, outletName);
    final saved = ReceiptBranchResolver.resolve(
      _event(ids: ids231First, names: names231First),
      'فرع طنطا اوت ليت',
    );
    expect(saved.id, 'fathalla_243');
    expect(saved.name, outletName);
  });

  test('a partial outlet name is not assigned to either sibling', () {
    final match = CanonicalBranchResolver.resolve(
      branchIds: ids231First,
      branchNames: names231First,
      detectedName: 'طنطا اوت',
    );
    expect(match.certain, isFalse);
    expect(match.id, isNull);
    expect(match.name, 'طنطا اوت');
  });

  test('ambiguous and unknown codes do not select a branch', () {
    final ambiguous = CanonicalBranchResolver.resolve(
      branchIds: const ['fathalla_243', 'gomla_243'],
      branchNames: const [outletName, 'جملة 243'],
      detectedName: '',
      receiptNumber: receipt243,
    );
    expect(ambiguous.certain, isFalse);
    expect(ambiguous.id, isNull);

    final unknown = ReceiptBranchResolver.resolve(
      _event(ids: ids231First, names: names231First),
      'فرع غير معروف',
      receiptNumber: '137/4/999/061126',
    );
    expect(unknown.certain, isFalse);
    expect(unknown.id, isNull);
    expect(unknown.name, 'فرع غير معروف');
  });

  test('the same store code on two chains is not a unique branch-doc match', () {
    final branches = [
      _branch('fathalla', '243', 'فرع طنطا اوت ليت'),
      _branch('gomla', '243', 'جملة ماركت 243'),
    ];
    expect(StoreCodeBranchResolver.resolve(receipt243, branches), isNull);
    expect(
      StoreCodeBranchResolver.resolve(receipt243, [branches.first])?.id,
      'fathalla_243',
    );
  });

  test('no store code and an empty name stay unresolved', () {
    final match = CanonicalBranchResolver.resolve(
      branchIds: ids231First,
      branchNames: names231First,
    );
    expect(match.certain, isFalse);
    expect(match.id, isNull);
  });

  test('legacy row with branch id 243 shows the outlet even if the name is short', () {
    final match = CanonicalBranchResolver.resolve(
      branchIds: ids231First,
      branchNames: names231First,
      branchId: 'fathalla_243',
      detectedName: shortName,
      receiptNumber: receipt243,
    );
    expect(match.certain, isTrue);
    expect(match.id, 'fathalla_243');
    expect(match.name, outletName);
  });

  test('legacy row without an id uses a unique receipt code and otherwise keeps the text', () {
    final byCode = CanonicalBranchResolver.resolve(
      branchIds: ids243First,
      branchNames: names243First,
      detectedName: shortName,
      receiptNumber: receipt243,
    );
    expect(byCode.certain, isTrue);
    expect(byCode.id, 'fathalla_243');
    expect(byCode.name, outletName);

    final storedShort = CanonicalBranchResolver.resolve(
      branchIds: ids231First,
      branchNames: names231First,
      detectedName: shortName,
    );
    expect(storedShort.certain, isTrue);
    expect(storedShort.id, 'fathalla_231');
    expect(storedShort.name, shortName);

    final foreignId = CanonicalBranchResolver.resolve(
      branchIds: ids231First,
      branchNames: names231First,
      branchId: 'other_chain_10',
      detectedName: shortName,
      receiptNumber: receipt243,
    );
    expect(foreignId.certain, isFalse);
    expect(foreignId.id, 'other_chain_10');
    expect(foreignId.name, shortName);
  });
}
