import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../features/admin/domain/event_model.dart';
import '../localization/app_strings.dart';

/// Unified Executive Screen Header Card across all portal pages
/// Features:
/// - Rounded container with subtle surface colors and borders
/// - Left/Start: Theme-tinted Icon container, bold title, descriptive subtitle
/// - Right/End: Campaign Selector Dropdown & Action buttons (e.g. Export Excel)
/// - Responsive narrow screen stacking (Wrap/Column)
class PortalScreenHeaderCard extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<EventModel> events;
  final String? selectedEventId;
  final ValueChanged<String?> onEventChanged;
  final String? lockedCompanySlug;
  final List<Widget> actions;
  final bool isMobile;

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
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = AppStrings.of(ref);
    final isAr = strings.isAr;

    final titleWidget = Row(
      children: [
        Container(
          padding: EdgeInsets.all(isMobile ? 10 : 12),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
          ),
          child: Icon(
            icon,
            color: colorScheme.onPrimaryContainer,
            size: isMobile ? 22 : 26,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 16 : 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 11 : 12,
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
    for (final evt in events) {
      if (evt.id.isNotEmpty && !uniqueEvents.containsKey(evt.id)) {
        uniqueEvents[evt.id] = evt;
      }
    }
    final cleanEvents = uniqueEvents.values.toList();
    final effectiveSelectedId = (selectedEventId != null &&
            selectedEventId != 'ALL' &&
            selectedEventId != 'all' &&
            cleanEvents.any((e) => e.id == selectedEventId))
        ? selectedEventId!
        : 'ALL';

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
          key: ValueKey('portal_header_event_${effectiveSelectedId}_${cleanEvents.length}'),
          value: effectiveSelectedId,
          isExpanded: true,
          dropdownColor: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: colorScheme.primary),
          style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
          items: [
            DropdownMenuItem<String>(
              value: 'ALL',
              child: Row(
                children: [
                  Icon(Icons.public_rounded, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (lockedCompanySlug != null && lockedCompanySlug!.isNotEmpty)
                          ? '🌐 ${strings.companyAllCampaigns}'
                          : (isAr ? '🌐 كافة الحملات والفعاليات (All)' : '🌐 All Campaigns & Events'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            ...cleanEvents.map((evt) => DropdownMenuItem<String>(
                  value: evt.id,
                  child: Row(
                    children: [
                      Icon(Icons.campaign_rounded, size: 18, color: colorScheme.secondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          evt.retailChainName.isNotEmpty
                              ? '${evt.eventName} (${evt.targetCompany} - ${evt.retailChainName})'
                              : '${evt.eventName} (${evt.targetCompany})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          onChanged: (val) {
            if (val == null || val == 'ALL' || val == 'all') {
              onEventChanged(null);
            } else {
              onEventChanged(val);
            }
          },
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 1150;
        return Container(
          padding: EdgeInsets.all(isMobile ? 14 : 18),
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
                    const SizedBox(height: 12),
                    dropdownWidget,
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        alignment: WrapAlignment.start,
                        children: actions,
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: titleWidget),
                    const SizedBox(width: 16),
                    SizedBox(width: 260, child: dropdownWidget),
                    if (actions.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      ...actions.map((act) => Padding(
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
