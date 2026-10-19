import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kPrimaryAdminEmail = 'support@switchpoint.com';
const String kFallbackAdminEmail = 'support@sw-point.com';
const String _kMasterAdminPassword = 'Youniis@!1987';

bool isAuthorizedAdminEmail(String? email) {
  if (email == null || email.trim().isEmpty) return false;
  final clean = email.trim().toLowerCase();
  return clean == kPrimaryAdminEmail.toLowerCase() ||
      clean == kFallbackAdminEmail.toLowerCase();
}

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final authStateStreamProvider = StreamProvider<User?>((ref) {
  try {
    return ref.watch(firebaseAuthProvider).authStateChanges();
  } catch (_) {
    return Stream.value(null);
  }
});

final adminSessionEmailProvider = StateProvider<String?>((ref) => null);

final isAdminProvider = Provider<bool>((ref) {
  final sessionEmail = ref.watch(adminSessionEmailProvider);
  if (sessionEmail != null && isAuthorizedAdminEmail(sessionEmail)) {
    return true;
  }
  try {
    final user = ref.watch(authStateStreamProvider).value ??
        ref.watch(firebaseAuthProvider).currentUser;
    if (user != null && !user.isAnonymous && isAuthorizedAdminEmail(user.email)) {
      return true;
    }
  } catch (_) {}
  return false;
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  final instance = FirebaseFirestore.instance;
  try {
    instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (_) {}
  return instance;
});

final firebaseStorageProvider = Provider<FirebaseStorage>((ref) {
  return FirebaseStorage.instance;
});

class FirebaseService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final Ref _ref;

  FirebaseService(this._auth, this._firestore, this._storage, this._ref);

  FirebaseFirestore get firestore => _firestore;
  FirebaseStorage get storage => _storage;

  // Authentication: Dual cloud verification with master fallback resilience
  Future<void> signIn(String email, String password) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPassword = password.trim();

    if (!isAuthorizedAdminEmail(cleanEmail)) {
      throw FirebaseAuthException(
        code: 'unauthorized-admin',
        message: 'هذا البريد الإلكتروني غير مسجل ضمن مسؤولي النظام المعتمدين.',
      );
    }

    final isMasterMatch = (cleanPassword == _kMasterAdminPassword);

    // 1. Attempt cloud Firebase Auth verification
    bool cloudAuthSuccess = false;
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: cleanEmail,
        password: cleanPassword,
      );
      if (credential.user != null) {
        cloudAuthSuccess = true;
        _ref.read(adminSessionEmailProvider.notifier).state = cleanEmail;
        await _syncAdminProfile(credential.user);
      }
    } on FirebaseAuthException catch (authErr) {
      if (authErr.code == 'user-not-found' || authErr.code == 'invalid-credential') {
        try {
          final newCred = await _auth.createUserWithEmailAndPassword(
            email: cleanEmail,
            password: cleanPassword,
          );
          if (newCred.user != null) {
            cloudAuthSuccess = true;
            _ref.read(adminSessionEmailProvider.notifier).state = cleanEmail;
            await _syncAdminProfile(newCred.user);
          }
        } catch (_) {}
      }
    } catch (_) {}

    // 2. Master Password Matching: Instant login guarantee with background session
    if (isMasterMatch) {
      _ref.read(adminSessionEmailProvider.notifier).state = cleanEmail;
      
      try {
        if (_auth.currentUser == null) {
          await _auth.signInAnonymously();
        }
      } catch (_) {}

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('active_admin_session', cleanEmail);
      } catch (_) {}

      try {
        await _firestore.collection('admins').doc(cleanEmail).set({
          'email': cleanEmail,
          'role': 'super_admin',
          'lastLoginAt': FieldValue.serverTimestamp(),
          'verified': true,
        }, SetOptions(merge: true));
      } catch (_) {}

      return;
    }

    if (!cloudAuthSuccess) {
      throw FirebaseAuthException(
        code: 'invalid-credential',
        message: 'كلمة المرور غير صحيحة، يرجى التأكد والمحاولة مجدداً.',
      );
    }
  }

  Future<void> _syncAdminProfile(User? user) async {
    if (user == null || user.email == null) return;
    try {
      await _firestore.collection('admins').doc(user.email!.toLowerCase()).set({
        'uid': user.uid,
        'email': user.email!.toLowerCase(),
        'role': 'super_admin',
        'lastLoginAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> ensureAuthenticatedSession() async {
    if (_auth.currentUser != null) return;
    try {
      await _auth.signInAnonymously();
    } catch (_) {}
  }

  Future<void> signOut() async {
    _ref.read(adminSessionEmailProvider.notifier).state = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_admin_session');
    } catch (_) {}
    try {
      await _auth.signOut();
      // Re-establish anonymous session so background listener streams don't break with permission denied
      await _auth.signInAnonymously();
    } catch (_) {}
  }

  User? get currentUser => _auth.currentUser;

  bool get isAdmin {
    final sessionEmail = _ref.read(adminSessionEmailProvider);
    if (sessionEmail != null && isAuthorizedAdminEmail(sessionEmail)) {
      return true;
    }
    final user = _auth.currentUser;
    return user != null && !user.isAnonymous && isAuthorizedAdminEmail(user.email);
  }
  
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
