import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'event_model.dart';

/// TAG-51 phase 1: the two large campaign fields (requiredProducts and
/// customPrompt) also live outside the campaign document, in
/// `events/{eventId}/content/{partId}`:
///
///   products-0 .. products-N  {kind: 'products', rev, part, parts, items: [..]}
///   prompt-0   .. prompt-M    {kind: 'prompt',   rev, part, parts, text: '..'}
///
/// The campaign document carries a small marker, `contentStorage`:
///   {v: 1, rev, productParts, promptParts, productsCount, promptLength,
///    legacyMirror: true}
///
/// While `legacyMirror` is true (phase 1 and 2) the legacy fields
/// `requiredProducts` / `customPrompt` on the campaign document stay the
/// source of truth and are still written by the editor; the parts are a copy
/// built FROM the campaign document (see [CampaignContentRepository.syncFromLegacy]
/// and functions/scripts/migrate_campaign_content.js, same layout).
///
/// Readers ([CampaignContentRepository.hydrate]) use the parts when the marker
/// is valid and every part matches its revision, and fall back to the legacy
/// fields otherwise. The JavaScript twin is functions/campaign_content.js.
class CampaignContentLayout {
  CampaignContentLayout._();

  static const String subcollection = 'content';
  static const String markerField = 'contentStorage';
  static const int version = 1;

  /// UTF-8 bytes per part. Firestore's limit is 1 MiB per document; this
  /// leaves room for field names and index overhead.
  static const int maxPartBytes = 600000;

  /// Matches the rules (`^(products|prompt)-[0-9]{1,2}$`).
  static const int maxParts = 100;

  static String productsPartId(int i) => 'products-$i';
  static String promptPartId(int i) => 'prompt-$i';

  /// Content revision: sha256 over the products (each followed by 0x00) and
  /// the prompt (after 0x01), first 24 hex chars. Same bytes as
  /// functions/campaign_content.js `contentRev`.
  static String rev(List<String> products, String prompt) {
    final bytes = BytesBuilder(copy: false);
    for (final p in products) {
      bytes.add(utf8.encode(p));
      bytes.addByte(0);
    }
    bytes.addByte(1);
    bytes.add(utf8.encode(prompt));
    return sha256.convert(bytes.takeBytes()).toString().substring(0, 24);
  }

  /// Splits [products] into parts of at most [maxPartBytes] (UTF-8 bytes plus
  /// 16 bytes per item). Always at least one part (possibly empty).
  static List<List<String>> chunkProducts(List<String> products, {int maxBytes = maxPartBytes}) {
    final parts = <List<String>>[];
    var current = <String>[];
    var size = 0;
    for (final p in products) {
      final s = utf8.encode(p).length + 16;
      if (current.isNotEmpty && size + s > maxBytes) {
        parts.add(current);
        current = <String>[];
        size = 0;
      }
      current.add(p);
      size += s;
    }
    parts.add(current);
    return parts;
  }

  /// Splits [prompt] into parts of at most [maxBytes] UTF-8 bytes without
  /// cutting a surrogate pair. Always at least one part (possibly '').
  static List<String> chunkPrompt(String prompt, {int maxBytes = maxPartBytes}) {
    final parts = <String>[];
    var start = 0;
    var bytes = 0;
    var i = 0;
    while (i < prompt.length) {
      final cu = prompt.codeUnitAt(i);
      final isPair = cu >= 0xD800 && cu <= 0xDBFF && i + 1 < prompt.length &&
          prompt.codeUnitAt(i + 1) >= 0xDC00 && prompt.codeUnitAt(i + 1) <= 0xDFFF;
      final width = isPair ? 2 : 1;
      final b = isPair ? 4 : (cu < 0x80 ? 1 : (cu < 0x800 ? 2 : 3));
      if (bytes + b > maxBytes && i > start) {
        parts.add(prompt.substring(start, i));
        start = i;
        bytes = 0;
      }
      bytes += b;
      i += width;
    }
    parts.add(prompt.substring(start));
    return parts;
  }

