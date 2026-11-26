import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../features/admin/domain/event_model.dart';
import '../localization/app_strings.dart';

/// Unified Executive Screen Header Card across all portal pages
/// Features:
/// - Rounded container with subtle surface colors and borders
/// - Left/Start: Theme-tinted Icon container, bold title, descriptive subtitle
/// - Right/End: Campaign Selector Dropdown (showing active by default) & Action buttons (e.g. Export CSV)
/// - One-touch Active Campaigns vs All Campaigns toggle button & menu option
/// - Responsive narrow screen stacking (Wrap/Column)
class PortalScreenHeaderCard extends ConsumerStatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<EventModel> events;
  final String? selectedEventId;
  final ValueChanged<String?> onEventChanged;
  final String? lockedCompanySlug;
  final List<Widget> actions;
  final bool isMobile;
  final bool defaultOnlyActive;
  final bool enableActiveFilterToggle;
  final ValueChanged<bool>? onActiveFilterChanged;

  /// When false the campaign selector (and its active-filter toggle) is not
  /// rendered. Used by screens locked to a single campaign (`/ep/` sessions).
  final bool showEventSelector;

  const PortalScreenHeaderCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.events,
    this.selectedEventId,
    required this.onEventChanged,
    this.lockedCompanySlug,
    this.actions = const [],
    this.isMobile = false,
    this.defaultOnlyActive = true,
    this.enableActiveFilterToggle = true,
    this.onActiveFilterChanged,
    this.showEventSelector = true,
  });

  @override
  ConsumerState<PortalScreenHeaderCard> createState() => _PortalScreenHeaderCardState();
}

class _PortalScreenHeaderCardState extends ConsumerState<PortalScreenHeaderCard> {
  late bool _showOnlyActive;

