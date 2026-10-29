import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/ai_config.dart';
import 'firebase_scope.dart';

/// Available Specialized AI Agent Modes
enum AiAgentMode {
  /// Standard POS vision & anti-fraud receipt inspector (Balanced speed & accuracy)
  standardVision,

  /// High reasoning & deep audit agent (Complex multi-tier promotions, twin-bundles & spend rules)
  highReasoning,

  /// Ultra-speed promotion matcher (Sub-second response for high-volume cashier desks)
  ultraSpeed,

  /// Strict fraud & image tamper auditor (Ultra-high sensitivity for blurred, copied, or paper notes)
  strictFraudAudit;

  String get displayNameAr {
    switch (this) {
      case AiAgentMode.standardVision:
        return 'فاحص البونات القياسي وكاشف التزوير (Standard Vision)';
      case AiAgentMode.highReasoning:
        return 'وكيل الاستدلال العميق والخصومات المركبة (High Reasoning)';
      case AiAgentMode.ultraSpeed:
        return 'المطابق فائق السرعة لكاونترات الذروة (Ultra-Speed)';
      case AiAgentMode.strictFraudAudit:
        return 'المدقق الأمني فائق الصرامة للصور المطموسة (Strict Audit)';
    }
  }

  String get labelAr => displayNameAr;

  String get displayNameEn {
    switch (this) {
      case AiAgentMode.standardVision:
        return 'Standard POS Vision & Anti-Fraud';
      case AiAgentMode.highReasoning:
        return 'High Reasoning & Deep Audit';
      case AiAgentMode.ultraSpeed:
        return 'Ultra-Speed Peak Promotion Matcher';
      case AiAgentMode.strictFraudAudit:
        return 'Strict Tamper & Blur Auditor';
    }
  }

  String get labelEn => displayNameEn;

  String get code {
    switch (this) {
      case AiAgentMode.standardVision:
        return 'standard_vision';
      case AiAgentMode.highReasoning:
        return 'high_reasoning';
      case AiAgentMode.ultraSpeed:
        return 'ultra_speed';
      case AiAgentMode.strictFraudAudit:
        return 'strict_fraud_audit';
    }
  }

  static AiAgentMode fromCode(String? code) {
    switch (code) {
      case 'high_reasoning':
        return AiAgentMode.highReasoning;
      case 'ultra_speed':
        return AiAgentMode.ultraSpeed;
      case 'strict_fraud_audit':
        return AiAgentMode.strictFraudAudit;
      default:
        return AiAgentMode.standardVision;
    }
  }
}

/// Known preset Gemini Models
class GeminiModelPreset {
  final String id;
  final String titleAr;
  final String titleEn;
  final String descriptionAr;
  final String badge;
  final bool isLatest;

  const GeminiModelPreset({
    required this.id,
    required this.titleAr,
    required this.titleEn,
    required this.descriptionAr,
    required this.badge,
    this.isLatest = false,
  });

