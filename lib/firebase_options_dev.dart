// Firebase options for the DEV project `tashil-gift-dev`.
//
// Used only by builds made with `--dart-define=APP_ENV=dev`
// (see lib/core/config/firebase_env_options.dart). Production builds never
// read this file.
//
// Values come from the `tashil-gift-dev-web` web app (Firebase console ->
// Project settings -> Your apps -> Web app -> SDK setup and configuration ->
// Config), registered 2026-11-25. Firebase web config is public, not a
// secret. If a value is ever reset to a `TODO_` placeholder, a dev build
// refuses to start (and CI skips the dev deploy) instead of falling back to
// production.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DevFirebaseOptions {
  /// Marker prefix of an unfilled value.
  static const String placeholderPrefix = 'TODO_';

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBvyzS6DuwJ1I5CST1wBta3YTPkA7re5Qc',
    appId: '1:871169518648:web:0ef2437d5b7183e299cacd',
    messagingSenderId: '871169518648',
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
