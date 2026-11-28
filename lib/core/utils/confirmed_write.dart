import 'dart:async';

/// N-01 / N-01b (TAG-35): a write that the server has not confirmed inside
/// the wait. Callers show «لسه ما اتأكدش» (and «تحقق» where they can) instead
/// of a success message. [path] is the document to read back, '' for a batch.
class WriteNotConfirmedException implements Exception {
  final String path;

  /// True when the write deletes [path] (confirmed once it is gone).
  final bool isDelete;

  const WriteNotConfirmedException(this.path, {this.isDelete = false});

  static const message = 'الحفظ لسه ما اتأكدش. دوس «تحقق» بعد ما النت يرجع.';

  @override
  String toString() => message;
}

const Duration kConfirmedWriteWait = Duration(seconds: 15);

/// Waits for the server to confirm [write]. Still pending after [wait] →
/// throws [WriteNotConfirmedException] (the write keeps syncing in the
/// background); it never counts as saved before the server answered.
Future<void> confirmedWrite(
  Future<void> write,
  String path, {
  bool isDelete = false,
  Duration wait = kConfirmedWriteWait,
}) async {
  unawaited(write.then((_) {}, onError: (Object _) {}));
  try {
    await write.timeout(wait);
  } on TimeoutException {
    throw WriteNotConfirmedException(path, isDelete: isDelete);
  }
}
