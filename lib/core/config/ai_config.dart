import 'package:al_mraay/core/constants/ai_models.dart';

/// Centralized AI Configuration & Dynamic Model Selection
///
/// The Gemini API key must NEVER ship in the client binary.
/// All Gemini traffic goes through the `geminiGenerate` Cloud Function,
/// which reads `GEMINI_API_KEY` from Firebase Secrets.
class AiConfig {
  // --- Dynamic Model & Agent In-Memory State ---
  static String _primaryModel = AiModels.defaultPrimary;
  static String _fallbackModel = AiModels.defaultFallback;
  static String _fastTierModel = AiModels.defaultFastTier;
  static String _deepAuditModel = AiModels.defaultDeepAudit;
  static dynamic _activeAgentMode;
  static int _thinkingBudget = 0;
  static String _helperModel = '';
  static String _helperFallbackModel = '';
  static String _thinkingLevelFast = '';
  static String _thinkingLevelDeep = '';

  /// Returns the currently active global primary model identifier
  static String get primaryModel => _primaryModel;

  /// Returns the active fallback model identifier
  static String get fallbackModel => _fallbackModel;

  /// Returns the model identifier for Tier 1 Fast Vision OCR
  static String get fastTierModel => _fastTierModel;

  /// Returns the model identifier for Tier 2 Deep Forensic Audit & Reasoning
  static String get deepAuditModel => _deepAuditModel;

  /// Active agent mode code or object
  static dynamic get activeAgentMode => _activeAgentMode;

  /// Optional thinking budget for reasoning models
  static int get thinkingBudget => _thinkingBudget;

  /// Model for the non-scan helper services. Runtime override from
  /// `system_settings/ai_engine.helper_model`, else [AiModels.helperServices].
  static String get helperModel =>
      _helperModel.isEmpty ? AiModels.helperServices : _helperModel;

  /// Fallback for the helper services, else [AiModels.helperServicesFallback].
  static String get helperFallbackModel => _helperFallbackModel.isEmpty
      ? AiModels.helperServicesFallback
      : _helperFallbackModel;

  /// Admin thinking level for the fast scan tier, or null when unset.
  static String? get thinkingLevelFast =>
      _thinkingLevelFast.isEmpty ? null : _thinkingLevelFast;

  /// Admin thinking level for the deep-audit tier, or null when unset.
  static String? get thinkingLevelDeep =>
      _thinkingLevelDeep.isEmpty ? null : _thinkingLevelDeep;

  /// Synchronize the in-memory active AI model configuration
  static void updateActiveModelConfig({
    required String primary,
    required String fallback,
    String? fastTier,
    String? deepAudit,
    dynamic mode,
    int budget = 0,
    String? helperModel,
    String? helperFallbackModel,
    String? thinkingLevelFast,
    String? thinkingLevelDeep,
  }) {
    if (primary.trim().isNotEmpty) {
      _primaryModel = primary.trim();
    }
    if (fallback.trim().isNotEmpty) {
      _fallbackModel = fallback.trim();
    }
    if (fastTier != null && fastTier.trim().isNotEmpty) {
      _fastTierModel = fastTier.trim();
    }
    if (deepAudit != null && deepAudit.trim().isNotEmpty) {
      _deepAuditModel = deepAudit.trim();
    }
    _activeAgentMode = mode;
    _thinkingBudget = budget;
    // null keeps the current value; an empty string clears the override.
    if (helperModel != null) _helperModel = helperModel.trim();
    if (helperFallbackModel != null) {
      _helperFallbackModel = helperFallbackModel.trim();
    }
    if (thinkingLevelFast != null) {
      _thinkingLevelFast = AiModels.normalizeThinkingLevel(thinkingLevelFast) ?? '';
    }
    if (thinkingLevelDeep != null) {
      _thinkingLevelDeep = AiModels.normalizeThinkingLevel(thinkingLevelDeep) ?? '';
    }
  }
}
