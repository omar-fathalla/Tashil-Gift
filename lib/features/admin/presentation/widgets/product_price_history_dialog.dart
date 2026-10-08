import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/constants/country_currency_config.dart';
import '../../../../core/widgets/interactive_receipt_viewer_dialog.dart';
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
  late ScrollController _scrollController;
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && _selectedTabIndex != _tabController.index) {
        setState(() {
          _selectedTabIndex = _tabController.index;
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
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
        vertical: isMobile ? 16 : 24,
      ),
      child: Container(
        width: isMobile ? size.width * 0.95 : 880,
        constraints: BoxConstraints(
          maxHeight: size.height * (isMobile ? 0.94 : 0.90),
          maxWidth: isMobile ? size.width * 0.95 : 880,
        ),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
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
                    tooltip: strings.close,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Scrollable Body with Unified Fluid Motion
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Fathalla Defense Alert Banner
                          if (product.isUnderpricedByCompetitors) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: cs.errorContainer,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: cs.error.withValues(alpha: 0.3), width: 1.2),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: cs.error,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.warning_amber_rounded, color: cs.onError, size: 22),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isAr ? 'إنذار كسر سعر لمنافس (سعر أرخص من أسواق فتح الله)' : 'Competitor Price Threat Detected',
                                            style: GoogleFonts.cairo(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: cs.onErrorContainer,
                                            ),
                                          ),
                                          Text(
                                            isAr
                                                ? 'سلسلة «${product.cheapestCompetitorName}» تبيع هذا الصنف بسعر ${product.minPrice.toStringAsFixed(product.minPrice == product.minPrice.roundToDouble() ? 0 : 2)} $currency (أرخص من فتح الله بـ ${product.competitorUnderpricedDiff.toStringAsFixed(1)} $currency بنسبة -${product.competitorUnderpricedPercent.toStringAsFixed(0)}%)'
                                                : '«${product.cheapestCompetitorName}» is selling at ${product.minPrice.toStringAsFixed(2)} $currency (Cheaper than Fathalla by ${product.competitorUnderpricedDiff.toStringAsFixed(1)} $currency, -${product.competitorUnderpricedPercent.toStringAsFixed(0)}%)',
                                            style: GoogleFonts.cairo(
                                              fontSize: 11.5,
                                              color: cs.onErrorContainer.withValues(alpha: 0.85),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ] else if (product.isFathallaCheapest && product.isMultiChain) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: cs.primary.withValues(alpha: 0.3), width: 1.2),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: cs.primary,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.verified_rounded, color: cs.onPrimary, size: 22),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isAr ? 'أسواق فتح الله هي الأرخص في السوق لهذا الصنف!' : 'Fathalla Markets has the Best Price in Market!',
                                            style: GoogleFonts.cairo(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: cs.onPrimaryContainer,
                                            ),
                                          ),
                                          Text(
                                            isAr
                                                ? 'سعر فتح الله (${(product.fathallaPrice ?? 0.0).toStringAsFixed((product.fathallaPrice ?? 0.0) == (product.fathallaPrice ?? 0.0).roundToDouble() ? 0 : 2)} $currency) يتفوق على كافة السلاسل المنافسة.'
                                                : 'Fathalla price (${(product.fathallaPrice ?? 0.0).toStringAsFixed(2)} $currency) outperforms all competitor chains.',
                                            style: GoogleFonts.cairo(
                                              fontSize: 11.5,
                                              color: cs.onPrimaryContainer.withValues(alpha: 0.85),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],

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
                                  ScrollConfiguration(
                                    behavior: ScrollConfiguration.of(context).copyWith(
                                      dragDevices: {
                                        PointerDeviceKind.touch,
                                        PointerDeviceKind.mouse,
                                        PointerDeviceKind.trackpad,
                                      },
                                    ),
                                    child: SingleChildScrollView(
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
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            chainSum.chainName,
                                                            style: GoogleFonts.cairo(
                                                              fontWeight: FontWeight.bold,
                                                              fontSize: 12,
                                                              color: cs.onSurface,
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                          if (product.latestPosNameByChain.containsKey(chainSum.chainName) &&
                                                              product.latestPosNameByChain[chainSum.chainName]!.isNotEmpty) ...[
                                                            Text(
                                                              product.latestPosNameByChain[chainSum.chainName]!,
                                                              style: GoogleFonts.cairo(
                                                                fontSize: 9.5,
                                                                color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                                                              ),
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ],
                                                        ],
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
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),

                    // Sticky/Pinned Tab Bar
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _SliverTabBarDelegate(
                        height: 52,
                        child: Container(
                          decoration: BoxDecoration(
                            color: cs.surface,
                            border: Border(
                              bottom: BorderSide(
                                color: cs.outlineVariant.withValues(alpha: 0.35),
                                width: 1,
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TabBar(
                            controller: _tabController,
                            onTap: (index) {
                              if (_selectedTabIndex != index) {
                                setState(() {
                                  _selectedTabIndex = index;
                                });
                              }
                            },
                            labelColor: cs.primary,
                            unselectedLabelColor: cs.onSurfaceVariant,
                            indicatorColor: cs.primary,
                            indicatorWeight: 3,
                            labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                            unselectedLabelStyle: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 13),
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
                      ),
                    ),

                    // Active Tab Sliver View
                    if (_selectedTabIndex == 0)
                      _buildPriceEvolutionSliver(product, cs, isAr, currency)
                    else
                      _buildRawReceiptsSliver(product, cs, strings, isAr, currency),
                  ],
                ),
              ),
            ),

            // Fixed Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                border: Border(
                  top: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: Text(strings.close, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceEvolutionSliver(ChainProductItem product, ColorScheme cs, bool isAr, String currency) {
    final events = product.distinctPriceChangeEvents;

    if (events.isEmpty) {
      return SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
            child: Text(
              isAr ? 'لا توجد تقلبات سعرية مسجلة' : 'No price fluctuations recorded',
              style: GoogleFonts.cairo(color: cs.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final entry = events[index];
            final isLatest = index == 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildPriceEvolutionItem(entry, isLatest, cs, isAr, currency),
            );
          },
          childCount: events.length,
        ),
      ),
    );
  }

  Widget _buildPriceEvolutionItem(
    ProductPriceHistoryEntry entry,
    bool isLatest,
    ColorScheme cs,
    bool isAr,
    String currency,
  ) {
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
  }

  Widget _buildRawReceiptsSliver(
    ChainProductItem product,
    ColorScheme cs,
    AppStrings strings,
    bool isAr,
    String currency,
  ) {
    if (product.priceHistory.isEmpty) {
      return SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
            child: Text(
              strings.noProductsInDatabase,
              style: GoogleFonts.cairo(color: cs.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final entry = product.priceHistory[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildRawReceiptItem(entry, cs, strings, isAr, currency),
            );
          },
          childCount: product.priceHistory.length,
        ),
      ),
    );
  }

  Widget _buildRawReceiptItem(
    ProductPriceHistoryEntry entry,
    ColorScheme cs,
    AppStrings strings,
    bool isAr,
    String currency,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_outlined, size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.storeChain} ${entry.branchName.isNotEmpty ? "• ${entry.branchName}" : ""}',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(entry.receiptDate, style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant)),
                    const SizedBox(width: 10),
                    Text('#${entry.receiptNumber}', style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant)),
                    if (entry.quantity > 1) ...[
                      const SizedBox(width: 10),
                      Text('(${entry.quantity} ${isAr ? "قطع" : "pcs"})', style: GoogleFonts.cairo(fontSize: 11, color: cs.primary, fontWeight: FontWeight.bold)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Text(
            '${entry.price.toStringAsFixed(entry.price == entry.price.roundToDouble() ? 0 : 2)} $currency',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14, color: cs.primary),
          ),
          if (entry.receiptImageUrl.isNotEmpty) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.image_outlined, size: 20),
              tooltip: strings.viewReceiptPhoto,
              color: cs.primary,
              onPressed: () {
                InteractiveReceiptViewerDialog.show(
                  context,
                  imageUrl: entry.receiptImageUrl,
                  receiptNumber: entry.receiptNumber,
                  storeName: entry.storeChain,
                  branchName: entry.branchName,
                  totalValue: entry.price.toStringAsFixed(entry.price == entry.price.roundToDouble() ? 0 : 2),
                  date: entry.receiptDate,
                  currencySymbol: currency,
                );
              },
            ),
          ],
        ],
      ),
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

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  _SliverTabBarDelegate({required this.child, this.height = 52.0});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(
      height: height,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _SliverTabBarDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.height != height;
  }
}
