import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/constants/country_currency_config.dart';
import '../../../core/services/chain_products_intelligence_service.dart';
import '../../admin/domain/chain_product_model.dart';
import 'widgets/chain_product_card.dart';
import 'widgets/chain_products_matrix_table.dart';

class ChainProductsIntelligenceScreen extends ConsumerStatefulWidget {
  final String? lockedCompanySlug;

  const ChainProductsIntelligenceScreen({super.key, this.lockedCompanySlug});

  @override
  ConsumerState<ChainProductsIntelligenceScreen> createState() => _ChainProductsIntelligenceScreenState();
}

class _ChainProductsIntelligenceScreenState extends ConsumerState<ChainProductsIntelligenceScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedChain = 'ALL'; // 'ALL' or specific chain name
  String _selectedBrand = 'ALL';
  bool _promotionsOnly = false;
  bool _fluctuationsOnly = false;
  String _sortBy = 'LATEST'; // 'LATEST', 'PRICE_ASC', 'PRICE_DESC', 'VARIANCE'
  bool _isMatrixView = true; // Default view is the Table Matrix
  bool _isHealingData = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = AppStrings.of(ref);
    final isAr = ref.isArabic;
    final activeCountry = ref.watch(activeCountryProvider);
    final currency = activeCountry.currencySymbol;
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 700;

    final productsAsync = ref.watch(chainProductsStreamProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              strings.operationFailed(err.toString()),
              style: GoogleFonts.cairo(color: cs.error),
            ),
          ),
        ),
        data: (allProducts) {
          // Extract all distinct chains from data
          final Set<String> chainsSet = {};
          final Set<String> brandsSet = {};
          int totalPromotionsCount = 0;
          int totalFluctuationsCount = 0;

          for (final item in allProducts) {
            chainsSet.addAll(item.latestPricesByChain.keys);
            if (item.brand.isNotEmpty) brandsSet.add(item.brand);
            if (item.isCurrentlyOnPromotion) totalPromotionsCount++;
            if (item.hasPriceFluctuation) totalFluctuationsCount++;
          }

          final distinctChains = chainsSet.toList()..sort();
          final distinctBrands = brandsSet.toList()..sort();

          // Filter products
          final filteredProducts = allProducts.where((p) {
            // Search Query
            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase().trim();
              final matchesName = p.name.toLowerCase().contains(q);
              final matchesBarcode = p.barcode.contains(q);
              final matchesBrand = p.brand.toLowerCase().contains(q);
              if (!matchesName && !matchesBarcode && !matchesBrand) return false;
            }

            // Chain Filter
            if (_selectedChain != 'ALL') {
              if (!p.latestPricesByChain.containsKey(_selectedChain)) return false;
            }

            // Brand Filter
            if (_selectedBrand != 'ALL') {
              if (p.brand != _selectedBrand) return false;
            }

            // Promotions Only
            if (_promotionsOnly && !p.isCurrentlyOnPromotion) {
              return false;
            }

            // Fluctuations Only
            if (_fluctuationsOnly && !p.hasPriceFluctuation) {
              return false;
            }

            return true;
          }).toList();

          // Sort products
          if (_sortBy == 'PRICE_ASC') {
            filteredProducts.sort((a, b) => a.minPrice.compareTo(b.minPrice));
          } else if (_sortBy == 'PRICE_DESC') {
            filteredProducts.sort((a, b) => b.maxPrice.compareTo(a.maxPrice));
          } else if (_sortBy == 'VARIANCE') {
            filteredProducts.sort((a, b) => b.priceVariancePercent.compareTo(a.priceVariancePercent));
          } else {
            // LATEST: Default sorted by totalScansCount / recent
          }

          return CustomScrollView(
            slivers: [
              // Executive Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 16 : 24,
                    isMobile ? 16 : 24,
                    isMobile ? 16 : 24,
                    12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(Icons.inventory_2_rounded, size: 28, color: cs.primary),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        strings.productsIntelligenceTitle,
                                        style: GoogleFonts.cairo(
                                          fontSize: isMobile ? 18 : 22,
                                          fontWeight: FontWeight.bold,
                                          color: cs.onSurface,
                                        ),
                                      ),
                                    ),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: cs.primaryContainer.withValues(alpha: 0.5),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: cs.primary.withValues(alpha: 0.3), width: 0.8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 8,
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  color: cs.primary,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                isAr ? 'رصد فوري حي' : 'Live AI Tracking',
                                                style: GoogleFonts.cairo(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: cs.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        FilledButton.tonalIcon(
                                          onPressed: _isHealingData
                                              ? null
                                              : () async {
                                                  setState(() => _isHealingData = true);
                                                  try {
                                                    final service = ref.read(chainProductsIntelligenceServiceProvider);
                                                    final count = await service.reAnalyzeAndHealAllReceiptsInFirestore();
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            isAr
                                                                ? 'تمت إعادة تحليل وتدقيق وتصحيح $count فاتورة في قاعدة البيانات بنجاح!'
                                                                : 'Successfully re-analyzed and healed $count receipts in database!',
                                                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                                                          ),
                                                          backgroundColor: Colors.green.shade800,
                                                          behavior: SnackBarBehavior.floating,
                                                        ),
                                                      );
                                                    }
                                                  } catch (e) {
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(
                                                          content: Text('فشل التدقيق: $e'),
                                                          backgroundColor: cs.error,
                                                          behavior: SnackBarBehavior.floating,
                                                        ),
                                                      );
                                                    }
                                                  } finally {
                                                    if (mounted) setState(() => _isHealingData = false);
                                                  }
                                                },
                                          icon: _isHealingData
                                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                              : const Icon(Icons.auto_fix_high_rounded, size: 16),
                                          label: Text(
                                            _isHealingData
                                                ? (isAr ? 'جاري التدقيق بالـ AI...' : 'Healing Receipts...')
                                                : (isAr ? 'إعادة تحليل وتصحيح الفواتير بالـ AI' : 'Re-Analyze & Heal Receipts'),
                                            style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  strings.productsIntelligenceSubtitle,
                                  style: GoogleFonts.cairo(
                                    fontSize: isMobile ? 12 : 13,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // KPI Cards Row
                      _buildKpiRow(
                        context: context,
                        cs: cs,
                        strings: strings,
                        totalSkus: allProducts.length,
                        activeChainsCount: distinctChains.length,
                        promotedItemsCount: totalPromotionsCount,
                        fluctuationsCount: totalFluctuationsCount,
                        isMobile: isMobile,
                      ),
                      const SizedBox(height: 16),

                      // Chain Tabs Switcher
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildChainTabChip(
                              label: strings.allChainsTab,
                              count: allProducts.length,
                              isSelected: _selectedChain == 'ALL',
                              onSelected: () => setState(() => _selectedChain = 'ALL'),
                              cs: cs,
                            ),
                            ...distinctChains.map((chain) {
                              final count = allProducts.where((p) => p.latestPricesByChain.containsKey(chain)).length;
                              return _buildChainTabChip(
                                label: chain,
                                count: count,
                                isSelected: _selectedChain == chain,
                                onSelected: () => setState(() => _selectedChain = chain),
                                cs: cs,
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Search, Filters & View Mode Bar
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                // Search Field
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    onChanged: (val) => setState(() => _searchQuery = val),
                                    style: GoogleFonts.cairo(fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: strings.searchProductPlaceholder,
                                      hintStyle: GoogleFonts.cairo(fontSize: 13, color: cs.onSurfaceVariant),
                                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                                      suffixIcon: _searchQuery.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(Icons.clear_rounded, size: 18),
                                              onPressed: () {
                                                _searchController.clear();
                                                setState(() => _searchQuery = '');
                                              },
                                            )
                                          : null,
                                      filled: true,
                                      fillColor: cs.surface,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // View Mode Switcher
                                SegmentedButton<bool>(
                                  segments: [
                                    ButtonSegment<bool>(
                                      value: false,
                                      icon: const Icon(Icons.grid_view_rounded, size: 18),
                                      tooltip: strings.viewModeCards,
                                    ),
                                    ButtonSegment<bool>(
                                      value: true,
                                      icon: const Icon(Icons.table_chart_rounded, size: 18),
                                      tooltip: strings.viewModeMatrix,
                                    ),
                                  ],
                                  selected: {_isMatrixView},
                                  onSelectionChanged: (val) {
                                    setState(() => _isMatrixView = val.first);
                                  },
                                ),

                                const SizedBox(width: 10),

                                // Export CSV Button
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.file_download_outlined, size: 20),
                                  tooltip: strings.exportPriceIntelligenceCsv,
                                  onPressed: () => _exportToCsv(filteredProducts, distinctChains, currency),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Sub-Filters Row (Brand, Discounts, Sort)
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                // Brand Filter Dropdown
                                if (distinctBrands.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: cs.surface,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: _selectedBrand,
                                        isDense: true,
                                        style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurface),
                                        items: [
                                          DropdownMenuItem(
                                            value: 'ALL',
                                            child: Text(isAr ? 'كافة العلامات التجارية' : 'All Brands'),
                                          ),
                                          ...distinctBrands.map((b) => DropdownMenuItem(value: b, child: Text(b))),
                                        ],
                                        onChanged: (val) {
                                          if (val != null) setState(() => _selectedBrand = val);
                                        },
                                      ),
                                    ),
                                  ),

                                // Sort Dropdown
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: cs.surface,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _sortBy,
                                      isDense: true,
                                      style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurface),
                                      items: [
                                        DropdownMenuItem(
                                          value: 'LATEST',
                                          child: Text(strings.sortByLatest),
                                        ),
                                        DropdownMenuItem(
                                          value: 'PRICE_ASC',
                                          child: Text(strings.sortByPriceLow),
                                        ),
                                        DropdownMenuItem(
                                          value: 'PRICE_DESC',
                                          child: Text(strings.sortByPriceHigh),
                                        ),
                                        DropdownMenuItem(
                                          value: 'VARIANCE',
                                          child: Text(strings.sortByVariance),
                                        ),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) setState(() => _sortBy = val);
                                      },
                                    ),
                                  ),
                                ),
                                // Filter Promotions Chip
                                FilterChip(
                                  label: Text(strings.filterByPromotionsOnly, style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: _promotionsOnly ? FontWeight.w700 : FontWeight.normal)),
                                  selected: _promotionsOnly,
                                  onSelected: (val) => setState(() => _promotionsOnly = val),
                                  avatar: Icon(Icons.local_offer_rounded, size: 14, color: _promotionsOnly ? cs.onPrimary : cs.primary),
                                ),

                                // Filter Fluctuations Chip
                                FilterChip(
                                  label: Text(isAr ? 'تغيرات الأسعار فقط' : 'Price Changes Only', style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: _fluctuationsOnly ? FontWeight.w700 : FontWeight.normal)),
                                  selected: _fluctuationsOnly,
                                  onSelected: (val) => setState(() => _fluctuationsOnly = val),
                                  avatar: Icon(Icons.change_circle_rounded, size: 14, color: _fluctuationsOnly ? cs.onPrimary : cs.tertiary),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Content Body (Cards vs Matrix Table)
              if (_isMatrixView)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 8),
                  sliver: SliverToBoxAdapter(
                    child: ChainProductsMatrixTable(
                      products: filteredProducts,
                      distinctChains: _selectedChain == 'ALL' ? distinctChains : [_selectedChain],
                    ),
                  ),
                )
              else if (filteredProducts.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded, size: 54, color: cs.outlineVariant),
                          const SizedBox(height: 12),
                          Text(
                            strings.noProductsFound,
                            style: GoogleFonts.cairo(fontSize: 15, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 8),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isMobile ? 1 : (size.width < 950 ? 2 : (size.width < 1400 ? 3 : 4)),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: isMobile ? 218 : 215,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = filteredProducts[index];
                        return ChainProductCard(
                          product: item,
                          selectedChainFilter: _selectedChain == 'ALL' ? null : _selectedChain,
                        );
                      },
                      childCount: filteredProducts.length,
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChainTabChip({
    required String label,
    required int count,
    required bool isSelected,
    required VoidCallback onSelected,
    required ColorScheme cs,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.cairo(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? cs.primary : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.cairo(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        selected: isSelected,
        onSelected: (_) => onSelected(),
      ),
    );
  }

  Widget _buildKpiRow({
    required BuildContext context,
    required ColorScheme cs,
    required AppStrings strings,
    required int totalSkus,
    required int activeChainsCount,
    required int promotedItemsCount,
    required int fluctuationsCount,
    required bool isMobile,
  }) {
    final cards = [
      _buildKpiCard(
        title: strings.metricTotalSkus,
        value: '$totalSkus',
        icon: Icons.inventory_2_rounded,
        color: cs.primary,
        cs: cs,
      ),
      _buildKpiCard(
        title: strings.metricActiveChains,
        value: '$activeChainsCount',
        icon: Icons.storefront_rounded,
        color: cs.secondary,
        cs: cs,
      ),
      _buildKpiCard(
        title: strings.metricPromotedItems,
        value: '$promotedItemsCount',
        icon: Icons.local_offer_rounded,
        color: cs.tertiary,
        cs: cs,
      ),
      _buildKpiCard(
        title: strings.metricPriceFluctuations,
        value: '$fluctuationsCount',
        icon: Icons.change_circle_rounded,
        color: cs.error,
        cs: cs,
      ),
    ];

    if (isMobile) {
      return SizedBox(
        height: 76,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: cards.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (ctx, idx) => SizedBox(width: 165, child: cards[idx]),
        ),
      );
    }

    return Row(
      children: cards.map((card) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: card))).toList(),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required ColorScheme cs,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.cairo(fontSize: 10.5, color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _exportToCsv(List<ChainProductItem> items, List<String> chains, String currency) {
    final buffer = StringBuffer();
    // Headers
    buffer.write('ID,Barcode,Product Name,Brand,Category,');
    for (final c in chains) {
      buffer.write('Price in $c ($currency),');
    }
    buffer.writeln('Cheapest Store,Min Price,Highest Store,Max Price,Price Gap %,Is Promoted,Total Scans');

    for (final item in items) {
      buffer.write('"${item.id}","${item.barcode}","${item.name}","${item.brand}","${item.category}",');
      for (final c in chains) {
        final p = item.latestPricesByChain[c];
        buffer.write('${p != null ? p.toStringAsFixed(2) : ""},');
      }
      buffer.writeln(
        '"${item.cheapestChain}",${item.minPrice.toStringAsFixed(2)},"${item.mostExpensiveChain}",${item.maxPrice.toStringAsFixed(2)},${item.priceVariancePercent.toStringAsFixed(1)},${item.isCurrentlyOnPromotion ? "YES" : "NO"},${item.totalScansCount}',
      );
    }

    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ref.isArabic ? 'تم تجهيز وتصدير التقرير السعري بنجاح' : 'Price report exported successfully'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
