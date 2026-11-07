import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/constants/ai_models.dart';

void main() {
  test('const labels match displayName(id)', () {
    expect(AiModels.gemini25FlashLabel, AiModels.displayName(AiModels.gemini25Flash));
    expect(AiModels.gemini36FlashLabel, AiModels.displayName(AiModels.gemini36Flash));
    expect(AiModels.gemini37FlashLabel, AiModels.displayName(AiModels.gemini37Flash));
    expect(AiModels.gemini38FlashLabel, AiModels.displayName(AiModels.gemini38Flash));
    expect(AiModels.gemini38ProLabel, AiModels.displayName(AiModels.gemini38Pro));
    expect(AiModels.helperServicesConstLabel, AiModels.helperServicesLabel);
    expect(AiModels.defaultPrimaryLabel, AiModels.displayName(AiModels.defaultPrimary));
  });
  test('runtime defaults unchanged', () {
    expect(AiModels.defaultPrimary, 'gemini-3.7-flash');
    expect(AiModels.defaultFallback, 'gemini-3.6-flash');
    expect(AiModels.defaultFastTier, 'gemini-3.7-flash');
    expect(AiModels.defaultDeepAudit, 'gemini-3.8-pro');
    expect(AiModels.helperServices, 'gemini-3.7-flash');
    expect(AiModels.familyName(AiModels.helperServices), 'Gemini 3.7');
  });
}
