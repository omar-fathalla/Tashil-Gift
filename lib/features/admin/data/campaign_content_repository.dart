import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/event_model.dart';

/// TAG-62: a campaign's product list and AI prompt, wherever they are stored.
class CampaignContent {
  final List<String> products;
  final String prompt;
  const CampaignContent({required this.products, required this.prompt});
}

/// The campaign says its content is in events/{id}/content but the docs are
/// missing or inconsistent. Callers must not fall back to an empty list (an
/// empty product list would accept every receipt).
class CampaignContentUnavailable implements Exception {
  final String eventId;
  final String reason;
  const CampaignContentUnavailable(this.eventId, this.reason);
  @override
  String toString() => 'تعذر تحميل منتجات/تعليمات الحملة ($eventId): $reason';
}

/// Content too large even for the content docs.
class CampaignContentTooLarge implements Exception {
  final String message;
  const CampaignContentTooLarge(this.message);
  @override
  String toString() => message;
}

/// Reads one doc of events/{id}/content by id; null when it does not exist.
typedef CampaignContentDocReader = Future<Map<String, dynamic>?> Function(String docId);

/// What one content write puts in Firestore.
class CampaignContentWrite {
  /// events/{id}/content/{docId} -> data (set, not merged).
  final Map<String, Map<String, dynamic>> docs;

  /// content doc ids to delete (chunks left over from a longer list).
  final List<String> deletes;

  /// Fields for the campaign doc. In an update patch, inline keys of a large
  /// campaign are FieldValue.delete(); use [applyToCreate] for a new doc.
  final Map<String, dynamic> eventFields;

  /// Products and prompt are also kept on the campaign doc.
  final bool inline;

  const CampaignContentWrite({
    required this.docs,
    required this.deletes,
    required this.eventFields,
    required this.inline,
  });

  /// [payload] (EventModel.toFirestore) with the content fields of a create.
  Map<String, dynamic> applyToCreate(Map<String, dynamic> payload) {
    final out = Map<String, dynamic>.from(payload);
    eventFields.forEach((k, v) {
      if (v is FieldValue) {
        out.remove(k);
      } else {
        out[k] = v;
      }
    });
    return out;
  }

  /// [patch] (an update payload) with the content fields of this write.
  Map<String, dynamic> applyToPatch(Map<String, dynamic> patch) =>
      Map<String, dynamic>.from(patch)..addAll(eventFields);
}

/// TAG-62 phase 1: campaign content lives in `events/{id}/content`:
///  * `products` { items, count, version, chunks, updatedAt } — when the list
///    is too big for one doc, `items` is empty and the list is split across
///    `products_0`, `products_1`, … { items, index, version, updatedAt };
///  * `prompt` { text, version, updatedAt }.
/// The campaign doc keeps `hasExternalContent`, `contentVersion`,
/// `contentChunks` and `requiredProductsCount`. Small campaigns also keep the
/// inline `requiredProducts` / `customPrompt` (older app versions read them);
/// large ones (over [inlineLimitBytes]) do not.
///
/// Reading never touches Firestore for a campaign whose content is inline, so
/// existing campaigns cost no extra reads.
class CampaignContentRepository {
  CampaignContentRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const String subcollection = 'content';
  static const String productsDocId = 'products';
  static const String promptDocId = 'prompt';
  static String chunkDocId(int i) => 'products_$i';

  /// Products + prompt above this stay out of the campaign doc.
  static const int inlineLimitBytes = 256 * 1024;

  /// Max bytes of product items in one content doc (Firestore limit is 1 MiB).
  static const int chunkLimitBytes = 700 * 1024;

  /// Max prompt size (one doc).
  static const int promptLimitBytes = 900 * 1024;

  /// Loaded content by `eventId@contentVersion` (content is immutable per version).
  static final Map<String, CampaignContent> _cache = {};

  static void clearCache() => _cache.clear();

  CollectionReference<Map<String, dynamic>> contentCollection(String eventId) =>
      _firestore.collection('events').doc(eventId).collection(subcollection);

  // ---------------------------------------------------------------- sizes

  static int productsBytes(List<String> products) => utf8.encode(jsonEncode(products)).length;

  static int promptBytes(String prompt) => utf8.encode(prompt).length;

  static bool fitsInline(List<String> products, String prompt) =>
      productsBytes(products) + promptBytes(prompt) <= inlineLimitBytes;