  static const List<GeminiModelPreset> presets = [
    GeminiModelPreset(
      id: 'gemini-3.7-flash',
      titleAr: 'جيميناي 3.7 فلاش (النموذج القياسي الحالي)',
      titleEn: 'Gemini 3.7 Flash (Standard Default)',
      descriptionAr: 'النموذج المعتمد حالياً في كافة أرجاء النظام، يحقق توازناً استثنائياً بين دقة الرؤية والسرعة الفائقة.',
      badge: 'القياسي الحالي ⚡',
    ),
    GeminiModelPreset(
      id: 'gemini-3.8-flash',
      titleAr: 'جيميناي 3.8 فلاش (High السرعة والدقة)',
      titleEn: 'Gemini 3.8 Flash (High Speed & Precision)',
      descriptionAr: 'الجيل المتقدم الجديد، سرعة قراءة أعلى لبونات الكاشير الطويلة وأداء استثنائي تحت الضغط.',
      badge: 'الجيل الجديد 🚀',
      isLatest: true,
    ),
    GeminiModelPreset(
      id: 'gemini-3.8-pro',
      titleAr: 'جيميناي 3.8 برو (High الاستدلال والتدقيق العميق)',
      titleEn: 'Gemini 3.8 Pro (High Reasoning & Deep Audit)',
      descriptionAr: 'قدرات استدلال وتفكير متقدمة لحساب العروض المركبة وحزم الكومبو والخصومات متعددة الشروط.',
      badge: 'استدلال عميق 🧠',
      isLatest: true,
    ),
    GeminiModelPreset(
      id: 'gemini-3.6-flash',
      titleAr: 'جيميناي 3.6 فلاش (الاحتياطي الأول)',
      titleEn: 'Gemini 3.6 Flash (Primary Fallback)',
      descriptionAr: 'نموذج مستقر وسريع، يعمل كمسار احتياطي أول في حال انقطاع الشبكة.',
      badge: 'احتياطي مستقر 🛡️',
    ),
    GeminiModelPreset(
      id: 'gemini-2.5-flash',
      titleAr: 'جيميناي 2.5 فلاش (الجيل السابق)',
      titleEn: 'Gemini 2.5 Flash (Legacy)',
      descriptionAr: 'النموذج الكلاسيكي خفيف الوزن.',
      badge: 'كلاسيكي ⏳',
    ),
  ];
}

/// Dynamic Model & Engine Configuration Data Model
class AiModelConfig {
  final String primaryModel;
  final String fallbackModel;
  final String fastTierModel;
  final String deepAuditModel;
  final AiAgentMode agentMode;
  final int thinkingBudget;
  final String? customModelIdentifier;
  final DateTime? updatedAt;
  final String? updatedBy;

  const AiModelConfig({
    this.primaryModel = 'gemini-3.7-flash',
    this.fallbackModel = 'gemini-3.6-flash',
    this.fastTierModel = 'gemini-3.7-flash',
    this.deepAuditModel = 'gemini-3.8-pro',
    this.agentMode = AiAgentMode.standardVision,
    this.thinkingBudget = 0,
    this.customModelIdentifier,
    this.updatedAt,
    this.updatedBy,
  });

  /// The effective model string sent to Gemini API
  String get effectivePrimaryModel {
    if (customModelIdentifier != null && customModelIdentifier!.trim().isNotEmpty) {
      return customModelIdentifier!.trim();
    }
    return primaryModel;
  }

  /// Alias for agentMode
  AiAgentMode get mode => agentMode;

  Map<String, dynamic> toMap() {
    return {
      'primary_model': primaryModel,
      'fallback_model': fallbackModel,
      'fast_tier_model': fastTierModel,
      'deep_audit_model': deepAuditModel,
      'agent_mode': agentMode.code,
      'thinking_budget': thinkingBudget,
      'custom_model_identifier': customModelIdentifier,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': updatedBy ?? 'admin',
    };
  }

  factory AiModelConfig.fromMap(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) {
      return const AiModelConfig();
    }
    final modeCode = data['agent_mode'] as String?;
    final primary = (data['primary_model'] as String?)?.trim();
    final fallback = (data['fallback_model'] as String?)?.trim();
    final fastTier = (data['fast_tier_model'] as String?)?.trim();
    final deepAudit = (data['deep_audit_model'] as String?)?.trim();
    final custom = (data['custom_model_identifier'] as String?)?.trim();
    final budget = (data['thinking_budget'] as num?)?.toInt() ?? 0;

    DateTime? updated;
    if (data['updated_at'] is Timestamp) {
      updated = (data['updated_at'] as Timestamp).toDate();
    }

