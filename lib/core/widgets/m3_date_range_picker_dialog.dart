import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Material Design 3 (M3) Date Range Picker Dialog.
///
/// Complies with official M3 Date Picker specifications:
/// - Contained modal dialog (maxWidth: 380dp - 420dp) without full-screen stretching.
/// - Prominent start/end selection badges with directional connector.
/// - Clear month-by-month calendar navigation.
/// - Continuous range selection band highlighting.
/// - Highly visible bottom action bar with prominent "حفظ النطاق" button (no clipping under debug banners).
/// - Strict validation: Displays clear error warning if start date is chosen but end date is missing.
class M3DateRangePickerDialog extends StatefulWidget {
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final bool isAr;

  const M3DateRangePickerDialog({
    super.key,
    this.initialStartDate,
    this.initialEndDate,
    required this.firstDate,
    required this.lastDate,
    this.isAr = true,
  });

  @override
  State<M3DateRangePickerDialog> createState() => _M3DateRangePickerDialogState();
}

class _M3DateRangePickerDialogState extends State<M3DateRangePickerDialog> {
  late DateTime _displayedMonth;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _errorMessage;

  static const List<String> _arabicMonths = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
  ];

  static const List<String> _englishMonths = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  static const List<String> _arabicWeekDays = ['س', 'ح', 'ن', 'ث', 'ر', 'خ', 'ج'];
  static const List<String> _englishWeekDays = ['Sa', 'Su', 'Mo', 'Tu', 'We', 'Th', 'Fr'];

  @override
  void initState() {
    super.initState();
    _startDate = widget.initialStartDate != null
        ? _stripTime(widget.initialStartDate!)
        : null;
    _endDate = widget.initialEndDate != null
        ? _stripTime(widget.initialEndDate!)
        : null;

    final initialTarget = _startDate ?? DateTime.now();
    _displayedMonth = DateTime(initialTarget.year, initialTarget.month, 1);
  }

  DateTime _stripTime(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  String _formatDate(DateTime dt) {
    final monthName = widget.isAr
        ? _arabicMonths[dt.month - 1]
        : _englishMonths[dt.month - 1];
    return '${dt.day} $monthName ${dt.year}';
  }

  String _formatMonthYear(DateTime dt) {
    final monthName = widget.isAr
        ? _arabicMonths[dt.month - 1]
        : _englishMonths[dt.month - 1];
    return '$monthName ${dt.year}';
  }

  void _onDaySelected(DateTime day) {
    final normalizedDay = _stripTime(day);
    if (normalizedDay.isBefore(_stripTime(widget.firstDate)) ||
        normalizedDay.isAfter(_stripTime(widget.lastDate))) {
      return;
    }

    setState(() {
      _errorMessage = null;

      if (_startDate == null || (_startDate != null && _endDate != null)) {
        _startDate = normalizedDay;
        _endDate = null;
      } else if (_startDate != null && _endDate == null) {
        if (normalizedDay.isBefore(_startDate!)) {
          _startDate = normalizedDay;
          _endDate = null;
        } else {
          _endDate = normalizedDay;
        }
      }
    });
  }

  void _onPreviousMonth() {
    setState(() {
      _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month - 1, 1);
    });
  }

  void _onNextMonth() {
    setState(() {
      _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1, 1);
    });
  }

  void _onSave() {
    if (_startDate == null) {
      setState(() {
        _errorMessage = widget.isAr
            ? 'برجاء تحديد تاريخ البداية والنهاية أولاً'
            : 'Please select both start date and end date first';
      });
      return;
    }

    if (_endDate == null) {
      setState(() {
        _errorMessage = widget.isAr
            ? 'لم تقم بتحديد تاريخ النهاية! برجاء اختيار تاريخ النهاية لاكتمال النطاق.'
            : 'End date is missing! Please select an end date to complete the range.';
      });
      return;
    }

    Navigator.of(context).pop(DateTimeRange(start: _startDate!, end: _endDate!));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isAr = widget.isAr;

    final firstDayOfMonth = DateTime(_displayedMonth.year, _displayedMonth.month, 1);
    final daysInMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1, 0).day;
    // Saturday = 0, Sunday = 1, ..., Friday = 6
    final int leadingEmptyDays = (firstDayOfMonth.weekday + 1) % 7;

    final weekDays = isAr ? _arabicWeekDays : _englishWeekDays;

    return Dialog(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: colorScheme.surfaceTint,
      elevation: 6,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header with Title & Close Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.date_range_rounded, size: 16, color: colorScheme.primary),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            isAr ? 'تحديد نطاق التاريخ' : 'Select Date Range',
                            style: GoogleFonts.cairo(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: isAr ? 'إغلاق' : 'Close',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 2. Date Selection Indicator Badges (Start -> End)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    // Start Date Badge
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr ? 'تاريخ البداية (من)' : 'Start Date (From)',
                            style: GoogleFonts.cairo(
                              fontSize: 10.5,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _startDate != null
                                ? _formatDate(_startDate!)
                                : (isAr ? 'اختر البداية' : 'Select start'),
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _startDate != null ? colorScheme.primary : colorScheme.outline,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    Icon(
                      isAr ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded,
                      size: 16,
                      color: colorScheme.outline,
                    ),
                    const SizedBox(width: 8),

                    // End Date Badge
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr ? 'تاريخ النهاية (إلى)' : 'End Date (To)',
                            style: GoogleFonts.cairo(
                              fontSize: 10.5,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _endDate != null
                                ? _formatDate(_endDate!)
                                : (_startDate != null
                                    ? (isAr ? 'اختر النهاية...' : 'Select end...')
                                    : (isAr ? '—' : '—')),
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _endDate != null
                                  ? colorScheme.primary
                                  : (_startDate != null ? colorScheme.error : colorScheme.outline),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 3. Month & Year Navigation Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: _onPreviousMonth,
                    icon: Icon(isAr ? Icons.chevron_right_rounded : Icons.chevron_left_rounded),
                    tooltip: isAr ? 'الشهر السابق' : 'Previous month',
                  ),
                  Text(
                    _formatMonthYear(_displayedMonth),
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  IconButton(
                    onPressed: _onNextMonth,
                    icon: Icon(isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded),
                    tooltip: isAr ? 'الشهر التالي' : 'Next month',
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // 4. Day-of-Week Header (Sa, Su, Mo, Tu, We, Th, Fr)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: weekDays.map((d) {
                  return Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 6),

              // 5. Calendar Days Grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: leadingEmptyDays + daysInMonth,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 1.5,
                  crossAxisSpacing: 0,
                  childAspectRatio: 1.25,
                ),
                itemBuilder: (context, index) {
                  if (index < leadingEmptyDays) {
                    return const SizedBox.shrink();
                  }

                  final dayNum = index - leadingEmptyDays + 1;
                  final dayDate = DateTime(_displayedMonth.year, _displayedMonth.month, dayNum);
                  final normalizedDay = _stripTime(dayDate);

                  final isStart = _startDate != null && normalizedDay.isAtSameMomentAs(_startDate!);
                  final isEnd = _endDate != null && normalizedDay.isAtSameMomentAs(_endDate!);
                  final isInRange = _startDate != null &&
                      _endDate != null &&
                      normalizedDay.isAfter(_startDate!) &&
                      normalizedDay.isBefore(_endDate!);

                  final isToday = normalizedDay.isAtSameMomentAs(_stripTime(DateTime.now()));
                  final isDisabled = normalizedDay.isBefore(_stripTime(widget.firstDate)) ||
                      normalizedDay.isAfter(_stripTime(widget.lastDate));

                  return GestureDetector(
                    onTap: isDisabled ? null : () => _onDaySelected(dayDate),
                    behavior: HitTestBehavior.opaque,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Range Continuous Connector Band
                        if (_startDate != null && _endDate != null) ...[
                          if (isInRange)
                            Positioned.fill(
                              child: Container(
                                color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                              ),
                            ),
                          if (isStart && !_startDate!.isAtSameMomentAs(_endDate!))
                            Positioned.fill(
                              child: Align(
                                alignment: isAr ? Alignment.centerLeft : Alignment.centerRight,
                                child: Container(
                                  width: 20,
                                  color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                                ),
                              ),
                            ),
                          if (isEnd && !_startDate!.isAtSameMomentAs(_endDate!))
                            Positioned.fill(
                              child: Align(
                                alignment: isAr ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  width: 20,
                                  color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                                ),
                              ),
                            ),
                        ],

                        // Day Circle / Text
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (isStart || isEnd)
                                ? colorScheme.primary
                                : (isToday ? colorScheme.surfaceContainerHighest : Colors.transparent),
                            border: isToday && !isStart && !isEnd
                                ? Border.all(color: colorScheme.primary, width: 1.2)
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$dayNum',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: (isStart || isEnd || isToday) ? FontWeight.bold : FontWeight.w500,
                              color: (isStart || isEnd)
                                  ? colorScheme.onPrimary
                                  : (isDisabled
                                      ? colorScheme.outline.withValues(alpha: 0.4)
                                      : (isInRange
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.onSurface)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 10),

              // 6. Validation Error Message Alert
              if (_errorMessage != null) ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              const Divider(height: 1),
              const SizedBox(height: 12),

              // 7. Bottom Actions: Cancel & Prominent Save Button
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      foregroundColor: colorScheme.onSurfaceVariant,
                    ),
                    child: Text(
                      isAr ? 'إلغاء' : 'Cancel',
                      style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _onSave,
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: Text(
                      isAr ? 'حفظ النطاق' : 'Save Range',
                      style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper function to display the M3 Date Range Picker Dialog.
Future<DateTimeRange?> showM3DateRangePicker({
  required BuildContext context,
  DateTime? initialStartDate,
  DateTime? initialEndDate,
  required DateTime firstDate,
  required DateTime lastDate,
  bool isAr = true,
}) {
  return showDialog<DateTimeRange>(
    context: context,
    builder: (context) => M3DateRangePickerDialog(
      initialStartDate: initialStartDate,
      initialEndDate: initialEndDate,
      firstDate: firstDate,
      lastDate: lastDate,
      isAr: isAr,
    ),
  );
}
