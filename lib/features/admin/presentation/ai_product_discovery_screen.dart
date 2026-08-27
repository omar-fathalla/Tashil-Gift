import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/services/ai_product_discovery_service.dart';
import '../../../core/services/firebase_service.dart';

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

            // 3. Reactive Discovered Items List / Table
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
                          child: Text('خطأ في جلب البيانات: ${snapshot.error}', style: TextStyle(color: cs.error)),
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

  // --- Header Banner with Stats ---
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
        gradient: LinearGradient(
          colors: [
            cs.primaryContainer.withValues(alpha: 0.9),
            cs.secondaryContainer.withValues(alpha: 0.7),
          ],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: cs.primary.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: const Icon(Icons.auto_fix_high_rounded, color: Colors.white, size: 28),
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
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      strings.discoveryHubSubtitle,
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // KPI Stats Row
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
                  final isNarrow = constraints.maxWidth < 600;
                  if (isNarrow) {
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _buildKpiChip(cs, Icons.pending_actions_rounded, '$pendingCount', strings.pendingTabLabel, Colors.orange),
                        _buildKpiChip(cs, Icons.check_circle_rounded, '$approvedCount', strings.approvedTabLabel, Colors.green),
                        _buildKpiChip(cs, Icons.business_rounded, '$companiesCount', isAr ? 'شركات' : 'Companies', Colors.blue),
                        _buildKpiChip(cs, Icons.receipt_long_rounded, '$totalFrequency', isAr ? 'رصد فواتير' : 'Invoices', Colors.purple),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: _buildKpiChip(cs, Icons.pending_actions_rounded, '$pendingCount', strings.pendingTabLabel, Colors.orange)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildKpiChip(cs, Icons.check_circle_rounded, '$approvedCount', strings.approvedTabLabel, Colors.green)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildKpiChip(cs, Icons.business_rounded, '$companiesCount', isAr ? 'شركات' : 'Companies', Colors.blue)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildKpiChip(cs, Icons.receipt_long_rounded, '$totalFrequency', isAr ? 'رصد فواتير' : 'Invoices', Colors.purple)),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildKpiChip(ColorScheme cs, IconData icon, String value, String label, Color accentColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: accentColor),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface)),
              Text(label, style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant)),
            ],
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Company selector & Search & Action buttons
          Row(
            children: [
              // Company Dropdown
              if (firestore != null)
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: firestore.collection('companies').snapshots(),
                  builder: (context, snapshot) {
                    final docs = snapshot.data?.docs ?? [];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCompany,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          items: [
                            DropdownMenuItem(
                              value: 'all',
                              child: Text(strings.allCompaniesFilter, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                            ...docs.map((d) {
                              final data = d.data();
                              final slug = (data['slug'] ?? data['code'] ?? d.id).toString();
                              final name = (data['name'] ?? slug).toString();
                              return DropdownMenuItem(
                                value: slug,
                                child: Text(name, style: GoogleFonts.cairo(fontSize: 13)),
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
                ),
              const SizedBox(width: 12),

              // Search field
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  decoration: InputDecoration(
                    hintText: isAr ? 'بحث بالاسم، الباركود، أو العلامة...' : 'Search by name, barcode...',
                    hintStyle: GoogleFonts.cairo(fontSize: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                    prefixIcon: Icon(Icons.search_rounded, size: 20, color: cs.onSurfaceVariant),
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Deep Scan Historical Invoices Button
              OutlinedButton.icon(
                onPressed: () => _showScanHistoricalDialog(context, strings, isAr, cs, discoveryService),
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: Text(strings.scanPastInvoicesAction, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Row 2: Status Segmented Button Group & Bulk Approve Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // M3 Segmented Button Group
              SegmentedButton<String>(
                segments: [
                  ButtonSegment<String>(
                    value: 'pending',
                    label: Text(strings.pendingTabLabel, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12)),
                    icon: const Icon(Icons.hourglass_top_rounded, size: 16),
                  ),
                  ButtonSegment<String>(
                    value: 'approved',
                    label: Text(strings.approvedTabLabel, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12)),
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                  ),
                  ButtonSegment<String>(
                    value: 'rejected',
                    label: Text(strings.rejectedTabLabel, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12)),
                    icon: const Icon(Icons.do_not_disturb_on_outlined, size: 16),
                  ),
                ],
                selected: {_selectedStatus},
                onSelectionChanged: (newSelection) {
                  setState(() => _selectedStatus = newSelection.first);
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),

              // Bulk Approve Button (Only in Pending status)
              if (_selectedStatus == 'pending')
                StreamBuilder<List<DiscoveredProductDocument>>(
                  stream: discoveryService.streamDiscoveredProducts(companySlug: _selectedCompany, status: 'pending'),
                  builder: (context, snapshot) {
                    final items = snapshot.data ?? [];
                    if (items.isEmpty) return const SizedBox.shrink();

                    return FilledButton.icon(
                      onPressed: _isProcessingBulk
                          ? null
                          : () => _handleBulkApprove(context, items, strings, isAr, cs, discoveryService),
                      icon: _isProcessingBulk
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.cloud_upload_rounded, size: 18),
                      label: Text(
                        '${strings.approveAllPendingAction} (${items.length})',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Discovered Product Card ---
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
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isApproved
              ? Colors.green.withValues(alpha: 0.3)
              : (isPending ? cs.primary.withValues(alpha: 0.25) : cs.outlineVariant.withValues(alpha: 0.3)),
          width: isPending ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isPending ? cs.primary.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isApproved ? Colors.green.shade50 : cs.secondaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isApproved ? Icons.verified_rounded : Icons.shopping_bag_outlined,
                  color: isApproved ? Colors.green.shade700 : cs.primary,
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
                        // Price Badge
                        if (item.averagePrice > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${item.averagePrice.toStringAsFixed(1)} ج.م',
                              style: GoogleFonts.cairo(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: cs.onPrimaryContainer,
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
                          _buildTagChip(cs, Icons.branding_watermark_rounded, item.brand, Colors.indigo),
                        if (item.category.isNotEmpty)
                          _buildTagChip(cs, Icons.category_outlined, item.category, Colors.teal),
                        if (item.barcode.isNotEmpty)
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: item.barcode));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('تم نسخ الباركود: ${item.barcode}'), duration: const Duration(seconds: 2)),
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: _buildTagChip(cs, Icons.qr_code_2_rounded, item.barcode, Colors.purple, isClickable: true),
                          ),
                        _buildTagChip(cs, Icons.repeat_rounded, '${item.invoiceFrequency} ${isAr ? 'مرات رصد' : 'scans'}', Colors.orange),
                        if (item.retailChains.isNotEmpty)
                          _buildTagChip(cs, Icons.storefront_rounded, item.retailChains.join(' • '), Colors.blueGrey),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // Actions Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Company name
              Text(
                '🏢 ${item.companyName}',
                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.primary),
              ),

              // Action buttons
              Row(
                children: [
                  if (isPending) ...[
                    // Edit details button
                    IconButton(
                      tooltip: strings.editItemTitle,
                      icon: const Icon(Icons.edit_outlined, size: 20),
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
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Approve & Sync button
                    FilledButton.icon(
                      onPressed: () => _handleApproveSingle(context, item, strings, isAr, cs, discoveryService),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: Text(strings.approveSingleItemAction, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ] else if (isApproved) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_rounded, size: 16, color: Colors.green.shade700),
                          const SizedBox(width: 6),
                          Text(
                            isAr ? 'تم الاعتماد بالكتالوج' : 'Cataloged',
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Text(
                      isAr ? 'مستبعد' : 'Dismissed',
                      style: GoogleFonts.cairo(fontSize: 12, color: cs.outline),
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

  Widget _buildTagChip(ColorScheme cs, IconData icon, String text, Color color, {bool isClickable = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.cairo(
              fontSize: 11,
              fontWeight: isClickable ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
          if (isClickable) ...[
            const SizedBox(width: 4),
            Icon(Icons.copy_rounded, size: 11, color: color.withValues(alpha: 0.7)),
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
          color: cs.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_outline_rounded, size: 48, color: Colors.green.shade600),
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

  // --- Handlers & Dialogs ---

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
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isAr
                      ? 'تم اعتماد الصنف "${item.canonicalName}" وإضافته لكتالوج ${item.companyName} بنجاح! 🚀'
                      : 'Approved "${item.canonicalName}" and saved to ${item.companyName} catalog! 🚀',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء الحفظ: $e'), backgroundColor: cs.error),
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
        title: Text(isAr ? 'تأكيد الاعتماد الجماعي 🚀' : 'Confirm Bulk Approval 🚀', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        content: Text(
          isAr
              ? 'هل أنت متأكد من رغبتك في اعتماد كافة الأصناف المكتشفة (${items.length} صنف) ودمجها مباشرة في كتالوج الشركات؟'
              : 'Are you sure you want to approve all ${items.length} discovered products and merge them into company catalogs?',
          style: GoogleFonts.cairo(fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(isAr ? 'إلغاء' : 'Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
            child: Text(isAr ? 'تأكيد واعتماد الكل' : 'Confirm & Approve All', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
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
          content: Text(strings.productsSavedSuccess(saved, isAr ? 'الشركات' : 'Companies')),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: cs.error),
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
        title: Text(strings.editItemTitle, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: strings.canonicalNameField, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: brandCtrl,
                      decoration: InputDecoration(labelText: strings.brandField, border: const OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: categoryCtrl,
                      decoration: InputDecoration(labelText: strings.discoveryCategoryField, border: const OutlineInputBorder()),
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
                      decoration: InputDecoration(labelText: strings.discoveryBarcodeField, border: const OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: unitSizeCtrl,
                      decoration: InputDecoration(labelText: strings.unitSizeField, border: const OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: strings.averagePriceField, border: const OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(isAr ? 'إلغاء' : 'Cancel')),
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
            child: Text(strings.approveSingleItemAction),
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
            const Icon(Icons.travel_explore_rounded, color: Colors.blue),
            const SizedBox(width: 10),
            Text(isAr ? 'استكشاف الفواتير التاريخية' : 'Deep Invoice Scan', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LinearProgressIndicator(),
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
        content: Text(
          isAr
              ? 'اكتمل الفحص! تم رصد وتحديث الأصناف المكتشفة بنجاح.'
              : 'Scan complete! Discovered items updated in inbox.',
        ),
        backgroundColor: Colors.green.shade700,
      ),
    );
  }
}
