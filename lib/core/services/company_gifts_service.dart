import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'claim_callable_fallback.dart';
import 'firebase_emulator_config.dart';
import 'firebase_service.dart';
import 'distributed_counter_service.dart';
import '../../features/admin/domain/company_gift_model.dart';
import '../../features/admin/domain/event_model.dart';
import 'firebase_scope.dart';

final companyGiftsServiceProvider = Provider<CompanyGiftsService>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final counterService = ref.watch(distributedCounterServiceProvider);
  return CompanyGiftsService(firestore, counterService: counterService);
});

class CompanyGiftsService {
  final FirebaseFirestore _firestore;
  final DistributedCounterService? _counterService;

  CompanyGiftsService(this._firestore, {DistributedCounterService? counterService})
      : _counterService = counterService ?? DistributedCounterService(_firestore);

  /// Returns a real-time stream of all gifts for a specific company.
  Stream<List<CompanyGiftModel>> giftsStream(String companySlug) {
    return _firestore
        .collection('company_gifts')
        .where('companySlug', isEqualTo: companySlug.toLowerCase())
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => CompanyGiftModel.fromFirestore(d)).toList());
  }

  /// Returns all gifts for a company with dynamic calculation of allocations
  /// across other active campaigns.
  /// [excludeEventId] allows excluding the current event being edited so its
  /// previous allocations are not counted as "other campaigns".
  Future<List<CompanyGiftModel>> getGiftsForCompany(
    String companySlug, {
    String? excludeEventId,
  }) async {
    final slug = companySlug.toLowerCase().trim();
    if (slug.isEmpty) return [];

    // 1. Fetch master gift records
    final giftsSnap = await _firestore
        .collection('company_gifts')
        .where('companySlug', isEqualTo: slug)
        .get();

    final gifts = giftsSnap.docs.map((d) => CompanyGiftModel.fromFirestore(d)).toList();
    if (gifts.isEmpty) return [];

    // 2. Fetch all active campaigns for this company to calculate active reservations
    final eventsSnap = await _firestore
        .collection('events')
        .where('companySlug', isEqualTo: slug)
        .where('isActive', isEqualTo: true)
        .get();

    final Map<String, int> allocatedInOtherCampaignsMap = {};

    for (final eventDoc in eventsSnap.docs) {
      if (excludeEventId != null && eventDoc.id == excludeEventId) {
        continue;
      }
      final data = eventDoc.data();
      final prizes = (data['allocatedPrizes'] as List<dynamic>?) ?? [];
      for (final p in prizes) {
        if (p is Map<String, dynamic>) {
          final giftId = p['giftId'] as String? ?? '';
          final giftName = (p['name'] as String? ?? '').trim();
          final allocatedQty = (p['allocatedQuantity'] as num?)?.toInt() ?? 0;
          
          if (giftId.isNotEmpty) {
            allocatedInOtherCampaignsMap[giftId] =
                (allocatedInOtherCampaignsMap[giftId] ?? 0) + allocatedQty;
          }
          if (giftName.isNotEmpty) {
            allocatedInOtherCampaignsMap[giftName] =
                (allocatedInOtherCampaignsMap[giftName] ?? 0) + allocatedQty;
          }
        }
      }
    }

    // 3. Return enriched gifts with true available quantities
    return gifts.map((g) {
      final allocatedOthers = allocatedInOtherCampaignsMap[g.id] ??
          allocatedInOtherCampaignsMap[g.giftName] ??
          0;
      final trueAvailable = (g.totalQuantity - allocatedOthers).clamp(0, g.totalQuantity);
      return g.copyWith(
        availableQuantity: trueAvailable,
        allocatedInOtherCampaigns: allocatedOthers,
      );
    }).toList();
  }

  /// Synchronizes `availableQuantity` field in Firestore for all `company_gifts` docs
  /// based on total allocations in active campaigns.
  Future<void> syncCompanyGiftsAvailableQuantities(String companySlug) async {
    final slug = companySlug.toLowerCase().trim();
    if (slug.isEmpty) return;

    try {
      final gifts = await getGiftsForCompany(slug);
      final batch = _firestore.batch();
      for (final gift in gifts) {
        final docRef = _firestore.collection('company_gifts').doc(gift.id);
        batch.update(docRef, {
          'availableQuantity': gift.availableQuantity,
        });
      }
      await batch.commit();
    } catch (_) {
      // Best-effort sync to keep Firestore persistent fields aligned
    }
  }

  /// Retrieves campaign usage details for a given gift.
  Future<List<Map<String, dynamic>>> getGiftCampaignUsage(String giftId, String companySlug) async {
    final slug = companySlug.toLowerCase().trim();
    if (slug.isEmpty) return [];

    final eventsSnap = await _firestore
        .collection('events')
        .where('companySlug', isEqualTo: slug)
        .get();

    final List<Map<String, dynamic>> usage = [];
    for (final doc in eventsSnap.docs) {
      final data = doc.data();
      final eventName = data['eventName'] as String? ?? 'حملة بدون اسم';
      final isActive = data['isActive'] as bool? ?? true;
      final prizes = (data['allocatedPrizes'] as List<dynamic>?) ?? [];
      int eventAllocated = 0;
      int eventRemaining = 0;

      for (final p in prizes) {
        if (p is Map<String, dynamic>) {
          if (p['giftId'] == giftId || p['name'] == giftId) {
            eventAllocated += (p['allocatedQuantity'] as num?)?.toInt() ?? 0;
            eventRemaining += (p['remainingQuantity'] as num?)?.toInt() ?? 0;
          }
        }
      }

      if (eventAllocated > 0) {
        usage.add({
          'eventId': doc.id,
          'eventName': eventName,
          'isActive': isActive,
          'allocatedQuantity': eventAllocated,
          'remainingQuantity': eventRemaining,
        });
      }
    }
    return usage;
  }

  /// Stream of all stock movements and audit logs for a company (or a specific gift).
  Stream<List<GiftStockMovement>> stockMovementsStream(String companySlug, {String? giftId}) {
    final slug = companySlug.toLowerCase().trim();
    if (slug.isEmpty) return Stream.value([]);

    Query query = _firestore
        .collection('gift_stock_movements')
        .where('companySlug', isEqualTo: slug);

    if (giftId != null && giftId.isNotEmpty) {
      query = query.where('giftId', isEqualTo: giftId);
    }

    return query.snapshots().map((snap) {
      final list = snap.docs.map((d) => GiftStockMovement.fromFirestore(d)).toList();
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return list;
    });
  }

  /// Adds a new supply batch to an existing gift in the master inventory.
  /// Automatically updates totalQuantity, availableQuantity, and logs to `gift_stock_movements`.
  Future<void> addSupplyBatch({
    required String giftId,
    required int quantity,
    required DateTime supplyDate,
    String referenceNumber = '',
    String notes = '',
    String addedBy = 'مسؤول النظام',
  }) async {
    if (quantity <= 0) return;

    final docRef = _firestore.collection('company_gifts').doc(giftId);
    final docSnap = await docRef.get();
    if (!docSnap.exists) return;

    final gift = CompanyGiftModel.fromFirestore(docSnap);
    final previousTotal = gift.totalQuantity;
    final previousAvailable = gift.availableQuantity;
    final newTotal = previousTotal + quantity;
    final newAvailable = previousAvailable + quantity;

    final nextBatchNum = gift.batches.length + 1;
    final newBatch = GiftSupplyBatch(
      id: 'batch_${DateTime.now().millisecondsSinceEpoch}',
      batchNumber: nextBatchNum,
      quantity: quantity,
      supplyDate: supplyDate,
      referenceNumber: referenceNumber.trim(),
      notes: notes.trim(),
      addedBy: addedBy.trim(),
    );

    final updatedBatches = List<GiftSupplyBatch>.from(gift.batches)..add(newBatch);

    final batch = _firestore.batch();
    batch.update(docRef, {
      'totalQuantity': newTotal,
      'availableQuantity': newAvailable,
      'batches': updatedBatches.map((b) => b.toMap()).toList(),
    });

    // Add movement audit record
    final movementRef = _firestore.collection('gift_stock_movements').doc();
    final movement = GiftStockMovement(
      id: movementRef.id,
      companySlug: gift.companySlug,
      giftId: gift.id,
      giftName: gift.giftName,
      movementType: 'supply_batch',
      quantityChange: quantity,
      previousTotal: previousTotal,
      newTotal: newTotal,
      previousAvailable: previousAvailable,
      newAvailable: newAvailable,
      reference: referenceNumber.trim().isNotEmpty ? referenceNumber.trim() : 'إذن توريد دفعة رقم $nextBatchNum',
      notes: notes.trim(),
      performedBy: addedBy.trim().isNotEmpty ? addedBy.trim() : 'مسؤول النظام',
      timestamp: supplyDate,
    );
    batch.set(movementRef, movement.toFirestore());

    await batch.commit();
  }

  /// Adjusts the stock of a gift (either increase or decrease) with a formal audit reason.
  Future<void> adjustStock({
    required String giftId,
    required bool isIncrease,
    required int quantity,
    required String reason,
    String notes = '',
    String performedBy = 'مسؤول النظام',
  }) async {
    if (quantity <= 0) return;

    final docRef = _firestore.collection('company_gifts').doc(giftId);
    final docSnap = await docRef.get();
    if (!docSnap.exists) return;

    final gift = CompanyGiftModel.fromFirestore(docSnap);
    final previousTotal = gift.totalQuantity;
    final previousAvailable = gift.availableQuantity;

    final qtyChange = isIncrease ? quantity : -quantity;
    final newTotal = (previousTotal + qtyChange).clamp(0, 9999999);
    final newAvailable = (previousAvailable + qtyChange).clamp(0, newTotal);

    final batch = _firestore.batch();
    batch.update(docRef, {
      'totalQuantity': newTotal,
      'availableQuantity': newAvailable,
    });

    // Add movement audit record
    final movementRef = _firestore.collection('gift_stock_movements').doc();
    final movement = GiftStockMovement(
      id: movementRef.id,
      companySlug: gift.companySlug,
      giftId: gift.id,
      giftName: gift.giftName,
      movementType: isIncrease ? 'adjustment_add' : 'adjustment_deduct',
      quantityChange: qtyChange,
      previousTotal: previousTotal,
      newTotal: newTotal,
      previousAvailable: previousAvailable,
      newAvailable: newAvailable,
      reference: reason.trim(),
      notes: notes.trim(),
      performedBy: performedBy.trim().isNotEmpty ? performedBy.trim() : 'مسؤول النظام',
      timestamp: DateTime.now(),
    );
    batch.set(movementRef, movement.toFirestore());

    await batch.commit();
  }

  /// Returns unused remaining prizes from a campaign back to the company master warehouse.
  Future<void> returnUnusedCampaignStock({
    required String eventId,
    required String giftId,
    required int returnQty,
    String eventName = '',
    String performedBy = 'مسؤول النظام',
  }) async {
    if (returnQty <= 0) return;

    final docRef = _firestore.collection('company_gifts').doc(giftId);
    final docSnap = await docRef.get();
    if (!docSnap.exists) return;

    final gift = CompanyGiftModel.fromFirestore(docSnap);
    final previousTotal = gift.totalQuantity;
    final previousAvailable = gift.availableQuantity;
    final newAvailable = (previousAvailable + returnQty).clamp(0, gift.totalQuantity);

    final batch = _firestore.batch();
    batch.update(docRef, {
      'availableQuantity': newAvailable,
    });

    final movementRef = _firestore.collection('gift_stock_movements').doc();
    final movement = GiftStockMovement(
      id: movementRef.id,
      companySlug: gift.companySlug,
      giftId: gift.id,
      giftName: gift.giftName,
      movementType: 'campaign_return',
      quantityChange: returnQty,
      previousTotal: previousTotal,
      newTotal: previousTotal,
      previousAvailable: previousAvailable,
      newAvailable: newAvailable,
      reference: eventName.isNotEmpty ? 'استرجاع من حملة: $eventName' : 'استرجاع فائض حملة',
      notes: 'إرجاع $returnQty قطعة غير مستهلكة إلى الرصيد المتاح للشركة',
      performedBy: performedBy,
      timestamp: DateTime.now(),
    );
    batch.set(movementRef, movement.toFirestore());

    await batch.commit();
  }

  /// Updates or supplies prize allocation for a specific branch in a campaign event.
  /// Enforces validation that new allocation cannot be less than already claimed/awarded prizes.
  /// Automatically updates event's allocatedPrizes, logs a GiftStockMovement audit entry,
  /// and synchronizes the company's master available inventory.
  Future<void> updateBranchPrizeAllocation({
    required String companySlug,
    required String eventId,
    required String branchName,
    String branchId = '',
    required String giftKey,
    required int newAllocatedQuantity,
    String notes = '',
    String performedBy = 'مدير الشركة',
  }) async {
    final slug = companySlug.toLowerCase().trim();
    if (eventId.isEmpty) return;

    final eventRef = _firestore.collection('events').doc(eventId);
    final eventSnap = await eventRef.get();
    if (!eventSnap.exists) {
      throw Exception('Campaign event not found: $eventId');
    }

    final eventData = eventSnap.data() ?? {};
    final eventName = eventData['eventName'] as String? ?? 'حملة ترويجية';
    final rawPrizes = (eventData['allocatedPrizes'] as List<dynamic>?) ?? [];

    List<AllocatedPrize> prizes = rawPrizes
        .map((p) => AllocatedPrize.fromMap(Map<String, dynamic>.from(p as Map)))
        .toList();

    final targetBranchNorm = branchName.trim().toLowerCase();
    final targetBranchIdNorm = branchId.trim().toLowerCase();
    final targetGiftKeyNorm = giftKey.trim().toLowerCase();

    // Also find master gift record for audit/details if available
    CompanyGiftModel? masterGift;
    try {
      final gifts = await getGiftsForCompany(slug);
      masterGift = gifts.where(
        (g) => g.id.toLowerCase() == targetGiftKeyNorm || g.giftName.trim().toLowerCase() == targetGiftKeyNorm,
      ).firstOrNull;
    } catch (_) {}

    int matchedIndex = -1;
    for (int i = 0; i < prizes.length; i++) {
      final p = prizes[i];
      final pBranchNorm = p.branchName.trim().toLowerCase();
      final pBranchIdNorm = p.branchId.trim().toLowerCase();
      final pGiftIdNorm = p.giftId.trim().toLowerCase();
      final pNameNorm = p.name.trim().toLowerCase();

      final branchMatches = (targetBranchIdNorm.isNotEmpty && pBranchIdNorm == targetBranchIdNorm) ||
          (pBranchNorm == targetBranchNorm);
      final giftMatches = pGiftIdNorm == targetGiftKeyNorm ||
          pNameNorm == targetGiftKeyNorm ||
          (masterGift != null && (pGiftIdNorm == masterGift.id.toLowerCase() || pNameNorm == masterGift.giftName.trim().toLowerCase()));

      if (branchMatches && giftMatches) {
        matchedIndex = i;
        break;
      }
    }

    int oldAllocated = 0;
    int oldRemaining = 0;
    String finalGiftId = masterGift?.id ?? giftKey;
    String finalGiftName = masterGift?.giftName ?? giftKey;
    String finalGiftType = masterGift?.giftType ?? 'product';
    double finalUnitValue = masterGift?.unitValue ?? 0.0;

    if (matchedIndex != -1) {
      final p = prizes[matchedIndex];
      oldAllocated = p.allocatedQuantity;
      oldRemaining = p.remainingQuantity;
      finalGiftId = p.giftId.isNotEmpty ? p.giftId : finalGiftId;
      finalGiftName = p.name.isNotEmpty ? p.name : finalGiftName;
      finalGiftType = p.giftType;
      finalUnitValue = p.unitValue;
    }

    if (newAllocatedQuantity < 0) {
      throw Exception('لا يمكن أن تكون حصة التخصيص سالبة');
    }

    final delta = newAllocatedQuantity - oldAllocated;
    final newRemaining = (oldRemaining + delta).clamp(0, newAllocatedQuantity);

    final updatedPrize = AllocatedPrize(
      giftId: finalGiftId,
      name: finalGiftName,
      allocatedQuantity: newAllocatedQuantity,
      remainingQuantity: newRemaining,
      branchId: branchId.isNotEmpty ? branchId : (matchedIndex != -1 ? prizes[matchedIndex].branchId : ''),
      branchName: branchName.isNotEmpty ? branchName : (matchedIndex != -1 ? prizes[matchedIndex].branchName : ''),
      giftType: finalGiftType,
      unitValue: finalUnitValue,
    );

    if (matchedIndex != -1) {
      prizes[matchedIndex] = updatedPrize;
    } else {
      prizes.add(updatedPrize);
    }

    final batch = _firestore.batch();
    batch.update(eventRef, {
      'allocatedPrizes': prizes.map((p) => p.toMap()).toList(),
    });

    // Write movement audit if there is a non-zero quantity change
    if (delta != 0) {
      final movementRef = _firestore.collection('gift_stock_movements').doc();
      final isIncrease = delta > 0;
      final movement = GiftStockMovement(
        id: movementRef.id,
        companySlug: slug,
        giftId: finalGiftId,
        giftName: finalGiftName,
        movementType: isIncrease ? 'branch_allocation_increase' : 'branch_allocation_decrease',
        quantityChange: delta,
        previousTotal: oldAllocated,
        newTotal: newAllocatedQuantity,
        previousAvailable: oldRemaining,
        newAvailable: newRemaining,
        reference: 'تعديل حصة $branchName في $eventName',
        notes: notes.trim().isNotEmpty
            ? notes.trim()
            : (isIncrease
                ? 'تزويد إضافي (+ $delta) لـ $branchName (المخصص: $newAllocatedQuantity، المتبقي: $newRemaining)'
                : 'تخفيض حصة ($delta) لـ $branchName (المخصص: $newAllocatedQuantity، المتبقي: $newRemaining)'),
        performedBy: performedBy.trim().isNotEmpty ? performedBy.trim() : 'مدير الشركة',
        timestamp: DateTime.now(),
      );
      batch.set(movementRef, movement.toFirestore());
    }

    await batch.commit();

    // Synchronize company available quantities
    await syncCompanyGiftsAvailableQuantities(slug);
  }

  /// Canonical Arabic-safe branch token normalizer (AIR-80 & Rule 8).
  /// Strips parenthetical governorates (e.g. "(الإسكندرية)", "(القاهرة)"), retail chain prefixes,
  /// and "فرع", while preserving all Arabic characters without destructive ASCII regexes.
  static String normalizeBranchToken(String raw) {
    var s = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي');
    // Strip parenthetical governorates and bracketed metadata first
    s = s.replaceAll(RegExp(r'\s*\([^)]*\)|\s*\[[^\]]*\]'), ' ');
    // Strip multi-word retail chain names
    for (final phrase in const [
      'اسواق فتح الله للجمله',
      'اسواق فتح الله',
      'فتح الله للجمله',
      'فتح الله',
      'جمله ماركت',
      'بيت الجمله',
      'خير زمان',
      'هايبر وان',
      'سوبر ماركت',
      'fatha..a',
      'fathalla',
    ]) {
      s = s.replaceAll(phrase, ' ');
    }
    s = s.replaceAll(RegExp(r'[^\w\s\d\u0600-\u06FF]'), ' ');
    const stopWords = {
      'اسواق',
      'سوق',
      'فتح',
      'الله',
      'للجمله',
      'كارفور',
      'سبينس',
      'زهران',
      'كازيون',
      'بيم',
      'هايبر',
      'سوبر',
      'ماركت',
      'سلسله',
      'فرع',
      'مفرع',
      'fathalla',
      'fatha',
      'gomla',
      'carrefour',
      'spinneys',
      'store',
      'branch',
      'pos',
    };
    final tokens = s
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty && !stopWords.contains(t))
        .toList();
    return tokens.join(' ').trim();
  }

  /// Helper to match branch names with fuzzy normalization (stripping city parentheticals and "فرع")
  static bool matchesBranchName(String b1, String b2) {
    final t1 = b1.trim().toLowerCase();
    final t2 = b2.trim().toLowerCase();
    if (t1.isEmpty || t2.isEmpty) return false;
    if (t1 == t2) return true;
    final c1 = normalizeBranchToken(b1);
    final c2 = normalizeBranchToken(b2);
    if (c1.isEmpty || c2.isEmpty) return false;
    return c1 == c2 || (c1.length >= 3 && c2.contains(c1)) || (c2.length >= 3 && c1.contains(c2));
  }

  /// High-performance bulk synchronization for multiple branch prize allocations across campaigns.
  /// Executes atomically with single read & batch write operations in < 500ms.
  Future<int> bulkUpdateBranchPrizeAllocations({
    required String companySlug,
    required List<EventModel> events,
    required List<CompanyGiftModel> masterGifts,
    required Map<String, int> cellAllocations,
    required Map<String, int> claimedCache,
    List<String> branches = const [],
    String notes = '',
    String performedBy = 'مدير الشركة',
  }) async {
    final slug = companySlug.toLowerCase().trim();
    if (slug.isEmpty || events.isEmpty) return 0;

    int totalUpdated = 0;
    // Writes go through the updateBranchAllocations callable (Admin SDK):
    // company users cannot write events / gift_stock_movements directly.
    final eventPayloads = <Map<String, dynamic>>[];
    final movementPayloads = <Map<String, dynamic>>[];

    for (final event in events) {
      final eventRef = _firestore.collection('events').doc(event.id);
      final eventSnap = await eventRef.get();
      if (!eventSnap.exists) continue;

      final eventData = eventSnap.data() ?? {};
      final eventName = eventData['eventName'] as String? ?? event.eventName;
      final rawPrizes = (eventData['allocatedPrizes'] as List<dynamic>?) ?? [];

      List<AllocatedPrize> prizes = rawPrizes
          .map((p) => AllocatedPrize.fromMap(Map<String, dynamic>.from(p as Map)))
          .toList();

      bool eventModified = false;

      // Resiliently gather all target branch names across all sources
      final Set<String> targetBranches = {};
      targetBranches.addAll(branches.map((b) => b.trim()).where((b) => b.isNotEmpty));
      targetBranches.addAll(event.branchNames.map((b) => b.trim()).where((b) => b.isNotEmpty));
      for (final p in prizes) {
        if (p.branchName.trim().isNotEmpty) targetBranches.add(p.branchName.trim());
      }
      for (final key in cellAllocations.keys) {
        if (key.startsWith('${event.id}_')) {
          final rest = key.substring('${event.id}_'.length);
          final lastUnderscore = rest.lastIndexOf('_');
          if (lastUnderscore > 0) {
            final bName = rest.substring(0, lastUnderscore).trim();
            if (bName.isNotEmpty) targetBranches.add(bName);
          }
        }
      }
      if (targetBranches.isEmpty) {
        targetBranches.add('الفرع الرئيسي');
      }

      for (final gift in masterGifts) {
        final giftKey = gift.id.isNotEmpty ? gift.id : gift.giftName;
        final targetGiftKeyNorm = giftKey.trim().toLowerCase();

        for (final branchName in targetBranches) {
          final cellKey = '${event.id}_${branchName}_$giftKey';
          int? newAllocatedQuantity = cellAllocations[cellKey];
          if (newAllocatedQuantity == null) {
            final altKey = '${event.id}_${branchName}_${gift.giftName}';
            newAllocatedQuantity = cellAllocations[altKey];
            if (newAllocatedQuantity == null && gift.id.isNotEmpty) {
              final altKey2 = '${event.id}_${branchName}_${gift.id}';
              newAllocatedQuantity = cellAllocations[altKey2];
            }
          }

          if (newAllocatedQuantity == null) continue;

          final claimed = claimedCache[cellKey] ?? claimedCache['${event.id}_${branchName}_${gift.giftName}'] ?? 0;

          final targetBranchNorm = branchName.trim().toLowerCase();

          // Find existing prize in event
          int matchedIndex = -1;
          for (int i = 0; i < prizes.length; i++) {
            final p = prizes[i];
            final pBranchNorm = p.branchName.trim().toLowerCase();
            final pGiftIdNorm = p.giftId.trim().toLowerCase();
            final pNameNorm = p.name.trim().toLowerCase();

            final branchMatches = pBranchNorm == targetBranchNorm || matchesBranchName(p.branchName, branchName);
            final giftMatches = pGiftIdNorm == targetGiftKeyNorm ||
                pNameNorm == targetGiftKeyNorm ||
                pGiftIdNorm == gift.id.toLowerCase() ||
                pNameNorm == gift.giftName.trim().toLowerCase();

            if (branchMatches && giftMatches) {
              matchedIndex = i;
              break;
            }
          }

          if (newAllocatedQuantity == 0 && matchedIndex == -1) {
            // Do not pollute campaign with empty unallocated branch prize entries
            continue;
          }

          int oldAllocated = 0;
          int oldRemaining = 0;
          String finalGiftId = gift.id.isNotEmpty ? gift.id : giftKey;
          String finalGiftName = gift.giftName.isNotEmpty ? gift.giftName : giftKey;
          String finalGiftType = gift.giftType;
          double finalUnitValue = gift.unitValue;

          if (matchedIndex != -1) {
            final p = prizes[matchedIndex];
            oldAllocated = p.allocatedQuantity;
            oldRemaining = p.remainingQuantity;
            finalGiftId = p.giftId.isNotEmpty ? p.giftId : finalGiftId;
            finalGiftName = p.name.isNotEmpty ? p.name : finalGiftName;
            finalGiftType = p.giftType;
            finalUnitValue = p.unitValue;
          }

          if (oldAllocated == newAllocatedQuantity && matchedIndex != -1) {
            // No change needed
            continue;
          }

          // Only rows the user changed are checked; untouched rows with old
          // inconsistent data must not block saving the others.
          if (newAllocatedQuantity < claimed) {
            throw Exception('لا يمكن تعيين رصيد فرع ($branchName) لصنف (${gift.giftName}) أقل من المنصرف ($claimed قطعة)');
          }

          final delta = newAllocatedQuantity - oldAllocated;
          final newRemaining = (oldRemaining + delta).clamp(0, newAllocatedQuantity);

          String resolvedBranchId = matchedIndex != -1 ? prizes[matchedIndex].branchId : '';
          if (resolvedBranchId.isEmpty && event.branchNames.isNotEmpty) {
            for (int i = 0; i < event.branchNames.length; i++) {
              if (matchesBranchName(event.branchNames[i], branchName)) {
                if (i < event.branchIds.length) {
                  resolvedBranchId = event.branchIds[i];
                  break;
                }
              }
            }
          }

          final updatedPrize = AllocatedPrize(
            giftId: finalGiftId,
            name: finalGiftName,
            allocatedQuantity: newAllocatedQuantity,
            remainingQuantity: newRemaining,
            branchId: resolvedBranchId,
            branchName: branchName,
            giftType: finalGiftType,
            unitValue: finalUnitValue,
          );

          if (matchedIndex != -1) {
            prizes[matchedIndex] = updatedPrize;
          } else {
            prizes.add(updatedPrize);
          }

          eventModified = true;
          totalUpdated++;

          if (delta != 0) {
            final isIncrease = delta > 0;
            final movement = GiftStockMovement(
              id: '',
              companySlug: slug,
              giftId: finalGiftId,
              giftName: finalGiftName,
              movementType: isIncrease ? 'branch_allocation_increase' : 'branch_allocation_decrease',
              quantityChange: delta,
              previousTotal: oldAllocated,
              newTotal: newAllocatedQuantity,
              previousAvailable: oldRemaining,
              newAvailable: newRemaining,
              reference: 'تعديل حصة $branchName في $eventName',
              notes: notes.trim().isNotEmpty
                  ? notes.trim()
                  : (isIncrease
                      ? 'تزويد إضافي (+ $delta) لـ $branchName (المخصص: $newAllocatedQuantity، المتبقي: $newRemaining)'
                      : 'تخفيض حصة ($delta) لـ $branchName (المخصص: $newAllocatedQuantity، المتبقي: $newRemaining)'),
              performedBy: performedBy.trim().isNotEmpty ? performedBy.trim() : 'مدير الشركة',
              timestamp: DateTime.now(),
            );
            movementPayloads.add(Map<String, dynamic>.from(movement.toFirestore())..remove('timestamp'));
          }
        }

        // If active branch-specific allocations exist for this gift, clean up unbranched ghost prizes
        // to prevent phantom quotas and total discrepancies.
        final hasActiveBranchAllocations = prizes.any((bp) =>
            (bp.branchName.trim().isNotEmpty || bp.branchId.trim().isNotEmpty) &&
            (bp.giftId.trim().toLowerCase() == targetGiftKeyNorm ||
                bp.name.trim().toLowerCase() == targetGiftKeyNorm ||
                bp.giftId.trim().toLowerCase() == gift.id.toLowerCase() ||
                bp.name.trim().toLowerCase() == gift.giftName.trim().toLowerCase()));

        if (hasActiveBranchAllocations) {
          final beforeLen = prizes.length;
          prizes.removeWhere((p) =>
              p.branchName.trim().isEmpty &&
              p.branchId.trim().isEmpty &&
              (p.giftId.trim().toLowerCase() == targetGiftKeyNorm ||
                  p.name.trim().toLowerCase() == targetGiftKeyNorm ||
                  p.giftId.trim().toLowerCase() == gift.id.toLowerCase() ||
                  p.name.trim().toLowerCase() == gift.giftName.trim().toLowerCase()));
          if (prizes.length != beforeLen) {
            eventModified = true;
          }
        } else {
          // If no branch-specific allocations exist, maintain general pool remaining
          for (int i = 0; i < prizes.length; i++) {
            final p = prizes[i];
            if (p.branchName.trim().isEmpty && p.branchId.trim().isEmpty) {
              final pGiftIdNorm = p.giftId.trim().toLowerCase();
              final pNameNorm = p.name.trim().toLowerCase();
              if (pGiftIdNorm == targetGiftKeyNorm ||
                  pNameNorm == targetGiftKeyNorm ||
                  pGiftIdNorm == gift.id.toLowerCase() ||
                  pNameNorm == gift.giftName.trim().toLowerCase()) {
                final totalBranchRemaining = prizes
                    .where((bp) =>
                        bp.branchName.trim().isNotEmpty &&
                        (bp.giftId.trim().toLowerCase() == targetGiftKeyNorm ||
                            bp.name.trim().toLowerCase() == pNameNorm ||
                            bp.giftId.trim().toLowerCase() == gift.id.toLowerCase() ||
                            bp.name.trim().toLowerCase() == gift.giftName.trim().toLowerCase()))
                    .fold<int>(0, (acc, bp) => acc + bp.remainingQuantity);
                if (totalBranchRemaining > 0 && p.remainingQuantity < totalBranchRemaining) {
                  prizes[i] = p.copyWith(remainingQuantity: totalBranchRemaining);
                  eventModified = true;
                }
              }
            }
          }
        }
      }

      if (eventModified) {
        final updatedBranches = <String>{};
        updatedBranches.addAll(event.branchNames);
        for (final b in targetBranches) {
          if (b != 'كافة الفروع / عام' && b != 'All Branches' && b != 'الفرع الرئيسي') {
            updatedBranches.add(b);
          }
        }
        eventPayloads.add({
          'eventId': event.id,
          'allocatedPrizes': prizes.map((p) => p.toMap()).toList(),
          if (updatedBranches.isNotEmpty) 'branchNames': updatedBranches.toList(),
        });
      }
    }

    if (totalUpdated > 0 && eventPayloads.isNotEmpty) {
      await _callUpdateBranchAllocations({
        'action': 'bulk',
        'companySlug': slug,
        'events': eventPayloads,
        'movements': movementPayloads,
      });
    }

    return totalUpdated;
  }

  /// Adds a new gift to a company's master inventory with initial batch creation.
  Future<void> addGift({
    required String companySlug,
    required String companyName,
    required String giftName,
    required int quantity,
    String giftType = 'product',
    double unitValue = 0.0,
    String? imageUrl,
    String referenceNumber = '',
    String notes = '',
    String addedBy = 'مسؤول النظام',
  }) async {
    if (quantity < 0) {
      throw Exception('الكمية لا يمكن أن تكون سالبة');
    }

    final docRef = _firestore.collection('company_gifts').doc();
    final now = DateTime.now();

    final List<Map<String, dynamic>> batchesList = [];
    if (quantity > 0) {
      final initialBatch = GiftSupplyBatch(
        id: 'batch_${now.millisecondsSinceEpoch}',
        batchNumber: 1,
        quantity: quantity,
        supplyDate: now,
        referenceNumber: referenceNumber.trim().isNotEmpty ? referenceNumber.trim() : 'الرصيد الافتتاحي (دفعة 1)',
        notes: notes.trim().isNotEmpty ? notes.trim() : 'دفعة التوريد الافتتاحية الأولى',
        addedBy: addedBy.trim(),
      );
      batchesList.add(initialBatch.toMap());
    }

    final batch = _firestore.batch();
    batch.set(docRef, {
      'id': docRef.id,
      'companySlug': companySlug.toLowerCase().trim(),
      'companyName': companyName,
      'giftName': giftName.trim(),
      'name': giftName.trim(),
      'totalQuantity': quantity,
      'availableQuantity': quantity,
      'giftType': giftType,
      'unitValue': unitValue,
      if (imageUrl != null && imageUrl.trim().isNotEmpty) 'imageUrl': imageUrl.trim(),
      'orderIndex': now.millisecondsSinceEpoch ~/ 1000,
      'batches': batchesList,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final movementRef = _firestore.collection('gift_stock_movements').doc();
    final movement = GiftStockMovement(
      id: movementRef.id,
      companySlug: companySlug.toLowerCase().trim(),
      giftId: docRef.id,
      giftName: giftName.trim(),
      movementType: quantity > 0 ? 'supply_batch' : 'gift_registered_zero_stock',
      quantityChange: quantity,
      previousTotal: 0,
      newTotal: quantity,
      previousAvailable: 0,
      newAvailable: quantity,
      reference: referenceNumber.trim().isNotEmpty ? referenceNumber.trim() : (quantity > 0 ? 'الرصيد الافتتاحي (دفعة 1)' : 'تكويد صنف جديد'),
      notes: notes.trim().isNotEmpty ? notes.trim() : (quantity > 0 ? 'تكويد وتوريد أولي للهدية' : 'تكويد الصنف في مخزون الشركة برصيد افتتاحي 0'),
      performedBy: addedBy,
      timestamp: now,
    );
    batch.set(movementRef, movement.toFirestore());

    await batch.commit();
  }

  /// Updates gift master details (name, voucher value, image) in the company's master catalog.
  Future<void> updateGiftDetails({
    required String giftId,
    String? giftName,
    double? unitValue,
    String? imageUrl,
    bool removeImage = false,
  }) async {
    final docRef = _firestore.collection('company_gifts').doc(giftId);
    final Map<String, dynamic> updates = {};
    if (giftName != null && giftName.trim().isNotEmpty) {
      updates['giftName'] = giftName.trim();
      updates['name'] = giftName.trim();
    }
    if (unitValue != null) {
      updates['unitValue'] = unitValue;
    }
    if (removeImage) {
      updates['imageUrl'] = FieldValue.delete();
    } else if (imageUrl != null && imageUrl.trim().isNotEmpty) {
      updates['imageUrl'] = imageUrl.trim();
    }
    if (updates.isNotEmpty) {
      await docRef.update(updates);
    }

    // Cascade update to company campaigns (allocatedPrizes & promotionalRules)
    try {
      final giftDoc = await docRef.get();
      final slug = (giftDoc.data()?['companySlug'] ?? '').toString().trim().toLowerCase();
      if (slug.isNotEmpty) {
        final eventsSnap = await _firestore.collection('events').where('companySlug', isEqualTo: slug).get();
        for (final eDoc in eventsSnap.docs) {
          final eData = eDoc.data();
          bool eventNeedsUpdate = false;
          final rawAllocated = (eData['allocatedPrizes'] as List<dynamic>?) ?? [];
          final List<Map<String, dynamic>> updatedAllocated = [];
          for (final p in rawAllocated) {
            if (p is Map<String, dynamic>) {
              final copy = Map<String, dynamic>.from(p);
              if (copy['giftId'] == giftId || (copy['name'] != null && copy['name'] == giftName)) {
                if (giftName != null && giftName.trim().isNotEmpty) copy['name'] = giftName.trim();
                if (removeImage) {
                  copy.remove('imageUrl');
                } else if (imageUrl != null && imageUrl.trim().isNotEmpty) {
                  copy['imageUrl'] = imageUrl.trim();
                }
                eventNeedsUpdate = true;
              }
              updatedAllocated.add(copy);
            }
          }

          final rawRules = (eData['promotionalRules'] as List<dynamic>?) ?? [];
          final List<Map<String, dynamic>> updatedRules = [];
          for (final r in rawRules) {
            if (r is Map<String, dynamic>) {
              final copyRule = Map<String, dynamic>.from(r);
              final rawLinked = (copyRule['linkedGifts'] as List<dynamic>?) ?? [];
              final List<Map<String, dynamic>> updatedLinked = [];
              for (final lg in rawLinked) {
                if (lg is Map<String, dynamic>) {
                  final copyLg = Map<String, dynamic>.from(lg);
                  if (copyLg['giftId'] == giftId || (copyLg['giftName'] != null && copyLg['giftName'] == giftName)) {
                    if (giftName != null && giftName.trim().isNotEmpty) copyLg['giftName'] = giftName.trim();
                    if (removeImage) {
                      copyLg.remove('imageUrl');
                    } else if (imageUrl != null && imageUrl.trim().isNotEmpty) {
                      copyLg['imageUrl'] = imageUrl.trim();
                    }
                    eventNeedsUpdate = true;
                  }
                  updatedLinked.add(copyLg);
                }
              }
              copyRule['linkedGifts'] = updatedLinked;
              updatedRules.add(copyRule);
            }
          }

          if (eventNeedsUpdate) {
            await eDoc.reference.update({
              'allocatedPrizes': updatedAllocated,
              'promotionalRules': updatedRules,
            });
          }
        }
      }
    } catch (_) {}
  }

  /// Resolves all prize image URLs for an event.
  /// Combines event.allocatedPrizes, event.promotionalRules.linkedGifts,
  /// and live master records from `company_gifts`.
  /// If any master gifts have images that are missing in the event doc,
  /// this method automatically enriches/backfills the event in Firestore.
  Future<Map<String, String>> resolvePrizeImagesForEvent({
    String? eventId,
    String? companySlug,
  }) async {
    final Map<String, String> nameToImageMap = {};
    final cleanSlug = (companySlug ?? '').trim().toLowerCase();
    String resolvedSlug = cleanSlug;
    DocumentSnapshot<Map<String, dynamic>>? eventDoc;

    if (eventId != null && eventId.isNotEmpty) {
      try {
        eventDoc = await _firestore.collection('events').doc(eventId).get();
        if (eventDoc.exists) {
          final data = eventDoc.data() ?? {};
          if (resolvedSlug.isEmpty) {
            resolvedSlug = (data['companySlug'] ?? '').toString().trim().toLowerCase();
          }

          // 1. Direct from event allocatedPrizes
          final rawAllocated = data['allocatedPrizes'] as List<dynamic>? ?? [];
          for (final p in rawAllocated) {
            if (p is Map<String, dynamic>) {
              final name = (p['name'] ?? '').toString().trim();
              final img = (p['imageUrl'] ?? '').toString().trim();
              final giftId = (p['giftId'] ?? '').toString().trim();
              if (img.isNotEmpty) {
                if (name.isNotEmpty) nameToImageMap[name] = img;
                if (giftId.isNotEmpty) nameToImageMap[giftId] = img;
              }
            }
          }

          // 2. Direct from event promotionalRules linkedGifts
          final rawRules = data['promotionalRules'] as List<dynamic>? ?? [];
          for (final r in rawRules) {
            if (r is Map<String, dynamic>) {
              final linkedGifts = r['linkedGifts'] as List<dynamic>? ?? [];
              for (final lg in linkedGifts) {
                if (lg is Map<String, dynamic>) {
                  final gName = (lg['giftName'] ?? '').toString().trim();
                  final gImg = (lg['imageUrl'] ?? '').toString().trim();
                  final giftId = (lg['giftId'] ?? '').toString().trim();
                  if (gImg.isNotEmpty) {
                    if (gName.isNotEmpty) nameToImageMap[gName] = gImg;
                    if (giftId.isNotEmpty) nameToImageMap[giftId] = gImg;
                  }
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    // 3. Query company_gifts collection (live master catalog)
    if (resolvedSlug.isNotEmpty) {
      try {
        final giftsSnap = await _firestore
            .collection('company_gifts')
            .where('companySlug', isEqualTo: resolvedSlug)
            .get();

        bool needsEventBackfill = false;
        final Map<String, String> masterImagesById = {};

        for (final doc in giftsSnap.docs) {
          final data = doc.data();
          final gName = (data['giftName'] ?? data['name'] ?? '').toString().trim();
          final gImg = (data['imageUrl'] ?? '').toString().trim();
          if (gImg.isNotEmpty) {
            if (gName.isNotEmpty) nameToImageMap[gName] = gImg;
            nameToImageMap[doc.id] = gImg;
            masterImagesById[doc.id] = gImg;
          }
        }

        // 4. Backfill event document if it was created before images were uploaded
        if (eventDoc != null && eventDoc.exists && masterImagesById.isNotEmpty) {
          final data = eventDoc.data() ?? {};
          final rawAllocated = (data['allocatedPrizes'] as List<dynamic>?) ?? [];
          final List<Map<String, dynamic>> updatedAllocated = [];
          for (final p in rawAllocated) {
            if (p is Map<String, dynamic>) {
              final copy = Map<String, dynamic>.from(p);
              final giftId = copy['giftId'] as String? ?? '';
              final name = (copy['name'] as String? ?? '').trim();
              final currentImg = (copy['imageUrl'] as String? ?? '').trim();
              if (currentImg.isEmpty) {
                final foundImg = masterImagesById[giftId] ?? nameToImageMap[name];
                if (foundImg != null && foundImg.isNotEmpty) {
                  copy['imageUrl'] = foundImg;
                  needsEventBackfill = true;
                }
              }
              updatedAllocated.add(copy);
            }
          }

          // Also check promotionalRules linkedGifts
          final rawRules = (data['promotionalRules'] as List<dynamic>?) ?? [];
          final List<Map<String, dynamic>> updatedRules = [];
          for (final r in rawRules) {
            if (r is Map<String, dynamic>) {
              final copyRule = Map<String, dynamic>.from(r);
              final rawLinked = (copyRule['linkedGifts'] as List<dynamic>?) ?? [];
              final List<Map<String, dynamic>> updatedLinked = [];
              for (final lg in rawLinked) {
                if (lg is Map<String, dynamic>) {
                  final copyLg = Map<String, dynamic>.from(lg);
                  final giftId = copyLg['giftId'] as String? ?? '';
                  final name = (copyLg['giftName'] as String? ?? '').trim();
                  final currentImg = (copyLg['imageUrl'] as String? ?? '').trim();
                  if (currentImg.isEmpty) {
                    final foundImg = masterImagesById[giftId] ?? nameToImageMap[name];
                    if (foundImg != null && foundImg.isNotEmpty) {
                      copyLg['imageUrl'] = foundImg;
                      needsEventBackfill = true;
                    }
                  }
                  updatedLinked.add(copyLg);
                }
              }
              copyRule['linkedGifts'] = updatedLinked;
              updatedRules.add(copyRule);
            }
          }

          if (needsEventBackfill && eventId != null) {
            _firestore.collection('events').doc(eventId).update({
              'allocatedPrizes': updatedAllocated,
              'promotionalRules': updatedRules,
            }).catchError((_) {});
          }
        }
      } catch (_) {}
    }

    return nameToImageMap;
  }

  /// Updates the quantity of an existing gift in the master inventory.
  Future<void> updateGiftQuantity(String giftId, int newTotal) async {
    final doc = await _firestore.collection('company_gifts').doc(giftId).get();
    if (!doc.exists) return;

    final data = doc.data()!;
    final currentTotal = data['totalQuantity'] ?? 0;
    final currentAvailable = data['availableQuantity'] ?? 0;

    // Adjust available by the same delta as the total change
    final delta = newTotal - currentTotal;
    final newAvailable = (currentAvailable + delta).clamp(0, newTotal);

    await _firestore.collection('company_gifts').doc(giftId).update({
      'totalQuantity': newTotal,
      'availableQuantity': newAvailable,
    });
  }

  /// Completely deletes a gift from the master inventory and cascades deletion
  /// across all campaigns/events and promotional rules of that company.
  Future<void> deleteGiftCascade({
    required String giftId,
    String? companySlug,
    String? giftName,
    String performedBy = 'مسؤول النظام',
  }) async {
    String slug = companySlug?.toLowerCase().trim() ?? '';
    String targetName = giftName?.trim() ?? '';

    // 1. Fetch gift document from Firestore if metadata is missing
    final giftDocRef = _firestore.collection('company_gifts').doc(giftId);
    final giftDocSnap = await giftDocRef.get();
    if (giftDocSnap.exists) {
      final giftData = giftDocSnap.data();
      if (giftData != null) {
        if (slug.isEmpty) {
          slug = (giftData['companySlug'] ?? '').toString().toLowerCase().trim();
        }
        if (targetName.isEmpty) {
          targetName = (giftData['giftName'] ?? giftData['name'] ?? '').toString().trim();
        }
      }
    }

    // 2. Delete the master company_gifts doc
    await giftDocRef.delete();

    // 3. Cascade clean up across events of this company
    Query<Map<String, dynamic>> eventsQuery = _firestore.collection('events');
    if (slug.isNotEmpty) {
      eventsQuery = eventsQuery.where('companySlug', isEqualTo: slug);
    }

    final eventsSnap = await eventsQuery.get();
    final cleanTarget = _normalizePrizeText(targetName);

    for (final eventDoc in eventsSnap.docs) {
      final eventData = eventDoc.data();
      final allocatedPrizesRaw = eventData['allocatedPrizes'] as List<dynamic>? ?? [];
      bool eventChanged = false;

      final updatedPrizes = allocatedPrizesRaw.where((p) {
        if (p is! Map<String, dynamic>) return false;
        final pGiftId = (p['giftId'] ?? '').toString().trim();
        final pName = (p['name'] ?? '').toString().trim();
        final cleanPName = _normalizePrizeText(pName);

        final matchesId = pGiftId.isNotEmpty && pGiftId == giftId;
        final matchesName = cleanTarget.isNotEmpty &&
            (cleanPName == cleanTarget || cleanPName.contains(cleanTarget) || cleanTarget.contains(cleanPName));

        if (matchesId || matchesName) {
          eventChanged = true;
          return false; // Remove this prize
        }
        return true;
      }).toList();

      // Also clean up promotional rules
      final rulesRaw = eventData['promotionalRules'] as List<dynamic>? ?? [];
      final updatedRules = rulesRaw.where((r) {
        if (r is! Map<String, dynamic>) return true;
        final rGiftId = (r['linkedGiftId'] ?? '').toString().trim();
        final rGiftName = (r['linkedGiftName'] ?? '').toString().trim();
        final cleanRGiftName = _normalizePrizeText(rGiftName);

        final matchesId = rGiftId.isNotEmpty && rGiftId == giftId;
        final matchesName = cleanTarget.isNotEmpty &&
            (cleanRGiftName == cleanTarget || cleanRGiftName.contains(cleanTarget) || cleanTarget.contains(cleanRGiftName));

        if (matchesId || matchesName) {
          eventChanged = true;
          return false; // Remove rule
        }

        // Also check linkedGifts array inside the rule
        final linkedGiftsRaw = r['linkedGifts'] as List<dynamic>? ?? [];
        if (linkedGiftsRaw.isNotEmpty) {
          final updatedLinked = linkedGiftsRaw.where((lg) {
            if (lg is! Map<String, dynamic>) return true;
            final lgGiftId = (lg['giftId'] ?? '').toString().trim();
            final lgGiftName = (lg['giftName'] ?? '').toString().trim();
            final cleanLgGiftName = _normalizePrizeText(lgGiftName);
            if (lgGiftId == giftId || (cleanTarget.isNotEmpty && (cleanLgGiftName == cleanTarget || cleanLgGiftName.contains(cleanTarget)))) {
              eventChanged = true;
              return false;
            }
            return true;
          }).toList();
          r['linkedGifts'] = updatedLinked;
        }

        return true;
      }).toList();

      if (eventChanged) {
        await _firestore.collection('events').doc(eventDoc.id).update({
          'allocatedPrizes': updatedPrizes,
          'promotionalRules': updatedRules,
        });
      }
    }

    // 4. Log deletion in movements audit ledger
    final movementRef = _firestore.collection('gift_stock_movements').doc();
    final movement = GiftStockMovement(
      id: movementRef.id,
      companySlug: slug,
      giftId: giftId,
      giftName: targetName.isNotEmpty ? targetName : 'هدية محذوفة',
      movementType: 'gift_deleted',
      quantityChange: 0,
      previousTotal: 0,
      newTotal: 0,
      previousAvailable: 0,
      newAvailable: 0,
      reference: 'حذف صنف نهائياً',
      notes: 'تم حذف الصنف ومسح كافة مخصصاته وتبعياته من كافة الفعاليات والحملات',
      performedBy: performedBy,
      timestamp: DateTime.now(),
    );
    await movementRef.set(movement.toFirestore());

    // 5. Re-synchronize remaining active company gifts
    if (slug.isNotEmpty) {
      await syncCompanyGiftsAvailableQuantities(slug);
    }
  }

  /// Cleans up any orphaned prizes in events that no longer exist in master company_gifts.
  Future<void> cleanupOrphanedPrizesForCompany(String companySlug) async {
    final slug = companySlug.toLowerCase().trim();
    if (slug.isEmpty) return;

    try {
      // 1. Fetch valid master gifts for this company
      final giftsSnap = await _firestore
          .collection('company_gifts')
          .where('companySlug', isEqualTo: slug)
          .get();

      final validGiftIds = giftsSnap.docs.map((d) => d.id.trim()).toSet();
      final validGiftNames = giftsSnap.docs
          .map((d) => _normalizePrizeText((d.data()['giftName'] ?? d.data()['name'] ?? '').toString()))
          .where((s) => s.isNotEmpty)
          .toSet();

      // 2. Query events for this company
      final eventsSnap = await _firestore
          .collection('events')
          .where('companySlug', isEqualTo: slug)
          .get();

      for (final eventDoc in eventsSnap.docs) {
        final eventData = eventDoc.data();
        final allocatedPrizesRaw = eventData['allocatedPrizes'] as List<dynamic>? ?? [];
        bool eventChanged = false;

        final updatedPrizes = allocatedPrizesRaw.where((p) {
          if (p is! Map<String, dynamic>) return false;
          final pGiftId = (p['giftId'] ?? '').toString().trim();
          final pName = (p['name'] ?? '').toString().trim();
          final cleanPName = _normalizePrizeText(pName);

          final isValid = validGiftIds.contains(pGiftId) ||
              validGiftNames.contains(cleanPName) ||
              validGiftNames.any((v) => cleanPName.isNotEmpty && (cleanPName.contains(v) || v.contains(cleanPName)));

          if (!isValid) {
            eventChanged = true;
            return false; // Remove orphaned prize
          }
          return true;
        }).toList();

        if (eventChanged) {
          await _firestore.collection('events').doc(eventDoc.id).update({
            'allocatedPrizes': updatedPrizes,
          });
        }
      }
    } catch (_) {
      // Best-effort cleanup
    }
  }

  /// Deletes a gift from the master inventory.
  Future<void> deleteGift(String giftId, {String? companySlug, String? giftName}) async {
    await deleteGiftCascade(giftId: giftId, companySlug: companySlug, giftName: giftName);
  }

  static String _normalizePrizeText(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '') // Remove Arabic tashkeel/diacritics
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('٠', '0')
        .replaceAll('١', '1')
        .replaceAll('٢', '2')
        .replaceAll('٣', '3')
        .replaceAll('٤', '4')
        .replaceAll('٥', '5')
        .replaceAll('٦', '6')
        .replaceAll('٧', '7')
        .replaceAll('٨', '8')
        .replaceAll('٩', '9')
        .replaceAll(RegExp(r'[^\w\s\d\u0600-\u06FF]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<int> _extractNumbers(String text) {
    final matches = RegExp(r'\d+').allMatches(text);
    return matches.map((m) => int.tryParse(m.group(0)!) ?? 0).where((n) => n > 0).toList();
  }

  static double _extractNumericValue(String text) {
    final match = RegExp(r'(\d+(\.\d+)?)').firstMatch(text);
    return match != null ? double.tryParse(match.group(1)!) ?? 0.0 : 0.0;
  }

  /// A branch key matches one prize row by id or by the full branch name.
  /// A shorter sibling token, a partial name, an unknown code, or a foreign
  /// id does not match a different row.
  static bool _prizeBranchAccepted(
    Map<String, dynamic> prize,
    String branchId,
    String? pickedBranchName,
  ) {
    if (branchId.isEmpty) return true;
    final id = (prize['branchId'] ?? '').toString().trim();
    final name = (prize['branchName'] ?? '').toString().trim();
    if (id.isEmpty && name.isEmpty) return true;
    if (id == branchId || name == branchId) return true;
    if (pickedBranchName != null && name == pickedBranchName) return true;
    if (name.isNotEmpty &&
        _normalizePrizeText(name) == _normalizePrizeText(branchId)) {
      return true;
    }
    return false;
  }

  static bool _prizeIdentityMatches(
    Map<String, dynamic> prize,
    String prizeIdentifier,
  ) {
    final id = prizeIdentifier.trim();
    if (id.isEmpty) return true;
    final pGiftId = (prize['giftId'] ?? '').toString().trim();
    final pName = (prize['name'] ?? '').toString().trim();
    final cleanTarget = _normalizePrizeText(id);
    final cleanName = _normalizePrizeText(pName);
    if (pGiftId.isNotEmpty && (pGiftId == id || pGiftId == cleanTarget)) {
      return true;
    }
    if (pName == id) return true;
    if (cleanName.isNotEmpty && cleanName == cleanTarget) return true;
    if (cleanTarget.isNotEmpty &&
        (cleanName.contains(cleanTarget) || cleanTarget.contains(cleanName))) {
      return true;
    }
    final targetVal = _extractNumericValue(id);
    final pUnit = (prize['unitValue'] as num?)?.toDouble() ?? 0.0;
    if (targetVal > 0 && pUnit > 0 && (targetVal - pUnit).abs() < 0.01) {
      return true;
    }
    return false;
  }

  static String? _pickedPrizeBranchName(
    List<Map<String, dynamic>> prizes,
    String branchId,
  ) {
    if (branchId.isEmpty) return null;
    final names = <String>[];
    for (final prize in prizes) {
      final name = (prize['branchName'] ?? '').toString().trim();
      if (name.isNotEmpty) names.add(name);
    }
    if (names.isEmpty) return null;
    final exact = names.where((name) => name == branchId).toList();
    if (exact.length == 1) return exact.first;
    final normalized = _normalizePrizeText(branchId);
    if (normalized.isEmpty) return null;
    final normalizedHits =
        names.where((name) => _normalizePrizeText(name) == normalized).toList();
    if (normalizedHits.length == 1) return normalizedHits.first;
    return null;
  }

  static int findBestPrizeMatchIndex(
    List<Map<String, dynamic>> prizes,
    String prizeIdentifier, {
    String? branchId,
    double? unitValue,
    bool? isVoucher,
    bool preferWithRemaining = true,
  }) {
    if (prizes.isEmpty || prizeIdentifier.trim().isEmpty) return -1;
    final queriedBranch = (branchId ?? '').trim();
    final pickedBranchName = _pickedPrizeBranchName(prizes, queriedBranch);

    final cleanTarget = _normalizePrizeText(prizeIdentifier);
    final targetVal = unitValue ?? _extractNumericValue(prizeIdentifier);
    final targetNums = _extractNumbers(prizeIdentifier);

    int bestIndex = -1;
    int highestScore = -1;

    for (int i = 0; i < prizes.length; i++) {
      final p = prizes[i];
      final pGiftId = (p['giftId'] ?? '').toString().trim();
      final pName = (p['name'] ?? '').toString().trim();
      final pBranchId = (p['branchId'] ?? '').toString().trim();
      final pUnitVal = (p['unitValue'] as num?)?.toDouble() ?? 0.0;
      final pType = (p['giftType'] ?? '').toString();
      final cleanPNameForCheck = pName.toLowerCase();
      final pIsVoucher = pType == 'voucher' ||
          (pType != 'product' &&
              pUnitVal > 0 &&
              (cleanPNameForCheck.contains('فواتشر') ||
                  cleanPNameForCheck.contains('فوتشر') ||
                  cleanPNameForCheck.contains('قسيمة') ||
                  cleanPNameForCheck.contains('قسائم') ||
                  cleanPNameForCheck.contains('كارت مشتريات') ||
                  cleanPNameForCheck.contains('كوبون') ||
                  cleanPNameForCheck.contains('voucher') ||
                  cleanPNameForCheck.contains('coupon')));
      final pRemaining = (p['remainingQuantity'] as num?)?.toInt() ?? 0;

      int score = 0;

      // 1. Branch match weighting. Exact id or the full branch name only.
      // A token inside a longer sibling ("طنطا" inside "طنطا اوت ليت") is not a match.
      final pBranchName = (p['branchName'] ?? '').toString().trim();
      final isExactBranch = _prizeBranchAccepted(p, queriedBranch, pickedBranchName) &&
          queriedBranch.isNotEmpty &&
          !(pBranchId.isEmpty && pBranchName.isEmpty);
      final isGeneralBranch = pBranchId.isEmpty && pBranchName.isEmpty;
      if (isExactBranch) {
        score += 120;
      } else if (isGeneralBranch) {
        score += 60;
      } else if (queriedBranch.isNotEmpty && (pBranchId.isNotEmpty || pBranchName.isNotEmpty) && !isExactBranch) {
        // Different specific branch penalty
        score -= 80;
      }

      // 2. Direct exact matches
      if (pGiftId.isNotEmpty && (pGiftId == prizeIdentifier || pGiftId == cleanTarget)) {
        score += 200;
      } else if (pName == prizeIdentifier) {
        score += 160;
      }

      // 3. Normalized string matching
      final cleanPName = _normalizePrizeText(pName);
      if (cleanPName == cleanTarget && cleanTarget.isNotEmpty) {
        score += 140;
      } else if (cleanTarget.isNotEmpty && (cleanPName.contains(cleanTarget) || cleanTarget.contains(cleanPName))) {
        score += 95;
      }

      // 4. Voucher Denomination matching
      if ((isVoucher == true || pIsVoucher) && targetVal > 0 && pUnitVal > 0) {
        if ((targetVal - pUnitVal).abs() < 0.01) {
          score += 110;
        }
      }

      // 5. Product size / numeric token match (e.g. 90, 250, 360, 50, 25)
      final pNums = _extractNumbers(pName);
      if (targetNums.isNotEmpty && pNums.isNotEmpty && targetNums.any((n) => pNums.contains(n))) {
        score += 50;
      }

      // 6. Remaining quantity preference during decrement
      if (preferWithRemaining && pRemaining > 0) {
        score += 15;
      }

      if (score > highestScore && score > 30) {
        highestScore = score;
        bestIndex = i;
      }
    }

    if (bestIndex == -1) return -1;
    final winner = prizes[bestIndex];
    if (!_prizeBranchAccepted(winner, queriedBranch, pickedBranchName)) {
      return -1;
    }
    if (!_prizeIdentityMatches(winner, prizeIdentifier)) return -1;
    return bestIndex;
  }

  bool _isAnonymousCaller() {
    try {
      final user = scopedAuth().currentUser;
      return user == null || user.isAnonymous;
    } catch (_) {
      return false;
    }
  }

  /// Sends the claim to `decrementCampaignPrize`. Returns true when the function
  /// accepted the call. Staff may fall back to a direct write only when the
  /// function cannot be reached. Security and business rejections are not
  /// treated as a missing function. Anonymous callers never write stock locally.
  Future<bool> _claimViaCallable({
    required String eventId,
    String? receiptId,
    Map<String, dynamic>? receiptPatch,
    required List<Map<String, dynamic>> decrements,
  }) async {
    final body = {
      'eventId': eventId,
      if (receiptId != null && receiptId.isNotEmpty) 'receiptId': receiptId,
      if (receiptPatch != null && receiptPatch.isNotEmpty) 'receiptPatch': receiptPatch,
      'decrements': decrements,
    };
    try {
      if (kFirebaseEmulator) {
        await _callDecrementOnLoopback(body);
      } else {
        final callable = scopedFunctions().httpsCallable('decrementCampaignPrize');
        await callable.call(body);
      }
      return true;
    } on FirebaseFunctionsException catch (e) {
      if (!_isAnonymousCaller() &&
          staffCallableMayUseLocalStock(
            code: e.code,
            message: e.message ?? '',
            emulator: kFirebaseEmulator,
          )) {
        return false;
      }
      rethrow;
    } catch (e) {
      if (!_isAnonymousCaller() &&
          kFirebaseEmulator &&
          staffCallableMayUseLocalStock(
            code: 'unknown',
            message: e.toString(),
            emulator: true,
          )) {
        return false;
      }
      rethrow;
    }
  }

  /// Calls the functions emulator on the loopback host with a local App Check
  /// header. Production builds never take this path. The deployed function
  /// still requires a real App Check token.
  Future<void> _callDecrementOnLoopback(Map<String, dynamic> body) async {
    final host = kFirebaseEmulatorHost;
    if (host != '127.0.0.1' && host != 'localhost' && host != '::1') {
      throw ClaimCallableException(
        code: 'failed-precondition',
        message: 'Emulator claim host is not loopback.',
      );
    }
    final user = scopedAuth().currentUser;
    final token = await user?.getIdToken();
    if (token == null || token.isEmpty) {
      throw ClaimCallableException(code: 'unauthenticated', message: 'Sign-in is required.');
    }
    final projectId = FirebaseScope.app.options.projectId;
    final uri = Uri.parse('http://$host:5001/$projectId/us-central1/decrementCampaignPrize');
    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $token',
              'x-firebase-appcheck': 'local.emulator.token',
            },
            body: jsonEncode({'data': body}),
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException catch (e) {
      throw ClaimCallableException(code: 'deadline-exceeded', message: e.toString());
    } catch (e) {
      throw ClaimCallableException(code: 'unavailable', message: e.toString());
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }
    final error = decoded is Map ? decoded['error'] : null;
    final status = error is Map ? (error['status'] ?? '').toString() : '';
    final message = error is Map ? (error['message'] ?? response.body).toString() : response.body;
    throw ClaimCallableException(
      code: _callableStatusCode(status, response.statusCode),
      message: message,
      details: error is Map ? error['details'] : null,
    );
  }

  String _callableStatusCode(String status, int httpStatus) {
    const codes = {
      'CANCELLED': 'cancelled',
      'UNKNOWN': 'unknown',
      'INVALID_ARGUMENT': 'invalid-argument',
      'DEADLINE_EXCEEDED': 'deadline-exceeded',
      'NOT_FOUND': 'not-found',
      'ALREADY_EXISTS': 'already-exists',
      'PERMISSION_DENIED': 'permission-denied',
      'RESOURCE_EXHAUSTED': 'resource-exhausted',
      'FAILED_PRECONDITION': 'failed-precondition',
      'ABORTED': 'aborted',
      'OUT_OF_RANGE': 'out-of-range',
      'UNIMPLEMENTED': 'unimplemented',
      'INTERNAL': 'internal',
      'UNAVAILABLE': 'unavailable',
      'DATA_LOSS': 'data-loss',
      'UNAUTHENTICATED': 'unauthenticated',
    };
    final mapped = codes[status];
    if (mapped != null) return mapped;
    if (httpStatus == 401) return 'unauthenticated';
    if (httpStatus == 403) return 'permission-denied';
    if (httpStatus == 404) return 'not-found';
    return 'internal';
  }

  Future<void> _decrementCampaignPrizeLocal(
    String eventId,
    String prizeIdentifier, {
    String? branchId,
    int count = 1,
    double? unitValue,
    bool? isVoucher,
    String gameType = 'claim',
  }) async {
    if (eventId.isEmpty || prizeIdentifier.isEmpty || count <= 0) return;

    try {
      await _counterService?.recordClaimEvent(
        eventId: eventId,
        prizeIdentifier: prizeIdentifier,
        branchId: branchId,
        count: count,
        gameType: gameType,
      );
    } catch (e) {
      debugPrint('⚠️ CompanyGiftsService.decrementCampaignPrize sharded record error: $e');
    }

    try {
      final doc = await _firestore.collection('events').doc(eventId).get();
      if (!doc.exists) return;

      final data = doc.data()!;
      final prizes = List<Map<String, dynamic>>.from(data['allocatedPrizes'] ?? []);
      if (prizes.isEmpty) return;

      final matchIndex = findBestPrizeMatchIndex(
        prizes,
        prizeIdentifier,
        branchId: branchId,
        unitValue: unitValue,
        isVoucher: isVoucher,
        preferWithRemaining: true,
      );

      if (matchIndex != -1) {
        final remaining = (prizes[matchIndex]['remainingQuantity'] as num?)?.toInt() ?? 0;
        final newRemaining = (remaining - count).clamp(0, double.infinity).toInt();
        prizes[matchIndex]['remainingQuantity'] = newRemaining;
        await _firestore.collection('events').doc(eventId).update({
          'allocatedPrizes': prizes,
        });
      }
    } catch (e) {
      debugPrint('⚠️ CompanyGiftsService.decrementCampaignPrize root update contention fallback: $e');
    }
  }

  /// A consuming ladder is only correct inside the callable transaction.
  /// If the campaign cannot be read, local stock is also refused: an unknown
  /// campaign must not be treated as an exclusive one.
  Future<bool> _localStockWouldBypassConsumingLedger(String eventId) async {
    try {
      final doc = await _firestore.collection('events').doc(eventId).get();
      if (!doc.exists) return true;
      final data = doc.data() ?? const <String, dynamic>{};
      final mode = (data['spendLadderMode'] ?? data['spend_ladder_mode'] ?? 'exclusive')
          .toString()
          .trim();
      return mode == 'consuming';
    } catch (_) {
      return true;
    }
  }

  /// Records a gift claim and decrements campaign stock on the server.
  ///
  /// Anonymous field reps cannot update the receipt or the prize counters
  /// themselves. The callable writes both with the Admin SDK.
  Future<void> claimCampaignPrizes({
    required String eventId,
    String? receiptId,
    Map<String, dynamic>? receiptPatch,
    required List<Map<String, dynamic>> decrements,
  }) async {
    final cleanDecrements = decrements.where((item) {
      final id = (item['prizeIdentifier'] ?? '').toString().trim();
      final count = (item['count'] as num?)?.toInt() ?? 0;
      return eventId.isNotEmpty && id.isNotEmpty && count > 0;
    }).toList();
    final patch = receiptPatch ?? const <String, dynamic>{};
    if (cleanDecrements.isEmpty && patch.isEmpty) return;

    if (eventId.isNotEmpty) {
      final handled = await _claimViaCallable(
        eventId: eventId,
        receiptId: receiptId,
        receiptPatch: patch,
        decrements: cleanDecrements,
      );
      if (handled) return;
      if (await _localStockWouldBypassConsumingLedger(eventId)) {
        throw ClaimCallableException(
          code: 'unavailable',
          message: 'تعذر اعتماد الجولة لأن الخادم غير متاح. لم يُكتب سجل الهدايا ولم يُخصم الرصيد.',
        );
      }
    }

    if (receiptId != null && receiptId.isNotEmpty && patch.isNotEmpty) {
      await _firestore.collection('receipts_transactions').doc(receiptId).update(patch);
    }
    for (final item in cleanDecrements) {
      await _decrementCampaignPrizeLocal(
        eventId,
        item['prizeIdentifier'].toString(),
        branchId: item['branchId']?.toString(),
        count: (item['count'] as num?)?.toInt() ?? 1,
        unitValue: (item['unitValue'] as num?)?.toDouble(),
        isVoucher: item['isVoucher'] as bool?,
        gameType: (item['gameType'] ?? 'claim').toString(),
      );
    }
  }

  /// Decrements the remaining quantity of a prize in a specific campaign after a win.
  /// [prizeIdentifier] can be a giftId or a prize name.
  /// If [branchId] is provided, prioritizes matching the specific branch prize.
  /// [count] is the quantity to decrement (defaults to 1).
  Future<void> decrementCampaignPrize(
    String eventId,
    String prizeIdentifier, {
    String? branchId,
    int count = 1,
    double? unitValue,
    bool? isVoucher,
    String gameType = 'claim',
    String? receiptId,
    Map<String, dynamic>? receiptPatch,
  }) {
    return claimCampaignPrizes(
      eventId: eventId,
      receiptId: receiptId,
      receiptPatch: receiptPatch,
      decrements: [
        {
          'prizeIdentifier': prizeIdentifier,
          'branchId': branchId,
          'count': count,
          'unitValue': unitValue,
          'isVoucher': isVoucher,
          'gameType': gameType,
        },
      ],
    );
  }

  /// Restores / Replenishes the remaining quantity of a prize in a campaign (e.g. when an invoice is deleted).
  Future<void> replenishCampaignPrize(
    String eventId,
    String prizeIdentifier, {
    String? branchId,
    int count = 1,
    double? unitValue,
    bool? isVoucher,
  }) async {
    if (eventId.isEmpty || prizeIdentifier.isEmpty || count <= 0) return;

    // 1. Revert distributed sharded counters by negative delta
    try {
      final cleanPrize = DistributedCounterService.sanitizeCounterKey(prizeIdentifier);
      await _counterService?.incrementCampaignCounter(
        eventId: eventId,
        counterName: 'prize_$cleanPrize',
        delta: -count,
      );
      await _counterService?.incrementCampaignCounter(
        eventId: eventId,
        counterName: 'claims_total',
        delta: -count,
      );
    } catch (e) {
      debugPrint('⚠️ CompanyGiftsService.replenishCampaignPrize sharded revert error: $e');
    }

    // 2. Replenish root event document
    try {
      final doc = await _firestore.collection('events').doc(eventId).get();
      if (!doc.exists) return;

      final data = doc.data()!;
      final prizes = List<Map<String, dynamic>>.from(data['allocatedPrizes'] ?? []);
      if (prizes.isEmpty) return;

      final matchIndex = findBestPrizeMatchIndex(
        prizes,
        prizeIdentifier,
        branchId: branchId,
        unitValue: unitValue,
        isVoucher: isVoucher,
        preferWithRemaining: false,
      );

      if (matchIndex != -1) {
        final allocated = (prizes[matchIndex]['allocatedQuantity'] as num?)?.toInt() ?? 0;
        final remaining = (prizes[matchIndex]['remainingQuantity'] as num?)?.toInt() ?? 0;
        final maxCapacity = allocated > 0 ? allocated : (remaining + count);
        final newRemaining = (remaining + count).clamp(0, maxCapacity).toInt();
        prizes[matchIndex]['remainingQuantity'] = newRemaining;
        await _firestore.collection('events').doc(eventId).update({
          'allocatedPrizes': prizes,
        });
      }
    } catch (e) {
      debugPrint('⚠️ CompanyGiftsService.replenishCampaignPrize root update fallback: $e');
    }
  }

  /// Records an immutable audit snapshot for a completed weekend/wave cycle,
  /// saves the settlement to `campaign_stock_settlements`, and updates the active campaign quota for the new wave.
  Future<String> recordWeekendSettlement({
    required String companySlug,
    required EventModel event,
    required String cycleTitle,
    required List<String> branches,
    required List<CompanyGiftModel> masterGifts,
    required Map<String, int> cellAllocations,
    required Map<String, int> claimedCache,
    required int newAllocatedQuota,
    String performedBy = 'مدير الشركة',
  }) async {
    final slug = companySlug.toLowerCase().trim();
    final eventRef = _firestore.collection('events').doc(event.id);
    final eventSnap = await eventRef.get();
    if (!eventSnap.exists) {
      throw Exception('الفعالية غير موجودة في قاعدة البيانات');
    }

    final eventData = eventSnap.data() ?? {};
    final rawPrizes = (eventData['allocatedPrizes'] as List<dynamic>?) ?? [];
    List<AllocatedPrize> livePrizes = rawPrizes
        .map((p) => AllocatedPrize.fromMap(Map<String, dynamic>.from(p as Map)))
        .toList();

    int totalAllocatedBefore = 0;
    int totalClaimed = 0;
    int totalReturned = 0;

    final Map<String, dynamic> branchSnapshots = {};

    for (final branchName in branches) {
      int branchAlloc = 0;
      int branchClaim = 0;
      final Map<String, dynamic> branchGifts = {};

      for (final gift in masterGifts) {
        final giftKey = gift.id.isNotEmpty ? gift.id : gift.giftName;
        final cellKey = '${event.id}_${branchName}_$giftKey';
        final alloc = cellAllocations[cellKey] ?? 0;
        final claimed = claimedCache[cellKey] ?? 0;
        final returned = (alloc - claimed).clamp(0, alloc);

        branchAlloc += alloc;
        branchClaim += claimed;

        branchGifts[giftKey] = {
          'giftId': gift.id,
          'giftName': gift.giftName,
          'allocated': alloc,
          'claimed': claimed,
          'returned': returned,
          'unitValue': gift.unitValue,
          'isVoucher': gift.isVoucher,
          'giftType': gift.giftType,
        };
      }

      final branchRet = (branchAlloc - branchClaim).clamp(0, branchAlloc);
      totalAllocatedBefore += branchAlloc;
      totalClaimed += branchClaim;
      totalReturned += branchRet;

      branchSnapshots[branchName] = {
        'branchName': branchName,
        'totalAllocated': branchAlloc,
        'totalClaimed': branchClaim,
        'totalReturned': branchRet,
        'gifts': branchGifts,
      };
    }

    // 1. Settlement snapshot (written server-side by updateBranchAllocations)
    final settlementData = {
      'campaignName': event.eventName,
      'cycleTitle': cycleTitle.trim().isNotEmpty ? cycleTitle.trim() : 'تسوية دورة الويك إند',
      'settledBy': performedBy,
      'totalAllocatedBefore': totalAllocatedBefore,
      'totalClaimed': totalClaimed,
      'totalReturned': totalReturned,
      'newAllocatedStock': newAllocatedQuota,
      'branchSnapshots': branchSnapshots,
    };

    // 2. Update the event with the new wave quotas
    final List<AllocatedPrize> newPrizes = [];
    for (final prize in livePrizes) {
      newPrizes.add(prize.copyWith(
        allocatedQuantity: newAllocatedQuota,
        remainingQuantity: newAllocatedQuota,
      ));
    }

    // 3. Audit entry in gift_stock_movements (reference = settlement id, set by server)
    final movement = GiftStockMovement(
      id: '',
      companySlug: slug,
      giftId: event.id,
      giftName: cycleTitle,
      movementType: 'settlement_cycle',
      quantityChange: totalReturned,
      previousTotal: totalAllocatedBefore,
      newTotal: newAllocatedQuota * branches.length * masterGifts.length,
      previousAvailable: totalReturned,
      newAvailable: newAllocatedQuota * branches.length * masterGifts.length,
      reference: '',
      notes: 'تم اعتماد وإغلاق $cycleTitle (منصرف: $totalClaimed, مرتجع: $totalReturned, جديد: $newAllocatedQuota)',
      performedBy: performedBy,
      timestamp: DateTime.now(),
    );
    final result = await _callUpdateBranchAllocations({
      'action': 'settlement',
      'companySlug': slug,
      'eventId': event.id,
      'allocatedPrizes': newPrizes.map((p) => p.toMap()).toList(),
      'settlement': settlementData,
      'movement': Map<String, dynamic>.from(movement.toFirestore())..remove('timestamp'),
    });
    return (result['settlementId'] ?? '').toString();
  }

  Future<Map<String, dynamic>> _callUpdateBranchAllocations(Map<String, dynamic> payload) async {
    try {
      final res = await scopedFunctions()
          .httpsCallable('updateBranchAllocations')
          .call(payload);
      final data = res.data;
      return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      throw Exception(msg.isNotEmpty ? msg : e.code);
    }
  }
}
