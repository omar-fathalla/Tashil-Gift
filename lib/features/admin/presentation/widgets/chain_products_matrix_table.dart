import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/constants/country_currency_config.dart';
import '../../domain/chain_product_model.dart';
import 'product_price_history_dialog.dart';

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
  final ScrollController _horizontalScrollController = ScrollController();

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChainProductsMatrixTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset page if total products shrunk
    final maxPages = (widget.products.length / _rowsPerPage).ceil();
    if (_currentPage >= maxPages && maxPages > 0) {
      setState(() {
        _currentPage = maxPages - 1;
      });
    }
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
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      color: cs.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Table Content Scrollable
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                controller: _horizontalScrollController,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    dataRowMinHeight: 78.0,
                    dataRowMaxHeight: 96.0,
                    headingRowHeight: 50.0,
                    headingRowColor: WidgetStateProperty.all(cs.surfaceContainerLow),
                    headingTextStyle: GoogleFonts.cairo(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: cs.onSurface,
                    ),
                    dataTextStyle: GoogleFonts.cairo(
                      fontSize: 12.5,
                      color: cs.onSurface,
                    ),
                    horizontalMargin: 16,
                    columnSpacing: 20,
                    columns: [
                      // Product info
                      DataColumn(
                        label: Text(isAr ? 'المنتج / الباركود' : 'Product / Barcode'),
                      ),
                      // Brand
                      DataColumn(
                        label: Text(strings.brandLabel),
                      ),
                      // Dynamic Enterprise Chain Columns
                      ...widget.distinctChains.map((chain) {
                        return DataColumn(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.storefront_rounded, size: 15, color: cs.primary),
                              const SizedBox(width: 5),
                              Text(chain),
                            ],
                          ),
                        );
                      }),
                      // Price Variance
                      DataColumn(
                        label: Text(strings.priceDifferenceLabel),
                      ),
                      // Best Discount / Promo
                      DataColumn(
                        label: Text(isAr ? 'أفضل عرض / خصم' : 'Best Promo'),
                      ),
                      // Actions
                      DataColumn(
                        label: Text(isAr ? 'السجل والتفاصيل' : 'History'),
                      ),
                    ],
                    rows: pageProducts.map((item) {
                      final minPrice = item.minPrice;
                      final maxPrice = item.maxPrice;
                      final hasMultipleChains = item.latestPricesByChain.length > 1;

                      return DataRow(
                        cells: [
                          // 1. Product Name & Barcode (Fixed Overflow Height)
                          DataCell(
                            Container(
                              constraints: const BoxConstraints(maxWidth: 290),
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    item.name,
                                    style: GoogleFonts.cairo(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                      height: 1.25,
                                      color: cs.onSurface,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (item.barcode.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Tooltip(
                                      message: isAr ? 'انقر لنسخ الباركود' : 'Click to copy barcode',
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(4),
                                        onTap: () {
                                          Clipboard.setData(ClipboardData(text: item.barcode));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(isAr ? 'تم نسخ الباركود: ${item.barcode}' : 'Barcode copied: ${item.barcode}'),
                                              duration: const Duration(seconds: 2),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        },
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.qr_code_2_rounded, size: 11, color: cs.onSurfaceVariant),
                                            const SizedBox(width: 4),
                                            Text(
                                              item.barcode,
                                              style: GoogleFonts.cairo(
                                                fontSize: 10,
                                                color: cs.onSurfaceVariant,
                                                fontWeight: FontWeight.w600,
                                                fontFeatures: const [FontFeature.tabularFigures()],
                                              ),
                                            ),
                                            const SizedBox(width: 3),
                                            Icon(Icons.copy_rounded, size: 9, color: cs.primary),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                          // 2. Brand Chip
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: cs.secondaryContainer.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item.brand.isNotEmpty ? item.brand : '—',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ),

                          // 3. Dynamic Chain Price Cells (Structured Before Promo, After Promo, Discount)
                          ...widget.distinctChains.map((chain) {
                            final chainSummary = item.chainSummaries[chain];
                            final price = item.latestPricesByChain[chain];

                            if (price == null && chainSummary == null) {
                              return DataCell(
                                Text('—', style: GoogleFonts.cairo(color: cs.outlineVariant)),
                              );
                            }

                            final netUnitPrice = chainSummary?.netUnitPrice ?? price ?? 0.0;
                            final regularPrice = chainSummary?.regularUnitPrice ?? item.latestRegularPricesByChain[chain] ?? netUnitPrice;
                            final isOnPromotion = chainSummary?.isOnPromotion == true || (regularPrice > netUnitPrice);
                            final unitDiscount = chainSummary?.unitDiscount ?? (regularPrice - netUnitPrice);
                            final discountPct = chainSummary?.discountPercent ?? (regularPrice > 0 ? ((regularPrice - netUnitPrice) / regularPrice) * 100 : 0.0);
                            final date = chainSummary?.lastReceiptDate ?? item.latestDatesByChain[chain] ?? '';

                            final isCheapest = hasMultipleChains && netUnitPrice == minPrice;
                            final isMostExpensive = hasMultipleChains && netUnitPrice == maxPrice && maxPrice > minPrice;

                            Color bgColor = cs.surfaceContainerLow;
                            Color textColor = cs.onSurface;
                            Border? border;

                            if (isCheapest) {
                              bgColor = Colors.green.shade50;
                              textColor = Colors.green.shade900;
                              border = Border.all(color: Colors.green.shade300, width: 1);
                            } else if (isMostExpensive) {
                              bgColor = Colors.red.shade50;
                              textColor = Colors.red.shade900;
                              border = Border.all(color: Colors.red.shade200, width: 0.8);
                            }

                            return DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: bgColor,
                                  borderRadius: BorderRadius.circular(10),
                                  border: border,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Row 1: Regular Price before discount (strikethrough) & Discount badge
                                    if (isOnPromotion && regularPrice > netUnitPrice) ...[
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${regularPrice.toStringAsFixed(regularPrice == regularPrice.roundToDouble() ? 0 : 2)} $currency',
                                            style: GoogleFonts.cairo(
                                              fontSize: 10,
                                              decoration: TextDecoration.lineThrough,
                                              color: cs.error.withValues(alpha: 0.85),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade100,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              discountPct > 0
                                                  ? 'خصم ${discountPct.toStringAsFixed(0)}%'
                                                  : 'وفر ${unitDiscount.toStringAsFixed(0)}',
                                              style: GoogleFonts.cairo(
                                                fontSize: 8.5,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green.shade900,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                    ],

                                    // Row 2: Net Unit Selling Price & Star Badge if cheapest
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${netUnitPrice.toStringAsFixed(netUnitPrice == netUnitPrice.roundToDouble() ? 0 : 2)} $currency',
                                          style: GoogleFonts.cairo(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13,
                                            color: isCheapest ? Colors.green.shade900 : textColor,
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                        if (isCheapest) ...[
                                          const SizedBox(width: 3),
                                          const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                                        ],
                                      ],
                                    ),

                                    // Row 3: Last Scan Date
                                    if (date.isNotEmpty)
                                      Text(
                                        date,
                                        style: GoogleFonts.cairo(
                                          fontSize: 9,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),

                          // 4. Price Variance %
                          DataCell(
                            hasMultipleChains && item.priceVariancePercent > 0
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: cs.primaryContainer.withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${item.priceVariancePercent.toStringAsFixed(1)}%',
                                      style: GoogleFonts.cairo(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: cs.primary,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  )
                                : Text('0%', style: GoogleFonts.cairo(color: cs.onSurfaceVariant, fontSize: 11.5)),
                          ),

                          // 5. Best Discount / Promo
                          DataCell(
                            item.maxObservedDiscountPercent > 0
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '-${item.maxObservedDiscountPercent.toStringAsFixed(0)}%',
                                      style: GoogleFonts.cairo(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.green.shade900,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  )
                                : Text('—', style: GoogleFonts.cairo(color: cs.outlineVariant)),
                          ),

                          // 6. Actions Button
                          DataCell(
                            IconButton.filledTonal(
                              icon: const Icon(Icons.history_rounded, size: 18),
                              tooltip: strings.priceHistoryTitle,
                              onPressed: () {
                                showProductPriceHistoryDialog(
                                  context: context,
                                  product: item,
                                  ref: ref,
                                );
                              },
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

          // M3 Standard Pagination Bar (25 Rows per page default)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                    Icon(Icons.format_list_numbered_rounded, size: 16, color: cs.primary),
                    const SizedBox(width: 6),
                    Text(
                      isAr
                          ? 'عرض ${startIndex + 1} - $endIndex من إجمالي $totalCount منتج'
                          : 'Showing ${startIndex + 1} - $endIndex of $totalCount products',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),

                // Rows Per Page Selector & Page Controls
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Rows per page dropdown
                    Text(
                      isAr ? 'الصفوف في الصفحة:' : 'Rows per page:',
                      style: GoogleFonts.cairo(fontSize: 11.5, color: cs.onSurfaceVariant),
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
                    const SizedBox(width: 16),

                    // First Page Button
                    IconButton(
                      icon: const Icon(Icons.first_page_rounded, size: 20),
                      tooltip: isAr ? 'الصفحة الأولى' : 'First page',
                      onPressed: _currentPage > 0
                          ? () => setState(() => _currentPage = 0)
                          : null,
                    ),

                    // Previous Page Button
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, size: 22),
                      tooltip: isAr ? 'السابق' : 'Previous',
                      onPressed: _currentPage > 0
                          ? () => setState(() => _currentPage--)
                          : null,
                    ),

                    // Page Indicator Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isAr
                            ? 'صفحة ${_currentPage + 1} من ${totalPages > 0 ? totalPages : 1}'
                            : 'Page ${_currentPage + 1} of ${totalPages > 0 ? totalPages : 1}',
                        style: GoogleFonts.cairo(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                      ),
                    ),

                    // Next Page Button
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, size: 22),
                      tooltip: isAr ? 'التالي' : 'Next',
                      onPressed: _currentPage < totalPages - 1
                          ? () => setState(() => _currentPage++)
                          : null,
                    ),

                    // Last Page Button
                    IconButton(
                      icon: const Icon(Icons.last_page_rounded, size: 20),
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
