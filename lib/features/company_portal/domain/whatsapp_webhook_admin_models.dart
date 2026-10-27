import 'package:cloud_firestore/cloud_firestore.dart';

/// Campaign row passed in from the marketing screen.
class WhatsappCampaignOption {
  final String id;
  final String name;

  const WhatsappCampaignOption({required this.id, required this.name});
}

/// Default reply templates. The webhook uses the same Arabic text when a
/// saved template is empty.
const Map<String, String> kWhatsappReplyTemplateDefaults = {
  'verified': 'تم التحقق من فاتورتك رقم {receipt}. جائزتك: {prize}. حملة {campaign}.',
  'pendingReview': 'مرحباً {name}، استلمنا رسالتك وهي قيد المراجعة لحملة {campaign}.',
  'rejected': 'تعذر قبول الفاتورة {receipt}. {campaign}',
  'notAllowed': 'هذا الرقم غير مسموح به. اطلب رابط الدعوة من المسؤول للانضمام.',
  'registered': 'تم تسجيلك يا {name} في حملة {campaign}. أرسل صورة الفاتورة الآن.',
};

const List<String> kWhatsappReplyTemplateKeys = [
  'verified',
  'pendingReview',
  'rejected',
  'notAllowed',
  'registered',
];

const List<String> kWhatsappInboxFilters = [
  'all',
  'verified',
  'pending_review',
  'rejected',
  'verified_without_prize',
  'not_allowed',
];

class WhatsappWebhookConfig {
  final bool enabled;
  final bool autoRepliesEnabled;
  final bool allowListOnly;
  final String businessNumber;
  final String businessDisplayName;
  final DateTime? lastEventAt;
  final String lastEventName;
  final String lastSessionStatus;
  final Map<String, String> templates;

  const WhatsappWebhookConfig({
    this.enabled = true,
    this.autoRepliesEnabled = false,
    this.allowListOnly = false,
    this.businessNumber = '',
    this.businessDisplayName = '',
    this.lastEventAt,
    this.lastEventName = '',
    this.lastSessionStatus = '',
    this.templates = const {},
  });

  String template(String key) {
    final saved = templates[key]?.trim() ?? '';
    if (saved.isNotEmpty) return saved;
    return kWhatsappReplyTemplateDefaults[key] ?? '';
  }

  factory WhatsappWebhookConfig.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    final rawTemplates = map['templates'];
    final templates = <String, String>{};
    if (rawTemplates is Map) {
      for (final key in kWhatsappReplyTemplateKeys) {
        final value = rawTemplates[key];
        if (value != null) templates[key] = value.toString();
      }
    }
    return WhatsappWebhookConfig(
      enabled: map['enabled'] != false,
      autoRepliesEnabled: map['autoRepliesEnabled'] == true,
      allowListOnly: map['allowListOnly'] == true,
      businessNumber: map['businessNumber']?.toString() ?? '',
      businessDisplayName: map['businessDisplayName']?.toString() ?? '',
      lastEventAt: readFirestoreTime(map['lastEventAt']) ?? readFirestoreTime(map['lastEventAtMs']),
      lastEventName: map['lastEventName']?.toString() ?? '',
      lastSessionStatus: map['lastSessionStatus']?.toString() ?? '',
      templates: templates,
    );
  }
}

class WhatsappCampaignRegistration {
  final String campaignId;
  final String campaignName;
  final bool selfRegistrationEnabled;
  final String joinCode;
  final String prizeIdentifier;

  const WhatsappCampaignRegistration({
    required this.campaignId,
    this.campaignName = '',
    this.selfRegistrationEnabled = false,
    this.joinCode = '',
    this.prizeIdentifier = '',
  });

  factory WhatsappCampaignRegistration.fromDoc(String id, Map<String, dynamic> data) {
    return WhatsappCampaignRegistration(
      campaignId: data['campaignId']?.toString().isNotEmpty == true ? data['campaignId'].toString() : id,
      campaignName: data['campaignName']?.toString() ?? '',
      selfRegistrationEnabled: data['selfRegistrationEnabled'] == true,
      joinCode: data['joinCode']?.toString() ?? '',
      prizeIdentifier: data['prizeIdentifier']?.toString() ?? '',
    );
  }
}

class WhatsappSenderLink {
  final String phone;
  final String campaignId;
  final String campaignName;
  final String prizeIdentifier;
  final String displayName;
  final bool active;

  const WhatsappSenderLink({
    required this.phone,
    required this.campaignId,
    this.campaignName = '',
    this.prizeIdentifier = '',
    this.displayName = '',
    this.active = true,
  });

  factory WhatsappSenderLink.fromDoc(String id, Map<String, dynamic> data) {
    return WhatsappSenderLink(
      phone: data['phone']?.toString().isNotEmpty == true ? data['phone'].toString() : id,
      campaignId: data['campaignId']?.toString() ?? '',
      campaignName: data['campaignName']?.toString() ?? '',
      prizeIdentifier: data['prizeIdentifier']?.toString() ?? '',
      displayName: data['displayName']?.toString() ?? '',
      active: data['active'] != false,
    );
  }
}

