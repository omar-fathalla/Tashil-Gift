import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/utils/receipt_run_guard.dart';

void main() {
  test('second run while busy is skipped', () async {
    final g = ReceiptRunGuard();
    final gate = Completer<void>();
    var runs = 0;
    final first = g.run(() async {
      runs++;
      await gate.future;
    });
    expect(g.isBusy, isTrue);
    expect(await g.run(() async => runs++), isFalse);
    gate.complete();
    expect(await first, isTrue);
    expect(runs, 1);
    expect(g.isBusy, isFalse);
  });

  test('guard is released after an error', () async {
    final g = ReceiptRunGuard();
    await expectLater(
      g.run(() async => throw StateError('x')),
      throwsStateError,
    );
    expect(g.isBusy, isFalse);
    expect(await g.run(() async {}), isTrue);
  });

  test('sequential runs (e.g. awaited silent retry) both execute', () async {
    final g = ReceiptRunGuard();
    var runs = 0;
    await g.run(() async {
      runs++;
    });
    await g.run(() async {
      runs++;
    });
    expect(runs, 2);
  });

  test('run state is independent per run', () {
    final a = ReceiptRunState(step: 'session');
    final b = ReceiptRunState(step: 'session');
    a.step = 'save';
    a.receiptNumber = '123';
    expect(b.step, 'session');
    expect(b.receiptNumber, '');
  });
}
