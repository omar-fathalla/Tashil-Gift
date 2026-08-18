import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/company_products_service.dart';
import '../../../core/services/company_gifts_service.dart';
import '../../../core/services/retail_chains_service.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/arabic_numbers_utils.dart';
import '../../../core/utils/slug_utils.dart';
import '../../../core/utils/url_builder.dart';
import '../../../core/constants/country_currency_config.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/services/campaign_ai_assistant_service.dart';
import '../domain/company_model.dart';
import '../domain/event_model.dart';
import '../domain/company_gift_model.dart';
import '../domain/retail_chain_model.dart';


class CreateEventScreen extends ConsumerStatefulWidget {
  final EventModel? eventToEdit;
  final VoidCallback? onCancel;
  final VoidCallback? onSaved;
  final bool isEmbedded;

  const CreateEventScreen({
    super.key,
    this.eventToEdit,
    this.onCancel,
    this.onSaved,
    this.isEmbedded = false,
  });

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _eventNameController;
  late final TextEditingController _targetCompanyController;
  late final TextEditingController _companySlugController;
  late final TextEditingController _minimumSpendController;
  late final TextEditingController _requiredProductsController;
  late final TextEditingController _customPromptController;
  late final TextEditingController _promotionalIdeaController;
  String _aiValidationSummary = '';
  List<PromotionalRuleItem> _promotionalRules = [];
  bool _isAiStructuringRules = false;
  late final TextEditingController _welcomeTitleController;
  late final TextEditingController _welcomeMessageController;
  late final TextEditingController _termsController;
  late final TextEditingController _maxChancesController;
  bool _allowMultipleChances = false;
  
  DateTime? _startDate;
  DateTime? _endDate;

  bool _isLoading = false;
  List<CompanyProductItem> _companyProducts = [];
  bool _isLoadingProducts = false;

  // Company Logo State
  String _companyLogoUrl = '';
  Uint8List? _pickedLogoBytes;
  String? _pickedLogoFileName;

  String _selectedGameType = 'wheel';
  List<CompanyGiftModel> _companyGifts = [];
  /// Branch-specific prize allocations: `Map<branchId, Map<giftId, quantity>>`
  final Map<String, Map<String, int>> _branchAllocationQuantities = {};
  String? _selectedAllocationBranchId;

  // Retail Chain & Branches State
  String? _selectedRetailChainId;
  String? _selectedRetailChainName;
  bool _isAllBranches = true;
  List<String> _selectedBranchIds = [];
  List<String> _selectedBranchNames = [];
  List<BranchModel> _availableBranches = [];
  bool _isLoadingBranches = false;

  @override
  void initState() {
    super.initState();
    final e = widget.eventToEdit;
    _eventNameController = TextEditingController(text: e?.eventName ?? '');
    _targetCompanyController = TextEditingController(text: e?.targetCompany ?? '');
    _companySlugController = TextEditingController(text: e?.companySlug ?? '');
    _companyLogoUrl = e?.companyLogoUrl ?? '';
    _minimumSpendController = TextEditingController(text: e?.minimumSpend.toString() ?? '');
    _requiredProductsController = TextEditingController(text: e?.requiredProducts.join(', ') ?? '');
    _allowMultipleChances = e?.allowMultipleChances ?? false;
    _maxChancesController = TextEditingController(
      text: (e?.maxChancesPerReceipt != null && e!.maxChancesPerReceipt > 0)
          ? e.maxChancesPerReceipt.toString()
          : '',
    );

    _startDate = e?.startDate;
    _endDate = e?.endDate;

    _selectedRetailChainId = e?.retailChainId.isNotEmpty == true ? e!.retailChainId : null;
    _selectedRetailChainName = e?.retailChainName;
    _isAllBranches = e?.isAllBranches ?? true;
    _selectedBranchIds = List<String>.from(e?.branchIds ?? []);
    _selectedBranchNames = List<String>.from(e?.branchNames ?? []);
    if (_selectedBranchIds.isNotEmpty) {
      _selectedAllocationBranchId = _selectedBranchIds.first;
    }
    
    _customPromptController = TextEditingController(
      text: e?.customPrompt ?? '''أنت مساعد ذكي متخصص في فحص فواتير السوبر ماركت الخاصة بعروض "{TARGET_COMPANY}".
قم بتحليل صورة الفاتورة المرفقة بدقة شديدة واستخرج البيانات التالية:
1. "رقم الفاتورة" (Receipt Number أو Transaction ID) مثل: 295/8/211/220726.
2. "تاريخ الفاتورة" (Receipt Date) مثل: 22/07/2026.
3. ابحث عن كافة الأصناف المشتراة، وقم بتصفيتها لتحديد المنتجات التابعة لشركة "{TARGET_COMPANY}" فقط.
4. قم بجمع أسعار منتجات "{TARGET_COMPANY}" فقط لتحصل على الإجمالي (targetCompanyTotal).

شروط الموافقة (isValid = true):
- يجب أن تكون الصورة لفاتورة حقيقية ومقروءة.
- يجب أن يكون "رقم الفاتورة" واضحاً وموجوداً.
- يجب أن تكون الفاتورة ضمن تاريخ سريان الفاعلية للحدث.
- يجب أن تحتوي الفاتورة على منتج واحد على الأقل من "{TARGET_COMPANY}".
- إجمالي المنتجات يجب أن يلبي الحد الأدنى {MIN_SPEND} جنيه.''',
    );
    
    _welcomeTitleController = TextEditingController(text: e?.welcomeTitle ?? 'عروض وحملات الشركات');
    _welcomeMessageController = TextEditingController(text: e?.welcomeMessage ?? 'قم برفع صورة فاتورة الشراء للحصول على فرص فوز فورية بأحد جوائزنا!');
    _termsController = TextEditingController(text: e?.termsAndConditions ?? 'الشروط والأحكام: الاحتفاظ بالفاتورة الأصلية عند الاستلام.');
    
    _promotionalIdeaController = TextEditingController(text: e?.promotionalIdea ?? '');
    _aiValidationSummary = e?.aiValidationSummary ?? '';
    _promotionalRules = List<PromotionalRuleItem>.from(e?.promotionalRules ?? []);

    if (e?.companySlug != null && e!.companySlug.isNotEmpty) {
      _loadCompanyProducts(e.companySlug);
      _loadCompanyGifts(e.companySlug);
      _loadCompanyLogo(e.companySlug);
    }

    if (_selectedRetailChainId != null && _selectedRetailChainId!.isNotEmpty) {
      _loadBranchesForChain(_selectedRetailChainId!);
    }

    _selectedGameType = e?.gameType ?? 'wheel';

    // Restore existing allocations when editing
    if (e != null) {
      for (final p in e.allocatedPrizes) {
        final bKey = p.branchId.isNotEmpty ? p.branchId : 'all';
        _branchAllocationQuantities.putIfAbsent(bKey, () => {})[p.giftId] = p.allocatedQuantity;
      }
    }
  }

