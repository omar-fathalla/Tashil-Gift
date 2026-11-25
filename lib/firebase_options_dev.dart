// Firebase options for the DEV project `tashil-gift-dev`.
//
// Used only by builds made with `--dart-define=APP_ENV=dev`
// (see lib/core/config/firebase_env_options.dart). Production builds never
// read this file.
//
// TODO(TAG-3/TAG-8): fill in the real web config of the `tashil-gift-dev` web
// app (Firebase console -> Project settings -> Your apps -> Web app ->
// SDK setup and configuration -> Config). Firebase web config is not a
// secret, but the values below must come from that console page; do not
// invent them. Until every `TODO_` value is replaced, a dev build refuses to
// start (and CI skips the dev deploy) instead of falling back to production.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DevFirebaseOptions {
  /// Marker prefix of an unfilled value.
  static const String placeholderPrefix = 'TODO_';

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'TODO_DEV_WEB_API_KEY',
    appId: 'TODO_DEV_WEB_APP_ID',
    messagingSenderId: 'TODO_DEV_MESSAGING_SENDER_ID',
    projectId: 'tashil-gift-dev',
    authDomain: 'tashil-gift-dev.firebaseapp.com',
    storageBucket: 'tashil-gift-dev.firebasestorage.app',
  );

  /// True once the console values replaced every placeholder.
  static bool get isConfigured => isConfiguredOptions(web);

  static bool isConfiguredOptions(FirebaseOptions o) {
    final values = <String?>[
      o.apiKey,
      o.appId,
      o.messagingSenderId,
      o.projectId,
      o.authDomain,
      o.storageBucket,
    ];
    return values.every(
      (v) => v != null && v.isNotEmpty && !v.startsWith(placeholderPrefix),
    );
  }
}