  /// Inline products/prompt of a stored campaign doc are too big to keep there.
  static bool inlineTooLarge(Map<String, dynamic> eventData) {
    final p = eventData['requiredProducts'];
    final products = p is List ? p.map((e) => e.toString()).toList() : const <String>[];
    final prompt = eventData['customPrompt'] is String ? eventData['customPrompt'] as String : '';
    return !fitsInline(products, prompt);
  }

  /// Splits [items] into lists of at most [limitBytes] JSON bytes each.
  static List<List<String>> chunk(List<String> items, {int limitBytes = chunkLimitBytes}) {
    final out = <List<String>>[];
    var current = <String>[];
    var size = 2; // []
    for (final item in items) {
      final itemBytes = utf8.encode(jsonEncode(item)).length + 1; // + comma
      if (current.isNotEmpty && size + itemBytes > limitBytes) {
        out.add(current);
        current = <String>[];
        size = 2;
      }
      current.add(item);
      size += itemBytes;
    }
    if (current.isNotEmpty || out.isEmpty) out.add(current);
    return out;
  }

  // ---------------------------------------------------------------- write plan

  /// Plans one content write at [version]. [previousChunks] is the stored
  /// `contentChunks`, so leftover chunk docs get deleted.
  static CampaignContentWrite plan({
    required List<String> products,
    required String prompt,
    required int version,
    int previousChunks = 0,
    Object? timestamp,
  }) {
    if (promptBytes(prompt) > promptLimitBytes) {
      throw const CampaignContentTooLarge(
          'تعليمات الذكاء الاصطناعي أكبر من الحد المسموح (حوالي 900 كيلوبايت). اختصرها وجرّب تاني.');
    }
    final ts = timestamp ?? FieldValue.serverTimestamp();
    final docs = <String, Map<String, dynamic>>{};
    final single = productsBytes(products) <= chunkLimitBytes;
    final parts = single ? <List<String>>[products] : chunk(products);
    final chunks = single ? 0 : parts.length;
    docs[productsDocId] = {
      'items': single ? products : <String>[],
      'count': products.length,
      'version': version,
      'chunks': chunks,
      'updatedAt': ts,
    };
    if (!single) {
      for (var i = 0; i < parts.length; i++) {
        docs[chunkDocId(i)] = {'items': parts[i], 'index': i, 'version': version, 'updatedAt': ts};
      }
    }
    docs[promptDocId] = {'text': prompt, 'version': version, 'updatedAt': ts};
    final deletes = [for (var i = chunks; i < previousChunks; i++) chunkDocId(i)];
    final inline = fitsInline(products, prompt);
    return CampaignContentWrite(
      docs: docs,
      deletes: deletes,
      inline: inline,
      eventFields: {
        'hasExternalContent': true,
        'contentVersion': version,
        'contentChunks': chunks,
        'requiredProductsCount': products.length,
        'requiredProducts': inline ? products : FieldValue.delete(),
        'customPrompt': inline ? prompt : FieldValue.delete(),
      },
    );
  }

  /// Content changes an edit [patch] (CampaignEditSave.buildEditPatch) has to
  /// write, given the stored doc [currentData]: null when products and prompt
  /// are unchanged and the stored inline copy is not too large.
  static CampaignContentWrite? planForEdit({
    required Map<String, dynamic> patch,
    required EventModel draft,
    required Map<String, dynamic> currentData,
    Object? timestamp,
  }) {
    final changed = patch.containsKey('requiredProducts') || patch.containsKey('customPrompt');
    final hasInline = currentData.containsKey('requiredProducts') || currentData.containsKey('customPrompt');
    final storedTooLarge = hasInline && inlineTooLarge(currentData);
    // Not externalized yet and the admin changed neither: leave as is.
    if (!changed && !storedTooLarge) return null;
    return plan(
      products: draft.requiredProducts,
      prompt: draft.customPrompt,
      version: ((currentData['contentVersion'] as num?)?.toInt() ?? 0) + 1,
      previousChunks: (currentData['contentChunks'] as num?)?.toInt() ?? 0,
      timestamp: timestamp,
    );
  }

  // ---------------------------------------------------------------- reads

