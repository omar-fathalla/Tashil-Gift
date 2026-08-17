import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/services/company_products_service.dart';
import '../../../core/services/ai_product_catalog_service.dart';
import '../../../core/animations/m3_motion.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/arabic_numbers_utils.dart';
import '../../../core/constants/country_currency_config.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/widgets/m3_button_groups.dart';
import '../../../core/widgets/m3_progress_indicators.dart';
import '../domain/company_model.dart';

enum CatalogInputMode {
  manual,
  excelCsv,
  liveCatalog,
}

class CompanyCatalogScreen extends ConsumerStatefulWidget {
  const CompanyCatalogScreen({super.key});

  @override
  ConsumerState<CompanyCatalogScreen> createState() => _CompanyCatalogScreenState();
}

class _CompanyCatalogScreenState extends ConsumerState<CompanyCatalogScreen> {
  // Card 1: Registration Form
  final _regFormKey = GlobalKey<FormState>();
  final _regCompanyNameController = TextEditingController();
  final _regCompanySlugController = TextEditingController();
  final _regCompanyNameFocusNode = FocusNode();
  final _regCompanySlugFocusNode = FocusNode();
  bool _isSavingCompany = false;

  // Card 2: Product Addition & Management
  String? _selectedProductCompanySlug;
  final _companySearchController = TextEditingController();
  final _manualBarcodeController = TextEditingController();
  final _manualProductNameController = TextEditingController();
  final _csvPasteController = TextEditingController();
  CatalogInputMode _activeMode = CatalogInputMode.manual;
  final List<Map<String, dynamic>> _stagedProducts = [];
  bool _isSavingProducts = false;
  double? _saveProgressValue;
  int _savedItemsCount = 0;
  int _totalItemsToSave = 0;
  bool _isAiAnalyzing = false;
  String _aiDetectionSummary = '';

  // Card 3: Global Catalog Browser
  final _globalSearchQueryController = TextEditingController();
  String _selectedGlobalFilter = 'ALL';
  int _catalogDisplayLimit = 20;

  bool _isSeeding = false;
  List<CompanyModel> _existingCompanies = [];

  CompanyModel? _findCompanyByCode(String code) {
    final clean = code.trim().toLowerCase();
    if (clean.isEmpty) return null;
    return _existingCompanies.where((c) => c.slug.toLowerCase().trim() == clean).firstOrNull;
  }

  @override
  void dispose() {
    _regCompanyNameController.dispose();
    _regCompanySlugController.dispose();
    _regCompanyNameFocusNode.dispose();
    _regCompanySlugFocusNode.dispose();
    _companySearchController.dispose();
    _manualBarcodeController.dispose();
    _manualProductNameController.dispose();
    _csvPasteController.dispose();
    _globalSearchQueryController.dispose();
    super.dispose();
  }

  // --- CARD 1 ACTIONS: COMPANY REGISTRATION ---
  Future<void> _saveCompanyOnlyToFirebase() async {
    final companyName = _regCompanyNameController.text.trim();
    final companyCode = _regCompanySlugController.text.trim().toLowerCase();

    if (companyName.isEmpty || companyCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى كتابة اسم الشركة وكودها الرقمي الفريد أولاً')),
      );
      return;
    }

