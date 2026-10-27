import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/arabic_numbers_utils.dart';
import '../presentation/widgets/whatsapp_campaign_dispatcher_dialog.dart';
import 'whatsapp_gateway_config_model.dart';

/// Global Riverpod Provider for WhatsAppGatewayService
final whatsappGatewayServiceProvider = Provider<WhatsAppGatewayService>((ref) => WhatsAppGatewayService());

/// Result of a single WhatsApp Gateway dispatch operation
class WhatsAppGatewayResult {
  final bool isSuccess;
  final String? messageId;
  final String? error;
  final int statusCode;
  final String? recipientPhone;

  const WhatsAppGatewayResult({
    required this.isSuccess,
    this.messageId,
    this.error,
    this.statusCode = 200,
    this.recipientPhone,
  });

  factory WhatsAppGatewayResult.success({
    String? messageId,
    int statusCode = 200,
    String? recipientPhone,
  }) {
    return WhatsAppGatewayResult(
      isSuccess: true,
      messageId: messageId,
      statusCode: statusCode,
      recipientPhone: recipientPhone,
    );
  }

  factory WhatsAppGatewayResult.failure({
    required String error,
    int statusCode = 400,
    String? recipientPhone,
  }) {
    return WhatsAppGatewayResult(
      isSuccess: false,
      error: error,
      statusCode: statusCode,
      recipientPhone: recipientPhone,
    );
  }

  WhatsAppGatewayResult withPhone(String phone) {
    return WhatsAppGatewayResult(
      isSuccess: isSuccess,
      messageId: messageId,
      error: error,
      statusCode: statusCode,
      recipientPhone: phone,
    );
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

/// Result of live screenshot capture with diagnostics
class WhatsAppScreenshotResult {
  final bool isSuccess;
  final Uint8List? bytes;
  final String? errorMessage;
  final int? statusCode;

  const WhatsAppScreenshotResult({
    required this.isSuccess,
    this.bytes,
    this.errorMessage,
    this.statusCode,
  });

  factory WhatsAppScreenshotResult.success(Uint8List bytes) => WhatsAppScreenshotResult(
        isSuccess: true,
        bytes: bytes,
        statusCode: 200,
      );

  factory WhatsAppScreenshotResult.failure({
    required String errorMessage,
    int? statusCode,
  }) =>
      WhatsAppScreenshotResult(
        isSuccess: false,
        errorMessage: errorMessage,
        statusCode: statusCode,
      );
}

/// Core Service for WhatsApp Gateway API Operations, Anti-Spam Pacing, and Batch Dispatching
class WhatsAppGatewayService {
  static const String _prefsKeyPrefix = 'whatsapp_gateway_config_';

  /// Optional override for tests. Production builds Firebase ID + App Check tokens.
  final Future<Map<String, String>> Function()? wahaAuthHeadersBuilder;

  WhatsAppGatewayService({this.wahaAuthHeadersBuilder});

  /// Auth headers required by the secured `wahaProxy` Cloud Function.
  /// Never includes WAHA's own x-api-key — that stays server-side only.
  Future<Map<String, String>> buildWahaProxyHeaders([
    Map<String, String>? extra,
  ]) async {
    if (wahaAuthHeadersBuilder != null) {
      final custom = await wahaAuthHeadersBuilder!();
      return <String, String>{...?extra, ...custom};
    }

    final headers = <String, String>{...?extra};
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError(
        'WhatsApp proxy requires a signed-in super_admin, admin, or partner account.',
      );
    }
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Failed to obtain Firebase ID token for WhatsApp proxy.');
    }
    headers['Authorization'] = 'Bearer $idToken';

    try {
      final appCheckToken = await FirebaseAppCheck.instance.getToken();
      if (appCheckToken != null && appCheckToken.isNotEmpty) {
        headers['X-Firebase-AppCheck'] = appCheckToken;
      }
    } catch (e) {
      debugPrint('App Check token unavailable for WAHA proxy: $e');
    }
    return headers;
  }

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

  /// Hosted HTTPS reverse proxy (Firebase Hosting → wahaProxy Function).
  /// The Function injects WAHA_API_KEY from Firebase Secrets; the client never needs it.
  static const String kDefaultWahaProxyBase = 'https://tashil-gift.web.app/waha';

