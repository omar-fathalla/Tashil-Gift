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
  static const String gemini40 = 'gemini-4.0';

  // --- Const display labels (for const widgets / default params).
  // Must equal displayName(id); guarded by test/ai_models_test.dart.
  static const String gemini25FlashLabel = 'Gemini 2.5 Flash';
  static const String gemini36FlashLabel = 'Gemini 3.6 Flash';
  static const String gemini37FlashLabel = 'Gemini 3.7 Flash';
  static const String gemini38FlashLabel = 'Gemini 3.8 Flash';
  static const String gemini38ProLabel = 'Gemini 3.8 Pro';

  /// Label of [helperServices] (const form).
  static const String helperServicesConstLabel = gemini37FlashLabel;

  /// Label of [defaultPrimary] (const form), e.g. directive defaults.
  static const String defaultPrimaryLabel = gemini37FlashLabel;

  // --- Role defaults (used before / without Firestore config) ---
  static const String defaultPrimary = gemini37Flash;
  static const String defaultFallback = gemini36Flash;
  static const String defaultFastTier = gemini37Flash;
  static const String defaultDeepAudit = gemini38Pro;


  /// Fixed model for the non-scan helper services (product catalog, product
  /// discovery, smart branch matcher, branch signature, campaign assistant,
  /// WhatsApp auto-reply). Kept on 3.7 for now.
  static const String helperServices = gemini37Flash;

  /// Fallback for the helper services.
  static const String helperServicesFallback = gemini36Flash;

  /// Placeholder examples shown in the custom-model text field.
  static const List<String> customExamples = [
    gemini38Flash,
    gemini38Ultra,
    gemini40,
  ];

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
