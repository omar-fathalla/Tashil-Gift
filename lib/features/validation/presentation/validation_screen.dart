import 'package:al_mraay/core/services/rep_device_id.dart';
import 'package:al_mraay/core/constants/app_version_config.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/utils/receipt_branch_resolver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/accepted_receipt_core.dart';
import '../../../core/services/ai_receipt_service.dart';
import '../../../core/services/ai_product_discovery_service.dart';
import '../../../core/services/company_products_service.dart';
import '../../../core/services/company_gifts_service.dart';
import '../../../core/services/retail_chains_service.dart';
import '../../../core/services/receipt_deduplication_helper.dart';
import '../../../core/utils/error_handler.dart';
import '../../games/presentation/spin_the_wheel_screen.dart';
import '../../games/presentation/scratch_card_screen.dart';
import '../../games/presentation/direct_gift_claim_screen.dart';
import '../../games/presentation/choose_gift_screen.dart';
import '../../admin/domain/event_model.dart';
import '../../admin/domain/retail_chain_model.dart';
import '../../client_portal/presentation/widgets/campaign_gift_balance_dialog.dart';
import '../../client_portal/presentation/widgets/campaign_brief_dialog.dart';
import 'invoices_log_screen.dart';
import 'widgets/receipt_validation_dialog.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/widgets/switch_point_branding.dart';
import '../../../core/constants/country_currency_config.dart';
import '../../../core/widgets/m3_adaptive_scaffold.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/widgets/m3_action_menu.dart';
import '../../../core/utils/receipt_image_calibrator.dart';
import '../../../core/widgets/optimistic_receipt_scanner_card.dart';

class ValidationScreen extends ConsumerStatefulWidget {
  const ValidationScreen({super.key});

  @override
  ConsumerState<ValidationScreen> createState() => _ValidationScreenState();
}

