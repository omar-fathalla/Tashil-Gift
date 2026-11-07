import 'package:cloud_functions/cloud_functions.dart';

/// Error from the local callable request. Staff stock fallback inspects [code].
class ClaimCallableException extends FirebaseFunctionsException {
  ClaimCallableException({
    required super.code,
    required super.message,
    super.details,
  });
}

/// Staff may write stock directly only when the callable could not be reached.
/// A security or business rejection must stay a rejection.
bool staffCallableMayUseLocalStock({
  required String code,
  required String message,
  required bool emulator,
}) {
  final text = message.toLowerCase();
  const business = {
    'failed-precondition',
    'permission-denied',
    'unauthenticated',
    'invalid-argument',
    'resource-exhausted',
    'aborted',
    'already-exists',
    'out-of-range',
    'cancelled',
    'data-loss',
  };
  if (business.contains(code)) return false;
  if (text.contains('campaign not found') ||
      text.contains('receipt not found') ||
      text.contains('app check') ||
      text.contains('already claimed') ||
      text.contains('not enough prize') ||
      text.contains('الهدية لا تطابق') ||
      text.contains('الكمية أكبر')) {
    return false;
  }
  if (code == 'not-found' || code == 'unimplemented' || code == 'unavailable') {
    return true;
  }
  if (!emulator || (code != 'internal' && code != 'unknown')) return false;
  return text.contains('connection refused') ||
      text.contains('xmlhttprequest') ||
      text.contains('failed host lookup') ||
      text.contains('socketexception') ||
      text.contains('clientexception');
}
