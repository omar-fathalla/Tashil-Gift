import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:excel/excel.dart' as xl;
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/constants/country_currency_config.dart';
import '../../../core/services/chain_products_intelligence_service.dart';
import '../../../core/widgets/m3_progress_indicators.dart';
import '../../../core/animations/m3_motion.dart';
import '../../../core/utils/file_download_helper.dart';
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
  // Default to THREATS_ONLY per user audio instructions (Priority 1: Competitors Cheaper)
  String _viewFilterMode = 'THREATS_ONLY'; // 'THREATS_ONLY', 'COMPETITOR_PROMO_NOT_AT_FATHALLA', 'ALL_COMPETITOR_PROMOS', 'THREATS_WITH_PROMO', 'ALL_ARCHIVED'
  String _selectedChain = 'ALL'; // 'ALL' or specific chain name
  String _selectedBrand = 'ALL';
  bool _promotionsOnly = false;
  bool _fluctuationsOnly = false;
  bool _selectedChainPromoOnly = false; // Filter to selected chain's promotions only
  String _sortBy = 'LATEST'; // 'LATEST', 'THREAT_DIFF', 'PRICE_ASC', 'PRICE_DESC', 'VARIANCE'
  bool _isMatrixView = true; // Default view is the Table Matrix
  bool _isHeadToHeadMode = false; // Toggle between Omni Radar & Head-to-Head Comparison
  String _headToHeadChain1 = 'أسواق فتح الله';
  String _headToHeadChain2 = 'جملة ماركت';
  bool _isHealingData = false;
  double _healingProgress = 0.0;
  int _healingCurrent = 0;
  int _healingTotal = 0;
  String _healingStatus = '';
  bool _isExporting = false;

  // Memoized computation caches for 60fps instant UI rebuilding (Rule 9)
  String? _lastFilterCacheKey;
  List<ChainProductItem> _cachedFilteredProducts = [];
  List<String> _cachedDistinctChains = [];
  List<String> _cachedDistinctBrands = [];
  int _cachedTotalPromos = 0;
  int _cachedTotalFluctuations = 0;
  int _cachedThreats = 0;
  int _cachedCompetitorPromosNotAtFathalla = 0;
  int _cachedAllCompetitorPromos = 0;
  int _cachedThreatsWithPromo = 0;
  int _cachedH2hChain2Cheaper = 0;
  int _cachedH2hChain1Cheaper = 0;
  int _cachedH2hChain2Promos = 0;
  int _cachedH2hChain2PromoNotChain1 = 0;

  Future<void> _startHealingProcess({required bool incrementalOnly}) async {
    setState(() {
      _isHealingData = true;
      _healingProgress = 0.0;
      _healingCurrent = 0;
      _healingTotal = 0;
      _healingStatus = ref.isArabic ? 'جاري بدء الاتصال بقاعدة البيانات...' : 'Connecting to database...';
    });

    try {
      final service = ref.read(chainProductsIntelligenceServiceProvider);
      final count = await service.reAnalyzeAndHealAllReceiptsInFirestore(
        incrementalOnly: incrementalOnly,
        onProgress: (processed, total, status) {
          if (mounted) {
            setState(() {
              _healingCurrent = processed;
              _healingTotal = total;
              _healingProgress = total > 0 ? (processed / total).clamp(0.0, 1.0) : 0.0;
              _healingStatus = status;
            });
          }
        },
      );

      if (mounted) {
        final isAr = ref.isArabic;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAr
                  ? (incrementalOnly
                      ? 'تم تدقيق الفواتير الجديدة وتحديث $count فاتورة بنجاح!'
                      : 'تمت إعادة التدقيق الشامل وتصحيح $count فاتورة في قاعدة البيانات بنجاح!')
                  : 'Successfully audited and updated $count receipts in database!',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل التدقيق: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isHealingData = false;
          _healingProgress = 0.0;
        });
      }
    }
  }

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
          final currentCacheKey = '${allProducts.length}_${_viewFilterMode}_${_searchQuery}_${_selectedChain}_${_selectedBrand}_${_promotionsOnly}_${_fluctuationsOnly}_${_selectedChainPromoOnly}_${_isHeadToHeadMode}_${_headToHeadChain1}_${_headToHeadChain2}_$_sortBy';

          if (_lastFilterCacheKey != currentCacheKey) {
            _lastFilterCacheKey = currentCacheKey;

            // Extract all distinct chains and dynamic metrics
            final Set<String> chainsSet = {};
            final Set<String> brandsSet = {};
            int totalPromotionsCount = 0;
            int totalFluctuationsCount = 0;
            int threatsCount = 0;
            int competitorPromosNotAtFathallaCount = 0;
            int allCompetitorPromosCount = 0;
            int threatsWithPromoCount = 0;

            // Head-to-Head metrics
            int h2hChain2Cheaper = 0;
            int h2hChain1Cheaper = 0;
            int h2hChain2Promos = 0;
            int h2hChain2PromoNotChain1 = 0;

            for (final item in allProducts) {
              chainsSet.addAll(item.latestPricesByChain.keys);
              if (item.brand.isNotEmpty) brandsSet.add(item.brand);
              if (item.isCurrentlyOnPromotion) totalPromotionsCount++;
              if (item.hasPriceFluctuation) totalFluctuationsCount++;
              if (item.isUnderpricedByCompetitors) threatsCount++;
              if (item.isCompetitorPromoNotAtFathalla) competitorPromosNotAtFathallaCount++;
              if (item.isAnyCompetitorOnPromotion) allCompetitorPromosCount++;
              if (item.isThreatWithPromo) threatsWithPromoCount++;

              // Head-to-Head direct comparison stats
              final p1 = item.latestPricesByChain[_headToHeadChain1];
              final p2 = item.latestPricesByChain[_headToHeadChain2];
              if (p1 != null && p2 != null) {
                if (p2 < (p1 - 0.05)) h2hChain2Cheaper++;
                if (p1 < (p2 - 0.05)) h2hChain1Cheaper++;
              }
              final isChain2Promo = item.isChainOnPromotion(_headToHeadChain2);
              if (isChain2Promo) {
                h2hChain2Promos++;
                final isChain1Promo = item.isChainOnPromotion(_headToHeadChain1);
                if (p1 == null || !isChain1Promo) {
                  h2hChain2PromoNotChain1++;
                }
              }
            }

            final distinctChains = chainsSet.toList()..sort();
            if (distinctChains.contains('أسواق فتح الله')) {
              distinctChains.remove('أسواق فتح الله');
              distinctChains.insert(0, 'أسواق فتح الله');
            }
            final distinctBrands = brandsSet.toList()..sort();

            // Filter products based on selected mode & criteria
            final filteredProducts = allProducts.where((p) {
              // 1. Head-to-Head Scope Constraint
              if (_isHeadToHeadMode) {
                final hasChain1 = p.latestPricesByChain.containsKey(_headToHeadChain1);
                final hasChain2 = p.latestPricesByChain.containsKey(_headToHeadChain2);
                if (!hasChain1 && !hasChain2) return false;

                final p1 = p.latestPricesByChain[_headToHeadChain1];
                final p2 = p.latestPricesByChain[_headToHeadChain2];

                if (_viewFilterMode == 'THREATS_ONLY') {
                  if (p1 == null || p2 == null || p2 >= (p1 - 0.05)) return false;
                } else if (_viewFilterMode == 'COMPETITOR_PROMO_NOT_AT_FATHALLA') {
                  final isChain2Promo = p.isChainOnPromotion(_headToHeadChain2);
                  final isChain1Promo = p.isChainOnPromotion(_headToHeadChain1);
                  if (!isChain2Promo || (p1 != null && isChain1Promo)) return false;
                } else if (_viewFilterMode == 'ALL_COMPETITOR_PROMOS') {
                  if (!p.isChainOnPromotion(_headToHeadChain2)) return false;
                } else if (_viewFilterMode == 'THREATS_WITH_PROMO') {
                  final isChain2Promo = p.isChainOnPromotion(_headToHeadChain2);
                  if (!isChain2Promo || p1 == null || p2 == null || p2 >= (p1 - 0.05)) return false;
                }
              } else {
                // Omni-Chain Radar Filter Mode
                if (_viewFilterMode == 'THREATS_ONLY') {
                  if (!p.isUnderpricedByCompetitors) return false;
                } else if (_viewFilterMode == 'COMPETITOR_PROMO_NOT_AT_FATHALLA') {
                  if (!p.isCompetitorPromoNotAtFathalla) return false;
                } else if (_viewFilterMode == 'ALL_COMPETITOR_PROMOS') {
                  if (!p.isAnyCompetitorOnPromotion) return false;
                } else if (_viewFilterMode == 'THREATS_WITH_PROMO') {
                  if (!p.isThreatWithPromo) return false;
                } else if (_viewFilterMode == 'ALL_ARCHIVED') {
                  // Show complete archive
                }
              }

              // 2. Search Query
              if (_searchQuery.isNotEmpty) {
                final q = _searchQuery.toLowerCase().trim();
                final matchesName = p.name.toLowerCase().contains(q);
                final matchesBarcode = p.barcode.contains(q);
                final matchesBrand = p.brand.toLowerCase().contains(q);
                if (!matchesName && !matchesBarcode && !matchesBrand) return false;
              }

              // 3. Chain Filter (Omni Mode)
              if (!_isHeadToHeadMode && _selectedChain != 'ALL') {
                if (!p.latestPricesByChain.containsKey(_selectedChain)) return false;
              }

              // 4. Single-Chain Promotion Filter (Audio 3 requirement)
              if (!_isHeadToHeadMode && _selectedChainPromoOnly && _selectedChain != 'ALL') {
                if (!p.isChainOnPromotion(_selectedChain)) return false;
              }

              // 5. Brand Filter
              if (_selectedBrand != 'ALL') {
                if (p.brand != _selectedBrand) return false;
              }

              // 6. Global Promotions Only
              if (_promotionsOnly && !p.isCurrentlyOnPromotion) {
                return false;
              }

              // 7. Fluctuations Only
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

            _cachedFilteredProducts = filteredProducts;
            _cachedDistinctChains = distinctChains;
            _cachedDistinctBrands = distinctBrands;
            _cachedTotalPromos = totalPromotionsCount;
            _cachedTotalFluctuations = totalFluctuationsCount;
            _cachedThreats = threatsCount;
            _cachedCompetitorPromosNotAtFathalla = competitorPromosNotAtFathallaCount;
            _cachedAllCompetitorPromos = allCompetitorPromosCount;
            _cachedThreatsWithPromo = threatsWithPromoCount;
            _cachedH2hChain2Cheaper = h2hChain2Cheaper;
            _cachedH2hChain1Cheaper = h2hChain1Cheaper;
            _cachedH2hChain2Promos = h2hChain2Promos;
            _cachedH2hChain2PromoNotChain1 = h2hChain2PromoNotChain1;
          }

          final distinctChains = _cachedDistinctChains;
          final distinctBrands = _cachedDistinctBrands;
          final filteredProducts = _cachedFilteredProducts;
          final totalPromotionsCount = _cachedTotalPromos;
          final totalFluctuationsCount = _cachedTotalFluctuations;
          final threatsCount = _cachedThreats;
          final competitorPromosNotAtFathallaCount = _cachedCompetitorPromosNotAtFathalla;
          final allCompetitorPromosCount = _cachedAllCompetitorPromos;
          final threatsWithPromoCount = _cachedThreatsWithPromo;
          final h2hChain2Cheaper = _cachedH2hChain2Cheaper;
          final h2hChain1Cheaper = _cachedH2hChain1Cheaper;
          final h2hChain2Promos = _cachedH2hChain2Promos;
          final h2hChain2PromoNotChain1 = _cachedH2hChain2PromoNotChain1;

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
                      // 1. Executive M3 Header (Title, Baseline Tag, Live Pulse & Audit Actions)
                      _buildExecutiveHeader(
                        context: context,
                        cs: cs,
                        strings: strings,
                        isAr: isAr,
                        isMobile: isMobile,
                      ),
                      if (_isHealingData) ...[
                        const SizedBox(height: 14),
                        RepaintBoundary(
                          child: M3ProgressCard(
                            title: _healingStatus.isNotEmpty
                                ? _healingStatus
                                : (isAr ? 'جاري فحص وتدقيق الفواتير بالذكاء الاصطناعي...' : 'Auditing receipts with AI...'),
                            subtitle: isAr
                                ? 'يتم فحص وتصحيح اقتصاديات القطعة الواحدة وكشف تكرار الفواتير وحوكمة الأسعار...'
                                : 'Verifying unit economics and price governance across all chains...',
                            progress: _healingProgress > 0 ? _healingProgress : null,
                            currentCount: _healingCurrent,
                            totalCount: _healingTotal,
                            icon: Icons.auto_fix_high_rounded,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // 2. M3 Comparison Mode Switcher (Omni Radar vs Head-to-Head 1-on-1)
                      _buildModeAndControlsBar(
                        context: context,
                        cs: cs,
                        strings: strings,
                        isAr: isAr,
                        isMobile: isMobile,
                        distinctChains: distinctChains,
                      ),
                      const SizedBox(height: 14),

                      // 3. Interactive M3 Hero Metric Filter Group (Merges KPI numbers and filter selection into one elegant M3 row)
                      _buildHeroMetricFilterGroup(
                        context: context,
                        cs: cs,
                        strings: strings,
                        isAr: isAr,
                        isMobile: isMobile,
                        threatsCount: threatsCount,
                        competitorPromosNotAtFathallaCount: competitorPromosNotAtFathallaCount,
                        allCompetitorPromosCount: allCompetitorPromosCount,
                        threatsWithPromoCount: threatsWithPromoCount,
                        allArchivedCount: filteredProducts.length,
                        h2hChain1Cheaper: h2hChain1Cheaper,
                        h2hChain2Cheaper: h2hChain2Cheaper,
                        h2hChain2Promos: h2hChain2Promos,
                        h2hChain2PromoNotChain1: h2hChain2PromoNotChain1,
                      ),
                      const SizedBox(height: 14),

                      // 4. M3 Chain Tabs Switcher & Single-Chain Promo Filter (Omni Mode only)
                      if (!_isHeadToHeadMode) ...[
                        _buildChainFilterBar(
                          context: context,
                          cs: cs,
                          strings: strings,
                          isAr: isAr,
                          distinctChains: distinctChains,
                          allProducts: allProducts,
                        ),
                        const SizedBox(height: 14),
                      ],

                      // 5. M3 Search, Filters & View Mode Bar
                      _buildSearchAndFiltersBar(
                        context: context,
                        cs: cs,
                        strings: strings,
                        isAr: isAr,
                        distinctBrands: distinctBrands,
                        filteredProducts: filteredProducts,
                        distinctChains: distinctChains,
                        currency: currency,
                        totalPromotionsCount: totalPromotionsCount,
                        totalFluctuationsCount: totalFluctuationsCount,
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_viewFilterMode == 'THREATS_ONLY' && filteredProducts.isNotEmpty)
                          _buildThreatsRadarBanner(
                            context: context,
                            cs: cs,
                            isAr: isAr,
                            currency: currency,
                            threatItems: filteredProducts,
                            isMobile: isMobile,
                          ),
                        if (_viewFilterMode == 'COMPETITOR_PROMO_NOT_AT_FATHALLA' && filteredProducts.isNotEmpty)
                          _buildPromoOpportunitiesBanner(
                            context: context,
                            cs: cs,
                            isAr: isAr,
                            items: filteredProducts,
                            isMobile: isMobile,
                          ),
                        ChainProductsMatrixTable(
                          products: filteredProducts,
                          distinctChains: _isHeadToHeadMode
                              ? [_headToHeadChain1, _headToHeadChain2]
                              : (_selectedChain == 'ALL' ? distinctChains : [_selectedChain]),
                          isHeadToHead: _isHeadToHeadMode,
                          anchorChain: _isHeadToHeadMode ? _headToHeadChain1 : 'أسواق فتح الله',
                          comparisonChain: _isHeadToHeadMode ? _headToHeadChain2 : null,
                        ),
                      ],
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

  Widget _buildThreatsRadarBanner({
    required BuildContext context,
    required ColorScheme cs,
    required bool isAr,
    required String currency,
    required List<ChainProductItem> threatItems,
    required bool isMobile,
  }) {
    if (threatItems.isEmpty) return const SizedBox.shrink();

    // Aggregate threat counts by competitor chain
    final Map<String, int> competitorThreatCounts = {};
    for (final item in threatItems) {
      final cheapestComp = item.cheapestCompetitorName;
      if (cheapestComp.isNotEmpty) {
        competitorThreatCounts[cheapestComp] = (competitorThreatCounts[cheapestComp] ?? 0) + 1;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.error.withValues(alpha: 0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: cs.error.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.error,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.shield_outlined, color: cs.onError, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr ? 'رادار كسر الأسعار التنافسي (الأصناف الأرخص عند المنافسين)' : 'Competitor Price Undercut Radar',
                      style: GoogleFonts.cairo(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      isAr
                          ? 'تم رصد ${threatItems.length} صنف يباع لدى المنافسين بسعر أقل من أسواق فتح الله (المرجع)'
                          : 'Detected ${threatItems.length} SKUs priced below Fathalla baseline by competitors',
                      style: GoogleFonts.cairo(
                        color: cs.onErrorContainer.withValues(alpha: 0.85),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (competitorThreatCounts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: competitorThreatCounts.entries.map((entry) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cs.error.withValues(alpha: 0.25), width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.storefront_rounded, size: 13, color: cs.error),
                      const SizedBox(width: 5),
                      Text(
                        '${entry.key}: ${entry.value} ${isAr ? "صنف أرخص" : "cheaper"}',
                        style: GoogleFonts.cairo(
                          color: cs.onSurface,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPromoOpportunitiesBanner({
    required BuildContext context,
    required ColorScheme cs,
    required bool isAr,
    required List<ChainProductItem> items,
    required bool isMobile,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.tertiary.withValues(alpha: 0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: cs.tertiary.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.tertiary,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lightbulb_outline_rounded, color: cs.onTertiary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr
                      ? 'فرص استيراد وتوريد جديدة (عروض نشطة بالمنافسين غير مسجلة بفتح الله)'
                      : 'Expansion Opportunities: Competitor Promos Missing from Fathalla',
                  style: GoogleFonts.cairo(
                    color: cs.onTertiaryContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
                Text(
                  isAr
                      ? 'تم رصد ${items.length} صنف عليه تخفيضات وعروض عند المنافسين بينما لم يتم رصد سعر بيع مسجل بفتح الله. أضف هذه الأصناف لتوسيع سلة منتجاتك.'
                      : 'Identified ${items.length} promotional items at competitors not currently sold at anchor.',
                  style: GoogleFonts.cairo(
                    color: cs.onTertiaryContainer.withValues(alpha: 0.85),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 1. Executive M3 Header (Title, Badges & Action Buttons)
  Widget _buildExecutiveHeader({
    required BuildContext context,
    required ColorScheme cs,
    required AppStrings strings,
    required bool isAr,
    required bool isMobile,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
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
                      // Fathalla Baseline Tag (M3 Tonal derivation)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.account_balance_rounded, size: 14, color: cs.primary),
                            const SizedBox(width: 5),
                            Text(
                              strings.fathallaBaselineTag,
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Live AI Tracking Pill (M3 Tonal derivation)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.4),
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
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Executive M3 Button Group
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Tooltip(
                    message: isAr
                        ? 'فحص وتدقيق الفواتير الجديدة المضافة فقط لتوفير الوقت والبيانات'
                        : 'Audit new/unscanned receipts only to save time',
                    child: AnimatedPressable(
                      child: FilledButton.tonalIcon(
                        onPressed: _isHealingData
                            ? null
                            : () => _startHealingProcess(incrementalOnly: true),
                        icon: const Icon(Icons.bolt_rounded, size: 16),
                        label: Text(
                          isAr ? 'تدقيق الجديد (سريع)' : 'Audit New (Fast)',
                          style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  Tooltip(
                    message: isAr
                        ? 'إعادة فحص كافة الفواتير من البداية وتصحيح أي أخطاء بالأسعار واقتصاديات القطعة'
                        : 'Full recalculation and healing for all receipts in database',
                    child: AnimatedPressable(
                      child: OutlinedButton.icon(
                        onPressed: _isHealingData
                            ? null
                            : () => _startHealingProcess(incrementalOnly: false),
                        icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                        label: Text(
                          isAr ? 'إعادة تدقيق شامل لكافة الفواتير' : 'Full Deep Rescan',
                          style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 2. M3 Comparison Mode Switcher & Controls Bar
  Widget _buildModeAndControlsBar({
    required BuildContext context,
    required ColorScheme cs,
    required AppStrings strings,
    required bool isAr,
    required bool isMobile,
    required List<String> distinctChains,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          SegmentedButton<bool>(
            style: ButtonStyle(
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
            ),
            segments: [
              ButtonSegment<bool>(
                value: false,
                icon: const Icon(Icons.radar_rounded, size: 18),
                label: Text(
                  strings.omniRadarModeLabel,
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              ButtonSegment<bool>(
                value: true,
                icon: const Icon(Icons.compare_arrows_rounded, size: 18),
                label: Text(
                  strings.headToHeadModeLabel,
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
            selected: {_isHeadToHeadMode},
            onSelectionChanged: (val) {
              setState(() {
                _isHeadToHeadMode = val.first;
                _viewFilterMode = 'THREATS_ONLY';
              });
            },
          ),

          // Head-to-Head Chain Selectors Toolbar
          if (_isHeadToHeadMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.account_balance_rounded, size: 15, color: cs.primary),
                  const SizedBox(width: 5),
                  Text(
                    isAr ? 'الأساس:' : 'Anchor:',
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: cs.primary),
                  ),
                  const SizedBox(width: 4),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _headToHeadChain1,
                      isDense: true,
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurface),
                      items: distinctChains.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (val) {
                        if (val != null && val != _headToHeadChain2) {
                          setState(() => _headToHeadChain1 = val);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedPressable(
                    onTap: () {
                      setState(() {
                        final temp = _headToHeadChain1;
                        _headToHeadChain1 = _headToHeadChain2;
                        _headToHeadChain2 = temp;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.swap_horiz_rounded, size: 16, color: cs.primary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.storefront_rounded, size: 15, color: cs.error),
                  const SizedBox(width: 5),
                  Text(
                    isAr ? 'المنافس:' : 'Vs:',
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: cs.error),
                  ),
                  const SizedBox(width: 4),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _headToHeadChain2,
                      isDense: true,
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurface),
                      items: distinctChains.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (val) {
                        if (val != null && val != _headToHeadChain1) {
                          setState(() => _headToHeadChain2 = val);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // 3. Interactive M3 Hero Metric Filter Group
  Widget _buildHeroMetricFilterGroup({
    required BuildContext context,
    required ColorScheme cs,
    required AppStrings strings,
    required bool isAr,
    required bool isMobile,
    required int threatsCount,
    required int competitorPromosNotAtFathallaCount,
    required int allCompetitorPromosCount,
    required int threatsWithPromoCount,
    required int allArchivedCount,
    required int h2hChain1Cheaper,
    required int h2hChain2Cheaper,
    required int h2hChain2Promos,
    required int h2hChain2PromoNotChain1,
  }) {
    final List<Widget> cards;

    if (_isHeadToHeadMode) {
      cards = [
        _buildM3MetricCard(
          context: context,
          title: isAr ? '$_headToHeadChain2 أرخص' : '$_headToHeadChain2 Cheaper',
          value: '$h2hChain2Cheaper',
          subtitle: isAr ? 'كسر سعر ضد $_headToHeadChain1' : 'Cheaper than $_headToHeadChain1',
          icon: Icons.gpp_maybe_rounded,
          color: cs.error,
          containerColor: cs.errorContainer,
          isSelected: _viewFilterMode == 'THREATS_ONLY',
          onTap: () => setState(() => _viewFilterMode = 'THREATS_ONLY'),
          cs: cs,
          isAr: isAr,
        ),
        _buildM3MetricCard(
          context: context,
          title: isAr ? 'عروض غير متوفرة بـ $_headToHeadChain1' : 'Promos not in $_headToHeadChain1',
          value: '$h2hChain2PromoNotChain1',
          subtitle: isAr ? 'فرص توريد وإضافة' : 'Expansion opportunities',
          icon: Icons.lightbulb_outline_rounded,
          color: cs.tertiary,
          containerColor: cs.tertiaryContainer,
          isSelected: _viewFilterMode == 'COMPETITOR_PROMO_NOT_AT_FATHALLA',
          onTap: () => setState(() => _viewFilterMode = 'COMPETITOR_PROMO_NOT_AT_FATHALLA'),
          cs: cs,
          isAr: isAr,
        ),
        _buildM3MetricCard(
          context: context,
          title: isAr ? 'كافة عروض $_headToHeadChain2' : 'All $_headToHeadChain2 Promos',
          value: '$h2hChain2Promos',
          subtitle: isAr ? 'خصومات نشطة بالسلسلة' : 'Active promotions',
          icon: Icons.local_offer_outlined,
          color: cs.secondary,
          containerColor: cs.secondaryContainer,
          isSelected: _viewFilterMode == 'ALL_COMPETITOR_PROMOS',
          onTap: () => setState(() => _viewFilterMode = 'ALL_COMPETITOR_PROMOS'),
          cs: cs,
          isAr: isAr,
        ),
        _buildM3MetricCard(
          context: context,
          title: isAr ? '$_headToHeadChain1 أرخص' : '$_headToHeadChain1 Cheaper',
          value: '$h2hChain1Cheaper',
          subtitle: isAr ? 'تفوق سعري لصالح $_headToHeadChain1' : '$_headToHeadChain1 advantage',
          icon: Icons.verified_outlined,
          color: cs.primary,
          containerColor: cs.primaryContainer,
          isSelected: _viewFilterMode == 'THREATS_WITH_PROMO',
          onTap: () => setState(() => _viewFilterMode = 'THREATS_WITH_PROMO'),
          cs: cs,
          isAr: isAr,
        ),
        _buildM3MetricCard(
          context: context,
          title: strings.filterSegmentAllArchive,
          value: '$allArchivedCount',
          subtitle: isAr ? 'كافة الأصناف المسجلة' : 'Complete SKU catalog',
          icon: Icons.inventory_2_outlined,
          color: cs.onSurfaceVariant,
          containerColor: cs.surfaceContainerHighest,
          isSelected: _viewFilterMode == 'ALL_ARCHIVED',
          onTap: () => setState(() => _viewFilterMode = 'ALL_ARCHIVED'),
          cs: cs,
          isAr: isAr,
        ),
      ];
    } else {
      cards = [
        _buildM3MetricCard(
          context: context,
          title: strings.metricPriceThreats,
          value: '$threatsCount',
          subtitle: isAr ? 'المنافس أرخص من فتح الله' : 'Cheaper than Fathalla',
          icon: Icons.gpp_maybe_rounded,
          color: cs.error,
          containerColor: cs.errorContainer,
          isSelected: _viewFilterMode == 'THREATS_ONLY',
          onTap: () => setState(() => _viewFilterMode = 'THREATS_ONLY'),
          cs: cs,
          isAr: isAr,
        ),
        _buildM3MetricCard(
          context: context,
          title: strings.metricCompetitorPromosNotAtFathalla,
          value: '$competitorPromosNotAtFathallaCount',
          subtitle: strings.metricCompetitorPromosNotAtFathallaSubtitle,
          icon: Icons.lightbulb_outline_rounded,
          color: cs.tertiary,
          containerColor: cs.tertiaryContainer,
          isSelected: _viewFilterMode == 'COMPETITOR_PROMO_NOT_AT_FATHALLA',
          onTap: () => setState(() => _viewFilterMode = 'COMPETITOR_PROMO_NOT_AT_FATHALLA'),
          cs: cs,
          isAr: isAr,
        ),
        _buildM3MetricCard(
          context: context,
          title: strings.metricAllCompetitorPromotions,
          value: '$allCompetitorPromosCount',
          subtitle: isAr ? 'عروض نشطة بالمنافسين' : 'Active competitor promos',
          icon: Icons.local_offer_outlined,
          color: cs.secondary,
          containerColor: cs.secondaryContainer,
          isSelected: _viewFilterMode == 'ALL_COMPETITOR_PROMOS',
          onTap: () => setState(() => _viewFilterMode = 'ALL_COMPETITOR_PROMOS'),
          cs: cs,
          isAr: isAr,
        ),
        _buildM3MetricCard(
          context: context,
          title: strings.metricThreatsWithPromo,
          value: '$threatsWithPromoCount',
          subtitle: isAr ? 'عروض ترويجية كسرت سعرنا' : 'Promos undercutting us',
          icon: Icons.bolt_rounded,
          color: cs.primary,
          containerColor: cs.primaryContainer,
          isSelected: _viewFilterMode == 'THREATS_WITH_PROMO',
          onTap: () => setState(() => _viewFilterMode = 'THREATS_WITH_PROMO'),
          cs: cs,
          isAr: isAr,
        ),
        _buildM3MetricCard(
          context: context,
          title: strings.filterSegmentAllArchive,
          value: '$allArchivedCount',
          subtitle: isAr ? 'كافة الأصناف المسجلة' : 'Complete SKU catalog',
          icon: Icons.inventory_2_outlined,
          color: cs.onSurfaceVariant,
          containerColor: cs.surfaceContainerHighest,
          isSelected: _viewFilterMode == 'ALL_ARCHIVED',
          onTap: () => setState(() => _viewFilterMode = 'ALL_ARCHIVED'),
          cs: cs,
          isAr: isAr,
        ),
      ];
    }

    if (isMobile) {
      return SizedBox(
        height: 88,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: cards.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (ctx, idx) => SizedBox(width: 215, child: cards[idx]),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1100) {
          return SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cards.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (ctx, idx) => SizedBox(width: 220, child: cards[idx]),
            ),
          );
        }
        return Row(
          children: cards
              .map((card) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: card,
                    ),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildM3MetricCard({
    required BuildContext context,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color containerColor,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme cs,
    required bool isAr,
  }) {
    return AnimatedPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? containerColor.withValues(alpha: 0.65) : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : cs.outlineVariant.withValues(alpha: 0.6),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.18) : containerColor.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: isSelected ? cs.onSurface : cs.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSelected)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isAr ? 'نشط' : 'Active',
                            style: GoogleFonts.cairo(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: cs.onPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        value,
                        style: GoogleFonts.cairo(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: color,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          subtitle,
                          style: GoogleFonts.cairo(
                            fontSize: 9.5,
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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

  // 4. M3 Chain Filter Bar & Tabs
  Widget _buildChainFilterBar({
    required BuildContext context,
    required ColorScheme cs,
    required AppStrings strings,
    required bool isAr,
    required List<String> distinctChains,
    required List<ChainProductItem> allProducts,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildChainTabChip(
            label: strings.allChainsTab,
            count: allProducts.length,
            isSelected: _selectedChain == 'ALL',
            onSelected: () => setState(() {
              _selectedChain = 'ALL';
              _selectedChainPromoOnly = false;
            }),
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
          if (_selectedChain != 'ALL') ...[
            const SizedBox(width: 8),
            FilterChip(
              avatar: Icon(
                Icons.local_offer_rounded,
                size: 14,
                color: _selectedChainPromoOnly ? cs.onPrimary : cs.primary,
              ),
              label: Text(
                isAr ? 'عروض $_selectedChain فقط' : '$_selectedChain Promos Only',
                style: GoogleFonts.cairo(
                  fontSize: 11.5,
                  fontWeight: _selectedChainPromoOnly ? FontWeight.w800 : FontWeight.bold,
                  color: _selectedChainPromoOnly ? cs.onPrimary : cs.primary,
                ),
              ),
              selected: _selectedChainPromoOnly,
              selectedColor: cs.primary,
              backgroundColor: cs.primaryContainer.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              side: BorderSide(
                color: _selectedChainPromoOnly ? cs.primary : cs.primary.withValues(alpha: 0.3),
              ),
              onSelected: (val) => setState(() => _selectedChainPromoOnly = val),
            ),
          ],
        ],
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
      padding: const EdgeInsets.only(left: 6),
      child: AnimatedPressable(
        onTap: onSelected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? cs.primary : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.6),
              width: isSelected ? 1.5 : 0.8,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.cairo(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  fontSize: 12,
                  color: isSelected ? cs.onPrimary : cs.onSurface,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? cs.onPrimary.withValues(alpha: 0.25) : cs.surfaceContainerHighest,
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
        ),
      ),
    );
  }

  // 5. M3 Search, Filters & View Mode Bar
  Widget _buildSearchAndFiltersBar({
    required BuildContext context,
    required ColorScheme cs,
    required AppStrings strings,
    required bool isAr,
    required List<String> distinctBrands,
    required List<ChainProductItem> filteredProducts,
    required List<String> distinctChains,
    required String currency,
    required int totalPromotionsCount,
    required int totalFluctuationsCount,
  }) {
    return Container(
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
                style: ButtonStyle(
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
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

              // Export Excel & CSV Menu Button
              PopupMenuButton<String>(
                tooltip: isAr ? 'تصدير تقرير الأسعار (Excel / CSV)' : 'Export Price Matrix Report',
                onSelected: (choice) {
                  if (choice == 'EXCEL') {
                    _exportToExcel(filteredProducts, distinctChains, currency);
                  } else if (choice == 'CSV') {
                    _exportToCsv(filteredProducts, distinctChains, currency);
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'EXCEL',
                    child: Row(
                      children: [
                        Icon(Icons.table_chart_rounded, color: cs.primary, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          isAr ? 'تصدير تقرير إكسيل كامل (.xlsx)' : 'Export Excel Workbook (.xlsx)',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'CSV',
                    child: Row(
                      children: [
                        Icon(Icons.description_outlined, color: cs.primary, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          isAr ? 'تصدير ملف بيانات (.csv)' : 'Export CSV Data (.csv)',
                          style: GoogleFonts.cairo(fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
                child: AnimatedPressable(
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _isExporting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.file_download_outlined, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          isAr ? 'تصدير التقرير' : 'Export',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_drop_down_rounded, size: 18, color: cs.onPrimaryContainer),
                      ],
                    ),
                  ),
                ),
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
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
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
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
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
                label: Text(
                  '${strings.filterByPromotionsOnly} ($totalPromotionsCount)',
                  style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: _promotionsOnly ? FontWeight.w700 : FontWeight.normal),
                ),
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
    );
  }

  Future<void> _exportToExcel(
    List<ChainProductItem> items,
    List<String> chains,
    String currency,
  ) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    final isAr = ref.isArabic;

    try {
      final excel = xl.Excel.createExcel();
      final sheetName = _isHeadToHeadMode
          ? (isAr ? 'مقارنة $_headToHeadChain1 ضد $_headToHeadChain2' : 'Head-to-Head Comparison')
          : (isAr ? 'مصفوفة الأسعار والمنافسين' : 'Price Matrix Intelligence');
      final defaultSheet = excel.getDefaultSheet();
      if (defaultSheet != null) {
        excel.rename(defaultSheet, sheetName);
      }

      final sheet = excel[sheetName];
      sheet.isRTL = isAr;

      final List<String> headers;
      if (_isHeadToHeadMode) {
        headers = [
          isAr ? 'الباركود' : 'Barcode',
          isAr ? 'اسم المنتج' : 'Product Name',
          isAr ? 'العلامة التجارية' : 'Brand',
          isAr ? 'التصنيف' : 'Category',
          isAr ? 'سعر $_headToHeadChain1 ($currency)' : 'Price in $_headToHeadChain1 ($currency)',
          isAr ? 'سعر $_headToHeadChain2 ($currency)' : 'Price in $_headToHeadChain2 ($currency)',
          isAr ? 'السلسلة الأرخص' : 'Cheapest Chain',
          isAr ? 'فارق السعر ($currency)' : 'Price Difference ($currency)',
          isAr ? 'نسبة الفارق %' : 'Difference %',
          isAr ? 'عرض نشط بـ $_headToHeadChain1' : '$_headToHeadChain1 Promo',
          isAr ? 'عرض نشط بـ $_headToHeadChain2' : '$_headToHeadChain2 Promo',
          isAr ? 'فرصة توريد (عرض بـ $_headToHeadChain2 غير متوفر بـ $_headToHeadChain1)' : 'Expansion Opportunity',
          isAr ? 'إجمالي الرصد بالفواتير' : 'Total Scans',
        ];
      } else {
        headers = [
          isAr ? 'الباركود' : 'Barcode',
          isAr ? 'اسم المنتج' : 'Product Name',
          isAr ? 'العلامة التجارية' : 'Brand',
          isAr ? 'التصنيف' : 'Category',
          ...chains.map((c) => isAr ? 'سعر $c ($currency)' : 'Price in $c ($currency)'),
          isAr ? 'السلسلة الأرخص' : 'Cheapest Chain',
          isAr ? 'أقل سعر ($currency)' : 'Min Price ($currency)',
          isAr ? 'السلسلة الأغلى' : 'Highest Chain',
          isAr ? 'أعلى سعر ($currency)' : 'Max Price ($currency)',
          isAr ? 'فارق السعر %' : 'Price Gap %',
          isAr ? 'موقف فتح الله التنافسي' : 'Fathalla Defense Status',
          isAr ? 'المنافس الأرخص' : 'Cheapest Competitor',
          isAr ? 'فارق السعر عن فتح الله ($currency)' : 'Competitor Price Diff ($currency)',
          isAr ? 'حالة العرض / الخصم' : 'Promotion Active',
          isAr ? 'عرض منافس غير متوفر بفتح الله (فرصة توريد)' : 'Competitor Promo Not in Anchor',
          isAr ? 'إجمالي الرصد بالفواتير' : 'Total Invoice Scans',
        ];
      }

      for (var col = 0; col < headers.length; col++) {
        final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
        cell.value = xl.TextCellValue(headers[col]);
        cell.cellStyle = xl.CellStyle(
          bold: true,
          horizontalAlign: xl.HorizontalAlign.Center,
          backgroundColorHex: xl.ExcelColor.fromHexString(_isHeadToHeadMode ? '#1565C0' : '#006C50'),
          fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
        );
      }

      int rowIndex = 1;
      for (final item in items) {
        int colIndex = 0;
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(item.barcode);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(item.name);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(item.brand);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(item.category);

        if (_isHeadToHeadMode) {
          final p1 = item.latestPricesByChain[_headToHeadChain1];
          final p2 = item.latestPricesByChain[_headToHeadChain2];

          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = p1 != null ? xl.DoubleCellValue(p1) : xl.TextCellValue('-');
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = p2 != null ? xl.DoubleCellValue(p2) : xl.TextCellValue('-');

          final String cheapest;
          final double diff;
          final double pct;
          if (p1 != null && p2 != null) {
            if (p2 < (p1 - 0.05)) {
              cheapest = _headToHeadChain2;
              diff = p1 - p2;
              pct = (diff / p1) * 100;
            } else if (p1 < (p2 - 0.05)) {
              cheapest = _headToHeadChain1;
              diff = p2 - p1;
              pct = (diff / p2) * 100;
            } else {
              cheapest = isAr ? 'متطابق' : 'Equal';
              diff = 0.0;
              pct = 0.0;
            }
          } else if (p1 != null) {
            cheapest = _headToHeadChain1;
            diff = 0.0;
            pct = 0.0;
          } else if (p2 != null) {
            cheapest = _headToHeadChain2;
            diff = 0.0;
            pct = 0.0;
          } else {
            cheapest = '-';
            diff = 0.0;
            pct = 0.0;
          }

          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(cheapest);
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.DoubleCellValue(diff);
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.DoubleCellValue(double.tryParse(pct.toStringAsFixed(1)) ?? 0.0);

          final isP1Promo = item.isChainOnPromotion(_headToHeadChain1);
          final isP2Promo = item.isChainOnPromotion(_headToHeadChain2);
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(isP1Promo ? (isAr ? 'نعم' : 'Yes') : (isAr ? 'لا' : 'No'));
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(isP2Promo ? (isAr ? 'نعم' : 'Yes') : (isAr ? 'لا' : 'No'));

          final isOpp = isP2Promo && (p1 == null || !isP1Promo);
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(isOpp ? (isAr ? 'فرصة توريد' : 'Opportunity') : '-');
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.IntCellValue(item.totalScansCount);
        } else {
          for (final c in chains) {
            final p = item.latestPricesByChain[c];
            if (p != null) {
              sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.DoubleCellValue(p);
            } else {
              sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue('-');
            }
          }

          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(item.cheapestChain);
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.DoubleCellValue(item.minPrice);
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(item.mostExpensiveChain);
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.DoubleCellValue(item.maxPrice);
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.DoubleCellValue(double.tryParse(item.priceVariancePercent.toStringAsFixed(1)) ?? 0.0);

          final defenseStatus = item.isUnderpricedByCompetitors
              ? (isAr ? 'تنبيه: ${item.cheapestCompetitorName} أرخص' : 'THREAT: ${item.cheapestCompetitorName} cheaper')
              : (item.isFathallaCheapest
                  ? (isAr ? 'أفضلية: فتح الله الأرخص بالسوق' : 'BEST: Fathalla Cheapest')
                  : (isAr ? 'متطابق / عادي' : 'NORMAL'));

          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(defenseStatus);
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(item.cheapestCompetitorName.isNotEmpty ? item.cheapestCompetitorName : '-');
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.DoubleCellValue(item.competitorUnderpricedDiff);
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(item.isCurrentlyOnPromotion ? (isAr ? 'نعم' : 'Yes') : (isAr ? 'لا' : 'No'));
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(item.isCompetitorPromoNotAtFathalla ? (isAr ? 'نعم - فرصة توريد' : 'Yes - Opportunity') : '-');
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.IntCellValue(item.totalScansCount);
        }

        rowIndex++;
      }

      final fileBytes = excel.save();
      if (fileBytes != null) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = _isHeadToHeadMode
            ? 'head_to_head_${_headToHeadChain1}_vs_${_headToHeadChain2}_$timestamp.xlsx'
            : 'price_intelligence_matrix_$timestamp.xlsx';
        downloadFileBytes(
          bytes: fileBytes,
          fileName: fileName,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isAr
                    ? 'تم تحميل وتنزيل تقرير الإكسيل بنجاح ($fileName)'
                    : 'Excel report downloaded successfully ($fileName)',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تصدير ملف الإكسيل: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportToCsv(
    List<ChainProductItem> items,
    List<String> chains,
    String currency,
  ) async {
    final isAr = ref.isArabic;
    final buffer = StringBuffer();
    // Add UTF-8 BOM for Arabic text compatibility in Excel
    buffer.write('\uFEFF');

    if (_isHeadToHeadMode) {
      buffer.writeln('Barcode,Product Name,Brand,Category,Price in $_headToHeadChain1 ($currency),Price in $_headToHeadChain2 ($currency),Cheapest Chain,Price Difference ($currency),Difference %,Promo in $_headToHeadChain1,Promo in $_headToHeadChain2,Opportunity SKU,Total Scans');
      for (final item in items) {
        final p1 = item.latestPricesByChain[_headToHeadChain1];
        final p2 = item.latestPricesByChain[_headToHeadChain2];
        final String cheapest;
        final double diff;
        final double pct;
        if (p1 != null && p2 != null) {
          if (p2 < (p1 - 0.05)) {
            cheapest = _headToHeadChain2;
            diff = p1 - p2;
            pct = (diff / p1) * 100;
          } else if (p1 < (p2 - 0.05)) {
            cheapest = _headToHeadChain1;
            diff = p2 - p1;
            pct = (diff / p2) * 100;
          } else {
            cheapest = 'EQUAL';
            diff = 0.0;
            pct = 0.0;
          }
        } else if (p1 != null) {
          cheapest = _headToHeadChain1;
          diff = 0.0;
          pct = 0.0;
        } else if (p2 != null) {
          cheapest = _headToHeadChain2;
          diff = 0.0;
          pct = 0.0;
        } else {
          cheapest = '-';
          diff = 0.0;
          pct = 0.0;
        }

        final isP1Promo = item.isChainOnPromotion(_headToHeadChain1);
        final isP2Promo = item.isChainOnPromotion(_headToHeadChain2);
        final isOpp = isP2Promo && (p1 == null || !isP1Promo);

        buffer.writeln(
          '"${item.barcode}","${item.name}","${item.brand}","${item.category}",${p1 != null ? p1.toStringAsFixed(2) : ""},${p2 != null ? p2.toStringAsFixed(2) : ""},"$cheapest",${diff.toStringAsFixed(2)},${pct.toStringAsFixed(1)},${isP1Promo ? "YES" : "NO"},${isP2Promo ? "YES" : "NO"},${isOpp ? "YES" : "NO"},${item.totalScansCount}',
        );
      }
    } else {
      buffer.write('Barcode,Product Name,Brand,Category,');
      for (final c in chains) {
        buffer.write('Price in $c ($currency),');
      }
      buffer.writeln('Cheapest Store,Min Price,Highest Store,Max Price,Price Gap %,Fathalla Defense Status,Cheapest Competitor,Price Underpriced Diff,Is Promoted,Opportunity Missing From Fathalla,Total Scans');

      for (final item in items) {
        buffer.write('"${item.barcode}","${item.name}","${item.brand}","${item.category}",');
        for (final c in chains) {
          final p = item.latestPricesByChain[c];
          buffer.write('${p != null ? p.toStringAsFixed(2) : ""},');
        }
        final defenseStatus = item.isUnderpricedByCompetitors
            ? 'THREAT (${item.cheapestCompetitorName} cheaper)'
            : (item.isFathallaCheapest ? 'FATHALLA BEST PRICE' : 'NORMAL');

        buffer.writeln(
          '"${item.cheapestChain}",${item.minPrice.toStringAsFixed(2)},"${item.mostExpensiveChain}",${item.maxPrice.toStringAsFixed(2)},${item.priceVariancePercent.toStringAsFixed(1)},"$defenseStatus","${item.cheapestCompetitorName}",${item.competitorUnderpricedDiff.toStringAsFixed(2)},${item.isCurrentlyOnPromotion ? "YES" : "NO"},${item.isCompetitorPromoNotAtFathalla ? "YES" : "NO"},${item.totalScansCount}',
        );
      }
    }

    final bytes = utf8.encode(buffer.toString());
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = _isHeadToHeadMode
        ? 'head_to_head_${_headToHeadChain1}_vs_${_headToHeadChain2}_$timestamp.csv'
        : 'price_intelligence_$timestamp.csv';

    downloadFileBytes(
      bytes: bytes,
      fileName: fileName,
      mimeType: 'text/csv;charset=utf-8',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAr
                ? 'تم تحميل وتنزيل ملف CSV بنجاح ($fileName)'
                : 'CSV file downloaded successfully ($fileName)',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
