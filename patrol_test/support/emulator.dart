// Seeding for the Patrol web tests (TAG-82 PR 2).
//
// Everything here talks to the local Firebase emulators only
// (project demo-tashil-branch on 127.0.0.1). The accounts and passwords are
// fixtures that exist only inside the emulator; they are not secrets.
// No Gemini, no WhatsApp, no tashil-gift or tashil-gift-dev.
import 'dart:convert';

import 'package:al_mraay/core/services/firebase_emulator_config.dart';
import 'package:http/http.dart' as http;

const projectId = 'demo-tashil-branch';
const host = kFirebaseEmulatorHost;

const adminEmail = 'patrol-admin@demo.local';
const adminPassword = 'fixture-pass-patrol';

const eventId = 'patrol-consuming-upload';
const eventName = 'اختبار Patrol سلم الإنفاق';
const gift350 = 'patrol-gift-350';
const gift500 = 'patrol-gift-500';

/// Stops the test before it can reach a real project.
void assertEmulatorBuild() {
  if (!kFirebaseEmulator) {
    throw StateError(
      'Patrol tests run only on an emulator build: '
      '--dart-define=FIREBASE_EMULATOR=true --dart-define=SYNTHETIC_RECEIPT_FIXTURE=true',
    );
  }
  if (kFirebaseEmulatorOptions.projectId != projectId || !projectId.startsWith('demo-')) {
    throw StateError('Emulator project must be $projectId, got ${kFirebaseEmulatorOptions.projectId}');
  }
  if (host != '127.0.0.1' && host != 'localhost') {
    throw StateError('Emulator host must be local, got $host');
  }
}

Uri _u(int port, String path) => Uri.parse('http://$host:$port$path');

Future<Map<String, dynamic>> _post(Uri url, Map<String, Object?> body, {Map<String, String> headers = const {}}) async {
  final res = await http.post(
    url,
    headers: {'content-type': 'application/json', ...headers},
    body: jsonEncode(body),
  );
  if (res.statusCode >= 300 && !res.body.contains('EMAIL_EXISTS')) {
    throw StateError('${res.statusCode} $url\n${res.body}');
  }
  return res.body.isEmpty ? {} : jsonDecode(res.body) as Map<String, dynamic>;
}

/// Creates (or reuses) the fixture super admin in the Auth emulator.
Future<void> seedAdmin() async {
  await _post(_u(9099, '/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo'),
      {'email': adminEmail, 'password': adminPassword, 'returnSecureToken': true});
  final signed = await _post(_u(9099, '/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo'),
      {'email': adminEmail, 'password': adminPassword, 'returnSecureToken': true});
  await _post(
    _u(9099, '/identitytoolkit.googleapis.com/v1/accounts:update?key=demo'),
    {'localId': signed['localId'], 'customAttributes': jsonEncode({'role': 'super_admin'})},
    headers: {'authorization': 'Bearer owner'},
  );
}

Map<String, Object?> _s(String v) => {'stringValue': v};
Map<String, Object?> _b(bool v) => {'booleanValue': v};
Map<String, Object?> _d(num v) => {'doubleValue': v};
Map<String, Object?> _i(int v) => {'integerValue': '$v'};
Map<String, Object?> _l(List<Object?> v) => {'arrayValue': {'values': v}};
Map<String, Object?> _m(Map<String, Object?> f) => {'mapValue': {'fields': f}};

Map<String, Object?> _tier(String id, num min, String giftId, num amount) => _m({
      'id': _s(id),
      'ruleTitle': _s('شريحة $min'),
      'conditionType': _s('by_spend'),
      'minSpend': _d(min),
      'triggerProduct': _s('كادبري'),
      'requiredBrands': _l([_s('كادبري')]),
      'selectedBarcodes': _l([_s('6220000000011')]),
      'rewardType': _s('voucher'),
      'rewardValue': _s('قسيمة شراء $amount جنيه'),
      'rewardAmount': _d(amount),
      'allowMultipliers': _b(true),
      'rewardOptions': _l([
        _m({
          'id': _s('opt-$id'),
          'kind': _s('voucher'),
          'giftId': _s(giftId),
          'giftType': _s('voucher'),
          'voucherAmount': _d(amount),
          'label': _s('قسيمة شراء $amount جنيه'),
        }),
      ]),
    });

Map<String, Object?> _stock(String giftId, num unit) => _m({
      'giftId': _s(giftId),
      'name': _s('قسيمة شراء $unit جنيه'),
      'giftType': _s('voucher'),
      'unitValue': _d(unit),
      'remainingQuantity': _i(5),
      'allocatedQuantity': _i(5),
    });

