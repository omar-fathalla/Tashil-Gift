import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'firebase_scope.dart';

/// Result of checking a receipt for duplication in Firestore.
class ReceiptDuplicateCheckResult {
  final bool isDuplicate;
  final String receiptNumber;
  final String? existingCampaignId;
  final String? existingCampaignName;
  final String? existingPrizeWon;
  final String? existingClaimedAt;
  final String? existingStoreChain;
  final String? existingBranch;
  final String? existingReceiptDate;
  final String? existingUploadedAt;
  final String? existingStatus;
  final String rejectionMessage;
  final Map<String, dynamic>? existingData;
  /// 2.0.149: the duplicate is the same-campaign doc at the deterministic id,
  /// so a re-upload can go through replaceReceipt instead of being blocked.
  final bool exactDocExists;
  /// 2.0.152: the existing receipt is approved and the caller is not an
  /// admin, so it can't be re-uploaded or replaced (server-decided).
  final bool locked;
  final String? existingApprovedAt;
  final num? existingTotal;

  const ReceiptDuplicateCheckResult({
    required this.isDuplicate,
    required this.receiptNumber,
    this.existingCampaignId,
    this.existingCampaignName,
    this.existingPrizeWon,
    this.existingClaimedAt,
    this.existingStoreChain,
    this.existingBranch,
    this.existingReceiptDate,
    this.existingUploadedAt,
    this.existingStatus,
    this.rejectionMessage = '',
    this.existingData,
    this.exactDocExists = false,
    this.locked = false,
    this.existingApprovedAt,
    this.existingTotal,
  });

  static const ReceiptDuplicateCheckResult notDuplicate = ReceiptDuplicateCheckResult(
    isDuplicate: false,
    receiptNumber: '',
  );
}

/// Authoritative helper for receipt deduplication, deterministic document ID generation,
/// and pre-write uniqueness enforcement across single-scan and multi-campaign scan modes.
class ReceiptDeduplicationHelper {
  /// Cleans and normalizes a receipt number for consistent queries and comparisons.
  static String normalizeReceiptNumber(String? raw) {
    if (raw == null) return '';
    return raw.trim().replaceAll(RegExp(r'\s+'), '');
  }

  /// Firestore field holding every physical receipt number in an upload.
  static const String componentsField = 'component_receipt_numbers';

  /// Physical receipt numbers inside one upload. A combined upload stores
  /// them joined with ' + '; a single receipt yields one entry.
  static List<String> componentReceiptNumbers(String? raw) {
    final out = <String>[];
    for (final part in normalizeReceiptNumber(raw).split('+')) {
      if (part.isNotEmpty && !out.contains(part)) out.add(part);
    }
    return out;
  }

  /// Components of a stored receipt. Records saved before the array field
  /// existed fall back to splitting their joined receipt_number.
  static List<String> storedComponents(Map<String, dynamic> data) {
    final raw = data[componentsField];
    if (raw is List && raw.isNotEmpty) {
      final out = <String>[];
      for (final v in raw) {
        final n = normalizeReceiptNumber(v?.toString());
        if (n.isNotEmpty && !out.contains(n)) out.add(n);
      }
      if (out.isNotEmpty) return out;
    }
    return componentReceiptNumbers(data['receipt_number']?.toString());
  }

  /// First physical receipt number shared by an upload and a stored record.
  static String? sharedComponent(String? receiptNumber, Map<String, dynamic> stored) {
    final existing = storedComponents(stored);
    for (final c in componentReceiptNumbers(receiptNumber)) {
      if (existing.contains(c)) return c;
    }
    return null;
  }

  /// Fields to write with a receipt so later uploads can match each component.
  static Map<String, dynamic> componentFields(String? receiptNumber) {
    final components = componentReceiptNumbers(receiptNumber);
    return components.isEmpty ? const {} : {componentsField: components};
  }

  /// Sanitizes receipt number for use inside Firestore document keys (removes /, \, etc.)
  static String sanitizeForDocId(String receiptNumber) {
    final clean = normalizeReceiptNumber(receiptNumber);
    if (clean.isEmpty) return 'UNKNOWN';
    return clean.replaceAll(RegExp(r'[/\\?%*:|"<>\s]'), '_');
  }

