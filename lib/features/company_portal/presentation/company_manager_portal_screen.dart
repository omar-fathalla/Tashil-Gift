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
import '../../../core/utils/responsive.dart';
import '../../../core/services/partner_portal_auth_service.dart';
import '../../auth/presentation/partner_portal_login_screen.dart';

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
  final bool requirePortalAuth;

  const CompanyManagerPortalScreen({
    super.key,
    required this.companySlug,
    this.initialEventId,
    this.isAgencyOpsMode = false,
    this.requirePortalAuth = false,
  });

  @override
  ConsumerState<CompanyManagerPortalScreen> createState() => _CompanyManagerPortalScreenState();
}

class _CompanyManagerPortalScreenState extends ConsumerState<CompanyManagerPortalScreen> {
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedTab = 0;
  final Set<int> _loadedTabs = {0}; // Lazy loading set: only render tabs when requested
  final Map<String, Widget> _cachedTabWidgets = {}; // High performance memoized tab widget cache (0ms instant tab switching)
  Stream<QuerySnapshot>? _memoizedEventsStream;
  String? _lastEventsStreamKey;

  Stream<QuerySnapshot>? _ensureEventsStream(FirebaseFirestore? firestore) {
    if (firestore == null) return null;
    final cleanSlug = widget.companySlug.trim().toLowerCase();
    final key = '$cleanSlug:${widget.initialEventId ?? ''}';
    if (_memoizedEventsStream == null || _lastEventsStreamKey != key) {
      _lastEventsStreamKey = key;
      try {
        _memoizedEventsStream = firestore.collection('events').snapshots();
      } catch (_) {
        _memoizedEventsStream = null;
      }
    }
    return _memoizedEventsStream;
  }

  Future<void> _signOutPortalSession(String effectiveSlug, {String? eventId}) async {
    final authService = ref.read(partnerPortalAuthServiceProvider);
    final role = widget.isAgencyOpsMode
        ? PartnerPortalRole.agencyOps
        : PartnerPortalRole.brandManager;
    await authService.signOut(
      companySlug: effectiveSlug.isNotEmpty ? effectiveSlug : widget.companySlug,
      role: role,
      eventId: eventId ?? widget.initialEventId,
    );
    if (!mounted) return;
    ref.read(partnerPortalSessionEpochProvider.notifier).state++;
  }

