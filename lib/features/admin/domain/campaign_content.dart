import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'event_model.dart';

/// TAG-56: a campaign's product list and AI prompt live outside the campaign
/// document, in `events/{id}/content/products_{n}` and `prompt_{n}` chunks.
///
/// The campaign document keeps a small pointer (`contentVersion`,
/// `contentRevision`, chunk counts). Readers use the chunks when the pointer
/// is there and fall back to the legacy `requiredProducts` / `customPrompt`
/// fields otherwise. Small campaigns still get the legacy fields as a mirror,
/// so older code keeps working; large ones drop them from the campaign doc.
class CampaignContentPointer {
  final int version;
  final int revision;
  final int productsChunks;
  final int promptChunks;
  final int productsCount;
  final int promptLength;

  const CampaignContentPointer({
    required this.version,
    required this.revision,
    required this.productsChunks,
    required this.promptChunks,
    required this.productsCount,
    required this.promptLength,
  });

  static int _int(dynamic v) => v is num ? v.toInt() : 0;

  /// Pointer stored on a campaign document, or null for a legacy campaign.
  static CampaignContentPointer? fromEventData(Map<String, dynamic>? data) {
    if (data == null) return null;
    final version = _int(data['contentVersion']);
    if (version < 1) return null;
    return CampaignContentPointer(
      version: version,
      revision: _int(data['contentRevision']),
      productsChunks: _int(data['contentProductsChunks']),
      promptChunks: _int(data['contentPromptChunks']),
      productsCount: _int(data['requiredProductsCount']),
      promptLength: _int(data['customPromptLength']),
    );
  }
}

/// The writes that store one version of a campaign's content.
class CampaignContentWrites {
  /// Pointer fields (and legacy mirror or deletes) for the campaign document.
  final Map<String, dynamic> eventFields;

  /// Chunk documents to set, by id inside `events/{id}/content`.
  final Map<String, Map<String, dynamic>> docs;

  /// Chunk ids left over from the previous revision, to delete.
  final List<String> deleteIds;

  const CampaignContentWrites({required this.eventFields, required this.docs, required this.deleteIds});
}

/// Thrown when a campaign's content pointer exists but its chunks could not
/// be read completely and the document has no legacy copy to fall back on.
class CampaignContentUnavailable implements Exception {
  final String eventId;
  const CampaignContentUnavailable(this.eventId);
  @override
  String toString() => 'تعذر تحميل منتجات وبرومبت الحملة ($eventId). جرّب تاني بعد شوية.';
}

class CampaignContentLayout {
  CampaignContentLayout._();

  static const int version = 1;
  static const String subcollection = 'content';
  static const int maxItemsPerChunk = 1500;
  static const int maxCharsPerChunk = 300000;

  /// Legacy fields are mirrored on the campaign doc only below this size.
  static const int legacyMirrorMaxBytes = 200 * 1024;

  static const Set<String> pointerKeys = {
    'contentVersion',
    'contentRevision',
    'contentProductsChunks',
    'contentPromptChunks',
    'requiredProductsCount',
    'customPromptLength',
    'contentUpdatedAt',
  };

  static String productsDocId(int i) => 'products_$i';
  static String promptDocId(int i) => 'prompt_$i';

  /// Products split so no chunk has more than [maxItemsPerChunk] items or
  /// [maxCharsPerChunk] UTF-8 bytes. An empty list gives no chunks.
  static List<List<String>> chunkProducts(List<String> products) {
    final chunks = <List<String>>[];
    var current = <String>[];
    var size = 0;
    for (final p in products) {
      final len = utf8.encode(p).length + 4;
      if (current.isNotEmpty && (current.length >= maxItemsPerChunk || size + len > maxCharsPerChunk)) {
        chunks.add(current);
        current = <String>[];
        size = 0;
      }
      current.add(p);
      size += len;
    }
    if (current.isNotEmpty) chunks.add(current);
    return chunks;
  }

  /// Prompt split into pieces of at most [maxCharsPerChunk] characters
  /// (a UTF-16 surrogate pair is never split). Empty prompt gives no chunks.
  static List<String> chunkPrompt(String prompt) {
    final chunks = <String>[];
    var start = 0;
    while (start < prompt.length) {
      var end = start + maxCharsPerChunk;
      if (end >= prompt.length) {
        end = prompt.length;
      } else {
        final unit = prompt.codeUnitAt(end - 1);
        if (unit >= 0xD800 && unit <= 0xDBFF) end -= 1;
      }
      chunks.add(prompt.substring(start, end));
      start = end;
    }
    return chunks;
  }

  static int contentBytes(List<String> products, String prompt) =>
      utf8.encode(jsonEncode(products)).length + utf8.encode(prompt).length;

  static bool keepsLegacyMirror(List<String> products, String prompt) =>
      contentBytes(products, prompt) <= legacyMirrorMaxBytes;

