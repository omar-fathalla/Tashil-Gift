import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kPrimaryAdminEmail = 'support@sw-point.com';
const String kPrimaryAdminPassword = 'Youniis@!1987';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final authStateStreamProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

final adminSessionEmailProvider = StateProvider<String?>((ref) => null);

final adminSessionInitializerProvider = FutureProvider<void>((ref) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool('remember_admin_me') ?? true;
    final activeSession = prefs.getString('active_admin_session');
    if (rememberMe && activeSession != null && activeSession.isNotEmpty) {
      ref.read(adminSessionEmailProvider.notifier).state = activeSession;
    }
  } catch (_) {}
});

final isAdminProvider = Provider<bool>((ref) {
  final sessionEmail = ref.watch(adminSessionEmailProvider);
  if (sessionEmail != null && sessionEmail.isNotEmpty) {
    final clean = sessionEmail.trim().toLowerCase();
    if (clean == kPrimaryAdminEmail.toLowerCase() || clean.endsWith('@sw-point.com')) {
      return true;
    }
  }
  return false;
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  final instance = FirebaseFirestore.instance;
  try {
    instance.settings = const Settings(persistenceEnabled: true);
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

  // Authentication
  Future<void> signIn(String email, String password) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPassword = password.trim();

    // 1. Check if entering primary super admin credentials
    final isSuperAdminMatch = (cleanEmail == kPrimaryAdminEmail.toLowerCase() || cleanEmail.endsWith('@sw-point.com')) &&
        (cleanPassword == kPrimaryAdminPassword);

    if (isSuperAdminMatch) {
      // Set active session in Riverpod state
      _ref.read(adminSessionEmailProvider.notifier).state = cleanEmail;

      // Persist active session in local storage
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('active_admin_session', cleanEmail);
      } catch (_) {}

      // Best effort Firebase Auth background session (for rules)
      try {
        await _auth.signInWithEmailAndPassword(email: cleanEmail, password: cleanPassword);
      } catch (_) {
        try {
          await _auth.createUserWithEmailAndPassword(email: cleanEmail, password: cleanPassword);
        } catch (_) {
          try {
            if (_auth.currentUser == null) {
              await _auth.signInAnonymously();
            }
          } catch (_) {}
        }
      }

      // Sync admin record in Firestore
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

    // 2. Standard Firebase Auth flow for any other users
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: cleanEmail,
        password: cleanPassword,
      );
      if (credential.user?.email != null) {
        _ref.read(adminSessionEmailProvider.notifier).state = credential.user!.email!.toLowerCase();
      }
      await _syncAdminProfile(credential.user);
    } on FirebaseAuthException {
      rethrow;
    } catch (_) {
      throw FirebaseAuthException(
        code: 'invalid-credential',
        message: 'بيانات الدخول غير صحيحة أو الحساب غير مصرح له كمسؤول نظام.',
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

  Future<void> signOut() async {
    _ref.read(adminSessionEmailProvider.notifier).state = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_admin_session');
    } catch (_) {}
    try {
      await _auth.signOut();
    } catch (_) {}
  }

  User? get currentUser => _auth.currentUser;

  bool get isAdmin {
    final sessionEmail = _ref.read(adminSessionEmailProvider);
    if (sessionEmail != null) {
      final clean = sessionEmail.trim().toLowerCase();
      if (clean == kPrimaryAdminEmail.toLowerCase() || clean.endsWith('@sw-point.com')) {
        return true;
      }
    }
    final user = _auth.currentUser;
    if (user == null || user.email == null) return false;
    final email = user.email!.trim().toLowerCase();
    return email == kPrimaryAdminEmail.toLowerCase() || email.endsWith('@sw-point.com');
  }
  
  Stream<User?> get authStateChanges => _auth.authStateChanges();
}

final firebaseServiceProvider = Provider<FirebaseService>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  final firestore = ref.watch(firestoreProvider);
  final storage = ref.watch(firebaseStorageProvider);
  return FirebaseService(auth, firestore, storage, ref);
});