  @override
  void didUpdateWidget(covariant CompanyManagerPortalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companySlug != widget.companySlug ||
        oldWidget.initialEventId != widget.initialEventId ||
        oldWidget.isAgencyOpsMode != widget.isAgencyOpsMode) {
      _cachedTabWidgets.clear();
    }
  }

  Future<void> _copyAgencyOpsLink(
    BuildContext context,
    AppStrings strings,
    String effectiveSlug, {
    String? eventId,
  }) async {
    final targetEventId = (eventId != null && eventId.trim().isNotEmpty)
        ? eventId.trim()
        : widget.initialEventId;
    final url = AppUrlBuilder.buildAgencyOpsUrl(effectiveSlug, eventId: targetEventId);
    final messenger = ScaffoldMessenger.of(context);
    final primaryColor = colorScheme.primary;
    try {
      final authService = ref.read(partnerPortalAuthServiceProvider);
      final creds = await authService.resolveCredentials(
        companySlug: effectiveSlug,
        eventId: targetEventId,
      );
      final card = PartnerPortalAuthService.buildWhatsAppLoginCard(
        role: PartnerPortalRole.agencyOps,
        companyName: creds.companyName,
        portalUrl: url,
        username: creds.effectiveAgencyUsername,
        password: creds.effectiveAgencyPassword,
        campaignName: creds.eventName,
        isCustomCampaignTier: creds.hasCustomAgencyCredentials,
        isAr: strings.isAr,
      );
      await Clipboard.setData(ClipboardData(text: card));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
    }
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('${strings.agencyOpsLinkCopied}: $url'),
        backgroundColor: primaryColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _copyBrandExecutiveLink(BuildContext context, AppStrings strings, String effectiveSlug) async {
    final url = AppUrlBuilder.buildBrandExecutiveUrl(effectiveSlug);
    final messenger = ScaffoldMessenger.of(context);
    final primaryColor = colorScheme.primary;
    try {
      final authService = ref.read(partnerPortalAuthServiceProvider);
      final creds = await authService.resolveCredentials(
        companySlug: effectiveSlug,
        eventId: widget.initialEventId,
      );
      final card = PartnerPortalAuthService.buildWhatsAppLoginCard(
        role: PartnerPortalRole.brandManager,
        companyName: creds.companyName,
        portalUrl: url,
        username: creds.brandManagerUsername,
        password: creds.brandManagerPassword,
        isAr: strings.isAr,
      );
      await Clipboard.setData(ClipboardData(text: card));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
    }
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('${strings.brandExecutiveLinkCopied}: $url'),
        backgroundColor: primaryColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copyPromoterLink(
    BuildContext context,
    AppStrings strings,
    String effectiveSlug, {
    String? eventId,
  }) {
    final url = AppUrlBuilder.buildPromoterUrl(effectiveSlug, eventId: eventId);
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${strings.promoterLinkCopied}: $url'),
        backgroundColor: colorScheme.tertiary,
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
          title: strings.partnerNavInvoices,
          subtitle: isAr ? 'سجل الفواتير وتدقيق المشتريات' : (isHi ? 'इनवॉइस ऑडिट और लॉग्स' : 'Invoices Audit & Live Logs'),
          tooltip: isAr ? 'متابعة وتدقيق فواتير اليوم المرفوعة من الفروع' : 'Review live receipts from branches',
          accentColor: colorScheme.tertiary,
        ),
        _PortalNavItem(
          index: 1,
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet_rounded,
          title: strings.partnerNavBalances,
          subtitle: strings.branchBalancesNavSubtitle,
          tooltip: strings.branchBalancesNavTooltip,
          accentColor: colorScheme.secondary,
        ),
        _PortalNavItem(
          index: 2,
          icon: Icons.confirmation_number_outlined,
          selectedIcon: Icons.confirmation_number_rounded,
          title: strings.partnerNavVouchers,
          subtitle: strings.vouchersNavSubtitle,
          tooltip: strings.vouchersNavTooltip,
          accentColor: colorScheme.secondary,
        ),
        _PortalNavItem(
          index: 3,
          icon: Icons.point_of_sale_outlined,
          selectedIcon: Icons.point_of_sale_rounded,
          title: strings.partnerNavSales,
          subtitle: strings.dailyBranchSalesNavSubtitle,
          tooltip: strings.dailyBranchSalesNavTooltip,
          accentColor: colorScheme.onPrimaryFixedVariant,
        ),
      ];
    }

    return [
      _PortalNavItem(
        index: 0,
        icon: Icons.analytics_outlined,
        selectedIcon: Icons.analytics_rounded,
        title: strings.partnerNavAnalytics,
        subtitle: isAr ? 'المؤشرات والتحليلات والـ ROI' : (isHi ? 'एनालिटिक्स और प्रदर्शन' : 'KPIs, Analytics & Sales'),
        tooltip: isAr ? 'التقارير والتحليلات التفاعلية الشاملة للشركة' : 'Comprehensive Analytics & Reports',
        accentColor: colorScheme.primary,
      ),
      _PortalNavItem(
        index: 1,
        icon: Icons.compare_arrows_outlined,
        selectedIcon: Icons.compare_arrows_rounded,
        title: strings.partnerNavComparison,
        subtitle: strings.campaignsComparisonNavSubtitle,
        tooltip: strings.campaignsComparisonNavTooltip,
        accentColor: colorScheme.tertiary,
      ),
      _PortalNavItem(
        index: 2,
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long_rounded,
        title: strings.partnerNavInvoices,
        subtitle: isAr ? 'سجل الفواتير وتدقيق المنتجات والـ CSV' : (isHi ? 'इनवॉइस ऑडिट और निर्यात' : 'Invoices Audit, Fraud & CSV Export'),
        tooltip: isAr ? 'سجل الفواتير وتدقيق المنتجات والمبيعات وعمليات التصدير' : 'Invoices Log, Product Audit & CSV',
        accentColor: colorScheme.secondary,
      ),
      _PortalNavItem(
        index: 3,
        icon: Icons.point_of_sale_outlined,
        selectedIcon: Icons.point_of_sale_rounded,
        title: strings.partnerNavSales,
        subtitle: strings.dailyBranchSalesNavSubtitle,
        tooltip: strings.dailyBranchSalesNavTooltip,
        accentColor: colorScheme.onPrimaryFixedVariant,
      ),
      _PortalNavItem(
        index: 4,
        icon: Icons.account_balance_wallet_outlined,
        selectedIcon: Icons.account_balance_wallet_rounded,
        title: strings.partnerNavBalances,
        subtitle: strings.branchBalancesNavSubtitle,
        tooltip: strings.branchBalancesNavTooltip,
        accentColor: colorScheme.primary,
      ),
      _PortalNavItem(
        index: 5,
        icon: Icons.confirmation_number_outlined,
        selectedIcon: Icons.confirmation_number_rounded,
        title: strings.partnerNavVouchers,
        subtitle: strings.vouchersNavSubtitle,
        tooltip: strings.vouchersNavTooltip,
        accentColor: colorScheme.secondary,
      ),
      _PortalNavItem(
        index: 6,
        icon: Icons.phone_android_rounded,
        selectedIcon: Icons.phone_android_rounded,
        title: strings.partnerNavPromoter,
        subtitle: strings.livePromoterSimulationNavSubtitle,
        tooltip: strings.livePromoterSimulationNavTooltip,
        accentColor: colorScheme.tertiary,
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
    required M3LayoutMetrics layout,
    required List<QueryDocumentSnapshot> allDocs,
    PartnerPortalSession? portalSession,
  }) {
    final isCompact = layout.isCompact;
    final isMedium = layout.isMedium;
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

    final lockedEventId = (portalSession?.lockedEventId != null && portalSession!.lockedEventId!.isNotEmpty)
        ? portalSession.lockedEventId
        : null;
    final activeEventId = lockedEventId ?? initialEvent?.id ?? widget.initialEventId;
    final navItems = _getNavItems(strings, isAr, isHi);
    final isSystemAdmin = ref.watch(isAdminProvider);
    final isReadOnlyStock =
        !widget.isAgencyOpsMode && (!isSystemAdmin || portalSession?.role == PartnerPortalRole.brandManager);

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
          showMobileMenu: isCompact,
          onMobileMenuPressed: isCompact ? () => _scaffoldKey.currentState?.openDrawer() : null,
          showLanguageSelector: false,
          showCountryCurrencySelector: false,
          showDarkModeToggle: true,
          customActions: null,
        ),

        // Mobile Drawer for compact smartphone navigation (Opens from Right in RTL, Left in LTR)
        drawer: isCompact
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
          // 1. M3 Collapsible Dashboard Menu / Navigation Rail (Placed at the START of layout: RIGHT in Arabic RTL, LEFT in English/Hindi LTR)
          if (!isCompact)
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
                isMedium: isMedium,
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
                                lockedEventId: lockedEventId,
                                initialEvent: initialEvent,
                                companyEvents: companyEvents,
                                isReadOnlyStock: isReadOnlyStock,
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
    required String? lockedEventId,
    required EventModel? initialEvent,
    required List<EventModel> companyEvents,
    required bool isReadOnlyStock,
  }) {
    final String tabKey;
    if (!widget.isAgencyOpsMode && tabIndex == 1) {
      // Comparison Analytics benchmarks all campaigns of the company; keep stable across single-campaign selector
      tabKey = '1-comparison-$effectiveSlug-${lockedEventId ?? 'all'}';
    } else {
      tabKey = '$tabIndex-${activeEventId ?? 'all'}-${lockedEventId ?? 'unlocked'}-$effectiveSlug-${widget.isAgencyOpsMode}-$isReadOnlyStock';
    }
    if (_cachedTabWidgets.containsKey(tabKey)) {
      return _cachedTabWidgets[tabKey]!;
    }
    final widgetContent = _buildTabContent(
      tabIndex: tabIndex,
      effectiveSlug: effectiveSlug,
      companyDisplayName: companyDisplayName,
      activeEventId: activeEventId,
      lockedEventId: lockedEventId,
      initialEvent: initialEvent,
      companyEvents: companyEvents,
      isReadOnlyStock: isReadOnlyStock,
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
    required String? lockedEventId,
    required EventModel? initialEvent,
    required List<EventModel> companyEvents,
    required bool isReadOnlyStock,
  }) {
    if (widget.isAgencyOpsMode) {
      switch (tabIndex) {
        case 0:
          return InvoicesLogScreen(
            key: ValueKey('agency_invoices_${effectiveSlug}_${activeEventId ?? 'all'}_${lockedEventId ?? 'unlocked'}'),
            initialEventId: activeEventId,
            lockedEventId: lockedEventId,
            lockedCompanySlug: effectiveSlug,
            lockedCompanyName: companyDisplayName,
            isEmbedded: true,
          );
        case 1:
          return BranchStockBalancesScreen(
            key: ValueKey('agency_balances_${effectiveSlug}_${activeEventId ?? 'all'}_${lockedEventId ?? 'unlocked'}'),
            initialEventId: activeEventId,
            lockedEventId: lockedEventId,
            lockedCompanySlug: effectiveSlug,
            lockedCompanyName: companyDisplayName,
            isEmbedded: true,
            isReadOnly: false,
          );
        case 2:
          return CompanyVouchersReportScreen(
            key: ValueKey('agency_vouchers_${effectiveSlug}_${activeEventId ?? 'all'}_${lockedEventId ?? 'unlocked'}'),
            initialEventId: activeEventId,
            lockedEventId: lockedEventId,
            lockedCompanySlug: effectiveSlug,
            lockedCompanyName: companyDisplayName,
            isEmbedded: true,
          );
        case 3:
          return DailyBranchSalesScreen(
            key: ValueKey('agency_daily_sales_${effectiveSlug}_${activeEventId ?? 'all'}_${lockedEventId ?? 'unlocked'}'),
            initialEventId: activeEventId,
            lockedEventId: lockedEventId,
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
          key: ValueKey('invoices_${effectiveSlug}_${activeEventId ?? 'all'}_${lockedEventId ?? 'unlocked'}'),
          initialEventId: activeEventId,
          lockedEventId: lockedEventId,
          lockedCompanySlug: effectiveSlug,
          lockedCompanyName: companyDisplayName,
          isEmbedded: true,
        );
      case 3:
        return DailyBranchSalesScreen(
          key: ValueKey('daily_sales_${effectiveSlug}_${activeEventId ?? 'all'}_${lockedEventId ?? 'unlocked'}'),
          initialEventId: activeEventId,
          lockedEventId: lockedEventId,
          lockedCompanySlug: effectiveSlug,
        );
      case 4:
        return BranchStockBalancesScreen(
          key: ValueKey('balances_${effectiveSlug}_${activeEventId ?? 'all'}_${lockedEventId ?? 'unlocked'}_$isReadOnlyStock'),
          initialEventId: activeEventId,
          lockedEventId: lockedEventId,
          lockedCompanySlug: effectiveSlug,
          lockedCompanyName: companyDisplayName,
          isEmbedded: true,
          isReadOnly: isReadOnlyStock,
        );
      case 5:
        return CompanyVouchersReportScreen(
          key: ValueKey('vouchers_${effectiveSlug}_${activeEventId ?? 'all'}_${lockedEventId ?? 'unlocked'}'),
          initialEventId: activeEventId,
          lockedEventId: lockedEventId,
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

  /// Builds the desktop/tablet M3 Navigation Rail (Fixed 80dp slim rail with icon on top and concise label underneath)
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
    bool isMedium = false,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.fastOutSlowIn,
      width: 80.0,
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
      child: SizedBox(
        width: 80.0,
        child: LayoutBuilder(
          builder: (context, railConstraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: railConstraints.maxHeight),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    selectedIndex: _selectedTab,
                    onDestinationSelected: (index) {
                      setState(() {
                        _selectedTab = index;
                        _loadedTabs.add(index);
                      });
                    },
                    labelType: NavigationRailLabelType.all,
                    minWidth: 80.0,
                    backgroundColor: colorScheme.surfaceContainerLow,
                    elevation: 1,
                    trailingAtBottom: true,
                    indicatorColor: colorScheme.secondaryContainer,
                    selectedIconTheme: IconThemeData(color: colorScheme.onSecondaryContainer, size: 24),
                    unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant, size: 22),
                    selectedLabelTextStyle: GoogleFonts.cairo(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      height: 1.15,
                    ),
                    unselectedLabelTextStyle: GoogleFonts.cairo(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      fontSize: 9.5,
                      height: 1.15,
                    ),
                    destinations: [
                      for (final item in navItems)
                        NavigationRailDestination(
                          icon: Tooltip(
                            message: item.tooltip,
                            child: Icon(item.icon),
                          ),
                          selectedIcon: Tooltip(
                            message: item.tooltip,
                            child: Icon(item.selectedIcon),
                          ),
                          label: Text(
                            item.title,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (campaignsCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Tooltip(
                              message: '$campaignsCount ${strings.companyAllCampaigns}',
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.campaign_rounded, size: 13, color: colorScheme.primary),
                                    const SizedBox(width: 3),
                                    Text(
                                      '$campaignsCount',
                                      style: GoogleFonts.cairo(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        // 1. Copy Promoter Link Quick Button
                        Tooltip(
                          message: strings.copyPromoterLink,
                          child: IconButton(
                            icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _copyPromoterLink(context, strings, effectiveSlug, eventId: activeEventId),
                          ),
                        ),
                        // 2. Copy Agency Ops Link Quick Button
                        Tooltip(
                          message: strings.copyAgencyOpsLink,
                          child: IconButton(
                            icon: const Icon(Icons.store_mall_directory_rounded, size: 18),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _copyAgencyOpsLink(context, strings, effectiveSlug, eventId: activeEventId),
                          ),
                        ),
                        // 3. Copy Brand Executive Master Link Quick Button (Brand Manager / Admin only)
                        if (!widget.isAgencyOpsMode)
                          Tooltip(
                            message: strings.copyBrandExecutiveLink,
                            child: IconButton(
                              icon: const Icon(Icons.business_center_rounded, size: 18),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _copyBrandExecutiveLink(context, strings, effectiveSlug),
                            ),
                          ),
                        const SizedBox(height: 4),
                        // 4. Portal Settings & Preferences Button
                        Tooltip(
                          message: isAr ? 'الإعدادات وتفضيلات النظام' : (isHi ? 'सेटिंग्स और प्राथमिकताएं' : 'Settings & Preferences'),
                          child: Container(
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                            ),
                            child: IconButton(
                              icon: Icon(Icons.tune_rounded, size: 18, color: colorScheme.primary),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(6),
                              constraints: const BoxConstraints(),
                              onPressed: () => _showPortalSettingsDialog(
                                context: context,
                                strings: strings,
                                isAr: isAr,
                                isHi: isHi,
                                colorScheme: colorScheme,
                                effectiveSlug: effectiveSlug,
                                activeEventId: activeEventId,
                                companyDisplayName: companyName,
                                companyLogoUrl: companyLogoUrl,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12, top: 2),
                          child: Tooltip(
                            message: '$companyName • ${strings.partnerPortalBadge}',
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: companyLogoUrl.isNotEmpty ? Colors.white : colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: companyLogoUrl.isNotEmpty
                                    ? Image.network(
                                        companyLogoUrl,
                                        fit: BoxFit.contain,
                                        errorBuilder: (context, error, stackTrace) => Center(
                                          child: Icon(Icons.business_rounded, color: colorScheme.primary, size: 20),
                                        ),
                                      )
                                    : Center(
                                        child: Icon(Icons.business_rounded, color: colorScheme.primary, size: 20),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
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
                ],
              ),
            ),

            const Divider(height: 1),

            // 2. Bottom Fixed Section (الإعدادات + 3 أيقونات مشاركة الروابط + Tashil Gift)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Preferences & Settings (الإعدادات) - Collapsed by default
                  Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: ExpansionTile(
                          initiallyExpanded: false,
                          shape: const Border(),
                          collapsedShape: const Border(),
                          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          leading: Icon(
                            Icons.settings_rounded,
                            size: 18,
                            color: colorScheme.secondary,
                          ),
                          title: Text(
                            isAr ? 'الإعدادات' : (isHi ? 'सेटिंग्स' : 'Settings'),
                            style: GoogleFonts.cairo(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            isAr ? 'اللغة والدولة والمظهر' : (isHi ? 'भाषा, देश और थीम' : 'Language, country & theme'),
                            style: GoogleFonts.cairo(
                              fontSize: 10,
                              color: colorScheme.outline,
                            ),
                          ),
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 280),
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const Divider(height: 12),
                                    // Language Selector
                                    Row(
                                      children: [
                                        Icon(Icons.translate_rounded, size: 14, color: colorScheme.primary),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            isAr ? 'لغة الواجهة' : (isHi ? 'ऐप भाषा' : 'Language'),
                                            style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      height: 38,
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: ref.watch(localeProvider).languageCode,
                                          isExpanded: true,
                                          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                                          dropdownColor: colorScheme.surfaceContainerHigh,
                                          borderRadius: BorderRadius.circular(10),
                                          style: GoogleFonts.cairo(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            color: colorScheme.onSurface,
                                          ),
                                          items: AppLanguage.values.map((lang) {
                                            return DropdownMenuItem<String>(
                                              value: lang.code,
                                              child: Text(
                                                lang.label,
                                                style: GoogleFonts.cairo(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: colorScheme.onSurface,
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (val) {
                                            if (val != null) ref.setLocale(val);
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),

                                    // Country & Currency Selector
                                    Row(
                                      children: [
                                        Icon(Icons.payments_rounded, size: 14, color: colorScheme.secondary),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            isAr ? 'الدولة والعملة المعتمدة' : (isHi ? 'देश और मुद्रा' : 'Country & Currency'),
                                            style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      height: 38,
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: ref.watch(activeCountryProvider).code,
                                          isExpanded: true,
                                          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                                          dropdownColor: colorScheme.surfaceContainerHigh,
                                          borderRadius: BorderRadius.circular(10),
                                          style: GoogleFonts.cairo(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            color: colorScheme.onSurface,
                                          ),
                                          items: CountryCurrencyConfig.supportedCountries.map((country) {
                                            final currentLangCode = ref.watch(localeProvider).languageCode;
                                            return DropdownMenuItem<String>(
                                              value: country.code,
                                              child: Text(
                                                '${country.name(currentLangCode)} (${country.currencySymbolFor(currentLangCode)})',
                                                style: GoogleFonts.cairo(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: colorScheme.onSurface,
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (val) {
                                            if (val != null) {
                                              final country = CountryCurrencyConfig.findByCode(val);
                                              ref.read(activeCountryProvider.notifier).state = country;
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),

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
                                          color: isDark ? colorScheme.primary : colorScheme.primary,
                                          size: 18,
                                        ),
                                        title: Text(
                                          isAr
                                              ? (isDark ? 'الوضع الداكن' : 'الوضع الفاتح')
                                              : (isHi
                                                  ? (isDark ? 'डार्क मोड' : 'लाइट मोड')
                                                  : (isDark ? 'Dark Mode' : 'Light Mode')),
                                          style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold),
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
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Section 3: Quick Portal Links (مشاركة روابط البوابات - 3 أيكونات فقط)
                  Row(
                    children: [
                      Icon(Icons.share_rounded, size: 13, color: colorScheme.outline),
                      const SizedBox(width: 6),
                      Text(
                        isAr ? 'مشاركة روابط البوابات' : (isHi ? 'पोर्टल लिंक साझा करें' : 'Share Portal Links'),
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // The 3 Portal Share Icon Buttons Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 1. رابط العميل / البروموتر
                      _buildDrawerShareIconButton(
                        context: context,
                        icon: Icons.qr_code_scanner_rounded,
                        tooltip: strings.copyPromoterLink,
                        colorScheme: colorScheme,
                        onTap: () {
                          _copyPromoterLink(context, strings, effectiveSlug, eventId: activeEventId);
                          Navigator.of(context).pop();
                        },
                      ),
                      // 2. رابط بوابة شركة الدعاية
                      _buildDrawerShareIconButton(
                        context: context,
                        icon: Icons.store_mall_directory_rounded,
                        tooltip: strings.copyAgencyOpsLink,
                        colorScheme: colorScheme,
                        onTap: () {
                          _copyAgencyOpsLink(context, strings, effectiveSlug, eventId: activeEventId);
                          Navigator.of(context).pop();
                        },
                      ),
                      // 3. رابط مدير الشركة الدائم (Brand Manager / Admin only)
                      if (!widget.isAgencyOpsMode)
                        _buildDrawerShareIconButton(
                          context: context,
                          icon: Icons.business_center_rounded,
                          tooltip: strings.copyBrandExecutiveLink,
                          colorScheme: colorScheme,
                          onTap: () {
                            _copyBrandExecutiveLink(context, strings, effectiveSlug);
                            Navigator.of(context).pop();
                          },
                        ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Tashil Gift Version Footer
                  Center(
                    child: Text(
                      'Tashil Gift ${AppVersionConfig.versionDisplay} (Build #${AppVersionConfig.buildNumber})',
                      style: GoogleFonts.cairo(
                        fontSize: 10,
                        color: colorScheme.outline.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a single compact share icon button for the mobile drawer bottom bar
  Widget _buildDrawerShareIconButton({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 58,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              size: 20,
              color: colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  /// Displays the Material Design 3 Portal Settings Dialog (Language, Currency, Theme & Share Links)
  void _showPortalSettingsDialog({
    required BuildContext context,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required ColorScheme colorScheme,
    required String effectiveSlug,
    required String? activeEventId,
    required String companyDisplayName,
    required String companyLogoUrl,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return Consumer(
          builder: (context, ref, _) {
            final activeLangCode = ref.watch(localeProvider).languageCode;
            final currentAr = activeLangCode == 'ar';
            final currentHi = activeLangCode == 'hi';
            final activeCountry = ref.watch(activeCountryProvider);
            final themeMode = ref.watch(themeModeProvider);
            final isDark = themeMode == ThemeMode.dark ||
                (themeMode == ThemeMode.system && Theme.of(context).brightness == Brightness.dark);
            final dialogTheme = Theme.of(context);
            final dialogColorScheme = dialogTheme.colorScheme;

            return Directionality(
              textDirection: currentAr ? TextDirection.rtl : TextDirection.ltr,
              child: Dialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                backgroundColor: dialogColorScheme.surface,
                elevation: 6,
                child: Container(
                  width: 480,
                  constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: dialogColorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.tune_rounded,
                              color: dialogColorScheme.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentAr ? 'الإعدادات وتفضيلات النظام' : (currentHi ? 'सेटिंग्स और सिस्टम प्राथमिकताएं' : 'Settings & Preferences'),
                                  style: GoogleFonts.cairo(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: dialogColorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  currentAr ? 'اللغة، العملة، مشاركة الروابط، والمظهر' : (currentHi ? 'भाषा, मुद्रा, पोर्टल लिंक और थीम' : 'Language, Currency, Links & Theme'),
                                  style: GoogleFonts.cairo(
                                    fontSize: 11.5,
                                    color: dialogColorScheme.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 16),

                      // Scrollable Settings Content
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 1. Language Section
                              Text(
                                currentAr ? 'لغة الواجهة' : (currentHi ? 'ऐप भाषा' : 'Interface Language'),
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: dialogColorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: AppLanguage.values.map((lang) {
                                  final isSelected = activeLangCode == lang.code;
                                  return ChoiceChip(
                                    label: Text(
                                      lang.label,
                                      style: GoogleFonts.cairo(
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                      ),
                                    ),
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      if (selected) {
                                        ref.setLocale(lang.code);
                                      }
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 18),

                              // 2. Country & Currency Section
                              Text(
                                currentAr ? 'الدولة والعملة المعتمدة' : (currentHi ? 'देश और मुद्रा' : 'Country & Currency'),
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: dialogColorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: dialogColorScheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: dialogColorScheme.outlineVariant.withValues(alpha: 0.6)),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: activeCountry.code,
                                    isExpanded: true,
                                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: dialogColorScheme.onSurfaceVariant),
                                    dropdownColor: dialogColorScheme.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(12),
                                    items: CountryCurrencyConfig.supportedCountries.map((c) {
                                      return DropdownMenuItem<String>(
                                        value: c.code,
                                        child: Text(
                                          '${c.name(activeLangCode)} (${c.currencySymbolFor(activeLangCode)})',
                                          style: GoogleFonts.cairo(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: dialogColorScheme.onSurface,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        final country = CountryCurrencyConfig.findByCode(val);
                                        ref.read(activeCountryProvider.notifier).state = country;
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),

                              // 3. Quick Share Links Section
                              Text(
                                currentAr ? 'روابط المنظومة المباشرة' : (currentHi ? 'पोर्टल लिंक' : 'Direct Portal Links'),
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: dialogColorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildSettingsLinkTile(
                                context: context,
                                icon: Icons.qr_code_scanner_rounded,
                                title: currentAr ? 'رابط المتسوق والبروموتر في الفرع' : (currentHi ? 'प्रमोटर और खरीदार लिंक' : 'Promoter & Shopper Link'),
                                subtitle: AppUrlBuilder.buildPromoterUrl(effectiveSlug, eventId: activeEventId),
                                tooltip: strings.copyPromoterLink,
                                colorScheme: dialogColorScheme,
                                onCopy: () => _copyPromoterLink(context, strings, effectiveSlug, eventId: activeEventId),
                              ),
                              const SizedBox(height: 6),
                              _buildSettingsLinkTile(
                                context: context,
                                icon: Icons.store_mall_directory_rounded,
                                title: currentAr ? 'رابط عمليات الوكالة وفريق الميدان' : (currentHi ? 'एजेंसी संचालन लिंक' : 'Agency Field Ops Link'),
                                subtitle: AppUrlBuilder.buildAgencyOpsUrl(effectiveSlug, eventId: activeEventId),
                                tooltip: strings.copyAgencyOpsLink,
                                colorScheme: dialogColorScheme,
                                onCopy: () => _copyAgencyOpsLink(context, strings, effectiveSlug, eventId: activeEventId),
                              ),
                              if (!widget.isAgencyOpsMode) ...[
                                const SizedBox(height: 6),
                                _buildSettingsLinkTile(
                                  context: context,
                                  icon: Icons.business_center_rounded,
                                  title: currentAr ? 'رابط مدير الشركة التنفيذي' : (currentHi ? 'कंपनी प्रबंधक लिंक' : 'Brand Executive Link'),
                                  subtitle: AppUrlBuilder.buildBrandExecutiveUrl(effectiveSlug),
                                  tooltip: strings.copyBrandExecutiveLink,
                                  colorScheme: dialogColorScheme,
                                  onCopy: () => _copyBrandExecutiveLink(context, strings, effectiveSlug),
                                ),
                              ],
                              const SizedBox(height: 18),

                              // 4. Theme Mode
                              Container(
                                decoration: BoxDecoration(
                                  color: dialogColorScheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: dialogColorScheme.outlineVariant.withValues(alpha: 0.6)),
                                ),
                                child: SwitchListTile(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  secondary: Icon(
                                    isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                                    color: isDark ? colorScheme.primary : dialogColorScheme.primary,
                                  ),
                                  title: Text(
                                    currentAr
                                        ? (isDark ? 'الوضع الداكن (Dark Mode)' : 'الوضع الفاتح (Light Mode)')
                                        : (currentHi
                                            ? (isDark ? 'डार्क मोड' : 'लाइट मोड')
                                            : (isDark ? 'Dark Mode' : 'Light Mode')),
                                    style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                  value: isDark,
                                  onChanged: (val) {
                                    ref.read(themeModeProvider.notifier).state =
                                        val ? ThemeMode.dark : ThemeMode.light;
                                  },
                                ),
                              ),

                              // 5. Sign Out Option (for Portal Sessions)
                              if (widget.requirePortalAuth) ...[
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.of(dialogContext).pop();
                                      _signOutPortalSession(effectiveSlug, eventId: activeEventId);
                                    },
                                    icon: Icon(Icons.logout_rounded, size: 18, color: dialogColorScheme.error),
                                    label: Text(
                                      currentAr
                                          ? 'تسجيل الخروج من البوابة'
                                          : (currentHi ? 'पोर्टल से साइन आउट करें' : 'Sign Out of Portal'),
                                      style: GoogleFonts.cairo(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: dialogColorScheme.error,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      side: BorderSide(color: dialogColorScheme.error.withValues(alpha: 0.5)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSettingsLinkTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String tooltip,
    required ColorScheme colorScheme,
    required VoidCallback onCopy,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.cairo(fontSize: 10, color: colorScheme.outline),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Tooltip(
            message: tooltip,
            child: IconButton.filledTonal(
              icon: const Icon(Icons.copy_rounded, size: 16),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
              onPressed: onCopy,
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
    final layout = M3Layout.of(context);

    FirebaseFirestore? firestore;
    try {
      firestore = ref.watch(firestoreProvider);
    } catch (_) {
      firestore = null;
    }

    final eventsStream = _ensureEventsStream(firestore);

    Widget buildPortalBody(PartnerPortalSession? session) {
      if (eventsStream != null) {
        return StreamBuilder<QuerySnapshot>(
          stream: eventsStream,
          builder: (context, snapshot) {
            final rawDocs = snapshot.data?.docs ?? [];
            final lockedId = session?.lockedEventId;
            final allDocs = (lockedId != null && lockedId.isNotEmpty)
                ? rawDocs.where((d) => d.id == lockedId).toList()
                : rawDocs;
            return _buildScaffoldContent(
              context: context,
              colorScheme: colorScheme,
              textTheme: textTheme,
              strings: strings,
              isAr: isAr,
              isHi: isHi,
              layout: layout,
              allDocs: allDocs,
              portalSession: session,
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
        layout: layout,
        allDocs: const [],
        portalSession: session,
      );
    }

    if (widget.requirePortalAuth) {
      return PortalAuthGuard(
        companySlug: widget.companySlug,
        eventId: widget.initialEventId,
        requiredRole: widget.isAgencyOpsMode
            ? PartnerPortalRole.agencyOps
            : PartnerPortalRole.brandManager,
        authenticatedBuilder: (context, session) => buildPortalBody(session),
      );
    }

    return buildPortalBody(null);
  }
}
