import 'dart:math' as math;
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
import '../../../core/localization/app_strings.dart';
import '../../../core/widgets/m3_button_groups.dart';
import '../../../core/widgets/m3_action_menu.dart';
import '../../../core/widgets/m3_progress_indicators.dart';
import '../../../core/services/ai_product_discovery_service.dart';
import '../../../core/services/partner_portal_auth_service.dart';
import 'widgets/ai_discovered_products_dialog.dart';
import 'widgets/portal_credentials_dialog.dart';
import '../domain/company_model.dart';
import '../../../core/utils/confirmed_write.dart';
import '../../../core/widgets/unconfirmed_write_snack.dart';

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
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

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
  String _companiesSortBy = 'PRODUCTS_DESC'; // 'PRODUCTS_DESC', 'PRODUCTS_ASC', 'NAME_ASC', 'SLUG_ASC'
  int _catalogDisplayLimit = 20;

  List<CompanyModel> _existingCompanies = [];

  CompanyModel? _findCompanyByCode(String code) {
    final clean = code.trim().toLowerCase();
    if (clean.isEmpty) return null;
    return _existingCompanies.where((c) => c.slug.toLowerCase().trim() == clean).firstOrNull;
  }

  // Memoized Firestore Streams (Rule 9: Never create streams inside build)
  Stream<QuerySnapshot>? _companiesStream;
  Stream<List<DiscoveredProductDocument>>? _discoveredProductsStream;
  String? _lastDiscoveredStreamSlug;
  Stream<QuerySnapshot>? _companyProductsStream;
  String? _lastCompanyProductsStreamKey;

  Stream<QuerySnapshot> _ensureCompaniesStream(FirebaseFirestore firestore) {
    _companiesStream ??= firestore.collection('companies').snapshots();
    return _companiesStream!;
  }

  Stream<List<DiscoveredProductDocument>> _ensureDiscoveredProductsStream(String slug) {
    if (_discoveredProductsStream == null || _lastDiscoveredStreamSlug != slug) {
      _lastDiscoveredStreamSlug = slug;
      _discoveredProductsStream = ref.read(aiProductDiscoveryServiceProvider).streamDiscoveredProducts(
        companySlug: slug,
        status: 'pending',
      );
    }
    return _discoveredProductsStream!;
  }

  Stream<QuerySnapshot> _ensureCompanyProductsStream(FirebaseFirestore firestore, String slug) {
    final key = '${slug}_$_catalogDisplayLimit';
    if (_companyProductsStream == null || _lastCompanyProductsStreamKey != key) {
      _lastCompanyProductsStreamKey = key;
      _companyProductsStream = firestore
          .collection('company_products')
          .where('companySlug', isEqualTo: slug)
          .limit(_catalogDisplayLimit)
          .snapshots();
    }
    return _companyProductsStream!;
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
              Icon(Icons.warning_amber_rounded, color: colorScheme.secondary, size: 28),
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
      // TAG-35 (N-01b): success only after the server confirmed the write.
      await confirmedWrite(companyRef.set({
        'name': companyName,
        'slug': companyCode,
        'productsCount': 0,
        'brandManagerUsername': PartnerPortalAuthService.defaultBrandUsername(companyCode),
        'brandManagerPassword': PartnerPortalAuthService.defaultBrandPassword(companyCode),
        'brandCredentialVersion': 1,
        'agencyOpsUsername': PartnerPortalAuthService.defaultAgencyUsername(companyCode),
        'agencyOpsPassword': PartnerPortalAuthService.defaultAgencyPassword(companyCode),
        'agencyCredentialVersion': 1,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)), companyRef.path);

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
            backgroundColor: colorScheme.onTertiaryFixedVariant,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } on WriteNotConfirmedException catch (e) {
      if (mounted) {
        showUnconfirmedWriteSnack(messenger, firestore, e, onConfirmed: () {
          if (!mounted) return;
          setState(() {
            _selectedProductCompanySlug = companyCode;
            _selectedGlobalFilter = companyCode;
          });
        });
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

  // --- DISCOVERED PRODUCTS FROM INVOICES SCAN & APPROVAL WORKFLOW ---
  Future<void> _scanAndReviewDiscoveredProductsForCompany(CompanyModel company) async {
    setState(() => _isAiAnalyzing = true);
    final strings = AppStrings.of(ref);

    try {
      final firestore = ref.read(firestoreProvider);
      final discoveryService = ref.read(aiProductDiscoveryServiceProvider);

      // Fetch all receipts transactions
      final txSnapshot = await firestore.collection('receipts_transactions').get();
      
      final relevantDocs = txSnapshot.docs.where((d) {
        final data = d.data();
        final cSlug = (data['companySlug'] ?? '').toString().trim().toLowerCase();
        return cSlug.isEmpty || cSlug == company.slug.toLowerCase();
      }).toList();

      final discovered = await discoveryService.discoverProductsFromTransactions(
        companySlug: company.slug,
        companyName: company.name,
        transactions: relevantDocs.isNotEmpty ? relevantDocs : txSnapshot.docs,
      );

      if (!mounted) return;
      setState(() => _isAiAnalyzing = false);

      if (discovered.isEmpty) {
        M3Feedback.showToast(
          context,
          message: strings.noNewProductsDiscovered,
          isSuccess: true,
        );
        return;
      }

      await AiDiscoveredProductsDialog.show(
        context: context,
        companySlug: company.slug,
        companyName: company.name,
        discoveredProducts: discovered,
        onSavedSuccessfully: () {
          if (mounted) setState(() {});
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isAiAnalyzing = false);
        M3Feedback.showToast(
          context,
          message: AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء فحص الأصناف الجديدة'),
          isSuccess: false,
        );
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
                Icon(Icons.edit_note_rounded, color: colorScheme.primary, size: 26),
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
                    style: GoogleFonts.cairo(fontSize: 13, color: colorScheme.onSurfaceVariant),
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
                                backgroundColor: colorScheme.onTertiaryFixedVariant,
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
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
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
        icon: Icon(Icons.delete_sweep_rounded, color: colorScheme.error, size: 44),
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
              backgroundColor: colorScheme.onErrorContainer,
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
                CircularProgressIndicator(color: colorScheme.error),
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

  /// Audits products catalog for a company and eliminates any duplicated records
  Future<void> _auditAndDeduplicateCompany(CompanyModel company) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Icon(Icons.cleaning_services_rounded, color: colorScheme.tertiary, size: 40),
        title: Text('تدقيق وفحص التكرار لشركة "${company.name}"', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
          'سيقوم النظام الآن بفحص وتدقيق كافة الأصناف والباركودات المسجلة لشركة "${company.name}"، والتأكد من عدم وجود أي أصناف مكررة، وحذف أي سجلات زائدة وتصحيح العداد بدقة.\n\nهل ترغب في بدء الفحص الآن؟',
          style: GoogleFonts.cairo(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('إلغاء', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.onTertiaryFixedVariant,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
            label: Text('بدء التدقيق ومنع التكرار', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final res = await ref.read(companyProductsServiceProvider).auditAndDeduplicateCompanyProducts(company.slug);
      if (mounted) {
        final total = res['total'] ?? 0;
        final unique = res['unique'] ?? 0;
        final dups = res['duplicatesRemoved'] ?? 0;

        await M3Feedback.showSuccess(
          context,
          title: 'اكتمل تدقيق الأصناف بنجاح',
          message: dups > 0
              ? 'تم فحص ($total) صنفاً، واكتشاف وإزالة ($dups) صنف مكرر بنجاح.\nإجمالي الأصناف الموثقة والفريدة حالياً: ($unique) صنف 🧹'
              : 'تم فحص ($total) صنفاً لشركة "${company.name}". الكتالوج سليم 100% وخالٍ تماماً من أي أصناف مكررة ($unique صنف موثق) ✅',
          buttonText: 'ممتاز',
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        M3Feedback.showToast(
          context,
          message: 'حدث خطأ أثناء تدقيق الأصناف: $e',
          isSuccess: false,
        );
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
              ],
            ),
            const SizedBox(height: 20),

            // Stream builder to keep _existingCompanies synced
            StreamBuilder<QuerySnapshot>(
              stream: _ensureCompaniesStream(firestore),
              builder: (context, snapshot) {
                final companies = snapshot.data?.docs.map((d) => CompanyModel.fromFirestore(d)).toList() ?? [];
                _existingCompanies = companies;


                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ==========================================
                    // 1. UNIFIED CARD: تسجيل الشركات وإضافة المنتجات
                    // ==========================================
                    _buildUnifiedCompanyAndProductsCard(colorScheme, companies),
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
  // SECTION: تسجيل شركة جديدة (مبسط بدون حشو أو أمثلة مكررة)
  // ---------------------------------------------------------------------------
  Widget _buildCompanyRegistrationSection(ColorScheme colorScheme) {
    return Form(
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
                child: Icon(Icons.domain_add_rounded, color: colorScheme.onPrimaryContainer, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                'تسجيل شركة',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
                        labelText: 'اسم الشركة',
                        hintText: 'اسم الشركة',
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
                        labelText: 'كود الشركة',
                        hintText: 'كود الشركة',
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
                          : const Icon(Icons.add_rounded),
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
                        labelText: 'اسم الشركة',
                        hintText: 'اسم الشركة',
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
                        labelText: 'كود الشركة',
                        hintText: 'كود الشركة',
                        prefixIcon: Icon(Icons.pin_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  FilledButton.tonalIcon(
                    onPressed: _isSavingCompany ? null : _saveCompanyOnlyToFirebase,
                    icon: _isSavingCompany
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_rounded),
                    label: Text(_isSavingCompany ? 'جاري التسجيل...' : 'تسجيل الشركة'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UNIFIED CARD: تسجيل الشركات وإضافة المنتجات (كارت موحد ومختزل بدون حشو)
  // ---------------------------------------------------------------------------
  Widget _buildUnifiedCompanyAndProductsCard(ColorScheme colorScheme, List<CompanyModel> companies) {
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
            // ==========================================
            // 1. تسجيل شركة
            // ==========================================
            _buildCompanyRegistrationSection(colorScheme),
            const SizedBox(height: 20),
            Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.5), height: 1),
            const SizedBox(height: 20),

            // ==========================================
            // 2. إضافة منتجات شركة
            // ==========================================
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
                Text(
                  'إضافة منتجات شركة',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

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
                        'تحديد الشركة',
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
                                prefixIcon: const Icon(Icons.arrow_drop_down_circle_outlined),
                                filled: true,
                                fillColor: colorScheme.surface,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              ),
                              items: filteredCompanies.map((c) {
                                return DropdownMenuItem<String>(
                                  value: c.slug,
                                  child: Text(
                                    '🏢 ${c.name} (${c.slug}) - ${c.productsCount} منتج',
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
                              hint: Text(
                                'اختر الشركة',
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Quick search by code / name
                            TextField(
                              controller: _companySearchController,
                              decoration: InputDecoration(
                                hintText: 'بحث بالكود أو الاسم...',
                                hintStyle: GoogleFonts.cairo(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                ),
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
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                                prefixIcon: const Icon(Icons.arrow_drop_down_circle_outlined),
                                filled: true,
                                fillColor: colorScheme.surface,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              ),
                              items: filteredCompanies.map((c) {
                                return DropdownMenuItem<String>(
                                  value: c.slug,
                                  child: Text(
                                    '🏢 ${c.name} (${c.slug}) - ${c.productsCount} منتج',
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
                              hint: Text(
                                'اختر الشركة',
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _companySearchController,
                              decoration: InputDecoration(
                                hintText: 'بحث بالكود أو الاسم...',
                                hintStyle: GoogleFonts.cairo(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                ),
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
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                    label: 'إدخال يدوي',
                    icon: Icons.edit_note_rounded,
                    tooltip: 'تسجيل وتكويد صنف جديد يدوياً بكتابة الاسم والباركود',
                  ),
                  const M3ButtonSegment(
                    value: CatalogInputMode.excelCsv,
                    label: 'استيراد Excel / CSV',
                    icon: Icons.file_upload_outlined,
                    tooltip: 'استيراد الأصناف عبر ملف أو نسخ ولصق بيانات CSV',
                  ),
                  M3ButtonSegment(
                    value: CatalogInputMode.liveCatalog,
                    label: 'دليل المنتجات',
                    icon: Icons.inventory_2_outlined,
                    tooltip: 'عرض الأصناف المسجلة في قاعدة بيانات الشركة',
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
                      decoration: const InputDecoration(
                        labelText: 'اسم المنتج',
                        hintText: 'اسم المنتج',
                        prefixIcon: Icon(Icons.shopping_bag_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _manualBarcodeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                      decoration: const InputDecoration(
                        labelText: 'الباركود',
                        hintText: 'الباركود',
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
                      decoration: const InputDecoration(
                        labelText: 'اسم المنتج',
                        hintText: 'اسم المنتج',
                        prefixIcon: Icon(Icons.shopping_bag_outlined),
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
                        labelText: 'الباركود',
                        hintText: 'الباركود',
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
                'إضافة لقائمة المعاينة',
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
                  icon: Icon(Icons.clear_all_rounded, color: colorScheme.error),
                  label: Text('مسح القائمة', style: TextStyle(color: colorScheme.error)),
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
                              color: colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              'الفئة: $pCategory',
                              style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onPrimaryFixedVariant),
                            ),
                          ),
                        if (pUnitSize.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              'الحجم: $pUnitSize',
                              style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onPrimaryFixedVariant),
                            ),
                          ),
                        if (pPrice != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.tertiary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              'السعر: $pPrice ${activeCountry.currencySymbol}',
                              style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onTertiaryFixedVariant),
                            ),
                          ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline_rounded, color: colorScheme.error, size: 20),
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
                    backgroundColor: colorScheme.onTertiaryFixedVariant,
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
  // MODE A: دليل الشركات المسجلة (Companies Enterprise Directory Table)
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

    // Sorting according to selected criteria
    final sortedCompanies = List<CompanyModel>.from(filteredCompanies);
    switch (_companiesSortBy) {
      case 'PRODUCTS_DESC':
        sortedCompanies.sort((a, b) => b.productsCount.compareTo(a.productsCount));
        break;
      case 'PRODUCTS_ASC':
        sortedCompanies.sort((a, b) => a.productsCount.compareTo(b.productsCount));
        break;
      case 'NAME_ASC':
        sortedCompanies.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'SLUG_ASC':
        sortedCompanies.sort((a, b) => a.slug.compareTo(b.slug));
        break;
    }

    final totalProducts = companies.fold<int>(0, (acc, c) => acc + c.productsCount);
    final emptyCompanies = companies.where((c) => c.productsCount == 0).length;
    final maxProducts = companies.fold<int>(0, (max, c) => c.productsCount > max ? c.productsCount : max);
    final averageProducts = companies.isNotEmpty ? (totalProducts / companies.length).round() : 0;

    Widget buildSearchField() {
      return SizedBox(
        height: 42,
        child: TextField(
          controller: _globalSearchQueryController,
          style: GoogleFonts.cairo(fontSize: 12.5),
          decoration: InputDecoration(
            hintText: 'بحث في أسماء الشركات أو الأكواد الرقمية...',
            hintStyle: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
            prefixIcon: Icon(Icons.search_rounded, size: 20, color: colorScheme.primary),
            suffixIcon: _globalSearchQueryController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 16),
                    onPressed: () {
                      _globalSearchQueryController.clear();
                      setState(() {});
                    },
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8), width: 1.0),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8), width: 1.0),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      );
    }

    Widget buildSortGroup() {
      return M3ConnectedButtonGroup<String>(
        height: 42,
        borderRadius: 12,
        isExpanded: false,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        segments: const [
          M3ButtonSegment<String>(
            value: 'PRODUCTS_DESC',
            label: 'الأعلى أصنافاً',
            icon: Icons.trending_up_rounded,
            tooltip: 'ترتيب تنازلي حسب عدد الأصناف الموثقة',
          ),
          M3ButtonSegment<String>(
            value: 'PRODUCTS_ASC',
            label: 'الأقل أصنافاً',
            icon: Icons.trending_down_rounded,
            tooltip: 'ترتيب تصاعدي حسب عدد الأصناف الموثقة',
          ),
          M3ButtonSegment<String>(
            value: 'NAME_ASC',
            label: 'أبجدياً',
            icon: Icons.sort_by_alpha_rounded,
            tooltip: 'ترتيب أبجدي حسب اسم الشركة',
          ),
          M3ButtonSegment<String>(
            value: 'SLUG_ASC',
            label: 'الكود',
            icon: Icons.tag_rounded,
            tooltip: 'ترتيب حسب الكود التعريفي للشركة',
          ),
        ],
        selectedValue: _companiesSortBy,
        onSelected: (val) => setState(() => _companiesSortBy = val),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Search & Sort Controls Bar
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 820) {
              return Row(
                children: [
                  Expanded(child: buildSearchField()),
                  const SizedBox(width: 10),
                  buildSortGroup(),
                ],
              );
            } else {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buildSearchField(),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: buildSortGroup(),
                  ),
                ],
              );
            }
          },
        ),
        const SizedBox(height: 12),

        // 2. Summary Info & KPI Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Metric 1: Registered Companies
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.domain_verification_rounded, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'الشركات المسجلة: ${companies.length} شركة',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              // Metric 2: Documented Items
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2_rounded, size: 17, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'إجمالي الأصناف: $totalProducts صنف',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              // Metric 3: Average per company
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.analytics_rounded, size: 17, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    'متوسط التوثيق: $averageProducts صنف/شركة',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              // Metric 4: Companies Needing Items
              if (emptyCompanies > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.primaryFixedDim),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 14, color: colorScheme.onSecondaryFixedVariant),
                      const SizedBox(width: 4),
                      Text(
                        '$emptyCompanies شركة بدون أصناف',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 16, color: colorScheme.onTertiaryFixedVariant),
                    const SizedBox(width: 4),
                    Text(
                      'كافة الشركات موثقة بأصناف',
                      style: GoogleFonts.cairo(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onTertiaryFixedVariant,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. Main Content: Empty State vs Enterprise Data Table
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
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                Icon(Icons.search_off_rounded, size: 40, color: colorScheme.onSurfaceVariant),
                const SizedBox(height: 8),
                Text(
                  'لا توجد شركات مطابقة لبحثك ("${_globalSearchQueryController.text.trim()}").',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () {
                    _globalSearchQueryController.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.clear_all_rounded, size: 16),
                  label: const Text('إلغاء الفلترة وعرض كافة الشركات'),
                ),
              ],
            ),
          ),
        ] else ...[
          // 4. Enterprise Companies Table
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: LayoutBuilder(
                builder: (context, tableConstraints) {
                  final minTableWidth = math.max(tableConstraints.maxWidth, 920.0);
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: SizedBox(
                      width: minTableWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Table Header
                          _buildDirectoryTableHeader(colorScheme),

                          // Table Body Rows
                          ...sortedCompanies.asMap().entries.map((entry) {
                            final index = entry.key;
                            final comp = entry.value;
                            return _buildDirectoryTableRow(
                              context: context,
                              index: index,
                              comp: comp,
                              totalProducts: totalProducts,
                              maxProducts: maxProducts,
                              colorScheme: colorScheme,
                            );
                          }),

                          // Table Footer
                          _buildDirectoryTableFooter(
                            colorScheme: colorScheme,
                            displayedCount: sortedCompanies.length,
                            totalCount: companies.length,
                            displayedProducts: sortedCompanies.fold<int>(0, (acc, c) => acc + c.productsCount),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDirectoryTableHeader(ColorScheme colorScheme) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.7),
            width: 1.2,
          ),
        ),
      ),
      child: Row(
        children: [
          // Col 1: #
          SizedBox(
            width: 52,
            child: Text(
              '#',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          // Col 2: Company Name
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(Icons.business_rounded, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'الشركة المسجلة والرمز',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),

          // Col 3: Slug / Code
          SizedBox(
            width: 130,
            child: Row(
              children: [
                Icon(Icons.tag_rounded, size: 15, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'الكود (Slug)',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),

          // Col 4: Documented Items
          SizedBox(
            width: 200,
            child: Row(
              children: [
                Icon(Icons.inventory_2_rounded, size: 15, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'الأصناف الموثقة',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),

          // Col 5: Catalog Status
          SizedBox(
            width: 135,
            child: Row(
              children: [
                Icon(Icons.fact_check_rounded, size: 15, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'حالة التوثيق',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),

          // Col 6: Actions
          SizedBox(
            width: 250,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.tune_rounded, size: 15, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'الإجراءات والعمليات',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectoryTableRow({
    required BuildContext context,
    required int index,
    required CompanyModel comp,
    required int totalProducts,
    required int maxProducts,
    required ColorScheme colorScheme,
  }) {
    final isEven = index.isEven;
    final rowBackground = isEven
        ? colorScheme.surface
        : colorScheme.surfaceContainerLowest.withValues(alpha: 0.65);

    return Material(
      color: rowBackground,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedGlobalFilter = comp.slug;
            _catalogDisplayLimit = 20;
            _globalSearchQueryController.clear();
          });
        },
        hoverColor: colorScheme.primary.withValues(alpha: 0.04),
        splashColor: colorScheme.primary.withValues(alpha: 0.08),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                width: 1.0,
              ),
            ),
          ),
          child: Row(
            children: [
              // Col 1: #
              SizedBox(
                width: 52,
                child: Center(
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${index + 1}',
                      style: GoogleFonts.cairo(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),

              // Col 2: Company Name & Brand
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: comp.productsCount > 0
                            ? colorScheme.primaryContainer.withValues(alpha: 0.8)
                            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: comp.productsCount > 0
                              ? colorScheme.primary.withValues(alpha: 0.3)
                              : colorScheme.outlineVariant.withValues(alpha: 0.4),
                          width: 1.0,
                        ),
                      ),
                      child: Icon(
                        Icons.apartment_rounded,
                        size: 20,
                        color: comp.productsCount > 0
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.outline,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            comp.name,
                            style: GoogleFonts.cairo(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (comp.createdAt != null)
                            Text(
                              'مسجلة: ${comp.createdAt!.year}/${comp.createdAt!.month.toString().padLeft(2, '0')}/${comp.createdAt!.day.toString().padLeft(2, '0')}',
                              style: GoogleFonts.cairo(
                                fontSize: 10.5,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Col 3: Slug / Code
              SizedBox(
                width: 130,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.7),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tag_rounded, size: 12, color: colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          comp.slug,
                          style: GoogleFonts.cairo(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Col 4: Documented Items
              SizedBox(
                width: 200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inventory_2_rounded,
                          size: 13,
                          color: comp.productsCount > 0 ? colorScheme.primary : colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${comp.productsCount} صنف',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: comp.productsCount > 0
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (totalProducts > 0 && comp.productsCount > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            '(${(comp.productsCount / totalProducts * 100).toStringAsFixed(1)}%)',
                            style: GoogleFonts.cairo(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        width: 140,
                        height: 5,
                        child: LinearProgressIndicator(
                          value: maxProducts > 0 ? (comp.productsCount / maxProducts) : 0.0,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            comp.productsCount > 0
                                ? colorScheme.primary
                                : colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Col 5: Catalog Status
              SizedBox(
                width: 135,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: comp.productsCount > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colorScheme.tertiaryFixedDim, width: 1.0),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_rounded, size: 12, color: colorScheme.onTertiaryFixedVariant),
                              const SizedBox(width: 4),
                              Text(
                                'موثقة ومكتملة',
                                style: GoogleFonts.cairo(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onTertiaryFixedVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colorScheme.primaryFixedDim, width: 1.0),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 12, color: colorScheme.onSecondaryFixedVariant),
                              const SizedBox(width: 4),
                              Text(
                                'بحاجة لأصناف',
                                style: GoogleFonts.cairo(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),

              // Col 6: Actions
              SizedBox(
                width: 250,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Primary Browse Button
                    FilledButton.tonalIcon(
                      onPressed: () {
                        setState(() {
                          _selectedGlobalFilter = comp.slug;
                          _catalogDisplayLimit = 20;
                          _globalSearchQueryController.clear();
                        });
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.65),
                        foregroundColor: colorScheme.primary,
                        minimumSize: const Size(0, 32),
                        fixedSize: const Size.fromHeight(32),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.inventory_2_outlined, size: 14),
                      label: Text(
                        comp.productsCount > 0 ? 'استعراض (${comp.productsCount})' : 'استعراض (0)',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),

                    // Quick Add Product Button
                    IconButton.filledTonal(
                      tooltip: 'إضافة منتجات لـ (${comp.name})',
                      icon: const Icon(Icons.add_rounded, size: 16),
                      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(32, 32),
                        fixedSize: const Size(32, 32),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
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
                    const SizedBox(width: 4),

                    // Quick Edit Company Button
                    IconButton.outlined(
                      tooltip: 'إدارة بيانات دخول البوابات وكارت الواتساب (${comp.name})',
                      icon: Icon(Icons.vpn_key_rounded, size: 16, color: colorScheme.primary),
                      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(32, 32),
                        fixedSize: const Size(32, 32),
                        padding: EdgeInsets.zero,
                        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.4)),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => PortalCredentialsDialog.show(
                        context,
                        companySlug: comp.slug,
                        companyName: comp.name,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton.outlined(
                      tooltip: 'تعديل اسم أو كود (${comp.name})',
                      icon: const Icon(Icons.edit_note_rounded, size: 16),
                      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(32, 32),
                        fixedSize: const Size(32, 32),
                        padding: EdgeInsets.zero,
                        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _showEditCompanyDialog(comp),
                    ),
                    const SizedBox(width: 4),

                    // M3 Action Menu for secondary & dangerous operations
                    M3ActionMenu(
                      tooltip: 'خيارات إضافية لـ (${comp.name})',
                      anchorIcon: Icon(Icons.more_vert_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                      children: [
                        M3ActionMenu.header(context: context, title: comp.name),
                        M3ActionMenu.item(
                          context: context,
                          label: 'بيانات دخول البوابات وكارت الواتساب',
                          icon: Icons.vpn_key_rounded,
                          onPressed: () => PortalCredentialsDialog.show(
                            context,
                            companySlug: comp.slug,
                            companyName: comp.name,
                          ),
                        ),
                        M3ActionMenu.item(
                          context: context,
                          label: 'فحص واكتشاف الأصناف بالذكاء الاصطناعي',
                          icon: Icons.auto_awesome_rounded,
                          onPressed: () => _scanAndReviewDiscoveredProductsForCompany(comp),
                        ),
                        M3ActionMenu.item(
                          context: context,
                          label: 'تدقيق ومنع التكرار',
                          icon: Icons.cleaning_services_rounded,
                          onPressed: () => _auditAndDeduplicateCompany(comp),
                        ),
                        M3ActionMenu.divider(),
                        if (comp.productsCount > 0)
                          M3ActionMenu.item(
                            context: context,
                            label: 'مسح وحذف كل منتجات الشركة',
                            icon: Icons.delete_sweep_rounded,
                            isDestructive: true,
                            onPressed: () => _deleteAllProductsForCompany(comp.slug, comp.name),
                          ),
                        M3ActionMenu.item(
                          context: context,
                          label: 'حذف الشركة نهائياً من النظام',
                          icon: Icons.delete_forever_rounded,
                          isDestructive: true,
                          onPressed: () => _deleteCompanyFromFirebase(comp.slug, comp.name),
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
    );
  }

  Widget _buildDirectoryTableFooter({
    required ColorScheme colorScheme,
    required int displayedCount,
    required int totalCount,
    required int displayedProducts,
  }) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            'عرض $displayedCount من أصل $totalCount شركة مسجلة • إجمالي الأصناف المعروضة: $displayedProducts صنف',
            style: GoogleFonts.cairo(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          if (_globalSearchQueryController.text.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                _globalSearchQueryController.clear();
                setState(() {});
              },
              icon: const Icon(Icons.clear_all_rounded, size: 14),
              label: Text(
                'إلغاء الفلترة',
                style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DISCOVERED PRODUCTS FROM INVOICES BANNER
  // ---------------------------------------------------------------------------
  Widget _buildDiscoveredProductsPendingBanner(
    ColorScheme colorScheme,
    FirebaseFirestore firestore,
    CompanyModel selectedCompany,
    AppStrings strings,
  ) {
    return StreamBuilder<List<DiscoveredProductDocument>>(
      stream: _ensureDiscoveredProductsStream(selectedCompany.slug),
      builder: (context, snapshot) {
        final pendingDocs = snapshot.data ?? [];
        if (pendingDocs.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.secondaryContainer,
                colorScheme.secondaryContainer,
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.primaryFixedDim),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.auto_awesome_rounded, color: colorScheme.onSecondaryContainer, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${strings.discoveredProductsPendingApproval} (${pendingDocs.length} صنف جديد)',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                    Text(
                      strings.discoveredProductsPendingSubtitle,
                      style: GoogleFonts.cairo(
                        fontSize: 11.5,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _isAiAnalyzing
                    ? null
                    : () => _scanAndReviewDiscoveredProductsForCompany(selectedCompany),
                icon: _isAiAnalyzing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.rate_review_rounded, size: 16),
                label: Text(
                  _isAiAnalyzing ? 'جاري الفحص...' : strings.reviewDiscoveredProductsBtn,
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.onSecondaryContainer,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompanyActionsM3ButtonGroup(
    ColorScheme colorScheme,
    CompanyModel selectedCompany,
    AppStrings strings,
  ) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.8),
          width: 1.0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. AI Product Discovery
              _buildM3GroupActionItem(
                colorScheme: colorScheme,
                icon: _isAiAnalyzing ? null : Icons.auto_awesome_rounded,
                customIcon: _isAiAnalyzing
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                      )
                    : null,
                label: _isAiAnalyzing ? 'جاري الفحص...' : 'فحص واكتشاف الأصناف',
                tooltip: 'فحص فواتير المشتريات تلقائياً لاكتشاف أي أصناف جديدة لم تسجل بعد لـ (${selectedCompany.name}) ومراجعتها واعتمادها',
                iconColor: colorScheme.onSecondaryFixedVariant,
                onPressed: _isAiAnalyzing ? null : () => _scanAndReviewDiscoveredProductsForCompany(selectedCompany),
              ),
              _buildM3GroupDivider(colorScheme),

              // 2. Edit Company
              _buildM3GroupActionItem(
                colorScheme: colorScheme,
                icon: Icons.edit_note_rounded,
                label: 'تعديل',
                tooltip: 'تعديل الاسم التجاري أو الكود الرقمي المعرف لـ (${selectedCompany.name})',
                iconColor: colorScheme.primary,
                onPressed: () => _showEditCompanyDialog(selectedCompany),
              ),
              _buildM3GroupDivider(colorScheme),

              // 3. Add Products
              _buildM3GroupActionItem(
                colorScheme: colorScheme,
                icon: Icons.add_box_rounded,
                label: 'إضافة منتجات',
                tooltip: 'الانتقال المباشر لقسم إضافة وتكويد أصناف جديدة لـ (${selectedCompany.name})',
                iconColor: colorScheme.primary,
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
              ),
              _buildM3GroupDivider(colorScheme),

              // 4. Audit & Deduplicate
              _buildM3GroupActionItem(
                colorScheme: colorScheme,
                icon: Icons.cleaning_services_rounded,
                label: 'تدقيق ومنع التكرار',
                tooltip: 'تدقيق وفحص كافة أصناف (${selectedCompany.name}) المسجلة وحذف أي أصناف مكررة فوراً وتصحيح العداد',
                iconColor: colorScheme.onTertiaryFixedVariant,
                textColor: colorScheme.onTertiaryContainer,
                onPressed: () => _auditAndDeduplicateCompany(selectedCompany),
              ),
              _buildM3GroupDivider(colorScheme),

              // 5. Delete All Products (Destructive)
              _buildM3GroupActionItem(
                colorScheme: colorScheme,
                icon: Icons.delete_sweep_rounded,
                label: 'مسح كل المنتجات',
                tooltip: 'مسح وحذف كافة المنتجات والأصناف المسجلة لـ (${selectedCompany.name}) من الـ Firebase دفعة واحدة',
                iconColor: colorScheme.onErrorContainer,
                textColor: colorScheme.onErrorContainer,
                hoverColor: colorScheme.errorContainer,
                onPressed: () => _deleteAllProductsForCompany(selectedCompany.slug, selectedCompany.name),
              ),
              _buildM3GroupDivider(colorScheme),

              // 6. Delete Entire Company (Icon Action)
              _buildM3GroupActionItem(
                colorScheme: colorScheme,
                icon: Icons.delete_outline_rounded,
                tooltip: 'حذف شركة (${selectedCompany.name}) وجميع أصنافها الموثقة من النظام نهائياً',
                iconColor: colorScheme.onErrorContainer,
                hoverColor: colorScheme.errorContainer,
                onPressed: () => _deleteCompanyFromFirebase(selectedCompany.slug, selectedCompany.name),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildM3GroupActionItem({
    required ColorScheme colorScheme,
    IconData? icon,
    Widget? customIcon,
    String? label,
    required String tooltip,
    Color? iconColor,
    Color? textColor,
    Color? hoverColor,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          hoverColor: hoverColor ?? colorScheme.primary.withValues(alpha: 0.08),
          splashColor: colorScheme.primary.withValues(alpha: 0.12),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: label != null ? 10 : 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (customIcon != null)
                  customIcon
                else if (icon != null)
                  Icon(icon, size: 16, color: iconColor ?? colorScheme.onSurfaceVariant),
                if (label != null) ...[
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textColor ?? colorScheme.onSurface,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildM3GroupDivider(ColorScheme colorScheme) {
    return VerticalDivider(
      width: 1,
      thickness: 1,
      color: colorScheme.outlineVariant.withValues(alpha: 0.7),
      indent: 4,
      endIndent: 4,
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
    final strings = AppStrings.of(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Company Information & M3 Action Button Group Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 850;
              final companyInfo = Row(
                mainAxisSize: MainAxisSize.min,
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
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
                ],
              );

              final actionGroup = _buildCompanyActionsM3ButtonGroup(colorScheme, selectedCompany, strings);

              if (isWide) {
                return Row(
                  children: [
                    Expanded(child: companyInfo),
                    const SizedBox(width: 12),
                    actionGroup,
                  ],
                );
              } else {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    companyInfo,
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: actionGroup,
                    ),
                  ],
                );
              }
            },
          ),
        ),
        const SizedBox(height: 14),

        // Live Discovered Products Banner
        _buildDiscoveredProductsPendingBanner(colorScheme, firestore, selectedCompany, strings),

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
          stream: _ensureCompanyProductsStream(firestore, selectedCompany.slug),
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
                  style: TextStyle(color: colorScheme.error),
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
                                    icon: Icon(Icons.delete_sweep_rounded, size: 15, color: colorScheme.error),
                                    label: Text(
                                      'مسح كل الـ $totalCompanyItems منتج',
                                      style: GoogleFonts.cairo(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onErrorContainer,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      side: BorderSide(color: colorScheme.errorContainer),
                                      backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.7),
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
                                    color: colorScheme.onTertiaryFixedVariant,
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
                        color: hasMore ? colorScheme.primary : colorScheme.tertiary,
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
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
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
                                if (item.chainAliases.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => _showChainAliasesDialog(context, item),
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: colorScheme.tertiaryContainer,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.3)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.storefront_rounded, size: 12, color: colorScheme.onTertiaryContainer),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${item.chainAliases.length} سلاسل مرصودة',
                                            style: GoogleFonts.cairo(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: colorScheme.onTertiaryContainer,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline_rounded, color: colorScheme.error, size: 20),
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

  void _showChainAliasesDialog(BuildContext context, CompanyProductModel item) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.storefront_rounded, color: colorScheme.onPrimaryContainer, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مسميات الصنف في السلاسل التجارية',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      item.productName,
                      style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.qr_code_2_rounded, size: 20, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'الباركود الذهبي الموحد: ',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        SelectableText(
                          item.barcode,
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.primary),
                        ),
                      ],
                    ),
                  ),
                  if (item.chainAliases.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'لم يتم رصد مسميات مختلفة لهذا الصنف في السلاسل الأخرى بعد.',
                        style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                      ),
                    )
                  else
                    ...item.chainAliases.entries.map((entry) {
                      final chain = entry.key;
                      final aliases = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.store_mall_directory_rounded, size: 16, color: colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  chain,
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.primary),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${aliases.length} مسمى في الكاشير',
                                    style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.onSecondaryContainer),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ...aliases.map((a) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('• ', style: TextStyle(color: colorScheme.outline)),
                                      Expanded(
                                        child: SelectableText(
                                          a,
                                          style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurface),
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }
}
