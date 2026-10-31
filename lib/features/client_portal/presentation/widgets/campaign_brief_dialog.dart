import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/services/firebase_service.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/constants/country_currency_config.dart';
import '../../../admin/domain/event_model.dart';
import '../../../admin/domain/retail_chain_model.dart';
import '../../../../core/services/retail_chains_service.dart';
import '../../../../core/utils/branch_chain_resolver.dart';
import 'campaign_gift_balance_dialog.dart';
import 'promoter_invoices_dialog.dart';

/// Interactive Material Design 3 Dialog displaying the Campaign Concept, Brief, and Structured Promotional Rules
class CampaignBriefDialog extends ConsumerStatefulWidget {
  final EventModel event;

  const CampaignBriefDialog({
    super.key,
    required this.event,
  });

  /// Static helper to display the dialog smoothly with M3 scale and fade transitions
  static Future<void> show(BuildContext context, EventModel event) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'CampaignBriefDialog',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) {
        return CampaignBriefDialog(event: event);
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: anim1,
            curve: Curves.easeOutCubic,
          ),
          child: FadeTransition(
            opacity: anim1,
            child: child,
          ),
        );
      },
    );
  }

  @override
  ConsumerState<CampaignBriefDialog> createState() => _CampaignBriefDialogState();
}

