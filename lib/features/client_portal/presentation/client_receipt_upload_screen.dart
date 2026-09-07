import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/services/ai_receipt_service.dart';
import '../../../core/services/ai_product_discovery_service.dart';
import '../../../core/services/company_products_service.dart';
import '../../../core/services/retail_chains_service.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/arabic_numbers_utils.dart';
import '../../../core/utils/slug_utils.dart';
import '../../../core/widgets/switch_point_branding.dart';
import '../../../core/constants/country_currency_config.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/widgets/m3_progress_indicators.dart';
import '../../../core/animations/m3_motion.dart';
import '../../admin/domain/event_model.dart';
import '../../admin/domain/retail_chain_model.dart';
import '../../games/presentation/spin_the_wheel_screen.dart';
import '../../games/presentation/scratch_card_screen.dart';
import '../../games/presentation/direct_gift_claim_screen.dart';
import '../../validation/presentation/widgets/receipt_validation_dialog.dart';
import 'widgets/campaign_gift_balance_dialog.dart';
import 'widgets/campaign_brief_dialog.dart';
import 'widgets/promoter_invoices_dialog.dart';
import '../../../core/widgets/campaign_suspended_screen.dart';


class ClientReceiptUploadScreen extends ConsumerStatefulWidget {
  final String? companySlug;
  final EventModel? event;
  final String? initialEventId;

  const ClientReceiptUploadScreen({
    super.key,
    this.companySlug,
    this.event,
    this.initialEventId,
  });

  @override
  ConsumerState<ClientReceiptUploadScreen> createState() => _ClientReceiptUploadScreenState();
}

class _ClientReceiptUploadScreenState extends ConsumerState<ClientReceiptUploadScreen> {
  EventModel? _activeEvent;
  List<EventModel> _availableCompanyEvents = [];
  bool _isLoadingEvent = true;
  String? _errorMessage;
  StreamSubscription? _eventSubscription;

  final List<XFile> _receiptImages = [];
  int _selectedPreviewIndex = 0;
  bool _isAiLoading = false;
  String _aiPhaseText = '';
  
