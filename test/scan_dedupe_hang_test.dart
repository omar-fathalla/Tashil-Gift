import 'dart:async';

import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/services/gemini_cloud_model.dart';
import 'package:al_mraay/core/services/receipt_save_failure.dart';
import 'package:al_mraay/features/client_portal/presentation/widgets/receipt_issue_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2.0.151+212: the in-flight scan dedupe used
/// `whenComplete(() => _inflightScans.remove(key))`, which handed the removed
/// future (itself) back to whenComplete -> it awaited itself and never
/// completed, so every keyed rep scan hung after the AI answered.
void main() {
  setUp(AiReceiptService.clearScanDedupeForTest);

  const answer = CloudGenerateContentResponse(text: '{"isValid":false}');

  test('keyed scan resolves as soon as the AI answers (no self-await)', () async {
    final sw = Stopwatch()..start();
    final r = await AiReceiptService.dedupedGenerateForTest('k1', () async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return answer;
    }).timeout(const Duration(seconds: 2));
    expect(r.text, answer.text);
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('keyed scan failure surfaces immediately (no hang until the ceiling)', () async {
    await expectLater(
      AiReceiptService.dedupedGenerateForTest('k2', () async {
        throw Exception('unauthenticated');
      }).timeout(const Duration(seconds: 2)),
      throwsA(isA<Exception>().having((e) => e is TimeoutException, 'is timeout', isFalse)),
    );
  });

  test('re-tap joins the running call, but a later upload re-reads fresh', () async {
    var calls = 0;
    final c = Completer<CloudGenerateContentResponse>();
    Future<CloudGenerateContentResponse> run() {
      calls++;
      return calls == 1 ? c.future : Future.value(answer);
    }
    final a = AiReceiptService.dedupedGenerateForTest('k3', run);
    final b = AiReceiptService.dedupedGenerateForTest('k3', run);
    c.complete(answer);
    expect((await a.timeout(const Duration(seconds: 2))).text, answer.text);
    expect((await b.timeout(const Duration(seconds: 2))).text, answer.text);
    expect(calls, 1, reason: 'concurrent re-tap shares one call');
    await AiReceiptService.dedupedGenerateForTest('k3', run)
        .timeout(const Duration(seconds: 2));
    expect(calls, 2, reason: 're-upload after completion must call the AI again');
  });

  test('a failed scan is not cached and can be retried', () async {
    var calls = 0;
    await expectLater(
      AiReceiptService.dedupedGenerateForTest('k4', () async {
        calls++;
        throw Exception('boom');
      }),
      throwsA(isA<Exception>()),
    );
    final r = await AiReceiptService.dedupedGenerateForTest('k4', () async {
      calls++;
      return answer;
    }).timeout(const Duration(seconds: 2));
    expect(r.text, answer.text);
    expect(calls, 2);
  });

  group('timeout is not "no internet"', () {
    final stage2 = TimeoutException(
        AiReceiptService.stage2TimeoutMessage, AiReceiptService.stage2Ceiling);
    test('stage-2 TimeoutException -> timeout kind + code', () {
      expect(classifyReceiptException(stage2), ReceiptIssueKind.timeout);
      expect(receiptErrorCode(stage2), 'timeout');
    });
    test('timeout message text', () {
      expect(receiptIssueSpecs[ReceiptIssueKind.timeout]!.titleAr,
          'الفحص اتأخر، دوس حاول مرة أخرى');
    });
    test('real network errors still map to network', () {
      expect(classifyReceiptException(Exception('Failed to fetch')),
          ReceiptIssueKind.network);
      expect(classifyReceiptException(Exception('SocketException: connection refused')),
          ReceiptIssueKind.network);
    });
  });
}
