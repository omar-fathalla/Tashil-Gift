import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'support/emulator.dart';
import 'support/flows.dart';

void main() {
  patrolTest('customer uploads a receipt and picks a gift for each chance', ($) async {
    assertEmulatorBuild();
    await seedCampaign();

    await startAppAt($, '/event/$eventId');

    final rounds = await allowSyntheticPreviewError(() async {
      await uploadReceipt($, utf8.encode(syntheticReceiptBytes));
      await $(RegExp('الفرصة الحالية')).waitUntilVisible(timeout: const Duration(seconds: 60));
      return pickGiftEachRound($);
    });
    // 1402 EGP on a consuming 500/350/200 ladder with at most 3 chances.
    expect(rounds, 3);

    final claimed = await receiptClaimedUnits();
    expect(claimed, rounds);

    // The receipt image went to the Storage emulator through storage.rules.
    final images = await receiptImagePaths();
    expect(images, isNotEmpty, reason: 'no receipt image in the Storage emulator');
  });
}