  Future<void> _loadBranchesForChain(String chainId) async {
    if (chainId.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _availableBranches = [];
          _isLoadingBranches = false;
        });
      }
      return;
    }
    setState(() => _isLoadingBranches = true);
    try {
      final branches = await ref.read(retailChainsServiceProvider).getBranchesForChain(chainId);
      if (mounted) {
        setState(() {
          _availableBranches = branches;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isLoadingBranches = false);
      }
    }
  }

  Future<void> _showQuickAddChainDialog() async {
    final nameCtrl = TextEditingController();
    final slugCtrl = TextEditingController();
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final theme = Theme.of(ctx);
          final colorScheme = theme.colorScheme;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(Icons.add_business_rounded, color: colorScheme.primary),
                const SizedBox(width: 10),
                Text('إضافة سلسلة تجارية سريعة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'أدخل اسم السلسلة والكود المعرف لإضافتها فوراً واختيارها في هذه الحملة.',
                    style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'اسم السلسلة *',
                      hintText: 'مثال: أسواق فتح الله أو كارفور',
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (val) {
                      if (slugCtrl.text.isEmpty) {
                        slugCtrl.text = val.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: slugCtrl,
                    inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                    decoration: InputDecoration(
                      labelText: 'الكود المعرف (Slug) *',
                      hintText: 'مثال: fathalla أو carrefour',
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                onPressed: isSaving ? null : () async {
                  final name = nameCtrl.text.trim();
                  final slug = slugCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
                  if (name.isEmpty || slug.isEmpty) return;

                  setDialogState(() => isSaving = true);
                  try {
                    final chain = RetailChainModel(id: slug, name: name, slug: slug);
                    await ref.read(retailChainsServiceProvider).addRetailChain(chain);
                    if (mounted) {
                      setState(() {
                        _selectedRetailChainId = slug;
                        _selectedRetailChainName = name;
                        _selectedBranchIds = [];
                        _selectedBranchNames = [];
                      });
                      _loadBranchesForChain(slug);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: Colors.red),
                      );
                    }
                  } finally {
                    if (ctx.mounted) setDialogState(() => isSaving = false);
                  }
                },
                icon: isSaving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check, size: 16),
                label: const Text('إضافة واختيار'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showQuickAddBranchDialog() async {
    if (_selectedRetailChainId == null || _selectedRetailChainId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار السلسلة التجارية أولاً')),
      );
      return;
    }

    final branchNameCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final theme = Theme.of(ctx);
          final colorScheme = theme.colorScheme;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(Icons.add_location_alt_rounded, color: colorScheme.secondary),
                const SizedBox(width: 10),
                Text('إضافة فرع جديد لـ ($_selectedRetailChainName)', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: branchNameCtrl,
                    decoration: InputDecoration(
                      labelText: 'اسم الفرع *',
                      hintText: 'مثال: فرع الهانوفيل أو فرع سموحة',
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: cityCtrl,
                    decoration: InputDecoration(
                      labelText: 'المحافظة / المنطقة',
                      hintText: 'مثال: الإسكندرية (العجمي)',
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeCtrl,
                    inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                    decoration: InputDecoration(
                      labelText: 'كود الفرع (اختياري)',
                      hintText: 'مثال: FAT-HNF',
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                onPressed: isSaving ? null : () async {
                  final branchName = branchNameCtrl.text.trim();
                  if (branchName.isEmpty) return;

                  setDialogState(() => isSaving = true);
                  try {
                    final branch = BranchModel(
                      id: '',
                      retailChainId: _selectedRetailChainId!,
                      retailChainName: _selectedRetailChainName ?? '',
                      branchName: branchName,
                      city: cityCtrl.text.trim(),
                      branchCode: codeCtrl.text.trim(),
                    );
                    await ref.read(retailChainsServiceProvider).addBranch(branch);
                    if (mounted) {
                      await _loadBranchesForChain(_selectedRetailChainId!);
                      setState(() {
                        if (!_isAllBranches) {
                          _selectedBranchNames.add(branchName);
                        }
                      });
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: Colors.red),
                      );
                    }
                  } finally {
                    if (ctx.mounted) setDialogState(() => isSaving = false);
                  }
                },
                icon: isSaving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check, size: 16),
                label: const Text('إضافة الفرع'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _loadCompanyProducts(String slug) async {
    final cleanSlug = slug.trim().toLowerCase();
    if (cleanSlug.isEmpty) {
      if (mounted) {
        setState(() {
          _companyProducts = [];
        });
      }
      return;
    }
    setState(() => _isLoadingProducts = true);
    try {
      final productsService = ref.read(companyProductsServiceProvider);
      final items = await productsService.getProductsForCompany(cleanSlug);
      if (mounted) {
        setState(() {
          _companyProducts = items;
        });
      }
    } catch (_) {
      // Ignored
    } finally {
      if (mounted) {
        setState(() => _isLoadingProducts = false);
      }
    }
  }

  Future<void> _loadCompanyLogo(String slug) async {
    final cleanSlug = slug.trim().toLowerCase();
    if (cleanSlug.isEmpty) return;
    try {
      final firestore = ref.read(firestoreProvider);
      final query = await firestore.collection('companies').where('slug', isEqualTo: cleanSlug).limit(1).get();
      if (query.docs.isNotEmpty) {
        final comp = CompanyModel.fromFirestore(query.docs.first);
        if (mounted && _pickedLogoBytes == null && comp.logoUrl.isNotEmpty) {
          setState(() {
            _companyLogoUrl = comp.logoUrl;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _pickCompanyLogo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'svg'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          setState(() {
            _pickedLogoBytes = file.bytes;
            _pickedLogoFileName = file.name;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء اختيار اللوجو: ${AppErrorHandler.getFriendlyMessage(e)}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<String> _uploadLogoIfNeeded(String slug) async {
    if (_pickedLogoBytes == null) {
      return _companyLogoUrl;
    }

    try {
      final storage = ref.read(firebaseStorageProvider);
      final ext = _pickedLogoFileName != null && _pickedLogoFileName!.contains('.')
          ? _pickedLogoFileName!.split('.').last.toLowerCase()
          : 'png';

      final cleanSlug = slug.isNotEmpty ? slug : 'company';
      final storagePath = 'company_logos/${cleanSlug}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final storageRef = storage.ref().child(storagePath);

      final metadata = SettableMetadata(
        contentType: ext == 'png'
            ? 'image/png'
            : (ext == 'webp'
                ? 'image/webp'
                : (ext == 'svg' ? 'image/svg+xml' : 'image/jpeg')),
        customMetadata: {
          'companySlug': cleanSlug,
          'targetCompany': _targetCompanyController.text.trim(),
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );

      await storageRef.putData(_pickedLogoBytes!, metadata).timeout(const Duration(seconds: 15));
      final downloadUrl = await storageRef.getDownloadURL().timeout(const Duration(seconds: 10));

      // Also persist to Company document in Firestore so future events automatically have it
      if (cleanSlug.isNotEmpty) {
        final firestore = ref.read(firestoreProvider);
        final compQuery = await firestore.collection('companies').where('slug', isEqualTo: cleanSlug).limit(1).get();
        if (compQuery.docs.isNotEmpty) {
          await compQuery.docs.first.reference.update({'logoUrl': downloadUrl});
        }
      }

      return downloadUrl;
    } catch (e) {
      debugPrint('Error uploading company logo: $e');
      return _companyLogoUrl;
    }
  }

  List<String> get _selectedProductNames {
    final text = _requiredProductsController.text.trim();
    if (text.isEmpty) return [];
    return text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  void _toggleProductSelection(String productName) {
    final current = List<String>.from(_selectedProductNames);
    if (current.contains(productName)) {
      current.remove(productName);
    } else {
      current.add(productName);
    }
    setState(() {
      _requiredProductsController.text = current.join(', ');
    });
  }

  void _clearSelectedProducts() {
    setState(() {
      _requiredProductsController.clear();
    });
  }

  Future<void> _showProductSelectorDialog() async {
    final colorScheme = Theme.of(context).colorScheme;
    if (_companyProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لا توجد منتجات مسجلة في كتالوج هذه الشركة حالياً.', style: GoogleFonts.cairo()),
          backgroundColor: colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final selectedSet = Set<String>.from(_selectedProductNames);
    String searchQuery = '';

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredProducts = _companyProducts.where((p) {
              if (searchQuery.trim().isEmpty) return true;
              final q = searchQuery.toLowerCase();
              return p.productName.toLowerCase().contains(q) || p.barcode.toLowerCase().contains(q);
            }).toList();

            final allFilteredSelected = filteredProducts.isNotEmpty &&
                filteredProducts.every((p) => selectedSet.contains(p.productName));

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: colorScheme.surface,
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              actionsPadding: const EdgeInsets.all(16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.tune_rounded, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تخصيص منتجات العرض من الكتالوج',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'حدد الأصناف المستهدفة فقط إذا كنت تريد حصر الحملة في منتجات معينة',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 600,
                height: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    TextFormField(
                      style: GoogleFonts.cairo(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'ابحث باسم المنتج أو الباركود...',
                        hintStyle: GoogleFonts.cairo(fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  setDialogState(() => searchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) {
                        setDialogState(() => searchQuery = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: selectedSet.isNotEmpty
                                ? colorScheme.primaryContainer
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            selectedSet.isEmpty
                                ? 'الوضع الافتراضي (كافة المنتجات)'
                                : 'محدد ${selectedSet.length} من أصل ${_companyProducts.length}',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: selectedSet.isNotEmpty
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: Icon(
                            allFilteredSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                            size: 16,
                          ),
                          label: Text(
                            allFilteredSelected ? 'إلغاء تحديد المعروض' : 'تحديد المعروض (${filteredProducts.length})',
                            style: GoogleFonts.cairo(fontSize: 12),
                          ),
                          onPressed: () {
                            setDialogState(() {
                              if (allFilteredSelected) {
                                for (final p in filteredProducts) {
                                  selectedSet.remove(p.productName);
                                }
                              } else {
                                for (final p in filteredProducts) {
                                  if (p.productName.isNotEmpty) {
                                    selectedSet.add(p.productName);
                                  }
                                }
                              }
                            });
                          },
                        ),
                        const SizedBox(width: 6),
                        if (selectedSet.isNotEmpty)
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'إلغاء التحديد',
                              style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.error),
                            ),
                            onPressed: () {
                              setDialogState(() => selectedSet.clear());
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    Expanded(
                      child: filteredProducts.isEmpty
                          ? Center(
                              child: Text(
                                'لا توجد منتجات مطابقة للبحث.',
                                style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filteredProducts.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = filteredProducts[index];
                                final isSelected = selectedSet.contains(item.productName);
                                return CheckboxListTile(
                                  value: isSelected,
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  title: Text(
                                    item.productName,
                                    style: GoogleFonts.cairo(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                                      fontSize: 13,
                                    ),
                                  ),
                                  subtitle: item.barcode.isNotEmpty
                                      ? Row(
                                          children: [
                                            Icon(Icons.qr_code_2_rounded, size: 14, color: colorScheme.primary),
                                            const SizedBox(width: 4),
                                            Text(
                                              item.barcode,
                                              style: GoogleFonts.robotoMono(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        )
                                      : null,
                                  activeColor: colorScheme.primary,
                                  checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  onChanged: (bool? checked) {
                                    setDialogState(() {
                                      if (checked == true) {
                                        selectedSet.add(item.productName);
                                      } else {
                                        selectedSet.remove(item.productName);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('إلغاء', style: GoogleFonts.cairo()),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    selectedSet.isEmpty || selectedSet.length == _companyProducts.length
                        ? 'تضمين كافة المنتجات تلقائياً'
                        : 'تأكيد تخصيص (${selectedSet.length} صنف)',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    setState(() {
                      if (selectedSet.isEmpty || selectedSet.length == _companyProducts.length) {
                        _requiredProductsController.clear();
                      } else {
                        _requiredProductsController.text = selectedSet.join(', ');
                      }
                    });
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _loadCompanyGifts(String slug) async {
    if (slug.trim().isEmpty) return;
    final giftsService = ref.read(companyGiftsServiceProvider);
    final gifts = await giftsService.getGiftsForCompany(
      slug,
      excludeEventId: widget.eventToEdit?.id,
    );
    if (mounted) {
      setState(() => _companyGifts = gifts);
    }
  }

  int _getAllocatedInOtherBranches(String giftId, String currentBranchId) {
    int sum = 0;
    _branchAllocationQuantities.forEach((bId, gifts) {
      if (bId != currentBranchId && (_isAllBranches || _selectedBranchIds.contains(bId))) {
        sum += gifts[giftId] ?? 0;
      }
    });
    return sum;
  }

  int _getTotalAllocatedForGift(String giftId) {
    int sum = 0;
    if (_isAllBranches || _selectedBranchIds.isEmpty) {
      sum = _branchAllocationQuantities['all']?[giftId] ?? 0;
    } else {
      for (final bId in _selectedBranchIds) {
        sum += _branchAllocationQuantities[bId]?[giftId] ?? 0;
      }
    }
    return sum;
  }

  int _getTotalAllocatedUnits() {
    int sum = 0;
    if (_isAllBranches || _selectedBranchIds.isEmpty) {
      _branchAllocationQuantities['all']?.forEach((_, qty) => sum += qty);
    } else {
      for (final bId in _selectedBranchIds) {
        _branchAllocationQuantities[bId]?.forEach((_, qty) => sum += qty);
      }
    }
    return sum;
  }

  int _getBranchAllocatedUnits(String branchId) {
    int sum = 0;
    _branchAllocationQuantities[branchId]?.forEach((_, qty) => sum += qty);
    return sum;
  }

  void _distributeEvenlyAcrossBranches() {
    if (_selectedBranchIds.isEmpty || _companyGifts.isEmpty) return;
    setState(() {
      for (final gift in _companyGifts) {
        final share = gift.availableQuantity ~/ _selectedBranchIds.length;
        for (final bId in _selectedBranchIds) {
          _branchAllocationQuantities.putIfAbsent(bId, () => {})[gift.id] = share;
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم توزيع المخزون المتاح بالتساوي على ${_selectedBranchIds.length} فرع.', style: GoogleFonts.cairo()),
        backgroundColor: Colors.green.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _clearBranchAllocations(String branchId) {
    setState(() {
      _branchAllocationQuantities[branchId]?.clear();
    });
  }

  @override
  void dispose() {
    _eventNameController.dispose();
    _targetCompanyController.dispose();
    _companySlugController.dispose();
    _minimumSpendController.dispose();
    _requiredProductsController.dispose();
    _customPromptController.dispose();
    _promotionalIdeaController.dispose();
    _welcomeTitleController.dispose();
    _welcomeMessageController.dispose();
    _termsController.dispose();
    _maxChancesController.dispose();
    super.dispose();
  }

  void _updatePromptForMultipleChances(bool enabled) {
    String currentPrompt = _customPromptController.text;
    const String clauseHeader = '- مضاعفة فرص السحب واللعب:';
    
    if (enabled) {
      if (!currentPrompt.contains(clauseHeader)) {
        final minSpendText = _minimumSpendController.text.trim().isNotEmpty
            ? _minimumSpendController.text.trim()
            : '{MIN_SPEND}';
        final addedClause = '\n$clauseHeader الحد الأدنى المطلوب هو $minSpendText جنيه. كل مضاعف لهذا المبلغ من منتجات الشركة يمنح العميل فرصة سحب إضافية (مثال: ضعف المبلغ = فرصتان، 3 أضعاف = 3 فرص).';
        _customPromptController.text = '$currentPrompt$addedClause';
      }
    } else {
      _customPromptController.text = currentPrompt
          .replaceAll(RegExp(r'\n?- مضاعفة فرص السحب واللعب:[^\n]+'), '')
          .trim();
    }
  }

  Future<void> _structureCampaignWithAi() async {
    final ideaText = _promotionalIdeaController.text.trim();
    if (ideaText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(ref).aiCampaignIdeaHint),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _isAiStructuringRules = true);

    try {
      final targetCompany = _targetCompanyController.text.trim().isNotEmpty
          ? _targetCompanyController.text.trim()
          : 'الشركة المستهدفة';
      final minSpend = _minimumSpendController.text.trim().toDoubleOrNull() ?? 0.0;

      final result = await ref.read(campaignAiAssistantServiceProvider).structureCampaignIdea(
        targetCompany: targetCompany,
        rawIdeaText: ideaText,
        existingPrompt: _customPromptController.text.trim(),
        minimumSpend: minSpend,
      );

      if (!mounted) return;

      setState(() {
        _aiValidationSummary = result.aiValidationSummary;
        _promotionalRules = result.rules;
        if (result.formattedSystemPrompt.isNotEmpty) {
          _customPromptController.text = result.formattedSystemPrompt;
        }

        if (result.suggestedRequiredProducts.isNotEmpty) {
          final currentProducts = _requiredProductsController.text.trim();
          if (currentProducts.isEmpty) {
            _requiredProductsController.text = result.suggestedRequiredProducts.join(', ');
          }
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✨ تم تحليل وهيكلة قواعد العرض وتحديث البرومبت بنجاح!'),
          backgroundColor: Colors.teal.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'فشل تحليل شروط العرض بالذكاء الاصطناعي')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAiStructuringRules = false);
      }
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final initialDate = isStart 
        ? (_startDate ?? DateTime.now()) 
        : (_endDate ?? DateTime.now().add(const Duration(days: 30)));
        
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      helpText: isStart ? 'اختر تاريخ بداية الحملة' : 'اختر تاريخ نهاية الحملة',
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _saveEvent() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      final firestore = ref.read(firestoreProvider);
      
      final productsText = _requiredProductsController.text.trim();
      final productsList = productsText.isNotEmpty 
          ? productsText.split(',').map((e) => e.trim()).toList() 
          : <String>[];

      final rawSlug = _companySlugController.text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');

      // Upload company logo to Firebase Storage if a new one was picked
      final finalLogoUrl = await _uploadLogoIfNeeded(rawSlug);

      final event = EventModel(
        id: widget.eventToEdit?.id ?? '',
        eventName: _eventNameController.text.trim(),
        targetCompany: _targetCompanyController.text.trim(),
        companySlug: rawSlug.isNotEmpty ? rawSlug : _targetCompanyController.text.trim().toLowerCase(),
        companyLogoUrl: finalLogoUrl,
        minimumSpend: _minimumSpendController.text.trim().toDoubleOrNull() ?? 0,
        requiredProducts: productsList,
        customPrompt: _customPromptController.text.trim(),
        welcomeTitle: _welcomeTitleController.text.trim(),
        welcomeMessage: _welcomeMessageController.text.trim(),
        termsAndConditions: _termsController.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
        isActive: widget.eventToEdit?.isActive ?? true,
        gameType: _selectedGameType,
        allocatedPrizes: () {
          final List<AllocatedPrize> prizes = [];
          if (_isAllBranches || _selectedBranchIds.isEmpty) {
            final allAllocations = _branchAllocationQuantities['all'] ?? {};
            for (final entry in allAllocations.entries) {
              if (entry.value > 0) {
                final gift = _companyGifts.firstWhere(
                  (g) => g.id == entry.key,
                  orElse: () => CompanyGiftModel(id: entry.key, companySlug: '', giftName: entry.key, totalQuantity: 0, availableQuantity: 0),
                );
                prizes.add(AllocatedPrize(
                  giftId: entry.key,
                  name: gift.giftName,
                  allocatedQuantity: entry.value,
                  remainingQuantity: entry.value,
                  branchId: '',
                  branchName: '',
                ));
              }
            }
          } else {
            for (int i = 0; i < _selectedBranchIds.length; i++) {
              final bId = _selectedBranchIds[i];
              final bName = i < _selectedBranchNames.length ? _selectedBranchNames[i] : bId;
              final bAllocations = _branchAllocationQuantities[bId] ?? {};
              for (final entry in bAllocations.entries) {
                if (entry.value > 0) {
                  final gift = _companyGifts.firstWhere(
                    (g) => g.id == entry.key,
                    orElse: () => CompanyGiftModel(id: entry.key, companySlug: '', giftName: entry.key, totalQuantity: 0, availableQuantity: 0),
                  );
                  prizes.add(AllocatedPrize(
                    giftId: entry.key,
                    name: gift.giftName,
                    allocatedQuantity: entry.value,
                    remainingQuantity: entry.value,
                    branchId: bId,
                    branchName: bName,
                  ));
                }
              }
            }
          }
          return prizes;
        }(),
        retailChainId: _selectedRetailChainId ?? '',
        retailChainName: _selectedRetailChainName ?? '',
        branchIds: _isAllBranches ? [] : _selectedBranchIds,
        branchNames: _isAllBranches ? [] : _selectedBranchNames,
        isAllBranches: _isAllBranches,
        allowMultipleChances: _allowMultipleChances,
        maxChancesPerReceipt: _maxChancesController.text.trim().toIntOrNull() ?? 0,
        promotionalIdea: _promotionalIdeaController.text.trim(),
        aiValidationSummary: _aiValidationSummary.trim(),
        promotionalRules: _promotionalRules,
      );

      String createdEventId = widget.eventToEdit?.id ?? '';
      if (widget.eventToEdit == null) {
        final docRef = await firestore.collection('events').add(event.toFirestore()).timeout(
          const Duration(seconds: 5),
          onTimeout: () => firestore.collection('events').doc(),
        );
        createdEventId = docRef.id;
      } else {
        await firestore.collection('events').doc(widget.eventToEdit!.id).update(event.toFirestore()).timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );
      }

      // Synchronize company master inventory in Firestore
      await ref.read(companyGiftsServiceProvider).syncCompanyGiftsAvailableQuantities(event.companySlug);

      if (mounted) {
        await _showCampaignSuccessLinksDialog(context, event, createdEventId);
        if (!mounted) return;
        if (widget.onSaved != null) {
          widget.onSaved!();
        } else if (Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء حفظ الحملة')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showCampaignSuccessLinksDialog(
    BuildContext context,
    EventModel event,
    String eventId,
  ) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isAr = ref.isArabic;
    final promoterUrl = AppUrlBuilder.buildPromoterUrl(event.companySlug, eventId: eventId);
    final managerUrl = AppUrlBuilder.buildManagerPortalUrl(event.companySlug, eventId: eventId);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_rounded, color: Colors.green.shade800, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isAr ? 'تم نشر وتفعيل الحملة على الفايربيس!' : 'Campaign Live on Firebase!',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr
                      ? 'تم توليد الروابط المباشرة للحملة بنجاح باسم إنجليزي فريد (${event.companySlug}). يمكنك نسخ الروابط أدناه وبدء الفحص والتشغيل من أي مكان:'
                      : 'Live campaign URLs generated with unique English slug (${event.companySlug}). You can copy the links below:',
                  style: GoogleFonts.cairo(fontSize: 13, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                // Promoter Link Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.campaign_rounded, size: 18, color: Colors.teal.shade800),
                          const SizedBox(width: 6),
                          Text(
                            isAr ? 'رابط البروموتر والعميل (Client Submission):' : 'Promoter & Client Link:',
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.teal.shade900),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        promoterUrl,
                        style: GoogleFonts.sourceCodePro(fontSize: 12, color: Colors.teal.shade900, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FilledButton.tonalIcon(
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: Text(isAr ? 'نسخ رابط البروموتر' : 'Copy Promoter Link', style: GoogleFonts.cairo(fontSize: 12)),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: promoterUrl));
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(isAr ? 'تم نسخ رابط البروموتر بنجاح!' : 'Promoter Link Copied!'),
                                backgroundColor: Colors.teal.shade700,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Company Manager Portal Link Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.indigo.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.storefront_rounded, size: 18, color: Colors.indigo.shade800),
                          const SizedBox(width: 6),
                          Text(
                            isAr ? 'رابط لوحة مدير وشريك الشركة (Partner Portal):' : 'Company Manager Portal Link:',
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo.shade900),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        managerUrl,
                        style: GoogleFonts.sourceCodePro(fontSize: 12, color: Colors.indigo.shade900, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FilledButton.tonalIcon(
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: Text(isAr ? 'نسخ رابط لوحة المدير' : 'Copy Manager Link', style: GoogleFonts.cairo(fontSize: 12)),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: managerUrl));
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(isAr ? 'تم نسخ رابط لوحة المدير بنجاح!' : 'Manager Portal Link Copied!'),
                                backgroundColor: Colors.indigo.shade700,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(isAr ? 'تم ومتابعة' : 'Done & Continue', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  InputDecoration _m3InputDecoration({
    required BuildContext context,
    required String labelText,
    String? hintText,
    String? helperText,
    IconData? prefixIcon,
    Widget? suffixIcon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: labelText,
      labelStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant, fontSize: 14),
      hintText: hintText,
      hintStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 13),
      helperText: helperText,
      helperStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8), fontSize: 11),
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: colorScheme.primary, size: 20) : null,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }


  @override
  Widget build(BuildContext context) {
    final isEditing = widget.eventToEdit != null;
    final isAr = ref.isArabic;
    final strings = AppStrings.of(ref);
    final title = isEditing ? (isAr ? 'تعديل الحملة وتخصيص الـ AI' : 'Edit Campaign & AI Config') : strings.createCampaignTitle;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (widget.isEmbedded) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
            child: Row(
              children: [
                if (widget.onCancel != null)
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: colorScheme.primary),
                    tooltip: isAr ? 'إلغاء والعودة للوحة التحكم' : 'Cancel & Return to Dashboard',
                    onPressed: widget.onCancel,
                  ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.campaign_rounded, color: colorScheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                if (isEditing)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isAr ? 'وضع التعديل' : 'Edit Mode',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _buildFormBody(isEditing)),
        ],
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(title, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: _buildFormBody(isEditing),
    );
  }

  Widget _buildFormBody(bool isEditing) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeCountry = ref.watch(activeCountryProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 650;
    final strings = AppStrings.of(ref);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Section 1: Basic Campaign Info
                _buildSectionCard(
                  context: context,
                  icon: Icons.info_outline_rounded,
                  title: 'البيانات الأساسية للحملة',
                  subtitle: 'حدد اسم الحملة، الشركة المستهدفة، وشروط الإنفاق',
                  children: [
                    TextFormField(
                      controller: _eventNameController,
                      style: GoogleFonts.cairo(),
                      decoration: _m3InputDecoration(
                        context: context,
                        labelText: 'اسم الحملة (مثال: عروض الصيف للمراعي)',
                        prefixIcon: Icons.edit_note_rounded,
                      ),
                      validator: (value) => value == null || value.isEmpty ? 'اسم الحملة مطلوب' : null,
                      onChanged: (val) {
                        if (_companySlugController.text.isEmpty && _targetCompanyController.text.isEmpty) {
                          final auto = SlugUtils.generateEnglishSlug(val);
                          setState(() => _companySlugController.text = auto);
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Company Selection Dropdown from Coded Catalog
                    StreamBuilder<QuerySnapshot>(
                      stream: ref.watch(firestoreProvider).collection('companies').snapshots(),
                      builder: (context, snapshot) {
                        final docs = snapshot.data?.docs ?? [];
                        final companies = docs.map((d) => CompanyModel.fromFirestore(d)).toList();

                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.primary.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.business_center_rounded, color: colorScheme.primary, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'اختيار الشركة المكوّدة (من القائمة المنسدلة):',
                                    style: GoogleFonts.cairo(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (companies.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${companies.length} شركة مكوّدة',
                                        style: GoogleFonts.cairo(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (companies.isNotEmpty)
                                DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  itemHeight: kMinInteractiveDimension,
                                  menuMaxHeight: 300,
                                  key: ValueKey('create_event_dropdown_${_companySlugController.text}_${companies.length}'),
                                  initialValue: companies.any((c) => c.slug == _companySlugController.text)
                                      ? _companySlugController.text
                                      : null,
                                  style: GoogleFonts.cairo(color: colorScheme.onSurface),
                                  decoration: _m3InputDecoration(
                                    context: context,
                                    labelText: 'اختر الشركة من القائمة المنسدلة',
                                    prefixIcon: Icons.domain_rounded,
                                  ),
                                  items: companies.map((comp) {
                                    return DropdownMenuItem<String>(
                                      value: comp.slug,
                                      child: Text(
                                        '${comp.name} (${comp.slug})',
                                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (selectedSlug) {
                                    if (selectedSlug != null) {
                                      final comp = companies.firstWhere((c) => c.slug == selectedSlug);
                                      setState(() {
                                        _targetCompanyController.text = comp.name;
                                        _companySlugController.text = comp.slug;
                                        if (_pickedLogoBytes == null && comp.logoUrl.isNotEmpty) {
                                          _companyLogoUrl = comp.logoUrl;
                                        }
                                      });
                                      _loadCompanyProducts(comp.slug);
                                      _loadCompanyGifts(comp.slug);
                                      _loadCompanyLogo(comp.slug);
                                    }
                                  },
                                )
                              else
                                Text(
                                  'لا توجد شركات مكوّدة بعد في النظام. يمكنك إدخال اسم الشركة يدوياً أدناه أو الذهاب إلى شاشة "تكويد الشركات".',
                                  style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                ),
                              const SizedBox(height: 14),
                              Flex(
                                direction: isMobile ? Axis.vertical : Axis.horizontal,
                                children: [
                                  Expanded(
                                    flex: isMobile ? 0 : 1,
                                    child: TextFormField(
                                      controller: _targetCompanyController,
                                      style: GoogleFonts.cairo(),
                                      decoration: _m3InputDecoration(
                                        context: context,
                                        labelText: 'اسم الشركة المستهدفة',
                                        prefixIcon: Icons.storefront_rounded,
                                      ),
                                      validator: (value) => value == null || value.isEmpty ? 'مطلوب' : null,
                                      onChanged: (val) {
                                        if (_companySlugController.text.isEmpty) {
                                          final auto = SlugUtils.generateEnglishSlug(val);
                                          setState(() => _companySlugController.text = auto);
                                        }
                                      },
                                    ),
                                  ),
                                  if (isMobile) const SizedBox(height: 12) else const SizedBox(width: 14),
                                  Expanded(
                                    flex: isMobile ? 0 : 1,
                                    child: TextFormField(
                                      controller: _companySlugController,
                                      style: GoogleFonts.cairo(),
                                      decoration: _m3InputDecoration(
                                        context: context,
                                        labelText: 'معرف الرابط الإنجليزي (English Slug)',
                                        hintText: 'مثال: almarai أو summer-promo',
                                        helperText: 'يحدد الرابط في الفايربيس: /c/${_companySlugController.text.isNotEmpty ? _companySlugController.text : 'slug'}',
                                        prefixIcon: Icons.link_rounded,
                                        suffixIcon: IconButton(
                                          icon: Icon(Icons.auto_awesome_rounded, color: colorScheme.primary, size: 20),
                                          tooltip: 'توليد المعرف الإنجليزي تلقائياً من الاسم',
                                          onPressed: () {
                                            final text = _targetCompanyController.text.isNotEmpty
                                                ? _targetCompanyController.text
                                                : _eventNameController.text;
                                            final auto = SlugUtils.generateEnglishSlug(text);
                                            setState(() => _companySlugController.text = auto);
                                            _loadCompanyProducts(auto);
                                          },
                                        ),
                                      ),
                                      onChanged: (val) {
                                        setState(() {});
                                        _loadCompanyProducts(val.trim().toLowerCase());
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Live Firebase URLs Preview
                              Builder(
                                builder: (context) {
                                  final currentSlug = _companySlugController.text.trim().isNotEmpty
                                      ? _companySlugController.text.trim().toLowerCase()
                                      : 'campaign';
                                  final promoterUrl = AppUrlBuilder.buildPromoterUrl(currentSlug);
                                  final managerUrl = AppUrlBuilder.buildManagerPortalUrl(currentSlug);

                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.cloud_done_rounded, size: 16, color: colorScheme.primary),
                                            const SizedBox(width: 6),
                                            Text(
                                              'معاينة روابط الفايربيس الحية (Firebase Web URLs):',
                                              style: GoogleFonts.cairo(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                color: colorScheme.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Icon(Icons.campaign_rounded, size: 15, color: Colors.teal.shade700),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'البروموتر: $promoterUrl',
                                                style: GoogleFonts.sourceCodePro(fontSize: 11, color: Colors.teal.shade900),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            InkWell(
                                              onTap: () {
                                                Clipboard.setData(ClipboardData(text: promoterUrl));
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('تم نسخ رابط البروموتر: $promoterUrl'),
                                                    backgroundColor: Colors.teal.shade700,
                                                    behavior: SnackBarBehavior.floating,
                                                  ),
                                                );
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                child: Icon(Icons.copy_rounded, size: 14, color: Colors.teal.shade700),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(Icons.storefront_rounded, size: 15, color: Colors.indigo.shade700),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'لوحة المدير: $managerUrl',
                                                style: GoogleFonts.sourceCodePro(fontSize: 11, color: Colors.indigo.shade900),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            InkWell(
                                              onTap: () {
                                                Clipboard.setData(ClipboardData(text: managerUrl));
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('تم نسخ رابط لوحة المدير: $managerUrl'),
                                                    backgroundColor: Colors.indigo.shade700,
                                                    behavior: SnackBarBehavior.floating,
                                                  ),
                                                );
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                child: Icon(Icons.copy_rounded, size: 14, color: Colors.indigo.shade700),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Flex(
                      direction: isMobile ? Axis.vertical : Axis.horizontal,
                      children: [
                        Expanded(
                          flex: isMobile ? 0 : 1,
                          child: TextFormField(
                            controller: _minimumSpendController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [const ArabicToEnglishDigitsFormatter.decimal()],
                            style: GoogleFonts.cairo(),
                            decoration: _m3InputDecoration(
                              context: context,
                              labelText: 'الحد الأدنى للشراء (${activeCountry.currencySymbol})',
                              prefixIcon: Icons.payments_outlined,
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'مطلوب';
                              if (value.toDoubleOrNull() == null) return 'رقم غير صحيح';
                              return null;
                            },
                          ),
                        ),
                        if (isMobile) const SizedBox(height: 12) else const SizedBox(width: 14),
                        Expanded(
                          flex: isMobile ? 0 : 1,
                          child: TextFormField(
                            controller: _requiredProductsController,
                            style: GoogleFonts.cairo(),
                            decoration: _m3InputDecoration(
                              context: context,
                              labelText: 'تخصيص منتجات معينة (اختياري)',
                              hintText: 'اتركه فارغاً لتضمين كافة منتجات الشركة تلقائياً',
                              helperText: _selectedProductNames.isEmpty
                                  ? 'الوضع الافتراضي: كافة منتجات الشركة مشمولة'
                                  : 'محدد ${_selectedProductNames.length} صنف مخصص',
                              prefixIcon: Icons.shopping_basket_outlined,
                            ),
                          ),
                        ),
                      ],
                    ),
                    _buildProductSelectorSection(context, colorScheme, isMobile),
                    _buildMultipleChancesSection(context, colorScheme, isMobile, activeCountry),
                  ],
                ),

                const SizedBox(height: 20),

                // Section 2: Date range selectors
                _buildSectionCard(
                  context: context,
                  icon: Icons.calendar_month_rounded,
                  title: 'فترة سريان الحملة',
                  subtitle: 'حدد تاريخ بداية ونهاية سريان الحملة للتحقق من الفواتير',
                  children: [
                    Flex(
                      direction: isMobile ? Axis.vertical : Axis.horizontal,
                      children: [
                        Expanded(
                          flex: isMobile ? 0 : 1,
                          child: OutlinedButton.icon(
                            onPressed: () => _pickDate(true),
                            icon: Icon(Icons.date_range_rounded, color: colorScheme.primary),
                            label: Text(
                              _startDate == null 
                                  ? 'تاريخ البداية: غير محدد' 
                                  : 'البداية: ${_startDate!.day}/${_startDate!.month}/${_startDate!.year}',
                              style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              side: BorderSide(
                                color: _startDate != null ? colorScheme.primary : colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                        ),
                        if (isMobile) const SizedBox(height: 12) else const SizedBox(width: 14),
                        Expanded(
                          flex: isMobile ? 0 : 1,
                          child: OutlinedButton.icon(
                            onPressed: () => _pickDate(false),
                            icon: Icon(Icons.event_busy_rounded, color: colorScheme.primary),
                            label: Text(
                              _endDate == null 
                                  ? 'تاريخ النهاية: غير محدد' 
                                  : 'النهاية: ${_endDate!.day}/${_endDate!.month}/${_endDate!.year}',
                              style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              side: BorderSide(
                                color: _endDate != null ? colorScheme.primary : colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Section 3: Game Type Selection
                _buildSectionCard(
                  context: context,
                  icon: Icons.casino_rounded,
                  title: 'نوع اللعبة (Game Type)',
                  subtitle: 'اختر نوع اللعبة التي ستظهر للعميل بعد التحقق من الفاتورة بنجاح',
                  children: [
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _selectedGameType,
                      style: GoogleFonts.cairo(color: colorScheme.onSurface),
                      decoration: _m3InputDecoration(
                        context: context,
                        labelText: 'اختر نوع اللعبة',
                        prefixIcon: Icons.videogame_asset_rounded,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'wheel',
                          child: Row(
                            children: [
                              Icon(Icons.casino_rounded, color: colorScheme.primary, size: 20),
                              const SizedBox(width: 10),
                              Text('عجلة الحظ (Spin the Wheel)', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'scratch',
                          child: Row(
                            children: [
                              Icon(Icons.style_rounded, color: colorScheme.primary, size: 20),
                              const SizedBox(width: 10),
                              Text('امسح واربح (Scratch & Win)', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'directGift',
                          child: Row(
                            children: [
                              Icon(Icons.redeem_rounded, color: colorScheme.secondary, size: 20),
                              const SizedBox(width: 10),
                              Text('هدية فورية مباشرة (Direct Instant Gift)', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedGameType = value);
                        }
                      },
                    ),
                    if (_selectedGameType == 'directGift') ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded, color: colorScheme.secondary, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'في نمط الهدية الفورية المباشرة: لن يتم إظهار سحب عشوائي للعميل، بل سيحصل فوراً على الهدية المخصصة للحملة بعد تدقيق الفاتورة. تأكد من تخصيص الهدية المطلوبة في قسم تخصيص الهدايا أدناه.',
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  color: colorScheme.onSecondaryContainer,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 20),

                // Section 4: Target Retail Chain and Outlets / Branches
                _buildRetailChainSection(context, colorScheme, isMobile),

                const SizedBox(height: 20),

                // Section 5: Prize Allocation from Company Inventory (Branch-Specific)
                _buildPrizeAllocationSection(context, colorScheme, isMobile),

                const SizedBox(height: 20),

                // Section 6: AI Campaign Idea & Rules Assistant (Smart Prompt Generator)
                _buildAiCampaignAssistantSection(context, colorScheme, isMobile, strings),

                const SizedBox(height: 20),

                // Section 7: AI Prompt Editor
                _buildSectionCard(
                  context: context,
                  icon: Icons.psychology_rounded,
                  title: 'محرر البرومبت للذكاء الاصطناعي (AI Prompt)',
                  subtitle: 'تعليمات الفحص والتدقيق الموجهة لموديل الذكاء الاصطناعي لفحص الفاتورة بدقة',
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildVariableChip(context, '{TARGET_COMPANY}', 'اسم الشركة المستهدفة'),
                        _buildVariableChip(context, '{MIN_SPEND}', 'الحد الأدنى للإنفاق'),
                        _buildVariableChip(context, '{REQUIRED_PRODUCTS}', 'المنتجات المشترطة'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: TextFormField(
                        controller: _customPromptController,
                        maxLines: 11,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13.5,
                          height: 1.5,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.all(8),
                        ),
                        validator: (value) => value == null || value.isEmpty ? 'البرومبت مطلوب' : null,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Section 5: Client Portal Settings & Terms
                _buildSectionCard(
                  context: context,
                  icon: Icons.language_rounded,
                  title: 'إعدادات واجهة العميل والشروط',
                  subtitle: 'النصوص والشروط وشعار الشركة التي تظهر للمستهلك في رابط الشركة المستهدفة',
                  children: [
                    // Company Logo Upload & Preview Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: (_pickedLogoBytes != null || _companyLogoUrl.isNotEmpty)
                              ? colorScheme.primary.withValues(alpha: 0.4)
                              : colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Logo preview container
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.8),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _pickedLogoBytes != null
                                ? Image.memory(
                                    _pickedLogoBytes!,
                                    fit: BoxFit.contain,
                                  )
                                : (_companyLogoUrl.isNotEmpty
                                    ? Image.network(
                                        _companyLogoUrl,
                                        fit: BoxFit.contain,
                                        errorBuilder: (context, error, stackTrace) => Icon(
                                          Icons.business_rounded,
                                          size: 38,
                                          color: colorScheme.primary,
                                        ),
                                      )
                                    : Icon(
                                        Icons.add_photo_alternate_rounded,
                                        size: 38,
                                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                      )),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'شعار / لوجو الشركة',
                                      style: GoogleFonts.cairo(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    if (_pickedLogoBytes != null) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade100,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.green.shade400),
                                        ),
                                        child: Text(
                                          'جاهز للرفع والتخزين',
                                          style: GoogleFonts.cairo(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green.shade800,
                                          ),
                                        ),
                                      ),
                                    ] else if (_companyLogoUrl.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'محفوظ سحابياً',
                                          style: GoogleFonts.cairo(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'يتم تخزين اللوجو سحابياً في Firebase Storage ليظهر دائماً للمستهلك والبروموتر في واجهة الفعالية.',
                                  style: GoogleFonts.cairo(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    FilledButton.tonalIcon(
                                      onPressed: _pickCompanyLogo,
                                      icon: const Icon(Icons.cloud_upload_rounded, size: 16),
                                      label: Text(
                                        (_pickedLogoBytes != null || _companyLogoUrl.isNotEmpty)
                                            ? 'تغيير صورة اللوجو'
                                            : 'رفع لوجو الشركة (PNG / JPG / WebP)',
                                        style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                    if (_pickedLogoBytes != null || _companyLogoUrl.isNotEmpty)
                                      OutlinedButton.icon(
                                        onPressed: () {
                                          setState(() {
                                            _pickedLogoBytes = null;
                                            _pickedLogoFileName = null;
                                            _companyLogoUrl = '';
                                          });
                                        },
                                        icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red),
                                        label: Text(
                                          'إزالة اللوجو',
                                          style: GoogleFonts.cairo(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(color: Colors.red.withValues(alpha: 0.4)),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                    TextFormField(
                      controller: _welcomeTitleController,
                      style: GoogleFonts.cairo(),
                      decoration: _m3InputDecoration(
                        context: context,
                        labelText: 'عنوان الصفحة للعميل',
                        prefixIcon: Icons.title_rounded,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _welcomeMessageController,
                      maxLines: 2,
                      style: GoogleFonts.cairo(),
                      decoration: _m3InputDecoration(
                        context: context,
                        labelText: 'رسالة الترحيب والتعليمات للعميل',
                        prefixIcon: Icons.chat_bubble_outline_rounded,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _termsController,
                      maxLines: 2,
                      style: GoogleFonts.cairo(),
                      decoration: _m3InputDecoration(
                        context: context,
                        labelText: 'الشروط والأحكام الخاصة بالحملة',
                        prefixIcon: Icons.rule_rounded,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // Save / Submit Button
                FilledButton.icon(
                  onPressed: _isLoading ? null : _saveEvent,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                        )
                      : const Icon(Icons.check_circle_rounded, size: 22),
                  label: Text(
                    isEditing ? 'حفظ وتحديث بيانات الحملة' : 'حفظ وإنشاء الحملة الجديدة',
                    style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductSelectorSection(BuildContext context, ColorScheme colorScheme, bool isMobile) {
    final selectedNames = _selectedProductNames;
    final totalCount = _companyProducts.length;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selectedNames.isNotEmpty 
              ? colorScheme.primary.withValues(alpha: 0.4) 
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: selectedNames.isNotEmpty ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  selectedNames.isNotEmpty ? Icons.checklist_rtl_rounded : Icons.tune_rounded, 
                  size: 18, 
                  color: selectedNames.isNotEmpty ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'نطاق منتجات العرض من كتالوج الشركة',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      selectedNames.isNotEmpty
                          ? 'محدد ${selectedNames.length} صنف مخصص من أصل $totalCount منتج (سيقوم الـ AI باحتساب هذه الأصناف فقط)'
                          : totalCount > 0
                              ? 'الوضع الافتراضي: الحملة تسري على جميع منتجات الشركة ($totalCount منتج) دون استثناء'
                              : 'لم يتم تسجيل منتجات في كتالوج الشركة بعد',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: selectedNames.isNotEmpty ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        fontWeight: selectedNames.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isLoadingProducts)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 14),

          if (selectedNames.isEmpty) ...[
            // Default Mode Card (Clean, all-inclusive, zero chips clutter)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: totalCount > 0 
                    ? colorScheme.primaryContainer.withValues(alpha: 0.2)
                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: totalCount > 0 
                      ? colorScheme.primary.withValues(alpha: 0.25)
                      : colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Flex(
                direction: isMobile ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        totalCount > 0 ? Icons.verified_rounded : Icons.info_outline_rounded,
                        color: totalCount > 0 ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        totalCount > 0
                            ? 'العرض يسري على كافة منتجات الشركة ($totalCount صنف)'
                            : 'العرض يسري على كافة فواتير الشركة',
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  if (isMobile) const SizedBox(height: 10) else const Spacer(),
                  if (totalCount > 0)
                    FilledButton.tonalIcon(
                      onPressed: _showProductSelectorDialog,
                      icon: const Icon(Icons.tune_rounded, size: 16),
                      label: Text(
                        '🎯 تخصيص أصناف محددة فقط',
                        style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                    ),
                ],
              ),
            ),
          ] else ...[
            // Custom Selection Mode (Header + Material Design 3 Table)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'قائمة الأصناف المخصصة (${selectedNames.length} صنف)',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _showProductSelectorDialog,
                  icon: const Icon(Icons.edit_note_rounded, size: 16),
                  label: Text('تعديل الأصناف', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _clearSelectedProducts,
                  icon: const Icon(Icons.undo_rounded, size: 16),
                  label: Text('العودة لتضمين كافة المنتجات', style: GoogleFonts.cairo(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildSelectedProductsTable(context, colorScheme, selectedNames),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedProductsTable(BuildContext context, ColorScheme colorScheme, List<String> selectedNames) {
    final List<Map<String, String>> tableItems = [];
    for (int i = 0; i < selectedNames.length; i++) {
      final name = selectedNames[i];
      final match = _companyProducts.where((p) => p.productName.trim() == name.trim()).firstOrNull;
      tableItems.add({
        'index': '${i + 1}',
        'name': name,
        'barcode': (match != null && match.barcode.trim().isNotEmpty) ? match.barcode : '—',
      });
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6))),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    'م',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: colorScheme.onSurface),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'اسم المنتج المشمول في الحملة',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: colorScheme.onSurface),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: Text(
                    'الباركود',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: colorScheme.onSurface),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    'إجراء',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: colorScheme.onSurface),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

          // Table Rows
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: tableItems.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              itemBuilder: (context, index) {
                final item = tableItems[index];
                final isEven = index % 2 == 0;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: isEven ? Colors.transparent : colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                  child: Row(
                    children: [
                      // Index
                      SizedBox(
                        width: 36,
                        child: Text(
                          item['index']!,
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Product Name
                      Expanded(
                        child: Text(
                          item['name']!,
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      // Barcode
                      SizedBox(
                        width: 150,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                item['barcode']!,
                                style: GoogleFonts.robotoMono(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                            if (item['barcode'] != '—') ...[
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: item['barcode']!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('تم نسخ الباركود (${item['barcode']})'),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.all(3),
                                  child: Icon(Icons.copy_rounded, size: 14, color: colorScheme.primary),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Delete Button
                      SizedBox(
                        width: 44,
                        child: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                          tooltip: 'استبعاد هذا المنتج',
                          onPressed: () => _toggleProductSelection(item['name']!),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultipleChancesSection(
    BuildContext context,
    ColorScheme colorScheme,
    bool isMobile,
    dynamic activeCountry,
  ) {
    final minSpend = _minimumSpendController.text.toDoubleOrNull() ?? 300.0;
    final currency = activeCountry.currencySymbol;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _allowMultipleChances
            ? colorScheme.primaryContainer.withValues(alpha: 0.22)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _allowMultipleChances
              ? colorScheme.primary.withValues(alpha: 0.5)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: _allowMultipleChances ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _allowMultipleChances
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 20,
                  color: _allowMultipleChances
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مضاعفة فرص السحب واللعب بناءً على قيمة الشراء',
                      style: GoogleFonts.cairo(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'منح العميل فرصة سحب إضافية لكل مضاعف للحد الأدنى من مشتريات الشركة في نفس الفاتورة.',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(
                value: _allowMultipleChances,
                onChanged: (val) {
                  setState(() {
                    _allowMultipleChances = val;
                    _updatePromptForMultipleChances(val);
                  });
                },
              ),
            ],
          ),
          if (_allowMultipleChances) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 14),
            // Formula Live Calculation Hint
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.calculate_outlined, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'المعادلة الحية: كل ${minSpend.toStringAsFixed(0)} $currency = فرصة سحب واحدة (مثال: ${(minSpend * 2).toStringAsFixed(0)} $currency = فرصتان، ${(minSpend * 3).toStringAsFixed(0)} $currency = 3 فرص).',
                      style: GoogleFonts.cairo(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Max chances limit per receipt input
            TextFormField(
              controller: _maxChancesController,
              keyboardType: TextInputType.number,
              inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
              style: GoogleFonts.cairo(),
              decoration: _m3InputDecoration(
                context: context,
                labelText: 'الحد الأقصى للفرص في الفاتورة الواحدة (اختياري)',
                hintText: 'اتركه فارغاً لعدد غير محدود من الفرص',
                helperText: 'مثال: إذا حددت 3، فلن يحصل العميل على أكثر من 3 فرص حتى لو اشترى بأكثر من ذلك.',
                prefixIcon: Icons.military_tech_outlined,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
    Widget? actionBadge,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                ?actionBadge,
              ],
            ),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildVariableChip(BuildContext context, String variable, String label) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            variable,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '($label)',
            style: GoogleFonts.cairo(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiCampaignAssistantSection(
    BuildContext context,
    ColorScheme colorScheme,
    bool isMobile,
    AppStrings strings,
  ) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: 0.07),
            colorScheme.secondary.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title & AI Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            strings.aiCampaignAssistantTitle,
                            style: GoogleFonts.cairo(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [colorScheme.primary, colorScheme.secondary],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'AI ⚡ Assistant',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      strings.aiCampaignAssistantSubtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Preset Suggestion Chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPresetChip(
                label: strings.presetIdea1,
                textToAdd: 'عند شراء عبوة كبيرة من المنتج يتم الحصول على عبوة صغيرة هدية فورية.',
                colorScheme: colorScheme,
              ),
              _buildPresetChip(
                label: strings.presetIdea2,
                textToAdd: 'عند شراء أي عبوة اسبراي ريكسونا أو أكس يتم الحصول على قسيمة مشتريات (Voucher) بقيمة 50 جنيه، وتتضاعف القسيمة مع كل قطعة إضافية.',
                colorScheme: colorScheme,
              ),
              _buildPresetChip(
                label: strings.presetIdea3,
                textToAdd: 'عند شراء قطعتين من منتجات تريزمي يحصل العميل على عبوة تريزمي 250 مل هدية مجانية.',
                colorScheme: colorScheme,
              ),
              _buildPresetChip(
                label: strings.presetIdea4,
                textToAdd: 'عند شراء أي قطعة اسبراي (ريكسونا أو أكس) يتم الحصول على فواتشر بقيمة 50 جنيه.\nعند شراء أي 2 قطعة اسبراي (ريكسونا أو أكس) يتم الحصول على فواتشر بقيمة 125 جنيه.\nعند شراء أي 2 قطعة ريكسونا رول اون (ريكسونا أو أكس) يتم الحصول على فواتشر بقيمة 50 جنيه.',
                colorScheme: colorScheme,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Text Field for natural language prompt
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.8),
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: TextFormField(
              controller: _promotionalIdeaController,
              maxLines: 4,
              minLines: 2,
              style: const TextStyle(fontSize: 13.5, height: 1.5),
              decoration: InputDecoration(
                hintText: strings.aiCampaignIdeaHint,
                hintStyle: TextStyle(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 12.5,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.all(4),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Magic Generate Action Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _isAiStructuringRules ? null : _structureCampaignWithAi,
              icon: _isAiStructuringRules
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.auto_awesome_rounded, size: 20),
              label: Text(
                _isAiStructuringRules
                    ? strings.aiGeneratingRulesLoading
                    : strings.aiGenerateRulesBtn,
                style: GoogleFonts.cairo(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),

          // AI Logic & Rules Summary Preview Card
          if (_aiValidationSummary.isNotEmpty || _promotionalRules.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildAiRulesPreviewContainer(context, colorScheme, strings),
          ],
        ],
      ),
    );
  }

  Widget _buildPresetChip({
    required String label,
    required String textToAdd,
    required ColorScheme colorScheme,
  }) {
    return ActionChip(
      avatar: const Icon(Icons.lightbulb_outline_rounded, size: 16),
      label: Text(
        label,
        style: GoogleFonts.cairo(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      side: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.6),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onPressed: () {
        final current = _promotionalIdeaController.text.trim();
        if (current.isEmpty) {
          _promotionalIdeaController.text = textToAdd;
        } else {
          _promotionalIdeaController.text = '$current\n$textToAdd';
        }
      },
    );
  }

  Widget _buildAiRulesPreviewContainer(
    BuildContext context,
    ColorScheme colorScheme,
    AppStrings strings,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.fact_check_rounded, color: colorScheme.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.aiValidationSummaryHeader,
                  style: GoogleFonts.cairo(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                tooltip: strings.clearAiSummaryBtn,
                onPressed: () {
                  setState(() {
                    _aiValidationSummary = '';
                    _promotionalRules.clear();
                  });
                },
              ),
            ],
          ),
          const Divider(height: 18),

          // Summary Text
          if (_aiValidationSummary.isNotEmpty)
            SelectableText(
              _aiValidationSummary,
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: colorScheme.onSurface,
              ),
            ),

          if (_promotionalRules.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              strings.aiPromotionalRulesListTitle,
              style: GoogleFonts.cairo(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _promotionalRules.length,
              separatorBuilder: (_, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final rule = _promotionalRules[index];
                return _buildRuleItemTile(rule, index, colorScheme, strings);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRuleItemTile(
    PromotionalRuleItem rule,
    int index,
    ColorScheme colorScheme,
    AppStrings strings,
  ) {
    IconData icon;
    Color badgeColor;
    String typeLabel;

    switch (rule.rewardType) {
      case 'voucher':
        icon = Icons.confirmation_number_rounded;
        badgeColor = Colors.amber.shade800;
        typeLabel = strings.voucherRewardLabel;
        break;
      case 'game_spin':
        icon = Icons.casino_rounded;
        badgeColor = Colors.purple.shade700;
        typeLabel = strings.gameSpinRewardLabel;
        break;
      case 'free_product':
      default:
        icon = Icons.card_giftcard_rounded;
        badgeColor = Colors.teal.shade700;
        typeLabel = strings.freeProductRewardLabel;
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: badgeColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        rule.ruleTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        typeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: badgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '• الشرط: شراء ${rule.minQuantity} من [${rule.triggerProduct}] ➔ المكافأة: [${rule.rewardValue}]',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (rule.allowMultipliers) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.all_inclusive_rounded, size: 14, color: Colors.blue.shade700),
                      const SizedBox(width: 4),
                      Text(
                        strings.multipliersAllowedLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
            onPressed: () {
              setState(() {
                _promotionalRules.removeAt(index);
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRetailChainSection(BuildContext context, ColorScheme colorScheme, bool isMobile) {
    final chainsStream = ref.watch(retailChainsServiceProvider).getRetailChainsStream();

    return StreamBuilder<List<RetailChainModel>>(
      stream: chainsStream,
      builder: (context, snapshot) {
        final chains = snapshot.data ?? [];

        return _buildSectionCard(
          context: context,
          icon: Icons.storefront_rounded,
          title: 'سلسلة الماركت والفروع المستهدفة (Retail Chain & Outlets)',
          subtitle: 'حدد سلسلة الهايبر ماركت (فتح الله، كارفور، سبينس...) والفروع المشمولة في الحملة',
          children: [
            // Row 1: Chain Dropdown + Quick Add Button
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: _selectedRetailChainId,
                    style: GoogleFonts.cairo(color: colorScheme.onSurface),
                    decoration: _m3InputDecoration(
                      context: context,
                      labelText: 'سلسلة الهايبر / المنظمة',
                      hintText: chains.isEmpty ? 'لا توجد سلاسل مسجلة بعد' : 'اختر السلسلة (مثال: أسواق فتح الله)',
                      prefixIcon: Icons.apartment_rounded,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('بدون تحديد سلسلة (عام لجميع المتاجر)'),
                      ),
                      ...chains.map((chain) {
                        return DropdownMenuItem<String?>(
                          value: chain.id,
                          child: Row(
                            children: [
                              Text(
                                chain.name,
                                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${chain.branchesCount} فرع',
                                  style: GoogleFonts.cairo(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedRetailChainId = val;
                        final matched = chains.where((c) => c.id == val).firstOrNull;
                        _selectedRetailChainName = matched?.name;
                        _selectedBranchIds = [];
                        _selectedBranchNames = [];
                      });
                      if (val != null && val.isNotEmpty) {
                        _loadBranchesForChain(val);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Tooltip(
                    message: 'إضافة سلسلة تجارية جديدة سريعة',
                    child: OutlinedButton.icon(
                      onPressed: _showQuickAddChainDialog,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text('سلسلة جديدة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            if (_selectedRetailChainId != null && _selectedRetailChainId!.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),

              // Mode Selection: All branches vs Specific branches
              Row(
                children: [
                  Icon(Icons.hub_rounded, size: 20, color: colorScheme.secondary),
                  const SizedBox(width: 8),
                  Text(
                    'نطاق الفروع المشمولة:',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text('جميع فروع $_selectedRetailChainName', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                          selected: _isAllBranches,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _isAllBranches = true;
                                _selectedBranchIds.clear();
                                _selectedBranchNames.clear();
                              });
                            }
                          },
                        ),
                        ChoiceChip(
                          label: Text('تحديد فروع معينة (${_selectedBranchNames.length})', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                          selected: !_isAllBranches,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _isAllBranches = false;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              if (!_isAllBranches) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'اختر الفروع التابعة لـ ($_selectedRetailChainName):',
                            style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          if (_availableBranches.isNotEmpty) ...[
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _selectedBranchIds = _availableBranches.map((b) => b.id).toList();
                                  _selectedBranchNames = _availableBranches.map((b) => b.branchName).toList();
                                });
                              },
                              icon: const Icon(Icons.select_all_rounded, size: 16),
                              label: const Text('تحديد الكل'),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _selectedBranchIds.clear();
                                  _selectedBranchNames.clear();
                                });
                              },
                              icon: const Icon(Icons.deselect_rounded, size: 16),
                              label: const Text('إلغاء التحديد'),
                            ),
                          ],
                          OutlinedButton.icon(
                            onPressed: _showQuickAddBranchDialog,
                            icon: const Icon(Icons.add_location_alt_rounded, size: 16),
                            label: Text('+ فرع جديد', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      if (_isLoadingBranches)
                        const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                      else if (_availableBranches.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Icon(Icons.store_mall_directory_outlined, size: 36, color: colorScheme.outline),
                                const SizedBox(height: 8),
                                Text(
                                  'لا توجد فروع مسجلة لهذه السلسلة حتى الآن',
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'اضغط على زر "+ فرع جديد" أعلاه لإضافة أول فرع بسهولة.',
                                  style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _availableBranches.map((branch) {
                            final isSelected = _selectedBranchIds.contains(branch.id) ||
                                _selectedBranchNames.contains(branch.branchName);

                            return FilterChip(
                              label: Text(
                                branch.city.isNotEmpty
                                    ? '${branch.branchName} (${branch.city})'
                                    : branch.branchName,
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                ),
                              ),
                              selected: isSelected,
                              selectedColor: colorScheme.primaryContainer,
                              checkmarkColor: colorScheme.onPrimaryContainer,
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedBranchIds.add(branch.id);
                                    if (!_selectedBranchNames.contains(branch.branchName)) {
                                      _selectedBranchNames.add(branch.branchName);
                                    }
                                  } else {
                                    _selectedBranchIds.remove(branch.id);
                                    _selectedBranchNames.remove(branch.branchName);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        );
      },
    );
  }

  Widget _buildPrizeAllocationSection(BuildContext context, ColorScheme colorScheme, bool isMobile) {
    final totalAllocatedUnits = _getTotalAllocatedUnits();
    
    // Determine active branch for allocation
    String activeBranchId = 'all';
    String activeBranchName = 'جميع الفروع';
    if (!_isAllBranches && _selectedBranchIds.isNotEmpty) {
      if (_selectedAllocationBranchId == null || !_selectedBranchIds.contains(_selectedAllocationBranchId)) {
        _selectedAllocationBranchId = _selectedBranchIds.first;
      }
      activeBranchId = _selectedAllocationBranchId!;
      final branchIndex = _selectedBranchIds.indexOf(activeBranchId);
      if (branchIndex >= 0 && branchIndex < _selectedBranchNames.length) {
        activeBranchName = _selectedBranchNames[branchIndex];
      } else {
        final b = _availableBranches.where((b) => b.id == activeBranchId).firstOrNull;
        activeBranchName = b != null ? '${b.branchName} (${b.city})' : activeBranchId;
      }
    }

    return _buildSectionCard(
      context: context,
      icon: Icons.card_giftcard_rounded,
      title: 'تخصيص الهدايا للحملة والفروع (Prize Allocation)',
      subtitle: _isAllBranches 
          ? 'اختر الهدايا ووزع الكميات المخصصة للحملة ككل'
          : 'اختر الفرع المستهدف بالضغط عليه، ثم خصص كميات الهدايا الخاصة به من الرصيد المتبقي',
      actionBadge: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: totalAllocatedUnits > 0 ? colorScheme.primaryContainer : colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$totalAllocatedUnits وحدة مخصصة',
          style: GoogleFonts.cairo(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: totalAllocatedUnits > 0 ? colorScheme.onPrimaryContainer : colorScheme.onSecondaryContainer,
          ),
        ),
      ),
      children: [
        if (_companyGifts.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: colorScheme.onSurfaceVariant, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'لا توجد هدايا مسجلة لهذه الشركة. قم أولاً بإضافة الهدايا من شاشة "هدايا الشركات" في القائمة الجانبية.',
                    style: GoogleFonts.cairo(fontSize: 13, color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          )
        else ...[
          // Branch selector tabs when specific branches are selected
          if (!_isAllBranches && _selectedBranchIds.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.storefront_rounded, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'اضغط على الفرع لضبط حصته من الهدايا:',
                        style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      if (_selectedBranchIds.length > 1) ...[
                        Tooltip(
                          message: 'توزيع المخزون المتاح بالتساوي على الفروع المحددة',
                          child: OutlinedButton.icon(
                            onPressed: _distributeEvenlyAcrossBranches,
                            icon: const Icon(Icons.balance_rounded, size: 14),
                            label: Text('توزيع متساوٍ', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Tooltip(
                        message: 'تصفير هدايا الفرع الحالي',
                        child: TextButton.icon(
                          onPressed: () => _clearBranchAllocations(activeBranchId),
                          icon: Icon(Icons.clear_rounded, size: 14, color: colorScheme.error),
                          label: Text('تصفير الفرع', style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.error)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _selectedBranchIds.map((bId) {
                      final bIndex = _selectedBranchIds.indexOf(bId);
                      final bName = bIndex >= 0 && bIndex < _selectedBranchNames.length 
                          ? _selectedBranchNames[bIndex] 
                          : bId;
                      final isSelected = bId == activeBranchId;
                      final branchAllocUnits = _getBranchAllocatedUnits(bId);

                      return ChoiceChip(
                        selected: isSelected,
                        onSelected: (val) {
                          if (val) {
                            setState(() => _selectedAllocationBranchId = bId);
                          }
                        },
                        avatar: Icon(
                          isSelected ? Icons.check_circle_rounded : Icons.store_rounded,
                          size: 16,
                          color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                        ),
                        label: Text(
                          branchAllocUnits > 0 ? '$bName ($branchAllocUnits)' : bName,
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Active branch indicator banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  !_isAllBranches ? Icons.edit_location_alt_rounded : Icons.hub_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.cairo(color: colorScheme.onSurface, fontSize: 13),
                      children: [
                        const TextSpan(text: 'الفرع النشط للتخصيص: '),
                        TextSpan(
                          text: activeBranchName,
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: colorScheme.primary),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    'حصة هذا الفرع: ${_getBranchAllocatedUnits(activeBranchId)} وحدة',
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Gift allocation cards
          ..._companyGifts.map((gift) {
            final currentAllocation = _branchAllocationQuantities[activeBranchId]?[gift.id] ?? 0;
            final isAllocated = currentAllocation > 0;
            final allocatedInOthers = _getAllocatedInOtherBranches(gift.id, activeBranchId);
            final totalAllocatedInThisEvent = _getTotalAllocatedForGift(gift.id);
            // Remaining unallocated balance from company's available pool for this campaign
            final remainingInCampaign = gift.availableQuantity - totalAllocatedInThisEvent;
            final maxAllowable = currentAllocation + (remainingInCampaign > 0 ? remainingInCampaign : 0);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isAllocated
                    ? colorScheme.primaryContainer.withValues(alpha: 0.25)
                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isAllocated
                      ? colorScheme.primary.withValues(alpha: 0.4)
                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isAllocated
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.card_giftcard_rounded,
                      color: isAllocated ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          gift.giftName,
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 2,
                          children: [
                            Text(
                              'إجمالي رصيد الشركة: ${gift.totalQuantity}',
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (gift.allocatedInOtherCampaigns > 0)
                              Text(
                                '• مخصص بحملات أخرى: ${gift.allocatedInOtherCampaigns}',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  color: Colors.orange.shade800,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (!_isAllBranches && _selectedBranchIds.length > 1 && allocatedInOthers > 0)
                              Text(
                                '• مخصص لفروع أخرى: $allocatedInOthers',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  color: colorScheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            Text(
                              '• المتبقي المتاح للتخصيص: ${remainingInCampaign > 0 ? remainingInCampaign : 0}',
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: remainingInCampaign > 0
                                    ? Colors.green.shade700
                                    : (remainingInCampaign == 0 && totalAllocatedInThisEvent > 0
                                        ? colorScheme.primary
                                        : colorScheme.error),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Interactive Stepper Buttons + Text Field
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded, size: 22),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        color: currentAllocation > 0 ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                        onPressed: currentAllocation > 0
                            ? () {
                                setState(() {
                                  final newQty = currentAllocation - 1;
                                  _branchAllocationQuantities.putIfAbsent(activeBranchId, () => {})[gift.id] = newQty;
                                });
                              }
                            : null,
                      ),
                      SizedBox(
                        width: 70,
                        child: TextFormField(
                          key: ValueKey('${activeBranchId}_${gift.id}_$currentAllocation'),
                          initialValue: currentAllocation > 0 ? currentAllocation.toString() : '',
                          keyboardType: TextInputType.number,
                          inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                          textAlign: TextAlign.center,
                          style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            hintText: '0',
                            hintStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: colorScheme.outlineVariant),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: colorScheme.outlineVariant),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: colorScheme.primary, width: 1.8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                            isDense: true,
                          ),
                          onChanged: (val) {
                            final parsed = int.tryParse(val) ?? 0;
                            final clamped = parsed.clamp(0, maxAllowable);
                            setState(() {
                              _branchAllocationQuantities.putIfAbsent(activeBranchId, () => {})[gift.id] = clamped;
                            });
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        color: remainingInCampaign > 0 ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                        onPressed: remainingInCampaign > 0
                            ? () {
                                setState(() {
                                  final newQty = currentAllocation + 1;
                                  _branchAllocationQuantities.putIfAbsent(activeBranchId, () => {})[gift.id] = newQty;
                                });
                              }
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),

          // Summary Matrix Breakdown Table across branches
          if (!_isAllBranches && _selectedBranchIds.length > 1) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.assessment_outlined, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'ملخص توزيع الهدايا عبر الفروع المختارة:',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  ..._selectedBranchIds.map((bId) {
                    final bIndex = _selectedBranchIds.indexOf(bId);
                    final bName = bIndex >= 0 && bIndex < _selectedBranchNames.length 
                        ? _selectedBranchNames[bIndex] 
                        : bId;
                    final bAllocations = _branchAllocationQuantities[bId] ?? {};
                    final allocatedGiftsText = bAllocations.entries
                        .where((e) => e.value > 0)
                        .map((e) {
                          final gName = _companyGifts.where((g) => g.id == e.key).firstOrNull?.giftName ?? e.key;
                          return '$gName (${e.value})';
                        })
                        .join('، ');

                    final bUnits = _getBranchAllocatedUnits(bId);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.arrow_left_rounded, size: 18, color: colorScheme.primary),
                          Text(
                            '$bName: ',
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          Expanded(
                            child: Text(
                              allocatedGiftsText.isNotEmpty ? allocatedGiftsText : 'لم يتم تخصيص هدايا بعد',
                              style: GoogleFonts.cairo(
                                fontSize: 12,
                                color: allocatedGiftsText.isNotEmpty ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: bUnits > 0 ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$bUnits وحدة',
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: bUnits > 0 ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Text(
                    'رصيد هدايا الشركة المستهلك عبر كل الفروع:',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: colorScheme.primary),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _companyGifts.map((gift) {
                      final totalAllocated = _getTotalAllocatedForGift(gift.id);
                      final remaining = gift.availableQuantity - totalAllocated;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 14, color: colorScheme.secondary),
                            const SizedBox(width: 6),
                            Text(
                              '${gift.giftName}: ',
                              style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'مخصص $totalAllocated من ${gift.availableQuantity} (المتبقي: $remaining)',
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: remaining > 0 ? Colors.green.shade700 : colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}
