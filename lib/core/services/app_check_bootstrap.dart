import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Public reCAPTCHA Enterprise site key registered for the Tashil Gift web app
/// in Firebase App Check (project tashil-gift). Site keys are public by design.
const String kDefaultAppCheckRecaptchaSiteKey =
    '6LeDqgAuAAAAAG85Dr9wbiM2KPg-LTktjT_qfN6H';

/// Web reCAPTCHA Enterprise site key. Override at build time with
/// `--dart-define=APP_CHECK_RECAPTCHA_SITE_KEY=<key>`; pass an empty value
/// to disable web App Check (e.g. for local experiments).
const String kAppCheckRecaptchaSiteKey = String.fromEnvironment(
  'APP_CHECK_RECAPTCHA_SITE_KEY',
  defaultValue: kDefaultAppCheckRecaptchaSiteKey,
);

/// Activates Firebase App Check.
///
/// Release builds use Play Integrity (Android), App Attest (Apple), and
/// reCAPTCHA Enterprise (web). Debug builds use the App Check debug providers
/// so a local debug token can be registered in the Firebase console.
///
/// Web activation is skipped only if [kAppCheckRecaptchaSiteKey] is empty.
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
