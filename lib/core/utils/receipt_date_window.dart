/// 2.0.155: shared receipt-date helpers for the rep upload screen.
library;

import '../services/ai_receipt_service.dart';

// ---------------------------------------------------------------------------
// 2.0.162: campaign date window in Cairo time (Africa/Cairo).
//
// Campaign start/end are whole calendar days in Cairo, both INCLUSIVE:
//   * the campaign opens at Cairo 00:00 of the start day;
//   * it closes (cutoff) at Cairo 00:00 of the day AFTER the end day;
//   * a receipt dated on any day from the start day to the end day counts.
// Everything is computed from the UTC instant, so the device timezone of the
// admin or the rep never changes the result.
// ---------------------------------------------------------------------------

/// Overridable clock for tests.
DateTime Function() campaignClock = DateTime.now;

DateTime _lastWeekdayOfMonth(int year, int month, int weekday) {
  var d = DateTime.utc(year, month + 1, 0); // last day of month
  while (d.weekday != weekday) {
    d = d.subtract(const Duration(days: 1));
  }
  return d;
}

/// Cairo UTC offset (hours) at [instant].
/// Egypt uses UTC+2, with summer time UTC+3 (2023 onwards) from 00:00 local
/// on the last Friday of April to 24:00 local on the last Thursday of October.
int cairoUtcOffsetHours(DateTime instant) {
  final u = instant.toUtc();
  if (u.year < 2023) return 2;
  final startDay = _lastWeekdayOfMonth(u.year, 4, DateTime.friday);
  final dstStartUtc = startDay.subtract(const Duration(hours: 2));
  final endDay = _lastWeekdayOfMonth(u.year, 10, DateTime.thursday);
  final dstEndUtc = endDay.add(const Duration(hours: 24 - 3));
  return (!u.isBefore(dstStartUtc) && u.isBefore(dstEndUtc)) ? 3 : 2;
}

/// Cairo calendar day of [instant], as a plain local `DateTime(y, m, d)`
/// (same shape as [AiReceiptService.parseReceiptDate] results).
DateTime cairoCalendarDay(DateTime instant) {
  final u = instant.toUtc();
  final c = u.add(Duration(hours: cairoUtcOffsetHours(u)));
  return DateTime(c.year, c.month, c.day);
}

/// The UTC instant of Cairo 00:00 on calendar day (y, m, d).
DateTime cairoStartOfDay(int year, int month, int day) {
  final base = DateTime.utc(year, month, day);
  final summer = base.subtract(const Duration(hours: 3));
  if (cairoUtcOffsetHours(summer) == 3) return summer;
  return base.subtract(const Duration(hours: 2));
}

/// First day of the campaign (Cairo calendar day), or null.
DateTime? campaignFirstDay(DateTime? start) =>
    start == null ? null : cairoCalendarDay(start);

/// Last INCLUSIVE day of the campaign (Cairo calendar day), or null.
DateTime? campaignLastDay(DateTime? end) =>
    end == null ? null : cairoCalendarDay(end);

/// Instant the campaign opens (Cairo 00:00 of the start day).
DateTime? campaignOpensAt(DateTime? start) {
  final d = campaignFirstDay(start);
  return d == null ? null : cairoStartOfDay(d.year, d.month, d.day);
}

/// Instant the campaign closes: Cairo 00:00 of the day after the end day.
DateTime? campaignCutoff(DateTime? end) {
  final d = campaignLastDay(end);
  return d == null ? null : cairoStartOfDay(d.year, d.month, d.day + 1);
}

/// True once Cairo time has reached the day after the end day.
bool isCampaignExpired(DateTime? end, {DateTime? now}) {
  final cut = campaignCutoff(end);
  if (cut == null) return false;
  return !(now ?? campaignClock()).toUtc().isBefore(cut);
}

/// True before Cairo 00:00 of the start day.
bool isCampaignNotStarted(DateTime? start, {DateTime? now}) {
  final open = campaignOpensAt(start);
  if (open == null) return false;
  return (now ?? campaignClock()).toUtc().isBefore(open);
}

