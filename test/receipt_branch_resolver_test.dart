import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/utils/receipt_branch_resolver.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  EventModel ev(List<String> ids, List<String> names) =>
      EventModel.fromFirestoreMap('e1', {'branchIds': ids, 'branchNames': names, 'eventName': 'x'});

  test('detected Rehab resolves to fathalla_250', () {
    final r = ReceiptBranchResolver.resolve(
        ev(['fathalla_224', 'fathalla_250'], ['عجمي ستار', 'فرع مدينة الرحاب (القاهرة)']),
        'فرع مدينة الرحاب');
    expect(r.id, 'fathalla_250');
  });
  test('empty detection with several branches is unresolved (no first-branch guess)', () {
    final r = ReceiptBranchResolver.resolve(ev(['a', 'b'], ['A', 'B']), '');
    expect(r.id, isNull);
  });
  // 2.0.173 (c67358d): one campaign branch is not a reason to assign it;
  // an empty detection stays unresolved, a matching name still resolves.
  test('single-branch campaign with no detected branch stays unresolved', () {
    expect(ReceiptBranchResolver.resolve(ev(['a'], ['A']), '').id, isNull);
  });
  test('single-branch campaign resolves when the detected name matches', () {
    expect(ReceiptBranchResolver.resolve(ev(['a'], ['فرع مدينة الرحاب']), 'فرع مدينة الرحاب').id, 'a');
  });
}
