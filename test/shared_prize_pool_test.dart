import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/shared_prize_pool.dart';

void main() {
  test('campaign without rows lists active siblings with rows', () {
    final ids = sharedPoolSourceEventIds(eventId: 'NEW', companyEvents: const [
      (id: 'NEW', isActive: true, rowCount: 0),
      (id: 'OLD', isActive: true, rowCount: 15),
      (id: 'OFF', isActive: false, rowCount: 5),
    ]);
    expect(ids, ['OLD']);
  });
  test('campaign with own rows uses none', () {
    expect(sharedPoolSourceEventIds(eventId: 'OLD', companyEvents: const [
      (id: 'OLD', isActive: true, rowCount: 15),
      (id: 'X', isActive: true, rowCount: 3),
    ]), isEmpty);
  });
  test('campaign_only opts out', () {
    expect(sharedPoolEnabledFor({'balanceMode': 'campaign_only'}), isFalse);
    expect(sharedPoolEnabledFor({}), isTrue);
  });
}
