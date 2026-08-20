import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/widgets/switch_point_branding.dart';
import '../../../core/widgets/m3_button_groups.dart';
import '../../admin/domain/event_model.dart';
import '../../admin/presentation/campaign_reports_screen.dart';
import '../../validation/presentation/invoices_log_screen.dart';
import 'company_prizes_stock_report_screen.dart';
import '../../../core/utils/url_builder.dart';
import '../../../core/utils/slug_utils.dart';
import '../../../core/widgets/campaign_suspended_screen.dart';

/// Dedicated Executive Company Manager & Partner Portal (بوابة مدير وشريك الشركة)
/// Provides a secure, white-labeled, scoped analytics, invoice audit, and real-time prizes inventory
/// strictly filtered to the company's campaigns and transactions.
class CompanyManagerPortalScreen extends ConsumerStatefulWidget {
  final String companySlug;
  final String? initialEventId;

  const CompanyManagerPortalScreen({
    super.key,
    required this.companySlug,
    this.initialEventId,
  });

  @override
  ConsumerState<CompanyManagerPortalScreen> createState() => _CompanyManagerPortalScreenState();
}

class _CompanyManagerPortalScreenState extends ConsumerState<CompanyManagerPortalScreen> {
  int _selectedTab = 0; // 0 = Analytics & Insights, 1 = Invoice Audit Feed, 2 = Prizes & Stock Balance

