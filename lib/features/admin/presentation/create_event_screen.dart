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
  String _multiplierBasis = 'both';
  bool _requireVoucherSerials = false;
  
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

  // Multi-Chain & Branches State
  List<String> _selectedRetailChainIds = [];
  List<String> _selectedRetailChainNames = [];
  final Map<String, List<BranchModel>> _chainBranchesMap = {};
  final Map<String, bool> _chainIsAllBranchesMap = {};
  final Map<String, Set<String>> _chainSelectedBranchIdsMap = {};
  final Map<String, Set<String>> _chainSelectedBranchNamesMap = {};
  List<BranchModel> _availableBranches = [];
  bool _isLoadingBranches = false;

  String? get _selectedRetailChainId {
    final unique = _selectedRetailChainIds.toSet().where((s) => s.isNotEmpty).toList();
    return unique.isNotEmpty ? unique.join(',') : null;
  }

  String? get _selectedRetailChainName {
    final unique = _selectedRetailChainNames.toSet().where((s) => s.isNotEmpty).toList();
    return unique.isNotEmpty ? unique.join(' • ') : null;
  }

  bool get _isAllBranches => _selectedRetailChainIds.isEmpty || _selectedRetailChainIds.every((id) => _chainIsAllBranchesMap[id] ?? true);

  /// Returns the strictly deduplicated list of selected branch IDs across all selected chains
  List<String> get _selectedBranchIds {
    final uniqueIds = <String>{};
    for (final id in _selectedRetailChainIds) {
      if (!(_chainIsAllBranchesMap[id] ?? true)) {
        uniqueIds.addAll(_chainSelectedBranchIdsMap[id] ?? {});
      }
    }
    return uniqueIds.toList();
  }

  /// Returns the corresponding list of branch display names aligned 1:1 with `_selectedBranchIds`
  List<String> get _selectedBranchNames {
    return _selectedBranchIds.map(_getBranchDisplayName).toList();
  }

  /// Resolves the human-readable display name (including city if available) for any branch ID
  String _getBranchDisplayName(String branchId) {
    final b = _availableBranches.where((b) => b.id == branchId).firstOrNull;
    if (b != null) {
      return b.city.isNotEmpty ? '${b.branchName} (${b.city})' : b.branchName;
    }
    if (widget.eventToEdit != null) {
      final idx = widget.eventToEdit!.branchIds.indexOf(branchId);
      if (idx >= 0 && idx < widget.eventToEdit!.branchNames.length) {
        return widget.eventToEdit!.branchNames[idx];
      }
    }
    return branchId;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.eventToEdit;
    _eventNameController = TextEditingController(text: e?.eventName ?? '');
    _targetCompanyController = TextEditingController(text: e?.targetCompany ?? '');
    _companySlugController = TextEditingController(text: e?.companySlug ?? '');
    _companyLogoUrl = e?.companyLogoUrl ?? '';
    _minimumSpendController = TextEditingController(
      text: (e?.minimumSpend != null && e!.minimumSpend > 0)
          ? (e.minimumSpend == e.minimumSpend.roundToDouble()
              ? e.minimumSpend.toInt().toString()
              : e.minimumSpend.toString())
          : '',
    );
    _requiredProductsController = TextEditingController(text: e?.requiredProducts.join(', ') ?? '');
    _allowMultipleChances = e?.allowMultipleChances ?? false;
    _multiplierBasis = e?.multiplierBasis ?? 'both';
    _requireVoucherSerials = e?.requireVoucherSerials ?? false;
    _maxChancesController = TextEditingController(
      text: (e?.maxChancesPerReceipt != null && e!.maxChancesPerReceipt > 0)
          ? e.maxChancesPerReceipt.toString()
          : '',
    );

    _startDate = e?.startDate;
    _endDate = e?.endDate;

    if (e != null && e.retailChainId.isNotEmpty) {
      final rawChainIds = <String>[];
      final seenChainIds = <String>{};
      for (final s in e.retailChainId.split(',')) {
        final trimmed = s.trim();
        if (trimmed.isNotEmpty && seenChainIds.add(trimmed)) {
          rawChainIds.add(trimmed);
        }
      }

      final rawChainNames = <String>[];
      final seenChainNames = <String>{};
      for (final s in e.retailChainName.split('•')) {
        final trimmed = s.trim();
        if (trimmed.isNotEmpty && seenChainNames.add(trimmed)) {
          rawChainNames.add(trimmed);
        }
      }

      _selectedRetailChainIds = List<String>.from(rawChainIds);
      _selectedRetailChainNames = List<String>.from(rawChainNames);

      final uniqueBranchIds = e.branchIds.toSet();
      final uniqueBranchNames = e.branchNames.toSet();

      for (final cId in rawChainIds) {
        _chainIsAllBranchesMap[cId] = e.isAllBranches;
        _chainSelectedBranchIdsMap[cId] = Set<String>.from(uniqueBranchIds);
        _chainSelectedBranchNamesMap[cId] = Set<String>.from(uniqueBranchNames);
        _loadBranchesForChain(cId);
      }
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
- يجب أن تحتوي الفاتورة على منتج واحد على الأقل من "{TARGET_COMPANY}".''',
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

    _selectedGameType = e?.gameType ?? 'wheel';

    // Restore existing allocations when editing
    if (e != null) {
      for (final p in e.allocatedPrizes) {
        final bKey = p.branchId.isNotEmpty ? p.branchId : 'all';
        final key = (p.name.isNotEmpty && !RegExp(r'^[a-zA-Z0-9_-]{15,35}$').hasMatch(p.name))
            ? p.name
            : p.giftId;
        _branchAllocationQuantities.putIfAbsent(bKey, () => {})[key] = p.allocatedQuantity;
      }
    }
  }

  Future<void> _loadBranchesForChain(String chainId) async {
    if (chainId.trim().isEmpty) return;
    setState(() => _isLoadingBranches = true);
    try {
      final branches = await ref.read(retailChainsServiceProvider).getBranchesForChain(chainId);
      if (mounted) {
        setState(() {
          _chainBranchesMap[chainId] = branches;
          _updateAvailableBranches();

          // Reconcile and filter selected branches so each chain only owns its own branches
          if (widget.eventToEdit != null && !(_chainIsAllBranchesMap[chainId] ?? true)) {
            final chainBranchIds = branches.map((b) => b.id).toSet();
            final currentSelectedIds = _chainSelectedBranchIdsMap[chainId] ?? {};

            // Keep only IDs that actually belong to this chain
            final validIds = currentSelectedIds.where((id) => chainBranchIds.contains(id)).toSet();

            // Also check name match in case IDs were slightly different or from older data
            final matchedByName = branches.where((b) =>
                (widget.eventToEdit?.branchNames ?? []).contains(b.branchName) ||
                currentSelectedIds.contains(b.branchName)
            ).toList();

            if (validIds.isNotEmpty) {
              _chainSelectedBranchIdsMap[chainId] = validIds;
              _chainSelectedBranchNamesMap[chainId] = branches
                  .where((b) => validIds.contains(b.id))
                  .map((b) => b.branchName)
                  .toSet();
            } else if (matchedByName.isNotEmpty) {
              _chainSelectedBranchIdsMap[chainId] = matchedByName.map((b) => b.id).toSet();
              _chainSelectedBranchNamesMap[chainId] = matchedByName.map((b) => b.branchName).toSet();
            } else if (_selectedRetailChainIds.length == 1 && branches.isNotEmpty) {
              // If this is the only chain, match all known branches
              final allInChain = branches.where((b) =>
                  currentSelectedIds.contains(b.id) ||
                  (widget.eventToEdit?.branchNames ?? []).contains(b.branchName)
              ).toList();
              if (allInChain.isNotEmpty) {
                _chainSelectedBranchIdsMap[chainId] = allInChain.map((b) => b.id).toSet();
                _chainSelectedBranchNamesMap[chainId] = allInChain.map((b) => b.branchName).toSet();
              }
            } else {
              _chainSelectedBranchIdsMap[chainId] = {};
              _chainSelectedBranchNamesMap[chainId] = {};
            }
          }
        });
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isLoadingBranches = false);
      }
    }
  }

  void _updateAvailableBranches() {
    final all = <BranchModel>[];
    for (final chainId in _selectedRetailChainIds) {
      all.addAll(_chainBranchesMap[chainId] ?? []);
    }
    _availableBranches = all;
  }

  Future<void> _showQuickAddChainDialog() async {
    final nameCtrl = TextEditingController();
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
                Text('إضافة سلسلة تجارية جديدة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'أدخل اسم السلسلة الجديدة لإضافتها فوراً إلى قائمة سلاسل النظام واختيارها لهذه الحملة.',
                    style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'اسم السلسلة التجارية *',
                      hintText: 'مثال: كارفور أو سبينس أو خير زمان',
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
                  if (name.isEmpty) return;

                  final slug = SlugUtils.generateSlug(name);
                  if (slug.isEmpty) return;

                  setDialogState(() => isSaving = true);
                  try {
                    final chain = RetailChainModel(id: slug, name: name, slug: slug);
                    await ref.read(retailChainsServiceProvider).addRetailChain(chain);
                    if (mounted) {
                      setState(() {
                        if (!_selectedRetailChainIds.contains(slug)) {
                          _selectedRetailChainIds.add(slug);
                          _selectedRetailChainNames.add(name);
                          _chainIsAllBranchesMap[slug] = true;
                          _chainSelectedBranchIdsMap[slug] = {};
                          _chainSelectedBranchNamesMap[slug] = {};
                        }
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
                icon: isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text('إضافة واختيار'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showQuickAddBranchDialog([String? targetChainId, String? targetChainName]) async {
    final effectiveChainId = targetChainId ?? (_selectedRetailChainIds.isNotEmpty ? _selectedRetailChainIds.first : null);
    final effectiveChainName = targetChainName ?? (_selectedRetailChainNames.isNotEmpty ? _selectedRetailChainNames.first : '');

    if (effectiveChainId == null || effectiveChainId.isEmpty) {
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
                Text('إضافة فرع جديد لـ ($effectiveChainName)', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15)),
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
                      retailChainId: effectiveChainId,
                      retailChainName: effectiveChainName,
                      branchName: branchName,
                      city: cityCtrl.text.trim(),
                      branchCode: codeCtrl.text.trim(),
                    );
                    await ref.read(retailChainsServiceProvider).addBranch(branch);
                    if (mounted) {
                      await _loadBranchesForChain(effectiveChainId);
                      setState(() {
                        _chainSelectedBranchNamesMap.putIfAbsent(effectiveChainId, () => {}).add(branchName);
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

  String _resolveGiftDisplayName(String giftKey) {
    if (giftKey.trim().isEmpty) return 'هدية';

    // 1. Check in loaded _companyGifts by ID or Name
    final matchedGift = _companyGifts.where((g) => g.id == giftKey || g.giftName == giftKey).firstOrNull;
    if (matchedGift != null && matchedGift.giftName.isNotEmpty) {
      return matchedGift.giftName;
    }

    // 2. Check in widget.eventToEdit?.allocatedPrizes
    if (widget.eventToEdit != null) {
      final matchedPrize = widget.eventToEdit!.allocatedPrizes
          .where((p) => (p.giftId == giftKey || p.name == giftKey) && p.name.isNotEmpty)
          .firstOrNull;
      if (matchedPrize != null && matchedPrize.name.isNotEmpty && !RegExp(r'^[a-zA-Z0-9_-]{15,35}$').hasMatch(matchedPrize.name)) {
        return matchedPrize.name;
      }
    }

    // 3. Check in _promotionalRules linked gifts
    for (final rule in _promotionalRules) {
      for (final linked in rule.linkedGifts) {
        if ((linked.giftId == giftKey || linked.giftName == giftKey) && linked.giftName.isNotEmpty) {
          return linked.giftName;
        }
      }
      if ((rule.linkedGiftId == giftKey || rule.linkedGiftName == giftKey) && rule.linkedGiftName?.isNotEmpty == true) {
        return rule.linkedGiftName!;
      }
    }

    // 4. If giftKey looks like a raw alphanumeric Firestore doc ID (e.g. 5ryhCunijL8NTUi2T49v), fallback cleanly
    final isRawId = RegExp(r'^[a-zA-Z0-9_-]{15,35}$').hasMatch(giftKey);
    if (isRawId) {
      return 'هدية ترويجية';
    }

    return giftKey;
  }

  Future<void> _loadCompanyGifts(String slug) async {
    if (slug.trim().isEmpty) return;
    final giftsService = ref.read(companyGiftsServiceProvider);
    final gifts = await giftsService.getGiftsForCompany(
      slug,
      excludeEventId: widget.eventToEdit?.id,
    );
    if (mounted) {
      setState(() {
        _companyGifts = gifts;
        // Normalize keys in _branchAllocationQuantities so that only valid existing gifts are kept
        for (final branchEntry in _branchAllocationQuantities.entries) {
          final bMap = branchEntry.value;
          final updatedMap = <String, int>{};
          for (final giftEntry in bMap.entries) {
            final key = giftEntry.key;
            final qty = giftEntry.value;
            if (qty <= 0) continue;
            final matched = gifts.where((g) => g.id == key || g.giftName == key || _resolveGiftDisplayName(key) == g.giftName).firstOrNull;
            if (matched != null) {
              updatedMap[matched.id] = (updatedMap[matched.id] ?? 0) + qty;
            }
          }
          bMap
            ..clear()
            ..addAll(updatedMap);
        }

        // Clean up promotional rules from deleted gifts
        _promotionalRules = _promotionalRules.where((rule) {
          if (rule.linkedGifts.isNotEmpty) {
            rule.linkedGifts.removeWhere((lg) => !gifts.any((g) => g.id == lg.giftId || g.giftName == lg.giftName));
          }
          if (rule.linkedGiftId != null && rule.linkedGiftId!.isNotEmpty) {
            final exists = gifts.any((g) => g.id == rule.linkedGiftId || g.giftName == rule.linkedGiftName);
            if (!exists) return false;
          }
          return true;
        }).toList();
      });
    }
  }

  int _getBranchAllocationForGift(String branchId, CompanyGiftModel gift) {
    final bMap = _branchAllocationQuantities[branchId] ?? {};
    int sum = 0;
    bMap.forEach((k, v) {
      if (k == gift.id || k == gift.giftName || _resolveGiftDisplayName(k) == gift.giftName) {
        sum += v;
      }
    });
    return sum;
  }

  void _setBranchAllocationForGift(String branchId, CompanyGiftModel gift, int newQty) {
    final bMap = _branchAllocationQuantities.putIfAbsent(branchId, () => {});
    final keysToRemove = <String>[];
    bMap.forEach((k, v) {
      if (k != gift.id && (k == gift.giftName || _resolveGiftDisplayName(k) == gift.giftName)) {
        keysToRemove.add(k);
      }
    });
    for (final k in keysToRemove) {
      bMap.remove(k);
    }
    bMap[gift.id] = newQty;
  }

  int _getAllocatedInOtherBranches(String giftId, String currentBranchId) {
    int sum = 0;
    final matchedGift = _companyGifts.where((g) => g.id == giftId).firstOrNull;
    final giftName = matchedGift?.giftName ?? giftId;

    _branchAllocationQuantities.forEach((bId, gifts) {
      if (bId != currentBranchId && (_isAllBranches || _selectedBranchIds.contains(bId))) {
        gifts.forEach((k, v) {
          if (k == giftId || k == giftName || _resolveGiftDisplayName(k) == giftName) {
            sum += v;
          }
        });
      }
    });
    return sum;
  }

  int _getTotalAllocatedForGift(String giftId) {
    int sum = 0;
    final matchedGift = _companyGifts.where((g) => g.id == giftId).firstOrNull;
    final giftName = matchedGift?.giftName ?? giftId;

    if (_isAllBranches || _selectedBranchIds.isEmpty) {
      final allMap = _branchAllocationQuantities['all'] ?? {};
      allMap.forEach((k, v) {
        if (k == giftId || k == giftName || _resolveGiftDisplayName(k) == giftName) {
          sum += v;
        }
      });
    } else {
      for (final bId in _selectedBranchIds) {
        final bMap = _branchAllocationQuantities[bId] ?? {};
        bMap.forEach((k, v) {
          if (k == giftId || k == giftName || _resolveGiftDisplayName(k) == giftName) {
            sum += v;
          }
        });
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
          _setBranchAllocationForGift(bId, gift, share);
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
    currentPrompt = currentPrompt
        .replaceAll(RegExp(r'\n?- مضاعفة (?:فرص السحب واللعب|الجوائز والفرص):[^\n]+'), '')
        .trim();
    
    if (enabled) {
      final minSpendText = _minimumSpendController.text.trim().isNotEmpty
          ? _minimumSpendController.text.trim()
          : '{MIN_SPEND}';
      final maxChances = _maxChancesController.text.trim();
      final maxCapText = maxChances.isNotEmpty ? ' (بحد أقصى $maxChances بالفاتورة الواحدة)' : '';

      String addedClause;
      if (_multiplierBasis == 'quantity') {
        addedClause = '\n- مضاعفة الجوائز والفرص: تتضاعف الجوائز والفرص طردياً مع تكرار ومضاعفة كمية المنتج المشروط بالفاتورة (مثال: شراء 1 قطعة = 1 هدية/فرصة، شراء قطعتين = هديتان/فرصتان)$maxCapText.';
      } else if (_multiplierBasis == 'spend') {
        addedClause = '\n- مضاعفة فرص السحب واللعب: الحد الأدنى المطلوب هو $minSpendText جنيه. كل مضاعف لهذا المبلغ من منتجات الشركة يمنح العميل فرصة سحب إضافية$maxCapText.';
      } else {
        addedClause = '\n- مضاعفة الجوائز والفرص: تتضاعف الجوائز الفورية بمضاعفة كميات الأصناف المشروطة، وتتضاعف فرص السحب بمضاعفة قيمة الشراء ($minSpendText جنيه)$maxCapText.';
      }
      _customPromptController.text = '$currentPrompt$addedClause';
    } else {
      _customPromptController.text = currentPrompt;
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
        availableCompanyGifts: _companyGifts,
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

  void _syncPromptFromRules() {
    final targetCompany = _targetCompanyController.text.trim().isNotEmpty
        ? _targetCompanyController.text.trim()
        : 'الشركة المستهدفة';
    final minSpend = double.tryParse(_minimumSpendController.text.trim()) ?? 0.0;
    final reqProducts = _requiredProductsController.text
        .split(RegExp(r'[,،]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final formatted = CampaignAiAssistantService.generateFormattedSystemPrompt(
      targetCompany: targetCompany,
      minimumSpend: minSpend,
      requiredProducts: reqProducts,
      promotionalRules: _promotionalRules,
      retailChainName: _selectedRetailChainName ?? '',
      allowedBranches: _selectedBranchNames,
      allowMultipleChances: _allowMultipleChances,
      multiplierBasis: _multiplierBasis,
      maxChancesPerReceipt: _maxChancesController.text.trim().toIntOrNull() ?? 0,
    );

    setState(() {
      _customPromptController.text = formatted;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppStrings.of(ref).syncPromptSuccessMsg,
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.teal.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _applyRulePreset(String presetKey) {
    final isAr = ref.isArabic;
    if (presetKey == 'clear_360') {
      final matchedGift = _companyGifts.where((g) => g.giftName.contains('كلير') || g.giftName.contains('Clear')).firstOrNull;
      if (matchedGift == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAr ? 'صنف هدية كلير غير متوفر في مخزون هدايا الشركة حالياً' : 'Clear gift is not in company stock',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.orange.shade800,
          ),
        );
        return;
      }
      final newRule = PromotionalRuleItem(
        id: 'rule_${_promotionalRules.length + 1}',
        ruleTitle: 'عرض كلير 360 مل -> هدية ${matchedGift.giftName}',
        triggerProduct: 'كلير 360 مل',
        minQuantity: 1,
        rewardType: 'free_product',
        rewardValue: matchedGift.giftName,
        rewardAmount: 0.0,
        allowMultipliers: true,
        linkedGiftId: matchedGift.id,
        linkedGiftName: matchedGift.giftName,
        linkedGifts: [
          LinkedGiftAllocation(giftId: matchedGift.id, giftName: matchedGift.giftName, quantity: 1, giftType: 'product'),
        ],
      );
      setState(() => _promotionalRules.add(newRule));
    } else if (presetKey == 'tresemme_shrink') {
      final matchedGift = _companyGifts.where((g) => g.giftName.contains('تريزيمي') || g.giftName.contains('Tresemme')).firstOrNull;
      if (matchedGift == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAr ? 'صنف هدية تريزيمي غير متوفر في مخزون هدايا الشركة حالياً' : 'Tresemme gift is not in company stock',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.orange.shade800,
          ),
        );
        return;
      }
      final newRule = PromotionalRuleItem(
        id: 'rule_${_promotionalRules.length + 1}',
        ruleTitle: 'عرض شرنك 2ق تريزيمي -> هدية ${matchedGift.giftName}',
        triggerProduct: 'عرض شرنك 2ق تريزيمي، تريزيمي شرنك',
        minQuantity: 1,
        rewardType: 'free_product',
        rewardValue: matchedGift.giftName,
        rewardAmount: 0.0,
        allowMultipliers: true,
        linkedGiftId: matchedGift.id,
        linkedGiftName: matchedGift.giftName,
        linkedGifts: [
          LinkedGiftAllocation(giftId: matchedGift.id, giftName: matchedGift.giftName, quantity: 1, giftType: 'product'),
        ],
      );
      setState(() => _promotionalRules.add(newRule));
    } else if (presetKey == 'spray_1pc_50') {
      final decomposed = CampaignAiAssistantService.decomposeVoucherAmount(50.0, _companyGifts);
      final newRule = PromotionalRuleItem(
        id: 'rule_${_promotionalRules.length + 1}',
        ruleTitle: 'عرض اسبراي ريكسونا أو أكس (قطعة واحدة) -> فواتشر 50 ج.م',
        triggerProduct: 'اسبراي ريكسونا، اسبراي أكس، مزيل عرق ريكسونا اسبراي، مزيل عرق أكس اسبراي',
        minQuantity: 1,
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات بقيمة 50 ج.م',
        rewardAmount: 50.0,
        allowMultipliers: true,
        linkedGifts: decomposed,
        linkedGiftId: decomposed.firstOrNull?.giftId,
        linkedGiftName: decomposed.firstOrNull?.giftName,
      );
      setState(() => _promotionalRules.add(newRule));
    } else if (presetKey == 'spray_2pc_125') {
      final decomposed = CampaignAiAssistantService.decomposeVoucherAmount(125.0, _companyGifts);
      final newRule = PromotionalRuleItem(
        id: 'rule_${_promotionalRules.length + 1}',
        ruleTitle: 'عرض اسبراي ريكسونا أو أكس (قطعتين) -> فواتشر 125 ج.م',
        triggerProduct: 'اسبراي ريكسونا، اسبراي أكس، مزيل عرق ريكسونا اسبراي، مزيل عرق أكس اسبراي',
        minQuantity: 2,
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات بقيمة 125 ج.م',
        rewardAmount: 125.0,
        allowMultipliers: true,
        linkedGifts: decomposed,
        linkedGiftId: decomposed.firstOrNull?.giftId,
        linkedGiftName: decomposed.firstOrNull?.giftName,
      );
      setState(() => _promotionalRules.add(newRule));
    } else if (presetKey == 'rollon_2pc_50') {
      final decomposed = CampaignAiAssistantService.decomposeVoucherAmount(50.0, _companyGifts);
      final newRule = PromotionalRuleItem(
        id: 'rule_${_promotionalRules.length + 1}',
        ruleTitle: 'عرض رول أون ريكسونا أو أكس (قطعتين) -> فواتشر 50 ج.م',
        triggerProduct: 'رول أون ريكسونا، رول أون أكس، ريكسونا رول اون، اكس رول اون',
        minQuantity: 2,
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات بقيمة 50 ج.م',
        rewardAmount: 50.0,
        allowMultipliers: true,
        linkedGifts: decomposed,
        linkedGiftId: decomposed.firstOrNull?.giftId,
        linkedGiftName: decomposed.firstOrNull?.giftName,
      );
      setState(() => _promotionalRules.add(newRule));
    } else if (presetKey == 'axe_twin_shrink') {
      final decomposed = CampaignAiAssistantService.decomposeVoucherAmount(125.0, _companyGifts);
      final newRule = PromotionalRuleItem(
        id: 'rule_${_promotionalRules.length + 1}',
        ruleTitle: 'عرض شرنك أكس المزدوج (بندل 2 قطعة) -> فواتشر 125 ج.م',
        triggerProduct: 'عرض اكس شرنك، اكس اسبراي شرنك، اكس مزدوج، اكس اسبراي 150مل 335، اكس اسبراي 150مل',
        minQuantity: 1,
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات بقيمة 125 ج.م',
        rewardAmount: 125.0,
        allowMultipliers: true,
        linkedGifts: decomposed,
        linkedGiftId: decomposed.firstOrNull?.giftId,
        linkedGiftName: decomposed.firstOrNull?.giftName,
      );
      setState(() => _promotionalRules.add(newRule));
    }
  }

  void _showAddOrEditPromotionalRuleDialog(BuildContext context, {int? ruleIndex}) {
    final strings = AppStrings.of(ref);
    final isEditing = ruleIndex != null && ruleIndex >= 0 && ruleIndex < _promotionalRules.length;
    final existingRule = isEditing ? _promotionalRules[ruleIndex] : null;

    final titleController = TextEditingController(text: existingRule?.ruleTitle ?? '');
    final triggerController = TextEditingController(text: existingRule?.triggerProduct ?? '');
    final minQtyController = TextEditingController(text: (existingRule?.minQuantity ?? 1).toString());
    final rewardValController = TextEditingController(text: existingRule?.rewardValue ?? '');
    final rewardAmtController = TextEditingController(text: (existingRule?.rewardAmount ?? 0.0).toString());
    String rewardType = existingRule?.rewardType ?? 'free_product';
    bool allowMultipliers = existingRule?.allowMultipliers ?? true;
    CompanyGiftModel? selectedGift = existingRule?.linkedGiftId != null
        ? _companyGifts.where((g) => g.id == existingRule!.linkedGiftId).firstOrNull
        : null;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(
                    isEditing ? Icons.edit_note_rounded : Icons.add_circle_outline_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isEditing ? strings.editRuleTitle : strings.addCustomRuleBtn,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 480,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: titleController,
                        decoration: InputDecoration(
                          labelText: strings.ruleTitleLabel,
                          hintText: 'مثال: عرض اسبراي ريكسونا أو أكس (قطعتين)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: triggerController,
                        decoration: InputDecoration(
                          labelText: strings.triggerProductLabel,
                          hintText: 'مثال: اسبراي ريكسونا، اسبراي أكس',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: minQtyController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: strings.minQuantityLabel,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: rewardType,
                              decoration: InputDecoration(
                                labelText: strings.rewardTypeLabel,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                isDense: true,
                              ),
                              items: [
                                DropdownMenuItem(value: 'free_product', child: Text(strings.freeProductRewardLabel)),
                                DropdownMenuItem(value: 'voucher', child: Text(strings.voucherRewardLabel)),
                                DropdownMenuItem(value: 'game_spin', child: Text(strings.gameSpinRewardLabel)),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setDialogState(() => rewardType = val);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_companyGifts.isNotEmpty) ...[
                        DropdownButtonFormField<CompanyGiftModel>(
                          initialValue: selectedGift,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: strings.chooseInventoryGiftLabel,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                          ),
                          items: _companyGifts.map((g) {
                            final typeDesc = g.isVoucher ? 'فواتشر (${g.formattedUnitValue})' : 'هدية عينية';
                            return DropdownMenuItem(
                              value: g,
                              child: Text(
                                '${g.giftName} - $typeDesc',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          }).toList(),
                          onChanged: (gift) {
                            if (gift != null) {
                              setDialogState(() {
                                selectedGift = gift;
                                if (gift.isVoucher) {
                                  rewardType = 'voucher';
                                  rewardAmtController.text = gift.unitValue.toString();
                                  if (rewardValController.text.isEmpty || rewardValController.text.contains('هدية')) {
                                    rewardValController.text = 'قسيمة مشتريات بقيمة ${gift.formattedUnitValue}';
                                  }
                                } else {
                                  rewardType = 'free_product';
                                  rewardAmtController.text = '0.0';
                                  if (rewardValController.text.isEmpty || rewardValController.text.contains('قسيمة')) {
                                    rewardValController.text = '${gift.giftName} هدية';
                                  }
                                }
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: rewardValController,
                        decoration: InputDecoration(
                          labelText: 'نص الجائزة / المكافأة',
                          hintText: 'مثال: فواتشر بقيمة 125 جنيه أو كلير 90 مل هدية',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                      ),
                      if (rewardType == 'voucher') ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: rewardAmtController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'المبلغ الإجمالي للفاوتشر (ج.م)',
                            hintText: '125',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: Text(
                          strings.multipliersAllowedLabel,
                          style: const TextStyle(fontSize: 13),
                        ),
                        value: allowMultipliers,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        onChanged: (v) => setDialogState(() => allowMultipliers = v),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text(strings.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    final title = titleController.text.trim();
                    final trigger = triggerController.text.trim();
                    final minQty = int.tryParse(minQtyController.text.trim()) ?? 1;
                    final rewardVal = rewardValController.text.trim();
                    final rewardAmt = double.tryParse(rewardAmtController.text.trim()) ?? 0.0;

                    if (title.isEmpty || trigger.isEmpty) return;

                    List<LinkedGiftAllocation> linkedGifts = [];
                    if (rewardType == 'voucher' && rewardAmt > 0) {
                      linkedGifts = CampaignAiAssistantService.decomposeVoucherAmount(rewardAmt, _companyGifts);
                    } else if (selectedGift != null) {
                      linkedGifts = [
                        LinkedGiftAllocation(
                          giftId: selectedGift!.id,
                          giftName: selectedGift!.giftName,
                          quantity: 1,
                          unitValue: selectedGift!.unitValue,
                          giftType: selectedGift!.giftType,
                        ),
                      ];
                    }

                    final ruleId = existingRule?.id.isNotEmpty == true
                        ? existingRule!.id
                        : 'rule_${isEditing ? ruleIndex + 1 : _promotionalRules.length + 1}';

                    final updatedRule = PromotionalRuleItem(
                      id: ruleId,
                      ruleTitle: title,
                      triggerProduct: trigger,
                      minQuantity: minQty,
                      rewardType: rewardType,
                      rewardValue: rewardVal.isNotEmpty ? rewardVal : title,
                      rewardAmount: rewardAmt,
                      allowMultipliers: allowMultipliers,
                      linkedGiftId: linkedGifts.isNotEmpty ? linkedGifts.first.giftId : selectedGift?.id,
                      linkedGiftName: linkedGifts.isNotEmpty ? linkedGifts.first.giftName : selectedGift?.giftName,
                      linkedGifts: linkedGifts,
                    );

                    setState(() {
                      if (isEditing) {
                        _promotionalRules[ruleIndex] = updatedRule;
                      } else {
                        _promotionalRules.add(updatedRule);
                      }
                    });
                    Navigator.pop(dialogCtx);
                  },
                  child: Text(strings.save),
                ),
              ],
            );
          },
        );
      },
    );
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
        isPromoterActive: widget.eventToEdit?.isPromoterActive ?? true,
        isManagerActive: widget.eventToEdit?.isManagerActive ?? true,
        gameType: _selectedGameType,
        allocatedPrizes: () {
          final List<AllocatedPrize> prizes = [];

          AllocatedPrize resolveAllocatedPrize({
            required String giftKey,
            required int quantity,
            required String branchId,
            required String branchName,
          }) {
            CompanyGiftModel? matchedGift;
            try {
              matchedGift = _companyGifts.firstWhere((g) => g.id == giftKey || g.giftName == giftKey);
            } catch (_) {}

            AllocatedPrize? originalPrize;
            if (widget.eventToEdit != null) {
              try {
                originalPrize = widget.eventToEdit!.allocatedPrizes.firstWhere(
                  (p) =>
                      (p.giftId == giftKey || p.name == giftKey) &&
                      (branchId.isEmpty || p.branchId == branchId || p.branchName == branchName),
                );
              } catch (_) {
                try {
                  originalPrize = widget.eventToEdit!.allocatedPrizes.firstWhere(
                    (p) => p.giftId == giftKey || p.name == giftKey,
                  );
                } catch (_) {}
              }
            }

            String finalName = matchedGift?.giftName ?? originalPrize?.name ?? giftKey;
            String finalType = matchedGift?.giftType ?? originalPrize?.giftType ?? 'product';
            double finalUnitValue = matchedGift?.unitValue ?? originalPrize?.unitValue ?? 0.0;

            final isRawId = finalName.isEmpty ||
                (finalName == giftKey && RegExp(r'^[a-zA-Z0-9_-]{15,35}$').hasMatch(finalName)) ||
                RegExp(r'^[a-zA-Z0-9]{18,30}$').hasMatch(finalName);

            if (isRawId) {
              if (finalType == 'voucher' || finalUnitValue > 0) {
                final val = finalUnitValue == finalUnitValue.roundToDouble() ? finalUnitValue.toInt() : finalUnitValue;
                finalName = finalUnitValue > 0 ? 'فواتشر $val جنيه' : 'كارت فواتشر مشتريات';
              } else {
                finalName = 'هدية ترويجية مميزة';
              }
            }

            // Preserve claimed count on edit so remaining is not reset to total
            int calculatedRemaining = quantity;
            if (originalPrize != null) {
              final alreadyClaimed = (originalPrize.allocatedQuantity - originalPrize.remainingQuantity).clamp(0, originalPrize.allocatedQuantity);
              calculatedRemaining = (quantity - alreadyClaimed).clamp(0, quantity);
            }

            return AllocatedPrize(
              giftId: giftKey,
              name: finalName,
              allocatedQuantity: quantity,
              remainingQuantity: calculatedRemaining,
              giftType: finalType,
              unitValue: finalUnitValue,
              branchId: branchId,
              branchName: branchName,
            );
          }

          if (_isAllBranches || _selectedBranchIds.isEmpty) {
            final allAllocations = _branchAllocationQuantities['all'] ?? {};
            for (final entry in allAllocations.entries) {
              if (entry.value > 0) {
                prizes.add(resolveAllocatedPrize(
                  giftKey: entry.key,
                  quantity: entry.value,
                  branchId: '',
                  branchName: '',
                ));
              }
            }
          } else {
            for (final bId in _selectedBranchIds) {
              final bName = _getBranchDisplayName(bId);
              final bAllocations = _branchAllocationQuantities[bId] ?? {};
              for (final entry in bAllocations.entries) {
                if (entry.value > 0) {
                  prizes.add(resolveAllocatedPrize(
                    giftKey: entry.key,
                    quantity: entry.value,
                    branchId: bId,
                    branchName: bName,
                  ));
                }
              }
            }
          }

          // Auto-include any gifts linked in promotional rules if not already present in prizes and exists in company gifts
          for (final rule in _promotionalRules) {
            for (final linked in rule.linkedGifts) {
              final isExistingInMaster = _companyGifts.isEmpty ||
                  _companyGifts.any((g) => g.id == linked.giftId || g.giftName == linked.giftName);
              if (!isExistingInMaster) continue;
              final alreadyInPrizes = prizes.any((p) => p.giftId == linked.giftId || p.name == linked.giftName);
              if (!alreadyInPrizes) {
                prizes.add(resolveAllocatedPrize(
                  giftKey: linked.giftId,
                  quantity: 100,
                  branchId: '',
                  branchName: '',
                ));
              }
            }
            if (rule.linkedGiftId != null && rule.linkedGiftId!.isNotEmpty) {
              final isExistingInMaster = _companyGifts.isEmpty ||
                  _companyGifts.any((g) => g.id == rule.linkedGiftId || g.giftName == rule.linkedGiftName);
              if (!isExistingInMaster) continue;
              final alreadyInPrizes = prizes.any((p) => p.giftId == rule.linkedGiftId || p.name == rule.linkedGiftName);
              if (!alreadyInPrizes) {
                prizes.add(resolveAllocatedPrize(
                  giftKey: rule.linkedGiftId!,
                  quantity: 100,
                  branchId: '',
                  branchName: '',
                ));
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
        multiplierBasis: _multiplierBasis,
        maxChancesPerReceipt: _maxChancesController.text.trim().toIntOrNull() ?? 0,
        promotionalIdea: _promotionalIdeaController.text.trim(),
        aiValidationSummary: _aiValidationSummary.trim(),
        promotionalRules: _promotionalRules,
        requireVoucherSerials: _requireVoucherSerials,
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

  Future<void> _deleteEvent() async {
    if (widget.eventToEdit == null) return;
    final strings = AppStrings.of(ref);
    final cs = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.delete_forever_rounded, color: cs.error, size: 24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                strings.deleteCampaignConfirmTitle,
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Text(
          strings.deleteCampaignConfirmBody,
          style: GoogleFonts.cairo(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(strings.cancel, style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: Text(strings.deleteCampaignBtn, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        final firestore = ref.read(firestoreProvider);
        await firestore.collection('events').doc(widget.eventToEdit!.id).delete();
        if (widget.eventToEdit!.companySlug.isNotEmpty) {
          await ref.read(companyGiftsServiceProvider).syncCompanyGiftsAvailableQuantities(widget.eventToEdit!.companySlug);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(strings.campaignDeletedSuccess),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
          if (widget.onCancel != null) {
            widget.onCancel!();
          } else if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(strings.operationFailed(e.toString())),
              backgroundColor: Colors.red.shade900,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
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
                              labelText: 'الحد الأدنى للشراء (${activeCountry.currencySymbol}) (اختياري)',
                              hintText: 'اتركه فارغاً إذا كان العرض بدون حد أدنى للمشتريات',
                              helperText: 'اختياري - في حال تركه فارغاً يعتمد الـ AI على شروط البرومبت والأصناف فقط',
                              prefixIcon: Icons.payments_outlined,
                            ),
                            validator: (value) {
                              if (value != null && value.trim().isNotEmpty) {
                                if (value.trim().toDoubleOrNull() == null) return 'رقم غير صحيح';
                              }
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
                    _buildVoucherSerialsSettingSection(context, colorScheme, isMobile),
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
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildVariableChip(context, '{TARGET_COMPANY}', 'اسم الشركة المستهدفة'),
                        _buildVariableChip(context, '{MIN_SPEND}', 'الحد الأدنى للإنفاق'),
                        _buildVariableChip(context, '{REQUIRED_PRODUCTS}', 'المنتجات المشترطة'),
                        const SizedBox(width: 6),
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.teal.shade700.withValues(alpha: 0.12),
                            foregroundColor: Colors.teal.shade800,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                          label: Text(
                            strings.syncPromptFromRulesBtn,
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          onPressed: _syncPromptFromRules,
                        ),
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
                Row(
                  children: [
                    if (isEditing) ...[
                      Expanded(
                        flex: 1,
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _deleteEvent,
                          icon: Icon(Icons.delete_forever_rounded, size: 22, color: colorScheme.error),
                          label: Text(
                            strings.deleteCampaignBtn,
                            style: GoogleFonts.cairo(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.error,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.error,
                            side: BorderSide(color: colorScheme.error.withValues(alpha: 0.6), width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
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
                    ),
                  ],
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
    final minSpend = _minimumSpendController.text.toDoubleOrNull() ?? 0.0;
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
                      'مضاعفة فرص السحب والجوائز (Smart Multipliers)',
                      style: GoogleFonts.cairo(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'منح العميل فرص سحب أو جوائز إضافية عند تكرار شراء كميات المنتجات المشروطة أو مضاعفة قيمة الفاتورة.',
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

            // Multiplier Basis Mode Selector (M3 Segmented Button)
            Text(
              'طريقة احتساب المضاعفة:',
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: 'quantity',
                    label: Text('📦 كمية المنتجات'),
                    tooltip: 'مضاعفة الجوائز والفرص طردياً مع كمية المنتجات المشتراة',
                  ),
                  ButtonSegment<String>(
                    value: 'spend',
                    label: Text('💰 قيمة الشراء'),
                    tooltip: 'مضاعفة الفرص لكل مضاعف للحد الأدنى للمبلغ',
                  ),
                  ButtonSegment<String>(
                    value: 'both',
                    label: Text('✨ كلاهما معاً'),
                    tooltip: 'مضاعفة الجوائز حسب الكمية + فرص السحب حسب القيمة',
                  ),
                ],
                selected: {_multiplierBasis},
                onSelectionChanged: (newSelection) {
                  setState(() {
                    _multiplierBasis = newSelection.first;
                    _updatePromptForMultipleChances(_allowMultipleChances);
                  });
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(
                    GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Formula Live Calculation & Explanation Box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _multiplierBasis == 'quantity'
                        ? Icons.inventory_2_outlined
                        : (_multiplierBasis == 'spend' ? Icons.calculate_outlined : Icons.auto_awesome_outlined),
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _multiplierBasis == 'quantity'
                          ? '📦 مضاعفة حسب كمية المنتجات: عند شراء مضاعفات للكمية المشروطة في العرض (مثال: شراء 1 قطعة = 1 هدية/فرصة، شراء 2 قطعة = 2 هدية/فرصتان، شراء 3 قطع = 3 هدايا/فرص).'
                          : (_multiplierBasis == 'spend'
                              ? (minSpend > 0
                                  ? '💰 مضاعفة حسب المبلغ: كل ${minSpend.toStringAsFixed(0)} $currency = فرصة سحب واحدة (مثال: ${(minSpend * 2).toStringAsFixed(0)} $currency = فرصتان، ${(minSpend * 3).toStringAsFixed(0)} $currency = 3 فرص).'
                                  : 'تنبيه: لمضاعفة الفرص بناءً على المبلغ، يرجى إدخال الحد الأدنى للشراء أعلاه.')
                              : '✨ نظام مركب ذكي: مضاعفة الجوائز الفورية عند تكرار كميات الأصناف المشروطة + مضاعفة فرص السحب واللعب لكل مضاعف للحد الأدنى من المبلغ (${minSpend > 0 ? minSpend.toStringAsFixed(0) : '...'} $currency).'),
                      style: GoogleFonts.cairo(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Max chances limit per receipt input
            TextFormField(
              controller: _maxChancesController,
              keyboardType: TextInputType.number,
              inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
              style: GoogleFonts.cairo(),
              onChanged: (_) {
                _updatePromptForMultipleChances(_allowMultipleChances);
              },
              decoration: _m3InputDecoration(
                context: context,
                labelText: 'سقف الحماية: الحد الأقصى للفرص / الجوائز بالفاتورة (اختياري)',
                hintText: 'اتركه فارغاً لعدد غير محدود من الفرص/الجوائز',
                helperText: 'مثال: إذا حددت 3، فلن يحصل العميل على أكثر من 3 جوائز أو فرص بالفاتورة الواحدة مهما زادت الكمية أو القيمة لحماية مخزون الحملة وميزانيتها.',
                prefixIcon: Icons.military_tech_outlined,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVoucherSerialsSettingSection(
    BuildContext context,
    ColorScheme colorScheme,
    bool isMobile,
  ) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _requireVoucherSerials
            ? Colors.amber.shade50.withValues(alpha: 0.55)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _requireVoucherSerials
              ? Colors.amber.shade400
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: _requireVoucherSerials ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _requireVoucherSerials
                  ? Colors.amber.shade700
                  : colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.confirmation_number_rounded,
              size: 20,
              color: _requireVoucherSerials
                  ? Colors.white
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      'تسجيل أرقام كروت الفواتشرات',
                      style: GoogleFonts.cairo(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _requireVoucherSerials
                            ? Colors.red.shade100
                            : Colors.green.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _requireVoucherSerials ? 'إلزامي للبروموتر' : 'اختياري (الافتراضي)',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _requireVoucherSerials
                              ? Colors.red.shade900
                              : Colors.green.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _requireVoucherSerials
                      ? 'يلزم البروموتر بإدخال الأرقام التسلسلية لكروت الفواتشرات المسلمة للعميل قبل تأكيد تسليم الهدية.'
                      : 'إدخال أرقام الفواتشرات اختياري للبروموتر، ويمكنه تأكيد تسليم الهدية مباشرة دون إدخالها.',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: _requireVoucherSerials,
            activeTrackColor: Colors.amber.shade700,
            onChanged: (val) {
              setState(() {
                _requireVoucherSerials = val;
              });
            },
          ),
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

          // Preset Suggestion Chips Header & Wrap
          Text(
            strings.presetIdeasHeader,
            style: GoogleFonts.cairo(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
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

          if (_companyGifts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              strings.dynamicInventoryChipsHeader,
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.teal.shade800,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _companyGifts.take(6).map((gift) {
                final isVoucher = gift.isVoucher;
                return ActionChip(
                  avatar: Icon(
                    isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                    size: 15,
                    color: isVoucher ? Colors.amber.shade900 : Colors.teal.shade700,
                  ),
                  label: Text(
                    isVoucher
                        ? '${gift.giftName} (${gift.formattedUnitValue})'
                        : gift.giftName,
                    style: GoogleFonts.cairo(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  backgroundColor: isVoucher
                      ? Colors.amber.shade50.withValues(alpha: 0.8)
                      : Colors.teal.shade50.withValues(alpha: 0.8),
                  side: BorderSide(
                    color: isVoucher
                        ? Colors.amber.shade300
                        : Colors.teal.shade300,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onPressed: () {
                    final textToAdd = isVoucher
                        ? 'عند شراء [حدد المنتج والكمية] يتم الحصول على ${gift.giftName} بقيمة ${gift.unitValue} جنيه.'
                        : 'عند شراء [حدد المنتج والكمية] يحصل العميل على عبوة ${gift.giftName} مجاناً.';
                    final current = _promotionalIdeaController.text.trim();
                    if (current.isEmpty) {
                      _promotionalIdeaController.text = textToAdd;
                    } else {
                      _promotionalIdeaController.text = '$current\n$textToAdd';
                    }
                  },
                );
              }).toList(),
            ),
          ],

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

          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                strings.aiPromotionalRulesListTitle,
                style: GoogleFonts.cairo(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_promotionalRules.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  side: BorderSide(color: Colors.teal.shade700.withValues(alpha: 0.5)),
                ),
                icon: const Icon(Icons.add_rounded, size: 16, color: Colors.teal),
                label: Text(
                  strings.addCustomRuleBtn,
                  style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.teal.shade800),
                ),
                onPressed: () => _showAddOrEditPromotionalRuleDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Presets Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                hint: Row(
                  children: [
                    const Icon(Icons.flash_on_rounded, size: 16, color: Colors.amber),
                    const SizedBox(width: 6),
                    Text(
                      strings.presetRulesDropdownHint,
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'clear_360',
                    child: Text('🎁 شراء 1 كلير 360 مل -> كلير 90 مل هدية', style: TextStyle(fontSize: 12.5)),
                  ),
                  DropdownMenuItem(
                    value: 'tresemme_shrink',
                    child: Text('🎁 شراء عرض تريزيمي شرنك 2ق -> تريزيمي 250 مل هدية', style: TextStyle(fontSize: 12.5)),
                  ),
                  DropdownMenuItem(
                    value: 'spray_1pc_50',
                    child: Text('💳 شراء 1 اسبراي ريكسونا أو أكس -> فواتشر 50 ج.م', style: TextStyle(fontSize: 12.5)),
                  ),
                  DropdownMenuItem(
                    value: 'spray_2pc_125',
                    child: Text('💳 شراء 2 اسبراي ريكسونا أو أكس -> فواتشر 125 ج.م (2×50 + 1×25)', style: TextStyle(fontSize: 12.5)),
                  ),
                  DropdownMenuItem(
                    value: 'rollon_2pc_50',
                    child: Text('💳 شراء 2 رول أون ريكسونا أو أكس -> فواتشر 50 ج.م', style: TextStyle(fontSize: 12.5)),
                  ),
                  DropdownMenuItem(
                    value: 'axe_twin_shrink',
                    child: Text('💳 شراء عرض شرنك أكس المزدوج (بندل 2 قطعة) -> فواتشر 125 ج.م', style: TextStyle(fontSize: 12.5)),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    _applyRulePreset(val);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 10),

          if (_promotionalRules.isNotEmpty) ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _promotionalRules.length,
              separatorBuilder: (_, index) => const SizedBox(height: 10),
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

    final isLinkedToInventory = (rule.linkedGifts.isNotEmpty &&
            rule.linkedGifts.any((g) => _companyGifts.any((cg) => cg.id == g.giftId))) ||
        (rule.linkedGiftId != null &&
            rule.linkedGiftId!.isNotEmpty &&
            _companyGifts.any((g) => g.id == rule.linkedGiftId));

    final isExplicitVoucher = rule.rewardType == 'voucher' ||
        rule.rewardValue.contains('فواتشر') ||
        rule.rewardValue.toLowerCase().contains('voucher') ||
        rule.rewardValue.contains('قسيمة');
    final isExplicitFreeProduct = rule.rewardType == 'free_product' ||
        rule.rewardValue.contains('هدية') ||
        rule.rewardValue.contains('منتج') ||
        (rule.linkedGifts.isNotEmpty && rule.linkedGifts.every((g) => !g.isVoucher));

    final isVoucherRule = isExplicitVoucher && !isExplicitFreeProduct;

    double effectiveVoucherAmount = rule.rewardAmount;
    if (isVoucherRule && effectiveVoucherAmount <= 0) {
      final match = RegExp(r'(\d+)').firstMatch(rule.rewardValue);
      if (match != null) {
        effectiveVoucherAmount = double.tryParse(match.group(1)!) ?? 0.0;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLinkedToInventory
              ? Colors.teal.shade300
              : colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: isLinkedToInventory ? 1.5 : 1.0,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: badgeColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.ruleTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            typeLabel,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: badgeColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: isLinkedToInventory
                                ? Colors.teal.shade100
                                : Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isLinkedToInventory
                                    ? Icons.check_circle_rounded
                                    : Icons.help_outline_rounded,
                                size: 12,
                                color: isLinkedToInventory
                                    ? Colors.teal.shade800
                                    : Colors.amber.shade900,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                isLinkedToInventory
                                    ? strings.ruleLinkedBadge
                                    : strings.ruleUnlinkedBadge,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: isLinkedToInventory
                                      ? Colors.teal.shade900
                                      : Colors.amber.shade900,
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
              IconButton(
                icon: const Icon(Icons.edit_note_rounded, size: 22, color: Colors.teal),
                tooltip: strings.editRuleTitle,
                onPressed: () => _showAddOrEditPromotionalRuleDialog(context, ruleIndex: index),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                tooltip: strings.deleteRuleTooltip,
                onPressed: () {
                  setState(() {
                    _promotionalRules.removeAt(index);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 10),

          // Multi-Gift & Voucher Linker Card
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isLinkedToInventory
                  ? Colors.teal.shade50.withValues(alpha: 0.5)
                  : Colors.amber.shade50.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isLinkedToInventory
                    ? Colors.teal.shade300
                    : Colors.amber.shade300,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.inventory_2_rounded,
                      size: 16,
                      color: isLinkedToInventory ? Colors.teal.shade800 : Colors.amber.shade900,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        strings.linkedCompanyGiftLabel,
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isLinkedToInventory ? Colors.teal.shade900 : Colors.amber.shade900,
                        ),
                      ),
                    ),
                    if (isVoucherRule && effectiveVoucherAmount > 0) ...[
                      InkWell(
                        onTap: () {
                          final decomposed = CampaignAiAssistantService.decomposeVoucherAmount(
                            effectiveVoucherAmount,
                            _companyGifts,
                          );
                          if (decomposed.isNotEmpty) {
                            setState(() {
                              _promotionalRules[index] = rule.copyWith(
                                linkedGifts: decomposed,
                                linkedGiftId: decomposed.first.giftId,
                                linkedGiftName: decomposed
                                    .map((d) => d.quantity > 1 ? '${d.quantity}x ${d.giftName}' : d.giftName)
                                    .join(' + '),
                                rewardType: 'voucher',
                                rewardAmount: effectiveVoucherAmount,
                              );
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'تم تفكيك الفواتشر تلقائياً: ${decomposed.map((d) => '${d.quantity} × ${d.giftName}').join(' + ')}',
                                ),
                                backgroundColor: Colors.teal.shade700,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'لم نتمكن من مطابقة فئات الفواتشر في المخزون بدقة مع $effectiveVoucherAmount ج.م',
                                ),
                                backgroundColor: Colors.orange.shade800,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.amber.shade400),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome_rounded, size: 13, color: Colors.amber.shade900),
                              const SizedBox(width: 4),
                              Text(
                                '${strings.autoDecomposeLabel} (${effectiveVoucherAmount.toInt()} ج.م)',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),

                // Linked Gifts List
                if (rule.linkedGifts.isNotEmpty) ...[
                  ...rule.linkedGifts.asMap().entries.map((entry) {
                    final giftIdx = entry.key;
                    final alloc = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            alloc.isVoucher
                                ? Icons.confirmation_number_rounded
                                : Icons.card_giftcard_rounded,
                            size: 16,
                            color: alloc.isVoucher ? Colors.amber.shade800 : Colors.teal.shade700,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  alloc.giftName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (alloc.isVoucher && alloc.unitValue > 0)
                                  Text(
                                    'فئة: ${alloc.unitValue.toInt()} ج.م × ${alloc.quantity} = ${alloc.totalMonetaryValue.toInt()} ج.م',
                                    style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                                  ),
                              ],
                            ),
                          ),
                          // Stepper: [-] [qty] [+]
                          InkWell(
                            onTap: () {
                              final updatedList = List<LinkedGiftAllocation>.from(rule.linkedGifts);
                              if (alloc.quantity > 1) {
                                updatedList[giftIdx] = alloc.copyWith(quantity: alloc.quantity - 1);
                              } else {
                                updatedList.removeAt(giftIdx);
                              }
                              setState(() {
                                _promotionalRules[index] = rule.copyWith(
                                  linkedGifts: updatedList,
                                  linkedGiftId: updatedList.isNotEmpty ? updatedList.first.giftId : '',
                                  linkedGiftName: updatedList.isNotEmpty
                                      ? updatedList.map((d) => d.quantity > 1 ? '${d.quantity}x ${d.giftName}' : d.giftName).join(' + ')
                                      : '',
                                );
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(Icons.remove, size: 14),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              '${alloc.quantity}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              final updatedList = List<LinkedGiftAllocation>.from(rule.linkedGifts);
                              updatedList[giftIdx] = alloc.copyWith(quantity: alloc.quantity + 1);
                              setState(() {
                                _promotionalRules[index] = rule.copyWith(
                                  linkedGifts: updatedList,
                                  linkedGiftId: updatedList.first.giftId,
                                  linkedGiftName: updatedList.map((d) => d.quantity > 1 ? '${d.quantity}x ${d.giftName}' : d.giftName).join(' + '),
                                );
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(Icons.add, size: 14),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16, color: Colors.redAccent),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              final updatedList = List<LinkedGiftAllocation>.from(rule.linkedGifts)..removeAt(giftIdx);
                              setState(() {
                                _promotionalRules[index] = rule.copyWith(
                                  linkedGifts: updatedList,
                                  linkedGiftId: updatedList.isNotEmpty ? updatedList.first.giftId : '',
                                  linkedGiftName: updatedList.isNotEmpty
                                      ? updatedList.map((d) => d.quantity > 1 ? '${d.quantity}x ${d.giftName}' : d.giftName).join(' + ')
                                      : '',
                                );
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }),

                  if (isVoucherRule && rule.totalVoucherValue > 0) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 6),
                      child: Row(
                        children: [
                          Icon(
                            (rule.totalVoucherValue - effectiveVoucherAmount).abs() < 0.01
                                ? Icons.check_circle_rounded
                                : Icons.info_outline_rounded,
                            size: 14,
                            color: (rule.totalVoucherValue - effectiveVoucherAmount).abs() < 0.01
                                ? Colors.teal.shade800
                                : Colors.amber.shade900,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${strings.totalCardsValueLabel} ${rule.totalVoucherValue.toInt()} ج.م '
                            '${(rule.totalVoucherValue - effectiveVoucherAmount).abs() < 0.01 ? '(مطابقة تامة ومكتملة ✓)' : '(المطلوب: ${effectiveVoucherAmount.toInt()} ج.م)'}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: (rule.totalVoucherValue - effectiveVoucherAmount).abs() < 0.01
                                  ? Colors.teal.shade900
                                  : Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],

                // Add Gift to Rule Dropdown
                DropdownButtonFormField<String?>(
                  initialValue: null,
                  isDense: true,
                  isExpanded: true,
                  hint: Text(
                    rule.linkedGifts.isEmpty
                        ? strings.unlinkedGiftOption
                        : strings.addGiftToRule,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: rule.linkedGifts.isEmpty
                          ? colorScheme.onSurfaceVariant
                          : Colors.teal.shade900,
                      fontWeight: rule.linkedGifts.isEmpty ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        rule.linkedGifts.isEmpty ? strings.unlinkedGiftOption : strings.addGiftToRule,
                        style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                    ..._companyGifts.map((gift) {
                      final isVoucher = gift.isVoucher;
                      return DropdownMenuItem<String?>(
                        value: gift.id,
                        child: Row(
                          children: [
                            Icon(
                              isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                              size: 15,
                              color: isVoucher ? Colors.amber.shade800 : Colors.teal.shade700,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                gift.giftName,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isVoucher) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  gift.formattedUnitValue,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 4),
                            Text(
                              '(${gift.availableQuantity})',
                              style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (selectedGiftId) {
                    if (selectedGiftId != null && selectedGiftId.isNotEmpty) {
                      final selectedGift = _companyGifts.where((g) => g.id == selectedGiftId).firstOrNull;
                      if (selectedGift != null) {
                        final updatedList = List<LinkedGiftAllocation>.from(rule.linkedGifts);
                        final existingIdx = updatedList.indexWhere((g) => g.giftId == selectedGift.id);
                        if (existingIdx >= 0) {
                          updatedList[existingIdx] = updatedList[existingIdx].copyWith(
                            quantity: updatedList[existingIdx].quantity + 1,
                          );
                        } else {
                          updatedList.add(
                            LinkedGiftAllocation(
                              giftId: selectedGift.id,
                              giftName: selectedGift.giftName,
                              quantity: 1,
                              unitValue: selectedGift.unitValue,
                              giftType: selectedGift.giftType,
                            ),
                          );
                        }
                        setState(() {
                          _promotionalRules[index] = rule.copyWith(
                            linkedGifts: updatedList,
                            linkedGiftId: updatedList.first.giftId,
                            linkedGiftName: updatedList.map((d) => d.quantity > 1 ? '${d.quantity}x ${d.giftName}' : d.giftName).join(' + '),
                            rewardType: selectedGift.isVoucher ? 'voucher' : rule.rewardType,
                            rewardAmount: isVoucherRule ? effectiveVoucherAmount : rule.rewardAmount,
                          );
                        });
                      }
                    }
                  },
                ),
              ],
            ),
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

        // 1. Deduplicate chains by ID
        final uniqueChains = <String, RetailChainModel>{};
        for (final chain in chains) {
          if (chain.id.isNotEmpty && !uniqueChains.containsKey(chain.id)) {
            uniqueChains[chain.id] = chain;
          }
        }
        final cleanChains = uniqueChains.values.toList();

        // Build list of chains available to add (or show all with (مضافة ✔️))
        final dropdownItems = <DropdownMenuItem<String?>>[
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('اختر سلسلة تجارية لإضافتها للحملة...'),
          ),
          ...cleanChains.map((chain) {
            final isAlreadyAdded = _selectedRetailChainIds.contains(chain.id);
            return DropdownMenuItem<String?>(
              value: chain.id,
              child: Row(
                children: [
                  Icon(
                    isAlreadyAdded ? Icons.check_circle_rounded : Icons.storefront_rounded,
                    size: 18,
                    color: isAlreadyAdded ? Colors.green : colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    chain.name,
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      color: isAlreadyAdded ? Colors.green.shade700 : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: isAlreadyAdded ? Colors.green.withValues(alpha: 0.15) : colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isAlreadyAdded ? 'مضافة بالحملة ✔️' : '${chain.branchesCount} فرع',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isAlreadyAdded ? Colors.green.shade800 : colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ];

        return _buildSectionCard(
          context: context,
          icon: Icons.storefront_rounded,
          title: 'سلاسل الماركت والفروع المستهدفة (Retail Chains & Outlets)',
          subtitle: 'اختر السلاسل التجارية المسجلة في النظام والفروع المشمولة في الحملة الترويجية',
          children: [
            // Row 1: Dropdown Selector for registered chains + Register new chain system button
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey('retail_chain_add_dropdown_${_selectedRetailChainIds.length}_${cleanChains.length}'),
                    isExpanded: true,
                    initialValue: null,
                    style: GoogleFonts.cairo(color: colorScheme.onSurface),
                    decoration: _m3InputDecoration(
                      context: context,
                      labelText: 'إضافة سلسلة تجارية من النظام (Dropdown)',
                      hintText: cleanChains.isEmpty
                          ? 'لا توجد سلاسل مسجلة بالنظام بعد'
                          : 'اختر سلسلة لإضافتها (مثل: أسواق فتح الله، كارفور...)',
                      prefixIcon: Icons.add_business_rounded,
                    ),
                    items: dropdownItems,
                    onChanged: (selectedChainId) {
                      if (selectedChainId == null || selectedChainId.isEmpty) return;
                      final matched = cleanChains.where((c) => c.id == selectedChainId).firstOrNull;
                      final chainName = matched?.name ?? selectedChainId;

                      if (_selectedRetailChainIds.contains(selectedChainId)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('السلسلة "$chainName" مضافة بالفعل في الحملة'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                        return;
                      }

                      setState(() {
                        _selectedRetailChainIds.add(selectedChainId);
                        _selectedRetailChainNames.add(chainName);
                        _chainIsAllBranchesMap[selectedChainId] = true;
                        _chainSelectedBranchIdsMap[selectedChainId] = {};
                        _chainSelectedBranchNamesMap[selectedChainId] = {};
                      });
                      _loadBranchesForChain(selectedChainId);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Tooltip(
                    message: 'تسجيل علامة تجارية جديدة كلياً في النظام لم تكن موجودة من قبل',
                    child: OutlinedButton.icon(
                      onPressed: _showQuickAddChainDialog,
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                      label: Text('+ تسجيل بالسيستم', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Active Chains in Campaign
            if (_selectedRetailChainIds.isEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: colorScheme.primary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'لم يتم تحديد سلسلة تجارية معينة بعد. يمكنك اختيار سلسلة أو أكثر من القائمة المنسدلة أعلاه، أو تركها فارغة لتكون الحملة عامة لجميع المتاجر.',
                        style: GoogleFonts.cairo(fontSize: 13, color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Text(
                'السلاسل والفروع المشمولة في هذه الحملة (${_selectedRetailChainIds.length} سلاسل • ${_isAllBranches ? 'جميع الفروع' : '${_selectedBranchIds.length} فرع مشمول'}):',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14, color: colorScheme.primary),
              ),
              const SizedBox(height: 10),

              // Build a card for each selected chain
              ..._selectedRetailChainIds.map((chainId) {
                final chainIndex = _selectedRetailChainIds.indexOf(chainId);
                final chainName = chainIndex < _selectedRetailChainNames.length
                    ? _selectedRetailChainNames[chainIndex]
                    : chainId;
                final chainBranches = _chainBranchesMap[chainId] ?? [];
                final isChainAllBranches = _chainIsAllBranchesMap[chainId] ?? true;
                final selectedBranchIds = _chainSelectedBranchIdsMap[chainId] ?? {};
                final selectedBranchNames = _chainSelectedBranchNamesMap[chainId] ?? {};

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Chain name + branch count badge + delete button
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.store_mall_directory_rounded, size: 20, color: colorScheme.onPrimaryContainer),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  chainName,
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                Text(
                                  '${chainBranches.length} فرع مسجل بالنظام',
                                  style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'إزالة هذه السلسلة من الحملة',
                            icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
                            onPressed: () {
                              setState(() {
                                final idx = _selectedRetailChainIds.indexOf(chainId);
                                if (idx >= 0) {
                                  _selectedRetailChainIds.removeAt(idx);
                                  if (idx < _selectedRetailChainNames.length) {
                                    _selectedRetailChainNames.removeAt(idx);
                                  }
                                }
                                _chainBranchesMap.remove(chainId);
                                _chainIsAllBranchesMap.remove(chainId);
                                _chainSelectedBranchIdsMap.remove(chainId);
                                _chainSelectedBranchNamesMap.remove(chainId);
                                _updateAvailableBranches();
                              });
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      // Scope Switcher for this chain
                      Row(
                        children: [
                          Icon(Icons.hub_rounded, size: 18, color: colorScheme.secondary),
                          const SizedBox(width: 8),
                          Text(
                            'نطاق فروع $chainName:',
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              children: [
                                ChoiceChip(
                                  label: Text('جميع فروع $chainName (${chainBranches.length})', style: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 12)),
                                  selected: isChainAllBranches,
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(() {
                                        _chainIsAllBranchesMap[chainId] = true;
                                        _chainSelectedBranchIdsMap[chainId] = {};
                                        _chainSelectedBranchNamesMap[chainId] = {};
                                      });
                                    }
                                  },
                                ),
                                ChoiceChip(
                                  label: Text('تحديد فروع معينة (${selectedBranchNames.length})', style: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 12)),
                                  selected: !isChainAllBranches,
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(() {
                                        _chainIsAllBranchesMap[chainId] = false;
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Branch Selection Chips if specific branches chosen
                      if (!isChainAllBranches) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
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
                                    'اختر الفروع المشمولة لـ ($chainName):',
                                    style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                  const Spacer(),
                                  if (chainBranches.isNotEmpty) ...[
                                    TextButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _chainSelectedBranchIdsMap[chainId] = chainBranches.map((b) => b.id).toSet();
                                          _chainSelectedBranchNamesMap[chainId] = chainBranches.map((b) => b.branchName).toSet();
                                        });
                                      },
                                      icon: const Icon(Icons.select_all_rounded, size: 16),
                                      label: const Text('تحديد الكل'),
                                    ),
                                    TextButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _chainSelectedBranchIdsMap[chainId] = {};
                                          _chainSelectedBranchNamesMap[chainId] = {};
                                        });
                                      },
                                      icon: const Icon(Icons.deselect_rounded, size: 16),
                                      label: const Text('إلغاء التحديد'),
                                    ),
                                  ],
                                  OutlinedButton.icon(
                                    onPressed: () => _showQuickAddBranchDialog(chainId, chainName),
                                    icon: const Icon(Icons.add_location_alt_rounded, size: 16),
                                    label: Text('+ فرع جديد', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              if (_isLoadingBranches && chainBranches.isEmpty)
                                const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                              else if (chainBranches.isEmpty)
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
                                  children: chainBranches.map((branch) {
                                    final isSelected = selectedBranchIds.contains(branch.id) ||
                                        selectedBranchNames.contains(branch.branchName);

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
                                          final idsSet = _chainSelectedBranchIdsMap.putIfAbsent(chainId, () => {});
                                          final namesSet = _chainSelectedBranchNamesMap.putIfAbsent(chainId, () => {});
                                          if (selected) {
                                            idsSet.add(branch.id);
                                            namesSet.add(branch.branchName);
                                          } else {
                                            idsSet.remove(branch.id);
                                            namesSet.remove(branch.branchName);
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
                  ),
                );
              }),
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
      actionBadge: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isAllBranches && _selectedBranchIds.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_selectedBranchIds.length} فروع مشمولة',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: totalAllocatedUnits > 0 ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$totalAllocatedUnits وحدة مخصصة',
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: totalAllocatedUnits > 0 ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
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
                        'اضغط على الفرع لضبط حصته من الهدايا (إجمالي الفروع: ${_selectedBranchIds.length} فرع):',
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
                      final bName = _getBranchDisplayName(bId);
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
                        if (!_isAllBranches && _selectedBranchIds.length > 1) ...[
                          TextSpan(
                            text: ' (فرع ${_selectedBranchIds.indexOf(activeBranchId) + 1} من ${_selectedBranchIds.length})',
                            style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                          ),
                        ],
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
            final currentAllocation = _getBranchAllocationForGift(activeBranchId, gift);
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
                      gift.isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                      color: isAllocated ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      size: 20,
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
                                gift.giftName,
                                style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (gift.isVoucher) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '💳 ${gift.formattedUnitValue}',
                                  style: GoogleFonts.cairo(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 2,
                          children: [
                            Text(
                              gift.isVoucher 
                                  ? 'رصيد الشركة: ${gift.totalQuantity} كارت (${gift.totalMonetaryValue.toInt()} ج.م)'
                                  : 'إجمالي رصيد الشركة: ${gift.totalQuantity}',
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
                              gift.isVoucher
                                  ? '• المتبقي المتاح: ${remainingInCampaign > 0 ? remainingInCampaign : 0} كارت (${((remainingInCampaign > 0 ? remainingInCampaign : 0) * gift.unitValue).toInt()} ج.م)'
                                  : '• المتبقي المتاح للتخصيص: ${remainingInCampaign > 0 ? remainingInCampaign : 0}',
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
                                  _setBranchAllocationForGift(activeBranchId, gift, newQty);
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
                              _setBranchAllocationForGift(activeBranchId, gift, clamped);
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
                                  _setBranchAllocationForGift(activeBranchId, gift, newQty);
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
                        'ملخص توزيع الهدايا عبر الفروع المختارة (${_selectedBranchIds.length} فرع):',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  ..._selectedBranchIds.map((bId) {
                    final bName = _getBranchDisplayName(bId);
                    final bAllocations = _branchAllocationQuantities[bId] ?? {};
                    final Map<String, int> resolvedGiftsMap = {};
                    for (final entry in bAllocations.entries) {
                      if (entry.value <= 0) continue;
                      final displayName = _resolveGiftDisplayName(entry.key);
                      resolvedGiftsMap[displayName] = (resolvedGiftsMap[displayName] ?? 0) + entry.value;
                    }

                    final allocatedGiftsText = resolvedGiftsMap.entries
                        .map((e) => '${e.key} (${e.value})')
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
