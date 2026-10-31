import 'dart:convert';

/// Supported WhatsApp Gateway Providers
enum WhatsAppGatewayProvider {
  waha,
  custom,
  greenApi,
  whapi,
}

extension WhatsAppGatewayProviderExtension on WhatsAppGatewayProvider {
  String get id {
    switch (this) {
      case WhatsAppGatewayProvider.waha:
        return 'waha';
      case WhatsAppGatewayProvider.custom:
        return 'custom';
      case WhatsAppGatewayProvider.greenApi:
        return 'greenapi';
      case WhatsAppGatewayProvider.whapi:
        return 'whapi';
    }
  }

  String get displayName {
    switch (this) {
      case WhatsAppGatewayProvider.waha:
        return 'سيرفر الواتساب الخاص (WAHA - مجاني 100%)';
      case WhatsAppGatewayProvider.custom:
        return 'سيرفر مخصص (Custom Endpoint)';
      case WhatsAppGatewayProvider.greenApi:
        return 'Green API (سحابي متقدم)';
      case WhatsAppGatewayProvider.whapi:
        return 'Whapi.cloud (سحابي احترافي)';
    }
  }

  static WhatsAppGatewayProvider fromId(String? id) {
    switch (id?.toLowerCase().trim()) {
      case 'custom':
      case 'self_hosted':
        return WhatsAppGatewayProvider.custom;
      case 'greenapi':
      case 'green_api':
        return WhatsAppGatewayProvider.greenApi;
      case 'whapi':
      case 'whapi_cloud':
        return WhatsAppGatewayProvider.whapi;
      case 'ultramsg':
      case 'waha':
      default:
        return WhatsAppGatewayProvider.waha;
    }
  }
}

/// Configuration Model for WhatsApp Gateway API
class WhatsAppGatewayConfigModel {
  final WhatsAppGatewayProvider provider;
  final String instanceId;
  final String apiToken;
  final String customEndpointUrl;
  final int delayBetweenMessagesSeconds;
  final bool isEnabled;
  final DateTime? lastTestedAt;
  final bool isConnected;
  final String? connectedPhoneNumber;
  final bool enableTypingSimulation;
  final int typingDurationSeconds;
  final bool enableAiAutoReply;
  final String aiCustomSystemPrompt;
  final bool autoNotifyWinnersOnGiftHandover;
  final String winnerNotificationTemplate;

  // 2.0.157: no gift/prize name in the customer message.
  static const String defaultWinnerTemplate =
      '🎉 ألف مبروك يا {customer_name}! كسبت معانا 🎁\n'
      '📱 رقم الواتساب: {phone}\n\n'
      'يسر {retail_chain} - {branch_name}\n'
      'بالتعاون مع {company_name}\n'
      'تهنئتكم بالفوز معانا! 🎉\n'
      '{voucher_details}'
      '📌 تفاصيل المشاركة:\n'
      '• الحملة: {campaign_name}\n'
      '• رقم الفاتورة: {receipt_number}\n'
      '• تاريخ الاستلام: {claim_date}\n\n'
      'سعداء جداً بخدمتكم ونتمنى لكم تجربة تسوق ممتعة ومميزة دائماً! 🛍️✨';

  const WhatsAppGatewayConfigModel({
    this.provider = WhatsAppGatewayProvider.waha,
    this.instanceId = 'default',
    this.apiToken = '',
    this.customEndpointUrl = '',
    this.delayBetweenMessagesSeconds = 3,
    this.isEnabled = true,
    this.lastTestedAt,
    this.isConnected = false,
    this.connectedPhoneNumber,
    this.enableTypingSimulation = true,
    this.typingDurationSeconds = 2,
    this.enableAiAutoReply = false,
    this.aiCustomSystemPrompt = '',
    this.autoNotifyWinnersOnGiftHandover = true,
    this.winnerNotificationTemplate = defaultWinnerTemplate,
  });

  bool get isConfigured {
    // WAHA uses the HTTPS Cloud proxy which injects the server secret.
    if (provider == WhatsAppGatewayProvider.waha) {
      return true;
    }
    if (provider == WhatsAppGatewayProvider.custom) {
      return customEndpointUrl.trim().isNotEmpty;
    }
    return instanceId.trim().isNotEmpty && apiToken.trim().isNotEmpty;
  }

