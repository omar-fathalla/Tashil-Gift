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
import '../../../core/widgets/m3_action_menu.dart';
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
import '../../../core/services/partner_portal_auth_service.dart';
import 'widgets/voucher_serials_management_dialog.dart';
import 'widgets/portal_credentials_dialog.dart';
import '../../../core/services/company_gifts_service.dart';
import '../../../core/utils/url_builder.dart';
import '../../../core/utils/receipt_date_window.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/theme/m3_shape_tokens.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  int _selectedIndex = 0;
  final Set<int> _loadedTabs = {0};
  String _campaignFilter = 'ACTIVE';
  EventModel? _selectedReportsEvent;
  final _searchController = TextEditingController();
  Stream<int>? _pendingDiscoveryCountStream;
  Stream<QuerySnapshot>? _eventsStream;
  Future<QuerySnapshot>? _eventsFuture;

  Stream<int> _getPendingDiscoveryCountStream() {
    return _pendingDiscoveryCountStream ??=
        ref.read(aiProductDiscoveryServiceProvider).streamPendingCount();
  }

  Stream<QuerySnapshot>? _getEventsStream(FirebaseFirestore? firestore) {
    if (firestore == null) return null;
    try {
      return _eventsStream ??= firestore.collection('events').snapshots();
    } catch (_) {
      return null;
    }
  }

  Future<QuerySnapshot>? _getEventsFuture(FirebaseFirestore? firestore) {
    if (firestore == null) return null;
    try {
      return _eventsFuture ??= firestore.collection('events').get();
    } catch (_) {
      return null;
    }
  }

  void _selectTab(int index) {
    if (_selectedIndex != index) {
      setState(() {
        _selectedIndex = index;
        _loadedTabs.add(index);
      });
    }
  }

  Future<void> _openCreateEventScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const CreateEventScreen()),
    );
    if (mounted) setState(() {});
  }

  void _showMobileMoreSheet(BuildContext context, AppStrings strings, bool isAr) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        final items = [
          (3, Icons.storefront_rounded, strings.navRetailChains),
          (4, Icons.inventory_2_rounded, strings.navProductsIntelligence),
          (6, Icons.card_giftcard_rounded, strings.navCompanyGifts),
          (7, Icons.casino_rounded, strings.navGameTypes),
          (8, Icons.speed_rounded, strings.navAiSpeedBenchmark),
          (9, Icons.psychology_rounded, strings.navAiBrainRules),
          (10, Icons.auto_awesome_rounded, strings.navAiProductDiscovery),
          (11, Icons.mark_chat_read_rounded, strings.navWhatsAppMarketing),
        ];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      ...items.map((item) {
                        final (idx, icon, title) = item;
                        final isSelected = _selectedIndex == idx;
                        return ListTile(
                          leading: Icon(icon, color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant),
                          title: Text(
                            title,
                            style: GoogleFonts.cairo(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                            ),
                          ),
                          selected: isSelected,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onTap: () {
                            Navigator.pop(ctx);
                            _selectTab(idx);
                          },
                        );
                      }),
                      Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ListTile(
                        leading: Icon(Icons.logout_rounded, color: colorScheme.error),
                        title: Text(
                          strings.signOutBtn,
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.error,
                          ),
                        ),
                        subtitle: Text(
                          strings.systemAdminRole,
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onTap: () {
                          Navigator.pop(ctx);
                          _handleSignOut(context, strings);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
    final isAr = ref.isArabic;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isAr
              ? 'تم نسخ رابط العميل والبروموتر الموحد للشركة ($slug): $url'
              : '${strings.promoterLinkCopied}: $url',
        ),
        backgroundColor: colorScheme.onTertiaryFixedVariant,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _copyAgencyOpsLink(
    BuildContext context,
    String slug, {
    String? eventId,
    EventModel? event,
  }) async {
    final isAr = ref.isArabic;
    final firestore = ref.read(firestoreProvider);
    final service = PartnerPortalAuthService(firestore: firestore);
    final effectiveEventId = event?.hasCustomAgencyCredentials == true ? event?.id : eventId;
    final creds = await service.resolveCredentials(
      companySlug: slug,
      companyNameHint: event?.targetCompany,
      eventId: effectiveEventId,
    );
    final url = AppUrlBuilder.buildAgencyOpsUrl(slug, eventId: effectiveEventId);
    final card = PartnerPortalAuthService.buildWhatsAppLoginCard(
      role: PartnerPortalRole.agencyOps,
      companyName: event != null && event.targetCompany.isNotEmpty ? event.targetCompany : creds.companyName,
      portalUrl: url,
      username: creds.effectiveAgencyUsername,
      password: creds.effectiveAgencyPassword,
      isAr: isAr,
      campaignName: event?.hasCustomAgencyCredentials == true ? event?.eventName : null,
      isCustomCampaignTier: creds.hasCustomAgencyCredentials,
    );
    await Clipboard.setData(ClipboardData(text: card));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isAr
              ? 'تم نسخ كارت دخول بوابة العمليات للواتساب (الرابط + اسم المستخدم + كلمة المرور)'
              : 'Copied Agency Operations WhatsApp Login Card (URL + Username + Password)',
        ),
        backgroundColor: colorScheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _copyBrandExecutiveLink(
    BuildContext context,
    String slug, {
    String? eventId,
    EventModel? event,
  }) async {
    final isAr = ref.isArabic;
    final firestore = ref.read(firestoreProvider);
    final service = PartnerPortalAuthService(firestore: firestore);
    final creds = await service.resolveCredentials(
      companySlug: slug,
      companyNameHint: event?.targetCompany,
    );
    final url = AppUrlBuilder.buildBrandExecutiveUrl(slug, eventId: eventId);
    final card = PartnerPortalAuthService.buildWhatsAppLoginCard(
      role: PartnerPortalRole.brandManager,
      companyName: event != null && event.targetCompany.isNotEmpty ? event.targetCompany : creds.companyName,
      portalUrl: url,
      username: creds.brandManagerUsername,
      password: creds.brandManagerPassword,
      isAr: isAr,
    );
    await Clipboard.setData(ClipboardData(text: card));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isAr
              ? 'تم نسخ كارت دخول البوابة التنفيذية للشركة للواتساب (الرابط + اسم المستخدم + كلمة المرور)'
              : 'Copied Brand Executive WhatsApp Login Card (URL + Username + Password)',
        ),
        backgroundColor: colorScheme.primary,
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
              backgroundColor: colorScheme.onErrorContainer,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppStrings.of(ref).operationFailed(e.toString())),
              backgroundColor: colorScheme.onErrorContainer,
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

  Widget _buildSideMenuProfileButton(
    BuildContext context,
    ColorScheme colorScheme,
    AppStrings strings,
  ) {
    String sessionEmail = kPrimaryAdminEmail;
    try {
      sessionEmail = ref.watch(adminSessionEmailProvider) ??
          ref.read(firebaseServiceProvider).currentUser?.email ??
          kPrimaryAdminEmail;
    } catch (_) {}

    return M3ActionMenu(
      tooltip: strings.adminProfileTooltip,
      anchorBuilder: (context, controller, child) {
        return Tooltip(
          message: '${strings.systemAdminRole}\n$sessionEmail',
          child: InkWell(
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 68,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: colorScheme.primary,
                    child: const Icon(
                      Icons.person_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    strings.systemAdminRole,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      children: [
        // 1. Profile Info Header Card
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
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
              Column(
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: colorScheme.tertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        strings.activeSessionLabel,
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onTertiaryFixedVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        M3ActionMenu.divider(),
        // 2. Sign Out Action
        M3ActionMenu.item(
          context: context,
          label: strings.signOutBtn,
          icon: Icons.logout_rounded,
          isDestructive: true,
          onPressed: () => _handleSignOut(context, strings),
        ),
      ],
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
    final layout = M3Layout.of(context);
    final isMobile = layout.isCompact;
    final strings = AppStrings.of(ref);
    final isAr = ref.isArabic;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: const SwitchPointHeader(
        subtitle: 'System Admin and Company Manager Portal',
      ),
      body: Row(
        children: [
          if (!isMobile) ...[
            // Sidebar Navigation (Desktop/Tablet) wrapped in RepaintBoundary for 60 FPS (Rule 9 / Pillar 2)
            RepaintBoundary(
              child: SizedBox(
                width: 80,
                child: Container(
                  color: colorScheme.surfaceContainerLow,
                  child: Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, railConstraints) {
                            return SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: railConstraints.maxHeight,
                                ),
                                child: IntrinsicHeight(
                                  child: NavigationRail(
                                    selectedIndex: _selectedIndex,
                                    onDestinationSelected: _selectTab,
                                    labelType: NavigationRailLabelType.all,
                                    minWidth: 80,
                                    backgroundColor: Colors.transparent,
                                    indicatorColor: colorScheme.secondaryContainer,
                                    selectedIconTheme: IconThemeData(color: colorScheme.onSecondaryContainer, size: 24),
                                    unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant, size: 24),
                                    selectedLabelTextStyle: GoogleFonts.cairo(
                                      color: colorScheme.onSurface,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      height: 1.33,
                                    ),
                                    unselectedLabelTextStyle: GoogleFonts.cairo(
                                      color: colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                      height: 1.33,
                                    ),
                                    destinations: [
                                      NavigationRailDestination(
                                        icon: const Icon(Icons.campaign_outlined),
                                        selectedIcon: const Icon(Icons.campaign_rounded),
                                        label: Text(strings.navEventsManagement, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ),
                                      NavigationRailDestination(
                                        icon: const Icon(Icons.bar_chart_outlined),
                                        selectedIcon: const Icon(Icons.bar_chart_rounded),
                                        label: Text(strings.navAnalytics, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ),
                                      NavigationRailDestination(
                                        icon: const Icon(Icons.business_center_outlined),
                                        selectedIcon: const Icon(Icons.business_center_rounded),
                                        label: Text(strings.navCompanyCatalog, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ),
                                      NavigationRailDestination(
                                        icon: const Icon(Icons.storefront_outlined),
                                        selectedIcon: const Icon(Icons.storefront_rounded),
                                        label: Text(strings.navRetailChains, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ),
                                      NavigationRailDestination(
                                        icon: const Icon(Icons.inventory_2_outlined),
                                        selectedIcon: const Icon(Icons.inventory_2_rounded),
                                        label: Text(strings.navProductsIntelligence, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ),
                                      NavigationRailDestination(
                                        icon: const Icon(Icons.receipt_long_outlined),
                                        selectedIcon: const Icon(Icons.receipt_long_rounded),
                                        label: Text(strings.navInvoicesAudit, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ),
                                      NavigationRailDestination(
                                        icon: const Icon(Icons.card_giftcard_outlined),
                                        selectedIcon: const Icon(Icons.card_giftcard_rounded),
                                        label: Text(strings.navCompanyGifts, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ),
                                      NavigationRailDestination(
                                        icon: const Icon(Icons.casino_outlined),
                                        selectedIcon: const Icon(Icons.casino_rounded),
                                        label: Text(strings.navGameTypes, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ),
                                      NavigationRailDestination(
                                        icon: const Icon(Icons.speed_outlined),
                                        selectedIcon: const Icon(Icons.speed_rounded),
                                        label: Text(strings.navAiSpeedBenchmark, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ),
                                      NavigationRailDestination(
                                        icon: const Icon(Icons.psychology_outlined),
                                        selectedIcon: const Icon(Icons.psychology_rounded),
                                        label: Text(strings.navAiBrainRules, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ),
                                      NavigationRailDestination(
                                        icon: StreamBuilder<int>(
                                          stream: _getPendingDiscoveryCountStream(),
                                          builder: (context, snapshot) {
                                            final count = snapshot.data ?? 0;
                                            return Badge(
                                              isLabelVisible: count > 0,
                                              label: Text('$count'),
                                              backgroundColor: colorScheme.tertiary,
                                              textColor: colorScheme.onTertiary,
                                              child: const Icon(Icons.auto_awesome_outlined),
                                            );
                                          },
                                        ),
                                        selectedIcon: StreamBuilder<int>(
                                          stream: _getPendingDiscoveryCountStream(),
                                          builder: (context, snapshot) {
                                            final count = snapshot.data ?? 0;
                                            return Badge(
                                              isLabelVisible: count > 0,
                                              label: Text('$count'),
                                              backgroundColor: colorScheme.tertiary,
                                              textColor: colorScheme.onTertiary,
                                              child: const Icon(Icons.auto_awesome_rounded),
                                            );
                                          },
                                        ),
                                        label: Text(strings.navAiProductDiscovery, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ),
                                      NavigationRailDestination(
                                        icon: const Icon(Icons.mark_chat_read_outlined),
                                        selectedIcon: const Icon(Icons.mark_chat_read_rounded),
                                        label: Text(strings.navWhatsAppMarketing, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: _buildSideMenuProfileButton(context, colorScheme, strings),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            VerticalDivider(thickness: 1, width: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ],

          // Main View Content
          Expanded(
            child: M3ContentBoundary(
              maxWidth: 1440.0,
              padding: EdgeInsets.zero,
              child: _buildMainView(firestore, strings, isAr),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isMobile
          ? NavigationBar(
              selectedIndex: _selectedIndex.clamp(0, 4),
              onDestinationSelected: (idx) {
                if (idx < 4) {
                  _selectTab(idx);
                } else {
                  _showMobileMoreSheet(context, strings, isAr);
                }
              },
              backgroundColor: colorScheme.surfaceContainerLow,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.campaign_outlined),
                  selectedIcon: const Icon(Icons.campaign_rounded),
                  label: strings.navEventsManagement,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.bar_chart_outlined),
                  selectedIcon: const Icon(Icons.bar_chart_rounded),
                  label: strings.navAnalytics,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.business_center_outlined),
                  selectedIcon: const Icon(Icons.business_center_rounded),
                  label: strings.navCompanyCatalog,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.receipt_long_outlined),
                  selectedIcon: const Icon(Icons.receipt_long_rounded),
                  label: strings.navInvoicesAudit,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.more_horiz_rounded),
                  selectedIcon: const Icon(Icons.more_horiz_rounded),
                  label: isAr ? 'المزيد' : 'More',
                ),
              ],
            )
          : null,
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              onPressed: _openCreateEventScreen,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                isAr ? 'إنشاء حملة' : 'New Campaign',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }

  /// High-Performance Lazy On-Demand Tab Viewport with in-memory caching (Pillar 1)
  Widget _buildMainView(FirebaseFirestore? firestore, AppStrings strings, bool isAr) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (int i = 0; i <= 11; i++)
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
        return const CompanyGiftsScreen();
      case 7:
        return const GameTypesScreen();
      case 8:
        return const AiSpeedBenchmarkScreen();
      case 9:
        return const AiBrainRulesScreen();
      case 10:
        return const AiProductDiscoveryScreen();
      case 11:
        return const CompanyCustomersMarketingScreen(isEmbedded: true);
      default:
        return _buildCampaignsDashboard(firestore, strings, isAr);
    }
  }

  // Fast & Instant Loading StreamBuilder + FutureBuilder Fallback for Campaigns
  Widget _buildCampaignsDashboard(FirebaseFirestore? firestore, AppStrings strings, bool isAr) {
    final eventsStream = _getEventsStream(firestore);

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
                  Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                  const SizedBox(height: 12),
                  Text('${strings.error}: ${snapshot.error}'),
                ],
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          final futureGet = _getEventsFuture(firestore);

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
                      Text(strings.loading, style: TextStyle(color: colorScheme.outline)),
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
                  onPressed: _openCreateEventScreen,
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

    final isCompactPage = MediaQuery.sizeOf(context).width < 600;
    final textTheme = theme.textTheme;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isCompactPage ? M3Spacing.sm : M3Spacing.md,
        isCompactPage ? M3Spacing.sm : M3Spacing.md,
        isCompactPage ? M3Spacing.sm : M3Spacing.md,
        96, // keep last card clear of the extended FAB
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 0. M3 page header (headline + supporting text)
          Text(
            isAr ? 'إدارة الحملات' : 'Campaigns',
            style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: M3Spacing.xxs),
          Text(
            isAr ? 'نظرة عامة على كل الحملات والشركات الراعية' : 'Overview of all campaigns and sponsor companies',
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: M3Spacing.md),
          // 1. Dashboard Metrics Banner (M3 Single-Seed Design)
          LayoutBuilder(
            builder: (context, constraints) {
              final layout = M3Layout.fromConstraints(constraints);
              final cardWidth = layout.isDesktop
                  ? (constraints.maxWidth - (3 * M3Spacing.sm)) / 4 
                  : (layout.isMedium || constraints.maxWidth >= 420)
                      ? (constraints.maxWidth - M3Spacing.sm) / 2
                      : (constraints.maxWidth - M3Spacing.sm) / 2; // compact: 2-up grid

              return Wrap(
                spacing: M3Spacing.sm,
                runSpacing: M3Spacing.sm,
                children: [
                  _buildMetricCard(
                    context: context,
                    title: strings.totalActiveEvents,
                    subtitle: isAr ? 'إجمالي الحملات المسجلة' : 'All Registered Campaigns',
                    value: '$totalCampaigns',
                    icon: Icons.campaign_rounded,
                    color: colorScheme.primary,
                    width: cardWidth,
                    tooltip: isAr ? 'إجمالي عدد الحملات والفعاليات في النظام (انقر للتصفية)' : 'Total number of campaigns in system (click to filter)',
                    isSelected: _campaignFilter == 'ALL',
                    onTap: () => setState(() => _campaignFilter = 'ALL'),
                  ),
                  _buildMetricCard(
                    context: context,
                    title: strings.activeStatus,
                    subtitle: isAr ? 'حملات جارية وسارية الآن' : 'Live & Running Campaigns',
                    value: '$activeCount',
                    icon: Icons.check_circle_rounded,
                    color: colorScheme.tertiary,
                    width: cardWidth,
                    hasPulse: true,
                    tooltip: isAr ? 'الحملات النشطة التي تستقبل فواتير العملاء حالياً (انقر للتصفية)' : 'Campaigns currently active and accepting receipts (click to filter)',
                    isSelected: _campaignFilter == 'ACTIVE',
                    onTap: () => setState(() => _campaignFilter = 'ACTIVE'),
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
                    color: colorScheme.secondary,
                    width: cardWidth,
                    tooltip: isAr ? 'حملات متوقفة مؤقتاً أو انتهت صلاحيتها الزمنية (انقر للتصفية)' : 'Paused or expired campaigns (click to filter)',
                    isSelected: _campaignFilter == 'INACTIVE',
                    onTap: () => setState(() => _campaignFilter = 'INACTIVE'),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: M3Spacing.md),

          // 2. Filter Tabs & Search Controls (M3 Button Group Standard)
          Card.outlined(
            margin: EdgeInsets.zero,
            color: colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: M3Shape.radiusMedium,
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            child: Padding(
            padding: const EdgeInsets.all(M3Spacing.sm),
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
                      child: SearchBar(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        hintText: isAr ? 'بحث باسم الحملة أو الشركة...' : 'Search campaigns or companies...',
                        leading: Icon(Icons.search_rounded, color: colorScheme.onSurfaceVariant),
                        trailing: [
                          if (_searchController.text.isNotEmpty)
                            IconButton(
                              tooltip: isAr ? 'مسح' : 'Clear',
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            ),
          ),
          const SizedBox(height: M3Spacing.md),

          // 3. Section Title with Count Indicator
          Row(
            children: [
              Expanded(
                child: Text(
                  '${strings.eventsTitle} (${filteredEvents.length})',
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (filteredEvents.length != allEvents.length && !isCompactPage) ...[
                Text(
                  isAr ? 'تمت تصفية ${filteredEvents.length} من أصل $totalCampaigns' : 'Showing ${filteredEvents.length} of $totalCampaigns',
                  style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: M3Spacing.xs),
              ],
              if (!isCompactPage)
                FilledButton.tonalIcon(
                  onPressed: _openCreateEventScreen,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(isAr ? 'إنشاء حملة جديدة' : 'New Campaign'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
            ],
          ),
          const SizedBox(height: M3Spacing.xs),

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
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final textTheme = theme.textTheme;
    final selectedBg = colorScheme.secondaryContainer;
    final onSelected = colorScheme.onSecondaryContainer;
    final content = Padding(
      padding: const EdgeInsets.all(M3Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? colorScheme.surface : color.withValues(alpha: 0.12),
                  borderRadius: M3Shape.radiusMedium,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const Spacer(),
              if (hasPulse)
                Chip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  avatar: Icon(Icons.circle, size: 8, color: colorScheme.tertiary),
                  label: const Text('LIVE'),
                  labelStyle: textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onTertiaryContainer,
                  ),
                  backgroundColor: colorScheme.tertiaryContainer,
                  side: BorderSide.none,
                ),
            ],
          ),
          const SizedBox(height: M3Spacing.sm),
          Text(
            value,
            style: textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: isSelected ? onSelected : colorScheme.onSurface,
              height: 1.1,
            ),
          ),
          const SizedBox(height: M3Spacing.xxs),
          Text(
            title,
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: isSelected ? onSelected : colorScheme.onSurface,
            ),
          ),
          Text(
            subtitle,
            style: textTheme.bodySmall?.copyWith(
              color: isSelected ? onSelected : colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    // M3 card variants: filled (secondaryContainer) when selected, outlined otherwise.
    final card = SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: M3Elevation.level0,
        color: isSelected ? selectedBg : colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: M3Shape.radiusMedium,
          side: isSelected ? BorderSide.none : BorderSide(color: colorScheme.outlineVariant),
        ),
        child: onTap != null ? InkWell(onTap: onTap, child: content) : content,
      ),
    );

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: card,
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
      statusBg = colorScheme.errorContainer;
      statusBorder = colorScheme.errorContainer;
      statusTextColor = colorScheme.onErrorContainer;
      statusIcon = Icons.event_busy_rounded;
      statusLabel = isAr ? 'منتهية' : 'Expired';
    } else if (event.isNotStartedYet) {
      statusBg = colorScheme.secondaryContainer;
      statusBorder = colorScheme.secondaryFixedDim;
      statusTextColor = colorScheme.onSecondaryContainer;
      statusIcon = Icons.schedule_rounded;
      statusLabel = isAr ? 'لم تبدأ بعد' : 'Upcoming';
    } else {
      statusBg = colorScheme.tertiaryContainer;
      statusBorder = colorScheme.tertiaryFixedDim;
      statusTextColor = colorScheme.onTertiaryFixedVariant;
      statusIcon = Icons.check_circle_rounded;
      statusLabel = isAr ? 'نشطة وسارية' : 'Active & Running';
    }

    // M3 outlined card (level 0, medium shape, outlineVariant stroke)
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: M3Spacing.sm),
      color: colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: M3Shape.radiusMedium,
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? M3Spacing.sm : M3Spacing.md),
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
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: M3Shape.radiusSmall,
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
                  tooltip: isAr ? 'الشركة المصنعة وصاحبة الحملة الراعية' : 'Sponsor brand company',
                  customBg: colorScheme.primary,
                  customColor: colorScheme.onPrimary,
                  customBorder: colorScheme.primary,
                  isHero: true,
                ),
                if (event.retailChainName.isNotEmpty)
                  _buildMetadataPill(
                    icon: Icons.storefront_rounded,
                    label: event.branchesDisplaySummary,
                    colorScheme: colorScheme,
                    customBg: colorScheme.secondaryContainer,
                    customBorder: colorScheme.secondaryFixedDim,
                    customColor: colorScheme.onSecondaryContainer,
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
                  customBg: colorScheme.tertiaryContainer,
                  customBorder: colorScheme.tertiaryFixedDim,
                  customColor: colorScheme.onTertiaryContainer,
                  tooltip: isAr ? 'قيمة المشتريات المطلوبة لقبول الفاتورة' : 'Minimum purchase threshold for receipt acceptance',
                ),
                if (event.startDate != null || event.endDate != null)
                  _buildMetadataPill(
                    icon: Icons.calendar_month_rounded,
                    label: '${isAr ? "الفترة: " : "Period: "}${event.startDate != null ? campaignFirstDayLabel(event.startDate) : (isAr ? "مفتوح" : "Open")} ${isAr ? "إلى" : "to"} ${event.endDate != null ? campaignLastDayLabel(event.endDate) : (isAr ? "مفتوح" : "Open")}',
                    colorScheme: colorScheme,
                    tooltip: isAr ? 'تاريخ بداية ونهاية سريان الحملة' : 'Campaign validity date range',
                  ),
                if (event.requiredProducts.isNotEmpty)
                  _buildMetadataPill(
                    icon: Icons.inventory_2_rounded,
                    label: '${isAr ? "الأصناف المستهدفة: " : "Target Items: "}${event.requiredProducts.length} ${isAr ? "صنفاً" : "items"}',
                    colorScheme: colorScheme,
                    customBg: colorScheme.primaryContainer,
                    customBorder: colorScheme.primaryFixedDim,
                    customColor: colorScheme.onPrimaryContainer,
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
                        subtitle: isAr ? 'رابط مدير الشركة الدائم والـ ROI' : 'Permanent Brand Executive & ROI',
                        icon: Icons.business_center_rounded,
                        isActive: event.isManagerActive,
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
                      // 4. WhatsApp Winner Auto-Notification Switch
                      _buildPortalControlTile(
                        context,
                        title: strings.campaignWhatsAppWinnerTileTitle,
                        subtitle: strings.campaignWhatsAppWinnerTileSubtitle,
                        icon: Icons.mark_chat_read_rounded,
                        isActive: event.isActive && event.enableWhatsAppWinnerNotification,
                        colorScheme: colorScheme,
                        isAr: isAr,
                        tooltip: event.enableWhatsAppWinnerNotification
                            ? (isAr ? 'الإرسال التلقائي لرسائل التهنئة عبر الواتساب مفعل لهذه الحملة' : 'WhatsApp winner auto-notification enabled')
                            : (isAr ? 'الإرسال التلقائي لرسائل التهنئة عبر الواتساب متوقف لهذه الحملة' : 'WhatsApp winner auto-notification paused'),
                        onChanged: (val) async {
                          if (firestore != null) {
                            await firestore.collection('events').doc(event.id).update({'enableWhatsAppWinnerNotification': val});
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
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // 1. Copy Promoter / Client Link (Unified Company Master Link)
                Tooltip(
                  message: isAr
                      ? 'نسخ رابط العميل والبروموتر الموحد الدائم لكافة عروض الشركة (كود: $companySlug)'
                      : strings.promoterPortalTooltip,
                  waitDuration: const Duration(milliseconds: 400),
                  child: FilledButton.tonalIcon(
                    onPressed: () => _copyPromoterLink(context, companySlug),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: Text(strings.copyPromoterLink, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primaryContainer,
                      foregroundColor: colorScheme.onPrimaryContainer,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.2)),
                      ),
                    ),
                  ),
                ),

                // 2. Copy Agency Operations Link (Unified Company Master Link)
                Tooltip(
                  message: isAr
                      ? 'نسخ كارت واتساب بوابة شركة الدعاية والعمليات (الرابط + اسم المستخدم + كلمة المرور)'
                      : strings.agencyOpsPortalTooltip,
                  waitDuration: const Duration(milliseconds: 400),
                  child: FilledButton.tonalIcon(
                    onPressed: () => _copyAgencyOpsLink(context, companySlug, event: event),
                    icon: const Icon(Icons.store_mall_directory_rounded, size: 18),
                    label: Text(strings.copyAgencyOpsLink, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primaryContainer,
                      foregroundColor: colorScheme.onPrimaryContainer,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                // 3. Copy Brand Executive Master Link (Unified Company Master Link)
                Tooltip(
                  message: isAr
                      ? 'نسخ كارت واتساب البوابة التنفيذية لمدير عام الشركة (الرابط + اسم المستخدم + كلمة المرور)'
                      : strings.brandExecutivePortalTooltip,
                  waitDuration: const Duration(milliseconds: 400),
                  child: FilledButton.tonalIcon(
                    onPressed: () => _copyBrandExecutiveLink(context, companySlug, event: event),
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

                // 3.5. Portal Credentials & WhatsApp Login Card
                Tooltip(
                  message: isAr
                      ? 'إدارة بيانات الدخول لبوابتي الشركة والعمليات ونسخ كارت الواتساب الجاهز'
                      : 'Manage Portal Credentials & Copy WhatsApp Login Card',
                  waitDuration: const Duration(milliseconds: 400),
                  child: OutlinedButton.icon(
                    onPressed: () => PortalCredentialsDialog.show(
                      context,
                      companySlug: companySlug,
                      companyName: event.targetCompany.isNotEmpty ? event.targetCompany : companySlug.toUpperCase(),
                      event: event,
                    ),
                    icon: const Icon(Icons.vpn_key_rounded, size: 18),
                    label: Text(
                      isAr ? 'بيانات الدخول وكارت الواتساب' : 'Portal Login & WhatsApp Card',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.4)),
                    ),
                  ),
                ),

                // 4. Material Design 3 Campaign Action & Previews Menu
                M3ActionMenu(
                  tooltip: isAr ? 'خيارات ومعاينات الحملة' : 'Campaign Options & Previews',
                  anchorBuilder: (context, controller, child) {
                    return OutlinedButton.icon(
                      onPressed: () {
                        if (controller.isOpen) {
                          controller.close();
                        } else {
                          controller.open();
                        }
                      },
                      icon: const Icon(Icons.more_horiz_rounded, size: 20),
                      label: Text(
                        isAr ? 'الإجراءات والمعاينة' : 'Actions & Previews',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
                      ),
                    );
                  },
                  children: [
                    M3ActionMenu.header(
                      context: context,
                      title: isAr ? 'معاينات البوابات المباشرة' : 'Live Portal Previews',
                      icon: Icons.visibility_outlined,
                    ),
                    M3ActionMenu.submenu(
                      context: context,
                      label: isAr ? 'معاينة تجربة المستخدم' : 'Live User Previews',
                      icon: Icons.remove_red_eye_rounded,
                      children: [
                        M3ActionMenu.item(
                          context: context,
                          label: isAr ? 'بوابة شركة الدعاية والعمليات' : 'Agency Operations Portal',
                          icon: Icons.store_mall_directory_rounded,
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
                        ),
                        M3ActionMenu.item(
                          context: context,
                          label: isAr ? 'البوابة التنفيذية للعلامة التجارية' : 'Brand Executive Portal',
                          icon: Icons.dashboard_customize_rounded,
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
                        ),
                        M3ActionMenu.item(
                          context: context,
                          label: isAr ? 'تطبيق رفع الفواتير الميداني' : 'Promoter / Client Mobile App',
                          icon: Icons.phone_android_rounded,
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
                        ),
                      ],
                    ),
                    M3ActionMenu.divider(),
                    M3ActionMenu.header(
                      context: context,
                      title: isAr ? 'إدارة وتحكم الحملة' : 'Campaign Management',
                      icon: Icons.tune_rounded,
                    ),
                    M3ActionMenu.item(
                      context: context,
                      label: isAr ? 'بيانات دخول البوابات وكارت الواتساب' : 'Portal Credentials & WhatsApp Card',
                      icon: Icons.vpn_key_rounded,
                      onPressed: () => PortalCredentialsDialog.show(
                        context,
                        companySlug: companySlug,
                        companyName: event.targetCompany.isNotEmpty ? event.targetCompany : companySlug.toUpperCase(),
                        event: event,
                      ),
                    ),
                    M3ActionMenu.item(
                      context: context,
                      label: isAr ? 'تعديل بيانات وشروط وبرومبت الحملة' : 'Edit Campaign Rules & Prompt',
                      icon: Icons.edit_note_rounded,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => CreateEventScreen(eventToEdit: event),
                          ),
                        );
                      },
                    ),
                    M3ActionMenu.item(
                      context: context,
                      label: isAr ? 'سجل وإعادة تعيين كروت الفواتشرات' : 'Voucher Cards Registry & Reset',
                      icon: Icons.confirmation_number_rounded,
                      onPressed: () => VoucherSerialsManagementDialog.show(context, event),
                    ),
                    M3ActionMenu.divider(),
                    M3ActionMenu.item(
                      context: context,
                      label: strings.deleteCampaignTooltip,
                      icon: Icons.delete_forever_rounded,
                      isDestructive: true,
                      onPressed: () => _showDeleteCampaignDialog(context, event, strings, firestore),
                    ),
                  ],
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
    bool isHero = false,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: EdgeInsets.symmetric(
          horizontal: isHero ? 14 : 10,
          vertical: isHero ? 7 : 6,
        ),
        decoration: BoxDecoration(
          color: customBg ?? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(isHero ? 12 : 10),
          border: Border.all(
            color: customBorder ?? colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: isHero ? 1.4 : 1.0,
          ),
          boxShadow: isHero
              ? [
                  BoxShadow(
                    color: (customBg ?? colorScheme.primary).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: isHero ? 17 : 15,
              color: customColor ?? colorScheme.primary,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: isHero ? 13 : 12,
                  fontWeight: isHero ? FontWeight.bold : FontWeight.w600,
                  color: customColor ?? colorScheme.onSurface,
                  letterSpacing: isHero ? 0.2 : 0,
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
    final statusColor = isActive ? colorScheme.onTertiaryFixedVariant : colorScheme.onSecondaryContainer;
    final statusBg = isActive ? colorScheme.tertiaryContainer : colorScheme.secondaryContainer;
    final statusBorder = isActive ? colorScheme.tertiaryFixedDim : colorScheme.primaryFixedDim;
    final statusText = isActive ? (isAr ? 'مفعلة 🟢' : 'Active 🟢') : (isAr ? 'متوقفة ⏸️' : 'Paused ⏸️');

    return Container(
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 340),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? colorScheme.outlineVariant.withValues(alpha: 0.6) : colorScheme.primaryFixedDim,
          width: isActive ? 1 : 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isActive ? colorScheme.primaryContainer : colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: isActive ? colorScheme.onPrimaryContainer : colorScheme.onSecondaryContainer,
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
