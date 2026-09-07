import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/widgets/switch_point_branding.dart';
import '../../../core/constants/country_currency_config.dart';
import '../../../core/constants/app_version_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../admin/domain/event_model.dart';
import '../../admin/presentation/campaign_reports_screen.dart';
import '../../validation/presentation/invoices_log_screen.dart';
import 'company_vouchers_report_screen.dart';
import 'branch_stock_balances_screen.dart';
import 'daily_branch_sales_screen.dart';
import 'campaigns_comparison_analytics_screen.dart';
import '../../../core/utils/url_builder.dart';
import '../../../core/utils/slug_utils.dart';
import '../../../core/widgets/campaign_suspended_screen.dart';
import '../../client_portal/presentation/client_receipt_upload_screen.dart';

/// Navigation destination model for Partner Portal Dashboard
class _PortalNavItem {
  final int index;
  final IconData icon;
  final IconData selectedIcon;
  final String title;
  final String subtitle;
  final String tooltip;
  final Color accentColor;

  const _PortalNavItem({
    required this.index,
    required this.icon,
    required this.selectedIcon,
    required this.title,
    required this.subtitle,
    required this.tooltip,
    required this.accentColor,
  });
}

/// Dedicated Executive Company Manager & Partner Portal (بوابة مدير وشريك الشركة)
/// Provides a modern M3 Dashboard layout with a right-side collapsible sidebar navigation on desktop
/// and a top header drawer / bottom bar on mobile, strictly scoped to the company's campaigns.
class CompanyManagerPortalScreen extends ConsumerStatefulWidget {
  final String companySlug;
  final String? initialEventId;
  final bool isAgencyOpsMode;

  const CompanyManagerPortalScreen({
    super.key,
    required this.companySlug,
    this.initialEventId,
    this.isAgencyOpsMode = false,
  });

  @override
  ConsumerState<CompanyManagerPortalScreen> createState() => _CompanyManagerPortalScreenState();
}

