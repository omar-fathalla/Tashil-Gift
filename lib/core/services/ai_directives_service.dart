import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firebase_service.dart';
import '../../features/admin/domain/ai_directive_model.dart';
import '../../features/admin/domain/ai_directives_seed_data.dart';

final aiDirectivesServiceProvider = Provider<AiDirectivesService>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return AiDirectivesService(firestore);
});

final aiDirectivesStreamProvider = StreamProvider<List<AiDirectiveModel>>((ref) {
  final service = ref.watch(aiDirectivesServiceProvider);
  return service.streamDirectives();
});

class AiDirectivesService {
  final FirebaseFirestore _firestore;

  AiDirectivesService(this._firestore);

  /// Streams all directives in real-time from Firestore, or returns preloaded seed data
  Stream<List<AiDirectiveModel>> streamDirectives() {
    try {
      return _firestore
          .collection('ai_brain_directives')
          .orderBy('order_index', descending: false)
          .snapshots()
          .map((snapshot) {
        if (snapshot.docs.isEmpty) {
          return AiDirectivesSeedData.initialDirectives;
        }
        final list = snapshot.docs.map((doc) => AiDirectiveModel.fromMap(doc.data(), doc.id)).toList();
        list.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
        return list;
      }).handleError((error) {
        debugPrint('Error streaming ai_brain_directives: $error');
        return AiDirectivesSeedData.initialDirectives;
      });
    } catch (e) {
      debugPrint('Exception in streamDirectives: $e');
      return Stream.value(AiDirectivesSeedData.initialDirectives);
    }
  }

  /// Sync seed directives to Firestore if collection is empty or missing new directives (e.g. AIR-19, AIR-20)
  Future<void> seedDirectivesIfEmpty() async {
    try {
      final snapshot = await _firestore.collection('ai_brain_directives').get();
      final existingIds = snapshot.docs.map((d) => d.id).toSet();

      final missingDirectives = AiDirectivesSeedData.initialDirectives
          .where((d) => !existingIds.contains(d.id))
          .toList();

      if (missingDirectives.isNotEmpty) {
        final batch = _firestore.batch();
        for (final directive in missingDirectives) {
          final docRef = _firestore.collection('ai_brain_directives').doc(directive.id);
          batch.set(docRef, directive.toMap());
        }
        await batch.commit();
        debugPrint('Successfully synced ${missingDirectives.length} new AI Brain Directives into Firestore');
      }
    } catch (e) {
      debugPrint('Error seeding AI directives to Firestore: $e');
    }
  }

  /// Add a new learned directive
  Future<void> addDirective(AiDirectiveModel directive) async {
    try {
      await _firestore.collection('ai_brain_directives').doc(directive.id).set(directive.toMap());
    } catch (e) {
      debugPrint('Error adding directive: $e');
      rethrow;
    }
  }

  /// Update an existing directive
  Future<void> updateDirective(AiDirectiveModel directive) async {
    try {
      await _firestore.collection('ai_brain_directives').doc(directive.id).update(directive.toMap());
    } catch (e) {
      debugPrint('Error updating directive: $e');
      rethrow;
    }
  }

  /// Toggle active state of a directive
  Future<void> toggleDirectiveActive(String id, bool currentStatus) async {
    try {
      await _firestore.collection('ai_brain_directives').doc(id).update({
        'is_globally_active': !currentStatus,
      });
    } catch (e) {
      debugPrint('Error toggling directive status: $e');
      rethrow;
    }
  }

  /// Delete a directive
  Future<void> deleteDirective(String id) async {
    try {
      await _firestore.collection('ai_brain_directives').doc(id).delete();
    } catch (e) {
      debugPrint('Error deleting directive: $e');
      rethrow;
    }
  }
}
