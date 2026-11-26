import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/constants/ai_models.dart';

void main() {
  test('const labels match displayName(id)', () {
    expect(AiModels.gemini25FlashLabel, AiModels.displayName(AiModels.gemini25Flash));
    expect(AiModels.gemini36FlashLabel, AiModels.displayName(AiModels.gemini36Flash));
    expect(AiModels.gemini37FlashLabel, AiModels.displayName(AiModels.gemini37Flash));
    expect(AiModels.gemini38FlashLabel, AiModels.displayName(AiModels.gemini38Flash));
    expect(AiModels.gemini38ProLabel, AiModels.displayName(AiModels.gemini38Pro));
    expect(AiModels.gemini4HydrogenLabel, AiModels.displayName(AiModels.gemini4Hydrogen));
    expect(AiModels.helperServicesConstLabel, AiModels.helperServicesLabel);
    expect(AiModels.defaultPrimaryLabel, AiModels.displayName(AiModels.defaultPrimary));
  });
  test('runtime defaults use explicit documented ids', () {
    expect(AiModels.defaultPrimary, 'gemini-3.8-flash');
    expect(AiModels.defaultFallback, 'gemini-3.6-flash');
    expect(AiModels.defaultFastTier, 'gemini-3.8-flash');
    expect(AiModels.defaultDeepAudit, 'gemini-3.8-flash');
    expect(AiModels.helperServices, 'gemini-3.8-flash');
    expect(AiModels.helperServicesFallback, 'gemini-3.6-flash');
    expect(AiModels.familyName(AiModels.helperServices), 'Gemini 3.8');
  });
  test('no code default points at a retired or undocumented model', () {
    const defaults = [
      AiModels.defaultPrimary,
      AiModels.defaultFallback,
      AiModels.defaultFastTier,
      AiModels.defaultDeepAudit,
      AiModels.helperServices,
      AiModels.helperServicesFallback,
    ];
    for (final id in defaults) {
      expect(id, isNot('gemini-3.7-flash'));
      expect(id, isNot('gemini-3.8-pro'));
      expect(id, isNot(startsWith('gemini-2')));
    }
  });
  test('Gemini 4 ids', () {
    expect(AiModels.gemini4Hydrogen, 'gemini-4-hydrogen');
    expect(AiModels.customExamples, contains('gemini-4-hydrogen'));
    expect(AiModels.customExamples, isNot(contains('gemini-4.0')));
    for (final id in ['gemini-4-hydrogen', 'gemini-4-neon', 'gemini-4-carbon', 'gemini-4-argon']) {
      expect(AiModels.isGemini4(id), isTrue, reason: id);
    }
    for (final id in ['gemini-4.0', 'gemini-3.8-flash', 'gemini-2.5-flash', '']) {
      expect(AiModels.isGemini4(id), isFalse, reason: id);
    }
  });
  test('normalizeThinkingLevel only accepts low, medium and high', () {
    expect(AiModels.normalizeThinkingLevel('low'), 'low');
    expect(AiModels.normalizeThinkingLevel(' Medium '), 'medium');
    expect(AiModels.normalizeThinkingLevel('HIGH'), 'high');
    expect(AiModels.normalizeThinkingLevel('minimal'), isNull);
    expect(AiModels.normalizeThinkingLevel('xhigh'), isNull);
    expect(AiModels.normalizeThinkingLevel(''), isNull);
    expect(AiModels.normalizeThinkingLevel(null), isNull);
    expect(AiModels.normalizeThinkingLevel(3), isNull);
  });
}
