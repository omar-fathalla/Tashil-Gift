import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String kPrimaryAdminEmail = 'support@sw-point.com';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final authStateStreamProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

final isAdminProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateStreamProvider);
  final user = authState.value ?? ref.watch(firebaseAuthProvider).currentUser;
  if (user == null || user.email == null) return false;
  final email = user.email!.trim().toLowerCase();
  return email == kPrimaryAdminEmail.toLowerCase() || email.endsWith('@sw-point.com');
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

  FirebaseService(this._auth, this._firestore, this._storage);

  FirebaseFirestore get firestore => _firestore;
  FirebaseStorage get storage => _storage;

  // Authentication
  Future<UserCredential> signIn(String email, String password) async {
    final cleanEmail = email.trim().toLowerCase();
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      // Ensure admin document exists in Firestore
      await _syncAdminProfile(credential.user);
      return credential;
    } on FirebaseAuthException catch (e) {
      // If user not found and attempting official primary admin account, auto-provision
      if ((e.code == 'user-not-found' || e.code == 'invalid-credential') && cleanEmail == kPrimaryAdminEmail.toLowerCase()) {
        try {
          final credential = await _auth.createUserWithEmailAndPassword(
            email: cleanEmail,
            password: password,
          );
          await _syncAdminProfile(credential.user);
          return credential;
        } catch (_) {
          // If creation fails (e.g. password mismatch with existing user), rethrow original error
          rethrow;
        }
      }
      rethrow;
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
    await _auth.signOut();
  }

  User? get currentUser => _auth.currentUser;

  bool get isAdmin {
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
  return FirebaseService(auth, firestore, storage);
});