class _CompanyManagerPortalScreenState extends ConsumerState<CompanyManagerPortalScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedTab = 0;
  final Set<int> _loadedTabs = {0}; // Lazy loading set: only render tabs when requested
  final Map<String, Widget> _cachedTabWidgets = {}; // High performance memoized tab widget cache (0ms instant tab switching)
  bool _isSidebarExpanded = true;

  @override
  void didUpdateWidget(covariant CompanyManagerPortalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companySlug != widget.companySlug ||
        oldWidget.initialEventId != widget.initialEventId ||
        oldWidget.isAgencyOpsMode != widget.isAgencyOpsMode) {
      _cachedTabWidgets.clear();
    }
  }

  void _copyPortalLink(BuildContext context, AppStrings strings, String effectiveSlug, String? eventId) {
    if (widget.isAgencyOpsMode) {
      _copyAgencyOpsLink(context, strings, effectiveSlug, eventId);
    } else {
      _copyBrandExecutiveLink(context, strings, effectiveSlug, eventId);
    }
  }

  void _copyAgencyOpsLink(BuildContext context, AppStrings strings, String effectiveSlug, String? eventId) {
    final url = AppUrlBuilder.buildAgencyOpsUrl(effectiveSlug, eventId: eventId);
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${strings.agencyOpsLinkCopied}: $url'),
        backgroundColor: Colors.purple.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copyBrandExecutiveLink(BuildContext context, AppStrings strings, String effectiveSlug, String? eventId) {
    final url = AppUrlBuilder.buildBrandExecutiveUrl(effectiveSlug, eventId: eventId);
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${strings.brandExecutiveLinkCopied}: $url'),
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

  List<_PortalNavItem> _getNavItems(AppStrings strings, bool isAr, bool isHi) {
    if (widget.isAgencyOpsMode) {
      return [
        _PortalNavItem(
          index: 0,
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long_rounded,
          title: strings.invoicesAuditTitle,
          subtitle: isAr ? 'سجل الفواتير وتدقيق المشتريات' : (isHi ? 'इनवॉइस ऑडिट और लॉग्स' : 'Invoices Audit & Live Logs'),
          tooltip: isAr ? 'متابعة وتدقيق فواتير اليوم المرفوعة من الفروع' : 'Review live receipts from branches',
          accentColor: const Color(0xFF006C50),
        ),
        _PortalNavItem(
          index: 1,
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet_rounded,
          title: strings.branchBalancesNavTitle,
          subtitle: strings.branchBalancesNavSubtitle,
          tooltip: strings.branchBalancesNavTooltip,
          accentColor: const Color(0xFF0284C7),
        ),
        _PortalNavItem(
          index: 2,
          icon: Icons.confirmation_number_outlined,
          selectedIcon: Icons.confirmation_number_rounded,
          title: strings.vouchersNavTitle,
          subtitle: strings.vouchersNavSubtitle,
          tooltip: strings.vouchersNavTooltip,
          accentColor: const Color(0xFFD97706),
        ),
        _PortalNavItem(
          index: 3,
          icon: Icons.point_of_sale_outlined,
          selectedIcon: Icons.point_of_sale_rounded,
          title: strings.dailyBranchSalesNavTitle,
          subtitle: strings.dailyBranchSalesNavSubtitle,
          tooltip: strings.dailyBranchSalesNavTooltip,
          accentColor: const Color(0xFF2563EB),
        ),
      ];
    }

    return [
      _PortalNavItem(
        index: 0,
        icon: Icons.analytics_outlined,
        selectedIcon: Icons.analytics_rounded,
        title: strings.analyticsTitle,
        subtitle: isAr ? 'المؤشرات والتحليلات والـ ROI' : (isHi ? 'एनालिटिक्स और प्रदर्शन' : 'KPIs, Analytics & Sales'),
        tooltip: isAr ? 'التقارير والتحليلات التفاعلية الشاملة للشركة' : 'Comprehensive Analytics & Reports',
        accentColor: const Color(0xFF6750A4),
      ),
      _PortalNavItem(
        index: 1,
        icon: Icons.compare_arrows_outlined,
        selectedIcon: Icons.compare_arrows_rounded,
        title: strings.campaignsComparisonNavTitle,
        subtitle: strings.campaignsComparisonNavSubtitle,
        tooltip: strings.campaignsComparisonNavTooltip,
        accentColor: const Color(0xFF006C51),
      ),
      _PortalNavItem(
        index: 2,
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long_rounded,
        title: strings.invoicesAuditTitle,
        subtitle: isAr ? 'سجل الفواتير وتدقيق المنتجات والـ CSV' : (isHi ? 'इनवॉइस ऑडिट और निर्यात' : 'Invoices Audit, Fraud & CSV Export'),
        tooltip: isAr ? 'سجل الفواتير وتدقيق المنتجات والمبيعات وعمليات التصدير' : 'Invoices Log, Product Audit & CSV',
        accentColor: const Color(0xFF0284C7),
      ),
      _PortalNavItem(
        index: 3,
        icon: Icons.point_of_sale_outlined,
        selectedIcon: Icons.point_of_sale_rounded,
        title: strings.dailyBranchSalesNavTitle,
        subtitle: strings.dailyBranchSalesNavSubtitle,
        tooltip: strings.dailyBranchSalesNavTooltip,
        accentColor: const Color(0xFF2563EB),
      ),
      _PortalNavItem(
        index: 4,
        icon: Icons.account_balance_wallet_outlined,
        selectedIcon: Icons.account_balance_wallet_rounded,
        title: strings.branchBalancesNavTitle,
        subtitle: strings.branchBalancesNavSubtitle,
        tooltip: strings.branchBalancesNavTooltip,
        accentColor: const Color(0xFF7C3AED),
      ),
      _PortalNavItem(
        index: 5,
        icon: Icons.confirmation_number_outlined,
        selectedIcon: Icons.confirmation_number_rounded,
        title: strings.vouchersNavTitle,
        subtitle: strings.vouchersNavSubtitle,
        tooltip: strings.vouchersNavTooltip,
        accentColor: const Color(0xFFD97706),
      ),
      _PortalNavItem(
        index: 6,
        icon: Icons.phone_android_rounded,
        selectedIcon: Icons.phone_android_rounded,
        title: strings.livePromoterSimulationNavTitle,
        subtitle: strings.livePromoterSimulationNavSubtitle,
        tooltip: strings.livePromoterSimulationNavTooltip,
        accentColor: const Color(0xFF0D9488),
      ),
    ];
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
        : widget.companySlug.trim();

    if (effectiveSlug.isEmpty && initialEvent == null) {
      if (allDocs.isEmpty) {
        return Scaffold(
          backgroundColor: colorScheme.surface,
          body: Center(
            child: CircularProgressIndicator(
              color: colorScheme.primary,
            ),
          ),
        );
      }
      return CampaignSuspendedScreen(
        portalType: widget.isAgencyOpsMode ? SuspendedPortalType.agency : SuspendedPortalType.manager,
        event: null,
        companySlug: widget.companySlug,
        companyName: isAr ? 'الحملة غير متوفرة' : (isHi ? 'अभियान उपलब्ध नहीं है' : 'Campaign Not Found'),
        onRefresh: () => setState(() {}),
      );
    }

    String companyDisplayName = initialEvent?.targetCompany ?? '';
    if (companyDisplayName.isEmpty) {
      final matchedEvents = allEvents.where((e) =>
          e.companySlug.toLowerCase() == effectiveSlug.toLowerCase() ||
          SlugUtils.toSlug(e.targetCompany).toLowerCase() == effectiveSlug.toLowerCase() ||
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
      final matchSlug = e.companySlug.toLowerCase() == effectiveSlug.toLowerCase() ||
          SlugUtils.toSlug(e.targetCompany).toLowerCase() == effectiveSlug.toLowerCase();
      final matchName = companyDisplayName.isNotEmpty &&
          e.targetCompany.toLowerCase() == companyDisplayName.toLowerCase();
      return matchSlug || matchName;
    }).toList();

    // Resolve company logo from initialEvent or any companyEvent
    String companyLogoUrl = initialEvent?.companyLogoUrl ?? '';
    if (companyLogoUrl.isEmpty) {
      for (final e in companyEvents) {
        if (e.companyLogoUrl.isNotEmpty) {
          companyLogoUrl = e.companyLogoUrl;
          break;
        }
      }
    }

    final bool isSuspended = widget.isAgencyOpsMode
        ? ((initialEvent != null && (!initialEvent.isActive || !initialEvent.isAgencyActive)) ||
            (companyEvents.isNotEmpty && companyEvents.every((e) => !e.isActive || !e.isAgencyActive)))
        : ((initialEvent != null && (!initialEvent.isActive || !initialEvent.isManagerActive)) ||
            (companyEvents.isNotEmpty && companyEvents.every((e) => !e.isActive || !e.isManagerActive)));

    if (isSuspended) {
      return CampaignSuspendedScreen(
        portalType: widget.isAgencyOpsMode ? SuspendedPortalType.agency : SuspendedPortalType.manager,
        event: initialEvent ?? (companyEvents.isNotEmpty ? companyEvents.first : null),
        companySlug: effectiveSlug,
        companyName: companyDisplayName,
        onRefresh: () => setState(() {}),
      );
    }

    final activeEventId = initialEvent?.id ?? widget.initialEventId;
    final navItems = _getNavItems(strings, isAr, isHi);

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: colorScheme.surface,
        appBar: SwitchPointHeader(
          subtitle: widget.isAgencyOpsMode
              ? '$companyDisplayName • ${strings.agencyOpsPortalLabel}'
              : '$companyDisplayName • ${strings.brandExecutivePortalLabel}',
          companyLogoUrl: companyLogoUrl,
          onMobileMenuPressed: isMobile ? () => _scaffoldKey.currentState?.openDrawer() : null,
          customActions: isMobile
              ? null
              : [
                  // Copy Promoter Link quick button
                  Tooltip(
                    message: strings.copyPromoterLink,
                    child: IconButton.filledTonal(
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                      padding: const EdgeInsets.all(8),
                      onPressed: () => _copyPromoterLink(context, strings, effectiveSlug, activeEventId),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Copy Agency Ops Link quick button
                  Tooltip(
                    message: strings.copyAgencyOpsLink,
                    child: IconButton.filledTonal(
                      icon: const Icon(Icons.store_mall_directory_rounded, size: 18),
                      padding: const EdgeInsets.all(8),
                      onPressed: () => _copyAgencyOpsLink(context, strings, effectiveSlug, activeEventId),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Copy Brand Executive Master Link quick button
                  Tooltip(
                    message: strings.copyBrandExecutiveLink,
                    child: IconButton.filledTonal(
                      icon: const Icon(Icons.business_center_rounded, size: 18),
                      padding: const EdgeInsets.all(8),
                      onPressed: () => _copyBrandExecutiveLink(context, strings, effectiveSlug, activeEventId),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
        ),

        // Mobile Drawer for seamless phone navigation (Opens from Right in RTL, Left in LTR)
        drawer: isMobile
            ? _buildMobileDrawer(
                context: context,
                colorScheme: colorScheme,
                textTheme: textTheme,
                strings: strings,
                companyName: companyDisplayName,
                companyLogoUrl: companyLogoUrl,
                effectiveSlug: effectiveSlug,
                activeEventId: activeEventId,
                campaignsCount: companyEvents.length,
                navItems: navItems,
                isAr: isAr,
                isHi: isHi,
              )
            : null,

        // No squished bottom navigation bar! All pages and settings are inside the drawer menu
        bottomNavigationBar: null,

      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. M3 Collapsible Dashboard Menu (Placed at the START of layout: RIGHT in Arabic RTL, LEFT in English/Hindi LTR)
          if (!isMobile)
            RepaintBoundary(
              child: _buildDesktopSidebar(
                context: context,
                colorScheme: colorScheme,
                textTheme: textTheme,
                strings: strings,
                companyName: companyDisplayName,
                companyLogoUrl: companyLogoUrl,
                effectiveSlug: effectiveSlug,
                activeEventId: activeEventId,
                campaignsCount: companyEvents.length,
                navItems: navItems,
                isAr: isAr,
                isHi: isHi,
              ),
            ),

          // 2. Main Executive Content Views (Lazy On-Demand Tab Loading + High Performance Offstage Cache)
          Expanded(
            child: RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  for (int i = 0; i < navItems.length; i++)
                    Offstage(
                      offstage: _selectedTab != i,
                      child: TickerMode(
                        enabled: _selectedTab == i,
                        child: _loadedTabs.contains(i)
                            ? _getOrCreateTabWidget(
                                tabIndex: i,
                                effectiveSlug: effectiveSlug,
                                companyDisplayName: companyDisplayName,
                                activeEventId: activeEventId,
                                initialEvent: initialEvent,
                                companyEvents: companyEvents,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  /// Retrieves existing tab widget from memory cache or builds it on-demand (0ms instant tab switching)
  Widget _getOrCreateTabWidget({
    required int tabIndex,
    required String effectiveSlug,
    required String companyDisplayName,
    required String? activeEventId,
    required EventModel? initialEvent,
    required List<EventModel> companyEvents,
  }) {
    final String tabKey;
    if (!widget.isAgencyOpsMode && tabIndex == 1) {
      // Comparison Analytics benchmarks all campaigns of the company; keep stable across single-campaign selector
      tabKey = '1-comparison-$effectiveSlug';
    } else {
      tabKey = '$tabIndex-${activeEventId ?? 'all'}-$effectiveSlug-${widget.isAgencyOpsMode}';
    }
    if (_cachedTabWidgets.containsKey(tabKey)) {
      return _cachedTabWidgets[tabKey]!;
    }
    final widgetContent = _buildTabContent(
      tabIndex: tabIndex,
      effectiveSlug: effectiveSlug,
      companyDisplayName: companyDisplayName,
      activeEventId: activeEventId,
      initialEvent: initialEvent,
      companyEvents: companyEvents,
    );
    _cachedTabWidgets[tabKey] = widgetContent;
    return widgetContent;
  }

  /// Builds tab content on-demand (Zero CPU/memory overhead for unvisited tabs)
  Widget _buildTabContent({
    required int tabIndex,
    required String effectiveSlug,
    required String companyDisplayName,
    required String? activeEventId,
    required EventModel? initialEvent,
    required List<EventModel> companyEvents,
  }) {
    if (widget.isAgencyOpsMode) {
      switch (tabIndex) {
        case 0:
          return InvoicesLogScreen(
            key: ValueKey('agency_invoices_${effectiveSlug}_${activeEventId ?? 'all'}'),
            initialEventId: activeEventId,
            lockedCompanySlug: effectiveSlug,
            lockedCompanyName: companyDisplayName,
            isEmbedded: true,
          );
        case 1:
          return BranchStockBalancesScreen(
            key: ValueKey('agency_balances_${effectiveSlug}_${activeEventId ?? 'all'}'),
            initialEventId: activeEventId,
            lockedCompanySlug: effectiveSlug,
            lockedCompanyName: companyDisplayName,
            isEmbedded: true,
          );
        case 2:
          return CompanyVouchersReportScreen(
            key: ValueKey('agency_vouchers_${effectiveSlug}_${activeEventId ?? 'all'}'),
            initialEventId: activeEventId,
            lockedCompanySlug: effectiveSlug,
            lockedCompanyName: companyDisplayName,
            isEmbedded: true,
          );
        case 3:
          return DailyBranchSalesScreen(
            key: ValueKey('agency_daily_sales_${effectiveSlug}_${activeEventId ?? 'all'}'),
            initialEventId: activeEventId,
            lockedCompanySlug: effectiveSlug,
          );
        default:
          return const SizedBox.shrink();
      }
    }

    // Brand Executive Master Mode:
    switch (tabIndex) {
      case 0:
        return CampaignReportsScreen(
          key: ValueKey('reports_${effectiveSlug}_${activeEventId ?? 'all'}'),
          initialEvent: initialEvent,
          initialEventId: activeEventId,
          lockedCompanySlug: effectiveSlug,
          lockedCompanyName: companyDisplayName,
          isEmbedded: true,
        );
      case 1:
        return CampaignsComparisonAnalyticsScreen(
          key: ValueKey('comparison_$effectiveSlug'),
          lockedCompanySlug: effectiveSlug,
          lockedCompanyName: companyDisplayName,
          initialEventId: activeEventId,
          companyEvents: companyEvents,
          isEmbedded: true,
        );
      case 2:
        return InvoicesLogScreen(
          key: ValueKey('invoices_${effectiveSlug}_${activeEventId ?? 'all'}'),
          initialEventId: activeEventId,
          lockedCompanySlug: effectiveSlug,
          lockedCompanyName: companyDisplayName,
          isEmbedded: true,
        );
      case 3:
        return DailyBranchSalesScreen(
          key: ValueKey('daily_sales_${effectiveSlug}_${activeEventId ?? 'all'}'),
          initialEventId: activeEventId,
          lockedCompanySlug: effectiveSlug,
        );
      case 4:
        return BranchStockBalancesScreen(
          key: ValueKey('balances_${effectiveSlug}_${activeEventId ?? 'all'}'),
          initialEventId: activeEventId,
          lockedCompanySlug: effectiveSlug,
          lockedCompanyName: companyDisplayName,
          isEmbedded: true,
        );
      case 5:
        return CompanyVouchersReportScreen(
          key: ValueKey('vouchers_${effectiveSlug}_${activeEventId ?? 'all'}'),
          initialEventId: activeEventId,
          lockedCompanySlug: effectiveSlug,
          lockedCompanyName: companyDisplayName,
          isEmbedded: true,
        );
      case 6:
        return _buildLivePromoterSimulationTab(
          context: context,
          colorScheme: Theme.of(context).colorScheme,
          effectiveSlug: effectiveSlug,
          activeEventId: activeEventId,
          initialEvent: initialEvent,
          isAr: AppStrings.of(ref).isAr,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildLivePromoterSimulationTab({
    required BuildContext context,
    required ColorScheme colorScheme,
    required String effectiveSlug,
    required String? activeEventId,
    required EventModel? initialEvent,
    required bool isAr,
  }) {
    return Container(
      color: colorScheme.surfaceContainerLowest,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Hero Explainer Badge
              Container(
                constraints: const BoxConstraints(maxWidth: 500),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.phone_android_rounded, color: colorScheme.primary, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr ? 'محاكاة رحلة البروموتر في الفرع (Live Simulation)' : 'In-Store Promoter Live Simulation',
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          Text(
                            isAr
                                ? 'هذه هي الشاشة المباشرة التي يستخدمها البروموتر والمتسوق داخل السوبرماركت لرفع الفواتير وتوزيع الهدايا.'
                                : 'Live preview of the in-store receipt upload and gift distribution screen.',
                            style: GoogleFonts.cairo(
                              fontSize: 11.5,
                              color: colorScheme.onPrimaryContainer.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Mockup Smartphone Device Frame
              Container(
                width: 390,
                height: 844,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(36),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.8), width: 3.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: const Size(390, 844),
                      padding: const EdgeInsets.only(top: 24, bottom: 20),
                    ),
                    child: ClientReceiptUploadScreen(
                      event: initialEvent,
                      companySlug: effectiveSlug,
                      initialEventId: activeEventId,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the desktop collapsible dashboard navigation sidebar (Right side in Arabic RTL, Left in English/Hindi LTR)
  Widget _buildDesktopSidebar({
    required BuildContext context,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required AppStrings strings,
    required String companyName,
    required String companyLogoUrl,
    required String effectiveSlug,
    required String? activeEventId,
    required int campaignsCount,
    required List<_PortalNavItem> navItems,
    required bool isAr,
    required bool isHi,
  }) {
    final width = _isSidebarExpanded ? 275.0 : 76.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.fastOutSlowIn,
      width: width,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: BorderDirectional(
          end: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: Offset(isAr ? -2 : 2, 0),
          ),
        ],
      ),
      child: ClipRect(
        child: OverflowBox(
          minWidth: 0,
          maxWidth: 275.0,
          alignment: AlignmentDirectional.topStart,
          child: SizedBox(
            width: 275.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sidebar Header: Company Info + Collapse Toggle Button
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: _isSidebarExpanded ? 14 : 10,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_isSidebarExpanded) ...[
                        // Company Icon & Name
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: companyLogoUrl.isNotEmpty ? Colors.white : null,
                                  gradient: companyLogoUrl.isEmpty
                                      ? LinearGradient(
                                          colors: [
                                            colorScheme.primary,
                                            colorScheme.secondary,
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : null,
                                  borderRadius: BorderRadius.circular(10),
                                  border: companyLogoUrl.isNotEmpty
                                      ? Border.all(
                                          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                                          width: 1,
                                        )
                                      : null,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(9),
                                  child: companyLogoUrl.isNotEmpty
                                      ? Image.network(
                                          companyLogoUrl,
                                          fit: BoxFit.contain,
                                          errorBuilder: (context, error, stackTrace) => Center(
                                            child: Icon(
                                              Icons.business_rounded,
                                              color: colorScheme.primary,
                                              size: 20,
                                            ),
                                          ),
                                        )
                                      : Center(
                                          child: Icon(
                                            Icons.business_rounded,
                                            color: colorScheme.onPrimary,
                                            size: 18,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      companyName,
                                      style: GoogleFonts.cairo(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      strings.partnerPortalBadge,
                                      style: GoogleFonts.cairo(
                                        fontSize: 10,
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w600,
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
                        const SizedBox(width: 4),
                      ],

                      // Collapse/Expand Action Button
                      Tooltip(
                        message: _isSidebarExpanded ? strings.collapseSidebar : strings.expandSidebar,
                        child: IconButton.filledTonal(
                          icon: Icon(
                            _isSidebarExpanded
                                ? (isAr ? Icons.keyboard_double_arrow_right_rounded : Icons.keyboard_double_arrow_left_rounded)
                                : (isAr ? Icons.keyboard_double_arrow_left_rounded : Icons.keyboard_double_arrow_right_rounded),
                            size: 18,
                          ),
                          style: IconButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(32, 32),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () {
                            setState(() {
                              _isSidebarExpanded = !_isSidebarExpanded;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // Navigation Items List
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    children: [
                      for (final item in navItems)
                        _buildSidebarItemTile(
                          item: item,
                          isSelected: _selectedTab == item.index,
                          isExpanded: _isSidebarExpanded,
                          colorScheme: colorScheme,
                          onTap: () {
                            setState(() {
                              _selectedTab = item.index;
                              _loadedTabs.add(item.index);
                            });
                          },
                        ),
                    ],
                  ),
                ),

                // Sidebar Footer: Quick Links & Summary
                Container(
                  padding: EdgeInsets.all(_isSidebarExpanded ? 12 : 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    border: Border(
                      top: BorderSide(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                  ),
                  child: _isSidebarExpanded
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Active Campaigns Count Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: colorScheme.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.campaign_rounded, size: 16, color: colorScheme.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '$campaignsCount ${strings.companyAllCampaigns}',
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
                            const SizedBox(height: 8),
                            // Quick Copy Links
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 14),
                                    label: Text(
                                      isAr ? 'رابط البروموتر' : 'Promoter',
                                      style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => _copyPromoterLink(context, strings, effectiveSlug, activeEventId),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.share_rounded, size: 14),
                                    label: Text(
                                      isAr ? 'رابط المدير' : 'Manager',
                                      style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => _copyPortalLink(context, strings, effectiveSlug, activeEventId),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Tooltip(
                              message: strings.copyPromoterLink,
                              child: IconButton(
                                icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                                onPressed: () => _copyPromoterLink(context, strings, effectiveSlug, activeEventId),
                              ),
                            ),
                            Tooltip(
                              message: strings.copyManagerPortalLink,
                              child: IconButton(
                                icon: const Icon(Icons.share_rounded, size: 18),
                                onPressed: () => _copyPortalLink(context, strings, effectiveSlug, activeEventId),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds a single dashboard item tile in the desktop sidebar
  Widget _buildSidebarItemTile({
    required _PortalNavItem item,
    required bool isSelected,
    required bool isExpanded,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    final bg = isSelected
        ? item.accentColor.withValues(alpha: 0.12)
        : Colors.transparent;
    final borderColor = isSelected
        ? item.accentColor.withValues(alpha: 0.6)
        : Colors.transparent;

    return Tooltip(
      message: item.tooltip,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isExpanded ? 12 : 8,
                vertical: isExpanded ? 12 : 12,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor, width: 1.5),
              ),
              child: isExpanded
                  ? Row(
                      children: [
                        // Icon Container
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? item.accentColor
                                : item.accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isSelected ? item.selectedIcon : item.icon,
                            color: isSelected ? Colors.white : item.accentColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Title and Subtitle
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                                  color: isSelected
                                      ? colorScheme.onSurface
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.subtitle,
                                style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  color: colorScheme.outline,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Container(
                            width: 6,
                            height: 24,
                            decoration: BoxDecoration(
                              color: item.accentColor,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                      ],
                    )
                  : Center(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? item.accentColor
                              : item.accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isSelected ? item.selectedIcon : item.icon,
                          color: isSelected ? Colors.white : item.accentColor,
                          size: 22,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the mobile Drawer for smartphones and tablets
  Widget _buildMobileDrawer({
    required BuildContext context,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required AppStrings strings,
    required String companyName,
    required String companyLogoUrl,
    required String effectiveSlug,
    required String? activeEventId,
    required int campaignsCount,
    required List<_PortalNavItem> navItems,
    required bool isAr,
    required bool isHi,
  }) {
    return Drawer(
      backgroundColor: colorScheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primary,
                    colorScheme.secondary,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: companyLogoUrl.isNotEmpty ? Colors.white : Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: companyLogoUrl.isNotEmpty
                              ? Border.all(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  width: 1.5,
                                )
                              : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: companyLogoUrl.isNotEmpty
                              ? Image.network(
                                  companyLogoUrl,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) => const Center(
                                    child: Icon(
                                      Icons.business_rounded,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                                  ),
                                )
                              : const Center(
                                  child: Icon(
                                    Icons.business_rounded,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    companyName,
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${strings.partnerPortalBadge} • $campaignsCount ${strings.companyAllCampaigns}',
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),

            // Navigation Items & Settings
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                children: [
                  // Section 1: Dashboard Pages
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.dashboard_rounded, size: 16, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isAr ? 'الصفحات ولوحات المتابعة' : (isHi ? 'डैशबोर्ड और रिपोर्ट' : 'Dashboards & Reports'),
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final item in navItems)
                    _buildSidebarItemTile(
                      item: item,
                      isSelected: _selectedTab == item.index,
                      isExpanded: true,
                      colorScheme: colorScheme,
                      onTap: () {
                        setState(() {
                          _selectedTab = item.index;
                          _loadedTabs.add(item.index);
                        });
                        Navigator.of(context).pop();
                      },
                    ),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1),
                  ),

                  // Section 2: Preferences & Settings (الإعدادات) - Collapsed by default
                  Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: ExpansionTile(
                          initiallyExpanded: false,
                          shape: const Border(),
                          collapsedShape: const Border(),
                          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                          leading: Icon(
                            Icons.settings_rounded,
                            size: 20,
                            color: colorScheme.secondary,
                          ),
                          title: Text(
                            isAr ? 'الإعدادات' : (isHi ? 'सेटिंग्स' : 'Settings'),
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            isAr ? 'اللغة والدولة والمظهر' : (isHi ? 'भाषा, देश और थीम' : 'Language, country & theme'),
                            style: GoogleFonts.cairo(
                              fontSize: 10.5,
                              color: colorScheme.outline,
                            ),
                          ),
                          children: [
                            const Divider(height: 16),
                            // Language Selector
                            Row(
                              children: [
                                Icon(Icons.translate_rounded, size: 15, color: colorScheme.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    isAr ? 'لغة الواجهة' : (isHi ? 'ऐप भाषा' : 'Language'),
                                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: AppLanguage.values.map((lang) {
                                final isSelected = ref.watch(localeProvider).languageCode == lang.code;
                                return ChoiceChip(
                                  avatar: Text(lang.flagEmoji, style: const TextStyle(fontSize: 13)),
                                  label: Text(
                                    lang.label,
                                    style: GoogleFonts.cairo(
                                      fontSize: 11,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  selected: isSelected,
                                  onSelected: (val) {
                                    if (val) ref.setLocale(lang.code);
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 14),

                            // Country & Currency Selector
                            Row(
                              children: [
                                Icon(Icons.payments_rounded, size: 15, color: colorScheme.secondary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    isAr ? 'الدولة والعملة المعتمدة' : (isHi ? 'देश और मुद्रा' : 'Country & Currency'),
                                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: CountryCurrencyConfig.supportedCountries.map((country) {
                                final activeCountry = ref.watch(activeCountryProvider);
                                final currentLangCode = ref.watch(localeProvider).languageCode;
                                final isSelected = activeCountry.code == country.code;
                                return ChoiceChip(
                                  avatar: Text(country.flagEmoji, style: const TextStyle(fontSize: 13)),
                                  label: Text(
                                    '${country.name(currentLangCode)} (${country.currencySymbolFor(currentLangCode)})',
                                    style: GoogleFonts.cairo(
                                      fontSize: 11,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  selected: isSelected,
                                  onSelected: (val) {
                                    if (val) ref.read(activeCountryProvider.notifier).state = country;
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 10),

                            // Dark / Light Theme Mode
                            Builder(builder: (ctx) {
                              final themeMode = ref.watch(themeModeProvider);
                              final isDark = themeMode == ThemeMode.dark ||
                                  (themeMode == ThemeMode.system && Theme.of(ctx).brightness == Brightness.dark);
                              return SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                secondary: Icon(
                                  isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                                  color: isDark ? Colors.amber : colorScheme.primary,
                                  size: 20,
                                ),
                                title: Text(
                                  isAr
                                      ? (isDark ? 'الوضع الداكن (مفعل)' : 'الوضع الفاتح (مفعل)')
                                      : (isHi
                                          ? (isDark ? 'डार्क मोड (सक्रिय)' : 'लाइट मोड (सक्रिय)')
                                          : (isDark ? 'Dark Mode (Active)' : 'Light Mode (Active)')),
                                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  isAr ? 'تبديل المظهر بين الوضع الليلي والنهاري' : (isHi ? 'दिन और रात के मोड के बीच स्विच करें' : 'Toggle between Dark and Light mode'),
                                  style: GoogleFonts.cairo(fontSize: 10, color: colorScheme.onSurfaceVariant),
                                ),
                                value: isDark,
                                onChanged: (val) {
                                  ref.read(themeModeProvider.notifier).state = val ? ThemeMode.dark : ThemeMode.light;
                                },
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1),
                  ),

                  // Section 3: Quick Portal Links
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.link_rounded, size: 16, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isAr ? 'مشاركة روابط البوابات' : (isHi ? 'पोर्टल लिंक साझा करें' : 'Share Portal Links'),
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                    label: Text(strings.copyPromoterLink),
                    onPressed: () {
                      _copyPromoterLink(context, strings, effectiveSlug, activeEventId);
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.store_mall_directory_rounded, size: 16),
                    label: Text(strings.copyAgencyOpsLink),
                    onPressed: () {
                      _copyAgencyOpsLink(context, strings, effectiveSlug, activeEventId);
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.business_center_rounded, size: 16),
                    label: Text(strings.copyBrandExecutiveLink),
                    onPressed: () {
                      _copyBrandExecutiveLink(context, strings, effectiveSlug, activeEventId);
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(height: 16),

                  // App Version Info
                  Center(
                    child: Text(
                      'Tashil Gift ${AppVersionConfig.versionDisplay} (Build #${AppVersionConfig.buildNumber})',
                      style: GoogleFonts.cairo(
                        fontSize: 10.5,
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
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
    final isMobile = screenWidth < 900;

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
}