    // Check duplicate code
    final existing = _findCompanyByCode(companyCode);
    if (existing != null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              const SizedBox(width: 10),
              Text(
                'كود الشركة مسجل مسبقاً',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          content: Text(
            'الكود الرقمي ($companyCode) مسجل مسبقاً في النظام باسم:\n"${existing.name}"\n\nهل ترغب في تعديل بيانات هذه الشركة أم اختيار كود رقمي آخر؟',
            style: GoogleFonts.cairo(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('اختيار كود آخر'),
            ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.edit_rounded, size: 18),
              onPressed: () => Navigator.pop(ctx, true),
              label: const Text('تعديل الشركة المسجلة'),
            ),
          ],
        ),
      );

      if (proceed == true && mounted) {
        _showEditCompanyDialog(existing);
      }
      return;
    }

    setState(() => _isSavingCompany = true);
    final firestore = ref.read(firestoreProvider);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final companyRef = firestore.collection('companies').doc(companyCode);
      await companyRef.set({
        'name': companyName,
        'slug': companyCode,
        'productsCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          // Firestore cache completes the write locally and syncs to server in background
        },
      );

      if (mounted) {
        setState(() {
          _selectedProductCompanySlug = companyCode;
          _selectedGlobalFilter = companyCode;
          _regCompanyNameController.clear();
          _regCompanySlugController.clear();
        });

        _regCompanyNameFocusNode.requestFocus();

        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('تم تسجيل وتكويد شركة ($companyName) برقم ($companyCode) بنجاح! تم تحديدها تلقائياً بالأسفل.'),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء تسجيل وتكويد الشركة')),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingCompany = false);
      }
    }
  }

  // --- CARD 2 ACTIONS: PRODUCT MANAGEMENT ---
  Future<void> _addManualProductToStaging() async {
    final barcode = _manualBarcodeController.text.toEnglishDigits().trim();
    final name = _manualProductNameController.text.trim();
    final company = _findCompanyByCode(_selectedProductCompanySlug ?? '');

    if (company == null) {
      M3Feedback.showToast(
        context,
        message: 'يرجى اختيار الشركة المراد إضافة المنتجات إليها أولاً',
        isSuccess: false,
      );
      return;
    }

    if (name.isEmpty && barcode.isEmpty) {
      M3Feedback.showToast(
        context,
        message: 'يرجى كتابة الباركود أو اسم المنتج على الأقل',
        isSuccess: false,
      );
      return;
    }

    // 1. Check against currently staged items in memory
    final inStaging = _stagedProducts.any((p) {
      final pBarcode = (p['barcode'] ?? '').toString().trim();
      final pName = (p['productName'] ?? '').toString().trim().toLowerCase();
      final isBarcodeDuplicate = barcode.isNotEmpty && pBarcode == barcode;
      final isNameDuplicate = name.isNotEmpty && pName == name.toLowerCase();
      return isBarcodeDuplicate || isNameDuplicate;
    });

    if (inStaging) {
      await M3Feedback.showError(
        context,
        title: 'المنتج مكرر في قائمة المعاينة!',
        message: 'هذا المنتج أو كود الباركود (${barcode.isNotEmpty ? barcode : name}) مضاف بالفعل في قائمة المعاينة الحالية بالأعلى، ولن يتم حفظه لمنع التكرار.',
        buttonText: 'فهمت',
      );
      return;
    }

    // 2. Check against database (already registered in system for this company)
    final existingItem = await ref.read(companyProductsServiceProvider).findExistingProduct(
      companySlug: company.slug,
      productName: name,
      barcode: barcode,
    );

    if (existingItem != null) {
      final reason = (barcode.isNotEmpty && existingItem.barcode == barcode)
          ? 'كود الباركود (${existingItem.barcode}) مسجل مسبقاً للصنف: "${existingItem.productName}"'
          : 'اسم المنتج "${existingItem.productName}" مسجل مسبقاً في دليل شركة (${company.name})';

      if (mounted) {
        await M3Feedback.showError(
          context,
          title: 'المنتج مسجل مسبقاً في النظام!',
          message: '$reason\n\nلا يمكن تكرار أو حفظ نفس المنتج لنفس الشركة لضمان دقة التحقق وفحص الفواتير بالذكاء الاصطناعي.',
          buttonText: 'إغلاق',
        );
      }
      return;
    }

    setState(() {
      _stagedProducts.add({
        'productName': name.isNotEmpty ? name : 'منتج بدون اسم',
        'barcode': barcode,
      });
      _manualBarcodeController.clear();
      _manualProductNameController.clear();
    });

    if (mounted) {
      M3Feedback.showToast(
        context,
        message: 'تمت إضافة "$name" إلى قائمة المعاينة الجاهزة للرفع',
        isSuccess: true,
      );
    }
  }

  Future<void> _pickAndParseExcelCsv() async {
    final company = _findCompanyByCode(_selectedProductCompanySlug ?? '');

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv', 'txt'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;

      setState(() => _isAiAnalyzing = true);

      // Show animated AI Analysis Progress Dialog
      if (mounted) {
        _showAiAnalysisProgressDialog(file.name);
      }

      final aiService = ref.read(aiProductCatalogServiceProvider);
      final analysisResult = await aiService.analyzeAndParseFile(
        fileBytes: bytes,
        fileName: file.name,
        companyNameHint: company?.name,
      );

      // Close progress dialog if open
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (mounted) {
        setState(() => _isAiAnalyzing = false);

        if (analysisResult.isSuccess && analysisResult.products.isNotEmpty) {
          setState(() {
            _aiDetectionSummary = analysisResult.detectedSchemaSummary;
            for (final p in analysisResult.products) {
              _stagedProducts.add(p.toMap());
            }
          });

          await M3Feedback.showSuccess(
            context,
            title: 'تم استخراج المنتجات بالـ AI بنجاح',
            message: '${analysisResult.detectedSchemaSummary}\nتم استخراج (${analysisResult.products.length}) صنف جاهز للمعاينة والحفظ.',
            buttonText: 'معاينة الأصناف',
          );
        } else {
          M3Feedback.showToast(
            context,
            message: analysisResult.message,
            isSuccess: false,
          );
        }
      }
    } catch (e) {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        setState(() => _isAiAnalyzing = false);
        M3Feedback.showToast(
          context,
          message: 'حدث خطأ أثناء معالجة الملف بالـ AI: $e',
          isSuccess: false,
        );
      }
    }
  }

  void _showAiAnalysisProgressDialog(String fileName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            backgroundColor: colorScheme.surfaceContainerHigh,
            content: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    ),
                    child: Icon(Icons.auto_awesome_rounded, color: colorScheme.primary, size: 36),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'جاري التحليل الذكي بالـ AI...',
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'يتم الآن فك شفرة ملف "$fileName" واستكشاف أعمدة الأسماء، الباركودات، والمجموعات تلقائياً عبر Gemini AI.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      color: colorScheme.primary,
                      backgroundColor: colorScheme.surfaceContainerHighest,
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

  void _processCsvContentToStaging(String content) {
    if (content.trim().isEmpty) return;

    // Detect binary ZIP / Excel pasted content
    if (content.contains('PK\x03\x04') ||
        content.contains('[Content_Types]') ||
        content.contains(r'$xml') ||
        content.contains('xl/worksheets')) {
      M3Feedback.showToast(
        context,
        message: 'النص المدخل يحتوي على رموز ثنائية لملف مضغوط. يرجى استخدام زر "تحليل واستيراد ملف Excel / CSV بالـ AI" أو نسخ النص من الإكسيل ولصقه هنا.',
        isSuccess: false,
      );
      return;
    }

    final lines = content.split(RegExp(r'\r?\n'));
    int addedCount = 0;

    for (var rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // Skip header lines
      final lowerLine = line.toLowerCase();
      if ((lowerLine.contains('اسم') || lowerLine.contains('name') || lowerLine.contains('صنف') || lowerLine.contains('item')) &&
          (lowerLine.contains('باركود') || lowerLine.contains('barcode') || lowerLine.contains('ean') || lowerLine.contains('كود'))) {
        continue;
      }

      String pName = '';
      String pBarcode = '';

      // 1. Try common column delimiters: Tab \t, Semicolon ;, Comma ,, Pipe |
      List<String> parts = [];
      if (line.contains('\t')) {
        parts = line.split('\t');
      } else if (line.contains(';')) {
        parts = line.split(';');
      } else if (line.contains(',')) {
        parts = line.split(',');
      } else if (line.contains('|')) {
        parts = line.split('|');
      }

      if (parts.length >= 2) {
        final col1 = parts[0].trim();
        final col2 = parts[1].trim();

        final col1Digits = col1.toEnglishDigits().replaceAll('.0', '').replaceAll(RegExp(r'[^\d]'), '');
        final col2Digits = col2.toEnglishDigits().replaceAll('.0', '').replaceAll(RegExp(r'[^\d]'), '');

        if (col1Digits.length >= 7 && !RegExp(r'[\u0600-\u06FFa-zA-Z]').hasMatch(col1)) {
          pBarcode = col1Digits;
          pName = col2;
        } else if (col2Digits.length >= 7 && !RegExp(r'[\u0600-\u06FFa-zA-Z]').hasMatch(col2)) {
          pBarcode = col2Digits;
          pName = col1;
        } else {
          // Fallback: check which column looks like digits vs name
          if (RegExp(r'^\d+$').hasMatch(col1Digits) && col1Digits.length > col2Digits.length) {
            pBarcode = col1Digits;
            pName = col2;
          } else {
            pName = col1;
            pBarcode = col2Digits;
          }
        }
      } else {
        // 2. Single text line (e.g. "6223004149962 ماكسيل 500مل..." or "55500001217 كلوركس كلور...")
        final normalizedLine = line.toEnglishDigits();

        // Check if barcode is at start: 7 to 18 digits followed by spaces or separators and name
        final matchStart = RegExp(r'^(\d{7,18})\s*[-–_:/\\]*\s*(.+)$').firstMatch(normalizedLine);
        if (matchStart != null) {
          pBarcode = matchStart.group(1) ?? '';
          pName = (matchStart.group(2) ?? '').trim();
        } else {
          // Check if barcode is at end: name followed by 7 to 18 digits
          final matchEnd = RegExp(r'^(.+?)\s*[-–_:/\\]*\s*(\d{7,18})$').firstMatch(normalizedLine);
          if (matchEnd != null) {
            pName = (matchEnd.group(1) ?? '').trim();
            pBarcode = matchEnd.group(2) ?? '';
          } else {
            // Pure text or pure barcode
            if (RegExp(r'^\d{7,18}$').hasMatch(normalizedLine.replaceAll('.0', '').trim())) {
              pBarcode = normalizedLine.replaceAll('.0', '').trim();
              pName = 'منتج مستورد';
            } else {
              pName = line;
            }
          }
        }
      }

      pBarcode = pBarcode.toEnglishDigits().replaceAll('.0', '').trim();
      pName = pName.trim().replaceAll(RegExp(r'\s+'), ' ');

      if (pName.isNotEmpty || pBarcode.isNotEmpty) {
        _stagedProducts.add({
          'productName': pName.isNotEmpty ? pName : 'منتج مستورد',
          'barcode': pBarcode,
        });
        addedCount++;
      }
    }

    setState(() {});

    if (mounted) {
      M3Feedback.showToast(
        context,
        message: 'تم استخراج وتفكيك $addedCount صنف مع الباركود بنجاح إلى قائمة المعاينة',
        isSuccess: true,
      );
    }
  }

  Future<void> _commitStagedProductsToFirebase() async {
    final company = _findCompanyByCode(_selectedProductCompanySlug ?? '');
    if (company == null) {
      M3Feedback.showToast(
        context,
        message: 'يرجى اختيار الشركة أولاً من القائمة المنسدلة لإضافة المنتجات إليها',
        isSuccess: false,
      );
      return;
    }

    if (_stagedProducts.isEmpty) {
      M3Feedback.showToast(
        context,
        message: 'قائمة المنتجات الجاهزة فارغة، أضف منتجات أولاً للمعاينة',
        isSuccess: false,
      );
      return;
    }

    setState(() {
      _isSavingProducts = true;
      _saveProgressValue = 0.0;
      _savedItemsCount = 0;
      _totalItemsToSave = _stagedProducts.length;
    });

    try {
      final totalSaved = await ref.read(companyProductsServiceProvider).batchSaveProducts(
        companySlug: company.slug,
        companyName: company.name,
        products: _stagedProducts,
        onProgress: (saved, total) {
          if (mounted) {
            setState(() {
              _savedItemsCount = saved;
              _totalItemsToSave = total;
              _saveProgressValue = total > 0 ? (saved / total).clamp(0.0, 1.0) : 0.0;
            });
          }
        },
      );

      if (mounted) {
        // Complete the progress to 100%
        setState(() {
          _saveProgressValue = 1.0;
          _savedItemsCount = totalSaved;
        });

        await Future.delayed(const Duration(milliseconds: 350));

        if (!mounted) return;

        setState(() {
          _stagedProducts.clear();
          _aiDetectionSummary = '';
          _selectedGlobalFilter = company.slug;
        });

        await M3Feedback.showSuccess(
          context,
          title: 'تم حفظ وتكويد $totalSaved منتج بنجاح!',
          message: 'تم تسجيل كافة المنتجات في قاعدة البيانات السحابية لشركة (${company.name}) مع تحديث إحصائيات الشركة.',
          buttonText: 'ممتاز',
        );
      }
    } catch (e) {
      if (mounted) {
        M3Feedback.showToast(
          context,
          message: AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء حفظ المنتجات في قاعدة البيانات'),
          isSuccess: false,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingProducts = false);
      }
    }
  }

  // --- EDIT & DELETE COMPANY MODALS ---
  Future<void> _showEditCompanyDialog(CompanyModel company) async {
    final nameCtrl = TextEditingController(text: company.name);
    final codeCtrl = TextEditingController(text: company.slug);
    final errorColor = Theme.of(context).colorScheme.error;
    bool isUpdating = false;

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogContentCtx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.edit_note_rounded, color: Colors.blueAccent, size: 26),
                const SizedBox(width: 8),
                Text('تعديل بيانات الشركة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'يمكنك تعديل اسم الشركة أو كودها الرقمي، وسيتم تحديث كافة المنتجات والباركودات التابعة لها تلقائياً:',
                    style: GoogleFonts.cairo(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم الشركة الجديد',
                      prefixIcon: Icon(Icons.apartment_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: codeCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                    decoration: const InputDecoration(
                      labelText: 'كود الشركة الرقمي (الفريد)',
                      hintText: '2450',
                      prefixIcon: Icon(Icons.pin_rounded),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isUpdating ? null : () => Navigator.pop(dialogCtx),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: isUpdating
                    ? null
                    : () async {
                        final newName = nameCtrl.text.trim();
                        final newCode = codeCtrl.text.trim().toLowerCase();

                        if (newName.isEmpty || newCode.isEmpty) {
                          ScaffoldMessenger.of(dialogCtx).showSnackBar(
                            const SnackBar(content: Text('يرجى ملء جميع الحقول')),
                          );
                          return;
                        }

                        if (newCode != company.slug) {
                          final duplicate = _findCompanyByCode(newCode);
                          if (duplicate != null) {
                            ScaffoldMessenger.of(dialogCtx).showSnackBar(
                              SnackBar(content: Text('الكود ($newCode) مسجل مسبقاً لشركة "${duplicate.name}"')),
                            );
                            return;
                          }
                        }

                        setDialogState(() => isUpdating = true);
                        final firestore = ref.read(firestoreProvider);
                        final messenger = ScaffoldMessenger.of(context);

                        try {
                          final batch = firestore.batch();

                          if (newCode != company.slug) {
                            if (mounted) {
                              setState(() {
                                if (_selectedProductCompanySlug == company.slug) {
                                  _selectedProductCompanySlug = newCode;
                                }
                                if (_selectedGlobalFilter == company.slug) {
                                  _selectedGlobalFilter = newCode;
                                }
                              });
                            }

                            final oldCompanyRef = firestore.collection('companies').doc(company.slug);
                            batch.delete(oldCompanyRef);

                            final newCompanyRef = firestore.collection('companies').doc(newCode);
                            batch.set(newCompanyRef, {
                              'name': newName,
                              'slug': newCode,
                              'productsCount': company.productsCount,
                              'createdAt': company.createdAt != null ? Timestamp.fromDate(company.createdAt!) : FieldValue.serverTimestamp(),
                              'updatedAt': FieldValue.serverTimestamp(),
                            });

                            final oldProducts = await firestore
                                .collection('company_products')
                                .where('companySlug', isEqualTo: company.slug)
                                .get();

                            for (final doc in oldProducts.docs) {
                              batch.update(doc.reference, {
                                'companySlug': newCode,
                                'companyName': newName,
                                'updatedAt': FieldValue.serverTimestamp(),
                              });
                            }
                          } else {
                            final companyRef = firestore.collection('companies').doc(company.slug);
                            batch.update(companyRef, {
                              'name': newName,
                              'updatedAt': FieldValue.serverTimestamp(),
                            });

                            final products = await firestore
                                .collection('company_products')
                                .where('companySlug', isEqualTo: company.slug)
                                .get();

                            for (final doc in products.docs) {
                              batch.update(doc.reference, {
                                'companyName': newName,
                                'updatedAt': FieldValue.serverTimestamp(),
                              });
                            }
                          }

                          await batch.commit();

                          if (mounted) {
                            setState(() {
                              if (_selectedProductCompanySlug == company.slug) {
                                _selectedProductCompanySlug = newCode;
                              }
                              if (_selectedGlobalFilter == company.slug) {
                                _selectedGlobalFilter = newCode;
                              }
                            });
                          }

                          if (dialogCtx.mounted) Navigator.pop(dialogCtx);

                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('تم تعديل بيانات شركة "$newName" بنجاح!'),
                                backgroundColor: Colors.green.shade800,
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isUpdating = false);
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء تعديل بيانات الشركة')),
                                backgroundColor: errorColor,
                              ),
                            );
                          }
                        }
                      },
                child: isUpdating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('حفظ التعديلات'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteCompanyFromFirebase(String slug, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف الشركة "$name"؟', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        content: Text(
          'هل أنت متأكد من حذف هذه الشركة وجميع المنتجات المرتبطة بها نهائياً من قاعدة البيانات؟',
          style: GoogleFonts.cairo(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final firestore = ref.read(firestoreProvider);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final batch = firestore.batch();
      batch.delete(firestore.collection('companies').doc(slug));

      final products =
          await firestore.collection('company_products').where('companySlug', isEqualTo: slug).get();
      for (final doc in products.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();

      if (_selectedProductCompanySlug == slug) {
        setState(() => _selectedProductCompanySlug = null);
      }
      if (_selectedGlobalFilter == slug) {
        setState(() => _selectedGlobalFilter = 'ALL');
      }

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('تم حذف شركة "$name" ومنتجاتها بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء حذف الشركة')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Wipes all products for a specific company from Firestore in batch
  Future<void> _deleteAllProductsForCompany(String slug, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.delete_sweep_rounded, color: Colors.red, size: 44),
        title: Text('مسح كافة منتجات "$name"؟', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 17)),
        content: Text(
          'هل أنت متأكد من حذف كافة المنتجات والأصناف المسجلة لشركة "$name" من قاعدة البيانات دفعة واحدة؟\n\nستتمكن بعد ذلك من إعادة رفع أو إدخال المنتجات والباركودات بشكل صحيح من ملف الإكسيل دون تكرار.\n(ملاحظة: لن يتم حذف الشركة نفسها، بل المنتجات فقط).',
          style: GoogleFonts.cairo(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('إلغاء', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.delete_sweep_rounded, size: 18),
            label: Text('نعم، مسح كافة المنتجات الآن', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    // Show loading spinner
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'جاري مسح كافة منتجات "$name" من الـ Firebase...',
                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final totalDeleted = await ref
          .read(companyProductsServiceProvider)
          .deleteAllProductsForCompany(companySlug: slug);

      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (mounted) {
        M3Feedback.showSuccess(
          context,
          title: 'تم مسح المنتجات بنجاح',
          message: 'تم حذف ($totalDeleted) صنف مسجل لشركة "$name" من قاعدة البيانات بنجاح. يمكنك الآن إعادة رفع أو تكويد الأصناف بدقة.',
          buttonText: 'حسناً',
        );
      }
    } catch (e) {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        M3Feedback.showToast(
          context,
          message: 'حدث خطأ أثناء مسح المنتجات: $e',
          isSuccess: false,
        );
      }
    }
  }

  Future<void> _seedDefaultSampleData() async {
    setState(() => _isSeeding = true);
    final service = ref.read(companyProductsServiceProvider);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await service.seedDefaultCompanyProducts();
      setState(() {
        _selectedProductCompanySlug = 'almarai';
        _selectedGlobalFilter = 'almarai';
      });
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('تم تحميل وتكويد نموذج منتجات المراعي بنجاح!')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'خطأ في تحميل النموذج التجريبي')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSeeding = false);
      }
    }
  }

  void _copySampleCsvTemplate() {
    const sample = "اسم المنتج,البار كود\nحليب كامل الدسم 1 لتر,6281007001001\nحليب قليل الدسم 1 لتر,6281007001002\nزبادي طبيعي 170 جم,6281007002001\nعصير برتقال 1 لتر,6281007003001";
    Clipboard.setData(const ClipboardData(text: sample));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ نموذج CSV التجريبي إلى الحافظة!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final firestore = ref.watch(firestoreProvider);
    final isAr = ref.isArabic;
    final strings = AppStrings.of(ref);

    return Container(
      color: colorScheme.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Page Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.qr_code_scanner_rounded, color: colorScheme.onPrimaryContainer, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.catalogTitle,
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        strings.catalogSubtitle,
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                M3MorphingActionButton(
                  onPressed: _seedDefaultSampleData,
                  icon: Icons.bolt_rounded,
                  label: _isSeeding ? strings.loading : (isAr ? 'تحميل نموذج المراعي' : 'Load Almarai Demo'),
                  isSelected: true,
                  customColor: colorScheme.primary,
                  tooltip: isAr ? 'توليد شركة ومنتجات المراعي كبيانات تجريبية' : 'Generate Almarai demo products & company',
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Stream builder to keep _existingCompanies synced
            StreamBuilder<QuerySnapshot>(
              stream: firestore.collection('companies').snapshots(),
              builder: (context, snapshot) {
                final companies = snapshot.data?.docs.map((d) => CompanyModel.fromFirestore(d)).toList() ?? [];
                _existingCompanies = companies;

                // Auto-select first company if none selected and companies exist
                if (_selectedProductCompanySlug == null && companies.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _selectedProductCompanySlug == null) {
                      setState(() {
                        _selectedProductCompanySlug = companies.first.slug;
                      });
                    }
                  });
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ==========================================
                    // 1. CARD 1: تسجيل وتكويد الشركات (Company Registration)
                    // ==========================================
                    _buildCompanyRegistrationCard(colorScheme),
                    const SizedBox(height: 20),

                    // ==========================================
                    // 2. CARD 2: إضافة وتكويد منتجات الشركات (Add & Manage Products)
                    // ==========================================
                    _buildCompanyProductsCard(colorScheme, companies),
                    const SizedBox(height: 20),

                    // ==========================================
                    // 3. CARD 3: دليل الشركات والمنتجات (Catalog Browser)
                    // ==========================================
                    _buildFirestoreCatalogBrowser(colorScheme, firestore, companies),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CARD 1: تسجيل شركة جديدة
  // ---------------------------------------------------------------------------
  Widget _buildCompanyRegistrationCard(ColorScheme colorScheme) {
    return Card(
      elevation: 1,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _regFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.add_business_rounded, color: colorScheme.onPrimaryContainer, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '١. تسجيل وتكويد شركة جديدة (Company Registration)',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'خطوة 1: تعريف الشركة',
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.primary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 700;
                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _regCompanyNameController,
                          focusNode: _regCompanyNameFocusNode,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) => _regCompanySlugFocusNode.requestFocus(),
                          decoration: const InputDecoration(
                            labelText: 'اسم الشركة (مثال: شركة جهينة)',
                            hintText: 'شركة جهينة',
                            prefixIcon: Icon(Icons.apartment_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _regCompanySlugController,
                          focusNode: _regCompanySlugFocusNode,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _isSavingCompany ? null : _saveCompanyOnlyToFirebase(),
                          inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                          decoration: const InputDecoration(
                            labelText: 'كود الشركة الرقمي الفريد (مثال: 2450)',
                            hintText: '2450',
                            prefixIcon: Icon(Icons.pin_rounded),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.tonalIcon(
                          onPressed: _isSavingCompany ? null : _saveCompanyOnlyToFirebase,
                          icon: _isSavingCompany
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.domain_add_rounded),
                          label: Text(_isSavingCompany ? 'جاري التسجيل...' : 'تسجيل الشركة'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _regCompanyNameController,
                          focusNode: _regCompanyNameFocusNode,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) => _regCompanySlugFocusNode.requestFocus(),
                          decoration: const InputDecoration(
                            labelText: 'اسم الشركة (مثال: شركة جهينة)',
                            hintText: 'شركة جهينة',
                            prefixIcon: Icon(Icons.apartment_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _regCompanySlugController,
                          focusNode: _regCompanySlugFocusNode,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _isSavingCompany ? null : _saveCompanyOnlyToFirebase(),
                          inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                          decoration: const InputDecoration(
                            labelText: 'كود الشركة الرقمي الفريد (مثال: 2450)',
                            hintText: '2450',
                            prefixIcon: Icon(Icons.pin_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Tooltip(
                        message: 'حفظ وتكويد الشركة في قاعدة البيانات مع إمكانية إضافة منتجاتها في أي وقت',
                        child: FilledButton.tonalIcon(
                          onPressed: _isSavingCompany ? null : _saveCompanyOnlyToFirebase,
                          icon: _isSavingCompany
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.domain_add_rounded),
                          label: Text(_isSavingCompany ? 'جاري التسجيل...' : 'تسجيل الشركة'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CARD 2: إضافة وتكويد منتجات الشركات (مع Dropdown + Search للشركة)
  // ---------------------------------------------------------------------------
  Widget _buildCompanyProductsCard(ColorScheme colorScheme, List<CompanyModel> companies) {
    final currentCompany = companies.where((c) => c.slug == _selectedProductCompanySlug).firstOrNull;

    // Filter companies by search query for selector
    final searchQuery = _companySearchController.text.trim().toLowerCase();
    final filteredCompanies = companies.where((c) {
      if (searchQuery.isEmpty) return true;
      return c.name.toLowerCase().contains(searchQuery) || c.slug.toLowerCase().contains(searchQuery);
    }).toList();

    return Card(
      elevation: 1,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.inventory_2_rounded, color: colorScheme.onPrimaryContainer, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '٢. إضافة وتكويد منتجات الشركة (Company Products)',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'اختر الشركة المسجلة ثم أضف منتجاتها وباركوداتها سواء يدوياً أو عبر ملف Excel/CSV',
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
            const SizedBox(height: 18),

            // Dropdown & Search for selecting company
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.apartment_rounded, color: colorScheme.primary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'تحديد الشركة المراد إضافة المنتجات إليها:',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 650;
                      final effectiveSlug = filteredCompanies.any((c) => c.slug == _selectedProductCompanySlug)
                          ? _selectedProductCompanySlug
                          : null;

                      if (isNarrow) {
                        return Column(
                          children: [
                            // Dropdown selector
                            DropdownButtonFormField<String>(
                              key: ValueKey('catalog_company_drop_narrow_${effectiveSlug}_${filteredCompanies.length}'),
                              initialValue: effectiveSlug,
                              decoration: InputDecoration(
                                labelText: 'قائمة الشركات المسجلة (${companies.length})',
                                prefixIcon: const Icon(Icons.arrow_drop_down_circle_outlined),
                                filled: true,
                                fillColor: colorScheme.surface,
                              ),
                              items: filteredCompanies.map((c) {
                                return DropdownMenuItem<String>(
                                  value: c.slug,
                                  child: Text(
                                    '🏢 ${c.name} (كود: ${c.slug}) - ${c.productsCount} منتج',
                                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedProductCompanySlug = val;
                                  if (val != null) _selectedGlobalFilter = val;
                                });
                              },
                              hint: Text('اختر الشركة من القائمة', style: GoogleFonts.cairo()),
                            ),
                            const SizedBox(height: 10),
                            // Quick search by code / name
                            TextField(
                              controller: _companySearchController,
                              decoration: InputDecoration(
                                labelText: 'بحث سريع بكود أو اسم الشركة...',
                                hintText: 'مثال: 2450 أو جهينة',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _companySearchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded),
                                        onPressed: () {
                                          _companySearchController.clear();
                                          setState(() {});
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: colorScheme.surface,
                              ),
                              onChanged: (val) {
                                final cleanVal = val.toEnglishDigits().trim().toLowerCase();
                                setState(() {
                                  final match = companies.where((c) =>
                                      c.slug.toLowerCase().trim() == cleanVal ||
                                      c.name.toLowerCase().contains(cleanVal)).firstOrNull;
                                  if (match != null) {
                                    _selectedProductCompanySlug = match.slug;
                                    _selectedGlobalFilter = match.slug;
                                  }
                                });
                              },
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('catalog_company_drop_wide_${effectiveSlug}_${filteredCompanies.length}'),
                              initialValue: effectiveSlug,
                              decoration: InputDecoration(
                                labelText: 'قائمة الشركات المسجلة (${companies.length} شركة)',
                                prefixIcon: const Icon(Icons.arrow_drop_down_circle_outlined),
                                filled: true,
                                fillColor: colorScheme.surface,
                              ),
                              items: filteredCompanies.map((c) {
                                return DropdownMenuItem<String>(
                                  value: c.slug,
                                  child: Text(
                                    '🏢 ${c.name} (كود: ${c.slug}) - ${c.productsCount} منتج',
                                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedProductCompanySlug = val;
                                  if (val != null) _selectedGlobalFilter = val;
                                });
                              },
                              hint: Text('اختر الشركة من القائمة المنسدلة', style: GoogleFonts.cairo()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _companySearchController,
                              decoration: InputDecoration(
                                labelText: 'بحث سريع بكود أو اسم الشركة...',
                                hintText: 'مثال: 2450 أو جهينة',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _companySearchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded),
                                        onPressed: () {
                                          _companySearchController.clear();
                                          setState(() {});
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: colorScheme.surface,
                              ),
                              onChanged: (val) {
                                final cleanVal = val.toEnglishDigits().trim().toLowerCase();
                                setState(() {
                                  final match = companies.where((c) =>
                                      c.slug.toLowerCase().trim() == cleanVal ||
                                      c.name.toLowerCase().contains(cleanVal)).firstOrNull;
                                  if (match != null) {
                                    _selectedProductCompanySlug = match.slug;
                                    _selectedGlobalFilter = match.slug;
                                  }
                                });
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  // Prominent Active Company Pill
                  if (currentCompany != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: colorScheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'الشركة المحددة لإضافة المنتجات: ',
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            '${currentCompany.name} (كود: ${currentCompany.slug})',
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: colorScheme.primary, fontSize: 13),
                          ),
                          const Spacer(),
                          Badge(
                            label: Text('${currentCompany.productsCount} منتج حالياً'),
                            backgroundColor: colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 10),
                    Text(
                      'يرجى اختيار شركة من القائمة أعلاه أو تسجيل شركة جديدة في الكارت الأول لبدء إضافة منتجاتها.',
                      style: GoogleFonts.cairo(fontSize: 12, color: Colors.orange.shade800),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Material Design 3 Connected Button Group (Mode Selector)
            Center(
              child: M3ConnectedButtonGroup<CatalogInputMode>(
                height: 48,
                borderRadius: 24,
                selectedValue: _activeMode,
                onSelected: (mode) => setState(() => _activeMode = mode),
                segments: [
                  const M3ButtonSegment(
                    value: CatalogInputMode.manual,
                    label: 'إدخال يدوي للمنتج',
                    icon: Icons.edit_note_rounded,
                    tooltip: 'تسجيل وتكويد صنف جديد يدوياً بكتابة الاسم والباركود',
                  ),
                  const M3ButtonSegment(
                    value: CatalogInputMode.excelCsv,
                    label: 'استيراد ملف Excel / CSV',
                    icon: Icons.file_upload_outlined,
                    tooltip: 'رفع ملف إكسيل أو لصق أسطر CSV ليقوم الذكاء الاصطناعي باستخراج المنتجات وتصنيفها آلياً',
                  ),
                  M3ButtonSegment(
                    value: CatalogInputMode.liveCatalog,
                    label: 'دليل منتجات الشركة المحفوظة',
                    icon: Icons.inventory_2_outlined,
                    tooltip: 'عرض الأصناف المسجلة والمحفوظة في قاعدة بيانات الشركة المحددة',
                    badgeText: currentCompany != null ? '${currentCompany.productsCount}' : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Dynamic Mode Workspace
            if (_activeMode == CatalogInputMode.manual) _buildManualEntryWorkspace(colorScheme, currentCompany),
            if (_activeMode == CatalogInputMode.excelCsv) _buildExcelImportWorkspace(colorScheme, currentCompany),
            if (_activeMode == CatalogInputMode.liveCatalog) _buildLiveCatalogSummary(colorScheme, currentCompany),

            // Staging Preview Card (if staged items exist)
            if (_stagedProducts.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildStagingPreviewCard(colorScheme, currentCompany),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildManualEntryWorkspace(ColorScheme colorScheme, CompanyModel? currentCompany) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 650;
              if (isNarrow) {
                return Column(
                  children: [
                    TextField(
                      controller: _manualProductNameController,
                      decoration: InputDecoration(
                        labelText: 'اسم وصنف المنتج (المسمى)',
                        hintText: currentCompany != null ? 'مثال: حليب ${currentCompany.name} 1 لتر' : 'اسم المنتج',
                        prefixIcon: const Icon(Icons.shopping_bag_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _manualBarcodeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                      decoration: const InputDecoration(
                        labelText: 'كود الباركود (Barcode / EAN)',
                        hintText: '6281007001001',
                        prefixIcon: Icon(Icons.qr_code_2_rounded),
                      ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _manualProductNameController,
                      decoration: InputDecoration(
                        labelText: 'اسم وصنف المنتج (المسمى)',
                        hintText: currentCompany != null ? 'مثال: حليب ${currentCompany.name} 1 لتر' : 'اسم المنتج',
                        prefixIcon: const Icon(Icons.shopping_bag_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _manualBarcodeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                      decoration: const InputDecoration(
                        labelText: 'كود الباركود (Barcode / EAN)',
                        hintText: '6281007001001',
                        prefixIcon: Icon(Icons.qr_code_2_rounded),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _addManualProductToStaging,
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: Text(
                currentCompany != null
                    ? 'إضافة إلى قائمة المعاينة لـ (${currentCompany.name})'
                    : 'إضافة إلى قائمة المعاينة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExcelImportWorkspace(ColorScheme colorScheme, CompanyModel? currentCompany) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI Banner Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primaryContainer.withValues(alpha: 0.6),
                  colorScheme.surfaceContainerLow,
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'المعالج الذكي لملفات Excel و CSV بالذكاء الاصطناعي',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ارفع أي شيت إكسيل للشركة مهما كان ترتيب أو أسماء الأعمدة؛ سيقوم Gemini AI باكتشاف أسماء الأصناف، الباركودات، المجموعات، والأحجام تلقائياً.',
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
          ),
          if (_isAiAnalyzing) ...[
            const SizedBox(height: 14),
            const M3ProgressCard(
              title: 'جاري قراءة وتحليل ملف المنتجات بواسطة الذكاء الاصطناعي (AI)',
              subtitle: 'يقوم النموذج الآن باستخراج الباركودات، الأسماء، الفئات، والأسعار تلقائياً...',
              icon: Icons.auto_awesome_rounded,
            ),
          ],
          const SizedBox(height: 16),

          // Action Buttons
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _isAiAnalyzing ? null : _pickAndParseExcelCsv,
                icon: const Icon(Icons.auto_awesome_rounded, size: 20),
                label: Text(
                  _isAiAnalyzing ? 'جاري التحليل بالـ AI...' : 'تحليل واستيراد ملف Excel / CSV بالـ AI',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _copySampleCsvTemplate,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(
                  'نسخ نموذج CSV تجريبي',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Text Field for manual CSV Paste
          TextField(
            controller: _csvPasteController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'أو الصق أسطر CSV هنا مباشرة للمعاينة السريعة',
              hintText: 'اسم الصنف, الباركود, المجموعة, الحجم\nحليب كامل الدسم 1 لتر, 6281007001001, ألبان, 1 لتر',
              prefixIcon: Icon(Icons.paste_rounded),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: () {
                _processCsvContentToStaging(_csvPasteController.text);
                _csvPasteController.clear();
              },
              icon: const Icon(Icons.playlist_add_check_rounded),
              label: const Text('تفريغ الأسطر وإضافتها للمعاينة'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveCatalogSummary(ColorScheme colorScheme, CompanyModel? currentCompany) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: colorScheme.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              currentCompany != null
                  ? 'أنت تستعرض الآن منتجات شركة (${currentCompany.name} - كود: ${currentCompany.slug}). يظهر أدناه كافة المنتجات المسجلة في السحابة.'
                  : 'يرجى اختيار شركة لاستعراض منتجاتها المسجلة.',
              style: GoogleFonts.cairo(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStagingPreviewCard(ColorScheme colorScheme, CompanyModel? currentCompany) {
    final companyName = currentCompany?.name ?? 'الشركة المحددة';
    final activeCountry = ref.watch(activeCountryProvider);

    return Card(
      elevation: 2,
      color: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar
            Row(
              children: [
                Badge(
                  label: Text('${_stagedProducts.length}'),
                  backgroundColor: colorScheme.primary,
                  child: Icon(Icons.pending_actions_rounded, color: colorScheme.primary, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'قائمة المنتجات الجاهزة للحفظ لـ ($companyName) - (${_stagedProducts.length} منتج)',
                    style: GoogleFonts.cairo(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _stagedProducts.clear();
                    _aiDetectionSummary = '';
                  }),
                  icon: const Icon(Icons.clear_all_rounded, color: Colors.red),
                  label: const Text('مسح القائمة', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),

            // AI Schema Badge
            if (_aiDetectionSummary.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: colorScheme.primary, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _aiDetectionSummary,
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Scrollable List of Staged Items
            Container(
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(14),
                color: colorScheme.surface,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _stagedProducts.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _stagedProducts[index];
                  final pName = item['productName']?.toString() ?? '';
                  final pBarcode = item['barcode']?.toString() ?? '';
                  final pCategory = item['category']?.toString() ?? '';
                  final pUnitSize = item['unitSize']?.toString() ?? '';
                  final pPrice = item['referencePrice'];

                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: colorScheme.primaryContainer,
                      child: Text(
                        '${index + 1}',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    title: Text(
                      pName,
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.qr_code_2_rounded, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                pBarcode.isNotEmpty ? pBarcode : 'بدون باركود',
                                style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        if (pCategory.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              'الفئة: $pCategory',
                              style: GoogleFonts.cairo(fontSize: 11, color: Colors.blue.shade800),
                            ),
                          ),
                        if (pUnitSize.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              'الحجم: $pUnitSize',
                              style: GoogleFonts.cairo(fontSize: 11, color: Colors.purple.shade800),
                            ),
                          ),
                        if (pPrice != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              'السعر: $pPrice ${activeCountry.currencySymbol}',
                              style: GoogleFonts.cairo(fontSize: 11, color: Colors.green.shade800),
                            ),
                          ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                      onPressed: () => setState(() => _stagedProducts.removeAt(index)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Save / Commit Action Area
            if (_isSavingProducts)
              M3ProgressCard(
                title: 'جاري حفظ واعتماد المنتجات في النظام',
                subtitle: 'يتم الآن تسجيل وترحيل المنتجات في قاعدة البيانات السحابية لـ ($companyName)...',
                progress: _saveProgressValue,
                currentCount: _savedItemsCount,
                totalCount: _totalItemsToSave > 0 ? _totalItemsToSave : _stagedProducts.length,
                icon: Icons.cloud_upload_rounded,
              )
            else
              Tooltip(
                message: 'ترحيل وحفظ الأصناف المجهزة أعلاه إلى قاعدة بيانات شركة ($companyName) في النظام',
                child: FilledButton.icon(
                  onPressed: _commitStagedProductsToFirebase,
                  icon: const Icon(Icons.cloud_upload_rounded),
                  label: Text(
                    'حفظ واعتماد ${_stagedProducts.length} منتج في النظام لـ ($companyName)',
                    style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: Colors.green.shade800,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CARD 3: دليل الشركات والمنتجات (Global Browser)
  // ---------------------------------------------------------------------------
  Widget _buildFirestoreCatalogBrowser(ColorScheme colorScheme, FirebaseFirestore firestore, List<CompanyModel> companies) {
    final isDirectoryMode = _selectedGlobalFilter == 'ALL';
    final selectedCompany = isDirectoryMode
        ? null
        : companies.where((c) => c.slug == _selectedGlobalFilter).firstOrNull;

    return Card(
      elevation: 1,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Title Header
            Row(
              children: [
                Icon(
                  isDirectoryMode ? Icons.business_center_rounded : Icons.inventory_2_rounded,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isDirectoryMode
                        ? '٣. دليل الشركات المسجلة'
                        : '٣. دليل منتجات شركة: ${selectedCompany?.name ?? _selectedGlobalFilter}',
                    style: GoogleFonts.cairo(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                if (!isDirectoryMode)
                  Tooltip(
                    message: 'الرجوع للقائمة الرئيسية لجميع الشركات',
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        setState(() {
                          _selectedGlobalFilter = 'ALL';
                          _catalogDisplayLimit = 20;
                          _globalSearchQueryController.clear();
                        });
                      },
                      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: Text(
                        'العودة لدليل الشركات',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Company Quick Switcher Tabs
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: M3ConnectedButtonGroup<String>(
                height: 42,
                borderRadius: 21,
                isExpanded: false,
                selectedValue: _selectedGlobalFilter,
                onSelected: (val) {
                  setState(() {
                    _selectedGlobalFilter = val;
                    _catalogDisplayLimit = 20;
                    _globalSearchQueryController.clear();
                    if (val != 'ALL') {
                      _selectedProductCompanySlug = val;
                    }
                  });
                },
                segments: [
                  const M3ButtonSegment(
                    value: 'ALL',
                    label: 'دليل كافة الشركات',
                    icon: Icons.apps_rounded,
                    tooltip: 'عرض بطاقات وإحصائيات جميع الشركات المسجلة في النظام',
                  ),
                  ...companies.map(
                    (c) => M3ButtonSegment(
                      value: c.slug,
                      label: '${c.name} (${c.productsCount})',
                      icon: Icons.apartment_rounded,
                      tooltip: 'استعراض والبحث في قائمة منتجات شركة ${c.name}',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Content Switch: Directory Mode vs. Company Products View
            if (isDirectoryMode)
              _buildCompaniesDirectoryView(colorScheme, firestore, companies)
            else if (selectedCompany != null)
              _buildCompanyProductsView(colorScheme, firestore, selectedCompany)
            else ...[
              // Fallback if company not found
              Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 40, color: colorScheme.error),
                    const SizedBox(height: 8),
                    Text(
                      'الشركة المحددة غير موجودة في قاعدة البيانات.',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(() => _selectedGlobalFilter = 'ALL'),
                      child: const Text('العودة لدليل الشركات'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MODE A: دليل الشركات المسجلة (Companies Directory Cards)
  // ---------------------------------------------------------------------------
  Widget _buildCompaniesDirectoryView(
    ColorScheme colorScheme,
    FirebaseFirestore firestore,
    List<CompanyModel> companies,
  ) {
    final query = _globalSearchQueryController.text.trim().toLowerCase();
    final filteredCompanies = companies.where((c) {
      if (query.isEmpty) return true;
      return c.name.toLowerCase().contains(query) || c.slug.toLowerCase().contains(query);
    }).toList();

    final totalProducts = companies.fold<int>(0, (acc, c) => acc + c.productsCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search & Stats Bar
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _globalSearchQueryController,
                decoration: InputDecoration(
                  labelText: 'بحث في أسماء الشركات أو الأكواد الرقمية...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _globalSearchQueryController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _globalSearchQueryController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Summary Info Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.domain_verification_rounded, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'الشركات المسجلة: ${companies.length} شركة',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              Text(
                'إجمالي الأصناف الموثقة: $totalProducts صنف',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        if (companies.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                Icon(Icons.apartment_rounded, size: 48, color: colorScheme.outline),
                const SizedBox(height: 10),
                Text(
                  'لم يتم تسجيل أي شركة حتى الآن.',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  'استخدم كارت "١. تسجيل وتكويد الشركات" بالأعلى لتسجيل أول شركة.',
                  style: GoogleFonts.cairo(fontSize: 13, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ] else if (filteredCompanies.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: Text(
              'لا توجد شركات مطابقة لبحثك.',
              style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ] else ...[
          // Grid / List of Company Cards
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 720;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: isWide ? 2 : 1,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 165,
                ),
                itemCount: filteredCompanies.length,
                itemBuilder: (context, index) {
                  final comp = filteredCompanies[index];
                  return Card(
                    elevation: 0,
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.55)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Top Row: Avatar, Name, Code & Count Badge
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.apartment_rounded,
                                  color: colorScheme.onPrimaryContainer,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      comp.name,
                                      style: GoogleFonts.cairo(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'كود: ${comp.slug}',
                                      style: GoogleFonts.cairo(
                                        fontSize: 11,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Products Count Badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: comp.productsCount > 0
                                      ? colorScheme.primary.withValues(alpha: 0.12)
                                      : colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: comp.productsCount > 0
                                        ? colorScheme.primary.withValues(alpha: 0.35)
                                        : colorScheme.outlineVariant,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.inventory_2_rounded,
                                      size: 14,
                                      color: comp.productsCount > 0
                                          ? colorScheme.primary
                                          : colorScheme.outline,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${comp.productsCount} صنف',
                                      style: GoogleFonts.cairo(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: comp.productsCount > 0
                                            ? colorScheme.primary
                                            : colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          // Bottom Action Row
                          Row(
                            children: [
                              // View Products Button
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: () {
                                    setState(() {
                                      _selectedGlobalFilter = comp.slug;
                                      _catalogDisplayLimit = 20;
                                      _globalSearchQueryController.clear();
                                    });
                                  },
                                  icon: const Icon(Icons.inventory_2_outlined, size: 16),
                                  label: Text(
                                    comp.productsCount > 0
                                        ? 'استعراض المنتجات (${comp.productsCount})'
                                        : 'استعراض (0 منتج)',
                                    style: GoogleFonts.cairo(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),

                              // Add Products Button
                              IconButton.filledTonal(
                                tooltip: 'إضافة منتجات لهذه الشركة',
                                icon: const Icon(Icons.add_box_rounded, size: 18),
                                onPressed: () {
                                  setState(() {
                                    _selectedProductCompanySlug = comp.slug;
                                    _activeMode = CatalogInputMode.manual;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('تم تفعيل شركة "${comp.name}" في كارت إضافة المنتجات بالأعلى.'),
                                      duration: const Duration(seconds: 3),
                                    ),
                                  );
                                },
                              ),

                              // Edit Company
                              IconButton.outlined(
                                tooltip: 'تعديل الاسم التجاري أو الكود الرقمي للشركة',
                                icon: const Icon(Icons.edit_note_rounded, size: 18),
                                onPressed: () => _showEditCompanyDialog(comp),
                              ),

                              // Clear all products for this company
                              if (comp.productsCount > 0)
                                IconButton.outlined(
                                  tooltip: 'مسح وحذف كافة الـ (${comp.productsCount}) منتج المسجلة لـ (${comp.name}) من قاعدة البيانات',
                                  icon: const Icon(Icons.delete_sweep_rounded, color: Colors.orange, size: 18),
                                  onPressed: () => _deleteAllProductsForCompany(comp.slug, comp.name),
                                ),

                              // Delete Company
                              IconButton.outlined(
                                tooltip: 'حذف هذه الشركة وجميع أصنافها الموثقة من النظام نهائياً',
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
                                onPressed: () => _deleteCompanyFromFirebase(comp.slug, comp.name),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // MODE B: استعراض منتجات الشركة المحددة (Paginated 20 Products View)
  // ---------------------------------------------------------------------------
  Widget _buildCompanyProductsView(
    ColorScheme colorScheme,
    FirebaseFirestore firestore,
    CompanyModel selectedCompany,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Company Information Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.business_rounded, color: colorScheme.onPrimaryContainer, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${selectedCompany.name} (كود: ${selectedCompany.slug})',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      'إجمالي الأصناف الموثقة: ${selectedCompany.productsCount} صنف',
                      style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'تعديل الاسم التجاري أو الكود الرقمي المعرف لـ (${selectedCompany.name})',
                child: FilledButton.tonalIcon(
                  onPressed: () => _showEditCompanyDialog(selectedCompany),
                  icon: const Icon(Icons.edit_note_rounded, size: 16),
                  label: const Text('تعديل'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: 'الانتقال المباشر لقسم إضافة وتكويد أصناف جديدة لـ (${selectedCompany.name})',
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    setState(() {
                      _selectedProductCompanySlug = selectedCompany.slug;
                      _activeMode = CatalogInputMode.manual;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تم تفعيل شركة "${selectedCompany.name}" في كارت إضافة المنتجات بالأعلى.'),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_box_rounded, size: 16),
                  label: const Text('إضافة منتجات'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: 'مسح وحذف كافة المنتجات والأصناف المسجلة لـ (${selectedCompany.name}) من الـ Firebase دفعة واحدة',
                child: FilledButton.tonalIcon(
                  onPressed: () => _deleteAllProductsForCompany(selectedCompany.slug, selectedCompany.name),
                  icon: const Icon(Icons.delete_sweep_rounded, size: 16, color: Colors.red),
                  label: Text('مسح كل المنتجات', style: GoogleFonts.cairo(color: Colors.red.shade700, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                tooltip: 'حذف شركة (${selectedCompany.name}) وجميع أصنافها الموثقة من النظام نهائياً',
                onPressed: () => _deleteCompanyFromFirebase(selectedCompany.slug, selectedCompany.name),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Product Search Field
        TextField(
          controller: _globalSearchQueryController,
          decoration: InputDecoration(
            labelText: 'بحث في منتجات ${selectedCompany.name} بالاسم أو الباركود...',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _globalSearchQueryController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () {
                      _globalSearchQueryController.clear();
                      setState(() {});
                    },
                  )
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),

        // Firestore Stream for this Company (Limited to _catalogDisplayLimit)
        StreamBuilder<QuerySnapshot>(
          stream: firestore
              .collection('company_products')
              .where('companySlug', isEqualTo: selectedCompany.slug)
              .limit(_catalogDisplayLimit)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (snapshot.hasError) {
              return Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                child: Text(
                  'حدث خطأ أثناء تحميل المنتجات: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                ),
              );
            }

            final rawDocs = snapshot.data?.docs ?? [];
            if (rawDocs.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(28),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 48, color: colorScheme.outline),
                    const SizedBox(height: 10),
                    Text(
                      'هذه الشركة مسجلة بنجاح ولكن بدون منتجات حتى الآن.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'يمكنك استخدام كارت "٢. إضافة وتكويد منتجات الشركات" بالأعلى لتسجيل منتجاتها.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedProductCompanySlug = selectedCompany.slug;
                          _activeMode = CatalogInputMode.manual;
                        });
                      },
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                      label: const Text('إضافة منتجات للشركة الآن'),
                    ),
                  ],
                ),
              );
            }

            final query = _globalSearchQueryController.text.trim().toLowerCase();
            final items = rawDocs
                .map((d) => CompanyProductModel.fromFirestore(d))
                .where((p) {
                  if (query.isEmpty) return true;
                  return p.productName.toLowerCase().contains(query) ||
                      p.barcode.toLowerCase().contains(query);
                })
                .toList();

            items.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

            if (items.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                child: Text(
                  'لا توجد نتائج مطابقة لبحثك في منتجات ${selectedCompany.name}.',
                  style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                ),
              );
            }

            final displayedItems = items;
            final totalCompanyItems = selectedCompany.productsCount > 0 ? selectedCompany.productsCount : rawDocs.length;
            final hasMore = rawDocs.length >= _catalogDisplayLimit && totalCompanyItems > displayedItems.length;
            final progressRatio = totalCompanyItems > 0 ? (displayedItems.length / totalCompanyItems).clamp(0.0, 1.0) : 1.0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Pagination & Progress Info Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.layers_outlined, size: 18, color: colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                'عرض ${displayedItems.length} من إجمالي $totalCompanyItems منتج',
                                style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              if (totalCompanyItems > 0) ...[
                                Tooltip(
                                  message: 'مسح وحذف كافة الـ $totalCompanyItems منتج المسجلة لهذه الشركة دفعة واحدة من قاعدة البيانات',
                                  child: OutlinedButton.icon(
                                    onPressed: () => _deleteAllProductsForCompany(selectedCompany.slug, selectedCompany.name),
                                    icon: const Icon(Icons.delete_sweep_rounded, size: 15, color: Colors.red),
                                    label: Text(
                                      'مسح كل الـ $totalCompanyItems منتج',
                                      style: GoogleFonts.cairo(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red.shade700,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      side: BorderSide(color: Colors.red.shade300),
                                      backgroundColor: Colors.red.shade50.withValues(alpha: 0.7),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ],
                              if (hasMore)
                                Text(
                                  'متبقي ${totalCompanyItems - displayedItems.length} منتج',
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              else
                                Text(
                                  'تم تحميل كافة المنتجات',
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      M3LinearProgress(
                        value: progressRatio,
                        height: 6,
                        color: hasMore ? colorScheme.primary : Colors.green.shade600,
                      ),
                    ],
                  ),
                ),

                // Paginated List of Products
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: displayedItems.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = displayedItems[index];
                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.qr_code_2_rounded, color: colorScheme.onPrimaryContainer, size: 22),
                        ),
                        title: Text(
                          item.productName,
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        subtitle: Row(
                          children: [
                            Text(
                              'الباركود: ${item.barcode}',
                              style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: item.barcode));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('تم نسخ الباركود (${item.barcode}) بنجاح'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Icon(Icons.copy_rounded, size: 14, color: colorScheme.primary),
                              ),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                          tooltip: 'حذف هذا الصنف وباركوده من النظام نهائياً',
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final batch = firestore.batch();
                            batch.delete(firestore.collection('company_products').doc(item.id));
                            if (item.companySlug.isNotEmpty) {
                              batch.update(firestore.collection('companies').doc(item.companySlug), {
                                'productsCount': FieldValue.increment(-1),
                              });
                            }
                            await batch.commit();
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(content: Text('تم حذف "${item.productName}" بنجاح')),
                              );
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),

                // Pagination Controls
                if (hasMore) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                          label: Text(
                            'تحميل 20 منتج إضافي (متبقي ${totalCompanyItems - displayedItems.length})',
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            setState(() {
                              _catalogDisplayLimit += 20;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.all_inclusive_rounded, size: 18),
                        label: Text(
                          'عرض الكل ($totalCompanyItems)',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          setState(() {
                            _catalogDisplayLimit = totalCompanyItems > 0 ? totalCompanyItems : 1000;
                          });
                        },
                      ),
                    ],
                  ),
                ] else if (displayedItems.length >= 20 || totalCompanyItems > 20) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      '✓ تم عرض كافة المنتجات المسجلة لشركة ${selectedCompany.name} ($totalCompanyItems منتج)',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}
