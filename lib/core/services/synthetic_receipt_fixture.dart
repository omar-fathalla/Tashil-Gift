import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';

import 'firebase_emulator_config.dart';

/// Compile-time switch for the local 1402 receipt fixture.
/// A production build does not pass this define.
const bool kSyntheticReceiptFixture = bool.fromEnvironment(
  'SYNTHETIC_RECEIPT_FIXTURE',
);

/// Closed unless every constraint is true. An uninitialized Firebase app is
/// not treated as a demo project.
bool syntheticReceiptMayServe({
  required bool emulatorBuild,
  required bool fixtureRequested,
  required bool firebaseReady,
  required String projectId,
  required String emulatorHost,
}) {
  if (!emulatorBuild || !fixtureRequested || !firebaseReady) return false;
  if (!projectId.startsWith('demo-')) return false;
  return emulatorHost == '127.0.0.1' ||
      emulatorHost == 'localhost' ||
      emulatorHost == '::1';
}

/// Local OCR stand-in for one synthetic image.
///
/// Served only when this build was compiled for the emulator, the fixture
/// define is on, Firebase is already initialized, the project id starts with
/// `demo-`, and the emulator host is loopback. Any other image still goes to
/// the model.
class SyntheticReceiptFixture {
  static bool get enabled {
    if (!kFirebaseEmulator || !kSyntheticReceiptFixture) return false;
    if (Firebase.apps.isEmpty) return false;
    return syntheticReceiptMayServe(
      emulatorBuild: true,
      fixtureRequested: true,
      firebaseReady: true,
      projectId: Firebase.app().options.projectId,
      emulatorHost: kFirebaseEmulatorHost,
    );
  }

  static final Uint8List imageBytes = Uint8List.fromList(
    utf8.encode('tashil-synthetic-receipt-v1:1402-ambiguous'),
  );

  static const String receiptNumber = '901/1/901/071126';

  /// Same JSON shape the model returns. Amounts are the printed lines.
  /// The ambiguous cake line is included and is not pre-classified as ineligible.
  static const String modelText = '''
{
  "isValid": true,
  "receiptNumber": "901/1/901/071126",
  "targetCompanyTotal": 1528,
  "receiptDate": "07/11/2026",
  "storeChainDetected": "سلسلة الاختبار",
  "branchDetected": "فرع الاختبار",
  "isBranchMatched": true,
  "isHandwritten": false,
  "isThermalPosReceipt": true,
  "isTampered": false,
  "isScreenCapture": false,
  "chancesEarned": 9,
  "message": "synthetic fixture",
  "unfulfilledConditions": [],
  "fraudReasons": [],
  "extractedProducts": [
    {"name": "كادبري بوبل", "price": 492, "quantity": 1, "barcode": "6220000000011", "discountAmount": 0, "isTargetCompany": true},
    {"name": "كادبري بوبل", "price": 240, "quantity": 1, "barcode": "6220000000011", "discountAmount": 0, "isTargetCompany": true},
    {"name": "كادبري بوبل", "price": 294, "quantity": 1, "barcode": "6220000000011", "discountAmount": 0, "isTargetCompany": true},
    {"name": "كادبري بوبل", "price": 294, "quantity": 1, "barcode": "6220000000011", "discountAmount": 0, "isTargetCompany": true},
    {"name": "كادبري بوبل", "price": 82, "quantity": 1, "barcode": "6220000000011", "discountAmount": 0, "isTargetCompany": true},
    {"name": "لارش كيك ميلت شوك", "price": 64, "quantity": 3, "barcode": "", "discountAmount": 22, "isTargetCompany": true}
  ]
}
''';

  static String? modelTextFor(Uint8List bytes) {
    if (!enabled || !_same(bytes, imageBytes)) return null;
    return modelText;
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
