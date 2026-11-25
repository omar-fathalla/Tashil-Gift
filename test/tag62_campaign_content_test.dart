import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/utils/error_handler.dart';
import 'package:al_mraay/features/admin/data/campaign_content_repository.dart';
import 'package:al_mraay/features/admin/domain/campaign_dry_run.dart';
import 'package:al_mraay/features/admin/domain/campaign_edit_save.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

// TAG-62 phase 1: products / prompt in events/{id}/content.

List<String> _products(int n) =>
    List.generate(n, (i) => 'منتج يونيليفر رقم $i - عبوة 250 جم - منظف متعدد الاستخدامات برائحة الليمون');

final _bigPrompt = 'تعليمات فحص الفاتورة ' * 7000; // ~145k chars

EventModel _campaign({List<String> products = const ['كادبري'], String prompt = 'p'}) => EventModel(
      id: 'E1',
      eventName: 'Unilever',
      targetCompany: 'Unilever',
      companySlug: 'unilever',
      minimumSpend: 0,
      requiredProducts: products,
      customPrompt: prompt,
    );

/// Content docs as a map, read through the repository's reader hook.
CampaignContentDocReader _reader(Map<String, Map<String, dynamic>> docs, List<String> reads) => (id) async {
      reads.add(id);
      return docs[id];
    };

