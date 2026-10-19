import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/services/ai_product_discovery_service.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/widgets/m3_button_groups.dart';

class AiProductDiscoveryScreen extends ConsumerStatefulWidget {
  const AiProductDiscoveryScreen({super.key});

  @override
  ConsumerState<AiProductDiscoveryScreen> createState() => _AiProductDiscoveryScreenState();
}

class _AiProductDiscoveryScreenState extends ConsumerState<AiProductDiscoveryScreen> {
  String _selectedCompany = 'all';
  String _selectedStatus = 'pending';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  bool _isProcessingBulk = false;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _companiesStream;

  Stream<QuerySnapshot<Map<String, dynamic>>> _getCompaniesStream(FirebaseFirestore firestore) {
    return _companiesStream ??= firestore.collection('companies').snapshots();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(ref);
    final isAr = ref.watch(localeProvider).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;
    final discoveryService = ref.watch(aiProductDiscoveryServiceProvider);
    final firestore = ref.watch(firestoreProvider);

    return RepaintBoundary(
      child: Scaffold(
        backgroundColor: cs.surfaceContainerLowest,
        body: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            // 1. Header Banner & KPI Dashboard
            SliverToBoxAdapter(
              child: _buildHeaderBanner(context, strings, isAr, cs, discoveryService),
            ),

            // 2. Filter & Actions Toolbar
            SliverToBoxAdapter(
              child: _buildFilterToolbar(context, strings, isAr, cs, firestore, discoveryService),
            ),

            // 3. Reactive Discovered Items List
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              sliver: StreamBuilder<List<DiscoveredProductDocument>>(
                stream: discoveryService.streamDiscoveredProducts(
                  companySlug: _selectedCompany,
                  status: _selectedStatus,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(60),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Text(
                            'خطأ في جلب البيانات: ${snapshot.error}',
                            style: GoogleFonts.cairo(color: cs.error),
                          ),
                        ),
                      ),
                    );
                  }

                  final allItems = snapshot.data ?? [];
                  final filteredItems = allItems.where((item) {
                    if (_searchQuery.isEmpty) return true;
                    final q = _searchQuery.toLowerCase();
                    return item.canonicalName.toLowerCase().contains(q) ||
                        item.rawProductName.toLowerCase().contains(q) ||
                        item.barcode.contains(q) ||
                        item.brand.toLowerCase().contains(q) ||
                        item.category.toLowerCase().contains(q);
                  }).toList();

                  if (filteredItems.isEmpty) {
                    return SliverToBoxAdapter(
                      child: _buildEmptyState(context, strings, isAr, cs),
                    );
                  }

                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = filteredItems[index];
                        return _buildDiscoveredProductCard(
                          context,
                          item,
                          strings,
                          isAr,
                          cs,
                          discoveryService,
                        );
                      },
                      childCount: filteredItems.length,
                    ),
                  );
                },
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }

  // --- Header Banner with Stats & Governance Criteria ---
  Widget _buildHeaderBanner(
    BuildContext context,
    AppStrings strings,
    bool isAr,
    ColorScheme cs,
    AiProductDiscoveryService discoveryService,
  ) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Title & Icon
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: cs.onPrimaryContainer,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.discoveryHubTitle,
                      style: GoogleFonts.cairo(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      strings.discoveryHubSubtitle,
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // KPI Stats Row (Derived from Theme ColorScheme)
          StreamBuilder<List<DiscoveredProductDocument>>(
            stream: discoveryService.streamDiscoveredProducts(companySlug: 'all', status: 'all'),
            builder: (context, snapshot) {
              final items = snapshot.data ?? [];
              final pendingCount = items.where((i) => i.status == 'pending').length;
              final approvedCount = items.where((i) => i.status == 'approved').length;
              final companiesCount = items.map((i) => i.companySlug).toSet().length;
              final totalFrequency = items.fold<int>(0, (acc, i) => acc + i.invoiceFrequency);

              return LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 650;
                  if (isNarrow) {
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildKpiCard(cs, Icons.hourglass_top_rounded, '$pendingCount', strings.pendingTabLabel, cs.tertiary, cs.tertiaryContainer),
                        _buildKpiCard(cs, Icons.verified_rounded, '$approvedCount', strings.approvedTabLabel, cs.primary, cs.primaryContainer),
                        _buildKpiCard(cs, Icons.business_rounded, '$companiesCount', isAr ? 'شركات' : 'Companies', cs.secondary, cs.secondaryContainer),
                        _buildKpiCard(cs, Icons.receipt_long_rounded, '$totalFrequency', isAr ? 'رصد فواتير' : 'Invoices', cs.onSurfaceVariant, cs.surfaceContainerHighest),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: _buildKpiCard(cs, Icons.hourglass_top_rounded, '$pendingCount', strings.pendingTabLabel, cs.tertiary, cs.tertiaryContainer)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildKpiCard(cs, Icons.verified_rounded, '$approvedCount', strings.approvedTabLabel, cs.primary, cs.primaryContainer)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildKpiCard(cs, Icons.business_rounded, '$companiesCount', isAr ? 'شركات' : 'Companies', cs.secondary, cs.secondaryContainer)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildKpiCard(cs, Icons.receipt_long_rounded, '$totalFrequency', isAr ? 'رصد فواتير' : 'Invoices', cs.onSurfaceVariant, cs.surfaceContainerHighest)),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: 16),

          // 5 Criteria Governance Pills (AIR-72) with Unified Theme Palette
          _buildCriteriaGovernanceBar(cs, isAr),
        ],
      ),
    );
  }

  Widget _buildCriteriaGovernanceBar(ColorScheme cs, bool isAr) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                isAr ? 'معايير حوكمة الحصاد التلقائي للأصناف (AIR-72):' : 'AI Harvest Governance Criteria (AIR-72):',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildCriteriaPill(cs, Icons.qr_code_2_rounded, isAr ? 'باركود دولي (8-14 رقم)' : 'Valid Barcode (8-14)'),
              _buildCriteriaPill(cs, Icons.repeat_rounded, isAr ? 'تكرار ≥ 2 أو سلسلتين' : 'Min 2 Scans / Chains'),
              _buildCriteriaPill(cs, Icons.block_rounded, isAr ? 'استبعاد السطور العامة' : 'No Generic/Service'),
              _buildCriteriaPill(cs, Icons.payments_outlined, isAr ? 'سعر ساري (> 0 ج.م)' : 'Valid Price (>0)'),
              _buildCriteriaPill(cs, Icons.verified_user_outlined, isAr ? 'مطابقة علامات الشركة' : 'Brand Whitelist'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCriteriaPill(ColorScheme cs, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(
    ColorScheme cs,
    IconData icon,
    String value,
    String label,
    Color iconColor,
    Color containerColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: containerColor.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Filter & Actions Toolbar ---
  Widget _buildFilterToolbar(
    BuildContext context,
    AppStrings strings,
    bool isAr,
    ColorScheme cs,
    FirebaseFirestore? firestore,
    AiProductDiscoveryService discoveryService,
  ) {
    return StreamBuilder<List<DiscoveredProductDocument>>(
      stream: discoveryService.streamDiscoveredProducts(
        companySlug: _selectedCompany,
        status: 'all',
      ),
      builder: (context, snapshot) {
        final companyItems = snapshot.data ?? [];
        final pendingCount = companyItems.where((i) => i.status == 'pending').length;
        final approvedCount = companyItems.where((i) => i.status == 'approved').length;
        final rejectedCount = companyItems.where((i) => i.status == 'rejected').length;
        final pendingItems = companyItems.where((i) => i.status == 'pending').toList();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Company selector, Search Field, and Deep Scan Action
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 750;
                  final companyDropdown = firestore != null
                      ? StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _getCompaniesStream(firestore),
                          builder: (context, compSnapshot) {
                            final docs = compSnapshot.data?.docs ?? [];
                            return Container(
                              height: 44,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedCompany,
                                  icon: Icon(Icons.keyboard_arrow_down_rounded, color: cs.onSurfaceVariant),
                                  items: [
                                    DropdownMenuItem(
                                      value: 'all',
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.business_rounded, size: 16, color: cs.primary),
                                          const SizedBox(width: 8),
                                          Text(
                                            strings.allCompaniesFilter,
                                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: cs.onSurface),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ...docs.map((d) {
                                      final data = d.data();
                                      final slug = (data['slug'] ?? data['code'] ?? d.id).toString();
                                      final name = (data['name'] ?? slug).toString();
                                      return DropdownMenuItem(
                                        value: slug,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.apartment_rounded, size: 16, color: cs.onSurfaceVariant),
                                            const SizedBox(width: 8),
                                            Text(name, style: GoogleFonts.cairo(fontSize: 13, color: cs.onSurface)),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) setState(() => _selectedCompany = val);
                                  },
                                ),
                              ),
                            );
                          },
                        )
                      : const SizedBox.shrink();

                  final searchField = SizedBox(
                    height: 44,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      decoration: InputDecoration(
                        hintText: isAr ? 'بحث بالاسم، الباركود، أو العلامة التجارية...' : 'Search by name, barcode, brand...',
                        hintStyle: GoogleFonts.cairo(fontSize: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                        prefixIcon: Icon(Icons.search_rounded, size: 20, color: cs.primary),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        isDense: true,
                        filled: true,
                        fillColor: cs.surfaceContainerLowest,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.primary, width: 1.5),
                        ),
                      ),
                    ),
                  );

                  final scanButton = SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: () => _showScanHistoricalDialog(context, strings, isAr, cs, discoveryService),
                      icon: Icon(Icons.travel_explore_rounded, size: 18, color: cs.primary),
                      label: Text(
                        strings.scanPastInvoicesAction,
                        style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.primary),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
                        backgroundColor: cs.surfaceContainerLowest,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  );

                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(child: companyDropdown),
                            const SizedBox(width: 10),
                            scanButton,
                          ],
                        ),
                        const SizedBox(height: 10),
                        searchField,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      companyDropdown,
                      const SizedBox(width: 12),
                      Expanded(child: searchField),
                      const SizedBox(width: 12),
                      scanButton,
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),

              // Row 2: Unified M3 Connected Button Group & Bulk Management Actions
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 800;

                  // M3 Connected Button Group for Status Tabs
                  final statusButtonGroup = M3ConnectedButtonGroup<String>(
                    height: 42,
                    borderRadius: 14,
                    showCheckmark: false,
                    selectedValue: _selectedStatus,
                    onSelected: (val) {
                      setState(() => _selectedStatus = val);
                    },
                    segments: [
                      M3ButtonSegment<String>(
                        value: 'pending',
                        label: strings.pendingTabLabel,
                        icon: Icons.hourglass_top_rounded,
                        selectedIcon: Icons.hourglass_full_rounded,
                        badgeText: '$pendingCount',
                        tooltip: isAr ? 'الأصناف المستخرجة بانتظار المراجعة والاعتماد' : 'Pending items awaiting catalog review',
                      ),
                      M3ButtonSegment<String>(
                        value: 'approved',
                        label: strings.approvedTabLabel,
                        icon: Icons.verified_outlined,
                        selectedIcon: Icons.verified_rounded,
                        badgeText: '$approvedCount',
                        tooltip: isAr ? 'الأصناف المعتمدة والمدمجة بالكتالوج' : 'Approved items in company catalog',
                      ),
                      M3ButtonSegment<String>(
                        value: 'rejected',
                        label: strings.rejectedTabLabel,
                        icon: Icons.block_rounded,
                        selectedIcon: Icons.block_rounded,
                        badgeText: '$rejectedCount',
                        tooltip: isAr ? 'الأصناف المستبعدة لعدم استيفاء المعايير' : 'Dismissed items not meeting criteria',
                      ),
                    ],
                  );

                  // Bulk Actions for Pending Status
                  Widget? bulkActions;
                  if (_selectedStatus == 'pending') {
                    bulkActions = Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Clean Inbox via 5 Criteria Button (AIR-72)
                        OutlinedButton.icon(
                          onPressed: () => _showCleanupInboxDialog(context, strings, isAr, cs, discoveryService),
                          icon: Icon(Icons.cleaning_services_rounded, size: 16, color: cs.tertiary),
                          label: Text(
                            strings.cleanInboxCriteriaAction,
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: cs.tertiary,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: cs.tertiary.withValues(alpha: 0.5), width: 1.2),
                            backgroundColor: cs.tertiaryContainer.withValues(alpha: 0.15),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),

                        // Bulk Approve Button
                        if (pendingItems.isNotEmpty)
                          FilledButton.icon(
                            onPressed: _isProcessingBulk
                                ? null
                                : () => _handleBulkApprove(context, pendingItems, strings, isAr, cs, discoveryService),
                            icon: _isProcessingBulk
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                                  )
                                : const Icon(Icons.done_all_rounded, size: 18),
                            label: Text(
                              '${strings.approveAllPendingAction} (${pendingItems.length})',
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                      ],
                    );
                  }

                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        statusButtonGroup,
                        if (bulkActions != null) ...[
                          const SizedBox(height: 12),
                          bulkActions,
                        ],
                      ],
                    );
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      statusButtonGroup,
                      ?bulkActions,
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Discovered Product Card (M3 Elevated Design) ---
  Widget _buildDiscoveredProductCard(
    BuildContext context,
    DiscoveredProductDocument item,
    AppStrings strings,
    bool isAr,
    ColorScheme cs,
    AiProductDiscoveryService discoveryService,
  ) {
    final isPending = item.status == 'pending';
    final isApproved = item.status == 'approved';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isApproved
              ? cs.primary.withValues(alpha: 0.3)
              : (isPending ? cs.tertiary.withValues(alpha: 0.35) : cs.outlineVariant.withValues(alpha: 0.3)),
          width: isPending ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Leading Icon / Brand Chip
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isApproved
                      ? cs.primaryContainer
                      : (isPending ? cs.tertiaryContainer.withValues(alpha: 0.6) : cs.surfaceContainerHighest),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isApproved
                      ? Icons.verified_rounded
                      : (isPending ? Icons.shopping_bag_outlined : Icons.block_rounded),
                  color: isApproved
                      ? cs.onPrimaryContainer
                      : (isPending ? cs.onTertiaryContainer : cs.onSurfaceVariant),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),

              // Product Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.canonicalName.isNotEmpty ? item.canonicalName : item.rawProductName,
                            style: GoogleFonts.cairo(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        // 5/5 Criteria Compliant Badge
                        if (item.isCriteriaCompliant == true) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified_rounded, size: 14, color: cs.primary),
                                const SizedBox(width: 4),
                                Text(
                                  strings.criteriaCompliantBadge,
                                  style: GoogleFonts.cairo(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: cs.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        // Price Badge
                        if (item.averagePrice > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${item.averagePrice.toStringAsFixed(1)} ج.م',
                              style: GoogleFonts.cairo(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: cs.onSecondaryContainer,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Raw name if different from canonical
                    if (item.rawProductName.isNotEmpty && item.rawProductName != item.canonicalName)
                      Text(
                        '${isAr ? 'المسمى في البون:' : 'POS Receipt text:'} "${item.rawProductName}"',
                        style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    const SizedBox(height: 8),

                    // Metadata Chips Row (Brand, Category, Barcode, Retail Chains, Frequency)
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (item.brand.isNotEmpty)
                          _buildTagChip(cs, Icons.branding_watermark_rounded, item.brand),
                        if (item.category.isNotEmpty)
                          _buildTagChip(cs, Icons.category_outlined, item.category),
                        if (item.barcode.isNotEmpty)
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: item.barcode));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.content_copy_rounded, color: Colors.white, size: 16),
                                      const SizedBox(width: 8),
                                      Text(
                                        'تم نسخ الباركود: ${item.barcode}',
                                        style: GoogleFonts.cairo(),
                                      ),
                                    ],
                                  ),
                                  duration: const Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: _buildTagChip(cs, Icons.qr_code_2_rounded, item.barcode, isClickable: true, isAccent: true),
                          ),
                        _buildTagChip(cs, Icons.repeat_rounded, '${item.invoiceFrequency} ${isAr ? 'مرات رصد' : 'scans'}'),
                        if (item.retailChains.isNotEmpty)
                          _buildTagChip(cs, Icons.storefront_rounded, item.retailChains.join(' • ')),
                      ],
                    ),

                    // Rejection reason banner if rejected
                    if (item.status == 'rejected' && item.rejectionReason.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: cs.errorContainer.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.error.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.report_problem_outlined, size: 16, color: cs.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${strings.rejectionReasonLabel} ${item.rejectionReason}',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 10),

          // Actions Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Company name with Google Icon (NO EMOJIS)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.business_rounded, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    item.companyName,
                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurface),
                  ),
                ],
              ),

              // Action buttons
              Row(
                children: [
                  if (isPending) ...[
                    // Edit details button
                    IconButton(
                      tooltip: strings.editItemTitle,
                      icon: Icon(Icons.edit_outlined, size: 20, color: cs.onSurfaceVariant),
                      onPressed: () => _showEditProductDialog(context, item, strings, isAr, cs),
                    ),
                    const SizedBox(width: 6),

                    // Dismiss button
                    OutlinedButton.icon(
                      onPressed: () => discoveryService.rejectDiscoveredDocuments([item.id]),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: Text(strings.rejectSingleItemAction, style: GoogleFonts.cairo(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.error,
                        side: BorderSide(color: cs.error.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Approve & Sync button
                    FilledButton.icon(
                      onPressed: () => _handleApproveSingle(context, item, strings, isAr, cs, discoveryService),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: Text(
                        strings.approveSingleItemAction,
                        style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ] else if (isApproved) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_rounded, size: 16, color: cs.primary),
                          const SizedBox(width: 6),
                          Text(
                            isAr ? 'تم الاعتماد بالكتالوج' : 'Cataloged',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isAr ? 'مستبعد' : 'Dismissed',
                          style: GoogleFonts.cairo(fontSize: 12, color: cs.outline),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _handleApproveSingle(context, item, strings, isAr, cs, discoveryService),
                          icon: const Icon(Icons.replay_rounded, size: 14),
                          label: Text(isAr ? 'إعادة اعتماد' : 'Re-approve', style: GoogleFonts.cairo(fontSize: 11)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: cs.primary,
                            side: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTagChip(
    ColorScheme cs,
    IconData icon,
    String text, {
    bool isClickable = false,
    bool isAccent = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isAccent
            ? cs.primaryContainer.withValues(alpha: 0.5)
            : cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isAccent
              ? cs.primary.withValues(alpha: 0.3)
              : cs.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: isAccent ? cs.primary : cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.cairo(
              fontSize: 11,
              fontWeight: isClickable ? FontWeight.bold : FontWeight.normal,
              color: isAccent ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
          ),
          if (isClickable) ...[
            const SizedBox(width: 4),
            Icon(Icons.content_copy_rounded, size: 11, color: cs.primary),
          ],
        ],
      ),
    );
  }

  // --- Empty State ---
  Widget _buildEmptyState(BuildContext context, AppStrings strings, bool isAr, ColorScheme cs) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.task_alt_rounded, size: 48, color: cs.primary),
            ),
            const SizedBox(height: 16),
            Text(
              strings.emptyDiscoveryStateTitle,
              style: GoogleFonts.cairo(fontSize: 17, fontWeight: FontWeight.bold, color: cs.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Text(
                strings.emptyDiscoveryStateSubtitle,
                style: GoogleFonts.cairo(fontSize: 13, color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Handlers & Dialogs (Zero Emojis, Google Icons Only) ---

  Future<void> _handleApproveSingle(
    BuildContext context,
    DiscoveredProductDocument item,
    AppStrings strings,
    bool isAr,
    ColorScheme cs,
    AiProductDiscoveryService discoveryService,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await discoveryService.approveAndMergeDiscoveredDocuments(documents: [item]);
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: cs.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isAr
                      ? 'تم اعتماد الصنف "${item.canonicalName}" وإضافته لكتالوج ${item.companyName} بنجاح!'
                      : 'Approved "${item.canonicalName}" and saved to ${item.companyName} catalog!',
                  style: GoogleFonts.cairo(color: cs.onPrimaryContainer, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: cs.primaryContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء الحفظ: $e', style: GoogleFonts.cairo()),
          backgroundColor: cs.error,
        ),
      );
    }
  }

  Future<void> _handleBulkApprove(
    BuildContext context,
    List<DiscoveredProductDocument> items,
    AppStrings strings,
    bool isAr,
    ColorScheme cs,
    AiProductDiscoveryService discoveryService,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.done_all_rounded, color: cs.primary),
            const SizedBox(width: 10),
            Text(
              isAr ? 'تأكيد الاعتماد الجماعي' : 'Confirm Bulk Approval',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          isAr
              ? 'هل أنت متأكد من رغبتك في اعتماد كافة الأصناف المكتشفة (${items.length} صنف) ودمجها مباشرة في كتالوج الشركات؟'
              : 'Are you sure you want to approve all ${items.length} discovered products and merge them into company catalogs?',
          style: GoogleFonts.cairo(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAr ? 'إلغاء' : 'Cancel', style: GoogleFonts.cairo()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.onPrimary),
            child: Text(
              isAr ? 'تأكيد واعتماد الكل' : 'Confirm & Approve All',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessingBulk = true;
    });

    try {
      final saved = await discoveryService.approveAndMergeDiscoveredDocuments(
        documents: items,
      );

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            strings.productsSavedSuccess(saved, isAr ? 'الشركات' : 'Companies'),
            style: GoogleFonts.cairo(color: cs.onPrimaryContainer, fontWeight: FontWeight.bold),
          ),
          backgroundColor: cs.primaryContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('حدث خطأ: $e', style: GoogleFonts.cairo()),
          backgroundColor: cs.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessingBulk = false);
      }
    }
  }

  Future<void> _showEditProductDialog(
    BuildContext context,
    DiscoveredProductDocument item,
    AppStrings strings,
    bool isAr,
    ColorScheme cs,
  ) async {
    final nameCtrl = TextEditingController(text: item.canonicalName);
    final brandCtrl = TextEditingController(text: item.brand);
    final categoryCtrl = TextEditingController(text: item.category);
    final barcodeCtrl = TextEditingController(text: item.barcode);
    final unitSizeCtrl = TextEditingController(text: item.unitSize);
    final priceCtrl = TextEditingController(text: item.averagePrice > 0 ? item.averagePrice.toString() : '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.edit_note_rounded, color: cs.primary),
            const SizedBox(width: 8),
            Text(strings.editItemTitle, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: strings.canonicalNameField,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: brandCtrl,
                      decoration: InputDecoration(
                        labelText: strings.brandField,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: categoryCtrl,
                      decoration: InputDecoration(
                        labelText: strings.discoveryCategoryField,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: barcodeCtrl,
                      decoration: InputDecoration(
                        labelText: strings.discoveryBarcodeField,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: unitSizeCtrl,
                      decoration: InputDecoration(
                        labelText: strings.unitSizeField,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: strings.averagePriceField,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isAr ? 'إلغاء' : 'Cancel', style: GoogleFonts.cairo()),
          ),
          FilledButton(
            onPressed: () async {
              final discoveryService = ref.read(aiProductDiscoveryServiceProvider);
              final updatedItem = item.copyWith(
                canonicalName: nameCtrl.text.trim(),
                brand: brandCtrl.text.trim(),
                category: categoryCtrl.text.trim(),
                barcode: barcodeCtrl.text.trim(),
                unitSize: unitSizeCtrl.text.trim(),
                averagePrice: double.tryParse(priceCtrl.text.trim()) ?? item.averagePrice,
              );
              Navigator.pop(ctx);
              await _handleApproveSingle(context, updatedItem, strings, isAr, cs, discoveryService);
            },
            style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.onPrimary),
            child: Text(strings.approveSingleItemAction, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _showScanHistoricalDialog(
    BuildContext context,
    AppStrings strings,
    bool isAr,
    ColorScheme cs,
    AiProductDiscoveryService discoveryService,
  ) async {
    final companySlug = _selectedCompany != 'all' ? _selectedCompany : 'unilever';
    final companyName = _selectedCompany != 'all' ? _selectedCompany : 'يونيليفر';
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context, rootNavigator: true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.travel_explore_rounded, color: cs.primary),
            const SizedBox(width: 10),
            Text(
              isAr ? 'استكشاف الفواتير التاريخية' : 'Deep Invoice Scan',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(color: cs.primary, backgroundColor: cs.primaryContainer),
            const SizedBox(height: 16),
            Text(
              isAr
                  ? 'جاري فحص بونات الكاشير المسجلة لاستخراج الأصناف والباركودات الجديدة...'
                  : 'Scanning past receipts to harvest new products & barcodes...',
              style: GoogleFonts.cairo(fontSize: 13),
            ),
          ],
        ),
      ),
    );

    try {
      await discoveryService.scanHistoricalTransactions(
        companySlug: companySlug,
        companyName: companyName,
      );
    } catch (_) {}

    nav.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.task_alt_rounded, color: cs.onPrimaryContainer),
            const SizedBox(width: 8),
            Text(
              isAr
                  ? 'اكتمل الفحص! تم رصد وتحديث الأصناف المكتشفة بنجاح.'
                  : 'Scan complete! Discovered items updated in inbox.',
              style: GoogleFonts.cairo(color: cs.onPrimaryContainer, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: cs.primaryContainer,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showCleanupInboxDialog(
    BuildContext context,
    AppStrings strings,
    bool isAr,
    ColorScheme cs,
    AiProductDiscoveryService discoveryService,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.cleaning_services_rounded, color: cs.tertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                strings.cleanInboxCriteriaAction,
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAr
                  ? 'سيتم فحص كافة الأصناف المعلقة في صندوق الانتظار وفقاً للمعايير الخمسة المعتمدة (AIR-72):'
                  : 'All pending items will be audited against the 5 governance criteria (AIR-72):',
              style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildCriteriaCheckItem(cs, isAr ? '1. الباركود الدولي الصريح (8 إلى 14 رقماً إنجليزياً فقط)' : '1. International Barcode (8-14 digits only)'),
            _buildCriteriaCheckItem(cs, isAr ? '2. حد التكرار والتأكيد (ظهور مرتين فأكثر أو بسلسلتين)' : '2. Minimum frequency (2+ scans or 2+ chains)'),
            _buildCriteriaCheckItem(cs, isAr ? '3. استبعاد السطور العامة (أكياس، توصيل، بونص، إكرامية، خصومات)' : '3. Exclude generic & service lines (bags, tips, etc.)'),
            _buildCriteriaCheckItem(cs, isAr ? '4. منطقية وصحة السعر (أكبر من صفر وجنيه واحد فأكثر)' : '4. Sanity price check (>= 1.0 EGP)'),
            _buildCriteriaCheckItem(cs, isAr ? '5. المطابقة لقائمة علامات الشركة (يونيليفر، كادبوري، إدكو، الضحى)' : '5. Company brand whitelist verification'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isAr
                          ? 'الأصناف غير المطابقة لن تُحذف نهائياً، بل ستُنقل لتبويب "المستبعدة" مع توثيق سبب الاستبعاد بدقة لحماية ونظافة الكتالوج.'
                          : 'Non-compliant items will be moved to "Dismissed" with clear audit reasons.',
                      style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAr ? 'إلغاء' : 'Cancel', style: GoogleFonts.cairo()),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.cleaning_services_rounded, size: 16),
            label: Text(
              isAr ? 'بدء التنظيف وتطبيق المعايير' : 'Start Cleanup',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(backgroundColor: cs.tertiary, foregroundColor: cs.onTertiary),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context, rootNavigator: true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Text(
              isAr ? 'جاري فحص وتطبيق المعايير...' : 'Applying Criteria...',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ],
        ),
        content: Text(
          isAr
              ? 'جاري تدقيق أصناف صندوق الانتظار واستبعاد غير المطابق وتوثيق أسباب الاستبعاد بدقة...'
              : 'Auditing pending products, moving non-compliant items to dismissed...',
          style: GoogleFonts.cairo(fontSize: 13),
        ),
      ),
    );

    try {
      final summary = await discoveryService.cleanupExistingPendingInbox(
        companySlug: _selectedCompany,
      );
      nav.pop();

      if (context.mounted) {
        _showCleanupSummaryDialog(context, summary, isAr, cs);
      }
    } catch (e) {
      nav.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء تنظيف الصندوق: $e', style: GoogleFonts.cairo()),
          backgroundColor: cs.error,
        ),
      );
    }
  }

  Widget _buildCriteriaCheckItem(ColorScheme cs, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  void _showCleanupSummaryDialog(
    BuildContext context,
    DiscoveryCleanupSummary summary,
    bool isAr,
    ColorScheme cs,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.task_alt_rounded, color: cs.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isAr ? 'تقرير تنظيف الصندوق وتطبيق المعايير' : 'Inbox Cleanup Report',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isAr
                    ? 'تم فحص وتدقيق كافة الأصناف المعلقة في صندوق الانتظار وتحديثها بنجاح:'
                    : 'All pending items audited against criteria and updated successfully:',
                style: GoogleFonts.cairo(fontSize: 13, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              // Summary KPI Cards
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryMetricCard(
                      cs: cs,
                      title: isAr ? 'تم فحصها' : 'Total Audited',
                      value: '${summary.totalProcessed}',
                      color: cs.secondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildSummaryMetricCard(
                      cs: cs,
                      title: isAr ? 'مستوفٍ ومؤكد' : 'Retained (5/5)',
                      value: '${summary.totalRetained}',
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildSummaryMetricCard(
                      cs: cs,
                      title: isAr ? 'تم استبعادها' : 'Dismissed',
                      value: '${summary.totalRejected}',
                      color: cs.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                isAr ? 'تفاصيل أسباب الاستبعاد التلقائي:' : 'Dismissal Reasons Breakdown:',
                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurface),
              ),
              const SizedBox(height: 8),
              _buildReasonRow(cs, isAr ? 'باركود غير صالح (أقل من 8 أرقام أو غير رقمي):' : 'Invalid Barcode (<8 digits):', summary.invalidBarcodeCount),
              _buildReasonRow(cs, isAr ? 'ظهور لمرة واحدة فقط (أقل من جلستي رصد):' : 'Single scan frequency (<2):', summary.singleFrequencyCount),
              _buildReasonRow(cs, isAr ? 'سطور عامة وخدمية (أكياس، توصيل، بونص):' : 'Generic & Service lines:', summary.genericItemCount),
              _buildReasonRow(cs, isAr ? 'سعر غير صالح (صفر أو غير محدد):' : 'Invalid price (<=0):', summary.invalidPriceCount),
              _buildReasonRow(cs, isAr ? 'علامة تجارية غير تابعة للشركة المعنية:' : 'Unmatched company brand:', summary.unmatchedBrandCount),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.onPrimary),
            child: Text(isAr ? 'إغلاق' : 'Close', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryMetricCard({
    required ColorScheme cs,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(value, style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(
            title,
            style: GoogleFonts.cairo(fontSize: 10, color: cs.onSurface),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildReasonRow(ColorScheme cs, String label, int count) {
    final hasCount = count > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurface))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: hasCount ? cs.errorContainer.withValues(alpha: 0.4) : cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: hasCount ? cs.error.withValues(alpha: 0.3) : cs.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: hasCount ? cs.error : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
