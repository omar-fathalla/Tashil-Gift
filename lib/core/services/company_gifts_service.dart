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

    // Match the target allocated prize for this branch & gift
    final targetBranchNorm = branchName.trim().toLowerCase();
    final targetBranchIdNorm = branchId.trim().toLowerCase();
    final targetGiftKeyNorm = giftKey.trim().toLowerCase();

    int matchedIndex = -1;
    for (int i = 0; i < prizes.length; i++) {
      final p = prizes[i];
      final pBranchNorm = p.branchName.trim().toLowerCase();
      final pBranchIdNorm = p.branchId.trim().toLowerCase();
      final pGiftIdNorm = p.giftId.trim().toLowerCase();
      final pNameNorm = p.name.trim().toLowerCase();

      final branchMatches = (targetBranchIdNorm.isNotEmpty && pBranchIdNorm == targetBranchIdNorm) ||
          (pBranchNorm == targetBranchNorm);
      final giftMatches = pGiftIdNorm == targetGiftKeyNorm || pNameNorm == targetGiftKeyNorm;

      if (branchMatches && giftMatches) {
        matchedIndex = i;
        break;
      }
    }

    // Also find master gift record for audit/details if available
    CompanyGiftModel? masterGift;
    try {
      final gifts = await getGiftsForCompany(slug);
      masterGift = gifts.firstWhere(
        (g) => g.id.toLowerCase() == targetGiftKeyNorm || g.giftName.trim().toLowerCase() == targetGiftKeyNorm,
      );
    } catch (_) {}

    int oldAllocated = 0;
    int oldRemaining = 0;
    int claimed = 0;
    String finalGiftId = masterGift?.id ?? giftKey;
    String finalGiftName = masterGift?.giftName ?? giftKey;
    String finalGiftType = masterGift?.giftType ?? 'product';
    double finalUnitValue = masterGift?.unitValue ?? 0.0;

    if (matchedIndex != -1) {
      final p = prizes[matchedIndex];
      oldAllocated = p.allocatedQuantity;
      oldRemaining = p.remainingQuantity;
      claimed = (oldAllocated - oldRemaining).clamp(0, oldAllocated);
      finalGiftId = p.giftId.isNotEmpty ? p.giftId : finalGiftId;
      finalGiftName = p.name.isNotEmpty ? p.name : finalGiftName;
      finalGiftType = p.giftType;
      finalUnitValue = p.unitValue;
    }

    if (newAllocatedQuantity < claimed) {
      throw Exception(
        'لا يمكن تقليل حصة الفرع إلى $newAllocatedQuantity حيث تم صرف $claimed جائزة للعملاء بالفعل.',
      );
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

  /// Adds a new gift to a company's master inventory with initial batch creation.
  Future<void> addGift({
    required String companySlug,
    required String companyName,
    required String giftName,
    required int quantity,
    String giftType = 'product',
    double unitValue = 0.0,
    String referenceNumber = '',
    String notes = '',
    String addedBy = 'مسؤول النظام',
  }) async {
    final docRef = _firestore.collection('company_gifts').doc();
    final now = DateTime.now();

    final initialBatch = GiftSupplyBatch(
      id: 'batch_${now.millisecondsSinceEpoch}',
      batchNumber: 1,
      quantity: quantity,
      supplyDate: now,
      referenceNumber: referenceNumber.trim().isNotEmpty ? referenceNumber.trim() : 'الرصيد الافتتاحي (دفعة 1)',
      notes: notes.trim().isNotEmpty ? notes.trim() : 'دفعة التوريد الافتتاحية الأولى',
      addedBy: addedBy.trim(),
    );

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
      'orderIndex': now.millisecondsSinceEpoch ~/ 1000,
      'batches': [initialBatch.toMap()],
      'createdAt': FieldValue.serverTimestamp(),
    });

    final movementRef = _firestore.collection('gift_stock_movements').doc();
    final movement = GiftStockMovement(
      id: movementRef.id,
      companySlug: companySlug.toLowerCase().trim(),
      giftId: docRef.id,
      giftName: giftName.trim(),
      movementType: 'supply_batch',
      quantityChange: quantity,
      previousTotal: 0,
      newTotal: quantity,
      previousAvailable: 0,
      newAvailable: quantity,
      reference: referenceNumber.trim().isNotEmpty ? referenceNumber.trim() : 'الرصيد الافتتاحي (دفعة 1)',
      notes: notes.trim().isNotEmpty ? notes.trim() : 'تكويد وتوريد أولي للهدية',
      performedBy: addedBy,
      timestamp: now,
    );
    batch.set(movementRef, movement.toFirestore());

    await batch.commit();
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

  /// Deletes a gift from the master inventory.
  Future<void> deleteGift(String giftId) async {
    await _firestore.collection('company_gifts').doc(giftId).delete();
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
      final pIsVoucher = pType == 'voucher' || pUnitVal > 0;
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
}
