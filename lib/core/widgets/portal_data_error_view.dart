import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Shown instead of empty/zero KPIs when a portal data stream fails, so a
/// permissions problem is visible rather than looking like "no data".
class PortalDataErrorView extends StatelessWidget {
  final Object? error;
  final VoidCallback? onRetry;

  /// Optional text that replaces the default message (TAG-81: the rep link
  /// must not tell an anonymous rep to sign out and in again).
  final String? message;

  /// Optional small technical code shown under the message.
  final String? detail;

  const PortalDataErrorView({
    super.key,
    this.error,
    this.onRetry,
    this.message,
    this.detail,
  });

  static bool isPermissionDenied(Object? e) =>
      e is FirebaseException && e.code == 'permission-denied' ||
      '$e'.contains('permission-denied') ||
      '$e'.contains('PERMISSION_DENIED');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final denied = isPermissionDenied(error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          color: cs.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(denied ? Icons.lock_outline_rounded : Icons.cloud_off_rounded, color: cs.onErrorContainer, size: 36),
                const SizedBox(height: 12),
                Text(
                  message ??
                      (denied
                          ? 'لا توجد صلاحية لعرض بيانات هذه الشركة. يرجى تسجيل الخروج ثم الدخول مرة أخرى.'
                          : 'تعذر تحميل البيانات. تحقق من الاتصال ثم حاول مرة أخرى.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w600),
                ),
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      detail!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onErrorContainer, fontSize: 11),
                    ),
                  ),
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonal(onPressed: onRetry, child: const Text('إعادة المحاولة')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
