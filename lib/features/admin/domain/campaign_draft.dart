import 'package:cloud_firestore/cloud_firestore.dart';

import 'event_model.dart';

/// C-05: campaign drafts live in their own staff-only collection, never in
/// `events`. Every reader of `events` (reps, branches, the partner portal,
/// claims, receipt matching, stats and autoCloseExpiredCampaigns) therefore
/// never sees a draft, and existing campaigns need no new field.
const String kEventDraftsCollection = 'event_drafts';

class CampaignDraft {
  final String id;

  /// The live campaign this draft edits, or null for a new campaign.
  final String? sourceEventId;
  final String eventName;
  final String companySlug;
  final DateTime? updatedAt;
  final String updatedBy;

  /// The editor state, in the same shape as an `events` document.
  final Map<String, dynamic> eventData;

  /// For an edit draft: the campaign as it was when the editor opened. On
  /// publish only the fields changed against it are written (C-02 rules).
  final Map<String, dynamic>? baseData;

  const CampaignDraft({
    required this.id,
    required this.sourceEventId,
    required this.eventName,
    required this.companySlug,
    required this.updatedAt,
    required this.updatedBy,
    required this.eventData,
    this.baseData,
  });

  bool get isEditDraft => (sourceEventId ?? '').isNotEmpty;

  /// The draft content as a campaign (id = the live campaign for an edit).
  EventModel get event => EventModel.fromFirestoreMap(sourceEventId ?? '', eventData);

  /// The campaign as opened when the edit draft was made.
  EventModel? get baseEvent =>
      isEditDraft && baseData != null ? EventModel.fromFirestoreMap(sourceEventId!, baseData!) : null;

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  factory CampaignDraft.fromMap(String id, Map<String, dynamic> data) {
    final source = (data['sourceEventId'] ?? '').toString().trim();
    final updated = data['updatedAt'];
    return CampaignDraft(
      id: id,
      sourceEventId: source.isEmpty ? null : source,
      eventName: (data['eventName'] ?? '').toString(),
      companySlug: (data['companySlug'] ?? '').toString(),
      updatedAt: updated is Timestamp ? updated.toDate() : null,
      updatedBy: (data['updatedBy'] ?? '').toString(),
      eventData: _map(data['event']),
      baseData: data['base'] is Map ? _map(data['base']) : null,
    );
  }

  /// Fields of the `events` document that a draft never stores.
  static Map<String, dynamic> _eventFields(EventModel e) {
    final m = e.toFirestore();
    // createdAt is a server timestamp on create; the live campaign keeps its own.
    m.remove('createdAt');
    return m;
  }

  /// Document written to [kEventDraftsCollection].
  static Map<String, dynamic> payload({
    required EventModel event,
    required String updatedBy,
    EventModel? editing,
  }) {
    return {
      'sourceEventId': editing?.id,
      'eventName': event.eventName,
      'companySlug': event.companySlug,
      'event': _eventFields(event),
      'base': editing == null ? null : _eventFields(editing),
      'updatedBy': updatedBy,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

/// Reads and writes drafts. Only `event_drafts` is touched; never `events`.
class CampaignDraftStore {
  final FirebaseFirestore firestore;
  const CampaignDraftStore(this.firestore);

  CollectionReference<Map<String, dynamic>> get _col => firestore.collection(kEventDraftsCollection);

  /// Creates a draft (draftId null) or overwrites it. Returns the draft id.
  Future<String> save({
    String? draftId,
    required EventModel event,
    required String updatedBy,
    EventModel? editing,
  }) async {
    final ref = (draftId == null || draftId.isEmpty) ? _col.doc() : _col.doc(draftId);
    await ref
        .set(CampaignDraft.payload(event: event, updatedBy: updatedBy, editing: editing))
        .timeout(const Duration(seconds: 15));
    return ref.id;
  }

  Future<void> delete(String draftId) => _col.doc(draftId).delete();

  Stream<List<CampaignDraft>> watchAll() => _col
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => CampaignDraft.fromMap(d.id, d.data())).toList());
}
