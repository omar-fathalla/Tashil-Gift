import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../firebase_options.dart';
import '../../firebase_options_dev.dart';
import 'app_env.dart';

/// Thrown when a dev build starts while lib/firebase_options_dev.dart still
/// holds placeholders. A dev build must never fall back to production.
class DevFirebaseConfigMissing implements Exception {
  const DevFirebaseConfigMissing();
  @override
  String toString() =>
      'APP_ENV=dev but lib/firebase_options_dev.dart still has TODO_ '
      'placeholders. Fill in the tashil-gift-dev web config '
      '(docs/DEV_ENVIRONMENT.md).';
}

/// FirebaseOptions for [env].
///
/// prod returns [DefaultFirebaseOptions.currentPlatform], unchanged.
/// dev returns [DevFirebaseOptions.web] (dev is web-only for now) and throws
/// [DevFirebaseConfigMissing] if it is not filled in, or [UnsupportedError]
/// on a non-web platform.
FirebaseOptions firebaseOptionsFor(
  AppEnvironment env, {
  bool? isWeb,
  FirebaseOptions? devWebOptions,
}) {
  switch (env) {
    case AppEnvironment.prod:
      return DefaultFirebaseOptions.currentPlatform;
    case AppEnvironment.dev:
      if (!(isWeb ?? kIsWeb)) {
        throw UnsupportedError(
          'APP_ENV=dev is web-only. Register Android/iOS apps in '
          'tashil-gift-dev before building mobile against dev.',
        );
      }
      final options = devWebOptions ?? DevFirebaseOptions.web;
      if (!DevFirebaseOptions.isConfiguredOptions(options)) {
        throw const DevFirebaseConfigMissing();
      }
      if (options.projectId != kDevProjectId) {
        throw StateError(
          'Dev FirebaseOptions point at ${options.projectId}, expected $kDevProjectId.',
        );
      }
      return options;
  }
}

/// Options for this build (APP_ENV).
FirebaseOptions get currentEnvFirebaseOptions =>
    firebaseOptionsFor(AppEnv.current);
