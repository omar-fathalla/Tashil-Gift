import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/campaign_content_repository.dart';
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

  /// TAG-65: set when the product lists / prompts are stored in
  /// `event_drafts/{id}/content` instead of this doc. [eventData] and
  /// [baseData] then lack them until [CampaignDraftStore.hydrate] runs.
  final Map<String, dynamic>? externalContent;

  const CampaignDraft({
    required this.id,
    required this.sourceEventId,
    required this.eventName,
    required this.companySlug,
    required this.updatedAt,
    required this.updatedBy,
    required this.eventData,
    this.baseData,
    this.externalContent,
  });

  bool get needsContentLoad => externalContent != null;

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
      externalContent: data['externalContent'] is Map ? _map(data['externalContent']) : null,
    );
  }

  CampaignDraft withContent(Map<String, dynamic> eventData, Map<String, dynamic>? baseData) => CampaignDraft(
        id: id,
        sourceEventId: sourceEventId,
        eventName: eventName,
        companySlug: companySlug,
        updatedAt: updatedAt,
        updatedBy: updatedBy,
        eventData: eventData,
        baseData: baseData,
      );

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

/// TAG-65: a draft's product lists / prompts are split out of the draft doc
/// when they would push it toward the 1 MiB Firestore limit.
///
/// Layout of `event_drafts/{id}/content`:
///  * `event_products_0..n` / `base_products_0..n` { items, index, version }
///  * `event_prompt` / `base_prompt` { text, version }
/// The draft doc then carries `externalContent` { version, event: {chunks,
/// count}, base: {chunks, count} | null } and its `event` / `base` maps have
/// no `requiredProducts` / `customPrompt`.
class CampaignDraftContentPlan {
  /// Fields for the draft doc (event/base maps with content removed, plus
  /// `externalContent`), or the payload unchanged when everything fits.
  final Map<String, dynamic> draftDoc;

  /// content doc id -> data.
  final Map<String, Map<String, dynamic>> docs;

  const CampaignDraftContentPlan(this.draftDoc, this.docs);

  bool get external => docs.isNotEmpty;
}

/// Reads one doc of `event_drafts/{id}/content`; null when missing.
typedef DraftContentDocReader = Future<Map<String, dynamic>?> Function(String docId);

class CampaignDraftContent {
  CampaignDraftContent._();

  static const String subcollection = 'content';

  /// Products + prompts (event and base together) above this leave the doc.
  static const int inlineLimitBytes = CampaignContentRepository.inlineLimitBytes;

  static String productsDocId(String side, int i) => '${side}_products_$i';
  static String promptDocId(String side) => '${side}_prompt';

  static List<String> _products(Map<String, dynamic>? m) {
    final p = m?['requiredProducts'];
    return p is List ? p.map((e) => e.toString()).toList() : <String>[];
  }

  static String _prompt(Map<String, dynamic>? m) => m?['customPrompt'] is String ? m!['customPrompt'] as String : '';

  static int _bytes(Map<String, dynamic>? m) => m == null
      ? 0
      : CampaignContentRepository.productsBytes(_products(m)) + CampaignContentRepository.promptBytes(_prompt(m));

  /// Splits the content out of [payload] (CampaignDraft.payload) when needed.
  static CampaignDraftContentPlan plan(Map<String, dynamic> payload, {required int version}) {
    final event = payload['event'] is Map ? Map<String, dynamic>.from(payload['event'] as Map) : <String, dynamic>{};
    final base = payload['base'] is Map ? Map<String, dynamic>.from(payload['base'] as Map) : null;
    if (_bytes(event) + _bytes(base) <= inlineLimitBytes) {
      return CampaignDraftContentPlan(payload, const {});
    }
    final docs = <String, Map<String, dynamic>>{};
    Map<String, dynamic> side(String name, Map<String, dynamic> m) {
      final products = _products(m);
      final prompt = _prompt(m);
      if (CampaignContentRepository.promptBytes(prompt) > CampaignContentRepository.promptLimitBytes) {
        throw const CampaignContentTooLarge(
            'تعليمات الذكاء الاصطناعي أكبر من الحد المسموح (حوالي 900 كيلوبايت). اختصرها وجرّب تاني.');
      }
      final parts = CampaignContentRepository.chunk(products);
      for (var i = 0; i < parts.length; i++) {
        docs[productsDocId(name, i)] = {'items': parts[i], 'index': i, 'version': version};
      }
      docs[promptDocId(name)] = {'text': prompt, 'version': version};
      m.remove('requiredProducts');
      m.remove('customPrompt');
      return {'chunks': parts.length, 'count': products.length};
    }

    final eventInfo = side('event', event);
    final baseInfo = base == null ? null : side('base', base);
    final doc = Map<String, dynamic>.from(payload)
      ..['event'] = event
      ..['base'] = base
      ..['externalContent'] = {'version': version, 'event': eventInfo, 'base': baseInfo};
    return CampaignDraftContentPlan(doc, docs);
  }