Future<void> _put(String collection, String id, Map<String, Object?> fields) async {
  final url = _u(8080, '/v1/projects/$projectId/databases/(default)/documents/$collection/$id');
  final res = await http.patch(url,
      headers: {'content-type': 'application/json', 'authorization': 'Bearer owner'},
      body: jsonEncode({'fields': fields}));
  if (res.statusCode >= 300) throw StateError('${res.statusCode} $collection/$id\n${res.body}');
}

Future<Map<String, dynamic>?> _get(String collection, String id) async {
  final url = _u(8080, '/v1/projects/$projectId/databases/(default)/documents/$collection/$id');
  final res = await http.get(url, headers: {'authorization': 'Bearer owner'});
  if (res.statusCode == 404) return null;
  if (res.statusCode >= 300) throw StateError('${res.statusCode} $collection/$id\n${res.body}');
  return jsonDecode(res.body) as Map<String, dynamic>;
}

Future<void> _delete(String collection, String id) async {
  final url = _u(8080, '/v1/projects/$projectId/databases/(default)/documents/$collection/$id');
  await http.delete(url, headers: {'authorization': 'Bearer owner'});
}

/// The receipt number the synthetic fixture reads as (same as
/// tool/consuming_upload_ui_runner.mjs).
const receiptNumber = '901/1/901/071126';

/// Bytes the app recognises as the synthetic receipt when built with
/// SYNTHETIC_RECEIPT_FIXTURE=true, so Gemini is never called.
const syntheticReceiptBytes = 'tashil-synthetic-receipt-v1:1402-ambiguous';

/// A consuming spend-ladder campaign with three voucher tiers and stock.
Future<void> seedCampaign() async {
  await _put('events', eventId, {
    'eventName': _s(eventName),
    'targetCompany': _s('كادبري'),
    'companySlug': _s('fixture-co'),
    'minimumSpend': _d(200),
    'isActive': _b(true),
    'gameType': _s('chooseGift'),
    'spendLadderMode': _s('consuming'),
    'allowMultipleChances': _b(true),
    'maxChancesPerReceipt': _i(3),
    'retailChainName': _s('سلسلة الاختبار'),
    'branchNames': _l([_s('فرع الاختبار')]),
    'isAllBranches': _b(true),
    'enableWhatsAppWinnerNotification': _b(false),
    'promotionalRules': _l([
      _tier('tier-200', 200, 'patrol-gift-200', 50),
      _tier('tier-350', 350, gift350, 100),
      _tier('tier-500', 500, gift500, 150),
    ]),
    'allocatedPrizes': _l([_stock(gift500, 150), _stock(gift500, 100), _stock(gift350, 100)]),
  });
  await _delete('receipts_transactions', receiptDocId);
}

/// The ledger document the upload creates for [receiptNumber].
const receiptDocId = 'rcpt_${eventId}_901_1_901_071126';

/// How many gifts the server recorded on the receipt (claimed_gifts).
Future<int> receiptClaimedUnits() async {
  final doc = await _get('receipts_transactions', receiptDocId);
  if (doc == null) throw StateError('receipt $receiptDocId was not saved');
  final fields = (doc['fields'] as Map<String, dynamic>?) ?? const {};
  final gifts = fields['claimed_gifts'] as Map<String, dynamic>?;
  final values = (gifts?['arrayValue'] as Map<String, dynamic>?)?['values'] as List?;
  return values?.length ?? 0;
}

/// Receipt images the upload stored in the Storage emulator for the test
/// fixture company (`receipts/fixture-co/...`, under the event id or `multi_bundles/`). The upload falls back to
/// an inline data: URL when Storage fails, so this is the only proof that the
/// image really went through storage.rules.
Future<List<String>> receiptImagePaths() async {
  final bucket = kFirebaseEmulatorOptions.storageBucket;
  final prefix = Uri.encodeQueryComponent('receipts/fixture-co/');
  final url = Uri.parse('http://$host:9199/v0/b/$bucket/o?prefix=$prefix');
  final res = await http.get(url, headers: {'authorization': 'Bearer owner'});
  if (res.statusCode >= 300) throw StateError('${res.statusCode} $url\n${res.body}');
  final items = (jsonDecode(res.body) as Map<String, dynamic>)['items'] as List? ?? const [];
  return [for (final i in items) (i as Map<String, dynamic>)['name'] as String];
}
