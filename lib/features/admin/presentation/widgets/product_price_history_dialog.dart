import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/constants/country_currency_config.dart';
import '../../domain/chain_product_model.dart';

void showProductPriceHistoryDialog({
  required BuildContext context,
  required ChainProductItem product,
  required WidgetRef ref,
}) {
  showDialog(
    context: context,
    builder: (ctx) => ProductPriceHistoryDialog(product: product),
  );
}

class ProductPriceHistoryDialog extends ConsumerStatefulWidget {
  final ChainProductItem product;

  const ProductPriceHistoryDialog({super.key, required this.product});

  @override
  ConsumerState<ProductPriceHistoryDialog> createState() => _ProductPriceHistoryDialogState();
}

class _ProductPriceHistoryDialogState extends ConsumerState<ProductPriceHistoryDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = AppStrings.of(ref);
    final activeCountry = ref.watch(activeCountryProvider);
    final currency = activeCountry.currencySymbol;
    final isAr = ref.isArabic;
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 700;
    final product = widget.product;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 32,
        vertical: isMobile ? 16 : 32,
      ),
      child: Container(
        width: 860,
        constraints: BoxConstraints(maxHeight: size.height * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.35),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.analytics_outlined, color: cs.onPrimary, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (product.barcode.isNotEmpty) ...[
                              Icon(Icons.qr_code_2_rounded, size: 14, color: cs.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(
                                product.barcode,
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: cs.secondaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                product.brand,
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: strings.cancel,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Intelligence Summary Banner (4 KPIs)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 10,
                  alignment: WrapAlignment.spaceAround,
                  children: [
                    _buildSummaryStat(
                      label: strings.cheapestStoreBadge,
                      value: '${product.minPrice.toStringAsFixed(product.minPrice == product.minPrice.roundToDouble() ? 0 : 2)} $currency',
                      subtext: product.cheapestChain,
                      color: cs.primary,
                      icon: Icons.trending_down_rounded,
                    ),
                    _buildSummaryStat(
                      label: strings.highestPriceStoreBadge,
                      value: '${product.maxPrice.toStringAsFixed(product.maxPrice == product.maxPrice.roundToDouble() ? 0 : 2)} $currency',
                      subtext: product.mostExpensiveChain,
                      color: cs.error,
                      icon: Icons.trending_up_rounded,
                    ),
                    _buildSummaryStat(
                      label: strings.priceDifferenceLabel,
                      value: '${product.priceVariancePercent.toStringAsFixed(1)}%',
                      subtext: '${product.chainSummaries.length} ${isAr ? "سلاسل مقارنة" : "chains"}',
                      color: cs.secondary,
                      icon: Icons.compare_arrows_rounded,
                    ),
                    _buildSummaryStat(
                      label: strings.scansCountLabel,
                      value: '${product.totalScansCount}',
                      subtext: '${product.totalQuantitySold} ${isAr ? "قطعة مباعة" : "units"}',
                      color: cs.tertiary,
                      icon: Icons.receipt_long_rounded,
                    ),
                  ],
                ),
              ),
            ),

            // Enterprise Chains Price Matrix Cards
            if (product.chainSummaries.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.storefront_rounded, size: 16, color: cs.primary),
                        const SizedBox(width: 6),
                        Text(
                          isAr ? 'تسعير السلاسل والمؤسسات التجارية المعتمدة:' : 'Enterprise Retail Chains Pricing:',
                          style: GoogleFonts.cairo(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: product.chainSummaries.values.map((chainSum) {
                          final isCheapest = chainSum.netUnitPrice == product.minPrice && product.chainSummaries.length > 1;
                          final isHighest = chainSum.netUnitPrice == product.maxPrice && product.maxPrice > product.minPrice;

                          Color cardBg = cs.surfaceContainerLowest;
                          Color borderColor = cs.outlineVariant.withValues(alpha: 0.4);
                          if (isCheapest) {
                            cardBg = cs.primaryContainer.withValues(alpha: 0.35);
                            borderColor = cs.primary.withValues(alpha: 0.5);
                          } else if (isHighest) {
                            cardBg = cs.errorContainer.withValues(alpha: 0.25);
                            borderColor = cs.error.withValues(alpha: 0.3);
                          }

                          return Container(
                            width: 220,
                            margin: const EdgeInsets.only(right: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: borderColor, width: isCheapest ? 1.5 : 1),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.storefront_rounded, size: 16, color: isCheapest ? cs.primary : cs.onSurfaceVariant),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        chainSum.chainName,
                                        style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: cs.onSurface,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isCheapest)
                                      Icon(Icons.star_rounded, size: 16, color: cs.primary),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    if (chainSum.isOnPromotion && chainSum.regularUnitPrice > chainSum.netUnitPrice) ...[
                                      Text(
                                        '${chainSum.regularUnitPrice.toStringAsFixed(chainSum.regularUnitPrice == chainSum.regularUnitPrice.roundToDouble() ? 0 : 2)} $currency',
                                        style: GoogleFonts.cairo(
                                          fontSize: 11,
                                          decoration: TextDecoration.lineThrough,
                                          color: cs.error.withValues(alpha: 0.8),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Text(
                                      chainSum.netUnitPrice.toStringAsFixed(chainSum.netUnitPrice == chainSum.netUnitPrice.roundToDouble() ? 0 : 2),
                                      style: GoogleFonts.cairo(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: isCheapest ? cs.primary : cs.onSurface,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(currency, style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: cs.primary)),
                                  ],
                                ),
                                if (chainSum.isOnPromotion) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: cs.primaryContainer.withValues(alpha: 0.6),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      chainSum.discountPercent > 0
                                          ? 'خصم ${chainSum.discountPercent.toStringAsFixed(0)}%'
                                          : 'وفر ${chainSum.unitDiscount.toStringAsFixed(0)} $currency',
                                      style: GoogleFonts.cairo(fontSize: 9, fontWeight: FontWeight.bold, color: cs.primary),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Text(
                                  '${chainSum.totalScans} ${isAr ? "رصد" : "scans"} (${chainSum.totalQuantity} ${isAr ? "قطعة" : "pcs"})',
                                  style: GoogleFonts.cairo(fontSize: 10, color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Tabs for Price Evolution vs Raw Invoices
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TabBar(
                controller: _tabController,
                labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: [
                  Tab(
                    icon: const Icon(Icons.timeline_rounded, size: 18),
                    text: isAr ? 'سجل تغيرات وتعديلات الأسعار' : 'Price Evolution History',
                  ),
                  Tab(
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    text: '${isAr ? "كافة الفواتير المرصودة" : "Raw Receipts"} (${product.priceHistory.length})',
                  ),
                ],
              ),
            ),

            // Tab Views
            Flexible(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Distinct Price Evolution Timeline
                  _buildPriceEvolutionTimeline(product, cs, isAr, currency),

                  // Tab 2: Raw Receipts Audit Stream
                  _buildRawReceiptsAudit(product, cs, strings, isAr, currency),
                ],
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton.tonal(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(strings.cancel, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceEvolutionTimeline(ChainProductItem product, ColorScheme cs, bool isAr, String currency) {
    final events = product.distinctPriceChangeEvents;

    if (events.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(isAr ? 'لا توجد تقلبات سعرية مسجلة' : 'No price fluctuations recorded', style: GoogleFonts.cairo(color: cs.onSurfaceVariant)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: events.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (ctx, idx) {
        final entry = events[idx];
        final isLatest = idx == 0;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isLatest ? cs.primaryContainer.withValues(alpha: 0.15) : cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isLatest ? cs.primary.withValues(alpha: 0.3) : cs.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.change_circle_rounded, color: cs.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          entry.storeChain,
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: cs.onSurface),
                        ),
                        if (isLatest) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isAr ? 'السعر الساري' : 'Active Price',
                              style: GoogleFonts.cairo(fontSize: 9, color: cs.onPrimary, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_rounded, size: 12, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          entry.receiptDate.isNotEmpty ? entry.receiptDate : (isAr ? 'غير محدد' : 'N/A'),
                          style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (entry.hasDiscount && entry.effectiveOriginalPrice > entry.price) ...[
                        Text(
                          '${entry.effectiveOriginalPrice.toStringAsFixed(entry.effectiveOriginalPrice == entry.effectiveOriginalPrice.roundToDouble() ? 0 : 2)} $currency',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            decoration: TextDecoration.lineThrough,
                            color: cs.error.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        '${entry.price.toStringAsFixed(entry.price == entry.price.roundToDouble() ? 0 : 2)} $currency',
                        style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold, color: cs.primary),
                      ),
                    ],
                  ),
                  if (entry.hasDiscount)
                    Text(
                      isAr ? 'عرض ترويجي' : 'Promotional Offer',
                      style: GoogleFonts.cairo(fontSize: 10, color: cs.primary, fontWeight: FontWeight.bold),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRawReceiptsAudit(
    ChainProductItem product,
    ColorScheme cs,
    AppStrings strings,
    bool isAr,
    String currency,
  ) {
    if (product.priceHistory.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(strings.noProductsInDatabase, style: GoogleFonts.cairo(color: cs.onSurfaceVariant)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      itemCount: product.priceHistory.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (ctx, index) {
        final entry = product.priceHistory[index];

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.receipt_outlined, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.storeChain} ${entry.branchName.isNotEmpty ? "• ${entry.branchName}" : ""}',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                    Row(
                      children: [
                        Text(entry.receiptDate, style: GoogleFonts.cairo(fontSize: 10, color: cs.onSurfaceVariant)),
                        const SizedBox(width: 8),
                        Text('#${entry.receiptNumber}', style: GoogleFonts.cairo(fontSize: 10, color: cs.onSurfaceVariant)),
                        if (entry.quantity > 1) ...[
                          const SizedBox(width: 8),
                          Text('(${entry.quantity} ${isAr ? "قطع" : "pcs"})', style: GoogleFonts.cairo(fontSize: 10, color: cs.primary, fontWeight: FontWeight.bold)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                '${entry.price.toStringAsFixed(entry.price == entry.price.roundToDouble() ? 0 : 2)} $currency',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: cs.primary),
              ),
              if (entry.receiptImageUrl.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.image_outlined, size: 18),
                  tooltip: strings.viewReceiptPhoto,
                  color: cs.primary,
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (iCtx) => Dialog(
                        backgroundColor: Colors.transparent,
                        insetPadding: const EdgeInsets.all(16),
                        child: Stack(
                          alignment: Alignment.topRight,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.network(
                                entry.receiptImageUrl,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  color: cs.surface,
                                  padding: const EdgeInsets.all(32),
                                  child: Text(isAr ? 'تعذر تحميل صورة الفاتورة' : 'Image load failed'),
                                ),
                              ),
                            ),
                            IconButton.filled(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.of(iCtx).pop(),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryStat({
    required String label,
    required String value,
    required String subtext,
    required Color color,
    required IconData icon,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.cairo(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            Text(
              value,
              style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: color),
            ),
            if (subtext.isNotEmpty)
              Text(
                subtext,
                style: GoogleFonts.cairo(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ],
    );
  }
}