  final _customerPhoneController = TextEditingController();
  final _customerNameController = TextEditingController();
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.event != null) {
      _activeEvent = widget.event;
      _availableCompanyEvents = [widget.event!];
      _isLoadingEvent = false;
    }
    _subscribeToLiveEvent();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _customerPhoneController.dispose();
    _customerNameController.dispose();
    super.dispose();
  }

  void _resetFormForNextCustomer() {
    _customerNameController.clear();
    _customerPhoneController.clear();
    _receiptImages.clear();
    _selectedPreviewIndex = 0;
    _aiPhaseText = '';
    if (mounted) {
      setState(() {});
    }
  }

  void _subscribeToLiveEvent() {
    _eventSubscription?.cancel();
    final targetEventId = widget.initialEventId;
    final slug = (widget.companySlug ?? '').trim().toLowerCase();

    if (slug.isEmpty && (targetEventId == null || targetEventId.isEmpty)) {
      if (widget.event != null) {
        setState(() {
          _activeEvent = widget.event;
          _availableCompanyEvents = [widget.event!];
          _isLoadingEvent = false;
          _errorMessage = null;
        });
        return;
      }
      setState(() {
        _activeEvent = null;
        _availableCompanyEvents = [];
        _errorMessage = 'رابط الحملة غير متوفر أو غير مكتمل.';
        _isLoadingEvent = false;
      });
      return;
    }

    try {
      final firestore = ref.read(firestoreProvider);

      // ⚡ Server-Side Scoped Query (Pillar 3): Stream only events for this specific company
      Query<Map<String, dynamic>> query = firestore.collection('events');
      if (slug.isNotEmpty) {
        query = query.where('companySlug', isEqualTo: slug);
      }

      _eventSubscription = query.snapshots().listen(
        (snapshot) async {
          if (!mounted) return;
          var docs = snapshot.docs;
          
          // Fallback if scoped query returned empty but targetEventId is provided
          if (docs.isEmpty && targetEventId != null && targetEventId.isNotEmpty) {
            final singleDoc = await firestore.collection('events').doc(targetEventId).get();
            if (singleDoc.exists && mounted) {
              final singleEvent = EventModel.fromFirestore(singleDoc);
              setState(() {
                _availableCompanyEvents = [singleEvent];
                _activeEvent = singleEvent;
                _isLoadingEvent = false;
                _errorMessage = null;
              });
              return;
            }
          }

          if (docs.isEmpty) {
            setState(() {
              _activeEvent = null;
              _availableCompanyEvents = [];
              _errorMessage = 'لا يوجد أي فعاليات مسجلة لهذه الشركة حالياً.';
              _isLoadingEvent = false;
            });
            return;
          }

          // Convert all valid event models
          final events = docs.map((d) {
            try {
              return EventModel.fromFirestore(d);
            } catch (_) {
              return null;
            }
          }).whereType<EventModel>().toList();

          // 1. If targetEventId was provided, find that specific event first
          EventModel? initialMatched;
          if (targetEventId != null && targetEventId.isNotEmpty) {
            initialMatched = events.cast<EventModel?>().firstWhere(
              (e) => e!.id == targetEventId,
              orElse: () => null,
            );
          }

          // 2. Identify target company key/slug
          final effectiveSlug = (initialMatched != null && initialMatched.companySlug.isNotEmpty)
              ? initialMatched.companySlug.trim().toLowerCase()
              : (slug.isNotEmpty ? slug : (initialMatched?.targetCompany.toLowerCase().trim() ?? ''));

          // 3. Find all campaigns for this company (active and promoter active)
          List<EventModel> companyEvents = events.where((e) {
            final eSlug = e.companySlug.trim().toLowerCase();
            final eTargetSlug = SlugUtils.toSlug(e.targetCompany).toLowerCase();
            final eTargetName = e.targetCompany.trim().toLowerCase();
            final matchesCompany = eSlug == effectiveSlug ||
                eTargetSlug == effectiveSlug ||
                eTargetName == effectiveSlug ||
                e.id == effectiveSlug ||
                (effectiveSlug.isNotEmpty && (eTargetName.contains(effectiveSlug) || effectiveSlug.contains(eTargetName)));
            return matchesCompany && e.isActive && e.isPromoterActive;
          }).toList();

          // Sort by creation date descending
          companyEvents.sort((a, b) {
            final aDate = a.createdAt ?? a.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? b.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });

          // Fallback if no promoter-active campaigns found
          if (companyEvents.isEmpty && initialMatched != null) {
            companyEvents = [initialMatched];
          }

          if (companyEvents.isNotEmpty) {
            // Determine active event
            EventModel selected;
            if (_activeEvent != null && companyEvents.any((e) => e.id == _activeEvent!.id)) {
              selected = companyEvents.firstWhere((e) => e.id == _activeEvent!.id);
            } else if (initialMatched != null && companyEvents.any((e) => e.id == initialMatched!.id)) {
              selected = companyEvents.firstWhere((e) => e.id == initialMatched!.id);
            } else {
              selected = companyEvents.first;
            }

            setState(() {
              _availableCompanyEvents = companyEvents;
              _activeEvent = selected;
              _isLoadingEvent = false;
              _errorMessage = null;
            });
          } else {
            setState(() {
              _availableCompanyEvents = [];
              _activeEvent = null;
              _errorMessage = 'لا توجد حملة مفعالة لهذه الشركة حالياً.';
              _isLoadingEvent = false;
            });
          }
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _errorMessage = AppErrorHandler.getFriendlyMessage(
              e,
              defaultMessage: 'حدث خطأ أثناء تحميل بيانات الحملة من الخادم.',
            );
            _isLoadingEvent = false;
          });
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'حدث خطأ أثناء الاتصال بالخادم.';
          _isLoadingEvent = false;
        });
      }
    }
  }

  Future<void> _pickImage(ImageSource source, [bool append = false]) async {
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
        maxWidth: 1400,
        maxHeight: 1400,
        imageQuality: 82,
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
          SnackBar(
            content: Text('خطأ أثناء اختيار الصورة: $e'),
            behavior: SnackBarBehavior.floating,
          ),
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

  void _showImageSourcePicker() {
    final colorScheme = Theme.of(context).colorScheme;
    final strings = AppStrings.of(ref);
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                  strings.isAr ? 'تغيير صورة الفاتورة' : 'Change Receipt Photo',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    fontSize: isMobile ? 15 : 16.5,
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
                    strings.captureReceiptAction,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.camera);
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
                    strings.pickFromGalleryAction,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.gallery);
                  },
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitAndValidateReceipt() async {
    if (_receiptImages.isEmpty) {
      _showPopupMessage('تنبيه', 'يرجى التقاط أو اختيار صورة الفاتورة أولاً.');
      return;
    }

    if (_activeEvent == null) {
      _showPopupMessage('خطأ', 'بيانات الحملة غير متوفرة.');
      return;
    }

    setState(() {
      _isAiLoading = true;
      _aiPhaseText = '1/3 جاري قراءة وتدقيق الفاتورة بالذكاء الاصطناعي...';
    });

    try {
      // 1. Check event active dates
      if (_activeEvent!.isExpired) {
        final endStr = "${_activeEvent!.endDate!.day}/${_activeEvent!.endDate!.month}/${_activeEvent!.endDate!.year}";
        _showPopupMessage(
          'عفواً، الحملة منتهية',
          'انتهت سريان فترة هذه الحملة بتاريخ $endStr. لا يمكن قبول فواتير جديدة.',
          isError: true,
        );
        return;
      }
      if (_activeEvent!.isNotStartedYet) {
        final startStr = "${_activeEvent!.startDate!.day}/${_activeEvent!.startDate!.month}/${_activeEvent!.startDate!.year}";
        _showPopupMessage(
          'عفواً، الحملة لم تبدأ بعد',
          'تبدأ هذه الحملة في تاريخ $startStr. يرجى العودة عند بدء الحملة.',
          isError: true,
        );
        return;
      }

      final firestore = ref.read(firestoreProvider);
      final aiService = ref.read(aiReceiptServiceProvider);
      final productsService = ref.read(companyProductsServiceProvider);

      final primaryImage = _receiptImages.first;
      final bytes = await primaryImage.readAsBytes();
      final mimeType = primaryImage.mimeType ?? 'image/jpeg';

      final List<Uint8List> additionalBytesList = [];
      final List<String> additionalMimesList = [];
      for (int i = 1; i < _receiptImages.length; i++) {
        additionalBytesList.add(await _receiptImages[i].readAsBytes());
        additionalMimesList.add(_receiptImages[i].mimeType ?? 'image/jpeg');
      }

      final allBytesList = [bytes, ...additionalBytesList];
      final allImagesList = List<XFile>.from(_receiptImages);

      // Fetch company product barcodes catalog and branch signatures concurrently in parallel
      List<String> registeredBarcodes = [];
      Map<String, String> catalogBarcodeMap = {};
      List<BranchModel> chainBranches = [];

      try {
        final results = await Future.wait([
          productsService.getProductsForCompany(_activeEvent!.companySlug).catchError((_) => <CompanyProductItem>[]),
          ref.read(retailChainsServiceProvider).getBranchesForEvent(
            retailChainId: _activeEvent!.retailChainId,
            branchIds: _activeEvent!.branchIds,
            branchNames: _activeEvent!.branchNames,
          ).catchError((_) => <BranchModel>[]),
        ]);

        final catalogItems = results[0] as List<CompanyProductItem>;
        chainBranches = results[1] as List<BranchModel>;

        registeredBarcodes = catalogItems.map((e) => "${e.productName} (${e.barcode})").toList();
        catalogBarcodeMap = {
          for (final item in catalogItems)
            if (item.productName.isNotEmpty && item.barcode.isNotEmpty)
              item.productName: item.barcode,
        };
      } catch (_) {}

      // Run Gemini AI analysis
      final result = await aiService.analyzeReceiptImage(
        bytes,
        mimeType,
        additionalImagesBytes: additionalBytesList,
        additionalMimeTypes: additionalMimesList,
        targetCompany: _activeEvent!.targetCompany,
        minimumSpend: _activeEvent!.minimumSpend,
        requiredProducts: _activeEvent!.requiredProducts,
        registeredBarcodes: registeredBarcodes,
        catalogBarcodeMap: catalogBarcodeMap,
        retailChainName: _activeEvent!.retailChainName,
        allowedBranches: _activeEvent!.branchNames,
        isAllBranches: _activeEvent!.isAllBranches,
        registeredBranches: chainBranches,
        startDate: _activeEvent!.startDate,
        endDate: _activeEvent!.endDate,
        customPrompt: _activeEvent!.customPrompt,
        allowMultipleChances: _activeEvent!.allowMultipleChances,
        multiplierBasis: _activeEvent!.multiplierBasis,
        maxChancesPerReceipt: _activeEvent!.maxChancesPerReceipt,
        promotionalRules: _activeEvent!.promotionalRules,
      );

      final previewImgUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
      final List<String> previewUrls = allBytesList
          .map((b) => 'data:image/jpeg;base64,${base64Encode(b)}')
          .toList();

      if (!result.isValid) {
        if (!mounted) return;
        final activeCountry = ref.read(activeCountryProvider);
        final unfulfilledList = result.unfulfilledConditions.isNotEmpty
            ? result.unfulfilledConditions
            : (_activeEvent!.promotionalRules.isNotEmpty
                ? PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
                    result: result,
                    promotionalRules: _activeEvent!.promotionalRules,
                  )
                : [result.message.trim().isNotEmpty ? result.message.trim() : 'الفاتورة غير مطابقة لشروط الحملة']);

        final conditions = buildValidationConditionItems(
          isValid: false,
          message: result.message,
          targetCompanyTotal: result.targetCompanyTotal,
          minimumSpend: _activeEvent!.minimumSpend,
          targetCompany: _activeEvent!.targetCompany,
          currencySymbol: activeCountry.currencySymbol,
          unfulfilledConditions: unfulfilledList,
          isBranchMatched: result.isBranchMatched,
          storeChainDetected: result.storeChainDetected,
          branchDetected: result.branchDetected,
          retailChainName: _activeEvent!.retailChainName,
          allowedBranches: _activeEvent!.branchNames,
          isAllBranches: _activeEvent!.isAllBranches,
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
          activeEvent: _activeEvent!,
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
          requiredMinimum: _activeEvent!.minimumSpend,
          currencySymbol: activeCountry.currencySymbol,
          imageUrl: previewImgUrl,
          imageUrls: previewUrls,
        );
        return;
      }

      final double totalValue = result.targetCompanyTotal;
      if (_activeEvent!.minimumSpend > 0 && totalValue < _activeEvent!.minimumSpend) {
        if (!mounted) return;
        final activeCountry = ref.read(activeCountryProvider);
        final unfulfilledList = [
          'إجمالي مشتريات منتجات ${_activeEvent!.targetCompany} في الفاتورة ($totalValue ${activeCountry.currencySymbol}) أقل من الحد الأدنى المطلوب لدخول السحب (${_activeEvent!.minimumSpend} ${activeCountry.currencySymbol}).'
        ];
        final conditions = [
          ValidationConditionItem(
            title: 'الحد الأدنى لقيمة المشتريات',
            description: unfulfilledList.first,
            icon: Icons.price_check_rounded,
            isMet: false,
            value: '$totalValue / ${_activeEvent!.minimumSpend} ${activeCountry.currencySymbol}',
          ),
        ];

        // Asynchronously persist rejected transaction to Firestore & Storage for audit
        _recordRejectedReceipt(
          result: result,
          allBytesList: allBytesList,
          allImagesList: allImagesList,
          activeEvent: _activeEvent!,
          rejectionReason: 'الحد الأدنى لقيمة المشتريات غير مستوفى ($totalValue / ${_activeEvent!.minimumSpend} ${activeCountry.currencySymbol})',
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
          requiredMinimum: _activeEvent!.minimumSpend,
          currencySymbol: activeCountry.currencySymbol,
          imageUrl: previewImgUrl,
          imageUrls: previewUrls,
        );
        return;
      }

      final receiptNumber = result.receiptNumber.trim();

      // Strict Zero-Fallback Rule: If campaign has promotional rules and none are met, reject receipt
      final matchedRulesList = PromotionalRuleMatcher.matchAllWithMultipliers(
        result: result,
        promotionalRules: _activeEvent!.promotionalRules,
        allowCampaignMultipliers: _activeEvent!.allowMultipleChances,
      );

      if (_activeEvent!.promotionalRules.isNotEmpty && matchedRulesList.isEmpty) {
        if (!mounted) return;
        final activeCountry = ref.read(activeCountryProvider);
        final unfulfilledPromoList = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
          result: result,
          promotionalRules: _activeEvent!.promotionalRules,
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
          activeEvent: _activeEvent!,
          rejectionReason: unfulfilledPromoList.isNotEmpty
              ? unfulfilledPromoList.join(' • ')
              : 'شروط العروض الترويجية غير مستوفاة في الفاتورة',
          unfulfilledConditions: unfulfilledPromoList,
          totalValue: totalValue,
        );

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
          requiredMinimum: _activeEvent!.minimumSpend,
          currencySymbol: activeCountry.currencySymbol,
          imageUrl: previewImgUrl,
          imageUrls: previewUrls,
        );
        _resetFormForNextCustomer();
        return;
      }

      // Check for existing receipt in this specific campaign to update/upsert
      DocumentSnapshot<Map<String, dynamic>>? existingDoc;
      if (receiptNumber.isNotEmpty) {
        final existing = await firestore
            .collection('receipts_transactions')
            .where('receipt_number', isEqualTo: receiptNumber)
            .where('campaignId', isEqualTo: _activeEvent!.id)
            .limit(1)
            .get();

        if (existing.docs.isNotEmpty) {
          existingDoc = existing.docs.first;
        }
      }

      // 2. Upload image to Firebase Storage named by Receipt Number and Campaign ID
      setState(() {
        _aiPhaseText = '2/3 جاري حفظ صورة الفاتورة في التخزين السحابي...';
      });

      final cleanReceiptNumber = (receiptNumber.isNotEmpty ? receiptNumber : "INV_${DateTime.now().millisecondsSinceEpoch}")
          .replaceAll(RegExp(r'[/\\?%*:|"<>]'), '_');

      final List<String> uploadedImageUrls = [];
      final List<String> uploadedStoragePaths = [];

      await Future.wait(
        List.generate(allBytesList.length, (index) async {
          final partNum = index + 1;
          final sPath = allBytesList.length == 1
              ? 'receipts/${_activeEvent!.companySlug}/${_activeEvent!.id}/$cleanReceiptNumber.jpg'
              : 'receipts/${_activeEvent!.companySlug}/${_activeEvent!.id}/${cleanReceiptNumber}_part$partNum.jpg';
          try {
            final storage = ref.read(firebaseStorageProvider);
            final storageRef = storage.ref().child(sPath);
            final metadata = SettableMetadata(
              contentType: 'image/jpeg',
              customMetadata: {
                'receiptNumber': receiptNumber,
                'companySlug': _activeEvent!.companySlug,
                'targetCompany': _activeEvent!.targetCompany,
                'totalValue': totalValue.toString(),
                'partIndex': '$partNum',
                'totalParts': '${allBytesList.length}',
                'uploadedAt': DateTime.now().toIso8601String(),
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
            debugPrint('Firebase Storage upload notice for part $partNum: $e');
            if (allBytesList[index].lengthInBytes <= 400 * 1024) {
              uploadedImageUrls.add('data:image/jpeg;base64,${base64Encode(allBytesList[index])}');
            } else {
              uploadedImageUrls.add('');
            }
            uploadedStoragePaths.add(sPath);
          }
        }),
      );

      final String primaryImageUrl = uploadedImageUrls.isNotEmpty ? uploadedImageUrls.first : '';
      final String primaryStoragePath = uploadedStoragePaths.isNotEmpty ? uploadedStoragePaths.first : '';

      // 3. Store transaction in Firestore with Duration & KPI metrics (Upsert)
      setState(() {
        _aiPhaseText = '3/3 جاري حفظ المعاملة وتجهيز الجائزة...';
      });

      final int calculatedChances = result.chancesEarned > 0 ? result.chancesEarned : 1;
      final DocumentReference<Map<String, dynamic>> transactionRef =
          existingDoc != null ? existingDoc.reference : firestore.collection('receipts_transactions').doc();
      final bool isExistingRecord = existingDoc != null;
      final existingData = existingDoc?.data() ?? {};
      final bool wasGamePlayed = existingData['game_played'] == true;

      final Map<String, dynamic> transactionData = {
        'receipt_number': receiptNumber,
        'is_valid': true,
        'status': 'accepted',
        'rejection_reason': null,
        'unfulfilled_conditions': const [],
        'total_value': totalValue,
        'target_company_total': totalValue,
        'receipt_date': result.receiptDate,
        'extracted_products': result.extractedProducts.map((p) => p.toJson()).toList(),
        'store_chain_detected': result.storeChainDetected,
        'branch_detected': result.branchDetected,
        'is_branch_matched': result.isBranchMatched,
        'is_handwritten': result.isHandwritten,
        'is_thermal_pos_receipt': result.isThermalPosReceipt,
        'is_tampered': result.isTampered,
        'is_screen_capture': result.isScreenCapture,
        'fraud_risk_score': result.fraudRiskScore,
        'fraud_reasons': result.fraudReasons,
        'retail_chain_name': _activeEvent!.retailChainName,
        if (primaryImageUrl.isNotEmpty) 'image_url': primaryImageUrl,
        if (primaryStoragePath.isNotEmpty) 'storage_path': primaryStoragePath,
        if (uploadedImageUrls.length > 1) 'image_urls': uploadedImageUrls,
        if (uploadedStoragePaths.length > 1) 'storage_paths': uploadedStoragePaths,
        'parts_count': allBytesList.length,
        'campaignId': _activeEvent!.id,
        'companySlug': _activeEvent!.companySlug,
        'targetCompany': _activeEvent!.targetCompany,
        'customerPhone': _customerPhoneController.text.toEnglishDigits().trim(),
        'customerName': _customerNameController.text.trim(),
        'aiMessage': result.message,
        'analysis_duration_seconds': result.durationSeconds,
        'analysis_duration_ms': result.durationMs,
        'ai_kpi_rating': result.kpiRating,
        'chances_earned': calculatedChances,
        'allow_multiple_chances': _activeEvent!.allowMultipleChances,
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
        companySlug: _activeEvent!.companySlug,
        companyName: _activeEvent!.targetCompany,
        retailChain: result.storeChainDetected,
        branch: result.branchDetected,
        receiptNumber: receiptNumber,
        extractedProducts: result.extractedProducts,
      ));

      if (!mounted) return;

      if (isExistingRecord && wasGamePlayed) {
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
          requiredMinimum: _activeEvent!.minimumSpend,
          currencySymbol: activeCountry.currencySymbol,
          imageUrl: primaryImageUrl.isNotEmpty ? primaryImageUrl : previewImgUrl,
          imageUrls: previewUrls,
          isDuplicate: true,
        );
        _resetFormForNextCustomer();
        return;
      }

      // Reset image preview immediately
      setState(() {
        _receiptImages.clear();
        _selectedPreviewIndex = 0;
      });

      // Route customer to prize game based on event settings or total purchase value
      final currentEvent = _activeEvent ?? widget.event;
      final currentEventId = currentEvent?.id ?? '';
      final prizeNames = currentEvent?.allocatedPrizes
          .where((p) => p.remainingQuantity > 0)
          .map((p) => p.name)
          .toList() ?? <String>[];

      // Composite promotional bundle from matched rules evaluated earlier
      final compositeBundle = CompositePromotionalBundle.fromMatchedRules(
        matchedRulesList,
        fallbackTitle: result.matchedRewardValue.trim().isNotEmpty
            ? result.matchedRewardValue.trim()
            : (prizeNames.isNotEmpty ? prizeNames.first : 'هدية ترويجية مميزة'),
      );
      final totalChances = math.max(
        result.chancesEarned > 0 ? result.chancesEarned : 1,
        compositeBundle.totalChances,
      );

      final gameType = currentEvent?.gameType ?? (totalValue >= 500 ? 'scratchCard' : 'spinTheWheel');

      if (gameType == 'directGift' || gameType == 'direct_gift') {
        final designatedPrizeObj = (currentEvent?.availablePrizes.isNotEmpty ?? false)
            ? currentEvent!.availablePrizes.first
            : ((currentEvent?.allocatedPrizes.isNotEmpty ?? false)
                ? currentEvent!.allocatedPrizes.first
                : null);

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

        // Smart branch ID resolution matching AI-detected branch name with campaign branches
        String? resolvedBranchId;
        if (currentEvent != null && currentEvent.branchIds.isNotEmpty) {
          final detectedBranchClean = result.branchDetected.trim().toLowerCase().replaceAll(RegExp(r'[^\w\s\d]'), ' ');
          if (detectedBranchClean.isNotEmpty) {
            for (int i = 0; i < currentEvent.branchNames.length; i++) {
              final bName = currentEvent.branchNames[i].trim().toLowerCase().replaceAll(RegExp(r'[^\w\s\d]'), ' ');
              if (bName.isNotEmpty && (bName.contains(detectedBranchClean) || detectedBranchClean.contains(bName))) {
                if (i < currentEvent.branchIds.length) {
                  resolvedBranchId = currentEvent.branchIds[i];
                  break;
                }
              }
            }
            if (resolvedBranchId == null) {
              for (final p in currentEvent.allocatedPrizes) {
                final pBranchName = p.branchName.trim().toLowerCase().replaceAll(RegExp(r'[^\w\s\d]'), ' ');
                if (pBranchName.isNotEmpty && (pBranchName.contains(detectedBranchClean) || detectedBranchClean.contains(pBranchName))) {
                  resolvedBranchId = p.branchId;
                  break;
                }
              }
            }
          }
          resolvedBranchId ??= currentEvent.branchIds.first;
        }

        final promoQuantity = resolvedLinkedGifts.isNotEmpty
            ? 1
            : ((currentEvent?.allowMultipleChances ?? false) ? totalChances : 1);
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DirectGiftClaimScreen(
              transactionId: transactionRef.id,
              eventId: currentEventId,
              prizeName: designatedPrize,
              quantity: promoQuantity,
              branchId: resolvedBranchId,
              unitValue: resolvedUnitValue,
              isVoucher: resolvedIsVoucher,
              linkedGifts: resolvedLinkedGifts,
              requireVoucherSerials: currentEvent?.requireVoucherSerials ?? false,
            ),
          ),
        );
        _resetFormForNextCustomer();
      } else if (gameType == 'scratch' || gameType == 'scratchCard' || (gameType.isEmpty && totalValue >= 500)) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ScratchCardScreen(
              transactionId: transactionRef.id,
              eventId: currentEventId,
              prizes: prizeNames,
              totalChances: totalChances,
            ),
          ),
        );
        _resetFormForNextCustomer();
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => SpinTheWheelScreen(
              transactionId: transactionRef.id,
              eventId: currentEventId,
              prizes: prizeNames,
              totalChances: totalChances,
            ),
          ),
        );
        _resetFormForNextCustomer();
      }
    } catch (e, stack) {
      debugPrint('Receipt processing error: $e\n$stack');
      if (mounted) {
        _showPopupMessage(
          'تنبيه النظام',
          AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء معالجة وإرسال الفاتورة.'),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAiLoading = false;
          _aiPhaseText = '';
        });
      }
    }
  }

  void _showPopupMessage(String title, String message, {bool isError = false}) {
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
    final isAr = ref.isArabic;
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isMobile = screenWidth < 600;
    final isTablet = screenWidth >= 600 && screenWidth < 960;

    if (_isLoadingEvent) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                strings.loadingCampaignData,
                style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null || (_activeEvent != null && (!_activeEvent!.isActive || !_activeEvent!.isPromoterActive))) {
      return CampaignSuspendedScreen(
        portalType: SuspendedPortalType.promoter,
        event: _activeEvent,
        companySlug: widget.companySlug,
        companyName: _activeEvent?.targetCompany,
        onRefresh: () {
          setState(() {
            _isLoadingEvent = true;
            _errorMessage = null;
          });
          _subscribeToLiveEvent();
        },
      );
    }

    final event = _activeEvent!;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: SwitchPointHeader(
        subtitle: '${strings.clientPortalSubtitle} — ${event.targetCompany}',
        companyLogoUrl: event.companyLogoUrl,
        customActions: [
          // 1. Campaign Concept & Offer Rules Action Button (Brief & Conditions)
          Tooltip(
            message: strings.promoterCampaignBriefTooltip,
            waitDuration: const Duration(milliseconds: 400),
            child: IconButton.filledTonal(
              icon: Icon(
                Icons.campaign_rounded,
                size: isMobile ? 18 : 20,
                color: colorScheme.primary,
              ),
              padding: EdgeInsets.all(isMobile ? 6 : 8),
              constraints: isMobile ? const BoxConstraints() : null,
              visualDensity: isMobile ? VisualDensity.compact : VisualDensity.standard,
              onPressed: () {
                CampaignBriefDialog.show(context, event);
              },
            ),
          ),
          SizedBox(width: isMobile ? 2 : 6),

          // 2. Remaining Gift Inventory & Branch Balance Action Button
          Tooltip(
            message: strings.promoterGiftsBalanceTooltip,
            waitDuration: const Duration(milliseconds: 400),
            child: IconButton.filledTonal(
              icon: Icon(
                Icons.card_giftcard_rounded,
                size: isMobile ? 18 : 20,
                color: colorScheme.primary,
              ),
              padding: EdgeInsets.all(isMobile ? 6 : 8),
              constraints: isMobile ? const BoxConstraints() : null,
              visualDensity: isMobile ? VisualDensity.compact : VisualDensity.standard,
              onPressed: () {
                CampaignGiftBalanceDialog.show(context, event);
              },
            ),
          ),
          SizedBox(width: isMobile ? 2 : 6),

          // 3. Invoices Log & Branch History Reference Action Button
          Tooltip(
            message: strings.promoterInvoicesLogTooltip,
            waitDuration: const Duration(milliseconds: 400),
            child: IconButton.filledTonal(
              icon: Icon(
                Icons.receipt_long_rounded,
                size: isMobile ? 18 : 20,
                color: colorScheme.primary,
              ),
              padding: EdgeInsets.all(isMobile ? 6 : 8),
              constraints: isMobile ? const BoxConstraints() : null,
              visualDensity: isMobile ? VisualDensity.compact : VisualDensity.standard,
              onPressed: () {
                PromoterInvoicesDialog.show(context, event);
              },
            ),
          ),
          SizedBox(width: isMobile ? 2 : 6),
        ],
      ),

      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: isMobile ? 12 : (isTablet ? 20 : 28),
                right: isMobile ? 12 : (isTablet ? 20 : 28),
                top: isMobile ? 10 : 24,
                bottom: isMobile ? 48 : 32,
              ),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Card(
                    elevation: isMobile ? 0 : 2,
                    color: isMobile ? colorScheme.surfaceContainerLowest : colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(isMobile ? 20 : 28),
                      side: BorderSide(
                        color: colorScheme.outlineVariant.withValues(alpha: isMobile ? 0.6 : 0.4),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(isMobile ? 16 : 26),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. Header Banner (M3 Elevated Hero)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 16 : 24,
                              vertical: isMobile ? 18 : 24,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  colorScheme.primary,
                                  colorScheme.primary.withValues(alpha: 0.88),
                                  colorScheme.tertiary,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(isMobile ? 18 : 22),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.primary.withValues(alpha: 0.28),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                if (event.companyLogoUrl.isNotEmpty) ...[
                                  Container(
                                    width: isMobile ? 64 : 76,
                                    height: isMobile ? 64 : 76,
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.18),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.9),
                                        width: 2.5,
                                      ),
                                    ),
                                    child: ClipOval(
                                      child: Image.network(
                                        event.companyLogoUrl,
                                        fit: BoxFit.contain,
                                        errorBuilder: (context, error, stackTrace) => Icon(
                                          Icons.business_rounded,
                                          size: isMobile ? 32 : 38,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                Text(
                                  event.welcomeTitle.isNotEmpty ? event.welcomeTitle : strings.campaignOffersTitle,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.cairo(
                                    color: colorScheme.onPrimary,
                                    fontSize: isMobile ? 19 : 23,
                                    fontWeight: FontWeight.bold,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  event.welcomeMessage.isNotEmpty
                                      ? event.welcomeMessage
                                      : strings.uploadReceiptInstruction,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.cairo(
                                    color: colorScheme.onPrimary.withValues(alpha: 0.92),
                                    fontSize: isMobile ? 12.5 : 14,
                                    height: 1.4,
                                  ),
                                ),
                                if (event.minimumSpend > 0) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.22),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.35),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.local_offer_rounded,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            '${strings.minSpendPrefix} ${event.minimumSpend} ${activeCountry.currencySymbolFor(strings.languageCode)}',
                                            style: GoogleFonts.cairo(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: isMobile ? 11.5 : 12.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          // 1.5. Dynamic Campaign Selector (Active when company has multiple active campaigns)
                          if (_availableCompanyEvents.length > 1) ...[
                            SizedBox(height: isMobile ? 14 : 18),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isMobile ? 12 : 16,
                                vertical: isMobile ? 10 : 12,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: colorScheme.primary.withValues(alpha: 0.35),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(5),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primary.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          Icons.layers_rounded,
                                          size: 16,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          isAr ? 'اختر الحملة / العرض المستهدف للفاتورة:' : 'Select Target Offer / Campaign:',
                                          style: GoogleFonts.cairo(
                                            fontSize: isMobile ? 12 : 13,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '${_availableCompanyEvents.length} ${isAr ? 'عروض متاحة' : 'Offers'}',
                                          style: GoogleFonts.cairo(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    initialValue: _activeEvent?.id,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      filled: true,
                                      fillColor: colorScheme.surface,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: colorScheme.outlineVariant),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: colorScheme.primary, width: 2),
                                      ),
                                    ),
                                    items: _availableCompanyEvents.map((ev) {
                                      final minSpendStr = ev.minimumSpend > 0
                                          ? ' (${isAr ? 'حد أدنى' : 'Min'}: ${ev.minimumSpend.toInt()} ${activeCountry.currencySymbolFor(strings.languageCode)})'
                                          : '';
                                      return DropdownMenuItem<String>(
                                        value: ev.id,
                                        child: Row(
                                          children: [
                                            Icon(
                                              ev.gameType == 'wheel' ? Icons.donut_large_rounded : Icons.card_giftcard_rounded,
                                              size: 16,
                                              color: colorScheme.primary,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '${ev.eventName}$minSpendStr',
                                                style: GoogleFonts.cairo(
                                                  fontSize: isMobile ? 12 : 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: colorScheme.onSurface,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (selectedId) {
                                      if (selectedId != null && selectedId != _activeEvent?.id) {
                                        final newActive = _availableCompanyEvents.firstWhere((e) => e.id == selectedId);
                                        setState(() {
                                          _activeEvent = newActive;
                                          _resetFormForNextCustomer();
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],

                          SizedBox(height: isMobile ? 18 : 24),

                          // 2. Customer Info Inputs (M3 Filled TextFields)
                          TextField(
                            controller: _customerNameController,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setState(() {}),
                            style: GoogleFonts.cairo(fontSize: isMobile ? 14 : 15),
                            decoration: InputDecoration(
                              labelText: strings.customerNameOptional,
                              labelStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                              prefixIcon: Icon(
                                Icons.person_outline_rounded,
                                color: colorScheme.primary,
                                size: isMobile ? 22 : 24,
                              ),
                              suffixIcon: _customerNameController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 20),
                                      tooltip: isAr ? 'مسح اسم العميل' : 'Clear name',
                                      onPressed: () {
                                        _customerNameController.clear();
                                        setState(() {});
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: isMobile ? 14 : 16,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: colorScheme.outlineVariant),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: colorScheme.primary, width: 2),
                              ),
                            ),
                          ),

                          SizedBox(height: isMobile ? 12 : 16),

                          TextField(
                            controller: _customerPhoneController,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.done,
                            onChanged: (_) => setState(() {}),
                            inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                            style: GoogleFonts.cairo(fontSize: isMobile ? 14 : 15),
                            decoration: InputDecoration(
                              labelText: strings.customerPhoneLabel,
                              labelStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                              prefixIcon: Icon(
                                Icons.phone_outlined,
                                color: colorScheme.primary,
                                size: isMobile ? 22 : 24,
                              ),
                              suffixIcon: _customerPhoneController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 20),
                                      tooltip: isAr ? 'مسح رقم الهاتف' : 'Clear phone',
                                      onPressed: () {
                                        _customerPhoneController.clear();
                                        setState(() {});
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: isMobile ? 14 : 16,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: colorScheme.outlineVariant),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: colorScheme.primary, width: 2),
                              ),
                            ),
                          ),

                          SizedBox(height: isMobile ? 18 : 24),

                          // 3. Receipt Upload Dropzone (M3 Interactive Card)
                          Container(
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLowest,
                              border: Border.all(
                                color: _receiptImages.isNotEmpty
                                    ? colorScheme.primary
                                    : colorScheme.outlineVariant.withValues(alpha: 0.7),
                                width: _receiptImages.isNotEmpty ? 2.0 : 1.2,
                              ),
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.shadow.withValues(alpha: 0.04),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: _receiptImages.isEmpty
                                ? Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isMobile ? 18 : 28,
                                      vertical: isMobile ? 24 : 32,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(isMobile ? 14 : 18),
                                          decoration: BoxDecoration(
                                            color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.receipt_long_rounded,
                                            size: isMobile ? 36 : 44,
                                            color: colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        Text(
                                          strings.receiptAuditSubtitle,
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.cairo(
                                            fontSize: isMobile ? 14 : 15.5,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onSurface,
                                            height: 1.3,
                                          ),
                                        ),
                                        const SizedBox(height: 22),
                                        // 1. Primary Action: Camera Capture
                                        SizedBox(
                                          width: double.infinity,
                                          child: AnimatedPressable(
                                            onTap: () => _pickImage(ImageSource.camera),
                                            child: FilledButton.icon(
                                              onPressed: () => _pickImage(ImageSource.camera),
                                              icon: const Icon(Icons.camera_alt_rounded, size: 22),
                                              label: Text(
                                                strings.captureReceiptAction,
                                                textAlign: TextAlign.center,
                                                style: GoogleFonts.cairo(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: isMobile ? 14.5 : 16,
                                                ),
                                              ),
                                              style: FilledButton.styleFrom(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 20,
                                                  vertical: isMobile ? 15 : 17,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(18),
                                                ),
                                                elevation: 2,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        // 2. Secondary Action: Pick from Gallery / Files
                                        SizedBox(
                                          width: double.infinity,
                                          child: AnimatedPressable(
                                            onTap: () => _pickImage(ImageSource.gallery),
                                            child: FilledButton.tonalIcon(
                                              onPressed: () => _pickImage(ImageSource.gallery),
                                              icon: const Icon(Icons.photo_library_rounded, size: 22),
                                              label: Text(
                                                strings.pickFromGalleryAction,
                                                textAlign: TextAlign.center,
                                                style: GoogleFonts.cairo(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: isMobile ? 14.5 : 16,
                                                ),
                                              ),
                                              style: FilledButton.styleFrom(
                                                backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
                                                foregroundColor: colorScheme.primary,
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 20,
                                                  vertical: isMobile ? 15 : 17,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(18),
                                                  side: BorderSide(
                                                    color: colorScheme.primary.withValues(alpha: 0.25),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        // Long Receipt Tip
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
                                  )
                                : SizedBox(
                                    height: isMobile ? 300 : 360,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(18),
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
                                        // Top part indicator badge and remove button
                                        Positioned(
                                          top: 10,
                                          left: 10,
                                          right: 10,
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withValues(alpha: 0.75),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons.layers_rounded,
                                                      size: 14,
                                                      color: Color(0xFF818CF8),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      strings.isAr
                                                          ? 'جزء ${_selectedPreviewIndex + 1} من ${_receiptImages.length}'
                                                          : 'Part ${_selectedPreviewIndex + 1} of ${_receiptImages.length}',
                                                      style: GoogleFonts.cairo(
                                                        color: Colors.white,
                                                        fontSize: 11.5,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Tooltip(
                                                message: strings.deletePartTooltip,
                                                waitDuration: const Duration(milliseconds: 400),
                                                child: IconButton.filled(
                                                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                                                  style: IconButton.styleFrom(
                                                    backgroundColor: colorScheme.error,
                                                    padding: const EdgeInsets.all(6),
                                                  ),
                                                  onPressed: () => _removePart(_selectedPreviewIndex),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Bottom retake button
                                        Positioned(
                                          bottom: 10,
                                          child: InkWell(
                                            onTap: _showImageSourcePicker,
                                            borderRadius: BorderRadius.circular(20),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: colorScheme.surface.withValues(alpha: 0.9),
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: colorScheme.primary.withValues(alpha: 0.4),
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withValues(alpha: 0.15),
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.cached_rounded, size: 16, color: colorScheme.primary),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    strings.isAr ? 'إعادة التقاط / تغيير' : 'Retake / Change',
                                                    style: GoogleFonts.cairo(
                                                      fontSize: 11.5,
                                                      fontWeight: FontWeight.bold,
                                                      color: colorScheme.primary,
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
                          ),

                          // Multi-part thumbnails strip & Add next part controls
                          if (_receiptImages.isNotEmpty) ...[
                            const SizedBox(height: 12),
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

                            // Add next part button & Clear all action
                            Row(
                              children: [
                                if (_receiptImages.length < 4)
                                  Expanded(
                                    child: FilledButton.tonalIcon(
                                      onPressed: _showAddPartModal,
                                      icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                                      label: Text(
                                        strings.addNextReceiptPartBtn,
                                        style: GoogleFonts.cairo(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (_receiptImages.length < 4) const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: _clearAllParts,
                                  icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                                  label: Text(
                                    strings.isAr ? 'مسح الكل' : 'Clear All',
                                    style: GoogleFonts.cairo(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.error,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: colorScheme.error,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          // 4. M3 Action Button & Progress Tracker
                          if (_receiptImages.isNotEmpty) ...[
                            SizedBox(height: isMobile ? 18 : 24),
                            if (_isAiLoading) ...[
                              Text(
                                _aiPhaseText,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold,
                                  fontSize: isMobile ? 12.5 : 13.5,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const M3LinearProgress(height: 6.0),
                              const SizedBox(height: 16),
                            ],
                            M3ActionButton(
                              label: _isAiLoading
                                  ? strings.auditingProgressText
                                  : (_receiptImages.length > 1
                                      ? strings.analyzeMultiPartsBtn(_receiptImages.length)
                                      : strings.auditReceiptActionBtn),
                              icon: Icons.auto_awesome_rounded,
                              isLoading: _isAiLoading,
                              variant: M3ButtonVariant.filled,
                              height: isMobile ? 50 : 54,
                              onPressed: _isAiLoading ? null : _submitAndValidateReceipt,
                            ),
                          ],

                          // 5. Terms & Conditions (M3 Card Note)
                          if (event.termsAndConditions.isNotEmpty) ...[
                            SizedBox(height: isMobile ? 18 : 24),
                            Container(
                              padding: EdgeInsets.all(isMobile ? 14 : 18),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.gavel_rounded,
                                        size: 18,
                                        color: colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${strings.participationTermsTitle}:',
                                          style: GoogleFonts.cairo(
                                            fontWeight: FontWeight.bold,
                                            fontSize: isMobile ? 12.5 : 13.5,
                                            color: colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    event.termsAndConditions,
                                    style: GoogleFonts.cairo(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: isMobile ? 11.5 : 12.5,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
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
          ),
          if (!isMobile) const SwitchPointFooter(),
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
        'branch_detected': result.branchDetected,
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
        'customerPhone': _customerPhoneController.text.toEnglishDigits().trim(),
        'customerName': _customerNameController.text.trim(),
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
        receiptNumber: receiptNumber,
        extractedProducts: result.extractedProducts,
      ));
    } catch (e) {
      debugPrint('Error recording rejected receipt transaction to Firestore: $e');
    }
  }
}