  /// Content of [event] using [read] for the content docs. No read happens
  /// when the model already holds the values.
  static Future<CampaignContent> loadWith(EventModel event, CampaignContentDocReader read) async {
    final info = event.contentInfo;
    if (!info.needsLoad) {
      return CampaignContent(products: event.requiredProducts, prompt: event.customPrompt);
    }
    final key = '${event.id}@${info.version}';
    final cached = _cache[key];
    if (cached != null) {
      return CampaignContent(
        products: info.productsInline ? event.requiredProducts : cached.products,
        prompt: info.promptInline ? event.customPrompt : cached.prompt,
      );
    }
    final results = await Future.wait([
      info.productsInline ? Future.value(event.requiredProducts) : _readProducts(event.id, read),
      info.promptInline ? Future.value(event.customPrompt) : _readPrompt(event.id, read),
    ]);
    final content = CampaignContent(products: results[0] as List<String>, prompt: results[1] as String);
    if (!info.productsInline && !info.promptInline) _cache[key] = content;
    return content;
  }

  static Future<List<String>> _readProducts(String eventId, CampaignContentDocReader read) async {
    final head = await read(productsDocId);
    if (head == null) throw CampaignContentUnavailable(eventId, 'products doc missing');
    final version = head['version'];
    final chunks = (head['chunks'] as num?)?.toInt() ?? 0;
    if (chunks <= 0) return _strings(head['items']);
    final parts = await Future.wait([for (var i = 0; i < chunks; i++) read(chunkDocId(i))]);
    final out = <String>[];
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part == null) throw CampaignContentUnavailable(eventId, 'chunk $i missing');
      if (part['version'] != version) throw CampaignContentUnavailable(eventId, 'chunk $i has another version');
      out.addAll(_strings(part['items']));
    }
    final count = (head['count'] as num?)?.toInt();
    if (count != null && count != out.length) {
      throw CampaignContentUnavailable(eventId, 'expected $count products, got ${out.length}');
    }
    return out;
  }

  static Future<String> _readPrompt(String eventId, CampaignContentDocReader read) async {
    final doc = await read(promptDocId);
    if (doc == null) throw CampaignContentUnavailable(eventId, 'prompt doc missing');
    final text = doc['text'];
    return text is String ? text : '';
  }

  static List<String> _strings(dynamic raw) =>
      raw is List ? raw.map((e) => e.toString()).toList() : <String>[];

  CampaignContentDocReader _reader(String eventId) => (docId) async {
        final snap = await contentCollection(eventId).doc(docId).get();
        return snap.exists ? snap.data() : null;
      };

  /// Content of [event] (inline values when present, else the content docs).
  Future<CampaignContent> load(EventModel event) => loadWith(event, _reader(event.id));

  /// [event] with requiredProducts / customPrompt filled in. Returns the same
  /// instance when nothing has to be read.
  Future<EventModel> hydrate(EventModel event) async {
    if (!event.contentInfo.needsLoad) return event;
    final c = await load(event);
    return event.copyWith(
      requiredProducts: c.products,
      customPrompt: c.prompt,
      contentInfo: event.contentInfo.loaded(),
    );
  }

  Future<List<EventModel>> hydrateAll(Iterable<EventModel> events) =>
      Future.wait(events.map(hydrate));

  // ---------------------------------------------------------------- writes

  /// Creates campaign [eventId] from [payload] (EventModel.toFirestore) and
  /// its content docs in one batch, so the campaign never exists without them.
  Future<void> createWithContent({
    required String eventId,
    required Map<String, dynamic> payload,
    required List<String> products,
    required String prompt,
  }) async {
    final write = plan(products: products, prompt: prompt, version: 1);
    final batch = _firestore.batch();
    batch.set(_firestore.collection('events').doc(eventId), write.applyToCreate(payload));
    final content = contentCollection(eventId);
    write.docs.forEach((id, data) => batch.set(content.doc(id), data));
    await batch.commit();
  }

  /// Writes [write]'s content docs inside transaction [tx] (after all reads).
  void writeInTransaction(Transaction tx, String eventId, CampaignContentWrite write) {
    final content = contentCollection(eventId);
    write.docs.forEach((id, data) => tx.set(content.doc(id), data));
    for (final id in write.deletes) {
      tx.delete(content.doc(id));
    }
  }

  /// Deletes the content docs of a deleted campaign (best effort by the caller).
  Future<void> deleteContent(String eventId) async {
    final snap = await contentCollection(eventId).get();
    if (snap.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }
}
