import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/widgets/switch_point_branding.dart';
import '../../../core/widgets/m3_button_groups.dart';
import '../../admin/domain/event_model.dart';
import '../../admin/domain/company_gift_model.dart';

/// Data structure representing aggregated prize stock metrics across events & branches
class AggregatedGiftStock {
  final String giftId;
  final String giftName;
  final String sku;
  final int totalAllocated;
  final int totalClaimed;
  final int totalRemaining;
  final Map<String, int> branchRemainingMap; // branchName -> remaining
  final Map<String, int> branchAllocatedMap; // branchName -> allocated
  final List<String> eventNames;

  AggregatedGiftStock({
    required this.giftId,
    required this.giftName,
    this.sku = '',
    required this.totalAllocated,
    required this.totalClaimed,
    required this.totalRemaining,
    required this.branchRemainingMap,
    required this.branchAllocatedMap,
    required this.eventNames,
  });

  double get depletionRate => totalAllocated > 0
      ? (totalClaimed / totalAllocated).clamp(0.0, 1.0)
      : 0.0;

  bool get isOutOfStock => totalRemaining <= 0;
  bool get isLowStock => !isOutOfStock && (totalRemaining <= 5 || (totalAllocated > 0 && totalRemaining / totalAllocated < 0.20));
  bool get isHealthy => !isOutOfStock && !isLowStock;
}

/// Enterprise-grade real-time Prizes & Stock Balance System (منظومة رصيد وجرد الهدايا والمخزون اللحظي)
class CompanyPrizesStockReportScreen extends ConsumerStatefulWidget {
  final String lockedCompanySlug;
  final String lockedCompanyName;
  final bool isEmbedded;
  final VoidCallback? onBack;

  const CompanyPrizesStockReportScreen({
    super.key,
    required this.lockedCompanySlug,
    required this.lockedCompanyName,
    this.isEmbedded = false,
    this.onBack,
  });

  @override
  ConsumerState<CompanyPrizesStockReportScreen> createState() =>
      _CompanyPrizesStockReportScreenState();
}

