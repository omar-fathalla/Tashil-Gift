/// 2.0.148+204: isolates partner / brand-manager portal auth from the field
/// rep session.
///
/// Firebase Auth persistence on web is keyed by app name and shared by every
/// tab of the site. When the partner portal signed in (custom token) or out on
/// the default app, it replaced or cleared the anonymous rep session in other
/// tabs on the same phone. Portal routes now run on a separate named app
/// ([kPartnerPortalAppName]) with its own Auth/Firestore/Functions/Storage, so
/// portal sign-in/out never touches the default app.
///
/// Rep routes and admin/super-admin routes keep the default app. A staff admin
/// already signed in on the default app who opens a portal link keeps the
/// default app too (admin preview bypass keeps working).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'anonymous_session_policy.dart' show entryRouteRoot;

const String kPartnerPortalAppName = 'partner-portal';
const String kFunctionsRegion = 'us-central1';

/// Entry route roots served by the partner / company / agency portal.
const Set<String> kPartnerPortalRoots = {
  'portal', 'p', 'company', // company manager / brand manager portal
  'ops', 'agency', 'operations', // agency ops portal
};

bool routeUsesPartnerPortalApp(Uri uri) =>
    kPartnerPortalRoots.contains(entryRouteRoot(uri));

/// Pure decision: should this tab use the isolated portal app?
bool shouldUsePartnerPortalApp({
  required bool portalRoute,
  required bool defaultUserIsStaff,
}) => portalRoute && !defaultUserIsStaff;

class FirebaseScope {
  FirebaseScope._();

  static FirebaseApp? _app;

  /// The Firebase app every service in this tab must use.
  static FirebaseApp get app => _app ?? Firebase.app();

  /// True when this tab runs on the isolated partner-portal app.
  static bool get isPartnerPortal => _app?.name == kPartnerPortalAppName;

  /// Selects the app for this tab. Call once in main() after the default app
  /// is initialized and its persisted session restored.
  static Future<void> init({
    required Uri entryUri,
    required FirebaseOptions options,
  }) async {
    final portalRoute = routeUsesPartnerPortalApp(entryUri);
    if (!portalRoute) return;
    var staff = false;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      try {
        final role = (await user.getIdTokenResult()).claims?['role']
            ?.toString();
        staff = role == 'admin' || role == 'super_admin';
      } catch (_) {}
    }
    if (!shouldUsePartnerPortalApp(
      portalRoute: true,
      defaultUserIsStaff: staff,
    )) {
      return;
    }
    FirebaseApp named;
    try {
      named = Firebase.app(kPartnerPortalAppName);
    } catch (_) {
      named = await Firebase.initializeApp(
        name: kPartnerPortalAppName,
        options: options,
      );
    }
    _app = named;
  }

  /// Test hook.
  static void debugReset() => _app = null;
}

FirebaseAuth scopedAuth() => FirebaseAuth.instanceFor(app: FirebaseScope.app);
FirebaseFirestore scopedFirestore() =>
    FirebaseFirestore.instanceFor(app: FirebaseScope.app);
FirebaseStorage scopedStorage() =>
    FirebaseStorage.instanceFor(app: FirebaseScope.app);
FirebaseFunctions scopedFunctions() => FirebaseFunctions.instanceFor(
  app: FirebaseScope.app,
  region: kFunctionsRegion,
);
