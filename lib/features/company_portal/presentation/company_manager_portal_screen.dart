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
import '../../../core/utils/url_builder.dart';
import '../../../core/utils/slug_utils.dart';


/// Dedicated Executive Company Manager & Partner Portal (بوابة مدير وشريك الشركة)
/// Provides a secure, white-labeled, scoped analytics and invoice audit environment
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
  int _selectedTab = 0; // 0 = Analytics & Insights, 1 = Invoice Audit Feed

  void _copyPortalLink(BuildContext context, AppStrings strings) {
    final url = AppUrlBuilder.buildManagerPortalUrl(widget.companySlug);
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${strings.managerPortalLinkCopied}: $url'),
        backgroundColor: Colors.indigo.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copyPromoterLink(BuildContext context, AppStrings strings) {
    final url = AppUrlBuilder.buildPromoterUrl(widget.companySlug);
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
    final companyEvents = allDocs
        .map((doc) {
          try {
            return EventModel.fromFirestore(doc);
          } catch (_) {
            return null;
          }
        })
        .whereType<EventModel>()
        .where((e) =>
            e.companySlug.toLowerCase() == widget.companySlug.toLowerCase() ||
            e.targetCompany.toLowerCase().contains(widget.companySlug.toLowerCase()))
        .toList();

    // Resolve company display name from existing events or format slug
    String companyDisplayName = '';
    if (companyEvents.isNotEmpty) {
      companyDisplayName = companyEvents.first.targetCompany;
    }
    if (companyDisplayName.isEmpty) {
      companyDisplayName = SlugUtils.formatSlugToName(widget.companySlug);
    }

    EventModel? initialEvent;
    if (widget.initialEventId != null && widget.initialEventId!.isNotEmpty) {
      final matches = companyEvents.where((e) => e.id == widget.initialEventId);
      if (matches.isNotEmpty) {
        initialEvent = matches.first;
      }
    }

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
              onPressed: () => _copyPromoterLink(context, strings),
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
              onPressed: () => _copyPortalLink(context, strings),
            ),
          ),
          SizedBox(width: isMobile ? 2 : 8),
        ],
      ),
      body: Column(
        children: [
          // 1. Executive Top Bar with Company Info & Tab Switcher
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
                  key: ValueKey('reports_${widget.companySlug}'),
                  initialEvent: initialEvent,
                  lockedCompanySlug: widget.companySlug,
                  lockedCompanyName: companyDisplayName,
                  isEmbedded: true,
                ),

                // Tab 1: Invoices Log & Audit
                InvoicesLogScreen(
                  key: ValueKey('invoices_${widget.companySlug}'),
                  lockedCompanySlug: widget.companySlug,
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
        ? (isAr ? 'التقارير والتحليلات' : (isHi ? 'विश्लेषण और रिपोर्ट' : 'Analytics & Reports'))
        : strings.analyticsTitle;
    final invoicesLabel = isMobile
        ? (isAr ? 'سجل الفواتير والتدقيق' : (isHi ? 'इनवॉइस लॉग' : 'Invoices & Audit'))
        : strings.invoicesAuditTitle;

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
          final isNarrow = constraints.maxWidth < 680;

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
                // Mobile Bottom: Full-Width 2-Segment Button Group
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

              // Enhanced M3 Connected Button Group for the 2 Portal Tabs
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