  @override
  void initState() {
    super.initState();
    _showOnlyActive = widget.defaultOnlyActive;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = AppStrings.of(ref);
    final isAr = strings.isAr;

    final titleWidget = Row(
      children: [
        Container(
          padding: EdgeInsets.all(widget.isMobile ? 10 : 12),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(widget.isMobile ? 12 : 16),
          ),
          child: Icon(
            widget.icon,
            color: colorScheme.onPrimaryContainer,
            size: widget.isMobile ? 22 : 26,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: GoogleFonts.cairo(
                  fontSize: widget.isMobile ? 16 : 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.subtitle.isNotEmpty)
                Text(
                  widget.subtitle,
                  style: GoogleFonts.cairo(
                    fontSize: widget.isMobile ? 11 : 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );

    final uniqueEvents = <String, EventModel>{};
    for (final evt in widget.events) {
      if (evt.id.isNotEmpty && !uniqueEvents.containsKey(evt.id)) {
        uniqueEvents[evt.id] = evt;
      }
    }
    final cleanEvents = uniqueEvents.values.toList();
    final activeEvents = cleanEvents.where((e) => e.isActive && !e.isExpired).toList();

    // Default to active events when _showOnlyActive is true
    final displayedEvents = (_showOnlyActive && activeEvents.isNotEmpty)
        ? cleanEvents.where((e) {
            if (widget.selectedEventId != null && e.id == widget.selectedEventId) return true;
            return e.isActive && !e.isExpired;
          }).toList()
        : cleanEvents;

    final effectiveSelectedId = (widget.selectedEventId != null &&
            widget.selectedEventId != 'ALL' &&
            widget.selectedEventId != 'all' &&
            displayedEvents.any((e) => e.id == widget.selectedEventId))
        ? widget.selectedEventId!
        : 'ALL';

    final showDropdownToggleItem = widget.enableActiveFilterToggle && cleanEvents.length > activeEvents.length;

    Widget? toggleActiveButton;
    if (widget.enableActiveFilterToggle && cleanEvents.length > activeEvents.length) {
      toggleActiveButton = Tooltip(
        message: _showOnlyActive
            ? (isAr
                ? 'يتم عرض الفعاليات النشطة فقط (${activeEvents.length} من أصل ${cleanEvents.length}). اضغط لإظهار كافة الفعاليات'
                : 'Showing active events only (${activeEvents.length} of ${cleanEvents.length}). Click to show all')
            : (isAr
                ? 'يتم عرض كافة الفعاليات (${cleanEvents.length}). اضغط للعودة إلى النشطة فقط (${activeEvents.length})'
                : 'Showing all events (${cleanEvents.length}). Click to show active only (${activeEvents.length})'),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                _showOnlyActive = !_showOnlyActive;
              });
              widget.onActiveFilterChanged?.call(_showOnlyActive);
            },
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _showOnlyActive
                    ? colorScheme.primaryContainer.withValues(alpha: 0.7)
                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _showOnlyActive
                      ? colorScheme.primary.withValues(alpha: 0.5)
                      : colorScheme.outlineVariant.withValues(alpha: 0.8),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _showOnlyActive ? Icons.bolt_rounded : Icons.public_rounded,
                    size: 16,
                    color: _showOnlyActive ? colorScheme.onPrimaryContainer : colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _showOnlyActive
                        ? (isAr ? 'النشطة فقط' : 'Active Only')
                        : (isAr ? 'كافة الحملات' : 'All Events'),
                    style: GoogleFonts.cairo(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: _showOnlyActive ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: _showOnlyActive
                          ? colorScheme.primary
                          : colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_showOnlyActive ? activeEvents.length : cleanEvents.length}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _showOnlyActive ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final dropdownWidget = Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: ValueKey('portal_header_event_${effectiveSelectedId}_${_showOnlyActive}_${displayedEvents.length}'),
          value: effectiveSelectedId,
          isExpanded: true,
          itemHeight: 62.0,
          menuMaxHeight: 460,
          dropdownColor: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: colorScheme.primary),
          style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
          selectedItemBuilder: (BuildContext context) {
            return [
              // Closed view for 'ALL'
              Row(
                children: [
                  Icon(
                    _showOnlyActive ? Icons.bolt_rounded : Icons.public_rounded,
                    size: 17,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (widget.lockedCompanySlug != null && widget.lockedCompanySlug!.isNotEmpty)
                          ? strings.companyAllCampaigns
                          : (_showOnlyActive
                              ? (isAr ? 'كافة الحملات النشطة (${activeEvents.length})' : 'All Active Campaigns (${activeEvents.length})')
                              : (isAr ? 'كافة الحملات والفعاليات (${cleanEvents.length})' : 'All Campaigns & Events (${cleanEvents.length})')),
                      style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              // Closed view for each campaign
              ...displayedEvents.map((evt) => Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3), width: 0.8),
                        ),
                        child: Text(
                          evt.targetCompany.isNotEmpty ? evt.targetCompany : (isAr ? 'عام' : 'General'),
                          style: GoogleFonts.cairo(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          evt.eventName,
                          style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )),
              if (showDropdownToggleItem)
                const SizedBox.shrink(),
            ];
          },
          items: [
            DropdownMenuItem<String>(
              value: 'ALL',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _showOnlyActive ? Icons.bolt_rounded : Icons.public_rounded,
                        size: 18,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            (widget.lockedCompanySlug != null && widget.lockedCompanySlug!.isNotEmpty)
                                ? strings.companyAllCampaigns
                                : (_showOnlyActive
                                    ? (isAr ? 'كافة الحملات النشطة (${activeEvents.length})' : 'All Active Campaigns (${activeEvents.length})')
                                    : (isAr ? 'كافة الحملات والفعاليات (${cleanEvents.length})' : 'All Campaigns & Events (${cleanEvents.length})')),
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _showOnlyActive
                                ? (isAr ? 'عرض فواتير جميع الفعاليات النشطة حالياً' : 'Audited invoices for all active events')
                                : (isAr ? 'عرض شامل لكافة الفواتير والفعاليات المسجلة' : 'Comprehensive view across all events'),
                            style: GoogleFonts.cairo(
                              fontSize: 10.5,
                              color: colorScheme.onSurfaceVariant,
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
            ),
            ...displayedEvents.map((evt) {
              final isEvtActive = evt.isActive && !evt.isExpired;
              return DropdownMenuItem<String>(
                value: evt.id,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: isEvtActive
                              ? colorScheme.primaryContainer.withValues(alpha: 0.8)
                              : colorScheme.secondaryContainer.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.campaign_rounded,
                          size: 18,
                          color: isEvtActive ? colorScheme.onPrimaryContainer : colorScheme.secondary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    evt.eventName,
                                    style: GoogleFonts.cairo(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: isEvtActive
                                        ? colorScheme.primaryContainer
                                        : colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isEvtActive ? (isAr ? 'نشطة' : 'Active') : (isAr ? 'منتهية' : 'Ended'),
                                    style: GoogleFonts.cairo(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: isEvtActive ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: colorScheme.primary.withValues(alpha: 0.3),
                                      width: 0.7,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.business_rounded, size: 10, color: colorScheme.primary),
                                      const SizedBox(width: 3),
                                      Text(
                                        evt.targetCompany.isNotEmpty ? evt.targetCompany : (isAr ? 'عام' : 'General'),
                                        style: GoogleFonts.cairo(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (evt.retailChainName.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.storefront_rounded, size: 10, color: colorScheme.onSurfaceVariant),
                                          const SizedBox(width: 3),
                                          Flexible(
                                            child: Text(
                                              evt.retailChainName,
                                              style: GoogleFonts.cairo(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: colorScheme.onSurfaceVariant,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            if (showDropdownToggleItem)
              DropdownMenuItem<String>(
                value: '__TOGGLE_ACTIVE_FILTER__',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colorScheme.primary.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _showOnlyActive ? Icons.unfold_more_rounded : Icons.filter_alt_rounded,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _showOnlyActive
                            ? (isAr
                                ? 'إظهار كافة الحملات والفعاليات المنتهية (${cleanEvents.length})'
                                : 'Show All Campaigns Including Ended (${cleanEvents.length})')
                            : (isAr
                                ? 'العودة لعرض الحملات النشطة فقط (${activeEvents.length})'
                                : 'Return to Active Campaigns Only (${activeEvents.length})'),
                        style: GoogleFonts.cairo(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          onChanged: (val) {
            if (val == '__TOGGLE_ACTIVE_FILTER__') {
              setState(() {
                _showOnlyActive = !_showOnlyActive;
              });
              widget.onActiveFilterChanged?.call(_showOnlyActive);
              return;
            }
            if (val == null || val == 'ALL' || val == 'all') {
              widget.onEventChanged(null);
            } else {
              widget.onEventChanged(val);
            }
          },
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 1180;
        return Container(
          padding: EdgeInsets.all(widget.isMobile ? 14 : 18),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    titleWidget,
                    if (widget.showEventSelector) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: dropdownWidget),
                          if (toggleActiveButton != null) ...[
                            const SizedBox(width: 8),
                            toggleActiveButton,
                          ],
                        ],
                      ),
                    ],
                    if (widget.actions.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        alignment: WrapAlignment.start,
                        children: widget.actions,
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: titleWidget),
                    if (widget.showEventSelector) ...[
                      const SizedBox(width: 14),
                      SizedBox(width: 300, child: dropdownWidget),
                      if (toggleActiveButton != null) ...[
                        const SizedBox(width: 8),
                        toggleActiveButton,
                      ],
                    ],
                    if (widget.actions.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      ...widget.actions.map((act) => Padding(
                            padding: const EdgeInsetsDirectional.only(start: 6),
                            child: act,
                          )),
                    ],
                  ],
                ),
        );
      },
    );
  }
}
