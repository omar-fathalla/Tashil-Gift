import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/retail_chains_service.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/arabic_numbers_utils.dart';
import '../../../core/animations/m3_motion.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../domain/retail_chain_model.dart';

class RetailChainsScreen extends ConsumerStatefulWidget {
  const RetailChainsScreen({super.key});

  @override
  ConsumerState<RetailChainsScreen> createState() => _RetailChainsScreenState();
}

class _RetailChainsScreenState extends ConsumerState<RetailChainsScreen> {
  // Card 1: Chain Form Controllers
  final _chainFormKey = GlobalKey<FormState>();
  final _chainNameController = TextEditingController();
  final _chainSlugController = TextEditingController();
  final _chainNameFocusNode = FocusNode();
  final _chainSlugFocusNode = FocusNode();
  bool _isSavingChain = false;
  String? _editingChainId;

  // Card 2: Branch Form Controllers
  final _branchFormKey = GlobalKey<FormState>();
  final _branchNameController = TextEditingController();
  final _branchCityController = TextEditingController();
  final _branchCodeController = TextEditingController();
  final _branchAddressController = TextEditingController();
  final _branchNameFocusNode = FocusNode();
  final _branchCityFocusNode = FocusNode();
  final _branchCodeFocusNode = FocusNode();
  final _branchAddressFocusNode = FocusNode();
  bool _isSavingBranch = false;
  String? _selectedChainIdForBranch;
  String? _editingBranchId;

  // Card 3: Directory Filter & Search
  int _selectedDirectoryTab = 0; // 0 = Chains View, 1 = Branches View
  final _searchController = TextEditingController();
  final _chainSearchController = TextEditingController();
  String _searchQuery = '';
  String _chainSearchQuery = '';
  String? _activeFilterChainId;
  bool _isSeeding = false;

  @override
  void dispose() {
    _chainNameController.dispose();
    _chainSlugController.dispose();
    _chainNameFocusNode.dispose();
    _chainSlugFocusNode.dispose();

    _branchNameController.dispose();
    _branchCityController.dispose();
    _branchCodeController.dispose();
    _branchAddressController.dispose();
    _branchNameFocusNode.dispose();
    _branchCityFocusNode.dispose();
    _branchCodeFocusNode.dispose();
    _branchAddressFocusNode.dispose();

    _searchController.dispose();
    _chainSearchController.dispose();
    super.dispose();
  }

  // --- ACTIONS: SAVE / EDIT / DELETE CHAIN ---

