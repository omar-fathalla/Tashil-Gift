import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/services/ai_receipt_service.dart';
import '../../../core/services/company_products_service.dart';
import '../../../core/services/retail_chains_service.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/arabic_numbers_utils.dart';
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
  bool _isLoadingEvent = true;
  String? _errorMessage;
  StreamSubscription? _eventSubscription;

  XFile? _receiptImage;
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
    _receiptImage = null;
    _aiPhaseText = '';
    if (mounted) {
      setState(() {});
    }
  }

  void _subscribeToLiveEvent() {
    _eventSubscription?.cancel();
    try {
      final firestore = ref.read(firestoreProvider);
      final targetEventId = widget.initialEventId ?? widget.event?.id;
      final slug = (widget.companySlug ?? widget.event?.companySlug ?? 'almarai').trim().toLowerCase();

      // 1. If explicit eventId is provided, listen directly to that specific event document
      if (targetEventId != null && targetEventId.isNotEmpty) {
        _eventSubscription = firestore
            .collection('events')
            .doc(targetEventId)
            .snapshots()
            .listen(
          (doc) {
            if (!mounted) return;
            if (doc.exists && doc.data() != null) {
              setState(() {
                _activeEvent = EventModel.fromFirestore(doc);
                _isLoadingEvent = false;
                _errorMessage = null;
              });
            } else {
              _fallbackToSlugStream(slug);
            }
          },
          onError: (e) {
            if (!mounted) return;
            _fallbackToSlugStream(slug);
          },
        );
        return;
      }

      _fallbackToSlugStream(slug);
    } catch (_) {}
  }

  void _fallbackToSlugStream(String slug) {
    _eventSubscription?.cancel();
    try {
      final firestore = ref.read(firestoreProvider);

      _eventSubscription = firestore.collection('events').snapshots().listen(
        (snapshot) {
          if (!mounted) return;
          final docs = snapshot.docs;
          if (docs.isEmpty) {
            setState(() {
              _activeEvent = null;
              _errorMessage = 'لا يوجد أي حملات مسجلة في النظام حالياً.';
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

        // 1. Try match by document ID == slug
        EventModel? matched = events.cast<EventModel?>().firstWhere(
          (e) => e!.id == slug,
          orElse: () => null,
        );

        // 2. Try match by companySlug == slug
        if (matched == null) {
          final slugMatches = events.where((e) => e.companySlug.trim().toLowerCase() == slug).toList();
          if (slugMatches.isNotEmpty) {
            slugMatches.sort((a, b) {
              if (a.isActive != b.isActive) {
                return a.isActive ? -1 : 1;
              }
              final aDate = a.createdAt ?? a.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bDate = b.createdAt ?? b.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bDate.compareTo(aDate);
            });
            matched = slugMatches.first;
          }
        }

        // 3. Try match by targetCompany contains or equal to slug
        if (matched == null) {
          final companyMatches = events.where((e) =>
            e.targetCompany.trim().toLowerCase() == slug ||
            e.targetCompany.trim().toLowerCase().contains(slug) ||
            slug.contains(e.targetCompany.trim().toLowerCase())
          ).toList();
          if (companyMatches.isNotEmpty) {
            companyMatches.sort((a, b) {
              if (a.isActive != b.isActive) {
                return a.isActive ? -1 : 1;
              }
              final aDate = a.createdAt ?? a.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bDate = b.createdAt ?? b.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bDate.compareTo(aDate);
            });
            matched = companyMatches.first;
          }
        }

        // 4. Fallback to any active event if none found
        if (matched == null) {
          final activeList = events.where((e) => e.isActive).toList();
          if (activeList.isNotEmpty) {
            activeList.sort((a, b) {
              final aDate = a.createdAt ?? a.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bDate = b.createdAt ?? b.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bDate.compareTo(aDate);
            });
            matched = activeList.first;
          }
        }

        if (matched != null) {
          setState(() {
            _activeEvent = matched;
            _isLoadingEvent = false;
            _errorMessage = null;
          });
        } else {
          setState(() {
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
    } catch (_) {}
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
      );
      if (pickedFile != null) {
        setState(() {
          _receiptImage = pickedFile;
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

  Future<void> _submitAndValidateReceipt() async {
    if (_receiptImage == null) {
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

      final bytes = await _receiptImage!.readAsBytes();
      final mimeType = _receiptImage!.mimeType ?? 'image/jpeg';

      // Fetch company product barcodes catalog if available
      final catalogItems = await productsService.getProductsForCompany(_activeEvent!.companySlug);
      final registeredBarcodes = catalogItems.map((e) => "${e.productName} (${e.barcode})").toList();
      final catalogBarcodeMap = {
        for (final item in catalogItems)
          if (item.productName.isNotEmpty && item.barcode.isNotEmpty)
            item.productName: item.barcode,
      };

      // Fetch retail chain branch signatures if available for deterministic anti-fraud matching
      List<BranchModel> chainBranches = [];
      try {
        chainBranches = await ref
            .read(retailChainsServiceProvider)
            .getBranchesForEvent(
              retailChainId: _activeEvent!.retailChainId,
              branchIds: _activeEvent!.branchIds,
              branchNames: _activeEvent!.branchNames,
            );
      } catch (_) {}

      // Run Gemini AI analysis
      final result = await aiService.analyzeReceiptImage(
        bytes,
        mimeType,
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

      if (!result.isValid) {
        if (!mounted) return;
        final activeCountry = ref.read(activeCountryProvider);
        final conditions = buildValidationConditionItems(
          isValid: false,
          message: result.message,
          targetCompanyTotal: result.targetCompanyTotal,
          minimumSpend: _activeEvent!.minimumSpend,
          targetCompany: _activeEvent!.targetCompany,
          currencySymbol: activeCountry.currencySymbol,
          unfulfilledConditions: result.unfulfilledConditions,
          isBranchMatched: result.isBranchMatched,
          storeChainDetected: result.storeChainDetected,
          branchDetected: result.branchDetected,
          retailChainName: _activeEvent!.retailChainName,
          allowedBranches: _activeEvent!.branchNames,
          isAllBranches: _activeEvent!.isAllBranches,
          receiptDate: result.receiptDate,
          hasTargetProducts: result.extractedProducts.any((p) => p.isTargetCompany),
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
        );
        return;
      }

      final double totalValue = result.targetCompanyTotal;
      if (_activeEvent!.minimumSpend > 0 && totalValue < _activeEvent!.minimumSpend) {
        if (!mounted) return;
        final activeCountry = ref.read(activeCountryProvider);
        final conditions = [
          ValidationConditionItem(
            title: 'الحد الأدنى لقيمة المشتريات',
            description: 'إجمالي مشتريات منتجات ${_activeEvent!.targetCompany} في الفاتورة ($totalValue ${activeCountry.currencySymbol}) أقل من الحد الأدنى المطلوب لدخول السحب (${_activeEvent!.minimumSpend} ${activeCountry.currencySymbol}).',
            icon: Icons.price_check_rounded,
            isMet: false,
            value: '$totalValue / ${_activeEvent!.minimumSpend} ${activeCountry.currencySymbol}',
          ),
        ];

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
        );
        return;
      }

      final receiptNumber = result.receiptNumber.trim();

      // Check for existing receipt to update/upsert
      DocumentSnapshot<Map<String, dynamic>>? existingDoc;
      if (receiptNumber.isNotEmpty) {
        final existing = await firestore
            .collection('receipts_transactions')
            .where('receipt_number', isEqualTo: receiptNumber)
            .limit(1)
            .get();

        if (existing.docs.isNotEmpty) {
          existingDoc = existing.docs.first;
        }
      }

      // 2. Upload image to Firebase Storage named by Receipt Number
      setState(() {
        _aiPhaseText = '2/3 جاري حفظ صورة الفاتورة في التخزين السحابي...';
      });

      String imageUrl = '';
      final cleanReceiptNumber = (receiptNumber.isNotEmpty ? receiptNumber : "INV_${DateTime.now().millisecondsSinceEpoch}")
          .replaceAll(RegExp(r'[/\\?%*:|"<>]'), '_');
      
      final storagePath = 'receipts/${_activeEvent!.companySlug}/$cleanReceiptNumber.jpg';

      try {
        final storage = ref.read(firebaseStorageProvider);
        final storageRef = storage.ref().child(storagePath);
        final metadata = SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'receiptNumber': receiptNumber,
            'companySlug': _activeEvent!.companySlug,
            'targetCompany': _activeEvent!.targetCompany,
            'totalValue': totalValue.toString(),
            'uploadedAt': DateTime.now().toIso8601String(),
          },
        );

        if (kIsWeb) {
          await storageRef.putData(bytes, metadata).timeout(const Duration(seconds: 15));
        } else {
          await storageRef.putFile(File(_receiptImage!.path), metadata).timeout(const Duration(seconds: 15));
        }
        imageUrl = await storageRef.getDownloadURL().timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('Firebase Storage upload notice: $e');
        // Resilient fallback: store base64 if storage is slow or unreachable so customer is never blocked
        imageUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
      }

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
        'total_value': totalValue,
        'target_company_total': totalValue,
        'receipt_date': result.receiptDate,
        'extracted_products': result.extractedProducts.map((p) => p.toJson()).toList(),
        'store_chain_detected': result.storeChainDetected,
        'branch_detected': result.branchDetected,
        'is_branch_matched': result.isBranchMatched,
        'retail_chain_name': _activeEvent!.retailChainName,
        if (imageUrl.isNotEmpty) 'image_url': imageUrl,
        if (imageUrl.isNotEmpty) 'storage_path': storagePath,
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
          imageUrl: imageUrl.isNotEmpty ? imageUrl : previewImgUrl,
          isDuplicate: true,
        );
        _resetFormForNextCustomer();
        return;
      }

      // Reset image preview immediately
      setState(() {
        _receiptImage = null;
      });

      // Route customer to prize game based on event settings or total purchase value
      final currentEvent = _activeEvent ?? widget.event;
      final currentEventId = currentEvent?.id ?? '';
      final prizeNames = currentEvent?.allocatedPrizes
          .where((p) => p.remainingQuantity > 0)
          .map((p) => p.name)
          .toList() ?? <String>[];

      final totalChances = result.chancesEarned > 0 ? result.chancesEarned : 1;
      final gameType = currentEvent?.gameType ?? (totalValue >= 500 ? 'scratchCard' : 'spinTheWheel');

      if (gameType == 'directGift' || gameType == 'direct_gift') {
        // Check promotional rules using our robust multi-tiered AI & NLP PromotionalRuleMatcher
        final matchedRule = PromotionalRuleMatcher.match(
          result: result,
          promotionalRules: currentEvent?.promotionalRules ?? const [],
        );

        final designatedPrizeObj = (currentEvent?.availablePrizes.isNotEmpty ?? false)
            ? currentEvent!.availablePrizes.first
            : ((currentEvent?.allocatedPrizes.isNotEmpty ?? false)
                ? currentEvent!.allocatedPrizes.first
                : null);

        String designatedPrize;
        List<LinkedGiftAllocation> resolvedLinkedGifts = [];
        double? resolvedUnitValue;
        bool resolvedIsVoucher = false;

        if (matchedRule != null) {
          resolvedLinkedGifts = matchedRule.linkedGifts;
          if (matchedRule.rewardValue.isNotEmpty) {
            designatedPrize = matchedRule.rewardValue;
          } else if (matchedRule.linkedGiftsSummary.isNotEmpty) {
            designatedPrize = matchedRule.linkedGiftsSummary;
          } else {
            designatedPrize = designatedPrizeObj?.name ?? (prizeNames.isNotEmpty ? prizeNames.first : '');
          }

          resolvedIsVoucher = matchedRule.rewardType == 'voucher' ||
              matchedRule.totalVoucherValue > 0 ||
              designatedPrize.contains('فواتشر') ||
              designatedPrize.toLowerCase().contains('voucher') ||
              designatedPrize.contains('قسيمة');

          resolvedUnitValue = resolvedIsVoucher
              ? (matchedRule.totalVoucherValue > 0
                  ? matchedRule.totalVoucherValue
                  : (matchedRule.rewardAmount > 0 ? matchedRule.rewardAmount : designatedPrizeObj?.unitValue))
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

        final promoQuantity = (currentEvent?.allowMultipleChances ?? false) ? totalChances : 1;
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
    } catch (e) {
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
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : (isTablet ? 20 : 28),
                vertical: isMobile ? 12 : 24,
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
                                color: _receiptImage != null
                                    ? colorScheme.primary
                                    : colorScheme.outlineVariant.withValues(alpha: 0.7),
                                width: _receiptImage != null ? 2.0 : 1.2,
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
                            child: _receiptImage == null
                                ? Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isMobile ? 16 : 24,
                                      vertical: isMobile ? 22 : 28,
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
                                        const SizedBox(height: 12),
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
                                        const SizedBox(height: 20),
                                        // 1. Primary Action: Camera Capture
                                        SizedBox(
                                          width: double.infinity,
                                          child: AnimatedPressable(
                                            onTap: () => _pickImage(ImageSource.camera),
                                            child: FilledButton.icon(
                                              onPressed: () => _pickImage(ImageSource.camera),
                                              icon: const Icon(Icons.camera_alt_rounded, size: 20),
                                              label: Text(
                                                strings.captureReceiptAction,
                                                textAlign: TextAlign.center,
                                                style: GoogleFonts.cairo(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: isMobile ? 13.5 : 14.5,
                                                ),
                                              ),
                                              style: FilledButton.styleFrom(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: isMobile ? 14 : 16,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(16),
                                                ),
                                                elevation: 1,
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
                                              icon: const Icon(Icons.photo_library_rounded, size: 20),
                                              label: Text(
                                                strings.pickFromGalleryAction,
                                                textAlign: TextAlign.center,
                                                style: GoogleFonts.cairo(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: isMobile ? 13.5 : 14.5,
                                                ),
                                              ),
                                              style: FilledButton.styleFrom(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: isMobile ? 13 : 15,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(16),
                                                ),
                                              ),
                                            ),
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
                                                _receiptImage!.path,
                                                fit: BoxFit.contain,
                                                width: double.infinity,
                                              )
                                            : Image.file(
                                                File(_receiptImage!.path),
                                                fit: BoxFit.contain,
                                                width: double.infinity,
                                              ),
                                      ),
                                      // Top info and actions bar
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
                                                color: Colors.black.withValues(alpha: 0.65),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.check_circle_rounded,
                                                    color: Color(0xFF4CAF50),
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    strings.isAr ? 'تم اختيار الفاتورة' : 'Receipt Selected',
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
                                              message: strings.delete,
                                              waitDuration: const Duration(milliseconds: 400),
                                              child: IconButton.filled(
                                                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                                                style: IconButton.styleFrom(
                                                  backgroundColor: colorScheme.error,
                                                  padding: const EdgeInsets.all(6),
                                                ),
                                                onPressed: () => setState(() => _receiptImage = null),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Bottom retake button
                                      Positioned(
                                        bottom: 10,
                                        child: InkWell(
                                          onTap: () => _pickImage(ImageSource.camera),
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

                          // 4. M3 Action Button & Progress Tracker
                          if (_receiptImage != null) ...[
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
                              label: _isAiLoading ? strings.auditingProgressText : strings.auditReceiptActionBtn,
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
          const SwitchPointFooter(),
        ],
      ),
    );
  }
}
