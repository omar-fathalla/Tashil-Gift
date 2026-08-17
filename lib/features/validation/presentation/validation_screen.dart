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
      if (totalValue < activeEvent.minimumSpend) {
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

      // Duplicate receipt check
      if (receiptNumber.isNotEmpty) {
        final existingReceipt = await firestore
            .collection('receipts_transactions')
            .where('receipt_number', isEqualTo: receiptNumber)
            .limit(1)
            .get();

        if (existingReceipt.docs.isNotEmpty) {
          if (!mounted) return;
          final activeCountry = ref.read(activeCountryProvider);
          final conditions = [
            ValidationConditionItem(
              title: 'حالة الفاتورة (مستخدمة مسبقاً)',
              description: 'رقم الفاتورة ($receiptNumber) تم استخدامه مسبقاً والمطالبة بجائزته في النظام، ولا يمكن إعادة استخدامه لمنع التكرار.',
              icon: Icons.history_toggle_off_rounded,
              isMet: false,
            ),
          ];

          showReceiptValidationReportDialog(
            context: context,
            title: 'عفواً، الفاتورة مسجلة مسبقاً',
            subtitle: 'تم التحقق من قاعدة البيانات وتبيّن وجود تسجيل سابق لهذه الفاتورة:',
            conditions: conditions,
            receiptNumber: receiptNumber,
            storeChain: result.storeChainDetected,
            branch: result.branchDetected,
            receiptDate: result.receiptDate,
            totalValue: totalValue,
            requiredMinimum: activeEvent.minimumSpend,
            currencySymbol: activeCountry.currencySymbol,
            imageUrl: previewImgUrl,
            isDuplicate: true,
          );
          return;
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

      // Save to Firestore
      final int totalChances = result.chancesEarned > 0 ? result.chancesEarned : 1;
      final transactionRef = firestore.collection('receipts_transactions').doc();
      await transactionRef.set({
        'receipt_number': receiptNumber,
        'total_value': totalValue,
        'target_company_total': totalValue,
        'receipt_date': result.receiptDate,
        'extracted_products': result.extractedProducts.map((p) => p.toJson()).toList(),
        'store_chain_detected': result.storeChainDetected,
        'branch_detected': result.branchDetected,
        'is_branch_matched': result.isBranchMatched,
        'retail_chain_name': activeEvent.retailChainName,
        'image_url': imageUrl,
        'storage_path': storagePath,
        'timestamp': FieldValue.serverTimestamp(),
        'promoter_id': ref.read(firebaseAuthProvider).currentUser?.uid,
        'campaignId': activeEvent.id,
        'companySlug': activeEvent.companySlug,
        'targetCompany': activeEvent.targetCompany,
        'analysis_duration_seconds': result.durationSeconds,
        'analysis_duration_ms': result.durationMs,
        'ai_kpi_rating': result.kpiRating,
        'chances_earned': totalChances,
        'allow_multiple_chances': activeEvent.allowMultipleChances,
        'game_played': false,
        'prize_won': null,
      });

      if (!mounted) return;

      // Reset form
      setState(() {
        _receiptImage = null;
      });

      // Route based on game type configured in the campaign
      final prizeNames = activeEvent.availablePrizeNames;
      final gameType = activeEvent.gameType;

      if (gameType == 'directGift' || gameType == 'direct_gift') {
        final designatedPrize = prizeNames.isNotEmpty
            ? prizeNames.first
            : (activeEvent.allocatedPrizes.isNotEmpty ? activeEvent.allocatedPrizes.first.name : 'هدية فورية مميزة');
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DirectGiftClaimScreen(
              transactionId: transactionRef.id,
              eventId: activeEvent.id,
              prizeName: designatedPrize,
              quantity: totalChances,
            ),
          ),
        );
      } else if (gameType == 'scratch') {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ScratchCardScreen(
              transactionId: transactionRef.id,
              eventId: activeEvent.id,
              prizes: prizeNames,
              totalChances: totalChances,
            ),
          ),
        );
      } else {
        // Default: wheel
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => SpinTheWheelScreen(
              transactionId: transactionRef.id,
              eventId: activeEvent.id,
              prizes: prizeNames,
              totalChances: totalChances,
            ),
          ),
        );
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
                                          ? '${strings.targetCompanyHeader}: ${_activeEvent!.targetCompany} • ${strings.minSpendPrefix} ${_activeEvent!.minimumSpend} ${activeCountry.currencySymbolFor(strings.languageCode)}'
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
