/// Single source of truth for every Gemini model id used by the Flutter app.
///
/// Change a model here once and every service, default, and label follows.
/// The live scan model is still read at runtime from Firestore
/// (`system_settings/ai_engine.fast_tier_model`) via [AiConfig]; the values
/// below are only the in-code defaults / fixed per-service choices.
///
/// Functions-side mirror: `functions/ai_models.js`.
class AiModels {
  AiModels._();

  // --- Known model ids ---
  static const String gemini25Flash = 'gemini-2.5-flash';
  static const String gemini36Flash = 'gemini-3.6-flash';
  static const String gemini37Flash = 'gemini-3.7-flash';
  static const String gemini38Flash = 'gemini-3.8-flash';
  static const String gemini38Pro = 'gemini-3.8-pro';
  static const String gemini38Ultra = 'gemini-3.8-ultra';
  static const String gemini4Hydrogen = 'gemini-4-hydrogen';

  // --- Const display labels (for const widgets / default params).
  // Must equal displayName(id); guarded by test/ai_models_test.dart.
  static const String gemini25FlashLabel = 'Gemini 2.5 Flash';
  static const String gemini36FlashLabel = 'Gemini 3.6 Flash';
  static const String gemini37FlashLabel = 'Gemini 3.7 Flash';
  static const String gemini38FlashLabel = 'Gemini 3.8 Flash';
  static const String gemini38ProLabel = 'Gemini 3.8 Pro';
  static const String gemini4HydrogenLabel = 'Gemini 4 Hydrogen';

  /// Label of [helperServices] (const form).
  static const String helperServicesConstLabel = gemini38FlashLabel;

  /// Label of [defaultPrimary] (const form), e.g. directive defaults.
  static const String defaultPrimaryLabel = gemini38FlashLabel;

  // --- Role defaults (used before / without Firestore config) ---
  //
  // 3.7 Flash is retired in AI Studio and the API already routes it to 3.8
  // Flash, so the 3.8 id is set explicitly (no behavior change).
  static const String defaultPrimary = gemini38Flash;
  static const String defaultFallback = gemini36Flash;
  static const String defaultFastTier = gemini38Flash;

  /// `gemini-3.8-pro` has no documented model page (see the Gemini models
  /// list), so the deep-audit default is a documented id. Admins can still set
  /// any id through `system_settings/ai_engine.deep_audit_model`.
  static const String defaultDeepAudit = gemini38Flash;

  /// Fixed model for the non-scan helper services (product catalog, product
  /// discovery, smart branch matcher, branch signature, campaign assistant,
  /// WhatsApp auto-reply). Overridable at runtime through
  /// `system_settings/ai_engine.helper_model` (see `AiConfig.helperModel`).
  static const String helperServices = gemini38Flash;

  /// Fallback for the helper services.
  static const String helperServicesFallback = gemini36Flash;

  /// Placeholder examples shown in the custom-model text field.
  static const List<String> customExamples = [
    gemini38Flash,
    gemini38Ultra,
    gemini4Hydrogen,
  ];

  /// Thinking levels an admin may set in `system_settings/ai_engine`.
  static const List<String> allowedThinkingLevels = ['low', 'medium', 'high'];

  /// True for the Gemini 4 family (`gemini-4-hydrogen`, `-neon`, `-carbon`, `-argon`).
  static bool isGemini4(String id) => id.trim().toLowerCase().startsWith('gemini-4-');

  /// Normalizes an admin-provided thinking level. Anything other than
  /// `low`, `medium` or `high` is ignored (null).
  static String? normalizeThinkingLevel(Object? raw) {
    if (raw is! String) return null;
    final level = raw.trim().toLowerCase();
    return allowedThinkingLevels.contains(level) ? level : null;
  }

  /// Human label for a model id: `gemini-3.7-flash` -> `Gemini 3.7 Flash`.
  static String displayName(String id) {
    final parts = id.trim().split('-');
    return parts
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join(' ');
  }

  /// Short label without the variant: `gemini-3.7-flash` -> `Gemini 3.7`.
  static String familyName(String id) {
    final parts = id.trim().split('-');
    if (parts.length < 2) return displayName(id);
    return 'Gemini ${parts[1]}';
  }

  static String get helperServicesLabel => displayName(helperServices);
  static String get helperServicesFallbackLabel =>
      displayName(helperServicesFallback);
}
