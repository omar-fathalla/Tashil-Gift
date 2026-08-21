import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/constants/country_currency_config.dart';
import '../../domain/chain_product_model.dart';
import 'product_price_history_dialog.dart';

class ChainProductCard extends ConsumerWidget {
  final ChainProductItem product;
  final String? selectedChainFilter;

  const ChainProductCard({
    super.key,
    required this.product,
    this.selectedChainFilter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final activeCountry = ref.watch(activeCountryProvider);
    final currency = activeCountry.currencySymbol;
    final isAr = ref.isArabic;

    // Price to display (if chain filtered, display that chain's price, else latest overall)
    final double displayPrice = (selectedChainFilter != null && product.latestPricesByChain.containsKey(selectedChainFilter))
        ? product.latestPricesByChain[selectedChainFilter]!
        : product.latestOverallPrice;

    final String displayDate = (selectedChainFilter != null && product.latestDatesByChain.containsKey(selectedChainFilter))
        ? product.latestDatesByChain[selectedChainFilter]!
        : product.latestOverallDate;

    final bool isOnPromotion = product.isCurrentlyOnPromotion;
    final bool hasFluctuation = product.hasPriceFluctuation;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isOnPromotion
              ? cs.primary.withValues(alpha: 0.5)
              : cs.outlineVariant.withValues(alpha: 0.45),
          width: isOnPromotion ? 1.5 : 1,
        ),
      ),
      color: cs.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          showProductPriceHistoryDialog(
            context: context,
            product: product,
            ref: ref,
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Metadata & Badges Row
              Row(
                children: [
                  // Brand Chip
                  if (product.brand.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        product.brand,
                        style: GoogleFonts.cairo(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                  if (product.brand.isNotEmpty && product.category.isNotEmpty)
                    const SizedBox(width: 5),
                  // Category Chip
                  if (product.category.isNotEmpty)
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          product.category,
                          style: GoogleFonts.cairo(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  const Spacer(),
                  // Promotion or Fluctuation Tonal Tag
                  if (isOnPromotion)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_offer_rounded, size: 11, color: cs.primary),
                          const SizedBox(width: 3),
                          Text(
                            isAr ? 'عرض ترويجي' : 'Promo',
                            style: GoogleFonts.cairo(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (hasFluctuation)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: cs.tertiaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.change_circle_rounded, size: 11, color: cs.onTertiaryContainer),
                          const SizedBox(width: 3),
                          Text(
                            isAr ? 'تغير سعر' : 'Price Shift',
                            style: GoogleFonts.cairo(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: cs.onTertiaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 6),

              // Product Name (2 Lines Max, balanced typography)
              SizedBox(
                height: 38,
                child: Text(
                  product.name,
                  style: GoogleFonts.cairo(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: cs.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              const SizedBox(height: 4),

              // Barcode Pill with Copy Affordance
              if (product.barcode.isNotEmpty)
                Tooltip(
                  message: isAr ? 'انقر لنسخ الباركود' : 'Click to copy barcode',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: product.barcode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isAr ? 'تم نسخ الباركود: ${product.barcode}' : 'Barcode copied: ${product.barcode}'),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.qr_code_2_rounded, size: 13, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          product.barcode,
                          style: GoogleFonts.cairo(
                            fontSize: 10.5,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.copy_rounded, size: 11, color: cs.primary),
                      ],
                    ),
                  ),
                )
              else
                const SizedBox(height: 16),

              const SizedBox(height: 6),
              Divider(height: 1, thickness: 0.5, color: cs.outlineVariant.withValues(alpha: 0.3)),
              const SizedBox(height: 6),

              // Price & Observation Date Row
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isOnPromotion && product.priceHistory.isNotEmpty && product.priceHistory.first.effectiveOriginalPrice > displayPrice) ...[
                    Row(
                      children: [
                        Text(
                          '${product.priceHistory.first.effectiveOriginalPrice.toStringAsFixed(product.priceHistory.first.effectiveOriginalPrice == product.priceHistory.first.effectiveOriginalPrice.roundToDouble() ? 0 : 2)} $currency',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            decoration: TextDecoration.lineThrough,
                            color: cs.error.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            product.priceHistory.first.calculatedDiscountPercent > 0
                                ? 'خصم ${product.priceHistory.first.calculatedDiscountPercent.toStringAsFixed(0)}%'
                                : 'وفر ${product.priceHistory.first.discountAmount.toStringAsFixed(0)}',
                            style: GoogleFonts.cairo(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        displayPrice.toStringAsFixed(displayPrice == displayPrice.roundToDouble() ? 0 : 2),
                        style: GoogleFonts.cairo(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: cs.primary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        currency,
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
                      ),
                      const Spacer(),
                      if (displayDate.isNotEmpty) ...[
                        Icon(Icons.calendar_today_rounded, size: 11, color: cs.onSurfaceVariant),
                        const SizedBox(width: 3),
                        Text(
                          displayDate,
                          style: GoogleFonts.cairo(fontSize: 10, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // Cross-Chain Comparison Summary Chips
              if (product.latestPricesByChain.length > 1)
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: product.latestPricesByChain.entries.take(3).map((e) {
                    final isMin = e.value == product.minPrice;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isMin ? cs.primaryContainer.withValues(alpha: 0.35) : cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isMin ? cs.primary.withValues(alpha: 0.5) : cs.outlineVariant.withValues(alpha: 0.35),
                          width: isMin ? 1 : 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isMin) ...[
                            Icon(Icons.star_rounded, size: 12, color: cs.primary),
                            const SizedBox(width: 2),
                          ],
                          Text(
                            '${e.key}: ${e.value.toStringAsFixed(e.value == e.value.roundToDouble() ? 0 : 1)} $currency',
                            style: GoogleFonts.cairo(
                              fontSize: 9.5,
                              fontWeight: isMin ? FontWeight.w700 : FontWeight.normal,
                              color: isMin ? cs.onSurface : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                )
              else
                const SizedBox(height: 18),

              const SizedBox(height: 6),

              // Footer: Scans & Interactive Action Indicator
              Row(
                children: [
                  Icon(Icons.receipt_long_rounded, size: 13, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    '${product.totalScansCount} ${isAr ? "رصد" : "scans"} (${product.totalQuantitySold} ${isAr ? "قطعة" : "pcs"})',
                    style: GoogleFonts.cairo(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isAr ? 'عرض السجل' : 'History',
                          style: GoogleFonts.cairo(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          isAr ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded,
                          size: 11,
                          color: cs.primary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
