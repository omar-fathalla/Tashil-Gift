import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Gemini 3.x fast tier uses thinkingLevel low', () {
    expect(AiReceiptService.fastTierThinkingConfig('gemini-3.8-flash'),
        {'thinkingLevel': 'low'});
  });
  test('Gemini 2.x fast tier uses a bounded thinkingBudget', () {
    expect(AiReceiptService.fastTierThinkingConfig('gemini-2.5-flash'),
        {'thinkingBudget': 1024});
  });
  test('client Gemini timeout sits under the 120s callable/server limit', () {
    expect(AiReceiptService.geminiCallTimeout.inSeconds, 90);
  });
}
