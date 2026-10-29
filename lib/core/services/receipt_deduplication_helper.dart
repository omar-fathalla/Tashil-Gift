import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

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
      final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
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
        rejectionMessage: duplicateMessage(cleanNumber, isMultiScan: isMultiScan),
      );
    } catch (e) {
      debugPrint('Receipt duplicate check unavailable (treated as unknown): $e');
      return ReceiptDuplicateCheckResult.notDuplicate;
    }
  }

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
