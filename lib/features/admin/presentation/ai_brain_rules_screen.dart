import 'package:al_mraay/core/constants/ai_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/m3_list_tile.dart';

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
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

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
    final allDirectives =
        directivesAsync.value ?? AiDirectivesSeedData.initialDirectives;
    final totalCount = allDirectives.length;
    final activeCount =
        allDirectives.where((d) => d.isGloballyActive).length;
    final canPop = Navigator.of(context).canPop();

    final modelConfig = ref.watch(aiModelConfigStreamProvider).value;
    final activeModelName =
        modelConfig?.effectivePrimaryModel ?? AiModels.defaultPrimary;
    final activeAgentMode = modelConfig?.mode ?? AiAgentMode.standardVision;

    return M3ResponsiveBuilder(
      builder: (context, layout) {
        final isDesktop = layout.isDesktop;

        return Scaffold(
          backgroundColor: colorScheme.surface,
          body: Column(
            children: [
              // 1. Header Banner & TabBar (Bounded by M3ContentBoundary on ultra-wide)
              _buildTopHeaderAndTabBar(
                context,
                strings,
                isAr,
                colorScheme,
                canPop,
                activeModelName,
                activeAgentMode,
                totalCount,
                layout,
              ),

              // 2. TabBarView
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 0: Directives Catalog
                    _buildCatalogView(
                      context,
                      strings,
                      isAr,
                      colorScheme,
                      directivesAsync,
                      totalCount,
                      activeCount,
                      activeModelName,
                      activeAgentMode,
                    ),

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
          // Show FAB on Compact/Medium screens; on Desktop it is integrated in the top header & list pane header
          floatingActionButton: (_tabController.index == 0 && !isDesktop)
              ? FloatingActionButton.extended(
                  onPressed: () =>
                      _showAddEditDirectiveDialog(context, strings, isAr, null),
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
      },
    );
  }

  Widget _buildCatalogView(
    BuildContext context,
    AppStrings strings,
    bool isAr,
    ColorScheme colorScheme,
    AsyncValue<List<AiDirectiveModel>> directivesAsync,
    int totalCount,
    int activeCount,
    String activeModelName,
    AiAgentMode activeAgentMode,
  ) {
    return M3ResponsiveBuilder(
      builder: (context, layout) {
        final isDualPane =
            layout.isExpanded || layout.isLarge || layout.isExtraLarge;

        return directivesAsync.when(
          data: (directives) {
            final filtered = _filterDirectives(directives, isAr);
            final effectiveSelectedId = (_selectedDirectiveId != null &&
                    filtered.any((d) => d.id == _selectedDirectiveId))
                ? _selectedDirectiveId!
                : (filtered.isNotEmpty ? filtered.first.id : null);

            final selectedDirective = effectiveSelectedId != null
                ? filtered.firstWhere(
                    (d) => d.id == effectiveSelectedId,
                    orElse: () => filtered.first,
                  )
                : null;

            // ── Compact & Medium (< 840dp): Single-Pane Scrollable Feed ──
            if (!isDualPane) {
              return M3ContentBoundary(
                maxWidth: 1440.0,
                padding: EdgeInsets.symmetric(horizontal: layout.margin),
                child: CustomScrollView(
                  slivers: [
                    const SliverToBoxAdapter(
                      child: SizedBox(height: M3Spacing.sm),
                    ),
                    SliverToBoxAdapter(
                      child: _buildKpiCardsSection(
                        context,
                        strings,
                        isAr,
                        colorScheme,
                        totalCount,
                        activeCount,
                        activeModelName,
                        activeAgentMode,
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: M3Spacing.sm),
                    ),
                    SliverToBoxAdapter(
                      child: _buildSearchAndFilterToolbar(
                        context,
                        strings,
                        isAr,
                        colorScheme,
                        filteredCount: filtered.length,
                        totalCount: directives.length,
                        isCompactHeader: false,
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: M3Spacing.sm),
                    ),
                    if (filtered.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyState(
                            context, strings, isAr, colorScheme),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = filtered[index];
                            return _buildDirectiveCard(
                              context,
                              item,
                              strings,
                              isAr,
                              colorScheme,
                              isSelected: false,
                              isDualPane: false,
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
                    const SliverToBoxAdapter(
                      child: SizedBox(height: M3Spacing.xxxl + M3Spacing.md),
                    ),
                  ],
                ),
              );
            }

            // ── Expanded, Large & Extra-Large (≥ 840dp): M3 Canonical Master-Detail Workspace ──
            final double listPaneWidth =
                (layout.isLarge || layout.isExtraLarge) ? 420.0 : 360.0;

            return M3ContentBoundary(
              maxWidth: 1440.0,
              padding: EdgeInsets.symmetric(
                horizontal: layout.margin,
                vertical: M3Spacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Full-Width 4-Card Responsive KPI Row across the top
                  _buildKpiCardsSection(
                    context,
                    strings,
                    isAr,
                    colorScheme,
                    totalCount,
                    activeCount,
                    activeModelName,
                    activeAgentMode,
                  ),
                  const SizedBox(height: M3Spacing.sm),

                  // 2. Canonical Split-Pane Workspace (Master List + Detail Inspector)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // START PANE (Right in Arabic RTL, Left in English/Hindi LTR): Master List Container
                        SizedBox(
                          width: listPaneWidth,
                          child: Container(
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: colorScheme.outlineVariant
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Pinned Search & Filter Header inside Master Pane
                                Container(
                                  padding: const EdgeInsets.all(M3Spacing.sm),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerLowest,
                                    border: Border(
                                      bottom: BorderSide(
                                        color: colorScheme.outlineVariant
                                            .withValues(alpha: 0.4),
                                      ),
                                    ),
                                  ),
                                  child: _buildSearchAndFilterToolbar(
                                    context,
                                    strings,
                                    isAr,
                                    colorScheme,
                                    filteredCount: filtered.length,
                                    totalCount: directives.length,
                                    isCompactHeader: true,
                                  ),
                                ),

                                // Scrollable Directives List
                                Expanded(
                                  child: filtered.isEmpty
                                      ? _buildEmptyState(
                                          context, strings, isAr, colorScheme)
                                      : ListView.builder(
                                          padding: const EdgeInsets.all(
                                              M3Spacing.sm),
                                          itemCount: filtered.length,
                                          itemBuilder: (context, index) {
                                            final item = filtered[index];
                                            final isSelected =
                                                item.id == effectiveSelectedId;
                                            return _buildDirectiveCard(
                                              context,
                                              item,
                                              strings,
                                              isAr,
                                              colorScheme,
                                              isSelected: isSelected,
                                              isDualPane: true,
                                              onSelect: () {
                                                setState(() {
                                                  _selectedDirectiveId =
                                                      item.id;
                                                });
                                              },
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(width: M3Spacing.md),

                        // END PANE (Left in Arabic RTL, Right in English/Hindi LTR): Detail Inspector Container
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: colorScheme.outlineVariant
                                    .withValues(alpha: 0.5),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.shadow
                                      .withValues(alpha: 0.03),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: selectedDirective != null
                                ? _buildDirectiveDetailPane(
                                    context: context,
                                    item: selectedDirective,
                                    strings: strings,
                                    isAr: isAr,
                                    colorScheme: colorScheme,
                                  )
                                : _buildEmptyState(
                                    context, strings, isAr, colorScheme),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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

  List<AiDirectiveModel> _filterDirectives(
      List<AiDirectiveModel> all, bool isAr) {
    return all.where((d) {
      if (_selectedCategory != null && d.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchTitle = d.getTitle(isAr).toLowerCase().contains(q);
        final matchCode =
            d.id.toLowerCase().contains(q) || d.code.toLowerCase().contains(q);
        final matchDesc = d.getDescription(isAr).toLowerCase().contains(q);
        final matchLogic = d.getLogic(isAr).toLowerCase().contains(q);
        final matchTags = d.tags.any((t) => t.toLowerCase().contains(q));
        if (!matchTitle &&
            !matchCode &&
            !matchDesc &&
            !matchLogic &&
            !matchTags) {
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
      final count = await ref
          .read(aiDirectivesServiceProvider)
          .forceSyncAllDirectives();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAr
                  ? 'تمت مزامنة كافة القواعد المعيارية ($count بنداً) مع السحابة بنجاح 🚀'
                  : 'All $count directives synced to cloud successfully',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            backgroundColor: colorScheme.onTertiaryFixedVariant,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشلت المزامنة: $e'),
            backgroundColor: colorScheme.onErrorContainer,
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
    int totalCount,
    M3LayoutMetrics layout,
  ) {
    final isCompactOrMedium = layout.isCompact || layout.isMedium;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: M3ContentBoundary(
          maxWidth: 1440.0,
          padding: EdgeInsets.symmetric(horizontal: layout.margin),
          child: Column(
            children: [
              // Top App Bar Row
              Padding(
                padding: const EdgeInsets.symmetric(vertical: M3Spacing.xs + M3Spacing.xxs),
                child: Row(
                  children: [
                    if (canPop) ...[
                      M3TouchTargetBoundary(
                        child: IconButton.filledTonal(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                          tooltip: isAr ? 'رجوع' : 'Back',
                        ),
                      ),
                      const SizedBox(width: M3Spacing.sm),
                    ],
                    Container(
                      padding: const EdgeInsets.all(M3Spacing.xs + M3Spacing.xxs),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.primary,
                            colorScheme.primary,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.psychology_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: M3Spacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: M3Spacing.xs,
                            runSpacing: M3Spacing.xxs,
                            children: [
                              Text(
                                isAr
                                    ? 'عقل الذكاء الاصطناعي (AI Brain Center)'
                                    : 'AI Brain Intelligence Center',
                                style: GoogleFonts.cairo(
                                  fontSize: isCompactOrMedium ? 16 : 18,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              // Dynamic Active Model Badge with click-to-switch
                              Tooltip(
                                message: isAr
                                    ? 'انقر لتبديل نموذج الذكاء الاصطناعي ونمط الوكيل'
                                    : 'Click to switch model and agent mode',
                                child: InkWell(
                                  onTap: () =>
                                      AiModelSwitcherDialog.show(context),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: M3Spacing.xs,
                                      vertical: M3Spacing.xxs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorScheme.tertiary
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: colorScheme.tertiary
                                            .withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: colorScheme.tertiary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: M3Spacing.xs),
                                        Flexible(
                                          child: Text(
                                            activeModelName,
                                            style: GoogleFonts.cairo(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: colorScheme
                                                  .onTertiaryFixedVariant,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: M3Spacing.xxs),
                                        Icon(
                                          Icons.tune_rounded,
                                          size: 13,
                                          color: colorScheme
                                              .onTertiaryFixedVariant,
                                        ),
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
                    const SizedBox(width: M3Spacing.xs),
                    if (isCompactOrMedium) ...[
                      M3TouchTargetBoundary(
                        child: IconButton.filledTonal(
                          onPressed: () => AiModelSwitcherDialog.show(context),
                          icon: const Icon(Icons.tune_rounded, size: 20),
                          tooltip: isAr
                              ? 'محرك الذكاء والوكيل'
                              : 'AI Engine & Agent',
                        ),
                      ),
                      const SizedBox(width: M3Spacing.xxs),
                      M3TouchTargetBoundary(
                        child: IconButton.outlined(
                          onPressed: _isSyncing
                              ? null
                              : () => _handleCloudSync(context, isAr),
                          icon: _isSyncing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.cloud_sync_rounded, size: 20),
                          tooltip: isAr ? 'مزامنة السحابة' : 'Sync Cloud',
                        ),
                      ),
                    ] else ...[
                      FilledButton.icon(
                        onPressed: () => _showAddEditDirectiveDialog(
                            context, strings, isAr, null),
                        icon: const Icon(Icons.add_task_rounded, size: 18),
                        label: Text(
                          strings.addNewDirectiveBtn,
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: M3Spacing.sm,
                            vertical: M3Spacing.xs,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(width: M3Spacing.xs),
                      FilledButton.tonalIcon(
                        onPressed: () => AiModelSwitcherDialog.show(context),
                        icon: const Icon(Icons.tune_rounded, size: 18),
                        label: Text(
                          isAr ? 'محرك الذكاء والوكيل' : 'AI Engine & Agent',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              colorScheme.primary.withValues(alpha: 0.12),
                          foregroundColor: colorScheme.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: M3Spacing.sm,
                            vertical: M3Spacing.xs,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(width: M3Spacing.xs),
                      // Cloud Sync Action
                      OutlinedButton.icon(
                        onPressed: _isSyncing
                            ? null
                            : () => _handleCloudSync(context, isAr),
                        icon: _isSyncing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_sync_rounded, size: 18),
                        label: Text(
                          isAr ? 'مزامنة السحابة' : 'Sync Cloud',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: M3Spacing.sm,
                            vertical: M3Spacing.xs,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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
                dividerColor: Colors.transparent,
                labelStyle: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                unselectedLabelStyle: GoogleFonts.cairo(fontSize: 13),
                tabs: [
                  Tab(
                    height: 48,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_stories_rounded, size: 18),
                        const SizedBox(width: M3Spacing.xs),
                        Flexible(
                          child: Text(
                            strings.aiBrainCatalogTab,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: M3Spacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: M3Spacing.xs,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$totalCount',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tab(
                    height: 48,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.smart_toy_rounded, size: 18),
                        const SizedBox(width: M3Spacing.xs),
                        Flexible(
                          child: Text(
                            strings.aiBrainStudioTab,
                            overflow: TextOverflow.ellipsis,
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
      ),
    );
  }

  Widget _buildKpiCardsSection(
    BuildContext context,
    AppStrings strings,
    bool isAr,
    ColorScheme colorScheme,
    int totalDirectivesCount,
    int activeDirectivesCount,
    String activeModelName,
    AiAgentMode activeAgentMode,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = M3Layout.fromConstraints(constraints);
        final double cardWidth;

        if (layout.isDesktop) {
          // 4 cards across on Expanded/Large/ExtraLarge (12 columns)
          cardWidth = (constraints.maxWidth - (3 * M3Spacing.sm)) / 4;
        } else if (layout.isMedium || constraints.maxWidth >= 520) {
          // 2 cards across on Medium (8 columns)
          cardWidth = (constraints.maxWidth - M3Spacing.sm) / 2;
        } else {
          // 1 card across on Compact (4 columns)
          cardWidth = constraints.maxWidth;
        }

        final selectedCategoryText = _selectedCategory != null
            ? _selectedCategory!.getLabel(isAr)
            : (isAr
                ? '${AiDirectiveCategory.values.length} قطاعات تشغيلية'
                : '${AiDirectiveCategory.values.length} Core Domains');

        return Wrap(
          spacing: M3Spacing.sm,
          runSpacing: M3Spacing.sm,
          children: [
            _buildKpiCard(
              width: cardWidth,
              title: strings.totalAiDirectivesCount,
              value:
                  '$totalDirectivesCount ${isAr ? 'بنداً معيارياً' : 'Directives'}',
              subtitle: isAr
                  ? '$activeDirectivesCount بند نشط بكافة الحملات'
                  : '$activeDirectivesCount Active Globally',
              icon: Icons.checklist_rtl_rounded,
              color: colorScheme.primary,
            ),
            _buildKpiCard(
              width: cardWidth,
              title: strings.activeAiModelPrimary,
              value: activeModelName,
              subtitle: isAr
                  ? '${activeAgentMode.labelAr} (انقر للتغيير ⚙️)'
                  : '${activeAgentMode.labelEn} (Click to change ⚙️)',
              icon: Icons.bolt_rounded,
              color: colorScheme.tertiary,
              onTap: () => AiModelSwitcherDialog.show(context),
            ),
            _buildKpiCard(
              width: cardWidth,
              title: strings.overallAiAccuracyScore,
              value: '99.8%',
              subtitle: isAr
                  ? 'فحص بونات الكاشير ومنع الهلوسة'
                  : 'POS Vision & Zero-Hallucination',
              icon: Icons.verified_rounded,
              color: colorScheme.primary,
            ),
            _buildKpiCard(
              width: cardWidth,
              title: isAr
                  ? 'نطاق التغطية والتصنيف'
                  : 'Governance Categories',
              value: selectedCategoryText,
              subtitle: _selectedCategory != null
                  ? (isAr ? 'انقر لإلغاء الفلتر وعرض الكل' : 'Tap to reset filter')
                  : (isAr ? 'شاملة العروض والأسعار والفروع' : 'Promos, Pricing & Branches'),
              icon: _selectedCategory?.icon ?? Icons.category_rounded,
              color: _selectedCategory?.color ?? colorScheme.secondary,
              onTap: _selectedCategory != null
                  ? () => setState(() => _selectedCategory = null)
                  : null,
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpiCard({
    required double width,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    final cardContent = Container(
      width: width,
      padding: const EdgeInsets.symmetric(
        horizontal: M3Spacing.sm,
        vertical: M3Spacing.xs + M3Spacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: M3Spacing.sm),
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
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
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

  Widget _buildSearchAndFilterToolbar(
    BuildContext context,
    AppStrings strings,
    bool isAr,
    ColorScheme colorScheme, {
    required int filteredCount,
    required int totalCount,
    required bool isCompactHeader,
  }) {
    final hasActiveFilter =
        _selectedCategory != null || _searchQuery.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Search Input
        TextField(
          controller: _searchController,
          onChanged: (val) => setState(() => _searchQuery = val.trim()),
          style: GoogleFonts.cairo(fontSize: 13),
          decoration: InputDecoration(
            hintText: strings.searchDirectivesPlaceholder,
            hintStyle: GoogleFonts.cairo(
              fontSize: 12.5,
              color: colorScheme.onSurfaceVariant,
            ),
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? M3TouchTargetBoundary(
                    child: IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      tooltip: isAr ? 'مسح البحث' : 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
                  )
                : null,
            filled: true,
            fillColor: isCompactHeader
                ? colorScheme.surfaceContainerLow
                : colorScheme.surfaceContainerLowest,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: M3Spacing.sm,
              vertical: M3Spacing.xs + M3Spacing.xxs,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: M3Spacing.xs + M3Spacing.xxs),

        // Category Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildCategoryFilterChip(
                label: '${strings.filterAllDirectives} ($totalCount)',
                icon: Icons.all_inclusive_rounded,
                isSelected: _selectedCategory == null,
                onSelected: () => setState(() => _selectedCategory = null),
                color: colorScheme.primary,
              ),
              const SizedBox(width: M3Spacing.xs),
              for (final cat in AiDirectiveCategory.values) ...[
                _buildCategoryFilterChip(
                  label: cat.getLabel(isAr),
                  icon: cat.icon,
                  isSelected: _selectedCategory == cat,
                  onSelected: () => setState(() => _selectedCategory = cat),
                  color: cat.color,
                ),
                const SizedBox(width: M3Spacing.xs),
              ],
            ],
          ),
        ),

        // Results Subheader counter
        const SizedBox(height: M3Spacing.xs),
        Row(
          children: [
            Icon(
              Icons.filter_list_rounded,
              size: 14,
              color: colorScheme.primary,
            ),
            const SizedBox(width: M3Spacing.xxs),
            Expanded(
              child: Text(
                isAr
                    ? 'عرض $filteredCount من أصل $totalCount بنداً معيارياً'
                    : 'Showing $filteredCount of $totalCount directives',
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (hasActiveFilter)
              TextButton.icon(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                    _selectedCategory = null;
                  });
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: M3Spacing.xs),
                ),
                icon: const Icon(Icons.restart_alt_rounded, size: 14),
                label: Text(
                  isAr ? 'إعادة ضبط' : 'Reset',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ],
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
      avatar: Icon(icon, size: 15, color: isSelected ? Colors.white : color),
      label: Text(
        label,
        style: GoogleFonts.cairo(
          fontSize: 11.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected
              ? Colors.white
              : Theme.of(context).colorScheme.onSurface,
        ),
      ),
      visualDensity: VisualDensity.compact,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      selectedColor: color,
      checkmarkColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? color
              : Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.4),
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

    // Adhere to M3 Selection State Standard:
    // Selected items immediately acquire secondaryContainer background & primary 1.5dp border
    final cardBgColor = isSelected
        ? colorScheme.secondaryContainer
        : colorScheme.surfaceContainerLowest;
    final borderColor = isSelected
        ? colorScheme.primary
        : colorScheme.outlineVariant.withValues(alpha: 0.5);

    return Container(
      margin: const EdgeInsets.only(bottom: M3Spacing.xs + M3Spacing.xxs),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (onSelect != null) onSelect();
            if (!isDualPane) {
              _showDirectiveDetailsDialog(
                  context, item, strings, isAr, colorScheme);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(M3Spacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Badges Row
                Row(
                  children: [
                    // Directive ID Badge (e.g. [AIR-01])
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: M3Spacing.xs,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: catColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        item.id,
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: catColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: M3Spacing.xs),

                    // Category Badge
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: M3Spacing.xs,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.surface.withValues(alpha: 0.7)
                              : colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(item.category.icon, size: 12, color: catColor),
                            const SizedBox(width: M3Spacing.xxs),
                            Flexible(
                              child: Text(
                                item.category.getLabel(isAr),
                                style: GoogleFonts.cairo(
                                  fontSize: 10.5,
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
                    const SizedBox(width: M3Spacing.xs),

                    // Active Status Chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: M3Spacing.xs,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: item.isGloballyActive
                            ? colorScheme.tertiaryContainer
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            item.isGloballyActive
                                ? Icons.check_circle_rounded
                                : Icons.pause_circle_rounded,
                            size: 11,
                            color: item.isGloballyActive
                                ? colorScheme.onTertiaryFixedVariant
                                : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: M3Spacing.xxs),
                          Text(
                            item.isGloballyActive
                                ? (isAr ? 'نشط' : 'Active')
                                : (isAr ? 'معطل' : 'Off'),
                            style: GoogleFonts.cairo(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: item.isGloballyActive
                                  ? colorScheme.onTertiaryContainer
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: M3Spacing.xs),

                // Title
                Text(
                  item.getTitle(isAr),
                  style: GoogleFonts.cairo(
                    fontSize: isDualPane ? 13.5 : 15,
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                    color: isSelected
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: M3Spacing.xxs),

                // Description
                Text(
                  item.getDescription(isAr),
                  style: GoogleFonts.cairo(
                    fontSize: 11.5,
                    height: 1.4,
                    color: isSelected
                        ? colorScheme.onSecondaryContainer
                            .withValues(alpha: 0.85)
                        : colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                if (!isDualPane) ...[
                  const SizedBox(height: M3Spacing.xs),
                  // Real-world POS Example Box on single-pane mobile/tablet
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(M3Spacing.xs + M3Spacing.xxs),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📥 ${isAr ? 'مدخلات البون:' : 'Input:'} ${item.exampleInput}',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '🎁 ${isAr ? 'النتيجة والاستحقاق:' : 'Result:'} ${item.exampleOutput}',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: catColor,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: M3Spacing.xs),

                // Footer info & action buttons
                Row(
                  children: [
                    Icon(
                      Icons.code_rounded,
                      size: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: M3Spacing.xxs),
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
                        onPressed: () => _showDirectiveDetailsDialog(
                            context, item, strings, isAr, colorScheme),
                        icon: const Icon(Icons.menu_book_rounded, size: 15),
                        label: Text(
                          isAr ? 'عرض المنطق' : 'View Logic',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      M3TouchTargetBoundary(
                        child: IconButton(
                          tooltip: isAr ? 'تعديل البند' : 'Edit Directive',
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => _showAddEditDirectiveDialog(
                              context, strings, isAr, item),
                        ),
                      ),
                    ] else if (isSelected) ...[
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: colorScheme.primary,
                      ),
                    ],
                  ],
                ),
              ],
            ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Pinned Top Inspector Action Toolbar (Always visible without scrolling)
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: M3Spacing.md,
            vertical: M3Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: M3Spacing.sm,
            runSpacing: M3Spacing.xs,
            children: [
              // Badges Group
              Wrap(
                spacing: M3Spacing.xs,
                runSpacing: M3Spacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: M3Spacing.sm,
                      vertical: M3Spacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: catColor.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      item.id,
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: catColor,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: M3Spacing.sm,
                      vertical: M3Spacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(item.category.icon, size: 14, color: catColor),
                        const SizedBox(width: M3Spacing.xxs),
                        Text(
                          item.category.getLabel(isAr),
                          style: GoogleFonts.cairo(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: M3Spacing.sm,
                      vertical: M3Spacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: item.isGloballyActive
                          ? colorScheme.tertiaryContainer
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: item.isGloballyActive
                            ? colorScheme.onTertiaryFixedVariant
                                .withValues(alpha: 0.3)
                            : colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.isGloballyActive
                              ? Icons.verified_rounded
                              : Icons.pause_circle_rounded,
                          size: 13,
                          color: item.isGloballyActive
                              ? colorScheme.onTertiaryFixedVariant
                              : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: M3Spacing.xxs),
                        Text(
                          item.isGloballyActive
                              ? (isAr
                                  ? 'نشط ومعتمد سحابياً'
                                  : 'Active & Enforced')
                              : (isAr ? 'معطل مؤقتاً' : 'Inactive'),
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: item.isGloballyActive
                                ? colorScheme.onTertiaryFixedVariant
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Primary Inspector Actions (Test in Studio + Edit Directive)
              Wrap(
                spacing: M3Spacing.xs,
                runSpacing: M3Spacing.xs,
                children: [
                  FilledButton.icon(
                    onPressed: () {
                      _tabController.animateTo(1);
                    },
                    icon: const Icon(Icons.science_rounded, size: 17),
                    label: Text(
                      isAr
                          ? 'تجربة في استوديو الذكاء'
                          : 'Test in Co-Pilot Studio',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: M3Spacing.sm,
                        vertical: M3Spacing.xs,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showAddEditDirectiveDialog(
                        context, strings, isAr, item),
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: Text(
                      isAr ? 'تعديل البند' : 'Edit Directive',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: M3Spacing.sm,
                        vertical: M3Spacing.xs,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 2. Scrollable Detail Body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(M3Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero Directive Overview Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(M3Spacing.md),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: catColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              item.category.icon,
                              color: catColor,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: M3Spacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.getTitle(isAr),
                                  style: GoogleFonts.cairo(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: M3Spacing.xxs),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.terminal_rounded,
                                      size: 14,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: M3Spacing.xxs),
                                    Flexible(
                                      child: SelectableText(
                                        item.code,
                                        style: GoogleFonts.firaCode(
                                          fontSize: 12,
                                          color: colorScheme.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: M3Spacing.xs),
                                    Tooltip(
                                      message: isAr
                                          ? 'نسخ الكود البرمجي'
                                          : 'Copy System Code',
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: () {
                                          Clipboard.setData(
                                            ClipboardData(text: item.code),
                                          );
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                isAr
                                                    ? 'تم نسخ الكود: ${item.code}'
                                                    : 'Copied: ${item.code}',
                                                style: GoogleFonts.cairo(),
                                              ),
                                              duration:
                                                  const Duration(seconds: 2),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(
                                              M3Spacing.xxs),
                                          child: Icon(
                                            Icons.copy_rounded,
                                            size: 14,
                                            color: colorScheme.onSurfaceVariant,
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
                      ),
                      const SizedBox(height: M3Spacing.sm),
                      const Divider(height: 1),
                      const SizedBox(height: M3Spacing.sm),
                      Text(
                        item.getDescription(isAr),
                        style: GoogleFonts.cairo(
                          fontSize: 13.5,
                          height: 1.6,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: M3Spacing.md),

                // Algorithm & Logic Section
                Row(
                  children: [
                    Icon(
                      Icons.account_tree_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: M3Spacing.xs),
                    Text(
                      strings.directiveLogicHeader,
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: M3Spacing.xs),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(M3Spacing.sm),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: SelectableText(
                    item.getLogic(isAr),
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      height: 1.75,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),

                const SizedBox(height: M3Spacing.md),

                // Real-World POS Input vs. AI Evaluation Output (Side-by-Side Responsive Comparison)
                Row(
                  children: [
                    Icon(
                      Icons.receipt_long_rounded,
                      size: 18,
                      color: colorScheme.onSecondaryFixedVariant,
                    ),
                    const SizedBox(width: M3Spacing.xs),
                    Text(
                      strings.directiveExampleHeader,
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: colorScheme.onSecondaryFixedVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: M3Spacing.xs),
                LayoutBuilder(
                  builder: (context, boxConstraints) {
                    final isSideBySide = boxConstraints.maxWidth >= 560;

                    final inputBox = Container(
                      padding: const EdgeInsets.all(M3Spacing.sm),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(M3Spacing.xs),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.input_rounded,
                                  size: 16,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: M3Spacing.xs),
                              Expanded(
                                child: Text(
                                  isAr
                                      ? 'بيانات البون المدخلة (POS Input)'
                                      : 'POS Receipt Input',
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: M3Spacing.xs),
                          SelectableText(
                            item.exampleInput,
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              height: 1.5,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    );

                    final outputBox = Container(
                      padding: const EdgeInsets.all(M3Spacing.sm),
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: catColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(M3Spacing.xs),
                                decoration: BoxDecoration(
                                  color: catColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 16,
                                  color: catColor,
                                ),
                              ),
                              const SizedBox(width: M3Spacing.xs),
                              Expanded(
                                child: Text(
                                  isAr
                                      ? 'القرار الذكي الناتج (AI Output)'
                                      : 'AI Evaluation Output',
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: catColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: M3Spacing.xs),
                          SelectableText(
                            item.exampleOutput,
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              height: 1.5,
                              fontWeight: FontWeight.w700,
                              color: catColor,
                            ),
                          ),
                        ],
                      ),
                    );

                    if (isSideBySide) {
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: inputBox),
                            const SizedBox(width: M3Spacing.sm),
                            Expanded(child: outputBox),
                          ],
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        inputBox,
                        const SizedBox(height: M3Spacing.sm),
                        outputBox,
                      ],
                    );
                  },
                ),

                if (item.tags.isNotEmpty) ...[
                  const SizedBox(height: M3Spacing.md),
                  Row(
                    children: [
                      Icon(
                        Icons.sell_outlined,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: M3Spacing.xs),
                      Text(
                        isAr ? 'الوسوم البرمجية للنظام' : 'System Tags',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: M3Spacing.xs),
                  Wrap(
                    spacing: M3Spacing.xs,
                    runSpacing: M3Spacing.xs,
                    children: item.tags.map((tag) {
                      return ActionChip(
                        label: Text(
                          '#$tag',
                          style: GoogleFonts.cairo(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        backgroundColor: colorScheme.surfaceContainerHigh,
                        side: BorderSide(
                          color: colorScheme.outlineVariant
                              .withValues(alpha: 0.4),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          _searchController.text = tag;
                          setState(() => _searchQuery = tag);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    AppStrings strings,
    bool isAr,
    ColorScheme colorScheme,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(M3Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.psychology_alt_outlined,
              size: 64,
              color: colorScheme.outline,
            ),
            const SizedBox(height: M3Spacing.sm),
            Text(
              isAr
                  ? 'لم يتم العثور على قواعد مطابقة للبحث'
                  : 'No matching AI Directives found',
              style: GoogleFonts.cairo(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: M3Spacing.xs),
            Text(
              isAr
                  ? 'جرب البحث بكلمات أخرى أو اختر تصنيفاً مختلفاً'
                  : 'Try searching with different terms',
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(M3Spacing.xs),
                decoration: BoxDecoration(
                  color: item.category.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  item.category.icon,
                  color: item.category.color,
                  size: 24,
                ),
              ),
              const SizedBox(width: M3Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.id}: ${item.getTitle(isAr)}',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      item.code,
                      style: GoogleFonts.firaCode(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
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
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: M3Spacing.xs),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(M3Spacing.sm),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      item.getLogic(isAr),
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        height: 1.6,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: M3Spacing.sm),
                  Text(
                    strings.directiveExampleHeader,
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: colorScheme.onSecondaryFixedVariant,
                    ),
                  ),
                  const SizedBox(height: M3Spacing.xs),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(M3Spacing.sm),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📥 ${isAr ? 'المدخلات:' : 'Input:'} ${item.exampleInput}',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: M3Spacing.xs),
                        Text(
                          '🎁 ${isAr ? 'المخرجات:' : 'Output:'} ${item.exampleOutput}',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: item.category.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (item.tags.isNotEmpty) ...[
                    const SizedBox(height: M3Spacing.sm),
                    Wrap(
                      spacing: M3Spacing.xs,
                      runSpacing: M3Spacing.xs,
                      children: item.tags.map((tag) {
                        return Chip(
                          label: Text(
                            '#$tag',
                            style: GoogleFonts.cairo(fontSize: 11),
                          ),
                          backgroundColor: colorScheme.surfaceContainerHigh,
                          padding: EdgeInsets.zero,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
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
              child: Text(
                isAr ? 'إغلاق' : 'Close',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
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
    final idController = TextEditingController(
        text: existing?.id ?? 'AIR-${DateTime.now().millisecond}');
    final codeController = TextEditingController(text: existing?.code ?? '');
    final titleArController =
        TextEditingController(text: existing?.titleAr ?? '');
    final titleEnController =
        TextEditingController(text: existing?.titleEn ?? '');
    final descArController =
        TextEditingController(text: existing?.descriptionAr ?? '');
    final descEnController =
        TextEditingController(text: existing?.descriptionEn ?? '');
    final logicArController =
        TextEditingController(text: existing?.logicAr ?? '');
    final logicEnController =
        TextEditingController(text: existing?.logicEn ?? '');
    final inExampleController =
        TextEditingController(text: existing?.exampleInput ?? '');
    final outExampleController =
        TextEditingController(text: existing?.exampleOutput ?? '');
    AiDirectiveCategory category =
        existing?.category ?? AiDirectiveCategory.promotionalRules;
    bool isActive = existing?.isGloballyActive ?? true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final cs = Theme.of(dialogContext).colorScheme;
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text(
                existing == null
                    ? strings.addNewDirectiveBtn
                    : (isAr ? 'تعديل البند الذكي' : 'Edit Directive'),
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold, fontSize: 17),
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
                                labelText:
                                    isAr ? 'رقم البند (ID)' : 'Directive ID',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: M3Spacing.sm),
                          Expanded(
                            child: DropdownButtonFormField<AiDirectiveCategory>(
                              initialValue: category,
                              decoration: InputDecoration(
                                labelText: isAr ? 'التصنيف' : 'Category',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              items: AiDirectiveCategory.values.map((c) {
                                return DropdownMenuItem(
                                  value: c,
                                  child: Text(
                                    c.getLabel(isAr),
                                    style: GoogleFonts.cairo(fontSize: 12),
                                  ),
                                );
                              }).toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setDialogState(() => category = v);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: M3Spacing.sm),
                      TextField(
                        controller: codeController,
                        decoration: InputDecoration(
                          labelText: isAr
                              ? 'الكود البرمجي (CODE)'
                              : 'System Code Name',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: M3Spacing.sm),
                      TextField(
                        controller: titleArController,
                        decoration: InputDecoration(
                          labelText:
                              isAr ? 'عنوان البند (بالعربية)' : 'Title (Arabic)',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: M3Spacing.sm),
                      TextField(
                        controller: titleEnController,
                        decoration: InputDecoration(
                          labelText: isAr
                              ? 'عنوان البند (بالإنجليزية)'
                              : 'Title (English)',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: M3Spacing.sm),
                      TextField(
                        controller: descArController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: isAr
                              ? 'الشرح والهدف (بالعربية)'
                              : 'Description (Arabic)',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: M3Spacing.sm),
                      TextField(
                        controller: logicArController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: isAr
                              ? 'المنطق البرمجي والخوارزمية'
                              : 'Algorithm & Logic',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: M3Spacing.sm),
                      TextField(
                        controller: inExampleController,
                        decoration: InputDecoration(
                          labelText: isAr
                              ? 'مثال المدخلات من الفاتورة'
                              : 'Sample Input',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: M3Spacing.sm),
                      TextField(
                        controller: outExampleController,
                        decoration: InputDecoration(
                          labelText: isAr
                              ? 'مثال النتيجة والمخرجات'
                              : 'Sample Output',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: M3Spacing.sm),
                      SwitchListTile(
                        value: isActive,
                        onChanged: (v) => setDialogState(() => isActive = v),
                        title: Text(
                          strings.directiveStatusActive,
                          style: GoogleFonts.cairo(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(isAr ? 'إلغاء' : 'Cancel',
                      style: GoogleFonts.cairo()),
                ),
                FilledButton(
                  onPressed: () async {
                    final newModel = AiDirectiveModel(
                      id: idController.text.trim(),
                      code: codeController.text.trim().toUpperCase(),
                      titleAr: titleArController.text.trim(),
                      titleEn: titleEnController.text.trim().isNotEmpty
                          ? titleEnController.text.trim()
                          : titleArController.text.trim(),
                      category: category,
                      descriptionAr: descArController.text.trim(),
                      descriptionEn: descEnController.text.trim().isNotEmpty
                          ? descEnController.text.trim()
                          : descArController.text.trim(),
                      logicAr: logicArController.text.trim(),
                      logicEn: logicEnController.text.trim().isNotEmpty
                          ? logicEnController.text.trim()
                          : logicArController.text.trim(),
                      exampleInput: inExampleController.text.trim(),
                      exampleOutput: outExampleController.text.trim(),
                      isGloballyActive: isActive,
                      orderIndex: existing?.orderIndex ?? 99,
                      lastUpdated:
                          DateTime.now().toIso8601String().substring(0, 10),
                    );

                    Navigator.of(ctx).pop();
                    try {
                      if (existing == null) {
                        await ref
                            .read(aiDirectivesServiceProvider)
                            .addDirective(newModel);
                      } else {
                        await ref
                            .read(aiDirectivesServiceProvider)
                            .updateDirective(newModel);
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(strings.directiveSavedSuccess),
                            backgroundColor:
                                colorScheme.onTertiaryFixedVariant,
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
                  child: Text(
                    isAr ? 'حفظ وتوثيق' : 'Save Directive',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
