import 'anonymous_session_policy.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'firebase_scope.dart';

/// Historical inboxes. These addresses are not an authorization allow-list.
/// Admin access comes only from the ID token `role` claim.
const String kPrimaryAdminEmail = 'support@switchpoint.com';
const String kFallbackAdminEmail = 'support@sw-point.com';

/// Default documented super admin for the one-time bootstrap script.
const String kBootstrapSuperAdminEmail = 'support@sw-point.com';

bool isAuthorizedAdminEmail(String? email) {
  if (email == null || email.trim().isEmpty) return false;
  final clean = email.trim().toLowerCase();
  return clean == kPrimaryAdminEmail.toLowerCase() ||
      clean == kFallbackAdminEmail.toLowerCase();
}

/// Staff portal access. `partner` is a company portal role, not a system admin.
bool isStaffRole(String? role) {
  return role == 'super_admin' || role == 'admin';
}

class StaffAuthClaims {
  final String? role;
  final String? email;
  final String? companySlug;
  final String? partnerAccess;

  const StaffAuthClaims({
    this.role,
    this.email,
    this.companySlug,
    this.partnerAccess,
  });

  static const empty = StaffAuthClaims();

  bool get isStaff => isStaffRole(role);
  bool get isSuperAdmin => role == 'super_admin';
  bool get isPartner => role == 'partner';
}

/// Cloud Functions for this tab's Firebase app (see FirebaseScope).
final firebaseFunctionsProvider = Provider<FirebaseFunctions>((ref) => scopedFunctions());

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return scopedAuth();
});

final authStateStreamProvider = StreamProvider<User?>((ref) {
  try {
    return ref.watch(firebaseAuthProvider).authStateChanges();
  } catch (_) {
    return Stream.value(null);
  }
});

/// Display-only email of the signed-in staff user. Never used to grant access.
final adminSessionEmailProvider = StateProvider<String?>((ref) => null);

/// ID token custom claims. Reloads when Firebase rotates the token.
final authClaimsProvider = StreamProvider<StaffAuthClaims>((ref) {
  try {
    final auth = ref.watch(firebaseAuthProvider);
    return auth.idTokenChanges().asyncMap((user) async {
      if (user == null || user.isAnonymous) return StaffAuthClaims.empty;
      try {
        final result = await user.getIdTokenResult();
        final claims = result.claims ?? const <String, dynamic>{};
        return StaffAuthClaims(
          role: claims['role']?.toString(),
          email: user.email,
          companySlug: claims['companySlug']?.toString(),
          partnerAccess: claims['partnerAccess']?.toString(),
        );
      } catch (_) {
        return StaffAuthClaims.empty;
      }
    });
  } catch (_) {
    return Stream.value(StaffAuthClaims.empty);
  }
});

final isAdminProvider = Provider<bool>((ref) {
  return ref.watch(authClaimsProvider).asData?.value.isStaff ?? false;
});

final isSuperAdminProvider = Provider<bool>((ref) {
  return ref.watch(authClaimsProvider).asData?.value.isSuperAdmin ?? false;
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  final instance = scopedFirestore();
  try {
    instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (_) {}
  return instance;
});

final firebaseStorageProvider = Provider<FirebaseStorage>((ref) {
  return scopedStorage();
});

class FirebaseService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final Ref _ref;

  FirebaseService(this._auth, this._firestore, this._storage, this._ref);

  FirebaseFirestore get firestore => _firestore;
  FirebaseStorage get storage => _storage;

  /// Email/password sign-in. Succeeds only when the ID token role is
  /// `super_admin` or `admin`. Does not create accounts.
  Future<void> signIn(String email, String password) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPassword = password;
    if (cleanEmail.isEmpty || cleanPassword.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-credential',
        message: 'يرجى إدخال البريد الإلكتروني وكلمة المرور.',
      );
    }

    final credential = await _auth.signInWithEmailAndPassword(
      email: cleanEmail,
      password: cleanPassword,
    );
    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'invalid-credential',
        message: 'تعذر تسجيل الدخول. حاول مرة أخرى.',
      );
    }

    final token = await user.getIdTokenResult(true);
    final role = token.claims?['role']?.toString();
    if (!isStaffRole(role)) {
      await _auth.signOut();
      await ensureAuthenticatedSession();
      throw FirebaseAuthException(
        code: 'unauthorized-admin',
        message: 'هذا الحساب لا يملك صلاحية مدير النظام. يجب أن يمنح المشرف الأعلى الدور عبر setUserRole.',
      );
    }

    _ref.read(adminSessionEmailProvider.notifier).state = user.email?.toLowerCase();
  }

  Future<void> ensureAuthenticatedSession() async {
    if (_auth.currentUser != null) return;
    if (!routeNeedsAnonymousSession(Uri.base)) return;
    try {
      await _auth.signInAnonymously();
    } catch (_) {}
  }

  Future<void> signOut() async {
    _ref.read(adminSessionEmailProvider.notifier).state = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_admin_session');
      await prefs.remove('saved_admin_password');
    } catch (_) {}
    try {
      await _auth.signOut();
      if (routeNeedsAnonymousSession(Uri.base)) {
        await _auth.signInAnonymously();
      }
    } catch (_) {}
  }

  User? get currentUser => _auth.currentUser;

  bool get isAdmin => _ref.read(isAdminProvider);

  Stream<User?> get authStateChanges => _auth.authStateChanges();
}

final firebaseServiceProvider = Provider<FirebaseService>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  final firestore = ref.watch(firestoreProvider);
  final storage = ref.watch(firebaseStorageProvider);
  final service = FirebaseService(auth, firestore, storage, ref);
  service.ensureAuthenticatedSession();
  return service;
});