  /// Every part document (id -> data) plus the marker for one content.
  static CampaignContentPlan plan(List<String> products, String prompt, {bool legacyMirror = true}) {
    final r = rev(products, prompt);
    final productParts = chunkProducts(products);
    final promptParts = chunkPrompt(prompt);
    if (productParts.length > maxParts || promptParts.length > maxParts) {
      throw StateError('campaign content too large: ${productParts.length} product parts, ${promptParts.length} prompt parts');
    }
    final docs = <String, Map<String, dynamic>>{};
    for (var i = 0; i < productParts.length; i++) {
      docs[productsPartId(i)] = {
        'kind': 'products',
        'rev': r,
        'part': i,
        'parts': productParts.length,
        'items': productParts[i],
      };
    }
    for (var i = 0; i < promptParts.length; i++) {
      docs[promptPartId(i)] = {
        'kind': 'prompt',
        'rev': r,
        'part': i,
        'parts': promptParts.length,
        'text': promptParts[i],
      };
    }
    return CampaignContentPlan(
      marker: CampaignContentMarker(
        rev: r,
        productParts: productParts.length,
        promptParts: promptParts.length,
        productsCount: products.length,
        promptLength: prompt.length,
        legacyMirror: legacyMirror,
      ),
      parts: docs,
    );
  }

  /// Rebuilds the content from part documents (id -> data, null when missing).
  /// Returns null when anything is missing or does not match the marker.
  static CampaignContent? assemble(CampaignContentMarker marker, Map<String, Map<String, dynamic>?> parts) {
    final products = <String>[];
    for (var i = 0; i < marker.productParts; i++) {
      final d = parts[productsPartId(i)];
      if (d == null || d['kind'] != 'products' || d['rev'] != marker.rev || d['parts'] != marker.productParts) return null;
      final items = d['items'];
      if (items is! List) return null;
      for (final x in items) {
        if (x is! String) return null;
        products.add(x);
      }
    }
    final prompt = StringBuffer();
    for (var i = 0; i < marker.promptParts; i++) {
      final d = parts[promptPartId(i)];
      if (d == null || d['kind'] != 'prompt' || d['rev'] != marker.rev || d['parts'] != marker.promptParts) return null;
      final text = d['text'];
      if (text is! String) return null;
      prompt.write(text);
    }
    final text = prompt.toString();
    if (products.length != marker.productsCount || text.length != marker.promptLength) return null;
    return CampaignContent(requiredProducts: products, customPrompt: text);
  }

  /// Part ids the marker points at.
  static List<String> partIds(CampaignContentMarker marker) => [
        for (var i = 0; i < marker.productParts; i++) productsPartId(i),
        for (var i = 0; i < marker.promptParts; i++) promptPartId(i),
      ];
}

/// The `contentStorage` marker on the campaign document.
@immutable
class CampaignContentMarker {
  final String rev;
  final int productParts;
  final int promptParts;
  final int productsCount;
  final int promptLength;
  final bool legacyMirror;

  const CampaignContentMarker({
    required this.rev,
    required this.productParts,
    required this.promptParts,
    required this.productsCount,
    required this.promptLength,
    this.legacyMirror = true,
  });

  /// Null when [raw] is not a valid version-1 marker.
  static CampaignContentMarker? tryParse(Object? raw) {
    if (raw is! Map) return null;
    int? n(Object? v) => v is int ? v : (v is num && v == v.roundToDouble() ? v.toInt() : null);
    final v = n(raw['v']);
    final rev = raw['rev'];
    final pp = n(raw['productParts']);
    final tp = n(raw['promptParts']);
    final pc = n(raw['productsCount']);
    final pl = n(raw['promptLength']);
    if (v != CampaignContentLayout.version || rev is! String || rev.isEmpty) return null;
    if (pp == null || tp == null || pc == null || pl == null) return null;
    if (pp < 1 || tp < 1 || pp > CampaignContentLayout.maxParts || tp > CampaignContentLayout.maxParts) return null;
    if (pc < 0 || pl < 0) return null;
    return CampaignContentMarker(
      rev: rev,
      productParts: pp,
      promptParts: tp,
      productsCount: pc,
      promptLength: pl,
      legacyMirror: raw['legacyMirror'] != false,
    );
  }

  Map<String, dynamic> toMap() => {
        'v': CampaignContentLayout.version,
        'rev': rev,
        'productParts': productParts,
        'promptParts': promptParts,
        'productsCount': productsCount,
        'promptLength': promptLength,
        'legacyMirror': legacyMirror,
      };
}

@immutable
class CampaignContent {
  final List<String> requiredProducts;
  final String customPrompt;
  const CampaignContent({required this.requiredProducts, required this.customPrompt});
}

@immutable
class CampaignContentPlan {
  final CampaignContentMarker marker;
  final Map<String, Map<String, dynamic>> parts;
  const CampaignContentPlan({required this.marker, required this.parts});
}

/// Reads part documents by id (null for a missing one).
typedef CampaignContentPartsReader = Future<Map<String, Map<String, dynamic>?>> Function(
    String eventId, List<String> partIds);