  /// Generates a deterministic Firestore document ID for a campaign receipt transaction.
  /// Format: rcpt_{campaignId}_{sanitizedReceiptNumber}
  /// This physically guarantees that a receipt cannot produce duplicate Firestore documents
  /// for the same campaign, even under race conditions or rapid double submissions.
  static String getDeterministicDocId({
    required String campaignId,
    required String receiptNumber,
  }) {
    final clean = sanitizeForDocId(receiptNumber);
    final cleanCampaignId = campaignId.trim().replaceAll(RegExp(r'[/\\?%*:|"<>\s]'), '_');
    return 'rcpt_${cleanCampaignId}_$clean';
  }

  /// Checks if an existing transaction document indicates that the receipt was already claimed/drawn.
  static bool isTransactionClaimed(Map<String, dynamic> data) {
    final status = data['status'];
    final isExplicitlyRejected = status == 'rejected' || data['is_valid'] == false;
    if (isExplicitlyRejected) {
      return false;
    }

    final gamePlayed = data['game_played'] == true;
    final claimStatus = data['claim_status']?.toString().toLowerCase();
    final isHandedOver = claimStatus == 'handed_over';
    final prizeWon = data['prize_won']?.toString().trim();
    final hasPrizeWon = prizeWon != null && prizeWon.isNotEmpty && prizeWon != 'null';

    final claimedGifts = data['claimed_gifts'];
    final hasClaimedGifts = claimedGifts is List && claimedGifts.isNotEmpty;

    final linkedGifts = data['linked_gifts'];
    final hasLinkedGifts = linkedGifts is List && linkedGifts.isNotEmpty && isHandedOver;

    return gamePlayed || isHandedOver || hasPrizeWon || hasClaimedGifts || hasLinkedGifts;
  }

  /// Performs a pre-write duplicate check against Firestore.
  /// 
  /// In [isMultiScan] mode:
  /// Verifies if the receipt has ALREADY been claimed in ANY campaign of [companySlug]
  /// or in a previous multi-campaign bundle. If so, rejects re-disbursal.
  /// 
  /// In single campaign mode ([campaignId] provided):
  /// Verifies if the receipt has ALREADY been claimed in that specific [campaignId]
  /// or as part of an already claimed multi-campaign bundle.
  static Future<ReceiptDuplicateCheckResult> checkReceiptDuplicate({
    required FirebaseFirestore firestore,
    required String receiptNumber,
    required String companySlug,
    String? campaignId,
    bool isMultiScan = false,
    bool exactDocId = false,
  }) async {
    final cleanNumber = normalizeReceiptNumber(receiptNumber);
    if (cleanNumber.isEmpty) {
      return ReceiptDuplicateCheckResult.notDuplicate;
    }

    // Anonymous reps cannot read other users' receipts under firestore.rules,
    // so the cross-user lookup runs server-side (checkReceiptDuplicate, Admin SDK).
    // [firestore] is kept for API compatibility. On any server failure the result
    // is "unknown" (not duplicate): the deterministic-ID create is still blocked
    // by the rules if the receipt already exists for the campaign.
    try {
      final res = await scopedFunctions()
          .httpsCallable(
            'checkReceiptDuplicate',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
          )
          .call<dynamic>({
        'receiptNumber': cleanNumber,
        'companySlug': companySlug,
        'campaignId': (campaignId != null && campaignId.isNotEmpty) ? campaignId : null,
        'isMultiScan': isMultiScan,
        if (exactDocId) 'exactDocId': true,
      });
      final data = res.data;
      final isDup = data is Map && data['duplicate'] == true;
      if (!isDup) return ReceiptDuplicateCheckResult.notDuplicate;
      final summary = (data['summary'] is Map) ? Map<String, dynamic>.from(data['summary'] as Map) : const <String, dynamic>{};
      String? pick(String k) {
        final v = summary[k]?.toString().trim();
        return (v == null || v.isEmpty || v == 'null') ? null : v;
      }
      return ReceiptDuplicateCheckResult(
        isDuplicate: true,
        receiptNumber: cleanNumber,
        existingCampaignId: campaignId,
        existingCampaignName: pick('campaignName'),
        existingPrizeWon: pick('giftValue'),
        existingClaimedAt: pick('redeemedAt'),
        existingBranch: pick('branch'),
        existingReceiptDate: pick('receiptDate'),
        existingUploadedAt: pick('uploadedAt'),
        existingStatus: pick('status') ?? data['existingStatus']?.toString(),
        rejectionMessage: data['locked'] == true
            ? lockedMessage(cleanNumber)
            : duplicateMessage(cleanNumber, isMultiScan: isMultiScan),
        exactDocExists: data['exactDocExists'] == true,
        locked: data['locked'] == true,
        existingApprovedAt: pick('approvedAt'),
        existingTotal: summary['total'] is num ? summary['total'] as num : null,
      );
    } catch (e) {
      debugPrint('Receipt duplicate check unavailable (treated as unknown): $e');
      return ReceiptDuplicateCheckResult.notDuplicate;
    }
  }

