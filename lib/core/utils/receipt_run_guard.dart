/// 2.0.156: one receipt scan/save run at a time per screen.
///
/// Taps, the error dialog's retry button and the silent session retry all go
/// through [tryBegin]; a second run while one is in progress is ignored, so
/// two runs can never overwrite each other's step or receipt number.
library;

/// Per-run pipeline state, reported with any save failure.
class ReceiptRunState {
  String step;
  String receiptNumber;
  ReceiptRunState({required this.step, this.receiptNumber = ''});
}

class ReceiptRunGuard {
  bool _busy = false;
  bool get isBusy => _busy;

  /// Returns false (and does nothing) if a run is already in progress.
  bool tryBegin() {
    if (_busy) return false;
    _busy = true;
    return true;
  }

  void end() => _busy = false;

  /// Runs [body] only if no other run is active. Returns false if skipped.
  Future<bool> run(Future<void> Function() body) async {
    if (!tryBegin()) return false;
    try {
      await body();
    } finally {
      end();
    }
    return true;
  }
}