/// Reads and syncs the content parts of campaigns.
class CampaignContentRepository {
  final CampaignContentPartsReader _readParts;
  final FirebaseFirestore? _firestore;

  /// Hydrated content per "eventId@rev"; a new revision is a new key.
  static final Map<String, CampaignContent> _cache = {};
  static const Duration readTimeout = Duration(seconds: 12);

  CampaignContentRepository(FirebaseFirestore firestore)
      : _firestore = firestore,
        _readParts = _firestoreReader(firestore);

  @visibleForTesting
  CampaignContentRepository.withReader(this._readParts) : _firestore = null;

  @visibleForTesting
  static void clearCache() => _cache.clear();

  static CampaignContentPartsReader _firestoreReader(FirebaseFirestore firestore) {
    return (eventId, ids) async {
      final col = firestore.collection('events').doc(eventId).collection(CampaignContentLayout.subcollection);
      final snaps = await Future.wait(ids.map((id) => col.doc(id).get()));
      return {for (var i = 0; i < ids.length; i++) ids[i]: snaps[i].exists ? snaps[i].data() : null};
    };
  }

  /// [event] with requiredProducts / customPrompt from the content parts when
  /// its marker is valid, else [event] unchanged (legacy fields). Never throws.
  Future<EventModel> hydrate(EventModel event) async {
    final marker = event.contentStorage;
    if (marker == null || event.id.isEmpty) return event;
    final key = '${event.id}@${marker.rev}';
    final cached = _cache[key];
    if (cached != null) {
      return event.copyWith(requiredProducts: cached.requiredProducts, customPrompt: cached.customPrompt);
    }
    try {
      final parts = await _readParts(event.id, CampaignContentLayout.partIds(marker)).timeout(readTimeout);
      final content = CampaignContentLayout.assemble(marker, parts);
      if (content == null) {
        debugPrint('TAG-51: content parts of ${event.id} do not match rev ${marker.rev}; using the campaign fields');
        return event;
      }
      _cache[key] = content;
      return event.copyWith(requiredProducts: content.requiredProducts, customPrompt: content.customPrompt);
    } catch (e) {
      debugPrint('TAG-51: content parts of ${event.id} not read ($e); using the campaign fields');
      return event;
    }
  }

  Future<List<EventModel>> hydrateAll(List<EventModel> events) => Future.wait(events.map(hydrate));

  /// Phase 1 writer: copies the legacy fields of the stored campaign into the
  /// content parts and sets the marker, in one transaction on the campaign
  /// document, so the parts always match what the campaign holds at that
  /// moment (a concurrent edit simply wins and is synced by its own save).
  /// Skips when the marker already has the same revision. Returns the marker
  /// written (or already there), or null when nothing could be written
  /// (missing campaign, rules not deployed yet, offline...). Never throws.
  Future<CampaignContentMarker?> syncFromLegacy(String eventId) async {
    final firestore = _firestore;
    if (firestore == null || eventId.isEmpty) return null;
    final eventRef = firestore.collection('events').doc(eventId);
    try {
      CampaignContentMarker? result;
      await firestore.runTransaction<void>((tx) async {
        result = null;
        final snap = await tx.get(eventRef);
        final data = snap.data();
        if (!snap.exists || data == null) return;
        final products = <String>[
          for (final p in (data['requiredProducts'] is List ? data['requiredProducts'] as List : const []))
            if (p is String) p,
        ];
        final prompt = data['customPrompt'] is String ? data['customPrompt'] as String : '';
        final existing = CampaignContentMarker.tryParse(data[CampaignContentLayout.markerField]);
        final plan = CampaignContentLayout.plan(products, prompt);
        if (existing != null && existing.rev == plan.marker.rev) {
          result = existing;
          return;
        }
        // After the cleanup step the parts are the only copy: never rebuild
        // them from the (removed) campaign fields.
        if (existing != null && !existing.legacyMirror) {
          result = existing;
          return;
        }
        final col = eventRef.collection(CampaignContentLayout.subcollection);
        plan.parts.forEach((id, doc) => tx.set(col.doc(id), doc));
        // Parts of an older, longer revision are left in place: the marker
        // only points at the new ones and their rev no longer matches.
        tx.update(eventRef, {CampaignContentLayout.markerField: plan.marker.toMap()});
        result = plan.marker;
      }, timeout: const Duration(seconds: 30));
      return result;
    } catch (e) {
      debugPrint('TAG-51: content parts of $eventId not synced ($e); the campaign fields stay in use');
      return null;
    }
  }
}