class _CampaignBriefDialogState extends ConsumerState<CampaignBriefDialog> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _eventDocStream;
  String? _lastEventId;
  List<BranchModel> _dbBranches = const [];
  bool _branchesRequested = false;

  /// Loads branch docs once (only for multi-chain campaigns) so chain
  /// membership is resolved by branch ID instead of by name.
  void _ensureDbBranches(EventModel event) {
    if (_branchesRequested) return;
    if (BranchChainResolver.splitChainNames(event.retailChainName).length < 2) return;
    _branchesRequested = true;
    Future(() async {
      try {
        final list = await ref.read(retailChainsServiceProvider).getAllBranches();
        if (mounted) setState(() => _dbBranches = list);
      } catch (_) {}
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _ensureEventDocStream() {
    if (_eventDocStream == null || _lastEventId != widget.event.id) {
      _lastEventId = widget.event.id;
      try {
        final firestore = ref.read(firestoreProvider);
        if (widget.event.id.isNotEmpty) {
          _eventDocStream = firestore.collection('events').doc(widget.event.id).snapshots();
        }
      } catch (_) {
        _eventDocStream = null;
      }
    }
    return _eventDocStream;
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = AppStrings.of(ref);
    final isAr = strings.isAr;
    final activeCountry = ref.watch(activeCountryProvider);
    final currencySymbol = activeCountry.currencySymbol;
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isMobile = screenWidth < 600;

    final eventDocStream = _ensureEventDocStream();

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Dialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isMobile ? 22 : 28),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        insetPadding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 24,
          vertical: isMobile ? 16 : 32,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 680,
            maxHeight: mediaQuery.size.height * 0.88,
          ),
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: eventDocStream,
            builder: (context, snapshot) {
              EventModel liveEvent = event;
              if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
                try {
                  liveEvent = EventModel.fromFirestore(snapshot.data!);
                } catch (_) {}
              }

              final rules = liveEvent.promotionalRules;

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Header
                  _buildHeader(
                    context: context,
                    colorScheme: colorScheme,
                    strings: strings,
                    event: liveEvent,
                    isMobile: isMobile,
                  ),

                  const Divider(height: 1),

                  // 2. Scrollable Body
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(isMobile ? 14 : 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Top Overview Card
                          _buildCampaignOverviewCard(
                            context: context,
                            colorScheme: colorScheme,
                            strings: strings,
                            event: liveEvent,
                            currencySymbol: currencySymbol,
                            isMobile: isMobile,
                          ),

                          const SizedBox(height: 14),

                          // Campaign Guide (merged from the former side-pane card)
                          _buildCampaignGuideSection(
                            context: context,
                            colorScheme: colorScheme,
                            event: liveEvent,
                            isAr: isAr,
                          ),

                          const SizedBox(height: 18),

                          // Promotional Rules Section Header
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.format_list_bulleted_rounded,
                                  size: 18,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  strings.promotionalConditionsListTitle,
                                  style: GoogleFonts.cairo(
                                    fontSize: isMobile ? 14 : 15.5,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                decoration: BoxDecoration(
                                  color: colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${rules.length} ${isAr ? 'عروض' : 'offers'}',
                                  style: GoogleFonts.cairo(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // Rules Cards List
                          if (rules.isEmpty)
                            _buildEmptyRulesCard(context, colorScheme, strings)
                          else
                            ...rules.asMap().entries.map((entry) {
                              final index = entry.key;
                              final rule = entry.value;
                              return _buildRuleCard(
                                context: context,
                                colorScheme: colorScheme,
                                strings: strings,
                                rule: rule,
                                index: index,
                                currencySymbol: currencySymbol,
                                isMobile: isMobile,
                              );
                            }),

                          // General Campaign Info & Dates
                          const SizedBox(height: 14),
                          _buildGeneralConditionsCard(
                            context: context,
                            colorScheme: colorScheme,
                            strings: strings,
                            event: liveEvent,
                            currencySymbol: currencySymbol,
                            isMobile: isMobile,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Divider(height: 1),

                  // 3. Footer Action
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 14 : 20,
                      vertical: isMobile ? 10 : 14,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: Text(
                            strings.closeBriefDialog,
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                          ),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required EventModel event,
    required bool isMobile,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 20,
        vertical: isMobile ? 12 : 16,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primary,
                  colorScheme.tertiary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.campaign_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.campaignBriefTitle,
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  '${event.eventName} • ${event.targetCompany}',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 11.5 : 12.5,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: strings.closeBriefDialog,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// "دليل وقواعد الحملة" quick reference, merged into the brief so the promoter
  /// page no longer needs a separate guide card.
  Widget _buildCampaignGuideSection({
    required BuildContext context,
    required ColorScheme colorScheme,
    required EventModel event,
    required bool isAr,
  }) {
    Widget btn(IconData icon, String label, VoidCallback onTap) => Expanded(
          child: OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 16),
            label: Text(
              label,
              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_rounded, color: colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isAr ? 'دليل وقواعد الحملة' : 'Campaign Guide',
                  style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          Text(
            isAr ? 'مرجع سريع للبروموتر والمبيعات' : 'Promoter quick reference',
            style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              btn(Icons.card_giftcard_rounded, isAr ? 'الهدايا' : 'Prizes',
                  () => CampaignGiftBalanceDialog.show(context, event)),
              const SizedBox(width: 8),
              btn(Icons.receipt_long_rounded, isAr ? 'الفواتير' : 'Invoices',
                  () => PromoterInvoicesDialog.show(context, event)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCampaignOverviewCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required EventModel event,
    required String currencySymbol,
    required bool isMobile,
  }) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final dateFormat = DateFormat('yyyy/MM/dd');
    final startDateStr = event.startDate != null ? dateFormat.format(event.startDate!) : '—';
    final endDateStr = event.endDate != null ? dateFormat.format(event.endDate!) : '—';

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer.withValues(alpha: 0.5),
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.storefront_rounded, color: colorScheme.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isAr
                      ? 'الجهات والفروع المشاركة'
                      : 'Participating organizations & branches',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: event.isActive ? colorScheme.tertiaryContainer : colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: event.isActive ? colorScheme.tertiaryFixedDim : colorScheme.outline,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: event.isActive ? colorScheme.tertiary : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      event.isActive ? 'نشط ومعتمد' : 'غير نشط',
                      style: GoogleFonts.cairo(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: event.isActive ? colorScheme.onTertiaryContainer : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              if (event.minimumSpend > 0)
                _buildInfoBadge(
                  icon: Icons.payments_outlined,
                  label: 'الحد الأدنى: ${event.minimumSpend.toInt()} $currencySymbol',
                  colorScheme: colorScheme,
                ),
              _buildInfoBadge(
                icon: Icons.calendar_month_outlined,
                label: 'ساري: $startDateStr إلى $endDateStr',
                colorScheme: colorScheme,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._organizationGroups(event, isAr).map(
            (g) => _buildOrganizationTile(
              orgName: g.key,
              branches: g.value,
              isAr: isAr,
              colorScheme: colorScheme,
            ),
          ),
        ],
      ),
    );
  }

  /// Groups the campaign's participating branches by organization (retail chain).
  /// Chain membership is resolved ID-first (branchIds[i] -> branch doc ->
  /// retailChainId); name matching is only a fallback for legacy events.
  List<MapEntry<String, List<String>>> _organizationGroups(EventModel event, bool isAr) {
    _ensureDbBranches(event);
    final orgs = BranchChainResolver.splitChainNames(event.retailChainName);
    final branches = <String>[];
    for (var i = 0; i < event.branchIds.length || i < event.branchNames.length; i++) {
      final n = i < event.branchNames.length ? event.branchNames[i].trim() : '';
      final id = i < event.branchIds.length ? event.branchIds[i].trim() : '';
      final label = n.isNotEmpty ? n : id;
      if (label.isNotEmpty && !branches.contains(label)) branches.add(label);
    }
    if (orgs.isEmpty) {
      if (branches.isEmpty) return const [];
      return [MapEntry(isAr ? 'الفروع المشاركة' : 'Participating branches', branches)];
    }
    if (orgs.length == 1) return [MapEntry(orgs.first, branches)];
    return BranchChainResolver.groupBranchesByChain(
      retailChainId: event.retailChainId,
      retailChainName: event.retailChainName,
      branchIds: event.branchIds,
      branchNames: event.branchNames,
      dbBranches: _dbBranches,
      unknownToAllChains: false,
    ).entries.toList();
  }

  Widget _buildOrganizationTile({
    required String orgName,
    required List<String> branches,
    required bool isAr,
    required ColorScheme colorScheme,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.business_rounded, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  orgName,
                  style: GoogleFonts.cairo(fontSize: 13.5, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                ),
              ),
              Text(
                branches.isEmpty
                    ? (isAr ? 'كل الفروع' : 'All branches')
                    : (isAr ? '${branches.length} فرع' : '${branches.length} branches'),
                style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          if (branches.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: branches
                  .map((b) => Chip(
                        avatar: Icon(Icons.location_on_outlined, size: 14, color: colorScheme.onSecondaryContainer),
                        label: Text(b, style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSecondaryContainer)),
                        backgroundColor: colorScheme.secondaryContainer.withValues(alpha: 0.7),
                        side: BorderSide.none,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoBadge({
    required IconData icon,
    required String label,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required PromotionalRuleItem rule,
    required int index,
    required String currencySymbol,
    required bool isMobile,
  }) {
    final isExplicitVoucher = rule.rewardType == 'voucher' ||
        rule.rewardValue.contains('فواتشر') ||
        rule.rewardValue.contains('قسيمة') ||
        rule.rewardValue.toLowerCase().contains('voucher');
    final isExplicitProduct = rule.rewardType == 'free_product' ||
        rule.rewardType == 'game_spin' ||
        rule.rewardValue.contains('هدية') ||
        rule.rewardValue.contains('منتج') ||
        (rule.linkedGifts.isNotEmpty && rule.linkedGifts.every((g) => !g.isVoucher));

    final isVoucher = isExplicitVoucher && !isExplicitProduct;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(isMobile ? 12 : 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isVoucher
              ? colorScheme.primaryFixedDim.withValues(alpha: 0.6)
              : colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rule Header: Title + Badges
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isVoucher ? colorScheme.secondaryContainer : colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                  size: 18,
                  color: isVoucher ? colorScheme.onSecondaryContainer : colorScheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.ruleTitle,
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 13.5 : 14.5,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: isVoucher ? colorScheme.secondaryContainer : colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isVoucher ? colorScheme.primaryFixedDim : colorScheme.tertiaryFixedDim,
                            ),
                          ),
                          child: Text(
                            isVoucher ? 'قسيمة مشتريات' : 'هدية عينية مجانية',
                            style: GoogleFonts.cairo(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isVoucher ? colorScheme.onSecondaryContainer : colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // Condition Row (شراء X من ...)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shopping_cart_outlined, size: 16, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '${strings.ruleConditionBuy}: ',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                Expanded(
                  child: Text(
                    '${rule.minQuantity} من [${rule.triggerProduct}]',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // Reward Row (المكافأة المستحقة)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isVoucher
                  ? colorScheme.secondaryContainer.withValues(alpha: 0.6)
                  : colorScheme.tertiaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isVoucher
                    ? colorScheme.secondaryFixedDim
                    : colorScheme.tertiaryFixedDim,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isVoucher ? Icons.payments_rounded : Icons.redeem_rounded,
                  size: 16,
                  color: isVoucher ? colorScheme.onSecondaryContainer : colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  '${strings.ruleConditionGet}: ',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isVoucher ? colorScheme.onSecondaryContainer : colorScheme.onTertiaryContainer,
                  ),
                ),
                Expanded(
                  child: Text(
                    rule.rewardValue,
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isVoucher ? colorScheme.onSecondaryContainer : colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Linked Cards Breakdown (e.g. 2x50 + 1x25)
          if (rule.linkedGifts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: rule.linkedGifts.map((g) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.primaryFixedDim),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        g.isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                        size: 12,
                        color: colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${g.quantity} × ${g.giftName}',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyRulesCard(BuildContext context, ColorScheme colorScheme, AppStrings strings) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Center(
        child: Text(
          strings.noSpecificPromotionalRules,
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }


  Widget _buildGeneralConditionsCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required EventModel event,
    required String currencySymbol,
    required bool isMobile,
  }) {
    final branchesText = event.isAllBranches || event.branchNames.isEmpty
        ? strings.allBranchesScope
        : event.branchNames.join(' • ');

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.campaignGeneralConditions,
            style: GoogleFonts.cairo(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          _buildBulletItem(
            icon: Icons.store_rounded,
            label: 'الفروع والمنافذ: $branchesText',
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 5),
          _buildBulletItem(
            icon: Icons.qr_code_scanner_rounded,
            label: 'فحص الفواتير: يتم التدقيق آلياً بواسطة الذكاء الاصطناعي مع منع التكرار.',
            colorScheme: colorScheme,
          ),
          if (event.minimumSpend > 0) ...[
            const SizedBox(height: 5),
            _buildBulletItem(
              icon: Icons.receipt_long_rounded,
              label: 'الحد الأدنى لقيمة الفاتورة: ${event.minimumSpend.toInt()} $currencySymbol',
              colorScheme: colorScheme,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBulletItem({
    required IconData icon,
    required String label,
    required ColorScheme colorScheme,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
