import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_service.dart';

/// Provider for [DistributedCounterService]
final distributedCounterServiceProvider = Provider<DistributedCounterService>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return DistributedCounterService(firestore);
});

/// High-throughput Distributed Sharded Counter Service for Google Cloud Firestore.
///
/// Solves single-document write lock contention (Firestore 1 write/sec limit)
/// by distributing increments across [defaultNumShards] random shard documents
/// located under `events/{eventId}/sharded_counters/{counterName}/shards/{shardId}`.
class DistributedCounterService {
  final FirebaseFirestore _firestore;
  static const int defaultNumShards = 10;
  final Random _random = Random();

  DistributedCounterService(this._firestore);

  /// Sanitizes key strings to be safe document IDs in Firestore
  static String sanitizeCounterKey(String raw) {
    if (raw.isEmpty) return 'general';
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\/\\#\?\[\]\s]+'), '_');
  }

  /// Increments a sharded counter for a specific campaign event atomically.
  /// Selects a random shard between 0 and [numShards - 1] to spread write load.
  Future<void> incrementCampaignCounter({
    required String eventId,
    required String counterName,
    int delta = 1,
    int numShards = defaultNumShards,
    Map<String, dynamic>? metadata,
  }) async {
    final cleanEventId = eventId.trim();
    final cleanCounter = sanitizeCounterKey(counterName);
    if (cleanEventId.isEmpty || cleanCounter.isEmpty || delta == 0) return;

    try {
      final shardId = _random.nextInt(numShards).toString();
      final shardRef = _firestore
          .collection('events')
          .doc(cleanEventId)
          .collection('sharded_counters')
          .doc(cleanCounter)
          .collection('shards')
          .doc(shardId);

      final Map<String, dynamic> data = {
        'count': FieldValue.increment(delta),
        'counterName': cleanCounter,
        'eventId': cleanEventId,
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      if (metadata != null && metadata.isNotEmpty) {
        data['metadata'] = metadata;
      }

      await shardRef.set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('⚠️ DistributedCounterService.incrementCampaignCounter error: $e');
    }
  }

  /// Records a high-throughput prize claim or game play event across distributed shards.
  /// Simultaneously increments total claims, game-type claims, prize-specific claims,
  /// and branch-specific claims without colliding on the main event document.
  Future<void> recordClaimEvent({
    required String eventId,
    required String prizeIdentifier,
    String? branchId,
    int count = 1,
    String gameType = 'scratch',
    String? transactionId,
  }) async {
    final cleanEventId = eventId.trim();
    if (cleanEventId.isEmpty || count <= 0) return;

    final List<Future<void>> futures = [];

    // 1. Overall campaign claims counter
    final meta = <String, dynamic>{'gameType': gameType};
    if (transactionId != null) meta['txId'] = transactionId;
    futures.add(incrementCampaignCounter(
      eventId: cleanEventId,
      counterName: 'claims_total',
      delta: count,
      metadata: meta,
    ));

    // 2. Per-game type counter (e.g. scratch, directGift, spinWheel)
    if (gameType.isNotEmpty) {
      futures.add(incrementCampaignCounter(
        eventId: cleanEventId,
        counterName: 'game_${sanitizeCounterKey(gameType)}_claims',
        delta: count,
      ));
    }

    // 3. Per-prize counter (e.g. prize_voucher_50)
    if (prizeIdentifier.isNotEmpty) {
      futures.add(incrementCampaignCounter(
        eventId: cleanEventId,
        counterName: 'prize_${sanitizeCounterKey(prizeIdentifier)}',
        delta: count,
      ));
    }

    // 4. Per-branch counter if branchId is specified
    if (branchId != null && branchId.trim().isNotEmpty) {
      futures.add(incrementCampaignCounter(
        eventId: cleanEventId,
        counterName: 'branch_${sanitizeCounterKey(branchId)}',
        delta: count,
      ));
    }

    await Future.wait(futures);
  }

  /// Real-time stream of the aggregated count across all shards of [counterName].
  Stream<int> watchCampaignCounter({
    required String eventId,
    required String counterName,
  }) {
    final cleanEventId = eventId.trim();
    final cleanCounter = sanitizeCounterKey(counterName);
    if (cleanEventId.isEmpty || cleanCounter.isEmpty) {
      return Stream.value(0);
    }

    return _firestore
        .collection('events')
        .doc(cleanEventId)
        .collection('sharded_counters')
        .doc(cleanCounter)
        .collection('shards')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.fold<int>(0, (total, doc) {
        final count = (doc.data()['count'] as num?)?.toInt() ?? 0;
        return total + count;
      });
    });
  }

  /// Asynchronously retrieves the total sum of all shards for [counterName].
  Future<int> getCampaignCounter({
    required String eventId,
    required String counterName,
    Source source = Source.serverAndCache,
  }) async {
    final cleanEventId = eventId.trim();
    final cleanCounter = sanitizeCounterKey(counterName);
    if (cleanEventId.isEmpty || cleanCounter.isEmpty) return 0;

    try {
      final snapshot = await _firestore
          .collection('events')
          .doc(cleanEventId)
          .collection('sharded_counters')
          .doc(cleanCounter)
          .collection('shards')
          .get(GetOptions(source: source));

      return snapshot.docs.fold<int>(0, (total, doc) {
        final count = (doc.data()['count'] as num?)?.toInt() ?? 0;
        return total + count;
      });
    } catch (e) {
      debugPrint('⚠️ DistributedCounterService.getCampaignCounter error: $e');
      return 0;
    }
  }

  /// Retrieves live claimed counts for a list of prizes across distributed shards.
  Future<Map<String, int>> getCampaignPrizesLiveClaims({
    required String eventId,
    required List<String> prizeIdentifiers,
  }) async {
    final cleanEventId = eventId.trim();
    final Map<String, int> results = {};
    if (cleanEventId.isEmpty || prizeIdentifiers.isEmpty) return results;

    final futures = prizeIdentifiers.map((prize) async {
      final key = 'prize_${sanitizeCounterKey(prize)}';
      final count = await getCampaignCounter(
        eventId: cleanEventId,
        counterName: key,
      );
      results[prize] = count;
    });

    await Future.wait(futures);
    return results;
  }

  /// Resets all shards for [counterName] to zero.
  Future<void> resetCounter({
    required String eventId,
    required String counterName,
    int numShards = defaultNumShards,
  }) async {
    final cleanEventId = eventId.trim();
    final cleanCounter = sanitizeCounterKey(counterName);
    if (cleanEventId.isEmpty || cleanCounter.isEmpty) return;

    final batch = _firestore.batch();
    for (int i = 0; i < numShards; i++) {
      final shardRef = _firestore
          .collection('events')
          .doc(cleanEventId)
          .collection('sharded_counters')
          .doc(cleanCounter)
          .collection('shards')
          .doc(i.toString());
      batch.set(shardRef, {
        'count': 0,
        'counterName': cleanCounter,
        'eventId': cleanEventId,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
