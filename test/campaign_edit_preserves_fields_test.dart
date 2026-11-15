import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

/// Mirrors admin_dashboard_screen createdAt ordering (newest Timestamp first).
int _byCreatedAtDesc(Map<String, dynamic> a, Map<String, dynamic> b) {
  final tsA = a['createdAt'];
  final tsB = b['createdAt'];
  if (tsA is! Timestamp) return 1;
  if (tsB is! Timestamp) return -1;
  return tsB.compareTo(tsA);
}

/// Mirrors client_receipt_upload_screen and company_manager_portal_screen.
DateTime _clientRecency(DateTime? createdAt, DateTime? startDate) {
  return createdAt ?? startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
}

EventModel _campaign({
  required String id,
  required String name,
  DateTime? createdAt,
  DateTime? startDate,
  String spendLadderMode = 'exclusive',
  bool isActive = true,
  bool isPromoterActive = true,
  bool isManagerActive = true,
}) {
  return EventModel(
    id: id,
    eventName: name,
    targetCompany: 'Acme',
    companySlug: '512',
    minimumSpend: 100,
    createdAt: createdAt,
    startDate: startDate,
    spendLadderMode: spendLadderMode,
    isActive: isActive,
    isPromoterActive: isPromoterActive,
    isManagerActive: isManagerActive,
  );
}

void main() {
  test('editing preserves spendLadderMode and does not write createdAt', () {
    final createdAt = DateTime.utc(2024, 1, 15, 8, 30);
    final existing = _campaign(
      id: 'camp-512',
      name: 'Original',
      createdAt: createdAt,
      startDate: DateTime.utc(2024, 2, 1),
      spendLadderMode: 'consuming',
      isActive: false,
      isPromoterActive: false,
      isManagerActive: false,
    );

    // The editor does not expose these fields. A draft that leaves them at
    // their constructor defaults must not overwrite the stored campaign.
    final forgotten = EventModel(
      id: existing.id,
      eventName: 'Renamed offer',
      targetCompany: 'Acme',
      companySlug: '512',
      minimumSpend: 250,
    );
    expect(forgotten.spendLadderMode, 'exclusive');
    expect(forgotten.createdAt, isNull);
    expect(forgotten.isPromoterActive, isTrue);

    final payload = forgotten.toEditFirestore(
      existing: existing,
      updatedBy: 'uid-admin',
    );

    expect(payload.containsKey('createdAt'), isFalse);
    expect(payload['spendLadderMode'], 'consuming');
    expect(payload['isActive'], isFalse);
    expect(payload['isPromoterActive'], isFalse);
    expect(payload['isManagerActive'], isFalse);
    expect(payload['eventName'], 'Renamed offer');
    expect(payload['minimumSpend'], 250);
    expect(payload['updatedBy'], 'uid-admin');
    expect(payload['updatedAt'], isA<FieldValue>());
    expect(
      EventModel.campaignEditorOwnedFields.contains('spendLadderMode'),
      isFalse,
    );
    expect(EventModel.campaignEditorOwnedFields.contains('createdAt'), isFalse);

    // The screen also copies the unexposed fields onto the in-memory draft.
    final screenDraft = EventModel(
      id: existing.id,
      eventName: 'Renamed offer',
      targetCompany: 'Acme',
      companySlug: '512',
      minimumSpend: 250,
      spendLadderMode: existing.spendLadderMode,
      createdAt: existing.createdAt,
      isActive: existing.isActive,
      isPromoterActive: existing.isPromoterActive,
      isManagerActive: existing.isManagerActive,
    );
    final screenPayload = screenDraft.toEditFirestore(
      existing: existing,
      updatedBy: 'uid-admin',
    );
    expect(screenDraft.spendLadderMode, 'consuming');
    expect(screenPayload.containsKey('createdAt'), isFalse);
    expect(screenPayload['spendLadderMode'], 'consuming');
    expect(screenPayload['updatedBy'], 'uid-admin');

    // Firestore update() merges keys. createdAt stays, so createdAt sorts do too.
    final storedOlder = existing.toFirestore();
    final storedNewer = _campaign(
      id: 'camp-newer',
      name: 'Newer',
      createdAt: DateTime.utc(2025, 6, 1),
    ).toFirestore();
    final afterEdit = Map<String, dynamic>.from(storedOlder)..addAll(payload);

    expect(afterEdit['createdAt'], storedOlder['createdAt']);
    expect((afterEdit['createdAt'] as Timestamp).toDate().toUtc(), createdAt);
    expect(afterEdit['spendLadderMode'], 'consuming');

    final ordered = [afterEdit, storedNewer]..sort(_byCreatedAtDesc);
    expect(ordered.first['eventName'], 'Newer');
    expect(ordered.last['eventName'], 'Renamed offer');

    final editedRecency = _clientRecency(createdAt, existing.startDate);
    final newerRecency = _clientRecency(DateTime.utc(2025, 6, 1), null);
    expect(newerRecency.isAfter(editedRecency), isTrue);
  });

  test('every persisted field is editor-owned or explicitly preserved', () {
    const preserved = {
      'isActive',
      'isPromoterActive',
      'isAgencyActive',
      'isManagerActive',
      'spendLadderMode',
      'createdAt',
    };
    final keys = _campaign(id: 'x', name: 'n').toFirestore().keys.toSet();
    final uncategorized = keys
        .difference(EventModel.campaignEditorOwnedFields)
        .difference(preserved);
    expect(uncategorized, isEmpty);
    expect(preserved.contains('createdAt'), isTrue);
    expect(preserved.contains('spendLadderMode'), isTrue);
  });

  test('create still writes createdAt and does not stamp an edit', () {
    final created = _campaign(id: '', name: 'New campaign').toFirestore();
    expect(created['createdAt'], isA<FieldValue>());
    expect(created.containsKey('updatedAt'), isFalse);
    expect(created.containsKey('updatedBy'), isFalse);
    expect(created['spendLadderMode'], 'exclusive');

    final stamped = _campaign(
      id: '',
      name: 'New campaign',
      createdAt: DateTime.utc(2026, 1, 2),
      spendLadderMode: 'consuming',
    ).toFirestore();
    expect(stamped['createdAt'], isA<Timestamp>());
    expect(stamped['spendLadderMode'], 'consuming');
    expect(stamped.containsKey('updatedAt'), isFalse);
  });
}
