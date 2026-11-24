import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/campaign_edit_save.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

// C-02: the editor opened the campaign at total 100 / remaining 50; reps then
// claimed 10 more (stored remaining 40) before the admin pressed save.
AllocatedPrize _row(int total, int remaining, {String giftId = 'g150', String branch = 'b1'}) => AllocatedPrize(
      giftId: giftId,
      name: 'فواتشر 150',
      allocatedQuantity: total,
      remainingQuantity: remaining,
      branchId: branch,
      branchName: 'فرع $branch',
      giftType: 'voucher',
      unitValue: 150,
    );

EventModel _campaign({String name = 'Cadbury', List<AllocatedPrize>? prizes, bool isActive = true}) => EventModel(
      id: 'E1',
      eventName: name,
      targetCompany: 'Cadbury',
      companySlug: 'cadbury',
      minimumSpend: 0,
      isActive: isActive,
      allocatedPrizes: prizes ?? [_row(100, 50)],
    );

Map<String, dynamic> _stored({int total = 100, int remaining = 40, bool isActive = false, List<AllocatedPrize>? rows}) => {
      ..._campaign(isActive: isActive).toFirestore(),
      'allocatedPrizes': (rows ?? [_row(total, remaining)]).map((p) => p.toMap()).toList(),
    };

int _remaining(Map<String, dynamic> patch, [int i = 0]) =>
    ((patch['allocatedPrizes'] as List)[i] as Map)['remainingQuantity'] as int;

void main() {
  final opened = _campaign();

  test('rename only: stock rows and isActive are not written (remaining stays 40)', () {
    final patch = CampaignEditSave.buildEditPatch(
      draft: _campaign(name: 'Cadbury renamed', prizes: [_row(100, 50)]),
      opened: opened,
      currentData: _stored(),
      updatedBy: 'admin1',
    );
    expect(patch['eventName'], 'Cadbury renamed');
    expect(patch.containsKey('allocatedPrizes'), isFalse);
    expect(patch.containsKey('isActive'), isFalse);
    expect(patch.containsKey('isPromoterActive'), isFalse);
    expect(patch.containsKey('spendLadderMode'), isFalse);
    expect(patch.containsKey('createdAt'), isFalse);
    expect(patch.containsKey('targetCompany'), isFalse, reason: 'unchanged fields are not written');
    expect(patch['updatedBy'], 'admin1');
    expect(patch['updatedAt'], isA<FieldValue>());
    // Firestore update() merges: the stored 40 survives.
    final after = {..._stored(), ...patch};
    expect(((after['allocatedPrizes'] as List).first as Map)['remainingQuantity'], 40);
    expect(after['isActive'], isFalse, reason: 'auto-closed campaign is not re-activated');
  });

  test('100 -> 120 uses fresh remaining: 40 + 20 = 60', () {
    final patch = CampaignEditSave.buildEditPatch(
      draft: _campaign(prizes: [_row(120, 70)]),
      opened: opened,
      currentData: _stored(),
      updatedBy: 'admin1',
    );
    expect(_remaining(patch), 60);
    expect(((patch['allocatedPrizes'] as List).first as Map)['allocatedQuantity'], 120);
  });

  test('total below consumed is rejected with an Arabic message', () {
    // consumed now = 100 - 40 = 60
    expect(
      () => CampaignEditSave.mergeAllocationsForEdit(
        opened: [_row(100, 50)],
        draft: [_row(55, 5)],
        currentRaw: [_row(100, 40).toMap()],
      ),
      throwsA(isA<CampaignEditRejected>().having((e) => e.message, 'message', contains('أقل من المصروف فعلاً 60'))),
    );
  });

  test('removing a row with handed-out stock is rejected', () {
    expect(
      () => CampaignEditSave.mergeAllocationsForEdit(
        opened: [_row(100, 50), _row(10, 10, giftId: 'g25')],
        draft: [_row(10, 10, giftId: 'g25')],
        currentRaw: [_row(100, 40).toMap(), _row(10, 10, giftId: 'g25').toMap()],
      ),
      throwsA(isA<CampaignEditRejected>().having((e) => e.message, 'message', contains('لا يمكن حذف هدية'))),
    );
  });

  test('removing an untouched-stock row is allowed', () {
    final out = CampaignEditSave.mergeAllocationsForEdit(
      opened: [_row(100, 50), _row(10, 10, giftId: 'g25')],
      draft: [_row(100, 50)],
      currentRaw: [_row(100, 40).toMap(), _row(10, 10, giftId: 'g25').toMap()],
    )!;
    expect(out.length, 1);
    expect(out.first['remainingQuantity'], 40, reason: 'untouched row written exactly as stored');
  });

  test('a new row starts full', () {
    final out = CampaignEditSave.mergeAllocationsForEdit(
      opened: [_row(100, 50)],
      draft: [_row(100, 50), _row(30, 0, branch: 'b2')],
      currentRaw: [_row(100, 40).toMap()],
    )!;
    expect(out.length, 2);
    expect(out[0]['remainingQuantity'], 40);
    expect(out[1]['branchId'], 'b2');
    expect(out[1]['remainingQuantity'], 30);
  });

  test('rows added by someone else meanwhile are kept', () {
    final out = CampaignEditSave.mergeAllocationsForEdit(
      opened: [_row(100, 50)],
      draft: [_row(120, 70)],
      currentRaw: [_row(100, 40).toMap(), _row(5, 5, branch: 'b9').toMap()],
    )!;
    expect(out.map((r) => r['branchId']), ['b1', 'b9']);
    expect(out[0]['remainingQuantity'], 60);
  });

  test('two branch rows of one gift never share a stored row', () {
    final out = CampaignEditSave.mergeAllocationsForEdit(
      opened: [_row(100, 50), _row(20, 20, branch: 'b2')],
      draft: [_row(110, 0), _row(25, 0, branch: 'b2')],
      currentRaw: [_row(100, 40).toMap(), _row(20, 18, branch: 'b2').toMap()],
    )!;
    expect(out[0]['remainingQuantity'], 50); // 40 + 10
    expect(out[1]['remainingQuantity'], 23); // 18 + 5
  });

  test('no quantity or row change returns null', () {
    expect(
      CampaignEditSave.mergeAllocationsForEdit(
        opened: [_row(100, 50)],
        draft: [_row(100, 50)],
        currentRaw: [_row(100, 40).toMap()],
      ),
      isNull,
    );
  });
}
