import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/widgets/switch_point_branding.dart';
import '../../admin/domain/event_model.dart';
import '../../admin/presentation/campaign_reports_screen.dart';
import '../../validation/presentation/invoices_log_screen.dart';
import 'company_vouchers_report_screen.dart';
import 'branch_stock_balances_screen.dart';
import 'daily_branch_sales_screen.dart';
import '../../../core/utils/url_builder.dart';
import '../../../core/utils/slug_utils.dart';
import '../../../core/widgets/campaign_suspended_screen.dart';

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

  const CompanyManagerPortalScreen({
    super.key,
    required this.companySlug,
    this.initialEventId,
  });

  @override
  ConsumerState<CompanyManagerPortalScreen> createState() => _CompanyManagerPortalScreenState();
}

class _CompanyManagerPortalScreenState extends ConsumerState<CompanyManagerPortalScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedTab = 0; // 0 = Analytics & Insights, 1 = Invoice Audit Feed, 2 = Vouchers, 3 = Prizes & Stock Balance
  final Set<int> _loadedTabs = {0}; // Lazy loading set: only render tabs when requested
  bool _isSidebarExpanded = true;

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

  List<_PortalNavItem> _getNavItems(AppStrings strings, bool isAr, bool isHi) {
    return [
      _PortalNavItem(
        index: 0,
        icon: Icons.analytics_outlined,
        selectedIcon: Icons.analytics_rounded,
        title: strings.analyticsTitle,
        subtitle: isAr ? 'المؤشرات والتحليلات والمبيعات' : (isHi ? 'एनालिटिक्स और प्रदर्शन' : 'KPIs, Analytics & Sales'),
        tooltip: isAr ? 'التقارير والتحليلات التفاعلية الشاملة للشركة' : 'Comprehensive Analytics & Reports',
        accentColor: const Color(0xFF6750A4),
      ),
      _PortalNavItem(
        index: 1,
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long_rounded,
        title: strings.invoicesAuditTitle,
        subtitle: isAr ? 'سجل الفواتير وتدقيق المنتجات والـ CSV' : (isHi ? 'इनवॉइस ऑडिट और निर्यात' : 'Invoices Audit, Fraud & CSV Export'),
        tooltip: isAr ? 'سجل الفواتير وتدقيق المنتجات والمبيعات وعمليات التصدير' : 'Invoices Log, Product Audit & CSV',
        accentColor: const Color(0xFF006C50),
      ),
      _PortalNavItem(
        index: 2,
        icon: Icons.point_of_sale_outlined,
        selectedIcon: Icons.point_of_sale_rounded,
        title: strings.dailyBranchSalesNavTitle,
        subtitle: strings.dailyBranchSalesNavSubtitle,
        tooltip: strings.dailyBranchSalesNavTooltip,
        accentColor: const Color(0xFF2563EB),
      ),
      _PortalNavItem(
        index: 3,
        icon: Icons.account_balance_wallet_outlined,
        selectedIcon: Icons.account_balance_wallet_rounded,
        title: strings.branchBalancesNavTitle,
        subtitle: strings.branchBalancesNavSubtitle,
        tooltip: strings.branchBalancesNavTooltip,
        accentColor: const Color(0xFF0284C7),
      ),
      _PortalNavItem(
        index: 4,
        icon: Icons.confirmation_number_outlined,
        selectedIcon: Icons.confirmation_number_rounded,
        title: strings.vouchersNavTitle,
        subtitle: strings.vouchersNavSubtitle,
        tooltip: strings.vouchersNavTooltip,
        accentColor: const Color(0xFFD97706),
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
    final navItems = _getNavItems(strings, isAr, isHi);

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: colorScheme.surface,
        appBar: SwitchPointHeader(
        leading: isMobile
            ? IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.dashboard_customize_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                tooltip: isAr ? 'قائمة لوحة التحكم' : 'Dashboard Menu',
                onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
              )
            : null,
        subtitle: '$companyDisplayName • ${strings.partnerPortalBadge}',
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
                // Copy Portal Link quick button
                Tooltip(
                  message: strings.copyManagerPortalLink,
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.share_rounded, size: 18),
                    padding: const EdgeInsets.all(8),
                    onPressed: () => _copyPortalLink(context, strings, effectiveSlug, activeEventId),
                  ),
                ),
                const SizedBox(width: 8),
              ],
      ),

      // Mobile EndDrawer for seamless phone navigation
      endDrawer: isMobile
          ? _buildMobileDrawer(
              context: context,
              colorScheme: colorScheme,
              textTheme: textTheme,
              strings: strings,
              companyName: companyDisplayName,
              effectiveSlug: effectiveSlug,
              activeEventId: activeEventId,
              campaignsCount: companyEvents.length,
              navItems: navItems,
              isAr: isAr,
              isHi: isHi,
            )
          : null,

      // Mobile Bottom Navigation Bar for quick thumb-reach switching
      bottomNavigationBar: isMobile
          ? NavigationBar(
              selectedIndex: _selectedTab.clamp(0, 5),
              onDestinationSelected: (idx) {
                setState(() {
                  _selectedTab = idx;
                  _loadedTabs.add(idx);
                });
              },
              backgroundColor: colorScheme.surfaceContainerLow,
              elevation: 3,
              height: 65,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.analytics_outlined),
                  selectedIcon: const Icon(Icons.analytics_rounded),
                  label: isAr ? 'التقارير' : (isHi ? 'रिपोर्ट' : 'Reports'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.receipt_long_outlined),
                  selectedIcon: const Icon(Icons.receipt_long_rounded),
                  label: isAr ? 'الفواتير' : (isHi ? 'इनवॉइस' : 'Invoices'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.point_of_sale_outlined),
                  selectedIcon: const Icon(Icons.point_of_sale_rounded),
                  label: isAr ? 'المبيعات' : (isHi ? 'दैनिक बिक्री' : 'Daily Sales'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: const Icon(Icons.account_balance_wallet_rounded),
                  label: isAr ? 'الأرصدة' : (isHi ? 'बैलेंस' : 'Balances'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.confirmation_number_outlined),
                  selectedIcon: const Icon(Icons.confirmation_number_rounded),
                  label: isAr ? 'القسائم' : (isHi ? 'वाउचर' : 'Vouchers'),
                ),
              ],
            )
          : null,

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
                  for (int i = 0; i < 5; i++)
                    Offstage(
                      offstage: _selectedTab != i,
                      child: TickerMode(
                        enabled: _selectedTab == i,
                        child: _loadedTabs.contains(i)
                            ? _buildTabContent(
                                tabIndex: i,
                                effectiveSlug: effectiveSlug,
                                companyDisplayName: companyDisplayName,
                                activeEventId: activeEventId,
                                initialEvent: initialEvent,
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

  /// Builds tab content on-demand (Zero CPU/memory overhead for unvisited tabs)
  Widget _buildTabContent({
    required int tabIndex,
    required String effectiveSlug,
    required String companyDisplayName,
    required String? activeEventId,
    required EventModel? initialEvent,
  }) {
    switch (tabIndex) {
      case 0:
        return CampaignReportsScreen(
          key: ValueKey('reports_${effectiveSlug}_${activeEventId ?? 'all'}'),
          initialEvent: initialEvent,
          lockedCompanySlug: effectiveSlug,
          lockedCompanyName: companyDisplayName,
          isEmbedded: true,
        );
      case 1:
        return InvoicesLogScreen(
          key: ValueKey('invoices_${effectiveSlug}_${activeEventId ?? 'all'}'),
          initialEventId: activeEventId,
          lockedCompanySlug: effectiveSlug,
          lockedCompanyName: companyDisplayName,
          isEmbedded: true,
        );
      case 2:
        return DailyBranchSalesScreen(
          key: ValueKey('daily_sales_${effectiveSlug}_${activeEventId ?? 'all'}'),
          initialEventId: activeEventId,
          lockedCompanySlug: effectiveSlug,
        );
      case 3:
        return BranchStockBalancesScreen(
          key: ValueKey('balances_${effectiveSlug}_${activeEventId ?? 'all'}'),
          initialEventId: activeEventId,
          lockedCompanySlug: effectiveSlug,
          lockedCompanyName: companyDisplayName,
          isEmbedded: true,
        );
      case 4:
        return CompanyVouchersReportScreen(
          key: ValueKey('vouchers_${effectiveSlug}_${activeEventId ?? 'all'}'),
          initialEventId: activeEventId,
          lockedCompanySlug: effectiveSlug,
          lockedCompanyName: companyDisplayName,
          isEmbedded: true,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  /// Builds the desktop collapsible dashboard navigation sidebar (Right side in Arabic RTL, Left in English/Hindi LTR)
  Widget _buildDesktopSidebar({
    required BuildContext context,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required AppStrings strings,
    required String companyName,
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
            width: _isSidebarExpanded ? 275.0 : 76.0,
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
                                  gradient: LinearGradient(
                                    colors: [
                                      colorScheme.primary,
                                      colorScheme.secondary,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.business_rounded,
                                    color: colorScheme.onPrimary,
                                    size: 18,
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
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.business_rounded,
                          color: Colors.white,
                          size: 26,
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

            // Navigation Items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
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

            // Drawer Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: Text(strings.copyManagerPortalLink),
                    onPressed: () {
                      _copyPortalLink(context, strings, effectiveSlug, activeEventId);
                      Navigator.of(context).pop();
                    },
                  ),
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