  void _copyPortalLink(BuildContext context, AppStrings strings, String effectiveSlug, String? eventId) {
    final url = AppUrlBuilder.buildManagerPortalUrl(effectiveSlug, eventId: eventId);
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${strings.managerPortalLinkCopied}: $url'),
        backgroundColor: Colors.indigo.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copyPromoterLink(BuildContext context, AppStrings strings, String effectiveSlug, String? eventId) {
    final url = AppUrlBuilder.buildPromoterUrl(effectiveSlug, eventId: eventId);
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${strings.promoterLinkCopied}: $url'),
        backgroundColor: Colors.teal.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildScaffoldContent({
    required BuildContext context,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required List<QueryDocumentSnapshot> allDocs,
  }) {
    final allEvents = allDocs
        .map((doc) {
          try {
            return EventModel.fromFirestore(doc);
          } catch (_) {
            return null;
          }
        })
        .whereType<EventModel>()
        .toList();

    // 1. Multi-tier resolution for the active initial event
    EventModel? initialEvent;

    // Tier A: Match by explicit initialEventId
    if (widget.initialEventId != null && widget.initialEventId!.isNotEmpty) {
      final matches = allEvents.where((e) => e.id == widget.initialEventId);
      if (matches.isNotEmpty) {
        initialEvent = matches.first;
      }
    }

    // Tier B: Match if companySlug is actually an event ID
    if (initialEvent == null && widget.companySlug.isNotEmpty) {
      final matches = allEvents.where((e) => e.id == widget.companySlug.trim());
      if (matches.isNotEmpty) {
        initialEvent = matches.first;
      }
    }

    // Tier C: Match by companySlug
    if (initialEvent == null && widget.companySlug.isNotEmpty) {
      final cleanSlug = widget.companySlug.trim().toLowerCase();
      final matches = allEvents.where((e) => e.companySlug.trim().toLowerCase() == cleanSlug).toList();
      if (matches.isNotEmpty) {
        matches.sort((a, b) {
          if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
          final aDate = a.createdAt ?? a.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? b.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
        initialEvent = matches.first;
      }
    }

    // Tier D: Match by targetCompany or brand translation
    if (initialEvent == null && widget.companySlug.isNotEmpty) {
      final cleanSlug = widget.companySlug.trim().toLowerCase();
      final matches = allEvents.where((e) {
        final comp = e.targetCompany.trim().toLowerCase();
        final brandSlug = SlugUtils.toSlug(comp);
        return comp == cleanSlug || comp.contains(cleanSlug) || cleanSlug.contains(comp) || brandSlug == cleanSlug;
      }).toList();
      if (matches.isNotEmpty) {
        matches.sort((a, b) {
          if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
          final aDate = a.createdAt ?? a.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? b.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
        initialEvent = matches.first;
      }
    }

    // 2. Resolve true effectiveSlug and companyDisplayName
    final String effectiveSlug = initialEvent?.companySlug.isNotEmpty == true
        ? initialEvent!.companySlug
        : (widget.companySlug.isNotEmpty ? widget.companySlug : 'almarai');

    String companyDisplayName = initialEvent?.targetCompany ?? '';
    if (companyDisplayName.isEmpty) {
      final matchedEvents = allEvents.where((e) =>
          e.companySlug.toLowerCase() == effectiveSlug.toLowerCase() ||
          e.targetCompany.toLowerCase().contains(effectiveSlug.toLowerCase())).toList();
      if (matchedEvents.isNotEmpty) {
        companyDisplayName = matchedEvents.first.targetCompany;
      }
    }
    if (companyDisplayName.isEmpty) {
      companyDisplayName = SlugUtils.formatSlugToName(effectiveSlug);
    }

    // 3. Resolve all scoped events for this company
    final List<EventModel> companyEvents = allEvents.where((e) {
      if (initialEvent != null && e.id == initialEvent.id) return true;
      final matchSlug = e.companySlug.toLowerCase() == effectiveSlug.toLowerCase();
      final matchName = companyDisplayName.isNotEmpty &&
          e.targetCompany.toLowerCase() == companyDisplayName.toLowerCase();
      return matchSlug || matchName;
    }).toList();

    final bool isManagerSuspended = (initialEvent != null && (!initialEvent.isActive || !initialEvent.isManagerActive)) ||
        (companyEvents.isNotEmpty && companyEvents.every((e) => !e.isActive || !e.isManagerActive));

    if (isManagerSuspended) {
      return CampaignSuspendedScreen(
        portalType: SuspendedPortalType.manager,
        event: initialEvent ?? (companyEvents.isNotEmpty ? companyEvents.first : null),
        companySlug: effectiveSlug,
        companyName: companyDisplayName,
        onRefresh: () => setState(() {}),
      );
    }

    final activeEventId = initialEvent?.id ?? widget.initialEventId;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: SwitchPointHeader(
        subtitle: companyDisplayName,
        customActions: [
          // Copy Promoter Link quick button
          Tooltip(
            message: strings.copyPromoterLink,
            child: IconButton.filledTonal(
              icon: Icon(Icons.qr_code_scanner_rounded, size: isMobile ? 16 : 18),
              padding: EdgeInsets.all(isMobile ? 5 : 8),
              constraints: isMobile ? const BoxConstraints() : null,
              visualDensity: isMobile ? VisualDensity.compact : VisualDensity.standard,
              onPressed: () => _copyPromoterLink(context, strings, effectiveSlug, activeEventId),
            ),
          ),
          SizedBox(width: isMobile ? 2 : 4),
          // Copy Portal Link quick button
          Tooltip(
            message: strings.copyManagerPortalLink,
            child: IconButton.filledTonal(
              icon: Icon(Icons.share_rounded, size: isMobile ? 16 : 18),
              padding: EdgeInsets.all(isMobile ? 5 : 8),
              constraints: isMobile ? const BoxConstraints() : null,
              visualDensity: isMobile ? VisualDensity.compact : VisualDensity.standard,
              onPressed: () => _copyPortalLink(context, strings, effectiveSlug, activeEventId),
            ),
          ),
          SizedBox(width: isMobile ? 2 : 8),
        ],
      ),
      body: Column(
        children: [
          // 1. Executive Top Bar with Company Info & 3-Tab Switcher
          _buildExecutiveHeader(
            context: context,
            colorScheme: colorScheme,
            textTheme: textTheme,
            strings: strings,
            companyName: companyDisplayName,
            campaignsCount: companyEvents.length,
            isAr: isAr,
            isHi: isHi,
            isMobile: isMobile,
          ),

          // 2. Main Executive Content Views
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: [
                // Tab 0: Comprehensive Reports & Analytics
                CampaignReportsScreen(
                  key: ValueKey('reports_${effectiveSlug}_${activeEventId ?? 'all'}'),
                  initialEvent: initialEvent,
                  lockedCompanySlug: effectiveSlug,
                  lockedCompanyName: companyDisplayName,
                  isEmbedded: true,
                ),

                // Tab 1: Invoices Log & Audit
                InvoicesLogScreen(
                  key: ValueKey('invoices_${effectiveSlug}_${activeEventId ?? 'all'}'),
                  initialEventId: activeEventId,
                  lockedCompanySlug: effectiveSlug,
                  lockedCompanyName: companyDisplayName,
                  isEmbedded: true,
                ),

                // Tab 2: Real-time Prizes & Stock Balance System
                CompanyPrizesStockReportScreen(
                  key: ValueKey('prizes_stock_${effectiveSlug}_${activeEventId ?? 'all'}'),
                  initialEventId: activeEventId,
                  lockedCompanySlug: effectiveSlug,
                  lockedCompanyName: companyDisplayName,
                  isEmbedded: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final strings = AppStrings.of(ref);
    final isAr = ref.isArabic;
    final isHi = ref.watch(localeProvider).languageCode == 'hi';
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    FirebaseFirestore? firestore;
    try {
      firestore = ref.watch(firestoreProvider);
    } catch (_) {
      firestore = null;
    }

    Stream<QuerySnapshot>? eventsStream;
    if (firestore != null) {
      try {
        eventsStream = firestore.collection('events').snapshots();
      } catch (_) {
        eventsStream = null;
      }
    }

    if (eventsStream != null) {
      return StreamBuilder<QuerySnapshot>(
        stream: eventsStream,
        builder: (context, snapshot) {
          final allDocs = snapshot.data?.docs ?? [];
          return _buildScaffoldContent(
            context: context,
            colorScheme: colorScheme,
            textTheme: textTheme,
            strings: strings,
            isAr: isAr,
            isHi: isHi,
            isMobile: isMobile,
            allDocs: allDocs,
          );
        },
      );
    }

    return _buildScaffoldContent(
      context: context,
      colorScheme: colorScheme,
      textTheme: textTheme,
      strings: strings,
      isAr: isAr,
      isHi: isHi,
      isMobile: isMobile,
      allDocs: const [],
    );
  }

  Widget _buildExecutiveHeader({
    required BuildContext context,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required AppStrings strings,
    required String companyName,
    required int campaignsCount,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
  }) {
    final analyticsLabel = isMobile
        ? (isAr ? 'التقارير' : (isHi ? 'रिपोर्ट' : 'Reports'))
        : strings.analyticsTitle;
    final invoicesLabel = isMobile
        ? (isAr ? 'الفواتير' : (isHi ? 'इनवॉइस' : 'Invoices'))
        : strings.invoicesAuditTitle;
    final prizesStockLabel = isMobile
        ? (isAr ? 'رصيد الهدايا' : (isHi ? 'उपहार शेष' : 'Prizes Stock'))
        : strings.prizesStockTitle;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 20,
        vertical: isMobile ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 780;

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Mobile Top: Company Brand & Scope Badge
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.primary,
                            colorScheme.secondary,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          Icons.business_rounded,
                          color: colorScheme.onPrimary,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  companyName,
                                  style: GoogleFonts.cairo(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isAr ? 'بوابة الشريك' : (isHi ? 'प्रबंधक' : 'Partner'),
                                  style: GoogleFonts.cairo(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            strings.companyScopeBanner,
                            style: GoogleFonts.cairo(
                              fontSize: 10,
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
                const SizedBox(height: 10),
                // Mobile Bottom: Full-Width 3-Segment Button Group
                M3ConnectedButtonGroup<int>(
                  height: 44,
                  borderRadius: 14,
                  isExpanded: true,
                  segments: [
                    M3ButtonSegment<int>(
                      value: 0,
                      icon: Icons.analytics_rounded,
                      selectedIcon: Icons.analytics_rounded,
                      label: analyticsLabel,
                      tooltip: isAr ? 'التقارير والتحليلات التفاعلية الشاملة للشركة' : 'Comprehensive Analytics & Reports',
                    ),
                    M3ButtonSegment<int>(
                      value: 1,
                      icon: Icons.receipt_long_rounded,
                      selectedIcon: Icons.receipt_long_rounded,
                      label: invoicesLabel,
                      tooltip: isAr ? 'سجل الفواتير وتدقيق المنتجات والمبيعات وعمليات التصدير' : 'Invoices Log, Product Audit & CSV',
                    ),
                    M3ButtonSegment<int>(
                      value: 2,
                      icon: Icons.inventory_2_rounded,
                      selectedIcon: Icons.inventory_2_rounded,
                      label: prizesStockLabel,
                      tooltip: isAr ? 'مراقبة لحظية شاملة لرصيد وجرد الهدايا والمخزون في الفروع' : 'Real-time Prize Stock & Branch Inventory',
                    ),
                  ],
                  selectedValue: _selectedTab,
                  onSelected: (newVal) => setState(() => _selectedTab = newVal),
                ),
              ],
            );
          }

          return Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              // Desktop: Company Brand & Scope Indicator
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primary,
                          colorScheme.secondary,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        Icons.business_rounded,
                        color: colorScheme.onPrimary,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            companyName,
                            style: GoogleFonts.cairo(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isAr ? 'بوابة الشريك' : (isHi ? 'प्रबंधक पोर्टल' : 'Partner Portal'),
                              style: GoogleFonts.cairo(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        strings.companyScopeBanner,
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),

              // Enhanced M3 Connected Button Group for the 3 Portal Tabs
              M3ConnectedButtonGroup<int>(
                height: 48,
                borderRadius: 16,
                segments: [
                  M3ButtonSegment<int>(
                    value: 0,
                    icon: Icons.analytics_rounded,
                    selectedIcon: Icons.analytics_rounded,
                    label: strings.analyticsTitle,
                    tooltip: isAr ? 'التقارير والتحليلات التفاعلية الشاملة للشركة' : 'Comprehensive Analytics & Reports',
                  ),
                  M3ButtonSegment<int>(
                    value: 1,
                    icon: Icons.receipt_long_rounded,
                    selectedIcon: Icons.receipt_long_rounded,
                    label: strings.invoicesAuditTitle,
                    tooltip: isAr ? 'سجل الفواتير وتدقيق المنتجات والمبيعات وعمليات التصدير' : 'Invoices Log, Product Audit & CSV',
                  ),
                  M3ButtonSegment<int>(
                    value: 2,
                    icon: Icons.inventory_2_rounded,
                    selectedIcon: Icons.inventory_2_rounded,
                    label: strings.prizesStockTitle,
                    tooltip: isAr ? 'مراقبة لحظية شاملة لرصيد وجرد الهدايا والمخزون في الفروع' : 'Real-time Prize Stock & Branch Inventory',
                  ),
                ],
                selectedValue: _selectedTab,
                onSelected: (newVal) => setState(() => _selectedTab = newVal),
              ),
            ],
          );
        },
      ),
    );
  }
}