class WhatsappInboundMessage {
  final String id;
  final String phone;
  final DateTime? receivedAt;
  final String status;
  final String reason;
  final String prize;
  final String receiptNumber;
  final String campaignId;
  final String thumbnailUrl;
  final String replyText;
  final String replyMessageId;
  final bool replySent;
  final String body;
  final Map<String, dynamic> analysis;

  const WhatsappInboundMessage({
    required this.id,
    this.phone = '',
    this.receivedAt,
    this.status = '',
    this.reason = '',
    this.prize = '',
    this.receiptNumber = '',
    this.campaignId = '',
    this.thumbnailUrl = '',
    this.replyText = '',
    this.replyMessageId = '',
    this.replySent = false,
    this.body = '',
    this.analysis = const {},
  });

  String get verificationKey {
    if (status == 'awarded') return 'verified';
    if (status == 'pending_review' && reason == 'verified_without_prize') {
      return 'verified_without_prize';
    }
    if (status == 'pending_review') return 'pending_review';
    if (status == 'rejected') return 'rejected';
    if (status == 'not_allowed') return 'not_allowed';
    if (status == 'registered') return 'registered';
    if (status == 'stored') return 'stored';
    if (status == 'ignored') return 'ignored';
    if (status == 'error') return 'error';
    return status.isEmpty ? 'stored' : status;
  }

  String get displayPrize {
    if (prize.isNotEmpty) return prize;
    final won = analysis['prizeWon']?.toString() ?? '';
    if (won.isNotEmpty) return won;
    final list = analysis['prizesWon'];
    if (list is List && list.isNotEmpty) return list.map((e) => e.toString()).join(', ');
    return '';
  }

  String get displayReceipt {
    if (receiptNumber.isNotEmpty) return receiptNumber;
    return analysis['receiptNumber']?.toString() ?? '';
  }

  factory WhatsappInboundMessage.fromDoc(String id, Map<String, dynamic> data) {
    final analysisRaw = data['analysis'];
    return WhatsappInboundMessage(
      id: id,
      phone: data['phone']?.toString() ?? '',
      receivedAt: readFirestoreTime(data['receivedAt']) ?? readFirestoreTime(data['updatedAt']),
      status: data['status']?.toString() ?? '',
      reason: data['reason']?.toString() ?? '',
      prize: data['prize']?.toString() ?? '',
      receiptNumber: data['receiptNumber']?.toString() ?? '',
      campaignId: data['campaignId']?.toString() ?? '',
      thumbnailUrl: _thumbnail(data),
      replyText: data['replyText']?.toString() ?? '',
      replyMessageId: data['replyMessageId']?.toString() ?? '',
      replySent: data['replySent'] == true,
      body: data['body']?.toString() ?? '',
      analysis: analysisRaw is Map ? Map<String, dynamic>.from(analysisRaw) : const {},
    );
  }
}

String _thumbnail(Map<String, dynamic> data) {
  for (final key in ['thumbnailUrl', 'mediaUrl', 'imageUrl']) {
    final value = data[key]?.toString() ?? '';
    if (value.startsWith('https://') || value.startsWith('http://')) return value;
  }
  return '';
}

DateTime? readFirestoreTime(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String fillWhatsappTemplate(String template, {
  String name = '',
  String prize = '',
  String receipt = '',
  String campaign = '',
}) {
  return template
      .replaceAll('{name}', name)
      .replaceAll('{prize}', prize)
      .replaceAll('{receipt}', receipt)
      .replaceAll('{campaign}', campaign);
}

String buildWaMeInvite(String businessNumber, String joinCode) {
  final digits = businessNumber.replaceAll(RegExp(r'\D'), '');
  final code = joinCode.trim();
  if (digits.isEmpty || code.isEmpty) return '';
  return 'https://wa.me/$digits?text=${Uri.encodeComponent(code)}';
}

String formatWebhookClock(DateTime? time) {
  if (time == null) return '';
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

String wahaSessionPhone(Map<String, dynamic>? details) {
  if (details == null) return '';
  final me = details['me'];
  if (me is Map) {
    final id = me['id']?.toString() ?? '';
    final user = id.split('@').first.split(':').first;
    if (user.isNotEmpty) return user;
    final push = me['pushName']?.toString() ?? '';
    if (push.isNotEmpty) return push;
  }
  return details['phone']?.toString() ?? '';
}

String wahaSessionStatus(Map<String, dynamic>? details) {
  if (details == null) return '';
  return details['status']?.toString() ?? details['state']?.toString() ?? '';
}

bool inboxMatchesQuery(WhatsappInboundMessage message, String query) {
  final needle = query.replaceAll(RegExp(r'\D'), '');
  if (needle.isEmpty) return true;
  final haystack = message.phone.replaceAll(RegExp(r'\D'), '');
  return haystack.contains(needle);
}