int _key(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

/// Whether calendar day [receiptDay] (y/m/d only) is before the first day.
bool receiptDayBeforeStart(DateTime receiptDay, DateTime? start) {
  final f = campaignFirstDay(start);
  return f != null && _key(receiptDay) < _key(f);
}

/// Whether calendar day [receiptDay] (y/m/d only) is after the last day.
bool receiptDayAfterEnd(DateTime receiptDay, DateTime? end) {
  final l = campaignLastDay(end);
  return l != null && _key(receiptDay) > _key(l);
}

/// Inclusive whole-day check of a receipt calendar day against the window.
bool receiptDayInCampaign(DateTime receiptDay, DateTime? start, DateTime? end) =>
    !receiptDayBeforeStart(receiptDay, start) &&
    !receiptDayAfterEnd(receiptDay, end);

/// d/M/yyyy of the campaign's first day (Cairo), '' when null.
String campaignFirstDayLabel(DateTime? start) {
  final d = campaignFirstDay(start);
  return d == null ? '' : '${d.day}/${d.month}/${d.year}';
}

/// d/M/yyyy of the campaign's last inclusive day (Cairo), '' when null.
String campaignLastDayLabel(DateTime? end) {
  final d = campaignLastDay(end);
  return d == null ? '' : '${d.day}/${d.month}/${d.year}';
}

/// True/false when [receiptDate] is inside/outside the campaign window
/// (whole Cairo days, inclusive), null when the date or window is unknown.
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
  return receiptDayInCampaign(parsed, start, end);
}

/// Arabic rejection reason when [receiptDate] is outside the campaign
/// window, or null when it is inside or cannot be checked.
String? campaignReceiptDateRejection(
  String receiptDate,
  DateTime? start,
  DateTime? end,
) {
  if (start == null && end == null) return null;
  final raw = receiptDate.trim();
  if (raw.isEmpty) return null;
  final parsed = AiReceiptService.parseReceiptDate(
    raw,
    startDate: start,
    endDate: end,
  );
  if (parsed == null) return null;
  if (receiptDayBeforeStart(parsed, start)) {
    return 'تاريخ الشراء بالفاتورة ($raw) أقدم من تاريخ بداية الحملة (${campaignFirstDayLabel(start)}). الشراء غير مشمول بالعرض.';
  }
  if (receiptDayAfterEnd(parsed, end)) {
    return 'تاريخ الشراء بالفاتورة ($raw) متأخر عن آخر يوم في الحملة (${campaignLastDayLabel(end)}). عذراً، انتهى العرض.';
  }
  return null;
}

/// 2.0.162 (issue #3): Arabic error when the last day is before the first
/// day, null when the dates are acceptable (either may be empty).
String? campaignDatesError(DateTime? start, DateTime? end) {
  final f = campaignFirstDay(start);
  final l = campaignLastDay(end);
  if (f == null || l == null) return null;
  if (_key(l) < _key(f)) {
    return 'لا يمكن الحفظ: آخر يوم في الحملة (${l.day}/${l.month}/${l.year}) '
        'قبل تاريخ البداية (${f.day}/${f.month}/${f.year}). '
        'يرجى تعديل التاريخين.';
  }
  return null;
}

/// Cairo 00:00 instant for a day picked in a date picker (only its
/// y/m/d are used, so the admin's device timezone does not matter).
DateTime pickedDayToCairoInstant(DateTime picked) =>
    cairoStartOfDay(picked.year, picked.month, picked.day);

const String kGenericRejectionReasonAr = 'الفاتورة غير مطابقة لشروط الحملة';

/// Rejection reason used when neither the AI nor the rules gave one.
String fallbackRejectionReason(String? aiMessage) {
  final m = (aiMessage ?? '').trim();
  if (m.isEmpty || m == kGenericRejectionReasonAr) {
    return kGenericRejectionReasonAr;
  }
  return '$kGenericRejectionReasonAr: $m';
}