class _ValidationScreenState extends ConsumerState<ValidationScreen> {
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  final List<XFile> _receiptImages = [];
  int _selectedPreviewIndex = 0;
  bool _isAiLoading = false;
  int _aiPhase = 0;
  String _aiPhaseText = '';
  CalibratedImageResult? _latestCalibration;
  Uint8List? _previewImageBytes;
  EventModel? _activeEvent;
  List<EventModel> _activeEvents = [];

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadActiveEvent();
  }

  Future<void> _loadActiveEvent() async {
    try {
      final firestore = ref.read(firestoreProvider);
      final eventsSnapshot = await firestore
          .collection('events')
          .where('isActive', isEqualTo: true)
          .get();
      if (eventsSnapshot.docs.isNotEmpty && mounted) {
        final events = eventsSnapshot.docs
            .map((d) => EventModel.fromFirestore(d))
            .toList();
        setState(() {
          _activeEvents = events;
          if (_activeEvent == null || !events.any((e) => e.id == _activeEvent!.id)) {
            _activeEvent = events.first;
          } else {
            _activeEvent = events.firstWhere((e) => e.id == _activeEvent!.id);
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _pickImage([ImageSource source = ImageSource.camera, bool append = false]) async {
    if (append && _receiptImages.length >= 4) {
      final strings = AppStrings.of(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.maxPartsReachedAlert),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 2560,
        maxHeight: 2560,
        imageQuality: 92,
      );
      if (pickedFile != null) {
        setState(() {
          if (append) {
            _receiptImages.add(pickedFile);
            _selectedPreviewIndex = _receiptImages.length - 1;
          } else {
            _receiptImages
              ..clear()
              ..add(pickedFile);
            _selectedPreviewIndex = 0;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  void _showAddPartModal() {
    final colorScheme = Theme.of(context).colorScheme;
    final strings = AppStrings.of(ref);

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final nextPartIndex = _receiptImages.length + 1;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '${strings.addNextReceiptPartBtn} (${strings.partIndexLabel(nextPartIndex)})',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.camera_alt_rounded, color: colorScheme.primary),
                  ),
                  title: Text(
                    strings.captureNextPartCamera,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.camera, true);
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.photo_library_rounded, color: colorScheme.secondary),
                  ),
                  title: Text(
                    strings.pickNextPartGallery,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.gallery, true);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _removePart(int index) {
    if (index >= 0 && index < _receiptImages.length) {
      setState(() {
        _receiptImages.removeAt(index);
        if (_selectedPreviewIndex >= _receiptImages.length) {
          _selectedPreviewIndex = math.max(0, _receiptImages.length - 1);
        }
      });
    }
  }

  void _clearAllParts() {
    setState(() {
      _receiptImages.clear();
      _selectedPreviewIndex = 0;
    });
  }

  Future<void> _processReceiptWithAI() async {
    if (_receiptImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture a receipt photo first.')),
      );
      return;
    }
    
    setState(() {
      _isAiLoading = true;
      _aiPhase = 0;
      _aiPhaseText = '1/3 جاري معايرة الصورة وضبط التباين محلياً...';
    });
    
    try {
      final firestore = ref.read(firestoreProvider);
      
      // Resolve active event
      final EventModel activeEvent;
      if (_activeEvent != null) {
        EventModel refreshed = _activeEvent!;
        try {
          final doc = await firestore.collection('events').doc(_activeEvent!.id).get();
          if (doc.exists) {
            refreshed = EventModel.fromFirestore(doc);
            if (mounted) setState(() => _activeEvent = refreshed);
          }
        } catch (_) {}
        activeEvent = refreshed;
      } else {
        final eventsSnapshot = await firestore
            .collection('events')
            .where('isActive', isEqualTo: true)
            .get();
            
        if (eventsSnapshot.docs.isEmpty) {
          if (!mounted) return;
          _showPopupMessage('خطأ', 'لا يوجد أي حملة (Event) مفعلة حالياً.', isError: true);
          setState(() => _isAiLoading = false);
          return;
        }
        activeEvent = EventModel.fromFirestore(eventsSnapshot.docs.first);
      }

      final aiService = ref.read(aiReceiptServiceProvider);
      final productsService = ref.read(companyProductsServiceProvider);
      
      final primaryImage = _receiptImages.first;
      final rawPrimaryBytes = await primaryImage.readAsBytes();

      if (mounted) {
        setState(() {
          _previewImageBytes = rawPrimaryBytes;
        });
      }

      // Step 1: Calibrate primary image & thermal contrast
      final primaryCalib = await ReceiptImageCalibrator.calibrateReceiptBytes(rawPrimaryBytes);
      final bytes = primaryCalib.bytes;
      final mimeType = primaryCalib.mimeType;

      // Step 2: Calibrate additional parts if present
      final List<Uint8List> additionalBytesList = [];
      final List<String> additionalMimesList = [];
      for (int i = 1; i < _receiptImages.length; i++) {
        final addRaw = await _receiptImages[i].readAsBytes();
        final addCalib = await ReceiptImageCalibrator.calibrateReceiptBytes(addRaw);
        additionalBytesList.add(addCalib.bytes);
        additionalMimesList.add(addCalib.mimeType);
      }

      final allBytesList = [bytes, ...additionalBytesList];
      final allImagesList = List<XFile>.from(_receiptImages);

      if (mounted) {
        setState(() {
          _latestCalibration = primaryCalib;
          _previewImageBytes = primaryCalib.bytes;
          _aiPhase = 1;
          _aiPhaseText = '2/3 جاري استخراج البيانات عبر الذكاء الاصطناعي...';
        });
      }

      // Fetch company catalog products & barcodes
      // Fetch company product barcodes catalog and branch signatures concurrently in parallel
      List<String> registeredBarcodes = [];
      Map<String, String> catalogBarcodeMap = {};
      List<BranchModel> chainBranches = [];

      try {
        final results = await Future.wait([
          productsService.getProductsForCompany(activeEvent.companySlug).catchError((_) => <CompanyProductItem>[]),
          ref.read(retailChainsServiceProvider).getBranchesForEvent(
            retailChainId: activeEvent.retailChainId,
            branchIds: activeEvent.branchIds,
            branchNames: activeEvent.branchNames,
          ).catchError((_) => <BranchModel>[]),
        ]).timeout(AiReceiptService.preScanLookupTimeout); // 2.0.150+211

        final catalogItems = results[0] as List<CompanyProductItem>;
        chainBranches = results[1] as List<BranchModel>;

        registeredBarcodes = catalogItems.map((e) => "${e.productName} (${e.barcode})").toList();
        catalogBarcodeMap = {
          for (final item in catalogItems)
            if (item.productName.isNotEmpty && item.barcode.isNotEmpty)
              item.productName: item.barcode,
        };
      } catch (_) {}
      
      final List<String> effectiveRequiredProducts = [
        ...activeEvent.requiredProducts,
        for (final rule in activeEvent.promotionalRules) ...[
          ...rule.selectedProductNames,
          ...rule.requiredBrands,
          if (rule.triggerProduct.trim().isNotEmpty) rule.triggerProduct.trim(),
        ],
      ].where((s) => s.trim().isNotEmpty).toSet().toList();

      final double effectiveCampaignMinSpend = activeEvent.promotionalRules
          .where((r) => r.isSpendBased)
          .map((r) => r.effectiveMinSpend)
          .fold<double>(activeEvent.minimumSpend, (min, s) => s > 0 && (min <= 0 || s < min) ? s : min);

      final result = await aiService.analyzeReceiptImage(
        bytes, 
        mimeType,
        additionalImagesBytes: additionalBytesList,
        additionalMimeTypes: additionalMimesList,
        targetCompany: activeEvent.targetCompany,
        minimumSpend: effectiveCampaignMinSpend,
        requiredProducts: effectiveRequiredProducts,
        registeredBarcodes: registeredBarcodes,
        catalogBarcodeMap: catalogBarcodeMap,
        retailChainName: activeEvent.retailChainName,
        allowedBranches: activeEvent.branchNames,
        isAllBranches: activeEvent.isAllBranches,
        registeredBranches: chainBranches,
        startDate: activeEvent.startDate,
        endDate: activeEvent.endDate,
        customPrompt: activeEvent.customPrompt,
        allowMultipleChances: activeEvent.allowMultipleChances,
        multiplierBasis: activeEvent.multiplierBasis,
        maxChancesPerReceipt: activeEvent.maxChancesPerReceipt,
        promotionalRules: activeEvent.promotionalRules,
        spendLadderMode: activeEvent.spendLadderMode,
      ).timeout(AiReceiptService.stage2Ceiling,
          onTimeout: () => throw TimeoutException(
              AiReceiptService.stage2TimeoutMessage,
              AiReceiptService.stage2Ceiling));

      if (mounted) {
        setState(() {
          _aiPhase = 2;
          _aiPhaseText = '3/3 جاري مطابقة شروط العروض واحتساب الجوائز...';
        });
      }

      final previewImgUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
      final List<String> previewUrls = allBytesList
          .map((b) => 'data:image/jpeg;base64,${base64Encode(b)}')
          .toList();

      // Asynchronously stage any newly harvested branch metadata for admin review & merge
      unawaited(
        ref.read(retailChainsServiceProvider).stageBranchEnrichment(
          chainName: result.storeChainDetected.isNotEmpty
              ? result.storeChainDetected
              : activeEvent.retailChainName,
          branchName: result.branchDetected,
          storeId: result.storeId,
          posNumber: result.posNumber,
          taxNumber: result.taxNumber,
          commercialReg: result.commercialReg,
          hotline: result.hotline,
          branchAddress: result.branchAddress,
          receiptNumber: result.receiptNumber,
          receiptDate: result.receiptDate,
          sourceReceiptUrl: previewImgUrl,
        ).catchError((_) => false),
      );

      if (!result.isValid) {
        if (!mounted) return;
        final activeCountry = ref.read(activeCountryProvider);
        final unfulfilledList = result.unfulfilledConditions.isNotEmpty
            ? result.unfulfilledConditions
            : (activeEvent.promotionalRules.isNotEmpty
                ? PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
                    result: result,
                    promotionalRules: activeEvent.promotionalRules,
                  )
                : [result.message.trim().isNotEmpty ? result.message.trim() : 'الفاتورة غير مطابقة لشروط الحملة']);

        final conditions = buildValidationConditionItems(
          isValid: false,
          message: result.message,
          targetCompanyTotal: result.targetCompanyTotal,
          minimumSpend: effectiveCampaignMinSpend,
          targetCompany: activeEvent.targetCompany,
          currencySymbol: activeCountry.currencySymbol,
          unfulfilledConditions: unfulfilledList,
          isBranchMatched: result.isBranchMatched,
          storeChainDetected: result.storeChainDetected,
          branchDetected: result.branchDetected,
          retailChainName: activeEvent.retailChainName,
          allowedBranches: activeEvent.branchNames,
          isAllBranches: activeEvent.isAllBranches,
          receiptDate: result.receiptDate,
          hasTargetProducts: result.extractedProducts.any((p) => p.isTargetCompany) || result.targetCompanyTotal > 0,
          isHandwritten: result.isHandwritten,
          isThermalPosReceipt: result.isThermalPosReceipt,
          isTampered: result.isTampered,
          isScreenCapture: result.isScreenCapture,
          fraudReasons: result.fraudReasons,
        );

        final rejectionReasonText = unfulfilledList.join(' • ');

        // Asynchronously persist rejected transaction to Firestore & Storage for audit
        _recordRejectedReceipt(
          result: result,
          allBytesList: allBytesList,
          allImagesList: allImagesList,
          activeEvent: activeEvent,
          rejectionReason: rejectionReasonText,
          unfulfilledConditions: unfulfilledList,
          totalValue: result.targetCompanyTotal,
        );

        showReceiptValidationReportDialog(
          context: context,
          title: 'عفواً، الفاتورة غير مطابقة للشروط',
          subtitle: 'تم فحص الفاتورة بالذكاء الاصطناعي وتبيّن عدم استيفاء الشروط التالية:',
          conditions: conditions,
          receiptNumber: result.receiptNumber,
          storeChain: result.storeChainDetected,
          branch: result.branchDetected,
          receiptDate: result.receiptDate,
          totalValue: result.targetCompanyTotal,
          requiredMinimum: activeEvent.minimumSpend,
          currencySymbol: activeCountry.currencySymbol,
          imageUrl: previewImgUrl,
          imageUrls: previewUrls,
        );
        return;
      }

      final double totalValue = result.targetCompanyTotal;
      if (activeEvent.minimumSpend > 0 && totalValue < activeEvent.minimumSpend) {
        if (!mounted) return;
        final activeCountry = ref.read(activeCountryProvider);
        final unfulfilledList = [
          'إجمالي مشتريات منتجات ${activeEvent.targetCompany} في الفاتورة ($totalValue ${activeCountry.currencySymbol}) أقل من الحد الأدنى المطلوب (${activeEvent.minimumSpend} ${activeCountry.currencySymbol}).'
        ];
        final conditions = [
          ValidationConditionItem(
            title: 'الحد الأدنى لقيمة المشتريات',
            description: unfulfilledList.first,
            icon: Icons.price_check_rounded,
            isMet: false,
            value: '$totalValue / ${activeEvent.minimumSpend} ${activeCountry.currencySymbol}',
          ),
        ];

        // Asynchronously persist rejected transaction to Firestore & Storage for audit
        _recordRejectedReceipt(
          result: result,
          allBytesList: allBytesList,
          allImagesList: allImagesList,
          activeEvent: activeEvent,
          rejectionReason: 'الحد الأدنى لقيمة المشتريات غير مستوفى ($totalValue / ${activeEvent.minimumSpend} ${activeCountry.currencySymbol})',
          unfulfilledConditions: unfulfilledList,
          totalValue: totalValue,
        );

        showReceiptValidationReportDialog(
          context: context,
          title: 'مبلغ المشتريات غير كافٍ',
          subtitle: 'تم فحص الفاتورة وتبيّن عدم بلوغ الحد الأدنى للمشاركة في العرض:',
          conditions: conditions,
          receiptNumber: result.receiptNumber,
          storeChain: result.storeChainDetected,
          branch: result.branchDetected,
          receiptDate: result.receiptDate,
          totalValue: totalValue,
          requiredMinimum: activeEvent.minimumSpend,
          currencySymbol: activeCountry.currencySymbol,
          imageUrl: previewImgUrl,
          imageUrls: previewUrls,
        );
        return;
      }

      final receiptNumber = result.receiptNumber.trim();
      if (receiptNumber.isNotEmpty) {
        final dupCheck = await ReceiptDeduplicationHelper.checkReceiptDuplicate(
          firestore: firestore,
          receiptNumber: receiptNumber,
          companySlug: activeEvent.companySlug,
          campaignId: activeEvent.id,
          isMultiScan: false,
        );

        if (dupCheck.isDuplicate) {
          if (!mounted) return;
          final activeCountry = ref.read(activeCountryProvider);
          final strings = AppStrings.of(ref);

          showReceiptValidationReportDialog(
            context: context,
            title: strings.duplicateReceiptAlreadyDrawnTitle,
            subtitle: dupCheck.rejectionMessage,
            conditions: [
              ValidationConditionItem(
                title: strings.duplicateReceiptConditionTitle,
                description: dupCheck.rejectionMessage,
                icon: Icons.history_toggle_off_rounded,
                isMet: false,
                value: dupCheck.existingPrizeWon,
              ),
            ],
            receiptNumber: receiptNumber,
            storeChain: result.storeChainDetected,
            branch: result.branchDetected,
            receiptDate: result.receiptDate,
            totalValue: result.targetCompanyTotal,
            requiredMinimum: activeEvent.minimumSpend,
            currencySymbol: activeCountry.currencySymbol,
            imageUrl: previewImgUrl,
            imageUrls: previewUrls,
            isDuplicate: true,
          );
          return;
        }
      }

      // Check for existing receipt in this specific campaign to update/upsert
      DocumentSnapshot<Map<String, dynamic>>? existingDoc;
      final deterministicDocId = ReceiptDeduplicationHelper.getDeterministicDocId(
        campaignId: activeEvent.id,
        receiptNumber: receiptNumber,
      );

      if (receiptNumber.isNotEmpty) {
        final directSnap = await firestore.collection('receipts_transactions').doc(deterministicDocId).get();
        if (directSnap.exists) {
          existingDoc = directSnap;
        } else {
          final existing = await firestore
              .collection('receipts_transactions')
              .where('receipt_number', isEqualTo: receiptNumber)
              .where('campaignId', isEqualTo: activeEvent.id)
              .limit(1)
              .get();

          if (existing.docs.isNotEmpty) {
            existingDoc = existing.docs.first;
          }
        }
      }

      // 2. Upload images to Firebase Storage named by Receipt Number and Campaign ID
      final cleanReceiptNumber = (receiptNumber.isNotEmpty ? receiptNumber : "INV_${DateTime.now().millisecondsSinceEpoch}")
          .replaceAll(RegExp(r'[/\\?%*:|"<>]'), '_');

      final List<String> uploadedImageUrls = [];
      final List<String> uploadedStoragePaths = [];

      await Future.wait(
        List.generate(allBytesList.length, (index) async {
          final partNum = index + 1;
          final sPath = allBytesList.length == 1
              ? 'receipts/${activeEvent.companySlug}/${activeEvent.id}/$cleanReceiptNumber.jpg'
              : 'receipts/${activeEvent.companySlug}/${activeEvent.id}/${cleanReceiptNumber}_part$partNum.jpg';
          try {
            final storage = ref.read(firebaseStorageProvider);
            final storageRef = storage.ref().child(sPath);
            final metadata = SettableMetadata(
              contentType: 'image/jpeg',
              customMetadata: {
                'receiptNumber': receiptNumber,
                'campaignId': activeEvent.id,
                'companySlug': activeEvent.companySlug,
                'targetCompany': activeEvent.targetCompany,
                'totalValue': totalValue.toString(),
                'partIndex': '$partNum',
                'totalParts': '${allBytesList.length}',
                'uploadedAt': DateTime.now().toIso8601String(),
                'uploaderUid': ref.read(firebaseAuthProvider).currentUser?.uid ?? '',
              },
            );

            if (kIsWeb) {
              await storageRef.putData(allBytesList[index], metadata).timeout(const Duration(seconds: 15));
            } else {
              await storageRef.putFile(File(allImagesList[index].path), metadata).timeout(const Duration(seconds: 15));
            }
            final url = await storageRef.getDownloadURL().timeout(const Duration(seconds: 10));
            uploadedImageUrls.add(url);
            uploadedStoragePaths.add(sPath);
          } catch (e) {
            debugPrint('Storage upload for part $partNum skipped or timed out: $e');
            final fallbackUrl = 'data:image/jpeg;base64,${base64Encode(allBytesList[index])}';
            uploadedImageUrls.add(fallbackUrl);
            uploadedStoragePaths.add(sPath);
          }
        }),
      );

      final String primaryImageUrl = uploadedImageUrls.isNotEmpty ? uploadedImageUrls.first : previewImgUrl;
      final String primaryStoragePath = uploadedStoragePaths.isNotEmpty ? uploadedStoragePaths.first : '';

      // Evaluate promotional rules using our robust multi-offer AI & NLP PromotionalRuleMatcher
      final matchedRulesList = PromotionalRuleMatcher.matchAllWithMultipliers(
        result: result,
        promotionalRules: activeEvent.promotionalRules,
        allowCampaignMultipliers: activeEvent.allowMultipleChances,
        maxUnitsPerReceipt: activeEvent.maxChancesPerReceipt,
        spendLadderMode: activeEvent.spendLadderMode,
      );

      // Strict Zero-Fallback Rule: If campaign has promotional rules and none are met, reject receipt
      if (activeEvent.promotionalRules.isNotEmpty && matchedRulesList.isEmpty) {
        if (!mounted) return;
        final activeCountry = ref.read(activeCountryProvider);
        final unfulfilledPromoList = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
          result: result,
          promotionalRules: activeEvent.promotionalRules,
        );

        final conditions = [
          ValidationConditionItem(
            title: 'شروط العروض والمنتجات الترويجية',
            description: unfulfilledPromoList.isNotEmpty
                ? unfulfilledPromoList.join('\n')
                : 'الفاتورة لا تستوفي شروط الكميات المطلوبة لعروض الحملة الحالية.',
            icon: Icons.inventory_2_outlined,
            isMet: false,
          ),
        ];

        // Asynchronously persist rejected transaction to Firestore & Storage for audit
        _recordRejectedReceipt(
          result: result,
          allBytesList: allBytesList,
          allImagesList: allImagesList,
          activeEvent: activeEvent,
          rejectionReason: unfulfilledPromoList.isNotEmpty
              ? unfulfilledPromoList.join(' • ')
              : 'شروط العروض الترويجية غير مستوفاة في الفاتورة',
          unfulfilledConditions: unfulfilledPromoList,
          totalValue: totalValue,
        );

        // Harvest unlisted company products so they immediately appear in "تحديث الأصناف" for review & one-click catalog addition
        if (result.extractedProducts.any((p) => p.isTargetCompany)) {
          unawaited(ref.read(aiProductDiscoveryServiceProvider).autoHarvestFromReceiptAnalysis(
            companySlug: activeEvent.companySlug,
            companyName: activeEvent.targetCompany,
            retailChain: result.storeChainDetected,
            branch: result.branchDetected,
            receiptNumber: result.receiptNumber,
            extractedProducts: result.extractedProducts,
          ));
        }

        showReceiptValidationReportDialog(
          context: context,
          title: 'عفواً، شروط العرض غير مستوفاة',
          subtitle: 'تم فحص الفاتورة بالذكاء الاصطناعي وتبيّن عدم استيفاء الشروط الترويجية التالية:',
          conditions: conditions,
          receiptNumber: result.receiptNumber,
          storeChain: result.storeChainDetected,
          branch: result.branchDetected,
          receiptDate: result.receiptDate,
          totalValue: totalValue,
          requiredMinimum: activeEvent.minimumSpend,
          currencySymbol: activeCountry.currencySymbol,
          imageUrl: previewImgUrl,
          imageUrls: previewUrls,
        );
        return;
      }

      final compositeBundle = CompositePromotionalBundle.fromMatchedRules(
        matchedRulesList,
        fallbackTitle: result.matchedRewardValue.trim().isNotEmpty
            ? result.matchedRewardValue.trim()
            : (activeEvent.availablePrizeNames.isNotEmpty ? activeEvent.availablePrizeNames.first : 'هدية ترويجية مميزة'),
      );

      // Save or Update in Firestore (Upsert) - Composite bundle chances govern (AIR-83)
      final int totalChances = clampCampaignChances(
        compositeBundle.matchedRules.isNotEmpty
            ? compositeBundle.totalChances
            : (result.chancesEarned > 0 ? result.chancesEarned : 1),
        allowMultipleChances: activeEvent.allowMultipleChances,
        maxChancesPerReceipt: activeEvent.maxChancesPerReceipt,
      );
      final DocumentReference<Map<String, dynamic>> transactionRef =
          existingDoc != null ? existingDoc.reference : firestore.collection('receipts_transactions').doc(deterministicDocId);
      final bool isExistingRecord = existingDoc != null;
      final existingData = existingDoc?.data() ?? {};
      final bool wasGamePlayed = existingData['game_played'] == true;

      final Map<String, dynamic> transactionData = {
        'app_version': AppVersionConfig.appVersion,
        if (RepDeviceId.value.isNotEmpty) 'rep_device_id': RepDeviceId.value,
        ...acceptedReceiptCore(
          result: result,
          campaignId: activeEvent.id,
          companySlug: activeEvent.companySlug,
          targetCompany: activeEvent.targetCompany,
          retailChainName: activeEvent.retailChainName,
          chancesEarned: totalChances,
          allowMultipleChances: activeEvent.allowMultipleChances,
          submittedByUid: ref.read(firebaseAuthProvider).currentUser?.uid ?? '',
          spendLadderMode: activeEvent.spendLadderMode,
          promotionalRules: activeEvent.promotionalRules,
          branchFields: ReceiptBranchResolver.firestoreFields(
            activeEvent,
            detectedName: result.branchDetected,
            receiptNumber: result.receiptNumber,
          ),
        ),
        'promoter_id': ref.read(firebaseAuthProvider).currentUser?.uid,
        if (primaryImageUrl.isNotEmpty) 'image_url': primaryImageUrl,
        if (primaryStoragePath.isNotEmpty) 'storage_path': primaryStoragePath,
        if (uploadedImageUrls.length > 1) 'image_urls': uploadedImageUrls,
        if (uploadedStoragePaths.length > 1) 'storage_paths': uploadedStoragePaths,
        'parts_count': allBytesList.length,
      };

      if (isExistingRecord) {
        transactionData['updated_at'] = FieldValue.serverTimestamp();
        transactionData['is_updated_via_ai'] = true;
        await transactionRef.set(transactionData, SetOptions(merge: true));
      } else {
        transactionData['timestamp'] = FieldValue.serverTimestamp();
        transactionData['game_played'] = false;
        transactionData['prize_won'] = null;
        await transactionRef.set(transactionData);
      }

      // Harvest discovered products asynchronously for the AI Product Discovery Hub
      unawaited(ref.read(aiProductDiscoveryServiceProvider).autoHarvestFromReceiptAnalysis(
        companySlug: activeEvent.companySlug,
        companyName: activeEvent.targetCompany,
        retailChain: result.storeChainDetected,
        branch: result.branchDetected,
        receiptNumber: receiptNumber.isNotEmpty ? receiptNumber : cleanReceiptNumber,
        extractedProducts: result.extractedProducts,
      ));

      if (!mounted) return;

      // Reset form
      setState(() {
        _receiptImages.clear();
        _selectedPreviewIndex = 0;
      });

      if (isExistingRecord) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تم تحديث بيانات الفاتورة رقم ($receiptNumber) بنجاح بالمعلومات الجديدة من البون 🔄',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: colorScheme.onTertiaryFixedVariant,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );

        if (wasGamePlayed) {
          final activeCountry = ref.read(activeCountryProvider);
          final strings = AppStrings.of(ref);
          showReceiptValidationReportDialog(
            context: context,
            title: strings.duplicateReceiptAlreadyDrawnTitle,
            subtitle: strings.duplicateReceiptAlreadyDrawnSubtitle,
            conditions: [
              ValidationConditionItem(
                title: strings.duplicateReceiptConditionTitle,
                description: strings.duplicateReceiptConditionDesc,
                icon: Icons.history_toggle_off_rounded,
                isMet: false,
              ),
            ],
            receiptNumber: receiptNumber,
            storeChain: result.storeChainDetected,
            branch: result.branchDetected,
            receiptDate: result.receiptDate,
            totalValue: totalValue,
            requiredMinimum: activeEvent.minimumSpend,
            currencySymbol: activeCountry.currencySymbol,
            imageUrl: primaryImageUrl,
            imageUrls: uploadedImageUrls.isNotEmpty ? uploadedImageUrls : previewUrls,
            isDuplicate: true,
          );
          return;
        }
      }
      setState(() {
        _receiptImages.clear();
        _selectedPreviewIndex = 0;
      });

      // Smart branch ID resolution matching AI-detected branch name with campaign branches (AIR-80 & Rule 8)
      String? resolvedBranchId;
      String resolvedCanonicalBranchName = result.branchDetected.trim();
      if (activeEvent.branchIds.isNotEmpty) {
        final detectedBranchClean = CompanyGiftsService.normalizeBranchToken(result.branchDetected);
        if (detectedBranchClean.isNotEmpty) {
          for (int i = 0; i < activeEvent.branchNames.length; i++) {
            final bName = CompanyGiftsService.normalizeBranchToken(activeEvent.branchNames[i]);
            if (bName.isNotEmpty && (bName == detectedBranchClean || bName.contains(detectedBranchClean) || detectedBranchClean.contains(bName))) {
              if (i < activeEvent.branchIds.length) {
                resolvedBranchId = activeEvent.branchIds[i];
                resolvedCanonicalBranchName = activeEvent.branchNames[i];
                break;
              }
            }
          }
          if (resolvedBranchId == null) {
            for (final p in activeEvent.allocatedPrizes) {
              final pBranchName = CompanyGiftsService.normalizeBranchToken(p.branchName);
              if (pBranchName.isNotEmpty && (pBranchName == detectedBranchClean || pBranchName.contains(detectedBranchClean) || detectedBranchClean.contains(pBranchName))) {
                resolvedBranchId = p.branchId.isNotEmpty ? p.branchId : p.branchName;
                if (p.branchName.trim().isNotEmpty) {
                  resolvedCanonicalBranchName = p.branchName.trim();
                }
                break;
              }
            }
          }
        }
        if (resolvedBranchId == null && (detectedBranchClean.isEmpty || activeEvent.branchIds.length == 1)) {
          resolvedBranchId = activeEvent.branchIds.first;
        }
      }

      final branchIdentifier = (resolvedCanonicalBranchName.isNotEmpty ? resolvedCanonicalBranchName : resolvedBranchId) ?? result.branchDetected.trim();

      // Route based on rule-level game type or fallback to campaign game type
      final prizeNames = activeEvent.availablePrizeNamesForBranch(branchIdentifier);
      final ruleLevelGame = (compositeBundle.resolvedGameType != null && compositeBundle.resolvedGameType!.trim().isNotEmpty)
          ? compositeBundle.resolvedGameType!.trim()
          : null;
      final gameType = ruleLevelGame ?? activeEvent.gameType;

      if (gameType == 'directGift' || gameType == 'direct_gift') {
        final designatedPrizeObj = activeEvent.availablePrizes.isNotEmpty
            ? activeEvent.availablePrizes.first
            : (activeEvent.allocatedPrizes.isNotEmpty ? activeEvent.allocatedPrizes.first : null);

        String designatedPrize;
        List<LinkedGiftAllocation> resolvedLinkedGifts = [];
        double? resolvedUnitValue;
        bool resolvedIsVoucher = false;

        if (matchedRulesList.isNotEmpty) {
          resolvedLinkedGifts = compositeBundle.combinedLinkedGifts;
          designatedPrize = compositeBundle.compositePrizeTitle;

          resolvedIsVoucher = compositeBundle.totalVoucherValue > 0 ||
              resolvedLinkedGifts.any((g) => g.isVoucher) ||
              designatedPrize.contains('فواتشر') ||
              designatedPrize.toLowerCase().contains('voucher') ||
              designatedPrize.contains('قسيمة');

          resolvedUnitValue = resolvedIsVoucher
              ? (compositeBundle.totalVoucherValue > 0
                  ? compositeBundle.totalVoucherValue
                  : designatedPrizeObj?.unitValue)
              : 0.0;
        } else if (result.matchedRewardValue.trim().isNotEmpty) {
          designatedPrize = result.matchedRewardValue.trim();
          resolvedIsVoucher = result.matchedRewardType == 'voucher' ||
              result.matchedRewardAmount > 0 ||
              designatedPrize.contains('فواتشر') ||
              designatedPrize.contains('قسيمة');
          resolvedUnitValue = resolvedIsVoucher
              ? (result.matchedRewardAmount > 0 ? result.matchedRewardAmount : designatedPrizeObj?.unitValue)
              : 0.0;
        } else {
          designatedPrize = designatedPrizeObj?.name ??
              (prizeNames.isNotEmpty ? prizeNames.first : '');
          resolvedUnitValue = designatedPrizeObj?.unitValue;
          resolvedIsVoucher = designatedPrizeObj?.isVoucher ?? false;
        }

        // Self-heal ONLY if empty or raw doc id or generic placeholder
        if (designatedPrize.isEmpty ||
            designatedPrize == 'هدية فورية مميزة' ||
            designatedPrize == 'هدية ترويجية مميزة' ||
            RegExp(r'^[a-zA-Z0-9_-]{15,35}$').hasMatch(designatedPrize)) {
          if (resolvedLinkedGifts.isNotEmpty) {
            designatedPrize = resolvedLinkedGifts.map((g) => g.quantity > 1 ? '${g.quantity} × ${g.giftName}' : g.giftName).join(' + ');
            resolvedIsVoucher = resolvedLinkedGifts.any((g) => g.isVoucher);
            resolvedUnitValue = resolvedIsVoucher
                ? resolvedLinkedGifts.fold<double>(0.0, (acc, g) => acc + g.totalMonetaryValue)
                : 0.0;
          } else if (resolvedIsVoucher || (resolvedUnitValue != null && resolvedUnitValue > 0)) {
            final val = (resolvedUnitValue != null && resolvedUnitValue > 0)
                ? (resolvedUnitValue == resolvedUnitValue.roundToDouble() ? resolvedUnitValue.toInt() : resolvedUnitValue)
                : 50;
            designatedPrize = 'فواتشر بقيمة $val جنيه';
            resolvedIsVoucher = true;
            resolvedUnitValue ??= 50.0;
          } else {
            designatedPrize = 'هدية فورية معتمدة';
            resolvedIsVoucher = false;
            resolvedUnitValue = 0.0;
          }
        }

        final promoQuantity = resolvedLinkedGifts.isNotEmpty
            ? 1
            : (activeEvent.allowMultipleChances ? totalChances : 1);
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DirectGiftClaimScreen(
              transactionId: transactionRef.id,
              eventId: activeEvent.id,
              prizeName: designatedPrize,
              quantity: promoQuantity,
              branchId: resolvedBranchId,
              branchName: resolvedCanonicalBranchName.isNotEmpty ? resolvedCanonicalBranchName : result.branchDetected,
              retailChainName: activeEvent.retailChainName.isNotEmpty ? activeEvent.retailChainName : result.storeChainDetected,
              companyName: activeEvent.targetCompany,
              receiptNumber: receiptNumber,
              companySlug: activeEvent.companySlug,
              unitValue: resolvedUnitValue,
              isVoucher: resolvedIsVoucher,
              linkedGifts: resolvedLinkedGifts,
              rewardChoiceGroups: compositeBundle.rewardChoiceGroups,
              baseLinkedGifts: compositeBundle.baseLinkedGifts,
              requireVoucherSerials: activeEvent.requireVoucherSerials, voucherSerialMode: activeEvent.voucherSerialMode,
            ),
          ),
        );
        if (mounted) {
          setState(() {
            _receiptImages.clear();
            _selectedPreviewIndex = 0;
          });
        }
      } else if (gameType == 'chooseGift') {
        final candidateGifts = compositeBundle.candidateGiftNames.isNotEmpty
            ? compositeBundle.candidateGiftNames
            : prizeNames;
        final awardRounds = compositeBundle.awardRounds;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChooseGiftScreen(
              transactionId: transactionRef.id,
              eventId: activeEvent.id,
              companySlug: activeEvent.companySlug,
              prizes: awardRounds.isNotEmpty
                  ? awardRounds.first.prizeNames
                  : (candidateGifts.isNotEmpty ? candidateGifts : prizeNames),
              roundPrizeNames: [for (final round in awardRounds) round.prizeNames],
              roundGiftIds: [for (final round in awardRounds) round.giftIds],
              roundUnitValues: [for (final round in awardRounds) round.unitValues],
              roundRuleIds: [for (final round in awardRounds) round.ruleId],
              roundTierMinSpends: [for (final round in awardRounds) round.tierMinSpend],
              totalChances: awardRounds.isNotEmpty ? awardRounds.length : totalChances,
              branchId: resolvedBranchId,
            ),
          ),
        );
        if (mounted) {
          setState(() {
            _receiptImages.clear();
            _selectedPreviewIndex = 0;
          });
        }
      } else if (gameType == 'scratch') {
        final candidateGifts = compositeBundle.candidateGiftNames.isNotEmpty
            ? compositeBundle.candidateGiftNames
            : prizeNames;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ScratchCardScreen(
              transactionId: transactionRef.id,
              eventId: activeEvent.id,
              prizes: candidateGifts.isNotEmpty ? candidateGifts : prizeNames,
              totalChances: totalChances,
            ),
          ),
        );
        if (mounted) {
          setState(() {
            _receiptImages.clear();
            _selectedPreviewIndex = 0;
          });
        }
      } else {
        // Default: wheel (AIR-85: filter prizes strictly by detected branch stock)
        final candidateGifts = compositeBundle.candidateGiftNames.isNotEmpty
            ? compositeBundle.candidateGiftNames
            : prizeNames;
        final branchFilteredPrizes = (activeEvent.allocatedPrizes.isNotEmpty)
            ? activeEvent.filterGiftsByBranchStock(
                candidateGifts: candidateGifts,
                branch: branchIdentifier,
              )
            : candidateGifts;
        final finalWheelPrizes = branchFilteredPrizes;

        if (finalWheelPrizes.isEmpty && activeEvent.allocatedPrizes.isNotEmpty) {
          final branchDisplay = resolvedCanonicalBranchName.isNotEmpty ? resolvedCanonicalBranchName : result.branchDetected;
          if (mounted) {
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, color: Theme.of(ctx).colorScheme.error),
                    const SizedBox(width: 8),
                    Text('عذراً، نفدت الهدايا بالفرع', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                content: Text(
                  'الفاتورة صحيحة ومطابقة لشروط العرض، ولكن جميع أصناف الهدايا المخصصة لـ ($branchDisplay) رصيدها صفر حالياً.\nيرجى التواصل مع إدارة الحملة لإعادة تعبئة رصيد الهدايا.',
                  style: GoogleFonts.cairo(fontSize: 14),
                ),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text('حسناً', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }
          if (mounted) {
            setState(() {
              _receiptImages.clear();
              _selectedPreviewIndex = 0;
            });
          }
          return;
        }

        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => SpinTheWheelScreen(
              transactionId: transactionRef.id,
              eventId: activeEvent.id,
              prizes: finalWheelPrizes,
              totalChances: totalChances,
              branchId: resolvedBranchId ?? branchIdentifier,
              branchName: resolvedCanonicalBranchName.isNotEmpty ? resolvedCanonicalBranchName : result.branchDetected,
            ),
          ),
        );
        if (mounted) {
          setState(() {
            _receiptImages.clear();
            _selectedPreviewIndex = 0;
          });
        }
      }

    } catch (e) {
      if (!mounted) return;
      _showPopupMessage('تنبيه النظام', AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء معالجة الفاتورة'), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isAiLoading = false;
          _aiPhase = 0;
        });
      }
    }
  }
  

  void _showPopupMessage(String title, String message, {bool isError = true}) {
    showReceiptValidationReportDialog(
      context: context,
      title: title,
      isDuplicate: isError && (title.contains('مسجلة') || title.contains('مسبقاً')),
      conditions: [
        ValidationConditionItem(
          title: title,
          description: message,
          icon: isError ? Icons.report_problem_rounded : Icons.info_outline_rounded,
          isMet: !isError,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeCountry = ref.watch(activeCountryProvider);
    final strings = AppStrings.of(ref);
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: SwitchPointHeader(
        subtitle: strings.validationScreenSubtitle,
        companyLogoUrl: _activeEvent?.companyLogoUrl,
        customActions: [
          if (_activeEvent != null) ...[
            // 1. Campaign Concept & Offer Rules Action Button (Brief & Conditions)
            IconButton.filledTonal(
              icon: Icon(
                Icons.campaign_rounded,
                color: colorScheme.primary,
                size: 20,
              ),
              tooltip: strings.promoterCampaignBriefTooltip,
              onPressed: () {
                CampaignBriefDialog.show(context, _activeEvent!);
              },
            ),
            const SizedBox(width: 4),

            // 2. Remaining Gift Inventory & Branch Balance Action Button
            IconButton.filledTonal(
              icon: Icon(
                Icons.card_giftcard_rounded,
                color: colorScheme.primary,
                size: 20,
              ),
              tooltip: strings.promoterGiftsBalanceTooltip,
              onPressed: () {
                CampaignGiftBalanceDialog.show(context, _activeEvent!);
              },
            ),
            const SizedBox(width: 4),
          ],
          IconButton(
            icon: const Icon(Icons.list_alt_rounded),
            tooltip: strings.invoicesLogTooltip,
            color: colorScheme.primary,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const InvoicesLogScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: strings.signOutTooltip,
            color: colorScheme.error,
            onPressed: () async {
              await ref.read(firebaseServiceProvider).signOut();
              if (context.mounted) Navigator.of(context).pushReplacementNamed('/');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: M3SupportingPaneLayout(
              supportingPaneWidth: 380.0,
              showDivider: true,
              body: Center(
                child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: isMobile ? 12 : 24,
                  right: isMobile ? 12 : 24,
                  top: isMobile ? 10 : 24,
                  bottom: isMobile ? 48 : 32,
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Card(
                    elevation: 0,
                    color: colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: BorderSide(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(28.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              if (_activeEvent != null && _activeEvent!.companyLogoUrl.isNotEmpty) ...[
                                Container(
                                  width: 52,
                                  height: 52,
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.08),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: Image.network(
                                      _activeEvent!.companyLogoUrl,
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error, stackTrace) => Icon(Icons.business_rounded, color: colorScheme.primary, size: 28),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                              ] else ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(Icons.qr_code_scanner_rounded, color: colorScheme.primary, size: 28),
                                ),
                                const SizedBox(width: 14),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _activeEvent != null && _activeEvent!.eventName.isNotEmpty
                                          ? '${strings.receiptAuditTitle}: ${_activeEvent!.eventName}'
                                          : strings.receiptAuditTitle,
                                      style: GoogleFonts.cairo(
                                        fontSize: 19,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    Text(
                                      _activeEvent != null && _activeEvent!.targetCompany.isNotEmpty
                                          ? '${strings.targetCompanyHeader}: ${_activeEvent!.targetCompany}${_activeEvent!.minimumSpend > 0 ? " • ${strings.minSpendPrefix} ${_activeEvent!.minimumSpend} ${activeCountry.currencySymbolFor(strings.languageCode)}" : ""}'
                                          : strings.receiptAuditSubtitle,
                                      style: GoogleFonts.cairo(
                                        fontSize: 13,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_activeEvents.length > 1) ...[
                                const SizedBox(width: 8),
                                M3ActionMenu(
                                  tooltip: 'تبديل الحملة النشطة',
                                  anchorBuilder: (context, controller, child) {
                                    return InkWell(
                                      onTap: () {
                                        if (controller.isOpen) {
                                          controller.close();
                                        } else {
                                          controller.open();
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(20),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.swap_horiz_rounded, size: 18, color: colorScheme.primary),
                                            const SizedBox(width: 4),
                                            Text(
                                              'تبديل الحملة (${_activeEvents.length})',
                                              style: GoogleFonts.cairo(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  children: [
                                    M3ActionMenu.header(
                                      context: context,
                                      title: 'الحملات الترويجية المتاحة',
                                      icon: Icons.campaign_rounded,
                                    ),
                                    for (final e in _activeEvents)
                                      () {
                                        final isSelected = e.id == _activeEvent?.id;
                                        return M3ActionMenu.item(
                                          context: context,
                                          label: e.eventName,
                                          icon: isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                          isSelected: isSelected,
                                          shortcutText: '${e.targetCompany} • ${e.retailChainName}',
                                          onPressed: () {
                                            setState(() => _activeEvent = e);
                                          },
                                        );
                                      }(),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 24),
                          
                          // Image Preview & Picker
                          Container(
                            height: 300,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                              ),
                              borderRadius: BorderRadius.circular(16),
                              color: colorScheme.surfaceContainerLowest,
                            ),
                            child: _receiptImages.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(20.0),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Wrap(
                                            alignment: WrapAlignment.center,
                                            spacing: 12,
                                            runSpacing: 12,
                                            children: [
                                              FilledButton.icon(
                                                onPressed: () => _pickImage(ImageSource.camera),
                                                icon: const Icon(Icons.camera_alt_rounded),
                                                label: Text(
                                                  strings.captureReceiptBtn,
                                                  style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold),
                                                ),
                                                style: FilledButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                                ),
                                              ),
                                              FilledButton.tonalIcon(
                                                onPressed: () => _pickImage(ImageSource.gallery),
                                                icon: const Icon(Icons.photo_library_rounded),
                                                label: Text(
                                                  strings.pickFromGalleryAction,
                                                  style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold),
                                                ),
                                                style: FilledButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 18),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.lightbulb_outline_rounded,
                                                  size: 16,
                                                  color: colorScheme.primary,
                                                ),
                                                const SizedBox(width: 8),
                                                Flexible(
                                                  child: Text(
                                                    strings.longReceiptTip,
                                                    style: GoogleFonts.cairo(
                                                      fontSize: 12,
                                                      color: colorScheme.onSurfaceVariant,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: kIsWeb
                                            ? Image.network(
                                                _receiptImages[_selectedPreviewIndex].path,
                                                fit: BoxFit.contain,
                                                width: double.infinity,
                                              )
                                            : Image.file(
                                                File(_receiptImages[_selectedPreviewIndex].path),
                                                fit: BoxFit.contain,
                                                width: double.infinity,
                                              ),
                                      ),
                                      // Part Badge on active preview
                                      Positioned(
                                        top: 10,
                                        left: 10,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.75),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(
                                              color: Colors.white.withValues(alpha: 0.2),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.layers_rounded,
                                                size: 14,
                                                color: colorScheme.primaryFixedDim,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                strings.isAr
                                                    ? 'جزء ${_selectedPreviewIndex + 1} من ${_receiptImages.length}'
                                                    : 'Part ${_selectedPreviewIndex + 1} of ${_receiptImages.length}',
                                                style: GoogleFonts.cairo(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // Delete active part button
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Tooltip(
                                          message: strings.deletePartTooltip,
                                          child: IconButton.filled(
                                            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                                            style: IconButton.styleFrom(
                                              backgroundColor: colorScheme.error,
                                              padding: const EdgeInsets.all(6),
                                            ),
                                            onPressed: () => _removePart(_selectedPreviewIndex),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),

                          // Multi-Part Controls & Thumbnails Strip
                          if (_receiptImages.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            // Thumbnail carousel when multiple parts exist
                            if (_receiptImages.length > 1) ...[
                              SizedBox(
                                height: 74,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _receiptImages.length,
                                  separatorBuilder: (context, _) => const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    final isSelected = index == _selectedPreviewIndex;
                                    return InkWell(
                                      onTap: () => setState(() => _selectedPreviewIndex = index),
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        width: 60,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
                                            width: isSelected ? 2.5 : 1,
                                          ),
                                          color: isSelected
                                              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                                              : colorScheme.surfaceContainerHighest,
                                        ),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: kIsWeb
                                                  ? Image.network(
                                                      _receiptImages[index].path,
                                                      fit: BoxFit.cover,
                                                    )
                                                  : Image.file(
                                                      File(_receiptImages[index].path),
                                                      fit: BoxFit.cover,
                                                    ),
                                            ),
                                            Positioned(
                                              bottom: 2,
                                              left: 2,
                                              right: 2,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withValues(alpha: 0.75),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  strings.partIndexLabel(index + 1),
                                                  style: GoogleFonts.cairo(
                                                    fontSize: 10,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],

                            // Add next part button & Clear all action (Responsive column layout)
                            if (_receiptImages.length < 4) ...[
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.tonalIcon(
                                  onPressed: _showAddPartModal,
                                  icon: const Icon(Icons.add_a_photo_rounded, size: 20),
                                  label: Text(
                                    strings.addNextReceiptPartBtn,
                                    style: GoogleFonts.cairo(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                            ],
                            Center(
                              child: TextButton.icon(
                                onPressed: _clearAllParts,
                                icon: Icon(
                                  Icons.delete_sweep_rounded,
                                  size: 18,
                                  color: colorScheme.error,
                                ),
                                label: Text(
                                  strings.clearAllPartsBtn,
                                  style: GoogleFonts.cairo(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.error,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: colorScheme.error,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                ),
                              ),
                            ),
                          ],

                          if (_isAiLoading) ...[
                            const SizedBox(height: 18),
                            OptimisticReceiptScannerCard(
                              imageBytes: _previewImageBytes,
                              activePhase: _aiPhase,
                              statusText: _aiPhaseText,
                              calibrationResult: _latestCalibration,
                            ),
                          ],

                          if (_receiptImages.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: _isAiLoading ? null : _processReceiptWithAI,
                              icon: _isAiLoading 
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.auto_awesome_rounded),
                              label: Text(
                                _isAiLoading 
                                    ? strings.auditingProgressText 
                                    : (_receiptImages.length > 1 
                                        ? strings.analyzeMultiPartsBtn(_receiptImages.length) 
                                        : strings.auditingAndStartingGame),
                                style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            supportingPane: _buildValidationSupportingPane(
              context: context,
              event: _activeEvent,
              strings: strings,
              isAr: ref.isArabic,
              colorScheme: colorScheme,
            ),
          ),
        ),
        if (!isMobile) const SwitchPointFooter(),
        ],
      ),
    );
  }

  Widget _buildValidationSupportingPane({
    required BuildContext context,
    required EventModel? event,
    required AppStrings strings,
    required bool isAr,
    required ColorScheme colorScheme,
  }) {
    if (event == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            isAr ? 'يرجى اختيار حملة ترويجية لعرض القواعد' : 'Select a campaign to view guidelines',
            style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.verified_user_rounded, color: colorScheme.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr ? 'حوكمة وتدقيق البونات' : 'Receipt Verification',
                            style: GoogleFonts.cairo(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            isAr ? 'معايير التحقق ورصيد الهدايا' : 'Audit criteria & prize balances',
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
                const SizedBox(height: 14),
                // Quick Dialog Launchers
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => CampaignBriefDialog.show(context, event),
                        icon: const Icon(Icons.campaign_rounded, size: 16),
                        label: Text(
                          isAr ? 'الشروط' : 'Rules',
                          style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => CampaignGiftBalanceDialog.show(context, event),
                        icon: const Icon(Icons.card_giftcard_rounded, size: 16),
                        label: Text(
                          isAr ? 'الهدايا' : 'Prizes',
                          style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const InvoicesLogScreen()),
                          );
                        },
                        icon: const Icon(Icons.receipt_long_rounded, size: 16),
                        label: Text(
                          isAr ? 'السجل' : 'Log',
                          style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Minimum Spend & Campaign Identity Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.monetization_on_outlined, size: 18, color: colorScheme.onTertiaryFixedVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isAr ? 'الحد الأدنى للشراء:' : 'Minimum Spend:',
                        style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.tertiaryFixedDim),
                      ),
                      child: Text(
                        event.minimumSpend > 0 ? '${event.minimumSpend} ج.م' : (isAr ? 'بدون حد أدنى' : 'No Minimum'),
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onTertiaryFixedVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                if (event.branchNames.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.storefront_rounded, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isAr ? 'عدد الفروع المعتمدة:' : 'Active Branches:',
                          style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${event.branchNames.length} ${isAr ? 'فرع' : 'branches'}',
                        style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Promotional Rules Summary (if any)
          if (event.promotionalRules.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.rule_rounded, size: 18, color: colorScheme.secondary),
                      const SizedBox(width: 8),
                      Text(
                        isAr ? 'قواعد العروض الترويجية (${event.promotionalRules.length})' : 'Promotional Rules (${event.promotionalRules.length})',
                        style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...event.promotionalRules.take(4).map((rule) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rule.ruleTitle,
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '🎁 ${isAr ? 'الهدية المستحقة:' : 'Reward:'} ${rule.rewardValue.isNotEmpty ? rule.rewardValue : (rule.linkedGifts.isNotEmpty ? rule.linkedGifts.map((g) => "${g.quantity}x ${g.giftName}").join(", ") : (rule.linkedGiftName ?? ''))}',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              color: colorScheme.onTertiaryFixedVariant,
                              fontWeight: FontWeight.w600,
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

          // 4. Photography Guidelines for Faster AI Processing
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.secondaryFixedDim),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.tips_and_updates_rounded, size: 18, color: colorScheme.onSecondaryFixedVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isAr ? 'معايير التدقيق بالذكاء الاصطناعي:' : 'AI Validation Standards:',
                        style: GoogleFonts.cairo(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSecondaryContainer,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  isAr
                      ? '• التأكد من وضوح اسم السلسلة وتاريخ الفاتورة بدقة.\n• التحقق من مطابقة أصناف الفاتورة لقواعد الحملة.\n• عدم قبول صور الفواتير المشوهة أو غير المقروءة.'
                      : '• Ensure retail chain name and date are sharp and legible.\n• Verify items comply strictly with campaign offer rules.\n• Reject blurred or cropped receipt images automatically.',
                  style: GoogleFonts.cairo(
                    fontSize: 11.5,
                    height: 1.5,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _recordRejectedReceipt({
    required AiReceiptAnalysisResult result,
    required List<Uint8List> allBytesList,
    required List<XFile> allImagesList,
    required EventModel activeEvent,
    required String rejectionReason,
    required List<String> unfulfilledConditions,
    required double totalValue,
  }) async {
    try {
      final firestore = ref.read(firestoreProvider);
      final receiptNumber = result.receiptNumber.trim();
      final cleanReceiptNumber = (receiptNumber.isNotEmpty ? receiptNumber : "REJ_${DateTime.now().millisecondsSinceEpoch}")
          .replaceAll(RegExp(r'[/\\?%*:|"<>]'), '_');

      final List<String> uploadedImageUrls = [];
      final List<String> uploadedStoragePaths = [];

      await Future.wait(
        List.generate(allBytesList.length, (index) async {
          final partNum = index + 1;
          final sPath = allBytesList.length == 1
              ? 'receipts/${activeEvent.companySlug}/${activeEvent.id}/$cleanReceiptNumber.jpg'
              : 'receipts/${activeEvent.companySlug}/${activeEvent.id}/${cleanReceiptNumber}_part$partNum.jpg';
          try {
            final storage = ref.read(firebaseStorageProvider);
            final storageRef = storage.ref().child(sPath);
            final metadata = SettableMetadata(
              contentType: 'image/jpeg',
              customMetadata: {
                'receiptNumber': receiptNumber,
                'campaignId': activeEvent.id,
                'companySlug': activeEvent.companySlug,
                'targetCompany': activeEvent.targetCompany,
                'totalValue': totalValue.toString(),
                'status': 'rejected',
                'partIndex': '$partNum',
                'totalParts': '${allBytesList.length}',
                'uploadedAt': DateTime.now().toIso8601String(),
                'uploaderUid': ref.read(firebaseAuthProvider).currentUser?.uid ?? '',
              },
            );

            if (kIsWeb) {
              await storageRef.putData(allBytesList[index], metadata).timeout(const Duration(seconds: 10));
            } else if (index < allImagesList.length) {
              await storageRef.putFile(File(allImagesList[index].path), metadata).timeout(const Duration(seconds: 10));
            }
            final url = await storageRef.getDownloadURL().timeout(const Duration(seconds: 8));
            uploadedImageUrls.add(url);
            uploadedStoragePaths.add(sPath);
          } catch (e) {
            debugPrint('Storage upload for rejected receipt part $partNum skipped or timed out: $e');
            final fallbackUrl = 'data:image/jpeg;base64,${base64Encode(allBytesList[index])}';
            uploadedImageUrls.add(fallbackUrl);
            uploadedStoragePaths.add(sPath);
          }
        }),
      );

      final String primaryImageUrl = uploadedImageUrls.isNotEmpty ? uploadedImageUrls.first : '';
      final String primaryStoragePath = uploadedStoragePaths.isNotEmpty ? uploadedStoragePaths.first : '';

      DocumentSnapshot<Map<String, dynamic>>? existingDoc;
      if (receiptNumber.isNotEmpty) {
        final existing = await firestore
            .collection('receipts_transactions')
            .where('receipt_number', isEqualTo: receiptNumber)
            .where('campaignId', isEqualTo: activeEvent.id)
            .limit(1)
            .get();
        if (existing.docs.isNotEmpty) {
          existingDoc = existing.docs.first;
        }
      }

      final docRef = existingDoc != null ? existingDoc.reference : firestore.collection('receipts_transactions').doc();
      final Map<String, dynamic> transactionData = {
        'app_version': AppVersionConfig.appVersion,
        if (RepDeviceId.value.isNotEmpty) 'rep_device_id': RepDeviceId.value,
        'receipt_number': receiptNumber.isNotEmpty ? receiptNumber : cleanReceiptNumber,
        'is_valid': false,
        'status': 'rejected',
        'rejection_reason': rejectionReason,
        'unfulfilled_conditions': unfulfilledConditions,
        'total_value': totalValue,
        'target_company_total': totalValue,
        'receipt_date': result.receiptDate,
        'extracted_products': result.extractedProducts.map((p) => p.toJson()).toList(),
        'store_chain_detected': result.storeChainDetected,
        ...ReceiptBranchResolver.firestoreFields(
          activeEvent,
          detectedName: result.branchDetected,
          receiptNumber: result.receiptNumber,
        ),
        'is_branch_matched': result.isBranchMatched,
        'is_handwritten': result.isHandwritten,
        'is_thermal_pos_receipt': result.isThermalPosReceipt,
        'is_tampered': result.isTampered,
        'is_screen_capture': result.isScreenCapture,
        'fraud_risk_score': result.fraudRiskScore,
        'fraud_reasons': result.fraudReasons,
        'retail_chain_name': activeEvent.retailChainName,
        if (primaryImageUrl.isNotEmpty) 'image_url': primaryImageUrl,
        if (primaryStoragePath.isNotEmpty) 'storage_path': primaryStoragePath,
        if (uploadedImageUrls.length > 1) 'image_urls': uploadedImageUrls,
        if (uploadedStoragePaths.length > 1) 'storage_paths': uploadedStoragePaths,
        'parts_count': allBytesList.length,
        'promoter_id': ref.read(firebaseAuthProvider).currentUser?.uid,
        'submittedByUid': ref.read(firebaseAuthProvider).currentUser?.uid ?? '',
        'campaignId': activeEvent.id,
        'companySlug': activeEvent.companySlug,
        'targetCompany': activeEvent.targetCompany,
        'analysis_duration_seconds': result.durationSeconds,
        'analysis_duration_ms': result.durationMs,
        'ai_kpi_rating': result.kpiRating,
        'chances_earned': 0,
        'game_played': false,
        'prize_won': null,
      };

      if (existingDoc != null) {
        transactionData['updated_at'] = FieldValue.serverTimestamp();
        transactionData['is_updated_via_ai'] = true;
        await docRef.set(transactionData, SetOptions(merge: true));
      } else {
        transactionData['timestamp'] = FieldValue.serverTimestamp();
        await docRef.set(transactionData);
      }

      // Harvest discovered products asynchronously even if receipt didn't meet spend threshold
      unawaited(ref.read(aiProductDiscoveryServiceProvider).autoHarvestFromReceiptAnalysis(
        companySlug: activeEvent.companySlug,
        companyName: activeEvent.targetCompany,
        retailChain: result.storeChainDetected,
        branch: result.branchDetected,
        receiptNumber: receiptNumber.isNotEmpty ? receiptNumber : cleanReceiptNumber,
        extractedProducts: result.extractedProducts,
      ));
    } catch (e) {
      debugPrint('Error recording rejected receipt transaction to Firestore: $e');
    }
  }
}
