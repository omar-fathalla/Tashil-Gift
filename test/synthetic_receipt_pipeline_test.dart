// Isolated upload path for the 1402 fixture.
//
// Production and a normal test build leave the fixture off:
//   flutter test test/synthetic_receipt_pipeline_test.dart
//
// The same production analysis, save fields, recheck, gift screen, and claim
// run only in an emulator build:
//   flutter test \
//     --dart-define=FIREBASE_EMULATOR=true \
//     --dart-define=SYNTHETIC_RECEIPT_FIXTURE=true \
//     test/synthetic_receipt_pipeline_test.dart
//
// Add persistence and the callable when the local emulators are already up:
//   RUN_SYNTHETIC_UPLOAD_E2E=1 flutter test \
//     --dart-define=FIREBASE_EMULATOR=true \
//     --dart-define=SYNTHETIC_RECEIPT_FIXTURE=true \
//     test/synthetic_receipt_pipeline_test.dart
//
// Functions must be on 127.0.0.1:5001 with
// FIREBASE_DEBUG_MODE=true and
// FIREBASE_DEBUG_FEATURES={"skipTokenVerification":true}.
// Those variables stay off the deployed function.

import 'dart:convert';
import 'dart:io';

import 'package:al_mraay/core/services/accepted_receipt_core.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/services/multi_campaign_receipt_evaluator.dart';
import 'package:al_mraay/core/services/receipt_deduplication_helper.dart';
import 'package:al_mraay/core/services/synthetic_receipt_fixture.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/games/presentation/choose_gift_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const gift500 = '4QDy4H8psECEP4AnJSON';
const gift350 = 'beGiYXcMAsW78OGevW5d';

PromotionalRuleItem tier(String id, double min, String giftId, double amount) {
  return PromotionalRuleItem(
    id: id,
    ruleTitle: 'شريحة ${min.toInt()}',
    triggerProduct: 'كادبري',
    conditionType: 'by_spend',
    minSpend: min,
    rewardType: 'voucher',
    rewardValue: 'قسيمة شراء ${amount.toInt()} جنيه',
    rewardAmount: amount,
    requiredBrands: const ['كادبري'],
    selectedBarcodes: const ['6220000000011'],
    rewardOptions: [
      RewardOption(
        id: 'opt-$id',
        kind: 'voucher',
        giftId: giftId,
        giftType: 'voucher',
        voucherAmount: amount,
        label: 'قسيمة شراء ${amount.toInt()} جنيه',
      ),
    ],
  );
}

final rules = [
  tier('tier-200', 200, 'gift-200', 50),
  tier('tier-350', 350, gift350, 100),
  tier('tier-500', 500, gift500, 150),
];

EventModel campaign({int cap = 3}) {
  return EventModel(
    id: 'fixture-consuming-upload',
    eventName: 'اختبار السلم',
    targetCompany: 'كادبري',
    companySlug: 'fixture-co',
    minimumSpend: 200,
    promotionalRules: rules,
    gameType: 'chooseGift',
    allowMultipleChances: true,
    maxChancesPerReceipt: cap,
    spendLadderMode: 'consuming',
    retailChainName: 'سلسلة الاختبار',
    branchNames: const ['فرع الاختبار'],
  );
}

Future<AiReceiptAnalysisResult> analyze(int cap) {
  return AiReceiptService().analyzeReceiptImage(
    SyntheticReceiptFixture.imageBytes,
    'image/jpeg',
    targetCompany: 'كادبري',
    minimumSpend: 200,
    requiredProducts: const ['كادبري'],
    promotionalRules: rules,
    allowMultipleChances: true,
    maxChancesPerReceipt: cap,
    spendLadderMode: 'consuming',
  );
}

