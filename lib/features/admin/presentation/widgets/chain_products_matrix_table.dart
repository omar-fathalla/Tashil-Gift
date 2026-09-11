import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/constants/country_currency_config.dart';
import '../../../../core/widgets/m3_button_groups.dart';
import '../../../../core/services/chain_products_intelligence_service.dart';
import '../../domain/chain_product_model.dart';
import 'product_price_history_dialog.dart';

/// Omni-Chain Competitive Price Intelligence Matrix Table
/// جدول مصفوفة أسعار ومنتجات السلاسل التجارية بتثبيت الأعمدة والتمرير الأفقي الذكي لكافة المنافسين
class ChainProductsMatrixTable extends ConsumerStatefulWidget {
  final List<ChainProductItem> products;
  final List<String> distinctChains;

  const ChainProductsMatrixTable({
    super.key,
    required this.products,
    required this.distinctChains,
  });

  @override
  ConsumerState<ChainProductsMatrixTable> createState() => _ChainProductsMatrixTableState();
}

class _ChainProductsMatrixTableState extends ConsumerState<ChainProductsMatrixTable> {
  int _currentPage = 0;
  int _rowsPerPage = 25;
  bool _isDenseMode = true; // High-Density mode by default for sleek, low-height rows
  bool _showAllRegisteredChains = true; // Show all 16 canonical chains by default
  int? _hoveredRowIndex; // Synchronized hover state between pinned and scrollable panes
  final ScrollController _horizontalScrollController = ScrollController();

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChainProductsMatrixTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    final maxPages = (widget.products.length / _rowsPerPage).ceil();
    if (_currentPage >= maxPages && maxPages > 0) {
      setState(() {
        _currentPage = maxPages - 1;
      });
    }
  }

  void _scrollForward() {
    if (_horizontalScrollController.hasClients) {
      final current = _horizontalScrollController.offset;
      final max = _horizontalScrollController.position.maxScrollExtent;
      _horizontalScrollController.animateTo(
        (current + 320).clamp(0.0, max),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _scrollBackward() {
    if (_horizontalScrollController.hasClients) {
      final current = _horizontalScrollController.offset;
      final max = _horizontalScrollController.position.maxScrollExtent;
      _horizontalScrollController.animateTo(
        (current - 320).clamp(0.0, max),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _scrollToStart() {
    if (_horizontalScrollController.hasClients) {
      _horizontalScrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _copyBarcode(String barcode, BuildContext context, bool isAr) {
    Clipboard.setData(ClipboardData(text: barcode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(
              isAr ? 'تم نسخ الباركود: $barcode' : 'Barcode copied: $barcode',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
        backgroundColor: Colors.teal.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = AppStrings.of(ref);
    final activeCountry = ref.watch(activeCountryProvider);
    final currency = activeCountry.currencySymbol;
    final isAr = ref.isArabic;
    final totalCount = widget.products.length;

    // Resolve competitor chains list (excluding Fathalla which is always pinned)
    final List<String> competitorChains;
    if (_showAllRegisteredChains) {
      competitorChains = ChainProductsIntelligenceService.canonicalRetailChains
          .where((c) => c != 'أسواق فتح الله')
          .toList();
    } else {
      competitorChains = widget.distinctChains
          .where((c) => c != 'أسواق فتح الله')
          .toList();
    }

    if (widget.products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 48, color: cs.outlineVariant),
              const SizedBox(height: 12),
              Text(
                strings.noProductsFound,
                style: GoogleFonts.cairo(fontSize: 15, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final totalPages = (totalCount / _rowsPerPage).ceil();
    final startIndex = _currentPage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage > totalCount) ? totalCount : startIndex + _rowsPerPage;
    final pageProducts = widget.products.sublist(startIndex, endIndex);

    final double headerHeight = _isDenseMode ? 42.0 : 48.0;
    final double rowHeight = _isDenseMode ? 50.0 : 68.0;

    // Pinned column widths
    final double colProductWidth = _isDenseMode ? 245.0 : 275.0;
    final double colBrandWidth = _isDenseMode ? 68.0 : 78.0;
    final double colFathallaWidth = _isDenseMode ? 145.0 : 155.0;
    final double totalPinnedWidth = colProductWidth + colBrandWidth + colFathallaWidth;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      color: cs.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // -------------------------------------------------------------------
          // 1. Table Top Toolbar (Chains View Toggle, Density, & Quick Scroll)
          // -------------------------------------------------------------------
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                // Left Group: Title, Items Count, & Chains Mode Toggle
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.table_chart_rounded, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      isAr ? 'مصفوفة الأسعار المقارنة' : 'Price Comparison Matrix',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$totalCount ${isAr ? 'صنف' : 'items'}',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Toggle: All Registered Chains vs Active Observed Chains
                    Tooltip(
                      message: isAr
                          ? 'عرض كافة السلاسل التجارية المعتمدة في السوق حتى لو لم يرصد الصنف فيها بعد'
                          : 'Toggle displaying all registered enterprise chains',
                      child: FilterChip(
                        avatar: Icon(
                          _showAllRegisteredChains ? Icons.view_column_rounded : Icons.filter_alt_outlined,
                          size: 14,
                          color: _showAllRegisteredChains ? cs.primary : cs.onSurfaceVariant,
                        ),
                        label: Text(
                          _showAllRegisteredChains
                              ? (isAr ? 'كافة السلاسل المنافسة (16)' : 'All 16 Chains')
                              : (isAr ? 'السلاسل النشطة فقط' : 'Active Chains Only'),
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _showAllRegisteredChains ? cs.primary : cs.onSurfaceVariant,
                          ),
                        ),
                        selected: _showAllRegisteredChains,
                        selectedColor: cs.primaryContainer.withValues(alpha: 0.5),
                        backgroundColor: cs.surfaceContainerLowest,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: _showAllRegisteredChains
                                ? cs.primary.withValues(alpha: 0.5)
                                : cs.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        onSelected: (val) {
                          setState(() {
                            _showAllRegisteredChains = val;
                          });
                        },
                      ),
                    ),
                  ],
                ),

                // Right Group: Horizontal Scroll Controls & Density Selector
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Horizontal Quick Scroll Buttons
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tooltip(
                            message: isAr ? 'تمرير المنافسين للبداية' : 'Scroll to start',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: _scrollToStart,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(Icons.first_page_rounded, size: 16, color: cs.primary),
                              ),
                            ),
                          ),
                          Container(width: 1, height: 14, color: cs.outlineVariant.withValues(alpha: 0.5)),
                          Tooltip(
                            message: isAr ? 'تمرير المنافسين لليمين' : 'Scroll right',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: isAr ? _scrollBackward : _scrollForward,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(Icons.chevron_right_rounded, size: 18, color: cs.primary),
                              ),
                            ),
                          ),
                          Container(width: 1, height: 14, color: cs.outlineVariant.withValues(alpha: 0.5)),
                          Tooltip(
                            message: isAr ? 'تمرير المنافسين لليسار' : 'Scroll left',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: isAr ? _scrollForward : _scrollBackward,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(Icons.chevron_left_rounded, size: 18, color: cs.primary),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Density Toggle (عرض مدمج فائق الرشاقة vs عرض عادي)
                    Tooltip(
                      message: strings.densityToggleTooltip,
                      child: M3ConnectedButtonGroup<bool>(
                        height: 30,
                        borderRadius: 8,
                        isExpanded: false,
                        selectedValue: _isDenseMode,
                        onSelected: (val) => setState(() => _isDenseMode = val),
                        segments: [
                          M3ButtonSegment(
                            value: true,
                            label: strings.compactTableDensity,
                            icon: Icons.density_small_rounded,
                          ),
                          M3ButtonSegment(
                            value: false,
                            label: strings.standardTableDensity,
                            icon: Icons.density_medium_rounded,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // -------------------------------------------------------------------
          // 2. Dual-Pane Table Body: Pinned Baseline Pane + Scrollable Competitors Pane
          // -------------------------------------------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------------------------------------------------------------
              // PANE A: Pinned Sticky Columns (Product + Brand + Fathalla Baseline)
              // ---------------------------------------------------------------
              SizedBox(
                width: totalPinnedWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pinned Header Row
                    _buildPinnedHeader(
                      cs: cs,
                      isAr: isAr,
                      headerHeight: headerHeight,
                      colProductWidth: colProductWidth,
                      colBrandWidth: colBrandWidth,
                      colFathallaWidth: colFathallaWidth,
                    ),

                    // Pinned Data Rows
                    ...pageProducts.asMap().entries.map((entry) {
                      final rowIndex = entry.key;
                      final item = entry.value;
                      final isHovered = _hoveredRowIndex == rowIndex;
                      final isEven = rowIndex % 2 == 0;
                      final rowColor = isHovered
                          ? cs.primary.withValues(alpha: 0.08)
                          : (isEven ? Colors.transparent : cs.surfaceContainerHighest.withValues(alpha: 0.22));

                      return MouseRegion(
                        onEnter: (_) => setState(() => _hoveredRowIndex = rowIndex),
                        onExit: (_) => setState(() => _hoveredRowIndex = null),
                        child: Container(
                          height: rowHeight,
                          decoration: BoxDecoration(
                            color: rowColor,
                            border: Border(
                              bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.25), width: 0.8),
                            ),
                          ),
                          child: Row(
                            children: [
                              // 1. Product & Barcode Cell
                              _buildProductCell(
                                item: item,
                                width: colProductWidth,
                                cs: cs,
                                isAr: isAr,
                                strings: strings,
                              ),

                              // 2. Brand Chip Cell
                              _buildBrandCell(
                                item: item,
                                width: colBrandWidth,
                                cs: cs,
                              ),

                              // 3. Fathalla Baseline Price Cell
                              _buildFathallaCell(
                                item: item,
                                width: colFathallaWidth,
                                cs: cs,
                                currency: currency,
                                isAr: isAr,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),

              // ---------------------------------------------------------------
              // ELEVATION DIVIDER: Subtle vertical line with depth shadow
              // ---------------------------------------------------------------
              Container(
                width: 1,
                height: headerHeight + (pageProducts.length * rowHeight),
                color: cs.outlineVariant.withValues(alpha: 0.65),
              ),

              // ---------------------------------------------------------------
              // PANE B: Horizontally Scrollable Competitors & Analysis Pane
              // ---------------------------------------------------------------
              Expanded(
                child: Scrollbar(
                  controller: _horizontalScrollController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  thickness: 8,
                  radius: const Radius.circular(4),
                  child: SingleChildScrollView(
                    controller: _horizontalScrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Competitors Header Row
                        _buildCompetitorsHeader(
                          competitorChains: competitorChains,
                          cs: cs,
                          isAr: isAr,
                          strings: strings,
                          headerHeight: headerHeight,
                        ),

                        // Competitors Data Rows
                        ...pageProducts.asMap().entries.map((entry) {
                          final rowIndex = entry.key;
                          final item = entry.value;
                          final isHovered = _hoveredRowIndex == rowIndex;
                          final isEven = rowIndex % 2 == 0;
                          final rowColor = isHovered
                              ? cs.primary.withValues(alpha: 0.08)
                              : (isEven ? Colors.transparent : cs.surfaceContainerHighest.withValues(alpha: 0.22));

                          return MouseRegion(
                            onEnter: (_) => setState(() => _hoveredRowIndex = rowIndex),
                            onExit: (_) => setState(() => _hoveredRowIndex = null),
                            child: Container(
                              height: rowHeight,
                              decoration: BoxDecoration(
                                color: rowColor,
                                border: Border(
                                  bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.25), width: 0.8),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Dynamic Competitor Price Cells
                                  ...competitorChains.map((chain) {
                                    return _buildCompetitorPriceCell(
                                      chain: chain,
                                      item: item,
                                      cs: cs,
                                      currency: currency,
                                      isAr: isAr,
                                    );
                                  }),

                                  // Summary Column: Fathalla Market Position
                                  _buildPositionCell(
                                    item: item,
                                    cs: cs,
                                    currency: currency,
                                    isAr: isAr,
                                    strings: strings,
                                  ),

                                  // Summary Column: Price Variance %
                                  _buildVarianceCell(
                                    item: item,
                                    cs: cs,
                                  ),

                                  // Summary Column: Best Promo %
                                  _buildPromoCell(
                                    item: item,
                                    cs: cs,
                                  ),

                                  // Summary Column: Proof & Log Button
                                  _buildActionCell(
                                    item: item,
                                    cs: cs,
                                    isAr: isAr,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Divider
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),

          // -------------------------------------------------------------------
          // 3. M3 Standard Pagination & Navigation Bar
          // -------------------------------------------------------------------
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: cs.surfaceContainerLow,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                // Rows Count Summary
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.format_list_numbered_rounded, size: 15, color: cs.primary),
                    const SizedBox(width: 6),
                    Text(
                      isAr
                          ? 'عرض ${startIndex + 1} - $endIndex من إجمالي $totalCount منتج'
                          : 'Showing ${startIndex + 1} - $endIndex of $totalCount products',
                      style: GoogleFonts.cairo(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),

                // Rows Per Page Selector & Page Navigation Controls
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      strings.rowsPerPageLabel,
                      style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: 6),
                    DropdownButton<int>(
                      value: _rowsPerPage,
                      isDense: true,
                      borderRadius: BorderRadius.circular(10),
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 25, child: Text('25')),
                        DropdownMenuItem(value: 50, child: Text('50')),
                        DropdownMenuItem(value: 100, child: Text('100')),
                      ],
                      onChanged: (val) {
                        if (val != null && val != _rowsPerPage) {
                          setState(() {
                            _rowsPerPage = val;
                            _currentPage = 0;
                          });
                        }
                      },
                    ),
                    const SizedBox(width: 12),

                    // First Page Button
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.first_page_rounded, size: 18),
                      tooltip: isAr ? 'الصفحة الأولى' : 'First page',
                      onPressed: _currentPage > 0 ? () => setState(() => _currentPage = 0) : null,
                    ),

                    // Previous Page Button
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.chevron_right_rounded, size: 20),
                      tooltip: isAr ? 'السابق' : 'Previous',
                      onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
                    ),

                    // Page Indicator Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isAr
                            ? 'صفحة ${_currentPage + 1} من ${totalPages > 0 ? totalPages : 1}'
                            : 'Page ${_currentPage + 1} of ${totalPages > 0 ? totalPages : 1}',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                      ),
                    ),

                    // Next Page Button
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.chevron_left_rounded, size: 20),
                      tooltip: isAr ? 'التالي' : 'Next',
                      onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
                    ),

                    // Last Page Button
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.last_page_rounded, size: 18),
                      tooltip: isAr ? 'الصفحة الأخيرة' : 'Last page',
                      onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage = totalPages - 1) : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SUB-BUILDERS: PINNED PANE
  // ===========================================================================

  Widget _buildPinnedHeader({
    required ColorScheme cs,
    required bool isAr,
    required double headerHeight,
    required double colProductWidth,
    required double colBrandWidth,
    required double colFathallaWidth,
  }) {
    return Container(
      height: headerHeight,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6), width: 1.2)),
      ),
      child: Row(
        children: [
          // Column 1: Product / Barcode Header
          Container(
            width: colProductWidth,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inventory_2_rounded, size: 14, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  isAr ? 'المنتج / الباركود' : 'Product / Barcode',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w700,
                    fontSize: _isDenseMode ? 11.5 : 12.5,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),

          // Column 2: Brand Header
          Container(
            width: colBrandWidth,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            child: Text(
              isAr ? 'العلامة' : 'Brand',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.w700,
                fontSize: _isDenseMode ? 11.5 : 12.5,
                color: cs.onSurface,
              ),
            ),
          ),

          // Column 3: Fathalla Anchor Header
          Container(
            width: colFathallaWidth,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.indigo.shade300, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_balance_rounded, size: 12, color: Colors.indigo),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      isAr ? 'أسواق فتح الله (المرجع)' : 'Fathalla (Anchor)',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w800,
                        fontSize: 10.5,
                        color: Colors.indigo.shade900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCell({
    required ChainProductItem item,
    required double width,
    required ColorScheme cs,
    required bool isAr,
    required AppStrings strings,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      alignment: AlignmentDirectional.centerStart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Product Name
          Text(
            item.name,
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.bold,
              fontSize: _isDenseMode ? 11.5 : 12.5,
              height: 1.2,
              color: cs.onSurface,
            ),
            maxLines: _isDenseMode ? 1 : 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),

          // Barcode Tag + Auto-Link + Aliases
          if (item.barcode.isNotEmpty)
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => _copyBarcode(item.barcode, context, isAr),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_2_rounded, size: 11, color: cs.primary),
                  const SizedBox(width: 3),
                  Text(
                    item.barcode,
                    style: GoogleFonts.robotoMono(
                      fontSize: 9.5,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(Icons.copy_rounded, size: 9, color: cs.primary.withValues(alpha: 0.7)),
                  if (item.isBarcodeAutoLinked) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: strings.barcodeAutoLinkedFromInvoices,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.blue.shade200, width: 0.5),
                        ),
                        child: Text(
                          isAr ? 'ربط' : 'Linked',
                          style: GoogleFonts.cairo(
                            fontSize: 8.5,
                            color: Colors.blue.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (item.chainAliases.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: isAr
                          ? 'مرصود بمسميات متعددة في ${item.chainAliases.length} سلاسل تجارية'
                          : 'Observed with aliases in ${item.chainAliases.length} chains',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.purple.shade200, width: 0.5),
                        ),
                        child: Text(
                          '${item.chainAliases.length} ${isAr ? "سلاسل" : "chains"}',
                          style: GoogleFonts.cairo(
                            fontSize: 8.5,
                            color: Colors.purple.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            )
          else
            Text(
              strings.barcodeMissingInAllInvoices,
              style: GoogleFonts.cairo(fontSize: 9, color: cs.outlineVariant, fontStyle: FontStyle.italic),
            ),
        ],
      ),
    );
  }

  Widget _buildBrandCell({
    required ChainProductItem item,
    required double width,
    required ColorScheme cs,
  }) {
    return Container(
      width: width,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: cs.secondaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          item.brand.isNotEmpty ? item.brand : '—',
          style: GoogleFonts.cairo(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: cs.onSecondaryContainer,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildFathallaCell({
    required ChainProductItem item,
    required double width,
    required ColorScheme cs,
    required String currency,
    required bool isAr,
  }) {
    final summary = item.chainSummaries['أسواق فتح الله'];
    final price = item.latestPricesByChain['أسواق فتح الله'];

    if (price == null && summary == null) {
      return Container(
        width: width,
        alignment: Alignment.center,
        child: Text('—', style: GoogleFonts.cairo(color: cs.outlineVariant, fontSize: 11)),
      );
    }

    final netUnitPrice = summary?.netUnitPrice ?? price ?? 0.0;
    final regularPrice = summary?.regularUnitPrice ?? item.latestRegularPricesByChain['أسواق فتح الله'] ?? netUnitPrice;
    final isOnPromo = summary?.isOnPromotion == true || (regularPrice > netUnitPrice);
    final discountPct = summary?.discountPercent ?? (regularPrice > 0 ? ((regularPrice - netUnitPrice) / regularPrice) * 100 : 0.0);
    final date = summary?.lastReceiptDate ?? item.latestDatesByChain['أسواق فتح الله'] ?? '';

    return Container(
      width: width,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Tooltip(
        message: 'أسواق فتح الله (المرجع الأساسي)\n'
            '${isAr ? 'سعر البيع المعتمد' : 'Net Price'}: $netUnitPrice $currency\n'
            '${isOnPromo ? '${isAr ? 'السعر الأصلي قبل الخصم' : 'Regular'}: $regularPrice $currency (-${discountPct.toStringAsFixed(0)}%)\n' : ''}'
            '${isAr ? 'تاريخ الفاتورة' : 'Receipt Date'}: ${date.isNotEmpty ? date : '—'}\n'
            '${isAr ? 'انقر لمعاينة البون والإثبات 🧾' : 'Click to view receipt proof 🧾'}',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => showProductPriceHistoryDialog(context: context, product: item, ref: ref),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: _isDenseMode ? 6 : 8, vertical: _isDenseMode ? 3 : 5),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.indigo.shade200, width: 0.9),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${netUnitPrice.toStringAsFixed(netUnitPrice == netUnitPrice.roundToDouble() ? 0 : 2)} $currency',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w900,
                      fontSize: _isDenseMode ? 11.5 : 12.5,
                      color: Colors.indigo.shade900,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (isOnPromo && regularPrice > netUnitPrice) ...[
                    const SizedBox(width: 3),
                    Text(
                      regularPrice.toStringAsFixed(0),
                      style: GoogleFonts.cairo(
                        fontSize: 8.5,
                        decoration: TextDecoration.lineThrough,
                        color: cs.error.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (discountPct > 0) ...[
                      const SizedBox(width: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 0.5),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          '-${discountPct.toStringAsFixed(0)}%',
                          style: GoogleFonts.cairo(
                            fontSize: 7.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // SUB-BUILDERS: SCROLLABLE COMPETITORS PANE
  // ===========================================================================

  Widget _buildCompetitorsHeader({
    required List<String> competitorChains,
    required ColorScheme cs,
    required bool isAr,
    required AppStrings strings,
    required double headerHeight,
  }) {
    const double colCompetitorWidth = 128.0;

    return Container(
      height: headerHeight,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6), width: 1.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Competitors Columns
          ...competitorChains.map((chain) {
            return Container(
              width: colCompetitorWidth,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.storefront_rounded, size: 13, color: cs.primary),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      chain,
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w700,
                        fontSize: _isDenseMode ? 11 : 12,
                        color: cs.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }),

          // Column: Fathalla Market Position
          Container(
            width: 220.0,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, size: 14, color: cs.primary),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    strings.fathallaMarketPositionLabel,
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w700,
                      fontSize: _isDenseMode ? 11 : 12,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Column: Price Variance
          Container(
            width: 80.0,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            child: Text(
              strings.priceDifferenceLabel,
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.w700,
                fontSize: _isDenseMode ? 11 : 12,
                color: cs.onSurface,
              ),
            ),
          ),

          // Column: Best Promo
          Container(
            width: 75.0,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            child: Text(
              isAr ? 'أفضل عرض' : 'Best Promo',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.w700,
                fontSize: _isDenseMode ? 11 : 12,
                color: cs.onSurface,
              ),
            ),
          ),

          // Column: Proof & Log
          Container(
            width: 65.0,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            child: Text(
              isAr ? 'البون والسجل' : 'Proof & Log',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.w700,
                fontSize: _isDenseMode ? 11 : 12,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompetitorPriceCell({
    required String chain,
    required ChainProductItem item,
    required ColorScheme cs,
    required String currency,
    required bool isAr,
  }) {
    const double colCompetitorWidth = 128.0;
    final summary = item.chainSummaries[chain];
    final price = item.latestPricesByChain[chain];

    if (price == null && summary == null) {
      return Container(
        width: colCompetitorWidth,
        alignment: Alignment.center,
        child: Text(
          '—',
          style: GoogleFonts.cairo(color: cs.outlineVariant.withValues(alpha: 0.6), fontSize: 11),
        ),
      );
    }

    final netUnitPrice = summary?.netUnitPrice ?? price ?? 0.0;
    final regularPrice = summary?.regularUnitPrice ?? item.latestRegularPricesByChain[chain] ?? netUnitPrice;
    final isOnPromo = summary?.isOnPromotion == true || (regularPrice > netUnitPrice);
    final discountPct = summary?.discountPercent ?? (regularPrice > 0 ? ((regularPrice - netUnitPrice) / regularPrice) * 100 : 0.0);
    final date = summary?.lastReceiptDate ?? item.latestDatesByChain[chain] ?? '';

    final hasMultiple = item.latestPricesByChain.length > 1;
    final minPrice = item.minPrice;
    final maxPrice = item.maxPrice;

    final isCheapestInMarket = hasMultiple && (netUnitPrice - minPrice).abs() < 0.05;
    final isCheaperThanFathalla = item.hasFathallaPrice && netUnitPrice < ((item.fathallaPrice ?? 0.0) - 0.05);

    Color bgColor = cs.surfaceContainerLow.withValues(alpha: 0.7);
    Color textColor = cs.onSurface;
    Border? border;

    if (isCheapestInMarket) {
      bgColor = Colors.green.shade50;
      textColor = Colors.green.shade900;
      border = Border.all(color: Colors.green.shade300, width: 1);
    } else if (isCheaperThanFathalla) {
      bgColor = Colors.amber.shade50;
      textColor = Colors.amber.shade900;
      border = Border.all(color: Colors.amber.shade300, width: 0.8);
    } else if (hasMultiple && (netUnitPrice - maxPrice).abs() < 0.05 && maxPrice > minPrice) {
      bgColor = Colors.red.shade50.withValues(alpha: 0.5);
      textColor = Colors.red.shade900;
    }

    final double priceDiffBelowFathalla = item.hasFathallaPrice ? (item.fathallaPrice! - netUnitPrice) : 0.0;

    return Container(
      width: colCompetitorWidth,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: '$chain\n'
            '${isAr ? 'سعر البيع' : 'Net Price'}: $netUnitPrice $currency\n'
            '${isCheaperThanFathalla ? '${isAr ? 'أرخص من فتح الله بـ' : 'Cheaper than Fathalla by'}: ${priceDiffBelowFathalla.toStringAsFixed(1)} $currency\n' : ''}'
            '${isOnPromo ? '${isAr ? 'السعر قبل الخصم' : 'Regular'}: $regularPrice $currency (-${discountPct.toStringAsFixed(0)}%)\n' : ''}'
            '${isAr ? 'تاريخ الفاتورة' : 'Receipt Date'}: ${date.isNotEmpty ? date : '—'}\n'
            '${isAr ? 'انقر لمعاينة البون والإثبات 🧾' : 'Click to view receipt proof 🧾'}',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => showProductPriceHistoryDialog(context: context, product: item, ref: ref),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: _isDenseMode ? 6 : 8, vertical: _isDenseMode ? 3 : 5),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
              border: border,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${netUnitPrice.toStringAsFixed(netUnitPrice == netUnitPrice.roundToDouble() ? 0 : 2)} $currency',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w900,
                      fontSize: _isDenseMode ? 11.5 : 12.5,
                      color: textColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),

                  // Best in Market Star Badge
                  if (isCheapestInMarket) ...[
                    const SizedBox(width: 3),
                    const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                  ],

                  // Strikethrough & Promo Badge
                  if (isOnPromo && regularPrice > netUnitPrice) ...[
                    const SizedBox(width: 3),
                    Text(
                      regularPrice.toStringAsFixed(0),
                      style: GoogleFonts.cairo(
                        fontSize: 8.5,
                        decoration: TextDecoration.lineThrough,
                        color: cs.error.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (discountPct > 0) ...[
                      const SizedBox(width: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 0.5),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          '-${discountPct.toStringAsFixed(0)}%',
                          style: GoogleFonts.cairo(
                            fontSize: 7.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPositionCell({
    required ChainProductItem item,
    required ColorScheme cs,
    required String currency,
    required bool isAr,
    required AppStrings strings,
  }) {
    const double colWidth = 220.0;

    if (item.isUnderpricedByCompetitors) {
      final diff = item.competitorUnderpricedDiff;
      final pct = item.competitorUnderpricedPercent;
      final competitor = item.cheapestCompetitorName;
      return Container(
        width: colWidth,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        child: Tooltip(
          message: isAr
              ? 'إنذار كسر سعر: $competitor تبيع بسعر أرخص من فتح الله بفارق ${diff.toStringAsFixed(1)} $currency (-${pct.toStringAsFixed(0)}%)'
              : 'Price Threat: $competitor is cheaper by ${diff.toStringAsFixed(1)} $currency (-${pct.toStringAsFixed(0)}%)',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade300, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 13, color: Colors.red),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    isAr
                        ? '$competitor أرخص بـ ${diff.toStringAsFixed(0)} $currency (-${pct.toStringAsFixed(0)}%)'
                        : '$competitor cheaper by ${diff.toStringAsFixed(0)} $currency',
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.red.shade900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (item.isFathallaCheapest && item.isMultiChain) {
      return Container(
        width: colWidth,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.shade300, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.stars_rounded, size: 14, color: Colors.amber),
              const SizedBox(width: 4),
              Text(
                isAr ? 'فتح الله الأرخص في السوق 🌟' : 'Fathalla Best Price 🌟',
                style: GoogleFonts.cairo(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.green.shade900,
                ),
              ),
            ],
          ),
        ),
      );
    } else if (item.isPricesEqual) {
      return Container(
        width: colWidth,
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            isAr ? 'سعر متطابق' : 'Equal Price',
            style: GoogleFonts.cairo(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    } else if (!item.hasFathallaPrice) {
      return Container(
        width: colWidth,
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Text(
            isAr ? 'غير مسجل بفتح الله' : 'Not in Fathalla',
            style: GoogleFonts.cairo(
              fontSize: 10,
              color: cs.outlineVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    } else {
      return Container(
        width: colWidth,
        alignment: Alignment.center,
        child: Text('—', style: GoogleFonts.cairo(color: cs.outlineVariant, fontSize: 11)),
      );
    }
  }

  Widget _buildVarianceCell({
    required ChainProductItem item,
    required ColorScheme cs,
  }) {
    const double colWidth = 80.0;
    final hasMultipleChains = item.latestPricesByChain.length > 1;

    return Container(
      width: colWidth,
      alignment: Alignment.center,
      child: hasMultipleChains && item.priceVariancePercent > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${item.priceVariancePercent.toStringAsFixed(1)}%',
                style: GoogleFonts.cairo(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            )
          : Text('0%', style: GoogleFonts.cairo(color: cs.onSurfaceVariant, fontSize: 10.5)),
    );
  }

  Widget _buildPromoCell({
    required ChainProductItem item,
    required ColorScheme cs,
  }) {
    const double colWidth = 75.0;

    return Container(
      width: colWidth,
      alignment: Alignment.center,
      child: item.maxObservedDiscountPercent > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '-${item.maxObservedDiscountPercent.toStringAsFixed(0)}%',
                style: GoogleFonts.cairo(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.green.shade900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            )
          : Text('—', style: GoogleFonts.cairo(color: cs.outlineVariant, fontSize: 10)),
    );
  }

  Widget _buildActionCell({
    required ChainProductItem item,
    required ColorScheme cs,
    required bool isAr,
  }) {
    const double colWidth = 65.0;

    return Container(
      width: colWidth,
      alignment: Alignment.center,
      child: Tooltip(
        message: isAr ? 'معاينة البون والإثبات التاريخي 🧾' : 'Proof of Receipt & History 🧾',
        child: IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: Icon(Icons.receipt_long_rounded, size: 17, color: cs.primary),
          onPressed: () {
            showProductPriceHistoryDialog(
              context: context,
              product: item,
              ref: ref,
            );
          },
        ),
      ),
    );
  }
}
