import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/services/ai_directives_service.dart';
import '../../../core/services/ai_model_config_service.dart';
import '../domain/ai_directive_model.dart';
import '../domain/ai_directives_seed_data.dart';
import 'widgets/ai_brain_copilot_studio_widget.dart';
import 'widgets/ai_model_switcher_dialog.dart';
import '../../../core/widgets/m3_adaptive_scaffold.dart';
import '../../../core/utils/responsive.dart';

class AiBrainRulesScreen extends ConsumerStatefulWidget {
  final int initialTabIndex;
  final String? initialInvoiceContext;
  final Uint8List? initialInvoiceImage;
  final String? initialInvoiceImageUrl;
  final List<String>? initialInvoiceImageUrls;

  const AiBrainRulesScreen({
    super.key,
    this.initialTabIndex = 0,
    this.initialInvoiceContext,
    this.initialInvoiceImage,
    this.initialInvoiceImageUrl,
    this.initialInvoiceImageUrls,
  });

  @override
  ConsumerState<AiBrainRulesScreen> createState() => _AiBrainRulesScreenState();
}

class _AiBrainRulesScreenState extends ConsumerState<AiBrainRulesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  AiDirectiveCategory? _selectedCategory; // null = all
  String _searchQuery = '';
  String? _selectedDirectiveId;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    // Seed directives to Firestore if collection is currently empty
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        ref.read(aiDirectivesServiceProvider).seedDirectivesIfEmpty();
      } catch (e) {
        debugPrint('Safe guard for seedDirectivesIfEmpty: $e');
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(ref);
    final isAr = ref.isArabic;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final directivesAsync = ref.watch(aiDirectivesStreamProvider);
    final totalCount = directivesAsync.value?.length ?? AiDirectivesSeedData.initialDirectives.length;
    final canPop = Navigator.of(context).canPop();

    final modelConfig = ref.watch(aiModelConfigStreamProvider).value;
    final activeModelName = modelConfig?.effectivePrimaryModel ?? 'gemini-3.7-flash';
    final activeAgentMode = modelConfig?.mode ?? AiAgentMode.standardVision;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Column(
        children: [
          // 1. Header Banner & TabBar
          _buildTopHeaderAndTabBar(context, strings, isAr, colorScheme, canPop, activeModelName, activeAgentMode),

          // 2. TabBarView
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 0: Directives Catalog
                _buildCatalogView(context, strings, isAr, colorScheme, directivesAsync, totalCount, activeModelName, activeAgentMode),

                // Tab 1: AI Brain Co-Pilot Studio
                AiBrainCoPilotStudioWidget(
                  initialInvoiceContext: widget.initialInvoiceContext,
                  initialInvoiceImage: widget.initialInvoiceImage,
                  initialInvoiceImageUrl: widget.initialInvoiceImageUrl,
                  initialInvoiceImageUrls: widget.initialInvoiceImageUrls,
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => _showAddEditDirectiveDialog(context, strings, isAr, null),
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              icon: const Icon(Icons.add_task_rounded),
              label: Text(
                strings.addNewDirectiveBtn,
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }

  Widget _buildCatalogView(
    BuildContext context,
    AppStrings strings,
    bool isAr,
    ColorScheme colorScheme,
    AsyncValue<List<AiDirectiveModel>> directivesAsync,
    int totalCount,
    String activeModelName,
    AiAgentMode activeAgentMode,
  ) {
    return M3ResponsiveBuilder(
      builder: (context, layout) {
        final isDualPane = layout.isExpanded || layout.isLarge || layout.isExtraLarge;

        return directivesAsync.when(
          data: (directives) {
            final filtered = _filterDirectives(directives, isAr);
            final effectiveSelectedId = (_selectedDirectiveId != null &&
                    filtered.any((d) => d.id == _selectedDirectiveId))
                ? _selectedDirectiveId!
                : (filtered.isNotEmpty ? filtered.first.id : null);

            final selectedDirective = effectiveSelectedId != null
                ? filtered.firstWhere((d) => d.id == effectiveSelectedId,
                    orElse: () => filtered.first)
                : null;

            if (filtered.isEmpty) {
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildKpiCardsSection(context, strings, isAr, colorScheme,
                        totalCount, activeModelName, activeAgentMode),
                  ),
                  SliverToBoxAdapter(
                    child: _buildSearchAndFilterToolbar(
                        context, strings, isAr, colorScheme),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(context, strings, isAr, colorScheme),
                  ),
                ],
              );
            }

            final listPane = CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _buildKpiCardsSection(context, strings, isAr, colorScheme,
                      totalCount, activeModelName, activeAgentMode),
                ),
                SliverToBoxAdapter(
                  child: _buildSearchAndFilterToolbar(
                      context, strings, isAr, colorScheme),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = filtered[index];
                        final isSelected = isDualPane && item.id == effectiveSelectedId;
                        return _buildDirectiveCard(
                          context,
                          item,
                          strings,
                          isAr,
                          colorScheme,
                          isSelected: isSelected,
                          isDualPane: isDualPane,
                          onSelect: () {
                            setState(() {
                              _selectedDirectiveId = item.id;
                            });
                          },
                        );
                      },
                      childCount: filtered.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            );

            if (!isDualPane) {
              return listPane;
            }

            return M3ListDetailLayout(
              listPaneWidth: 440.0,
              listPane: listPane,
              detailPane: selectedDirective != null
                  ? _buildDirectiveDetailPane(
                      context: context,
                      item: selectedDirective,
                      strings: strings,
                      isAr: isAr,
                      colorScheme: colorScheme,
                    )
                  : null,
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(
            child: Text(
              'Error loading AI Directives: $err',
              style: GoogleFonts.cairo(color: colorScheme.error),
            ),
          ),
        );
      },
    );
  }

  List<AiDirectiveModel> _filterDirectives(List<AiDirectiveModel> all, bool isAr) {
    return all.where((d) {
      if (_selectedCategory != null && d.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchTitle = d.getTitle(isAr).toLowerCase().contains(q);
        final matchCode = d.id.toLowerCase().contains(q) || d.code.toLowerCase().contains(q);
        final matchDesc = d.getDescription(isAr).toLowerCase().contains(q);
        final matchLogic = d.getLogic(isAr).toLowerCase().contains(q);
        final matchTags = d.tags.any((t) => t.toLowerCase().contains(q));
        if (!matchTitle && !matchCode && !matchDesc && !matchLogic && !matchTags) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Future<void> _handleCloudSync(BuildContext context, bool isAr) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      final count = await ref.read(aiDirectivesServiceProvider).forceSyncAllDirectives();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAr
                  ? 'تمت مزامنة كافة القواعد المعيارية ($count بنداً) مع السحابة بنجاح 🚀'
                  : 'All $count directives synced to cloud successfully',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.teal.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشلت المزامنة: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Widget _buildTopHeaderAndTabBar(
    BuildContext context,
    AppStrings strings,
    bool isAr,
    ColorScheme colorScheme,
    bool canPop,
    String activeModelName,
    AiAgentMode activeAgentMode,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top App Bar Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  if (canPop) ...[
                    IconButton.filledTonal(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: isAr ? 'رجوع' : 'Back',
                    ),
                    const SizedBox(width: 12),
                  ],
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primary,
                          const Color(0xFF6750A4),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          runSpacing: 4,
                          children: [
                            Text(
                              isAr ? 'عقل الذكاء الاصطناعي (AI Brain Center)' : 'AI Brain Intelligence Center',
                              style: GoogleFonts.cairo(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            // Dynamic Active Model Badge with click-to-switch
                            Tooltip(
                              message: isAr ? 'انقر لتبديل نموذج الذكاء الاصطناعي ونمط الوكيل' : 'Click to switch model and agent mode',
                              child: InkWell(
                                onTap: () => AiModelSwitcherDialog.show(context),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF10B981),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          activeModelName,
                                          style: GoogleFonts.cairo(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF047857),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      const Icon(Icons.tune_rounded, size: 13, color: Color(0xFF047857)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          isAr
                              ? 'استوديو حوكمة وفحص البونات بالذكاء الاصطناعي وصياغة واعتماد المعايير السحابية فورياً'
                              : 'Real-time POS verification co-pilot & instant cloud directive governance',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (MediaQuery.sizeOf(context).width < 700) ...[
                    IconButton.filledTonal(
                      onPressed: () => AiModelSwitcherDialog.show(context),
                      icon: const Icon(Icons.tune_rounded, size: 20),
                      tooltip: isAr ? 'محرك الذكاء والوكيل' : 'AI Engine & Agent',
                    ),
                    const SizedBox(width: 4),
                    IconButton.outlined(
                      onPressed: _isSyncing ? null : () => _handleCloudSync(context, isAr),
                      icon: _isSyncing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.cloud_sync_rounded, size: 20),
                      tooltip: isAr ? 'مزامنة السحابة' : 'Sync Cloud',
                    ),
                  ] else ...[
                    FilledButton.tonalIcon(
                      onPressed: () => AiModelSwitcherDialog.show(context),
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: Text(
                        isAr ? 'محرك الذكاء والوكيل' : 'AI Engine & Agent',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6750A4).withValues(alpha: 0.12),
                        foregroundColor: const Color(0xFF6750A4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Cloud Sync Action
                    OutlinedButton.icon(
                      onPressed: _isSyncing ? null : () => _handleCloudSync(context, isAr),
                      icon: _isSyncing
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.cloud_sync_rounded, size: 18),
                      label: Text(
                        isAr ? 'مزامنة السحابة' : 'Sync Cloud',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // TabBar Navigation
            TabBar(
              controller: _tabController,
              labelColor: colorScheme.primary,
              unselectedLabelColor: colorScheme.onSurfaceVariant,
              indicatorColor: colorScheme.primary,
              indicatorWeight: 3,
              labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
              unselectedLabelStyle: GoogleFonts.cairo(fontSize: 13),
              tabs: [
                Tab(
                  icon: const Icon(Icons.auto_stories_rounded, size: 20),
                  text: strings.aiBrainCatalogTab,
                ),
                Tab(
                  icon: const Icon(Icons.smart_toy_rounded, size: 20),
                  text: strings.aiBrainStudioTab,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCardsSection(
    BuildContext context,
    AppStrings strings,
    bool isAr,
    ColorScheme colorScheme,
    int totalDirectivesCount,
    String activeModelName,
    AiAgentMode activeAgentMode,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 700;
          return Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _buildKpiCard(
                title: strings.totalAiDirectivesCount,
                value: '$totalDirectivesCount ${isAr ? 'بنداً معيارياً' : 'Directives'}',
                subtitle: isAr ? 'محدثة ونشطة بكافة الحملات' : 'Enforced Globally',
                icon: Icons.checklist_rtl_rounded,
                color: const Color(0xFF6750A4),
                isWide: isWide,
              ),
              _buildKpiCard(
                title: strings.activeAiModelPrimary,
                value: activeModelName,
                subtitle: isAr ? '${activeAgentMode.labelAr} (انقر للتغيير ⚙️)' : '${activeAgentMode.labelEn} (Click to change ⚙️)',
                icon: Icons.bolt_rounded,
                color: const Color(0xFF006C50),
                isWide: isWide,
                onTap: () => AiModelSwitcherDialog.show(context),
              ),
              _buildKpiCard(
                title: strings.overallAiAccuracyScore,
                value: '99.8%',
                subtitle: isAr ? 'فحص بونات الكاشير' : 'POS Vision & Rules',
                icon: Icons.verified_rounded,
                color: const Color(0xFF00639B),
                isWide: isWide,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isWide,
    VoidCallback? onTap,
  }) {
    final cardContent = Container(
      width: isWide ? 220 : double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: GoogleFonts.cairo(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: cardContent,
        ),
      );
    }
    return cardContent;
  }

  Widget _buildSearchAndFilterToolbar(BuildContext context, AppStrings strings, bool isAr, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Input
          TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val.trim()),
            decoration: InputDecoration(
              hintText: strings.searchDirectivesPlaceholder,
              hintStyle: GoogleFonts.cairo(fontSize: 13, color: colorScheme.onSurfaceVariant),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: colorScheme.surfaceContainerLow,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Category Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildCategoryFilterChip(
                  label: strings.filterAllDirectives,
                  icon: Icons.all_inclusive_rounded,
                  isSelected: _selectedCategory == null,
                  onSelected: () => setState(() => _selectedCategory = null),
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                for (final cat in AiDirectiveCategory.values) ...[
                  _buildCategoryFilterChip(
                    label: cat.getLabel(isAr),
                    icon: cat.icon,
                    isSelected: _selectedCategory == cat,
                    onSelected: () => setState(() => _selectedCategory = cat),
                    color: cat.color,
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onSelected,
    required Color color,
  }) {
    return FilterChip(
      selected: isSelected,
      onSelected: (_) => onSelected(),
      avatar: Icon(icon, size: 16, color: isSelected ? Colors.white : color),
      label: Text(
        label,
        style: GoogleFonts.cairo(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
        ),
      ),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      selectedColor: color,
      checkmarkColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? color : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _buildDirectiveCard(
    BuildContext context,
    AiDirectiveModel item,
    AppStrings strings,
    bool isAr,
    ColorScheme colorScheme, {
    bool isSelected = false,
    bool isDualPane = false,
    VoidCallback? onSelect,
  }) {
    final catColor = item.category.color;

    return Card(
      elevation: isSelected ? 2 : 0,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: isSelected ? 2 : 1,
        ),
      ),
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.3)
          : colorScheme.surfaceContainerLowest,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (onSelect != null) onSelect();
          if (!isDualPane) {
            _showDirectiveDetailsDialog(context, item, strings, isAr, colorScheme);
          }
        },
        child: Padding(
          padding: EdgeInsets.all(isDualPane ? 14 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Badges Row
              Row(
                children: [
                  // Directive ID Badge (e.g. [AIR-01])
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: catColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      item.id,
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: catColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Category Badge (Flexible to prevent any overflow)
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(item.category.icon, size: 11, color: catColor),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              item.category.getLabel(isAr),
                              style: GoogleFonts.cairo(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Active Status Chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.isGloballyActive
                          ? const Color(0xFFE8F5E9)
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: item.isGloballyActive
                            ? const Color(0xFF2E7D32).withValues(alpha: 0.3)
                            : colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.isGloballyActive ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
                          size: 11,
                          color: item.isGloballyActive ? const Color(0xFF2E7D32) : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          item.isGloballyActive ? (isAr ? 'نشط' : 'Active') : (isAr ? 'معطل' : 'Off'),
                          style: GoogleFonts.cairo(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: item.isGloballyActive ? const Color(0xFF1B5E20) : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Title
              Text(
                item.getTitle(isAr),
                style: GoogleFonts.cairo(
                  fontSize: isDualPane ? 13.5 : 15,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                  color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                ),
                maxLines: isDualPane ? 2 : 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),

              // Description
              Text(
                item.getDescription(isAr),
                style: GoogleFonts.cairo(
                  fontSize: 11.5,
                  height: 1.4,
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: isDualPane ? 2 : 4,
                overflow: TextOverflow.ellipsis,
              ),

              if (!isDualPane) ...[
                const SizedBox(height: 12),
                // Real-world POS Example Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lightbulb_rounded, size: 15, color: Colors.amber.shade700),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              strings.directiveExampleHeader,
                              style: GoogleFonts.cairo(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '📥 ${isAr ? 'مدخلات البون:' : 'Input:'} ${item.exampleInput}',
                        style: GoogleFonts.cairo(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '🎁 ${isAr ? 'النتيجة والاستحقاق:' : 'Result:'} ${item.exampleOutput}',
                        style: GoogleFonts.cairo(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: catColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 10),

              // Footer info & action buttons
              Row(
                children: [
                  Icon(Icons.code_rounded, size: 13, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      item.code,
                      style: GoogleFonts.firaCode(
                        fontSize: 10,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!isDualPane) ...[
                    TextButton.icon(
                      onPressed: () => _showDirectiveDetailsDialog(context, item, strings, isAr, colorScheme),
                      icon: const Icon(Icons.menu_book_rounded, size: 15),
                      label: Text(
                        isAr ? 'عرض المنطق' : 'View Logic',
                        style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      tooltip: isAr ? 'تعديل البند' : 'Edit Directive',
                      icon: const Icon(Icons.edit_outlined, size: 17),
                      onPressed: () => _showAddEditDirectiveDialog(context, strings, isAr, item),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Dedicated Directive Detail Pane Builder (M3 ListDetailLayout Inspector)
  // ---------------------------------------------------------------------------
  Widget _buildDirectiveDetailPane({
    required BuildContext context,
    required AiDirectiveModel item,
    required AppStrings strings,
    required bool isAr,
    required ColorScheme colorScheme,
  }) {
    final catColor = item.category.color;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(item.category.icon, color: catColor, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: catColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: catColor.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  item.id,
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: catColor,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  item.category.getLabel(isAr),
                                  style: GoogleFonts.cairo(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: item.isGloballyActive
                                      ? const Color(0xFFE8F5E9)
                                      : colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: item.isGloballyActive
                                        ? const Color(0xFF2E7D32).withValues(alpha: 0.3)
                                        : colorScheme.outlineVariant,
                                  ),
                                ),
                                child: Text(
                                  item.isGloballyActive
                                      ? (isAr ? 'نشط ومعتمد سحابياً' : 'Active & Enforced')
                                      : (isAr ? 'معطل مؤقتاً' : 'Inactive'),
                                  style: GoogleFonts.cairo(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: item.isGloballyActive
                                        ? const Color(0xFF2E7D32)
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            item.getTitle(isAr),
                            style: GoogleFonts.cairo(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.code,
                            style: GoogleFonts.firaCode(
                              fontSize: 12,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  item.getDescription(isAr),
                  style: GoogleFonts.cairo(
                    fontSize: 13,
                    height: 1.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Logic Card
          Text(
            strings.directiveLogicHeader,
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Text(
              item.getLogic(isAr),
              style: GoogleFonts.cairo(
                fontSize: 13,
                height: 1.7,
                color: colorScheme.onSurface,
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Example Input / Output
          Text(
            strings.directiveExampleHeader,
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.amber.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('📥 ', style: TextStyle(fontSize: 16)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr ? 'بيانات البون المدخلة / POS Input:' : 'POS Input:',
                            style: GoogleFonts.cairo(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.exampleInput,
                            style: GoogleFonts.cairo(fontSize: 12.5, color: colorScheme.onSurface),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🎁 ', style: TextStyle(fontSize: 16)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr ? 'القرار الذكي الناتج / AI Evaluation Output:' : 'AI Evaluation Output:',
                            style: GoogleFonts.cairo(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: item.category.color,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.exampleOutput,
                            style: GoogleFonts.cairo(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: item.category.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (item.tags.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              isAr ? 'الوسوم البرمجية للنظام' : 'System Tags',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: item.tags.map((tag) {
                return Chip(
                  label: Text('#$tag', style: GoogleFonts.cairo(fontSize: 11)),
                  backgroundColor: colorScheme.surfaceContainerHigh,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 24),

          // Action Toolbar
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () {
                  _tabController.animateTo(1);
                },
                icon: const Icon(Icons.science_rounded, size: 18),
                label: Text(
                  isAr ? 'تجربة في استوديو الذكاء الاصطناعي' : 'Test in Co-Pilot Studio',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _showAddEditDirectiveDialog(context, strings, isAr, item),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(
                  isAr ? 'تعديل البند' : 'Edit Directive',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppStrings strings, bool isAr, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.psychology_alt_outlined, size: 64, color: colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            isAr ? 'لم يتم العثور على قواعد مطابقة للبحث' : 'No matching AI Directives found',
            style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            isAr ? 'جرب البحث بكلمات أخرى أو اختر تصنيفاً مختلفاً' : 'Try searching with different terms',
            style: GoogleFonts.cairo(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  void _showDirectiveDetailsDialog(
    BuildContext context,
    AiDirectiveModel item,
    AppStrings strings,
    bool isAr,
    ColorScheme colorScheme,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: item.category.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(item.category.icon, color: item.category.color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.id}: ${item.getTitle(isAr)}',
                      style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      item.code,
                      style: GoogleFonts.firaCode(fontSize: 11, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 600,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.directiveLogicHeader,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.primary),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      item.getLogic(isAr),
                      style: GoogleFonts.cairo(fontSize: 12, height: 1.6, color: colorScheme.onSurface),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    strings.directiveExampleHeader,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber.shade800),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('📥 ${isAr ? 'المدخلات:' : 'Input:'} ${item.exampleInput}',
                            style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurface)),
                        const SizedBox(height: 6),
                        Text('🎁 ${isAr ? 'المخرجات:' : 'Output:'} ${item.exampleOutput}',
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: item.category.color)),
                      ],
                    ),
                  ),
                  if (item.tags.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: item.tags.map((tag) {
                        return Chip(
                          label: Text('#$tag', style: GoogleFonts.cairo(fontSize: 11)),
                          backgroundColor: colorScheme.surfaceContainerHigh,
                          padding: EdgeInsets.zero,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(isAr ? 'إغلاق' : 'Close', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showAddEditDirectiveDialog(
    BuildContext context,
    AppStrings strings,
    bool isAr,
    AiDirectiveModel? existing,
  ) {
    final idController = TextEditingController(text: existing?.id ?? 'AIR-${DateTime.now().millisecond}');
    final codeController = TextEditingController(text: existing?.code ?? '');
    final titleArController = TextEditingController(text: existing?.titleAr ?? '');
    final titleEnController = TextEditingController(text: existing?.titleEn ?? '');
    final descArController = TextEditingController(text: existing?.descriptionAr ?? '');
    final descEnController = TextEditingController(text: existing?.descriptionEn ?? '');
    final logicArController = TextEditingController(text: existing?.logicAr ?? '');
    final logicEnController = TextEditingController(text: existing?.logicEn ?? '');
    final inExampleController = TextEditingController(text: existing?.exampleInput ?? '');
    final outExampleController = TextEditingController(text: existing?.exampleOutput ?? '');
    AiDirectiveCategory category = existing?.category ?? AiDirectiveCategory.promotionalRules;
    bool isActive = existing?.isGloballyActive ?? true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final cs = Theme.of(dialogContext).colorScheme;
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                existing == null ? strings.addNewDirectiveBtn : (isAr ? 'تعديل البند الذكي' : 'Edit Directive'),
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 17),
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 600,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: idController,
                              decoration: InputDecoration(
                                labelText: isAr ? 'رقم البند (ID)' : 'Directive ID',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<AiDirectiveCategory>(
                              initialValue: category,
                              decoration: InputDecoration(
                                labelText: isAr ? 'التصنيف' : 'Category',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              items: AiDirectiveCategory.values.map((c) {
                                return DropdownMenuItem(
                                  value: c,
                                  child: Text(c.getLabel(isAr), style: GoogleFonts.cairo(fontSize: 12)),
                                );
                              }).toList(),
                              onChanged: (v) {
                                if (v != null) setDialogState(() => category = v);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: codeController,
                        decoration: InputDecoration(
                          labelText: isAr ? 'الكود البرمجي (CODE)' : 'System Code Name',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: titleArController,
                        decoration: InputDecoration(
                          labelText: isAr ? 'عنوان البند (بالعربية)' : 'Title (Arabic)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: titleEnController,
                        decoration: InputDecoration(
                          labelText: isAr ? 'عنوان البند (بالإنجليزية)' : 'Title (English)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descArController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: isAr ? 'الشرح والهدف (بالعربية)' : 'Description (Arabic)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: logicArController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: isAr ? 'المنطق البرمجي والخوارزمية' : 'Algorithm & Logic',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: inExampleController,
                        decoration: InputDecoration(
                          labelText: isAr ? 'مثال المدخلات من الفاتورة' : 'Sample Input',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: outExampleController,
                        decoration: InputDecoration(
                          labelText: isAr ? 'مثال النتيجة والمخرجات' : 'Sample Output',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        value: isActive,
                        onChanged: (v) => setDialogState(() => isActive = v),
                        title: Text(strings.directiveStatusActive, style: GoogleFonts.cairo(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(isAr ? 'إلغاء' : 'Cancel', style: GoogleFonts.cairo()),
                ),
                FilledButton(
                  onPressed: () async {
                    final newModel = AiDirectiveModel(
                      id: idController.text.trim(),
                      code: codeController.text.trim().toUpperCase(),
                      titleAr: titleArController.text.trim(),
                      titleEn: titleEnController.text.trim().isNotEmpty ? titleEnController.text.trim() : titleArController.text.trim(),
                      category: category,
                      descriptionAr: descArController.text.trim(),
                      descriptionEn: descEnController.text.trim().isNotEmpty ? descEnController.text.trim() : descArController.text.trim(),
                      logicAr: logicArController.text.trim(),
                      logicEn: logicEnController.text.trim().isNotEmpty ? logicEnController.text.trim() : logicArController.text.trim(),
                      exampleInput: inExampleController.text.trim(),
                      exampleOutput: outExampleController.text.trim(),
                      isGloballyActive: isActive,
                      orderIndex: existing?.orderIndex ?? 99,
                      lastUpdated: DateTime.now().toIso8601String().substring(0, 10),
                    );

                    Navigator.of(ctx).pop();
                    try {
                      if (existing == null) {
                        await ref.read(aiDirectivesServiceProvider).addDirective(newModel);
                      } else {
                        await ref.read(aiDirectivesServiceProvider).updateDirective(newModel);
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(strings.directiveSavedSuccess),
                            backgroundColor: Colors.teal.shade700,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: cs.error,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    }
                  },
                  child: Text(isAr ? 'حفظ وتوثيق' : 'Save Directive', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
