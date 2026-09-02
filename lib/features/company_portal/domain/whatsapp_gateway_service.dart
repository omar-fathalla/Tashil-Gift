import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/arabic_numbers_utils.dart';
import '../presentation/widgets/whatsapp_campaign_dispatcher_dialog.dart';
import 'whatsapp_gateway_config_model.dart';

/// Result of a single WhatsApp Gateway dispatch operation
class WhatsAppGatewayResult {
  final bool isSuccess;
  final String? messageId;
  final String? error;
  final int statusCode;

  const WhatsAppGatewayResult({
    required this.isSuccess,
    this.messageId,
    this.error,
    this.statusCode = 200,
  });

  factory WhatsAppGatewayResult.success({String? messageId, int statusCode = 200}) {
    return WhatsAppGatewayResult(isSuccess: true, messageId: messageId, statusCode: statusCode);
  }

  factory WhatsAppGatewayResult.failure({required String error, int statusCode = 400}) {
    return WhatsAppGatewayResult(isSuccess: false, error: error, statusCode: statusCode);
  }
}

/// Status of connection to WhatsApp Gateway
class WhatsAppGatewayConnectionStatus {
  final bool isConnected;
  final String? phoneNumber;
  final String? instanceStatus;
  final String? statusDetails;

  const WhatsAppGatewayConnectionStatus({
    required this.isConnected,
    this.phoneNumber,
    this.instanceStatus,
    this.statusDetails,
  });
}

/// Core Service for WhatsApp Gateway API Operations, Anti-Spam Pacing, and Batch Dispatching
class WhatsAppGatewayService {
  static const String _prefsKeyPrefix = 'whatsapp_gateway_config_';

  /// Normalizes and formats raw phone numbers into standard international digits without '+'
  /// (e.g. Egypt 01012345678 -> 201012345678, +2011... -> 2011...)
  static String formatInternationalPhone(String rawPhone) {
    if (rawPhone.trim().isEmpty) return '';

    // Normalize Arabic/Persian digits to Western
    String clean = rawPhone.toEnglishDigits().trim();

    // Strip any non-digit character (spaces, dashes, parens, plus)
    clean = clean.replaceAll(RegExp(r'\D'), '');

    if (clean.startsWith('+')) {
      clean = clean.substring(1);
    }
    if (clean.startsWith('00')) {
      clean = clean.substring(2);
    }

    // 3. Handle Egyptian mobile numbers starting with '01' (010, 011, 012, 015)
    if (clean.startsWith('01') && clean.length == 11) {
      clean = '2$clean';
    }

    return clean;
  }

