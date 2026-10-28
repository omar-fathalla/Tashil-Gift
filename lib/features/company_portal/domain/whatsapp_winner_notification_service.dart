import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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

      return result.withPhone(toPhone.trim().isNotEmpty ? toPhone.trim() : cleanPhone);
    } catch (e) {
      debugPrint('Error in WhatsAppWinnerNotificationService.sendWinnerNotification: $e');
      return WhatsAppGatewayResult.failure(
        error: e.toString(),
        recipientPhone: toPhone.trim(),
      );
    }
  }

  /// Resolves transaction & campaign metadata from Firestore (when not already provided)
  /// and dispatches the celebratory WhatsApp winner notification across any game type
  /// (directGift, wheel, chooseGift, scratch).
  Future<WhatsAppGatewayResult?> dispatchForTransaction({
    required String transactionId,
    required String eventId,
    required String prizeName,
    String? customerPhone,
    String? customerName,
    String? retailChain,
    String? branchName,
    String? companyName,
    String? campaignName,
    String? companySlug,
    String? receiptNumber,
    List<String> voucherSerials = const [],
    bool? isEnabledForCampaign,
    http.Client? client,
  }) async {
    // Real receipts: the server builds and sends the message from the stored receipt
    // (works for anonymous reps; once per receipt; WAHA key stays server-side).
    if (transactionId.trim().isNotEmpty && client == null) {
      if (isEnabledForCampaign == false) return null;
      final server = await sendViaServer(transactionId: transactionId.trim(), fallbackPhone: customerPhone);
      if (server.handled) return server.result;
      // Non-WAHA gateway (e.g. Green API / Whapi): keep the existing client path below.
    }
    try {
      String phone = (customerPhone ?? '').trim();
      String name = (customerName ?? '').trim();
      String chain = (retailChain ?? '').trim();
      String branch = (branchName ?? '').trim();
      String company = (companyName ?? '').trim();
      String campaign = (campaignName ?? '').trim();
      String receipt = (receiptNumber ?? '').trim();
      String slug = (companySlug ?? '').trim();
      String effectiveEventId = eventId.trim();
      bool? enabled = isEnabledForCampaign;

      final firestore = _ref.read(firestoreProvider);

      // 1. Resolve missing customer/receipt details from receipts_transactions
      if (transactionId.trim().isNotEmpty &&
          (phone.isEmpty ||
              name.isEmpty ||
              chain.isEmpty ||
              branch.isEmpty ||
              company.isEmpty ||
              receipt.isEmpty ||
              slug.isEmpty ||
              effectiveEventId.isEmpty)) {
        final txDoc = await firestore.collection('receipts_transactions').doc(transactionId.trim()).get();
        if (txDoc.exists) {
          final data = txDoc.data() ?? {};
          if (phone.isEmpty) {
            phone = (data['customerPhone'] ?? data['customer_phone'] ?? data['phone'] ?? '').toString().trim();
          }
          if (name.isEmpty) {
            name = (data['customerName'] ?? data['customer_name'] ?? '').toString().trim();
          }
          if (chain.isEmpty) {
            chain = (data['retail_chain_name'] ?? data['store_chain_detected'] ?? '').toString().trim();
          }
          if (branch.isEmpty) {
            branch = (data['canonical_branch'] ?? data['branch_detected'] ?? '').toString().trim();
          }
          if (company.isEmpty) {
            company = (data['targetCompany'] ?? '').toString().trim();
          }
          if (receipt.isEmpty) {
            receipt = (data['receipt_number'] ?? data['receiptNumber'] ?? '').toString().trim();
          }
          if (slug.isEmpty) {
            slug = (data['companySlug'] ?? '').toString().trim();
          }
          if (effectiveEventId.isEmpty) {
            effectiveEventId = (data['campaignId'] ?? data['event_id'] ?? '').toString().trim();
          }
        }
      }

      // 2. Resolve campaign title and WhatsApp toggle from events collection
      if (effectiveEventId.isNotEmpty &&
          (enabled == null || campaign.isEmpty || company.isEmpty || chain.isEmpty || slug.isEmpty)) {
        final eventDoc = await firestore.collection('events').doc(effectiveEventId).get();
        if (eventDoc.exists) {
          final eventData = eventDoc.data() ?? {};
          enabled ??= eventData['enableWhatsAppWinnerNotification'] != false &&
              eventData['enable_whatsapp_winner_notification'] != false;
          if (campaign.isEmpty) {
            campaign = (eventData['title'] ?? eventData['name'] ?? '').toString().trim();
          }
          if (company.isEmpty) {
            company = (eventData['targetCompany'] ?? '').toString().trim();
          }
          if (chain.isEmpty) {
            chain = (eventData['retailChainName'] ?? '').toString().trim();
          }
          if (slug.isEmpty) {
            slug = (eventData['companySlug'] ?? '').toString().trim();
          }
        }
      }

      if (enabled == false) {
        debugPrint('WhatsApp winner notification skipped: Disabled for campaign $effectiveEventId');
        return null;
      }

      if (phone.isEmpty) {
        debugPrint('WhatsApp winner notification skipped: No customer phone on transaction $transactionId');
        return null;
      }

      return await sendWinnerNotification(
        toPhone: phone,
        prizeName: prizeName,
        customerName: name,
        retailChain: chain,
        branchName: branch,
        companyName: company,
        campaignName: campaign,
        voucherSerials: voucherSerials,
        receiptNumber: receipt,
        transactionId: transactionId,
        companySlug: slug.isNotEmpty ? slug : null,
        isEnabledForCampaign: enabled ?? true,
        client: client,
      );
    } catch (e) {
      debugPrint('Error in WhatsAppWinnerNotificationService.dispatchForTransaction: $e');
      return WhatsAppGatewayResult.failure(error: e.toString());
    }
  }

  /// Calls the `sendWinnerWhatsApp` callable (handled=false => use the legacy client gateway) for an accepted, handed-over receipt.
  Future<({bool handled, WhatsAppGatewayResult? result})> sendViaServer({required String transactionId, String? fallbackPhone}) async {
    final phone = (fallbackPhone ?? '').trim();
    try {
      final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('sendWinnerWhatsApp', options: HttpsCallableOptions(timeout: const Duration(seconds: 40)))
          .call<Map<String, dynamic>>({'receiptId': transactionId});
      final data = Map<String, dynamic>.from(res.data as Map);
      final recipient = (data['recipientPhone'] ?? phone).toString();
      if (data['sent'] == true || data['alreadySent'] == true) {
        return (handled: true, result: WhatsAppGatewayResult.success(messageId: data['messageId']?.toString(), recipientPhone: recipient));
      }
      final reason = (data['reason'] ?? '').toString();
      // Nothing to send (disabled / no phone / provider handled elsewhere / in progress): no failure notice.
      if (reason == 'provider-not-supported') return (handled: false, result: null);
      if (reason.startsWith('disabled') || reason == 'no-phone' || reason == 'in-progress') {
        return (handled: true, result: null);
      }
      return (handled: true, result: WhatsAppGatewayResult.failure(error: reason, statusCode: reason == 'not-on-whatsapp' ? 404 : 502, recipientPhone: recipient));
    } catch (e) {
      debugPrint('sendWinnerWhatsApp failed: $e');
      return (handled: true, result: WhatsAppGatewayResult.failure(error: e.toString(), statusCode: 500, recipientPhone: phone));
    }
  }
}
