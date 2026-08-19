import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/ai_receipt_service.dart';
import '../../../core/services/company_products_service.dart';
import '../../../core/utils/error_handler.dart';
import '../../games/presentation/spin_the_wheel_screen.dart';
import '../../games/presentation/scratch_card_screen.dart';
import '../../games/presentation/direct_gift_claim_screen.dart';
import '../../admin/domain/event_model.dart';
import '../../client_portal/presentation/widgets/campaign_gift_balance_dialog.dart';
import '../../client_portal/presentation/widgets/campaign_brief_dialog.dart';
import 'invoices_log_screen.dart';
import 'widgets/receipt_validation_dialog.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/widgets/switch_point_branding.dart';
import '../../../core/constants/country_currency_config.dart';
import '../../../core/localization/app_strings.dart';

class ValidationScreen extends ConsumerStatefulWidget {
  const ValidationScreen({super.key});

  @override
  ConsumerState<ValidationScreen> createState() => _ValidationScreenState();
}

class _ValidationScreenState extends ConsumerState<ValidationScreen> {
  XFile? _receiptImage;
  bool _isAiLoading = false;
  EventModel? _activeEvent;

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
          .limit(1)
          .get();
      if (eventsSnapshot.docs.isNotEmpty && mounted) {
        setState(() {
          _activeEvent = EventModel.fromFirestore(eventsSnapshot.docs.first);
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
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
      if (context.mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<void> _processReceiptWithAI() async {
    if (_receiptImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture a receipt photo first.')),
      );
      return;
    }
    
    setState(() => _isAiLoading = true);
    
    try {
      final firestore = ref.read(firestoreProvider);
      
      // Fetch active event
      final eventsSnapshot = await firestore
          .collection('events')
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
          
      if (eventsSnapshot.docs.isEmpty) {
        if (!mounted) return;
        _showPopupMessage('خطأ', 'لا يوجد أي حملة (Event) مفعلة حالياً.', isError: true);
        setState(() => _isAiLoading = false);
        return;
      }
      
      final activeEvent = EventModel.fromFirestore(eventsSnapshot.docs.first);

      final aiService = ref.read(aiReceiptServiceProvider);
      final productsService = ref.read(companyProductsServiceProvider);
      final bytes = await _receiptImage!.readAsBytes();
      final mimeType = _receiptImage!.mimeType ?? 'image/jpeg'; 

      // Fetch company catalog products & barcodes
      final catalogItems = await productsService.getProductsForCompany(activeEvent.companySlug);
      final registeredBarcodes = catalogItems.map((e) => "${e.productName} (${e.barcode})").toList();
      final catalogBarcodeMap = {
        for (final item in catalogItems)
          if (item.productName.isNotEmpty && item.barcode.isNotEmpty)
            item.productName: item.barcode,
      };
      
      final result = await aiService.analyzeReceiptImage(
        bytes, 
        mimeType,
        targetCompany: activeEvent.targetCompany,
        minimumSpend: activeEvent.minimumSpend,
        requiredProducts: activeEvent.requiredProducts,
        registeredBarcodes: registeredBarcodes,
        catalogBarcodeMap: catalogBarcodeMap,
        retailChainName: activeEvent.retailChainName,
        allowedBranches: activeEvent.branchNames,
        isAllBranches: activeEvent.isAllBranches,
        startDate: activeEvent.startDate,
        customPrompt: activeEvent.customPrompt,
        allowMultipleChances: activeEvent.allowMultipleChances,
        maxChancesPerReceipt: activeEvent.maxChancesPerReceipt,
        promotionalRules: activeEvent.promotionalRules,
      );

      final previewImgUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';

      if (!result.isValid) {
        if (!mounted) return;
        final activeCountry = ref.read(activeCountryProvider);
        final conditions = buildValidationConditionItems(
          isValid: false,
          message: result.message,
          targetCompanyTotal: result.targetCompanyTotal,
          minimumSpend: activeEvent.minimumSpend,
          targetCompany: activeEvent.targetCompany,
          currencySymbol: activeCountry.currencySymbol,
          unfulfilledConditions: result.unfulfilledConditions,
          isBranchMatched: result.isBranchMatched,
          storeChainDetected: result.storeChainDetected,
          branchDetected: result.branchDetected,
          retailChainName: activeEvent.retailChainName,
          allowedBranches: activeEvent.branchNames,
          isAllBranches: activeEvent.isAllBranches,
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
          requiredMinimum: activeEvent.minimumSpend,
          currencySymbol: activeCountry.currencySymbol,
          imageUrl: previewImgUrl,
        );
        return;
      }

      final double totalValue = result.targetCompanyTotal;
      if (activeEvent.minimumSpend > 0 && totalValue < activeEvent.minimumSpend) {
        if (!mounted) return;
        final activeCountry = ref.read(activeCountryProvider);
        final conditions = [
          ValidationConditionItem(
            title: 'الحد الأدنى لمشتريات ${activeEvent.targetCompany}',
            description: 'إجمالي منتجات الشركة بالفاتورة (${totalValue.toStringAsFixed(1)} ${activeCountry.currencySymbol}) أقل من الحد الأدنى المطلوب (${activeEvent.minimumSpend.toStringAsFixed(1)} ${activeCountry.currencySymbol}).',
            icon: Icons.payments_outlined,
            isMet: false,
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
          requiredMinimum: activeEvent.minimumSpend,
          currencySymbol: activeCountry.currencySymbol,
          imageUrl: previewImgUrl,
        );
        return;
      }

      final receiptNumber = result.receiptNumber.trim();

      // Check for existing receipt to update/upsert
      DocumentSnapshot<Map<String, dynamic>>? existingDoc;
      if (receiptNumber.isNotEmpty) {
        final existingReceipt = await firestore
            .collection('receipts_transactions')
            .where('receipt_number', isEqualTo: receiptNumber)
            .limit(1)
            .get();

        if (existingReceipt.docs.isNotEmpty) {
          existingDoc = existingReceipt.docs.first;
        }
      }

      // Upload Image (Resilient with timeout & base64 fallback)
      String imageUrl = '';
      final cleanReceiptNumber = (receiptNumber.isNotEmpty ? receiptNumber : "INV_${DateTime.now().millisecondsSinceEpoch}")
          .replaceAll(RegExp(r'[/\\?%*:|"<>]'), '_');
      final storagePath = 'receipts/${activeEvent.companySlug}/$cleanReceiptNumber.jpg';

      try {
        final storage = ref.read(firebaseStorageProvider);
        final storageRef = storage.ref().child(storagePath);
        final metadata = SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'receiptNumber': receiptNumber,
            'receiptDate': result.receiptDate,
            'storeChain': result.storeChainDetected.isNotEmpty ? result.storeChainDetected : activeEvent.retailChainName,
            'branch': result.branchDetected,
            'companySlug': activeEvent.companySlug,
            'targetCompany': activeEvent.targetCompany,
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
        debugPrint('Storage upload skipped or timed out: $e');
        imageUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
      }

      // Save or Update in Firestore (Upsert)
      final int totalChances = result.chancesEarned > 0 ? result.chancesEarned : 1;
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
        'retail_chain_name': activeEvent.retailChainName,
        if (imageUrl.isNotEmpty) 'image_url': imageUrl,
        if (imageUrl.isNotEmpty) 'storage_path': storagePath,
        'promoter_id': ref.read(firebaseAuthProvider).currentUser?.uid,
        'campaignId': activeEvent.id,
        'companySlug': activeEvent.companySlug,
        'targetCompany': activeEvent.targetCompany,
        'analysis_duration_seconds': result.durationSeconds,
        'analysis_duration_ms': result.durationMs,
        'ai_kpi_rating': result.kpiRating,
        'chances_earned': totalChances,
        'allow_multiple_chances': activeEvent.allowMultipleChances,
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

      // Reset form
      setState(() {
        _receiptImage = null;
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
            backgroundColor: Colors.green.shade700,
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
            imageUrl: imageUrl.isNotEmpty ? imageUrl : previewImgUrl,
            isDuplicate: true,
          );
          return;
        }
      }
      setState(() {
        _receiptImage = null;
      });

      // Route based on game type configured in the campaign
      final prizeNames = activeEvent.availablePrizeNames;
      final gameType = activeEvent.gameType;

      if (gameType == 'directGift' || gameType == 'direct_gift') {
        // Check promotional rules using our robust multi-tiered AI & NLP PromotionalRuleMatcher
        final matchedRule = PromotionalRuleMatcher.match(
          result: result,
          promotionalRules: activeEvent.promotionalRules,
        );

        final designatedPrizeObj = activeEvent.availablePrizes.isNotEmpty
            ? activeEvent.availablePrizes.first
            : (activeEvent.allocatedPrizes.isNotEmpty ? activeEvent.allocatedPrizes.first : null);

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

        final promoQuantity = activeEvent.allowMultipleChances ? totalChances : 1;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DirectGiftClaimScreen(
              transactionId: transactionRef.id,
              eventId: activeEvent.id,
              prizeName: designatedPrize,
              quantity: promoQuantity,
              branchId: activeEvent.branchIds.isNotEmpty ? activeEvent.branchIds.first : null,
              unitValue: resolvedUnitValue,
              isVoucher: resolvedIsVoucher,
              linkedGifts: resolvedLinkedGifts,
            ),
          ),
        );
        if (mounted) setState(() => _receiptImage = null);
      } else if (gameType == 'scratch') {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ScratchCardScreen(
              transactionId: transactionRef.id,
              eventId: activeEvent.id,
              prizes: prizeNames,
              totalChances: totalChances,
            ),
          ),
        );
        if (mounted) setState(() => _receiptImage = null);
      } else {
        // Default: wheel
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => SpinTheWheelScreen(
              transactionId: transactionRef.id,
              eventId: activeEvent.id,
              prizes: prizeNames,
              totalChances: totalChances,
            ),
          ),
        );
        if (mounted) setState(() => _receiptImage = null);
      }

    } catch (e) {
      if (!mounted) return;
      _showPopupMessage('تنبيه النظام', AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء معالجة الفاتورة'), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isAiLoading = false);
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

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: SwitchPointHeader(
        subtitle: strings.validationScreenSubtitle,
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
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
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
                            child: _receiptImage == null 
                                ? Center(
                                    child: FilledButton.icon(
                                      onPressed: _pickImage,
                                      icon: const Icon(Icons.camera_alt_rounded),
                                      label: Text(
                                        strings.captureReceiptBtn,
                                        style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold),
                                      ),
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                    ),
                                  )
                                : Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: kIsWeb
                                            ? Image.network(_receiptImage!.path, fit: BoxFit.contain, width: double.infinity)
                                            : Image.file(File(_receiptImage!.path), fit: BoxFit.contain, width: double.infinity),
                                      ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: IconButton.filled(
                                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                                          style: IconButton.styleFrom(backgroundColor: colorScheme.error),
                                          onPressed: () => setState(() => _receiptImage = null),
                                        ),
                                      )
                                    ],
                                  ),
                          ),
                          if (_receiptImage != null) ...[
                            const SizedBox(height: 24),
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
                                _isAiLoading ? strings.auditingProgressText : strings.auditingAndStartingGame,
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
          ),
          const SwitchPointFooter(),
        ],
      ),
    );
  }
}
