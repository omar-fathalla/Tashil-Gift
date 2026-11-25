// TAG-56: requiredProducts / customPrompt stored in events/{id}/content.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/campaign_content.dart';
import 'package:al_mraay/features/admin/domain/campaign_edit_save.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

List<String> bigProducts() => List.generate(3636, (i) => 'منتج يونيلفر رقم $i - صابون لوكس ${i % 7} جم');
String bigPrompt() => List.filled(7100, 'أنت مساعد ذكي لفحص فواتير يونيلفر. ').join();

EventModel event(Map<String, dynamic> extra) => EventModel.fromFirestoreMap('e1', {
      'eventName': 'Unilever',
      'targetCompany': 'Unilever',
      'minimumSpend': 0,
      ...extra,
    });

Map<String, Map<String, dynamic>> store(CampaignContentWrites w) => Map.of(w.docs);

void main() {
  test('chunks respect limits and keep order', () {
    final products = bigProducts();
    final chunks = CampaignContentLayout.chunkProducts(products);
    expect(chunks.length, greaterThanOrEqualTo(3));
    for (final c in chunks) {
      expect(c.length, lessThanOrEqualTo(CampaignContentLayout.maxItemsPerChunk));
      expect(utf8.encode(jsonEncode(c)).length, lessThan(900 * 1024));
    }
    expect(chunks.expand((c) => c).toList(), products);
    final prompt = bigPrompt();
    expect(CampaignContentLayout.chunkPrompt(prompt).join(), prompt);
    expect(CampaignContentLayout.chunkProducts(const []), isEmpty);
    expect(CampaignContentLayout.chunkPrompt(''), isEmpty);
  });

  test('a large campaign drops the legacy fields and round-trips', () {
    final products = bigProducts();
    final prompt = bigPrompt();
    final w = CampaignContentLayout.plan(products: products, prompt: prompt);
    expect(w.eventFields['requiredProducts'], isA<FieldValue>());
    expect(w.eventFields['customPrompt'], isA<FieldValue>());
    final pointer = CampaignContentPointer.fromEventData(w.eventFields)!;
    expect(pointer.revision, 1);
    expect(pointer.productsCount, 3636);
    final back = CampaignContentLayout.assemble(pointer, store(w))!;
    expect(back.products, products);
    expect(back.prompt, prompt);
  });

  test('a small campaign keeps the legacy mirror', () {
    final w = CampaignContentLayout.plan(products: const ['Lux'], prompt: 'p');
    expect(w.eventFields['requiredProducts'], ['Lux']);
    expect(w.eventFields['customPrompt'], 'p');
  });

  test('a mixed-revision chunk is rejected; stale chunks are deleted', () {
    final first = CampaignContentLayout.plan(products: bigProducts(), prompt: bigPrompt());
    final p1 = CampaignContentPointer.fromEventData(first.eventFields)!;
    final second = CampaignContentLayout.plan(products: const ['Lux'], prompt: '', previous: p1);
    expect(CampaignContentPointer.fromEventData(second.eventFields)!.revision, 2);
    expect(second.deleteIds, containsAll(['products_1', 'prompt_0']));
    final mixed = store(first)..['products_0'] = second.docs['products_0']!;
    expect(CampaignContentLayout.assemble(p1, mixed), isNull);
  });

  test('create payload: pointer set, large legacy fields absent', () {
    final e = event({'requiredProducts': bigProducts(), 'customPrompt': bigPrompt()});
    final built = CampaignContentLayout.forCreate(e);
    expect(built.eventData.containsKey('requiredProducts'), isFalse);
    expect(built.eventData.containsKey('customPrompt'), isFalse);
    expect(built.eventData['contentVersion'], 1);
    expect(built.eventData['eventName'], 'Unilever');
    final size = utf8.encode(jsonEncode(built.eventData, toEncodable: (_) => null)).length;
    expect(size, lessThan(50 * 1024));
  });

  test('edit: unchanged products and prompt leave the patch alone', () {
    final opened = event({'requiredProducts': ['Lux'], 'customPrompt': 'p'});
    final draft = opened.copyWith(eventName: 'Unilever 2');
    final current = {'eventName': 'Unilever', 'requiredProducts': ['Lux'], 'customPrompt': 'p'};
    final patch = CampaignEditSave.buildEditPatch(draft: draft, opened: opened, currentData: current, updatedBy: 'u');
    expect(CampaignContentLayout.splitEditPatch(patch: patch, draft: draft, currentData: current), isNull);
    expect(patch['eventName'], 'Unilever 2');
    expect(patch.keys.any(CampaignContentLayout.pointerKeys.contains), isFalse);
  });

  test('edit: changed products move to chunks with the next revision', () {
    final products = bigProducts();
    final opened = event({'requiredProducts': products, 'customPrompt': 'p', 'contentVersion': 1, 'contentRevision': 3, 'contentProductsChunks': 3, 'contentPromptChunks': 1, 'requiredProductsCount': products.length, 'customPromptLength': 1}).copyWith(contentLoaded: true);
    final draft = opened.copyWith(requiredProducts: [...products, 'Dove جديد']);
    final current = {'contentVersion': 1, 'contentRevision': 3, 'contentProductsChunks': 3, 'contentPromptChunks': 1};
    final patch = CampaignEditSave.buildEditPatch(draft: draft, opened: opened, currentData: current, updatedBy: 'u');
    expect(patch.containsKey('requiredProducts'), isTrue);
    final w = CampaignContentLayout.splitEditPatch(patch: patch, draft: draft, currentData: current)!;
    expect(patch['contentRevision'], 4);
    expect(patch['requiredProductsCount'], products.length + 1);
    expect(patch['requiredProducts'], isA<FieldValue>(), reason: 'too large to mirror');
    final back = CampaignContentLayout.assemble(CampaignContentPointer.fromEventData(patch)!, store(w))!;
    expect(back.products.last, 'Dove جديد');
    expect(back.prompt, 'p');
  });

  test('model: pointer parsed, counts shown before the content is loaded', () {
    final e = event({'contentVersion': 1, 'contentRevision': 1, 'contentProductsChunks': 3, 'contentPromptChunks': 1, 'requiredProductsCount': 3636, 'customPromptLength': 144730});
    expect(e.contentPointer, isNotNull);
    expect(e.requiredProducts, isEmpty);
    expect(e.requiredProductsCountForDisplay, 3636);
    expect(e.hasCustomPrompt, isTrue);
    final legacy = event({'requiredProducts': ['Lux']});
    expect(legacy.contentPointer, isNull);
    expect(legacy.requiredProductsCountForDisplay, 1);
  });

  final unilever = Platform.environment['TAG56_UNILEVER_JSON'];
  test('optional: real Unilever copy round-trips (never committed)', () {
    final data = jsonDecode(File(unilever!).readAsStringSync()) as Map<String, dynamic>;
    final products = List<String>.from(data['requiredProducts'] as List);
    final prompt = data['customPrompt'] as String;
    final w = CampaignContentLayout.plan(products: products, prompt: prompt);
    final back = CampaignContentLayout.assemble(CampaignContentPointer.fromEventData(w.eventFields)!, store(w))!;
    expect(back.products, products);
    expect(back.prompt, prompt);
  }, skip: unilever == null);
}
