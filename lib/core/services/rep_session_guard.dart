/// 2.0.148: keeps the rep upload screen on an anonymous Firebase session.
///
/// Firebase Auth is shared by every tab of the same site. Signing in to (or
/// out of) the partner portal in another tab swaps or clears the rep tab's
/// anonymous identity, and the next scan fails with unauthenticated /
/// permission-denied. These helpers detect that and restore an anonymous
/// session (staff/admin sessions are never signed out).
library;

import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_service.dart' show isStaffRole;
import 'receipt_save_failure.dart' show receiptErrorCode;

/// Minimal view of the current user, so the decision is unit-testable.
class RepIdentity {
  final bool signedIn;
  final bool isAnonymous;
  final String? role;
  const RepIdentity({required this.signedIn, this.isAnonymous = false, this.role});
}

enum RepSessionAction { none, signInAnonymously, signOutThenAnonymous }

/// What the rep screen must do to get back to an anonymous session.
RepSessionAction repSessionActionFor(RepIdentity id) {
  if (!id.signedIn) return RepSessionAction.signInAnonymously;
  if (id.isAnonymous) return RepSessionAction.none;
  if (isStaffRole(id.role)) return RepSessionAction.none; // admin testing: keep
  return RepSessionAction.signOutThenAnonymous; // partner / other identity
}

/// True when an error is an auth/session problem worth one silent retry.
bool isRepSessionError(Object error) {
  final code = receiptErrorCode(error);
  return code == 'unauthenticated' || code == 'permission-denied';
}

/// Short raw error code to show (small) in the error dialog.
String repErrorCode(Object error) => receiptErrorCode(error);

/// True when the AI read no usable receipt number. Such receipts must not be
/// saved (they would all collide on `rcpt_{campaignId}_UNKNOWN`).
bool isUnusableReceiptNumber(String? receiptNumber) {
  final s = (receiptNumber ?? '').trim();
  if (s.isEmpty) return true;
  final u = s.toUpperCase();
  if (u == 'UNKNOWN' || u == 'N/A' || u == 'NULL' || u == 'NONE') return true;
  return !RegExp(r'[0-9A-Za-z\u0660-\u0669]').hasMatch(s);
}

const String kUnreadableReceiptNumberAr =
    'لم نتمكن من قراءة رقم الفاتورة. صوّر الفاتورة مرة أخرى بوضوح بحيث يظهر رقم الفاتورة كاملًا، ثم اضغط فحص مرة أخرى.';

/// Restores an anonymous session if needed and refreshes the ID token.
/// Returns true when the session was changed.
Future<bool> ensureRepAnonymousSession(FirebaseAuth auth, {bool forceRefresh = false}) async {
  final user = auth.currentUser;
  String? role;
  if (user != null && !user.isAnonymous) {
    try {
      role = (await user.getIdTokenResult()).claims?['role']?.toString();
    } catch (_) {}
  }
  final action = repSessionActionFor(RepIdentity(
    signedIn: user != null,
    isAnonymous: user?.isAnonymous ?? false,
    role: role,
  ));
  var changed = false;
  if (action == RepSessionAction.signOutThenAnonymous) {
    await auth.signOut();
  }
  if (action != RepSessionAction.none) {
    await auth.signInAnonymously();
    changed = true;
  }
  if (changed || forceRefresh) {
    try {
      await auth.currentUser?.getIdToken(true);
    } catch (_) {}
  }
  return changed;
}
