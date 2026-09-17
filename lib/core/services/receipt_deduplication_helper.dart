import 'package:cloud_firestore/cloud_firestore.dart';
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
  }) async {
    final cleanNumber = normalizeReceiptNumber(receiptNumber);
    if (cleanNumber.isEmpty) {
      return ReceiptDuplicateCheckResult.notDuplicate;
    }

    try {
      // 1. Direct deterministic document lookup if campaignId is known
      if (campaignId != null && campaignId.isNotEmpty) {
        final deterministicId = getDeterministicDocId(
          campaignId: campaignId,
          receiptNumber: cleanNumber,
        );
        final directDoc = await firestore
            .collection('receipts_transactions')
            .doc(deterministicId)
            .get();

        if (directDoc.exists && directDoc.data() != null) {
          final data = directDoc.data()!;
          if (isTransactionClaimed(data)) {
            final prizeDesc = data['prize_won'] ?? 'هدية/قسيمة معتمدة';
            final dateStr = data['receipt_date'] ?? '';
            return ReceiptDuplicateCheckResult(
              isDuplicate: true,
              receiptNumber: cleanNumber,
              existingCampaignId: data['campaignId'] ?? campaignId,
              existingCampaignName: data['targetCompany'] ?? '',
              existingPrizeWon: prizeDesc.toString(),
              existingClaimedAt: data['claimed_at']?.toString(),
              existingStoreChain: data['store_chain_detected']?.toString(),
              existingBranch: data['branch_detected']?.toString(),
              rejectionMessage: 'الفاتورة رقم ($cleanNumber) مسجلة بالنظام ومصروفة مسبقاً في هذه الحملة (الجائزة: $prizeDesc${dateStr.isNotEmpty ? ' - تاريخ البون: $dateStr' : ''}). لا يمكن تكرار استخدام الفاتورة لنفس العرض.',
              existingData: data,
            );
          }
        }
      }

      // 2. Query Firestore by receipt_number
      final snapshot = await firestore
          .collection('receipts_transactions')
          .where('receipt_number', isEqualTo: cleanNumber)
          .limit(10)
          .get();

      if (snapshot.docs.isEmpty) {
        return ReceiptDuplicateCheckResult.notDuplicate;
      }

      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (!isTransactionClaimed(data)) {
          continue; // Skip rejected or unfulfilled receipts
        }

        final docCampaignId = data['campaignId']?.toString();
        final docCompanySlug = data['companySlug']?.toString();
        final isMultiBundle = data['is_multi_campaign_bundle'] == true || data['bundle_group_id'] != null;

        // Condition A: In Multi-Scan mode, any claimed receipt under this company or multi-bundle is rejected
        if (isMultiScan) {
          if (docCompanySlug == companySlug || isMultiBundle) {
            final prizeDesc = data['prize_won'] ?? 'قسائم/هدايا معتمدة';
            final dateStr = data['receipt_date'] ?? '';
            return ReceiptDuplicateCheckResult(
              isDuplicate: true,
              receiptNumber: cleanNumber,
              existingCampaignId: docCampaignId,
              existingCampaignName: data['targetCompany'] ?? '',
              existingPrizeWon: prizeDesc.toString(),
              existingClaimedAt: data['claimed_at']?.toString(),
              existingStoreChain: data['store_chain_detected']?.toString(),
              existingBranch: data['branch_detected']?.toString(),
              rejectionMessage: 'الفاتورة رقم ($cleanNumber) مسجلة بالنظام ومصروفة مسبقاً في عروض الشركة (الجائزة: $prizeDesc${dateStr.isNotEmpty ? ' - تاريخ البون: $dateStr' : ''}). لا يمكن إعادة صرف الفاتورة في وضع الفحص المتوازي.',
              existingData: data,
            );
          }
        }

        // Condition B: In Single-Scan mode, match specific campaign or multi-bundle
        if (campaignId != null && campaignId.isNotEmpty) {
          if (docCampaignId == campaignId || (isMultiBundle && docCompanySlug == companySlug)) {
            final prizeDesc = data['prize_won'] ?? 'هدية/قسيمة معتمدة';
            final dateStr = data['receipt_date'] ?? '';
            return ReceiptDuplicateCheckResult(
              isDuplicate: true,
              receiptNumber: cleanNumber,
              existingCampaignId: docCampaignId,
              existingCampaignName: data['targetCompany'] ?? '',
              existingPrizeWon: prizeDesc.toString(),
              existingClaimedAt: data['claimed_at']?.toString(),
              existingStoreChain: data['store_chain_detected']?.toString(),
              existingBranch: data['branch_detected']?.toString(),
              rejectionMessage: 'الفاتورة رقم ($cleanNumber) مسجلة بالنظام ومصروفة مسبقاً (الجائزة: $prizeDesc${dateStr.isNotEmpty ? ' - تاريخ البون: $dateStr' : ''}). لا يمكن استخدام نفس الفاتورة للمطالبة بهدايا مرة أخرى.',
              existingData: data,
            );
          }
        }
      }

      return ReceiptDuplicateCheckResult.notDuplicate;
    } catch (e) {
      debugPrint('Receipt duplicate check notice: $e');
      return ReceiptDuplicateCheckResult.notDuplicate;
    }
  }
}
