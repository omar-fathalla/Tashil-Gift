import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// TAG-43: drops every write this browser has queued but not sent
/// (Firestore keeps them in IndexedDB and resends them after a refresh).
/// Server data is not touched. The [firestore] instance is terminated and
/// cannot be used afterwards: reload the page.
///
/// Returns false when the local cache could not be cleared (usually another
/// tab of the app keeps it open).
Future<bool> clearPendingFirestoreWrites(FirebaseFirestore firestore) async {
  try {
    await firestore.terminate();
  } catch (e) {
    debugPrint('TAG-43 terminate failed: $e');
  }
  try {
    await firestore.clearPersistence();
    return true;
  } catch (e) {
    debugPrint('TAG-43 clearPersistence failed: $e');
    return false;
  }
}
