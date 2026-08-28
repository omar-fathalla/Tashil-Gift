import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/constants/country_currency_config.dart';
import '../../../../core/widgets/m3_button_groups.dart';
import '../../domain/chain_product_model.dart';
import 'product_price_history_dialog.dart';

/// Ultra-Compact & High-Density Retail Chain Products Matrix Table
/// جدول مصفوفة أسعار ومنتجات السلاسل التجارية فائق الكثافة والرشاقة
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
    final orderedChains = List<String>.from(widget.distinctChains);
    if (orderedChains.contains('أسواق فتح الله')) {
      orderedChains.remove('أسواق فتح الله');
      orderedChains.insert(0, 'أسواق فتح الله');
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
          // 1. Table Top Toolbar (Density Selector & Rows Count)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
            ),
            child: Row(
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
                const Spacer(),

                // Density Toggle (عرض مدمج فائق الرشاقة vs عرض عادي)
                Tooltip(
                  message: strings.densityToggleTooltip,
                  child: M3ConnectedButtonGroup<bool>(
                    height: 32,
                    borderRadius: 16,
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
          ),

          // 2. High-Density Scrollable Table Content
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                controller: _horizontalScrollController,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    dataRowMinHeight: _isDenseMode ? 46.0 : 64.0,
                    dataRowMaxHeight: _isDenseMode ? 52.0 : 74.0,
                    headingRowHeight: _isDenseMode ? 40.0 : 48.0,
                    headingRowColor: WidgetStateProperty.all(cs.surfaceContainerLow),
                    headingTextStyle: GoogleFonts.cairo(
                      fontWeight: FontWeight.w700,
                      fontSize: _isDenseMode ? 11.5 : 12.5,
                      color: cs.onSurface,
                    ),
                    dataTextStyle: GoogleFonts.cairo(
                      fontSize: _isDenseMode ? 11.5 : 12.5,
                      color: cs.onSurface,
                    ),
                    horizontalMargin: 12,
                    columnSpacing: _isDenseMode ? 14 : 20,
                    columns: [
                      // Column 1: Product & Barcode
                      DataColumn(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_rounded, size: 14, color: cs.primary),
                            const SizedBox(width: 6),
                            Text(isAr ? 'المنتج / الباركود' : 'Product / Barcode'),
                          ],
                        ),
                      ),
                      // Column 2: Brand
                      DataColumn(
                        label: Text(strings.brandLabel),
                      ),
                      // Columns 3+: Dynamic Enterprise Chain Columns (Ordered with Fathalla First)
                      ...orderedChains.map((chain) {
                        final isFathalla = chain == 'أسواق فتح الله';
                        return DataColumn(
                          label: isFathalla
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.indigo.shade300, width: 1),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.account_balance_rounded, size: 13, color: Colors.indigo),
                                      const SizedBox(width: 4),
                                      Text(
                                        isAr ? 'أسواق فتح الله (المرجع)' : 'Fathalla (Baseline)',
                                        style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.w800,
                                          fontSize: _isDenseMode ? 11 : 12,
                                          color: Colors.indigo.shade900,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.storefront_rounded, size: 14, color: cs.primary),
                                    const SizedBox(width: 5),
                                    Text(chain),
                                  ],
                                ),
                        );
                      }),
                      // Column: Fathalla Market Position 🎯
                      DataColumn(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shield_outlined, size: 14, color: cs.primary),
                            const SizedBox(width: 5),
                            Text(strings.fathallaMarketPositionLabel),
                          ],
                        ),
                      ),
                      // Column: Price Variance
                      DataColumn(
                        label: Text(strings.priceDifferenceLabel),
                      ),
                      // Column: Best Promo
                      DataColumn(
                        label: Text(isAr ? 'أفضل عرض' : 'Best Promo'),
                      ),
                      // Column: Action / History & Receipt Proof
                      DataColumn(
                        label: Text(isAr ? 'البون والسجل' : 'Proof & Log'),
                      ),
                    ],
                    rows: pageProducts.asMap().entries.map((entry) {
                      final rowIndex = entry.key;
                      final item = entry.value;
                      final minPrice = item.minPrice;
                      final maxPrice = item.maxPrice;
                      final hasMultipleChains = item.latestPricesByChain.length > 1;

                      final isEven = rowIndex % 2 == 0;
                      final rowColor = isEven
                          ? Colors.transparent
                          : cs.surfaceContainerHighest.withValues(alpha: 0.2);

                      return DataRow(
                        color: WidgetStateProperty.all(rowColor),
                        cells: [
                          // 1. PRODUCT NAME & INLINE BARCODE PILL (Ultra-Compact)
                          DataCell(
                            Container(
                              constraints: BoxConstraints(maxWidth: _isDenseMode ? 280 : 320),
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Product Title
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

                                  // Monospace Barcode Tag with Direct Copy & Auto-link Indicator
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
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.link_rounded, size: 9, color: Colors.blue.shade700),
                                                    const SizedBox(width: 2),
                                                    Text(
                                                      isAr ? 'ربط تلقائي' : 'Linked',
                                                      style: GoogleFonts.cairo(
                                                        fontSize: 8.5,
                                                        color: Colors.blue.shade800,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                          if (item.chainAliases.isNotEmpty) ...[
                                            const SizedBox(width: 4),
                                            Tooltip(
                                              message: isAr
                                                  ? 'مرصود بمسميات متعددة في ${item.chainAliases.length} سلاسل تجارية'
                                                  : 'Recorded with POS aliases in ${item.chainAliases.length} retail chains',
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                                                decoration: BoxDecoration(
                                                  color: Colors.purple.shade50,
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: Colors.purple.shade200, width: 0.5),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.storefront_rounded, size: 9, color: Colors.purple.shade700),
                                                    const SizedBox(width: 2),
                                                    Text(
                                                      '${item.chainAliases.length} ${isAr ? "سلاسل" : "chains"}',
                                                      style: GoogleFonts.cairo(
                                                        fontSize: 8.5,
                                                        color: Colors.purple.shade800,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
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
                                      style: GoogleFonts.cairo(
                                        fontSize: 9,
                                        color: cs.outlineVariant,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),

                          // 2. BRAND CHIP (Compact)
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: cs.secondaryContainer.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item.brand.isNotEmpty ? item.brand : '—',
                                style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ),

                          // 3. DYNAMIC CHAIN PRICE CELLS (Ultra-Compact Pill)
                          ...orderedChains.map((chain) {
                            final chainSummary = item.chainSummaries[chain];
                            final price = item.latestPricesByChain[chain];

                            if (price == null && chainSummary == null) {
                              return DataCell(
                                Text('—', style: GoogleFonts.cairo(color: cs.outlineVariant, fontSize: 11)),
                              );
                            }

                            final netUnitPrice = chainSummary?.netUnitPrice ?? price ?? 0.0;
                            final regularPrice = chainSummary?.regularUnitPrice ?? item.latestRegularPricesByChain[chain] ?? netUnitPrice;
                            final isOnPromotion = chainSummary?.isOnPromotion == true || (regularPrice > netUnitPrice);
                            final discountPct = chainSummary?.discountPercent ?? (regularPrice > 0 ? ((regularPrice - netUnitPrice) / regularPrice) * 100 : 0.0);
                            final date = chainSummary?.lastReceiptDate ?? item.latestDatesByChain[chain] ?? '';
                            final isFathalla = chain == 'أسواق فتح الله';

                            final isCheapest = hasMultipleChains && netUnitPrice == minPrice;
                            final isMostExpensive = hasMultipleChains && netUnitPrice == maxPrice && maxPrice > minPrice;

                            Color bgColor = isFathalla 
                                ? Colors.indigo.shade50.withValues(alpha: 0.6)
                                : cs.surfaceContainerLow.withValues(alpha: 0.7);
                            Color textColor = isFathalla ? Colors.indigo.shade900 : cs.onSurface;
                            Border? border = isFathalla ? Border.all(color: Colors.indigo.shade200, width: 0.8) : null;

                            if (isCheapest) {
                              bgColor = Colors.green.shade50;
                              textColor = Colors.green.shade900;
                              border = Border.all(color: Colors.green.shade300, width: 1);
                            } else if (isMostExpensive && !isFathalla) {
                              bgColor = Colors.red.shade50;
                              textColor = Colors.red.shade900;
                              border = Border.all(color: Colors.red.shade200, width: 0.7);
                            }

                            return DataCell(
                              Tooltip(
                                message: '$chain\n${isAr ? 'تاريخ الفاتورة' : 'Receipt Date'}: ${date.isNotEmpty ? date : '—'}\n${isOnPromotion ? '${isAr ? 'السعر الأصلي' : 'Original'}: $regularPrice $currency' : ''}\n${isAr ? 'انقر لمعاينة البون والإثبات 🧾' : 'Click to view receipt proof 🧾'}',
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () {
                                    showProductPriceHistoryDialog(
                                      context: context,
                                      product: item,
                                      ref: ref,
                                    );
                                  },
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: _isDenseMode ? 8 : 10,
                                      vertical: _isDenseMode ? 3 : 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: bgColor,
                                      borderRadius: BorderRadius.circular(8),
                                      border: border,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Net Selling Price
                                        Text(
                                          '${netUnitPrice.toStringAsFixed(netUnitPrice == netUnitPrice.roundToDouble() ? 0 : 2)} $currency',
                                          style: GoogleFonts.cairo(
                                            fontWeight: FontWeight.w900,
                                            fontSize: _isDenseMode ? 11.5 : 12.5,
                                            color: isCheapest ? Colors.green.shade900 : textColor,
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                          ),
                                        ),

                                        // Best Price Star Badge
                                        if (isCheapest) ...[
                                          const SizedBox(width: 3),
                                          const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                                        ],

                                        // Strikethrough & Promo Badge (if on offer)
                                        if (isOnPromotion && regularPrice > netUnitPrice) ...[
                                          const SizedBox(width: 4),
                                          Text(
                                            regularPrice.toStringAsFixed(0),
                                            style: GoogleFonts.cairo(
                                              fontSize: 9,
                                              decoration: TextDecoration.lineThrough,
                                              color: cs.error.withValues(alpha: 0.75),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (discountPct > 0) ...[
                                            const SizedBox(width: 2),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
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
                            );
                          }),

                          // 4. FATHALLA MARKET POSITION CELL 🎯 (Threat Warning or Best Price)
                          DataCell(
                            Builder(
                              builder: (context) {
                                if (item.isUnderpricedByCompetitors) {
                                  final diff = item.competitorUnderpricedDiff;
                                  final pct = item.competitorUnderpricedPercent;
                                  final competitor = item.cheapestCompetitorName;
                                  return Tooltip(
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
                                          Text(
                                            isAr
                                                ? '$competitor أرخص بـ ${diff.toStringAsFixed(0)} $currency (-${pct.toStringAsFixed(0)}%)'
                                                : '$competitor cheaper by ${diff.toStringAsFixed(0)} $currency',
                                            style: GoogleFonts.cairo(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.red.shade900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                } else if (item.isFathallaCheapest && item.isMultiChain) {
                                  return Container(
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
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.green.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                } else if (item.isPricesEqual) {
                                  return Container(
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
                                  );
                                } else if (!item.hasFathallaPrice) {
                                  return Container(
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
                                  );
                                } else {
                                  return Text('—', style: GoogleFonts.cairo(color: cs.outlineVariant, fontSize: 11));
                                }
                              },
                            ),
                          ),

                          // 5. PRICE VARIANCE %
                          DataCell(
                            hasMultipleChains && item.priceVariancePercent > 0
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
                          ),

                          // 6. BEST DISCOUNT / PROMO
                          DataCell(
                            item.maxObservedDiscountPercent > 0
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
                          ),

                          // 7. ACTIONS / HISTORY & PROOF BUTTON
                          DataCell(
                            Tooltip(
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
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),

          // Divider
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),

          // 3. M3 Standard Pagination & Navigation Bar
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
                      onPressed: _currentPage > 0
                          ? () => setState(() => _currentPage = 0)
                          : null,
                    ),

                    // Previous Page Button
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.chevron_right_rounded, size: 20),
                      tooltip: isAr ? 'السابق' : 'Previous',
                      onPressed: _currentPage > 0
                          ? () => setState(() => _currentPage--)
                          : null,
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
                      onPressed: _currentPage < totalPages - 1
                          ? () => setState(() => _currentPage++)
                          : null,
                    ),

                    // Last Page Button
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.last_page_rounded, size: 18),
                      tooltip: isAr ? 'الصفحة الأخيرة' : 'Last page',
                      onPressed: _currentPage < totalPages - 1
                          ? () => setState(() => _currentPage = totalPages - 1)
                          : null,
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
}

