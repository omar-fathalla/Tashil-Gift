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

  test('TAG-43: the save token is written only when given', () {
    final withToken = CampaignEditSave.buildEditPatch(
      draft: _campaign(name: 'x'),
      opened: opened,
      currentData: _stored(),
      updatedBy: 'admin1',
      saveToken: 'tok-1',
    );
    expect(withToken['lastSaveToken'], 'tok-1');
    final without = CampaignEditSave.buildEditPatch(
      draft: _campaign(name: 'x'),
      opened: opened,
      currentData: _stored(),
      updatedBy: 'admin1',
    );
    expect(without.containsKey('lastSaveToken'), isFalse);
    final attempt = CampaignEditAttempt(draft: _campaign(name: 'x'), opened: opened, updatedBy: 'admin1', saveToken: 'tok-2');
    expect(attempt.plan(_stored())?['lastSaveToken'], 'tok-2');
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

  group('row matching runs in passes (new branch row listed first)', () {
    test('matchRows: an existing branch keeps its own stored row', () {
      expect(
        CampaignEditSave.matchRows([_row(100, 40)], [_row(200, 200, branch: 'b0'), _row(100, 50)]),
        [-1, 0],
      );
    });

    test('[b0 200, b1 100] with stored b1 100/40: b1 stays 100/40, b0 new 200/200', () {
      final out = CampaignEditSave.mergeAllocationsForEdit(
        opened: [_row(100, 50)],
        draft: [_row(200, 0, branch: 'b0'), _row(100, 50)],
        currentRaw: [_row(100, 40).toMap()],
      )!;
      expect(out.length, 2);
      expect(out[0]['branchId'], 'b0');
      expect(out[0]['allocatedQuantity'], 200);
      expect(out[0]['remainingQuantity'], 200);
      expect(out[1]['branchId'], 'b1');
      expect(out[1]['allocatedQuantity'], 100);
      expect(out[1]['remainingQuantity'], 40, reason: 'the 60 handed out at b1 are kept');
    });

    test('[b0 30, b1, b2] saves without a rejection and keeps b1/b2 as stored', () {
      final out = CampaignEditSave.mergeAllocationsForEdit(
        opened: [_row(100, 50), _row(20, 20, branch: 'b2')],
        draft: [_row(30, 0, branch: 'b0'), _row(100, 50), _row(20, 20, branch: 'b2')],
        currentRaw: [_row(100, 40).toMap(), _row(20, 18, branch: 'b2').toMap()],
      )!;
      expect(out.map((r) => r['branchId']), ['b0', 'b1', 'b2']);
      expect(out.map((r) => r['remainingQuantity']), [30, 40, 18]);
    });

    test('a general row still falls back to the stored row of its gift', () {
      final out = CampaignEditSave.mergeAllocationsForEdit(
        opened: [_row(100, 50)],
        draft: [_row(120, 0, branch: '')],
        currentRaw: [_row(100, 40).toMap()],
      )!;
      expect(out.length, 1);
      expect(out[0]['remainingQuantity'], 60); // 40 + 20, consumed 60 kept
    });
  });

  group('save() result path: rejection is recorded, then thrown after the transaction', () {
    test('below-consumed edit: plan returns no patch and does not throw', () {
      final attempt = CampaignEditAttempt(
        draft: _campaign(prizes: [_row(55, 5)]),
        opened: opened,
        updatedBy: 'admin1',
      );
      final patch = attempt.plan(_stored()); // stored 100/40, consumed 60
      expect(patch, isNull, reason: 'nothing is written');
      expect(attempt.rejection, contains('أقل من المصروف فعلاً 60'));
      expect(
        attempt.throwIfRejected,
        throwsA(isA<CampaignEditRejected>().having((e) => e.message, 'message', contains('لم يتغير أي شيء في الحملة'))),
      );
    });

    test('missing campaign is a rejection, not an exception in the handler', () {
      final attempt = CampaignEditAttempt(draft: _campaign(), opened: opened, updatedBy: 'admin1');
      expect(attempt.plan(null), isNull);
      expect(attempt.rejection, contains('الحملة غير موجودة'));
      expect(attempt.throwIfRejected, throwsA(isA<CampaignEditRejected>()));
    });

    test('a retried attempt that succeeds clears the earlier rejection', () {
      final attempt = CampaignEditAttempt(
        draft: _campaign(prizes: [_row(55, 5)]),
        opened: opened,
        updatedBy: 'admin1',
      );
      expect(attempt.plan(_stored()), isNull);
      // Retry sees a stored row with only 50 handed out: 55 is now allowed.
      final patch = attempt.plan(_stored(total: 100, remaining: 50));
      expect(patch, isNotNull);
      expect(_remaining(patch!), 5);
      expect(attempt.rejection, isNull);
      attempt.throwIfRejected(); // does not throw
    });
  });
}
