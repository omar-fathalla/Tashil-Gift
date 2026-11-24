import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/company_portal/domain/branch_claim_tally.dart';

// TG-2 Smouha: voucher 150, allocated 100. Old app versions saved 51 units
// without a giftId, the current app saved 49 with it. Stored remaining is 0;
// the table used to show 100 - 49 = 51.
const v150 = '4QDy4H8psECEP4AnJSON';
const v100 = 'beGiYXcMAsW78OGevW5d';
const ids = {v150, v100};
const names = {'فواتشر 150 جنيه', 'فواتشر 100 جنيه'};

int _claimed(BranchClaimTally t, String id, String name, double value) => t.claimedFor(
      giftId: id,
      giftName: name,
      isVoucher: true,
      unitValue: value,
      knownGiftIds: ids,
      knownGiftNames: names,
    );

void main() {
  test('Smouha: 51 legacy + 49 with giftId -> 100 claimed, remaining 0 (not 51)', () {
    final t = BranchClaimTally();
    for (var i = 0; i < 51; i++) {
      t.addEntry(giftId: '', giftName: 'فواتشر 150 جنيه', qty: 1);
    }
    for (var i = 0; i < 49; i++) {
      t.addEntry(giftId: v150, giftName: 'فواتشر 150 جنيه', qty: 1);
    }
    final claimed = _claimed(t, v150, 'فواتشر 150 جنيه', 150);
    expect(claimed, 100);
    expect((100 - claimed).clamp(0, 100), 0);
  });

  test('an entry with both giftId and name is counted once', () {
    final t = BranchClaimTally()..addEntry(giftId: v150, giftName: 'فواتشر 150 جنيه', qty: 2);
    expect(_claimed(t, v150, 'فواتشر 150 جنيه', 150), 2);
  });

  test('entries of another gift column are not counted', () {
    final t = BranchClaimTally()
      ..addEntry(giftId: v100, giftName: 'فواتشر 100 جنيه', qty: 3)
      ..addEntry(giftId: '', giftName: 'فواتشر 100 جنيه', qty: 4);
    expect(_claimed(t, v150, 'فواتشر 150 جنيه', 150), 0);
    expect(_claimed(t, v100, 'فواتشر 100 جنيه', 100), 7);
  });

  test('name matching is case/space insensitive and unknown ids fall back to the name', () {
    final t = BranchClaimTally()
      ..addEntry(giftId: 'some-other-doc', giftName: '  فواتشر 150 جنيه ', qty: 1)
      ..addEntry(giftId: '', giftName: 'Lunch Box', qty: 1);
    expect(_claimed(t, v150, 'فواتشر 150 جنيه', 150), 1);
    expect(
      t.claimedFor(
        giftId: 'lb', giftName: 'lunch box', isVoucher: false, unitValue: 0,
        knownGiftIds: {'lb'}, knownGiftNames: {'lunch box'}),
      1,
    );
  });

  test('legacy receipts without gift entries keep the loose name/denomination match', () {
    final t = BranchClaimTally()
      ..addLegacyKey('voucher_150', 1)
      ..addLegacyKey('قسيمة 150', 1)
      ..addEntry(giftId: v150, giftName: 'فواتشر 150 جنيه', qty: 1);
    expect(_claimed(t, v150, 'فواتشر 150 جنيه', 150), 3);
  });
}