  WhatsAppGatewayConfigModel copyWith({
    WhatsAppGatewayProvider? provider,
    String? instanceId,
    String? apiToken,
    String? customEndpointUrl,
    int? delayBetweenMessagesSeconds,
    bool? isEnabled,
    DateTime? lastTestedAt,
    bool? isConnected,
    String? connectedPhoneNumber,
    bool? enableTypingSimulation,
    int? typingDurationSeconds,
    bool? enableAiAutoReply,
    String? aiCustomSystemPrompt,
    bool? autoNotifyWinnersOnGiftHandover,
    String? winnerNotificationTemplate,
  }) {
    return WhatsAppGatewayConfigModel(
      provider: provider ?? this.provider,
      instanceId: instanceId ?? this.instanceId,
      apiToken: apiToken ?? this.apiToken,
      customEndpointUrl: customEndpointUrl ?? this.customEndpointUrl,
      delayBetweenMessagesSeconds: delayBetweenMessagesSeconds ?? this.delayBetweenMessagesSeconds,
      isEnabled: isEnabled ?? this.isEnabled,
      lastTestedAt: lastTestedAt ?? this.lastTestedAt,
      isConnected: isConnected ?? this.isConnected,
      connectedPhoneNumber: connectedPhoneNumber ?? this.connectedPhoneNumber,
      enableTypingSimulation: enableTypingSimulation ?? this.enableTypingSimulation,
      typingDurationSeconds: typingDurationSeconds ?? this.typingDurationSeconds,
      enableAiAutoReply: enableAiAutoReply ?? this.enableAiAutoReply,
      aiCustomSystemPrompt: aiCustomSystemPrompt ?? this.aiCustomSystemPrompt,
      autoNotifyWinnersOnGiftHandover: autoNotifyWinnersOnGiftHandover ?? this.autoNotifyWinnersOnGiftHandover,
      winnerNotificationTemplate: winnerNotificationTemplate ?? this.winnerNotificationTemplate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'provider': provider.id,
      'instanceId': instanceId.trim(),
      'apiToken': apiToken.trim(),
      'customEndpointUrl': customEndpointUrl.trim(),
      'delayBetweenMessagesSeconds': delayBetweenMessagesSeconds,
      'isEnabled': isEnabled,
      'lastTestedAt': lastTestedAt?.toIso8601String(),
      'isConnected': isConnected,
      'connectedPhoneNumber': connectedPhoneNumber,
      'enableTypingSimulation': enableTypingSimulation,
      'typingDurationSeconds': typingDurationSeconds,
      'enableAiAutoReply': enableAiAutoReply,
      'aiCustomSystemPrompt': aiCustomSystemPrompt.trim(),
      'autoNotifyWinnersOnGiftHandover': autoNotifyWinnersOnGiftHandover,
      'winnerNotificationTemplate': winnerNotificationTemplate,
    };
  }

  factory WhatsAppGatewayConfigModel.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const WhatsAppGatewayConfigModel();
    return WhatsAppGatewayConfigModel(
      provider: WhatsAppGatewayProviderExtension.fromId(map['provider']?.toString()),
      instanceId: map['instanceId']?.toString() ?? '',
      apiToken: map['apiToken']?.toString() ?? '',
      customEndpointUrl: map['customEndpointUrl']?.toString() ?? '',
      delayBetweenMessagesSeconds: int.tryParse(map['delayBetweenMessagesSeconds']?.toString() ?? '') ?? 3,
      isEnabled: map['isEnabled'] == true,
      lastTestedAt: map['lastTestedAt'] != null ? DateTime.tryParse(map['lastTestedAt'].toString()) : null,
      isConnected: map['isConnected'] == true,
      connectedPhoneNumber: map['connectedPhoneNumber']?.toString(),
      enableTypingSimulation: map['enableTypingSimulation'] != false,
      typingDurationSeconds: int.tryParse(map['typingDurationSeconds']?.toString() ?? '') ?? 2,
      enableAiAutoReply: map['enableAiAutoReply'] == true,
      aiCustomSystemPrompt: map['aiCustomSystemPrompt']?.toString() ?? '',
      autoNotifyWinnersOnGiftHandover: map['autoNotifyWinnersOnGiftHandover'] != false,
      winnerNotificationTemplate: map['winnerNotificationTemplate']?.toString() ?? defaultWinnerTemplate,
    );
  }

  String toJson() => json.encode(toMap());

  factory WhatsAppGatewayConfigModel.fromJson(String source) {
    try {
      return WhatsAppGatewayConfigModel.fromMap(json.decode(source) as Map<String, dynamic>);
    } catch (_) {
      return const WhatsAppGatewayConfigModel();
    }
  }
}