  /// 2.0.149: re-upload an existing same-campaign receipt server-side.
  /// Returns 'reupload' (was rejected: continue to the normal claim),
  /// 'replace' (was approved: scan replaced, claim kept, stop here),
  /// 'create' (no doc: create normally) or null on failure.
  static Future<String?> replaceReceipt({
    required String campaignId,
    required String receiptNumber,
    required Map<String, dynamic> receipt,
  }) async {
    final payload = Map<String, dynamic>.from(receipt)
      ..removeWhere((k, v) => v is FieldValue);
    try {
      final res = await scopedFunctions()
          .httpsCallable('replaceReceipt',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
          .call<dynamic>({
        'campaignId': campaignId,
        'receiptNumber': normalizeReceiptNumber(receiptNumber),
        'receipt': payload,
      });
      final data = res.data;
      final mode = data is Map ? data['mode']?.toString() : null;
      return (mode == 'reupload' || mode == 'replace' || mode == 'create') ? mode : null;
    } on FirebaseFunctionsException catch (e) {
      // 2.0.152: approved receipt is locked for non-admins.
      if (isLockedError(e.code, e.details)) return 'locked';
      debugPrint('replaceReceipt failed: ${e.code}');
      return null;
    } catch (e) {
      debugPrint('replaceReceipt failed: $e');
      return null;
    }
  }

  /// 2.0.152: true for the server's "approved receipt is locked" error.
  static bool isLockedError(String code, Object? details) =>
      code == 'failed-precondition' && details is Map && details['locked'] == true;

  /// 2.0.152: shown when a non-admin re-uploads an approved receipt.
  static String lockedMessage(String receiptNumber) =>
      'الفاتورة دي اتعمدت قبل كده (رقم ${normalizeReceiptNumber(receiptNumber)}). لا يمكن رفعها أو استبدالها مرة أخرى.';

  /// Friendly message for an already-used receipt (no other users' data shown).
  static String duplicateMessage(String receiptNumber, {bool isMultiScan = false}) {
    final n = normalizeReceiptNumber(receiptNumber);
    return isMultiScan
        ? 'الفاتورة رقم ($n) مسجلة بالنظام ومصروفة مسبقاً في عروض الشركة. لا يمكن إعادة صرف الفاتورة في وضع الفحص المتوازي.'
        : 'الفاتورة رقم ($n) مسجلة بالنظام ومستخدمة مسبقاً في هذا العرض. لا يمكن استخدام نفس الفاتورة للمطالبة بهدايا مرة أخرى.';
  }

  /// True when a Firestore write failed because the deterministic receipt doc
  /// already exists (rules allow create only, so re-creating is denied).
  static bool isDuplicateWriteDenied(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('permission-denied') || s.contains('permission_denied') ||
        s.contains('missing or insufficient permissions');
  }
}

/// Human label for a receipt status from the server ("accepted", "claimed", ...).
String receiptStatusLabel(String status, {bool isAr = true}) {
  switch (status.trim().toLowerCase()) {
    case 'claimed':
      return isAr ? 'تم صرف الهدية' : 'Gift handed over';
    case 'accepted':
      return isAr ? 'مقبولة' : 'Accepted';
    case 'rejected':
      return isAr ? 'مرفوضة' : 'Rejected';
    case 'pending':
      return isAr ? 'قيد المراجعة' : 'Pending';
    default:
      return status;
  }
}