class _CompanyPrizesStockReportScreenState
    extends ConsumerState<CompanyPrizesStockReportScreen> {
  // Search & Filter State
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedEventId; // null = all campaigns
  String? _selectedBranch; // null = all branches
  String _stockStatusFilter = 'ALL'; // 'ALL', 'AVAILABLE', 'LOW', 'OUT'
  int _viewMode = 0; // 0: Itemized SKU, 1: Branch Breakdown, 2: Campaign Breakdown

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _exportCsvReport(List<AggregatedGiftStock> gifts, AppStrings strings) async {
    final buffer = StringBuffer();
    // CSV Header
    buffer.writeln(
      'Gift SKU,Gift Name,Total Allocated,Awarded/Claimed,Remaining Stock,Depletion Rate %,Status,Branches Breakdown,Campaigns',
    );

    for (final gift in gifts) {
      final branchesInfo = gift.branchRemainingMap.entries
          .map((e) => '${e.key}: ${e.value} remaining')
          .join(' | ');
      final campaignsInfo = gift.eventNames.join(' | ');
      final status = gift.isOutOfStock
          ? 'Out of Stock'
          : (gift.isLowStock ? 'Low Stock' : 'In Stock');

      buffer.writeln(
        '"${gift.sku}","${gift.giftName}",${gift.totalAllocated},${gift.totalClaimed},${gift.totalRemaining},"${(gift.depletionRate * 100).toStringAsFixed(1)}%","$status","$branchesInfo","$campaignsInfo"',
      );
    }

    final csvString = buffer.toString();
    final utf8Bom = [0xEF, 0xBB, 0xBF];
    final bytes = Uint8List.fromList([...utf8Bom, ...utf8.encode(csvString)]);

    if (kIsWeb) {
      final base64Csv = base64Encode(bytes);
      final url = 'data:text/csv;charset=utf-8;base64,$base64Csv';
      await launchUrl(Uri.parse(url));
    } else {
      Clipboard.setData(ClipboardData(text: csvString));
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strings.isAr
              ? 'تم تصدير كشف جرد ورصيد الهدايا بنجاح 📥'
              : 'Prizes Stock Report exported successfully 📥',
        ),
        backgroundColor: Colors.teal.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = AppStrings.of(ref);
    final isAr = ref.isArabic;
    final isHi = ref.isHindi;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    FirebaseFirestore? firestore;
    try {
      firestore = ref.watch(firestoreProvider);
    } catch (_) {
      firestore = null;
    }

    final content = _buildRealtimeContent(
      context: context,
      firestore: firestore,
      colorScheme: colorScheme,
      strings: strings,
      isAr: isAr,
      isHi: isHi,
      isMobile: isMobile,
    );

    if (widget.isEmbedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: SwitchPointHeader(
        subtitle: '${widget.lockedCompanyName} — ${strings.prizesStockTitle}',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: strings.back,
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(child: content),
          const SwitchPointFooter(),
        ],
      ),
    );
  }

  Widget _buildRealtimeContent({
    required BuildContext context,
    required FirebaseFirestore? firestore,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
  }) {
    if (firestore == null) {
      return _buildAnalyzedView(
        context: context,
        colorScheme: colorScheme,
        strings: strings,
        isAr: isAr,
        isHi: isHi,
        isMobile: isMobile,
        companyEvents: const [],
        masterGifts: const [],
      );
    }

    final slug = widget.lockedCompanySlug.toLowerCase().trim();

    // 1. Stream events for this company to obtain all allocated prizes per campaign & branch
    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('events').snapshots(),
      builder: (context, eventsSnapshot) {
        if (eventsSnapshot.connectionState == ConnectionState.waiting &&
            !eventsSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        final allEventDocs = eventsSnapshot.data?.docs ?? [];
        final companyEvents = allEventDocs
            .map((doc) {
              try {
                return EventModel.fromFirestore(doc);
              } catch (_) {
                return null;
              }
            })
            .whereType<EventModel>()
            .where((e) =>
                e.companySlug.toLowerCase() == slug ||
                e.targetCompany.toLowerCase().contains(slug) ||
                slug.isEmpty)
            .toList();

        // 2. Stream company_gifts master catalog
        return StreamBuilder<QuerySnapshot>(
          stream: firestore
              .collection('company_gifts')
              .where('companySlug', isEqualTo: slug)
              .snapshots(),
          builder: (context, giftsSnapshot) {
            final masterGifts = (giftsSnapshot.data?.docs ?? [])
                .map((d) {
                  try {
                    return CompanyGiftModel.fromFirestore(d);
                  } catch (_) {
                    return null;
                  }
                })
                .whereType<CompanyGiftModel>()
                .toList();

            return _buildAnalyzedView(
              context: context,
              colorScheme: colorScheme,
              strings: strings,
              isAr: isAr,
              isHi: isHi,
              isMobile: isMobile,
              companyEvents: companyEvents,
              masterGifts: masterGifts,
            );
          },
        );
      },
    );
  }

  Widget _buildAnalyzedView({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required List<EventModel> companyEvents,
    required List<CompanyGiftModel> masterGifts,
  }) {
    // 1. Filter events if specific event selected
    List<EventModel> filteredEvents = companyEvents;
    if (_selectedEventId != null && _selectedEventId!.isNotEmpty) {
      filteredEvents =
          companyEvents.where((e) => e.id == _selectedEventId).toList();
    }

    // 2. Extract distinct branches across filtered events
    final Set<String> distinctBranches = {};
    for (final event in companyEvents) {
      for (final bName in event.branchNames) {
        if (bName.trim().isNotEmpty) distinctBranches.add(bName.trim());
      }
      for (final prize in event.allocatedPrizes) {
        if (prize.branchName.trim().isNotEmpty) {
          distinctBranches.add(prize.branchName.trim());
        }
      }
    }

    // 3. Aggregate all prizes across filtered events & branches
    final Map<String, AggregatedGiftStock> aggregatedMap = {};

    for (final event in filteredEvents) {
      for (final prize in event.allocatedPrizes) {
        // If branch filter is applied, skip prizes not in that branch
        if (_selectedBranch != null && _selectedBranch!.isNotEmpty) {
          final prizeBranch = prize.branchName.trim();
          if (prizeBranch.isNotEmpty && prizeBranch != _selectedBranch) {
            continue;
          }
        }

        final key = prize.name.trim().toLowerCase();
        final branchKey = prize.branchName.isNotEmpty
            ? prize.branchName.trim()
            : (prize.branchId.isNotEmpty ? prize.branchId : (isAr ? 'الفرع الرئيسي' : 'Main Branch'));

        final existing = aggregatedMap[key];
        if (existing == null) {
          final branchRem = <String, int>{branchKey: prize.remainingQuantity};
          final branchAlloc = <String, int>{branchKey: prize.allocatedQuantity};
          final claimed = (prize.allocatedQuantity - prize.remainingQuantity).clamp(0, prize.allocatedQuantity);

          aggregatedMap[key] = AggregatedGiftStock(
            giftId: prize.giftId.isNotEmpty ? prize.giftId : key,
            giftName: prize.name.trim(),
            sku: prize.giftId,
            totalAllocated: prize.allocatedQuantity,
            totalClaimed: claimed,
            totalRemaining: prize.remainingQuantity,
            branchRemainingMap: branchRem,
            branchAllocatedMap: branchAlloc,
            eventNames: [event.eventName],
          );
        } else {
          final newAllocated = existing.totalAllocated + prize.allocatedQuantity;
          final newRemaining = existing.totalRemaining + prize.remainingQuantity;
          final claimed = (prize.allocatedQuantity - prize.remainingQuantity).clamp(0, prize.allocatedQuantity);
          final newClaimed = existing.totalClaimed + claimed;

          existing.branchRemainingMap[branchKey] =
              (existing.branchRemainingMap[branchKey] ?? 0) + prize.remainingQuantity;
          existing.branchAllocatedMap[branchKey] =
              (existing.branchAllocatedMap[branchKey] ?? 0) + prize.allocatedQuantity;

          if (!existing.eventNames.contains(event.eventName)) {
            existing.eventNames.add(event.eventName);
          }

          aggregatedMap[key] = AggregatedGiftStock(
            giftId: existing.giftId,
            giftName: existing.giftName,
            sku: existing.sku,
            totalAllocated: newAllocated,
            totalClaimed: newClaimed,
            totalRemaining: newRemaining,
            branchRemainingMap: existing.branchRemainingMap,
            branchAllocatedMap: existing.branchAllocatedMap,
            eventNames: existing.eventNames,
          );
        }
      }
    }

    // If master gifts exist and some are not in campaigns yet, add them if no event filter
    if (_selectedEventId == null && (_selectedBranch == null || _selectedBranch!.isEmpty)) {
      for (final mg in masterGifts) {
        final key = mg.giftName.trim().toLowerCase();
        if (!aggregatedMap.containsKey(key)) {
          aggregatedMap[key] = AggregatedGiftStock(
            giftId: mg.id,
            giftName: mg.giftName,
            sku: mg.id,
            totalAllocated: mg.totalQuantity,
            totalClaimed: (mg.totalQuantity - mg.availableQuantity).clamp(0, mg.totalQuantity),
            totalRemaining: mg.availableQuantity,
            branchRemainingMap: {isAr ? 'المخزون الرئيسي للشركة' : 'Master Inventory': mg.availableQuantity},
            branchAllocatedMap: {isAr ? 'المخزون الرئيسي للشركة' : 'Master Inventory': mg.totalQuantity},
            eventNames: [isAr ? 'المستودع الرئيسي' : 'Master Warehouse'],
          );
        }
      }
    }

    // 4. Filter by search query & stock status
    List<AggregatedGiftStock> allGiftsList = aggregatedMap.values.toList();

    if (_searchQuery.isNotEmpty) {
      allGiftsList = allGiftsList.where((g) {
        final nameMatch = g.giftName.toLowerCase().contains(_searchQuery);
        final skuMatch = g.sku.toLowerCase().contains(_searchQuery);
        final branchMatch = g.branchRemainingMap.keys.any((b) => b.toLowerCase().contains(_searchQuery));
        return nameMatch || skuMatch || branchMatch;
      }).toList();
    }

    if (_stockStatusFilter == 'AVAILABLE') {
      allGiftsList = allGiftsList.where((g) => g.isHealthy).toList();
    } else if (_stockStatusFilter == 'LOW') {
      allGiftsList = allGiftsList.where((g) => g.isLowStock).toList();
    } else if (_stockStatusFilter == 'OUT') {
      allGiftsList = allGiftsList.where((g) => g.isOutOfStock).toList();
    }

    // Sort by remaining (highest allocated first)
    allGiftsList.sort((a, b) => b.totalAllocated.compareTo(a.totalAllocated));

    // Calculate High-level Summary Metrics
    int grandTotalAllocated = 0;
    int grandTotalClaimed = 0;
    int grandTotalRemaining = 0;

    for (final g in aggregatedMap.values) {
      grandTotalAllocated += g.totalAllocated;
      grandTotalClaimed += g.totalClaimed;
      grandTotalRemaining += g.totalRemaining;
    }

    final double overallDepletion = grandTotalAllocated > 0
        ? (grandTotalClaimed / grandTotalAllocated).clamp(0.0, 1.0)
        : 0.0;

    final coveredBranchesCount = distinctBranches.isNotEmpty
        ? distinctBranches.length
        : (companyEvents.isNotEmpty ? companyEvents.length : 1);

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 24,
          vertical: isMobile ? 12 : 20,
        ),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Hero KPI Stat Cards
                _buildHeroKpiGrid(
                  colorScheme: colorScheme,
                  strings: strings,
                  isAr: isAr,
                  isHi: isHi,
                  isMobile: isMobile,
                  totalAllocated: grandTotalAllocated,
                  totalClaimed: grandTotalClaimed,
                  totalRemaining: grandTotalRemaining,
                  depletionRate: overallDepletion,
                  coveredBranches: coveredBranchesCount,
                  campaignsCount: filteredEvents.length,
                ),

                const SizedBox(height: 20),

                // 2. Toolbar: Search, Filters & Export
                _buildToolbar(
                  context: context,
                  colorScheme: colorScheme,
                  strings: strings,
                  isAr: isAr,
                  isHi: isHi,
                  isMobile: isMobile,
                  companyEvents: companyEvents,
                  distinctBranches: distinctBranches.toList(),
                  onExport: () => _exportCsvReport(allGiftsList, strings),
                ),

                const SizedBox(height: 16),

                // 3. View Mode Switcher (3-Segment Connected Buttons)
                _buildViewModeSwitcher(
                  colorScheme: colorScheme,
                  strings: strings,
                  isAr: isAr,
                  isHi: isHi,
                  isMobile: isMobile,
                ),

                const SizedBox(height: 20),

                // 4. Main Dynamic View Content
                if (allGiftsList.isEmpty)
                  _buildEmptyState(colorScheme: colorScheme, strings: strings)
                else if (_viewMode == 0)
                  _buildItemizedGiftsView(
                    colorScheme: colorScheme,
                    strings: strings,
                    isAr: isAr,
                    isHi: isHi,
                    isMobile: isMobile,
                    gifts: allGiftsList,
                  )
                else if (_viewMode == 1)
                  _buildBranchBreakdownView(
                    colorScheme: colorScheme,
                    strings: strings,
                    isAr: isAr,
                    isHi: isHi,
                    isMobile: isMobile,
                    filteredEvents: filteredEvents,
                    gifts: allGiftsList,
                  )
                else
                  _buildCampaignBreakdownView(
                    colorScheme: colorScheme,
                    strings: strings,
                    isAr: isAr,
                    isHi: isHi,
                    isMobile: isMobile,
                    filteredEvents: filteredEvents,
                  ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Hero KPI Summary Grid
  // ---------------------------------------------------------------------------
  Widget _buildHeroKpiGrid({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required int totalAllocated,
    required int totalClaimed,
    required int totalRemaining,
    required double depletionRate,
    required int coveredBranches,
    required int campaignsCount,
  }) {
    final cards = [
      _buildStatCard(
        colorScheme: colorScheme,
        icon: Icons.inventory_2_rounded,
        iconColor: const Color(0xFF6750A4),
        title: strings.totalAllocatedGifts,
        value: '$totalAllocated',
        badgeText: isAr ? 'إجمالي المعتمد' : (isHi ? 'कुल' : 'Total Coded'),
        badgeColor: const Color(0xFF6750A4).withValues(alpha: 0.12),
        badgeTextColor: const Color(0xFF6750A4),
        subtitle: isAr ? 'شاملاً كافة الحملات والمخزون' : 'Across all campaigns',
      ),
      _buildStatCard(
        colorScheme: colorScheme,
        icon: Icons.card_giftcard_rounded,
        iconColor: const Color(0xFF00639B),
        title: strings.awardedGiftsCount,
        value: '$totalClaimed',
        badgeText: '${(depletionRate * 100).toStringAsFixed(0)}% ${strings.depletionRateLabel}',
        badgeColor: const Color(0xFF00639B).withValues(alpha: 0.12),
        badgeTextColor: const Color(0xFF00639B),
        subtitle: isAr ? 'هدايا تم تسليمها للعملاء الفائزين' : 'Claimed by shoppers',
      ),
      _buildStatCard(
        colorScheme: colorScheme,
        icon: Icons.verified_rounded,
        iconColor: totalRemaining <= 0
            ? const Color(0xFFB3261E)
            : (totalRemaining < 20 ? const Color(0xFFD97706) : const Color(0xFF006C50)),
        title: strings.remainingStockBalance,
        value: '$totalRemaining',
        badgeText: totalRemaining <= 0
            ? strings.stockDepletedBadge
            : (totalRemaining < 20 ? strings.stockLowBadge : strings.stockHealthyBadge),
        badgeColor: (totalRemaining <= 0
                ? const Color(0xFFB3261E)
                : (totalRemaining < 20 ? const Color(0xFFD97706) : const Color(0xFF006C50)))
            .withValues(alpha: 0.12),
        badgeTextColor: totalRemaining <= 0
            ? const Color(0xFFB3261E)
            : (totalRemaining < 20 ? const Color(0xFFD97706) : const Color(0xFF006C50)),
        subtitle: isAr ? 'الرصيد المتاح للسحب الآن' : 'Available in live wheels',
      ),
      _buildStatCard(
        colorScheme: colorScheme,
        icon: Icons.storefront_rounded,
        iconColor: const Color(0xFF006874),
        title: strings.coveredOutletsCount,
        value: '$coveredBranches',
        badgeText: '$campaignsCount ${isAr ? 'فعاليات' : 'Campaigns'}',
        badgeColor: const Color(0xFF006874).withValues(alpha: 0.12),
        badgeTextColor: const Color(0xFF006874),
        subtitle: isAr ? 'موزعة عبر الفروع والسلاسل' : 'Active retail outlets',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            children: cards
                .map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: c,
                    ))
                .toList(),
          );
        } else if (constraints.maxWidth < 1000) {
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: cards
                .map((c) => SizedBox(
                      width: (constraints.maxWidth - 12) / 2,
                      child: c,
                    ))
                .toList(),
          );
        } else {
          return Row(
            children: cards
                .map((c) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: c,
                      ),
                    ))
                .toList(),
          );
        }
      },
    );
  }

  Widget _buildStatCard({
    required ColorScheme colorScheme,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String badgeText,
    required Color badgeColor,
    required Color badgeTextColor,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badgeText,
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: badgeTextColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: colorScheme.onSurface,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.cairo(
              fontSize: 10,
              color: colorScheme.outline,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Toolbar: Search, Filters & Export
  // ---------------------------------------------------------------------------
  Widget _buildToolbar({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required List<EventModel> companyEvents,
    required List<String> distinctBranches,
    required VoidCallback onExport,
  }) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Row: Search + Export Button
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: strings.searchGiftsPlaceholder,
                      hintStyle: GoogleFonts.cairo(
                        fontSize: 12,
                        color: colorScheme.outline,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: strings.exportStockReportCsv,
                child: FilledButton.tonalIcon(
                  onPressed: onExport,
                  icon: const Icon(Icons.file_download_rounded, size: 18),
                  label: isMobile
                      ? const SizedBox.shrink()
                      : Text(
                          strings.exportStockReportCsv,
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 12 : 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Bottom Row: Dropdown Filters & Status Pills
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Campaign Selector Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _selectedEventId,
                    hint: Text(
                      strings.allCampaignsOption,
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          strings.allCampaignsOption,
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      for (final ev in companyEvents)
                        DropdownMenuItem<String?>(
                          value: ev.id,
                          child: Text(
                            ev.eventName,
                            style: GoogleFonts.cairo(fontSize: 12),
                          ),
                        ),
                    ],
                    onChanged: (val) => setState(() => _selectedEventId = val),
                  ),
                ),
              ),

              // Branch Selector Dropdown
              if (distinctBranches.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedBranch,
                      hint: Text(
                        strings.allBranchesOption,
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(
                            strings.allBranchesOption,
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        for (final b in distinctBranches)
                          DropdownMenuItem<String?>(
                            value: b,
                            child: Text(
                              b,
                              style: GoogleFonts.cairo(fontSize: 12),
                            ),
                          ),
                      ],
                      onChanged: (val) => setState(() => _selectedBranch = val),
                    ),
                  ),
                ),

              // Stock Status Pills
              _buildFilterPill(
                label: strings.filterAllStock,
                isSelected: _stockStatusFilter == 'ALL',
                onTap: () => setState(() => _stockStatusFilter = 'ALL'),
                colorScheme: colorScheme,
              ),
              _buildFilterPill(
                label: strings.filterAvailableStock,
                isSelected: _stockStatusFilter == 'AVAILABLE',
                onTap: () => setState(() => _stockStatusFilter = 'AVAILABLE'),
                colorScheme: colorScheme,
              ),
              _buildFilterPill(
                label: strings.filterLowStock,
                isSelected: _stockStatusFilter == 'LOW',
                onTap: () => setState(() => _stockStatusFilter = 'LOW'),
                colorScheme: colorScheme,
              ),
              _buildFilterPill(
                label: strings.filterOutOfStock,
                isSelected: _stockStatusFilter == 'OUT',
                onTap: () => setState(() => _stockStatusFilter = 'OUT'),
                colorScheme: colorScheme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // View Mode Switcher (3-Segment Button Group)
  // ---------------------------------------------------------------------------
  Widget _buildViewModeSwitcher({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
  }) {
    return M3ConnectedButtonGroup<int>(
      height: 44,
      borderRadius: 14,
      isExpanded: isMobile,
      segments: [
        M3ButtonSegment<int>(
          value: 0,
          icon: Icons.view_list_rounded,
          selectedIcon: Icons.view_list_rounded,
          label: strings.itemizedGiftsTab,
          tooltip: isAr
              ? 'جرد تفصيلي لكافة أصناف وهدايا الشركة مع أشرطة النفاذ المئوية'
              : 'Detailed SKU-level gift stock with depletion progress',
        ),
        M3ButtonSegment<int>(
          value: 1,
          icon: Icons.storefront_rounded,
          selectedIcon: Icons.storefront_rounded,
          label: strings.branchBreakdownTab,
          tooltip: isAr
              ? 'توزيع الأرصدة والهدايا المتبقية في كل فرع وسلسلة'
              : 'Stock balances grouped per retail branch',
        ),
        M3ButtonSegment<int>(
          value: 2,
          icon: Icons.campaign_rounded,
          selectedIcon: Icons.campaign_rounded,
          label: strings.campaignBreakdownTab,
          tooltip: isAr
              ? 'أرصدة الجوائز واستهلاكها حسب كل فعالية وحملة ترويجية'
              : 'Prize consumption per promotional campaign',
        ),
      ],
      selectedValue: _viewMode,
      onSelected: (newVal) => setState(() => _viewMode = newVal),
    );
  }

  // ---------------------------------------------------------------------------
  // Mode 0: Itemized SKU Inventory Cards & Table
  // ---------------------------------------------------------------------------
  Widget _buildItemizedGiftsView({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required List<AggregatedGiftStock> gifts,
  }) {
    return Column(
      children: [
        for (final gift in gifts)
          _buildItemizedGiftCard(
            colorScheme: colorScheme,
            strings: strings,
            isAr: isAr,
            isHi: isHi,
            isMobile: isMobile,
            gift: gift,
          ),
      ],
    );
  }

  Widget _buildItemizedGiftCard({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required AggregatedGiftStock gift,
  }) {
    final statusColor = gift.isOutOfStock
        ? const Color(0xFFB3261E)
        : (gift.isLowStock ? const Color(0xFFD97706) : const Color(0xFF006C50));
    final statusLabel = gift.isOutOfStock
        ? strings.stockDepletedBadge
        : (gift.isLowStock ? strings.stockLowBadge : strings.stockHealthyBadge);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Icon + Gift Name + Status Badge + Remaining Big Counter
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    Icons.card_giftcard_rounded,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            gift.giftName,
                            style: GoogleFonts.cairo(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                statusLabel,
                                style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (gift.eventNames.isNotEmpty)
                      Text(
                        gift.eventNames.join(' • '),
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Big Live Remaining Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '${gift.totalRemaining}',
                      style: GoogleFonts.cairo(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: statusColor,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      isAr ? 'متبقي' : 'Left',
                      style: GoogleFonts.cairo(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Middle: Metrics Row (Allocated, Claimed, Depletion Rate %)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildMetricSnippet(
                      label: isAr ? 'المخصص' : 'Allocated',
                      value: '${gift.totalAllocated}',
                      colorScheme: colorScheme,
                    ),
                    _buildMetricSnippet(
                      label: isAr ? 'المصروف' : 'Claimed',
                      value: '${gift.totalClaimed}',
                      colorScheme: colorScheme,
                    ),
                    _buildMetricSnippet(
                      label: isAr ? 'نسبة الصرف' : 'Depletion',
                      value: '${(gift.depletionRate * 100).toStringAsFixed(0)}%',
                      colorScheme: colorScheme,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: gift.depletionRate,
                    minHeight: 8,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      gift.depletionRate > 0.85
                          ? const Color(0xFFB3261E)
                          : (gift.depletionRate > 0.60
                              ? const Color(0xFFD97706)
                              : colorScheme.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom: Branch Distribution Pills
          if (gift.branchRemainingMap.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              strings.branchDistributionLabel,
              style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final entry in gift.branchRemainingMap.entries)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: entry.value <= 0
                          ? const Color(0xFFB3261E).withValues(alpha: 0.08)
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: entry.value <= 0
                            ? const Color(0xFFB3261E).withValues(alpha: 0.3)
                            : colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.store_rounded,
                          size: 13,
                          color: entry.value <= 0
                              ? const Color(0xFFB3261E)
                              : colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          entry.key,
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: entry.value <= 0
                                ? const Color(0xFFB3261E)
                                : colorScheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${entry.value}',
                            style: GoogleFonts.cairo(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricSnippet({
    required String label,
    required String value,
    required ColorScheme colorScheme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 10,
            color: colorScheme.outline,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.cairo(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Mode 1: Branch-by-Branch Breakdown & Stock Heatmap
  // ---------------------------------------------------------------------------
  Widget _buildBranchBreakdownView({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required List<EventModel> filteredEvents,
    required List<AggregatedGiftStock> gifts,
  }) {
    // Group all prizes by branch name
    final Map<String, List<Map<String, dynamic>>> branchGroups = {};

    for (final event in filteredEvents) {
      for (final prize in event.allocatedPrizes) {
        final bName = prize.branchName.trim().isNotEmpty
            ? prize.branchName.trim()
            : (prize.branchId.trim().isNotEmpty
                ? prize.branchId.trim()
                : (isAr ? 'كافة الفروع / عام' : 'All Branches / General'));

        branchGroups.putIfAbsent(bName, () => []).add({
          'eventName': event.eventName,
          'giftName': prize.name,
          'allocated': prize.allocatedQuantity,
          'remaining': prize.remainingQuantity,
          'claimed': (prize.allocatedQuantity - prize.remainingQuantity).clamp(0, prize.allocatedQuantity),
        });
      }
    }

    if (branchGroups.isEmpty) {
      return _buildEmptyState(colorScheme: colorScheme, strings: strings);
    }

    return Column(
      children: [
        for (final branchEntry in branchGroups.entries)
          _buildBranchGroupCard(
            colorScheme: colorScheme,
            strings: strings,
            isAr: isAr,
            isHi: isHi,
            isMobile: isMobile,
            branchName: branchEntry.key,
            prizesList: branchEntry.value,
          ),
      ],
    );
  }

  Widget _buildBranchGroupCard({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required String branchName,
    required List<Map<String, dynamic>> prizesList,
  }) {
    int branchAllocated = 0;
    int branchClaimed = 0;
    int branchRemaining = 0;

    for (final p in prizesList) {
      branchAllocated += (p['allocated'] as int? ?? 0);
      branchClaimed += (p['claimed'] as int? ?? 0);
      branchRemaining += (p['remaining'] as int? ?? 0);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Branch Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.storefront_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        branchName,
                        style: GoogleFonts.cairo(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        '${prizesList.length} ${isAr ? 'أصناف' : 'SKUs'} • $branchAllocated ${isAr ? 'مخصص' : 'Allocated'} • $branchClaimed ${isAr ? 'فائز' : 'Claimed'}',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Branch Summary Badges
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: branchRemaining <= 0
                        ? const Color(0xFFB3261E).withValues(alpha: 0.12)
                        : colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '$branchRemaining',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: branchRemaining <= 0
                              ? const Color(0xFFB3261E)
                              : colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isAr ? 'متبقي' : 'Left',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: branchRemaining <= 0
                              ? const Color(0xFFB3261E)
                              : colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Branch Items Table
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final p in prizesList)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.card_giftcard_rounded,
                          size: 18,
                          color: (p['remaining'] as int? ?? 0) <= 0
                              ? const Color(0xFFB3261E)
                              : colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p['giftName'] as String? ?? '',
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                p['eventName'] as String? ?? '',
                                style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  color: colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildBranchQtyPill(
                          label: isAr ? 'المخصص' : 'Allocated',
                          value: '${p['allocated']}',
                          color: colorScheme.onSurfaceVariant,
                          colorScheme: colorScheme,
                        ),
                        const SizedBox(width: 6),
                        _buildBranchQtyPill(
                          label: isAr ? 'المصروف' : 'Claimed',
                          value: '${p['claimed']}',
                          color: colorScheme.secondary,
                          colorScheme: colorScheme,
                        ),
                        const SizedBox(width: 6),
                        _buildBranchQtyPill(
                          label: isAr ? 'المتبقي' : 'Left',
                          value: '${p['remaining']}',
                          color: (p['remaining'] as int? ?? 0) <= 0
                              ? const Color(0xFFB3261E)
                              : const Color(0xFF006C50),
                          isHighlight: true,
                          colorScheme: colorScheme,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchQtyPill({
    required String label,
    required String value,
    required Color color,
    bool isHighlight = false,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isHighlight
            ? color.withValues(alpha: 0.12)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1.1,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 8,
              color: colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mode 2: Campaign-by-Campaign Breakdown
  // ---------------------------------------------------------------------------
  Widget _buildCampaignBreakdownView({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required List<EventModel> filteredEvents,
  }) {
    return Column(
      children: [
        for (final event in filteredEvents)
          _buildCampaignGroupCard(
            colorScheme: colorScheme,
            strings: strings,
            isAr: isAr,
            isHi: isHi,
            isMobile: isMobile,
            event: event,
          ),
      ],
    );
  }

  Widget _buildCampaignGroupCard({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required EventModel event,
  }) {
    int campaignAllocated = 0;
    int campaignRemaining = 0;

    for (final p in event.allocatedPrizes) {
      campaignAllocated += p.allocatedQuantity;
      campaignRemaining += p.remainingQuantity;
    }
    final int campaignClaimed = (campaignAllocated - campaignRemaining).clamp(0, campaignAllocated);
    final double depletion = campaignAllocated > 0
        ? (campaignClaimed / campaignAllocated).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    event.gameType == 'scratch'
                        ? Icons.content_cut_rounded
                        : (event.gameType == 'direct'
                            ? Icons.card_giftcard_rounded
                            : Icons.rotate_right_rounded),
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.eventName,
                        style: GoogleFonts.cairo(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        '${event.targetCompany} • ${event.retailChainName.isNotEmpty ? event.retailChainName : (isAr ? 'كافة السلاسل' : 'All Chains')}',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Depletion Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${(depletion * 100).toStringAsFixed(0)}% ${strings.depletionRateLabel}',
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Items inside campaign
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (event.allocatedPrizes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      isAr ? 'لم يتم تكويد هدايا مخصصة لهذه الحملة بعد.' : 'No prizes allocated yet.',
                      style: GoogleFonts.cairo(
                        color: colorScheme.outline,
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  for (final prize in event.allocatedPrizes)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.card_giftcard_rounded,
                            size: 18,
                            color: prize.remainingQuantity <= 0
                                ? const Color(0xFFB3261E)
                                : colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  prize.name,
                                  style: GoogleFonts.cairo(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                if (prize.branchName.isNotEmpty)
                                  Text(
                                    prize.branchName,
                                    style: GoogleFonts.cairo(
                                      fontSize: 10,
                                      color: colorScheme.outline,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          _buildBranchQtyPill(
                            label: isAr ? 'المخصص' : 'Allocated',
                            value: '${prize.allocatedQuantity}',
                            color: colorScheme.onSurfaceVariant,
                            colorScheme: colorScheme,
                          ),
                          const SizedBox(width: 6),
                          _buildBranchQtyPill(
                            label: isAr ? 'المصروف' : 'Claimed',
                            value: '${(prize.allocatedQuantity - prize.remainingQuantity).clamp(0, prize.allocatedQuantity)}',
                            color: colorScheme.secondary,
                            colorScheme: colorScheme,
                          ),
                          const SizedBox(width: 6),
                          _buildBranchQtyPill(
                            label: isAr ? 'المتبقي' : 'Left',
                            value: '${prize.remainingQuantity}',
                            color: prize.remainingQuantity <= 0
                                ? const Color(0xFFB3261E)
                                : const Color(0xFF006C50),
                            isHighlight: true,
                            colorScheme: colorScheme,
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty State
  // ---------------------------------------------------------------------------
  Widget _buildEmptyState({
    required ColorScheme colorScheme,
    required AppStrings strings,
  }) {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 48,
            color: colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            strings.noGiftsFoundMsg,
            style: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