void main() {
  test('the fixture image is served only when the emulator switch is compiled in', () {
    expect(
      SyntheticReceiptFixture.modelTextFor(SyntheticReceiptFixture.imageBytes),
      SyntheticReceiptFixture.enabled ? isNotNull : isNull,
    );
  });

  test('fixture bytes travel through production analysis, save, recheck, and the gift screen', () async {
    if (!SyntheticReceiptFixture.enabled) return;

    final result = await analyze(3);
    expect(result.pipelineTierUsed, 'synthetic_fixture');
    expect(result.extractedProducts.map((item) => item.name), contains('لارش كيك ميلت شوك'));
    expect(result.chancesEarned, 3);

    final matched = PromotionalRuleMatcher.matchAllWithMultipliers(
      result: result,
      promotionalRules: rules,
      allowCampaignMultipliers: true,
      maxUnitsPerReceipt: 3,
      spendLadderMode: 'consuming',
    );
    final rounds = SpendAwardRound.expand(matched);
    expect(rounds.map((round) => round.tierMinSpend), [500, 500, 350]);
    expect(rounds.map((round) => round.giftIds.single), [gift500, gift500, gift350]);

    final capped = await analyze(2);
    expect(capped.chancesEarned, 2);

    final summary = MultiCampaignReceiptEvaluator.evaluateAll(
      result: result,
      campaigns: [campaign()],
    );
    final winning = summary.qualifiedCampaigns.single;
    expect(winning.totalChances, 3);
    expect(
      SpendAwardRound.expand(winning.matchedRules).map((round) => round.tierMinSpend),
      [500, 500, 350],
    );

    final saved = acceptedReceiptCore(
      result: result,
      campaignId: campaign().id,
      companySlug: 'fixture-co',
      targetCompany: 'كادبري',
      retailChainName: 'سلسلة الاختبار',
      chancesEarned: winning.totalChances,
      allowMultipleChances: true,
      submittedByUid: 'fixture-user',
      branchFields: const {'branch_detected': 'فرع الاختبار'},
    );
    final reloaded = (saved['extracted_products'] as List)
        .map((item) => ExtractedProductItem.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    expect(reloaded.map((item) => item.name), contains('لارش كيك ميلت شوك'));
    final recheck = AiReceiptAnalysisResult(
      isValid: true,
      receiptNumber: saved['receipt_number'] as String,
      targetCompanyTotal: (saved['target_company_total'] as num).toDouble(),
      receiptDate: saved['receipt_date'] as String,
      extractedProducts: reloaded,
      storeChainDetected: saved['store_chain_detected'] as String,
      branchDetected: 'فرع الاختبار',
      message: 'recheck',
      durationMs: 0,
    );
    final again = MultiCampaignReceiptEvaluator.evaluateAll(
      result: recheck,
      campaigns: [campaign()],
    );
    expect(
      SpendAwardRound.expand(again.qualifiedCampaigns.single.matchedRules).map((round) => round.unitValues.single),
      [150, 150, 100],
    );
  });

  testWidgets('the analyzed rounds open on the production gift screen', (tester) async {
    if (!SyntheticReceiptFixture.enabled) return;
    final result = await analyze(3);
    final rounds = SpendAwardRound.expand(PromotionalRuleMatcher.matchAllWithMultipliers(
      result: result,
      promotionalRules: rules,
      allowCampaignMultipliers: true,
      maxUnitsPerReceipt: 3,
      spendLadderMode: 'consuming',
    ));
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ChooseGiftScreen(
            totalChances: rounds.length,
            isDemo: true,
            prizes: rounds.first.prizeNames,
            roundPrizeNames: [for (final round in rounds) round.prizeNames],
            roundGiftIds: [for (final round in rounds) round.giftIds],
            roundUnitValues: [for (final round in rounds) round.unitValues],
            roundTierMinSpends: [for (final round in rounds) round.tierMinSpend],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('شريحة 500'), findsWidgets);
    expect(find.text('قسيمة شراء 150 جنيه'), findsOneWidget);
    expect(find.textContaining('شريحة 350: قسيمة شراء 100 جنيه'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  test('uploaded fixture can be rechecked and claimed on the local emulators', () async {
    if (!SyntheticReceiptFixture.enabled) return;
    if (Platform.environment['RUN_SYNTHETIC_UPLOAD_E2E'] != '1') return;
    await _runEmulatorFlow();
  });
}

Future<void> _runEmulatorFlow() async {
  final result = await analyze(3);
  final winning = MultiCampaignReceiptEvaluator.evaluateAll(
    result: result,
    campaigns: [campaign()],
  ).qualifiedCampaigns.single;
  final core = acceptedReceiptCore(
    result: result,
    campaignId: 'fixture-consuming-upload',
    companySlug: 'fixture-co',
    targetCompany: 'كادبري',
    retailChainName: 'سلسلة الاختبار',
    chancesEarned: winning.totalChances,
    allowMultipleChances: true,
    submittedByUid: 'pending',
    branchFields: const {'branch_detected': 'فرع الاختبار', 'canonical_branch': 'فرع الاختبار'},
  );
  core['game_played'] = false;
  core['remaining_chances'] = winning.totalChances;

  HttpOverrides.global = null;
  final client = HttpClient();
  try {
    final auth = await _post(client, Uri.parse(
      'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo',
    ), {'email': 'upload-flow@demo.local', 'password': 'fixture-pass-234', 'returnSecureToken': true});
    var localId = auth['localId']?.toString();
    if (localId == null) {
      final signed = await _post(client, Uri.parse(
        'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo',
      ), {'email': 'upload-flow@demo.local', 'password': 'fixture-pass-234', 'returnSecureToken': true});
      localId = signed['localId'].toString();
    }
    await _post(
      client,
      Uri.parse('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:update?key=demo'),
      {'localId': localId, 'customAttributes': jsonEncode({'role': 'super_admin'})},
      headers: {'authorization': 'Bearer owner'},
    );
    final token = (await _post(client, Uri.parse(
      'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo',
    ), {'email': 'upload-flow@demo.local', 'password': 'fixture-pass-234', 'returnSecureToken': true}))['idToken'].toString();

    core['submittedByUid'] = localId;
    await _putDoc(client, 'events', 'fixture-consuming-upload', _eventFields());
    final docId = ReceiptDeduplicationHelper.getDeterministicDocId(
      campaignId: 'fixture-consuming-upload',
      receiptNumber: SyntheticReceiptFixture.receiptNumber,
    );
    await _putDoc(client, 'receipts_transactions', docId, core.map((key, value) => MapEntry(key, value)));

    final stored = await _readDoc(client, 'receipts_transactions', docId);
    final names = (stored['extracted_products'] as List).map((item) => (item as Map)['name']).toList();
    expect(names, contains('لارش كيك ميلت شوك'));

    Future<Map<String, dynamic>> claim(String prize, num unit) {
      return _post(
        client,
        Uri.parse('http://127.0.0.1:5001/demo-tashil-branch/us-central1/decrementCampaignPrize'),
        {
          'data': {
            'eventId': 'fixture-consuming-upload',
            'receiptId': docId,
            'decrements': [{
              'prizeIdentifier': prize,
              'count': 1,
              'unitValue': unit,
              'isVoucher': true,
              'gameType': 'chooseGift',
            }],
            'receiptPatch': {
              'game_played': true,
              'claimed_gifts': [
                {'giftName': 'forged', 'unitValue': 100},
              ],
              'remaining_chances': 0,
            },
          },
        },
        headers: {
          'authorization': 'Bearer $token',
          'x-firebase-appcheck': 'local.emulator.token',
        },
        allowError: true,
      );
    }

    final first = await claim(gift500, 100);
    expect(first['error'], isNull);
    final legacy = await _readDoc(client, 'receipts_transactions', docId);
    final gifts = legacy['claimed_gifts'] as List;
    expect(gifts, hasLength(1));
    expect((gifts.single as Map)['unitValue'], 150);
    expect((gifts.single as Map)['quantity'] ?? 1, 1);

    expect((await claim(gift500, 100))['error'], isNull);
    expect((await claim(gift350, 150))['error'], isNull);
    final done = await _readDoc(client, 'receipts_transactions', docId);
    final ledger = done['claimed_gifts'] as List;
    expect(ledger.map((item) => (item as Map)['unitValue']), [150, 150, 100]);
    expect((await claim(gift500, 150))['error'], isNotNull);

    final event = await _readDoc(client, 'events', 'fixture-consuming-upload');
    final rows = event['allocatedPrizes'] as List;
    expect((rows[1] as Map)['remainingQuantity'], 5);
  } finally {
    client.close();
  }
}

Map<String, dynamic> _eventFields() {
  Map<String, dynamic> one(String id, int min, String giftId, int amount) => {
    'id': id,
    'conditionType': 'by_spend',
    'minSpend': min,
    'triggerProduct': 'كادبري',
    'requiredBrands': ['كادبري'],
    'selectedBarcodes': ['6220000000011'],
    'allowMultipliers': true,
    'rewardOptions': [{
      'kind': 'voucher',
      'giftId': giftId,
      'giftType': 'voucher',
      'voucherAmount': amount,
      'label': 'قسيمة شراء $amount جنيه',
    }],
  };
  return {
    'companySlug': 'fixture-co',
    'isActive': true,
    'spendLadderMode': 'consuming',
    'allowMultipleChances': true,
    'maxChancesPerReceipt': 3,
    'balanceMode': 'campaign_only',
    'promotionalRules': [
      one('tier-200', 200, 'gift-200', 50),
      one('tier-350', 350, gift350, 100),
      one('tier-500', 500, gift500, 150),
    ],
    'allocatedPrizes': [
      {'giftId': gift500, 'name': 'قسيمة شراء 150 جنيه', 'giftType': 'voucher', 'unitValue': 150, 'remainingQuantity': 5, 'allocatedQuantity': 5},
      {'giftId': gift500, 'name': 'قسيمة شراء 100 جنيه', 'giftType': 'voucher', 'unitValue': 100, 'remainingQuantity': 5, 'allocatedQuantity': 5},
      {'giftId': gift350, 'name': 'قسيمة شراء 100 جنيه', 'giftType': 'voucher', 'unitValue': 100, 'remainingQuantity': 5, 'allocatedQuantity': 5},
    ],
  };
}

Object _fs(Object? value) {
  if (value == null) return {'nullValue': null};
  if (value is bool) return {'booleanValue': value};
  if (value is int) return {'integerValue': '$value'};
  if (value is double) return {'doubleValue': value};
  if (value is String) return {'stringValue': value};
  if (value is List) return {'arrayValue': {'values': value.map(_fs).toList()}};
  if (value is Map) {
    return {
      'mapValue': {
        'fields': value.map((key, item) => MapEntry(key.toString(), _fs(item))),
      },
    };
  }
  return {'stringValue': value.toString()};
}

Object? _un(Object? field) {
  if (field is! Map) return field;
  if (field.containsKey('stringValue')) return field['stringValue'];
  if (field.containsKey('integerValue')) return int.parse(field['integerValue'].toString());
  if (field.containsKey('doubleValue')) return field['doubleValue'];
  if (field.containsKey('booleanValue')) return field['booleanValue'];
  if (field.containsKey('nullValue')) return null;
  if (field.containsKey('arrayValue')) {
    final values = (field['arrayValue'] as Map)['values'];
    if (values is! List) return <Object?>[];
    return values.map(_un).toList();
  }
  if (field.containsKey('mapValue')) {
    final fields = ((field['mapValue'] as Map)['fields'] as Map?) ?? {};
    return fields.map((key, item) => MapEntry(key.toString(), _un(item)));
  }
  return field;
}

Future<Map<String, dynamic>> _post(
  HttpClient client,
  Uri uri,
  Map<String, dynamic> body, {
  Map<String, String> headers = const {},
  bool allowError = false,
}) async {
  final request = await client.postUrl(uri);
  request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  headers.forEach(request.headers.set);
  request.add(utf8.encode(jsonEncode(body)));
  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
  if (response.statusCode >= 400 && !allowError && decoded['error'] == null) {
    throw HttpException('${response.statusCode} $uri $text', uri: uri);
  }
  if (response.statusCode >= 400 && decoded['error'] == null) {
    return {'error': {'status': response.statusCode, 'message': text}};
  }
  return decoded;
}

Future<void> _putDoc(HttpClient client, String collection, String id, Map<String, dynamic> fields) async {
  final uri = Uri.parse(
    'http://127.0.0.1:8080/v1/projects/demo-tashil-branch/databases/(default)/documents/$collection/$id',
  );
  final request = await client.patchUrl(uri);
  request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
  request.add(utf8.encode(jsonEncode({
    'fields': fields.map((key, value) => MapEntry(key, _fs(value))),
  })));
  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  if (response.statusCode >= 400) {
    throw HttpException('${response.statusCode} $collection/$id $text', uri: uri);
  }
}

Future<Map<String, dynamic>> _readDoc(HttpClient client, String collection, String id) async {
  final uri = Uri.parse(
    'http://127.0.0.1:8080/v1/projects/demo-tashil-branch/databases/(default)/documents/$collection/$id',
  );
  final request = await client.getUrl(uri);
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  if (response.statusCode >= 400) {
    throw HttpException('${response.statusCode} $text', uri: uri);
  }
  final fields = (jsonDecode(text) as Map)['fields'] as Map? ?? {};
  return fields.map((key, value) => MapEntry(key.toString(), _un(value)));
}
