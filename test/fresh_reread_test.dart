import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/services/gemini_cloud_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2.0.171+232: re-uploading the same receipt photo must trigger a fresh AI
/// read (Knorr 139/2/241: attempts 2 and 3 reused the 9.50 misread in 0.58s).
void main() {
  setUp(AiReceiptService.clearScanDedupeForTest);
  const r1 = CloudGenerateContentResponse(text: '{"isValid":false,"t":53}');
  const r2 = CloudGenerateContentResponse(text: '{"isValid":true,"t":76.5}');

  test('same key, sequential uploads -> each one hits the AI', () async {
    var calls = 0;
    final answers = [r1, r2, r2];
    Future<CloudGenerateContentResponse> run() async => answers[calls++];
    final key = AiReceiptService.scanCacheKeyForTest('m', 'p', []);
    final a = await AiReceiptService.dedupedGenerateForTest(key, run);
    final b = await AiReceiptService.dedupedGenerateForTest(key, run);
    final c = await AiReceiptService.dedupedGenerateForTest(key, run);
    expect(calls, 3);
    expect(a.text, r1.text);
    expect(b.text, r2.text, reason: 'second upload must not see the first answer');
    expect(c.text, r2.text);
  });
}