/// Statistics model for live WhatsApp Gateway queue and status metrics
class WhatsAppGatewayStats {
  final int sentCount;
  final int queueCount;
  final int unsentCount;
  final int invalidCount;
  final int expiredCount;

  const WhatsAppGatewayStats({
    this.sentCount = 0,
    this.queueCount = 0,
    this.unsentCount = 0,
    this.invalidCount = 0,
    this.expiredCount = 0,
  });

  int get totalTracked => sentCount + queueCount + unsentCount + invalidCount + expiredCount;
}

/// Represents an individual message in the WhatsApp Gateway live outbox/log
class WhatsAppOutboxMessage {
  final String id;
  final String toPhone;
  final String fromPhone;
  final String contactName;
  final bool isGroup;
  final String? groupName;
  final String body;
  final String status; // 'sent', 'queue', 'unsent', 'invalid', 'expired', 'received'
  final String? failedReason;
  final String? ack;
  final DateTime? createdAt;
  final DateTime? sentAt;

  const WhatsAppOutboxMessage({
    required this.id,
    required this.toPhone,
    this.fromPhone = '',
    this.contactName = '',
    this.isGroup = false,
    this.groupName,
    required this.body,
    required this.status,
    this.failedReason,
    this.ack,
    this.createdAt,
    this.sentAt,
  });

  factory WhatsAppOutboxMessage.fromJson(Map<String, dynamic> json) {
    DateTime? parseUnix(dynamic val) {
      if (val is num && val > 0) {
        return DateTime.fromMillisecondsSinceEpoch(val.toInt() * 1000);
      }
      return null;
    }

    final rawTo = (json['to'] ?? '').toString().replaceAll('@c.us', '').replaceAll('@lid', '').replaceAll('@g.us', '');
    final rawFrom = (json['from'] ?? '').toString().replaceAll('@c.us', '').replaceAll('@lid', '').replaceAll('@g.us', '');

    return WhatsAppOutboxMessage(
      id: (json['id'] ?? '').toString(),
      toPhone: rawTo,
      fromPhone: rawFrom,
      contactName: (json['contact_name'] ?? json['name'] ?? '').toString().trim(),
      isGroup: json['is_group'] == true || json['isGroup'] == true,
      groupName: json['group_name']?.toString() ?? json['groupName']?.toString(),
      body: (json['body'] ?? '').toString(),
      status: (json['status'] ?? 'unknown').toString().toLowerCase().trim(),
      failedReason: json['failed_reason']?.toString(),
      ack: json['ack']?.toString(),
      createdAt: parseUnix(json['created_at']),
      sentAt: parseUnix(json['sent_at']),
    );
  }

  factory WhatsAppOutboxMessage.fromUltraMsgJson(Map<String, dynamic> json) =>
      WhatsAppOutboxMessage.fromJson(json);
}

/// Paginated result of live outbox messages
class WhatsAppOutboxPageResult {
  final int total;
  final int totalPages;
  final int page;
  final int limit;
  final List<WhatsAppOutboxMessage> messages;
  final String? errorMessage;
  final bool isSuccess;

  const WhatsAppOutboxPageResult({
    this.total = 0,
    this.totalPages = 1,
    this.page = 1,
    this.limit = 10,
    this.messages = const [],
    this.errorMessage,
    this.isSuccess = true,
  });
}
