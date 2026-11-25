import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/campaign_content_storage.dart';
import 'package:al_mraay/features/admin/domain/campaign_edit_save.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

// TAG-51 phase 1: requiredProducts / customPrompt copied to events/{id}/content.
// Same fixture and revisions as functions/test/campaign_content.test.js.
const _fixtureProducts = ['كادبري', 'Dove 😀', 'a,b', ''];
const _fixturePrompt = 'برومبت\n{REQUIRED_PRODUCTS} 🎁';

EventModel _event({List<String> products = const ['قديم'], String prompt = 'برومبت قديم', CampaignContentMarker? marker}) => EventModel(
      id: 'E1',
      eventName: 'يونيلفر',
      targetCompany: 'Unilever',
      companySlug: '512',
      minimumSpend: 0,
      requiredProducts: products,
      customPrompt: prompt,
      contentStorage: marker,
    );

void main() {
  setUp(CampaignContentRepository.clearCache);

  test('revision bytes match functions/campaign_content.js', () {
    expect(CampaignContentLayout.rev(_fixtureProducts, _fixturePrompt), '616d97bf7cf48b48acf02b76');
    expect(CampaignContentLayout.rev(const [], ''), '4bf5122f344554c53bde2ebb');
    expect(CampaignContentLayout.rev(const ['ab'], ''), isNot(CampaignContentLayout.rev(const ['a', 'b'], '')));
  });

  test('products and prompt are chunked under the byte limit, order kept, no split surrogate pair', () {
    final products = [for (var i = 0; i < 1000; i++) 'منتج رقم $i'];
    final parts = CampaignContentLayout.chunkProducts(products, maxBytes: 2000);
    expect(parts.length, greaterThan(1));
    for (final p in parts) {
      final bytes = p.fold<int>(0, (s, x) => s + utf8.encode(x).length + 16);
      expect(bytes, lessThanOrEqualTo(2000));
    }
    expect(parts.expand((p) => p).toList(), products);

    final prompt = 'أ😀b' * 5000;
    final promptParts = CampaignContentLayout.chunkPrompt(prompt, maxBytes: 999);
    expect(promptParts.length, greaterThan(1));
    for (final p in promptParts) {
      expect(utf8.encode(p).length, lessThanOrEqualTo(999));
      final last = p.codeUnitAt(p.length - 1);
      expect(last >= 0xD800 && last <= 0xDBFF, isFalse);
    }
    expect(promptParts.join(), prompt);
    expect(CampaignContentLayout.chunkProducts(const []), [<String>[]]);
    expect(CampaignContentLayout.chunkPrompt(''), ['']);
  });

  test('Unilever-sized content (3,636 products, 145k-char prompt) fits in parts well under 1 MiB', () {
    final products = [for (var i = 0; i < 3636; i++) 'يونيلفر صنف $i ${'x' * 40}'];
    final prompt = 'تعليمات ' * 18000;
    final plan = CampaignContentLayout.plan(products, prompt);
    for (final doc in plan.parts.values) {
      expect(utf8.encode(jsonEncode(doc)).length, lessThan(1000000));
    }
    final back = CampaignContentLayout.assemble(plan.marker, plan.parts);
    expect(back!.requiredProducts, products);
    expect(back.customPrompt, prompt);
    expect(CampaignContentLayout.partIds(plan.marker), plan.parts.keys.toList());
  });

  test('assemble returns null on a missing part, an old revision or a wrong count', () {
    final plan = CampaignContentLayout.plan(const ['a', 'b'], 'p');
    expect(CampaignContentLayout.assemble(plan.marker, {...plan.parts, 'prompt-0': null}), isNull);
    expect(
      CampaignContentLayout.assemble(plan.marker, {
        ...plan.parts,
        'products-0': {...plan.parts['products-0']!, 'rev': 'old'},
      }),
      isNull,
    );
    final wrong = CampaignContentMarker(rev: plan.marker.rev, productParts: 1, promptParts: 1, productsCount: 5, promptLength: 1);
    expect(CampaignContentLayout.assemble(wrong, plan.parts), isNull);
  });

  test('marker parsing: EventModel reads it, toFirestore never writes it', () {
    final plan = CampaignContentLayout.plan(const ['a'], 'p');
    final e = EventModel.fromFirestoreMap('E1', {
      'eventName': 'x',
      'targetCompany': 'y',
      'requiredProducts': ['a'],
      'customPrompt': 'p',
      CampaignContentLayout.markerField: plan.marker.toMap(),
    });
    expect(e.contentStorage?.rev, plan.marker.rev);
    expect(e.toFirestore().containsKey(CampaignContentLayout.markerField), isFalse);
    expect(EventModel.campaignEditorOwnedFields.contains(CampaignContentLayout.markerField), isFalse);
    expect(CampaignContentMarker.tryParse({'v': 2, 'rev': 'a'}), isNull);
    expect(CampaignContentMarker.tryParse(null), isNull);
    expect(EventModel.fromFirestoreMap('E2', {'eventName': 'x', 'targetCompany': 'y'}).contentStorage, isNull);
  });

  group('hydrate', () {
    final plan = CampaignContentLayout.plan(const ['جديد 1', 'جديد 2'], 'برومبت جديد');

    test('no marker: the campaign fields, no read at all', () async {
      var reads = 0;
      final repo = CampaignContentRepository.withReader((_, _) async {
        reads++;
        return {};
      });
      final out = await repo.hydrate(_event());
      expect(out.requiredProducts, ['قديم']);
      expect(reads, 0);
    });

    test('valid marker: products and prompt come from the parts (and are cached per revision)', () async {
      var reads = 0;
      final repo = CampaignContentRepository.withReader((id, ids) async {
        reads++;
        expect(id, 'E1');
        return {for (final i in ids) i: plan.parts[i]};
      });
      final out = await repo.hydrate(_event(marker: plan.marker));
      expect(out.requiredProducts, ['جديد 1', 'جديد 2']);
      expect(out.customPrompt, 'برومبت جديد');
      expect(out.eventName, 'يونيلفر');
      await repo.hydrate(_event(marker: plan.marker));
      expect(reads, 1);
    });

    test('parts denied, missing or stale: falls back to the campaign fields, never throws', () async {
      final denied = CampaignContentRepository.withReader((_, _) async => throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
      expect((await denied.hydrate(_event(marker: plan.marker))).requiredProducts, ['قديم']);

      final missing = CampaignContentRepository.withReader((_, ids) async => {for (final i in ids) i: null});
      expect((await missing.hydrate(_event(marker: plan.marker))).customPrompt, 'برومبت قديم');

      final stale = CampaignContentRepository.withReader(
          (_, ids) async => {for (final i in ids) i: {...plan.parts[i]!, 'rev': 'older'}});
      expect((await stale.hydrate(_event(marker: plan.marker))).requiredProducts, ['قديم']);
    });
  });

  group('edit transaction (2.0.185 guards kept)', () {
    final plan = CampaignContentLayout.plan(const ['قديم'], 'برومبت قديم');
    Map<String, dynamic> stored({bool withMarker = true}) => {
          ..._event().toFirestore(),
          if (withMarker) CampaignContentLayout.markerField: plan.marker.toMap(),
        };

    test('prompt edit drops the marker and writes both fields in full', () {
      final opened = _event(marker: plan.marker);
      final draft = opened.copyWith(customPrompt: 'برومبت معدل');
      final patch = CampaignEditSave.buildEditPatch(draft: draft, opened: opened, currentData: stored(), updatedBy: 'u1');
      expect(patch['customPrompt'], 'برومبت معدل');
      expect(patch['requiredProducts'], ['قديم']);
      expect(patch[CampaignContentLayout.markerField], isA<FieldValue>());
    });

    test('an edit that does not touch products or prompt keeps the marker and does not resend them', () {
      final opened = _event(marker: plan.marker);
      final draft = opened.copyWith(eventName: 'اسم جديد');
      final patch = CampaignEditSave.buildEditPatch(draft: draft, opened: opened, currentData: stored(), updatedBy: 'u1');
      expect(patch['eventName'], 'اسم جديد');
      expect(patch.containsKey('requiredProducts'), isFalse);
      expect(patch.containsKey('customPrompt'), isFalse);
      expect(patch.containsKey(CampaignContentLayout.markerField), isFalse);
    });

    test('campaign without a copy: patch unchanged by TAG-51', () {
      final opened = _event();
      final draft = opened.copyWith(requiredProducts: const ['قديم', 'جديد']);
      final patch = CampaignEditSave.buildEditPatch(draft: draft, opened: opened, currentData: stored(withMarker: false), updatedBy: 'u1');
      expect(patch['requiredProducts'], ['قديم', 'جديد']);
      expect(patch.containsKey('customPrompt'), isFalse);
      expect(patch.containsKey(CampaignContentLayout.markerField), isFalse);
    });

    test('lowering a gift below what was handed out is still refused', () {
      final row = AllocatedPrize(giftId: 'g1', name: 'هدية', allocatedQuantity: 100, remainingQuantity: 40, branchId: 'b1', branchName: 'فرع');
      final opened = _event(marker: plan.marker).copyWith(allocatedPrizes: [row]);
      final draft = opened.copyWith(
        customPrompt: 'برومبت معدل',
        allocatedPrizes: [row.copyWith(allocatedQuantity: 10)],
      );
      final current = {...stored(), 'allocatedPrizes': [row.toMap()]};
      expect(
        () => CampaignEditSave.buildEditPatch(draft: draft, opened: opened, currentData: current, updatedBy: 'u1'),
        throwsA(isA<CampaignEditRejected>()),
      );
    });
  });
}
