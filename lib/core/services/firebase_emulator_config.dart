import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'firebase_scope.dart';

/// Local-only switch. A normal build leaves this false and keeps production.
const bool kFirebaseEmulator = bool.fromEnvironment('FIREBASE_EMULATOR');

/// `demo-` project ids are rejected by production Firebase. Combined with the
/// emulator ports below, this build cannot reach the live project.
const FirebaseOptions kFirebaseEmulatorOptions = FirebaseOptions(
  apiKey: 'demo',
  appId: '1:0:web:demo-tashil-branch',
  messagingSenderId: '0',
  projectId: 'demo-tashil-branch',
  storageBucket: 'demo-tashil-branch.appspot.com',
);

const String kFirebaseEmulatorHost = String.fromEnvironment(
  'FIREBASE_EMULATOR_HOST',
  defaultValue: '127.0.0.1',
);

/// Points Auth, Firestore, Storage, and Functions at localhost.
/// Call immediately after [Firebase.initializeApp] and before any read.
///
/// The functions emulator is not required to be running. The host is set so a
/// claim never builds a `cloudfunctions.net` URL. A refused connection may
/// fall back to the Firestore emulator for a signed-in staff user. A callable
/// that answers with App Check, permission, or a gift-rule rejection does not.
Future<void> attachFirebaseEmulators() async {
  FirebaseFirestore.instance.useFirestoreEmulator(kFirebaseEmulatorHost, 8080);
  await FirebaseAuth.instance.useAuthEmulator(kFirebaseEmulatorHost, 9099);
  try {
    await FirebaseStorage.instance.useStorageEmulator(kFirebaseEmulatorHost, 9199);
  } catch (e) {
    debugPrint('Storage emulator attach skipped: $e');
  }
  try {
    FirebaseFunctions.instanceFor(region: kFunctionsRegion).useFunctionsEmulator(
      kFirebaseEmulatorHost,
      5001,
    );
  } catch (e) {
    debugPrint('Functions emulator attach skipped: $e');
  }
  if (kDebugMode) {
    debugPrint(
      'Firebase emulators attached at $kFirebaseEmulatorHost '
      '(project ${kFirebaseEmulatorOptions.projectId}).',
    );
  }
}
