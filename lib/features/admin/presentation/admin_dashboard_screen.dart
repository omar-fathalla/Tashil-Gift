import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../domain/event_model.dart';
import 'create_event_screen.dart';
import 'campaign_reports_screen.dart';
import '../../validation/presentation/invoices_log_screen.dart';
import '../../client_portal/presentation/client_receipt_upload_screen.dart';
import '../../company_portal/presentation/company_manager_portal_screen.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/widgets/switch_point_branding.dart';
import '../../../core/constants/country_currency_config.dart';
import '../../../core/widgets/m3_button_groups.dart';
import 'company_catalog_screen.dart';
import '../../company_portal/presentation/company_customers_marketing_screen.dart';
import 'company_gifts_screen.dart';
import '../../games/presentation/game_types_screen.dart';
import 'retail_chains_screen.dart';
import 'chain_products_intelligence_screen.dart';
import 'ai_speed_benchmark_screen.dart';
import 'ai_brain_rules_screen.dart';
import 'ai_product_discovery_screen.dart';
import '../../../core/services/ai_product_discovery_service.dart';
import 'widgets/voucher_serials_management_dialog.dart';
import '../../../core/services/company_gifts_service.dart';
import '../../../core/utils/url_builder.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  int _selectedIndex = 0;
  final Set<int> _loadedTabs = {0};
  bool _isSidebarExpanded = true;
  String _campaignFilter = 'ALL';
  EventModel? _selectedReportsEvent;
  final _searchController = TextEditingController();

  void _selectTab(int index) {
    if (_selectedIndex != index) {
      setState(() {
        _selectedIndex = index;
        _loadedTabs.add(index);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _copyPromoterLink(BuildContext context, String slug, {String? eventId}) {
    final url = AppUrlBuilder.buildPromoterUrl(slug, eventId: eventId);
    Clipboard.setData(ClipboardData(text: url));
    final strings = AppStrings.of(ref);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${strings.promoterLinkCopied}: $url'),
        backgroundColor: Colors.teal.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copyAgencyOpsLink(BuildContext context, String slug, {String? eventId}) {
    final url = AppUrlBuilder.buildAgencyOpsUrl(slug, eventId: eventId);
    Clipboard.setData(ClipboardData(text: url));
    final strings = AppStrings.of(ref);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${strings.agencyOpsLinkCopied}: $url'),
        backgroundColor: Colors.purple.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copyBrandExecutiveLink(BuildContext context, String slug, {String? eventId}) {
    final url = AppUrlBuilder.buildBrandExecutiveUrl(slug, eventId: eventId);
    Clipboard.setData(ClipboardData(text: url));
    final strings = AppStrings.of(ref);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${strings.brandExecutiveLinkCopied}: $url'),
        backgroundColor: Colors.indigo.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showDeleteCampaignDialog(
    BuildContext context,
    EventModel event,
    AppStrings strings,
    FirebaseFirestore? firestore,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final isAr = ref.isArabic;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.delete_forever_rounded, color: cs.error, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  strings.deleteCampaignConfirmTitle,
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.eventName,
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14, color: cs.primary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${isAr ? 'الشركة:' : 'Company:'} ${event.targetCompany} • ${isAr ? 'السلسلة:' : 'Chain:'} ${event.retailChainName}',
                      style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                strings.deleteCampaignConfirmBody,
                style: GoogleFonts.cairo(fontSize: 13, color: cs.onSurface),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(strings.cancel, style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.delete_forever_rounded, size: 18),
              label: Text(strings.deleteCampaignBtn, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirmed == true && firestore != null) {
      try {
        await firestore.collection('events').doc(event.id).delete();
        if (event.companySlug.isNotEmpty) {
          await ref.read(companyGiftsServiceProvider).syncCompanyGiftsAvailableQuantities(event.companySlug);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(strings.campaignDeletedSuccess),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppStrings.of(ref).operationFailed(e.toString())),
              backgroundColor: Colors.red.shade900,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleSignOut(BuildContext context, AppStrings strings) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.logout_rounded, color: cs.error),
              const SizedBox(width: 8),
              Text(
                strings.confirmSignOutTitle,
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            strings.confirmSignOutMsg,
            style: GoogleFonts.cairo(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(strings.cancel, style: GoogleFonts.cairo()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(strings.signOutBtn, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await ref.read(firebaseServiceProvider).signOut();
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    }
  }

  Widget _buildProfileMenu(
    BuildContext context,
    ColorScheme colorScheme,
    AppStrings strings,
    bool isMobile,
  ) {
    String sessionEmail = kPrimaryAdminEmail;
    try {
      sessionEmail = ref.watch(adminSessionEmailProvider) ??
          ref.read(firebaseServiceProvider).currentUser?.email ??
          kPrimaryAdminEmail;
    } catch (_) {}

    return PopupMenuButton<String>(
      tooltip: strings.adminProfileTooltip,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      color: colorScheme.surfaceContainerHigh,
      elevation: 6,
      onSelected: (value) {
        if (value == 'sign_out') {
          _handleSignOut(context, strings);
        }
      },
      itemBuilder: (BuildContext ctx) => [
        // 1. Profile Info Header Card
        PopupMenuItem<String>(
          enabled: false,
          child: Container(
            constraints: const BoxConstraints(minWidth: 200),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(
                    Icons.admin_panel_settings_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        strings.systemAdminRole,
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        sessionEmail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            strings.activeSessionLabel,
                            style: GoogleFonts.cairo(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const PopupMenuDivider(height: 1),
        // 2. Sign Out Action
        PopupMenuItem<String>(
          value: 'sign_out',
          child: Row(
            children: [
              Icon(
                Icons.logout_rounded,
                color: colorScheme.error,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                strings.signOutBtn,
                style: GoogleFonts.cairo(
                  color: colorScheme.error,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 6 : 10,
          vertical: isMobile ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: isMobile ? 12 : 14,
              backgroundColor: colorScheme.primary,
              child: const Icon(
                Icons.person_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
            if (!isMobile) ...[
              const SizedBox(width: 6),
              Text(
                strings.systemAdminRole,
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_drop_down_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    FirebaseFirestore? firestore;
    try {
      firestore = ref.watch(firestoreProvider);
    } catch (_) {
      firestore = null;
    }
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isTablet = screenWidth >= 600 && screenWidth < 1000;
    final strings = AppStrings.of(ref);
    final isAr = ref.isArabic;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: SwitchPointHeader(
        leading: !isMobile
            ? IconButton(
                icon: Icon(_isSidebarExpanded ? Icons.menu_open : Icons.menu, color: colorScheme.primary),
                tooltip: _isSidebarExpanded ? strings.collapseMenu : strings.expandMenu,
                onPressed: () {
                  setState(() => _isSidebarExpanded = !_isSidebarExpanded);
                },
              )
            : null,
        customActions: [
          _buildProfileMenu(context, colorScheme, strings, isMobile),
        ],
      ),
      body: Row(
        children: [
          if (!isMobile) ...[
            // Sidebar Navigation (Desktop/Tablet) wrapped in RepaintBoundary for 60 FPS (Rule 9 / Pillar 2)
            RepaintBoundary(
              child: NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _selectTab,
                extended: !isTablet && _isSidebarExpanded,
                minWidth: 72,
                minExtendedWidth: 230,
                backgroundColor: colorScheme.surfaceContainerLow,
                elevation: 1,
                indicatorColor: colorScheme.secondaryContainer,
                selectedIconTheme: IconThemeData(color: colorScheme.onSecondaryContainer, size: 24),
                unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant, size: 22),
                selectedLabelTextStyle: GoogleFonts.cairo(color: colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 14),
                unselectedLabelTextStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant, fontSize: 13),
                destinations: [
                  NavigationRailDestination(
                    icon: const Icon(Icons.dashboard_outlined),
                    selectedIcon: const Icon(Icons.dashboard_rounded),
                    label: Text(strings.navEventsManagement),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.bar_chart_outlined),
                    selectedIcon: const Icon(Icons.bar_chart_rounded),
                    label: Text(strings.navAnalytics),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.business_center_outlined),
                    selectedIcon: const Icon(Icons.business_center_rounded),
                    label: Text(strings.navCompanyCatalog),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.storefront_outlined),
                    selectedIcon: const Icon(Icons.storefront_rounded),
                    label: Text(strings.navRetailChains),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.inventory_2_outlined),
                    selectedIcon: const Icon(Icons.inventory_2_rounded),
                    label: Text(strings.navProductsIntelligence),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.receipt_long_outlined),
                    selectedIcon: const Icon(Icons.receipt_long_rounded),
                    label: Text(strings.navInvoicesAudit),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    selectedIcon: const Icon(Icons.add_circle_rounded),
                    label: Text(strings.navCreateCampaign),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.card_giftcard_outlined),
                    selectedIcon: const Icon(Icons.card_giftcard_rounded),
                    label: Text(strings.navCompanyGifts),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.casino_outlined),
                    selectedIcon: const Icon(Icons.casino_rounded),
                    label: Text(strings.navGameTypes),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.speed_outlined),
                    selectedIcon: const Icon(Icons.speed_rounded),
                    label: Text(strings.navAiSpeedBenchmark),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.psychology_outlined),
                    selectedIcon: const Icon(Icons.psychology_rounded),
                    label: Text(strings.navAiBrainRules),
                  ),
                  NavigationRailDestination(
                    icon: StreamBuilder<int>(
                      stream: ref.watch(aiProductDiscoveryServiceProvider).streamPendingCount(),
                      builder: (context, snapshot) {
                        final count = snapshot.data ?? 0;
                        return Badge(
                          isLabelVisible: count > 0,
                          label: Text('$count'),
                          backgroundColor: Colors.orange.shade800,
                          child: const Icon(Icons.auto_awesome_outlined),
                        );
                      },
                    ),
                    selectedIcon: StreamBuilder<int>(
                      stream: ref.watch(aiProductDiscoveryServiceProvider).streamPendingCount(),
                      builder: (context, snapshot) {
                        final count = snapshot.data ?? 0;
                        return Badge(
                          isLabelVisible: count > 0,
                          label: Text('$count'),
                          backgroundColor: Colors.orange.shade800,
                          child: const Icon(Icons.auto_awesome_rounded),
                        );
                      },
                    ),
                    label: Text(strings.navAiProductDiscovery),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.mark_chat_read_outlined),
                    selectedIcon: const Icon(Icons.mark_chat_read_rounded),
                    label: Text(strings.customersMarketingNavTitle),
                  ),
                ],
              ),
            ),
            VerticalDivider(thickness: 1, width: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ],

          // Main View Content + Switch Point Persistent Footer
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _buildMainView(firestore, strings, isAr),
                ),
                const SwitchPointFooter(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isMobile
          ? NavigationBar(
              selectedIndex: _selectedIndex > 10 ? 0 : _selectedIndex,
              onDestinationSelected: _selectTab,
              backgroundColor: colorScheme.surfaceContainerLow,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.dashboard_outlined),
                  selectedIcon: const Icon(Icons.dashboard),
                  label: isAr ? 'الحملات' : 'Campaigns',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.bar_chart_outlined),
                  selectedIcon: const Icon(Icons.bar_chart),
                  label: isAr ? 'التقارير' : 'Reports',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.business_center_outlined),
                  selectedIcon: const Icon(Icons.business_center),
                  label: isAr ? 'الشركات' : 'Catalog',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.storefront_outlined),
                  selectedIcon: const Icon(Icons.storefront),
                  label: isAr ? 'السلاسل' : 'Chains',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.inventory_2_outlined),
                  selectedIcon: const Icon(Icons.inventory_2),
                  label: isAr ? 'المنتجات' : 'Products',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.receipt_long_outlined),
                  selectedIcon: const Icon(Icons.receipt_long),
                  label: isAr ? 'الفواتير' : 'Invoices',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.add_circle_outline),
                  selectedIcon: const Icon(Icons.add_circle),
                  label: isAr ? 'حملة جديدة' : 'New',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.card_giftcard_outlined),
                  selectedIcon: const Icon(Icons.card_giftcard),
                  label: isAr ? 'الهدايا' : 'Gifts',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.casino_outlined),
                  selectedIcon: const Icon(Icons.casino),
                  label: isAr ? 'الألعاب' : 'Games',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.speed_outlined),
                  selectedIcon: const Icon(Icons.speed),
                  label: isAr ? 'سرعة AI' : 'AI Speed',
                ),
              ],
            )
          : null,
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => _selectTab(6),
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              icon: const Icon(Icons.add_rounded),
              label: Text(strings.navCreateCampaign, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  /// High-Performance Lazy On-Demand Tab Viewport with in-memory caching (Pillar 1)
  Widget _buildMainView(FirebaseFirestore? firestore, AppStrings strings, bool isAr) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (int i = 0; i <= 12; i++)
          Offstage(
            offstage: _selectedIndex != i,
            child: TickerMode(
              enabled: _selectedIndex == i,
              child: _loadedTabs.contains(i)
                  ? RepaintBoundary(
                      child: _buildMainViewForIndex(i, firestore, strings, isAr),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }

  Widget _buildMainViewForIndex(int index, FirebaseFirestore? firestore, AppStrings strings, bool isAr) {
    switch (index) {
      case 0:
        return _buildCampaignsDashboard(firestore, strings, isAr);
      case 1:
        return CampaignReportsScreen(
          isEmbedded: true,
          initialEvent: _selectedReportsEvent,
          onBack: () => _selectTab(0),
        );
      case 2:
        return const CompanyCatalogScreen();
      case 3:
        return const RetailChainsScreen();
      case 4:
        return const ChainProductsIntelligenceScreen();
      case 5:
        return const InvoicesLogScreen();
      case 6:
        return CreateEventScreen(
          isEmbedded: true,
          onCancel: () => _selectTab(0),
          onSaved: () => _selectTab(0),
        );
      case 7:
        return const CompanyGiftsScreen();
      case 8:
        return const GameTypesScreen();
      case 9:
        return const AiSpeedBenchmarkScreen();
      case 10:
        return const AiBrainRulesScreen();
      case 11:
        return const AiProductDiscoveryScreen();
      case 12:
        return const CompanyCustomersMarketingScreen(isEmbedded: true);
      default:
        return _buildCampaignsDashboard(firestore, strings, isAr);
    }
  }

  // Fast & Instant Loading StreamBuilder + FutureBuilder Fallback for Campaigns
  Widget _buildCampaignsDashboard(FirebaseFirestore? firestore, AppStrings strings, bool isAr) {
    Stream<QuerySnapshot>? eventsStream;
    try {
      if (firestore != null) {
        eventsStream = firestore.collection('events').snapshots();
      }
    } catch (_) {}

    return StreamBuilder<QuerySnapshot>(
      stream: eventsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text('${strings.error}: ${snapshot.error}'),
                ],
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          Future<QuerySnapshot>? futureGet;
          try {
            if (firestore != null) {
              futureGet = firestore.collection('events').get();
            }
          } catch (_) {}

          return FutureBuilder<QuerySnapshot>(
            future: futureGet,
            builder: (context, futureSnapshot) {
              if (futureSnapshot.connectionState == ConnectionState.waiting && !futureSnapshot.hasData) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                      const SizedBox(height: 12),
                      Text(strings.loading, style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              }
              final rawDocs = futureSnapshot.data?.docs ?? [];
              return _buildCampaignsList(rawDocs, firestore, strings, isAr);
            },
          );
        }

        final rawDocs = snapshot.data?.docs ?? [];
        return _buildCampaignsList(rawDocs, firestore, strings, isAr);
      },
    );
  }

  Widget _buildCampaignsList(List<QueryDocumentSnapshot> rawDocs, FirebaseFirestore? firestore, AppStrings strings, bool isAr) {
    final activeCountry = ref.watch(activeCountryProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final allDocs = List<QueryDocumentSnapshot>.from(rawDocs)
      ..sort((a, b) {
        final dataA = a.data() as Map<String, dynamic>;
        final dataB = b.data() as Map<String, dynamic>;
        final tsA = dataA['createdAt'] as Timestamp?;
        final tsB = dataB['createdAt'] as Timestamp?;
        if (tsA == null) return 1;
        if (tsB == null) return -1;
        return tsB.compareTo(tsA);
      });

    final allEvents = allDocs.map((d) => EventModel.fromFirestore(d)).toList();
    final totalCampaigns = allEvents.length;
    final activeCount = allEvents.where((e) => e.isActive && !e.isExpired && !e.isNotStartedYet).length;
    final expiredOrDisabledCount = allEvents.where((e) => !e.isActive || e.isExpired).length;
    final partnerCompaniesCount = allEvents.map((e) => e.companySlug).toSet().length;

    // Filter events by selected filter tab and search text
    final searchQuery = _searchController.text.trim().toLowerCase();
    final filteredEvents = allEvents.where((event) {
      if (_campaignFilter == 'ACTIVE') {
        if (!event.isActive || event.isExpired) return false;
      } else if (_campaignFilter == 'INACTIVE') {
        if (event.isActive && !event.isExpired) return false;
      }

      if (searchQuery.isNotEmpty) {
        final nameMatch = event.eventName.toLowerCase().contains(searchQuery);
        final companyMatch = event.targetCompany.toLowerCase().contains(searchQuery);
        final slugMatch = event.companySlug.toLowerCase().contains(searchQuery);
        final storeMatch = event.retailChainName.toLowerCase().contains(searchQuery);
        if (!nameMatch && !companyMatch && !slugMatch && !storeMatch) return false;
      }

      return true;
    }).toList();

    if (totalCampaigns == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.campaign_rounded, size: 56, color: colorScheme.primary),
                ),
                const SizedBox(height: 20),
                Text(
                  strings.noEventsFound,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(fontSize: 19, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                ),
                const SizedBox(height: 8),
                Text(
                  isAr ? 'لم يتم العثور على حملات ترويجية مسجلة. ابدأ بإنشاء حملتك الترويجية الأولى وتحديد الشروط.' : 'No promotional campaigns registered yet. Start by creating your first campaign with tailored rules.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(fontSize: 13, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    setState(() => _selectedIndex = 6);
                  },
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text(strings.navCreateCampaign, style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Dashboard Metrics Banner (M3 Single-Seed Design)
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 800;
              final isMedium = constraints.maxWidth > 500 && constraints.maxWidth <= 800;
              final cardWidth = isWide 
                  ? (constraints.maxWidth - 48) / 4 
                  : isMedium 
                      ? (constraints.maxWidth - 16) / 2 
                      : constraints.maxWidth;

              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildMetricCard(
                    context: context,
                    title: strings.totalActiveEvents,
                    subtitle: isAr ? 'إجمالي الحملات المسجلة' : 'All Registered Campaigns',
                    value: '$totalCampaigns',
                    icon: Icons.campaign_rounded,
                    color: colorScheme.primary,
                    width: cardWidth,
                    tooltip: isAr ? 'إجمالي عدد الحملات والفعاليات في النظام' : 'Total number of campaigns in system',
                  ),
                  _buildMetricCard(
                    context: context,
                    title: strings.activeStatus,
                    subtitle: isAr ? 'حملات جارية وسارية الآن' : 'Live & Running Campaigns',
                    value: '$activeCount',
                    icon: Icons.check_circle_rounded,
                    color: Colors.green.shade600,
                    width: cardWidth,
                    hasPulse: true,
                    tooltip: isAr ? 'الحملات النشطة التي تستقبل فواتير العملاء حالياً' : 'Campaigns currently active and accepting receipts',
                  ),
                  _buildMetricCard(
                    context: context,
                    title: strings.totalCompaniesRegistered,
                    subtitle: isAr ? 'الشركات الراعية للحملات' : 'Partner Sponsor Companies',
                    value: '$partnerCompaniesCount',
                    icon: Icons.apartment_rounded,
                    color: colorScheme.tertiary,
                    width: cardWidth,
                    tooltip: isAr ? 'عدد الشركات المسجلة التي لها حملات ترويجية' : 'Total partner companies with campaigns',
                  ),
                  _buildMetricCard(
                    context: context,
                    title: isAr ? 'المتوقفة والمنتهية' : 'Inactive / Expired',
                    subtitle: isAr ? 'حملات تم إيقافها أو انتهت' : 'Disabled or ended campaigns',
                    value: '$expiredOrDisabledCount',
                    icon: Icons.pause_circle_outline_rounded,
                    color: Colors.amber.shade700,
                    width: cardWidth,
                    tooltip: isAr ? 'حملات متوقفة مؤقتاً أو انتهت صلاحيتها الزمنية' : 'Paused or expired campaigns',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),

          // 2. Filter Tabs & Search Controls (M3 Button Group Standard)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flex(
                  direction: MediaQuery.of(context).size.width < 700 ? Axis.vertical : Axis.horizontal,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: MediaQuery.of(context).size.width < 700 ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
                  children: [
                    // Segmented Button Group
                    M3ConnectedButtonGroup<String>(
                      segments: [
                        M3ButtonSegment<String>(
                          value: 'ALL',
                          label: isAr ? 'جميع الحملات' : 'All Campaigns',
                          icon: Icons.apps_rounded,
                          badgeText: '$totalCampaigns',
                          tooltip: isAr ? 'عرض جميع الحملات المسجلة بدون استثناء' : 'Show all registered campaigns',
                        ),
                        M3ButtonSegment<String>(
                          value: 'ACTIVE',
                          label: isAr ? 'النشطة والسارية' : 'Active',
                          icon: Icons.check_circle_rounded,
                          badgeText: '$activeCount',
                          tooltip: isAr ? 'تصفية الحملات الجارية والنشطة فقط' : 'Filter by active and running campaigns',
                        ),
                        M3ButtonSegment<String>(
                          value: 'INACTIVE',
                          label: isAr ? 'المتوقفة والمنتهية' : 'Inactive',
                          icon: Icons.pause_circle_rounded,
                          badgeText: '$expiredOrDisabledCount',
                          tooltip: isAr ? 'تصفية الحملات المتوقفة أو منتهية الصلاحية' : 'Filter by paused or expired campaigns',
                        ),
                      ],
                      selectedValue: _campaignFilter,
                      onSelected: (val) {
                        setState(() => _campaignFilter = val);
                      },
                    ),
                    if (MediaQuery.of(context).size.width < 700) const SizedBox(height: 12),

                    // Search input
                    SizedBox(
                      width: MediaQuery.of(context).size.width < 700 ? double.infinity : 280,
                      child: TextField(
                        controller: _searchController,
                        style: GoogleFonts.cairo(fontSize: 13),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: isAr ? 'بحث باسم الحملة أو الشركة...' : 'Search campaigns or companies...',
                          hintStyle: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          prefixIcon: Icon(Icons.search_rounded, size: 20, color: colorScheme.primary),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 3. Section Title with Count Indicator
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.view_list_rounded, size: 18, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 10),
              Text(
                '${strings.eventsTitle} (${filteredEvents.length}):',
                style: GoogleFonts.cairo(fontSize: 17, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
              ),
              const Spacer(),
              if (filteredEvents.length != allEvents.length)
                Text(
                  isAr ? 'تمت تصفية ${filteredEvents.length} من أصل $totalCampaigns' : 'Showing ${filteredEvents.length} of $totalCampaigns',
                  style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // 4. Campaigns List (M3 Cards)
          if (filteredEvents.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0),
                child: Column(
                  children: [
                    Icon(Icons.filter_alt_off_rounded, size: 48, color: colorScheme.outline),
                    const SizedBox(height: 12),
                    Text(
                      isAr ? 'لا توجد حملات تطابق معايير البحث أو التصفية الحالية.' : 'No campaigns match the current search or filter criteria.',
                      style: GoogleFonts.cairo(fontSize: 14, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredEvents.length,
              itemBuilder: (context, index) {
                final event = filteredEvents[index];
                return _buildCampaignCard(context, event, firestore, activeCountry, strings, isAr, colorScheme);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
    required Color color,
    required double width,
    required String tooltip,
    bool hasPulse = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                if (hasPulse)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'LIVE',
                          style: GoogleFonts.cairo(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: GoogleFonts.cairo(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: colorScheme.onSurface,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: GoogleFonts.cairo(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.cairo(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCampaignCard(
    BuildContext context,
    EventModel event,
    FirebaseFirestore? firestore,
    CountryCurrency activeCountry,
    AppStrings strings,
    bool isAr,
    ColorScheme colorScheme,
  ) {
    final companySlug = event.companySlug.isNotEmpty ? event.companySlug : event.targetCompany.toLowerCase();

    // Determine status badge
    Color statusBg;
    Color statusBorder;
    Color statusTextColor;
    IconData statusIcon;
    String statusLabel;

    if (!event.isActive) {
      statusBg = colorScheme.surfaceContainerHighest;
      statusBorder = colorScheme.outlineVariant;
      statusTextColor = colorScheme.onSurfaceVariant;
      statusIcon = Icons.pause_circle_outline_rounded;
      statusLabel = isAr ? 'معطلة' : 'Disabled';
    } else if (event.isExpired) {
      statusBg = Colors.red.shade50;
      statusBorder = Colors.red.shade200;
      statusTextColor = Colors.red.shade800;
      statusIcon = Icons.event_busy_rounded;
      statusLabel = isAr ? 'منتهية' : 'Expired';
    } else if (event.isNotStartedYet) {
      statusBg = Colors.amber.shade50;
      statusBorder = Colors.amber.shade200;
      statusTextColor = Colors.amber.shade900;
      statusIcon = Icons.schedule_rounded;
      statusLabel = isAr ? 'لم تبدأ بعد' : 'Upcoming';
    } else {
      statusBg = Colors.green.shade50;
      statusBorder = Colors.green.shade200;
      statusTextColor = Colors.green.shade800;
      statusIcon = Icons.check_circle_rounded;
      statusLabel = isAr ? 'نشطة وسارية' : 'Active & Running';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Campaign Title, Status Badge, and Quick Switch Toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      Text(
                        event.eventName,
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: colorScheme.primary,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: statusBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, size: 14, color: statusTextColor),
                            const SizedBox(width: 4),
                            Text(
                              statusLabel,
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: statusTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isAr ? 'الحالة: ' : 'Status: ',
                      style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                    ),
                    Tooltip(
                      message: event.isActive
                          ? (isAr ? 'الحملة مفعلة حالياً - اضغط لإيقافها مؤقتاً' : 'Campaign is active - tap to pause')
                          : (isAr ? 'الحملة متوقفة - اضغط لتفعيلها فورياً' : 'Campaign is paused - tap to activate'),
                      waitDuration: const Duration(milliseconds: 400),
                      child: Switch(
                        value: event.isActive,
                        onChanged: (value) async {
                          if (firestore != null) {
                            await firestore.collection('events').doc(event.id).update({'isActive': value});
                          }
                          if (event.companySlug.isNotEmpty) {
                            await ref.read(companyGiftsServiceProvider).syncCompanyGiftsAvailableQuantities(event.companySlug);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Metadata Chips (Company, Retail Chain, Min Spend, Date Range)
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _buildMetadataPill(
                  icon: Icons.apartment_rounded,
                  label: '${isAr ? "الشركة الراعية: " : "Company: "}${event.targetCompany}',
                  colorScheme: colorScheme,
                  tooltip: isAr ? 'الشركة المصنعة وصاحبة الحملة' : 'Sponsor brand company',
                ),
                if (event.retailChainName.isNotEmpty)
                  _buildMetadataPill(
                    icon: Icons.storefront_rounded,
                    label: event.branchesDisplaySummary,
                    colorScheme: colorScheme,
                    customBg: Colors.amber.shade50,
                    customBorder: Colors.amber.shade200,
                    customColor: Colors.amber.shade900,
                    tooltip: isAr ? 'السلسلة والفروع المحددة لسريان العرض' : 'Eligible retail chain & branch',
                  ),
                _buildMetadataPill(
                  icon: Icons.key_rounded,
                  label: '${isAr ? "كود الرابط: " : "Slug: "}$companySlug',
                  colorScheme: colorScheme,
                  tooltip: isAr ? 'المعرف الفريد لرابط الحملة' : 'Unique URL slug identifier',
                ),
                _buildMetadataPill(
                  icon: Icons.payments_rounded,
                  label: event.minimumSpend > 0
                      ? '${isAr ? "الحد الأدنى: " : "Min Spend: "}${event.minimumSpend == event.minimumSpend.roundToDouble() ? event.minimumSpend.toInt() : event.minimumSpend} ${activeCountry.currencySymbol}'
                      : (isAr ? 'بدون حد أدنى' : 'No Min Spend'),
                  colorScheme: colorScheme,
                  customBg: Colors.teal.shade50,
                  customBorder: Colors.teal.shade200,
                  customColor: Colors.teal.shade900,
                  tooltip: isAr ? 'قيمة المشتريات المطلوبة لقبول الفاتورة' : 'Minimum purchase threshold for receipt acceptance',
                ),
                if (event.startDate != null || event.endDate != null)
                  _buildMetadataPill(
                    icon: Icons.calendar_month_rounded,
                    label: '${isAr ? "الفترة: " : "Period: "}${event.startDate != null ? "${event.startDate!.day}/${event.startDate!.month}/${event.startDate!.year}" : (isAr ? "مفتوح" : "Open")} ${isAr ? "إلى" : "to"} ${event.endDate != null ? "${event.endDate!.day}/${event.endDate!.month}/${event.endDate!.year}" : (isAr ? "مفتوح" : "Open")}',
                    colorScheme: colorScheme,
                    tooltip: isAr ? 'تاريخ بداية ونهاية سريان الحملة' : 'Campaign validity date range',
                  ),
                if (event.requiredProducts.isNotEmpty)
                  _buildMetadataPill(
                    icon: Icons.inventory_2_rounded,
                    label: '${isAr ? "الأصناف المستهدفة: " : "Target Items: "}${event.requiredProducts.length} ${isAr ? "صنفاً" : "items"}',
                    colorScheme: colorScheme,
                    customBg: Colors.indigo.shade50,
                    customBorder: Colors.indigo.shade200,
                    customColor: Colors.indigo.shade900,
                    tooltip: isAr
                        ? 'الأصناف المستهدفة (${event.requiredProducts.length} صنف):\n${event.requiredProducts.join(" • ")}'
                        : 'Target Products (${event.requiredProducts.length} items):\n${event.requiredProducts.join(" • ")}',
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // AI Prompt Guidelines (Smart Tonal Container)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isAr ? 'البرومبت المخصص للذكاء الاصطناعي (Gemini Vision AI Prompt):' : 'Custom Gemini AI Verification Prompt:',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: colorScheme.primary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: isAr ? 'نسخ نص برومبت الذكاء الاصطناعي للحافظة' : 'Copy AI prompt text',
                        child: InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: event.customPrompt));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(isAr ? 'تم نسخ البرومبت بنجاح!' : 'AI Prompt copied to clipboard!'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Row(
                              children: [
                                Icon(Icons.copy_rounded, size: 13, color: colorScheme.primary),
                                const SizedBox(width: 4),
                                Text(
                                  isAr ? 'نسخ البرومبت' : 'Copy',
                                  style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    event.customPrompt.isNotEmpty ? event.customPrompt : (isAr ? 'يستخدم البرومبت الافتراضي الذكي للنظام' : 'Using smart system default prompt'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurface),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Granular Portal Access Toggles & Live Controls (M3 Dual Control Strip)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tune_rounded, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        isAr ? 'التحكم في بوابات الوصول المباشرة (Portal Access Controls):' : 'Direct Portal Access Controls:',
                        style: GoogleFonts.cairo(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      // 1. Promoter & In-Store Portal Switch
                      _buildPortalControlTile(
                        context,
                        title: strings.promoterPortalLabel,
                        subtitle: isAr ? 'رابط رفع الفواتير والجوائز بالفرع' : 'In-Store Promoter & Receipts',
                        icon: Icons.qr_code_scanner_rounded,
                        isActive: event.isActive && event.isPromoterActive,
                        colorScheme: colorScheme,
                        isAr: isAr,
                        tooltip: event.isPromoterActive
                            ? strings.promoterPortalToggleTooltipActive
                            : strings.promoterPortalToggleTooltipPaused,
                        onChanged: (val) async {
                          if (firestore != null) {
                            await firestore.collection('events').doc(event.id).update({'isPromoterActive': val});
                          }
                        },
                      ),
                      // 2. Agency Operations Portal Switch
                      _buildPortalControlTile(
                        context,
                        title: strings.agencyOpsPortalLabel,
                        subtitle: isAr ? 'رابط العمليات والأرصدة والفواتير' : 'Agency Field Ops & Stock',
                        icon: Icons.store_mall_directory_rounded,
                        isActive: event.isActive && event.isAgencyActive,
                        colorScheme: colorScheme,
                        isAr: isAr,
                        tooltip: event.isAgencyActive
                            ? strings.agencyOpsPortalToggleTooltipActive
                            : strings.agencyOpsPortalToggleTooltipPaused,
                        onChanged: (val) async {
                          if (firestore != null) {
                            await firestore.collection('events').doc(event.id).update({'isAgencyActive': val});
                          }
                        },
                      ),
                      // 3. Brand Executive Master Portal Switch
                      _buildPortalControlTile(
                        context,
                        title: strings.brandExecutivePortalLabel,
                        subtitle: isAr ? 'رابط العلامة التجارية والـ ROI' : 'Brand Executive & ROI',
                        icon: Icons.business_center_rounded,
                        isActive: event.isActive && event.isManagerActive,
                        colorScheme: colorScheme,
                        isAr: isAr,
                        tooltip: event.isManagerActive
                            ? strings.managerPortalToggleTooltipActive
                            : strings.managerPortalToggleTooltipPaused,
                        onChanged: (val) async {
                          if (firestore != null) {
                            await firestore.collection('events').doc(event.id).update({'isManagerActive': val});
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Action Buttons (Material Design 3 Standard with Rich Tooltips)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                // 1. Internal Reports & Analytics View
                Tooltip(
                  message: isAr ? 'عرض تقارير وتحليلات الفواتير والمبيعات المحققة للحملة' : 'View invoices analytics & sales performance reports',
                  waitDuration: const Duration(milliseconds: 400),
                  child: FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedReportsEvent = event;
                        _selectedIndex = 1;
                      });
                    },
                    icon: const Icon(Icons.analytics_rounded, size: 18),
                    label: Text(strings.viewReports, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                // 2. Copy Promoter / Client Link
                Tooltip(
                  message: strings.promoterPortalTooltip,
                  waitDuration: const Duration(milliseconds: 400),
                  child: FilledButton.tonalIcon(
                    onPressed: () => _copyPromoterLink(context, companySlug, eventId: event.id),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: Text(strings.copyPromoterLink, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                // 3. Copy Agency Operations Link
                Tooltip(
                  message: strings.agencyOpsPortalTooltip,
                  waitDuration: const Duration(milliseconds: 400),
                  child: FilledButton.tonalIcon(
                    onPressed: () => _copyAgencyOpsLink(context, companySlug, eventId: event.id),
                    icon: const Icon(Icons.store_mall_directory_rounded, size: 18),
                    label: Text(strings.copyAgencyOpsLink, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.purple.shade50,
                      foregroundColor: Colors.purple.shade900,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                // 4. Copy Brand Executive Master Link
                Tooltip(
                  message: strings.brandExecutivePortalTooltip,
                  waitDuration: const Duration(milliseconds: 400),
                  child: FilledButton.tonalIcon(
                    onPressed: () => _copyBrandExecutiveLink(context, companySlug, eventId: event.id),
                    icon: const Icon(Icons.business_center_rounded, size: 18),
                    label: Text(strings.copyBrandExecutiveLink, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.secondaryContainer,
                      foregroundColor: colorScheme.onSecondaryContainer,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                // 5. Preview Agency Operations Portal
                Tooltip(
                  message: isAr ? 'معاينة بوابة شركة الدعاية والعمليات واستعراض الأرصدة والفواتير' : 'Live preview of Agency Operations Portal',
                  waitDuration: const Duration(milliseconds: 400),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => CompanyManagerPortalScreen(
                            companySlug: companySlug,
                            initialEventId: event.id,
                            isAgencyOpsMode: true,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.store_mall_directory_rounded, size: 18),
                    label: Text(strings.previewAgencyOpsPortal, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                // 6. Preview Brand Executive Master Portal
                Tooltip(
                  message: isAr
                      ? 'معاينة البوابة التنفيذية للعلامة التجارية واستعراض الـ ROI ومحاكاة البروموتر'
                      : 'Live preview of Brand Executive Master Portal',
                  waitDuration: const Duration(milliseconds: 400),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => CompanyManagerPortalScreen(
                            companySlug: companySlug,
                            initialEventId: event.id,
                            isAgencyOpsMode: false,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.dashboard_customize_rounded, size: 18),
                    label: Text(strings.previewBrandExecutivePortal, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                // 7. Preview Client / Promoter Mobile App
                Tooltip(
                  message: isAr ? 'معاينة تجربة العميل والبروموتر في رفع وفحص الفاتورة' : 'Live preview of client mobile web app',
                  waitDuration: const Duration(milliseconds: 400),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ClientReceiptUploadScreen(
                            event: event,
                            companySlug: companySlug,
                            initialEventId: event.id,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(strings.previewClientApp, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                // 6. Edit Campaign
                Tooltip(
                  message: isAr ? 'تعديل بيانات وشروط وبرومبت الفحص الذكي للحملة' : 'Edit campaign rules, target products & prompt',
                  waitDuration: const Duration(milliseconds: 400),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => CreateEventScreen(eventToEdit: event),
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: Text(isAr ? 'تعديل الحملة' : 'Edit Campaign', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                // 7. Voucher Cards & Reset Action
                Tooltip(
                  message: isAr
                      ? 'استعلام أرقام كروت الفواتشرات المسلمة، والبحث برقم الكارت، وإعادة التعيين'
                      : 'Audit claimed voucher serials & reset registry for reuse',
                  waitDuration: const Duration(milliseconds: 400),
                  child: OutlinedButton.icon(
                    onPressed: () => VoucherSerialsManagementDialog.show(context, event),
                    icon: Icon(Icons.confirmation_number_rounded, size: 18, color: Colors.amber.shade900),
                    label: Text(
                      isAr ? 'سجل وإعادة تعيين الفواتشرات' : 'Vouchers & Reset',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.amber.shade900,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.amber.shade50,
                      side: BorderSide(color: Colors.amber.shade300),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                // 7. Delete Campaign
                Tooltip(
                  message: strings.deleteCampaignTooltip,
                  waitDuration: const Duration(milliseconds: 400),
                  child: OutlinedButton.icon(
                    onPressed: () => _showDeleteCampaignDialog(context, event, strings, firestore),
                    icon: Icon(Icons.delete_forever_rounded, size: 18, color: colorScheme.error),
                    label: Text(
                      strings.deleteCampaignBtn,
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: colorScheme.error,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataPill({
    required IconData icon,
    required String label,
    required ColorScheme colorScheme,
    required String tooltip,
    Color? customBg,
    Color? customBorder,
    Color? customColor,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: customBg ?? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: customBorder ?? colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: customColor ?? colorScheme.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: customColor ?? colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortalControlTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isActive,
    required ColorScheme colorScheme,
    required bool isAr,
    required String tooltip,
    required ValueChanged<bool> onChanged,
  }) {
    final statusColor = isActive ? Colors.green.shade700 : Colors.amber.shade900;
    final statusBg = isActive ? Colors.green.shade50 : Colors.amber.shade50;
    final statusBorder = isActive ? Colors.green.shade200 : Colors.amber.shade300;
    final statusText = isActive ? (isAr ? 'مفعلة 🟢' : 'Active 🟢') : (isAr ? 'متوقفة ⏸️' : 'Paused ⏸️');

    return Container(
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 340),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? colorScheme.outlineVariant.withValues(alpha: 0.6) : Colors.amber.shade300,
          width: isActive ? 1 : 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isActive ? colorScheme.primaryContainer : Colors.amber.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: isActive ? colorScheme.onPrimaryContainer : Colors.amber.shade900,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusBorder),
                  ),
                  child: Text(
                    statusText,
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: tooltip,
            waitDuration: const Duration(milliseconds: 300),
            child: Transform.scale(
              scale: 0.85,
              child: Switch(
                value: isActive,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
