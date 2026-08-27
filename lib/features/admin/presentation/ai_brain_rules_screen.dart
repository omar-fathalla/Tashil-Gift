import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/services/ai_directives_service.dart';
import '../domain/ai_directive_model.dart';

class AiBrainRulesScreen extends ConsumerStatefulWidget {
  const AiBrainRulesScreen({super.key});

  @override
  ConsumerState<AiBrainRulesScreen> createState() => _AiBrainRulesScreenState();
}

class _AiBrainRulesScreenState extends ConsumerState<AiBrainRulesScreen> {
  final TextEditingController _searchController = TextEditingController();
  AiDirectiveCategory? _selectedCategory; // null = all
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Seed directives to Firestore if collection is currently empty
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(aiDirectivesServiceProvider).seedDirectivesIfEmpty();
    });
  }

  @override
  void dispose() {
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

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          // 1. Header Banner & KPIs
          SliverToBoxAdapter(
            child: _buildHeaderBanner(context, strings, isAr, colorScheme),
          ),

          // 2. Search & Category Filter Toolbar
          SliverToBoxAdapter(
            child: _buildSearchAndFilterToolbar(context, strings, isAr, colorScheme),
          ),

          // 3. Directives List
          directivesAsync.when(
            data: (directives) {
              final filtered = _filterDirectives(directives, isAr);
              if (filtered.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(context, strings, isAr, colorScheme),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = filtered[index];
                      return _buildDirectiveCard(context, item, strings, isAr, colorScheme);
                    },
                    childCount: filtered.length,
                  ),
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => SliverFillRemaining(
              child: Center(
                child: Text(
                  'Error loading AI Directives: $err',
                  style: GoogleFonts.cairo(color: colorScheme.error),
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditDirectiveDialog(context, strings, isAr, null),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        icon: const Icon(Icons.add_task_rounded),
        label: Text(
          strings.addNewDirectiveBtn,
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
      ),
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

  Widget _buildHeaderBanner(BuildContext context, AppStrings strings, bool isAr, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer.withValues(alpha: 0.8),
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.aiBrainTitle,
                      style: GoogleFonts.cairo(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      strings.aiBrainSubtitle,
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // KPI Cards Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              return Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  _buildKpiCard(
                    title: strings.totalAiDirectivesCount,
                    value: '18 ${isAr ? 'بنداً معيارياً' : 'Directives'}',
                    subtitle: isAr ? 'محدثة ونشطة بكافة الحملات' : 'Enforced Globally',
                    icon: Icons.checklist_rtl_rounded,
                    color: const Color(0xFF6750A4),
                    isWide: isWide,
                  ),
                  _buildKpiCard(
                    title: strings.activeAiModelPrimary,
                    value: 'Gemini 3.7 Flash',
                    subtitle: isAr ? 'النموذج القياسي الفائق' : 'Primary Tier-1 Engine',
                    icon: Icons.bolt_rounded,
                    color: const Color(0xFF006C50),
                    isWide: isWide,
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
        ],
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
  }) {
    return Container(
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
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
    ColorScheme colorScheme,
  ) {
    final catColor = item.category.color;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      color: colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Badges Row
            Row(
              children: [
                // Directive ID Badge (e.g. [AIR-01])
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
                const SizedBox(width: 8),

                // Category Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(item.category.icon, size: 13, color: catColor),
                      const SizedBox(width: 5),
                      Text(
                        item.category.getLabel(isAr),
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),

                // Active Status Chip
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.isGloballyActive ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
                        size: 13,
                        color: item.isGloballyActive ? const Color(0xFF2E7D32) : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.isGloballyActive ? strings.directiveStatusActive : strings.directiveStatusInactive,
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: item.isGloballyActive ? const Color(0xFF1B5E20) : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Title
            Text(
              item.getTitle(isAr),
              style: GoogleFonts.cairo(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),

            // Description
            Text(
              item.getDescription(isAr),
              style: GoogleFonts.cairo(
                fontSize: 13,
                height: 1.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),

            // Real-world POS Example Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
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
                      Icon(Icons.lightbulb_rounded, size: 16, color: Colors.amber.shade700),
                      const SizedBox(width: 6),
                      Text(
                        strings.directiveExampleHeader,
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '📥 ${isAr ? 'مدخلات البون:' : 'Input:'} ${item.exampleInput}',
                    style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '🎁 ${isAr ? 'النتيجة والاستحقاق:' : 'Result:'} ${item.exampleOutput}',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: catColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Footer info & action buttons
            Row(
              children: [
                Icon(Icons.code_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 5),
                Text(
                  item.code,
                  style: GoogleFonts.firaCode(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _showDirectiveDetailsDialog(context, item, strings, isAr, colorScheme),
                  icon: const Icon(Icons.menu_book_rounded, size: 16),
                  label: Text(
                    isAr ? 'عرض المنطق البرمجي' : 'View Full Logic',
                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: isAr ? 'تعديل البند' : 'Edit Directive',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _showAddEditDirectiveDialog(context, strings, isAr, item),
                ),
              ],
            ),
          ],
        ),
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
