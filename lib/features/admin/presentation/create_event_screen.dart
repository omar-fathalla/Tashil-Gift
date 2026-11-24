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
import '../../../core/utils/receipt_date_window.dart';
import '../../../core/constants/country_currency_config.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/services/campaign_ai_assistant_service.dart';
import '../../../core/services/partner_portal_auth_service.dart';
import '../domain/company_model.dart';
import '../domain/event_model.dart';
import '../domain/campaign_stock_integrity.dart';
import '../domain/campaign_edit_save.dart';
import '../domain/company_gift_model.dart';
import '../domain/retail_chain_model.dart';
import 'widgets/portal_credentials_dialog.dart';
import 'widgets/smart_branch_batch_importer_dialog.dart';


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

class RuleConflictIssue {
  final String title;
  final String description;
  final List<int> conflictingRuleIndices;
  final String? suggestedFixLabel;
  final VoidCallback? onResolve;

  RuleConflictIssue({
    required this.title,
    required this.description,
    required this.conflictingRuleIndices,
    this.suggestedFixLabel,
    this.onResolve,
  });
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

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
  bool _isPromptExpanded = false;
  bool _isAiAssistantExpanded = false;
  late final TextEditingController _welcomeTitleController;
  late final TextEditingController _welcomeMessageController;
  late final TextEditingController _termsController;
  late final TextEditingController _maxChancesController;
  bool _allowMultipleChances = false;
  String _multiplierBasis = 'both';
  String _voucherSerialMode = 'optional';
  bool _allowComplementaryReceipts = false;
  bool _enableWhatsAppWinnerNotification = true;
  bool _hasCustomAgencyCredentials = false;
  late final TextEditingController _customAgencyUsernameController;
  late final TextEditingController _customAgencyPasswordController;
  int _customAgencyCredentialVersion = 1;
  
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
  final Map<String, TextEditingController> _chainBranchSearchControllers = {};
  final Map<String, String?> _chainSelectedGovernorateFilterMap = {};
  List<BranchModel> _availableBranches = [];
  bool _isLoadingBranches = false;

  // Memoized Firestore Streams (Rule 9: Never create streams inside build)
  Stream<QuerySnapshot>? _companiesStream;
  Stream<List<RetailChainModel>>? _chainsStream;

  Stream<QuerySnapshot>? _ensureCompaniesStream() {
    if (_companiesStream == null) {
      try {
        _companiesStream = ref.read(firestoreProvider).collection('companies').snapshots();
      } catch (_) {}
    }
    return _companiesStream;
  }