    return AiModelConfig(
      primaryModel: primary != null && primary.isNotEmpty ? primary : 'gemini-3.7-flash',
      fallbackModel: fallback != null && fallback.isNotEmpty ? fallback : 'gemini-3.6-flash',
      fastTierModel: fastTier != null && fastTier.isNotEmpty ? fastTier : 'gemini-3.7-flash',
      deepAuditModel: deepAudit != null && deepAudit.isNotEmpty ? deepAudit : 'gemini-3.8-pro',
      agentMode: AiAgentMode.fromCode(modeCode),
      thinkingBudget: budget,
      customModelIdentifier: custom != null && custom.isNotEmpty ? custom : null,
      updatedAt: updated,
      updatedBy: data['updated_by'] as String?,
    );
  }
}

/// Central Service Managing Dynamic Global AI Model & Agent Settings
class AiModelConfigService {
  final FirebaseFirestore _firestore;

  AiModelConfigService(this._firestore);

  DocumentReference<Map<String, dynamic>> get _configDocRef =>
      _firestore.collection('system_settings').doc('ai_engine');

  /// Real-time stream of the global AI model configuration
  Stream<AiModelConfig> streamConfig() {
    return _configDocRef.snapshots().map((snapshot) {
      final config = snapshot.exists ? AiModelConfig.fromMap(snapshot.data()) : const AiModelConfig();
      // Synchronize in-memory static config immediately for synchronous consumers
      AiConfig.updateActiveModelConfig(
        primary: config.effectivePrimaryModel,
        fallback: config.fallbackModel,
        fastTier: config.fastTierModel,
        deepAudit: config.deepAuditModel,
        mode: config.agentMode,
        budget: config.thinkingBudget,
      );
      return config;
    });
  }

  /// Fetch current configuration once
  Future<AiModelConfig> getConfig() async {
    try {
      final doc = await _configDocRef.get();
      final config = doc.exists ? AiModelConfig.fromMap(doc.data()) : const AiModelConfig();
      AiConfig.updateActiveModelConfig(
        primary: config.effectivePrimaryModel,
        fallback: config.fallbackModel,
        fastTier: config.fastTierModel,
        deepAudit: config.deepAuditModel,
        mode: config.agentMode,
        budget: config.thinkingBudget,
      );
      return config;
    } catch (e) {
      debugPrint('Error getting AI Model Config from Firestore: $e');
      return const AiModelConfig();
    }
  }

  /// Updates the global AI model and agent mode in Cloud Firestore
  Future<void> updateConfig({
    required String primaryModel,
    required String fallbackModel,
    String? fastTierModel,
    String? deepAuditModel,
    required AiAgentMode agentMode,
    int thinkingBudget = 0,
    String? customModelIdentifier,
    String? updatedBy,
  }) async {
    final effectiveModel = (customModelIdentifier != null && customModelIdentifier.trim().isNotEmpty)
        ? customModelIdentifier.trim()
        : primaryModel;

    final config = AiModelConfig(
      primaryModel: primaryModel,
      fallbackModel: fallbackModel,
      fastTierModel: fastTierModel ?? 'gemini-3.7-flash',
      deepAuditModel: deepAuditModel ?? 'gemini-3.8-pro',
      agentMode: agentMode,
      thinkingBudget: thinkingBudget,
      customModelIdentifier: customModelIdentifier,
      updatedBy: updatedBy,
    );

    // Update in-memory immediately
    AiConfig.updateActiveModelConfig(
      primary: effectiveModel,
      fallback: fallbackModel,
      fastTier: config.fastTierModel,
      deepAudit: config.deepAuditModel,
      mode: agentMode,
      budget: thinkingBudget,
    );

    // Persist to Cloud Firestore for instant propagation to all clients
    await _configDocRef.set(config.toMap(), SetOptions(merge: true));
  }
}

/// Riverpod Providers
final aiModelConfigServiceProvider = Provider<AiModelConfigService>((ref) {
  return AiModelConfigService(scopedFirestore());
});

final aiModelConfigStreamProvider = StreamProvider<AiModelConfig>((ref) {
  final service = ref.watch(aiModelConfigServiceProvider);
  return service.streamConfig();
});
