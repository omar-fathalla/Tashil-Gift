import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/retail_chains_service.dart';
import '../../../core/services/branch_signature_ai_service.dart';
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
  Map<String, int> _liveBranchCounts = const {};
  int _branchCountFor(RetailChainModel chain) =>
      _liveBranchCounts.isEmpty ? chain.branchesCount : (_liveBranchCounts[chain.id] ?? 0);

  ColorScheme get colorScheme => Theme.of(context).colorScheme;

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

  // AI Receipt Scanner
  final ImagePicker _picker = ImagePicker();
  bool _isScanningReceipt = false;
  bool _isDeduplicating = false;

  // Memoized Firestore Streams (Rule 9: Never create streams inside build)
  Stream<List<RetailChainModel>>? _chainsStream;
  Stream<List<BranchModel>>? _branchesStream;

  void _ensureStreams() {
    _chainsStream ??= ref.read(retailChainsServiceProvider).getRetailChainsStream();
    _branchesStream ??= ref.read(retailChainsServiceProvider).getAllBranchesStream();
  }

  @override
  void initState() {
    super.initState();
    // Auto-run background deduplication on mount to clean any pre-existing duplicate docs
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(retailChainsServiceProvider).deduplicateAllBranchesInFirestore();
    });
  }

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

  Future<void> _deduplicateRecords() async {
    setState(() => _isDeduplicating = true);
    final isAr = ref.isArabic;
    try {
      final deletedCount = await ref.read(retailChainsServiceProvider).deduplicateAllBranchesInFirestore();
      if (mounted) {
        if (deletedCount > 0) {
          await M3Feedback.showSuccess(
            context,
            title: isAr ? 'تم تنظيف وحذف السجلات المكررة 🛡️' : 'Duplicate Records Cleaned',
            message: isAr
                ? 'تم فحص قاعدة البيانات وحذف $deletedCount سجل مكرر بنجاح، وتوحيد السجلات الأساسية.'
                : 'Scanned database and safely removed $deletedCount duplicate records.',
          );
        } else {
          await M3Feedback.showSuccess(
            context,
            title: isAr ? 'قاعدة البيانات نقية ومطابقة 100% ✨' : 'Database Fully Clean',
            message: isAr
                ? 'لا توجد أي سجلات مكررة، جميع السلاسل والفروع فريدة ومطابقة للمعايير.'
                : 'No duplicate records found. All chains and branches are unique.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorHandler.getFriendlyMessage(e, defaultMessage: isAr ? 'حدث خطأ أثناء تنظيف التكرارات' : 'Error cleaning duplicates')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeduplicating = false);
    }
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
        final isDuplicate = await service.addRetailChain(chain);
        if (mounted) {
          if (isDuplicate) {
            await M3Feedback.showDuplicateWarning(
              context,
              title: 'تم رفض الإضافة: السلسلة مسجلة مسبقاً ⚠️',
              message: 'السلسلة التجارية "$name" مسجلة مسبقاً بالفعل في النظام. تم رفض العملية لمنع تكرار البيانات.',
            );
            return;
          } else {
            await M3Feedback.showAdded(
              context,
              itemName: name,
              message: 'تمت إضافة السلسلة التجارية إلى النظام بنجاح.',
              icon: Icons.storefront_rounded,
            );
          }
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
              backgroundColor: colorScheme.onTertiaryFixedVariant,
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
        final isDuplicate = await service.addBranch(branch);
        if (mounted) {
          if (isDuplicate) {
            await M3Feedback.showDuplicateWarning(
              context,
              title: 'تم رفض الإضافة: الفرع مسجل مسبقاً ⚠️',
              message: 'فرع "$branchName" مسجل مسبقاً بالفعل في السلسلة "${selectedChain.name}". تم رفض تسجيله لمنع التكرار.',
            );
            return;
          } else {
            await M3Feedback.showAdded(
              context,
              itemName: '$branchName (${selectedChain.name})',
              message: 'تمت إضافة الفرع بنجاح.',
              icon: Icons.store_rounded,
            );
          }
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
              backgroundColor: colorScheme.onTertiaryFixedVariant,
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

  // --- AI RECEIPT & POS SIGNATURE SCANNER ---

  Future<void> _scanReceiptWithAi(List<RetailChainModel> existingChains) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (image == null) return;

      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) return;

      if (!mounted) return;
      setState(() => _isScanningReceipt = true);

      final isAr = ref.isArabic;

      // Show animated loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          return PopScope(
            canPop: false,
            child: Dialog(
              backgroundColor: cs.surfaceContainerHighest,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.auto_awesome_rounded, color: cs.primary, size: 36),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      isAr ? 'جاري تحليل بصمة البونة بالذكاء الاصطناعي...' : 'Analyzing receipt signature with AI...',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isAr
                          ? 'استخراج كود المتجر، رقم الـ POS، نسق الباركود، والكلمات الدلالية للفرع والسلسلة.'
                          : 'Extracting Store ID, POS pattern, Barcode structure, and Brand keywords.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 220,
                      child: LinearProgressIndicator(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      final result = await ref
          .read(branchSignatureAiServiceProvider)
          .extractSignatureFromImage(bytes, existingChains: existingChains);

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Close loading dialog
        _showSignatureConfirmationDialog(result, existingChains, bytes);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'فشل تحليل بونة الفاتورة بالذكاء الاصطناعي'),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanningReceipt = false);
    }
  }

  void _showSignatureConfirmationDialog(
    ExtractedBranchSignatureResult result,
    List<RetailChainModel> existingChains,
    Uint8List imageBytes,
  ) {
    final isAr = ref.isArabic;
    final strings = AppStrings.of(ref);

    // Form state
    bool isLinkingExisting = result.isMatchedWithExistingChain && existingChains.isNotEmpty;
    String? selectedChainId = result.matchedChainId ?? (existingChains.isNotEmpty ? existingChains.first.id : null);

    final chainNameCtrl = TextEditingController(text: result.chainName);
    final chainSlugCtrl = TextEditingController(text: result.chainSlug);
    final branchNameCtrl = TextEditingController(text: result.branchName);
    final cityCtrl = TextEditingController(text: result.city);
    final branchCodeCtrl = TextEditingController(text: result.branchCode);
    final addressCtrl = TextEditingController(text: result.address);

    final storeIdCtrl = TextEditingController(text: result.storeId);
    final posPatternCtrl = TextEditingController(text: result.posNumberPattern);
    final receiptPatternCtrl = TextEditingController(text: result.receiptPattern);
    final taxNumberCtrl = TextEditingController(text: result.taxNumber);
    final commercialRegCtrl = TextEditingController(text: result.commercialReg);
    final hotlineCtrl = TextEditingController(text: result.hotline);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final cs = Theme.of(context).colorScheme;

            return Dialog(
              backgroundColor: cs.surface,
              surfaceTintColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780, maxHeight: 720),
                child: Column(
                  children: [
                    // Header Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  strings.signatureExtractedSuccess,
                                  style: GoogleFonts.cairo(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: cs.onPrimaryContainer,
                                  ),
                                ),
                                Text(
                                  isAr
                                      ? 'تم تحليل بنية البونة واستخراج بصمة الكاشير بنجاح. راجع البيانات واعتمدها.'
                                      : 'Receipt structure analyzed successfully. Review and save.',
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Confidence badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: cs.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified_rounded, size: 14, color: colorScheme.tertiary),
                                const SizedBox(width: 4),
                                Text(
                                  '${strings.confidenceScoreLabel}: ${(result.confidenceScore * 100).toInt()}%',
                                  style: GoogleFonts.cairo(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Scrollable Body
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Receipt Image + Summary Card
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.memory(
                                      imageBytes,
                                      width: 90,
                                      height: 120,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.receipt_long_rounded, size: 18, color: cs.primary),
                                            const SizedBox(width: 6),
                                            Text(
                                              isAr ? 'ملخص البصمة المكتشفة' : 'Detected Signature Summary',
                                              style: GoogleFonts.cairo(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: cs.onSurface,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          result.extractedSummary.isNotEmpty
                                              ? result.extractedSummary
                                              : (isAr
                                                  ? 'تم التعرف على كود المتجر [${result.storeId}] ونمط باركود [${result.receiptPattern}].'
                                                  : 'Store ID [${result.storeId}] & receipt pattern identified.'),
                                          style: GoogleFonts.cairo(
                                            fontSize: 12.5,
                                            height: 1.4,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                        if (result.headerKeywords.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: result.headerKeywords.map((k) {
                                              return Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: cs.primary.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  k,
                                                  style: GoogleFonts.cairo(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: cs.primary,
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Section 1: Retail Chain Selection
                            Text(
                              isAr ? '1. السلسلة التجارية التابع لها الفرع' : '1. Retail Chain Organization',
                              style: GoogleFonts.cairo(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Chain mode switcher
                            if (existingChains.isNotEmpty) ...[
                              SegmentedButton<bool>(
                                segments: [
                                  ButtonSegment<bool>(
                                    value: true,
                                    label: Text(strings.linkWithExistingChain, style: GoogleFonts.cairo(fontSize: 12)),
                                    icon: const Icon(Icons.link_rounded, size: 16),
                                  ),
                                  ButtonSegment<bool>(
                                    value: false,
                                    label: Text(strings.createNewChain, style: GoogleFonts.cairo(fontSize: 12)),
                                    icon: const Icon(Icons.add_business_rounded, size: 16),
                                  ),
                                ],
                                selected: {isLinkingExisting},
                                onSelectionChanged: (set) {
                                  setDialogState(() {
                                    isLinkingExisting = set.first;
                                  });
                                },
                              ),
                              const SizedBox(height: 12),
                            ],

                            if (isLinkingExisting && existingChains.isNotEmpty) ...[
                              Builder(
                                builder: (context) {
                                  final hasValidChain = existingChains.any((c) => c.id == selectedChainId);
                                  final effectiveId = hasValidChain
                                      ? selectedChainId
                                      : (existingChains.isNotEmpty ? existingChains.first.id : null);
                                  return DropdownButtonFormField<String>(
                                    key: ValueKey('link_chain_${effectiveId}_${existingChains.length}'),
                                    initialValue: effectiveId,
                                    decoration: InputDecoration(
                                      labelText: isAr ? 'اختر السلسلة المسجلة' : 'Select Existing Chain',
                                      prefixIcon: const Icon(Icons.storefront_rounded),
                                      filled: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    items: existingChains.map((c) {
                                      return DropdownMenuItem<String>(
                                        value: c.id,
                                        child: Text('${c.name} (${_branchCountFor(c)} فرع)', style: GoogleFonts.cairo(fontSize: 13)),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      setDialogState(() => selectedChainId = val);
                                    },
                                  );
                                },
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: chainNameCtrl,
                                      decoration: InputDecoration(
                                        labelText: isAr ? 'اسم السلسلة التجارية *' : 'Chain Name *',
                                        prefixIcon: const Icon(Icons.storefront_rounded),
                                        filled: true,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      controller: chainSlugCtrl,
                                      decoration: InputDecoration(
                                        labelText: isAr ? 'المعرف اللاتيني (Slug)' : 'Chain Slug',
                                        prefixIcon: const Icon(Icons.tag_rounded),
                                        filled: true,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            const SizedBox(height: 20),

                            // Section 2: Branch Info
                            Text(
                              isAr ? '2. بيانات الفرع المستخرجة' : '2. Extracted Branch Details',
                              style: GoogleFonts.cairo(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 10),

                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    controller: branchNameCtrl,
                                    decoration: InputDecoration(
                                      labelText: isAr ? 'اسم الفرع *' : 'Branch Name *',
                                      prefixIcon: const Icon(Icons.store_rounded),
                                      filled: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: cityCtrl,
                                    decoration: InputDecoration(
                                      labelText: isAr ? 'المدينة' : 'City',
                                      prefixIcon: const Icon(Icons.location_city_rounded),
                                      filled: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: branchCodeCtrl,
                                    decoration: InputDecoration(
                                      labelText: isAr ? 'كود الفرع المختصر' : 'Branch Code',
                                      prefixIcon: const Icon(Icons.pin_outlined),
                                      filled: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // Section 3: Smart POS Receipt Signature Fields
                            Row(
                              children: [
                                Icon(Icons.shield_rounded, size: 18, color: cs.primary),
                                const SizedBox(width: 6),
                                Text(
                                  isAr ? '3. البصمة الهيكلية لنظام الكاشير (Smart POS Signature)' : '3. POS Receipt Signature',
                                  style: GoogleFonts.cairo(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: storeIdCtrl,
                                    decoration: InputDecoration(
                                      labelText: strings.posStoreId,
                                      hintText: '502, 440, 4, 3912...',
                                      prefixIcon: const Icon(Icons.confirmation_number_rounded),
                                      filled: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: posPatternCtrl,
                                    decoration: InputDecoration(
                                      labelText: isAr ? 'نسق رقم الـ POS' : 'POS Format',
                                      hintText: 'PoS: 1, POS: 21...',
                                      prefixIcon: const Icon(Icons.point_of_sale_rounded),
                                      filled: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            TextFormField(
                              controller: receiptPatternCtrl,
                              decoration: InputDecoration(
                                labelText: strings.receiptBarcodePattern,
                                hintText: 'Trans/PoS/Store/Date أو 66{Store}{POS}{Receipt}{Date}',
                                prefixIcon: const Icon(Icons.qr_code_2_rounded),
                                filled: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(height: 12),

                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: taxNumberCtrl,
                                    decoration: InputDecoration(
                                      labelText: isAr ? 'الرقم الضريبي (ب.ض)' : 'Tax Number',
                                      prefixIcon: const Icon(Icons.receipt_outlined),
                                      filled: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: hotlineCtrl,
                                    decoration: InputDecoration(
                                      labelText: isAr ? 'الخط الساخن' : 'Hotline',
                                      prefixIcon: const Icon(Icons.phone_in_talk_rounded),
                                      filled: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Actions Bottom Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            child: Text(strings.cancel, style: GoogleFonts.cairo()),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: () async {
                              final branchName = branchNameCtrl.text.trim();
                              if (branchName.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(isAr ? 'يرجى إدخال اسم الفرع' : 'Branch name is required'),
                                    backgroundColor: cs.error,
                                  ),
                                );
                                return;
                              }

                              String targetChainId = '';
                              String targetChainName = '';

                              final service = ref.read(retailChainsServiceProvider);

                              if (isLinkingExisting && selectedChainId != null) {
                                targetChainId = selectedChainId!;
                                final matched = existingChains.firstWhere(
                                  (c) => c.id == targetChainId,
                                  orElse: () => RetailChainModel(id: targetChainId, name: '', slug: ''),
                                );
                                targetChainName = matched.name;
                              } else {
                                final cName = chainNameCtrl.text.trim();
                                if (cName.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(isAr ? 'يرجى إدخال اسم السلسلة' : 'Chain name is required'),
                                      backgroundColor: cs.error,
                                    ),
                                  );
                                  return;
                                }
                                final cSlug = chainSlugCtrl.text.trim().toLowerCase().toEnglishDigits().replaceAll(RegExp(r'\s+'), '-');
                                final newChain = RetailChainModel(
                                  id: '',
                                  name: cName,
                                  slug: cSlug.isNotEmpty ? cSlug : cName.toLowerCase().replaceAll(RegExp(r'\s+'), '-'),
                                );
                                await service.addRetailChain(newChain);
                                final allChains = await service.getRetailChains();
                                final savedChain = allChains.firstWhere(
                                  (c) => c.name == cName || c.slug == newChain.slug,
                                  orElse: () => newChain,
                                );
                                targetChainId = savedChain.id;
                                targetChainName = savedChain.name;
                              }

                              final sig = BranchReceiptSignature(
                                storeId: storeIdCtrl.text.trim().toEnglishDigits(),
                                posNumberPattern: posPatternCtrl.text.trim().toEnglishDigits(),
                                receiptPattern: receiptPatternCtrl.text.trim().toEnglishDigits(),
                                headerKeywords: result.headerKeywords,
                                footerKeywords: result.footerKeywords,
                                taxNumber: taxNumberCtrl.text.trim().toEnglishDigits(),
                                commercialReg: commercialRegCtrl.text.trim().toEnglishDigits(),
                                hotline: hotlineCtrl.text.trim().toEnglishDigits(),
                                extractedSummary: result.extractedSummary,
                                confidenceScore: result.confidenceScore,
                                scannedAt: DateTime.now(),
                              );

                              final newBranch = BranchModel(
                                id: '',
                                retailChainId: targetChainId,
                                retailChainName: targetChainName,
                                branchName: branchName,
                                city: cityCtrl.text.trim(),
                                branchCode: branchCodeCtrl.text.trim().toUpperCase().toEnglishDigits(),
                                address: addressCtrl.text.trim(),
                                receiptSignature: sig,
                              );

                              // Check if branch already exists in this chain
                              final existingBranch = await service.findMatchingBranch(newBranch);

                              if (existingBranch != null) {
                                if (!context.mounted) return;
                                final shouldUpdate = await _showBranchUpdateDiffDialog(
                                  context: context,
                                  existingBranch: existingBranch,
                                  newBranch: newBranch,
                                  chainName: targetChainName,
                                );

                                if (shouldUpdate != true) {
                                  // User cancelled update
                                  return;
                                }

                                await service.upsertBranch(newBranch.copyWith(id: existingBranch.id));
                                if (context.mounted) {
                                  Navigator.of(dialogCtx).pop();
                                  await M3Feedback.showSuccess(
                                    context,
                                    title: isAr ? 'تم تحديث بيانات وبصمة الفرع بنجاح! 🔄' : 'Branch & Signature Updated! 🔄',
                                    message: isAr
                                        ? 'تم تحديث فرع "$branchName" في سلسلة "$targetChainName" بالبصمة الجديدة المستخرجة من الإيصال (Store ID: ${sig.storeId}).'
                                        : 'Branch "$branchName" updated with new receipt POS signature.',
                                  );
                                }
                              } else {
                                await service.upsertBranch(newBranch);
                                if (context.mounted) {
                                  Navigator.of(dialogCtx).pop();
                                  await M3Feedback.showSuccess(
                                    context,
                                    title: isAr ? 'تم اعتماد الفرع والبصمة بنجاح! 🛡️' : 'Branch & Signature Saved!',
                                    message: isAr
                                        ? 'تم ربط فرع "$branchName" بالسلسلة "$targetChainName" مع بصمة الكاشير (Store ID: ${sig.storeId}).'
                                        : 'Branch "$branchName" saved with smart POS signature.',
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.verified_rounded, size: 18),
                            label: Text(
                              strings.saveChainAndBranchWithSignature,
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showSignatureDetailsModal(BranchModel branch) {
    final sig = branch.receiptSignature;
    if (sig == null) return;

    final isAr = ref.isArabic;
    final strings = AppStrings.of(ref);
    final cs = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 550),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colorScheme.tertiary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.verified_user_rounded, color: colorScheme.tertiary, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${branch.branchName} (${branch.retailChainName})',
                              style: GoogleFonts.cairo(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: cs.onSurface,
                              ),
                            ),
                            Text(
                              strings.hasSmartSignatureBadge,
                              style: GoogleFonts.cairo(
                                fontSize: 12,
                                color: colorScheme.onTertiaryFixedVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: [
                        _buildSignatureDetailRow(cs, strings.posStoreId, sig.storeId.isNotEmpty ? sig.storeId : 'غير محدد'),
                        const Divider(height: 16),
                        _buildSignatureDetailRow(cs, isAr ? 'نسق رقم الـ POS' : 'POS Format', sig.posNumberPattern.isNotEmpty ? sig.posNumberPattern : 'تلقائي'),
                        const Divider(height: 16),
                        _buildSignatureDetailRow(cs, strings.receiptBarcodePattern, sig.receiptPattern.isNotEmpty ? sig.receiptPattern : 'تلقائي'),
                        if (sig.taxNumber.isNotEmpty) ...[
                          const Divider(height: 16),
                          _buildSignatureDetailRow(cs, isAr ? 'الرقم الضريبي' : 'Tax Number', sig.taxNumber),
                        ],
                        if (sig.hotline.isNotEmpty) ...[
                          const Divider(height: 16),
                          _buildSignatureDetailRow(cs, isAr ? 'الخط الساخن' : 'Hotline', sig.hotline),
                        ],
                      ],
                    ),
                  ),
                  if (sig.extractedSummary.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      sig.extractedSummary,
                      style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurfaceVariant, height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonal(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(isAr ? 'إغلاق' : 'Close', style: GoogleFonts.cairo()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSignatureDetailRow(ColorScheme cs, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.cairo(fontSize: 12.5, color: cs.onSurfaceVariant)),
        Text(
          value,
          style: GoogleFonts.cairo(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }

  // --- AUTOMATED BRANCH DATA ENRICHMENT MODALS ---

  void _showBranchEnrichmentModal(BranchModel branch) {
    final pe = branch.pendingEnrichment;
    if (pe == null) return;

    final isAr = ref.isArabic;
    final cs = Theme.of(context).colorScheme;
    final sig = branch.receiptSignature;

    final List<_BranchFieldDiff> diffs = [];

    if (pe.storeId.isNotEmpty) {
      final currentStoreId = sig?.storeId.isNotEmpty == true ? sig!.storeId : branch.branchCode;
      diffs.add(_BranchFieldDiff(
        fieldLabel: isAr ? 'كود المتجر (Store ID)' : 'Store ID',
        icon: Icons.confirmation_number_rounded,
        oldValue: currentStoreId.isNotEmpty ? currentStoreId : (isAr ? 'غير مسجل' : 'Not set'),
        newValue: pe.storeId,
      ));
    }

    if (pe.posNumber.isNotEmpty) {
      final currentPos = sig?.posNumberPattern ?? '';
      diffs.add(_BranchFieldDiff(
        fieldLabel: isAr ? 'رقم / نمط نقطة البيع (POS)' : 'POS Pattern',
        icon: Icons.point_of_sale_rounded,
        oldValue: currentPos.isNotEmpty ? currentPos : (isAr ? 'غير مسجل' : 'Not set'),
        newValue: pe.posNumber,
      ));
    }

    if (pe.branchAddress.isNotEmpty) {
      diffs.add(_BranchFieldDiff(
        fieldLabel: isAr ? 'العنوان التفصيلي' : 'Address',
        icon: Icons.place_outlined,
        oldValue: branch.address.isNotEmpty ? branch.address : (isAr ? 'غير مسجل' : 'Not set'),
        newValue: pe.branchAddress,
      ));
    }

    if (pe.taxNumber.isNotEmpty) {
      final currentTax = sig?.taxNumber ?? '';
      diffs.add(_BranchFieldDiff(
        fieldLabel: isAr ? 'الرقم الضريبي' : 'Tax Number',
        icon: Icons.receipt_outlined,
        oldValue: currentTax.isNotEmpty ? currentTax : (isAr ? 'غير مسجل' : 'Not set'),
        newValue: pe.taxNumber,
      ));
    }

    if (pe.commercialReg.isNotEmpty) {
      final currentComm = sig?.commercialReg ?? '';
      diffs.add(_BranchFieldDiff(
        fieldLabel: isAr ? 'السجل التجاري' : 'Commercial Reg',
        icon: Icons.badge_outlined,
        oldValue: currentComm.isNotEmpty ? currentComm : (isAr ? 'غير مسجل' : 'Not set'),
        newValue: pe.commercialReg,
      ));
    }

    if (pe.hotline.isNotEmpty) {
      final currentHotline = sig?.hotline ?? '';
      diffs.add(_BranchFieldDiff(
        fieldLabel: isAr ? 'الخط الساخن' : 'Hotline',
        icon: Icons.phone_in_talk_rounded,
        oldValue: currentHotline.isNotEmpty ? currentHotline : (isAr ? 'غير مسجل' : 'Not set'),
        newValue: pe.hotline,
      ));
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 750),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.primary,
                        colorScheme.primary,
                      ],
                    ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isAr ? 'مراجعة وإثراء بيانات الفرع من الفاتورة الحية' : 'Live Receipt Branch Data Review & Merge',
                              style: GoogleFonts.cairo(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '${branch.branchName} • ${branch.retailChainName}',
                              style: GoogleFonts.cairo(
                                fontSize: 12.5,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),

                // Receipt Source Badge
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  color: colorScheme.primary.withValues(alpha: 0.08),
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long_rounded, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isAr
                              ? 'مصدر الرصد: فاتورة كاشير ${pe.receiptNumber.isNotEmpty ? "#${pe.receiptNumber}" : ""} ${pe.receiptDate.isNotEmpty ? "بتاريخ ${pe.receiptDate}" : ""}'
                              : 'Source: Live Receipt ${pe.receiptNumber.isNotEmpty ? "#${pe.receiptNumber}" : ""} ${pe.receiptDate.isNotEmpty ? "dated ${pe.receiptDate}" : ""}',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Body Diff List
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    shrinkWrap: true,
                    children: [
                      Text(
                        isAr
                            ? 'رصد الذكاء الاصطناعي بيانات تكميلية غير مكتملة في الفرع. يمكنك مراجعتها أدناه ودمجها مباشرة في قاعدة البيانات:'
                            : 'AI detected missing metadata from a live receipt. Review and merge it into the database:',
                        style: GoogleFonts.cairo(fontSize: 12.5, color: cs.onSurfaceVariant, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      ...diffs.map((diff) => _buildEnrichmentDiffRow(cs, isAr, diff)),
                    ],
                  ),
                ),

                // Action Buttons
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                    border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: cs.error,
                        ),
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: Text(
                          isAr ? 'تجاهل المقترح' : 'Dismiss Proposal',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await ref.read(retailChainsServiceProvider).dismissBranchEnrichment(branch.id);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isAr ? 'تم تجاهل المقترح بنجاح' : 'Proposal dismissed',
                                  style: GoogleFonts.cairo(),
                                ),
                              ),
                            );
                          }
                        },
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.check_circle_rounded, size: 20),
                        label: Text(
                          isAr ? 'قبول ودمج البيانات التكميلية ✅' : 'Approve & Merge Metadata ✅',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await ref.read(retailChainsServiceProvider).applyBranchEnrichment(branch.id);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: colorScheme.onTertiaryFixedVariant,
                                content: Text(
                                  isAr
                                      ? '✅ تم دمج البيانات التكميلية واعتماد البصمة الذكية لـ (${branch.branchName}) بنجاح!'
                                      : '✅ Branch metadata successfully merged and verified!',
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _applyAllPendingEnrichmentsModal(List<BranchModel> pendingBranches) {
    final isAr = ref.isArabic;
    final cs = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.done_all_rounded, color: colorScheme.primary, size: 32),
          ),
          title: Text(
            isAr ? 'دمج بيانات جميع الفروع المرصودة' : 'Merge All Detected Branch Metadata',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isAr
                    ? 'هل تريد دمج واعتماد البيانات التكميلية لـ ${pendingBranches.length} فرع دفعة واحدة؟ سيتم تحديث أكواد المتاجر ونقاط البيع والعناوين والبصمات الذكية تلقائياً.'
                    : 'Do you want to merge and verify harvested metadata for ${pendingBranches.length} branches at once? Store codes, POS numbers, addresses, and smart signatures will be updated.',
                style: GoogleFonts.cairo(fontSize: 13, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(10),
                  itemCount: pendingBranches.length,
                  separatorBuilder: (ctx, i) => const Divider(height: 8),
                  itemBuilder: (_, i) {
                    final b = pendingBranches[i];
                    return Text(
                      '• ${b.branchName} (${b.retailChainName})',
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600),
                    );
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(isAr ? 'إلغاء' : 'Cancel', style: GoogleFonts.cairo()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colorScheme.primary),
              onPressed: () async {
                Navigator.of(ctx).pop();
                final count = await ref.read(retailChainsServiceProvider).applyAllPendingEnrichments();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: colorScheme.onTertiaryFixedVariant,
                      content: Text(
                        isAr
                            ? '✅ تم بنجاح دمج وتحديث بيانات $count فرع في قاعدة البيانات!'
                            : '✅ Successfully merged metadata for $count branches!',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                }
              },
              child: Text(
                isAr ? 'تأكيد دمج الكل ✨' : 'Confirm Merge All ✨',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEnrichmentDiffRow(ColorScheme cs, bool isAr, _BranchFieldDiff diff) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(diff.icon, size: 16, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                diff.fieldLabel,
                style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: cs.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAr ? 'البيانات الحالية:' : 'Current Value:',
                        style: GoogleFonts.cairo(fontSize: 10, color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        diff.oldValue.isNotEmpty ? diff.oldValue : (isAr ? 'غير مسجل' : 'None'),
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: diff.oldValue.isNotEmpty && diff.oldValue != 'غير مسجل' && diff.oldValue != 'Not set'
                              ? cs.onSurface
                              : cs.outline,
                          decoration: diff.oldValue.isNotEmpty && diff.oldValue != 'غير مسجل' && diff.oldValue != 'Not set'
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward_rounded, size: 18, color: colorScheme.primary),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAr ? 'المقترح من الفاتورة:' : 'Harvested from Receipt:',
                        style: GoogleFonts.cairo(fontSize: 10, color: colorScheme.onTertiaryFixedVariant, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        diff.newValue,
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- HERO AI SCAN CARD WIDGET ---

  Widget _buildAiScanHeroCard(ColorScheme colorScheme, List<RetailChainModel> chains) {
    final strings = AppStrings.of(ref);

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.tertiaryContainer.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              Icons.document_scanner_rounded,
              color: colorScheme.primary,
              size: 32,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      strings.aiScanReceiptTemplate,
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'AI Vision',
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  strings.aiScanReceiptTemplateSub,
                  style: GoogleFonts.cairo(
                    fontSize: 12.5,
                    color: colorScheme.onPrimaryContainer.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: _isScanningReceipt ? null : () => _scanReceiptWithAi(chains),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _isScanningReceipt
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.camera_alt_rounded, size: 20),
            label: Text(
              _isScanningReceipt ? strings.loading : strings.uploadReceiptSampleBtn,
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    _ensureStreams();
    final chainsStream = _chainsStream;
    final branchesStream = _branchesStream;

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
            // 2.0.172: branch counts per chain come from the loaded branch docs
            // (single source of truth); the stored chain.branchesCount is a
            // denormalized field that drifts (was 48 vs 98 actual branches).
            _liveBranchCounts = <String, int>{};
            for (final b in allBranches) {
              _liveBranchCounts[b.retailChainId] = (_liveBranchCounts[b.retailChainId] ?? 0) + 1;
            }
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
                              // AI Scan Header Action Button
                              FilledButton.icon(
                                onPressed: _isScanningReceipt ? null : () => _scanReceiptWithAi(chains),
                                style: FilledButton.styleFrom(
                                  backgroundColor: colorScheme.primary,
                                  foregroundColor: colorScheme.onPrimary,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: _isScanningReceipt
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.document_scanner_rounded, size: 18),
                                label: Text(
                                  _isScanningReceipt ? strings.loading : strings.uploadReceiptSampleBtn,
                                  style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
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
                              const SizedBox(width: 10),
                              // Auto-deduplicate button
                              FilledButton.tonalIcon(
                                onPressed: _isDeduplicating ? null : _deduplicateRecords,
                                icon: _isDeduplicating
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.cleaning_services_rounded, size: 18),
                                label: Text(
                                  _isDeduplicating ? strings.loading : (isAr ? 'تنظيف التكرارات' : 'Auto-Deduplicate'),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // AI Vision Hero Card for Instant Receipt & Branch Signature Extraction
                          _buildAiScanHeroCard(colorScheme, chains),

                          if (isDesktop)
                            Row(
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
                                  child: _buildDirectoryCard(colorScheme, chains, filteredBranches, allBranches.length, allBranches),
                                ),
                              ],
                            )
                          else
                            Column(
                              children: [
                                _buildChainFormCard(colorScheme),
                                const SizedBox(height: 20),
                                _buildBranchFormCard(colorScheme, chains),
                                const SizedBox(height: 24),
                                _buildDirectoryCard(colorScheme, chains, filteredBranches, allBranches.length, allBranches),
                              ],
                            ),
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
                Builder(
                  builder: (context) {
                    final hasMatchingChain = chains.any((c) => c.id == _selectedChainIdForBranch);
                    final effectiveChainId = hasMatchingChain
                        ? _selectedChainIdForBranch
                        : (chains.isNotEmpty ? chains.first.id : null);

                    return DropdownButtonFormField<String>(
                      key: ValueKey('branch_chain_${effectiveChainId}_${chains.length}'),
                      initialValue: effectiveChainId,
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
                    );
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
    int totalBranchesCount, [
    List<BranchModel> allBranches = const [],
  ]) {
    final pendingEnrichmentBranches = allBranches
        .where((b) => b.pendingEnrichment != null && b.pendingEnrichment!.hasActionableData)
        .toList();

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
                            ? 'دليل السلاسل التجارية المركزية'
                            : 'دليل الفروع ونقاط البيع (POS)',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        _selectedDirectoryTab == 0
                            ? 'إدارة وحوكمة أسماء وشعارات السلاسل الرسمية'
                            : 'استعراض وإدارة جميع الفروع وتعديل بصمات الكاشير الذكية',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Quick Action: Add Chain or Branch
                if (_selectedDirectoryTab == 0)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text('تحديث', style: GoogleFonts.cairo(fontSize: 12)),
                    onPressed: () => setState(() {}),
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
                            if (pendingEnrichmentBranches.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${pendingEnrichmentBranches.length} رادار ✨',
                                  style: GoogleFonts.cairo(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
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
              // Radar Banner for Pending Enrichments
              if (pendingEnrichmentBranches.isNotEmpty) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.primary,
                        colorScheme.primary,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.radar_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'رادار الذكاء الاصطناعي: تم رصد بيانات تكميلية لـ ${pendingEnrichmentBranches.length} فرع من الفواتير الحية',
                              style: GoogleFonts.cairo(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'تم استخراج كود المتجر وPOS والعناوين والأرقام الضريبية تلقائياً من البونات الممسوحة.',
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: colorScheme.onPrimaryFixedVariant,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.done_all_rounded, size: 16),
                        label: Text(
                          'دمج الكل (${pendingEnrichmentBranches.length})',
                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _applyAllPendingEnrichmentsModal(pendingEnrichmentBranches),
                      ),
                    ],
                  ),
                ),
              ],

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
                      label: Text('كل الفروع ($totalBranchesCount)', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
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
                                  '${_branchCountFor(chain)}',
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
    final hasBranches = _branchCountFor(chain) > 0;
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
                      hasBranches ? '${_branchCountFor(chain)} فروع' : '0 فرع (سلسلة فارغة)',
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
                  'استعراض الفروع (${_branchCountFor(chain)})',
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
                if (branch.receiptSignature != null && branch.receiptSignature!.hasSignature) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => _showSignatureDetailsModal(branch),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_user_rounded, size: 13, color: colorScheme.tertiary),
                          const SizedBox(width: 4),
                          Text(
                            'بصمة ذكية معتمدة (Store ID: ${branch.receiptSignature!.storeId.isNotEmpty ? branch.receiptSignature!.storeId : 'نشط'})',
                            style: GoogleFonts.cairo(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onTertiaryFixedVariant,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.info_outline_rounded, size: 12, color: colorScheme.tertiary),
                        ],
                      ),
                    ),
                  ),
                ],
                if (branch.pendingEnrichment != null && branch.pendingEnrichment!.hasActionableData) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => _showBranchEnrichmentModal(branch),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, size: 14, color: colorScheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            'بيانات تكميلية مرصودة من فاتورة حية (${branch.pendingEnrichment!.receiptNumber.isNotEmpty ? "فاتورة #${branch.pendingEnrichment!.receiptNumber}" : "جاهزة للمراجعة"})',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'مراجعة ودمج 🪄',
                              style: GoogleFonts.cairo(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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

  Future<bool?> _showBranchUpdateDiffDialog({
    required BuildContext context,
    required BranchModel existingBranch,
    required BranchModel newBranch,
    required String chainName,
  }) {
    final isAr = ref.isArabic;
    final cs = Theme.of(context).colorScheme;

    final existingSig = existingBranch.receiptSignature;
    final newSig = newBranch.receiptSignature;

    final List<_BranchFieldDiff> diffs = [
      _BranchFieldDiff(
        fieldLabel: isAr ? 'اسم الفرع' : 'Branch Name',
        icon: Icons.store_rounded,
        oldValue: existingBranch.branchName,
        newValue: newBranch.branchName,
      ),
      _BranchFieldDiff(
        fieldLabel: isAr ? 'كود المتجر (Store ID)' : 'Store ID',
        icon: Icons.confirmation_number_rounded,
        oldValue: existingSig?.storeId ?? '',
        newValue: newSig?.storeId ?? '',
      ),
      _BranchFieldDiff(
        fieldLabel: isAr ? 'كود الفرع المختصر' : 'Branch Code',
        icon: Icons.pin_outlined,
        oldValue: existingBranch.branchCode,
        newValue: newBranch.branchCode,
      ),
      _BranchFieldDiff(
        fieldLabel: isAr ? 'نسق رقم الـ POS' : 'POS Pattern',
        icon: Icons.point_of_sale_rounded,
        oldValue: existingSig?.posNumberPattern ?? '',
        newValue: newSig?.posNumberPattern ?? '',
      ),
      _BranchFieldDiff(
        fieldLabel: isAr ? 'نمط الباركود / المعاملة' : 'Receipt Pattern',
        icon: Icons.qr_code_2_rounded,
        oldValue: existingSig?.receiptPattern ?? '',
        newValue: newSig?.receiptPattern ?? '',
      ),
      _BranchFieldDiff(
        fieldLabel: isAr ? 'المدينة' : 'City',
        icon: Icons.location_city_rounded,
        oldValue: existingBranch.city,
        newValue: newBranch.city,
      ),
      _BranchFieldDiff(
        fieldLabel: isAr ? 'العنوان' : 'Address',
        icon: Icons.place_outlined,
        oldValue: existingBranch.address,
        newValue: newBranch.address,
      ),
      _BranchFieldDiff(
        fieldLabel: isAr ? 'الرقم الضريبي' : 'Tax Number',
        icon: Icons.receipt_outlined,
        oldValue: existingSig?.taxNumber ?? '',
        newValue: newSig?.taxNumber ?? '',
      ),
      _BranchFieldDiff(
        fieldLabel: isAr ? 'الخط الساخن' : 'Hotline',
        icon: Icons.phone_in_talk_rounded,
        oldValue: existingSig?.hotline ?? '',
        newValue: newSig?.hotline ?? '',
      ),
    ];

    final hasAnyChanges = diffs.any((d) => d.isChanged);

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: BoxDecoration(
                    color: colorScheme.secondary.withValues(alpha: 0.12),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colorScheme.secondary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.published_with_changes_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isAr ? 'الفرع مسجل مسبقاً - مراجعة وتأكيد التحديث' : 'Branch Already Registered - Review Update',
                              style: GoogleFonts.cairo(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isAr
                                  ? 'تم العثور على سجل سابق لفرع "${existingBranch.branchName}" بسلسلة "$chainName". يرجى مراجعة التغييرات قبل الاعتماد.'
                                  : 'Existing record found for "${existingBranch.branchName}" in "$chainName". Review changes before applying.',
                              style: GoogleFonts.cairo(
                                fontSize: 12.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Diff Body
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    shrinkWrap: true,
                    children: [
                      if (!hasAnyChanges)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.tertiary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_rounded, color: colorScheme.tertiary, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isAr
                                      ? 'جميع بيانات وبصمة الفاتورة متطابقة تماماً مع السجل الحالي في قاعدة البيانات.'
                                      : 'All extracted receipt details match the existing database record.',
                                  style: GoogleFonts.cairo(fontSize: 12.5, color: colorScheme.onTertiaryFixedVariant, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),

                      ...diffs.map((diff) => _buildDiffRow(context, diff, isAr)),
                    ],
                  ),
                ),

                // Action Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                    border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: Text(
                          isAr ? 'إلغاء والإبقاء على البيانات الحالية' : 'Cancel & Keep Existing',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.onSecondaryFixedVariant,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(
                          isAr ? 'تأكيد وتحديث بيانات الفرع' : 'Confirm & Apply Update',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDiffRow(BuildContext context, _BranchFieldDiff diff, bool isAr) {
    final cs = Theme.of(context).colorScheme;
    final isChanged = diff.isChanged;
    final oldDisplay = diff.oldValue.trim().isNotEmpty ? diff.oldValue.trim() : (isAr ? '(فارغ)' : '(Empty)');
    final newDisplay = diff.newValue.trim().isNotEmpty ? diff.newValue.trim() : (isAr ? '(غير مستخرج)' : '(Not extracted)');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isChanged
            ? colorScheme.secondary.withValues(alpha: 0.08)
            : cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isChanged ? colorScheme.secondary.withValues(alpha: 0.4) : cs.outlineVariant.withValues(alpha: 0.3),
          width: isChanged ? 1.2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(diff.icon, size: 18, color: isChanged ? colorScheme.onSecondaryFixedVariant : cs.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
            width: 140,
            child: Text(
              diff.fieldLabel,
              style: GoogleFonts.cairo(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      oldDisplay,
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                        decoration: isChanged ? TextDecoration.lineThrough : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: isChanged ? colorScheme.onSecondaryFixedVariant : cs.outlineVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: isChanged ? colorScheme.secondaryContainer : cs.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isChanged ? colorScheme.secondary : cs.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      newDisplay,
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: isChanged ? FontWeight.bold : FontWeight.normal,
                        color: isChanged ? colorScheme.onSecondaryContainer : cs.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isChanged)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: colorScheme.secondary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isAr ? 'محدث' : 'Updated',
                style: GoogleFonts.cairo(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            )
          else
            Icon(Icons.check_rounded, size: 16, color: colorScheme.onTertiaryFixedVariant),
        ],
      ),
    );
  }
}

class _BranchFieldDiff {
  final String fieldLabel;
  final IconData icon;
  final String oldValue;
  final String newValue;

  _BranchFieldDiff({
    required this.fieldLabel,
    required this.icon,
    required this.oldValue,
    required this.newValue,
  });

  bool get isChanged {
    final oldClean = oldValue.trim();
    final newClean = newValue.trim();
    return newClean.isNotEmpty && oldClean != newClean;
  }
}
