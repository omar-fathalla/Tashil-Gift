import 'package:al_mraay/core/utils/error_handler.dart';

/// Runs a gift claim, retrying ONCE on failure. "Already claimed" (e.g. the
/// first attempt succeeded but its response was lost) counts as success, so
/// a retry, re-render or back navigation can never decrement stock twice:
/// the server transaction blocks a second claim of the same receipt.
Future<void> runClaimWithSingleRetry(
  Future<void> Function() call, {
  Duration delay = const Duration(milliseconds: 1200),
}) async {
  try {
    await call();
  } catch (e) {
    if (AppErrorHandler.isAlreadyClaimedError(e)) return;
    await Future<void>.delayed(delay);
    try {
      await call();
    } catch (e2) {
      if (AppErrorHandler.isAlreadyClaimedError(e2)) return;
      rethrow;
    }
  }
}

/// Game claims (wheel/scratch/choose/mystery) run automatically on the game
/// result. Only the LAST chance is retried: the server then blocks a second
/// claim, so a retry is idempotent. Earlier chances are not retried because a
/// lost response could otherwise decrement stock twice.
Future<void> runGameClaim(
  Future<void> Function() call, {
  required bool isFinalChance,
  Duration delay = const Duration(milliseconds: 1200),
}) {
  if (isFinalChance) return runClaimWithSingleRetry(call, delay: delay);
  return call();
}
