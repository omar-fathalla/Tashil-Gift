import 'dart:convert';

import 'package:al_mraay/features/admin/data/campaign_content_repository.dart';
import 'package:al_mraay/features/admin/domain/campaign_draft.dart';
import 'package:al_mraay/features/admin/domain/campaign_dry_run.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// TAG-65: a draft of a big campaign (event + base lists) must not exceed the
// 1 MiB doc limit. TAG-66: an unsaved big campaign can still be tried on a receipt.

List<String> _products(int n) => [for (var i = 0; i < n; i++) 'منتج يونيليفر رقم $i باركود 62211556${i.toString().padLeft(5, '0')}'];

EventModel _campaign({String id = '', List<String>? products, String prompt = 'p'}) => EventModel(
      id: id,
      eventName: 'Big',
      targetCompany: 'Unilever',
      companySlug: 'uni',
      minimumSpend: 100,
      requiredProducts: products ?? const ['كنور'],
      customPrompt: prompt,
      startDate: DateTime(2026, 11, 20),
      endDate: DateTime(2026, 11, 30),
    );

int _docBytes(Map<String, dynamic>? m) => utf8.encode(jsonEncode(m, toEncodable: (_) => null)).length;

void main() {
  group('TAG-65 draft content', () {
    test('a small draft stays in one doc with no content docs', () async {
      final db = FakeFirebaseFirestore();
      final store = CampaignDraftStore(db);
      final id = await store.save(event: _campaign(), updatedBy: 'u');
      final doc = (await db.collection(kEventDraftsCollection).doc(id).get()).data()!;
      expect(doc.containsKey('externalContent'), isFalse);
      expect((doc['event'] as Map)['requiredProducts'], ['كنور']);
      expect((await db.collection('$kEventDraftsCollection/$id/content').get()).docs, isEmpty);
    });

    test('a 10,000-product edit draft splits its lists out and loads back the same', () async {
      final db = FakeFirebaseFirestore();
      final store = CampaignDraftStore(db);
      final base = _campaign(id: 'E1', products: _products(10000), prompt: 'base prompt');
      final edited = _campaign(id: 'E1', products: [..._products(10000), 'صنف جديد'], prompt: 'new prompt');
      expect(CampaignContentRepository.productsBytes(edited.requiredProducts) * 2, greaterThan(1024 * 1024));

      final id = await store.save(event: edited, updatedBy: 'u', editing: base);
      final raw = (await db.collection(kEventDraftsCollection).doc(id).get()).data()!;
      expect(raw['externalContent'], isA<Map>());
      expect((raw['event'] as Map).containsKey('requiredProducts'), isFalse);
      expect((raw['base'] as Map).containsKey('customPrompt'), isFalse);
      expect(_docBytes(raw), lessThan(64 * 1024));
      final content = await db.collection('$kEventDraftsCollection/$id/content').get();
      for (final d in content.docs) {
        expect(_docBytes(d.data()), lessThan(1024 * 1024 - 1024));
      }

      final stored = CampaignDraft.fromMap(id, raw);
      expect(stored.needsContentLoad, isTrue);
      final full = await store.hydrate(stored);
      expect(full.event.requiredProducts, edited.requiredProducts);
      expect(full.event.customPrompt, 'new prompt');
      expect(full.baseEvent!.requiredProducts, base.requiredProducts);
      expect(full.baseEvent!.customPrompt, 'base prompt');
      expect(full.event.id, 'E1');
    });

    test('saving it small again removes the leftover content docs; delete removes them too', () async {
      final db = FakeFirebaseFirestore();
      final store = CampaignDraftStore(db);
      final id = await store.save(event: _campaign(products: _products(12000)), updatedBy: 'u');
      expect((await db.collection('$kEventDraftsCollection/$id/content').get()).docs, isNotEmpty);

      await store.save(draftId: id, event: _campaign(), updatedBy: 'u');
      expect((await db.collection('$kEventDraftsCollection/$id/content').get()).docs, isEmpty);
      final raw = (await db.collection(kEventDraftsCollection).doc(id).get()).data()!;
      expect(raw.containsKey('externalContent'), isFalse);

      await store.save(draftId: id, event: _campaign(products: _products(12000)), updatedBy: 'u');
      await store.delete(id);
      expect((await db.collection('$kEventDraftsCollection/$id/content').get()).docs, isEmpty);
      expect((await db.collection(kEventDraftsCollection).doc(id).get()).exists, isFalse);
    });

    test('a missing or stale chunk is an error, never an empty list', () async {
      final db = FakeFirebaseFirestore();
      final store = CampaignDraftStore(db);
      final id = await store.save(event: _campaign(products: _products(12000)), updatedBy: 'u');
      await db.doc('$kEventDraftsCollection/$id/content/${CampaignDraftContent.productsDocId('event', 0)}').update({'version': -1});
      final raw = (await db.collection(kEventDraftsCollection).doc(id).get()).data()!;
      expect(() => store.hydrate(CampaignDraft.fromMap(id, raw)), throwsA(isA<CampaignContentUnavailable>()));
    });
  });

  group('TAG-66 dry run before save', () {
    test('an unsaved campaign sends its whole list, even a big one', () {
      final big = _campaign(products: _products(8000));
      final req = CampaignDryRun.request(campaign: big, receipt: const {});
      expect((req['campaign'] as Map)['requiredProducts'], hasLength(8000));
      expect(req.containsKey('contentEventId'), isFalse);
      expect(jsonEncode(req).length, greaterThan(300000));
      expect(jsonEncode(req).length, lessThan(CampaignDryRun.maxRequestChars));
    });

    test('past the server cap the app says to save first', () {
      final huge = _campaign(products: _products(120000));
      expect(() => CampaignDryRun.request(campaign: huge, receipt: const {}), throwsA(isA<DryRunTooLarge>()));
    });
  });
}
