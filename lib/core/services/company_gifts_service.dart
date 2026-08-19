import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_service.dart';
import '../../features/admin/domain/company_gift_model.dart';

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

  /// Adds a new gift to a company's master inventory.
  Future<void> addGift({
    required String companySlug,
    required String companyName,
    required String giftName,
    required int quantity,
  }) async {
    await _firestore.collection('company_gifts').add({
      'companySlug': companySlug.toLowerCase().trim(),
      'companyName': companyName,
      'giftName': giftName.trim(),
      'name': giftName.trim(),
      'totalQuantity': quantity,
      'availableQuantity': quantity,
      'createdAt': FieldValue.serverTimestamp(),
    });
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

  /// Allocates a quantity from the master inventory to a campaign.
  /// Decreases availableQuantity by the allocated amount.
  Future<bool> allocateGiftToCampaign(String giftId, int quantity) async {
    final doc = await _firestore.collection('company_gifts').doc(giftId).get();
    if (!doc.exists) return false;

    final available = (doc.data()!['availableQuantity'] ?? 0) as int;
    if (available < quantity) return false;

    await _firestore.collection('company_gifts').doc(giftId).update({
      'availableQuantity': FieldValue.increment(-quantity),
    });
    return true;
  }

  /// Returns allocated quantity back to the master inventory (e.g. when a campaign is deleted).
  Future<void> deallocateGift(String giftId, int quantity) async {
    await _firestore.collection('company_gifts').doc(giftId).update({
      'availableQuantity': FieldValue.increment(quantity),
    });
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

      // 1. Branch match weighting
      final isExactBranch = branchId != null && branchId.isNotEmpty && pBranchId == branchId;
      final isGeneralBranch = pBranchId.isEmpty;
      if (isExactBranch) {
        score += 120;
      } else if (isGeneralBranch) {
        score += 60;
      } else if (branchId != null && branchId.isNotEmpty && pBranchId.isNotEmpty && pBranchId != branchId) {
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