  Future<void> _saveChain() async {
    if (!_chainFormKey.currentState!.validate()) return;

    final name = _chainNameController.text.trim();
    final slug = _chainSlugController.text.trim().toLowerCase().toEnglishDigits().replaceAll(RegExp(r'\s+'), '-');

    setState(() => _isSavingChain = true);
    final service = ref.read(retailChainsServiceProvider);

    try {
      final chain = RetailChainModel(
        id: _editingChainId ?? '',
        name: name,
        slug: slug.isNotEmpty ? slug : name.toLowerCase().replaceAll(RegExp(r'\s+'), '-'),
      );

      if (_editingChainId == null) {
        await service.addRetailChain(chain);
        if (mounted) {
          await M3Feedback.showAdded(
            context,
            itemName: name,
            message: 'تمت إضافة السلسلة التجارية إلى النظام بنجاح.',
            icon: Icons.storefront_rounded,
          );
        }
      } else {
        await service.updateRetailChain(chain);
        if (mounted) {
          await M3Feedback.showSuccess(
            context,
            title: 'تم التعديل بنجاح',
            message: 'تم تحديث بيانات السلسلة "$name".',
          );
        }
      }

      _chainNameController.clear();
      _chainSlugController.clear();
      setState(() {
        _editingChainId = null;
      });

      if (mounted) {
        _chainNameFocusNode.requestFocus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء حفظ السلسلة')),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingChain = false);
    }
  }

  void _editChain(RetailChainModel chain) {
    setState(() {
      _editingChainId = chain.id;
      _chainNameController.text = chain.name;
      _chainSlugController.text = chain.slug;
    });
    _chainNameFocusNode.requestFocus();
  }

  Future<void> _deleteChain(RetailChainModel chain) async {
    final confirmed = await M3Feedback.showApprovalDialog(
      context,
      title: 'حذف السلسلة وفروعها',
      message: 'هل أنت متأكد من حذف سلسلة "${chain.name}"؟ سيتم حذف جميع الفروع المرتبطة بها نهائياً.',
      confirmText: 'نعم، حذف السلسلة',
      cancelText: 'تراجع',
    );

    if (confirmed == true) {
      try {
        await ref.read(retailChainsServiceProvider).deleteRetailChain(chain.id);
        if (mounted) {
          if (_selectedChainIdForBranch == chain.id) {
            setState(() => _selectedChainIdForBranch = null);
          }
          if (_activeFilterChainId == chain.id) {
            setState(() => _activeFilterChainId = null);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم حذف سلسلة "${chain.name}" وفروعها بنجاح'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green.shade800,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء الحذف')),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  // --- ACTIONS: SAVE / EDIT / DELETE BRANCH ---

  Future<void> _saveBranch(List<RetailChainModel> chains) async {
    if (_selectedChainIdForBranch == null || _selectedChainIdForBranch!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار السلسلة التجارية التابع لها الفرع أولاً'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!_branchFormKey.currentState!.validate()) return;

    final selectedChain = chains.firstWhere(
      (c) => c.id == _selectedChainIdForBranch,
      orElse: () => RetailChainModel(id: '', name: '', slug: ''),
    );

    final branchName = _branchNameController.text.trim();
    final city = _branchCityController.text.trim();
    final code = _branchCodeController.text.trim().toUpperCase().toEnglishDigits();
    final address = _branchAddressController.text.trim();

    setState(() => _isSavingBranch = true);
    final service = ref.read(retailChainsServiceProvider);

    try {
      final branch = BranchModel(
        id: _editingBranchId ?? '',
        retailChainId: selectedChain.id,
        retailChainName: selectedChain.name,
        branchName: branchName,
        city: city,
        branchCode: code,
        address: address,
      );

      if (_editingBranchId == null) {
        await service.addBranch(branch);
        if (mounted) {
          await M3Feedback.showAdded(
            context,
            itemName: '$branchName (${selectedChain.name})',
            message: 'تمت إضافة الفرع بنجاح.',
            icon: Icons.store_rounded,
          );
        }
      } else {
        await service.updateBranch(branch);
        if (mounted) {
          await M3Feedback.showSuccess(
            context,
            title: 'تم التعديل بنجاح',
            message: 'تم تحديث بيانات الفرع "$branchName".',
          );
        }
      }

      _branchNameController.clear();
      _branchCityController.clear();
      _branchCodeController.clear();
      _branchAddressController.clear();
      setState(() {
        _editingBranchId = null;
      });

      if (mounted) {
        _branchNameFocusNode.requestFocus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء حفظ الفرع')),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingBranch = false);
    }
  }

  void _editBranch(BranchModel branch) {
    setState(() {
      _selectedChainIdForBranch = branch.retailChainId;
      _editingBranchId = branch.id;
      _branchNameController.text = branch.branchName;
      _branchCityController.text = branch.city;
      _branchCodeController.text = branch.branchCode;
      _branchAddressController.text = branch.address;
    });
    _branchNameFocusNode.requestFocus();
  }

  Future<void> _deleteBranch(BranchModel branch) async {
    final confirmed = await M3Feedback.showApprovalDialog(
      context,
      title: 'حذف الفرع',
      message: 'هل أنت متأكد من حذف "${branch.branchName}" التابع لـ "${branch.retailChainName}"؟',
      confirmText: 'نعم، حذف',
      cancelText: 'إلغاء',
    );

    if (confirmed == true) {
      try {
        await ref.read(retailChainsServiceProvider).deleteBranch(branch.id, branch.retailChainId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم حذف "${branch.branchName}" بنجاح'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green.shade800,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء الحذف')),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  // --- SEED PREDEFINED CHAINS ---

  Future<void> _seedChains() async {
    final confirm = await M3Feedback.showApprovalDialog(
      context,
      title: 'تهيئة السلاسل والفروع التلقائية',
      message: 'سيتم إضافة أشهر سلاسل الهايبر ماركت في مصر (أسواق فتح الله، كارفور، سبينس، سعودي، زهران، بيت الجملة، جملة ماركت) مع فروعها الشهيرة لتسهيل العمل فوراً.',
      confirmText: 'نعم، تهيئة الآن',
      cancelText: 'إلغاء',
    );

    if (confirm != true) return;

    setState(() => _isSeeding = true);
    try {
      final count = await ref.read(retailChainsServiceProvider).seedPredefinedRetailChains();
      if (mounted) {
        await M3Feedback.showSuccess(
          context,
          title: 'تمت التهيئة بنجاح!',
          message: 'تم تكويد $count فرعاً وسلسلة تجارية جاهزة للاستخدام في الحملات.',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء التهيئة')),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSeeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chainsStream = ref.watch(retailChainsServiceProvider).getRetailChainsStream();
    final branchesStream = ref.watch(retailChainsServiceProvider).getAllBranchesStream();

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1050;

    return StreamBuilder<List<RetailChainModel>>(
      stream: chainsStream,
      builder: (context, chainsSnap) {
        final chains = chainsSnap.data ?? [];

        // Auto select first chain if none selected
        if (_selectedChainIdForBranch == null && chains.isNotEmpty) {
          _selectedChainIdForBranch = chains.first.id;
        }

        return StreamBuilder<List<BranchModel>>(
          stream: branchesStream,
          builder: (context, branchesSnap) {
            final allBranches = branchesSnap.data ?? [];

            // Filter branches based on search query and chain filter
            final filteredBranches = allBranches.where((b) {
              final query = _searchQuery.trim().toLowerCase().toEnglishDigits();
              final matchesChain = _activeFilterChainId == null || b.retailChainId == _activeFilterChainId;
              if (!matchesChain) return false;
              if (query.isEmpty) return true;
              return b.branchName.toLowerCase().toEnglishDigits().contains(query) ||
                  b.retailChainName.toLowerCase().toEnglishDigits().contains(query) ||
                  b.city.toLowerCase().toEnglishDigits().contains(query) ||
                  b.branchCode.toLowerCase().toEnglishDigits().contains(query);
            }).toList();

            final isAr = ref.isArabic;
            final strings = AppStrings.of(ref);

            return Scaffold(
              backgroundColor: colorScheme.surface,
              body: CustomScrollView(
                slivers: [
                  // App Bar / Hero Header
                  SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        border: Border(
                          bottom: BorderSide(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.storefront_rounded,
                                  color: colorScheme.onPrimaryContainer,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      strings.retailChainsTitle,
                                      style: GoogleFonts.cairo(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    Text(
                                      strings.retailChainsSubtitle,
                                      style: GoogleFonts.cairo(
                                        fontSize: 13,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Predefined seed button
                              FilledButton.tonalIcon(
                                onPressed: _isSeeding ? null : _seedChains,
                                icon: _isSeeding
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.auto_fix_high_rounded, size: 18),
                                label: Text(
                                  _isSeeding ? strings.loading : (isAr ? 'تهيئة السلاسل الشهيرة تلقائياً' : 'Auto-Seed Popular Chains'),
                                  style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Main Content
                  SliverPadding(
                    padding: const EdgeInsets.all(24),
                    sliver: SliverToBoxAdapter(
                      child: isDesktop
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left Column: Forms (Chain + Branch creation)
                                SizedBox(
                                  width: 440,
                                  child: Column(
                                    children: [
                                      _buildChainFormCard(colorScheme),
                                      const SizedBox(height: 20),
                                      _buildBranchFormCard(colorScheme, chains),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 24),
                                // Right Column: Directory of Chains & Branches
                                Expanded(
                                  child: _buildDirectoryCard(colorScheme, chains, filteredBranches, allBranches.length),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                _buildChainFormCard(colorScheme),
                                const SizedBox(height: 20),
                                _buildBranchFormCard(colorScheme, chains),
                                const SizedBox(height: 24),
                                _buildDirectoryCard(colorScheme, chains, filteredBranches, allBranches.length),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- CARD 1: RETAIL CHAIN FORM ---

  Widget _buildChainFormCard(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _chainFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _editingChainId == null ? Icons.add_business_rounded : Icons.edit_note_rounded,
                    color: colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _editingChainId == null ? '1. تكويد سلسلة تجارية جديدة' : 'تعديل السلسلة التجارية',
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (_editingChainId != null) ...[
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _editingChainId = null;
                          _chainNameController.clear();
                          _chainSlugController.clear();
                        });
                      },
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('إلغاء التعديل'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'مثل: أسواق فتح الله، كارفور مصر، سبينس، سعودي ماركت، زهران ماركت، بيت الجملة.',
                style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),

              // Chain Name
              TextFormField(
                controller: _chainNameController,
                focusNode: _chainNameFocusNode,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _chainSlugFocusNode.requestFocus(),
                decoration: InputDecoration(
                  labelText: 'اسم السلسلة / المنظمة *',
                  hintText: 'مثال: أسواق فتح الله',
                  prefixIcon: const Icon(Icons.storefront_outlined),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'يرجى كتابة اسم السلسلة';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Chain Slug/Code
              TextFormField(
                controller: _chainSlugController,
                focusNode: _chainSlugFocusNode,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _isSavingChain ? null : _saveChain(),
                inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                decoration: InputDecoration(
                  labelText: 'الكود المعرف للسلسلة (Slug) *',
                  hintText: 'مثال: fathalla أو carrefour',
                  prefixIcon: const Icon(Icons.qr_code_2_rounded),
                  helperText: 'يستخدم داخلياً باللغة الإنجليزية أو الأرقام لربط السلسلة بالحملة',
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'يرجى كتابة الكود المعرف';
                  return null;
                },
              ),
              const SizedBox(height: 18),

              // Submit Button
              Align(
                alignment: Alignment.centerLeft,
                child: M3ActionButton(
                  label: _editingChainId == null ? 'حفظ السلسلة' : 'تحديث السلسلة',
                  icon: _editingChainId == null ? Icons.save_rounded : Icons.check_circle_rounded,
                  isLoading: _isSavingChain,
                  variant: M3ButtonVariant.filled,
                  onPressed: _saveChain,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- CARD 2: BRANCH FORM ---

  Widget _buildBranchFormCard(ColorScheme colorScheme, List<RetailChainModel> chains) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _branchFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _editingBranchId == null ? Icons.add_location_alt_rounded : Icons.edit_location_alt_rounded,
                    color: colorScheme.secondary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _editingBranchId == null ? '2. إضافة فرع للسلسلة' : 'تعديل بيانات الفرع',
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (_editingBranchId != null) ...[
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _editingBranchId = null;
                          _branchNameController.clear();
                          _branchCityController.clear();
                          _branchCodeController.clear();
                          _branchAddressController.clear();
                        });
                      },
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('إلغاء التعديل'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'اختر السلسلة ثم أضف الفرع مع المحافظة/المنطقة الخاصة به.',
                style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),

              // Parent Chain Selector Dropdown
              if (chains.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'يرجى تكويد سلسلة تجارية واحدة على الأقل أعلاه لتتمكن من إضافة فروع.',
                    style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onErrorContainer),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _selectedChainIdForBranch,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'السلسلة التجارية التابع لها الفرع *',
                    prefixIcon: const Icon(Icons.apartment_rounded),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: chains.map((c) {
                    return DropdownMenuItem<String>(
                      value: c.id,
                      child: Text(
                        '${c.name} (${c.slug})',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() => _selectedChainIdForBranch = val);
                  },
                ),
              const SizedBox(height: 12),

              // Branch Name
              TextFormField(
                controller: _branchNameController,
                focusNode: _branchNameFocusNode,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _branchCityFocusNode.requestFocus(),
                decoration: InputDecoration(
                  labelText: 'اسم الفرع *',
                  hintText: 'مثال: فرع الهانوفيل أو فرع سموحة',
                  prefixIcon: const Icon(Icons.store_outlined),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'يرجى كتابة اسم الفرع';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // City / Governorate
              TextFormField(
                controller: _branchCityController,
                focusNode: _branchCityFocusNode,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _branchCodeFocusNode.requestFocus(),
                decoration: InputDecoration(
                  labelText: 'المحافظة / المنطقة',
                  hintText: 'مثال: الإسكندرية (العجمي)',
                  prefixIcon: const Icon(Icons.location_city_rounded),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),

              // Branch Code (Optional)
              TextFormField(
                controller: _branchCodeController,
                focusNode: _branchCodeFocusNode,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _branchAddressFocusNode.requestFocus(),
                inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                decoration: InputDecoration(
                  labelText: 'كود الفرع الداخلي (اختياري)',
                  hintText: 'مثال: FAT-HNF أو 102',
                  prefixIcon: const Icon(Icons.tag_rounded),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),

              // Address (Optional)
              TextFormField(
                controller: _branchAddressController,
                focusNode: _branchAddressFocusNode,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _isSavingBranch ? null : _saveBranch(chains),
                decoration: InputDecoration(
                  labelText: 'عنوان الفرع (اختياري)',
                  hintText: 'مثال: طريق إسكندرية مطروح، العجمي',
                  prefixIcon: const Icon(Icons.map_outlined),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 18),

              // Submit Button
              Align(
                alignment: Alignment.centerLeft,
                child: M3ActionButton(
                  label: _editingBranchId == null ? 'إضافة الفرع' : 'تحديث الفرع',
                  icon: _editingBranchId == null ? Icons.add_circle_outline_rounded : Icons.check_circle_rounded,
                  isLoading: _isSavingBranch,
                  variant: M3ButtonVariant.tonal,
                  onPressed: () => _saveBranch(chains),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- CARD 3: DIRECTORY OF CHAINS & BRANCHES (DUAL-VIEW: CHAINS & BRANCHES) ---

  Widget _buildDirectoryCard(
    ColorScheme colorScheme,
    List<RetailChainModel> chains,
    List<BranchModel> filteredBranches,
    int totalBranchesCount,
  ) {
    // Filter chains based on chain search query
    final chainQuery = _chainSearchQuery.trim().toLowerCase().toEnglishDigits();
    final matchingChains = chains.where((c) {
      if (chainQuery.isEmpty) return true;
      return c.name.toLowerCase().toEnglishDigits().contains(chainQuery) ||
          c.slug.toLowerCase().toEnglishDigits().contains(chainQuery);
    }).toList();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Title + Total Badges
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _selectedDirectoryTab == 0 ? Icons.apartment_rounded : Icons.store_rounded,
                    color: colorScheme.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedDirectoryTab == 0
                            ? 'دليل وإدارة السلاسل الرئيسية'
                            : 'دليل وتصفية الفروع والمنافذ',
                        style: GoogleFonts.cairo(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        _selectedDirectoryTab == 0
                            ? 'عرض كافة السلاسل المسجلة مع إمكانية تعديلها أو حذفها بنقرة واحدة'
                            : 'استعراض فروع كل سلسلة مع التصفية السريعة والبحث والتحكم',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${chains.length} سلسلة | $totalBranchesCount فرع',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tab / Mode Switcher Buttons
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _selectedDirectoryTab = 0),
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _selectedDirectoryTab == 0 ? colorScheme.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _selectedDirectoryTab == 0
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.apartment_rounded,
                              size: 18,
                              color: _selectedDirectoryTab == 0 ? colorScheme.primary : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '🏬 السلاسل الرئيسية (${chains.length})',
                              style: GoogleFonts.cairo(
                                fontWeight: _selectedDirectoryTab == 0 ? FontWeight.bold : FontWeight.w600,
                                fontSize: 13,
                                color: _selectedDirectoryTab == 0 ? colorScheme.primary : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _selectedDirectoryTab = 1),
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _selectedDirectoryTab == 1 ? colorScheme.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _selectedDirectoryTab == 1
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.store_rounded,
                              size: 18,
                              color: _selectedDirectoryTab == 1 ? colorScheme.primary : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '📍 الفروع والمنافذ ($totalBranchesCount)',
                              style: GoogleFonts.cairo(
                                fontWeight: _selectedDirectoryTab == 1 ? FontWeight.bold : FontWeight.w600,
                                fontSize: 13,
                                color: _selectedDirectoryTab == 1 ? colorScheme.primary : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // --- VIEW 0: CHAINS VIEW ---
            if (_selectedDirectoryTab == 0) ...[
              // Search Bar for Chains
              TextField(
                controller: _chainSearchController,
                onChanged: (val) => setState(() => _chainSearchQuery = val),
                decoration: InputDecoration(
                  hintText: 'ابحث باسم السلسلة أو الكود المعرف (Slug)...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _chainSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _chainSearchController.clear();
                            setState(() => _chainSearchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),

              // Chains Cards List
              if (chains.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(Icons.storefront_outlined, size: 54, color: colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          'لا توجد سلاسل تجارية مضافة حتى الآن',
                          style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'قم بإضافة سلسلة من النموذج الأيمن أو اضغط على "تهيئة السلاسل الشهيرة تلقائياً".',
                          style: GoogleFonts.cairo(fontSize: 13, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                )
              else if (matchingChains.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(Icons.search_off_rounded, size: 48, color: colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          'لم يتم العثور على سلاسل مطابقة لـ "$_chainSearchQuery"',
                          style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: matchingChains.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final chain = matchingChains[i];
                    return _buildChainCard(colorScheme, chain);
                  },
                ),
            ],

            // --- VIEW 1: BRANCHES VIEW ---
            if (_selectedDirectoryTab == 1) ...[
              // Search Bar for Branches
              TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'ابحث باسم الفرع أو السلسلة أو المحافظة أو كود الفرع...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 14),

              // Filter Chips for Chains
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text('جميع السلاسل ($totalBranchesCount)', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                      selected: _activeFilterChainId == null,
                      onSelected: (selected) {
                        if (selected) setState(() => _activeFilterChainId = null);
                      },
                    ),
                    const SizedBox(width: 8),
                    ...chains.map((chain) {
                      final isSelected = _activeFilterChainId == chain.id;
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(chain.name, style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? colorScheme.primary
                                      : colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${chain.branchesCount}',
                                  style: GoogleFonts.cairo(
                                    fontSize: 11,
                                    color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() => _activeFilterChainId = selected ? chain.id : null);
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),

              // Branches List
              if (chains.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(Icons.storefront_outlined, size: 48, color: colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          'لا توجد سلاسل تجارية مضافة حتى الآن',
                          style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'قم بإضافة سلسلة يدوياً من النموذج أو اضغط "تهيئة السلاسل الشهيرة تلقائياً"',
                          style: GoogleFonts.cairo(fontSize: 13, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                )
              else if (filteredBranches.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(Icons.search_off_rounded, size: 48, color: colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          'لم يتم العثور على فروع مطابقة لنتائج البحث أو الفلتر',
                          style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredBranches.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final branch = filteredBranches[i];
                    return _buildBranchTile(colorScheme, branch);
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  // --- CHAIN CARD WIDGET WITH CLEAR EDIT & DELETE ACTIONS ---

  Widget _buildChainCard(ColorScheme colorScheme, RetailChainModel chain) {
    final hasBranches = chain.branchesCount > 0;
    final isEditingThis = _editingChainId == chain.id;

    return Container(
      decoration: BoxDecoration(
        color: isEditingThis
            ? colorScheme.primaryContainer.withValues(alpha: 0.25)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isEditingThis
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isEditingThis ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon Avatar
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isEditingThis
                      ? colorScheme.primary
                      : colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.apartment_rounded,
                  color: isEditingThis ? colorScheme.onPrimary : colorScheme.onPrimaryContainer,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              // Chain Name & Slug
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          chain.name,
                          style: GoogleFonts.cairo(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        if (isEditingThis) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'قيد التعديل الآن',
                              style: GoogleFonts.cairo(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          'المعرف (Slug): ',
                          style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            chain.slug,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Branches Count Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: hasBranches
                      ? colorScheme.secondaryContainer
                      : colorScheme.errorContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasBranches ? Icons.storefront_rounded : Icons.info_outline_rounded,
                      size: 14,
                      color: hasBranches ? colorScheme.onSecondaryContainer : colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      hasBranches ? '${chain.branchesCount} فروع' : '0 فرع (سلسلة فارغة)',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: hasBranches ? colorScheme.onSecondaryContainer : colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // Action Buttons Bar
          Row(
            children: [
              // View Branches Button
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedDirectoryTab = 1;
                    _activeFilterChainId = chain.id;
                  });
                },
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: Text(
                  'استعراض الفروع (${chain.branchesCount})',
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const Spacer(),
              // Edit Chain Button
              FilledButton.tonalIcon(
                onPressed: () => _editChain(chain),
                icon: const Icon(Icons.edit_note_rounded, size: 17),
                label: Text(
                  'تعديل السلسلة',
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(width: 8),
              // Delete Chain Button
              OutlinedButton.icon(
                onPressed: () => _deleteChain(chain),
                icon: Icon(Icons.delete_forever_rounded, size: 17, color: colorScheme.error),
                label: Text(
                  'حذف السلسلة',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.error,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- BRANCH TILE WIDGET ---

  Widget _buildBranchTile(ColorScheme colorScheme, BranchModel branch) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.store_rounded, color: colorScheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      branch.branchName,
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        branch.retailChainName,
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    if (branch.branchCode.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          branch.branchCode,
                          style: GoogleFonts.cairo(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (branch.city.isNotEmpty || branch.address.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (branch.city.isNotEmpty) ...[
                        Icon(Icons.location_on_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 3),
                        Text(
                          branch.city,
                          style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                      if (branch.city.isNotEmpty && branch.address.isNotEmpty) ...[
                        Text(' • ', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                      ],
                      if (branch.address.isNotEmpty)
                        Expanded(
                          child: Text(
                            branch.address,
                            style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'تعديل الفرع',
            onPressed: () => _editBranch(branch),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, size: 18, color: colorScheme.error),
            tooltip: 'حذف الفرع',
            onPressed: () => _deleteBranch(branch),
          ),
        ],
      ),
    );
  }
}
