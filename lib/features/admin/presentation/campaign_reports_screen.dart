import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:excel/excel.dart' hide Border;
import '../../../core/services/firebase_service.dart';
import '../../../core/services/retail_chains_service.dart';
import '../../../core/services/chain_products_intelligence_service.dart';
import '../domain/retail_chain_model.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/constants/country_currency_config.dart';
import '../../../core/widgets/switch_point_branding.dart';
import '../../../core/widgets/m3_button_groups.dart';
import '../domain/event_model.dart';
import '../../../core/utils/file_download_helper.dart';
import '../../../core/utils/arabic_numbers_utils.dart';
import '../../../core/widgets/portal_screen_header_card.dart';
import 'widgets/branch_chain_analytics_charts.dart';


/// High-performance data structure for memoized report analytics
class _ReportAggregationResult {
  final int totalScans;
  final int acceptedInvoices;
  final int rejectedInvoices;
  final double totalSalesVolume;
  final int totalUnitsSold;
  final List<_ProductStat> sortedProducts;
  final List<_BranchStat> sortedBranches;
  final List<_BranchStat> sortedChains;
  final String topProductName;

  const _ReportAggregationResult({
    required this.totalScans,
    required this.acceptedInvoices,
    required this.rejectedInvoices,
    required this.totalSalesVolume,
    required this.totalUnitsSold,
    required this.sortedProducts,
    required this.sortedBranches,
    required this.sortedChains,
    required this.topProductName,
  });
}

/// Comprehensive Reports & Analytics Screen (منظومة التقارير والتحليلات الشاملة)
/// Adheres strictly to Material Design 3, M3 Button Groups, Trilingual Localization,
/// and Event-Scoped Analytics breakdowns.
class CampaignReportsScreen extends ConsumerStatefulWidget {
  final EventModel? initialEvent;
  final String? lockedCompanySlug;
  final String? lockedCompanyName;
  final bool isEmbedded;
  final VoidCallback? onBack;

  const CampaignReportsScreen({
    super.key,
    this.initialEvent,
    this.lockedCompanySlug,
    this.lockedCompanyName,
    this.isEmbedded = false,
    this.onBack,
  });

  @override
  ConsumerState<CampaignReportsScreen> createState() => _CampaignReportsScreenState();
}

