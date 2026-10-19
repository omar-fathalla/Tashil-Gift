import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/services/ai_model_config_service.dart';

class AiModelSwitcherDialog extends ConsumerStatefulWidget {
  const AiModelSwitcherDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const AiModelSwitcherDialog(),
    );
  }

  @override
  ConsumerState<AiModelSwitcherDialog> createState() => _AiModelSwitcherDialogState();
}

class _AiModelSwitcherDialogState extends ConsumerState<AiModelSwitcherDialog> {
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  late String _selectedPrimaryModel;
  late String _selectedFallbackModel;
  late AiAgentMode _selectedAgentMode;
  late int _thinkingBudget;
  bool _isCustomModel = false;
  final TextEditingController _customModelController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final currentConfig = ref.read(aiModelConfigStreamProvider).value ?? const AiModelConfig();
    _selectedPrimaryModel = currentConfig.primaryModel;
    _selectedFallbackModel = currentConfig.fallbackModel;
    _selectedAgentMode = currentConfig.agentMode;
    _thinkingBudget = currentConfig.thinkingBudget;

    if (currentConfig.customModelIdentifier != null && currentConfig.customModelIdentifier!.isNotEmpty) {
      _isCustomModel = true;
      _customModelController.text = currentConfig.customModelIdentifier!;
    } else {
      // Check if primaryModel is not in known presets
      final isPreset = GeminiModelPreset.presets.any((p) => p.id == _selectedPrimaryModel);
      if (!isPreset) {
        _isCustomModel = true;
        _customModelController.text = _selectedPrimaryModel;
      }
    }
  }

  @override
  void dispose() {
    _customModelController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    final isAr = ref.read(localeProvider).languageCode == 'ar';

    try {
      final service = ref.read(aiModelConfigServiceProvider);
      final customName = _isCustomModel ? _customModelController.text.trim() : null;

      await service.updateConfig(
        primaryModel: _selectedPrimaryModel,
        fallbackModel: _selectedFallbackModel,
        agentMode: _selectedAgentMode,
        thinkingBudget: _thinkingBudget,
        customModelIdentifier: customName,
        updatedBy: 'admin',
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: colorScheme.tertiary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isAr
                        ? 'تم تحديث نموذج ووكيل الذكاء الاصطناعي المركزي بنجاح وتطبيقه عبر النظام كاملاً! 🚀'
                        : 'Global AI model & agent updated and propagated successfully! 🚀',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text('خطأ في حفظ الإعدادات: $e', style: GoogleFonts.cairo()),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isAr = ref.isArabic;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: colorScheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Column(
          children: [
            // 1. Header Banner
            _buildDialogHeader(colorScheme, isAr),

            // 2. Scrollable Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 1: Primary Model Selection
                    _buildSectionTitle(
                      title: isAr ? '1. اختيار النموذج الأساسي (Primary Model)' : '1. Select Primary Model',
                      subtitle: isAr
                          ? 'النموذج الذي يعتمد عليه النظام في الفحص واستخراج البونات ومحادثة الاستوديو'
                          : 'The core AI model powering receipt analysis and co-pilot studio',
                      icon: Icons.bolt_rounded,
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(height: 12),
                    ...GeminiModelPreset.presets.map((preset) => _buildModelRadioCard(preset, colorScheme, isAr)),

                    // Custom Model Option
                    _buildCustomModelCard(colorScheme, isAr),

                    const SizedBox(height: 24),
                    const Divider(height: 1),
                    const SizedBox(height: 24),

                    // Section 2: Agent Mode Selection
                    _buildSectionTitle(
                      title: isAr ? '2. اختيار نمط الوكيل المتخصص (Specialized Agent Mode)' : '2. Specialized Agent Mode',
                      subtitle: isAr
                          ? 'توجيه عقل الذكاء الاصطناعي للتركيز على مهمة محددة وفق طبيعة عمليات الحملات'
                          : 'Fine-tunes the AI engine behavior for specific campaign operational focus',
                      icon: Icons.psychology_rounded,
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(height: 12),
                    ...AiAgentMode.values.map((mode) => _buildAgentModeRadioCard(mode, colorScheme, isAr)),

                    const SizedBox(height: 24),
                    const Divider(height: 1),
                    const SizedBox(height: 24),

                    // Section 3: Fallback Model
                    _buildSectionTitle(
                      title: isAr ? '3. النموذج الاحتياطي التلقائي (Automated Fallback)' : '3. Automated Fallback Model',
                      subtitle: isAr
                          ? 'يتم تفعيله فورياً وبشكل صامت عند أي بطء في الشبكة أو ضغط على السيرفرات'
                          : 'Automatically triggered on network latency or rate limit quotas',
                      icon: Icons.shield_rounded,
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(height: 12),
                    _buildFallbackSelector(colorScheme, isAr),
                  ],
                ),
              ),
            ),

            // 3. Action Footer
            _buildDialogFooter(colorScheme, isAr),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader(ColorScheme colorScheme, bool isAr) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colorScheme.primary, colorScheme.tertiary],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.tune_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr ? 'إعدادات محرك ووكيل الذكاء الاصطناعي المركزي' : 'Global AI Model & Agent Settings',
                  style: GoogleFonts.cairo(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  isAr
                      ? 'التحكم الفوري في نموذج Gemini ونمط التدقيق عبر كافة التابلت والكاونترات سحابياً'
                      : 'Real-time cloud control for Gemini model & agent modes across all devices',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle({
    required String title,
    required String subtitle,
    required IconData icon,
    required ColorScheme colorScheme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: GoogleFonts.cairo(
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 26),
          child: Text(
            subtitle,
            style: GoogleFonts.cairo(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _buildModelRadioCard(GeminiModelPreset preset, ColorScheme colorScheme, bool isAr) {
    final isSelected = !_isCustomModel && _selectedPrimaryModel == preset.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          setState(() {
            _isCustomModel = false;
            _selectedPrimaryModel = preset.id;
          });
        },
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primaryContainer.withValues(alpha: 0.35)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            isAr ? preset.titleAr : preset.titleEn,
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: preset.isLatest
                                ? colorScheme.tertiary.withValues(alpha: 0.15)
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: preset.isLatest
                                  ? colorScheme.tertiary.withValues(alpha: 0.5)
                                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            preset.badge,
                            style: GoogleFonts.cairo(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: preset.isLatest ? colorScheme.onTertiaryFixedVariant : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isAr ? preset.descriptionAr : preset.id,
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomModelCard(ColorScheme colorScheme, bool isAr) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          setState(() => _isCustomModel = true);
        },
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _isCustomModel
                ? colorScheme.primaryContainer.withValues(alpha: 0.35)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isCustomModel ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: _isCustomModel ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _isCustomModel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: _isCustomModel ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      isAr ? 'نموذج مخصص (+ Custom Model Identifier)' : 'Custom Model Identifier (+)',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: _isCustomModel ? colorScheme.primary : colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      isAr ? 'أي موديل مستقبلي ✨' : 'Future-Proof ✨',
                      style: GoogleFonts.cairo(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              if (_isCustomModel) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _customModelController,
                  autofocus: true,
                  style: GoogleFonts.cairo(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: isAr
                        ? 'اكتب اسم الموديل كما في Google AI Studio (مثلاً: gemini-3.8-flash, gemini-3.8-ultra, إلخ)'
                        : 'e.g. gemini-3.8-flash, gemini-3.8-ultra, gemini-4.0',
                    hintStyle: GoogleFonts.cairo(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    prefixIcon: const Icon(Icons.code_rounded, size: 18),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgentModeRadioCard(AiAgentMode mode, ColorScheme colorScheme, bool isAr) {
    final isSelected = _selectedAgentMode == mode;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          setState(() => _selectedAgentMode = mode);
        },
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.12)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
                color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  isAr ? mode.displayNameAr : mode.displayNameEn,
                  style: GoogleFonts.cairo(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                    color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackSelector(ColorScheme colorScheme, bool isAr) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedFallbackModel,
          isExpanded: true,
          style: GoogleFonts.cairo(fontSize: 13, color: colorScheme.onSurface, fontWeight: FontWeight.bold),
          icon: const Icon(Icons.arrow_drop_down_rounded),
          items: const [
            DropdownMenuItem(
              value: 'gemini-3.6-flash',
              child: Text('جيميناي 3.6 فلاش (موصى به للاحتياطي - عالي الاعتمادية)'),
            ),
            DropdownMenuItem(
              value: 'gemini-2.5-flash',
              child: Text('جيميناي 2.5 فلاش (احتياطي ثانوي خفيف)'),
            ),
            DropdownMenuItem(
              value: 'gemini-3.7-flash',
              child: Text('جيميناي 3.7 فلاش (عند تشغيل 3.8 كنموذج أساسي)'),
            ),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _selectedFallbackModel = val);
          },
        ),
      ),
    );
  }

  Widget _buildDialogFooter(ColorScheme colorScheme, bool isAr) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(isAr ? 'إلغاء' : 'Cancel', style: GoogleFonts.cairo()),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _isSaving ? null : _handleSave,
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.cloud_done_rounded, size: 18),
            label: Text(
              isAr ? 'حفظ وتطبيق على السيستم فوراً' : 'Save & Propagate Globally',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.tertiary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
