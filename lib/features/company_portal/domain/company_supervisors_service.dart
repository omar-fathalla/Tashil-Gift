import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/services/firebase_scope.dart';
import 'company_supervisor.dart';

/// Firestore access for the company-supervisors WhatsApp audience.
///
/// Document ids are the Western-digit mobile numbers, so a later import of the
/// same phone updates the existing record.
class CompanySupervisorsService {
  final FirebaseFirestore? _firestore;

  CompanySupervisorsService({FirebaseFirestore? firestore}) : _firestore = firestore;

  FirebaseFirestore get _db => _firestore ?? scopedFirestore();

  static const String collectionName = CompanySupervisor.collectionName;

  Stream<List<CompanySupervisor>> streamSupervisors() {
    return _db.collection(collectionName).snapshots().map((snapshot) {
      final parsed = snapshot.docs.map(CompanySupervisor.fromFirestore).toList();
      return CompanySupervisor.dedupeByMobile(parsed);
    });
  }

  /// Inserts or updates every supervisor. Missing phones are left in place
  /// unless [replaceMissing] is true.
  Future<int> upsertAll(
    List<CompanySupervisor> supervisors, {
    bool replaceMissing = false,
  }) async {
    if (supervisors.isEmpty && !replaceMissing) return 0;
    var saved = 0;
    const chunkSize = 400;
    for (var i = 0; i < supervisors.length; i += chunkSize) {
      final end = (i + chunkSize) > supervisors.length ? supervisors.length : i + chunkSize;
      final chunk = supervisors.sublist(i, end);
      final batch = _db.batch();
      for (final supervisor in chunk) {
        final ref = _db.collection(collectionName).doc(supervisor.mobile);
        batch.set(ref, supervisor.toMap(), SetOptions(merge: true));
      }
      await batch.commit();
      saved += chunk.length;
    }

    if (replaceMissing) {
      final keep = supervisors.map((supervisor) => supervisor.mobile).toSet();
      final existing = await _db.collection(collectionName).get();
      WriteBatch? batch;
      var pending = 0;
      for (final doc in existing.docs) {
        if (keep.contains(doc.id)) continue;
        batch ??= _db.batch();
        batch.delete(doc.reference);
        pending++;
        if (pending == chunkSize) {
          await batch.commit();
          batch = null;
          pending = 0;
        }
      }
      if (batch != null && pending > 0) {
        await batch.commit();
      }
    }
    return saved;
  }
}
