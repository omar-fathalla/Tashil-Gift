import 'dart:async';
import 'dart:io';
import 'package:al_mraay/core/services/gemini_cloud_model.dart';
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
  test('2.0.150: strict 40s per-call timeout under the 45s callable cap', () {
    expect(AiReceiptService.geminiCallTimeout.inSeconds, 40);
    expect(CloudGenerativeModel.callableTimeout.inSeconds, 45);
    expect(AiReceiptService.geminiCallTimeout < CloudGenerativeModel.callableTimeout, isTrue);
    expect(AiReceiptService.firstCheckBudget.inSeconds, 60);
  });
  test('attemptTimeout clamps to remaining budget and never stacks', () {
    final now = DateTime(2026, 10, 30, 15);
    const per = Duration(seconds: 40);
    expect(AiReceiptService.attemptTimeout(null, per), per);
    expect(AiReceiptService.attemptTimeout(now.add(const Duration(seconds: 60)), per, now: now), per);
    expect(AiReceiptService.attemptTimeout(now.add(const Duration(seconds: 15)), per, now: now),
        const Duration(seconds: 15));
    expect(() => AiReceiptService.attemptTimeout(now.add(const Duration(seconds: 2)), per, now: now),
        throwsA(isA<TimeoutException>()));
  });
  test('automatic second forensic check is removed from the scan pipeline', () {
    final src = File('lib/core/services/ai_receipt_service.dart').readAsStringSync();
    expect(src.contains('_deepAuditModel\n                .generateContent'), isFalse);
    expect(src.contains('result.fraudRiskScore >= 40 &&'), isFalse);
  });
}
