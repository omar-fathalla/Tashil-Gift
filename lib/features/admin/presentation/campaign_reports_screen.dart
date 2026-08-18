import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/constants/country_currency_config.dart';
import '../../../core/widgets/switch_point_branding.dart';
import '../../../core/widgets/m3_button_groups.dart';
import '../domain/event_model.dart';

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

class _CampaignReportsScreenState extends ConsumerState<CampaignReportsScreen> {
  // Selected Event: null means "All Campaigns / جميع الحملات"
  EventModel? _selectedEvent;
  int _selectedTab = 0; // 0: Products, 1: Receipts, 2: Branches

  // Search & Filter controllers
  final TextEditingController _productSearchController = TextEditingController();
  final TextEditingController _receiptSearchController = TextEditingController();
  String _productSortBy = 'QTY'; // 'QTY', 'REVENUE', 'NAME'
  String _receiptStatusFilter = 'ALL'; // 'ALL', 'VALID', 'INVALID'

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
    _receiptSearchController.dispose();
    super.dispose();
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

    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('events').snapshots(),
      builder: (context, eventsSnapshot) {
        final allEvents = (eventsSnapshot.data?.docs ?? [])
            .map((doc) => EventModel.fromFirestore(doc))
            .toList();

        // Scope events if lockedCompanySlug is present
        final scopedEvents = (widget.lockedCompanySlug != null && widget.lockedCompanySlug!.isNotEmpty)
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

        return StreamBuilder<QuerySnapshot>(
          stream: firestore.collection('receipts_transactions').snapshots(),
          builder: (context, transactionsSnapshot) {
            if (transactionsSnapshot.connectionState == ConnectionState.waiting && !transactionsSnapshot.hasData) {
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

              if (_selectedEvent == null) {
                if (widget.lockedCompanySlug != null && widget.lockedCompanySlug!.isNotEmpty) {
                  final isSlugMatch = cSlug.toLowerCase() == widget.lockedCompanySlug!.toLowerCase();
                  final isNameMatch = widget.lockedCompanyName != null &&
                      widget.lockedCompanyName!.isNotEmpty &&
                      (compName.toLowerCase() == widget.lockedCompanyName!.toLowerCase() ||
                          targetComp.toLowerCase() == widget.lockedCompanyName!.toLowerCase());
                  return isSlugMatch || isNameMatch;
                }
                return true;
              }

              if (cId.isNotEmpty && cId == _selectedEvent!.id) return true;
              if (_selectedEvent!.companySlug.isNotEmpty && cSlug == _selectedEvent!.companySlug) return true;
              if (_selectedEvent!.targetCompany.isNotEmpty &&
                  (compName == _selectedEvent!.targetCompany || targetComp == _selectedEvent!.targetCompany)) {
                return true;
              }

              return false;
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
            );
          },
        );
      },
    );
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
  }) {
    int totalScans = filteredTransactions.length;
    int acceptedInvoices = 0;
    int rejectedInvoices = 0;
    double totalSalesVolume = 0.0;
    int totalUnitsSold = 0;
    final Map<String, _ProductStat> productStatsMap = {};
    final Map<String, _BranchStat> branchStatsMap = {};

    for (final doc in filteredTransactions) {
              final data = doc.data() as Map<String, dynamic>;
              final bool isValid = data['isValid'] == true ||
                  (data['is_valid'] == true) ||
                  ((data['unfulfilled_conditions'] as List?)?.isEmpty ?? true);

              if (isValid) {
                acceptedInvoices++;
              } else {
                rejectedInvoices++;
              }

              final spendVal = (data['target_company_total'] ?? data['total_value'] as num?)?.toDouble() ?? 0.0;
              totalSalesVolume += spendVal;

              // Branch aggregation
              final branchName = (data['branch_detected'] ?? data['branchName'] ?? data['store_chain_detected'] ?? '').toString().trim();
              final effectiveBranch = branchName.isNotEmpty ? branchName : (isAr ? 'فرع غير محدد' : 'Unspecified Branch');
              if (!branchStatsMap.containsKey(effectiveBranch)) {
                branchStatsMap[effectiveBranch] = _BranchStat(branchName: effectiveBranch);
              }
              branchStatsMap[effectiveBranch]!.receiptCount++;
              branchStatsMap[effectiveBranch]!.totalRevenue += spendVal;

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
            }

            final sortedProducts = productStatsMap.values.toList();
            if (_productSortBy == 'QTY') {
              sortedProducts.sort((a, b) => b.totalQty.compareTo(a.totalQty));
            } else if (_productSortBy == 'REVENUE') {
              sortedProducts.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
            } else {
              sortedProducts.sort((a, b) => a.name.compareTo(b.name));
            }

            final sortedBranches = branchStatsMap.values.toList()
              ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

            final String topProductName = sortedProducts.isNotEmpty
                ? sortedProducts.first.name
                : (isAr ? 'لا توجد منتجات مسجلة' : (isHi ? 'कोई उत्पाद नहीं' : 'No items recorded'));

            return LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 900;
                final isMobile = constraints.maxWidth < 700;

                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 12 : 20,
                    vertical: isMobile ? 12 : 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Unified Header Bar with Event Selector & Export Action
                      _buildHeaderCard(
                        context: context,
                        colorScheme: colorScheme,
                        strings: strings,
                        isAr: isAr,
                        isHi: isHi,
                        allEvents: scopedEvents,
                        isMobile: isMobile,
                        onExport: () => _exportAnalyticsCsv(
                          context: context,
                          filteredTransactions: filteredTransactions,
                          sortedProducts: sortedProducts,
                          isAr: isAr,
                          activeCountry: activeCountry,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 2. Active Campaign Information Card (if a specific campaign is selected)
                      if (_selectedEvent != null) ...[
                        _buildEventDetailsBadgeCard(
                          event: _selectedEvent!,
                          colorScheme: colorScheme,
                          activeCountry: activeCountry,
                          isAr: isAr,
                          isHi: isHi,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 3. M3 High-Impact KPI Metric Cards Grid
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
                      ),
                      const SizedBox(height: 24),

                      // 4. M3 Navigation / Segmented Button Tabs
                      _buildTabsSelector(
                        colorScheme: colorScheme,
                        strings: strings,
                        isAr: isAr,
                        isHi: isHi,
                        productsCount: sortedProducts.length,
                        receiptsCount: filteredTransactions.length,
                        branchesCount: sortedBranches.length,
                        isMobile: isMobile,
                      ),
                      const SizedBox(height: 16),

                      // 5. Active Tab View Content
                      if (_selectedTab == 0)
                        _buildProductsBreakdownTab(
                          sortedProducts: sortedProducts,
                          colorScheme: colorScheme,
                          strings: strings,
                          isAr: isAr,
                          isHi: isHi,
                          activeCountry: activeCountry,
                          isMobile: isMobile,
                        )
                      else if (_selectedTab == 1)
                        _buildReceiptsLogTab(
                          transactions: filteredTransactions,
                          colorScheme: colorScheme,
                          strings: strings,
                          isAr: isAr,
                          isHi: isHi,
                          activeCountry: activeCountry,
                          isMobile: isMobile,
                        )
                      else
                        _buildBranchesBreakdownTab(
                          sortedBranches: sortedBranches,
                          totalSales: totalSalesVolume,
                          colorScheme: colorScheme,
                          strings: strings,
                          isAr: isAr,
                          isHi: isHi,
                          activeCountry: activeCountry,
                          isMobile: isMobile,
                        ),
                    ],
                  ),
                );
              },
            );
  }

  // ---------------------------------------------------------------------------
  // 1. Header Card with Event Selector & Export CSV
  // ---------------------------------------------------------------------------
  Widget _buildHeaderCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required List<EventModel> allEvents,
    required VoidCallback onExport,
    required bool isMobile,
  }) {
    final titleWidget = Row(
      children: [
        Container(
          padding: EdgeInsets.all(isMobile ? 10 : 12),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
          ),
          child: Icon(
            Icons.analytics_rounded,
            color: colorScheme.onPrimaryContainer,
            size: isMobile ? 22 : 26,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.analyticsTitle,
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 16 : 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                isAr
                    ? 'تحليل مبيعات الأصناف، أداء الفعاليات، وسجل الفواتير والمرفوعات'
                    : (isHi ? 'उत्पाद बिक्री विश्लेषण, अभियान प्रदर्शन और रसीद रिपोर्ट' : 'Sales performance, top product rankings, and audited invoices'),
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 11 : 12,
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );

    final dropdownWidget = Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedEvent?.id ?? 'ALL',
          isExpanded: true,
          dropdownColor: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: colorScheme.primary),
          style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
          items: [
            DropdownMenuItem<String>(
              value: 'ALL',
              child: Row(
                children: [
                  Icon(Icons.public_rounded, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (widget.lockedCompanySlug != null && widget.lockedCompanySlug!.isNotEmpty)
                          ? '🌐 ${strings.companyAllCampaigns}'
                          : (isAr ? '🌐 كافة الحملات والفعاليات (All)' : '🌐 All Campaigns & Events'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            ...allEvents.map((evt) => DropdownMenuItem<String>(
                  value: evt.id,
                  child: Row(
                    children: [
                      Icon(Icons.campaign_rounded, size: 18, color: colorScheme.secondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          evt.retailChainName.isNotEmpty
                              ? '${evt.eventName} (${evt.targetCompany} - ${evt.retailChainName})'
                              : '${evt.eventName} (${evt.targetCompany})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          onChanged: (val) {
            setState(() {
              if (val == null || val == 'ALL') {
                _selectedEvent = null;
              } else {
                final match = allEvents.where((e) => e.id == val);
                _selectedEvent = match.isNotEmpty ? match.first : null;
              }
            });
          },
        ),
      ),
    );

    final exportBtn = Tooltip(
      message: isAr ? 'تصدير بيانات المبيعات والفواتير إلى ملف CSV / Excel' : 'Export sales & invoices data to CSV / Excel',
      child: FilledButton.tonalIcon(
        onPressed: onExport,
        icon: const Icon(Icons.file_download_outlined, size: 18),
        label: Text(strings.exportExcelCsv, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );

    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleWidget,
                const SizedBox(height: 12),
                dropdownWidget,
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: exportBtn,
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: titleWidget),
                const SizedBox(width: 16),
                SizedBox(width: 260, child: dropdownWidget),
                const SizedBox(width: 10),
                exportBtn,
              ],
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Active Event Details Badge Card
  // ---------------------------------------------------------------------------
  Widget _buildEventDetailsBadgeCard({
    required EventModel event,
    required ColorScheme colorScheme,
    required CountryCurrency activeCountry,
    required bool isAr,
    required bool isHi,
  }) {
    final statusColor = event.isActive ? Colors.green : Colors.amber.shade800;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                '${isAr ? "الحملة المحددة: " : "Selected Campaign: "}${event.eventName}',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14, color: colorScheme.primary),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              // Company Chip
              _buildMetaPill(
                icon: Icons.business_rounded,
                label: event.targetCompany,
                colorScheme: colorScheme,
              ),
              // Store Chain & Branch Chip
              if (event.retailChainName.isNotEmpty)
                _buildMetaPill(
                  icon: Icons.storefront_rounded,
                  label: event.branchesDisplaySummary.isNotEmpty ? '${event.retailChainName} - ${event.branchesDisplaySummary}' : event.retailChainName,
                  colorScheme: colorScheme,
                ),
              // Minimum Spend Chip
              _buildMetaPill(
                icon: Icons.monetization_on_outlined,
                label: event.minimumSpend > 0
                    ? '${isAr ? "الحد الأدنى: " : "Min: "}${event.minimumSpend.toStringAsFixed(0)} ${activeCountry.currencySymbol}'
                    : (isAr ? 'بدون حد أدنى' : 'No Min Spend'),
                colorScheme: colorScheme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaPill({
    required IconData icon,
    required String label,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
          ),
        ],
      ),
    );
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
  }) {
    final acceptanceRate = totalScans > 0 ? ((acceptedInvoices / totalScans) * 100).toStringAsFixed(0) : '100';

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        int crossAxisCount = 4;
        double childAspectRatio = 1.9;
        if (width < 600) {
          crossAxisCount = 1;
          childAspectRatio = 2.4;
        } else if (width < 960) {
          crossAxisCount = 2;
          childAspectRatio = 2.1;
        }

        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
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
              subtitle: isAr ? 'إجمالي القطع المستخرجة بالفواتير' : 'Total items extracted from receipts',
              icon: Icons.inventory_2_rounded,
              accentColor: Colors.purple.shade700,
              badgeText: isAr ? 'قطع مباعة' : 'Units',
              colorScheme: colorScheme,
              tooltip: isAr ? 'إجمالي كميات الأصناف المشتراة في كافة الفواتير' : 'Total quantity of items purchased',
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
        padding: const EdgeInsets.all(16),
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
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accentColor, size: 22),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badgeText,
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              value,
              style: GoogleFonts.cairo(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: colorScheme.onSurface,
                letterSpacing: -0.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtitle,
              style: GoogleFonts.cairo(
                fontSize: 10,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. M3 Navigation / Segmented Button Tabs
  // ---------------------------------------------------------------------------
  Widget _buildTabsSelector({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required int productsCount,
    required int receiptsCount,
    required int branchesCount,
    required bool isMobile,
  }) {
    final prodLabel = isMobile
        ? (isAr ? 'الأصناف' : (isHi ? 'उत्पाद' : 'Products'))
        : (isAr ? '🏆 الأصناف والمنتجات الأكثر مبيعاً' : (isHi ? '🏆 सर्वाधिक बिकने वाले उत्पाद' : '🏆 Top Selling Products & Brands'));
    final recLabel = isMobile
        ? (isAr ? 'الفواتير' : (isHi ? 'रसीदें' : 'Invoices'))
        : (isAr ? '📑 سجل الفواتير والمرفوعات' : (isHi ? '📑 रसीदें और इनवॉइस लॉग' : '📑 Invoices & Receipts Log'));
    final branchLabel = isMobile
        ? (isAr ? 'الفروع' : (isHi ? 'शाखाएं' : 'Branches'))
        : (isAr ? '🏬 توزيع الفروع والسلاسل' : (isHi ? '🏬 शाखावार बिक्री' : '🏬 Store & Branch Distribution'));

    return M3ConnectedButtonGroup<int>(
      height: isMobile ? 44 : 48,
      borderRadius: 16,
      isExpanded: isMobile,
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
          label: recLabel,
          icon: Icons.receipt_long_rounded,
          badgeText: '$receiptsCount',
          tooltip: isAr ? 'سجل كافة الفواتير المفحوصة والمرفوعة وتفاصيل أصناف كل فاتورة' : 'Audited transactions and receipt scan logs',
        ),
        M3ButtonSegment<int>(
          value: 2,
          label: branchLabel,
          icon: Icons.storefront_rounded,
          badgeText: '$branchesCount',
          tooltip: isAr ? 'توزيع المبيعات وعدد الفواتير حسب الفروع ومنافذ البيع' : 'Breakdown of sales by retail branch and supermarket chain',
        ),
      ],
      selectedValue: _selectedTab,
      onSelected: (val) => setState(() => _selectedTab = val),
    );
  }

  // ---------------------------------------------------------------------------
  // 5. Tab 1: Product Sales & Ranking Breakdown
  // ---------------------------------------------------------------------------
  Widget _buildProductsBreakdownTab({
    required List<_ProductStat> sortedProducts,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required CountryCurrency activeCountry,
    required bool isMobile,
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

    final searchInputWidget = SizedBox(
      width: isMobile ? double.infinity : 280,
      child: TextField(
        controller: _productSearchController,
        style: GoogleFonts.cairo(fontSize: 13),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: isAr ? 'بحث باسم الصنف أو الباركود...' : 'Search item name or barcode...',
          hintStyle: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: colorScheme.primary),
          suffixIcon: _productSearchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () {
                    _productSearchController.clear();
                    setState(() {});
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );

    final sortSelectorWidget = Row(
      mainAxisSize: isMobile ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: isMobile ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
      children: [
        Text(
          isAr ? 'ترتيب حسب: ' : 'Sort by: ',
          style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        SegmentedButton<String>(
          segments: [
            ButtonSegment<String>(
              value: 'QTY',
              label: Text(isAr ? 'الكمية' : 'Qty', style: GoogleFonts.cairo(fontSize: 11)),
              icon: const Icon(Icons.format_list_numbered_rounded, size: 14),
            ),
            ButtonSegment<String>(
              value: 'REVENUE',
              label: Text(isAr ? 'القيمة' : 'Revenue', style: GoogleFonts.cairo(fontSize: 11)),
              icon: const Icon(Icons.attach_money_rounded, size: 14),
            ),
            ButtonSegment<String>(
              value: 'NAME',
              label: Text(isAr ? 'الاسم' : 'Name', style: GoogleFonts.cairo(fontSize: 11)),
              icon: const Icon(Icons.sort_by_alpha_rounded, size: 14),
            ),
          ],
          selected: {_productSortBy},
          onSelectionChanged: (set) => setState(() => _productSortBy = set.first),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );

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
          // Filter & Search Header
          if (isMobile)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchInputWidget,
                const SizedBox(height: 10),
                sortSelectorWidget,
              ],
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                searchInputWidget,
                sortSelectorWidget,
              ],
            ),
          const SizedBox(height: 18),

          // Product Ranking Cards
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayedList.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final prod = displayedList[index];
              final double progress = maxQty > 0 ? (prod.totalQty / maxQty) : 0.0;

              // Color for medal ranks
              Color rankColor = colorScheme.primary;
              String medalEmoji = '';
              if (index == 0) {
                rankColor = const Color(0xFFD4AF37); // Gold
                medalEmoji = '🥇 ';
              } else if (index == 1) {
                rankColor = const Color(0xFF9E9E9E); // Silver
                medalEmoji = '🥈 ';
              } else if (index == 2) {
                rankColor = const Color(0xFFCD7F32); // Bronze
                medalEmoji = '🥉 ';
              }

              return Container(
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: index < 3 ? rankColor.withValues(alpha: 0.5) : colorScheme.outlineVariant.withValues(alpha: 0.4),
                    width: index < 3 ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Rank Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: rankColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: rankColor.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            '$medalEmoji#${index + 1}',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: rankColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Product Name & Barcode
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
                              ),
                              if (prod.barcode.isNotEmpty)
                                Text(
                                  'Barcode: ${prod.barcode}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    color: Colors.grey,
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
                          index == 0 ? const Color(0xFFD4AF37) : (index == 1 ? colorScheme.primary : colorScheme.secondary),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 6. Tab 2: Invoices & Receipts Log
  // ---------------------------------------------------------------------------
  Widget _buildReceiptsLogTab({
    required List<QueryDocumentSnapshot> transactions,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required CountryCurrency activeCountry,
    required bool isMobile,
  }) {
    final query = _receiptSearchController.text.toLowerCase().trim();
    final filtered = transactions.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final recNum = data['receipt_number']?.toString().toLowerCase() ?? '';
      final phone = data['customerPhone']?.toString().toLowerCase() ?? '';
      final name = data['customerName']?.toString().toLowerCase() ?? '';
      final branch = (data['branch_detected'] ?? data['store_chain_detected'] ?? '').toString().toLowerCase();

      final bool isValid = data['isValid'] == true ||
          (data['is_valid'] == true) ||
          ((data['unfulfilled_conditions'] as List?)?.isEmpty ?? true);

      if (_receiptStatusFilter == 'VALID' && !isValid) return false;
      if (_receiptStatusFilter == 'INVALID' && isValid) return false;

      if (query.isEmpty) return true;
      return recNum.contains(query) || phone.contains(query) || name.contains(query) || branch.contains(query);
    }).toList();

    final searchInputWidget = SizedBox(
      width: isMobile ? double.infinity : 320,
      child: TextField(
        controller: _receiptSearchController,
        style: GoogleFonts.cairo(fontSize: 13),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: isAr ? 'بحث برقم الفاتورة، الفرع، العميل، الهاتف...' : 'Search receipt #, store, customer, phone...',
          hintStyle: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: colorScheme.primary),
          suffixIcon: _receiptSearchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () {
                    _receiptSearchController.clear();
                    setState(() {});
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );

    final statusFilterWidget = SegmentedButton<String>(
      segments: [
        ButtonSegment<String>(
          value: 'ALL',
          label: Text(isAr ? 'الكل' : 'All', style: GoogleFonts.cairo(fontSize: 11)),
        ),
        ButtonSegment<String>(
          value: 'VALID',
          label: Text(isAr ? 'المقبولة' : 'Accepted', style: GoogleFonts.cairo(fontSize: 11)),
          icon: const Icon(Icons.check_circle_outline_rounded, size: 14, color: Colors.green),
        ),
        ButtonSegment<String>(
          value: 'INVALID',
          label: Text(isAr ? 'المرفوضة' : 'Rejected', style: GoogleFonts.cairo(fontSize: 11)),
          icon: const Icon(Icons.cancel_outlined, size: 14, color: Colors.red),
        ),
      ],
      selected: {_receiptStatusFilter},
      onSelectionChanged: (set) => setState(() => _receiptStatusFilter = set.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );

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
          // Filter & Search Controls
          if (isMobile)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchInputWidget,
                const SizedBox(height: 10),
                statusFilterWidget,
              ],
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                searchInputWidget,
                statusFilterWidget,
              ],
            ),
          const SizedBox(height: 18),

          // Invoices List
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_outlined, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    Text(
                      isAr ? 'لا توجد فواتير مطابقة لبحثك.' : 'No receipts matched your search.',
                      style: GoogleFonts.cairo(fontSize: 14, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final doc = filtered[index];
                final data = doc.data() as Map<String, dynamic>;
                final recNum = data['receipt_number']?.toString() ?? (isAr ? 'بدون رقم' : 'No Number');
                final total = (data['target_company_total'] ?? data['total_value'] as num?)?.toDouble() ?? 0.0;
                final bool isValid = data['isValid'] == true ||
                    (data['is_valid'] == true) ||
                    ((data['unfulfilled_conditions'] as List?)?.isEmpty ?? true);
                final custName = data['customerName']?.toString() ?? '';
                final custPhone = data['customerPhone']?.toString() ?? '';
                final storeChain = data['store_chain_detected']?.toString() ?? '';
                final branch = data['branch_detected']?.toString() ?? '';
                final recDate = data['receipt_date']?.toString() ?? '';
                final extractedProds = (data['extracted_products'] as List?) ?? [];

                return Container(
                  padding: EdgeInsets.all(isMobile ? 12 : 14),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      // Status Icon
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isValid ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isValid ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          color: isValid ? Colors.green.shade700 : Colors.red.shade700,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Info Column
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    '#$recNum',
                                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.onSurface),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: isValid ? Colors.green.shade100 : Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isValid ? (isAr ? 'مقبولة' : 'Valid') : (isAr ? 'مرفوضة' : 'Invalid'),
                                    style: GoogleFonts.cairo(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isValid ? Colors.green.shade800 : Colors.red.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (storeChain.isNotEmpty || branch.isNotEmpty) '$storeChain - $branch',
                                if (recDate.isNotEmpty) recDate,
                                if (custName.isNotEmpty || custPhone.isNotEmpty) '$custName $custPhone',
                              ].join(' • '),
                              style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // Spend Value & Details Action Button
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${total.toStringAsFixed(1)} ${activeCountry.currencySymbol}',
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          OutlinedButton.icon(
                            onPressed: () => _showReceiptDetailsModal(
                              context: context,
                              data: data,
                              colorScheme: colorScheme,
                              strings: strings,
                              isAr: isAr,
                              activeCountry: activeCountry,
                            ),
                            icon: const Icon(Icons.visibility_outlined, size: 13),
                            label: Text(
                              isAr ? 'التفاصيل (${extractedProds.length})' : 'Details (${extractedProds.length})',
                              style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 7. Tab 3: Branches & Store Distribution
  // ---------------------------------------------------------------------------
  Widget _buildBranchesBreakdownTab({
    required List<_BranchStat> sortedBranches,
    required double totalSales,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required CountryCurrency activeCountry,
    required bool isMobile,
  }) {
    if (sortedBranches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Center(
          child: Text(
            isAr ? 'لا توجد بيانات فروع مسجلة حتى الآن.' : 'No branch data recorded yet.',
            style: GoogleFonts.cairo(fontSize: 15, color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final maxRevenue = sortedBranches.isNotEmpty ? sortedBranches.first.totalRevenue : 1.0;

    return Container(
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
              Icon(Icons.storefront_rounded, color: colorScheme.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isAr ? 'توزيع المبيعات وعدد الفواتير حسب الفروع ومنافذ البيع' : 'Branch & Retail Chain Performance Breakdown',
                  style: GoogleFonts.cairo(fontSize: isMobile ? 13 : 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sortedBranches.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final branch = sortedBranches[index];
              final double progress = maxRevenue > 0 ? (branch.totalRevenue / maxRevenue) : 0.0;
              final double percentageOfTotal = totalSales > 0 ? ((branch.totalRevenue / totalSales) * 100) : 0.0;

              return Container(
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.location_on_rounded, size: 16, color: colorScheme.onSecondaryContainer),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  branch.branchName,
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.onSurface),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${branch.totalRevenue.toStringAsFixed(1)} ${activeCountry.currencySymbol}',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 13, color: colorScheme.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${isAr ? "عدد الفواتير: " : "Receipts Count: "}${branch.receiptCount}',
                          style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                        Text(
                          '${percentageOfTotal.toStringAsFixed(1)}% ${isAr ? "من إجمالي المبيعات" : "of total sales"}',
                          style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.secondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 8. Modals & Dialogs (Receipt Details)
  // ---------------------------------------------------------------------------
  void _showReceiptDetailsModal({
    required BuildContext context,
    required Map<String, dynamic> data,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required CountryCurrency activeCountry,
  }) {
    final recNum = data['receipt_number']?.toString() ?? (isAr ? 'بدون رقم' : 'No Number');
    final recDate = data['receipt_date']?.toString() ?? '';
    final total = (data['target_company_total'] ?? data['total_value'] as num?)?.toDouble() ?? 0.0;
    final custName = data['customerName']?.toString() ?? '';
    final custPhone = data['customerPhone']?.toString() ?? '';
    final aiMessage = data['aiMessage']?.toString() ?? '';
    final imageUrl = data['image_url']?.toString() ?? '';
    final storeChain = data['store_chain_detected']?.toString() ?? '';
    final branch = data['branch_detected']?.toString() ?? '';
    final extractedProds = (data['extracted_products'] as List?) ?? [];

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 650, maxHeight: 750),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.receipt_long_rounded, color: colorScheme.primary, size: 26),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${isAr ? "تفاصيل الفاتورة: #" : "Invoice Details: #"}$recNum',
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15, color: colorScheme.onSurface),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(height: 24),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header info pills
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (storeChain.isNotEmpty || branch.isNotEmpty)
                            _buildMetaPill(icon: Icons.storefront_rounded, label: '$storeChain - $branch', colorScheme: colorScheme),
                          if (recDate.isNotEmpty)
                            _buildMetaPill(icon: Icons.calendar_today_rounded, label: recDate, colorScheme: colorScheme),
                          if (custName.isNotEmpty)
                            _buildMetaPill(icon: Icons.person_rounded, label: custName, colorScheme: colorScheme),
                          if (custPhone.isNotEmpty)
                            _buildMetaPill(icon: Icons.phone_rounded, label: custPhone, colorScheme: colorScheme),
                          _buildMetaPill(
                            icon: Icons.payments_rounded,
                            label: '${total.toStringAsFixed(1)} ${activeCountry.currencySymbol}',
                            colorScheme: colorScheme,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Image preview if available
                      if (imageUrl.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            height: 140,
                            width: double.infinity,
                            color: colorScheme.surfaceContainerHighest,
                            child: Image.network(
                              imageUrl,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image_rounded)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],

                      // Items Table
                      Text(
                        isAr ? '📦 الأصناف المستخرجة بالفاتورة:' : '📦 Extracted Items:',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.primary),
                      ),
                      const SizedBox(height: 8),
                      if (extractedProds.isEmpty)
                        Text(
                          isAr ? 'لم يتم حفظ تفاصيل أصناف لهذه الفاتورة.' : 'No item details stored for this receipt.',
                          style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Table(
                              columnWidths: const {
                                0: FlexColumnWidth(2.5),
                                1: FlexColumnWidth(1.8),
                                2: FlexColumnWidth(1.2),
                                3: FlexColumnWidth(1.0),
                              },
                              children: [
                                TableRow(
                                  decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(isAr ? 'اسم المنتج' : 'Item Name', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(isAr ? 'الباركود' : 'Barcode', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(isAr ? 'السعر' : 'Price', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(isAr ? 'الكمية' : 'Qty', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11)),
                                    ),
                                  ],
                                ),
                                ...extractedProds.map((item) {
                                  final name = item['name']?.toString() ?? '';
                                  final barcode = item['barcode']?.toString() ?? '-';
                                  final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                                  final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                                  final isTarget = item['isTargetCompany'] == true;

                                  return TableRow(
                                    decoration: BoxDecoration(
                                      color: isTarget ? Colors.green.withValues(alpha: 0.06) : Colors.transparent,
                                    ),
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text(
                                          name,
                                          style: GoogleFonts.cairo(
                                            fontSize: 11,
                                            fontWeight: isTarget ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text(barcode.isNotEmpty ? barcode : '-', style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text('${price.toStringAsFixed(1)} ${activeCountry.currencySymbol}', style: const TextStyle(fontSize: 11)),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text('$qty', style: const TextStyle(fontSize: 11)),
                                      ),
                                    ],
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),

                      // AI Report
                      if (aiMessage.isNotEmpty) ...[
                        Text(
                          isAr ? '🤖 تقرير الذكاء الاصطناعي:' : '🤖 AI Validation Report:',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.primary),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            aiMessage,
                            style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurface),
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
  }

  // ---------------------------------------------------------------------------
  // 9. Export Analytics CSV
  // ---------------------------------------------------------------------------
  void _exportAnalyticsCsv({
    required BuildContext context,
    required List<QueryDocumentSnapshot> filteredTransactions,
    required List<_ProductStat> sortedProducts,
    required bool isAr,
    required CountryCurrency activeCountry,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final buffer = StringBuffer();
      buffer.writeln(isAr
          ? '=== تقرير مبيعات الأصناف الأكثر طلباً ==='
          : '=== Top Selling Products Report ===');
      buffer.writeln(isAr ? 'الترتيب,اسم المنتج,الباركود,الكمية المباعة,إجمالي القيمة (${activeCountry.currencySymbol})' : 'Rank,Item Name,Barcode,Quantity Sold,Total Revenue (${activeCountry.currencySymbol})');

      for (int i = 0; i < sortedProducts.length; i++) {
        final p = sortedProducts[i];
        buffer.writeln('${i + 1},"${p.name}","${p.barcode}",${p.totalQty},${p.totalRevenue.toStringAsFixed(2)}');
      }

      buffer.writeln('');
      buffer.writeln(isAr
          ? '=== سجل الفواتير والمعاملات المفحوصة ==='
          : '=== Audited Invoices Transactions ===');
      buffer.writeln(isAr
          ? 'رقم الفاتورة,تاريخ الفاتورة,السلسلة,الفرع,اسم العميل,رقم الهاتف,قيمة المشتريات,الحالة,تاريخ التسجيل'
          : 'Receipt Number,Receipt Date,Chain,Branch,Customer Name,Phone Number,Amount,Status,Timestamp');

      for (final doc in filteredTransactions) {
        final data = doc.data() as Map<String, dynamic>;
        final recNum = data['receipt_number'] ?? '';
        final recDate = data['receipt_date'] ?? '';
        final chain = data['store_chain_detected'] ?? '';
        final branch = data['branch_detected'] ?? '';
        final custName = data['customerName'] ?? '';
        final custPhone = data['customerPhone'] ?? '';
        final val = data['target_company_total'] ?? data['total_value'] ?? 0;
        final bool isValid = data['isValid'] == true || (data['is_valid'] == true);
        final status = isValid ? (isAr ? 'مقبولة' : 'Accepted') : (isAr ? 'مرفوضة' : 'Rejected');
        final ts = data['timestamp'] != null ? (data['timestamp'] as Timestamp).toDate().toString() : '';

        buffer.writeln('"$recNum","$recDate","$chain","$branch","$custName","$custPhone","$val","$status","$ts"');
      }

      await Clipboard.setData(ClipboardData(text: buffer.toString()));

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isAr
                ? 'تم نسخ ملف التقرير الشامل (CSV) إلى الحافظة بنجاح!'
                : 'Comprehensive Analytics Report (CSV) copied to clipboard!',
          ),
          backgroundColor: Colors.teal.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('${isAr ? "خطأ في التصدير: " : "Export error: "}$e')),
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
