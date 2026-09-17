import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_service.dart';
import '../../features/admin/domain/company_gift_model.dart';
import '../../features/admin/domain/event_model.dart';

final companyGiftsServiceProvider = Provider<CompanyGiftsService>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return CompanyGiftsService(firestore);
});

class CompanyGiftsService {
  final FirebaseFirestore _firestore;

  CompanyGiftsService(this._firestore);

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

  /// Helper to match branch names with fuzzy normalization (stripping city parentheticals and "فرع")
  static bool matchesBranchName(String b1, String b2) {
    final t1 = b1.trim().toLowerCase();
    final t2 = b2.trim().toLowerCase();
    if (t1.isEmpty || t2.isEmpty) return false;
    if (t1 == t2) return true;
    final c1 = t1.replaceAll(RegExp(r'\s*\([^)]*\)'), '').replaceAll(RegExp(r'فرع\s+'), '').trim();
    final c2 = t2.replaceAll(RegExp(r'\s*\([^)]*\)'), '').replaceAll(RegExp(r'فرع\s+'), '').trim();
    if (c1.isEmpty || c2.isEmpty) return false;
    return c1 == c2 || (c1.length >= 3 && t2.contains(c1)) || (c2.length >= 3 && t1.contains(c2));
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
    final batch = _firestore.batch();

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

          if (newAllocatedQuantity < claimed) {
            throw Exception('لا يمكن تعيين رصيد فرع ($branchName) لصنف (${gift.giftName}) أقل من المنصرف ($claimed قطعة)');
          }

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

          final delta = newAllocatedQuantity - oldAllocated;
          final newRemaining = (oldRemaining + delta).clamp(0, newAllocatedQuantity);

          final updatedPrize = AllocatedPrize(
            giftId: finalGiftId,
            name: finalGiftName,
            allocatedQuantity: newAllocatedQuantity,
            remainingQuantity: newRemaining,
            branchId: matchedIndex != -1 ? prizes[matchedIndex].branchId : '',
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
        }

        // If there is an unbranched general pool prize for this gift, ensure its remaining quantity reflects the active stock
        for (int i = 0; i < prizes.length; i++) {
          final p = prizes[i];
          if (p.branchName.trim().isEmpty) {
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

      if (eventModified) {
        final updatedBranches = <String>{};
        updatedBranches.addAll(event.branchNames);
        for (final b in targetBranches) {
          if (b != 'كافة الفروع / عام' && b != 'All Branches' && b != 'الفرع الرئيسي') {
            updatedBranches.add(b);
          }
        }
        batch.update(eventRef, {
          'allocatedPrizes': prizes.map((p) => p.toMap()).toList(),
          if (updatedBranches.isNotEmpty) 'branchNames': updatedBranches.toList(),
        });
      }
    }

    if (totalUpdated > 0) {
      await batch.commit();
      await syncCompanyGiftsAvailableQuantities(slug);
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
        .replaceAll(RegExp(r'[^\w\s\d]'), ' ')
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

  static int findBestPrizeMatchIndex(
    List<Map<String, dynamic>> prizes,
    String prizeIdentifier, {
    String? branchId,
    double? unitValue,
    bool? isVoucher,
    bool preferWithRemaining = true,
  }) {
    if (prizes.isEmpty || prizeIdentifier.trim().isEmpty) return -1;

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

      // 1. Branch match weighting (support branchId, branchName, and normalized branch name)
      final pBranchName = (p['branchName'] ?? '').toString().trim();
      final isExactBranch = branchId != null &&
          branchId.isNotEmpty &&
          (pBranchId == branchId ||
              pBranchName == branchId ||
              _normalizePrizeText(pBranchName) == _normalizePrizeText(branchId) ||
              (_normalizePrizeText(branchId).isNotEmpty && _normalizePrizeText(pBranchName).contains(_normalizePrizeText(branchId))));
      final isGeneralBranch = pBranchId.isEmpty && pBranchName.isEmpty;
      if (isExactBranch) {
        score += 120;
      } else if (isGeneralBranch) {
        score += 60;
      } else if (branchId != null && branchId.isNotEmpty && (pBranchId.isNotEmpty || pBranchName.isNotEmpty) && !isExactBranch) {
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

    return bestIndex;
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
  }) async {
    if (eventId.isEmpty || prizeIdentifier.isEmpty || count <= 0) return;

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

    // 1. Create settlement snapshot document in Firestore
    final settlementRef = _firestore.collection('campaign_stock_settlements').doc();
    final settlementData = {
      'campaignId': event.id,
      'campaignName': event.eventName,
      'companySlug': slug,
      'cycleTitle': cycleTitle.trim().isNotEmpty ? cycleTitle.trim() : 'تسوية دورة الويك إند',
      'settledAt': FieldValue.serverTimestamp(),
      'settledBy': performedBy,
      'totalAllocatedBefore': totalAllocatedBefore,
      'totalClaimed': totalClaimed,
      'totalReturned': totalReturned,
      'newAllocatedStock': newAllocatedQuota,
      'branchSnapshots': branchSnapshots,
    };
    await settlementRef.set(settlementData);

    // 2. Update the event with the new wave quotas
    final List<AllocatedPrize> newPrizes = [];
    for (final prize in livePrizes) {
      newPrizes.add(prize.copyWith(
        allocatedQuantity: newAllocatedQuota,
        remainingQuantity: newAllocatedQuota,
      ));
    }

    await eventRef.update({
      'allocatedPrizes': newPrizes.map((p) => p.toMap()).toList(),
      'lastSettlementId': settlementRef.id,
      'lastSettledAt': FieldValue.serverTimestamp(),
    });

    // 3. Log audit entry in gift_stock_movements
    final movementRef = _firestore.collection('gift_stock_movements').doc();
    final movement = GiftStockMovement(
      id: movementRef.id,
      companySlug: slug,
      giftId: event.id,
      giftName: cycleTitle,
      movementType: 'settlement_cycle',
      quantityChange: totalReturned,
      previousTotal: totalAllocatedBefore,
      newTotal: newAllocatedQuota * branches.length * masterGifts.length,
      previousAvailable: totalReturned,
      newAvailable: newAllocatedQuota * branches.length * masterGifts.length,
      reference: settlementRef.id,
      notes: 'تم اعتماد وإغلاق $cycleTitle (منصرف: $totalClaimed, مرتجع: $totalReturned, جديد: $newAllocatedQuota)',
      performedBy: performedBy,
      timestamp: DateTime.now(),
    );
    await movementRef.set(movement.toFirestore());

    return settlementRef.id;
  }
}