  /// Loads configuration from Local Storage with Firestore fallback
  Future<WhatsAppGatewayConfigModel> loadConfig({String? companySlug}) async {
    try {
      final key = '$_prefsKeyPrefix${companySlug ?? "global"}';
      final prefs = await SharedPreferences.getInstance();
      final localJson = prefs.getString(key);

      if (localJson != null && localJson.isNotEmpty) {
        return WhatsAppGatewayConfigModel.fromJson(localJson);
      }

      // Fallback: Check Firestore company document
      if (companySlug != null && companySlug.isNotEmpty) {
        final doc = await FirebaseFirestore.instance.collection('companies').doc(companySlug).get();
        if (doc.exists && doc.data() != null && doc.data()!.containsKey('whatsappGatewayConfig')) {
          final configMap = doc.data()!['whatsappGatewayConfig'] as Map<String, dynamic>?;
          if (configMap != null) {
            final config = WhatsAppGatewayConfigModel.fromMap(configMap);
            // Cache locally
            await prefs.setString(key, config.toJson());
            return config;
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading WhatsApp gateway config: $e');
    }
    return const WhatsAppGatewayConfigModel(
      provider: WhatsAppGatewayProvider.ultraMsg,
      instanceId: 'instance190005',
      apiToken: 'v699gpqwmv242cgq',
      delayBetweenMessagesSeconds: 3,
      isEnabled: true,
    );
  }

  /// Saves configuration to Local Storage and Firestore
  Future<bool> saveConfig(WhatsAppGatewayConfigModel config, {String? companySlug}) async {
    try {
      final key = '$_prefsKeyPrefix${companySlug ?? "global"}';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, config.toJson());

      // Save to Firestore company document for persistence across team members
      if (companySlug != null && companySlug.isNotEmpty) {
        await FirebaseFirestore.instance.collection('companies').doc(companySlug).set({
          'whatsappGatewayConfig': config.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      return true;
    } catch (e) {
      debugPrint('Error saving WhatsApp gateway config: $e');
      return false;
    }
  }

  /// Tests connection to the gateway instance and returns connection status
  Future<WhatsAppGatewayConnectionStatus> testConnection(
    WhatsAppGatewayConfigModel config, {
    http.Client? client,
  }) async {
    if (!config.isConfigured) {
      return const WhatsAppGatewayConnectionStatus(
        isConnected: false,
        statusDetails: 'بيانات الاتصال غير مكتملة (Instance ID أو Token مفقود)',
      );
    }

    final httpClient = client ?? http.Client();
    try {
      switch (config.provider) {
        case WhatsAppGatewayProvider.ultraMsg:
          final instance = config.instanceId.trim();
          final token = config.apiToken.trim();
          final statusUrl = Uri.parse('https://api.ultramsg.com/$instance/instance/status?token=$token');
          final statusResponse = await httpClient.get(statusUrl).timeout(const Duration(seconds: 12));
          if (statusResponse.statusCode == 200) {
            final data = json.decode(statusResponse.body) as Map<String, dynamic>? ?? {};
            
            // UltraMsg nested structure: {"status": {"accountStatus": {"status": "authenticated", "substatus": "connected"}}}
            final statusMap = data['status'] is Map ? (data['status'] as Map<String, dynamic>) : null;
            final accountStatusMap = statusMap?['accountStatus'] is Map ? (statusMap!['accountStatus'] as Map<String, dynamic>) : null;
            final statusStr = (accountStatusMap?['status'] ?? data['status'] ?? '').toString().toLowerCase();
            final substatusStr = (accountStatusMap?['substatus'] ?? '').toString().toLowerCase();
            final isConnected = statusStr == 'authenticated' ||
                substatusStr == 'connected' ||
                statusStr.contains('authenticated') ||
                statusStr.contains('connected') ||
                data['authenticated'] == true;

            String? phone;
            String? userName;
            if (isConnected) {
              try {
                final meUrl = Uri.parse('https://api.ultramsg.com/$instance/instance/me?token=$token');
                final meRes = await httpClient.get(meUrl).timeout(const Duration(seconds: 8));
                if (meRes.statusCode == 200) {
                  final meData = json.decode(meRes.body) as Map<String, dynamic>?;
                  phone = meData?['id']?.toString().replaceAll('@c.us', '');
                  userName = meData?['name']?.toString();
                }
              } catch (_) {}
            }

            return WhatsAppGatewayConnectionStatus(
              isConnected: isConnected,
              instanceStatus: substatusStr.isNotEmpty ? substatusStr : statusStr,
              phoneNumber: phone != null && phone.isNotEmpty
                  ? '+$phone${userName != null && userName.isNotEmpty ? " ($userName)" : ""}'
                  : data['phone']?.toString(),
              statusDetails: isConnected ? 'متصل بنجاح وجاهز للإرسال' : 'غير متصل بالواتساب، يرجى مسح QR Code من لوحة مزود البوابة',
            );
          }
          return WhatsAppGatewayConnectionStatus(
            isConnected: false,
            statusDetails: 'فشل الاتصال: كود الرد (${statusResponse.statusCode})',
          );

        case WhatsAppGatewayProvider.greenApi:
          final url = Uri.parse('https://api.green-api.com/waInstance${config.instanceId.trim()}/getStateInstance/${config.apiToken.trim()}');
          final response = await httpClient.get(url).timeout(const Duration(seconds: 12));
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            final state = data['stateInstance']?.toString().toLowerCase() ?? '';
            final isConnected = state == 'authorized';
            return WhatsAppGatewayConnectionStatus(
              isConnected: isConnected,
              instanceStatus: state,
              statusDetails: isConnected ? 'متصل ومصرح بالكامل (Authorized)' : 'غير مصرح أو بانتظار مسح QR ($state)',
            );
          }
          return WhatsAppGatewayConnectionStatus(
            isConnected: false,
            statusDetails: 'فشل الاتصال بـ Green API: (${response.statusCode})',
          );

        case WhatsAppGatewayProvider.whapi:
          final url = Uri.parse('https://gate.whapi.cloud/health');
          final response = await httpClient.get(
            url,
            headers: {'Authorization': 'Bearer ${config.apiToken.trim()}'},
          ).timeout(const Duration(seconds: 12));
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            final isConnected = data['status']?.toString().toLowerCase() == 'ok' || data['user'] != null;
            return WhatsAppGatewayConnectionStatus(
              isConnected: isConnected,
              instanceStatus: data['status']?.toString(),
              phoneNumber: data['user']?['id']?.toString(),
              statusDetails: isConnected ? 'متصل بنجاح (Whapi Online)' : 'حالة الجلسة غير متصلة',
            );
          }
          return WhatsAppGatewayConnectionStatus(
            isConnected: false,
            statusDetails: 'فشل الاتصال بـ Whapi: (${response.statusCode})',
          );

        case WhatsAppGatewayProvider.custom:
          final endpoint = config.customEndpointUrl.trim();
          final url = Uri.parse(endpoint.endsWith('/status') ? endpoint : '$endpoint/status');
          final response = await httpClient.get(
            url,
            headers: config.apiToken.isNotEmpty ? {'Authorization': 'Bearer ${config.apiToken.trim()}'} : {},
          ).timeout(const Duration(seconds: 12));
          final isOk = response.statusCode >= 200 && response.statusCode < 300;
          return WhatsAppGatewayConnectionStatus(
            isConnected: isOk,
            statusDetails: isOk ? 'تم الاتصال بالسيرفر المخصص بنجاح' : 'السيرفر المخصص أعاد رمز خطأ (${response.statusCode})',
          );
      }
    } catch (e) {
      return WhatsAppGatewayConnectionStatus(
        isConnected: false,
        statusDetails: 'تعذر الوصول للمزود: $e',
      );
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Fetches real-time message statistics from UltraMsg / Provider
  Future<WhatsAppGatewayStats?> fetchStatistics(WhatsAppGatewayConfigModel config, {http.Client? client}) async {
    if (!config.isConfigured || config.provider != WhatsAppGatewayProvider.ultraMsg) {
      return null;
    }
    final httpClient = client ?? http.Client();
    try {
      final url = 'https://api.ultramsg.com/${config.instanceId.trim()}/messages/statistics?token=${config.apiToken.trim()}';
      final response = await httpClient.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>? ?? {};
        final statsMap = data['messages_statistics'] is Map
            ? (data['messages_statistics'] as Map<String, dynamic>)
            : data;
        return WhatsAppGatewayStats(
          sentCount: (statsMap['sent'] as num?)?.toInt() ?? 0,
          queueCount: (statsMap['queue'] as num?)?.toInt() ?? 0,
          unsentCount: (statsMap['unsent'] as num?)?.toInt() ?? 0,
          invalidCount: (statsMap['invalid'] as num?)?.toInt() ?? 0,
          expiredCount: (statsMap['expired'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (e) {
      debugPrint('Error fetching WhatsApp gateway statistics: $e');
    } finally {
      if (client == null) httpClient.close();
    }
    return null;
  }

  /// Fetches paginated list of live outbox messages from UltraMsg
  Future<WhatsAppOutboxPageResult> fetchMessagesList({
    required WhatsAppGatewayConfigModel config,
    String status = 'all',
    int page = 1,
    int limit = 20,
    http.Client? client,
  }) async {
    if (!config.isConfigured || config.provider != WhatsAppGatewayProvider.ultraMsg) {
      return const WhatsAppOutboxPageResult();
    }
    final httpClient = client ?? http.Client();
    try {
      final params = {
        'token': config.apiToken.trim(),
        'page': page.toString(),
        'limit': limit.toString(),
        'status': status,
        'sort': 'desc',
      };
      final uri = Uri.https(
        'api.ultramsg.com',
        '/${config.instanceId.trim()}/messages',
        params,
      );
      final response = await httpClient.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>? ?? {};
        final rawMessages = data['messages'] as List? ?? [];
        final messages = rawMessages
            .map((m) {
              if (m is Map<String, dynamic>) {
                return WhatsAppOutboxMessage.fromUltraMsgJson(m);
              }
              if (m is Map) {
                return WhatsAppOutboxMessage.fromUltraMsgJson(Map<String, dynamic>.from(m));
              }
              return null;
            })
            .whereType<WhatsAppOutboxMessage>()
            .toList();

        return WhatsAppOutboxPageResult(
          total: (data['total'] as num?)?.toInt() ?? messages.length,
          totalPages: (data['pages'] as num?)?.toInt() ?? 1,
          page: (data['page'] as num?)?.toInt() ?? page,
          limit: (data['limit'] as num?)?.toInt() ?? limit,
          messages: messages,
        );
      }
    } catch (e) {
      debugPrint('Error fetching WhatsApp messages list: $e');
    } finally {
      if (client == null) httpClient.close();
    }
    return const WhatsAppOutboxPageResult();
  }

  /// Triggers a remote restart of the WhatsApp gateway instance
  Future<bool> restartInstance(WhatsAppGatewayConfigModel config, {http.Client? client}) async {
    if (!config.isConfigured || config.provider != WhatsAppGatewayProvider.ultraMsg) {
      return false;
    }
    final httpClient = client ?? http.Client();
    try {
      final url = 'https://api.ultramsg.com/${config.instanceId.trim()}/instance/restart';
      final response = await httpClient.post(
        Uri.parse(url),
        body: {'token': config.apiToken.trim()},
      ).timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error restarting WhatsApp gateway instance: $e');
      return false;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Triggers a remote logout of the WhatsApp gateway instance
  Future<bool> logoutInstance(WhatsAppGatewayConfigModel config, {http.Client? client}) async {
    if (!config.isConfigured || config.provider != WhatsAppGatewayProvider.ultraMsg) {
      return false;
    }
    final httpClient = client ?? http.Client();
    try {
      final url = 'https://api.ultramsg.com/${config.instanceId.trim()}/instance/logout';
      final response = await httpClient.post(
        Uri.parse(url),
        body: {'token': config.apiToken.trim()},
      ).timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error logging out WhatsApp gateway instance: $e');
      return false;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Sends a single message to a phone number via the configured gateway
  Future<WhatsAppGatewayResult> sendSingleMessage({
    required WhatsAppGatewayConfigModel config,
    required String toPhone,
    required String messageText,
    http.Client? client,
  }) async {
    final cleanPhone = formatInternationalPhone(toPhone);
    if (cleanPhone.isEmpty || cleanPhone.length < 9) {
      return WhatsAppGatewayResult.failure(error: 'رقم الهاتف غير صالح: $toPhone');
    }

    if (!config.isConfigured) {
      return WhatsAppGatewayResult.failure(error: 'بوابة الواتساب غير مضبوطة، يرجى ضبط الإعدادات أولاً');
    }

    final httpClient = client ?? http.Client();
    try {
      switch (config.provider) {
        case WhatsAppGatewayProvider.ultraMsg:
          final url = Uri.parse('https://api.ultramsg.com/${config.instanceId.trim()}/messages/chat');
          final response = await httpClient.post(
            url,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'token': config.apiToken.trim(),
              'to': cleanPhone,
              'body': messageText,
            },
          ).timeout(const Duration(seconds: 15));

          if (response.statusCode >= 200 && response.statusCode < 300) {
            final data = json.decode(response.body);
            if (data['error'] != null) {
              return WhatsAppGatewayResult.failure(error: data['error']?.toString() ?? 'خطأ غير معروف من UltraMsg', statusCode: response.statusCode);
            }
            return WhatsAppGatewayResult.success(messageId: data['id']?.toString(), statusCode: response.statusCode);
          }
          return WhatsAppGatewayResult.failure(error: 'خطأ إرسال UltraMsg (${response.statusCode}): ${response.body}', statusCode: response.statusCode);

        case WhatsAppGatewayProvider.greenApi:
          final url = Uri.parse('https://api.green-api.com/waInstance${config.instanceId.trim()}/sendMessage/${config.apiToken.trim()}');
          final response = await httpClient.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'chatId': '$cleanPhone@c.us',
              'message': messageText,
            }),
          ).timeout(const Duration(seconds: 15));

          if (response.statusCode >= 200 && response.statusCode < 300) {
            final data = json.decode(response.body);
            return WhatsAppGatewayResult.success(messageId: data['idMessage']?.toString(), statusCode: response.statusCode);
          }
          return WhatsAppGatewayResult.failure(error: 'خطأ إرسال Green API (${response.statusCode}): ${response.body}', statusCode: response.statusCode);

        case WhatsAppGatewayProvider.whapi:
          final url = Uri.parse('https://gate.whapi.cloud/messages/text');
          final response = await httpClient.post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${config.apiToken.trim()}',
            },
            body: json.encode({
              'to': '$cleanPhone@s.whatsapp.net',
              'body': messageText,
            }),
          ).timeout(const Duration(seconds: 15));

          if (response.statusCode >= 200 && response.statusCode < 300) {
            final data = json.decode(response.body);
            return WhatsAppGatewayResult.success(messageId: data['message']?['id']?.toString(), statusCode: response.statusCode);
          }
          return WhatsAppGatewayResult.failure(error: 'خطأ إرسال Whapi (${response.statusCode}): ${response.body}', statusCode: response.statusCode);

        case WhatsAppGatewayProvider.custom:
          final endpoint = config.customEndpointUrl.trim();
          final url = Uri.parse(endpoint.endsWith('/send') ? endpoint : '$endpoint/send');
          final headers = <String, String>{'Content-Type': 'application/json'};
          if (config.apiToken.isNotEmpty) {
            headers['Authorization'] = 'Bearer ${config.apiToken.trim()}';
          }
          final response = await httpClient.post(
            url,
            headers: headers,
            body: json.encode({
              'to': cleanPhone,
              'message': messageText,
            }),
          ).timeout(const Duration(seconds: 15));

          if (response.statusCode >= 200 && response.statusCode < 300) {
            return WhatsAppGatewayResult.success(statusCode: response.statusCode);
          }
          return WhatsAppGatewayResult.failure(error: 'خطأ إرسال السيرفر المخصص (${response.statusCode}): ${response.body}', statusCode: response.statusCode);
      }
    } catch (e) {
      return WhatsAppGatewayResult.failure(error: 'فشل الاتصال: $e');
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Replaces smart tags inside a template with actual customer data
  static String buildPersonalizedMessage({
    required String template,
    required CustomerCampaignContact contact,
    required String companyName,
    required String campaignName,
  }) {
    final customerName = contact.name.isNotEmpty ? contact.name : 'عميلنا العزيز';
    final branchName = contact.lastBranch.isNotEmpty ? contact.lastBranch : (contact.branches.isNotEmpty ? contact.branches.first : 'أقرب فرع');
    final giftsText = contact.isWinner ? contact.prizesWon.join(', ') : 'هدايا وقسائم تسوق فورية';

    return template
        .replaceAll('{اسم_العميل}', customerName)
        .replaceAll('{الشركة}', companyName.isNotEmpty ? companyName : 'الشركة')
        .replaceAll('{الحملة}', campaignName.isNotEmpty ? campaignName : 'الحملة')
        .replaceAll('{الفرع}', branchName)
        .replaceAll('{الهدايا}', giftsText)
        .replaceAll('{المشتريات}', '${contact.totalSpend.toStringAsFixed(0)} ج.م');
  }

  /// Dispatches a batch of messages sequentially with anti-spam pacing jitter and progress notifications
  Stream<BatchProgressEvent> sendBatchStream({
    required WhatsAppGatewayConfigModel config,
    required List<CustomerCampaignContact> contacts,
    required String template,
    required String companyName,
    required String campaignName,
    bool Function()? isCancelled,
  }) async* {
    final random = math.Random();
    int successCount = 0;
    int failureCount = 0;

    for (int i = 0; i < contacts.length; i++) {
      if (isCancelled != null && isCancelled()) {
        yield BatchProgressEvent(
          currentIndex: i,
          totalContacts: contacts.length,
          successCount: successCount,
          failureCount: failureCount,
          currentContact: contacts[i],
          isCompleted: false,
          isCancelled: true,
          statusMessage: 'تم إيقاف الإرسال بواسطة المستخدم',
        );
        break;
      }

      final contact = contacts[i];
      final personalizedMessage = buildPersonalizedMessage(
        template: template,
        contact: contact,
        companyName: companyName,
        campaignName: campaignName,
      );

      yield BatchProgressEvent(
        currentIndex: i + 1,
        totalContacts: contacts.length,
        successCount: successCount,
        failureCount: failureCount,
        currentContact: contact,
        isCompleted: false,
        statusMessage: 'جاري الإرسال للعميل: ${contact.name.isNotEmpty ? contact.name : contact.rawPhone}...',
      );

      final result = await sendSingleMessage(
        config: config,
        toPhone: contact.cleanPhone.isNotEmpty ? contact.cleanPhone : contact.rawPhone,
        messageText: personalizedMessage,
      );

      if (result.isSuccess) {
        successCount++;
        contact.status = ContactDispatchStatus.sent;
      } else {
        failureCount++;
      }

      yield BatchProgressEvent(
        currentIndex: i + 1,
        totalContacts: contacts.length,
        successCount: successCount,
        failureCount: failureCount,
        currentContact: contact,
        lastResult: result,
        isCompleted: i == contacts.length - 1,
        statusMessage: result.isSuccess
            ? 'تم إرسال الرسالة بنجاح للعميل (${i + 1}/${contacts.length})'
            : 'فشل الإرسال للعميل (${contact.rawPhone}): ${result.error}',
      );

      // Anti-Spam human pacing delay (e.g. 2500ms to 3500ms) unless it's the last item
      if (i < contacts.length - 1 && (isCancelled == null || !isCancelled())) {
        final baseDelay = config.delayBetweenMessagesSeconds * 1000;
        final jitterMs = random.nextInt(1000) - 500; // +/- 500ms jitter
        final effectiveDelayMs = math.max(1500, baseDelay + jitterMs);
        await Future.delayed(Duration(milliseconds: effectiveDelayMs));
      }
    }
  }
}

/// Progress event emitted during batch WhatsApp dispatching
class BatchProgressEvent {
  final int currentIndex;
  final int totalContacts;
  final int successCount;
  final int failureCount;
  final CustomerCampaignContact currentContact;
  final WhatsAppGatewayResult? lastResult;
  final bool isCompleted;
  final bool isCancelled;
  final String statusMessage;

  const BatchProgressEvent({
    required this.currentIndex,
    required this.totalContacts,
    required this.successCount,
    required this.failureCount,
    required this.currentContact,
    this.lastResult,
    this.isCompleted = false,
    this.isCancelled = false,
    required this.statusMessage,
  });

  double get progressFraction => totalContacts > 0 ? (currentIndex / totalContacts).clamp(0.0, 1.0) : 0.0;
}
