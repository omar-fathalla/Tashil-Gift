import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' as intl;

import '../../../core/services/firebase_service.dart';
import 'whatsapp_gateway_config_model.dart';
import 'whatsapp_gateway_service.dart';

/// Riverpod provider for WhatsAppWinnerNotificationService
final whatsappWinnerNotificationServiceProvider =
    Provider<WhatsAppWinnerNotificationService>((ref) => WhatsAppWinnerNotificationService(ref));

/// Automated service for dispatching personalized celebratory WhatsApp messages
/// to winning shoppers upon receipt verification and gift handover.
class WhatsAppWinnerNotificationService {
  final Ref _ref;

  WhatsAppWinnerNotificationService(this._ref);

  /// Builds a personalized, celebratory winner notification text
  static String buildWinnerMessage({
    required WhatsAppGatewayConfigModel config,
    required String prizeName,
    String? customerName,
    String? retailChain,
    String? branchName,
    String? companyName,
    String? campaignName,
    List<String> voucherSerials = const [],
    String? receiptNumber,
    DateTime? claimDate,
  }) {
    final effectiveName = (customerName != null && customerName.trim().isNotEmpty)
        ? customerName.trim()
        : 'عميلنا العزيز';
    final effectiveRetailChain = (retailChain != null && retailChain.trim().isNotEmpty)
        ? retailChain.trim()
        : 'المتجر';
    final effectiveBranch = (branchName != null && branchName.trim().isNotEmpty)
        ? branchName.trim()
        : '';
    final effectiveCompany = (companyName != null && companyName.trim().isNotEmpty)
        ? companyName.trim()
        : 'إدارة العروض الترويجية';
    final effectiveCampaign = (campaignName != null && campaignName.trim().isNotEmpty)
        ? campaignName.trim()
        : 'حملة الهدايا الفورية';
    final effectiveReceiptNumber = (receiptNumber != null && receiptNumber.trim().isNotEmpty)
        ? receiptNumber.trim()
        : 'بون الشراء المعتمد';

    final effectiveDate = claimDate ?? DateTime.now();
    String dateStr;
    try {
      dateStr = intl.DateFormat('yyyy/MM/dd - hh:mm a', 'ar').format(effectiveDate);
    } catch (_) {
      dateStr = intl.DateFormat('yyyy/MM/dd - hh:mm a').format(effectiveDate);
    }

    String voucherDetails = '';
    if (voucherSerials.isNotEmpty) {
      final serialsStr = voucherSerials.join(' ، ');
      voucherDetails = '🎟️ كود الفواتشر / الرقم التسلسلي: $serialsStr\n';
    }

    var template = config.winnerNotificationTemplate.trim().isNotEmpty
        ? config.winnerNotificationTemplate
        : WhatsAppGatewayConfigModel.defaultWinnerTemplate;

    return template
        .replaceAll('{customer_name}', effectiveName)
        .replaceAll('{retail_chain}', effectiveRetailChain)
        .replaceAll('{branch_name}', effectiveBranch)
        .replaceAll('{company_name}', effectiveCompany)
        .replaceAll('{campaign_name}', effectiveCampaign)
        .replaceAll('{prize_name}', prizeName.trim())
        .replaceAll('{voucher_details}', voucherDetails)
        .replaceAll('{voucher_code}', voucherSerials.isNotEmpty ? voucherSerials.first : '')
        .replaceAll('{receipt_number}', effectiveReceiptNumber)
        .replaceAll('{claim_date}', dateStr);
  }

  /// Sends a celebratory WhatsApp notification to a winner upon gift handover
  Future<WhatsAppGatewayResult?> sendWinnerNotification({
    required String toPhone,
    required String prizeName,
    String? customerName,
    String? retailChain,
    String? branchName,
    String? companyName,
    String? campaignName,
    List<String> voucherSerials = const [],
    String? receiptNumber,
    String? transactionId,
    String? companySlug,
    DateTime? claimDate,
    bool isEnabledForCampaign = true,
    http.Client? client,
  }) async {
    if (!isEnabledForCampaign) {
      debugPrint('WhatsApp winner notification skipped: Campaign has disabled WhatsApp winner notifications');
      return null;
    }

    final cleanPhone = WhatsAppGatewayService.formatInternationalPhone(toPhone);
    if (cleanPhone.isEmpty) {
      debugPrint('WhatsApp winner notification skipped: Empty or invalid phone "$toPhone"');
      return null;
    }

    try {
      final gatewayService = _ref.read(whatsappGatewayServiceProvider);
      final config = await gatewayService.loadConfig(companySlug: companySlug);

      if (!config.isEnabled || !config.autoNotifyWinnersOnGiftHandover) {
        debugPrint('WhatsApp winner notification skipped: Gateway disabled or autoNotifyWinners disabled');
        return null;
      }

      final messageText = buildWinnerMessage(
        config: config,
        prizeName: prizeName,
        customerName: customerName,
        retailChain: retailChain,
        branchName: branchName,
        companyName: companyName,
        campaignName: campaignName,
        voucherSerials: voucherSerials,
        receiptNumber: receiptNumber,
        claimDate: claimDate,
      );

      debugPrint('🚀 Dispatching WhatsApp winner notification to $cleanPhone ($prizeName)...');
      final result = await gatewayService.sendSingleMessage(
        config: config,
        toPhone: cleanPhone,
        messageText: messageText,
        client: client,
      );

      if (result.isSuccess) {
        debugPrint('✅ WhatsApp winner notification sent successfully to $cleanPhone! MessageId: ${result.messageId}');

        // Asynchronously update receipts_transactions record in Firestore
        if (transactionId != null && transactionId.isNotEmpty) {
          try {
            final firestore = _ref.read(firestoreProvider);
            await firestore.collection('receipts_transactions').doc(transactionId).set({
              'whatsapp_notification_sent': true,
              'whatsapp_sent_at': FieldValue.serverTimestamp(),
              if (result.messageId != null) 'whatsapp_message_id': result.messageId,
              'whatsapp_recipient_phone': cleanPhone,
            }, SetOptions(merge: true));
          } catch (e) {
            debugPrint('Error updating receipts_transactions with WhatsApp dispatch status: $e');
          }
        }
      } else {
        debugPrint('⚠️ WhatsApp winner notification delivery failed for $cleanPhone: ${result.error}');
      }

      return result;
    } catch (e) {
      debugPrint('Error in WhatsAppWinnerNotificationService.sendWinnerNotification: $e');
      return WhatsAppGatewayResult.failure(error: e.toString());
    }
  }
}
