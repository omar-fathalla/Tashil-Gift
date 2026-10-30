/// 2.0.147: classifies a failed receipt save (Firestore/Storage rejection)
/// into a precise rep-facing reason instead of the generic
/// "تعذّر حفظ الفاتورة". Pure logic so it is unit-testable.
library;

import 'dart:async';

enum ReceiptSaveFailureKind {
  alreadyUploaded,
  sessionExpired,
  campaignStopped,
  branchNotInCampaign,
  invalidData,
  permissionDenied,
}

class ReceiptSaveFailure {
  final ReceiptSaveFailureKind kind;
  final String? field;
  final String? code;
  const ReceiptSaveFailure(this.kind, {this.field, this.code});
}

/// Extracts a short error code (e.g. permission-denied) from any exception.
String receiptErrorCode(Object error) {
  // 2.0.151+212: timeouts report "timeout", never "unknown".
  if (error is TimeoutException) return 'timeout';
  try {
    final dynamic e = error;
    final c = e.code;
    if (c is String && c.isNotEmpty) {
      return (c == 'deadline-exceeded' || c == 'deadline_exceeded') ? 'timeout' : c;
    }
  } catch (_) {}
  final s = error.toString().toLowerCase();
  for (final c in ['permission-denied', 'unauthenticated', 'failed-precondition', 'not-found', 'unauthorized']) {
    if (s.contains(c)) return c;
  }
  if (s.contains('insufficient permissions')) return 'permission-denied';
  if (s.contains('timeoutexception') || s.contains('timed out') || s.contains('deadline-exceeded')) return 'timeout';
  return 'unknown';
}

bool _tooLong(Object? v, int max) => v is String && v.length > max;

/// Mirrors validAnonymousReceipt in firestore.rules (read-only copy; rules are
/// unchanged) and returns the Arabic name of the first invalid field, or null.
String? invalidReceiptField(Map<String, dynamic> data) {
  if (data.length > 80) return 'عدد بيانات الفاتورة';
  final campaignId = data['campaignId'];
  if (campaignId is! String || campaignId.isEmpty || campaignId.length > 128) return 'رقم الحملة';
  final companySlug = data['companySlug'];
  if (companySlug is! String || companySlug.isEmpty || companySlug.length > 128) return 'كود الشركة';
  if (_tooLong(data['receipt_number'], 80) || (data.containsKey('receipt_number') && data['receipt_number'] is! String)) return 'رقم الفاتورة';
  if (_tooLong(data['customerPhone'], 32) || (data.containsKey('customerPhone') && data['customerPhone'] != null && data['customerPhone'] is! String)) return 'رقم الهاتف';
  if (_tooLong(data['customerName'], 160)) return 'اسم العميل';
  if (data.containsKey('total_value')) {
    final t = data['total_value'];
    if (t is! num || t < 0 || t >= 1000000000) return 'قيمة الفاتورة';
  }
  if (data.containsKey('extracted_products')) {
    final p = data['extracted_products'];
    if (p is! List || p.length > 80) return 'قائمة المنتجات';
  }
  return null;
}

/// Order: already uploaded > session > campaign > branch > field > raw code.
ReceiptSaveFailure diagnoseReceiptSaveFailure({
  required Object error,
  Map<String, dynamic>? data,
  bool alreadyUploaded = false,
  String? currentUid,
  bool? campaignActive,
  bool? branchInCampaign,
}) {
  final code = receiptErrorCode(error);
  if (alreadyUploaded) return const ReceiptSaveFailure(ReceiptSaveFailureKind.alreadyUploaded);
  final submitted = data?['submittedByUid']?.toString() ?? '';
  if (code == 'unauthenticated' ||
      currentUid == null || currentUid.isEmpty ||
      (data != null && submitted != currentUid)) {
    return ReceiptSaveFailure(ReceiptSaveFailureKind.sessionExpired, code: code);
  }
  if (campaignActive == false) return ReceiptSaveFailure(ReceiptSaveFailureKind.campaignStopped, code: code);
  if (branchInCampaign == false) return ReceiptSaveFailure(ReceiptSaveFailureKind.branchNotInCampaign, code: code);
  final field = data == null ? null : invalidReceiptField(data);
  if (field != null) return ReceiptSaveFailure(ReceiptSaveFailureKind.invalidData, field: field, code: code);
  return ReceiptSaveFailure(ReceiptSaveFailureKind.permissionDenied, code: code);
}

/// Approved texts (Mohamed, 2026-10-29 19:17).
String receiptSaveFailureMessage(
  ReceiptSaveFailure f, {
  String? uploadedAt,
  String? branch,
  String? status,
}) {
  String v(String? s) => (s == null || s.trim().isEmpty) ? 'غير معروف' : s.trim();
  switch (f.kind) {
    case ReceiptSaveFailureKind.alreadyUploaded:
      return 'هذه الفاتورة مرفوعة بالفعل بتاريخ ${v(uploadedAt)} من فرع ${v(branch)} — حالتها: ${v(status)}. لا يمكن رفعها مرة أخرى.';
    case ReceiptSaveFailureKind.sessionExpired:
      return 'انتهت جلسة الرابط. أعد فتح رابط الحملة من الرسالة الأصلية ثم ارفع الفاتورة مرة أخرى.';
    case ReceiptSaveFailureKind.campaignStopped:
      return 'الحملة متوقفة حاليًا ولا تقبل فواتير جديدة. تواصل مع المشرف.';
    case ReceiptSaveFailureKind.branchNotInCampaign:
      return 'الفرع ${v(branch)} غير مسجّل في هذه الحملة، لذلك لم يتم حفظ الفاتورة.';
    case ReceiptSaveFailureKind.invalidData:
      return 'بيانات الفاتورة غير مقبولة: ${v(f.field)} غير صالح. صحّح البيانات ثم حاول مرة أخرى.';
    case ReceiptSaveFailureKind.permissionDenied:
      return 'تعذّر حفظ الفاتورة: تم رفض صلاحية الحفظ (${v(f.code)}). أرسل لقطة الشاشة للمشرف.';
  }
}