  /// Writes that store [products] and [prompt] as revision `previous + 1`.
  /// Chunks of [previous] beyond the new counts are deleted.
  static CampaignContentWrites plan({
    required List<String> products,
    required String prompt,
    CampaignContentPointer? previous,
  }) {
    final revision = (previous?.revision ?? 0) + 1;
    final productChunks = chunkProducts(products);
    final promptChunks = chunkPrompt(prompt);
    final docs = <String, Map<String, dynamic>>{};
    for (var i = 0; i < productChunks.length; i++) {
      docs[productsDocId(i)] = {'kind': 'products', 'index': i, 'revision': revision, 'items': productChunks[i]};
    }
    for (var i = 0; i < promptChunks.length; i++) {
      docs[promptDocId(i)] = {'kind': 'prompt', 'index': i, 'revision': revision, 'text': promptChunks[i]};
    }
    final deleteIds = <String>[
      if (previous != null) ...[
        for (var i = productChunks.length; i < previous.productsChunks; i++) productsDocId(i),
        for (var i = promptChunks.length; i < previous.promptChunks; i++) promptDocId(i),
      ],
    ];
    final mirror = keepsLegacyMirror(products, prompt);
    final eventFields = <String, dynamic>{
      'contentVersion': version,
      'contentRevision': revision,
      'contentProductsChunks': productChunks.length,
      'contentPromptChunks': promptChunks.length,
      'requiredProductsCount': products.length,
      'customPromptLength': prompt.length,
      'contentUpdatedAt': FieldValue.serverTimestamp(),
      'requiredProducts': mirror ? products : FieldValue.delete(),
      'customPrompt': mirror ? prompt : FieldValue.delete(),
    };
    return CampaignContentWrites(eventFields: eventFields, docs: docs, deleteIds: deleteIds);
  }

  /// Products and prompt rebuilt from the chunk documents [docs] (by id) for
  /// [pointer], or null when a chunk is missing or from another revision.
  static ({List<String> products, String prompt})? assemble(
    CampaignContentPointer pointer,
    Map<String, Map<String, dynamic>> docs,
  ) {
    final products = <String>[];
    for (var i = 0; i < pointer.productsChunks; i++) {
      final d = docs[productsDocId(i)];
      if (d == null || CampaignContentPointer._int(d['revision']) != pointer.revision) return null;
      final items = d['items'];
      if (items is! List) return null;
      products.addAll(items.map((e) => e.toString()));
    }
    final prompt = StringBuffer();
    for (var i = 0; i < pointer.promptChunks; i++) {
      final d = docs[promptDocId(i)];
      if (d == null || CampaignContentPointer._int(d['revision']) != pointer.revision) return null;
      prompt.write((d['text'] ?? '').toString());
    }
    return (products: products, prompt: prompt.toString());
  }

  /// For a create: the campaign document data with the pointer applied, plus
  /// the chunk writes.
  static ({Map<String, dynamic> eventData, CampaignContentWrites writes}) forCreate(EventModel event) {
    final writes = plan(products: event.requiredProducts, prompt: event.customPrompt);
    final data = event.toFirestore();
    writes.eventFields.forEach((k, v) {
      if (v is FieldValue && (k == 'requiredProducts' || k == 'customPrompt')) {
        data.remove(k); // set(): an absent field is the same as a deleted one
      } else {
        data[k] = v;
      }
    });
    return (eventData: data, writes: writes);
  }

  /// For an edit [patch] built by CampaignEditSave: when the admin changed
  /// the products or the prompt, those legacy keys are replaced by the
  /// pointer (and mirror) and the chunk writes are returned. Returns null when
  /// neither changed; the patch is then left as is.
  static CampaignContentWrites? splitEditPatch({
    required Map<String, dynamic> patch,
    required EventModel draft,
    required Map<String, dynamic> currentData,
  }) {
    if (!patch.containsKey('requiredProducts') && !patch.containsKey('customPrompt')) return null;
    patch.remove('requiredProducts');
    patch.remove('customPrompt');
    final writes = plan(
      products: draft.requiredProducts,
      prompt: draft.customPrompt,
      previous: CampaignContentPointer.fromEventData(currentData),
    );
    patch.addAll(writes.eventFields);
    return writes;
  }
}

/// Reads campaign content from Firestore.
class CampaignContentStore {
  final FirebaseFirestore firestore;
  const CampaignContentStore(this.firestore);

  CollectionReference<Map<String, dynamic>> contentOf(String eventId) =>
      firestore.collection('events').doc(eventId).collection(CampaignContentLayout.subcollection);

  /// [event] with its products and prompt loaded from the content chunks.
  /// Legacy campaigns (no pointer) and already loaded ones come back as is.
  /// When the chunks are incomplete the legacy fields on the document are
  /// used; with no legacy copy either, [CampaignContentUnavailable] is thrown.
  Future<EventModel> hydrate(EventModel event) async {
    final pointer = event.contentPointer;
    if (pointer == null || event.contentLoaded || event.id.isEmpty) return event;
    // Small campaigns carry a mirror on the document: no extra read needed.
    if (event.requiredProducts.length == pointer.productsCount &&
        event.customPrompt.length == pointer.promptLength) {
      return event.copyWith(contentLoaded: true);
    }
    ({List<String> products, String prompt})? content;
    try {
      final snap = await contentOf(event.id).get();
      content = CampaignContentLayout.assemble(pointer, {for (final d in snap.docs) d.id: d.data()});
    } catch (_) {
      content = null;
    }
    if (content == null) {
      final hasLegacy = event.requiredProducts.isNotEmpty || event.customPrompt.isNotEmpty;
      final contentIsEmpty = pointer.productsChunks == 0 && pointer.promptChunks == 0;
      if (hasLegacy || contentIsEmpty) return event.copyWith(contentLoaded: true);
      throw CampaignContentUnavailable(event.id);
    }
    return event.copyWith(requiredProducts: content.products, customPrompt: content.prompt, contentLoaded: true);
  }

  Future<List<EventModel>> hydrateAll(Iterable<EventModel> events) => Future.wait(events.map(hydrate));

  /// Create: campaign document and content chunks in one batch.
  Future<void> create(String eventId, EventModel event) {
    final built = CampaignContentLayout.forCreate(event);
    final batch = firestore.batch();
    batch.set(firestore.collection('events').doc(eventId), built.eventData);
    final content = contentOf(eventId);
    built.writes.docs.forEach((id, data) => batch.set(content.doc(id), data));
    return batch.commit();
  }
}
