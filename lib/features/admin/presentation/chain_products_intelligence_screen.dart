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
  String _viewFilterMode = 'SHARED_ONLY'; // 'THREATS_ONLY', 'FATHALLA_WINNING', 'SHARED_ONLY', 'ALL_ARCHIVED'
  String _selectedChain = 'ALL'; // 'ALL' or specific chain name
  String _selectedBrand = 'ALL';
  bool _promotionsOnly = false;
  bool _fluctuationsOnly = false;
  String _sortBy = 'LATEST'; // 'LATEST', 'THREAT_DIFF', 'PRICE_ASC', 'PRICE_DESC', 'VARIANCE'
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
          // Extract all distinct chains and dynamic metrics
          final Set<String> chainsSet = {};
          final Set<String> brandsSet = {};
          int totalPromotionsCount = 0;
          int totalFluctuationsCount = 0;
          int threatsCount = 0;
          int fathallaWinningCount = 0;
          int sharedSkusCount = 0;

          for (final item in allProducts) {
            chainsSet.addAll(item.latestPricesByChain.keys);
            if (item.brand.isNotEmpty) brandsSet.add(item.brand);
            if (item.isCurrentlyOnPromotion) totalPromotionsCount++;
            if (item.hasPriceFluctuation) totalFluctuationsCount++;
            if (item.isUnderpricedByCompetitors) threatsCount++;
            if (item.isFathallaCheapest && item.isMultiChain) fathallaWinningCount++;
            if (item.isMultiChain) sharedSkusCount++;
          }

          final distinctChains = chainsSet.toList()..sort();
          if (distinctChains.contains('أسواق فتح الله')) {
            distinctChains.remove('أسواق فتح الله');
            distinctChains.insert(0, 'أسواق فتح الله');
          }
          final distinctBrands = brandsSet.toList()..sort();

          // Filter products based on Fathalla Defense & View Mode
          final filteredProducts = allProducts.where((p) {
            // 1. View Filter Mode (Default: SHARED_ONLY to hide single-chain clutter)
            if (_viewFilterMode == 'THREATS_ONLY') {
              if (!p.isUnderpricedByCompetitors) return false;
            } else if (_viewFilterMode == 'FATHALLA_WINNING') {
              if (!p.isFathallaCheapest || !p.isMultiChain) return false;
            } else if (_viewFilterMode == 'SHARED_ONLY') {
              if (!p.isMultiChain) return false;
            } else if (_viewFilterMode == 'ALL_ARCHIVED') {
              // Show complete database archive
            }

            // 2. Search Query
            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase().trim();
              final matchesName = p.name.toLowerCase().contains(q);
              final matchesBarcode = p.barcode.contains(q);
              final matchesBrand = p.brand.toLowerCase().contains(q);
              if (!matchesName && !matchesBarcode && !matchesBrand) return false;
            }

            // 3. Chain Filter
            if (_selectedChain != 'ALL') {
              if (!p.latestPricesByChain.containsKey(_selectedChain)) return false;
            }

            // 4. Brand Filter
            if (_selectedBrand != 'ALL') {
              if (p.brand != _selectedBrand) return false;
            }

            // 5. Promotions Only
            if (_promotionsOnly && !p.isCurrentlyOnPromotion) {
              return false;
            }

            // 6. Fluctuations Only
            if (_fluctuationsOnly && !p.hasPriceFluctuation) {
              return false;
            }

            return true;
          }).toList();

          // Sort products
          if (_sortBy == 'THREAT_DIFF') {
            filteredProducts.sort((a, b) => b.competitorUnderpricedDiff.compareTo(a.competitorUnderpricedDiff));
          } else if (_sortBy == 'PRICE_ASC') {
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
                            child: Icon(Icons.shield_rounded, size: 28, color: cs.primary),
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
                                        // Fathalla Baseline Tag
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.indigo.shade50,
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: Colors.indigo.shade200, width: 1),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.account_balance_rounded, size: 14, color: Colors.indigo),
                                              const SizedBox(width: 5),
                                              Text(
                                                strings.fathallaBaselineTag,
                                                style: GoogleFonts.cairo(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                  color: Colors.indigo.shade900,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Live AI Tracking Pill
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

                      // Executive Fathalla Defense KPI Cards Row
                      _buildKpiRow(
                        context: context,
                        cs: cs,
                        strings: strings,
                        threatsCount: threatsCount,
                        fathallaWinningCount: fathallaWinningCount,
                        sharedSkusCount: sharedSkusCount,
                        promotedItemsCount: totalPromotionsCount,
                        isMobile: isMobile,
                      ),
                      const SizedBox(height: 16),

                      // Fathalla Defense & Presence Segment Filter Bar
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            // 1. Threat Radar Mode (🚨 كسر الأسعار - المنافس أرخص)
                            _buildDefenseModeChip(
                              label: strings.filterSegmentThreatsOnly,
                              count: threatsCount,
                              icon: Icons.warning_amber_rounded,
                              activeColor: Colors.red.shade700,
                              activeBgColor: Colors.red.shade50,
                              isSelected: _viewFilterMode == 'THREATS_ONLY',
                              onSelected: () => setState(() => _viewFilterMode = 'THREATS_ONLY'),
                              cs: cs,
                            ),
                            const SizedBox(width: 8),

                            // 2. Fathalla Winning Mode (🏆 تفوق فتح الله - الأرخص)
                            _buildDefenseModeChip(
                              label: strings.filterSegmentFathallaWinning,
                              count: fathallaWinningCount,
                              icon: Icons.stars_rounded,
                              activeColor: Colors.green.shade800,
                              activeBgColor: Colors.green.shade50,
                              isSelected: _viewFilterMode == 'FATHALLA_WINNING',
                              onSelected: () => setState(() => _viewFilterMode = 'FATHALLA_WINNING'),
                              cs: cs,
                            ),
                            const SizedBox(width: 8),

                            // 3. Shared SKUs Mode (📊 الأصناف المشتركة - 2+ chains) [DEFAULT]
                            _buildDefenseModeChip(
                              label: strings.filterSegmentSharedOnly,
                              count: sharedSkusCount,
                              icon: Icons.compare_arrows_rounded,
                              activeColor: cs.primary,
                              activeBgColor: cs.primaryContainer.withValues(alpha: 0.3),
                              isSelected: _viewFilterMode == 'SHARED_ONLY',
                              onSelected: () => setState(() => _viewFilterMode = 'SHARED_ONLY'),
                              cs: cs,
                            ),
                            const SizedBox(width: 8),

                            // 4. All Database Archive Mode (🗄️ الأرشيف الشامل)
                            _buildDefenseModeChip(
                              label: strings.filterSegmentAllArchive,
                              count: allProducts.length,
                              icon: Icons.inventory_2_outlined,
                              activeColor: cs.secondary,
                              activeBgColor: cs.secondaryContainer.withValues(alpha: 0.3),
                              isSelected: _viewFilterMode == 'ALL_ARCHIVED',
                              onSelected: () => setState(() => _viewFilterMode = 'ALL_ARCHIVED'),
                              cs: cs,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

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
                                          value: 'THREAT_DIFF',
                                          child: Text(strings.sortByThreatDiff),
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
                                  label: Text(
                                    isAr ? 'تغيرات الأسعار ($totalFluctuationsCount)' : 'Price Shifts ($totalFluctuationsCount)',
                                    style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: _fluctuationsOnly ? FontWeight.w700 : FontWeight.normal),
                                  ),
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
                            style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isAr ? 'جرب البحث باسم صنف أو باركود أو تغيير خيارات الفلترة' : 'Try searching another product name or adjusting filters',
                            style: GoogleFonts.cairo(fontSize: 12.5, color: cs.outlineVariant),
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
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 380,
                      mainAxisExtent: 275,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final product = filteredProducts[index];
                        return ChainProductCard(product: product);
                      },
                      childCount: filteredProducts.length,
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDefenseModeChip({
    required String label,
    required int count,
    required IconData icon,
    required Color activeColor,
    required Color activeBgColor,
    required bool isSelected,
    required VoidCallback onSelected,
    required ColorScheme cs,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onSelected,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? activeBgColor : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? activeColor : cs.outlineVariant.withValues(alpha: 0.5),
            width: isSelected ? 1.5 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? activeColor : cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? activeColor : cs.onSurface,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? activeColor : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.cairo(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? Colors.white : cs.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
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
    required int threatsCount,
    required int fathallaWinningCount,
    required int sharedSkusCount,
    required int promotedItemsCount,
    required bool isMobile,
  }) {
    final cards = [
      _buildKpiCard(
        title: strings.metricPriceThreats,
        value: '$threatsCount',
        subtitle: ref.isArabic ? 'أصناف أرخص من فتح الله' : 'Cheaper than Fathalla',
        icon: Icons.warning_amber_rounded,
        color: Colors.red.shade700,
        bgColor: Colors.red.shade50,
        isSelected: _viewFilterMode == 'THREATS_ONLY',
        onTap: () => setState(() => _viewFilterMode = 'THREATS_ONLY'),
        cs: cs,
      ),
      _buildKpiCard(
        title: strings.metricFathallaWinning,
        value: '$fathallaWinningCount',
        subtitle: ref.isArabic ? 'أنت الأرخص في السوق' : 'Fathalla Best Price',
        icon: Icons.stars_rounded,
        color: Colors.green.shade800,
        bgColor: Colors.green.shade50,
        isSelected: _viewFilterMode == 'FATHALLA_WINNING',
        onTap: () => setState(() => _viewFilterMode = 'FATHALLA_WINNING'),
        cs: cs,
      ),
      _buildKpiCard(
        title: strings.metricSharedSkus,
        value: '$sharedSkusCount',
        subtitle: ref.isArabic ? 'سلسلتين فأكثر' : '2+ Stores Compared',
        icon: Icons.compare_arrows_rounded,
        color: cs.primary,
        bgColor: cs.primaryContainer.withValues(alpha: 0.35),
        isSelected: _viewFilterMode == 'SHARED_ONLY',
        onTap: () => setState(() => _viewFilterMode = 'SHARED_ONLY'),
        cs: cs,
      ),
      _buildKpiCard(
        title: strings.metricPromotedItems,
        value: '$promotedItemsCount',
        subtitle: ref.isArabic ? 'عروض ترويجية نشطة' : 'Active Discounts',
        icon: Icons.local_offer_rounded,
        color: cs.tertiary,
        bgColor: cs.tertiaryContainer.withValues(alpha: 0.35),
        isSelected: _promotionsOnly,
        onTap: () => setState(() => _promotionsOnly = !_promotionsOnly),
        cs: cs,
      ),
    ];

    if (isMobile) {
      return SizedBox(
        height: 82,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: cards.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (ctx, idx) => SizedBox(width: 175, child: cards[idx]),
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
    String? subtitle,
    required IconData icon,
    required Color color,
    Color? bgColor,
    bool isSelected = false,
    VoidCallback? onTap,
    required ColorScheme cs,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor ?? color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.22),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
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
                    style: GoogleFonts.cairo(
                      fontSize: 10.5,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Text(
                        value,
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: color,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            subtitle,
                            style: GoogleFonts.cairo(fontSize: 8.5, color: cs.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
    buffer.writeln('Cheapest Store,Min Price,Highest Store,Max Price,Price Gap %,Fathalla Defense Status,Cheapest Competitor,Price Underpriced Diff,Is Promoted,Total Scans');

    for (final item in items) {
      buffer.write('"${item.id}","${item.barcode}","${item.name}","${item.brand}","${item.category}",');
      for (final c in chains) {
        final p = item.latestPricesByChain[c];
        buffer.write('${p != null ? p.toStringAsFixed(2) : ""},');
      }
      final defenseStatus = item.isUnderpricedByCompetitors
          ? 'THREAT (${item.cheapestCompetitorName} cheaper)'
          : (item.isFathallaCheapest ? 'FATHALLA BEST PRICE' : 'NORMAL');

      buffer.writeln(
        '"${item.cheapestChain}",${item.minPrice.toStringAsFixed(2)},"${item.mostExpensiveChain}",${item.maxPrice.toStringAsFixed(2)},${item.priceVariancePercent.toStringAsFixed(1)},"$defenseStatus","${item.cheapestCompetitorName}",${item.competitorUnderpricedDiff.toStringAsFixed(2)},${item.isCurrentlyOnPromotion ? "YES" : "NO"},${item.totalScansCount}',
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
