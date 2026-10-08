import 'dart:ui';
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
  final bool isHeadToHead;
  final String? anchorChain;
  final String? comparisonChain;

  const ChainProductsMatrixTable({
    super.key,
    required this.products,
    required this.distinctChains,
    this.isHeadToHead = false,
    this.anchorChain,
    this.comparisonChain,
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
  void initState() {
    super.initState();
    _horizontalScrollController.addListener(_onHorizontalScrollChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _onHorizontalScrollChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _horizontalScrollController.removeListener(_onHorizontalScrollChanged);
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  bool get _canScrollTowardsStart {
    if (!_horizontalScrollController.hasClients) return false;
    return _horizontalScrollController.offset > 5.0;
  }

  bool get _canScrollTowardsEnd {
    if (!_horizontalScrollController.hasClients) return false;
    final max = _horizontalScrollController.position.maxScrollExtent;
    return max > 5.0 && _horizontalScrollController.offset < (max - 5.0);
  }

  void _scrollNextChains() {
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

  void _scrollPrevChains() {
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
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _copyBarcode(String barcode, BuildContext context, bool isAr) {
    final cs = Theme.of(context).colorScheme;
    Clipboard.setData(ClipboardData(text: barcode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: cs.onInverseSurface, size: 16),
            const SizedBox(width: 8),
            Text(
              isAr ? 'تم نسخ الباركود: $barcode' : 'Barcode copied: $barcode',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: cs.onInverseSurface),
            ),
          ],
        ),
        backgroundColor: cs.inverseSurface,
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

    final String baselineChain = widget.anchorChain ?? 'أسواق فتح الله';

    // Resolve competitor chains list (excluding baseline chain which is always pinned)
    final List<String> competitorChains;
    if (widget.isHeadToHead && widget.comparisonChain != null) {
      competitorChains = [widget.comparisonChain!];
    } else if (_showAllRegisteredChains) {
      competitorChains = ChainProductsIntelligenceService.canonicalRetailChains
          .where((c) => c != baselineChain)
          .toList();
    } else {
      competitorChains = widget.distinctChains
          .where((c) => c != baselineChain)
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
                    if (!widget.isHeadToHead) ...[
                      const SizedBox(width: 10),

                      // Toggle: All Registered Chains vs Active Observed Chains
                      Tooltip(
                        message: isAr
                            ? (_showAllRegisteredChains
                                ? 'عرض كافة الـ 16 سلسلة منافسة مسجلة في السوق حتى لو لم يرصد الصنف فيها بعد'
                                : 'عرض السلاسل التي تم رصد أسعار لها فقط وإخفاء الأعمدة غير المرصودة')
                            : 'Toggle displaying all 16 registered chains vs active chains only',
                        child: M3ConnectedButtonGroup<bool>(
                          height: 30,
                          borderRadius: 8,
                          showCheckmark: false,
                          isExpanded: false,
                          selectedValue: _showAllRegisteredChains,
                          onSelected: (val) => setState(() => _showAllRegisteredChains = val),
                          segments: [
                            M3ButtonSegment(
                              value: true,
                              label: isAr ? 'كافة السلاسل' : 'All Chains',
                              badgeText: '16',
                              icon: Icons.view_column_rounded,
                            ),
                            M3ButtonSegment(
                              value: false,
                              label: isAr ? 'النشطة فقط' : 'Active Only',
                              icon: Icons.filter_alt_outlined,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),

                // Right Group: Horizontal Scroll Controls & Density Selector
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Horizontal Quick Scroll Buttons with Tooltips & Active State
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tooltip(
                            message: isAr ? 'العودة لأول سلسلة منافسة' : 'Scroll to first competitor',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: _canScrollTowardsStart ? _scrollToStart : null,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.first_page_rounded,
                                  size: 16,
                                  color: _canScrollTowardsStart ? cs.primary : cs.outlineVariant.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                          ),
                          Container(width: 1, height: 14, color: cs.outlineVariant.withValues(alpha: 0.5)),
                          Tooltip(
                            message: isAr ? 'السلاسل السابقة' : 'Previous chains',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: _canScrollTowardsStart ? _scrollPrevChains : null,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isAr ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
                                      size: 17,
                                      color: _canScrollTowardsStart ? cs.primary : cs.outlineVariant.withValues(alpha: 0.6),
                                    ),
                                    Text(
                                      isAr ? 'السابقة' : 'Prev',
                                      style: GoogleFonts.cairo(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: _canScrollTowardsStart ? cs.onSurface : cs.outlineVariant.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Container(width: 1, height: 14, color: cs.outlineVariant.withValues(alpha: 0.5)),
                          Tooltip(
                            message: isAr ? 'السلاسل التالية' : 'Next chains',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: _canScrollTowardsEnd ? _scrollNextChains : null,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      isAr ? 'التالية' : 'Next',
                                      style: GoogleFonts.cairo(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: _canScrollTowardsEnd ? cs.onSurface : cs.outlineVariant.withValues(alpha: 0.6),
                                      ),
                                    ),
                                    Icon(
                                      isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                                      size: 17,
                                      color: _canScrollTowardsEnd ? cs.primary : cs.outlineVariant.withValues(alpha: 0.6),
                                    ),
                                  ],
                                ),
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
                        showCheckmark: false,
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
          // 2. Top Scroll Control Bar (Always visible at top of matrix table)
          // -------------------------------------------------------------------
          _buildTopScrollControlBar(
            cs: cs,
            isAr: isAr,
            totalPinnedWidth: totalPinnedWidth,
            competitorChains: competitorChains,
          ),

          // -------------------------------------------------------------------
          // 3. Dual-Pane Table Body: Pinned Baseline Pane + Scrollable Competitors Pane
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
                      baselineChain: baselineChain,
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

                              // 3. Fathalla / Baseline Price Cell
                              _buildFathallaCell(
                                item: item,
                                width: colFathallaWidth,
                                cs: cs,
                                currency: currency,
                                isAr: isAr,
                                baselineChain: baselineChain,
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
              // PANE B: Horizontally Scrollable Competitors & Analysis Pane (Dynamic Full-Width Scaling)
              // ---------------------------------------------------------------
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final numCompetitors = competitorChains.length;
                    const double fixedSummaryWidth = 440.0;
                    final double baseCompWidth = _isDenseMode ? 128.0 : 140.0;
                    final double totalMinWidth = (numCompetitors * baseCompWidth) + fixedSummaryWidth;
                    final availableWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : totalMinWidth;

                    final double effectiveCompetitorWidth;
                    final double effectivePositionWidth;
                    final double totalPaneWidth;

                    if (availableWidth > totalMinWidth && numCompetitors > 0) {
                      // Dynamically distribute extra viewport space so table fills 100% of the screen width
                      final extra = availableWidth - totalMinWidth;
                      effectiveCompetitorWidth = baseCompWidth + (extra * 0.65 / numCompetitors);
                      effectivePositionWidth = 220.0 + (extra * 0.35);
                      totalPaneWidth = availableWidth;
                    } else {
                      effectiveCompetitorWidth = baseCompWidth;
                      effectivePositionWidth = 220.0;
                      totalPaneWidth = totalMinWidth > availableWidth ? totalMinWidth : availableWidth;
                    }

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Scrollbar(
                          controller: _horizontalScrollController,
                          thumbVisibility: true,
                          trackVisibility: true,
                          thickness: 8,
                          radius: const Radius.circular(4),
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(context).copyWith(
                              dragDevices: {
                                PointerDeviceKind.touch,
                                PointerDeviceKind.mouse,
                                PointerDeviceKind.trackpad,
                                PointerDeviceKind.stylus,
                              },
                            ),
                            child: SingleChildScrollView(
                              controller: _horizontalScrollController,
                              scrollDirection: Axis.horizontal,
                              physics: const ClampingScrollPhysics(),
                              child: SizedBox(
                                width: totalPaneWidth,
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
                                      totalWidth: totalPaneWidth,
                                      competitorWidth: effectiveCompetitorWidth,
                                      positionWidth: effectivePositionWidth,
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
                                          width: totalPaneWidth,
                                          decoration: BoxDecoration(
                                            color: rowColor,
                                            border: Border(
                                              bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.25), width: 0.8),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.max,
                                            children: [
                                              // Dynamic Competitor Price Cells
                                              ...competitorChains.map((chain) {
                                                return _buildCompetitorPriceCell(
                                                  chain: chain,
                                                  item: item,
                                                  cs: cs,
                                                  currency: currency,
                                                  isAr: isAr,
                                                  width: effectiveCompetitorWidth,
                                                  baselineChain: baselineChain,
                                                );
                                              }),

                                              // Summary Column: Fathalla Market Position
                                              _buildPositionCell(
                                                item: item,
                                                cs: cs,
                                                currency: currency,
                                                isAr: isAr,
                                                strings: strings,
                                                width: effectivePositionWidth,
                                                baselineChain: baselineChain,
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
                        ),

                        // Floating Edge Chevrons over Header
                        if (_canScrollTowardsStart)
                          PositionedDirectional(
                            start: 6,
                            top: (headerHeight - 28) / 2,
                            child: _buildFloatingChevron(
                              isForward: false,
                              isAr: isAr,
                              cs: cs,
                              onTap: _scrollPrevChains,
                            ),
                          ),
                        if (_canScrollTowardsEnd)
                          PositionedDirectional(
                            end: 6,
                            top: (headerHeight - 28) / 2,
                            child: _buildFloatingChevron(
                              isForward: true,
                              isAr: isAr,
                              cs: cs,
                              onTap: _scrollNextChains,
                            ),
                          ),
                      ],
                    );
                  },
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
  // SUB-BUILDERS: TOP SCROLLBAR TRACK & PINNED PANE
  // ===========================================================================

  Widget _buildTopScrollControlBar({
    required ColorScheme cs,
    required bool isAr,
    required double totalPinnedWidth,
    required List<String> competitorChains,
  }) {
    final bool hasClients = _horizontalScrollController.hasClients;
    final double maxScrollExtent = hasClients ? _horizontalScrollController.position.maxScrollExtent : 0.0;
    final double currentOffset = hasClients ? _horizontalScrollController.offset : 0.0;
    final double viewportDimension = hasClients ? _horizontalScrollController.position.viewportDimension : 0.0;
    final bool canScroll = hasClients ? (maxScrollExtent > 5.0) : (competitorChains.length > 3);

    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4), width: 1.0),
        ),
      ),
      child: Row(
        children: [
          // Pinned Reference Info (aligns exactly with PANE A)
          Container(
            width: totalPinnedWidth,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.push_pin_rounded, size: 13, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  isAr ? 'الأعمدة المرجعية المثبتة' : 'Pinned Reference Columns',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: cs.primary.withValues(alpha: 0.25), width: 0.8),
                  ),
                  child: Text(
                    isAr ? '3 أعمدة مثبتة' : '3 Pinned',
                    style: GoogleFonts.cairo(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Elevation Divider
          Container(
            width: 1,
            height: 34,
            color: cs.outlineVariant.withValues(alpha: 0.65),
          ),

          // Competitor Columns Interactive Scroller (aligns exactly with PANE B)
          Expanded(
            child: !canScroll
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline_rounded, size: 14, color: cs.primary),
                        const SizedBox(width: 6),
                        Text(
                          isAr
                              ? 'كافة السلاسل الـ (${competitorChains.length}) معروضة بالكامل على الشاشة'
                              : 'All (${competitorChains.length}) chains fully visible on screen',
                          style: GoogleFonts.cairo(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, trackConstraints) {
                      final double totalContentWidth = viewportDimension + maxScrollExtent;
                      final double visibleRatio = totalContentWidth > 0
                          ? (viewportDimension / totalContentWidth).clamp(0.08, 1.0)
                          : 0.2;
                      final double progressRatio = maxScrollExtent > 0
                          ? (currentOffset / maxScrollExtent).clamp(0.0, 1.0)
                          : 0.0;

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            // Previous Chains Button
                            Tooltip(
                              message: isAr ? 'تمرير السلاسل السابقة' : 'Scroll previous chains',
                              child: InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: _canScrollTowardsStart ? _scrollPrevChains : null,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isAr ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
                                        size: 16,
                                        color: _canScrollTowardsStart ? cs.primary : cs.outlineVariant,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        isAr ? 'السابقة' : 'Prev',
                                        style: GoogleFonts.cairo(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: _canScrollTowardsStart ? cs.onSurface : cs.outlineVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),

                            // Draggable / Clickable Track
                            Expanded(
                              child: SizedBox(
                                height: 20,
                                child: LayoutBuilder(
                                  builder: (context, innerConstraints) {
                                    final double actualTrackWidth = innerConstraints.maxWidth;
                                    final double actualThumbWidth = (actualTrackWidth * visibleRatio).clamp(36.0, actualTrackWidth);
                                    final double actualTravel = (actualTrackWidth - actualThumbWidth).clamp(0.0, actualTrackWidth);
                                    final double actualThumbOffset = (actualTravel * progressRatio).clamp(0.0, actualTravel);

                                    void handleDragOrTap(double localDx) {
                                      if (maxScrollExtent <= 0 || actualTrackWidth <= 0) return;
                                      final double ratio = isAr
                                          ? ((actualTrackWidth - localDx) / actualTrackWidth).clamp(0.0, 1.0)
                                          : (localDx / actualTrackWidth).clamp(0.0, 1.0);
                                      final double targetOffset = ratio * maxScrollExtent;
                                      _horizontalScrollController.jumpTo(targetOffset);
                                    }

                                    return GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTapDown: (details) => handleDragOrTap(details.localPosition.dx),
                                      onHorizontalDragUpdate: (details) => handleDragOrTap(details.localPosition.dx),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          // Track Line
                                          Container(
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: cs.outlineVariant.withValues(alpha: 0.4),
                                                width: 0.8,
                                              ),
                                            ),
                                          ),

                                          // Guide Text inside track
                                          if (actualTrackWidth > 180)
                                            IgnorePointer(
                                              child: Text(
                                                isAr
                                                    ? 'اسحب للتمرير بين ${competitorChains.length} سلسلة منافسة'
                                                    : 'Drag or click to scroll ${competitorChains.length} chains',
                                                style: GoogleFonts.cairo(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w600,
                                                  color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                                                ),
                                              ),
                                            ),

                                          // Thumb
                                          PositionedDirectional(
                                            start: actualThumbOffset,
                                            child: MouseRegion(
                                              cursor: SystemMouseCursors.grab,
                                              child: Container(
                                                width: actualThumbWidth,
                                                height: 16,
                                                decoration: BoxDecoration(
                                                  color: cs.primary,
                                                  borderRadius: BorderRadius.circular(8),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: cs.primary.withValues(alpha: 0.35),
                                                      blurRadius: 4,
                                                      offset: const Offset(0, 1),
                                                    ),
                                                  ],
                                                ),
                                                child: Center(
                                                  child: Icon(
                                                    Icons.drag_handle_rounded,
                                                    size: 13,
                                                    color: cs.onPrimary,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),

                            // Next Chains Button
                            Tooltip(
                              message: isAr ? 'تمرير السلاسل التالية' : 'Scroll next chains',
                              child: InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: _canScrollTowardsEnd ? _scrollNextChains : null,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        isAr ? 'التالية' : 'Next',
                                        style: GoogleFonts.cairo(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: _canScrollTowardsEnd ? cs.onSurface : cs.outlineVariant,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(
                                        isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                                        size: 16,
                                        color: _canScrollTowardsEnd ? cs.primary : cs.outlineVariant,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Jump to start icon button
                            Tooltip(
                              message: isAr ? 'العودة لأول سلسلة' : 'Jump to first chain',
                              child: InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: _canScrollTowardsStart ? _scrollToStart : null,
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.first_page_rounded,
                                    size: 16,
                                    color: _canScrollTowardsStart ? cs.primary : cs.outlineVariant,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingChevron({
    required bool isForward,
    required bool isAr,
    required ColorScheme cs,
    required VoidCallback onTap,
  }) {
    final IconData icon = isForward
        ? (isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded)
        : (isAr ? Icons.chevron_right_rounded : Icons.chevron_left_rounded);

    return Tooltip(
      message: isForward
          ? (isAr ? 'السلاسل التالية' : 'Next chains')
          : (isAr ? 'السلاسل السابقة' : 'Previous chains'),
      child: Material(
        color: cs.surfaceContainerHighest,
        elevation: 3,
        shadowColor: Colors.black38,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6), width: 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: cs.primary),
          ),
        ),
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
    String baselineChain = 'أسواق فتح الله',
  }) {
    final isDefaultAnchor = baselineChain == 'أسواق فتح الله';
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

          // Column 3: Anchor Header
          Container(
            width: colFathallaWidth,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: cs.primary.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isDefaultAnchor ? Icons.account_balance_rounded : Icons.storefront_rounded,
                    size: 12,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      isDefaultAnchor
                          ? (isAr ? 'أسواق فتح الله (المرجع)' : 'Fathalla (Anchor)')
                          : (isAr ? '$baselineChain (المرجع)' : '$baselineChain (Anchor)'),
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w800,
                        fontSize: 10.5,
                        color: cs.onPrimaryContainer,
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
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: cs.secondary.withValues(alpha: 0.3), width: 0.5),
                        ),
                        child: Text(
                          isAr ? 'ربط' : 'Linked',
                          style: GoogleFonts.cairo(
                            fontSize: 8.5,
                            color: cs.onSecondaryContainer,
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
                          color: cs.tertiaryContainer,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: cs.tertiary.withValues(alpha: 0.3), width: 0.5),
                        ),
                        child: Text(
                          '${item.chainAliases.length} ${isAr ? "سلاسل" : "chains"}',
                          style: GoogleFonts.cairo(
                            fontSize: 8.5,
                            color: cs.onTertiaryContainer,
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
    String baselineChain = 'أسواق فتح الله',
  }) {
    final summary = item.chainSummaries[baselineChain];
    final price = item.latestPricesByChain[baselineChain];

    if (price == null && summary == null) {
      return Container(
        width: width,
        alignment: Alignment.center,
        child: Text('—', style: GoogleFonts.cairo(color: cs.outlineVariant, fontSize: 11)),
      );
    }

    final isDefaultAnchor = baselineChain == 'أسواق فتح الله';
    final netUnitPrice = summary?.netUnitPrice ?? price ?? 0.0;
    final regularPrice = summary?.regularUnitPrice ?? item.latestRegularPricesByChain[baselineChain] ?? netUnitPrice;
    final isOnPromo = summary?.isOnPromotion == true || (regularPrice > netUnitPrice);
    final discountPct = summary?.discountPercent ?? (regularPrice > 0 ? ((regularPrice - netUnitPrice) / regularPrice) * 100 : 0.0);
    final date = summary?.lastReceiptDate ?? item.latestDatesByChain[baselineChain] ?? '';

    return Container(
      width: width,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Tooltip(
        message: '$baselineChain (${isDefaultAnchor ? (isAr ? 'المرجع الأساسي' : 'Primary Anchor') : (isAr ? 'سلسلة الأساس' : 'Baseline')})\n'
            '${isAr ? 'سعر البيع المعتمد' : 'Net Price'}: $netUnitPrice $currency\n'
            '${isOnPromo ? '${isAr ? 'السعر الأصلي قبل الخصم' : 'Regular'}: $regularPrice $currency (-${discountPct.toStringAsFixed(0)}%)\n' : ''}'
            '${isAr ? 'تاريخ الفاتورة' : 'Receipt Date'}: ${date.isNotEmpty ? date : '—'}\n'
            '${isAr ? 'انقر لمعاينة البون والإثبات' : 'Click to view receipt proof'}',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => showProductPriceHistoryDialog(context: context, product: item, ref: ref),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: _isDenseMode ? 6 : 8, vertical: _isDenseMode ? 3 : 5),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.35),
                width: 0.9,
              ),
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
                      color: cs.onPrimaryContainer,
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
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          '-${discountPct.toStringAsFixed(0)}%',
                          style: GoogleFonts.cairo(
                            fontSize: 7.5,
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimaryContainer,
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
    double? totalWidth,
    double competitorWidth = 128.0,
    double positionWidth = 220.0,
  }) {
    return Container(
      width: totalWidth,
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
              width: competitorWidth,
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

          // Column: Fathalla / Baseline Market Position
          Container(
            width: positionWidth,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, size: 14, color: cs.primary),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    widget.isHeadToHead
                        ? (isAr ? 'المقارنة المباشرة' : 'Head-to-Head')
                        : strings.fathallaMarketPositionLabel,
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
    double width = 128.0,
    String baselineChain = 'أسواق فتح الله',
  }) {
    final summary = item.chainSummaries[chain];
    final price = item.latestPricesByChain[chain];

    if (price == null && summary == null) {
      return Container(
        width: width,
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
    final baselinePrice = item.latestPricesByChain[baselineChain];
    final hasBaselinePrice = baselinePrice != null;
    final isCheaperThanBaseline = hasBaselinePrice && netUnitPrice < (baselinePrice - 0.05);

    Color bgColor = cs.surfaceContainerLow.withValues(alpha: 0.7);
    Color textColor = cs.onSurface;
    Border? border;

    if (isCheapestInMarket) {
      bgColor = cs.primaryContainer.withValues(alpha: 0.45);
      textColor = cs.onPrimaryContainer;
      border = Border.all(color: cs.primary.withValues(alpha: 0.4), width: 1);
    } else if (isCheaperThanBaseline) {
      bgColor = cs.errorContainer;
      textColor = cs.onErrorContainer;
      border = Border.all(color: cs.error.withValues(alpha: 0.35), width: 1);
    } else if (hasMultiple && (netUnitPrice - maxPrice).abs() < 0.05 && maxPrice > minPrice) {
      bgColor = cs.surfaceContainerHighest.withValues(alpha: 0.5);
      textColor = cs.onSurfaceVariant;
    }

    final double priceDiffBelowBaseline = hasBaselinePrice ? (baselinePrice - netUnitPrice) : 0.0;

    return Container(
      width: width,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: '$chain\n'
            '${isAr ? 'سعر البيع' : 'Net Price'}: $netUnitPrice $currency\n'
            '${isCheaperThanBaseline ? '${isAr ? 'أرخص من $baselineChain بـ' : 'Cheaper than $baselineChain by'}: ${priceDiffBelowBaseline.toStringAsFixed(1)} $currency\n' : ''}'
            '${isOnPromo ? '${isAr ? 'السعر قبل الخصم' : 'Regular'}: $regularPrice $currency (-${discountPct.toStringAsFixed(0)}%)\n' : ''}'
            '${isAr ? 'تاريخ الفاتورة' : 'Receipt Date'}: ${date.isNotEmpty ? date : '—'}\n'
            '${isAr ? 'انقر لمعاينة البون والإثبات' : 'Click to view receipt proof'}',
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

                  // Best in Market Verified Badge
                  if (isCheapestInMarket) ...[
                    const SizedBox(width: 3),
                    Icon(Icons.verified_rounded, size: 12, color: cs.primary),
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
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          '-${discountPct.toStringAsFixed(0)}%',
                          style: GoogleFonts.cairo(
                            fontSize: 7.5,
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimaryContainer,
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
    double width = 220.0,
    String baselineChain = 'أسواق فتح الله',
  }) {
    // 1. Head-to-Head Direct Mode Evaluation
    if (widget.isHeadToHead && widget.comparisonChain != null) {
      final compChain = widget.comparisonChain!;
      final pBaseline = item.latestPricesByChain[baselineChain];
      final pComp = item.latestPricesByChain[compChain];

      if (pBaseline != null && pComp != null) {
        if (pComp < (pBaseline - 0.05)) {
          final diff = pBaseline - pComp;
          final pct = (diff / pBaseline) * 100;
          return Container(
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.error.withValues(alpha: 0.3), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.trending_down_rounded, size: 13, color: cs.error),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      isAr
                          ? '$compChain أرخص بفارق ${diff.toStringAsFixed(1)} $currency (-${pct.toStringAsFixed(0)}%)'
                          : '$compChain cheaper by ${diff.toStringAsFixed(1)} $currency',
                      style: GoogleFonts.cairo(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: cs.onErrorContainer,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        } else if (pBaseline < (pComp - 0.05)) {
          final diff = pComp - pBaseline;
          final pct = (diff / pComp) * 100;
          return Container(
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.primary.withValues(alpha: 0.3), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_rounded, size: 14, color: cs.primary),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      isAr
                          ? '$baselineChain أرخص بفارق ${diff.toStringAsFixed(1)} $currency (+${pct.toStringAsFixed(0)}%)'
                          : '$baselineChain cheaper by ${diff.toStringAsFixed(1)} $currency',
                      style: GoogleFonts.cairo(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: cs.onPrimaryContainer,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          return Container(
            width: width,
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isAr ? 'السعر متطابق بين السلسلتين' : 'Equal Price',
                style: GoogleFonts.cairo(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          );
        }
      }
    }

    // 2. Competitor Promo NOT at Fathalla (Priority 2)
    if (baselineChain == 'أسواق فتح الله' && item.isCompetitorPromoNotAtFathalla) {
      final compPromoChains = item.chainSummaries.entries
          .where((e) => e.key != 'أسواق فتح الله' && e.value.isOnPromotion)
          .map((e) => e.key)
          .join(', ');
      return Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        child: Tooltip(
          message: isAr
              ? 'عرض ترويجي نشط لدى ($compPromoChains) وغير متوفر بفتح الله — فرصة توريد وإضافة'
              : 'Active promo at ($compPromoChains) missing from Fathalla — expansion opportunity',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cs.tertiaryContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.tertiary.withValues(alpha: 0.3), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lightbulb_outline_rounded, size: 13, color: cs.tertiary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    isAr ? 'عرض غير متوفر بفتح الله' : 'Promo not in Fathalla',
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: cs.onTertiaryContainer,
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
    }

    // 3. Price Threat (Competitor Undercutting Baseline)
    if (item.isUnderpricedByCompetitors) {
      final diff = item.competitorUnderpricedDiff;
      final pct = item.competitorUnderpricedPercent;
      final competitor = item.cheapestCompetitorName;
      return Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        child: Tooltip(
          message: isAr
              ? 'إنذار كسر سعر: $competitor تبيع بسعر أرخص من $baselineChain بفارق ${diff.toStringAsFixed(1)} $currency (-${pct.toStringAsFixed(0)}%)'
              : 'Price Threat: $competitor is cheaper by ${diff.toStringAsFixed(1)} $currency (-${pct.toStringAsFixed(0)}%)',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.error.withValues(alpha: 0.3), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, size: 13, color: cs.error),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    isAr
                        ? '$competitor أرخص بـ ${diff.toStringAsFixed(0)} $currency (-${pct.toStringAsFixed(0)}%)'
                        : '$competitor cheaper by ${diff.toStringAsFixed(0)} $currency',
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: cs.onErrorContainer,
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
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.primary.withValues(alpha: 0.3), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_rounded, size: 14, color: cs.primary),
              const SizedBox(width: 4),
              Text(
                isAr ? '$baselineChain الأرخص في السوق' : '$baselineChain Best Price',
                style: GoogleFonts.cairo(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: cs.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      );
    } else if (item.isPricesEqual) {
      return Container(
        width: width,
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
        width: width,
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Text(
            isAr ? 'غير مسجل بـ $baselineChain' : 'Not in $baselineChain',
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
        width: width,
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
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '-${item.maxObservedDiscountPercent.toStringAsFixed(0)}%',
                style: GoogleFonts.cairo(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: cs.onPrimaryContainer,
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
        message: isAr ? 'معاينة البون والإثبات التاريخي' : 'Proof of Receipt & History',
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