  /// Resolves the effective API endpoint for WAHA / Gateway requests.
  /// Prefers the HTTPS Cloud proxy so the browser/app never talks to the raw HTTP WAHA host
  /// and never needs a baked-in API token.
  static String resolveEndpoint(WhatsAppGatewayConfigModel config) {
    final raw = config.customEndpointUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (kIsWeb) {
      final isHttps = Uri.base.scheme == 'https';
      if (isHttps && (raw.startsWith('http://') || raw.isEmpty)) {
        return '${Uri.base.origin}/waha';
      }
    }
    if (raw.isEmpty || raw.startsWith('http://')) {
      return kDefaultWahaProxyBase;
    }
    return raw;
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
      provider: WhatsAppGatewayProvider.waha,
      instanceId: 'default',
      apiToken: '',
      customEndpointUrl: '',
      delayBetweenMessagesSeconds: 3,
      isEnabled: true,
      isConnected: false,
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

        case WhatsAppGatewayProvider.waha:
          final endpoint = resolveEndpoint(config);
          final session = config.instanceId.trim().isEmpty ? 'default' : config.instanceId.trim();
          final url = Uri.parse('$endpoint/api/sessions/$session');
          final headers = await buildWahaProxyHeaders();
          final response = await httpClient.get(url, headers: headers).timeout(const Duration(seconds: 12));
          if (response.statusCode == 200) {
            final data = json.decode(response.body) as Map<String, dynamic>? ?? {};
            final status = data['status']?.toString().toUpperCase() ?? '';
            final isConnected = status == 'WORKING';
            final me = data['me'] as Map<String, dynamic>?;
            final rawPhone = me?['id']?.toString().replaceAll('@c.us', '') ?? '';
            final pushName = me?['pushName']?.toString() ?? '';
            final displayPhone = rawPhone.isNotEmpty
                ? '+$rawPhone${pushName.isNotEmpty ? " ($pushName)" : ""}'
                : null;
            return WhatsAppGatewayConnectionStatus(
              isConnected: isConnected,
              instanceStatus: status,
              phoneNumber: displayPhone,
              statusDetails: isConnected
                  ? 'متصل بنجاح وجاهز للإرسال (سيرفر WAHA الخاص)'
                  : 'حالة السيرفر: $status (يلزم الربط بالرمز أو QR Code)',
            );
          }
          return WhatsAppGatewayConnectionStatus(
            isConnected: false,
            statusDetails: 'فشل الاتصال بسيرفر WAHA: رمز (${response.statusCode})',
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
      final errorStr = e.toString();
      final isFetchError = errorStr.contains('Failed to fetch') || errorStr.contains('XMLHttpRequest') || errorStr.contains('ClientException');
      return WhatsAppGatewayConnectionStatus(
        isConnected: false,
        statusDetails: isFetchError
            ? 'تعذر الاتصال بالخادم (${config.customEndpointUrl.isNotEmpty ? config.customEndpointUrl : config.instanceId}): يرجى التحقق من عمل الخادم وصحة المفتاح.'
            : 'تعذر الوصول للمزود: $e',
      );
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Fetches real-time message statistics from WAHA / Gateway
  Future<WhatsAppGatewayStats?> fetchStatistics(WhatsAppGatewayConfigModel config, {http.Client? client}) async {
    if (!config.isConfigured || config.provider != WhatsAppGatewayProvider.waha) {
      return null;
    }
    final httpClient = client ?? http.Client();
    try {
      final endpoint = resolveEndpoint(config);
      final session = config.instanceId.trim().isEmpty ? 'default' : config.instanceId.trim();
      final url = Uri.parse('$endpoint/api/$session/chats?limit=100');
      final headers = await buildWahaProxyHeaders();
      final response = await httpClient.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final list = json.decode(utf8.decode(response.bodyBytes)) as List? ?? [];
        int sent = 0;
        for (final chat in list) {
          if (chat is Map && chat['lastMessage'] is Map && chat['lastMessage']['fromMe'] == true) {
            sent++;
          }
        }
        return WhatsAppGatewayStats(
          sentCount: sent,
          queueCount: 0,
          unsentCount: 0,
          invalidCount: 0,
          expiredCount: 0,
        );
      }
    } catch (e) {
      debugPrint('Error fetching WhatsApp gateway statistics: $e');
    } finally {
      if (client == null) httpClient.close();
    }
    return null;
  }

  /// Fetches paginated list of live outbox messages from WAHA
  /// Discovered and verified WhatsApp contact names cached in-memory across the session
  static final Map<String, String> _discoveredWhatsAppNames = {};

  /// Saves a discovered contact name for a given phone number
  static void saveDiscoveredContactName(String phone, String name) {
    final clean = formatInternationalPhone(phone);
    if (clean.isNotEmpty && name.trim().isNotEmpty) {
      _discoveredWhatsAppNames[clean] = name.trim();
    }
  }

  /// Retrieves a saved contact name if discovered
  static String? getDiscoveredContactName(String phone) {
    final clean = formatInternationalPhone(phone);
    return _discoveredWhatsAppNames[clean];
  }

  Future<WhatsAppOutboxPageResult> fetchMessagesList({
    required WhatsAppGatewayConfigModel config,
    String status = 'all',
    int page = 1,
    int limit = 20,
    http.Client? client,
  }) async {
    if (!config.isConfigured || config.provider != WhatsAppGatewayProvider.waha) {
      return const WhatsAppOutboxPageResult();
    }
    final httpClient = client ?? http.Client();
    try {
      final endpoint = resolveEndpoint(config);
      final session = config.instanceId.trim().isEmpty ? 'default' : config.instanceId.trim();
      final url = Uri.parse('$endpoint/api/$session/chats?limit=$limit');
      final headers = await buildWahaProxyHeaders();
      final response = await httpClient.get(url, headers: headers).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final list = json.decode(utf8.decode(response.bodyBytes)) as List? ?? [];
        final messages = <WhatsAppOutboxMessage>[];
        for (final item in list) {
          if (item is! Map) continue;
          final lastMsg = item['lastMessage'] as Map?;
          if (lastMsg == null) continue;
          final id = lastMsg['id'] is Map
              ? (lastMsg['id']['id']?.toString() ?? lastMsg['id']['_serialized']?.toString() ?? '')
              : (lastMsg['id']?.toString() ?? '');

          // Extract Chat JID details
          String chatServer = '';
          String chatUser = '';
          String chatIdSerialized = '';
          if (item['id'] is Map) {
            chatServer = (item['id']['server'] ?? '').toString();
            chatUser = (item['id']['user'] ?? '').toString();
            chatIdSerialized = (item['id']['_serialized'] ?? '').toString();
          } else if (item['id'] is String) {
            chatIdSerialized = item['id'].toString();
            final parts = chatIdSerialized.split('@');
            if (parts.length == 2) {
              chatUser = parts[0];
              chatServer = parts[1];
            } else {
              chatUser = chatIdSerialized;
            }
          }

          final isGroup = item['isGroup'] == true || chatServer == 'g.us' || chatUser.contains('-');
          final chatName = (item['name'] ?? '').toString().trim();
          final notifyName = (lastMsg['_data'] is Map ? lastMsg['_data']['notifyName'] : null)?.toString().trim() ?? '';

          String contactName = '';
          String? groupName;
          if (isGroup) {
            groupName = chatName.isNotEmpty ? chatName : 'مجموعة واتساب';
            contactName = groupName;
          } else {
            if (chatName.isNotEmpty && !chatName.startsWith('+')) {
              contactName = chatName;
            } else if (notifyName.isNotEmpty) {
              contactName = notifyName;
            } else if (chatName.isNotEmpty) {
              contactName = chatName;
            }
          }

          // Extract and normalize phone numbers
          final fromMe = lastMsg['fromMe'] == true;
          final rawTo = (lastMsg['to']?.toString() ?? '').replaceAll('@c.us', '').replaceAll('@lid', '').replaceAll('@g.us', '');
          final rawFrom = (lastMsg['from']?.toString() ?? '').replaceAll('@c.us', '').replaceAll('@lid', '').replaceAll('@g.us', '');

          String targetPhone = '';
          // 1. Check if chatName itself contains a formatted phone number (e.g. "+20 12 84814490")
          if (chatName.startsWith('+') || chatName.startsWith('01') || (chatName.length >= 10 && RegExp(r'^\+?[\d\s-]+$').hasMatch(chatName))) {
            targetPhone = formatInternationalPhone(chatName);
          }
          // 2. Check chatUser if on c.us
          if (targetPhone.isEmpty && chatServer == 'c.us' && RegExp(r'^\d+$').hasMatch(chatUser)) {
            targetPhone = chatUser;
          }
          // 3. Check from / to if ending with c.us
          if (targetPhone.isEmpty) {
            final toStr = (lastMsg['to']?.toString() ?? '');
            final fromStr = (lastMsg['from']?.toString() ?? '');
            final connectedNum = config.connectedPhoneNumber?.trim() ?? '';
            final hasConnected = connectedNum.isNotEmpty;
            if (toStr.contains('@c.us') && (!hasConnected || !toStr.contains(connectedNum))) {
              targetPhone = toStr.replaceAll('@c.us', '').replaceAll(RegExp(r'\D'), '');
            } else if (fromStr.contains('@c.us') && (!hasConnected || !fromStr.contains(connectedNum))) {
              targetPhone = fromStr.replaceAll('@c.us', '').replaceAll(RegExp(r'\D'), '');
            }
          }
          // 4. Fallback to rawTo / rawFrom
          if (targetPhone.isEmpty) {
            targetPhone = fromMe ? rawTo : rawFrom;
          }

          // Clean up if it was a group or lid without phone
          if (isGroup) {
            targetPhone = groupName ?? chatName;
          }

          // If we found a valid phone and a valid contact name, cache it!
          if (targetPhone.isNotEmpty && contactName.isNotEmpty && !contactName.startsWith('+') && !isGroup) {
            saveDiscoveredContactName(targetPhone, contactName);
          } else if (contactName.isEmpty && targetPhone.isNotEmpty) {
            contactName = getDiscoveredContactName(targetPhone) ?? '';
          }

          final body = lastMsg['body']?.toString() ?? '';
          final ts = lastMsg['timestamp'] as num?;
          final sentAt = ts != null && ts > 0 ? DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000) : null;
          final ack = lastMsg['ack']?.toString();

          messages.add(
            WhatsAppOutboxMessage(
              id: id,
              toPhone: targetPhone,
              fromPhone: rawFrom,
              contactName: contactName,
              isGroup: isGroup,
              groupName: groupName,
              body: body,
              status: fromMe ? 'sent' : 'received',
              ack: ack,
              createdAt: sentAt,
              sentAt: sentAt,
            ),
          );
        }
        final filteredMessages = (status == 'all' || status.trim().isEmpty)
            ? messages
            : messages.where((m) {
                if (status == 'sent') return m.status == 'sent';
                if (status == 'received') return m.status == 'received';
                if (status == 'queue') return m.status == 'queue';
                if (status == 'unsent') return m.status == 'unsent';
                if (status == 'invalid') return m.status == 'invalid';
                if (status == 'expired') return m.status == 'expired';
                return m.status.toLowerCase() == status.toLowerCase();
              }).toList();
        return WhatsAppOutboxPageResult(
          total: filteredMessages.length,
          totalPages: 1,
          page: 1,
          limit: limit,
          messages: filteredMessages,
        );
      }
    } catch (e) {
      debugPrint('Error fetching WhatsApp messages list: $e');
      return WhatsAppOutboxPageResult(
        isSuccess: false,
        errorMessage: e.toString(),
      );
    } finally {
      if (client == null) httpClient.close();
    }
    return const WhatsAppOutboxPageResult();
  }

  /// Triggers a remote restart of the WhatsApp gateway instance
  Future<bool> restartInstance(WhatsAppGatewayConfigModel config, {http.Client? client}) async {
    if (!config.isConfigured) {
      return false;
    }
    final httpClient = client ?? http.Client();
    try {
      if (config.provider == WhatsAppGatewayProvider.waha) {
      final endpoint = resolveEndpoint(config);
        final session = config.instanceId.trim().isEmpty ? 'default' : config.instanceId.trim();
        final url = Uri.parse('$endpoint/api/sessions/$session/restart');
        final headers = await buildWahaProxyHeaders();
        final response = await httpClient.post(url, headers: headers).timeout(const Duration(seconds: 15));
        return response.statusCode >= 200 && response.statusCode < 300;
      }
      return false;
    } catch (e) {
      debugPrint('Error restarting WhatsApp gateway instance: $e');
      return false;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Triggers a remote logout of the WhatsApp gateway instance
  Future<bool> logoutInstance(WhatsAppGatewayConfigModel config, {http.Client? client}) async {
    if (!config.isConfigured) {
      return false;
    }
    final httpClient = client ?? http.Client();
    try {
      if (config.provider == WhatsAppGatewayProvider.waha) {
      final endpoint = resolveEndpoint(config);
        final session = config.instanceId.trim().isEmpty ? 'default' : config.instanceId.trim();
        final url = Uri.parse('$endpoint/api/sessions/$session/logout');
        final headers = await buildWahaProxyHeaders();
        final response = await httpClient.post(url, headers: headers).timeout(const Duration(seconds: 15));
        return response.statusCode >= 200 && response.statusCode < 300;
      }
      return false;
    } catch (e) {
      debugPrint('Error logging out WhatsApp gateway instance: $e');
      return false;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Cache of resolved WAHA chatIds (e.g. 225674946170895@lid or 2010...@c.us) keyed by international phone
  static final Map<String, String> _resolvedWahaChatIds = {};

  /// Resolves the active WAHA chatId (`@lid` or `@c.us`) for a phone number via `/api/contacts/check-exists`.
  /// Prevents `500 No LID for user` errors on newer WhatsApp Web (`WEBJS`) sessions.
  Future<({String? chatId, String? error})> _resolveWahaChatId({
    required http.Client httpClient,
    required String endpoint,
    required String session,
    required Map<String, String> headers,
    required String cleanPhone,
  }) async {
    final cached = _resolvedWahaChatIds[cleanPhone];
    if (cached != null && cached.isNotEmpty) {
      return (chatId: cached, error: null);
    }

    try {
      final checkUrl = Uri.parse(
        '$endpoint/api/contacts/check-exists?phone=${Uri.encodeQueryComponent(cleanPhone)}&session=${Uri.encodeQueryComponent(session)}',
      );
      // Forward Firebase auth headers only (never a WAHA x-api-key from the client).
      final checkHeaders = <String, String>{
        if (headers['Authorization'] != null) 'Authorization': headers['Authorization']!,
        if (headers['X-Firebase-AppCheck'] != null)
          'X-Firebase-AppCheck': headers['X-Firebase-AppCheck']!,
      };
      final resp = await httpClient.get(checkUrl, headers: checkHeaders).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data is Map) {
          if (data['numberExists'] == false) {
            return (chatId: null, error: 'رقم الهاتف (+$cleanPhone) غير مسجل على تطبيق واتساب');
          }
          final resolved = data['chatId']?.toString().trim() ?? '';
          if (resolved.isNotEmpty) {
            _resolvedWahaChatIds[cleanPhone] = resolved;
            return (chatId: resolved, error: null);
          }
        }
      }
    } catch (e) {
      debugPrint('WAHA check-exists fallback notice for $cleanPhone: $e');
    }

    return (chatId: '$cleanPhone@c.us', error: null);
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
        case WhatsAppGatewayProvider.waha:
          final endpoint = resolveEndpoint(config);
          final session = config.instanceId.trim().isEmpty ? 'default' : config.instanceId.trim();
          final url = Uri.parse('$endpoint/api/sendText');
          final headers = await buildWahaProxyHeaders({
            'Content-Type': 'application/json',
          });

          final resolved = await _resolveWahaChatId(
            httpClient: httpClient,
            endpoint: endpoint,
            session: session,
            headers: headers,
            cleanPhone: cleanPhone,
          );
          if (resolved.chatId == null) {
            return WhatsAppGatewayResult.failure(
              error: resolved.error ?? 'الرقم غير مسجل على واتساب: $toPhone',
              statusCode: 404,
            );
          }

          final response = await httpClient.post(
            url,
            headers: headers,
            body: json.encode({
              'session': session,
              'chatId': resolved.chatId,
              'text': messageText,
            }),
          ).timeout(const Duration(seconds: 15));

          if (response.statusCode >= 200 && response.statusCode < 300) {
            final data = json.decode(response.body);
            final msgId = (data is Map && data['_data'] is Map && data['_data']['id'] is Map)
                ? data['_data']['id']['id']?.toString()
                : (data is Map ? (data['id'] is Map ? data['id']['id']?.toString() : data['id']?.toString()) : null);
            return WhatsAppGatewayResult.success(messageId: msgId, statusCode: response.statusCode);
          }
          return WhatsAppGatewayResult.failure(
            error: 'خطأ إرسال سيرفر WAHA (${response.statusCode}): ${response.body}',
            statusCode: response.statusCode,
          );

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
      final errorStr = e.toString();
      if (errorStr.contains('Failed to fetch') || errorStr.contains('XMLHttpRequest') || errorStr.contains('ClientException')) {
        return WhatsAppGatewayResult.failure(
          error: 'تعذر الاتصال بخادم الواتساب (${config.customEndpointUrl.isNotEmpty ? config.customEndpointUrl : config.instanceId}): يرجى التحقق من اتصال السيرفر وصحة الإعدادات.',
        );
      }
      return WhatsAppGatewayResult.failure(error: 'فشل الاتصال: $e');
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Sends an image or media file to a phone number via WAHA
  Future<WhatsAppGatewayResult> sendMediaMessage({
    required WhatsAppGatewayConfigModel config,
    required String toPhone,
    required String mediaUrl,
    String? caption,
    String? filename,
    String? mimeType,
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
      if (config.provider == WhatsAppGatewayProvider.waha) {
        final endpoint = resolveEndpoint(config);
        final session = config.instanceId.trim().isEmpty ? 'default' : config.instanceId.trim();
        final url = Uri.parse('$endpoint/api/sendImage');
        final headers = await buildWahaProxyHeaders({
          'Content-Type': 'application/json',
        });
        final resolved = await _resolveWahaChatId(
          httpClient: httpClient,
          endpoint: endpoint,
          session: session,
          headers: headers,
          cleanPhone: cleanPhone,
        );
        if (resolved.chatId == null) {
          return WhatsAppGatewayResult.failure(
            error: resolved.error ?? 'الرقم غير مسجل على واتساب: $toPhone',
            statusCode: 404,
          );
        }
        final body = {
          'session': session,
          'chatId': resolved.chatId,
          'file': {
            'mimetype': mimeType ?? 'image/jpeg',
            'filename': filename ?? 'offer_poster.jpg',
            'url': mediaUrl,
          },
          'caption': caption ?? '',
        };
        final response = await httpClient.post(
          url,
          headers: headers,
          body: json.encode(body),
        ).timeout(const Duration(seconds: 25));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = json.decode(response.body);
          final msgId = (data is Map && data['_data'] is Map && data['_data']['id'] is Map)
              ? data['_data']['id']['id']?.toString()
              : (data is Map ? (data['id'] is Map ? data['id']['id']?.toString() : data['id']?.toString()) : null);
          return WhatsAppGatewayResult.success(messageId: msgId, statusCode: response.statusCode);
        }
        return WhatsAppGatewayResult.failure(
          error: 'خطأ إرسال الوسائط سيرفر WAHA (${response.statusCode}): ${response.body}',
          statusCode: response.statusCode,
        );
      }
      return await sendSingleMessage(
        config: config,
        toPhone: toPhone,
        messageText: caption != null && caption.isNotEmpty ? '$caption\n\n$mediaUrl' : mediaUrl,
        client: httpClient,
      );
    } catch (e) {
      return WhatsAppGatewayResult.failure(error: 'فشل إرسال الوسائط: $e');
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Sends an interactive poll to a phone number via WAHA
  Future<WhatsAppGatewayResult> sendPollMessage({
    required WhatsAppGatewayConfigModel config,
    required String toPhone,
    required String pollTitle,
    required List<String> pollOptions,
    bool multipleAnswers = false,
    http.Client? client,
  }) async {
    final cleanPhone = formatInternationalPhone(toPhone);
    if (cleanPhone.isEmpty || cleanPhone.length < 9) {
      return WhatsAppGatewayResult.failure(error: 'رقم الهاتف غير صالح: $toPhone');
    }

    if (!config.isConfigured) {
      return WhatsAppGatewayResult.failure(error: 'بوابة الواتساب غير مضبوطة، يرجى ضبط الإعدادات أولاً');
    }

    final trimmedTitle = pollTitle.trim();
    final cleanOptions = pollOptions.map((o) => o.trim()).where((o) => o.isNotEmpty).toList();
    if (trimmedTitle.isEmpty) {
      return WhatsAppGatewayResult.failure(error: 'سؤال الاستطلاع مطلوب');
    }
    if (cleanOptions.length < 2) {
      return WhatsAppGatewayResult.failure(error: 'يتطلب الاستطلاع خيارين على الأقل للتصويت');
    }

    final httpClient = client ?? http.Client();
    try {
      if (config.provider == WhatsAppGatewayProvider.waha) {
        final endpoint = resolveEndpoint(config);
        final session = config.instanceId.trim().isEmpty ? 'default' : config.instanceId.trim();
        final url = Uri.parse('$endpoint/api/sendPoll');
        final headers = await buildWahaProxyHeaders({
          'Content-Type': 'application/json',
        });
        final resolved = await _resolveWahaChatId(
          httpClient: httpClient,
          endpoint: endpoint,
          session: session,
          headers: headers,
          cleanPhone: cleanPhone,
        );
        if (resolved.chatId == null) {
          return WhatsAppGatewayResult.failure(
            error: resolved.error ?? 'الرقم غير مسجل على واتساب: $toPhone',
            statusCode: 404,
          );
        }
        final body = {
          'session': session,
          'chatId': resolved.chatId,
          'poll': {
            'name': trimmedTitle,
            'options': cleanOptions,
            'multipleAnswers': multipleAnswers,
          },
        };
        final response = await httpClient.post(
          url,
          headers: headers,
          body: json.encode(body),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = json.decode(response.body);
          final msgId = (data is Map && data['_data'] is Map && data['_data']['id'] is Map)
              ? data['_data']['id']['id']?.toString()
              : (data is Map ? (data['id'] is Map ? data['id']['id']?.toString() : data['id']?.toString()) : null);
          return WhatsAppGatewayResult.success(messageId: msgId, statusCode: response.statusCode);
        }
        return WhatsAppGatewayResult.failure(
          error: 'خطأ إرسال الاستطلاع سيرفر WAHA (${response.statusCode}): ${response.body}',
          statusCode: response.statusCode,
        );
      }
      return WhatsAppGatewayResult.failure(error: 'استطلاعات الرأي مدعومة حصرياً على سيرفر WAHA الخاص');
    } catch (e) {
      return WhatsAppGatewayResult.failure(error: 'فشل إرسال الاستطلاع: $e');
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Triggers typing indicator (يكتب الآن...) on a chat
  Future<bool> startTyping({
    required WhatsAppGatewayConfigModel config,
    required String toPhone,
    http.Client? client,
  }) async {
    final cleanPhone = formatInternationalPhone(toPhone);
    if (cleanPhone.isEmpty || config.provider != WhatsAppGatewayProvider.waha) return false;
    final httpClient = client ?? http.Client();
    try {
      final endpoint = resolveEndpoint(config);
      final session = config.instanceId.trim().isEmpty ? 'default' : config.instanceId.trim();
      final url = Uri.parse('$endpoint/api/startTyping');
      final headers = await buildWahaProxyHeaders({'Content-Type': 'application/json'});
      final response = await httpClient.post(
        url,
        headers: headers,
        body: json.encode({'session': session, 'chatId': '$cleanPhone@c.us'}),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Stops typing indicator on a chat
  Future<bool> stopTyping({
    required WhatsAppGatewayConfigModel config,
    required String toPhone,
    http.Client? client,
  }) async {
    final cleanPhone = formatInternationalPhone(toPhone);
    if (cleanPhone.isEmpty || config.provider != WhatsAppGatewayProvider.waha) return false;
    final httpClient = client ?? http.Client();
    try {
      final endpoint = resolveEndpoint(config);
      final session = config.instanceId.trim().isEmpty ? 'default' : config.instanceId.trim();
      final url = Uri.parse('$endpoint/api/stopTyping');
      final headers = await buildWahaProxyHeaders({'Content-Type': 'application/json'});
      final response = await httpClient.post(
        url,
        headers: headers,
        body: json.encode({'session': session, 'chatId': '$cleanPhone@c.us'}),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Checks whether a given phone number has an active registered WhatsApp account
  Future<bool?> checkNumberExists({
    required WhatsAppGatewayConfigModel config,
    required String rawPhone,
    http.Client? client,
  }) async {
    final cleanPhone = formatInternationalPhone(rawPhone);
    if (cleanPhone.isEmpty || config.provider != WhatsAppGatewayProvider.waha) return null;
    final httpClient = client ?? http.Client();
    try {
      final endpoint = resolveEndpoint(config);
      final session = config.instanceId.trim().isEmpty ? 'default' : config.instanceId.trim();
      final url = Uri.parse('$endpoint/api/contacts/check-exists?session=$session&phone=$cleanPhone');
      final headers = await buildWahaProxyHeaders();
      final response = await httpClient.get(url, headers: headers).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data.containsKey('numberExists')) {
          return data['numberExists'] == true;
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error checking number exists: $e');
      return null;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Fetches a live rendered screenshot PNG of the server WhatsApp Web session with detailed diagnostic error reporting
  Future<WhatsAppScreenshotResult> fetchLiveScreenshotDetailed({
    required WhatsAppGatewayConfigModel config,
    http.Client? client,
    bool isAr = true,
  }) async {
    if (config.provider != WhatsAppGatewayProvider.waha) {
      return WhatsAppScreenshotResult.failure(
        errorMessage: isAr
            ? 'خاصية لقطة الشاشة متاحة حصرياً لسيرفر WAHA الخاص'
            : 'Live screenshot is only available for WAHA server',
      );
    }
    final httpClient = client ?? http.Client();
    try {
      final endpoint = resolveEndpoint(config);
      final session = config.instanceId.trim().isEmpty ? 'default' : config.instanceId.trim();
      final url = Uri.parse('$endpoint/api/screenshot?session=$session');
      final headers = await buildWahaProxyHeaders();
      final response = await httpClient.get(url, headers: headers).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return WhatsAppScreenshotResult.success(response.bodyBytes);
      }

      // Detailed diagnosis from WAHA response
      String detailedMsg;
      final bodyStr = response.body.toLowerCase();
      if (bodyStr.contains('noweb') || bodyStr.contains('not available for noweb') || bodyStr.contains('no browser')) {
        detailedMsg = isAr
            ? 'سيرفر WAHA يعمل بمحرك (NOWEB) الخفيف، وهو لا يتضمن متصفح ويب، لذا لا يدعم التقاط الشاشة.\n(للربط: استخدم كود QR أو رمز الاقتران Pairing Code، أو قم بتشغيل السيرفر بمحرك WEBJS).'
            : 'WAHA server is running on NOWEB engine (no browser instance), which does not support screenshots. Use QR / Pairing code instead, or switch engine to WEBJS.';
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        detailedMsg = isAr
            ? 'خطأ مصادقة (${response.statusCode}): مفتاح API غير صحيح أو غير مفعل في إعدادات السيرفر.'
            : 'Authentication error (${response.statusCode}): Invalid or missing API key.';
      } else if (response.statusCode == 404) {
        detailedMsg = isAr
            ? 'الجلسة ($session) غير موجودة أو متوقفة على السيرفر. اضغط على "إعادة تشغيل الجلسة" لتنشيطها.'
            : 'Session ($session) not found or stopped. Tap "Restart Session" to start it.';
      } else {
        detailedMsg = isAr
            ? 'أعاد السيرفر رمز خطأ (${response.statusCode})${response.body.isNotEmpty ? ": ${response.body}" : ""}'
            : 'Server returned error (${response.statusCode})${response.body.isNotEmpty ? ": ${response.body}" : ""}';
      }

      return WhatsAppScreenshotResult.failure(
        errorMessage: detailedMsg,
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('Error fetching WAHA live screenshot: $e');
      final err = e.toString();
      String detailedMsg;
      if (kIsWeb && config.customEndpointUrl.trim().startsWith('http://')) {
        detailedMsg = isAr
            ? 'حظر المتصفح للاتصال (Mixed Content):\nالتطبيق يعمل عبر HTTPS بينما عنوان السيرفر يبدأ بـ HTTP غير المشفر. يمنع المتصفح هذا الطلب لأسباب أمنية. يرجى توفير رابط HTTPS للسيرفر (SSL).'
            : 'Browser blocked insecure request (Mixed Content): App runs on HTTPS while server endpoint uses HTTP. Please configure HTTPS (SSL) for your server.';
      } else if (err.contains('XMLHttpRequest') || err.contains('Failed to fetch') || err.contains('ClientException')) {
        detailedMsg = isAr
            ? 'تعذر الاتصال بالسيرفر. تأكد من أن السيرفر يعمل وتأكد من تفعيل CORS في إعدادات السيرفر (WAHA_CORS_ORIGIN=*).'
            : 'Could not connect to server. Ensure the server is online and CORS is enabled (WAHA_CORS_ORIGIN=*).';
      } else if (err.contains('TimeoutException')) {
        detailedMsg = isAr
            ? 'انتهت مهلة انتظار السيرفر (Timeout). قد يكون السيرفر بطيئاً أو غير متاح حالياً.'
            : 'Connection timed out. Server may be overloaded or unreachable.';
      } else {
        detailedMsg = isAr
            ? 'خطأ أثناء الاتصال بالسيرفر: $e'
            : 'Connection error: $e';
      }

      return WhatsAppScreenshotResult.failure(
        errorMessage: detailedMsg,
      );
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Fetches a live rendered screenshot PNG of the server WhatsApp Web session
  Future<Uint8List?> fetchLiveScreenshot({
    required WhatsAppGatewayConfigModel config,
    http.Client? client,
  }) async {
    final result = await fetchLiveScreenshotDetailed(config: config, client: client);
    return result.bytes;
  }

  /// Fetches the live QR code PNG image for session authorization
  Future<Uint8List?> fetchQrCode(WhatsAppGatewayConfigModel config, {http.Client? client}) async {
    if (config.provider != WhatsAppGatewayProvider.waha) return null;
    final httpClient = client ?? http.Client();
    try {
      final endpoint = resolveEndpoint(config);
      final session = config.instanceId.trim().isEmpty ? 'default' : config.instanceId.trim();
      final url = Uri.parse('$endpoint/api/$session/auth/qr');
      final headers = await buildWahaProxyHeaders();
      final response = await httpClient.get(url, headers: headers).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching WAHA QR code: $e');
      return null;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Requests an 8-character pairing code to link WhatsApp by entering the code in mobile app
  Future<String?> requestPairingCode({
    required WhatsAppGatewayConfigModel config,
    required String phoneNumber,
    http.Client? client,
  }) async {
    if (config.provider != WhatsAppGatewayProvider.waha) return null;
    final cleanPhone = formatInternationalPhone(phoneNumber);
    if (cleanPhone.isEmpty) return null;

    final httpClient = client ?? http.Client();
    try {
      final endpoint = resolveEndpoint(config);
      final session = config.instanceId.trim().isEmpty ? 'default' : config.instanceId.trim();
      final url = Uri.parse('$endpoint/api/$session/auth/request-code');
      final headers = await buildWahaProxyHeaders({
        'Content-Type': 'application/json',
      });
      final body = json.encode({'phoneNumber': cleanPhone});
      final response = await httpClient.post(url, headers: headers, body: body).timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = json.decode(response.body);
        if (data is Map && data.containsKey('code')) {
          return data['code']?.toString();
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error requesting WAHA pairing code: $e');
      return null;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Retrieves real-time session information (status, me, phone, pushName)
  Future<Map<String, dynamic>?> fetchSessionDetails(WhatsAppGatewayConfigModel config, {http.Client? client}) async {
    if (config.provider != WhatsAppGatewayProvider.waha) return null;
    final httpClient = client ?? http.Client();
    try {
      final endpoint = resolveEndpoint(config);
      final session = config.instanceId.trim().isEmpty ? 'default' : config.instanceId.trim();
      final url = Uri.parse('$endpoint/api/sessions/$session');
      final headers = await buildWahaProxyHeaders();
      final response = await httpClient.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching session details: $e');
      return null;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Starts a WAHA session
  Future<bool> startInstance(WhatsAppGatewayConfigModel config, {http.Client? client}) async {
    if (!config.isConfigured || config.provider != WhatsAppGatewayProvider.waha) return false;
    final httpClient = client ?? http.Client();
    try {
      final endpoint = resolveEndpoint(config);
      final session = config.instanceId.trim().isEmpty ? 'default' : config.instanceId.trim();
      final url = Uri.parse('$endpoint/api/sessions/$session/start');
      final headers = await buildWahaProxyHeaders();
      final response = await httpClient.post(url, headers: headers).timeout(const Duration(seconds: 15));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Error starting WAHA instance: $e');
      return false;
    } finally {
      if (client == null) httpClient.close();
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
    String? attachedMediaUrl,
    String? pollTitle,
    List<String>? pollOptions,
    bool multiplePollAnswers = false,
    bool Function()? isCancelled,
    http.Client? client,
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
      final targetPhone = contact.cleanPhone.isNotEmpty ? contact.cleanPhone : contact.rawPhone;
      final personalizedMessage = buildPersonalizedMessage(
        template: template,
        contact: contact,
        companyName: companyName,
        campaignName: campaignName,
      );

      // 1. Optional Typing Simulation
      if (config.enableTypingSimulation) {
        yield BatchProgressEvent(
          currentIndex: i + 1,
          totalContacts: contacts.length,
          successCount: successCount,
          failureCount: failureCount,
          currentContact: contact,
          isCompleted: false,
          statusMessage: 'جاري محاكاة الكتابة للعميل: ${contact.name.isNotEmpty ? contact.name : contact.rawPhone}...',
        );
        await startTyping(config: config, toPhone: targetPhone, client: client);
        await Future.delayed(Duration(seconds: math.max(1, config.typingDurationSeconds)));
      }

      yield BatchProgressEvent(
        currentIndex: i + 1,
        totalContacts: contacts.length,
        successCount: successCount,
        failureCount: failureCount,
        currentContact: contact,
        isCompleted: false,
        statusMessage: 'جاري الإرسال للعميل: ${contact.name.isNotEmpty ? contact.name : contact.rawPhone}...',
      );

      // 2. Dispatch Media, Poll, or Standard Text
      final WhatsAppGatewayResult result;
      if (pollOptions != null && pollOptions.isNotEmpty && pollTitle != null && pollTitle.isNotEmpty) {
        final personalizedPollTitle = buildPersonalizedMessage(
          template: pollTitle,
          contact: contact,
          companyName: companyName,
          campaignName: campaignName,
        );
        result = await sendPollMessage(
          config: config,
          toPhone: targetPhone,
          pollTitle: personalizedPollTitle,
          pollOptions: pollOptions,
          multipleAnswers: multiplePollAnswers,
          client: client,
        );
      } else if (attachedMediaUrl != null && attachedMediaUrl.trim().isNotEmpty) {
        result = await sendMediaMessage(
          config: config,
          toPhone: targetPhone,
          mediaUrl: attachedMediaUrl.trim(),
          caption: personalizedMessage,
          client: client,
        );
      } else {
        result = await sendSingleMessage(
          config: config,
          toPhone: targetPhone,
          messageText: personalizedMessage,
          client: client,
        );
      }

      // Stop typing simulation if it was triggered
      if (config.enableTypingSimulation) {
        await stopTyping(config: config, toPhone: targetPhone, client: client);
      }

      if (result.isSuccess) {
        successCount++;
        contact.status = ContactDispatchStatus.sent;
      } else {
        failureCount++;
        contact.status = ContactDispatchStatus.failed;
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
