/// 2.0.155: fire-and-forget report of a failed receipt save to the
/// logReceiptSaveFailure callable (log only, rate limited server-side).
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_version_config.dart';
import 'firebase_scope.dart';

/// Short step codes shown in the error dialog and sent to the log.
abstract final class ReceiptSaveStep {
  static const session = 'session';
  static const lookup = 'lookup';
  static const ai = 'ai';
  static const dupCheck = 'dup_check';
  static const storage = 'storage';
  static const replace = 'replace';
  static const save = 'save';
  static const after = 'after_save';
}

/// Error code with the failing step, e.g. "permission-denied @ save".
String errorCodeWithStep(String? code, String? step) {
  final c = (code ?? '').trim();
  final s = (step ?? '').trim();
  if (s.isEmpty) return c;
  return c.isEmpty ? '@ $s' : '$c @ $s';
}

Future<void> reportReceiptSaveFailure({
  required String step,
  required String code,
  required Object error,
  String? uid,
  String? receiptNumber,
  String? campaignId,
  String? companySlug,
}) async {
  try {
    await scopedFunctions()
        .httpsCallable(
          'logReceiptSaveFailure',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
        )
        .call<dynamic>({
          'step': step,
          'code': code,
          'message': error.toString(),
          'clientUid': uid ?? '',
          'receiptNumber': receiptNumber ?? '',
          'campaignId': campaignId ?? '',
          'companySlug': companySlug ?? '',
          'appVersion': AppVersionConfig.appVersion,
        });
  } catch (e) {
    debugPrint('Receipt save failure report not sent: $e');
  }
}
