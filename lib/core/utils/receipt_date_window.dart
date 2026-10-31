/// 2.0.155: shared receipt-date helpers for the rep upload screen.
library;

import '../services/ai_receipt_service.dart';

/// True/false when [receiptDate] is inside/outside the campaign window
/// (whole days, inclusive), null when the date or window is unknown.
/// Accepts yyyy/mm/dd (also - or .) before dd/mm/yy, and ignores a trailing
/// time. Uses the same parser as the AI service.
bool? receiptDateWithinCampaign(
  String receiptDate,
  DateTime? start,
  DateTime? end,
) {
  if (start == null && end == null) return null;
  if (receiptDate.trim().isEmpty) return null;
  final parsed = AiReceiptService.parseReceiptDate(
    receiptDate,
    startDate: start,
    endDate: end,
  );
  if (parsed == null) return null;
  final d = DateTime(parsed.year, parsed.month, parsed.day);
  if (start != null) {
    final s = start.toLocal();
    if (d.isBefore(DateTime(s.year, s.month, s.day))) return false;
  }
  if (end != null) {
    final e = end.toLocal();
    if (d.isAfter(DateTime(e.year, e.month, e.day))) return false;
  }
  return true;
}

const String kGenericRejectionReasonAr = 'الفاتورة غير مطابقة لشروط الحملة';

/// Rejection reason used when neither the AI nor the rules gave one.
String fallbackRejectionReason(String? aiMessage) {
  final m = (aiMessage ?? '').trim();
  if (m.isEmpty || m == kGenericRejectionReasonAr) {
    return kGenericRejectionReasonAr;
  }
  return '$kGenericRejectionReasonAr: $m';
}
