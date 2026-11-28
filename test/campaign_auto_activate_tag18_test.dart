// TAG-18: the dashboard switch marks a manual pause (so the daily
// auto-activate leaves the campaign off), the edit save never writes the
// status fields, and the review dialog explains what will happen.
import 'package:al_mraay/features/admin/domain/campaign_activation_review.dart';
import 'package:al_mraay/features/admin/domain/campaign_edit_save.dart';
import 'package:al_mraay/features/admin/domain/campaign_status_toggle.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

EventModel _campaign({bool isActive = false, bool pausedManually = false, DateTime? start, DateTime? end}) => EventModel(
      id: 'knorr',
      eventName: 'منتجات كنور',
      targetCompany: 'يونيليفر',
      companySlug: '512',
      minimumSpend: 90,
      requiredProducts: const ['كنور'],
      customPrompt: 'تعليمات',
      welcomeTitle: '',
      welcomeMessage: '',
      termsAndConditions: '',
      startDate: start ?? DateTime(2026, 11, 25),
      endDate: end ?? DateTime(2026, 12, 14),
      isActive: isActive,
      pausedManually: pausedManually,
      allocatedPrizes: [
        AllocatedPrize(giftId: 'g1', name: 'شنطة', allocatedQuantity: 10, remainingQuantity: 10, branchId: 'b1', branchName: 'فرع'),
      ],
    );

final _now = DateTime(2026, 11, 25, 14);

Iterable<String> _messages(CampaignActivationReview r) => r.warnings.map((w) => w.message);

void main() {
  group('dashboard switch', () {
    test('turning off marks a manual pause and records who and when', () {
      final p = CampaignStatusToggle.patch(active: false, uid: 'admin-1', timestamp: 'T');
      expect(p, {'isActive': false, 'pausedManually': true, 'statusUpdatedAt': 'T', 'statusUpdatedBy': 'admin-1'});
    });

    test('turning on clears the manual pause', () {
      final p = CampaignStatusToggle.patch(active: true, uid: 'admin-1', timestamp: 'T');
      expect(p, {'isActive': true, 'pausedManually': false, 'statusUpdatedAt': 'T', 'statusUpdatedBy': 'admin-1'});
    });

    test('defaults to the server time', () {
      final p = CampaignStatusToggle.patch(active: true, uid: 'u');
      expect(p['statusUpdatedAt'], isA<FieldValue>());
    });
  });

  group('event model', () {
    test('reads pausedManually; missing means false (legacy campaigns)', () {
      final base = _campaign().toFirestore();
      expect(EventModel.fromFirestoreMap('a', {...base, 'pausedManually': true}).pausedManually, isTrue);
      expect(EventModel.fromFirestoreMap('a', base).pausedManually, isFalse);
      expect(EventModel.fromFirestoreMap('a', {...base, 'pausedManually': 'yes'}).pausedManually, isFalse);
    });

    test('create and edit never write the status fields', () {
      final map = _campaign(pausedManually: true).toFirestore();
      for (final k in ['pausedManually', 'statusUpdatedAt', 'statusUpdatedBy']) {
        expect(map.containsKey(k), isFalse, reason: k);
      }
      final opened = _campaign(pausedManually: true);
      final draft = opened.copyWith(endDate: DateTime(2026, 12, 31), isActive: true, pausedManually: false);
      final patch = CampaignEditSave.buildEditPatch(
        draft: draft,
        opened: opened,
        currentData: opened.toFirestore(),
        updatedBy: 'admin-1',
      );
      expect(patch.containsKey('endDate'), isTrue);
      for (final k in ['isActive', 'pausedManually', 'statusUpdatedAt', 'statusUpdatedBy']) {
        expect(patch.containsKey(k), isFalse, reason: k);
      }
    });

    test('copyWith keeps pausedManually', () {
      expect(_campaign(pausedManually: true).copyWith(eventName: 'x').pausedManually, isTrue);
    });
  });

  group('review dialog note', () {
    test('off and paused manually, dates still ahead: says it will not turn on by itself', () {
      final r = CampaignActivationReview.of(_campaign(pausedManually: true), isNew: false, now: _now);
      final note = r.warnings.firstWhere((w) => w.message.contains('متوقفة يدويًا'));
      expect(note.level, ReviewLevel.warning);
      expect(note.message, contains('مش هتتفعّل تلقائيًا'));
    });

    test('the pausedManually argument wins over the form copy', () {
      final r = CampaignActivationReview.of(_campaign(), isNew: false, willBeActive: false, pausedManually: true, now: _now);
      expect(_messages(r).any((m) => m.contains('متوقفة يدويًا')), isTrue);
    });

    test('off but not paused, start already reached: turns on at the next 00:10', () {
      final r = CampaignActivationReview.of(_campaign(), isNew: false, willBeActive: false, pausedManually: false, now: _now);
      final note = _messages(r).firstWhere((m) => m.contains('هتتفعّل تلقائيًا'));
      expect(note, contains('2026-11-26'));
      expect(note, contains('12:10'));
    });

    test('off but not paused, future start: turns on on the start day', () {
      final r = CampaignActivationReview.of(_campaign(start: DateTime(2026, 12, 1)), isNew: false, willBeActive: false, now: _now);
      expect(_messages(r).firstWhere((m) => m.contains('هتتفعّل تلقائيًا')), contains('2026-12-01'));
    });

    test('ended or active campaigns get no auto-activate note', () {
      final ended = CampaignActivationReview.of(
          _campaign(pausedManually: true, start: DateTime(2026, 11, 1), end: DateTime(2026, 11, 20)),
          isNew: false,
          now: _now);
      expect(_messages(ended).any((m) => m.contains('تلقائيًا في مواعيدها') || m.contains('هتتفعّل تلقائيًا')), isFalse);
      final active = CampaignActivationReview.of(_campaign(isActive: true), isNew: false, now: _now);
      expect(_messages(active).any((m) => m.contains('متوقفة')), isFalse);
    });
  });
}
