import 'dart:convert';

/// Supported WhatsApp Gateway Providers
enum WhatsAppGatewayProvider {
  ultraMsg,
  greenApi,
  whapi,
  custom,
}

extension WhatsAppGatewayProviderExtension on WhatsAppGatewayProvider {
  String get id {
    switch (this) {
      case WhatsAppGatewayProvider.ultraMsg:
        return 'ultramsg';
      case WhatsAppGatewayProvider.greenApi:
        return 'greenapi';
      case WhatsAppGatewayProvider.whapi:
        return 'whapi';
      case WhatsAppGatewayProvider.custom:
        return 'custom';
    }
  }

  String get displayName {
    switch (this) {
      case WhatsAppGatewayProvider.ultraMsg:
        return 'UltraMsg (سحابي سريع)';
      case WhatsAppGatewayProvider.greenApi:
        return 'Green API (سحابي متقدم)';
      case WhatsAppGatewayProvider.whapi:
        return 'Whapi.cloud (سحابي احترافي)';
      case WhatsAppGatewayProvider.custom:
        return 'سيرفر مخصص (Custom Endpoint / Self-Hosted)';
    }
  }

  static WhatsAppGatewayProvider fromId(String? id) {
    switch (id?.toLowerCase().trim()) {
      case 'greenapi':
      case 'green_api':
        return WhatsAppGatewayProvider.greenApi;
      case 'whapi':
      case 'whapi_cloud':
        return WhatsAppGatewayProvider.whapi;
      case 'custom':
      case 'self_hosted':
        return WhatsAppGatewayProvider.custom;
      case 'ultramsg':
      default:
        return WhatsAppGatewayProvider.ultraMsg;
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

  const WhatsAppGatewayConfigModel({
    this.provider = WhatsAppGatewayProvider.ultraMsg,
    this.instanceId = '',
    this.apiToken = '',
    this.customEndpointUrl = '',
    this.delayBetweenMessagesSeconds = 3,
    this.isEnabled = false,
    this.lastTestedAt,
    this.isConnected = false,
    this.connectedPhoneNumber,
  });

  bool get isConfigured {
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
  final String body;
  final String status; // 'sent', 'queue', 'unsent', 'invalid', 'expired'
  final String? failedReason;
  final String? ack;
  final DateTime? createdAt;
  final DateTime? sentAt;

  const WhatsAppOutboxMessage({
    required this.id,
    required this.toPhone,
    this.fromPhone = '',
    required this.body,
    required this.status,
    this.failedReason,
    this.ack,
    this.createdAt,
    this.sentAt,
  });

  factory WhatsAppOutboxMessage.fromUltraMsgJson(Map<String, dynamic> json) {
    DateTime? parseUnix(dynamic val) {
      if (val is num && val > 0) {
        return DateTime.fromMillisecondsSinceEpoch(val.toInt() * 1000);
      }
      return null;
    }

    final rawTo = (json['to'] ?? '').toString().replaceAll('@c.us', '');
    final rawFrom = (json['from'] ?? '').toString().replaceAll('@c.us', '');

    return WhatsAppOutboxMessage(
      id: (json['id'] ?? '').toString(),
      toPhone: rawTo,
      fromPhone: rawFrom,
      body: (json['body'] ?? '').toString(),
      status: (json['status'] ?? 'unknown').toString().toLowerCase().trim(),
      failedReason: json['failed_reason']?.toString(),
      ack: json['ack']?.toString(),
      createdAt: parseUnix(json['created_at']),
      sentAt: parseUnix(json['sent_at']),
    );
  }
}

/// Paginated result of live outbox messages
class WhatsAppOutboxPageResult {
  final int total;
  final int totalPages;
  final int page;
  final int limit;
  final List<WhatsAppOutboxMessage> messages;

  const WhatsAppOutboxPageResult({
    this.total = 0,
    this.totalPages = 1,
    this.page = 1,
    this.limit = 10,
    this.messages = const [],
  });
}
