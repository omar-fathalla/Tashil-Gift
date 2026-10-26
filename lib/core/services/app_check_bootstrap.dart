import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Web reCAPTCHA Enterprise site key.
/// Pass it at build time:
/// `--dart-define=APP_CHECK_RECAPTCHA_SITE_KEY=your-site-key`
const String kAppCheckRecaptchaSiteKey = String.fromEnvironment(
  'APP_CHECK_RECAPTCHA_SITE_KEY',
  defaultValue: '',
);

/// Activates Firebase App Check.
///
/// Release builds use Play Integrity (Android), App Attest (Apple), and
/// reCAPTCHA Enterprise (web). Debug builds use the App Check debug providers
/// so a local debug token can be registered in the Firebase console.
///
/// Web activation is skipped until [kAppCheckRecaptchaSiteKey] is provided.
/// Callable functions still reject requests that arrive without an App Check token.
Future<void> activateFirebaseAppCheck() async {
  if (kIsWeb && kAppCheckRecaptchaSiteKey.isEmpty) {
    debugPrint(
      'App Check web provider skipped: set APP_CHECK_RECAPTCHA_SITE_KEY via --dart-define.',
    );
    return;
  }

  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleAppAttestProvider(),
      providerWeb: kAppCheckRecaptchaSiteKey.isEmpty
          ? null
          : ReCaptchaEnterpriseProvider(kAppCheckRecaptchaSiteKey),
    );
  } catch (e) {
    debugPrint('App Check activation failed: $e');
  }
}