class _CampaignReportsScreenState extends ConsumerState<CampaignReportsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Selected Event: null means "All Campaigns / جميع الحملات"
  EventModel? _selectedEvent;
  int _selectedTab = 0; // 0: Products, 1: Branches

  final TextEditingController _productSearchController = TextEditingController();
  String _productSortBy = 'QTY'; // 'QTY', 'REVENUE', 'NAME'
  bool _onlyCompanyProductsFilter = true; // Strict company products filtering

  // Memoization cache for lightning-fast UI rendering
  _ReportAggregationResult? _cachedMetrics;
  String? _lastMetricsCacheKey;

  // Branch & Retail Chain Analytics Controls
  String _branchAggregationLevel = 'BRANCH'; // 'BRANCH' vs 'CHAIN'
  String _branchChartViewMode = 'DONUT'; // 'DONUT', 'BAR', 'LIST'
  String _branchMetricDimension = 'REVENUE'; // 'REVENUE' vs 'COUNT'

  // Pagination Constants & State (25 items per page / load)
  static const int _reportPageSize = 25;
  int _productsCurrentPage = 0;
  int _productsMobileLimit = _reportPageSize;
  int _branchesCurrentPage = 0;
  int _branchesMobileLimit = _reportPageSize;

  @override
  void initState() {
    super.initState();
    _selectedEvent = widget.initialEvent;
  }

  @override
  void didUpdateWidget(covariant CampaignReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialEvent != oldWidget.initialEvent) {
      setState(() {
        _selectedEvent = widget.initialEvent;
      });
    }
  }

  @override
  void dispose() {
    _productSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    FirebaseFirestore? firestore;
    try {
      firestore = ref.watch(firestoreProvider);
    } catch (_) {
      firestore = null;
    }
    final strings = AppStrings.of(ref);
    final isAr = ref.isArabic;
    final isHi = ref.isHindi;
    final activeCountry = ref.watch(activeCountryProvider);

    final content = _buildReportsBody(
      context: context,
      firestore: firestore,
      colorScheme: colorScheme,
      strings: strings,
      isAr: isAr,
      isHi: isHi,
      activeCountry: activeCountry,
    );

    if (widget.isEmbedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: SwitchPointHeader(
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

  Widget _buildReportsBody({
    required BuildContext context,
    required FirebaseFirestore? firestore,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required CountryCurrency activeCountry,
  }) {
    if (firestore == null) {
      return _buildReportsViewContent(
        context: context,
        colorScheme: colorScheme,
        strings: strings,
        isAr: isAr,
        isHi: isHi,
        activeCountry: activeCountry,
        scopedEvents: const [],
        filteredTransactions: const [],
      );
    }

    Stream<List<BranchModel>> branchesStream;
    try {
      branchesStream = ref.watch(retailChainsServiceProvider).getAllBranchesStream();
    } catch (_) {
      branchesStream = Stream.value([]);
    }

    return StreamBuilder<List<BranchModel>>(
      stream: branchesStream,
      builder: (context, branchesSnapshot) {
        final dbBranches = branchesSnapshot.data ?? [];
        final isLocked = widget.lockedCompanySlug != null && widget.lockedCompanySlug!.isNotEmpty;

        Query eventsQuery = firestore.collection('events');
        if (isLocked) {
          eventsQuery = eventsQuery.where('companySlug', isEqualTo: widget.lockedCompanySlug);
        }

        return StreamBuilder<QuerySnapshot>(
          stream: eventsQuery.snapshots(),
          builder: (context, eventsSnapshot) {
            final allEvents = (eventsSnapshot.data?.docs ?? [])
                .map((doc) => EventModel.fromFirestore(doc))
                .toList();

            // Scope events if lockedCompanySlug is present
            final scopedEvents = isLocked
                ? allEvents.where((e) {
                    final matchSlug = e.companySlug.toLowerCase() == widget.lockedCompanySlug!.toLowerCase();
                    final matchName = widget.lockedCompanyName != null &&
                        widget.lockedCompanyName!.isNotEmpty &&
                        e.targetCompany.toLowerCase() == widget.lockedCompanyName!.toLowerCase();
                    return matchSlug || matchName;
                  }).toList()
                : allEvents;

            // If an initialEvent was provided with an ID, sync it with real-time events list
            if (_selectedEvent != null && scopedEvents.isNotEmpty) {
              final matched = scopedEvents.where((e) => e.id == _selectedEvent!.id);
              if (matched.isNotEmpty) {
                _selectedEvent = matched.first;
              }
            }

            Query transactionsQuery = firestore.collection('receipts_transactions');
            if (_selectedEvent != null) {
              transactionsQuery = transactionsQuery.where('campaignId', isEqualTo: _selectedEvent!.id);
            } else if (isLocked) {
              transactionsQuery = transactionsQuery.where('companySlug', isEqualTo: widget.lockedCompanySlug);
            }

            return StreamBuilder<QuerySnapshot>(
              stream: transactionsQuery.snapshots(),
              builder: (context, transactionsSnapshot) {
                if (transactionsSnapshot.connectionState == ConnectionState.waiting && !transactionsSnapshot.hasData && _cachedMetrics == null) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: colorScheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          isAr ? 'جاري تحميل التقارير والبيانات الإحصائية...' : (isHi ? 'डेटा लोड हो रहा है...' : 'Loading analytics & reports...'),
                          style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                  );
                }

                final allTransactions = transactionsSnapshot.data?.docs ?? [];

                // Filter transactions according to selected event or locked company
                final filteredTransactions = allTransactions.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final cId = data['campaignId']?.toString() ?? '';
                  final cSlug = data['companySlug']?.toString() ?? '';
                  final compName = data['companyName']?.toString() ?? '';
                  final targetComp = data['target_company']?.toString() ?? '';

                  if (_selectedEvent != null) {
                    if (cId.isNotEmpty) {
                      return cId == _selectedEvent!.id;
                    }
                    if (_selectedEvent!.companySlug.isNotEmpty && cSlug.toLowerCase() == _selectedEvent!.companySlug.toLowerCase()) {
                      return true;
                    }
                    if (_selectedEvent!.targetCompany.isNotEmpty &&
                        (compName.toLowerCase() == _selectedEvent!.targetCompany.toLowerCase() ||
                            targetComp.toLowerCase() == _selectedEvent!.targetCompany.toLowerCase())) {
                      return true;
                    }
                    return false;
                  }

                  if (widget.lockedCompanySlug != null && widget.lockedCompanySlug!.isNotEmpty) {
                    final isSlugMatch = cSlug.toLowerCase() == widget.lockedCompanySlug!.toLowerCase();
                    final isNameMatch = widget.lockedCompanyName != null &&
                        widget.lockedCompanyName!.isNotEmpty &&
                        (compName.toLowerCase() == widget.lockedCompanyName!.toLowerCase() ||
                            targetComp.toLowerCase() == widget.lockedCompanyName!.toLowerCase());
                    final isScopedEventMatch = scopedEvents.any((e) => e.id == cId);
                    return isSlugMatch || isNameMatch || isScopedEventMatch;
                  }
                  return true;
                }).toList();

                return _buildReportsViewContent(
                  context: context,
                  colorScheme: colorScheme,
                  strings: strings,
                  isAr: isAr,
                  isHi: isHi,
                  activeCountry: activeCountry,
                  scopedEvents: scopedEvents,
                  filteredTransactions: filteredTransactions,
                  dbBranches: dbBranches,
                );
              },
            );
          },
        );
      },
    );
  }

  /// Memoized computation of report metrics & aggregations (Ultra-Fast O(1) cache on rebuilds)
  _ReportAggregationResult _computeMetrics({
    required List<QueryDocumentSnapshot> filteredTransactions,
    required List<EventModel> scopedEvents,
    required List<BranchModel> dbBranches,
    required bool isAr,
    required bool isHi,
    required bool effectiveFilterCompanyOnly,
    required String productSortBy,
  }) {
    final firstId = filteredTransactions.isNotEmpty ? filteredTransactions.first.id : '';
    final lastId = filteredTransactions.isNotEmpty ? filteredTransactions.last.id : '';
    final cacheKey = '${filteredTransactions.length}_${firstId}_${lastId}_${productSortBy}_${effectiveFilterCompanyOnly}_${_selectedEvent?.id}_$isAr';

    if (_cachedMetrics != null && _lastMetricsCacheKey == cacheKey) {
      return _cachedMetrics!;
    }

    int totalScans = filteredTransactions.length;
    int acceptedInvoices = 0;
    int rejectedInvoices = 0;
    double totalSalesVolume = 0.0;
    int totalUnitsSold = 0;
    final Map<String, _ProductStat> productStatsMap = {};
    final Map<String, _BranchStat> branchStatsMap = {};
    final Map<String, _BranchStat> chainStatsMap = {};

    final allKnownBranches = _selectedEvent != null
        ? _selectedEvent!.branchNames
        : scopedEvents.expand((e) => e.branchNames).toSet().toList();

    for (final doc in filteredTransactions) {
      final data = doc.data() as Map<String, dynamic>;
      final bool isExplicitlyValid = data['is_valid'] == true || data['status'] == 'accepted' || data['isValid'] == true;
      final bool isExplicitlyRejected = data['is_valid'] == false || data['status'] == 'rejected' || data['isValid'] == false || ((data['unfulfilled_conditions'] as List?)?.isNotEmpty ?? false);
      final bool isValid = isExplicitlyValid || (!isExplicitlyRejected && ((data['unfulfilled_conditions'] as List?)?.isEmpty ?? true));

      if (isValid) {
        acceptedInvoices++;
        final spendVal = (data['target_company_total'] ?? data['total_value'] as num?)?.toDouble() ?? 0.0;
        totalSalesVolume += spendVal;

        // Smart Branch aggregation with canonical matching & deduplication
        final rawBranch = (data['branch_detected'] ?? data['branchName'] ?? data['store_chain_detected'] ?? '').toString().trim();
        final effectiveBranch = _normalizeBranchName(
          rawBranch,
          allKnownBranches,
          isAr,
          dbBranches: dbBranches,
        );
        if (!branchStatsMap.containsKey(effectiveBranch)) {
          branchStatsMap[effectiveBranch] = _BranchStat(branchName: effectiveBranch);
        }
        branchStatsMap[effectiveBranch]!.receiptCount++;
        branchStatsMap[effectiveBranch]!.totalRevenue += spendVal;

        // Smart Retail Chain Consolidation
        final rawStoreChain = (data['store_chain_detected'] ?? data['retail_chain'] ?? data['branch_detected'] ?? rawBranch).toString().trim();
        final canonicalChain = ChainProductsIntelligenceService.normalizeRetailChain(rawStoreChain.isNotEmpty ? rawStoreChain : effectiveBranch);
        if (!chainStatsMap.containsKey(canonicalChain)) {
          chainStatsMap[canonicalChain] = _BranchStat(branchName: canonicalChain);
        }
        chainStatsMap[canonicalChain]!.receiptCount++;
        chainStatsMap[canonicalChain]!.totalRevenue += spendVal;

        // Product aggregation
        final rawProducts = data['extracted_products'];
        if (rawProducts is List) {
          for (final p in rawProducts) {
            if (p is Map) {
              final name = p['name']?.toString().trim() ?? (isAr ? 'منتج غير معروف' : 'Unknown Item');
              if (name.isEmpty) continue;

              final qty = (p['quantity'] as num?)?.toInt() ?? 1;
              final price = (p['price'] as num?)?.toDouble() ?? 0.0;
              final isTarget = p['isTargetCompany'] == true;
              final barcode = p['barcode']?.toString().trim() ?? '';

              // Strict company product filtering when scoped
              if (effectiveFilterCompanyOnly && !isTarget) {
                continue;
              }

              totalUnitsSold += qty;

              if (!productStatsMap.containsKey(name)) {
                productStatsMap[name] = _ProductStat(
                  name: name,
                  totalQty: 0,
                  totalRevenue: 0.0,
                  isTargetCompany: isTarget,
                  barcode: barcode,
                );
              }
              productStatsMap[name]!.totalQty += qty;
              productStatsMap[name]!.totalRevenue += (price * qty);
              if (barcode.isNotEmpty && productStatsMap[name]!.barcode.isEmpty) {
                productStatsMap[name]!.barcode = barcode;
              }
            }
          }
        }
      } else {
        rejectedInvoices++;
      }
    }

    final sortedProducts = productStatsMap.values.toList();
    if (productSortBy == 'QTY') {
      sortedProducts.sort((a, b) => b.totalQty.compareTo(a.totalQty));
    } else if (productSortBy == 'REVENUE') {
      sortedProducts.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
    } else {
      sortedProducts.sort((a, b) => a.name.compareTo(b.name));
    }

    final sortedBranches = branchStatsMap.values.toList()
      ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

    final sortedChains = chainStatsMap.values.toList()
      ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

    final String topProductName = sortedProducts.isNotEmpty
        ? sortedProducts.first.name
        : (isAr ? 'لا توجد منتجات مسجلة' : (isHi ? 'कोई उत्पाद नहीं' : 'No items recorded'));

    _cachedMetrics = _ReportAggregationResult(
      totalScans: totalScans,
      acceptedInvoices: acceptedInvoices,
      rejectedInvoices: rejectedInvoices,
      totalSalesVolume: totalSalesVolume,
      totalUnitsSold: totalUnitsSold,
      sortedProducts: sortedProducts,
      sortedBranches: sortedBranches,
      sortedChains: sortedChains,
      topProductName: topProductName,
    );
    _lastMetricsCacheKey = cacheKey;
    return _cachedMetrics!;
  }

  Widget _buildReportsViewContent({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required CountryCurrency activeCountry,
    required List<EventModel> scopedEvents,
    required List<QueryDocumentSnapshot> filteredTransactions,
    List<BranchModel> dbBranches = const [],
  }) {
    final String effectiveCompanySlug = widget.lockedCompanySlug?.isNotEmpty == true
        ? widget.lockedCompanySlug!
        : (_selectedEvent?.companySlug ?? '');
    final String effectiveCompanyName = widget.lockedCompanyName?.isNotEmpty == true
        ? widget.lockedCompanyName!
        : (_selectedEvent?.targetCompany ?? effectiveCompanySlug);

    final bool isLockedToCompany = widget.lockedCompanySlug != null && widget.lockedCompanySlug!.isNotEmpty;
    final bool effectiveFilterCompanyOnly = isLockedToCompany || _onlyCompanyProductsFilter;

    // Use memoized metrics computation
    final metrics = _computeMetrics(
      filteredTransactions: filteredTransactions,
      scopedEvents: scopedEvents,
      dbBranches: dbBranches,
      isAr: isAr,
      isHi: isHi,
      effectiveFilterCompanyOnly: effectiveFilterCompanyOnly,
      productSortBy: _productSortBy,
    );

    final int totalScans = metrics.totalScans;
    final int acceptedInvoices = metrics.acceptedInvoices;
    final int rejectedInvoices = metrics.rejectedInvoices;
    final double totalSalesVolume = metrics.totalSalesVolume;
    final int totalUnitsSold = metrics.totalUnitsSold;
    final List<_ProductStat> sortedProducts = metrics.sortedProducts;
    final List<_BranchStat> sortedBranches = metrics.sortedBranches;
    final List<_BranchStat> sortedChains = metrics.sortedChains;
    final String topProductName = metrics.topProductName;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;
        final isMobile = constraints.maxWidth < 700;
        final isCompact = constraints.maxWidth < 960;
        final stickyHeight = _computeStickyHeaderHeight(
          selectedTab: _selectedTab,
          isCompact: isCompact,
          isLockedToCompany: isLockedToCompany,
        );

        return CustomScrollView(
          shrinkWrap: constraints.maxHeight.isInfinite,
          physics: const BouncingScrollPhysics(),
          slivers: [
            // 1. Scrollable Upper Overview Section (Header + Campaign Info + KPI Cards)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 12 : 20,
                  isMobile ? 12 : 20,
                  isMobile ? 12 : 20,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Unified Header Bar with Event Selector & Export Excel Action
                    _buildHeaderCard(
                      context: context,
                      colorScheme: colorScheme,
                      strings: strings,
                      isAr: isAr,
                      isHi: isHi,
                      allEvents: scopedEvents,
                      effectiveSlug: effectiveCompanySlug,
                      effectiveCompanyName: effectiveCompanyName,
                      filteredTransactions: filteredTransactions,
                      isMobile: isMobile,
                      onExport: () => _exportAnalyticsExcel(
                        context: context,
                        filteredTransactions: filteredTransactions,
                        sortedProducts: sortedProducts,
                        sortedBranches: sortedBranches,
                        effectiveCompanyName: effectiveCompanyName.isNotEmpty ? effectiveCompanyName : 'Tashil_Gift',
                        isAr: isAr,
                        activeCountry: activeCountry,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Active Campaign Information Card (if a specific campaign is selected)
                    if (_selectedEvent != null) ...[
                      _CampaignEventDetailsCard(
                        event: _selectedEvent!,
                        colorScheme: colorScheme,
                        activeCountry: activeCountry,
                        isAr: isAr,
                        isHi: isHi,
                        isMobile: isMobile,
                      ),
                      const SizedBox(height: 14),
                    ],

                    // M3 High-Impact KPI Metric Cards Grid
                    _buildKpiMetricsGrid(
                      context: context,
                      colorScheme: colorScheme,
                      strings: strings,
                      isAr: isAr,
                      isHi: isHi,
                      activeCountry: activeCountry,
                      totalScans: totalScans,
                      acceptedInvoices: acceptedInvoices,
                      rejectedInvoices: rejectedInvoices,
                      totalSalesVolume: totalSalesVolume,
                      totalUnitsSold: totalUnitsSold,
                      topProductName: topProductName,
                      isWide: isWide,
                      effectiveFilterCompanyOnly: effectiveFilterCompanyOnly,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // 2. PINNED STICKY HEADER DELEGATE (Tabs + Contextual Search/Sort/Filter Bar)
            SliverPersistentHeader(
              pinned: true,
              delegate: _StickyReportsHeaderDelegate(
                height: stickyHeight,
                child: _buildStickyControlsSection(
                  context: context,
                  colorScheme: colorScheme,
                  strings: strings,
                  isAr: isAr,
                  isHi: isHi,
                  productsCount: sortedProducts.length,
                  branchesCount: sortedBranches.length,
                  isMobile: isMobile,
                  isCompact: isCompact,
                  isLockedToCompany: isLockedToCompany,
                  isPinned: true,
                ),
              ),
            ),

            // 3. Scrollable Active Tab View Content
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 12 : 20,
                  14,
                  isMobile ? 12 : 20,
                  isMobile ? 24 : 36,
                ),
                child: _selectedTab == 0
                    ? _buildProductsBreakdownTab(
                        sortedProducts: sortedProducts,
                        colorScheme: colorScheme,
                        strings: strings,
                        isAr: isAr,
                        isHi: isHi,
                        activeCountry: activeCountry,
                        isMobile: isMobile,
                        isLockedToCompany: isLockedToCompany,
                      )
                    : _buildBranchesBreakdownTab(
                        sortedBranches: sortedBranches,
                        sortedChains: sortedChains,
                        totalSales: totalSalesVolume,
                        totalReceipts: acceptedInvoices,
                        colorScheme: colorScheme,
                        strings: strings,
                        isAr: isAr,
                        isHi: isHi,
                        activeCountry: activeCountry,
                        isMobile: isMobile,
                      ),
              ),
            ),
          ],
        );
      },
    );
  }



    // ---------------------------------------------------------------------------
  // 1. Header Card with Event Selector & Export CSV & AI Discovery
  // ---------------------------------------------------------------------------
  Widget _buildHeaderCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required List<EventModel> allEvents,
    required String effectiveSlug,
    required String effectiveCompanyName,
    required List<QueryDocumentSnapshot> filteredTransactions,
    required VoidCallback onExport,
    required bool isMobile,
  }) {
    return PortalScreenHeaderCard(
      icon: Icons.analytics_rounded,
      title: strings.analyticsTitle,
      subtitle: isAr
          ? 'تحليل مبيعات الأصناف، أداء الفعاليات، وتوزيع الفروع والسلاسل'
          : (isHi ? 'उत्पाद बिक्री विश्लेषण, अभियान प्रदर्शन और शाखा वितरण' : 'Sales performance, top product rankings, and branch analytics'),
      events: allEvents,
      selectedEventId: _selectedEvent?.id,
      onEventChanged: (val) {
        setState(() {
          if (val == null || val == 'ALL' || val == 'all') {
            _selectedEvent = null;
          } else {
            _selectedEvent = allEvents.where((e) => e.id == val).firstOrNull;
          }
        });
      },
      lockedCompanySlug: widget.lockedCompanySlug,
      isMobile: isMobile,
      actions: [
        FilledButton.tonalIcon(
          onPressed: onExport,
          icon: const Icon(Icons.table_chart_rounded, size: 18),
          label: Text(
            strings.exportExcelCsv,
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }



  // ---------------------------------------------------------------------------
  // Canonical Branch Name Normalization Helpers
  // ---------------------------------------------------------------------------
  static String _normalizeBranchName(
    String rawBranch,
    List<String> canonicalBranches,
    bool isAr, {
    List<BranchModel> dbBranches = const [],
  }) {
    final clean = rawBranch.trim();
    if (clean.isEmpty) return isAr ? 'فرع غير محدد' : 'Unspecified Branch';

    // 1. Direct match against campaign canonical branches
    for (final canonical in canonicalBranches) {
      if (_isBranchMatch(clean, canonical)) {
        return canonical;
      }
    }

    // 2. Resolve via dbBranches by code, storeId, or branchName
    if (dbBranches.isNotEmpty) {
      final englishClean = clean.toEnglishDigits();

      // Extract candidate codes (e.g. from "Store: 418", "فرع كود 418", "كود 418", "418")
      final candidateCodes = <String>{};
      final codeMatches = RegExp(
        r'(?:store|كود|فرع|pos)?[\s:]*([0-9a-zA-Z\-]+)',
        caseSensitive: false,
      ).allMatches(englishClean);

      for (final m in codeMatches) {
        final val = m.group(1)?.trim();
        if (val != null &&
            val.isNotEmpty &&
            val.toLowerCase() != 'فرع' &&
            val.toLowerCase() != 'كود' &&
            val.toLowerCase() != 'store' &&
            val.toLowerCase() != 'pos') {
          candidateCodes.add(val.toLowerCase());
        }
      }

      final digitMatch = RegExp(r'\b\d+\b').firstMatch(englishClean);
      if (digitMatch != null) {
        candidateCodes.add(digitMatch.group(0)!);
      }

      for (final branch in dbBranches) {
        final bCode = branch.branchCode.trim().toLowerCase().toEnglishDigits();
        final storeId = (branch.receiptSignature?.storeId ?? '').trim().toLowerCase().toEnglishDigits();
        final bName = branch.branchName.trim();

        bool isCodeMatched = false;
        if (candidateCodes.isNotEmpty) {
          if (bCode.isNotEmpty && bCode != '0' && bCode != 'def' && candidateCodes.contains(bCode)) {
            isCodeMatched = true;
          }
          if (storeId.isNotEmpty && storeId != '0' && candidateCodes.contains(storeId)) {
            isCodeMatched = true;
          }
        }

        if (isCodeMatched || _isBranchMatch(clean, bName)) {
          // If this DB branch matches one of the canonical branches in the event, return that canonical branch
          for (final canonical in canonicalBranches) {
            if (_isBranchMatch(bName, canonical) ||
                (bCode.isNotEmpty && canonical.toEnglishDigits().contains(bCode)) ||
                (storeId.isNotEmpty && canonical.toEnglishDigits().contains(storeId))) {
              return canonical;
            }
          }
          return _standardizeBranchName(bName);
        }
      }
    }

    // 3. Fallback: normalize store code variations if unmatched (e.g. "Store: 418" / "فرع 418 :Store" -> "فرع كود 418")
    final englishDigitsStr = clean.toEnglishDigits();
    final codeRegex = RegExp(r'(?:store|كود|فرع|pos)[\s:]*(\d+)|(\d+)[\s:]*(?:store|كود|فرع|pos)', caseSensitive: false);
    final match = codeRegex.firstMatch(englishDigitsStr);
    if (match != null) {
      final codeNum = match.group(1) ?? match.group(2);
      if (codeNum != null && codeNum.isNotEmpty) {
        // Check if any canonical branch contains this code
        for (final canonical in canonicalBranches) {
          if (canonical.toEnglishDigits().contains(codeNum)) {
            return canonical;
          }
        }
        return 'فرع كود $codeNum';
      }
    }

    // 4. Standardize formatting
    return _standardizeBranchName(clean);
  }

  static bool _isBranchMatch(String a, String b) {
    final normA = _cleanBranchForComparison(a);
    final normB = _cleanBranchForComparison(b);
    if (normA.isEmpty || normB.isEmpty) return false;
    return normA == normB || normA.contains(normB) || normB.contains(normA);
  }

  static String _cleanBranchForComparison(String s) {
    String str = s.toLowerCase().trim();
    str = str.replaceAll(RegExp(r'[\u064B-\u065F]'), ''); // diacritics
    str = str.replaceAll(RegExp(r'[أإآ]'), 'ا');
    str = str.replaceAll('ة', 'ه');
    str = str.replaceAll('ى', 'ي');
    str = str.replaceAll(RegExp(r'\(.*?\)'), ''); // remove city in parentheses
    str = str.replaceAll(RegExp(r'^(فرع|branch|مفرع)\s+'), ''); // remove prefix
    str = str.replaceAll(RegExp(r'\s+'), ' ').trim();
    return str;
  }

  static String _standardizeBranchName(String raw) {
    String clean = raw.trim();
    if (!clean.startsWith('فرع ') &&
        !clean.toLowerCase().startsWith('branch ') &&
        !clean.startsWith('سلسلة ')) {
      return 'فرع $clean';
    }
    return clean;
  }

  // ---------------------------------------------------------------------------
  // 3. M3 High-Impact KPI Stat Cards Grid
  // ---------------------------------------------------------------------------
  Widget _buildKpiMetricsGrid({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required CountryCurrency activeCountry,
    required int totalScans,
    required int acceptedInvoices,
    required int rejectedInvoices,
    required double totalSalesVolume,
    required int totalUnitsSold,
    required String topProductName,
    required bool isWide,
    required bool effectiveFilterCompanyOnly,
  }) {
    final acceptanceRate = totalScans > 0 ? ((acceptedInvoices / totalScans) * 100).toStringAsFixed(0) : '100';

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        int crossAxisCount = 4;
        double childAspectRatio = 1.65;
        if (width < 600) {
          crossAxisCount = 1;
          childAspectRatio = 2.3;
        } else if (width < 960) {
          crossAxisCount = 2;
          childAspectRatio = 1.85;
        }

        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: childAspectRatio,
          children: [
            // Card 1: Accepted Invoices
            _buildStatKpiCard(
              title: strings.metricAcceptedInvoices,
              value: '$acceptedInvoices',
              subtitle: isAr ? 'من إجمالي $totalScans فاتورة مفحوصة' : 'out of $totalScans total scanned',
              icon: Icons.receipt_long_rounded,
              accentColor: Colors.blue.shade700,
              badgeText: '$acceptanceRate% ${isAr ? "مقبول" : "valid"}',
              colorScheme: colorScheme,
              tooltip: isAr ? 'عدد الفواتير المستوفية لكافة الشروط والحد الأدنى' : 'Count of validated receipts meeting campaign rules',
            ),

            // Card 2: Total Sales Volume
            _buildStatKpiCard(
              title: strings.metricTotalSalesVolume,
              value: '${totalSalesVolume.toStringAsFixed(1)} ${activeCountry.currencySymbol}',
              subtitle: isAr ? 'مبيعات منتجات العرض المعتمدة' : 'Total promotional target revenue',
              icon: Icons.payments_rounded,
              accentColor: Colors.teal.shade700,
              badgeText: activeCountry.nameAr,
              colorScheme: colorScheme,
              tooltip: isAr ? 'إجمالي المبيعات المحققة لمنتجات الحملة بالعُملة المحلية' : 'Total sales volume for verified promotional purchases',
            ),

            // Card 3: Total Units Sold
            _buildStatKpiCard(
              title: isAr ? 'عدد المنتجات المباعة' : (isHi ? 'बेचे गए कुल उत्पाद' : 'Total Units Sold'),
              value: '$totalUnitsSold',
              subtitle: isAr
                  ? (effectiveFilterCompanyOnly ? 'إجمالي قطع منتجات الشركة بالفواتير' : 'إجمالي القطع المستخرجة بالفواتير')
                  : (isHi ? 'कुल उत्पाद इकाइयाँ' : 'Promotional items sold'),
              icon: Icons.inventory_2_rounded,
              accentColor: Colors.purple.shade700,
              badgeText: isAr ? 'قطع مباعة' : 'Units',
              colorScheme: colorScheme,
              tooltip: isAr
                  ? (effectiveFilterCompanyOnly ? 'إجمالي كميات منتجات الشركة المعتمدة في كافة الفواتير' : 'إجمالي كميات الأصناف المشتراة في كافة الفواتير')
                  : 'Total quantity of items purchased',
            ),

            // Card 4: Top Performing Product
            _buildStatKpiCard(
              title: isAr ? 'الأعلى مبيعاً وطلباً' : (isHi ? 'शीर्ष उत्पाद' : 'Top Performing Item'),
              value: topProductName,
              subtitle: isAr ? 'الصنف صاحب أعلى معدل شراء' : 'Highest quantity purchased item',
              icon: Icons.emoji_events_rounded,
              accentColor: Colors.amber.shade800,
              badgeText: '🏆 #1',
              colorScheme: colorScheme,
              tooltip: isAr ? 'المنتج الأكثر تكراراً وطلباً في الفواتير المقبولة' : 'The #1 most purchased product in this campaign',
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required String badgeText,
    required ColorScheme colorScheme,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accentColor, size: 18),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badgeText,
                    style: GoogleFonts.cairo(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      value,
                      style: GoogleFonts.cairo(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: colorScheme.onSurface,
                        letterSpacing: -0.3,
                        height: 1.1,
                      ),
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: GoogleFonts.cairo(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                      height: 1.15,
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
    );
  }

  // ---------------------------------------------------------------------------
  // 4. Sticky Header Computation & Controls Section
  // ---------------------------------------------------------------------------
  double _computeStickyHeaderHeight({
    required int selectedTab,
    required bool isCompact,
    required bool isLockedToCompany,
  }) {
    if (selectedTab == 0) {
      return isCompact ? 172.0 : 130.0;
    } else {
      return isCompact ? 130.0 : 130.0;
    }
  }

  Widget _buildStickyControlsSection({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required int productsCount,
    required int branchesCount,
    required bool isMobile,
    required bool isCompact,
    required bool isLockedToCompany,
    required bool isPinned,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: isPinned ? 0.95 : 1.0),
        boxShadow: isPinned
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
        border: isPinned
            ? Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  width: 1,
                ),
              )
            : null,
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: isPinned
              ? ImageFilter.blur(sigmaX: 12, sigmaY: 12)
              : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 20,
              vertical: isMobile ? 10 : 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Navigation / Segmented Button Tabs
                _buildTabsSelector(
                  colorScheme: colorScheme,
                  strings: strings,
                  isAr: isAr,
                  isHi: isHi,
                  productsCount: productsCount,
                  branchesCount: branchesCount,
                  isMobile: isMobile,
                ),

                // 2. Active Tab Toolbar (Search, Sort, Filters)
                if (_selectedTab == 0) ...[
                  SizedBox(height: isMobile ? 8 : 10),
                  _buildProductsToolbar(
                    colorScheme: colorScheme,
                    strings: strings,
                    isAr: isAr,
                    isHi: isHi,
                    isCompact: isCompact,
                    isLockedToCompany: isLockedToCompany,
                  ),
                ] else ...[
                  SizedBox(height: isMobile ? 8 : 10),
                  _buildBranchesToolbar(
                    colorScheme: colorScheme,
                    strings: strings,
                    isAr: isAr,
                    isCompact: isCompact,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductsToolbar({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isCompact,
    required bool isLockedToCompany,
  }) {
    final searchInputWidget = SizedBox(
      width: isCompact ? double.infinity : 280,
      height: isCompact ? 38 : 42,
      child: TextField(
        controller: _productSearchController,
        style: GoogleFonts.cairo(fontSize: 12.5),
        onChanged: (_) => setState(() {
          _productsCurrentPage = 0;
          _productsMobileLimit = _reportPageSize;
        }),
        decoration: InputDecoration(
          hintText: isAr ? 'بحث باسم الصنف أو الباركود...' : (isHi ? 'नाम या बारकोड से खोजें...' : 'Search item name or barcode...'),
          hintStyle: GoogleFonts.cairo(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
          prefixIcon: Icon(Icons.search_rounded, size: 18, color: colorScheme.primary),
          suffixIcon: _productSearchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  onPressed: () {
                    _productSearchController.clear();
                    setState(() {
                      _productsCurrentPage = 0;
                      _productsMobileLimit = _reportPageSize;
                    });
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8), width: 1.2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8), width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
          ),
        ),
      ),
    );

    final sortSelectorWidget = M3ConnectedButtonGroup<String>(
      height: isCompact ? 38 : 42,
      borderRadius: 12,
      isExpanded: false,
      showCheckmark: true,
      segments: [
        M3ButtonSegment<String>(
          value: 'QTY',
          label: isAr ? 'الكمية' : (isHi ? 'मात्रा' : 'Qty'),
          icon: Icons.inventory_2_rounded,
          tooltip: isAr ? 'ترتيب تنازلي حسب الكمية المباعة' : (isHi ? 'मात्रा کے مطابق ترتیب' : 'Sort by sold quantity'),
        ),
        M3ButtonSegment<String>(
          value: 'REVENUE',
          label: isAr ? 'القيمة' : (isHi ? 'मूल्य' : 'Revenue'),
          icon: Icons.payments_rounded,
          tooltip: isAr ? 'ترتيب تنازلي حسب إجمالي القيمة والمبيعات' : (isHi ? 'قیمت کے مطابق ترتیب' : 'Sort by total value'),
        ),
        M3ButtonSegment<String>(
          value: 'NAME',
          label: isAr ? 'الاسم' : (isHi ? 'नाम' : 'Name'),
          icon: Icons.sort_by_alpha_rounded,
          tooltip: isAr ? 'ترتيب أبجدي حسب اسم الصنف' : (isHi ? 'نام کے مطابق حروف تہجی کی ترتیب' : 'Sort alphabetically by item name'),
        ),
      ],
      selectedValue: _productSortBy,
      onSelected: (val) => setState(() => _productSortBy = val),
    );

    final companyFilterWidget = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _onlyCompanyProductsFilter = !_onlyCompanyProductsFilter;
            _productsCurrentPage = 0;
            _productsMobileLimit = _reportPageSize;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          height: isCompact ? 38 : 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _onlyCompanyProductsFilter
                ? colorScheme.primaryContainer.withValues(alpha: 0.7)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _onlyCompanyProductsFilter
                  ? colorScheme.primary.withValues(alpha: 0.8)
                  : colorScheme.outlineVariant.withValues(alpha: 0.8),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _onlyCompanyProductsFilter ? Icons.verified_rounded : Icons.all_inclusive_rounded,
                size: 17,
                color: _onlyCompanyProductsFilter ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                _onlyCompanyProductsFilter
                    ? (isAr ? 'أصناف الشركة فقط' : (isHi ? 'केवल कंपनी आइटम' : 'Company Items Only'))
                    : (isAr ? 'كافة أصناف الفاتورة' : (isHi ? 'सभी रसीद आइटम' : 'All Receipt Items')),
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: _onlyCompanyProductsFilter ? FontWeight.bold : FontWeight.w600,
                  color: _onlyCompanyProductsFilter ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          searchInputWidget,
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                companyFilterWidget,
                const SizedBox(width: 8),
                sortSelectorWidget,
              ],
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: searchInputWidget),
        const SizedBox(width: 10),
        companyFilterWidget,
        const SizedBox(width: 10),
        sortSelectorWidget,
      ],
    );
  }

  Widget _buildBranchesToolbar({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isCompact,
  }) {
    final viewModeGroup = M3ConnectedButtonGroup<String>(
      height: isCompact ? 38 : 42,
      borderRadius: 12,
      isExpanded: false,
      segments: [
        M3ButtonSegment<String>(
          value: 'DONUT',
          label: isAr ? 'مخطط دائري' : 'Donut',
          icon: Icons.pie_chart_rounded,
          tooltip: strings.chartViewDonut,
        ),
        M3ButtonSegment<String>(
          value: 'BAR',
          label: isAr ? 'مخطط أعمدة' : 'Bar Chart',
          icon: Icons.bar_chart_rounded,
          tooltip: strings.chartViewBar,
        ),
        M3ButtonSegment<String>(
          value: 'LIST',
          label: isAr ? 'بطاقات وترتيب' : 'Leaderboard',
          icon: Icons.format_list_numbered_rounded,
          tooltip: strings.chartViewList,
        ),
      ],
      selectedValue: _branchChartViewMode,
      onSelected: (val) => setState(() => _branchChartViewMode = val),
    );

    final aggregationGroup = M3ConnectedButtonGroup<String>(
      height: isCompact ? 38 : 42,
      borderRadius: 12,
      isExpanded: false,
      segments: [
        M3ButtonSegment<String>(
          value: 'BRANCH',
          label: isAr ? 'الفروع' : 'Branches',
          icon: Icons.store_rounded,
          tooltip: strings.aggregationBranches,
        ),
        M3ButtonSegment<String>(
          value: 'CHAIN',
          label: isAr ? 'السلاسل' : 'Chains',
          icon: Icons.corporate_fare_rounded,
          tooltip: strings.aggregationChains,
        ),
      ],
      selectedValue: _branchAggregationLevel,
      onSelected: (val) => setState(() {
        _branchAggregationLevel = val;
        _branchesCurrentPage = 0;
      }),
    );

    final metricGroup = M3ConnectedButtonGroup<String>(
      height: isCompact ? 38 : 42,
      borderRadius: 12,
      isExpanded: false,
      segments: [
        M3ButtonSegment<String>(
          value: 'REVENUE',
          label: isAr ? 'المبيعات' : 'Revenue',
          icon: Icons.payments_rounded,
          tooltip: strings.metricRevenue,
        ),
        M3ButtonSegment<String>(
          value: 'COUNT',
          label: isAr ? 'الفواتير' : 'Receipts',
          icon: Icons.receipt_long_rounded,
          tooltip: strings.metricReceiptsCount,
        ),
      ],
      selectedValue: _branchMetricDimension,
      onSelected: (val) => setState(() => _branchMetricDimension = val),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          viewModeGroup,
          const SizedBox(width: 8),
          aggregationGroup,
          const SizedBox(width: 8),
          metricGroup,
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 5. M3 Navigation / Segmented Button Tabs
  // ---------------------------------------------------------------------------
  Widget _buildTabsSelector({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required int productsCount,
    required int branchesCount,
    required bool isMobile,
  }) {
    final prodLabel = isMobile
        ? (isAr ? 'الأصناف' : (isHi ? 'उत्पाद' : 'Products'))
        : (isAr ? 'الأصناف والمنتجات الأكثر مبيعاً' : (isHi ? 'सर्वाधिक बिकने वाले उत्पाद' : 'Top Selling Products & Brands'));
    final branchLabel = isMobile
        ? (isAr ? 'الفروع' : (isHi ? 'शाखाएं' : 'Branches'))
        : (isAr ? 'توزيع الفروع والسلاسل' : (isHi ? 'शाखावार बिक्री' : 'Store & Branch Distribution'));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: M3ConnectedButtonGroup<int>(
        height: isMobile ? 44 : 48,
        borderRadius: 16,
        isExpanded: false,
        segments: [
          M3ButtonSegment<int>(
            value: 0,
            label: prodLabel,
            icon: Icons.bar_chart_rounded,
            badgeText: '$productsCount',
            tooltip: isAr ? 'ترتيب الأصناف والمنتجات المباعة بحسب الكمية والقيمة الإجمالية' : 'Ranked product sales by quantity and revenue',
          ),
          M3ButtonSegment<int>(
            value: 1,
            label: branchLabel,
            icon: Icons.storefront_rounded,
            badgeText: '$branchesCount',
            tooltip: isAr ? 'توزيع المبيعات وعدد الفواتير حسب الفروع ومنافذ البيع' : 'Breakdown of sales by retail branch and supermarket chain',
          ),
        ],
        selectedValue: _selectedTab,
        onSelected: (val) => setState(() => _selectedTab = val),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 6. Tab 1: Product Sales & Ranking Breakdown
  // ---------------------------------------------------------------------------
  Widget _buildProductsBreakdownTab({
    required List<_ProductStat> sortedProducts,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required CountryCurrency activeCountry,
    required bool isMobile,
    bool isLockedToCompany = false,
  }) {
    final query = _productSearchController.text.toLowerCase().trim();
    final displayedList = sortedProducts.where((p) {
      if (query.isEmpty) return true;
      return p.name.toLowerCase().contains(query) || p.barcode.contains(query);
    }).toList();

    if (sortedProducts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined, size: 56, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
              const SizedBox(height: 16),
              Text(
                isAr ? 'لا توجد بيانات أصناف مباعة مسجلة لهذه الفعالية بعد.' : 'No product sales recorded for this campaign yet.',
                style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                isAr ? 'بمجرد فحص وقبول فواتير العملاء، ستظهر هنا إحصائيات المنتجات بدقة.' : 'Once receipts are scanned and validated, product statistics will populate automatically.',
                style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final maxQty = sortedProducts.isNotEmpty ? sortedProducts.first.totalQty : 1;

    // Compute paginated items for display (25 items per page on desktop / lazy limit on mobile)
    final totalItems = displayedList.length;
    final totalPages = (totalItems / _reportPageSize).ceil();
    final safePage = _productsCurrentPage.clamp(0, totalPages > 0 ? totalPages - 1 : 0);
    final startIndex = safePage * _reportPageSize;
    final endIndex = (startIndex + _reportPageSize).clamp(0, totalItems);
    final pagedProducts = isMobile
        ? displayedList.take(_productsMobileLimit).toList()
        : (totalItems > 0 ? displayedList.sublist(startIndex, endIndex) : <_ProductStat>[]);

    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          if (displayedList.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Center(
                child: Text(
                  isAr ? 'لا توجد نتائج مطابقة لبحثك.' : 'No matching items found.',
                  style: GoogleFonts.cairo(fontSize: 13, color: colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else ...[
            // Product Ranking Cards
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pagedProducts.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final prod = pagedProducts[index];
                final double progress = maxQty > 0 ? (prod.totalQty / maxQty) : 0.0;
                final actualRank = isMobile ? index : (startIndex + index);

                // Color for medal ranks
                Color rankBadgeColor = colorScheme.surfaceContainerHighest;
                Color rankTextColor = colorScheme.onSurfaceVariant;
                String rankPrefix = '#${actualRank + 1}';

                if (actualRank == 0) {
                  rankBadgeColor = const Color(0xFFFFF8E1);
                  rankTextColor = const Color(0xFFB78103);
                  rankPrefix = '🥇 #1';
                } else if (actualRank == 1) {
                  rankBadgeColor = const Color(0xFFF1F5F9);
                  rankTextColor = const Color(0xFF64748B);
                  rankPrefix = '🥈 #2';
                } else if (actualRank == 2) {
                  rankBadgeColor = const Color(0xFFFDF2E9);
                  rankTextColor = const Color(0xFFC05621);
                  rankPrefix = '🥉 #3';
                }

                return Container(
                  padding: EdgeInsets.all(isMobile ? 12 : 16),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: actualRank == 0
                          ? const Color(0xFFD4AF37).withValues(alpha: 0.5)
                          : colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top: Rank + Product Name + Target Tag
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: rankBadgeColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              rankPrefix,
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: rankTextColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  prod.name,
                                  style: GoogleFonts.cairo(
                                    fontSize: isMobile ? 13 : 14,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (prod.barcode.isNotEmpty)
                                  Text(
                                    'Barcode: ${prod.barcode}',
                                    style: GoogleFonts.cairo(
                                      fontSize: 10,
                                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          // Target Company Tag
                          if (prod.isTargetCompany)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.verified_rounded, size: 12, color: Colors.green.shade700),
                                  const SizedBox(width: 4),
                                  Text(
                                    isAr ? 'منتج العرض' : 'Target Item',
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
                      const SizedBox(height: 10),

                      // Metrics Values
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.shopping_bag_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(
                                '${isAr ? "الكمية المباعة: " : "Quantity Sold: "}${prod.totalQty}',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${prod.totalRevenue.toStringAsFixed(1)} ${activeCountry.currencySymbol}',
                            style: GoogleFonts.cairo(
                              fontSize: isMobile ? 13 : 14,
                              fontWeight: FontWeight.w900,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // M3 Animated Linear Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            actualRank == 0 ? const Color(0xFFD4AF37) : (actualRank == 1 ? colorScheme.primary : colorScheme.secondary),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Pagination Controls / Mobile Load More Footer
            if (isMobile)
              _buildMobileLoadMoreFooter(
                totalItems: totalItems,
                currentLimit: _productsMobileLimit,
                colorScheme: colorScheme,
                isAr: isAr,
                itemTypeLabelAr: 'صنف',
                itemTypeLabelEn: 'products',
                onLoadMore: () => setState(() => _productsMobileLimit += _reportPageSize),
              )
            else
              _buildPaginationControls(
                totalItems: totalItems,
                currentPage: safePage,
                pageSize: _reportPageSize,
                colorScheme: colorScheme,
                strings: strings,
                isAr: isAr,
                onPageChanged: (newPage) => setState(() => _productsCurrentPage = newPage),
              ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 7. Tab 2: Branches & Store Distribution
  // ---------------------------------------------------------------------------
  Widget _buildBranchesBreakdownTab({
    required List<_BranchStat> sortedBranches,
    required List<_BranchStat> sortedChains,
    required double totalSales,
    required int totalReceipts,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required CountryCurrency activeCountry,
    required bool isMobile,
  }) {
    final isChainMode = _branchAggregationLevel == 'CHAIN';
    final isByRevenue = _branchMetricDimension == 'REVENUE';
    final rawStats = isChainMode ? sortedChains : sortedBranches;

    if (rawStats.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Center(
          child: Text(
            isAr
                ? (isChainMode ? 'لا توجد بيانات سلاسل مسجلة حتى الآن.' : 'لا توجد بيانات فروع مسجلة حتى الآن.')
                : (isHi
                    ? (isChainMode ? 'अभी तक कोई रिटेल चेन डेटा दर्ज नहीं किया गया है।' : 'अभी तक कोई शाखा डेटा दर्ज नहीं किया गया है।')
                    : (isChainMode ? 'No retail chain data recorded yet.' : 'No branch data recorded yet.')),
            style: GoogleFonts.cairo(fontSize: 15, color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    // Sort active dataset
    final currentStats = List<_BranchStat>.from(rawStats)..sort((a, b) {
      if (isByRevenue) {
        return b.totalRevenue.compareTo(a.totalRevenue);
      } else {
        return b.receiptCount.compareTo(a.receiptCount);
      }
    });

    final double maxRevenue = currentStats.isNotEmpty ? currentStats.first.totalRevenue : 1.0;
    final int activeEntitiesCount = currentStats.length;
    final String topEntityName = currentStats.isNotEmpty ? currentStats.first.branchName : '-';
    final double topEntityRevenue = currentStats.isNotEmpty ? currentStats.first.totalRevenue : 0.0;
    final double avgRevenue = activeEntitiesCount > 0 ? (totalSales / activeEntitiesCount) : 0.0;

    // Map to BranchChartItem
    final chartItems = currentStats.asMap().entries.map((entry) {
      final idx = entry.key;
      final stat = entry.value;
      final double pct = isByRevenue
          ? (totalSales > 0 ? (stat.totalRevenue / totalSales) * 100 : 0.0)
          : (totalReceipts > 0 ? (stat.receiptCount / totalReceipts) * 100 : 0.0);

      return BranchChartItem(
        name: stat.branchName,
        totalRevenue: stat.totalRevenue,
        receiptCount: stat.receiptCount,
        percentageOfTotal: pct,
        isChain: isChainMode,
        color: M3ChartPalette.getColor(idx),
      );
    }).toList();

    // Pagination for Leaderboard List (25 per page on desktop / lazy limit on mobile)
    final totalItems = chartItems.length;
    final totalPages = (totalItems / _reportPageSize).ceil();
    final safePage = _branchesCurrentPage.clamp(0, totalPages > 0 ? totalPages - 1 : 0);
    final startIndex = safePage * _reportPageSize;
    final endIndex = (startIndex + _reportPageSize).clamp(0, totalItems);
    final pagedChartItems = isMobile
        ? chartItems.take(_branchesMobileLimit).toList()
        : (totalItems > 0 ? chartItems.sublist(startIndex, endIndex) : <BranchChartItem>[]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Performance Summary KPI Row
        BranchPerformanceKpiRow(
          activeEntitiesCount: activeEntitiesCount,
          topEntityName: topEntityName,
          topEntityRevenue: topEntityRevenue,
          avgRevenuePerEntity: avgRevenue,
          activeCountry: activeCountry,
          colorScheme: colorScheme,
          isChainMode: isChainMode,
          isAr: isAr,
          isHi: isHi,
          isMobile: isMobile,
        ),
        const SizedBox(height: 14),

        // 2. Active Chart View / Leaderboard Container
        if (_branchChartViewMode == 'DONUT') ...[
          BranchChainDonutChart(
            items: chartItems,
            totalSales: totalSales,
            totalReceipts: totalReceipts,
            metricDimension: _branchMetricDimension,
            activeCountry: activeCountry,
            isAr: isAr,
            isHi: isHi,
          ),
        ] else if (_branchChartViewMode == 'BAR') ...[
          BranchChainBarChart(
            items: chartItems,
            metricDimension: _branchMetricDimension,
            activeCountry: activeCountry,
            isAr: isAr,
            isHi: isHi,
          ),
        ] else ...[
          Container(
            padding: EdgeInsets.all(isMobile ? 14 : 20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isChainMode ? Icons.corporate_fare_rounded : Icons.storefront_rounded,
                      color: colorScheme.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isChainMode
                            ? (isAr ? 'ترتيب وتوزيع السلاسل التجارية والماركت' : (isHi ? 'रिटेल चेन प्रदर्शन और रैंकिंग' : 'Retail Chains Performance & Ranking'))
                            : (isAr ? 'ترتيب وتوزيع مبيعات الفروع ومنافذ البيع' : (isHi ? 'शाखा बिक्री प्रदर्शन और रैंकिंग' : 'Store Outlets Performance & Ranking')),
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 13 : 15,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                BranchChainLeaderboardList(
                  items: pagedChartItems,
                  maxRevenue: maxRevenue,
                  activeCountry: activeCountry,
                  colorScheme: colorScheme,
                  isAr: isAr,
                  isHi: isHi,
                  isMobile: isMobile,
                ),

                // Pagination Controls / Mobile Load More Footer
                if (isMobile)
                  _buildMobileLoadMoreFooter(
                    totalItems: totalItems,
                    currentLimit: _branchesMobileLimit,
                    colorScheme: colorScheme,
                    isAr: isAr,
                    itemTypeLabelAr: isChainMode ? 'سلسلة' : 'فرع',
                    itemTypeLabelEn: isChainMode ? 'chains' : 'branches',
                    onLoadMore: () => setState(() => _branchesMobileLimit += _reportPageSize),
                  )
                else
                  _buildPaginationControls(
                    totalItems: totalItems,
                    currentPage: safePage,
                    pageSize: _reportPageSize,
                    colorScheme: colorScheme,
                    strings: strings,
                    isAr: isAr,
                    onPageChanged: (newPage) => setState(() => _branchesCurrentPage = newPage),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Pagination & Mobile Lazy Load UI Components
  // ---------------------------------------------------------------------------
  Widget _buildPaginationControls({
    required int totalItems,
    required int currentPage,
    required int pageSize,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required ValueChanged<int> onPageChanged,
  }) {
    if (totalItems <= pageSize) return const SizedBox.shrink();

    final totalPages = (totalItems / pageSize).ceil();
    final startItem = (currentPage * pageSize) + 1;
    final endItem = ((currentPage + 1) * pageSize).clamp(1, totalItems);

    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Range & Total summary
          Text(
            isAr
                ? 'عرض $startItem-$endItem من إجمالي $totalItems'
                : 'Showing $startItem-$endItem of $totalItems',
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
          ),

          // Navigation Controls
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // First Page
              Tooltip(
                message: isAr ? 'الصفحة الأولى' : 'First Page',
                child: IconButton.filledTonal(
                  icon: Icon(
                    isAr ? Icons.last_page_rounded : Icons.first_page_rounded,
                    size: 18,
                  ),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: currentPage > 0 ? () => onPageChanged(0) : null,
                ),
              ),
              const SizedBox(width: 4),

              // Previous Page
              Tooltip(
                message: isAr ? 'الصفحة السابقة' : 'Previous Page',
                child: IconButton.filledTonal(
                  icon: Icon(
                    isAr ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
                    size: 18,
                  ),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: currentPage > 0 ? () => onPageChanged(currentPage - 1) : null,
                ),
              ),
              const SizedBox(width: 8),

              // Current Page Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  isAr
                      ? 'صفحة ${currentPage + 1} من $totalPages'
                      : 'Page ${currentPage + 1} of $totalPages',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Next Page
              Tooltip(
                message: isAr ? 'الصفحة التالية' : 'Next Page',
                child: IconButton.filledTonal(
                  icon: Icon(
                    isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                    size: 18,
                  ),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: currentPage < totalPages - 1
                      ? () => onPageChanged(currentPage + 1)
                      : null,
                ),
              ),
              const SizedBox(width: 4),

              // Last Page
              Tooltip(
                message: isAr ? 'الصفحة الأخيرة' : 'Last Page',
                child: IconButton.filledTonal(
                  icon: Icon(
                    isAr ? Icons.first_page_rounded : Icons.last_page_rounded,
                    size: 18,
                  ),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: currentPage < totalPages - 1
                      ? () => onPageChanged(totalPages - 1)
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLoadMoreFooter({
    required int totalItems,
    required int currentLimit,
    required ColorScheme colorScheme,
    required bool isAr,
    required VoidCallback onLoadMore,
    required String itemTypeLabelAr,
    required String itemTypeLabelEn,
  }) {
    if (totalItems <= _reportPageSize) return const SizedBox.shrink();

    final hasMore = currentLimit < totalItems;
    final remaining = totalItems - currentLimit;

    if (hasMore) {
      return Container(
        margin: const EdgeInsets.only(top: 14),
        child: Center(
          child: FilledButton.tonalIcon(
            onPressed: onLoadMore,
            icon: const Icon(Icons.expand_more_rounded, size: 18),
            label: Text(
              isAr
                  ? 'عرض 25 $itemTypeLabelAr إضافية (متبقي $remaining من $totalItems)'
                  : 'Load 25 More $itemTypeLabelEn ($remaining of $totalItems remaining)',
              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      );
    } else {
      return Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            isAr
                ? 'تم عرض كافة الـ $totalItems $itemTypeLabelAr بالكامل'
                : 'All $totalItems $itemTypeLabelEn displayed',
            style: GoogleFonts.cairo(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 9. Export Analytics Excel (.xlsx)
  // ---------------------------------------------------------------------------
  void _exportAnalyticsExcel({
    required BuildContext context,
    required List<QueryDocumentSnapshot> filteredTransactions,
    required List<_ProductStat> sortedProducts,
    required List<_BranchStat> sortedBranches,
    required String effectiveCompanyName,
    required bool isAr,
    required CountryCurrency activeCountry,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final excel = Excel.createExcel();

      // Sheet 1: Top Selling Products (الأصناف الأكثر مبيعاً)
      final String productsSheetName = isAr ? 'الأصناف الأكثر مبيعاً' : 'Top Products';
      excel.rename('Sheet1', productsSheetName);
      final Sheet productsSheet = excel[productsSheetName];

      productsSheet.appendRow([
        TextCellValue(isAr ? 'الترتيب' : 'Rank'),
        TextCellValue(isAr ? 'اسم الصنف' : 'Product Name'),
        TextCellValue(isAr ? 'الباركود' : 'Barcode'),
        TextCellValue(isAr ? 'الكمية المباعة' : 'Quantity Sold'),
        TextCellValue(isAr ? 'إجمالي المبيعات (${activeCountry.currencySymbol})' : 'Total Revenue (${activeCountry.currencySymbol})'),
        TextCellValue(isAr ? 'نوع المنتج' : 'Item Type'),
      ]);

      for (int i = 0; i < sortedProducts.length; i++) {
        final p = sortedProducts[i];
        productsSheet.appendRow([
          IntCellValue(i + 1),
          TextCellValue(p.name),
          TextCellValue(p.barcode),
          IntCellValue(p.totalQty),
          DoubleCellValue(double.parse(p.totalRevenue.toStringAsFixed(2))),
          TextCellValue(p.isTargetCompany ? (isAr ? 'منتج العرض' : 'Target Item') : (isAr ? 'منتج عام' : 'Regular Item')),
        ]);
      }

      // Sheet 2: Audited Invoices Log (سجل الفواتير والمرفوعات)
      final String receiptsSheetName = isAr ? 'سجل الفواتير' : 'Invoices Log';
      final Sheet receiptsSheet = excel[receiptsSheetName];

      receiptsSheet.appendRow([
        TextCellValue(isAr ? 'رقم الفاتورة' : 'Receipt #'),
        TextCellValue(isAr ? 'تاريخ الفاتورة' : 'Receipt Date'),
        TextCellValue(isAr ? 'السلسلة التجارية' : 'Store Chain'),
        TextCellValue(isAr ? 'الفرع' : 'Branch'),
        TextCellValue(isAr ? 'اسم العميل' : 'Customer Name'),
        TextCellValue(isAr ? 'رقم الهاتف' : 'Phone Number'),
        TextCellValue(isAr ? 'قيمة المشتريات (${activeCountry.currencySymbol})' : 'Amount (${activeCountry.currencySymbol})'),
        TextCellValue(isAr ? 'حالة الفاتورة' : 'Status'),
        TextCellValue(isAr ? 'سبب الرفض إن وجد' : 'Rejection Reason'),
        TextCellValue(isAr ? 'تاريخ التسجيل' : 'Timestamp'),
      ]);

      for (final doc in filteredTransactions) {
        final data = doc.data() as Map<String, dynamic>;
        final recNum = data['receipt_number']?.toString() ?? '';
        final recDate = data['receipt_date']?.toString() ?? '';
        final chain = data['store_chain_detected']?.toString() ?? '';
        final branch = data['branch_detected']?.toString() ?? '';
        final custName = data['customerName']?.toString() ?? '';
        final custPhone = data['customerPhone']?.toString() ?? '';
        final val = (data['target_company_total'] ?? data['total_value'] as num?)?.toDouble() ?? 0.0;
        final bool isExplicitlyValid = data['is_valid'] == true || data['status'] == 'accepted' || data['isValid'] == true;
        final bool isExplicitlyRejected = data['is_valid'] == false || data['status'] == 'rejected' || data['isValid'] == false || ((data['unfulfilled_conditions'] as List?)?.isNotEmpty ?? false);
        final bool isValid = isExplicitlyValid || (!isExplicitlyRejected && ((data['unfulfilled_conditions'] as List?)?.isEmpty ?? true));
        final status = isValid ? (isAr ? 'مقبولة' : 'Accepted') : (isAr ? 'مرفوضة' : 'Rejected');
        final unfulfilled = (data['unfulfilled_conditions'] as List?)?.join(', ') ?? '';
        final rejectionReason = data['rejection_reason']?.toString() ?? unfulfilled;
        final ts = data['timestamp'] != null ? (data['timestamp'] as Timestamp).toDate().toString() : '';

        receiptsSheet.appendRow([
          TextCellValue(recNum),
          TextCellValue(recDate),
          TextCellValue(chain),
          TextCellValue(branch),
          TextCellValue(custName),
          TextCellValue(custPhone),
          DoubleCellValue(double.parse(val.toStringAsFixed(2))),
          TextCellValue(status),
          TextCellValue(rejectionReason),
          TextCellValue(ts),
        ]);
      }

      // Sheet 3: Branches Breakdown (توزيع الفروع)
      final String branchesSheetName = isAr ? 'توزيع الفروع' : 'Branches Breakdown';
      final Sheet branchesSheet = excel[branchesSheetName];

      branchesSheet.appendRow([
        TextCellValue(isAr ? 'اسم الفرع' : 'Branch Name'),
        TextCellValue(isAr ? 'عدد الفواتير' : 'Receipts Count'),
        TextCellValue(isAr ? 'إجمالي المبيعات (${activeCountry.currencySymbol})' : 'Total Revenue (${activeCountry.currencySymbol})'),
      ]);

      for (final b in sortedBranches) {
        branchesSheet.appendRow([
          TextCellValue(b.branchName),
          IntCellValue(b.receiptCount),
          DoubleCellValue(double.parse(b.totalRevenue.toStringAsFixed(2))),
        ]);
      }

      final fileBytes = excel.encode();
      if (fileBytes != null) {
        final now = DateTime.now();
        final dateStr = '${now.year}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}';
        final cleanName = effectiveCompanyName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), '').replaceAll(' ', '_');
        final fileName = 'Tashil_Report_${cleanName}_$dateStr.xlsx';

        downloadFileBytes(
          bytes: fileBytes,
          fileName: fileName,
        );

        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isAr
                        ? 'تم تحميل وتنزيل ملف تقرير Excel بنجاح ($fileName)'
                        : 'Excel report downloaded successfully ($fileName)',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF107C41),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('${isAr ? "خطأ في تحميل Excel: " : "Excel export error: "}$e'),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _ProductStat {
  final String name;
  int totalQty;
  double totalRevenue;
  final bool isTargetCompany;
  String barcode;

  _ProductStat({
    required this.name,
    required this.totalQty,
    required this.totalRevenue,
    required this.isTargetCompany,
    this.barcode = '',
  });
}

class _BranchStat {
  final String branchName;
  int receiptCount = 0;
  double totalRevenue = 0.0;

  _BranchStat({required this.branchName});
}

// =============================================================================
// Active Campaign Details Card (with Split Chains & Interactive Branches Drawer)
// =============================================================================
class _CampaignEventDetailsCard extends ConsumerStatefulWidget {
  final EventModel event;
  final ColorScheme colorScheme;
  final CountryCurrency activeCountry;
  final bool isAr;
  final bool isHi;
  final bool isMobile;

  const _CampaignEventDetailsCard({
    required this.event,
    required this.colorScheme,
    required this.activeCountry,
    required this.isAr,
    required this.isHi,
    required this.isMobile,
  });

  @override
  ConsumerState<_CampaignEventDetailsCard> createState() => _CampaignEventDetailsCardState();
}

class _CampaignEventDetailsCardState extends ConsumerState<_CampaignEventDetailsCard> {
  bool _isBranchesExpanded = false;
  String? _selectedChainFilter; // null means 'ALL' (كافة السلاسل)
  String? _lastEventId;

  @override
  void initState() {
    super.initState();
    _lastEventId = widget.event.id;
  }

  @override
  void didUpdateWidget(covariant _CampaignEventDetailsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.event.id != _lastEventId) {
      _lastEventId = widget.event.id;
      _isBranchesExpanded = false;
      _selectedChainFilter = null;
    }
  }

  List<String> _extractRetailChains(String rawChainName) {
    if (rawChainName.trim().isEmpty) return [];
    final parts = rawChainName
        .split(RegExp(r'[•,،|/\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    return parts.isNotEmpty ? parts : [rawChainName.trim()];
  }

  bool _isBranchBelongingToChain({
    required String branchStr,
    required String targetChain,
    required List<BranchModel> dbBranches,
    required List<String> allChainNames,
  }) {
    if (allChainNames.length <= 1) return true;

    final normTargetChain = targetChain.trim().toLowerCase();
    final normTargetCanonical =
        ChainProductsIntelligenceService.normalizeRetailChain(targetChain).toLowerCase();

    // 1. Check in Firestore dbBranches
    final matchedDbBranch = dbBranches.where((dbB) {
      return _CampaignReportsScreenState._isBranchMatch(branchStr, dbB.branchName);
    }).firstOrNull;

    if (matchedDbBranch != null) {
      final dbChain = matchedDbBranch.retailChainName.trim().toLowerCase();
      final dbCanonical =
          ChainProductsIntelligenceService.normalizeRetailChain(dbChain).toLowerCase();
      if (dbChain.contains(normTargetChain) ||
          normTargetChain.contains(dbChain) ||
          dbCanonical == normTargetCanonical) {
        return true;
      }
    }

    // 2. String containment heuristic
    final normBranch = branchStr.trim().toLowerCase();
    if (normBranch.contains(normTargetChain) || normBranch.contains(normTargetCanonical)) {
      return true;
    }

    // 3. Check if it matches any OTHER chain explicitly
    bool matchesOther = false;
    for (final other in allChainNames) {
      if (other == targetChain) continue;
      final otherNorm = other.trim().toLowerCase();
      final otherCanonical =
          ChainProductsIntelligenceService.normalizeRetailChain(other).toLowerCase();
      if (matchedDbBranch != null) {
        final dbChain = matchedDbBranch.retailChainName.trim().toLowerCase();
        if (dbChain.contains(otherNorm) || otherNorm.contains(dbChain) || dbChain == otherNorm) {
          matchesOther = true;
          break;
        }
      }
      if (normBranch.contains(otherNorm) || normBranch.contains(otherCanonical)) {
        matchesOther = true;
        break;
      }
    }

    return !matchesOther;
  }

  String? _getChainNameForBranch(
    String branch,
    Map<String, List<String>> chainToBranchesMap,
  ) {
    for (final entry in chainToBranchesMap.entries) {
      if (entry.value.contains(branch)) {
        return entry.key;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final colorScheme = widget.colorScheme;
    final activeCountry = widget.activeCountry;
    final isAr = widget.isAr;
    final isMobile = widget.isMobile;

    final statusColor = event.isActive ? const Color(0xFF006C50) : const Color(0xFFD97706);
    final statusText = event.isActive
        ? (isAr ? 'حملة ترويجية نشطة' : 'Active Campaign')
        : (isAr ? 'حملة متوقفة / منتهية' : 'Inactive Campaign');

    final rawBranches = event.branchNames;
    final chainNames = _extractRetailChains(event.retailChainName);

    Stream<List<BranchModel>> branchesStream;
    try {
      branchesStream = ref.watch(retailChainsServiceProvider).getAllBranchesStream();
    } catch (_) {
      branchesStream = Stream.value([]);
    }

    return StreamBuilder<List<BranchModel>>(
      stream: branchesStream,
      builder: (context, snapshot) {
        final dbBranches = snapshot.data ?? [];

        // Group branches by chain
        final Map<String, List<String>> chainToBranchesMap = {};
        for (final chain in chainNames) {
          chainToBranchesMap[chain] = rawBranches.where((b) {
            return _isBranchBelongingToChain(
              branchStr: b,
              targetChain: chain,
              dbBranches: dbBranches,
              allChainNames: chainNames,
            );
          }).toList();
        }

        // Active filtered branches
        final List<String> activeBranches;
        if (_selectedChainFilter == null) {
          activeBranches = rawBranches;
        } else {
          activeBranches = chainToBranchesMap[_selectedChainFilter] ?? [];
        }

        final branchesCount = rawBranches.isNotEmpty ? rawBranches.length : (event.isAllBranches ? 1 : 0);

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Top Header Row: Campaign Title, Status Badge & Key Meta Pills
              Padding(
                padding: EdgeInsets.all(isMobile ? 14 : 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top line: Status + Campaign Name
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.campaign_rounded,
                            color: colorScheme.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: statusColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    statusText,
                                    style: GoogleFonts.cairo(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: statusColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                event.eventName,
                                style: GoogleFonts.cairo(
                                  fontSize: isMobile ? 15 : 17,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Key Meta Pills: Target Company, Individual Chains, Min Spend, Total Branches
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Target Company
                        _buildMetaPill(
                          icon: Icons.business_rounded,
                          label: event.targetCompany,
                          colorScheme: colorScheme,
                        ),

                        // Retail Chains (Each in its own distinct mini-card / badge)
                        for (final chain in chainNames)
                          _buildChainPill(
                            chainName: chain,
                            branchCount: chainToBranchesMap[chain]?.length ?? 0,
                            isSelected: _isBranchesExpanded && _selectedChainFilter == chain,
                            colorScheme: colorScheme,
                            isAr: isAr,
                            onTap: () {
                              if (event.isAllBranches) return;
                              setState(() {
                                if (_isBranchesExpanded && _selectedChainFilter == chain) {
                                  _isBranchesExpanded = false;
                                  _selectedChainFilter = null;
                                } else {
                                  _isBranchesExpanded = true;
                                  _selectedChainFilter = chain;
                                }
                              });
                            },
                          ),

                        // Minimum Spend
                        _buildMetaPill(
                          icon: Icons.monetization_on_outlined,
                          label: event.minimumSpend > 0
                              ? '${isAr ? "الحد الأدنى: " : "Min: "}${event.minimumSpend == event.minimumSpend.roundToDouble() ? event.minimumSpend.toInt() : event.minimumSpend.toStringAsFixed(0)} ${activeCountry.currencySymbol}'
                              : (isAr ? 'بدون حد أدنى' : 'No Min Spend'),
                          colorScheme: colorScheme,
                        ),

                        // Covered Branches Count Pill (Interactive Toggle)
                        _buildBranchesTogglePill(
                          branchesCount: branchesCount,
                          isAllBranches: event.isAllBranches,
                          isExpanded: _isBranchesExpanded && _selectedChainFilter == null,
                          isAnyExpanded: _isBranchesExpanded,
                          colorScheme: colorScheme,
                          isAr: isAr,
                          onTap: () {
                            if (event.isAllBranches) return;
                            setState(() {
                              if (_isBranchesExpanded && _selectedChainFilter == null) {
                                _isBranchesExpanded = false;
                              } else {
                                _isBranchesExpanded = true;
                                _selectedChainFilter = null; // Show all branches
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 2. Beautiful Collapsible Branches & Outlets List
              if (!event.isAllBranches && rawBranches.isNotEmpty && _isBranchesExpanded) ...[
                _buildExpandedBranchesSection(
                  activeBranches: activeBranches,
                  totalBranchesCount: rawBranches.length,
                  chainNames: chainNames,
                  chainToBranchesMap: chainToBranchesMap,
                  colorScheme: colorScheme,
                  isAr: isAr,
                  isMobile: isMobile,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetaPill({
    required IconData icon,
    required String label,
    required ColorScheme colorScheme,
    bool isHighlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isHighlighted
            ? colorScheme.primaryContainer.withValues(alpha: 0.7)
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlighted
              ? colorScheme.primary.withValues(alpha: 0.4)
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isHighlighted ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 11,
              fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w600,
              color: isHighlighted ? colorScheme.primary : colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChainPill({
    required String chainName,
    required int branchCount,
    required bool isSelected,
    required ColorScheme colorScheme,
    required bool isAr,
    required VoidCallback onTap,
  }) {
    final borderColor = isSelected
        ? colorScheme.primary
        : colorScheme.outlineVariant.withValues(alpha: 0.7);
    final bgColor = isSelected
        ? colorScheme.primaryContainer.withValues(alpha: 0.85)
        : colorScheme.surface;
    final textColor = isSelected ? colorScheme.primary : colorScheme.onSurface;
    final iconColor = colorScheme.primary;

    return Tooltip(
      message: isSelected
          ? (isAr ? 'اضغط لإخفاء قائمة الفروع' : 'Click to hide branches')
          : (isAr
              ? 'اضغط لعرض فروع $chainName (${branchCount > 0 ? "$branchCount فرع" : ""})'
              : 'Click to view $chainName branches'),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1.0),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.store_mall_directory_rounded,
                size: 14,
                color: iconColor,
              ),
              const SizedBox(width: 6),
              Text(
                chainName,
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: textColor,
                ),
              ),
              if (branchCount > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary.withValues(alpha: 0.2)
                        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected
                          ? colorScheme.primary.withValues(alpha: 0.4)
                          : colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    '$branchCount',
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(
                isSelected ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                size: 14,
                color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBranchesTogglePill({
    required int branchesCount,
    required bool isAllBranches,
    required bool isExpanded,
    required bool isAnyExpanded,
    required ColorScheme colorScheme,
    required bool isAr,
    required VoidCallback onTap,
  }) {
    final label = isAllBranches
        ? (isAr ? 'تغطية شاملة (كافة الفروع)' : 'All Branches Covered')
        : '$branchesCount ${isAr ? "فروع ومنافذ معتمدة" : "Covered Branches"}';

    if (isAllBranches) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.storefront_rounded,
              size: 14,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
      );
    }

    final borderColor = isExpanded
        ? colorScheme.primary
        : (isAnyExpanded
            ? colorScheme.primary.withValues(alpha: 0.5)
            : colorScheme.outlineVariant.withValues(alpha: 0.6));
    final bgColor = isExpanded
        ? colorScheme.primaryContainer
        : colorScheme.primaryContainer.withValues(alpha: 0.65);

    return Tooltip(
      message: isAr
          ? (isExpanded ? 'اضغط لإخفاء قائمة الفروع' : 'اضغط لعرض كافة الفروع ($branchesCount فرع)')
          : (isExpanded ? 'Click to collapse branches' : 'Click to expand all branches ($branchesCount)'),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: isExpanded ? 1.5 : 1.0),
            boxShadow: isExpanded
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.storefront_rounded,
                size: 14,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                size: 14,
                color: colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedBranchesSection({
    required List<String> activeBranches,
    required int totalBranchesCount,
    required List<String> chainNames,
    required Map<String, List<String>> chainToBranchesMap,
    required ColorScheme colorScheme,
    required bool isAr,
    required bool isMobile,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(
          height: 1,
          thickness: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 14 : 18,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(20),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Title + Chain Filter Chips + Collapse Button
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Title and Count
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.pin_drop_outlined,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _selectedChainFilter == null
                            ? (isAr
                                ? 'المنافذ والفروع المعتمدة لكافة السلاسل ($totalBranchesCount فرع):'
                                : 'Authorized Outlets Across All Chains ($totalBranchesCount Branches):')
                            : (isAr
                                ? 'فروع ومنافذ "$_selectedChainFilter" المعتمدة (${activeBranches.length} فرع):'
                                : 'Authorized Outlets for "$_selectedChainFilter" (${activeBranches.length} Branches):'),
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),

                  // Interactive Filters + Close Button
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (chainNames.length > 1) ...[
                        // "All Chains" filter badge
                        _buildFilterChip(
                          label: isAr ? 'كافة السلاسل ($totalBranchesCount)' : 'All ($totalBranchesCount)',
                          isActive: _selectedChainFilter == null,
                          colorScheme: colorScheme,
                          onTap: () {
                            setState(() {
                              _selectedChainFilter = null;
                            });
                          },
                        ),
                        // Individual chain filter badges
                        for (final c in chainNames)
                          _buildFilterChip(
                            label: '$c (${chainToBranchesMap[c]?.length ?? 0})',
                            isActive: _selectedChainFilter == c,
                            colorScheme: colorScheme,
                            onTap: () {
                              setState(() {
                                _selectedChainFilter = c;
                              });
                            },
                          ),
                      ],

                      // Collapse button
                      InkWell(
                        onTap: () {
                          setState(() {
                            _isBranchesExpanded = false;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.keyboard_arrow_up_rounded,
                                size: 14,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isAr ? 'إخفاء الفروع' : 'Hide',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Branches list / Wrap
              if (activeBranches.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    isAr ? 'لا توجد فروع مسجلة لهذه السلسلة في الحملة' : 'No branches registered for this chain in this campaign',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final b in activeBranches)
                      _buildBranchPill(
                        branchName: b,
                        chainName: _getChainNameForBranch(b, chainToBranchesMap),
                        showChainTag: _selectedChainFilter == null && chainNames.length > 1,
                        colorScheme: colorScheme,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isActive,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? colorScheme.primary : colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
            color: isActive ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildBranchPill({
    required String branchName,
    required String? chainName,
    required bool showChainTag,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.store_rounded,
            size: 13,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 5),
          Text(
            branchName,
            style: GoogleFonts.cairo(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          if (showChainTag && chainName != null && chainName.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                chainName,
                style: GoogleFonts.cairo(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StickyReportsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  _StickyReportsHeaderDelegate({
    required this.height,
    required this.child,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant _StickyReportsHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}
