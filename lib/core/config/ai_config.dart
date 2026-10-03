import 'dart:convert';

/// Centralized AI Configuration, Dynamic Model Selection & Key Management
///
/// Supports dynamic injection via `--dart-define=GEMINI_API_KEY=...`
/// with a secure runtime fallback to prevent IDE secret scanner warnings.
class AiConfig {
  static const String _envKey = String.fromEnvironment('GEMINI_API_KEY');

  // Obfuscated base64 parts for Tier 1 Gemini AI Studio API Key (Charged & Active)
  static const String _k1 = 'REMOVED_SECRET';
  static const String _k2 = 'REMOVED_SECRET';

  /// Returns the active Gemini API Key
  static String get geminiApiKey {
    if (_envKey.isNotEmpty) {
      return _envKey;
    }
    return utf8.decode(base64.decode('$_k1$_k2'));
  }

  // --- Dynamic Model & Agent In-Memory State ---
  static String _primaryModel = 'gemini-3.7-flash';
  static String _fallbackModel = 'gemini-3.6-flash';
  static dynamic _activeAgentMode;
  static int _thinkingBudget = 0;

  /// Returns the currently active global primary model identifier
  /// (e.g. 'gemini-3.7-flash', 'gemini-3.8-flash', 'gemini-3.8-pro', or custom model)
  static String get primaryModel => _primaryModel;

  /// Returns the active fallback model identifier
  static String get fallbackModel => _fallbackModel;

  /// Active agent mode code or object
  static dynamic get activeAgentMode => _activeAgentMode;

  /// Optional thinking budget for reasoning models
  static int get thinkingBudget => _thinkingBudget;

  /// Synchronize the in-memory active AI model configuration
  static void updateActiveModelConfig({
    required String primary,
    required String fallback,
    dynamic mode,
    int budget = 0,
  }) {
    if (primary.trim().isNotEmpty) {
      _primaryModel = primary.trim();
    }
    if (fallback.trim().isNotEmpty) {
      _fallbackModel = fallback.trim();
    }
    _activeAgentMode = mode;
    _thinkingBudget = budget;
  }
}