void main() {
  setUp(CampaignContentRepository.clearCache);

  group('CampaignContentInfo', () {
    test('legacy campaign doc: inline, nothing to load', () {
      final e = EventModel.fromFirestoreMap('E1', {'requiredProducts': ['أ'], 'customPrompt': 'p'});
      expect(e.contentInfo.needsLoad, isFalse);
      expect(e.requiredProductsCount, 1);
    });

    test('externalized doc: needs load, count from the campaign doc', () {
      final e = EventModel.fromFirestoreMap('E1', {
        'hasExternalContent': true,
        'contentVersion': 3,
        'contentChunks': 2,
        'requiredProductsCount': 3636,
      });
      expect(e.contentInfo.needsLoad, isTrue);
      expect(e.requiredProducts, isEmpty);
      expect(e.requiredProductsCount, 3636);
    });
  });

  group('plan', () {
    test('small campaign is written in both places', () {
      final w = CampaignContentRepository.plan(products: ['أ', 'ب'], prompt: 'p', version: 1);
      expect(w.inline, isTrue);
      expect(w.eventFields['requiredProducts'], ['أ', 'ب']);
      expect(w.eventFields['hasExternalContent'], isTrue);
      expect(w.docs.keys, containsAll(['products', 'prompt']));
      expect(w.docs['products']!['items'], ['أ', 'ب']);
    });

    test('Unilever-sized campaign keeps no inline copy; create payload omits the keys', () {
      final w = CampaignContentRepository.plan(products: _products(3636), prompt: _bigPrompt, version: 1);
      expect(w.inline, isFalse);
      expect(w.eventFields['requiredProducts'], isA<FieldValue>());
      final create = w.applyToCreate(_campaign(products: _products(3636), prompt: _bigPrompt).toFirestore());
      expect(create.containsKey('requiredProducts'), isFalse);
      expect(create.containsKey('customPrompt'), isFalse);
      expect(create['requiredProductsCount'], 3636);
    });

    test('10,000 products are chunked under the limit; shrinking deletes leftover chunks', () {
      final list = _products(10000);
      final w = CampaignContentRepository.plan(products: list, prompt: _bigPrompt, version: 2, previousChunks: 5);
      final chunks = w.eventFields['contentChunks'] as int;
      expect(chunks, greaterThanOrEqualTo(2));
      for (var i = 0; i < chunks; i++) {
        final items = w.docs['products_$i']!['items'] as List<String>;
        expect(utf8.encode(jsonEncode(items)).length, lessThanOrEqualTo(CampaignContentRepository.chunkLimitBytes));
      }
      expect(w.deletes, [for (var i = chunks; i < 5; i++) 'products_$i']);
    });

    test('a prompt over the limit is refused', () {
      expect(
        () => CampaignContentRepository.plan(products: const [], prompt: 'x' * (950 * 1024), version: 1),
        throwsA(isA<CampaignContentTooLarge>()),
      );
    });
  });

  group('loadWith', () {
    test('inline content: no read', () async {
      final reads = <String>[];
      final c = await CampaignContentRepository.loadWith(_campaign(), _reader({}, reads));
      expect(c.products, ['كادبري']);
      expect(reads, isEmpty);
    });

    test('chunked content reads back in order and is cached per version', () async {
      final list = _products(10000);
      final w = CampaignContentRepository.plan(products: list, prompt: _bigPrompt, version: 4, timestamp: 0);
      final e = EventModel.fromFirestoreMap('E1', w.applyToCreate({'eventName': 'x'}));
      final reads = <String>[];
      final c = await CampaignContentRepository.loadWith(e, _reader(w.docs, reads));
      expect(c.products, list);
      expect(c.prompt, _bigPrompt);
      final n = reads.length;
      await CampaignContentRepository.loadWith(e, _reader(w.docs, reads));
      expect(reads.length, n);
    });

    test('missing doc or mixed chunk versions fail closed', () async {
      final e = EventModel.fromFirestoreMap('E1', {'hasExternalContent': true, 'contentVersion': 1});
      await expectLater(CampaignContentRepository.loadWith(e, _reader({}, [])), throwsA(isA<CampaignContentUnavailable>()));
      final w = CampaignContentRepository.plan(products: _products(10000), prompt: '', version: 2, timestamp: 0);
      final docs = Map<String, Map<String, dynamic>>.from(w.docs);
      docs['products_0'] = {...docs['products_0']!, 'version': 1};
      final e2 = EventModel.fromFirestoreMap('E2', {'hasExternalContent': true, 'contentVersion': 2});
      await expectLater(CampaignContentRepository.loadWith(e2, _reader(docs, [])), throwsA(isA<CampaignContentUnavailable>()));
    });
  });

  group('edit transaction plan', () {
    Map<String, dynamic> stored(EventModel e) => e.toFirestore()..remove('createdAt');

    test('rename only: no content write', () {
      final opened = _campaign();
      final attempt = CampaignEditAttempt(draft: opened.copyWith(eventName: 'New'), opened: opened, updatedBy: 'u');
      final patch = attempt.plan(stored(opened))!;
      expect(attempt.contentWrite, isNull);
      expect(patch.containsKey('requiredProducts'), isFalse);
    });

    test('products changed on a small campaign: content docs + inline copy, version bumped', () {
      final opened = _campaign();
      final attempt = CampaignEditAttempt(draft: opened.copyWith(requiredProducts: ['جديد']), opened: opened, updatedBy: 'u');
      final patch = attempt.plan({...stored(opened), 'contentVersion': 2})!;
      expect(attempt.contentWrite, isNotNull);
      expect(patch['requiredProducts'], ['جديد']);
      expect(patch['contentVersion'], 3);
      expect(attempt.contentWrite!.docs['products']!['items'], ['جديد']);
    });

    test('editing another field of the stored oversized Unilever doc externalizes it (TAG-50)', () {
      final opened = _campaign(products: _products(3636), prompt: _bigPrompt);
      final attempt = CampaignEditAttempt(draft: opened.copyWith(eventName: 'Unilever 2'), opened: opened, updatedBy: 'u');
      final patch = attempt.plan(stored(opened))!;
      expect(attempt.contentWrite, isNotNull);
      expect(patch['requiredProducts'], isA<FieldValue>());
      expect(patch['customPrompt'], isA<FieldValue>());
      expect(patch['eventName'], 'Unilever 2');
      // What goes on the campaign doc itself is small now.
      final inlineBytes = utf8.encode(jsonEncode({
        for (final e in patch.entries)
          if (e.value is! FieldValue) e.key: e.value.toString(),
      })).length;
      expect(inlineBytes, lessThan(64 * 1024));
    });

    test('a too-large prompt is a rejection, not an exception in the transaction', () {
      final opened = _campaign();
      final attempt = CampaignEditAttempt(draft: opened.copyWith(customPrompt: 'x' * (950 * 1024)), opened: opened, updatedBy: 'u');
      expect(attempt.plan(stored(opened)), isNull);
      expect(attempt.rejection, isNotNull);
      expect(() => attempt.throwIfRejected(), throwsA(isA<CampaignEditRejected>()));
    });
  });

  test('dry run sends a stored campaign id instead of a huge product list', () {
    final big = _campaign(products: _products(3636));
    final req = CampaignDryRun.request(campaign: big, receipt: const {});
    expect((req['campaign'] as Map).containsKey('requiredProducts'), isFalse);
    expect(req['contentEventId'], 'E1');
    final small = CampaignDryRun.request(campaign: _campaign(), receipt: const {});
    expect((small['campaign'] as Map)['requiredProducts'], ['كادبري']);
    expect(small.containsKey('contentEventId'), isFalse);
  });

  group('TAG-50 error messages', () {
    for (final code in ['invalid-argument', 'aborted', 'failed-precondition', 'resource-exhausted']) {
      test('$code has an Arabic message and the raw code is shown', () {
        final e = FirebaseException(plugin: 'cloud_firestore', code: code, message: 'raw $code');
        final friendly = AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'افتراضي');
        expect(friendly, isNot('افتراضي'));
        expect(RegExp(r'[\u0600-\u06FF]').hasMatch(friendly), isTrue);
        final withCode = AppErrorHandler.getMessageWithCode(e, defaultMessage: 'افتراضي');
        expect(withCode, contains(code));
        expect(withCode, contains('raw $code'));
      });
    }
  });
}