  Stream<List<RetailChainModel>>? _ensureChainsStream() {
    if (_chainsStream == null) {
      try {
        _chainsStream = ref.read(retailChainsServiceProvider).getRetailChainsStream();
      } catch (_) {}
    }
    return _chainsStream;
  }

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
      if (b.city.isNotEmpty && !b.branchName.contains(b.city) && !b.branchName.contains('(')) {
        return '${b.branchName} (${b.city})';
      }
      return b.branchName;
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
    _voucherSerialMode = e?.voucherSerialMode ?? 'optional';
    _allowComplementaryReceipts = e?.allowComplementaryReceipts ?? false;
    _enableWhatsAppWinnerNotification = e?.enableWhatsAppWinnerNotification ?? true;
    _hasCustomAgencyCredentials = e?.hasCustomAgencyCredentials ?? false;
    _customAgencyUsernameController = TextEditingController(text: e?.customAgencyUsername ?? '');
    _customAgencyPasswordController = TextEditingController(text: e?.customAgencyPassword ?? '');
    _customAgencyCredentialVersion = e?.customAgencyCredentialVersion ?? 1;
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
    _promotionalRules = (e?.promotionalRules ?? []).map((rule) {
      if (rule.conditionType == 'by_quantity' && (rule.minSpend > 0 || rule.maxSpend != null || rule.discountTolerance > 0)) {
        return rule.copyWith(minSpend: 0.0, maxSpend: null, discountTolerance: 0.0);
      }
      return rule;
    }).toList();

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
                        SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: colorScheme.error),
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

  Future<void> _openSmartBranchImporter(List<RetailChainModel> cleanChains) async {
    final allBranches = await ref.read(retailChainsServiceProvider).getAllBranches();

    if (!mounted) return;

    final result = await SmartBranchBatchImporterDialog.show(
      context: context,
      existingChains: cleanChains,
      existingBranches: allBranches,
    );

    if (result != null && result.totalBranchesCount > 0) {
      setState(() {
        for (final cId in result.chainIds) {
          if (!_selectedRetailChainIds.contains(cId)) {
            _selectedRetailChainIds.add(cId);
            _selectedRetailChainNames.add(result.chainNames[cId] ?? cId);
          }
          _chainIsAllBranchesMap[cId] = false;
          _chainSelectedBranchIdsMap[cId] = Set<String>.from(result.chainSelectedBranchIds[cId] ?? {});
          _chainSelectedBranchNamesMap[cId] = Set<String>.from(result.chainSelectedBranchNames[cId] ?? {});
        }
        _updateAvailableBranches();
      });

      for (final cId in result.chainIds) {
        _loadBranchesForChain(cId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم استيراد واعتماد ${result.totalBranchesCount} فرعاً عبر ${result.chainIds.length} سلاسل تجارية في الحملة بنجاح! ✓',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            backgroundColor: colorScheme.onTertiaryFixedVariant,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
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
                        SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: colorScheme.error),
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

  /// Normalizes Arabic text with phonetic aliases for brands and search terms
  String _normalizeCatalogSearchText(String s) {
    var str = s.toLowerCase().trim();
    // Diacritics
    str = str.replaceAll(RegExp(r'[\u064B-\u0652\u0640]'), '');
    str = str.replaceAll(RegExp(r'[أإآ]'), 'ا');
    str = str.replaceAll(RegExp(r'[ىيیئ]'), 'ي');
    str = str.replaceAll(RegExp(r'[ةه]'), 'ه');
    str = str.replaceAll('ؤ', 'و');
    str = str.replaceAll('ك', 'ك');
    str = str.replaceAll('ک', 'ك');

    // Phonetic & POS Brand Aliases
    str = str.replaceAll(RegExp(r'\b(سيج|سجنال|signal)\b'), 'سيجنال');
    str = str.replaceAll(RegExp(r'\b(كلوس|كلوساب|closeup|close-up|close up)\b'), 'كلوس اب');
    str = str.replaceAll(RegExp(r'\b(تريزم|تريسم|تريزمي|tresemme|treseme)\b'), 'تريزيمي');
    str = str.replaceAll(RegExp(r'\b(ريكس|ركس|rexona)\b'), 'ريكسونا');
    str = str.replaceAll(RegExp(r'\b(axe)\b'), 'اكس');
    str = str.replaceAll(RegExp(r'\b(dove)\b'), 'دوف');
    str = str.replaceAll(RegExp(r'\b(clear)\b'), 'كلير');
    str = str.replaceAll(RegExp(r'\b(sunsilk|صنسلك|صانسيلك|صانسلك)\b'), 'صنسيلك');
    str = str.replaceAll(RegExp(r'\b(lux)\b'), 'لوكس');
    str = str.replaceAll(RegExp(r'\b(camay|كامي)\b'), 'كاماي');
    str = str.replaceAll(RegExp(r'\b(lifebuoy|لايف بوي)\b'), 'لايفبوي');
    str = str.replaceAll(RegExp(r'\b(vaseline)\b'), 'فازلين');
    str = str.replaceAll(RegExp(r'\b(knorr)\b'), 'كنور');
    str = str.replaceAll(RegExp(r'\b(lipton)\b'), 'ليبتون');
    return str;
  }

  /// Checks whether a product name contains a standalone Axe word (not wax or XL size)
  bool _hasStandaloneAxeWord(List<String> tokens, String rawLower) {
    if (RegExp(r'\baxe\b', caseSensitive: false).hasMatch(rawLower)) return true;
    for (int i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t == 'اكس' || t == 'أكس' || t == 'آكس') {
        if (i + 1 < tokens.length) {
          final next = tokens[i + 1].toLowerCase();
          if (next == 'لارج' || next == 'large') {
            continue; // Extra Large size, not Axe deodorant
          }
        }
        return true;
      }
    }
    return false;
  }

  /// Checks whether a product name contains a standalone Lux word (not deluxe)
  bool _hasStandaloneLuxWord(List<String> tokens, String rawLower) {
    if (rawLower.contains('deluxe') || tokens.contains('ديلوكس')) return false;
    if (RegExp(r'\blux\b', caseSensitive: false).hasMatch(rawLower)) return true;
    return tokens.contains('لوكس');
  }

  /// Returns known sub-brands for a specific company slug
  List<String> _getCompanyBrands({String? companySlug}) {
    final slug = (companySlug ?? _companySlugController.text).trim().toLowerCase();
    final pNames = _companyProducts.map((p) => p.productName).toList();
    final dynamicBrands = CampaignAiAssistantService.resolveCompanySubBrands(slug, productNames: pNames);
    if (dynamicBrands.isNotEmpty) return dynamicBrands;
    if (slug == 'fine' || slug == 'فاين' || slug.contains('fine')) {
      return ['فاين', 'إيزي', 'سندريلا'];
    } else if (slug == 'unilever' || slug == '512' || slug == 'يونيليفر' || slug.contains('unilever')) {
      return ['دوف', 'ريكسونا', 'سيجنال', 'كلوس اب', 'تريزيمي', 'كلير', 'لوكس', 'أكس', 'صنسيلك', 'فازلين', 'لايفبوي', 'كاماي', 'كنور', 'ليبتون'];
    } else if (slug == 'almarai' || slug == 'المراعي' || slug.contains('marai')) {
      return ['المراعي', 'اليوم', 'لوزين', 'سفن دايز'];
    } else if (slug == 'pg' || slug == 'بي اند جي' || slug == 'procter') {
      return ['بامبرز', 'تايد', 'اريال', 'بانتين', 'هيد اند شولدرز', 'داوني', 'اولويز', 'اورال بي', 'جيليت', 'فيري'];
    } else if (slug == 'nestle' || slug == 'نستله' || slug == 'نستلة' || slug.contains('nestle')) {
      return ['كيت كات', 'نسكافيه جولد', 'نسكافيه', 'سيريلاك', 'اس-26', 'نسكويك', 'ماجي', 'نيدو'];
    }
    return [];
  }

  /// Generates dynamic contextual search placeholder based on the active company
  String _getSearchHintText({String? companySlug}) {
    final slug = (companySlug ?? _companySlugController.text).trim().toLowerCase();
    if (slug == 'fine' || slug == 'فاين' || slug.contains('fine')) {
      return 'ابحث باسم المنتج أو الماركة (فاين، إيزي، سندريلا) أو الباركود...';
    } else if (slug == 'unilever' || slug == '512' || slug == 'يونيليفر' || slug.contains('unilever')) {
      return 'ابحث باسم المنتج أو الماركة (سيجنال، كلوس اب، دوف) أو الباركود...';
    } else if (slug == 'almarai' || slug == 'المراعي' || slug.contains('marai')) {
      return 'ابحث باسم المنتج أو الماركة (المراعي، اليوم، لوزين) أو الباركود...';
    }
    return 'ابحث باسم المنتج أو الماركة أو الباركود...';
  }

  /// Checks whether a product name matches a specific brand name or alias with word-boundary safety
  bool _productMatchesBrandName(String productName, String brand, {String? companySlug}) {
    final pNorm = _normalizeCatalogSearchText(productName);
    final rawLower = productName.toLowerCase();
    final bNorm = _normalizeCatalogSearchText(brand);
    final tokens = pNorm.split(RegExp(r'[\s,\-_/\\+*().:]+')).where((t) => t.isNotEmpty).toList();

    // 1. Fine Brands
    if (brand == 'فاين' || bNorm == 'فاين') {
      return tokens.contains('فاين') ||
          rawLower.contains(RegExp(r'\bfine\b')) ||
          pNorm.startsWith('حفاضات فاين') ||
          pNorm.startsWith('مناديل فاين');
    }
    if (brand == 'إيزي' || brand == 'ايزي' || bNorm == 'ايزي') {
      return tokens.contains('ايزي') ||
          tokens.contains('ايزى') ||
          tokens.contains('إيزي') ||
          rawLower.contains(RegExp(r'\beasy\b')) ||
          tokens.contains('سويت') ||
          pNorm.startsWith('عرض سويت') ||
          pNorm.startsWith('عرض 3ق سويت');
    }
    if (brand == 'سندريلا' || bNorm == 'سندريلا') {
      return tokens.contains('سندريلا') || rawLower.contains(RegExp(r'\bcinderella\b'));
    }

    // 2. Unilever Brands (with strict word boundaries)
    if (bNorm == 'سيجنال' || brand == 'سيجنال') {
      return tokens.contains('سيجنال') || tokens.contains('سجنال') || rawLower.contains(RegExp(r'\bsignal\b'));
    }
    if (bNorm.contains('كلوس') || brand == 'كلوس اب') {
      return tokens.contains('كلوس') || tokens.contains('كلوس اب') || rawLower.contains(RegExp(r'\bclose\s*up\b|\bcloseup\b'));
    }
    if (bNorm.contains('تريزيم') || brand == 'تريزيمي') {
      return tokens.contains('تريزيمي') || tokens.contains('تريزم') || tokens.contains('تريزمي') || rawLower.contains(RegExp(r'\btresemme\b|\btreseme\b'));
    }
    if (bNorm.contains('ريكسون') || brand == 'ريكسونا') {
      return tokens.contains('ريكسونا') || tokens.contains('ركسونا') || rawLower.contains(RegExp(r'\brexona\b'));
    }
    if (bNorm == 'دوف' || brand == 'دوف') {
      return tokens.contains('دوف') || rawLower.contains(RegExp(r'\bdove\b'));
    }
    if (bNorm == 'كلير' || brand == 'كلير') {
      return tokens.contains('كلير') || rawLower.contains(RegExp(r'\bclear\b'));
    }
    if (bNorm == 'لوكس' || brand == 'لوكس') {
      return _hasStandaloneLuxWord(tokens, rawLower);
    }
    if (bNorm == 'اكس' || brand == 'أكس' || brand == 'اكس') {
      return _hasStandaloneAxeWord(tokens, rawLower);
    }
    if (bNorm.contains('صنسيلك') || brand == 'صنسيلك') {
      return tokens.contains('صنسيلك') || tokens.contains('صانسيلك') || tokens.contains('صنسلك') || rawLower.contains(RegExp(r'\bsunsilk\b'));
    }
    if (bNorm.contains('كاما') || brand == 'كاماي') {
      return tokens.contains('كاماي') || tokens.contains('كامي') || rawLower.contains(RegExp(r'\bcamay\b'));
    }
    if (bNorm == 'فازلين' || brand == 'فازلين') {
      return tokens.contains('فازلين') || rawLower.contains(RegExp(r'\bvaseline\b'));
    }
    if (bNorm.contains('لايفبو') || brand == 'لايفبوي') {
      return tokens.contains('لايفبوي') || tokens.contains('لايف بوي') || rawLower.contains(RegExp(r'\blifebuoy\b'));
    }
    if (bNorm == 'كنور' || brand == 'كنور') {
      return tokens.contains('كنور') || rawLower.contains(RegExp(r'\bknorr\b'));
    }
    if (bNorm == 'ليبتون' || brand == 'ليبتون') {
      return tokens.contains('ليبتون') || rawLower.contains(RegExp(r'\blipton\b'));
    }

    // 3. Almarai Brands
    if (bNorm == 'المراعي' || brand == 'المراعي') {
      return tokens.contains('المراعي') || rawLower.contains(RegExp(r'\balmarai\b'));
    }
    if (bNorm == 'اليوم' || brand == 'اليوم') {
      return tokens.contains('اليوم') || rawLower.contains(RegExp(r'\balyoum\b'));
    }
    if (bNorm == 'لوزين' || brand == 'لوزين') {
      return tokens.contains('لوزين') || rawLower.contains(RegExp(r'\blusine\b'));
    }
    if (bNorm == 'سفن دايز' || brand == 'سفن دايز') {
      return tokens.contains('سفن دايز') || rawLower.contains(RegExp(r'\b7days\b'));
    }

    // 4. Nestle Brands & Sub-Brands (AIR-84)
    if (bNorm == 'نسكافيه جولد' || brand == 'نسكافيه جولد') {
      final hasCoffee = tokens.contains('نسكافيه') || tokens.contains('نسكافية') || rawLower.contains('nescafe') || tokens.contains('نسله') || tokens.contains('نستله');
      final hasGold = tokens.contains('جولد') || rawLower.contains('gold');
      return hasCoffee && hasGold;
    }
    if (bNorm == 'نسكافيه' || brand == 'نسكافيه') {
      final hasCoffee = tokens.contains('نسكافيه') || tokens.contains('نسكافية') || rawLower.contains('nescafe');
      final hasGold = tokens.contains('جولد') || rawLower.contains('gold');
      return hasCoffee && !hasGold;
    }
    if (bNorm == 'كيت كات' || brand == 'كيت كات') {
      return tokens.contains('كيت') || rawLower.contains('kitkat');
    }

    // Dynamic brand or fallback token check
    return tokens.contains(bNorm) || rawLower.contains(RegExp(r'\b' + RegExp.escape(brand.toLowerCase()) + r'\b'));
  }

  /// Extracts brand clusters with counts from the loaded company products catalog
  Map<String, int> _extractBrandCountsFromProducts(
    List<CompanyProductItem> products, {
    String? companySlug,
  }) {
    final Map<String, int> counts = {};
    if (products.isEmpty) return counts;

    final effectiveSlug = (companySlug ?? (products.firstOrNull?.companySlug ?? _companySlugController.text))
        .trim()
        .toLowerCase();
    final knownBrands = _getCompanyBrands(companySlug: effectiveSlug);

    if (knownBrands.isNotEmpty) {
      for (final brand in knownBrands) {
        int qty = 0;
        for (final p in products) {
          if (_productMatchesBrandName(p.productName, brand, companySlug: effectiveSlug)) {
            qty++;
          }
        }
        if (qty > 0) {
          counts[brand] = qty;
        }
      }
    } else {
      // Dynamic Brand Auto-Discovery for arbitrary companies:
      // Group products by their first significant Arabic/English word
      final Map<String, int> wordFrequencies = {};
      for (final p in products) {
        final norm = _normalizeCatalogSearchText(p.productName);
        final tokens = norm.split(RegExp(r'[\s,\-_/\\+*().:]+')).where((t) => t.length >= 3).toList();
        if (tokens.isNotEmpty) {
          final firstWord = tokens.first;
          if (!['عرض', 'كرتونة', 'علبة', 'باكو', 'قطعة', 'طقم', 'كيس'].contains(firstWord)) {
            wordFrequencies[firstWord] = (wordFrequencies[firstWord] ?? 0) + 1;
          }
        }
      }

      final candidateBrands = wordFrequencies.entries
          .where((e) => e.value >= 2)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      for (final candidate in candidateBrands.take(8)) {
        counts[candidate.key] = candidate.value;
      }
    }

    return counts;
  }

  /// Filters company products based on search query, barcode, and active brand chip
  List<CompanyProductItem> _filterCompanyProducts({
    required List<CompanyProductItem> products,
    required String searchQuery,
    String? selectedBrand,
    String? companySlug,
  }) {
    final cleanQuery = searchQuery.trim();
    final normQuery = _normalizeCatalogSearchText(cleanQuery);
    final queryTokens = normQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    return products.where((p) {
      final pNorm = _normalizeCatalogSearchText(p.productName);
      final rawLower = p.productName.toLowerCase();

      // 1. Brand filter chip check
      if (selectedBrand != null && selectedBrand.isNotEmpty) {
        if (!_productMatchesBrandName(p.productName, selectedBrand, companySlug: companySlug)) {
          return false;
        }
      }

      // 2. Query filter
      if (cleanQuery.isEmpty) return true;

      // Direct barcode match
      if (p.barcode.isNotEmpty && p.barcode.contains(cleanQuery)) {
        return true;
      }

      // Special shorthand for "سج" -> matches "سيجنال" or "سجنال" or "signal"
      if (cleanQuery == 'سج' || cleanQuery == 'سجنال' || cleanQuery == 'سيجنال') {
        if (pNorm.contains('سيجنال') || p.productName.contains('سجنال') || rawLower.contains('signal')) {
          return true;
        }
      }

      // Special shorthand for "كلوس" -> matches "كلوس اب" or "closeup"
      if (cleanQuery == 'كلوس' || cleanQuery == 'كلوس اب') {
        if (pNorm.contains('كلوس اب') || p.productName.contains('كلوس') || rawLower.contains('closeup')) {
          return true;
        }
      }

      // Shorthand for "فاي" or "فاين"
      if (cleanQuery == 'فاي' || cleanQuery == 'فاين') {
        if (pNorm.contains('فاين') || rawLower.contains('fine')) {
          return true;
        }
      }

      // Shorthand for "ايز" or "ايزي"
      if (cleanQuery == 'ايز' || cleanQuery == 'ايزي' || cleanQuery == 'إيزي') {
        if (pNorm.contains('ايزي') || pNorm.contains('ايزى') || rawLower.contains('easy')) {
          return true;
        }
      }

      // Shorthand for "سندر" or "سندريلا"
      if (cleanQuery == 'سندر' || cleanQuery == 'سندريلا') {
        if (pNorm.contains('سندريلا') || rawLower.contains('cinderella')) {
          return true;
        }
      }

      // Substring match in raw name or category or unit size
      if (rawLower.contains(cleanQuery.toLowerCase()) || p.category.toLowerCase().contains(cleanQuery.toLowerCase()) || p.unitSize.toLowerCase().contains(cleanQuery.toLowerCase())) {
        return true;
      }

      // All search tokens must be found in either normalized name or raw name or barcode
      if (queryTokens.isNotEmpty) {
        final allTokensMatch = queryTokens.every((token) {
          if (pNorm.contains(token) || rawLower.contains(token) || p.barcode.contains(token)) return true;
          if (token.length >= 3 && (pNorm.startsWith(token) || rawLower.startsWith(token))) return true;
          return false;
        });
        if (allTokensMatch) return true;
      }

      return false;
    }).toList();
  }

  /// Builds horizontal scrollable brand filter chips
  Widget _buildBrandFilterChipsWidget({
    required BuildContext context,
    required Map<String, int> brandCounts,
    required int totalCount,
    required String selectedBrand,
    required Function(String) onSelectBrand,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final List<Map<String, dynamic>> brandItems = [
      {'name': '', 'label': 'كافة المنتجات ($totalCount)'},
    ];

    final iconMap = {
      'فاين': '🧻',
      'إيزي': '🍯',
      'ايزي': '🍯',
      'سندريلا': '🌸',
      'سيجنال': '🦷',
      'كلوس اب': '💎',
      'تريزيمي': '✨',
      'ريكسونا': '🌿',
      'دوف': '🕊️',
      'كلير': '❄️',
      'لوكس': '🌸',
      'أكس': '⚡',
      'اكس': '⚡',
      'كاماي': '🧼',
      'فازلين': '🧴',
      'صنسيلك': '💆',
      'لايفبوي': '🛡️',
      'كنور': '🍲',
      'ليبتون': '🍵',
      'المراعي': '🥛',
      'اليوم': '🍗',
      'لوزين': '🥐',
      'سفن دايز': '🥐',
      'بامبرز': '👶',
      'تايد': '🧺',
      'اريال': '🧺',
      'بانتين': '💆',
    };

    brandCounts.forEach((brand, qty) {
      final emoji = iconMap[brand] ?? '🏷️';
      brandItems.add({
        'name': brand,
        'label': '$emoji $brand ($qty)',
        'count': qty,
      });
    });

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: brandItems.map((item) {
          final isSelected = selectedBrand == item['name'];
          return Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: ChoiceChip(
              label: Text(
                item['label'] as String,
                style: GoogleFonts.cairo(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                ),
              ),
              selected: isSelected,
              selectedColor: colorScheme.primary,
              backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onSelectBrand(item['name'] as String),
            ),
          );
        }).toList(),
      ),
    );
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
    String selectedBrand = '';
    final effectiveSlug = _companySlugController.text.trim().toLowerCase();
    final brandCounts = _extractBrandCountsFromProducts(_companyProducts, companySlug: effectiveSlug);

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredProducts = _filterCompanyProducts(
              products: _companyProducts,
              searchQuery: searchQuery,
              selectedBrand: selectedBrand,
              companySlug: effectiveSlug,
            );

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
                width: 650,
                height: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    TextFormField(
                      style: GoogleFonts.cairo(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: _getSearchHintText(companySlug: effectiveSlug),
                        hintStyle: GoogleFonts.cairo(fontSize: 12.5),
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
                    const SizedBox(height: 8),
                    if (brandCounts.isNotEmpty) ...[
                      _buildBrandFilterChipsWidget(
                        context: context,
                        brandCounts: brandCounts,
                        totalCount: _companyProducts.length,
                        selectedBrand: selectedBrand,
                        onSelectBrand: (brand) {
                          setDialogState(() => selectedBrand = brand);
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
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
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
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
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.search_off_rounded, size: 40, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                                  const SizedBox(height: 8),
                                  Text(
                                    'لا توجد منتجات مطابقة للبحث في قاعدة البيانات.',
                                    style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
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
                                            if (item.unitSize.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              Text(item.unitSize, style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                                            ],
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
        backgroundColor: colorScheme.onTertiaryFixedVariant,
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
    for (final controller in _chainBranchSearchControllers.values) {
      controller.dispose();
    }
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
    _customAgencyUsernameController.dispose();
    _customAgencyPasswordController.dispose();
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
          backgroundColor: colorScheme.onTertiaryFixedVariant,
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

  static final RegExp _generatedPromptCompanyRe =
      RegExp(r'^أنت مدقق فواتير فائق الدقة ومسؤول عن فحص وتدقيق فواتير عروض ومهرجانات شركة "([^"]*)"');

  /// True when the current prompt was produced by the rules generator for a
  /// different company than the one now selected (or is empty). Hand-written
  /// prompts are never touched.
  bool _promptNeedsCompanyRefresh() {
    final company = _targetCompanyController.text.trim();
    if (company.isEmpty) return false;
    final prompt = _customPromptController.text.trim();
    if (prompt.isEmpty) return true;
    final m = _generatedPromptCompanyRe.firstMatch(prompt);
    if (m == null) return false;
    return m.group(1)!.trim() != company;
  }

  void _syncPromptFromRules({bool showSnackbar = true}) {
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

    if (showSnackbar && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(ref).syncPromptSuccessMsg,
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          backgroundColor: colorScheme.onTertiaryFixedVariant,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
            backgroundColor: colorScheme.onSecondaryFixedVariant,
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
        linkedGiftId: matchedGift.id,
        linkedGiftName: matchedGift.giftName,
        linkedGifts: [
          LinkedGiftAllocation(giftId: matchedGift.id, giftName: matchedGift.giftName, quantity: 1, giftType: 'product'),
        ],
      );
      setState(() => _promotionalRules.add(newRule));
      _syncPromptFromRules(showSnackbar: false);
    } else if (presetKey == 'tresemme_single') {
      final matchedGift = _companyGifts.where((g) => g.giftName.contains('تريزيمي') || g.giftName.contains('Tresemme')).firstOrNull;
      if (matchedGift == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAr ? 'صنف هدية تريزيمي غير متوفر في مخزون هدايا الشركة حالياً' : 'Tresemme gift is not in company stock',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: colorScheme.onSecondaryFixedVariant,
          ),
        );
        return;
      }
      final newRule = PromotionalRuleItem(
        id: 'rule_${_promotionalRules.length + 1}',
        ruleTitle: 'عرض تريزيمي 400 مل (شراء 1 قطعة) -> هدية ${matchedGift.giftName}',
        triggerProduct: 'تريزيمي 400 مل، تريزيمى 400 مل، تريزمي 400، tresemme 400ml',
        minQuantity: 1,
        rewardType: 'free_product',
        rewardValue: matchedGift.giftName,
        rewardAmount: 0.0,
        linkedGiftId: matchedGift.id,
        linkedGiftName: matchedGift.giftName,
        linkedGifts: [
          LinkedGiftAllocation(giftId: matchedGift.id, giftName: matchedGift.giftName, quantity: 1, giftType: 'product'),
        ],
      );
      setState(() => _promotionalRules.add(newRule));
      _syncPromptFromRules(showSnackbar: false);
    } else if (presetKey == 'tresemme_shrink') {
      final matchedGift = _companyGifts.where((g) => g.giftName.contains('تريزيمي') || g.giftName.contains('Tresemme')).firstOrNull;
      if (matchedGift == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAr ? 'صنف هدية تريزيمي غير متوفر في مخزون هدايا الشركة حالياً' : 'Tresemme gift is not in company stock',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: colorScheme.onSecondaryFixedVariant,
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
        linkedGiftId: matchedGift.id,
        linkedGiftName: matchedGift.giftName,
        linkedGifts: [
          LinkedGiftAllocation(giftId: matchedGift.id, giftName: matchedGift.giftName, quantity: 1, giftType: 'product'),
        ],
      );
      setState(() => _promotionalRules.add(newRule));
      _syncPromptFromRules(showSnackbar: false);
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
        linkedGifts: decomposed,
        linkedGiftId: decomposed.firstOrNull?.giftId,
        linkedGiftName: decomposed.firstOrNull?.giftName,
      );
      setState(() => _promotionalRules.add(newRule));
      _syncPromptFromRules(showSnackbar: false);
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
        linkedGifts: decomposed,
        linkedGiftId: decomposed.firstOrNull?.giftId,
        linkedGiftName: decomposed.firstOrNull?.giftName,
      );
      setState(() => _promotionalRules.add(newRule));
      _syncPromptFromRules(showSnackbar: false);
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
        linkedGifts: decomposed,
        linkedGiftId: decomposed.firstOrNull?.giftId,
        linkedGiftName: decomposed.firstOrNull?.giftName,
      );
      setState(() => _promotionalRules.add(newRule));
      _syncPromptFromRules(showSnackbar: false);
    } else if (presetKey == 'sunsilk_2pc_50') {
      final decomposed = CampaignAiAssistantService.decomposeVoucherAmount(50.0, _companyGifts);
      final newRule = PromotionalRuleItem(
        id: 'rule_${_promotionalRules.length + 1}',
        ruleTitle: 'عرض صانسيلك (شراء قطعتين للحصول على فوتشر 50 ج.م)',
        triggerProduct: 'صانسيلك، صنسيلك، sunsilk، شامبو صانسيلك، بلسم صانسيلك، صانسيلك شامبو نعومه الحرير 350 مل + بلسم، 6221155611154',
        minQuantity: 2,
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات بقيمة 50 ج.م',
        rewardAmount: 50.0,
        linkedGifts: decomposed,
        linkedGiftId: decomposed.firstOrNull?.giftId,
        linkedGiftName: decomposed.firstOrNull?.giftName,
      );
      setState(() => _promotionalRules.add(newRule));
      _syncPromptFromRules(showSnackbar: false);
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
        linkedGifts: decomposed,
        linkedGiftId: decomposed.firstOrNull?.giftId,
        linkedGiftName: decomposed.firstOrNull?.giftName,
      );
      setState(() => _promotionalRules.add(newRule));
      _syncPromptFromRules(showSnackbar: false);
    } else if (presetKey == 'oral_bundle_100') {
      final decomposed = CampaignAiAssistantService.decomposeVoucherAmount(25.0, _companyGifts);
      final oralProducts = _companyProducts.where((p) {
        final n = p.productName.toLowerCase();
        return n.contains('سيجنال') || n.contains('كلوس') || n.contains('signal') || n.contains('close');
      }).toList();
      final newRule = PromotionalRuleItem(
        id: 'rule_${_promotionalRules.length + 1}',
        ruleTitle: 'حزمة العناية بالفم 1 (Signal أو Closeup بقيمة 100 ج.م) -> فواتشر 25 ج.م',
        triggerProduct: 'معجون أسنان سيجنال، معجون أسنان كلوس اب، Signal Toothpaste, Closeup Toothpaste',
        conditionType: 'by_spend',
        minSpend: 100.0,
        matchMode: 'OR',
        requiredBrands: ['سيجنال', 'كلوس اب'],
        selectedProductIds: oralProducts.map((p) => p.id).toList(),
        selectedBarcodes: oralProducts.map((p) => p.barcode).where((b) => b.isNotEmpty).toList(),
        selectedProductNames: oralProducts.map((p) => p.productName).toList(),
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات بقيمة 25 ج.م',
        rewardAmount: 25.0,
        linkedGifts: decomposed,
        linkedGiftId: decomposed.firstOrNull?.giftId,
        linkedGiftName: decomposed.firstOrNull?.giftName,
      );
      setState(() => _promotionalRules.add(newRule));
      _syncPromptFromRules(showSnackbar: false);
    } else if (presetKey == 'oral_bundle_150') {
      final decomposed = CampaignAiAssistantService.decomposeVoucherAmount(50.0, _companyGifts);
      final oralProducts = _companyProducts.where((p) {
        final n = p.productName.toLowerCase();
        return n.contains('سيجنال') || n.contains('كلوس') || n.contains('signal') || n.contains('close');
      }).toList();
      final newRule = PromotionalRuleItem(
        id: 'rule_${_promotionalRules.length + 1}',
        ruleTitle: 'حزمة العناية بالفم 2 (Signal أو Closeup بقيمة 150 ج.م) -> فواتشر 50 ج.م',
        triggerProduct: 'معجون أسنان سيجنال، معجون أسنان كلوس اب، Signal Toothpaste, Closeup Toothpaste',
        conditionType: 'by_spend',
        minSpend: 150.0,
        matchMode: 'OR',
        requiredBrands: ['سيجنال', 'كلوس اب'],
        selectedProductIds: oralProducts.map((p) => p.id).toList(),
        selectedBarcodes: oralProducts.map((p) => p.barcode).where((b) => b.isNotEmpty).toList(),
        selectedProductNames: oralProducts.map((p) => p.productName).toList(),
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات بقيمة 50 ج.م',
        rewardAmount: 50.0,
        linkedGifts: decomposed,
        linkedGiftId: decomposed.firstOrNull?.giftId,
        linkedGiftName: decomposed.firstOrNull?.giftName,
      );
      setState(() => _promotionalRules.add(newRule));
      _syncPromptFromRules(showSnackbar: false);
    } else if (presetKey == 'oral_bundle_200') {
      final decomposed = CampaignAiAssistantService.decomposeVoucherAmount(75.0, _companyGifts);
      final oralProducts = _companyProducts.where((p) {
        final n = p.productName.toLowerCase();
        return n.contains('سيجنال') || n.contains('كلوس') || n.contains('signal') || n.contains('close');
      }).toList();
      final newRule = PromotionalRuleItem(
        id: 'rule_${_promotionalRules.length + 1}',
        ruleTitle: 'حزمة العناية بالفم 3 (Signal أو Closeup بقيمة 200 ج.م) -> فواتشر 75 ج.م',
        triggerProduct: 'معجون أسنان سيجنال، معجون أسنان كلوس اب، Signal Toothpaste, Closeup Toothpaste',
        conditionType: 'by_spend',
        minSpend: 200.0,
        matchMode: 'OR',
        requiredBrands: ['سيجنال', 'كلوس اب'],
        selectedProductIds: oralProducts.map((p) => p.id).toList(),
        selectedBarcodes: oralProducts.map((p) => p.barcode).where((b) => b.isNotEmpty).toList(),
        selectedProductNames: oralProducts.map((p) => p.productName).toList(),
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات بقيمة 75 ج.م',
        rewardAmount: 75.0,
        linkedGifts: decomposed,
        linkedGiftId: decomposed.firstOrNull?.giftId,
        linkedGiftName: decomposed.firstOrNull?.giftName,
      );
      setState(() => _promotionalRules.add(newRule));
      _syncPromptFromRules(showSnackbar: false);
    } else if (presetKey == 'oral_bundle_range_all') {
      final oralProducts = _companyProducts.where((p) {
        final n = p.productName.toLowerCase();
        return n.contains('سيجنال') || n.contains('كلوس') || n.contains('signal') || n.contains('close');
      }).toList();

      final decomposed25 = CampaignAiAssistantService.decomposeVoucherAmount(25.0, _companyGifts);
      final decomposed50 = CampaignAiAssistantService.decomposeVoucherAmount(50.0, _companyGifts);
      final decomposed75 = CampaignAiAssistantService.decomposeVoucherAmount(75.0, _companyGifts);

      final rule1 = PromotionalRuleItem(
        id: 'rule_${_promotionalRules.length + 1}',
        ruleTitle: 'حزمة العناية بالفم 1 (Signal أو Closeup: نطاق 95 إلى 139 ج.م) -> فواتشر 25 ج.م',
        triggerProduct: 'معجون أسنان سيجنال، معجون أسنان كلوس اب، Signal Toothpaste, Closeup Toothpaste',
        conditionType: 'by_spend',
        minSpend: 95.0,
        maxSpend: 139.99,
        discountTolerance: 5.0,
        matchMode: 'OR',
        requiredBrands: ['سيجنال', 'كلوس اب'],
        selectedProductIds: oralProducts.map((p) => p.id).toList(),
        selectedBarcodes: oralProducts.map((p) => p.barcode).where((b) => b.isNotEmpty).toList(),
        selectedProductNames: oralProducts.map((p) => p.productName).toList(),
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات بقيمة 25 ج.م',
        rewardAmount: 25.0,
        linkedGifts: decomposed25,
        linkedGiftId: decomposed25.firstOrNull?.giftId,
        linkedGiftName: decomposed25.firstOrNull?.giftName,
      );

      final rule2 = PromotionalRuleItem(
        id: 'rule_${_promotionalRules.length + 2}',
        ruleTitle: 'حزمة العناية بالفم 2 (Signal أو Closeup: نطاق 140 إلى 189 ج.م) -> فواتشر 50 ج.م',
        triggerProduct: 'معجون أسنان سيجنال، معجون أسنان كلوس اب، Signal Toothpaste, Closeup Toothpaste',
        conditionType: 'by_spend',
        minSpend: 140.0,
        maxSpend: 189.99,
        discountTolerance: 5.0,
        matchMode: 'OR',
        requiredBrands: ['سيجنال', 'كلوس اب'],
        selectedProductIds: oralProducts.map((p) => p.id).toList(),
        selectedBarcodes: oralProducts.map((p) => p.barcode).where((b) => b.isNotEmpty).toList(),
        selectedProductNames: oralProducts.map((p) => p.productName).toList(),
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات بقيمة 50 ج.م',
        rewardAmount: 50.0,
        linkedGifts: decomposed50,
        linkedGiftId: decomposed50.firstOrNull?.giftId,
        linkedGiftName: decomposed50.firstOrNull?.giftName,
      );

      final rule3 = PromotionalRuleItem(
        id: 'rule_${_promotionalRules.length + 3}',
        ruleTitle: 'حزمة العناية بالفم 3 (Signal أو Closeup: نطاق 190+ ج.م) -> فواتشر 75 ج.م',
        triggerProduct: 'معجون أسنان سيجنال، معجون أسنان كلوس اب، Signal Toothpaste, Closeup Toothpaste',
        conditionType: 'by_spend',
        minSpend: 190.0,
        discountTolerance: 10.0,
        matchMode: 'OR',
        requiredBrands: ['سيجنال', 'كلوس اب'],
        selectedProductIds: oralProducts.map((p) => p.id).toList(),
        selectedBarcodes: oralProducts.map((p) => p.barcode).where((b) => b.isNotEmpty).toList(),
        selectedProductNames: oralProducts.map((p) => p.productName).toList(),
        rewardType: 'voucher',
        rewardValue: 'قسيمة مشتريات بقيمة 75 ج.م',
        rewardAmount: 75.0,
        linkedGifts: decomposed75,
        linkedGiftId: decomposed75.firstOrNull?.giftId,
        linkedGiftName: decomposed75.firstOrNull?.giftName,
      );

      setState(() {
        _promotionalRules.addAll([rule1, rule2, rule3]);
      });
      _syncPromptFromRules(showSnackbar: false);
    }
  }

  Future<void> _showCatalogProductPickerDialog({
    required BuildContext context,
    required List<String> initialSelectedIds,
    required Function(List<CompanyProductItem> selectedItems) onConfirm,
  }) async {
    final strings = AppStrings.of(ref);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final Set<String> selectedIds = Set<String>.from(initialSelectedIds);
    String searchQuery = '';
    String selectedBrand = '';
    final effectiveSlug = _companySlugController.text.trim().toLowerCase();
    final brandCounts = _extractBrandCountsFromProducts(_companyProducts, companySlug: effectiveSlug);

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final filteredProducts = _filterCompanyProducts(
              products: _companyProducts,
              searchQuery: searchQuery,
              selectedBrand: selectedBrand,
              companySlug: effectiveSlug,
            );

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.inventory_2_rounded, color: colorScheme.primary, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          strings.chooseProductsFromCatalogTitle,
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (val) => setDialogState(() => searchQuery = val),
                    decoration: InputDecoration(
                      hintText: _getSearchHintText(companySlug: effectiveSlug),
                      hintStyle: GoogleFonts.cairo(fontSize: 12.5),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (brandCounts.isNotEmpty) ...[
                    _buildBrandFilterChipsWidget(
                      context: context,
                      brandCounts: brandCounts,
                      totalCount: _companyProducts.length,
                      selectedBrand: selectedBrand,
                      onSelectBrand: (brand) {
                        setDialogState(() => selectedBrand = brand);
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.select_all_rounded, size: 16),
                        label: Text(
                          'تحديد المعروض (${filteredProducts.length})',
                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          setDialogState(() {
                            for (final p in filteredProducts) {
                              selectedIds.add(p.id);
                            }
                          });
                        },
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.deselect_rounded, size: 16),
                        label: Text(strings.deselectAll, style: GoogleFonts.cairo(fontSize: 12)),
                        onPressed: () {
                          setDialogState(() {
                            for (final p in filteredProducts) {
                              selectedIds.remove(p.id);
                            }
                          });
                        },
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${selectedIds.length} صنف محدد',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              content: SizedBox(
                width: 600,
                height: 420,
                child: filteredProducts.isEmpty
                    ? Center(
                        child: Text(
                          _companyProducts.isEmpty
                              ? 'لم يتم تحميل أي أصناف لكتالوج الشركة الحالي.'
                              : 'لا توجد منتجات مطابقة لكلمة البحث.',
                          style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filteredProducts.length,
                        separatorBuilder: (context, i) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = filteredProducts[index];
                          final isChecked = selectedIds.contains(item.id);
                          return CheckboxListTile(
                            value: isChecked,
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              item.productName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            subtitle: Wrap(
                              spacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (item.barcode.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '🏷️ ${item.barcode}',
                                      style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5),
                                    ),
                                  ),
                                if (item.unitSize.isNotEmpty)
                                  Text(item.unitSize, style: const TextStyle(fontSize: 11)),
                                if (item.referencePrice != null && item.referencePrice! > 0)
                                  Text('${item.referencePrice} ج.م', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.tertiary)),
                              ],
                            ),
                            onChanged: (val) {
                              setDialogState(() {
                                if (val == true) {
                                  selectedIds.add(item.id);
                                } else {
                                  selectedIds.remove(item.id);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text(strings.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    final selectedItems = _companyProducts.where((p) => selectedIds.contains(p.id)).toList();
                    onConfirm(selectedItems);
                    Navigator.pop(dialogCtx);
                  },
                  child: Text('تأكيد الاختيار (${selectedIds.length})'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showSelectedProductsViewerDialog(PromotionalRuleItem rule) async {
    final colorScheme = Theme.of(context).colorScheme;

    // Resolve products from company catalog
    List<CompanyProductItem> matchedProducts = [];
    if (rule.selectedProductIds.isNotEmpty) {
      final idSet = rule.selectedProductIds.toSet();
      matchedProducts = _companyProducts.where((p) => idSet.contains(p.id)).toList();
    }
    if (matchedProducts.isEmpty && rule.selectedBarcodes.isNotEmpty) {
      final barcodeSet = rule.selectedBarcodes.toSet();
      matchedProducts = _companyProducts.where((p) => barcodeSet.contains(p.barcode)).toList();
    }
    if (matchedProducts.isEmpty && rule.selectedProductNames.isNotEmpty) {
      final nameSet = rule.selectedProductNames.toSet();
      matchedProducts = _companyProducts.where((p) => nameSet.contains(p.productName)).toList();
    }

    final List<Map<String, String>> displayItems = [];
    if (matchedProducts.isNotEmpty) {
      for (final p in matchedProducts) {
        displayItems.add({
          'name': p.productName,
          'barcode': p.barcode,
          'unit': p.unitSize,
          'price': p.referencePrice != null && p.referencePrice! > 0 ? '${p.referencePrice} ج.م' : '',
        });
      }
    } else {
      for (int i = 0; i < rule.selectedProductNames.length; i++) {
        final name = rule.selectedProductNames[i];
        final barcode = i < rule.selectedBarcodes.length ? rule.selectedBarcodes[i] : '';
        displayItems.add({
          'name': name,
          'barcode': barcode,
          'unit': '',
          'price': '',
        });
      }
    }

    // Extract brand clusters from matched items
    final Map<String, int> brandBreakdown = {};
    final effectiveSlug = _companySlugController.text.trim().toLowerCase();
    final candidateBrands = _getCompanyBrands(companySlug: effectiveSlug).isNotEmpty
        ? _getCompanyBrands(companySlug: effectiveSlug)
        : ['فاين', 'إيزي', 'سندريلا', 'دوف', 'ريكسونا', 'سيجنال', 'كلوس اب', 'تريزيمي', 'كلير', 'لوكس', 'أكس', 'صنسيلك', 'فازلين', 'لايفبوي', 'المراعي'];

    for (final it in displayItems) {
      final name = it['name'] ?? '';
      for (final brand in candidateBrands) {
        if (_productMatchesBrandName(name, brand, companySlug: effectiveSlug)) {
          brandBreakdown[brand] = (brandBreakdown[brand] ?? 0) + 1;
        }
      }
    }

    String localSearch = '';
    String localBrand = '';

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filtered = displayItems.where((item) {
              final name = item['name'] ?? '';
              final barcode = item['barcode'] ?? '';
              final norm = _normalizeCatalogSearchText(name);

              if (localBrand.isNotEmpty) {
                if (!_productMatchesBrandName(name, localBrand, companySlug: effectiveSlug)) return false;
              }

              if (localSearch.trim().isEmpty) return true;
              final q = localSearch.trim().toLowerCase();
              return norm.contains(_normalizeCatalogSearchText(q)) ||
                  name.toLowerCase().contains(q) ||
                  barcode.contains(q);
            }).toList();

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              actionsPadding: const EdgeInsets.all(16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.format_list_bulleted_rounded, color: colorScheme.primary, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الأصناف والباركودات المربوطة بالشرط',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          rule.ruleTitle,
                          style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colorScheme.tertiaryFixedDim),
                    ),
                    child: Text(
                      '${displayItems.length} صنف',
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onTertiaryContainer),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 650,
                height: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      style: GoogleFonts.cairo(fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: 'بحث سريع في أصناف هذا الشرط أو الباركود...',
                        hintStyle: GoogleFonts.cairo(fontSize: 12.5),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        suffixIcon: localSearch.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () => setDialogState(() => localSearch = ''),
                              )
                            : null,
                        isDense: true,
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) => setDialogState(() => localSearch = val),
                    ),
                    const SizedBox(height: 8),
                    if (brandBreakdown.isNotEmpty) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 6),
                              child: ChoiceChip(
                                label: Text('الكل (${displayItems.length})', style: GoogleFonts.cairo(fontSize: 11.5)),
                                selected: localBrand.isEmpty,
                                onSelected: (_) => setDialogState(() => localBrand = ''),
                              ),
                            ),
                            ...brandBreakdown.entries.map((e) {
                              return Padding(
                                padding: const EdgeInsetsDirectional.only(end: 6),
                                child: ChoiceChip(
                                  label: Text('${e.key} (${e.value})', style: GoogleFonts.cairo(fontSize: 11.5)),
                                  selected: localBrand == e.key,
                                  onSelected: (_) => setDialogState(() => localBrand = e.key),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const Divider(height: 1),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                'لا توجد أصناف مطابقة للبحث.',
                                style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, idx) {
                                final item = filtered[idx];
                                return ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  leading: CircleAvatar(
                                    radius: 13,
                                    backgroundColor: colorScheme.primaryContainer,
                                    child: Text(
                                      '${idx + 1}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    item['name'] ?? '',
                                    style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Wrap(
                                    spacing: 8,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      if ((item['barcode'] ?? '').isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: colorScheme.surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '🏷️ ${item['barcode']}',
                                            style: GoogleFonts.robotoMono(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      if ((item['unit'] ?? '').isNotEmpty)
                                        Text(
                                          item['unit']!,
                                          style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                        ),
                                      if ((item['price'] ?? '').isNotEmpty)
                                        Text(
                                          item['price']!,
                                          style: GoogleFonts.cairo(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onTertiaryFixedVariant,
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
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('إغلاق', style: GoogleFonts.cairo()),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<RuleConflictIssue> _detectRuleConflicts() {
    final conflicts = <RuleConflictIssue>[];
    if (_promotionalRules.isEmpty) return conflicts;

    // 1. Check title vs quantity mismatch (ONLY for by_quantity rules)
    for (int i = 0; i < _promotionalRules.length; i++) {
      final rule = _promotionalRules[i];
      if (rule.conditionType != 'by_quantity') continue;

      final title = rule.ruleTitle.trim();
      final titleHas1 = RegExp(r'(شراء\s*1\s*قطعة|شراء\s*1\s*قطعه|1\s*قطعة|1\s*قطعه|قطعة\s*واحدة|قطعه\s*واحده)').hasMatch(title);
      final titleHas2 = RegExp(r'(شراء\s*2\s*قطعة|شراء\s*2\s*قطعه|2\s*قطعة|2\s*قطعه|قطعتين|قطعتان|2\s*قطع|2\s*ق|شرنك)').hasMatch(title);

      if (titleHas1 && rule.minQuantity > 1) {
        conflicts.add(RuleConflictIssue(
          title: 'تضارب في القاعدة #${i + 1} (${rule.ruleTitle})',
          description: 'عنوان القاعدة يذكر (شراء 1 قطعة) بينما الحد الأدنى المضبوط برمجياً هو (${rule.minQuantity}) قطعة.',
          conflictingRuleIndices: [i],
          suggestedFixLabel: 'ضبط الحد الأدنى إلى 1 قطعة فوراً ⚡',
          onResolve: () {
            setState(() {
              _promotionalRules[i] = rule.copyWith(minQuantity: 1);
            });
            _syncPromptFromRules(showSnackbar: false);
          },
        ));
      } else if (titleHas2 && rule.minQuantity == 1 && !rule.triggerProduct.contains('شرنك') && !rule.triggerProduct.contains('مزدوج') && !rule.triggerProduct.contains('بندل') && !rule.triggerProduct.contains('باندل')) {
        conflicts.add(RuleConflictIssue(
          title: 'تضارب في القاعدة #${i + 1} (${rule.ruleTitle})',
          description: 'عنوان القاعدة يذكر (شراء 2 قطعة) بينما الحد الأدنى المضبوط برمجياً هو (1) قطعة.',
          conflictingRuleIndices: [i],
          suggestedFixLabel: 'ضبط الحد الأدنى إلى 2 قطعة فوراً ⚡',
          onResolve: () {
            setState(() {
              _promotionalRules[i] = rule.copyWith(minQuantity: 2);
            });
            _syncPromptFromRules(showSnackbar: false);
          },
        ));
      }
    }

    // 2. Check duplicate / conflicting rules with identical trigger products AND identical threshold (spend or quantity)
    for (int i = 0; i < _promotionalRules.length; i++) {
      for (int j = i + 1; j < _promotionalRules.length; j++) {
        final ruleA = _promotionalRules[i];
        final ruleB = _promotionalRules[j];

        final normA = _normalizeProductKeywords(ruleA.triggerProduct);
        final normB = _normalizeProductKeywords(ruleB.triggerProduct);

        final bool isSimilarProduct = (normA.isNotEmpty && normB.isNotEmpty) &&
            (normA == normB || (normA.length > 5 && normB.length > 5 && (normA.contains(normB) || normB.contains(normA))));

        if (!isSimilarProduct) continue;

        // Check if condition types match
        final bool sameConditionType = ruleA.conditionType == ruleB.conditionType;
        if (!sameConditionType) continue;

        // Spend-based conditions (by_spend, combo_spend)
        if (ruleA.conditionType == 'by_spend' || ruleA.conditionType == 'combo_spend') {
          // If spend thresholds differ (e.g. 100 vs 150 vs 200), this is a tiered offer, NOT a conflict!
          if ((ruleA.minSpend - ruleB.minSpend).abs() < 0.01 && ruleA.matchMode == ruleB.matchMode) {
            conflicts.add(RuleConflictIssue(
              title: 'تكرار متعارض بين القاعدة #${i + 1} والقاعدة #${j + 1}',
              description: 'كلا القاعدتين تشترطان نفس الأصناف ونفس المبلغ (${ruleA.minSpend.toInt()} ج.م) ولكن بمكافأتين منفصلتين.',
              conflictingRuleIndices: [i, j],
              suggestedFixLabel: 'حذف القاعدة المكررة #${j + 1} 🗑️',
              onResolve: () {
                setState(() {
                  _promotionalRules.removeAt(j);
                });
                _syncPromptFromRules(showSnackbar: false);
              },
            ));
          }
        } else {
          // Quantity-based conditions (by_quantity)
          // If minimum quantities differ (e.g. 1 piece vs 2 pieces), this is a tiered offer, NOT a conflict!
          if (ruleA.minQuantity == ruleB.minQuantity) {
            conflicts.add(RuleConflictIssue(
              title: 'تكرار متعارض بين القاعدة #${i + 1} والقاعدة #${j + 1}',
              description: 'كلا القاعدتين تشترطان نفس الأصناف (${ruleA.triggerProduct}) بنفس الكمية (${ruleA.minQuantity}) ولكن بمكافأتين منفصلتين.',
              conflictingRuleIndices: [i, j],
              suggestedFixLabel: 'حذف القاعدة المكررة #${j + 1} 🗑️',
              onResolve: () {
                setState(() {
                  _promotionalRules.removeAt(j);
                });
                _syncPromptFromRules(showSnackbar: false);
              },
            ));
          }
        }
      }
    }

    return conflicts;
  }

  String _normalizeProductKeywords(String s) {
    return s.toLowerCase()
        .replaceAll(RegExp(r'[\s,\.،/\+\-_]+'), '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');
  }

  void _showAddOrEditPromotionalRuleDialog(BuildContext context, {int? ruleIndex}) {
    final strings = AppStrings.of(ref);
    final isEditing = ruleIndex != null && ruleIndex >= 0 && ruleIndex < _promotionalRules.length;
    final existingRule = isEditing ? _promotionalRules[ruleIndex] : null;

    final titleController = TextEditingController(text: existingRule?.ruleTitle ?? '');
    final triggerController = TextEditingController(text: existingRule?.triggerProduct ?? '');
    final minQtyController = TextEditingController(text: (existingRule?.minQuantity ?? 1).toString());
    final minSpendController = TextEditingController(
      text: existingRule?.isSpendBased == true && existingRule!.minSpend > 0
          ? existingRule.minSpend.toInt().toString()
          : (existingRule != null && existingRule.conditionType == 'by_quantity' ? '' : (existingRule?.minSpend ?? 100.0).toInt().toString()),
    );
    final maxSpendController = TextEditingController(
      text: existingRule?.maxSpend != null && existingRule!.maxSpend! > 0
          ? existingRule.maxSpend!.toInt().toString()
          : '',
    );
    final discountToleranceController = TextEditingController(
      text: existingRule != null && existingRule.discountTolerance > 0
          ? existingRule.discountTolerance.toInt().toString()
          : '5',
    );
    final rewardValController = TextEditingController(text: existingRule?.rewardValue ?? '');
    final rewardAmtController = TextEditingController(text: (existingRule?.rewardAmount ?? 0.0).toString());
    String conditionType = existingRule?.conditionType ?? 'by_quantity';
    String rewardType = existingRule?.rewardType ?? 'free_product';
    String? selectedRuleGameType = existingRule?.gameType;
    List<String> selectedProductIds = List<String>.from(existingRule?.selectedProductIds ?? []);
    List<String> selectedBarcodes = List<String>.from(existingRule?.selectedBarcodes ?? []);
    List<String> selectedProductNames = List<String>.from(existingRule?.selectedProductNames ?? []);
    List<String> requiredBrands = List<String>.from(existingRule?.requiredBrands ?? []);
    String matchMode = existingRule?.matchMode ?? 'OR';

    CompanyGiftModel? selectedGift = existingRule?.linkedGiftId != null
        ? _companyGifts.where((g) => g.id == existingRule!.linkedGiftId).firstOrNull
        : null;
    List<LinkedGiftAllocation> dialogLinkedGifts = List<LinkedGiftAllocation>.from(existingRule?.linkedGifts ?? []);
    // "خيارات المكافأة": optional list; customer picks exactly one at handover.
    final List<RewardOption> dialogRewardOptions = List<RewardOption>.from(existingRule?.rewardOptions ?? const []);
    final optionVoucherCtrl = TextEditingController();
    final optionLabelCtrl = TextEditingController();
    if (dialogLinkedGifts.isEmpty && selectedGift != null) {
      dialogLinkedGifts.add(LinkedGiftAllocation(
        giftId: selectedGift.id,
        giftName: selectedGift.giftName,
        quantity: 1,
        unitValue: selectedGift.unitValue,
        giftType: selectedGift.giftType,
        imageUrl: selectedGift.imageUrl,
      ));
    }

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final double currentAllocatedTotal = dialogLinkedGifts.fold<double>(
              0.0,
              (runningTotal, item) => runningTotal + (item.unitValue * item.quantity),
            );
            final double targetVoucherAmt = double.tryParse(rewardAmtController.text.trim()) ?? 0.0;
            final bool isVoucherMatch = rewardType != 'voucher' || (targetVoucherAmt > 0 && (currentAllocatedTotal - targetVoucherAmt).abs() < 0.01);

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
                  width: 580,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Condition Type Selector
                      Text(
                        strings.conditionTypeLabel,
                        style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      SegmentedButton<String>(
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        segments: [
                          ButtonSegment(
                            value: 'by_quantity',
                            label: Text(strings.byQuantityCondition, style: const TextStyle(fontSize: 11)),
                            icon: const Icon(Icons.pin_rounded, size: 15),
                          ),
                          ButtonSegment(
                            value: 'by_spend',
                            label: Text(strings.bySpendCondition, style: const TextStyle(fontSize: 11)),
                            icon: const Icon(Icons.attach_money_rounded, size: 15),
                          ),
                          ButtonSegment(
                            value: 'combo_spend',
                            label: Text(strings.comboSpendCondition, style: const TextStyle(fontSize: 11)),
                            icon: const Icon(Icons.join_inner_rounded, size: 15),
                          ),
                        ],
                        selected: {conditionType},
                        onSelectionChanged: (set) {
                          setDialogState(() {
                            conditionType = set.first;
                            if (conditionType == 'combo_spend') {
                              matchMode = 'AND';
                              if (requiredBrands.isEmpty) {
                                requiredBrands = ['سيجنال', 'كلوس اب'];
                              }
                            } else {
                              matchMode = 'OR';
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: titleController,
                        decoration: InputDecoration(
                          labelText: strings.ruleTitleLabel,
                          hintText: conditionType == 'combo_spend'
                              ? 'مثال: حزمة سيجنال + كلوس اب بقيمة 100 ج.م -> فواتشر 25 ج.م'
                              : 'مثال: عرض اسبراي ريكسونا أو أكس (قطعتين)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Product Catalog Picker Card
                      if (_companyProducts.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: selectedProductIds.isNotEmpty
                                ? colorScheme.tertiaryContainer
                                : colorScheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selectedProductIds.isNotEmpty
                                  ? colorScheme.tertiaryFixedDim
                                  : colorScheme.outlineVariant,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.inventory_2_rounded,
                                    size: 18,
                                    color: selectedProductIds.isNotEmpty ? colorScheme.onTertiaryFixedVariant : colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      selectedProductIds.isNotEmpty
                                          ? 'تم ربط ${selectedProductIds.length} صنف و ${selectedBarcodes.length} باركود من الكتالوج'
                                          : 'ربط الأصناف والباركودات من كتالوج الشركة مباشرة',
                                      style: GoogleFonts.cairo(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: selectedProductIds.isNotEmpty ? colorScheme.onTertiaryContainer : colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  FilledButton.tonalIcon(
                                    style: FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    ),
                                    icon: const Icon(Icons.playlist_add_check_rounded, size: 16),
                                    label: Text(
                                      selectedProductIds.isNotEmpty ? 'تعديل الأصناف' : strings.selectFromCatalogBtn,
                                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                    onPressed: () {
                                      _showCatalogProductPickerDialog(
                                        context: context,
                                        initialSelectedIds: selectedProductIds,
                                        onConfirm: (items) {
                                          setDialogState(() {
                                            selectedProductIds = items.map((e) => e.id).toList();
                                            selectedBarcodes = items.map((e) => e.barcode).where((b) => b.isNotEmpty).toList();
                                            selectedProductNames = items.map((e) => e.productName).toList();
                                            // Auto-detect brands
                                            final Set<String> detectedBrands = {};
                                            final effectiveSlug = _companySlugController.text.trim().toLowerCase();
                                            final brandsToCheck = _getCompanyBrands(companySlug: effectiveSlug).isNotEmpty
                                                ? _getCompanyBrands(companySlug: effectiveSlug)
                                                : ['فاين', 'إيزي', 'سندريلا', 'دوف', 'ريكسونا', 'سيجنال', 'كلوس اب', 'تريزيمي', 'كلير', 'لوكس', 'أكس', 'صنسيلك', 'فازلين', 'لايفبوي', 'كاماي', 'المراعي'];

                                            for (final item in items) {
                                              for (final brand in brandsToCheck) {
                                                if (_productMatchesBrandName(item.productName, brand, companySlug: effectiveSlug)) {
                                                  detectedBrands.add(brand);
                                                }
                                              }
                                            }
                                            if (detectedBrands.isNotEmpty) {
                                              requiredBrands = detectedBrands.toList();
                                            }

                                            if (items.isNotEmpty) {
                                              if (detectedBrands.isNotEmpty) {
                                                triggerController.text = 'منتجات ${detectedBrands.join(' و ')} (${items.length} صنف)';
                                              } else if (items.length > 3) {
                                                triggerController.text = '${items.length} صنف محدد من الكتالوج';
                                              } else {
                                                triggerController.text = items.map((e) => e.productName).join('، ');
                                              }
                                            }
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ],
                              ),
                              if (selectedProductNames.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    ...requiredBrands.map((b) {
                                      return Container(
                                        padding: const EdgeInsetsDirectional.only(start: 8, end: 4, top: 2, bottom: 2),
                                        decoration: BoxDecoration(
                                          color: colorScheme.tertiaryContainer,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: colorScheme.tertiaryFixedDim),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '🏷️ $b',
                                              style: GoogleFonts.cairo(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.onTertiaryContainer,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Tooltip(
                                              message: 'حذف علامة $b وكافة أصنافها وباركوداتها من هذه القاعدة',
                                              child: InkWell(
                                                borderRadius: BorderRadius.circular(10),
                                                onTap: () {
                                                  setDialogState(() {
                                                    // 1. Identify all products, barcodes, and names matching brand b
                                                    final Set<String> idsToRemove = {};
                                                    final Set<String> barcodesToRemove = {};
                                                    final Set<String> namesToRemove = {};

                                                    for (final p in _companyProducts) {
                                                      if (_productMatchesBrandName(p.productName, b)) {
                                                        idsToRemove.add(p.id);
                                                        if (p.barcode.isNotEmpty) barcodesToRemove.add(p.barcode);
                                                        namesToRemove.add(p.productName);
                                                      }
                                                    }

                                                    for (final name in selectedProductNames) {
                                                      if (_productMatchesBrandName(name, b)) {
                                                        namesToRemove.add(name);
                                                      }
                                                    }

                                                    // 2. Remove matching items from selected lists
                                                    selectedProductIds.removeWhere((id) => idsToRemove.contains(id));
                                                    selectedBarcodes.removeWhere((bc) => barcodesToRemove.contains(bc));
                                                    selectedProductNames.removeWhere((name) => namesToRemove.contains(name));

                                                    // 3. Re-detect brands from the remaining products
                                                    final Set<String> remainingDetectedBrands = {};
                                                    final effectiveSlug = _companySlugController.text.trim().toLowerCase();
                                                    final candidateBrands = _getCompanyBrands(companySlug: effectiveSlug).isNotEmpty
                                                        ? _getCompanyBrands(companySlug: effectiveSlug)
                                                        : ['فاين', 'إيزي', 'سندريلا', 'دوف', 'ريكسونا', 'سيجنال', 'كلوس اب', 'تريزيمي', 'كلير', 'لوكس', 'أكس', 'صنسيلك', 'فازلين', 'لايفبوي', 'كاماي', 'المراعي'];

                                                    for (final name in selectedProductNames) {
                                                      for (final candidate in candidateBrands) {
                                                        if (_productMatchesBrandName(name, candidate, companySlug: effectiveSlug) && candidate != b) {
                                                          remainingDetectedBrands.add(candidate);
                                                        }
                                                      }
                                                    }
                                                    if (remainingDetectedBrands.isNotEmpty) {
                                                      requiredBrands = remainingDetectedBrands.toList();
                                                    } else {
                                                      requiredBrands.remove(b);
                                                    }

                                                    // 4. Update triggerController.text accordingly
                                                    if (selectedProductNames.isNotEmpty) {
                                                      if (requiredBrands.isNotEmpty) {
                                                        triggerController.text = 'منتجات ${requiredBrands.join(' و ')} (${selectedProductNames.length} صنف)';
                                                      } else {
                                                        triggerController.text = '${selectedProductNames.length} صنف محدد من الكتالوج';
                                                      }
                                                    } else {
                                                      selectedProductIds.clear();
                                                      selectedBarcodes.clear();
                                                      selectedProductNames.clear();
                                                      requiredBrands.clear();
                                                      triggerController.clear();
                                                    }
                                                  });
                                                },
                                                child: Padding(
                                                  padding: const EdgeInsets.all(2.0),
                                                  child: Icon(
                                                    Icons.cancel_rounded,
                                                    size: 15,
                                                    color: colorScheme.onErrorContainer,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: colorScheme.tertiaryFixedDim),
                                      ),
                                      child: Text(
                                        'إجمالي: ${selectedProductNames.length} صنف و ${selectedBarcodes.length} باركود',
                                        style: GoogleFonts.cairo(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onTertiaryContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      TextFormField(
                        controller: triggerController,
                        decoration: InputDecoration(
                          labelText: strings.triggerProductLabel,
                          hintText: 'مثال: معجون أسنان سيجنال، كلوس اب، اسبراي أكس',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (conditionType == 'combo_spend') ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: colorScheme.primaryFixedDim),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                strings.requiredBrandsLabel,
                                style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                children: ['سيجنال', 'كلوس اب', 'تريزيمي', 'ريكسونا', 'أكس', 'كلير'].map((b) {
                                  final isSelected = requiredBrands.contains(b);
                                  return FilterChip(
                                    label: Text(b, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                                    selected: isSelected,
                                    onSelected: (val) {
                                      setDialogState(() {
                                        if (val) {
                                          requiredBrands.add(b);
                                        } else {
                                          requiredBrands.remove(b);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      if (conditionType == 'by_quantity') ...[
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
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: rewardType,
                                decoration: InputDecoration(
                                  labelText: strings.rewardTypeLabel,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  isDense: true,
                                ),
                                items: [
                                  DropdownMenuItem(value: 'voucher', child: Text(strings.voucherRewardLabel)),
                                  DropdownMenuItem(value: 'free_product', child: Text(strings.freeProductRewardLabel)),
                                  DropdownMenuItem(value: 'game_spin', child: Text(strings.gameSpinRewardLabel)),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(() {
                                      rewardType = val;
                                      if (rewardType == 'voucher' && dialogLinkedGifts.isEmpty && targetVoucherAmt > 0) {
                                        dialogLinkedGifts = CampaignAiAssistantService.decomposeVoucherAmount(targetVoucherAmt, _companyGifts);
                                      }
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        // Spend Range Row (Min & Max Spend)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colorScheme.secondaryFixedDim),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.tune_rounded, size: 16, color: colorScheme.onSecondaryFixedVariant),
                                  const SizedBox(width: 6),
                                  Text(
                                    'نطاق القيمة المالية وسماحية الخصم:',
                                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSecondaryFixedVariant),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: minSpendController,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'الحد الأدنى (من ج.م)',
                                        hintText: '95',
                                        prefixIcon: const Icon(Icons.arrow_forward_rounded, size: 16),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        isDense: true,
                                        fillColor: Colors.white,
                                        filled: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextFormField(
                                      controller: maxSpendController,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'الحد الأقصى (إلى ج.م)',
                                        hintText: '139 (أو اتركه فارغاً)',
                                        prefixIcon: const Icon(Icons.arrow_back_rounded, size: 16),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        isDense: true,
                                        fillColor: Colors.white,
                                        filled: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: rewardType,
                                      decoration: InputDecoration(
                                        labelText: strings.rewardTypeLabel,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        isDense: true,
                                        fillColor: Colors.white,
                                        filled: true,
                                      ),
                                      items: [
                                        DropdownMenuItem(value: 'voucher', child: Text(strings.voucherRewardLabel)),
                                        DropdownMenuItem(value: 'free_product', child: Text(strings.freeProductRewardLabel)),
                                        DropdownMenuItem(value: 'game_spin', child: Text(strings.gameSpinRewardLabel)),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) {
                                          setDialogState(() {
                                            rewardType = val;
                                            if (rewardType == 'voucher' && dialogLinkedGifts.isEmpty && targetVoucherAmt > 0) {
                                              dialogLinkedGifts = CampaignAiAssistantService.decomposeVoucherAmount(targetVoucherAmt, _companyGifts);
                                            }
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextFormField(
                                      controller: discountToleranceController,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'سماحية الخصم (ج.م)',
                                        hintText: '5',
                                        prefixIcon: const Icon(Icons.price_check_rounded, size: 16),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        isDense: true,
                                        fillColor: Colors.white,
                                        filled: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '💡 تتيح السماحية قبول الفواتير حتى لو انخفض الصافي بعد الخصومات (مثال: 95 ج.م بدلاً من 100 ج.م)',
                                style: GoogleFonts.cairo(fontSize: 10.5, color: colorScheme.onSecondaryFixedVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: rewardValController,
                        decoration: InputDecoration(
                          labelText: 'نص الجائزة / المكافأة',
                          hintText: 'مثال: قسيمة مشتريات بقيمة 75 ج.م أو كلير 90 مل هدية',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (rewardType == 'voucher') ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: rewardAmtController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'المبلغ الإجمالي للفاوتشر (ج.م)',
                                  hintText: '75',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  isDense: true,
                                ),
                                onChanged: (val) {
                                  final numVal = double.tryParse(val.trim()) ?? 0.0;
                                  if (numVal > 0) {
                                    setDialogState(() {
                                      if (rewardValController.text.isEmpty || rewardValController.text.contains('قسيمة') || rewardValController.text.contains('فواتشر')) {
                                        rewardValController.text = 'قسيمة مشتريات بقيمة ${numVal.toInt()} ج.م';
                                      }
                                      dialogLinkedGifts = CampaignAiAssistantService.decomposeVoucherAmount(numVal, _companyGifts);
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                              label: Text(
                                'تفكيك تلقائي',
                                style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold),
                              ),
                              onPressed: () {
                                final numVal = double.tryParse(rewardAmtController.text.trim()) ?? 0.0;
                                if (numVal > 0) {
                                  setDialogState(() {
                                    dialogLinkedGifts = CampaignAiAssistantService.decomposeVoucherAmount(numVal, _companyGifts);
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Game Type Delivery Selector for this specific Rule / Tier
                      Builder(
                        builder: (fieldCtx) {
                          final fColorScheme = Theme.of(fieldCtx).colorScheme;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: fColorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: fColorScheme.outlineVariant.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.sports_esports_rounded, size: 20, color: fColorScheme.primary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: DropdownButtonFormField<String?>(
                                    initialValue: selectedRuleGameType,
                                    decoration: InputDecoration(
                                      labelText: 'طريقة تسليم الجائزة (نوع اللعبة للشريحة)',
                                      labelStyle: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                                      border: InputBorder.none,
                                      isDense: true,
                                    ),
                                    style: GoogleFonts.cairo(fontSize: 12.5, color: fColorScheme.onSurface),
                                items: [
                                  DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text(
                                      '⚙️ الافتراضي (حسب لعبة الحملة العامة: ${_selectedGameType == 'scratch' ? 'خربش واكسب' : (_selectedGameType == 'wheel' ? 'عجلة الحظ' : (_selectedGameType == 'directGift' ? 'هدية فورية' : 'اختر هديتك'))})',
                                      style: GoogleFonts.cairo(fontWeight: FontWeight.normal),
                                    ),
                                  ),
                                  DropdownMenuItem<String?>(
                                    value: 'directGift',
                                    child: Row(
                                      children: [
                                        Icon(Icons.redeem_rounded, size: 16, color: colorScheme.tertiary),
                                        const SizedBox(width: 6),
                                        Text(
                                          '🎁 هدية فورية مباشرة (Direct Gift)',
                                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: colorScheme.onTertiaryFixedVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                  DropdownMenuItem<String?>(
                                    value: 'scratch',
                                    child: Row(
                                      children: [
                                        Icon(Icons.style_rounded, size: 16, color: colorScheme.primary),
                                        const SizedBox(width: 6),
                                        Text(
                                          '🎟️ كارت خربش واكسب (Scratch Card)',
                                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: colorScheme.onPrimaryFixedVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                  DropdownMenuItem<String?>(
                                    value: 'wheel',
                                    child: Row(
                                      children: [
                                        Icon(Icons.casino_rounded, size: 16, color: colorScheme.primary),
                                        const SizedBox(width: 6),
                                        Text(
                                          '🎡 عجلة الحظ (Spin The Wheel)',
                                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: colorScheme.onPrimaryFixedVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                  DropdownMenuItem<String?>(
                                    value: 'chooseGift',
                                    child: Row(
                                      children: [
                                        Icon(Icons.grid_view_rounded, size: 16, color: colorScheme.secondary),
                                        const SizedBox(width: 6),
                                        Text(
                                          '📦 اختر هديتك (Choose Gift)',
                                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: colorScheme.onSecondaryFixedVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                onChanged: (val) {
                                  setDialogState(() {
                                    selectedRuleGameType = val;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                      // Multi-Gift / Multi-Voucher Allocation Builder Inside Dialog
                      if (_companyGifts.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isVoucherMatch
                                ? colorScheme.tertiaryContainer.withValues(alpha: 0.5)
                                : colorScheme.secondaryContainer.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isVoucherMatch
                                  ? colorScheme.tertiaryFixedDim
                                  : colorScheme.primaryFixedDim,
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
                                    color: isVoucherMatch ? colorScheme.onTertiaryFixedVariant : colorScheme.onSecondaryContainer,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'الهدية / الكروت المربوطة من مخزون الشركة:',
                                      style: GoogleFonts.cairo(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isVoucherMatch ? colorScheme.onTertiaryContainer : colorScheme.onSecondaryContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Active allocations list
                              if (dialogLinkedGifts.isNotEmpty) ...[
                                ...dialogLinkedGifts.asMap().entries.map((entry) {
                                  final gIndex = entry.key;
                                  final alloc = entry.value;
                                  final isVoucher = alloc.isVoucher;

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: colorScheme.outlineVariant),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                                          size: 16,
                                          color: isVoucher ? colorScheme.onSecondaryFixedVariant : colorScheme.onTertiaryFixedVariant,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                alloc.giftName,
                                                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                isVoucher
                                                    ? 'فئة: ${alloc.unitValue.toInt()} ج.م × ${alloc.quantity} = ${(alloc.unitValue * alloc.quantity).toInt()} ج.م'
                                                    : 'هدية عينية × ${alloc.quantity}',
                                                style: GoogleFonts.cairo(fontSize: 10.5, color: colorScheme.onSurfaceVariant),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.remove_circle_outline, size: 18),
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () {
                                            setDialogState(() {
                                              if (alloc.quantity > 1) {
                                                dialogLinkedGifts[gIndex] = alloc.copyWith(quantity: alloc.quantity - 1);
                                              } else {
                                                dialogLinkedGifts.removeAt(gIndex);
                                              }
                                            });
                                          },
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                          child: Text(
                                            '${alloc.quantity}',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.add_circle_outline, size: 18, color: colorScheme.tertiary),
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () {
                                            setDialogState(() {
                                              dialogLinkedGifts[gIndex] = alloc.copyWith(quantity: alloc.quantity + 1);
                                            });
                                          },
                                        ),
                                        const SizedBox(width: 6),
                                        IconButton(
                                          icon: Icon(Icons.close_rounded, size: 16, color: colorScheme.error),
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () {
                                            setDialogState(() {
                                              dialogLinkedGifts.removeAt(gIndex);
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                const SizedBox(height: 4),
                              ],

                              // Real-time Total Status Badge
                              if (dialogLinkedGifts.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isVoucherMatch
                                        ? colorScheme.tertiaryContainer.withValues(alpha: 0.6)
                                        : colorScheme.secondaryContainer.withValues(alpha: 0.8),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isVoucherMatch ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                                        size: 14,
                                        color: isVoucherMatch ? colorScheme.onTertiaryFixedVariant : colorScheme.onSecondaryContainer,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isVoucherMatch
                                            ? ((dialogLinkedGifts.any((g) => g.isVoucher) || rewardType == 'voucher')
                                                ? 'إجمالي قيمة الكروت المربوطة: ${currentAllocatedTotal.toInt()} ج.م (مطابقة تامة ومكتملة ✓)'
                                                : 'تم ربط ${dialogLinkedGifts.length} هدايا عينية من المخزون (مطابقة تامة ومكتملة ✓)')
                                            : 'إجمالي الكروت: ${currentAllocatedTotal.toInt()} ج.م (المطلوب: ${targetVoucherAmt.toInt()} ج.م - فرق ${(targetVoucherAmt - currentAllocatedTotal).toInt()} ج.م ⚠️)',
                                        style: GoogleFonts.cairo(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: isVoucherMatch ? colorScheme.onTertiaryContainer : colorScheme.onSecondaryContainer,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],

                              // Add gift dropdown
                              DropdownButtonFormField<CompanyGiftModel>(
                                isExpanded: true,
                                decoration: InputDecoration(
                                  hintText: '+ إضافة هدية / كارت للمكافأة',
                                  hintStyle: GoogleFonts.cairo(fontSize: 12),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  isDense: true,
                                ),
                                items: _companyGifts.map((g) {
                                  final typeDesc = g.isVoucher ? 'فواتشر (${g.formattedUnitValue})' : 'هدية عينية';
                                  return DropdownMenuItem(
                                    value: g,
                                    child: Text(
                                      '${g.giftName} - $typeDesc',
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.cairo(fontSize: 12),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (gift) {
                                  if (gift != null) {
                                    setDialogState(() {
                                      final existingIdx = dialogLinkedGifts.indexWhere((a) => a.giftId == gift.id);
                                      if (existingIdx >= 0) {
                                        dialogLinkedGifts[existingIdx] = dialogLinkedGifts[existingIdx].copyWith(
                                          quantity: dialogLinkedGifts[existingIdx].quantity + 1,
                                        );
                                      } else {
                                        dialogLinkedGifts.add(LinkedGiftAllocation(
                                          giftId: gift.id,
                                          giftName: gift.giftName,
                                          quantity: 1,
                                          unitValue: gift.unitValue,
                                          giftType: gift.giftType,
                                          imageUrl: gift.imageUrl,
                                        ));
                                      }
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ── خيارات المكافأة (customer picks one) ──
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.alt_route_rounded, size: 18, color: colorScheme.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'خيارات المكافأة (العميل يختار واحدة)',
                                    style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              dialogRewardOptions.length > 1
                                  ? 'العميل هيختار خيار واحد من ${dialogRewardOptions.length} وقت التسليم، وهيتخصم من المخزون الخيار اللي اختاره بس.'
                                  : 'اختياري: ضيف خيارين أو أكتر (مثلاً قسيمة 50 جنيه أو إزازة). لو أقل من خيارين، القاعدة بتشتغل بالمكافأة العادية.',
                              style: GoogleFonts.cairo(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 8),
                            ...dialogRewardOptions.asMap().entries.map((entry) {
                              final opt = entry.value;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: InputChip(
                                  key: ValueKey('rule_reward_option_${entry.key}'),
                                  avatar: Icon(
                                    opt.isVoucher ? Icons.local_activity_rounded : Icons.card_giftcard_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    '${entry.key + 1}. ${opt.displayLabel}',
                                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onDeleted: () => setDialogState(() => dialogRewardOptions.removeAt(entry.key)),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text('الكمية', style: GoogleFonts.cairo(fontSize: 11)),
                                    IconButton(
                                      key: ValueKey('rule_reward_option_qty_minus_${entry.key}'),
                                      visualDensity: VisualDensity.compact,
                                      tooltip: 'تقليل الكمية',
                                      icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                                      onPressed: opt.unitsPerChoice <= 1
                                          ? null
                                          : () => setDialogState(() => dialogRewardOptions[entry.key] =
                                              opt.withQuantity(opt.unitsPerChoice - 1)),
                                    ),
                                    Text('${opt.unitsPerChoice}',
                                        key: ValueKey('rule_reward_option_qty_${entry.key}'),
                                        style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700)),
                                    IconButton(
                                      key: ValueKey('rule_reward_option_qty_plus_${entry.key}'),
                                      visualDensity: VisualDensity.compact,
                                      tooltip: 'زيادة الكمية',
                                      icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                                      onPressed: opt.unitsPerChoice >= 100
                                          ? null
                                          : () => setDialogState(() => dialogRewardOptions[entry.key] =
                                              opt.withQuantity(opt.unitsPerChoice + 1)),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: optionVoucherCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'قيمة القسيمة (ج.م)',
                                      labelStyle: GoogleFonts.cairo(fontSize: 12),
                                      isDense: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: optionLabelCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'اسم الخيار (اختياري)',
                                      labelStyle: GoogleFonts.cairo(fontSize: 12),
                                      isDense: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton.filledTonal(
                                  tooltip: 'إضافة قسيمة كخيار',
                                  icon: const Icon(Icons.add_rounded),
                                  onPressed: () {
                                    final amt = double.tryParse(optionVoucherCtrl.text.toEnglishDigits().trim()) ?? 0.0;
                                    if (amt <= 0) return;
                                    // Link to a matching voucher card in inventory when one exists (for stock tracking).
                                    final match = _companyGifts
                                        .where((g) => g.isVoucher && (g.unitValue - amt).abs() < 0.01)
                                        .firstOrNull;
                                    setDialogState(() {
                                      dialogRewardOptions.add(RewardOption(
                                        id: 'opt_${DateTime.now().microsecondsSinceEpoch}',
                                        kind: 'voucher',
                                        label: optionLabelCtrl.text.trim(),
                                        voucherAmount: amt,
                                        giftId: match?.id ?? '',
                                        giftName: match?.giftName ?? '',
                                        giftType: 'voucher',
                                        unitValue: amt,
                                        imageUrl: match?.imageUrl,
                                      ));
                                      optionVoucherCtrl.clear();
                                      optionLabelCtrl.clear();
                                    });
                                  },
                                ),
                              ],
                            ),
                            if (_companyGifts.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              DropdownButtonFormField<CompanyGiftModel>(
                                key: ValueKey('reward_option_gift_picker_${dialogRewardOptions.length}'),
                                isExpanded: true,
                                decoration: InputDecoration(
                                  hintText: '+ إضافة هدية من المخزون كخيار',
                                  hintStyle: GoogleFonts.cairo(fontSize: 12),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  isDense: true,
                                ),
                                items: _companyGifts.map((g) {
                                  final typeDesc = g.isVoucher ? 'فواتشر (${g.formattedUnitValue})' : 'هدية عينية';
                                  return DropdownMenuItem(
                                    value: g,
                                    child: Text('${g.giftName} - $typeDesc',
                                        overflow: TextOverflow.ellipsis, style: GoogleFonts.cairo(fontSize: 12)),
                                  );
                                }).toList(),
                                onChanged: (gift) {
                                  if (gift == null) return;
                                  if (dialogRewardOptions.any((o) => o.giftId.isNotEmpty && o.giftId == gift.id)) return;
                                  setDialogState(() {
                                    dialogRewardOptions.add(RewardOption(
                                      id: 'opt_${DateTime.now().microsecondsSinceEpoch}',
                                      kind: 'gift',
                                      label: gift.giftName,
                                      giftId: gift.id,
                                      giftName: gift.giftName,
                                      giftType: gift.giftType,
                                      unitValue: gift.unitValue,
                                      imageUrl: gift.imageUrl,
                                    ));
                                  });
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text(strings.cancel, style: GoogleFonts.cairo()),
                ),
                FilledButton(
                  onPressed: () {
                    final title = titleController.text.trim();
                    final trigger = triggerController.text.trim();
                    final minQty = int.tryParse(minQtyController.text.trim()) ?? 1;
                    final minSpend = conditionType == 'by_quantity'
                        ? 0.0
                        : (double.tryParse(minSpendController.text.trim()) ?? 0.0);
                    final maxSpend = conditionType == 'by_quantity'
                        ? null
                        : double.tryParse(maxSpendController.text.trim());
                    final discountTolerance = conditionType == 'by_quantity'
                        ? 0.0
                        : (double.tryParse(discountToleranceController.text.trim()) ?? 0.0);
                    final rewardVal = rewardValController.text.trim();
                    final rewardAmt = double.tryParse(rewardAmtController.text.trim()) ?? 0.0;

                    if (title.isEmpty) return;

                    List<LinkedGiftAllocation> finalLinkedGifts = List<LinkedGiftAllocation>.from(dialogLinkedGifts);
                    if (finalLinkedGifts.isEmpty && rewardType == 'voucher' && rewardAmt > 0) {
                      finalLinkedGifts = CampaignAiAssistantService.decomposeVoucherAmount(rewardAmt, _companyGifts);
                    }

                    final ruleId = existingRule?.id.isNotEmpty == true
                        ? existingRule!.id
                        : 'rule_${isEditing ? ruleIndex + 1 : _promotionalRules.length + 1}';

                    final updatedRule = PromotionalRuleItem(
                      id: ruleId,
                      ruleTitle: title,
                      triggerProduct: trigger.isNotEmpty ? trigger : title,
                      minQuantity: minQty,
                      conditionType: conditionType,
                      minSpend: minSpend,
                      maxSpend: maxSpend != null && maxSpend > 0 ? maxSpend : null,
                      discountTolerance: discountTolerance,
                      matchMode: matchMode,
                      requiredBrands: requiredBrands,
                      selectedProductIds: selectedProductIds,
                      selectedBarcodes: selectedBarcodes,
                      selectedProductNames: selectedProductNames,
                      rewardType: rewardType,
                      rewardValue: rewardVal.isNotEmpty ? rewardVal : title,
                      rewardAmount: rewardAmt,
                      linkedGiftId: finalLinkedGifts.isNotEmpty ? finalLinkedGifts.first.giftId : selectedGift?.id,
                      linkedGiftName: finalLinkedGifts.isNotEmpty
                          ? finalLinkedGifts.map((d) => d.quantity > 1 ? '${d.quantity}x ${d.giftName}' : d.giftName).join(' + ')
                          : selectedGift?.giftName,
                      linkedGifts: finalLinkedGifts,
                      gameType: selectedRuleGameType,
                      rewardOptions: List<RewardOption>.from(dialogRewardOptions),
                    );

                    setState(() {
                      if (isEditing) {
                        _promotionalRules[ruleIndex] = updatedRule;
                      } else {
                        _promotionalRules.add(updatedRule);
                      }
                    });
                    _syncPromptFromRules(showSnackbar: false);
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
    // 2.0.162: show and store Cairo calendar days.
    final initialDate = isStart
        ? (campaignFirstDay(_startDate) ?? cairoCalendarDay(DateTime.now()))
        : (campaignLastDay(_endDate) ??
            cairoCalendarDay(DateTime.now()).add(const Duration(days: 30)));

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      helpText: isStart ? 'اختر تاريخ بداية الحملة' : 'اختر تاريخ نهاية الحملة',
    );

    if (picked != null) {
      setState(() {
        // Stored as Cairo 00:00 of the picked day; the end day is inclusive.
        if (isStart) {
          _startDate = pickedDayToCairoInstant(picked);
        } else {
          _endDate = pickedDayToCairoInstant(picked);
        }
      });
    }
  }

  Future<void> _saveEvent() async {
    if (!_formKey.currentState!.validate()) return;

    // 2.0.162 (issue #3): block an end day before the start day.
    final datesError = campaignDatesError(_startDate, _endDate);
    if (datesError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(datesError, style: GoogleFonts.cairo()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    // Warn when an active campaign has no start or end date.
    final willBeActive = widget.eventToEdit?.isActive ?? true;
    if (willBeActive && (_startDate == null || _endDate == null)) {
      final missing = [
        if (_startDate == null) 'تاريخ البداية',
        if (_endDate == null) 'آخر يوم في الحملة',
      ].join(' و');
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('تواريخ الحملة غير مكتملة',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          content: Text(
            'لم يتم تحديد $missing. الحملة مفعّلة، لذلك ستبقى مفتوحة بلا حد '
            'زمني وتُقبل الفواتير بأي تاريخ. هل تريد الحفظ على أي حال؟',
            style: GoogleFonts.cairo(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('رجوع وتحديد التاريخ', style: GoogleFonts.cairo()),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('حفظ على أي حال', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      final firestore = ref.read(firestoreProvider);
      
      final productsText = _requiredProductsController.text.trim();
      final productsList = productsText.isNotEmpty 
          ? productsText.split(',').map((e) => e.trim()).toList() 
          : <String>[];

      // Never persist an auto-generated prompt that names another company.
      if (_promptNeedsCompanyRefresh()) {
        _syncPromptFromRules(showSnackbar: false);
      }

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
        isAgencyActive: widget.eventToEdit?.isAgencyActive ?? true,
        isManagerActive: widget.eventToEdit?.isManagerActive ?? true,
        hasCustomAgencyCredentials: _hasCustomAgencyCredentials,
        customAgencyUsername: _hasCustomAgencyCredentials
            ? (_customAgencyUsernameController.text.trim().isNotEmpty
                ? _customAgencyUsernameController.text.trim()
                : 'ops_${rawSlug}_custom')
            : '',
        customAgencyPassword: _hasCustomAgencyCredentials
            ? (_customAgencyPasswordController.text.trim().isNotEmpty
                ? _customAgencyPasswordController.text.trim()
                : PartnerPortalAuthService.defaultAgencyPassword(rawSlug))
            : '',
        customAgencyCredentialVersion: (widget.eventToEdit != null &&
                (widget.eventToEdit!.hasCustomAgencyCredentials != _hasCustomAgencyCredentials ||
                    widget.eventToEdit!.customAgencyUsername != _customAgencyUsernameController.text.trim() ||
                    widget.eventToEdit!.customAgencyPassword != _customAgencyPasswordController.text.trim()))
            ? _customAgencyCredentialVersion + 1
            : _customAgencyCredentialVersion,
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
              imageUrl: matchedGift?.imageUrl ?? originalPrize?.imageUrl,
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
                // Only create general pool prize if campaign applies to all branches
                if (_isAllBranches || _selectedBranchIds.isEmpty) {
                  prizes.add(resolveAllocatedPrize(
                    giftKey: linked.giftId,
                    quantity: 0,
                    branchId: '',
                    branchName: '',
                  ));
                }
              }
            }
            if (rule.linkedGiftId != null && rule.linkedGiftId!.isNotEmpty) {
              final isExistingInMaster = _companyGifts.isEmpty ||
                  _companyGifts.any((g) => g.id == rule.linkedGiftId || g.giftName == rule.linkedGiftName);
              if (!isExistingInMaster) continue;
              final alreadyInPrizes = prizes.any((p) => p.giftId == rule.linkedGiftId || p.name == rule.linkedGiftName);
              if (!alreadyInPrizes) {
                if (_isAllBranches || _selectedBranchIds.isEmpty) {
                  prizes.add(resolveAllocatedPrize(
                    giftKey: rule.linkedGiftId!,
                    quantity: 0,
                    branchId: '',
                    branchName: '',
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
        multiplierBasis: _multiplierBasis,
        maxChancesPerReceipt: _maxChancesController.text.trim().toIntOrNull() ?? 0,
        promotionalIdea: _promotionalIdeaController.text.trim(),
        aiValidationSummary: _aiValidationSummary.trim(),
        promotionalRules: _promotionalRules.map((rule) {
          if (rule.conditionType == 'by_quantity' && (rule.minSpend > 0 || rule.maxSpend != null || rule.discountTolerance > 0)) {
            return rule.copyWith(minSpend: 0.0, maxSpend: null, discountTolerance: 0.0);
          }
          return rule;
        }).toList(),
        requireVoucherSerials: _voucherSerialMode == 'required',
        voucherSerialMode: _voucherSerialMode,
        allowComplementaryReceipts: _allowComplementaryReceipts,
        enableWhatsAppWinnerNotification: _enableWhatsAppWinnerNotification,
        spendLadderMode: widget.eventToEdit?.spendLadderMode ?? 'exclusive',
        createdAt: widget.eventToEdit?.createdAt,
      );

      // TG-2: a tier option must point at a stock row of the same gift and
      // value, otherwise every claim of it fails as "no stock".
      final stockError = CampaignStockIntegrity.tierOptionStockError(
        rules: event.promotionalRules,
        prizes: [...event.allocatedPrizes, ...?widget.eventToEdit?.allocatedPrizes],
      );
      if (stockError != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(stockError, style: GoogleFonts.cairo()),
              backgroundColor: Theme.of(context).colorScheme.error,
              duration: const Duration(seconds: 10),
            ),
          );
        }
        return;
      }

      String createdEventId = widget.eventToEdit?.id ?? '';
      if (widget.eventToEdit == null) {
        final docRef = await firestore.collection('events').add(event.toFirestore()).timeout(
          const Duration(seconds: 5),
          onTimeout: () => firestore.collection('events').doc(),
        );
        createdEventId = docRef.id;
      } else {
        final updatedBy = ref.read(firebaseAuthProvider).currentUser?.uid ?? '';
        // C-02: transaction on the stored campaign; only changed fields are
        // written and stock rows are merged from fresh data. Failures throw.
        await CampaignEditSave.save(
          firestore: firestore,
          draft: event,
          opened: widget.eventToEdit!,
          updatedBy: updatedBy,
        );
      }

      if (createdEventId.isNotEmpty) {
        await ref.read(partnerPortalAuthServiceProvider).saveCampaignAgencyOverride(
              eventId: createdEventId,
              companySlug: event.companySlug,
              hasCustomAgencyCredentials: event.hasCustomAgencyCredentials,
              customAgencyUsername: event.customAgencyUsername,
              customAgencyPassword: event.customAgencyPassword,
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
            content: Text(e is CampaignEditRejected
                ? e.message
                : AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء حفظ الحملة')),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: e is CampaignEditRejected ? const Duration(seconds: 10) : const Duration(seconds: 4),
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
              backgroundColor: colorScheme.onErrorContainer,
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
              backgroundColor: colorScheme.onErrorContainer,
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
    final authService = ref.read(partnerPortalAuthServiceProvider);
    final resolvedCreds = await authService.resolveCredentials(
      companySlug: event.companySlug,
      companyNameHint: event.targetCompany,
      eventId: eventId,
    );
    if (!context.mounted) return;
    final promoterUrl = AppUrlBuilder.buildPromoterUrl(event.companySlug, eventId: eventId);
    final agencyOpsUrl = AppUrlBuilder.buildAgencyOpsUrl(event.companySlug, eventId: eventId);
    final managerUrl = AppUrlBuilder.buildManagerPortalUrl(event.companySlug, eventId: eventId);

    final agencyWhatsAppCard = PartnerPortalAuthService.buildWhatsAppLoginCard(
      role: PartnerPortalRole.agencyOps,
      companyName: event.targetCompany,
      campaignName: event.eventName,
      portalUrl: agencyOpsUrl,
      username: resolvedCreds.effectiveAgencyUsername,
      password: resolvedCreds.effectiveAgencyPassword,
      isCustomCampaignTier: resolvedCreds.hasCustomAgencyCredentials,
      isAr: isAr,
    );
    final brandWhatsAppCard = PartnerPortalAuthService.buildWhatsAppLoginCard(
      role: PartnerPortalRole.brandManager,
      companyName: event.targetCompany,
      campaignName: event.eventName,
      portalUrl: managerUrl,
      username: resolvedCreds.brandManagerUsername,
      password: resolvedCreds.brandManagerPassword,
      isCustomCampaignTier: false,
      isAr: isAr,
    );

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
                color: colorScheme.tertiaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_rounded, color: colorScheme.onTertiaryFixedVariant, size: 28),
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
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr
                      ? 'تم توليد الروابط الثلاثة المباشرة للحملة بنجاح (${event.companySlug})، مع بطاقات دخول الواتساب الجاهزة:'
                      : 'All 3 campaign links generated (${event.companySlug}) with 1-Click WhatsApp login cards:',
                  style: GoogleFonts.cairo(fontSize: 13, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                // 1. Promoter Link Card (Open / Frictionless)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.qr_code_scanner_rounded, size: 18, color: colorScheme.onTertiaryFixedVariant),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              isAr ? '1. رابط البروموتر الميداني (مفتوح بدون باسورد):' : '1. Field Promoter Link (Open / No Password):',
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: colorScheme.onTertiaryContainer),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        promoterUrl,
                        style: GoogleFonts.sourceCodePro(fontSize: 12, color: colorScheme.onTertiaryContainer, fontWeight: FontWeight.w600),
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
                                backgroundColor: colorScheme.onTertiaryFixedVariant,
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
                // 2. Agency Operations Supervisor Link Card (Protected + Stock Edit)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.inventory_rounded, size: 18, color: colorScheme.secondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              isAr
                                  ? '2. رابط شركة الدعاية والعمليات (تعديل المخزون والهدايا):'
                                  : '2. Agency Operations Link (Stock & Gifts Management):',
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: colorScheme.onSecondaryContainer),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        agencyOpsUrl,
                        style: GoogleFonts.sourceCodePro(fontSize: 12, color: colorScheme.onSecondaryContainer, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${isAr ? 'المستخدم:' : 'User:'} ${resolvedCreds.effectiveAgencyUsername}  |  ${isAr ? 'كلمة المرور: مخفية (انسخ كارت الواتساب)' : 'Pass: hidden'}',
                        style: GoogleFonts.sourceCodePro(fontSize: 11, color: colorScheme.onSecondaryContainer, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.link_rounded, size: 16),
                            label: Text(isAr ? 'نسخ الرابط فقط' : 'Copy URL', style: GoogleFonts.cairo(fontSize: 11)),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: agencyOpsUrl));
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(isAr ? 'تم نسخ رابط شركة الدعاية!' : 'Agency Ops URL Copied!'),
                                  backgroundColor: colorScheme.secondary,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.chat_rounded, size: 16),
                            label: Text(isAr ? 'نسخ بطاقة دخول واتساب' : 'Copy WhatsApp Login Card', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: agencyWhatsAppCard));
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(isAr ? 'تم نسخ بطاقة دخول مشرف الدعاية للواتساب!' : 'Agency WhatsApp Card Copied!'),
                                  backgroundColor: colorScheme.secondary,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 3. Company Manager Portal Link Card (Protected + Read-Only Stock)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.storefront_rounded, size: 18, color: colorScheme.onPrimaryFixedVariant),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              isAr ? '3. رابط مدير العلامة التجارية (تقارير ومخزون للقراءة فقط):' : '3. Brand Executive Portal (Analytics & Read-Only Stock):',
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: colorScheme.onPrimaryContainer),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        managerUrl,
                        style: GoogleFonts.sourceCodePro(fontSize: 12, color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${isAr ? 'المستخدم:' : 'User:'} ${resolvedCreds.brandManagerUsername}  |  ${isAr ? 'كلمة المرور: مخفية (انسخ كارت الواتساب)' : 'Pass: hidden'}',
                        style: GoogleFonts.sourceCodePro(fontSize: 11, color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.link_rounded, size: 16),
                            label: Text(isAr ? 'نسخ الرابط فقط' : 'Copy URL', style: GoogleFonts.cairo(fontSize: 11)),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: managerUrl));
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(isAr ? 'تم نسخ رابط مدير العلامة!' : 'Manager Portal URL Copied!'),
                                  backgroundColor: colorScheme.primary,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.chat_rounded, size: 16),
                            label: Text(isAr ? 'نسخ بطاقة دخول واتساب' : 'Copy WhatsApp Login Card', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: brandWhatsAppCard));
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(isAr ? 'تم نسخ بطاقة دخول مدير العلامة للواتساب!' : 'Brand Executive WhatsApp Card Copied!'),
                                  backgroundColor: colorScheme.primary,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
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
                      stream: _ensureCompaniesStream(),
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
                                      if (_promptNeedsCompanyRefresh()) {
                                        _syncPromptFromRules(showSnackbar: false);
                                      }
                                      _loadCompanyProducts(comp.slug);
                                      _loadCompanyGifts(comp.slug);
                                      _loadCompanyLogo(comp.slug);
                                    }
                                  },
                                )
                              // 2.0.172: while the companies stream is still loading
                              // (typical on the edit page) show progress, not the
                              // misleading "no companies" empty state.
                              else if (!snapshot.hasData && !snapshot.hasError)
                                const LinearProgressIndicator()
                              else if (snapshot.hasError)
                                Text(
                                  'تعذّر تحميل الشركات. أعد فتح الصفحة.',
                                  style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.error),
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
                                            Icon(Icons.campaign_rounded, size: 15, color: colorScheme.onTertiaryFixedVariant),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'البروموتر: $promoterUrl',
                                                style: GoogleFonts.sourceCodePro(fontSize: 11, color: colorScheme.onTertiaryContainer),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            InkWell(
                                              onTap: () {
                                                Clipboard.setData(ClipboardData(text: promoterUrl));
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('تم نسخ رابط البروموتر: $promoterUrl'),
                                                    backgroundColor: colorScheme.onTertiaryFixedVariant,
                                                    behavior: SnackBarBehavior.floating,
                                                  ),
                                                );
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                child: Icon(Icons.copy_rounded, size: 14, color: colorScheme.onTertiaryFixedVariant),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(Icons.storefront_rounded, size: 15, color: colorScheme.primary),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'لوحة المدير: $managerUrl',
                                                style: GoogleFonts.sourceCodePro(fontSize: 11, color: colorScheme.onPrimaryContainer),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            InkWell(
                                              onTap: () {
                                                Clipboard.setData(ClipboardData(text: managerUrl));
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('تم نسخ رابط لوحة المدير: $managerUrl'),
                                                    backgroundColor: colorScheme.primary,
                                                    behavior: SnackBarBehavior.floating,
                                                  ),
                                                );
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                child: Icon(Icons.copy_rounded, size: 14, color: colorScheme.primary),
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
                    _buildComplementaryReceiptsSettingSection(context, colorScheme, isMobile),
                    _buildWhatsAppWinnerNotificationSettingSection(context, colorScheme, isMobile),
                    _buildCampaignAgencyCredentialsSettingSection(context, colorScheme, isMobile),
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
                                  : 'البداية: ${campaignFirstDayLabel(_startDate)}',
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
                                  ? 'آخر يوم في الحملة: غير محدد'
                                  : 'آخر يوم في الحملة: ${campaignLastDay(_endDate)!.day}/${campaignLastDay(_endDate)!.month} (شامل)',
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
                        DropdownMenuItem(
                          value: 'chooseGift',
                          child: Row(
                            children: [
                              Icon(Icons.grid_view_rounded, color: colorScheme.primary, size: 20),
                              const SizedBox(width: 10),
                              Text('اختر هديتك - شبكة الاختيارات (Choose Your Gift)', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
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
                    if (_selectedGameType == 'chooseGift') ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.touch_app_rounded, color: colorScheme.primary, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'في نمط "اختر هديتك": تظهر للعميل شبكة بطاقات تفاعلية بكافة الهدايا المتوفرة في الحملة والفرع، ليختار بنفسه الهدية التي تفضلها بلمسة واحدة دون اعتماد على القرعة العشوائية أو عجلة الحظ.',
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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

                // Section 6: Unified AI & Promotional Rules Studio
                _buildUnifiedAiAndRulesStudio(context, colorScheme, isMobile, strings),

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
                                          color: colorScheme.tertiaryContainer,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: colorScheme.tertiaryFixedDim),
                                        ),
                                        child: Text(
                                          'جاهز للرفع والتخزين',
                                          style: GoogleFonts.cairo(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onTertiaryFixedVariant,
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
                                        icon: Icon(Icons.delete_outline_rounded, size: 16, color: colorScheme.error),
                                        label: Text(
                                          'إزالة اللوجو',
                                          style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.error, fontWeight: FontWeight.bold),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(color: colorScheme.error.withValues(alpha: 0.4)),
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
                          icon: Icon(Icons.delete_outline_rounded, size: 18, color: colorScheme.error),
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
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final mode = _voucherSerialMode;
    final active = mode != 'hidden';
    String desc;
    switch (mode) {
      case 'required':
        desc = isAr
            ? 'يلزم البروموتر بإدخال أرقام كروت الفواتشرات قبل تأكيد تسليم الهدية.'
            : 'The promoter must enter voucher card numbers before confirming the handover.';
        break;
      case 'hidden':
        desc = isAr
            ? 'حقل أرقام الكروت لا يظهر إطلاقاً في شاشة تسليم الهدية.'
            : 'The card number field is not shown at all on the gift handover screen.';
        break;
      default:
        desc = isAr
            ? 'إدخال أرقام الكروت اختياري، ويمكن تأكيد التسليم بدونها.'
            : 'Entering card numbers is optional; handover can be confirmed without them.';
    }
    return Container(
      key: const ValueKey('voucherSerialModeSection'),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: active
            ? colorScheme.secondaryContainer.withValues(alpha: 0.55)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: mode == 'required' ? colorScheme.primaryFixedDim : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: mode == 'required' ? 1.5 : 1,
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
                  color: active ? colorScheme.secondary : colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  active ? Icons.confirmation_number_rounded : Icons.visibility_off_rounded,
                  size: 20,
                  color: active ? colorScheme.onSecondary : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isAr ? 'أرقام كروت الفواتشرات' : 'Voucher card numbers',
                  style: GoogleFonts.cairo(fontSize: 14.5, fontWeight: FontWeight.w700, color: colorScheme.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: !isMobile,
              segments: [
                ButtonSegment(value: 'required', icon: const Icon(Icons.lock_rounded, size: 18), label: Text(isAr ? 'إجباري' : 'Required', style: GoogleFonts.cairo(fontSize: 13))),
                ButtonSegment(value: 'optional', icon: const Icon(Icons.edit_note_rounded, size: 18), label: Text(isAr ? 'اختياري' : 'Optional', style: GoogleFonts.cairo(fontSize: 13))),
                ButtonSegment(value: 'hidden', icon: const Icon(Icons.visibility_off_rounded, size: 18), label: Text(isAr ? 'مخفي' : 'Hidden', style: GoogleFonts.cairo(fontSize: 13))),
              ],
              selected: {mode},
              onSelectionChanged: (v) => setState(() {
                _voucherSerialMode = v.first;
              }),
            ),
          ),
          const SizedBox(height: 8),
          Text(desc, style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant, height: 1.35)),
        ],
      ),
    );
  }

  Widget _buildComplementaryReceiptsSettingSection(
    BuildContext context,
    ColorScheme colorScheme,
    bool isMobile,
  ) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _allowComplementaryReceipts
            ? colorScheme.primaryContainer.withValues(alpha: 0.55)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _allowComplementaryReceipts
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: _allowComplementaryReceipts ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _allowComplementaryReceipts
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_long_rounded,
              size: 20,
              color: _allowComplementaryReceipts
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
                      'السماح بالبونات التكميلية (Complementary Receipts)',
                      style: GoogleFonts.cairo(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _allowComplementaryReceipts
                            ? colorScheme.tertiaryContainer
                            : colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _allowComplementaryReceipts ? 'مفعل (يسمح بدمج البونات)' : 'معطل (فاتورة واحدة فقط)',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _allowComplementaryReceipts
                              ? colorScheme.onTertiaryContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _allowComplementaryReceipts
                      ? 'يسمح للعميل برفع بونين منفصلين لنفس السوبرماركت والفرع في نفس اليوم (أحدهما بون أساسي والآخر بون تكميلي مثل "تكملة الفاتورة") ودمج إجمالي مشترياتهما لتأهيل العميل لمستويات الجوائز الأعلى.'
                      : 'يلزم استيفاء شروط العرض في فاتورة كاشير واحدة مستقلة بذاتها، ويمنع دمج أو جمع أكثر من بون كاشير منفصل لنفس المعاملة.',
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
            value: _allowComplementaryReceipts,
            activeTrackColor: colorScheme.primary,
            onChanged: (val) {
              setState(() {
                _allowComplementaryReceipts = val;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWhatsAppWinnerNotificationSettingSection(
    BuildContext context,
    ColorScheme colorScheme,
    bool isMobile,
  ) {
    final isEnabled = _enableWhatsAppWinnerNotification;
    final primaryColor = colorScheme.onTertiaryFixedVariant;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isEnabled
            ? colorScheme.tertiaryContainer.withValues(alpha: 0.55)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEnabled
              ? colorScheme.tertiaryFixedDim
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: isEnabled ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isEnabled
                  ? primaryColor
                  : colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mark_chat_read_rounded,
              size: 20,
              color: isEnabled
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
                      'إرسال التهنئة التلقائي للفائزين عبر الواتساب',
                      style: GoogleFonts.cairo(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isEnabled
                            ? colorScheme.tertiaryContainer
                            : colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isEnabled ? 'إرسال تلقائي مفعل 🟢' : 'معطل لهذه الحملة ⏸️',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isEnabled
                              ? colorScheme.onTertiaryContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  isEnabled
                      ? 'عند تفعيل هذا الخيار، يقوم النظام تلقائياً بإرسال رسالة تهنئة احتفالية رسمية برقم الفاتورة واسم الجائزة وكود الفواتشر إلى هاتف العميل عبر الواتساب فور تأكيد تسليم الهدية.'
                      : 'تم تعطيل إرسال رسائل التهنئة عبر الواتساب لهذه الحملة تحديداً، ولن يتم إرسال أي رسائل تلقائية للعملاء عند استلام هداياهم.',
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
            value: _enableWhatsAppWinnerNotification,
            activeTrackColor: primaryColor,
            onChanged: (val) {
              setState(() {
                _enableWhatsAppWinnerNotification = val;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCampaignAgencyCredentialsSettingSection(
    BuildContext context,
    ColorScheme colorScheme,
    bool isMobile,
  ) {
    final isAr = ref.isArabic;
    final slugPreview = _companySlugController.text.trim().isNotEmpty
        ? _companySlugController.text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-')
        : _targetCompanyController.text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
    final defaultOpsUser = PartnerPortalAuthService.defaultAgencyUsername(slugPreview);
    final defaultOpsPass = PartnerPortalAuthService.defaultAgencyPassword(slugPreview);

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: _hasCustomAgencyCredentials
            ? colorScheme.secondaryContainer.withValues(alpha: 0.25)
            : colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _hasCustomAgencyCredentials
              ? colorScheme.secondary.withValues(alpha: 0.45)
              : colorScheme.outlineVariant,
          width: _hasCustomAgencyCredentials ? 1.5 : 1,
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
                  color: _hasCustomAgencyCredentials
                      ? colorScheme.secondaryContainer
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.admin_panel_settings_rounded,
                  color: _hasCustomAgencyCredentials
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onSurfaceVariant,
                  size: 22,
                ),
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
                            isAr
                                ? 'تخصيص كلمة مرور مستقلة لشركة الدعاية في هذه الحملة (Tier 2)'
                                : 'Custom Campaign-Specific Agency Credentials (Tier 2)',
                            style: GoogleFonts.cairo(
                              fontSize: isMobile ? 14 : 15,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _hasCustomAgencyCredentials
                                ? colorScheme.secondaryContainer
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _hasCustomAgencyCredentials
                                ? (isAr ? 'مخصص للحملة 🔒' : 'Campaign Custom 🔒')
                                : (isAr ? 'موروث من الشركة ($defaultOpsUser)' : 'Inherited ($defaultOpsUser)'),
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _hasCustomAgencyCredentials
                                  ? colorScheme.onSecondaryContainer
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _hasCustomAgencyCredentials
                          ? (isAr
                              ? 'تعمل هذه الحملة باسم مستخدم وكلمة مرور مستقلين لشركة الدعاية والعمليات (لتعديل المخزون والهدايا في هذه الحملة فقط).'
                              : 'This campaign uses isolated Agency Operations credentials for stock & gifts management.')
                          : (isAr
                              ? 'الوضع الافتراضي (Tier 1): ترث الحملة تلقائياً بيانات دخول شركة الدعاية الموحدة للشركة ($defaultOpsUser / $defaultOpsPass) دون الحاجة لإعداد يدوي.'
                              : 'Default (Tier 1): Automatically inherits the company-wide Agency Operations credentials ($defaultOpsUser / $defaultOpsPass).'),
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
              if (widget.eventToEdit != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      PortalCredentialsDialog.show(
                        context,
                        companySlug: slugPreview,
                        companyName: _targetCompanyController.text.trim(),
                        event: widget.eventToEdit,
                      );
                    },
                    icon: const Icon(Icons.key_rounded, size: 16),
                    label: Text(
                      isAr ? 'بطاقات الدخول' : 'Login Cards',
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              Switch.adaptive(
                value: _hasCustomAgencyCredentials,
                activeTrackColor: colorScheme.secondary,
                onChanged: (val) {
                  setState(() {
                    _hasCustomAgencyCredentials = val;
                    if (val) {
                      if (_customAgencyUsernameController.text.trim().isEmpty) {
                        _customAgencyUsernameController.text = 'ops_${slugPreview}_custom';
                      }
                      if (_customAgencyPasswordController.text.trim().isEmpty) {
                        _customAgencyPasswordController.text = defaultOpsPass;
                      }
                    }
                  });
                },
              ),
            ],
          ),
          if (_hasCustomAgencyCredentials) ...[
            const SizedBox(height: 14),
            Flex(
              direction: isMobile ? Axis.vertical : Axis.horizontal,
              children: [
                Expanded(
                  flex: isMobile ? 0 : 1,
                  child: TextFormField(
                    controller: _customAgencyUsernameController,
                    style: GoogleFonts.sourceCodePro(fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: _m3InputDecoration(
                      context: context,
                      labelText: isAr ? 'اسم مستخدم شركة الدعاية المخصص للحملة' : 'Custom Campaign Agency Username',
                      hintText: 'ops_${slugPreview}_custom',
                      prefixIcon: Icons.person_outline_rounded,
                    ),
                  ),
                ),
                if (isMobile) const SizedBox(height: 12) else const SizedBox(width: 14),
                Expanded(
                  flex: isMobile ? 0 : 1,
                  child: TextFormField(
                    controller: _customAgencyPasswordController,
                    style: GoogleFonts.sourceCodePro(fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: _m3InputDecoration(
                      context: context,
                      labelText: isAr ? 'كلمة المرور المخصصة للحملة' : 'Custom Campaign Agency Password',
                      hintText: defaultOpsPass,
                      prefixIcon: Icons.lock_outline_rounded,
                    ),
                  ),
                ),
              ],
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

  Widget _buildUnifiedAiAndRulesStudio(
    BuildContext context,
    ColorScheme colorScheme,
    bool isMobile,
    AppStrings strings,
  ) {
    final conflicts = _detectRuleConflicts();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: 0.08),
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Studio Main Header
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
                            'استوديو العروض وقواعد الذكاء الاصطناعي (AI & Rules Studio)',
                            style: GoogleFonts.cairo(
                              fontSize: 16,
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
                            'AI ⚡ Studio',
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
                      'إدارة وتنسيق قواعد العروض والجوائز الترويجية، وربطها بمخزون الشركة، وتوليد منطق الفحص الذكي تلقائياً.',
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

          // ⚠️ Smart Conflict & Duplicate Detector Alert Banner
          if (conflicts.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.primaryFixedDim, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: colorScheme.onSecondaryContainer, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'الكاشف الذكي: تم رصد (${conflicts.length}) تعارض أو تكرار في قواعد العرض',
                          style: GoogleFonts.cairo(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...conflicts.map((conflict) {
                    return Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colorScheme.secondaryFixedDim),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  conflict.title,
                                  style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                                Text(
                                  conflict.description,
                                  style: GoogleFonts.cairo(
                                    fontSize: 11.5,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (conflict.onResolve != null && conflict.suggestedFixLabel != null)
                            FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                backgroundColor: colorScheme.onSecondaryFixedVariant,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: conflict.onResolve,
                              child: Text(
                                conflict.suggestedFixLabel!,
                                style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 1️⃣ الخطوة 1: تحديد وإضافة العروض (1-Click Presets & Assistant)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.touch_app_rounded, color: colorScheme.primary, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '1️⃣ إضافة وتحديد عروض الحملة:',
                      style: GoogleFonts.cairo(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        side: BorderSide(color: colorScheme.onTertiaryFixedVariant.withValues(alpha: 0.5)),
                      ),
                      icon: Icon(Icons.add_rounded, size: 16, color: colorScheme.tertiary),
                      label: Text(
                        strings.addCustomRuleBtn,
                        style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: colorScheme.onTertiaryFixedVariant),
                      ),
                      onPressed: () => _showAddOrEditPromotionalRuleDialog(context),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Quick Presets Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.primaryFixedDim),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      hint: Row(
                        children: [
                          Icon(Icons.flash_on_rounded, size: 18, color: colorScheme.secondary),
                          const SizedBox(width: 8),
                          Text(
                            '⚡ نماذج عروض وقواعد شائعة جاهزة (إدراج فوري بنقرة واحدة)...',
                            style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold, color: colorScheme.onSecondaryContainer),
                          ),
                        ],
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'oral_bundle_range_all',
                          child: Text('✨🦷 إدراج حزم العناية بالفم الثلاثة بنطاق الأسعار والخصومات (95-140-190 ج.م)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: colorScheme.tertiary)),
                        ),
                        DropdownMenuItem(
                          value: 'oral_bundle_100',
                          child: Text('🦷 حزمة العناية بالفم 1: سيجنال أو كلوس اب ≥ 100 ج.م -> فواتشر 25 ج.م', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        ),
                        DropdownMenuItem(
                          value: 'oral_bundle_150',
                          child: Text('🦷 حزمة العناية بالفم 2: سيجنال أو كلوس اب ≥ 150 ج.م -> فواتشر 50 ج.م', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        ),
                        DropdownMenuItem(
                          value: 'oral_bundle_200',
                          child: Text('🦷 حزمة العناية بالفم 3: سيجنال أو كلوس اب ≥ 200 ج.م -> فواتشر 75 ج.م', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        ),
                        DropdownMenuItem(
                          value: 'tresemme_single',
                          child: Text('🧴 شراء 1 تريزيمي 400 مل -> هدية تريزيمي 250 مل', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        ),
                        DropdownMenuItem(
                          value: 'tresemme_shrink',
                          child: Text('🧴 شراء عرض شرنك تريزيمي 2ق (أو بكج مزدوج) -> هدية تريزيمي 250 مل', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        ),
                        DropdownMenuItem(
                          value: 'clear_360',
                          child: Text('🧴 شراء 1 كلير 360 مل -> هدية كلير 90 مل', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        ),
                        DropdownMenuItem(
                          value: 'spray_1pc_50',
                          child: Text('💳 شراء 1 اسبراي ريكسونا أو أكس -> فواتشر 50 ج.م', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        ),
                        DropdownMenuItem(
                          value: 'spray_2pc_125',
                          child: Text('💳 شراء 2 اسبراي ريكسونا أو أكس -> فواتشر 125 ج.م (2×50 + 1×25)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        ),
                        DropdownMenuItem(
                          value: 'rollon_2pc_50',
                          child: Text('💳 شراء 2 رول أون ريكسونا أو أكس -> فواتشر 50 ج.م', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        ),
                        DropdownMenuItem(
                          value: 'axe_twin_shrink',
                          child: Text('💳 شراء عرض شرنك أكس المزدوج (بندل 2 قطعة) -> فواتشر 125 ج.م', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        ),
                        DropdownMenuItem(
                          value: 'sunsilk_2pc_50',
                          child: Text('💳 شراء 2 صانسيلك (أو عرض شامبو+بلسم المزدوج) -> فواتشر 50 ج.م', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
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

                const SizedBox(height: 12),

                // Collapsible Natural Language AI Assistant Expansion
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    initiallyExpanded: _isAiAssistantExpanded,
                    onExpansionChanged: (exp) => setState(() => _isAiAssistantExpanded = exp),
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.auto_fix_high_rounded, color: colorScheme.primary, size: 18),
                    ),
                    title: Text(
                      'أو صياغة فكرة العرض بحرية عبر مساعد الذكاء الاصطناعي 🪄',
                      style: GoogleFonts.cairo(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    children: [
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _promotionalIdeaController,
                        maxLines: 3,
                        minLines: 2,
                        style: const TextStyle(fontSize: 13, height: 1.4),
                        decoration: InputDecoration(
                          hintText: strings.aiCampaignIdeaHint,
                          hintStyle: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colorScheme.outlineVariant)),
                          contentPadding: const EdgeInsets.all(10),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: FilledButton.icon(
                          onPressed: _isAiStructuringRules ? null : _structureCampaignWithAi,
                          icon: _isAiStructuringRules
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                                )
                              : const Icon(Icons.auto_awesome_rounded, size: 18),
                          label: Text(
                            _isAiStructuringRules ? strings.aiGeneratingRulesLoading : strings.aiGenerateRulesBtn,
                            style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 2️⃣ الخطوة 2: بطاقات العروض والجوائز المعتمدة (Active Promotional Rules Cards)
          Row(
            children: [
              Icon(Icons.fact_check_rounded, color: colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                '2️⃣ قواعد العروض والجوائز المعتمدة في الحملة:',
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
              if (_promotionalRules.isNotEmpty)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: colorScheme.error),
                  icon: const Icon(Icons.clear_all_rounded, size: 16),
                  label: Text('مسح الكل', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    setState(() {
                      _promotionalRules.clear();
                      _aiValidationSummary = '';
                    });
                    _syncPromptFromRules(showSnackbar: false);
                  },
                ),
            ],
          ),

          const SizedBox(height: 8),

          if (_promotionalRules.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  Icon(Icons.card_giftcard_rounded, size: 36, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                  const SizedBox(height: 8),
                  Text(
                    'لم يتم إضافة أي قواعد عروض ترويجية حتى الآن',
                    style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                  ),
                  Text(
                    'اختر نموذجاً جاهزاً من القائمة أعلاه أو أضف قاعدة مخصصة بنقرة واحدة.',
                    style: GoogleFonts.cairo(fontSize: 11.5, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            )
          else
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

          const SizedBox(height: 16),

          // 3️⃣ الخطوة 3: التوليد التلقائي للبرومبت مع خيار المعاينة المتقدمة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.tertiaryFixedDim),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: colorScheme.onTertiaryFixedVariant, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'منطق تدقيق وفحص الذكاء الاصطناعي (AI Prompt) متزامن ويعمل تلقائياً في الخلفية 100%',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Optional Advanced Prompt Customizer Accordion (Closed by default)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              initiallyExpanded: _isPromptExpanded,
              onExpansionChanged: (exp) => setState(() => _isPromptExpanded = exp),
              leading: Icon(Icons.code_rounded, size: 18, color: colorScheme.onSurfaceVariant),
              title: Text(
                '👁️ معاينة أو تخصيص متقدم للبرومبت البرمجي (AI Prompt Customizer) - اختياري للمطورين',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              children: [
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildVariableChip(context, '{TARGET_COMPANY}', 'اسم الشركة'),
                    _buildVariableChip(context, '{MIN_SPEND}', 'الحد الأدنى'),
                    _buildVariableChip(context, '{REQUIRED_PRODUCTS}', 'المنتجات المشترطة'),
                    const SizedBox(width: 6),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.onTertiaryFixedVariant.withValues(alpha: 0.12),
                        foregroundColor: colorScheme.onTertiaryFixedVariant,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 15),
                      label: Text(
                        strings.syncPromptFromRulesBtn,
                        style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _syncPromptFromRules,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: TextFormField(
                    controller: _customPromptController,
                    maxLines: 9,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.all(6),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
        badgeColor = colorScheme.onSecondaryFixedVariant;
        typeLabel = strings.voucherRewardLabel;
        break;
      case 'game_spin':
        icon = Icons.casino_rounded;
        badgeColor = colorScheme.primary;
        typeLabel = strings.gameSpinRewardLabel;
        break;
      case 'free_product':
      default:
        icon = Icons.card_giftcard_rounded;
        badgeColor = colorScheme.onTertiaryFixedVariant;
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

    final int linkedItemsCount = rule.selectedProductIds.isNotEmpty
        ? rule.selectedProductIds.length
        : (rule.selectedBarcodes.isNotEmpty ? rule.selectedBarcodes.length : rule.selectedProductNames.length);

    String triggerDisplay;
    if (rule.requiredBrands.isNotEmpty) {
      final brandsStr = 'منتجات ${rule.requiredBrands.join(rule.isCombo ? ' و ' : ' أو ')}';
      if (linkedItemsCount > 0) {
        final barcodePart = rule.selectedBarcodes.isNotEmpty ? ' - ${rule.selectedBarcodes.length} باركود' : '';
        triggerDisplay = '$brandsStr ($linkedItemsCount صنف$barcodePart)';
      } else {
        triggerDisplay = brandsStr;
      }
    } else if (linkedItemsCount > 0) {
      final barcodePart = rule.selectedBarcodes.isNotEmpty ? ' و ${rule.selectedBarcodes.length} باركود' : '';
      triggerDisplay = '$linkedItemsCount صنف$barcodePart محدد من الكتالوج';
    } else if (rule.triggerProduct.isNotEmpty && rule.triggerProduct.length <= 80 && !rule.triggerProduct.contains('،')) {
      triggerDisplay = rule.triggerProduct;
    } else {
      triggerDisplay = rule.triggerProduct.length > 80
          ? '${rule.triggerProduct.substring(0, 77)}...'
          : rule.triggerProduct;
    }

    String conditionSummary;
    if (rule.isCombo) {
      conditionSummary = '• الشرط: شراء بقيمة ${rule.minSpend.toInt()} ج.م من ($triggerDisplay) معاً ➔ المكافأة: [${rule.rewardValue}]';
    } else if (rule.isSpendBased) {
      conditionSummary = '• الشرط: شراء بقيمة ${rule.minSpend.toInt()} ج.م من ($triggerDisplay) ➔ المكافأة: [${rule.rewardValue}]';
    } else {
      conditionSummary = '• الشرط: شراء كمية ${rule.minQuantity} قطعة من ($triggerDisplay) ➔ المكافأة: [${rule.rewardValue}]';
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLinkedToInventory
              ? colorScheme.tertiaryFixedDim
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
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 5,
                      runSpacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
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
                        if (rule.gameType != null && rule.gameType!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: rule.gameType == 'directGift'
                                  ? colorScheme.tertiaryContainer
                                  : (rule.gameType == 'scratch'
                                      ? colorScheme.primaryContainer
                                      : (rule.gameType == 'wheel'
                                          ? colorScheme.primaryContainer
                                          : colorScheme.secondaryContainer)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  rule.gameType == 'directGift'
                                      ? Icons.redeem_rounded
                                      : (rule.gameType == 'scratch'
                                          ? Icons.style_rounded
                                          : (rule.gameType == 'wheel'
                                              ? Icons.casino_rounded
                                              : Icons.grid_view_rounded)),
                                  size: 11,
                                  color: rule.gameType == 'directGift'
                                      ? colorScheme.onTertiaryContainer
                                      : (rule.gameType == 'scratch'
                                          ? colorScheme.onPrimaryContainer
                                          : (rule.gameType == 'wheel'
                                              ? colorScheme.onPrimaryContainer
                                              : colorScheme.onSecondaryContainer)),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  rule.gameType == 'directGift'
                                      ? 'هدية فورية مباشرة'
                                      : (rule.gameType == 'scratch'
                                          ? 'خربش واكسب'
                                          : (rule.gameType == 'wheel'
                                              ? 'عجلة الحظ'
                                              : 'اختر هديتك')),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: rule.gameType == 'directGift'
                                        ? colorScheme.onTertiaryContainer
                                        : (rule.gameType == 'scratch'
                                            ? colorScheme.onPrimaryContainer
                                            : (rule.gameType == 'wheel'
                                                ? colorScheme.onPrimaryContainer
                                                : colorScheme.onSecondaryContainer)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (rule.isCombo)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'حزمة كومبو (${rule.requiredBrands.join(' + ')})',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          )
                        else if (rule.isSpendBased)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'شرط إنفاق (${rule.minSpend.toInt()} ج.م)',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'شرط كمية (${rule.minQuantity} قطعة)',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        if (rule.selectedBarcodes.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '🏷️ ${rule.selectedBarcodes.length} باركود',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onTertiaryContainer,
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: isLinkedToInventory
                                ? colorScheme.tertiaryContainer
                                : colorScheme.secondaryContainer,
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
                                    ? colorScheme.onTertiaryFixedVariant
                                    : colorScheme.onSecondaryContainer,
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
                                      ? colorScheme.onTertiaryContainer
                                      : colorScheme.onSecondaryContainer,
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
                icon: Icon(Icons.edit_note_rounded, size: 22, color: colorScheme.tertiary),
                tooltip: strings.editRuleTitle,
                onPressed: () => _showAddOrEditPromotionalRuleDialog(context, ruleIndex: index),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline_rounded, size: 20, color: colorScheme.error),
                tooltip: strings.deleteRuleTooltip,
                onPressed: () {
                  setState(() {
                    _promotionalRules.removeAt(index);
                  });
                  _syncPromptFromRules(showSnackbar: false);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            conditionSummary,
            style: GoogleFonts.cairo(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          if (linkedItemsCount > 0) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _showSelectedProductsViewerDialog(rule),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.tertiaryFixedDim),
                ),
                child: Row(
                  children: [
                    Icon(Icons.format_list_bulleted_rounded, size: 16, color: colorScheme.onTertiaryFixedVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'قائمة الأصناف والباركودات المربوطة بهذا الشرط ($linkedItemsCount صنف) — انقر للاستعراض والبحث',
                        style: GoogleFonts.cairo(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorScheme.onTertiaryFixedVariant,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'عرض القائمة',
                            style: GoogleFonts.cairo(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.open_in_new_rounded, size: 12, color: Colors.white),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),

          // Multi-Gift & Voucher Linker Card
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isLinkedToInventory
                  ? colorScheme.tertiaryContainer.withValues(alpha: 0.5)
                  : colorScheme.secondaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isLinkedToInventory
                    ? colorScheme.tertiaryFixedDim
                    : colorScheme.primaryFixedDim,
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
                      color: isLinkedToInventory ? colorScheme.onTertiaryFixedVariant : colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        strings.linkedCompanyGiftLabel,
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isLinkedToInventory ? colorScheme.onTertiaryContainer : colorScheme.onSecondaryContainer,
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
                                backgroundColor: colorScheme.onTertiaryFixedVariant,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'لم نتمكن من مطابقة فئات الفواتشر في المخزون بدقة مع $effectiveVoucherAmount ج.م',
                                ),
                                backgroundColor: colorScheme.onSecondaryFixedVariant,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: colorScheme.primaryFixedDim),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome_rounded, size: 13, color: colorScheme.onSecondaryContainer),
                              const SizedBox(width: 4),
                              Text(
                                '${strings.autoDecomposeLabel} (${effectiveVoucherAmount.toInt()} ج.م)',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSecondaryContainer,
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
                        border: Border.all(color: colorScheme.tertiaryFixedDim),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            alloc.isVoucher
                                ? Icons.confirmation_number_rounded
                                : Icons.card_giftcard_rounded,
                            size: 16,
                            color: alloc.isVoucher ? colorScheme.onSecondaryFixedVariant : colorScheme.onTertiaryFixedVariant,
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
                                    style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
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
                                color: colorScheme.surfaceContainer,
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
                                color: colorScheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(Icons.add, size: 14),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(Icons.close_rounded, size: 16, color: colorScheme.error),
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
                                ? colorScheme.onTertiaryFixedVariant
                                : colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${strings.totalCardsValueLabel} ${rule.totalVoucherValue.toInt()} ج.م '
                            '${(rule.totalVoucherValue - effectiveVoucherAmount).abs() < 0.01 ? '(مطابقة تامة ومكتملة ✓)' : '(المطلوب: ${effectiveVoucherAmount.toInt()} ج.م)'}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: (rule.totalVoucherValue - effectiveVoucherAmount).abs() < 0.01
                                  ? colorScheme.onTertiaryContainer
                                  : colorScheme.onSecondaryContainer,
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
                          : colorScheme.onTertiaryContainer,
                      fontWeight: rule.linkedGifts.isEmpty ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
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
                              color: isVoucher ? colorScheme.onSecondaryFixedVariant : colorScheme.onTertiaryFixedVariant,
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
                                  color: colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  gift.formattedUnitValue,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSecondaryContainer,
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
                              imageUrl: selectedGift.imageUrl,
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
    final chainsStream = _ensureChainsStream();

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
                    color: isAlreadyAdded ? colorScheme.tertiary : colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    chain.name,
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      color: isAlreadyAdded ? colorScheme.onTertiaryFixedVariant : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: isAlreadyAdded ? colorScheme.tertiary.withValues(alpha: 0.15) : colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isAlreadyAdded ? 'مضافة بالحملة ✔️' : '${chain.branchesCount} فرع',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isAlreadyAdded ? colorScheme.onTertiaryFixedVariant : colorScheme.onSecondaryContainer,
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
            // Smart Importer Action Button Banner
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primaryContainer,
                      foregroundColor: colorScheme.onPrimaryContainer,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => _openSmartBranchImporter(cleanChains),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 20),
                    label: Text(
                      '✨ استيراد وتحديد الفروع بالذكاء الاصطناعي (لصق نص • ملف إكسيل • صورة / PDF)',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

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
                            icon: Icon(Icons.close_rounded, color: colorScheme.error),
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
                                _chainBranchSearchControllers[chainId]?.dispose();
                                _chainBranchSearchControllers.remove(chainId);
                                _chainSelectedGovernorateFilterMap.remove(chainId);
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
                              // 1. Header with title, counter, and actions
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'اختر الفروع المشمولة لـ ($chainName):',
                                        style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: selectedBranchIds.isNotEmpty
                                              ? colorScheme.primaryContainer
                                              : colorScheme.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '${selectedBranchIds.length} من ${chainBranches.length} فرع محدد',
                                          style: GoogleFonts.cairo(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: selectedBranchIds.isNotEmpty
                                                ? colorScheme.onPrimaryContainer
                                                : colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      if (chainBranches.isNotEmpty) ...[
                                        TextButton.icon(
                                          onPressed: () {
                                            setState(() {
                                              _chainSelectedBranchIdsMap[chainId] = chainBranches.map((b) => b.id).toSet();
                                              _chainSelectedBranchNamesMap[chainId] = chainBranches.map((b) => b.branchName).toSet();
                                            });
                                          },
                                          icon: const Icon(Icons.select_all_rounded, size: 16),
                                          label: Text('تحديد الكل (${chainBranches.length})', style: GoogleFonts.cairo(fontSize: 12)),
                                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                                        ),
                                        TextButton.icon(
                                          onPressed: () {
                                            setState(() {
                                              _chainSelectedBranchIdsMap[chainId] = {};
                                              _chainSelectedBranchNamesMap[chainId] = {};
                                            });
                                          },
                                          icon: const Icon(Icons.deselect_rounded, size: 16),
                                          label: Text('إلغاء التحديد', style: GoogleFonts.cairo(fontSize: 12)),
                                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                                        ),
                                      ],
                                      OutlinedButton.icon(
                                        onPressed: () => _showQuickAddBranchDialog(chainId, chainName),
                                        icon: const Icon(Icons.add_location_alt_rounded, size: 15),
                                        label: Text('+ فرع جديد', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),

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
                              else ...[
                                const SizedBox(height: 12),

                                // 2. Instant Live Search Bar
                                TextField(
                                  controller: _getBranchSearchController(chainId),
                                  onChanged: (_) => setState(() {}),
                                  style: GoogleFonts.cairo(fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: 'بحث سريع بالاسم أو المنطقة (مثال: ابو يوسف، سموحة، بدر، دمنهور، المحلة...)...',
                                    hintStyle: GoogleFonts.cairo(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                    ),
                                    prefixIcon: Icon(Icons.search_rounded, size: 20, color: colorScheme.primary),
                                    suffixIcon: (_chainBranchSearchControllers[chainId]?.text.isNotEmpty ?? false)
                                        ? IconButton(
                                            icon: const Icon(Icons.clear_rounded, size: 18),
                                            tooltip: 'مسح البحث',
                                            onPressed: () {
                                              _chainBranchSearchControllers[chainId]?.clear();
                                              setState(() {});
                                            },
                                          )
                                        : null,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    filled: true,
                                    fillColor: colorScheme.surface,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                                    ),
                                  ),
                                ),

                                // 3. Quick Governorate Filter Tabs / Chips & Grouped Cards
                                Builder(
                                  builder: (context) {
                                    final searchQuery = _chainBranchSearchControllers[chainId]?.text.trim() ?? '';
                                    final filteredByQueryBranches = chainBranches
                                        .where((b) => _doesBranchMatchQuery(b, searchQuery))
                                        .toList();

                                    // Calculate all governorate counts in this chain
                                    final Map<String, int> govBranchCounts = {};
                                    for (final branch in chainBranches) {
                                      final gov = _resolveBranchGovernorate(branch);
                                      govBranchCounts[gov] = (govBranchCounts[gov] ?? 0) + 1;
                                    }

                                    final availableGovs = govBranchCounts.keys.toList()..sort(_compareGovernorates);
                                    final activeGovFilter = _chainSelectedGovernorateFilterMap[chainId];

                                    // Only show governorate filter bar if there is more than 1 governorate
                                    final showGovFilterBar = availableGovs.length > 1;

                                    // Filter by active governorate
                                    List<BranchModel> finalDisplayedBranches = filteredByQueryBranches;
                                    if (activeGovFilter != null && activeGovFilter != 'all') {
                                      finalDisplayedBranches = filteredByQueryBranches
                                          .where((b) => _resolveBranchGovernorate(b) == activeGovFilter)
                                          .toList();
                                    }

                                    // Group displayed branches by governorate
                                    final Map<String, List<BranchModel>> groupedGovBranches = {};
                                    for (final b in finalDisplayedBranches) {
                                      final gov = _resolveBranchGovernorate(b);
                                      groupedGovBranches.putIfAbsent(gov, () => []).add(b);
                                    }

                                    // Sort branches inside each governorate alphabetically
                                    for (final list in groupedGovBranches.values) {
                                      list.sort((a, b) => a.branchName.compareTo(b.branchName));
                                    }

                                    final sortedGovKeys = groupedGovBranches.keys.toList()..sort(_compareGovernorates);

                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (showGovFilterBar) ...[
                                          const SizedBox(height: 10),
                                          SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(
                                              children: [
                                                ChoiceChip(
                                                  label: Text(
                                                    'جميع المحافظات (${chainBranches.length})',
                                                    style: GoogleFonts.cairo(
                                                      fontSize: 11,
                                                      fontWeight: (activeGovFilter == null || activeGovFilter == 'all')
                                                          ? FontWeight.bold
                                                          : FontWeight.w500,
                                                    ),
                                                  ),
                                                  selected: activeGovFilter == null || activeGovFilter == 'all',
                                                  onSelected: (selected) {
                                                    if (selected) {
                                                      setState(() {
                                                        _chainSelectedGovernorateFilterMap[chainId] = 'all';
                                                      });
                                                    }
                                                  },
                                                ),
                                                const SizedBox(width: 6),
                                                ...availableGovs.map((gov) {
                                                  final count = govBranchCounts[gov] ?? 0;
                                                  final isGovSelected = activeGovFilter == gov;
                                                  final govColor = _getGovernorateColor(gov, colorScheme);
                                                  final icon = _getGovernorateIcon(gov);

                                                  return Padding(
                                                    padding: const EdgeInsets.only(left: 6),
                                                    child: ChoiceChip(
                                                      avatar: Icon(
                                                        icon,
                                                        size: 14,
                                                        color: isGovSelected ? colorScheme.onPrimary : govColor,
                                                      ),
                                                      label: Text(
                                                        '$gov ($count)',
                                                        style: GoogleFonts.cairo(
                                                          fontSize: 11,
                                                          fontWeight: isGovSelected ? FontWeight.bold : FontWeight.w500,
                                                        ),
                                                      ),
                                                      selected: isGovSelected,
                                                      onSelected: (selected) {
                                                        setState(() {
                                                          _chainSelectedGovernorateFilterMap[chainId] = selected ? gov : 'all';
                                                        });
                                                      },
                                                    ),
                                                  );
                                                }),
                                              ],
                                            ),
                                          ),
                                        ],

                                        const SizedBox(height: 12),

                                        // 4. Empty State if search yields no results
                                        if (finalDisplayedBranches.isEmpty)
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                                            decoration: BoxDecoration(
                                              color: colorScheme.surface,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.search_off_rounded, size: 36, color: colorScheme.outline),
                                                const SizedBox(height: 8),
                                                Text(
                                                  searchQuery.isNotEmpty
                                                      ? 'لم يتم العثور على أي فرع يطابق "$searchQuery"'
                                                      : 'لا توجد فروع في هذا القسم',
                                                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                                                  textAlign: TextAlign.center,
                                                ),
                                                if (searchQuery.isNotEmpty || (activeGovFilter != null && activeGovFilter != 'all')) ...[
                                                  const SizedBox(height: 8),
                                                  OutlinedButton.icon(
                                                    onPressed: () {
                                                      _chainBranchSearchControllers[chainId]?.clear();
                                                      _chainSelectedGovernorateFilterMap[chainId] = 'all';
                                                      setState(() {});
                                                    },
                                                    icon: const Icon(Icons.refresh_rounded, size: 16),
                                                    label: Text('إعادة ضبط البحث والفلاتر', style: GoogleFonts.cairo(fontSize: 12)),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          )
                                        else
                                          // 5. Grouped Governorate Cards
                                          ...sortedGovKeys.map((gov) {
                                            final govBranches = groupedGovBranches[gov] ?? [];
                                            final govColor = _getGovernorateColor(gov, colorScheme);
                                            final govIcon = _getGovernorateIcon(gov);

                                            // Count selected branches in this governorate
                                            final selectedInGovCount = govBranches.where((b) =>
                                                selectedBranchIds.contains(b.id) ||
                                                selectedBranchNames.contains(b.branchName)
                                            ).length;

                                            final isAllGovSelected = govBranches.isNotEmpty && selectedInGovCount == govBranches.length;

                                            return Container(
                                              margin: const EdgeInsets.only(bottom: 12),
                                              decoration: BoxDecoration(
                                                color: colorScheme.surface,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: selectedInGovCount > 0
                                                      ? govColor.withValues(alpha: 0.4)
                                                      : colorScheme.outlineVariant.withValues(alpha: 0.4),
                                                  width: selectedInGovCount > 0 ? 1.2 : 1.0,
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  // Governorate Header
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                    decoration: BoxDecoration(
                                                      color: govColor.withValues(alpha: 0.07),
                                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Container(
                                                          padding: const EdgeInsets.all(4),
                                                          decoration: BoxDecoration(
                                                            color: govColor.withValues(alpha: 0.15),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Icon(govIcon, size: 16, color: govColor),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          gov,
                                                          style: GoogleFonts.cairo(
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 13,
                                                            color: colorScheme.onSurface,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                                                          decoration: BoxDecoration(
                                                            color: isAllGovSelected
                                                                ? colorScheme.primary
                                                                : (selectedInGovCount > 0
                                                                    ? govColor.withValues(alpha: 0.2)
                                                                    : colorScheme.surfaceContainerHighest),
                                                            borderRadius: BorderRadius.circular(10),
                                                          ),
                                                          child: Text(
                                                            '$selectedInGovCount من ${govBranches.length} مشمول',
                                                            style: GoogleFonts.cairo(
                                                              fontSize: 10.5,
                                                              fontWeight: FontWeight.bold,
                                                              color: isAllGovSelected
                                                                  ? colorScheme.onPrimary
                                                                  : (selectedInGovCount > 0
                                                                      ? govColor
                                                                      : colorScheme.onSurfaceVariant),
                                                            ),
                                                          ),
                                                        ),
                                                        const Spacer(),
                                                        TextButton.icon(
                                                          onPressed: () {
                                                            setState(() {
                                                              final idsSet = _chainSelectedBranchIdsMap.putIfAbsent(chainId, () => {});
                                                              final namesSet = _chainSelectedBranchNamesMap.putIfAbsent(chainId, () => {});
                                                              if (isAllGovSelected) {
                                                                // Deselect all in this governorate
                                                                for (final b in govBranches) {
                                                                  idsSet.remove(b.id);
                                                                  namesSet.remove(b.branchName);
                                                                }
                                                              } else {
                                                                // Select all in this governorate
                                                                for (final b in govBranches) {
                                                                  idsSet.add(b.id);
                                                                  namesSet.add(b.branchName);
                                                                }
                                                              }
                                                            });
                                                          },
                                                          icon: Icon(
                                                            isAllGovSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                                                            size: 14,
                                                            color: govColor,
                                                          ),
                                                          label: Text(
                                                            isAllGovSelected ? 'إلغاء فروع المحافظة' : 'تحديد كل فروع المحافظة',
                                                            style: GoogleFonts.cairo(
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.bold,
                                                              color: govColor,
                                                            ),
                                                          ),
                                                          style: TextButton.styleFrom(
                                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                            minimumSize: Size.zero,
                                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),

                                                  // Branches FilterChips
                                                  Padding(
                                                    padding: const EdgeInsets.all(10),
                                                    child: Wrap(
                                                      spacing: 8,
                                                      runSpacing: 8,
                                                      children: govBranches.map((branch) {
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
                                                  ),
                                                ],
                                              ),
                                            );
                                          }),
                                      ],
                                    );
                                  },
                                ),
                              ],
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

  // --- RETAIL CHAIN BRANCHES SEARCH & GOVERNORATE GROUPING LOGIC ---

  static const String _govAlexandria = 'الإسكندرية';
  static const String _govCairoGiza = 'القاهرة والجيزة';
  static const String _govNorthCoast = 'الساحل الشمالي ومطروح';
  static const String _govBeheira = 'البحيرة';
  static const String _govGharbiaDelta = 'الغربية والدلتا';
  static const String _govCanalDamietta = 'دمياط ومدن القناة';
  static const String _govUpperEgypt = 'محافظات الصعيد والبحر الأحمر';
  static const String _govOther = 'فروع ومناطق أخرى';

  static const List<String> _canonicalGovernorateOrder = [
    _govAlexandria,
    _govCairoGiza,
    _govNorthCoast,
    _govBeheira,
    _govGharbiaDelta,
    _govCanalDamietta,
    _govUpperEgypt,
    _govOther,
  ];

  TextEditingController _getBranchSearchController(String chainId) {
    return _chainBranchSearchControllers.putIfAbsent(chainId, () => TextEditingController());
  }

  static String _normalizeBranchSearchText(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[ًٌٍَُِّْـ]'), '') // remove tashkeel & tatweel
        .replaceAll(RegExp(r'[إأآا]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[\s_-]+'), ' ')
        .trim();
  }

  static String _resolveBranchGovernorate(BranchModel branch) {
    final rawCity = branch.city.trim();
    final rawName = branch.branchName.trim();
    final rawAddress = branch.address.trim();

    // Extract parenthetical governorate if present in branchName, e.g. "فرع بدر (القاهرة)"
    String parenthetical = '';
    final parenMatch = RegExp(r'\(([^)]+)\)').firstMatch(rawName);
    if (parenMatch != null) {
      parenthetical = parenMatch.group(1)?.trim() ?? '';
    }

    final normCity = _normalizeBranchSearchText(rawCity);
    final normParen = _normalizeBranchSearchText(parenthetical);
    final normName = _normalizeBranchSearchText(rawName);
    final normAddress = _normalizeBranchSearchText(rawAddress);

    bool hasInLoc(List<String> keywords) {
      for (final kw in keywords) {
        final normKw = _normalizeBranchSearchText(kw);
        if (normCity.contains(normKw) || normParen.contains(normKw)) return true;
      }
      return false;
    }

    bool hasAnywhere(List<String> keywords) {
      for (final kw in keywords) {
        final normKw = _normalizeBranchSearchText(kw);
        if (normCity.contains(normKw) ||
            normParen.contains(normKw) ||
            normName.contains(normKw) ||
            normAddress.contains(normKw)) {
          return true;
        }
      }
      return false;
    }

    // A. Alexandria check
    if (hasInLoc(['اسكندرية', 'الإسكندرية', 'alexandria', 'alex'])) {
      return _govAlexandria;
    }

    // B. Cairo & Giza check
    if (hasInLoc(['القاهرة', 'الجيزة', 'cairo', 'giza', 'اكتوبر', 'زايد', 'تجمع', 'معادي', 'شروق', 'بدر', 'عبور', 'مدينتي', 'رحاب'])) {
      return _govCairoGiza;
    }

    // C. North Coast & Matrouh check
    if (hasInLoc(['مطروح', 'الساحل الشمالي', 'ساحل', 'علمين', 'مارينا', 'امواج', 'روزانا', 'سيدي عبد الرحمن', 'الضبعة', 'الحمام'])) {
      return _govNorthCoast;
    }

    // D. Beheira check
    if (hasInLoc(['البحيرة', 'دمنهور', 'كفر الدوار', 'ايتاي', 'حوش عيسى', 'ابو حمص', 'رشيد', 'ادكو', 'كوم حمادة'])) {
      return _govBeheira;
    }

    // E. Gharbia & Delta check
    if (hasInLoc(['الغربية', 'طنطا', 'المحلة', 'الدقهلية', 'المنصورة', 'المنوفية', 'شبين', 'القليوبية', 'بنها', 'الشرقية', 'الزقازيق', 'كفر الشيخ', 'دلتا'])) {
      return _govGharbiaDelta;
    }

    // F. Damietta & Canal check
    if (hasInLoc(['دمياط', 'بورسعيد', 'الإسماعيلية', 'السويس', 'القناة', 'راس البر'])) {
      return _govCanalDamietta;
    }

    // G. Upper Egypt & Red Sea check
    if (hasInLoc(['صعيد', 'الفيوم', 'بني سويف', 'المنيا', 'اسيوط', 'سوهاج', 'قنا', 'الأقصر', 'اسوان', 'البحر الاحمر', 'الغردقة', 'شرم الشيخ'])) {
      return _govUpperEgypt;
    }

    // If city or parenthetical didn't match, check full text keywords for Alexandria sub-areas:
    if (hasAnywhere([
      'سموحة', 'ستانلي', 'سيدي بشر', 'سيدي جابر', 'الابراهيمية', 'الانفوشي',
      'الدخيلة', 'العجمي', 'الهانوفيل', 'البيطاش', 'ابو يوسف', 'جاردينيا',
      'سيتي سكوير', 'ميامي', 'فكتوريا', 'العصافرة', 'المنتزه', 'المندرة',
      'محرم بك', 'الشاطبي', 'كامب شيزار', 'كليوباترا', 'رشدي', 'جليم',
      'سابا باشا', 'ثروت', 'زيزينيا', 'جناكليس', 'بولكلي', 'شدس', 'العوايد',
      'السيوف', 'المعمورة', 'بحري', 'المنشية', 'محطة الرمل', 'الورديان', 'المكس', 'برج العرب'
    ])) {
      return _govAlexandria;
    }

    // Check full text keywords for Cairo & Giza sub-areas:
    if (hasAnywhere([
      'المعادي', 'مدينة نصر', 'مصر الجديدة', 'التجمع', 'الرحاب', 'مدينتي',
      'الشروق', 'العبور', 'الشيخ زايد', '6 اكتوبر', 'حدائق الاهرام',
      'المهندسين', 'الدقي', 'الهرم', 'فيصل', 'العجوزة', 'الزمالك', 'شبرا',
      'حلوان', 'المقطم', 'عين شمس', 'المرج', 'المطرية', 'الزيتون', 'حدائق القبة'
    ])) {
      return _govCairoGiza;
    }

    // Check full text for North Coast
    if (hasAnywhere(['أمواج', 'امواج', 'روزانا', 'مارينا', 'مراسي', 'هاسيندا', 'العلمين'])) {
      return _govNorthCoast;
    }

    // Check full text for Beheira
    if (hasAnywhere(['دمنهور', 'كفر الدوار', 'ايتاي البارود'])) {
      return _govBeheira;
    }

    // Check full text for Delta
    if (hasAnywhere(['المحلة', 'طنطا', 'المنصورة', 'بنها', 'الزقازيق', 'شبين الكوم'])) {
      return _govGharbiaDelta;
    }

    // Check full text for Damietta
    if (hasAnywhere(['دمياط', 'بورسعيد', 'الاسماعيلية', 'السويس', 'راس البر'])) {
      return _govCanalDamietta;
    }

    // If branch has a specific non-empty city name, return it cleanly
    if (rawCity.isNotEmpty) {
      return rawCity;
    }

    return _govOther;
  }

  static int _compareGovernorates(String a, String b) {
    final idxA = _canonicalGovernorateOrder.indexOf(a);
    final idxB = _canonicalGovernorateOrder.indexOf(b);
    if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
    if (idxA != -1) return -1;
    if (idxB != -1) return 1;
    return a.compareTo(b);
  }

  static bool _doesBranchMatchQuery(BranchModel branch, String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return true;
    final cleanQuery = _normalizeBranchSearchText(trimmed);
    if (cleanQuery.isEmpty) return true;

    final cleanName = _normalizeBranchSearchText(branch.branchName);
    final cleanCity = _normalizeBranchSearchText(branch.city);
    final cleanCode = _normalizeBranchSearchText(branch.branchCode);
    final cleanAddress = _normalizeBranchSearchText(branch.address);

    final fullText = '$cleanName $cleanCity $cleanCode $cleanAddress';

    // 1. Direct match on full text
    if (fullText.contains(cleanQuery)) return true;

    // 2. Also check without the word "فرع"
    final strippedQuery = cleanQuery.replaceAll(RegExp(r'\bفرع\b'), '').trim();
    final strippedName = cleanName.replaceAll(RegExp(r'\bفرع\b'), '').trim();
    if (strippedQuery.isNotEmpty) {
      if (strippedName.contains(strippedQuery) || fullText.contains(strippedQuery)) {
        return true;
      }
    }

    // 3. Multi-token match: all tokens in query must appear in fullText
    final tokens = cleanQuery.split(' ').where((t) => t.isNotEmpty && t != 'فرع').toList();
    if (tokens.isNotEmpty && tokens.every((token) => fullText.contains(token))) {
      return true;
    }

    return false;
  }

  static IconData _getGovernorateIcon(String gov) {
    switch (gov) {
      case _govAlexandria:
        return Icons.waves_rounded;
      case _govCairoGiza:
        return Icons.location_city_rounded;
      case _govNorthCoast:
        return Icons.beach_access_rounded;
      case _govBeheira:
        return Icons.agriculture_rounded;
      case _govGharbiaDelta:
        return Icons.factory_rounded;
      case _govCanalDamietta:
        return Icons.directions_boat_rounded;
      case _govUpperEgypt:
        return Icons.wb_sunny_rounded;
      default:
        return Icons.store_mall_directory_rounded;
    }
  }

  static Color _getGovernorateColor(String gov, ColorScheme colorScheme) {
    switch (gov) {
      case _govAlexandria:
        return colorScheme.primary; // Sky blue
      case _govCairoGiza:
        return colorScheme.primary; // Royal purple
      case _govNorthCoast:
        return colorScheme.tertiary; // Teal
      case _govBeheira:
        return colorScheme.tertiary; // Emerald green
      case _govGharbiaDelta:
        return colorScheme.onSecondaryFixedVariant; // Warm amber-orange
      case _govCanalDamietta:
        return colorScheme.primary; // Deep marine blue
      case _govUpperEgypt:
        return colorScheme.secondary; // Golden sun
      default:
        return colorScheme.primary;
    }
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
        activeBranchName = b != null
            ? (b.city.isNotEmpty && !b.branchName.contains(b.city) && !b.branchName.contains('(')
                ? '${b.branchName} (${b.city})'
                : b.branchName)
            : activeBranchId;
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
                                  color: colorScheme.onSecondaryFixedVariant,
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
                                    ? colorScheme.onTertiaryFixedVariant
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
                                color: remaining > 0 ? colorScheme.onTertiaryFixedVariant : colorScheme.error,
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