  /// [draft] with its event/base content read back through [read].
  static Future<CampaignDraft> loadWith(CampaignDraft draft, DraftContentDocReader read) async {
    final info = draft.externalContent;
    if (info == null) return draft;
    final version = info['version'];

    Future<Map<String, dynamic>> fill(String name, Map<String, dynamic> m, dynamic sideInfo) async {
      final si = sideInfo is Map ? sideInfo : const {};
      final chunks = (si['chunks'] as num?)?.toInt() ?? 0;
      final docs = await Future.wait([
        for (var i = 0; i < chunks; i++) read(productsDocId(name, i)),
        read(promptDocId(name)),
      ]);
      final products = <String>[];
      for (var i = 0; i < chunks; i++) {
        final d = docs[i];
        if (d == null || d['version'] != version) {
          throw CampaignContentUnavailable(draft.id, 'draft $name chunk $i missing or stale');
        }
        final items = d['items'];
        if (items is List) products.addAll(items.map((e) => e.toString()));
      }
      final count = (si['count'] as num?)?.toInt();
      if (count != null && count != products.length) {
        throw CampaignContentUnavailable(draft.id, 'draft $name expected $count products, got ${products.length}');
      }
      final prompt = docs.last;
      if (prompt == null || prompt['version'] != version) {
        throw CampaignContentUnavailable(draft.id, 'draft $name prompt missing or stale');
      }
      return Map<String, dynamic>.from(m)
        ..['requiredProducts'] = products
        ..['customPrompt'] = prompt['text'] is String ? prompt['text'] : '';
    }

    final event = await fill('event', draft.eventData, info['event']);
    final base = draft.baseData == null ? null : await fill('base', draft.baseData!, info['base']);
    return draft.withContent(event, base);
  }
}

/// Reads and writes drafts. Only `event_drafts` is touched; never `events`.
class CampaignDraftStore {
  final FirebaseFirestore firestore;
  const CampaignDraftStore(this.firestore);

  CollectionReference<Map<String, dynamic>> get _col => firestore.collection(kEventDraftsCollection);

  CollectionReference<Map<String, dynamic>> _content(String draftId) =>
      _col.doc(draftId).collection(CampaignDraftContent.subcollection);

  /// Creates a draft (draftId null) or overwrites it. Returns the draft id.
  /// TAG-65: large product lists / prompts go to the draft's content docs, in
  /// the same batch as the draft, and leftover content docs are deleted.
  Future<String> save({
    String? draftId,
    required EventModel event,
    required String updatedBy,
    EventModel? editing,
  }) async {
    final isNew = draftId == null || draftId.isEmpty;
    final ref = isNew ? _col.doc() : _col.doc(draftId);
    final plan = CampaignDraftContent.plan(
      CampaignDraft.payload(event: event, updatedBy: updatedBy, editing: editing),
      version: DateTime.now().microsecondsSinceEpoch,
    );
    final existing = isNew
        ? const <String>[]
        : (await _content(ref.id).get().timeout(const Duration(seconds: 15))).docs.map((d) => d.id).toList();
    final batch = firestore.batch();
    batch.set(ref, plan.draftDoc);
    plan.docs.forEach((id, data) => batch.set(_content(ref.id).doc(id), data));
    for (final id in existing) {
      if (!plan.docs.containsKey(id)) batch.delete(_content(ref.id).doc(id));
    }
    await batch.commit().timeout(const Duration(seconds: 15));
    return ref.id;
  }

  /// [draft] with any externally stored content filled in.
  Future<CampaignDraft> hydrate(CampaignDraft draft) => CampaignDraftContent.loadWith(draft, (docId) async {
        final snap = await _content(draft.id).doc(docId).get();
        return snap.exists ? snap.data() : null;
      });

  Future<void> delete(String draftId) async {
    final content = await _content(draftId).get();
    final batch = firestore.batch();
    for (final d in content.docs) {
      batch.delete(d.reference);
    }
    batch.delete(_col.doc(draftId));
    await batch.commit();
  }

  Stream<List<CampaignDraft>> watchAll() => _col
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => CampaignDraft.fromMap(d.id, d.data())).toList());
}
