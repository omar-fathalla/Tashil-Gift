import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'event_model.dart';

/// C-05 "try with receipt": payloads for the dryRunCampaignEligibility
/// callable and its result. The server runs the same eligibility check a real
/// claim runs, and never writes anything.
class DryRunLine {
  final String name;
  final String barcode;
  final double price;
  final int quantity;
  final bool isTargetCompany;

  const DryRunLine({
    required this.name,
    this.barcode = '',
    required this.price,
    this.quantity = 1,
    this.isTargetCompany = true,
  });

  Map<String, dynamic> toMap() => {
        'name': name.trim(),
        if (barcode.trim().isNotEmpty) 'barcode': barcode.trim(),
        'price': price,
        'quantity': quantity,
        'isTargetCompany': isTargetCompany,
      };
}

class DryRunResult {
  final bool ok;
  final String? code;
  final String? message;
  final int? serverUnits;
  final String mode;
  final bool campaignActive;
  final int lineCount;

  const DryRunResult({
    required this.ok,
    this.code,
    this.message,
    this.serverUnits,
    this.mode = 'exclusive',
    this.campaignActive = false,
    this.lineCount = 0,
  });

  factory DryRunResult.fromMap(Map<dynamic, dynamic> m) => DryRunResult(
        ok: m['ok'] == true,
        code: m['code']?.toString(),
        message: m['message']?.toString(),
        serverUnits: m['serverUnits'] is num ? (m['serverUnits'] as num).toInt() : null,
        mode: (m['mode'] ?? 'exclusive').toString(),
        campaignActive: m['campaignActive'] == true,
        lineCount: m['lineCount'] is num ? (m['lineCount'] as num).toInt() : 0,
      );
}

/// TAG-66: the campaign is too large to test before it is saved.
class DryRunTooLarge implements Exception {
  const DryRunTooLarge();
  String get message => 'قائمة منتجات الحملة كبيرة جدًا للتجربة قبل الحفظ. احفظ الحملة الأول وجرّب تاني.';
  @override
  String toString() => message;
}

class CampaignDryRun {
  CampaignDryRun._();

  static const String callableName = 'dryRunCampaignEligibility';

  /// Fields the eligibility check never needs (and credentials never leave).
  static const Set<String> _dropped = {
    'createdAt',
    'customAgencyUsername',
    'customAgencyPassword',
    'customPrompt',
    'aiValidationSummary',
    'promotionalIdea',
    'termsAndConditions',
    'welcomeMessage',
    'welcomeTitle',
    'companyLogoUrl',
  };

  /// Callable-safe value: Timestamp/DateTime become epoch ms, FieldValue is dropped.
  static dynamic _plain(dynamic v) {
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    if (v is DateTime) return v.millisecondsSinceEpoch;
    if (v is FieldValue) return null;
    if (v is Map) {
      final out = <String, dynamic>{};
      v.forEach((k, val) {
        if (val is FieldValue) return;
        out[k.toString()] = _plain(val);
      });
      return out;
    }
    if (v is Iterable) return v.map(_plain).toList();
    return v;
  }

  /// The editor's current campaign, as the server check expects it.
  static Map<String, dynamic> campaignPayload(EventModel e) {
    final m = Map<String, dynamic>.from(_plain(e.toFirestore()) as Map);
    m.removeWhere((k, _) => _dropped.contains(k));
    return m;
  }

  /// Manual receipt: printed date (as on the receipt) and its lines.
  static Map<String, dynamic> receiptPayload({String receiptDate = '', required List<DryRunLine> lines}) => {
        'receipt_date': receiptDate.trim(),
        'extracted_products': lines.where((l) => l.name.trim().isNotEmpty).map((l) => l.toMap()).toList(),
      };

  /// TAG-62: above this the product list is not sent; the server reads the
  /// stored list of [EventModel.id] instead (callable payload limit).
  static const int maxInlineProductsChars = 200000;

  static Map<String, dynamic> request({
    required EventModel campaign,
    Map<String, dynamic>? receipt,
    String? receiptId,
  }) {
    final payload = campaignPayload(campaign);
    String? contentEventId;
    final products = payload['requiredProducts'];
    final tooBig = products is List && jsonEncode(products).length > maxInlineProductsChars;
    if (campaign.id.isNotEmpty && (tooBig || !campaign.contentInfo.productsInline)) {
      payload.remove('requiredProducts');
      contentEventId = campaign.id;
    }
    final out = {
      'campaign': payload,
      if (contentEventId != null) 'contentEventId': contentEventId,
      if (receiptId != null && receiptId.trim().isNotEmpty) 'receiptId': receiptId.trim() else 'receipt': receipt ?? const {},
    };
    // TAG-66: an unsaved campaign has no stored list to fall back on, so its
    // whole list is sent; only a list past the server cap is refused here.
    if (jsonEncode(out).length > maxRequestChars) throw const DryRunTooLarge();
    return out;
  }

  /// Same cap as MAX_PAYLOAD_CHARS in functions/campaign_dry_run.js.
  static const int maxRequestChars = 4000000;
}
