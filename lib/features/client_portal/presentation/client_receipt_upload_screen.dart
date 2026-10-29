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
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/services/ai_receipt_service.dart';
import '../../../core/services/ai_product_discovery_service.dart';
import '../../../core/services/chain_products_intelligence_service.dart';
import '../../../core/services/company_products_service.dart';
import '../../../core/services/retail_chains_service.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/arabic_numbers_utils.dart';
import '../../../core/utils/slug_utils.dart';
import '../../../core/widgets/switch_point_branding.dart';
import '../../../core/constants/country_currency_config.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/animations/m3_motion.dart';
import '../../admin/domain/event_model.dart';
import '../../admin/domain/retail_chain_model.dart';
import '../../games/presentation/spin_the_wheel_screen.dart';
import '../../games/presentation/scratch_card_screen.dart';
import '../../games/presentation/direct_gift_claim_screen.dart';
import '../../games/presentation/choose_gift_screen.dart';
import '../../validation/presentation/widgets/receipt_validation_dialog.dart';
import 'widgets/receipt_issue_dialog.dart';
import 'widgets/campaign_gift_balance_dialog.dart';
import 'widgets/campaign_brief_dialog.dart';
import 'widgets/promoter_invoices_dialog.dart';
import 'widgets/unified_multi_campaign_claim_screen.dart';
import '../../../core/services/multi_campaign_receipt_evaluator.dart';
import '../../../core/services/receipt_deduplication_helper.dart';
import '../../../core/widgets/campaign_suspended_screen.dart';
import '../../../core/utils/receipt_image_calibrator.dart';
import '../../../core/widgets/optimistic_receipt_scanner_card.dart';

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
  ConsumerState<ClientReceiptUploadScreen> createState() =>
      _ClientReceiptUploadScreenState();
}

class _ClientReceiptUploadScreenState
    extends ConsumerState<ClientReceiptUploadScreen> {
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  static const String kAutoAllCampaignsId = '__AUTO_ALL__';
  bool _isAutoMultiCampaignMode = true;

  EventModel? _activeEvent;
  List<EventModel> _availableCompanyEvents = [];
  bool _isLoadingEvent = true;
  String? _errorMessage;
  StreamSubscription? _eventSubscription;

  final List<XFile> _receiptImages = [];
  // Bytes read once at pick time, keyed by XFile.path. Used to render previews
  // with Image.memory on web (avoids fetching blob: URLs, which CanvasKit does
  // via XHR and a strict CSP connect-src can block -> blank white preview).
  final Map<String, Uint8List> _receiptImageBytes = {};
  int _selectedPreviewIndex = 0;
  bool _isAiLoading = false;
  int _aiPhase = 0;
  String _aiPhaseText = '';
  CalibratedImageResult? _latestCalibration;
  Uint8List? _previewImageBytes;

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
    _receiptImageBytes.clear();
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

      // Active campaigns only. A bare event link reads that one document.
      // A company link lists active events for that slug.
      if (slug.isEmpty && targetEventId != null && targetEventId.isNotEmpty) {
        _eventSubscription = firestore
            .collection('events')
            .doc(targetEventId)
            .snapshots()
            .listen(
              (snap) {
                if (!mounted) return;
                if (!snap.exists) {
                  setState(() {
                    _activeEvent = null;
                    _availableCompanyEvents = [];
                    _errorMessage =
                        'لا يوجد أي فعاليات مسجلة لهذه الشركة حالياً.';
                    _isLoadingEvent = false;
                  });
                  return;
                }
                _applyLiveEventDocs(
                  [snap],
                  targetEventId: targetEventId,
                  slug: slug,
                );
              },
              onError: (e) {
                if (!mounted) return;
                setState(() {
                  _errorMessage = AppErrorHandler.getFriendlyMessage(
                    e,
                    defaultMessage:
                        'حدث خطأ أثناء تحميل بيانات الحملة من الخادم.',
                  );
                  _isLoadingEvent = false;
                });
              },
            );
        return;
      }

      Query<Map<String, dynamic>> query = firestore
          .collection('events')
          .where('isActive', isEqualTo: true);
      if (slug.isNotEmpty) {
        query = query.where('companySlug', isEqualTo: slug);
      }

      _eventSubscription = query.snapshots().listen(
        (snapshot) {
          if (!mounted) return;
          _applyLiveEventDocs(
            snapshot.docs,
            targetEventId: targetEventId,
            slug: slug,
          );
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

  Future<void> _applyLiveEventDocs(
    List<DocumentSnapshot<Map<String, dynamic>>> docs, {
    required String? targetEventId,
    required String slug,
  }) async {
    if (!mounted) return;
    final firestore = ref.read(firestoreProvider);
    {
      // Fallback if scoped query returned empty but targetEventId is provided
      if (docs.isEmpty && targetEventId != null && targetEventId.isNotEmpty) {
        final singleDoc = await firestore
            .collection('events')
            .doc(targetEventId)
            .get();
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
      final events = docs
          .map((d) {
            try {
              return EventModel.fromFirestore(d);
            } catch (_) {
              return null;
            }
          })
          .whereType<EventModel>()
          .toList();

      // 1. If targetEventId was provided, find that specific event first
      EventModel? initialMatched;
      if (targetEventId != null && targetEventId.isNotEmpty) {
        initialMatched = events.cast<EventModel?>().firstWhere(
          (e) => e!.id == targetEventId,
          orElse: () => null,
        );
      }

      // 2. Identify target company key/slug
      final effectiveSlug =
          (initialMatched != null && initialMatched.companySlug.isNotEmpty)
          ? initialMatched.companySlug.trim().toLowerCase()
          : (slug.isNotEmpty
                ? slug
                : (initialMatched?.targetCompany.toLowerCase().trim() ?? ''));

      // 3. Find all campaigns for this company (active and promoter active)
      List<EventModel> companyEvents = events.where((e) {
        final eSlug = e.companySlug.trim().toLowerCase();
        final eTargetSlug = SlugUtils.toSlug(e.targetCompany).toLowerCase();
        final eTargetName = e.targetCompany.trim().toLowerCase();
        final matchesCompany =
            eSlug == effectiveSlug ||
            eTargetSlug == effectiveSlug ||
            eTargetName == effectiveSlug ||
            e.id == effectiveSlug ||
            (effectiveSlug.isNotEmpty &&
                (eTargetName.contains(effectiveSlug) ||
                    effectiveSlug.contains(eTargetName)));
        return matchesCompany && e.isActive && e.isPromoterActive;
      }).toList();

      // Sort by creation date descending
      companyEvents.sort((a, b) {
        final aDate =
            a.createdAt ??
            a.startDate ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate =
            b.createdAt ??
            b.startDate ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

      // Fallback if no promoter-active campaigns found
      if (companyEvents.isEmpty && initialMatched != null) {
        companyEvents = [initialMatched];
      }

      if (companyEvents.isNotEmpty) {
        // Determine active event
        EventModel selected;
        if (_activeEvent != null &&
            companyEvents.any((e) => e.id == _activeEvent!.id)) {
          selected = companyEvents.firstWhere((e) => e.id == _activeEvent!.id);
        } else if (initialMatched != null &&
            companyEvents.any((e) => e.id == initialMatched!.id)) {
          selected = companyEvents.firstWhere(
            (e) => e.id == initialMatched!.id,
          );
        } else {
          selected = companyEvents.first;
        }

        setState(() {
          _availableCompanyEvents = companyEvents;
          _activeEvent = selected;
          if (companyEvents.length > 1) {
            _isAutoMultiCampaignMode = true;
          }
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
    }
  }

  Widget _receiptImageErrorFallback({required bool compact}) {
    final isAr = ref.read(localeProvider).languageCode == 'ar';
    return Container(
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: compact ? 22 : 48,
            color: Colors.grey.shade600,
          ),
          if (!compact) ...[
            const SizedBox(height: 8),
            Text(
              isAr
                  ? 'تعذر عرض المعاينة، الصورة محفوظة وسيتم رفعها'
                  : 'Preview unavailable — the image is saved and will be uploaded',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReceiptImage(
    XFile file, {
    BoxFit fit = BoxFit.cover,
    double? width,
    bool compact = false,
  }) {
    Widget onError(
      BuildContext context,
      Object error,
      StackTrace? stackTrace,
    ) => _receiptImageErrorFallback(compact: compact);
    if (!kIsWeb) {
      return Image.file(
        File(file.path),
        fit: fit,
        width: width,
        errorBuilder: onError,
      );
    }
    final cached = _receiptImageBytes[file.path];
    if (cached != null) {
      return Image.memory(
        cached,
        fit: fit,
        width: width,
        gaplessPlayback: true,
        errorBuilder: onError,
      );
    }
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snap) {
        if (snap.hasData) {
          _receiptImageBytes[file.path] = snap.data!;
          return Image.memory(
            snap.data!,
            fit: fit,
            width: width,
            gaplessPlayback: true,
            errorBuilder: onError,
          );
        }
        if (snap.hasError) return _receiptImageErrorFallback(compact: compact);
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      },
    );
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
        maxWidth: 2560,
        maxHeight: 2560,
        imageQuality: 92,
      );
      if (pickedFile != null) {
        Uint8List? pickedBytes;
        try {
          pickedBytes = await pickedFile.readAsBytes();
        } catch (_) {
          pickedBytes = null;
        }
        if (!mounted) return;
        setState(() {
          if (pickedBytes != null) {
            if (!append) _receiptImageBytes.clear();
            _receiptImageBytes[pickedFile.path] = pickedBytes;
          }
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
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.6,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.camera_alt_rounded,
                      color: colorScheme.primary,
                    ),
                  ),
                  title: Text(
                    strings.captureNextPartCamera,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
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
                      color: colorScheme.secondaryContainer.withValues(
                        alpha: 0.6,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.photo_library_rounded,
                      color: colorScheme.secondary,
                    ),
                  ),
                  title: Text(
                    strings.pickNextPartGallery,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
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
        final removed = _receiptImages.removeAt(index);
        if (!_receiptImages.any((f) => f.path == removed.path)) {
          _receiptImageBytes.remove(removed.path);
        }
        if (_selectedPreviewIndex >= _receiptImages.length) {
          _selectedPreviewIndex = math.max(0, _receiptImages.length - 1);
        }
      });
    }
  }

  void _clearAllParts() {
    setState(() {
      _receiptImages.clear();
      _receiptImageBytes.clear();
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
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.6,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.camera_alt_rounded,
                      color: colorScheme.primary,
                    ),
                  ),
                  title: Text(
                    strings.captureReceiptAction,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
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
                      color: colorScheme.secondaryContainer.withValues(
                        alpha: 0.6,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.photo_library_rounded,
                      color: colorScheme.secondary,
                    ),
                  ),
                  title: Text(
                    strings.pickFromGalleryAction,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
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
      _showIssue(ReceiptIssueKind.noImage);
      return;
    }

    final bool isMultiScan =
        _isAutoMultiCampaignMode && _availableCompanyEvents.length > 1;
    final EventModel? primaryTargetEvent =
        _activeEvent ??
        (isMultiScan && _availableCompanyEvents.isNotEmpty
            ? _availableCompanyEvents.first
            : widget.event);

    if (primaryTargetEvent == null) {
      _showIssue(ReceiptIssueKind.campaignUnavailable);
      return;
    }

    setState(() {
      _isAiLoading = true;
      _aiPhase = 0;
      _aiPhaseText = '1/3 جاري معايرة الصورة وضبط التباين محلياً...';
    });

    try {
      // 1. Check event active dates if single focused campaign mode
      if (!isMultiScan && _activeEvent != null) {
        if (_activeEvent!.isExpired) {
          final endStr =
              "${_activeEvent!.endDate!.day}/${_activeEvent!.endDate!.month}/${_activeEvent!.endDate!.year}";
          _showIssue(
            ReceiptIssueKind.campaignEnded,
            subtitle: _isAr
                ? 'انتهت الحملة بتاريخ $endStr. لا يمكن قبول فواتير جديدة.'
                : 'The campaign ended on $endStr. New receipts can no longer be accepted.',
          );
          return;
        }
        if (_activeEvent!.isNotStartedYet) {
          final startStr =
              "${_activeEvent!.startDate!.day}/${_activeEvent!.startDate!.month}/${_activeEvent!.startDate!.year}";
          _showIssue(
            ReceiptIssueKind.campaignNotStarted,
            subtitle: _isAr
                ? 'تبدأ الحملة بتاريخ $startStr.'
                : 'The campaign starts on $startStr.',
          );
          return;
        }
      }

      final firestore = ref.read(firestoreProvider);
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
      final primaryCalib = await ReceiptImageCalibrator.calibrateReceiptBytes(
        rawPrimaryBytes,
      );
      final bytes = primaryCalib.bytes;
      final mimeType = primaryCalib.mimeType;

      // Step 2: Calibrate additional parts if present
      final List<Uint8List> additionalBytesList = [];
      final List<String> additionalMimesList = [];
      for (int i = 1; i < _receiptImages.length; i++) {
        final addRaw = await _receiptImages[i].readAsBytes();
        final addCalib = await ReceiptImageCalibrator.calibrateReceiptBytes(
          addRaw,
        );
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
          _aiPhaseText = '2/3 جاري قراءة وتدقيق الفاتورة بالذكاء الاصطناعي...';
        });
      }

      // Fetch company product barcodes catalog and branch signatures concurrently in parallel
      List<String> registeredBarcodes = [];
      Map<String, String> catalogBarcodeMap = {};
      List<BranchModel> chainBranches = [];

      try {
        final results = await Future.wait([
          productsService
              .getProductsForCompany(primaryTargetEvent.companySlug)
              .catchError((_) => <CompanyProductItem>[]),
          ref
              .read(retailChainsServiceProvider)
              .getBranchesForEvent(
                retailChainId: primaryTargetEvent.retailChainId,
                branchIds: primaryTargetEvent.branchIds,
                branchNames: primaryTargetEvent.branchNames,
              )
              .catchError((_) => <BranchModel>[]),
        ]);

        final catalogItems = results[0] as List<CompanyProductItem>;
        chainBranches = results[1] as List<BranchModel>;

        registeredBarcodes = catalogItems
            .map((e) => "${e.productName} (${e.barcode})")
            .toList();
        catalogBarcodeMap = {
          for (final item in catalogItems)
            if (item.productName.isNotEmpty && item.barcode.isNotEmpty)
              item.productName: item.barcode,
        };
      } catch (_) {}

      List<String> combinedRequiredProducts = [];
      List<PromotionalRuleItem> combinedPromotionalRules = [];
      List<String> combinedAllowedBranches = [];
      bool combinedIsAllBranches = false;

      if (isMultiScan) {
        final Set<String> reqProdSet = {};
        final Set<String> ruleIdSet = {};
        final Set<String> branchSet = {};

        for (final ev in _availableCompanyEvents) {
          if (ev.isAllBranches) combinedIsAllBranches = true;
          for (final b in ev.branchNames) {
            if (b.trim().isNotEmpty) branchSet.add(b.trim());
          }
          for (final p in ev.requiredProducts) {
            if (p.trim().isNotEmpty) reqProdSet.add(p.trim());
          }
          for (final r in ev.promotionalRules) {
            final key = '${ev.id}_${r.id.isNotEmpty ? r.id : r.ruleTitle}';
            if (ruleIdSet.add(key)) {
              combinedPromotionalRules.add(r);
            }
            for (final sp in r.selectedProductNames) {
              if (sp.trim().isNotEmpty) reqProdSet.add(sp.trim());
            }
            for (final rb in r.requiredBrands) {
              if (rb.trim().isNotEmpty) reqProdSet.add(rb.trim());
            }
          }
        }
        combinedRequiredProducts = reqProdSet.toList();
        combinedAllowedBranches = branchSet.toList();
      } else {
        final Set<String> singleReqProds = Set<String>.from(
          _activeEvent!.requiredProducts,
        );
        for (final r in _activeEvent!.promotionalRules) {
          for (final sp in r.selectedProductNames) {
            if (sp.trim().isNotEmpty) singleReqProds.add(sp.trim());
          }
          for (final rb in r.requiredBrands) {
            if (rb.trim().isNotEmpty) singleReqProds.add(rb.trim());
          }
        }
        combinedRequiredProducts = singleReqProds.toList();
        combinedPromotionalRules = _activeEvent!.promotionalRules;
        combinedAllowedBranches = _activeEvent!.branchNames;
        combinedIsAllBranches = _activeEvent!.isAllBranches;
      }

      final double effectiveCampaignMinSpend = isMultiScan
          ? 0.0
          : (combinedPromotionalRules
                .where((r) => r.isSpendBased)
                .map((r) => r.effectiveMinSpend)
                .fold<double>(
                  _activeEvent!.minimumSpend,
                  (min, s) => s > 0 && (min <= 0 || s < min) ? s : min,
                ));

      // Run Gemini AI analysis
      final result = await aiService.analyzeReceiptImage(
        bytes,
        mimeType,
        additionalImagesBytes: additionalBytesList,
        additionalMimeTypes: additionalMimesList,
        targetCompany: primaryTargetEvent.targetCompany,
        minimumSpend: effectiveCampaignMinSpend,
        requiredProducts: combinedRequiredProducts,
        registeredBarcodes: registeredBarcodes,
        catalogBarcodeMap: catalogBarcodeMap,
        retailChainName: primaryTargetEvent.retailChainName,
        allowedBranches: combinedAllowedBranches,
        isAllBranches: combinedIsAllBranches,
        registeredBranches: chainBranches,
        startDate: isMultiScan ? null : _activeEvent!.startDate,
        endDate: isMultiScan ? null : _activeEvent!.endDate,
        customPrompt: isMultiScan ? '' : _activeEvent!.customPrompt,
        allowMultipleChances: true,
        multiplierBasis: isMultiScan ? 'both' : _activeEvent!.multiplierBasis,
        maxChancesPerReceipt: isMultiScan
            ? 0
            : _activeEvent!.maxChancesPerReceipt,
        promotionalRules: combinedPromotionalRules,
        allowComplementaryReceipts:
            _activeEvent?.allowComplementaryReceipts ?? false,
      );

      final previewImgUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
      final List<String> previewUrls = allBytesList
          .map((b) => 'data:image/jpeg;base64,${base64Encode(b)}')
          .toList();

      // Asynchronously stage any newly harvested branch metadata for admin review & merge
      unawaited(
        ref
            .read(retailChainsServiceProvider)
            .stageBranchEnrichment(
              chainName: result.storeChainDetected.isNotEmpty
                  ? result.storeChainDetected
                  : primaryTargetEvent.retailChainName,
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
            )
            .catchError((_) => false),
      );

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
                  : [
                      result.message.trim().isNotEmpty
                          ? result.message.trim()
                          : 'الفاتورة غير مطابقة لشروط الحملة',
                    ]);

        final conditions = buildValidationConditionItems(
          isValid: false,
          message: result.message,
          targetCompanyTotal: result.targetCompanyTotal,
          minimumSpend: effectiveCampaignMinSpend,
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
          hasTargetProducts:
              result.extractedProducts.any((p) => p.isTargetCompany) ||
              result.targetCompanyTotal > 0,
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

        _showIssue(
          _kindForInvalidResult(
            result,
            unfulfilledList,
            effectiveCampaignMinSpend,
          ),
          chips: _receiptChips(
            result,
            minimumSpend: effectiveCampaignMinSpend,
            currency: activeCountry.currencySymbol,
          ),
          extraReasons: <String>{
            ...unfulfilledList,
            ...conditions.map((c) => c.description),
          }.toList(),
          onPrimary: _clearPhotosForRetake,
        );
        return;
      }

      final candidateReceiptNumber = result.receiptNumber.trim();
      if (candidateReceiptNumber.isNotEmpty) {
        final duplicateCheck =
            await ReceiptDeduplicationHelper.checkReceiptDuplicate(
              firestore: firestore,
              receiptNumber: candidateReceiptNumber,
              companySlug: primaryTargetEvent.companySlug,
              campaignId: isMultiScan ? null : _activeEvent?.id,
              isMultiScan: isMultiScan,
            );

        if (duplicateCheck.isDuplicate) {
          if (!mounted) return;

          _showAlreadyRedeemed(duplicateCheck);
          _resetFormForNextCustomer();
          return;
        }
      }

      if (isMultiScan) {
        final summary = MultiCampaignReceiptEvaluator.evaluateAll(
          result: result,
          campaigns: _availableCompanyEvents,
        );

        if (summary.isMultiMatch) {
          // Upload to Firebase Storage
          setState(() {
            _aiPhaseText = '2/3 جاري حفظ صورة الفاتورة في التخزين السحابي...';
          });

          final receiptNumber = result.receiptNumber.trim();
          final cleanReceiptNumber =
              (receiptNumber.isNotEmpty
                      ? receiptNumber
                      : "INV_${DateTime.now().millisecondsSinceEpoch}")
                  .replaceAll(RegExp(r'[/\\?%*:|"<>]'), '_');

          final List<String> uploadedImageUrls = [];
          final List<String> uploadedStoragePaths = [];

          await Future.wait(
            List.generate(allBytesList.length, (index) async {
              final partNum = index + 1;
              final sPath = allBytesList.length == 1
                  ? 'receipts/${primaryTargetEvent.companySlug}/multi_bundles/$cleanReceiptNumber.jpg'
                  : 'receipts/${primaryTargetEvent.companySlug}/multi_bundles/${cleanReceiptNumber}_part$partNum.jpg';
              try {
                final storage = ref.read(firebaseStorageProvider);
                final storageRef = storage.ref().child(sPath);
                final metadata = SettableMetadata(
                  contentType: 'image/jpeg',
                  customMetadata: {
                    'receiptNumber': receiptNumber,
                    'companySlug': primaryTargetEvent.companySlug,
                    'targetCompany': primaryTargetEvent.targetCompany,
                    'totalValue': result.targetCompanyTotal.toString(),
                    'partIndex': '$partNum',
                    'totalParts': '${allBytesList.length}',
                    'uploadedAt': DateTime.now().toIso8601String(),
                    'uploaderUid':
                        ref.read(firebaseAuthProvider).currentUser?.uid ?? '',
                  },
                );

                await storageRef
                    .putData(allBytesList[index], metadata)
                    .timeout(const Duration(seconds: 15));
                final url = await storageRef.getDownloadURL().timeout(
                  const Duration(seconds: 10),
                );
                uploadedImageUrls.add(url);
                uploadedStoragePaths.add(sPath);
              } catch (e) {
                debugPrint(
                  'Firebase Storage upload notice for part $partNum: $e',
                );
                if (allBytesList[index].lengthInBytes <= 400 * 1024) {
                  uploadedImageUrls.add(
                    'data:image/jpeg;base64,${base64Encode(allBytesList[index])}',
                  );
                } else {
                  uploadedImageUrls.add('');
                }
                uploadedStoragePaths.add(sPath);
              }
            }),
          );

          // Harvest discovered products asynchronously
          unawaited(
            ref
                .read(aiProductDiscoveryServiceProvider)
                .autoHarvestFromReceiptAnalysis(
                  companySlug: primaryTargetEvent.companySlug,
                  companyName: primaryTargetEvent.targetCompany,
                  retailChain: result.storeChainDetected,
                  branch: result.branchDetected,
                  receiptNumber: receiptNumber,
                  extractedProducts: result.extractedProducts,
                ),
          );

          // Reset image preview and analysis state immediately
          setState(() {
            _receiptImages.clear();
            _receiptImageBytes.clear();
            _selectedPreviewIndex = 0;
            _isAiLoading = false;
            _aiPhaseText = '';
          });

          final bundleGroupId =
              'BUNDLE_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(9999)}';
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => UnifiedMultiCampaignClaimScreen(
                bundleGroupId: bundleGroupId,
                receiptNumber: receiptNumber,
                customerPhone: _customerPhoneController.text
                    .toEnglishDigits()
                    .trim(),
                customerName: _customerNameController.text.trim(),
                qualifiedCampaigns: summary.qualifiedCampaigns,
                imageUrls: uploadedImageUrls.isNotEmpty
                    ? uploadedImageUrls
                    : previewUrls,
                initialAiMetadata: {
                  'store_chain_detected': result.storeChainDetected,
                  'branch_detected': result.branchDetected,
                  'branch_id': ReceiptBranchResolver.resolve(_activeEvent ?? widget.event, result.branchDetected).id ?? '',
                  'receipt_date': result.receiptDate,
                  'analysis_duration_seconds': result.durationSeconds,
                  'analysis_duration_ms': result.durationMs,
                  'ai_kpi_rating': result.kpiRating,
                  'extracted_products': result.extractedProducts
                      .map((p) => p.toJson())
                      .toList(),
                },
                onDisbursalCompleted: () {
                  _resetFormForNextCustomer();
                },
              ),
            ),
          );
          _resetFormForNextCustomer();
          return;
        } else if (summary.isSingleMatch) {
          // Exactly 1 campaign matched! Switch _activeEvent to that campaign
          _activeEvent = summary.qualifiedCampaigns.first.campaign;
        } else {
          // 0 campaigns matched in multi-scan! Show aggregated report
          if (!mounted) return;
          final activeCountry = ref.read(activeCountryProvider);

          final List<ValidationConditionItem> conditions = [];
          final List<String> allUnfulfilled = [];

          for (final unfulfilled in summary.unfulfilledCampaigns) {
            final campaignName = unfulfilled.campaign.eventName;
            final reasons = unfulfilled.unfulfilledConditions.isNotEmpty
                ? unfulfilled.unfulfilledConditions.join('\n• ')
                : (unfulfilled.rejectionReason ?? 'الشروط غير مستوفاة');
            allUnfulfilled.add('$campaignName: $reasons');

            conditions.add(
              ValidationConditionItem(
                title: campaignName,
                description: reasons,
                icon: Icons.layers_clear_rounded,
                isMet: false,
              ),
            );
          }

          _recordRejectedReceipt(
            result: result,
            allBytesList: allBytesList,
            allImagesList: allImagesList,
            activeEvent: primaryTargetEvent,
            rejectionReason: allUnfulfilled.join(' | '),
            unfulfilledConditions: allUnfulfilled,
            totalValue: result.targetCompanyTotal,
          );

          _showIssue(
            ReceiptIssueKind.multiNoMatch,
            chips: _receiptChips(
              result,
              minimumSpend: 0,
              currency: activeCountry.currencySymbol,
            ),
            extraReasons: conditions
                .map((c) => '${c.title}: ${c.description}')
                .toList(),
          );
          _resetFormForNextCustomer();
          return;
        }
      }

      final double totalValue = result.targetCompanyTotal;
      if (_activeEvent!.minimumSpend > 0 &&
          totalValue < _activeEvent!.minimumSpend) {
        if (!mounted) return;
        final activeCountry = ref.read(activeCountryProvider);
        final unfulfilledList = [
          'إجمالي مشتريات منتجات ${_activeEvent!.targetCompany} في الفاتورة ($totalValue ${activeCountry.currencySymbol}) أقل من الحد الأدنى المطلوب لدخول السحب (${_activeEvent!.minimumSpend} ${activeCountry.currencySymbol}).',
        ];
        final conditions = [
          ValidationConditionItem(
            title: 'الحد الأدنى لقيمة المشتريات',
            description: unfulfilledList.first,
            icon: Icons.price_check_rounded,
            isMet: false,
            value:
                '$totalValue / ${_activeEvent!.minimumSpend} ${activeCountry.currencySymbol}',
          ),
        ];

        // Asynchronously persist rejected transaction to Firestore & Storage for audit
        _recordRejectedReceipt(
          result: result,
          allBytesList: allBytesList,
          allImagesList: allImagesList,
          activeEvent: _activeEvent!,
          rejectionReason:
              'الحد الأدنى لقيمة المشتريات غير مستوفى ($totalValue / ${_activeEvent!.minimumSpend} ${activeCountry.currencySymbol})',
          unfulfilledConditions: unfulfilledList,
          totalValue: totalValue,
        );

        _showIssue(
          ReceiptIssueKind.belowMinimum,
          chips: _receiptChips(
            result,
            minimumSpend: _activeEvent!.minimumSpend,
            currency: activeCountry.currencySymbol,
          ),
          extraReasons: conditions.map((c) => c.description).toList(),
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

      if (_activeEvent!.promotionalRules.isNotEmpty &&
          matchedRulesList.isEmpty) {
        if (!mounted) return;
        final activeCountry = ref.read(activeCountryProvider);
        final unfulfilledPromoList =
            PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
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

        // Harvest unlisted company products so they immediately appear in "تحديث الأصناف" for review & one-click catalog addition
        if (result.extractedProducts.any((p) => p.isTargetCompany)) {
          unawaited(
            ref
                .read(aiProductDiscoveryServiceProvider)
                .autoHarvestFromReceiptAnalysis(
                  companySlug: _activeEvent!.companySlug,
                  companyName: _activeEvent!.targetCompany,
                  retailChain: result.storeChainDetected,
                  branch: result.branchDetected,
                  receiptNumber: receiptNumber,
                  extractedProducts: result.extractedProducts,
                ),
          );
        }

        _showIssue(
          ReceiptIssueKind.promoNotMet,
          chips: _receiptChips(
            result,
            minimumSpend: _activeEvent!.minimumSpend,
            currency: activeCountry.currencySymbol,
          ),
          extraReasons: <String>{
            ...unfulfilledPromoList,
            ...conditions.map((c) => c.description),
          }.toList(),
        );
        _resetFormForNextCustomer();
        return;
      }

      final deterministicDocId =
          ReceiptDeduplicationHelper.getDeterministicDocId(
            campaignId: _activeEvent!.id,
            receiptNumber: receiptNumber,
          );

      // Duplicate detection runs server-side (checkReceiptDuplicate) before this
      // point. Anonymous reps cannot read receipts (firestore.rules), so the
      // receipt is always created at its deterministic ID; if it already exists
      // the create is denied by the rules and handled as a duplicate below.

      // 2. Upload image to Firebase Storage named by Receipt Number and Campaign ID
      setState(() {
        _aiPhaseText = '2/3 جاري حفظ صورة الفاتورة في التخزين السحابي...';
      });

      final cleanReceiptNumber =
          (receiptNumber.isNotEmpty
                  ? receiptNumber
                  : "INV_${DateTime.now().millisecondsSinceEpoch}")
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
                'campaignId': _activeEvent!.id,
                'companySlug': _activeEvent!.companySlug,
                'targetCompany': _activeEvent!.targetCompany,
                'totalValue': totalValue.toString(),
                'partIndex': '$partNum',
                'totalParts': '${allBytesList.length}',
                'uploadedAt': DateTime.now().toIso8601String(),
                'uploaderUid':
                    ref.read(firebaseAuthProvider).currentUser?.uid ?? '',
              },
            );

            await storageRef
                .putData(allBytesList[index], metadata)
                .timeout(const Duration(seconds: 15));
            final url = await storageRef.getDownloadURL().timeout(
              const Duration(seconds: 10),
            );
            uploadedImageUrls.add(url);
            uploadedStoragePaths.add(sPath);
          } catch (e) {
            debugPrint('Firebase Storage upload notice for part $partNum: $e');
            if (allBytesList[index].lengthInBytes <= 400 * 1024) {
              uploadedImageUrls.add(
                'data:image/jpeg;base64,${base64Encode(allBytesList[index])}',
              );
            } else {
              uploadedImageUrls.add('');
            }
            uploadedStoragePaths.add(sPath);
          }
        }),
      );

      final String primaryImageUrl = uploadedImageUrls.isNotEmpty
          ? uploadedImageUrls.first
          : '';
      final String primaryStoragePath = uploadedStoragePaths.isNotEmpty
          ? uploadedStoragePaths.first
          : '';

      // 3. Store transaction in Firestore with Duration & KPI metrics (Upsert)
      setState(() {
        _aiPhaseText = '3/3 جاري حفظ المعاملة وتجهيز الجائزة...';
      });

      final int calculatedChances = result.chancesEarned > 0
          ? result.chancesEarned
          : 1;
      final DocumentReference<Map<String, dynamic>> transactionRef = firestore
          .collection('receipts_transactions')
          .doc(deterministicDocId);

      final Map<String, dynamic> transactionData = {
        'receipt_number': receiptNumber,
        'is_valid': true,
        'status': 'accepted',
        'rejection_reason': null,
        'unfulfilled_conditions': const [],
        'total_value': totalValue,
        'target_company_total': totalValue,
        'receipt_date': result.receiptDate,
        'extracted_products': result.extractedProducts
            .map((p) => p.toJson())
            .toList(),
        'store_chain_detected': result.storeChainDetected,
        'branch_detected': result.branchDetected,
        'branch_id': ReceiptBranchResolver.resolve(_activeEvent ?? widget.event, result.branchDetected).id ?? '',
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
        if (uploadedStoragePaths.length > 1)
          'storage_paths': uploadedStoragePaths,
        'parts_count': allBytesList.length,
        'campaignId': _activeEvent!.id,
        'submittedByUid': ref.read(firebaseAuthProvider).currentUser?.uid ?? '',
        'companySlug': _activeEvent!.companySlug,
        'targetCompany': _activeEvent!.targetCompany,
        'customerPhone': _customerPhoneController.text.toEnglishDigits().trim(),
        'customerName': _customerNameController.text.trim(),
        'aiMessage': result.message,
        'analysis_duration_seconds': result.durationSeconds,
        'analysis_duration_ms': result.durationMs,
        'ai_kpi_rating': result.kpiRating,
        'chances_earned': calculatedChances,
        if (result.matchedRuleId.isNotEmpty)
          'matched_rule_id': result.matchedRuleId,
        if (result.matchedRewardValue.isNotEmpty)
          'matched_reward_value': result.matchedRewardValue,
        'allow_multiple_chances': _activeEvent!.allowMultipleChances,
      };

      transactionData['timestamp'] = FieldValue.serverTimestamp();
      transactionData['game_played'] = false;
      transactionData['prize_won'] = null;
      try {
        await transactionRef.set(transactionData);
      } on FirebaseException catch (e) {
        if (!ReceiptDeduplicationHelper.isDuplicateWriteDenied(e)) rethrow;
        debugPrint('Receipt create denied (already exists for campaign): $e');
        if (!mounted) return;
        final dup = await ReceiptDeduplicationHelper.checkReceiptDuplicate(
          firestore: firestore,
          receiptNumber: receiptNumber,
          companySlug: _activeEvent!.companySlug,
          campaignId: _activeEvent!.id,
        );
        if (!mounted) return;
        _showAlreadyRedeemed(dup);
        return;
      }

      // Harvest discovered products asynchronously for the AI Product Discovery Hub
      unawaited(
        ref
            .read(aiProductDiscoveryServiceProvider)
            .autoHarvestFromReceiptAnalysis(
              companySlug: _activeEvent!.companySlug,
              companyName: _activeEvent!.targetCompany,
              retailChain: result.storeChainDetected,
              branch: result.branchDetected,
              receiptNumber: receiptNumber,
              extractedProducts: result.extractedProducts,
            ),
      );

      // Live Ingest into Cross-Chain Price Intelligence & Competitor Threat Catalog (0ms dynamic radar update)
      unawaited(
        ref
            .read(chainProductsIntelligenceServiceProvider)
            .ingestReceiptLive(receiptData: transactionData),
      );

      if (!mounted) return;

      // Reset image preview immediately
      setState(() {
        _receiptImages.clear();
        _receiptImageBytes.clear();
        _selectedPreviewIndex = 0;
      });

      // Route customer to prize game based on event settings or total purchase value
      final currentEvent = _activeEvent ?? widget.event;
      final currentEventId = currentEvent?.id ?? '';
      // Smart branch ID resolution (AIR-80 & Rule 8). No first-branch guess.
      final branchResolution =
          ReceiptBranchResolver.resolve(currentEvent, result.branchDetected);
      final String? resolvedBranchId = branchResolution.id;
      final String resolvedCanonicalBranchName = branchResolution.name;

      final branchIdentifier =
          (resolvedCanonicalBranchName.isNotEmpty
              ? resolvedCanonicalBranchName
              : resolvedBranchId) ??
          result.branchDetected.trim();
      final prizeNames =
          currentEvent?.availablePrizeNamesForBranch(branchIdentifier) ??
          <String>[];

      // Composite promotional bundle from matched rules evaluated earlier
      final compositeBundle = CompositePromotionalBundle.fromMatchedRules(
        matchedRulesList,
        fallbackTitle: result.matchedRewardValue.trim().isNotEmpty
            ? result.matchedRewardValue.trim()
            : (prizeNames.isNotEmpty ? prizeNames.first : 'هدية ترويجية مميزة'),
      );
      // Composite bundle chances govern (AIR-83)
      final totalChances = compositeBundle.matchedRules.isNotEmpty
          ? compositeBundle.totalChances
          : (result.chancesEarned > 0 ? result.chancesEarned : 1);

      final ruleLevelGame =
          (compositeBundle.resolvedGameType != null &&
              compositeBundle.resolvedGameType!.trim().isNotEmpty)
          ? compositeBundle.resolvedGameType!.trim()
          : null;
      final gameType =
          ruleLevelGame ??
          currentEvent?.gameType ??
          (totalValue >= 500 ? 'scratchCard' : 'spinTheWheel');

      if (gameType == 'directGift' || gameType == 'direct_gift') {
        final designatedPrizeObj =
            (currentEvent?.availablePrizes.isNotEmpty ?? false)
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

          resolvedIsVoucher =
              compositeBundle.totalVoucherValue > 0 ||
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
          resolvedIsVoucher =
              result.matchedRewardType == 'voucher' ||
              result.matchedRewardAmount > 0 ||
              designatedPrize.contains('فواتشر') ||
              designatedPrize.contains('قسيمة');
          resolvedUnitValue = resolvedIsVoucher
              ? (result.matchedRewardAmount > 0
                    ? result.matchedRewardAmount
                    : designatedPrizeObj?.unitValue)
              : 0.0;
        } else {
          designatedPrize =
              designatedPrizeObj?.name ??
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
            designatedPrize = resolvedLinkedGifts
                .map(
                  (g) => g.quantity > 1
                      ? '${g.quantity} × ${g.giftName}'
                      : g.giftName,
                )
                .join(' + ');
            resolvedIsVoucher = resolvedLinkedGifts.any((g) => g.isVoucher);
            resolvedUnitValue = resolvedIsVoucher
                ? resolvedLinkedGifts.fold<double>(
                    0.0,
                    (acc, g) => acc + g.totalMonetaryValue,
                  )
                : 0.0;
          } else if (resolvedIsVoucher ||
              (resolvedUnitValue != null && resolvedUnitValue > 0)) {
            final val = (resolvedUnitValue != null && resolvedUnitValue > 0)
                ? (resolvedUnitValue == resolvedUnitValue.roundToDouble()
                      ? resolvedUnitValue.toInt()
                      : resolvedUnitValue)
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
            : ((currentEvent?.allowMultipleChances ?? false)
                  ? totalChances
                  : 1);
        final enteredPhone = _customerPhoneController.text
            .toEnglishDigits()
            .trim();
        final enteredName = _customerNameController.text.trim();
        final isWaEnabled =
            currentEvent?.enableWhatsAppWinnerNotification ?? true;
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
              rewardChoiceGroups: compositeBundle.rewardChoiceGroups,
              baseLinkedGifts: compositeBundle.baseLinkedGifts,
              requireVoucherSerials:
                  currentEvent?.requireVoucherSerials ?? false,
              voucherSerialMode: currentEvent?.voucherSerialMode,
              customerPhone: enteredPhone,
              customerName: enteredName,
              retailChainName:
                  currentEvent?.retailChainName ?? result.storeChainDetected,
              branchName: resolvedCanonicalBranchName.isNotEmpty
                  ? resolvedCanonicalBranchName
                  : result.branchDetected,
              companyName: currentEvent?.targetCompany ?? '',
              receiptNumber: receiptNumber,
              companySlug: currentEvent?.companySlug,
              enableWhatsAppWinnerNotification: isWaEnabled,
            ),
          ),
        );
        _resetFormForNextCustomer();
      } else if (gameType == 'chooseGift') {
        final enteredPhone = _customerPhoneController.text
            .toEnglishDigits()
            .trim();
        final enteredName = _customerNameController.text.trim();
        final isWaEnabled =
            currentEvent?.enableWhatsAppWinnerNotification ?? true;
        final candidateGifts = compositeBundle.candidateGiftNames.isNotEmpty
            ? compositeBundle.candidateGiftNames
            : prizeNames;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChooseGiftScreen(
              transactionId: transactionRef.id,
              eventId: currentEventId,
              companySlug: currentEvent?.companySlug ?? '',
              prizes: candidateGifts.isNotEmpty ? candidateGifts : prizeNames,
              totalChances: totalChances,
              branchId: resolvedBranchId,
              customerPhone: enteredPhone,
              customerName: enteredName,
              enableWhatsAppWinnerNotification: isWaEnabled,
            ),
          ),
        );
        _resetFormForNextCustomer();
      } else if (gameType == 'scratch' ||
          gameType == 'scratchCard' ||
          (gameType.isEmpty && totalValue >= 500)) {
        final enteredPhone = _customerPhoneController.text
            .toEnglishDigits()
            .trim();
        final enteredName = _customerNameController.text.trim();
        final isWaEnabled =
            currentEvent?.enableWhatsAppWinnerNotification ?? true;
        final candidateGifts = compositeBundle.candidateGiftNames.isNotEmpty
            ? compositeBundle.candidateGiftNames
            : prizeNames;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ScratchCardScreen(
              transactionId: transactionRef.id,
              eventId: currentEventId,
              prizes: candidateGifts.isNotEmpty ? candidateGifts : prizeNames,
              totalChances: totalChances,
              branchId: resolvedBranchId,
              customerPhone: enteredPhone,
              customerName: enteredName,
              enableWhatsAppWinnerNotification: isWaEnabled,
            ),
          ),
        );
        _resetFormForNextCustomer();
      } else {
        final enteredPhone = _customerPhoneController.text
            .toEnglishDigits()
            .trim();
        final enteredName = _customerNameController.text.trim();
        final isWaEnabled =
            currentEvent?.enableWhatsAppWinnerNotification ?? true;
        final candidateGifts = compositeBundle.candidateGiftNames.isNotEmpty
            ? compositeBundle.candidateGiftNames
            : prizeNames;
        final branchFilteredPrizes =
            (currentEvent != null && currentEvent.allocatedPrizes.isNotEmpty)
            ? currentEvent.filterGiftsByBranchStock(
                candidateGifts: candidateGifts,
                branch: branchIdentifier,
              )
            : candidateGifts;
        final finalWheelPrizes = branchFilteredPrizes;

        if (finalWheelPrizes.isEmpty &&
            (currentEvent?.allocatedPrizes.isNotEmpty ?? false)) {
          final branchDisplay = resolvedCanonicalBranchName.isNotEmpty
              ? resolvedCanonicalBranchName
              : result.branchDetected;
          if (mounted) {
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      color: Theme.of(ctx).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'عذراً، نفدت الهدايا بالفرع',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                content: Text(
                  'الفاتورة صحيحة ومطابقة لشروط العرض، ولكن جميع أصناف الهدايا المخصصة لـ ($branchDisplay) رصيدها صفر حالياً.\nيرجى التواصل مع إدارة الحملة لإعادة تعبئة رصيد الهدايا.',
                  style: GoogleFonts.cairo(fontSize: 14),
                ),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      'حسناً',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          }
          _resetFormForNextCustomer();
          return;
        }

        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => SpinTheWheelScreen(
              transactionId: transactionRef.id,
              eventId: currentEventId,
              prizes: finalWheelPrizes,
              totalChances: totalChances,
              branchId: resolvedBranchId ?? branchIdentifier,
              branchName: resolvedCanonicalBranchName.isNotEmpty
                  ? resolvedCanonicalBranchName
                  : result.branchDetected,
              customerPhone: enteredPhone,
              customerName: enteredName,
              enableWhatsAppWinnerNotification: isWaEnabled,
            ),
          ),
        );
        _resetFormForNextCustomer();
      }
    } catch (e, stack) {
      debugPrint('Receipt processing error: $e\n$stack');
      if (mounted) {
        final kind = classifyReceiptException(e);
        _showIssue(
          kind,
          onPrimary: _receiptImages.isNotEmpty
              ? _submitAndValidateReceipt
              : null,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAiLoading = false;
          _aiPhase = 0;
          _aiPhaseText = '';
        });
      }
    }
  }

  bool get _isAr => ref.read(localeProvider).languageCode == 'ar';

  void _clearPhotosForRetake() {
    if (!mounted) return;
    setState(() {
      _receiptImages.clear();
      _receiptImageBytes.clear();
      _selectedPreviewIndex = 0;
    });
  }

  void _showIssue(
    ReceiptIssueKind kind, {
    List<ReceiptCheckChip> chips = const [],
    List<ReceiptIssueDetail> details = const [],
    List<String> extraReasons = const [],
    String? subtitle,
    VoidCallback? onPrimary,
  }) {
    if (!mounted) return;
    final spec = receiptIssueSpecs[kind]!;
    showReceiptIssueDialog(
      context: context,
      kind: kind,
      isArabic: _isAr,
      chips: chips,
      details: details,
      extraReasons: extraReasons.where((r) => r.trim().isNotEmpty).toList(),
      subtitleOverride: subtitle,
      onPrimary:
          onPrimary ??
          (spec.action == ReceiptIssueAction.retake
              ? _clearPhotosForRetake
              : null),
    );
  }

  /// Already-redeemed receipt: show when/where/what it was redeemed for (no personal data).
  void _showAlreadyRedeemed(ReceiptDuplicateCheckResult dup) {
    String fmtDate(String? iso) {
      final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
      if (d == null) return iso ?? '';
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(d.day)}/${two(d.month)}/${d.year}  ${two(d.hour)}:${two(d.minute)}';
    }

    final currency = ref.read(activeCountryProvider).currencySymbol;
    String gift(String v) =>
        RegExp(r'^\d+(\.\d+)?$').hasMatch(v) ? '$v $currency' : v;
    _showIssue(
      ReceiptIssueKind.alreadyRedeemed,
      details: [
        if (dup.receiptNumber.isNotEmpty)
          ReceiptIssueDetail(
            Icons.tag_rounded,
            'رقم الفاتورة',
            'Receipt no.',
            dup.receiptNumber,
          ),
        if ((dup.existingClaimedAt ?? '').isNotEmpty)
          ReceiptIssueDetail(
            Icons.event_available_rounded,
            'تاريخ الصرف',
            'Redeemed on',
            fmtDate(dup.existingClaimedAt),
          ),
        if ((dup.existingCampaignName ?? '').isNotEmpty)
          ReceiptIssueDetail(
            Icons.campaign_rounded,
            'الحملة',
            'Campaign',
            dup.existingCampaignName!,
          ),
        if ((dup.existingPrizeWon ?? '').isNotEmpty)
          ReceiptIssueDetail(
            Icons.card_giftcard_rounded,
            'الهدية / القسيمة',
            'Gift / voucher',
            gift(dup.existingPrizeWon!),
          ),
        if ((dup.existingBranch ?? '').isNotEmpty)
          ReceiptIssueDetail(
            Icons.storefront_rounded,
            'الفرع',
            'Branch',
            dup.existingBranch!,
          ),
      ],
    );
  }

  ReceiptIssueKind _kindForInvalidResult(
    AiReceiptAnalysisResult r,
    List<String> reasons,
    double minimumSpend,
  ) {
    final msg = '${r.message} ${reasons.join(' ')}';
    if (r.isHandwritten) return ReceiptIssueKind.handwritten;
    if (r.isTampered) return ReceiptIssueKind.tampered;
    if (r.isScreenCapture) return ReceiptIssueKind.screenCapture;
    if (!r.isThermalPosReceipt) return ReceiptIssueKind.notReceipt;
    final fromText = classifyConditionText(msg);
    if (fromText == ReceiptIssueKind.unreadable ||
        fromText == ReceiptIssueKind.incomplete ||
        fromText == ReceiptIssueKind.notReceipt) {
      return fromText;
    }
    final hasProducts =
        r.extractedProducts.any((p) => p.isTargetCompany) ||
        r.targetCompanyTotal > 0;
    if (!hasProducts) return ReceiptIssueKind.noProducts;
    if (_chainMet(r) == false) return ReceiptIssueKind.wrongChain;
    if (!r.isBranchMatched) return ReceiptIssueKind.wrongBranch;
    if (_dateMet(r) == false) return ReceiptIssueKind.outOfDate;
    if (minimumSpend > 0 && r.targetCompanyTotal < minimumSpend) {
      return ReceiptIssueKind.belowMinimum;
    }
    return reasons.isNotEmpty ? classifyConditionText(reasons.first) : fromText;
  }

  bool? _chainMet(AiReceiptAnalysisResult r) {
    final allowed = (_activeEvent?.retailChainName ?? '').trim();
    final got = r.storeChainDetected.trim();
    if (allowed.isEmpty || got.isEmpty) return null;
    String n(String x) => x
        .replaceAll(RegExp(r'[\sـ]'), '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');
    final g = n(got);
    return allowed
        .split('•')
        .map((c) => n(c))
        .where((c) => c.isNotEmpty)
        .any((c) => g.contains(c) || c.contains(g));
  }

  bool? _dateMet(AiReceiptAnalysisResult r) {
    final m = RegExp(
      r'(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})',
    ).firstMatch(r.receiptDate);
    final ev = _activeEvent;
    if (m == null || ev == null || (ev.startDate == null && ev.endDate == null)) {
      return null;
    }
    var y = int.parse(m.group(3)!);
    if (y < 100) y += 2000;
    final d = DateTime(y, int.parse(m.group(2)!), int.parse(m.group(1)!));
    final start = ev.startDate == null
        ? null
        : DateTime(ev.startDate!.year, ev.startDate!.month, ev.startDate!.day);
    final end = ev.endDate == null
        ? null
        : DateTime(ev.endDate!.year, ev.endDate!.month, ev.endDate!.day);
    if (start != null && d.isBefore(start)) return false;
    if (end != null && d.isAfter(end)) return false;
    return true;
  }

  List<ReceiptCheckChip> _receiptChips(
    AiReceiptAnalysisResult r, {
    required double minimumSpend,
    required String currency,
  }) {
    String num(double v) =>
        v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    final chain = _chainMet(r);
    final date = _dateMet(r);
    final hasProducts =
        r.extractedProducts.any((p) => p.isTargetCompany) ||
        r.targetCompanyTotal > 0;
    return [
      if (chain != null) ReceiptCheckChip('السلسلة', 'Chain', chain),
      ReceiptCheckChip('الفرع', 'Branch', r.isBranchMatched),
      if (date != null)
        ReceiptCheckChip(
          'التاريخ',
          'Date',
          date,
          value: r.receiptDate.isNotEmpty ? r.receiptDate : null,
        ),
      ReceiptCheckChip('المنتجات', 'Products', hasProducts),
      if (minimumSpend > 0)
        ReceiptCheckChip(
          'الحد الأدنى',
          'Min. spend',
          r.targetCompanyTotal >= minimumSpend,
          value: '${num(r.targetCompanyTotal)}/${num(minimumSpend)} $currency',
        ),
    ];
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

    if (_errorMessage != null ||
        (_activeEvent != null &&
            (!_activeEvent!.isActive || !_activeEvent!.isPromoterActive))) {
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
            message: isAr
                ? 'فكرة وشروط العرض + دليل وقواعد الحملة'
                : 'Offer brief, terms & campaign guide',
            waitDuration: const Duration(milliseconds: 400),
            child: IconButton.filledTonal(
              icon: Icon(
                Icons.campaign_rounded,
                size: isMobile ? 16 : 20,
                color: colorScheme.primary,
              ),
              style: isMobile
                  ? IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: const Size(30, 30),
                      padding: const EdgeInsets.all(5),
                    )
                  : null,
              padding: EdgeInsets.all(isMobile ? 5 : 8),
              constraints: isMobile ? const BoxConstraints() : null,
              visualDensity: isMobile
                  ? VisualDensity.compact
                  : VisualDensity.standard,
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
                size: isMobile ? 16 : 20,
                color: colorScheme.primary,
              ),
              style: isMobile
                  ? IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: const Size(30, 30),
                      padding: const EdgeInsets.all(5),
                    )
                  : null,
              padding: EdgeInsets.all(isMobile ? 5 : 8),
              constraints: isMobile ? const BoxConstraints() : null,
              visualDensity: isMobile
                  ? VisualDensity.compact
                  : VisualDensity.standard,
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
                size: isMobile ? 16 : 20,
                color: colorScheme.primary,
              ),
              style: isMobile
                  ? IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: const Size(30, 30),
                      padding: const EdgeInsets.all(5),
                    )
                  : null,
              padding: EdgeInsets.all(isMobile ? 5 : 8),
              constraints: isMobile ? const BoxConstraints() : null,
              visualDensity: isMobile
                  ? VisualDensity.compact
                  : VisualDensity.standard,
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
                    color: isMobile
                        ? colorScheme.surfaceContainerLowest
                        : colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(isMobile ? 20 : 28),
                      side: BorderSide(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: isMobile ? 0.6 : 0.4,
                        ),
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
                              borderRadius: BorderRadius.circular(
                                isMobile ? 18 : 22,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.28,
                                  ),
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
                                          color: Colors.black.withValues(
                                            alpha: 0.18,
                                          ),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                        width: 2.5,
                                      ),
                                    ),
                                    child: ClipOval(
                                      child: Image.network(
                                        event.companyLogoUrl,
                                        fit: BoxFit.contain,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                Icon(
                                                  Icons.business_rounded,
                                                  size: isMobile ? 32 : 38,
                                                  color: colorScheme.primary,
                                                ),
                                      ),
                                    ),
                                  ),
                                ],
                                Text(
                                  event.welcomeTitle.isNotEmpty
                                      ? event.welcomeTitle
                                      : strings.campaignOffersTitle,
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
                                    color: colorScheme.onPrimary.withValues(
                                      alpha: 0.92,
                                    ),
                                    fontSize: isMobile ? 12.5 : 14,
                                    height: 1.4,
                                  ),
                                ),
                                if (event.minimumSpend > 0) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.22,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.35,
                                        ),
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
                                color: colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.35,
                                  ),
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
                                          color: colorScheme.primary.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                                          isAr
                                              ? 'اختر الحملة / العرض المستهدف للفاتورة:'
                                              : 'Select Target Offer / Campaign:',
                                          style: GoogleFonts.cairo(
                                            fontSize: isMobile ? 12 : 13,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          '${_availableCompanyEvents.length} ${isAr ? 'عروض متاحة' : 'Offers'}',
                                          style: GoogleFonts.cairo(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color:
                                                colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    initialValue:
                                        (_isAutoMultiCampaignMode &&
                                            _availableCompanyEvents.length > 1)
                                        ? kAutoAllCampaignsId
                                        : _activeEvent?.id,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                      filled: true,
                                      fillColor: colorScheme.surface,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: colorScheme.outlineVariant,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: colorScheme.outlineVariant
                                              .withValues(alpha: 0.7),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: colorScheme.primary,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    items: [
                                      if (_availableCompanyEvents.length > 1)
                                        DropdownMenuItem<String>(
                                          value: kAutoAllCampaignsId,
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: colorScheme
                                                      .secondaryContainer,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Icon(
                                                  Icons.auto_awesome_rounded,
                                                  size: 15,
                                                  color: colorScheme
                                                      .onSecondaryContainer,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  isAr
                                                      ? '✨ فحص ذكي لكافة عروض الشركة (تحديد تلقائي)'
                                                      : '✨ Smart Auto-Match (All Company Offers)',
                                                  style: GoogleFonts.cairo(
                                                    fontSize: isMobile
                                                        ? 12
                                                        : 13,
                                                    fontWeight: FontWeight.bold,
                                                    color: colorScheme.primary,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ..._availableCompanyEvents.map((ev) {
                                        final minSpendStr = ev.minimumSpend > 0
                                            ? ' (${isAr ? 'حد أدنى' : 'Min'}: ${ev.minimumSpend.toInt()} ${activeCountry.currencySymbolFor(strings.languageCode)})'
                                            : '';
                                        return DropdownMenuItem<String>(
                                          value: ev.id,
                                          child: Row(
                                            children: [
                                              Icon(
                                                ev.gameType == 'wheel'
                                                    ? Icons.donut_large_rounded
                                                    : Icons
                                                          .card_giftcard_rounded,
                                                size: 16,
                                                color: colorScheme.primary,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  '${ev.eventName}$minSpendStr',
                                                  style: GoogleFonts.cairo(
                                                    fontSize: isMobile
                                                        ? 12
                                                        : 13,
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        colorScheme.onSurface,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                    ],
                                    onChanged: (selectedId) {
                                      if (selectedId == kAutoAllCampaignsId) {
                                        setState(() {
                                          _isAutoMultiCampaignMode = true;
                                          _resetFormForNextCustomer();
                                        });
                                      } else if (selectedId != null &&
                                          (selectedId != _activeEvent?.id ||
                                              _isAutoMultiCampaignMode)) {
                                        final newActive =
                                            _availableCompanyEvents.firstWhere(
                                              (e) => e.id == selectedId,
                                            );
                                        setState(() {
                                          _isAutoMultiCampaignMode = false;
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

                          TextField(
                            controller: _customerNameController,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setState(() {}),
                            style: GoogleFonts.cairo(
                              fontSize: isMobile ? 14 : 15,
                            ),
                            decoration: InputDecoration(
                              labelText: strings.customerNameOptional,
                              labelStyle: GoogleFonts.cairo(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              prefixIcon: Icon(
                                Icons.person_outline_rounded,
                                color: colorScheme.primary,
                                size: isMobile ? 22 : 24,
                              ),
                              suffixIcon:
                                  _customerNameController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.clear_rounded,
                                        size: 20,
                                      ),
                                      tooltip: isAr
                                          ? 'مسح اسم العميل'
                                          : 'Clear name',
                                      onPressed: () {
                                        _customerNameController.clear();
                                        setState(() {});
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.35),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: isMobile ? 14 : 16,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: colorScheme.outlineVariant,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: colorScheme.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),

                          SizedBox(height: isMobile ? 12 : 16),

                          TextField(
                            controller: _customerPhoneController,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.done,
                            onChanged: (_) => setState(() {}),
                            inputFormatters: [
                              const ArabicToEnglishDigitsFormatter.digitsOnly(),
                            ],
                            style: GoogleFonts.cairo(
                              fontSize: isMobile ? 14 : 15,
                            ),
                            decoration: InputDecoration(
                              labelText: strings.customerPhoneLabel,
                              labelStyle: GoogleFonts.cairo(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              prefixIcon: Icon(
                                Icons.phone_outlined,
                                color: colorScheme.primary,
                                size: isMobile ? 22 : 24,
                              ),
                              suffixIcon:
                                  _customerPhoneController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.clear_rounded,
                                        size: 20,
                                      ),
                                      tooltip: isAr
                                          ? 'مسح رقم الهاتف'
                                          : 'Clear phone',
                                      onPressed: () {
                                        _customerPhoneController.clear();
                                        setState(() {});
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.35),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: isMobile ? 14 : 16,
                              ),
                              helperText: isAr
                                  ? '📲 يُنصح بكتابة رقم الهاتف لإرسال تهنئة الهدية للعميل عبر الواتساب فوراً'
                                  : '📲 Enter phone number for instant WhatsApp gift notification',
                              helperStyle: GoogleFonts.cairo(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onTertiaryFixedVariant,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: colorScheme.outlineVariant,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: colorScheme.primary,
                                  width: 2,
                                ),
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
                                    : colorScheme.outlineVariant.withValues(
                                        alpha: 0.7,
                                      ),
                                width: _receiptImages.isNotEmpty ? 2.0 : 1.2,
                              ),
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.shadow.withValues(
                                    alpha: 0.04,
                                  ),
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
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(
                                            isMobile ? 14 : 18,
                                          ),
                                          decoration: BoxDecoration(
                                            color: colorScheme.primaryContainer
                                                .withValues(alpha: 0.5),
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
                                            onTap: () =>
                                                _pickImage(ImageSource.camera),
                                            child: FilledButton.icon(
                                              onPressed: () => _pickImage(
                                                ImageSource.camera,
                                              ),
                                              icon: const Icon(
                                                Icons.camera_alt_rounded,
                                                size: 22,
                                              ),
                                              label: Text(
                                                strings.captureReceiptAction,
                                                textAlign: TextAlign.center,
                                                style: GoogleFonts.cairo(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: isMobile
                                                      ? 14.5
                                                      : 16,
                                                ),
                                              ),
                                              style: FilledButton.styleFrom(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 20,
                                                  vertical: isMobile ? 15 : 17,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(18),
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
                                            onTap: () =>
                                                _pickImage(ImageSource.gallery),
                                            child: FilledButton.tonalIcon(
                                              onPressed: () => _pickImage(
                                                ImageSource.gallery,
                                              ),
                                              icon: const Icon(
                                                Icons.photo_library_rounded,
                                                size: 22,
                                              ),
                                              label: Text(
                                                strings.pickFromGalleryAction,
                                                textAlign: TextAlign.center,
                                                style: GoogleFonts.cairo(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: isMobile
                                                      ? 14.5
                                                      : 16,
                                                ),
                                              ),
                                              style: FilledButton.styleFrom(
                                                backgroundColor: colorScheme
                                                    .surfaceContainerHighest
                                                    .withValues(alpha: 0.85),
                                                foregroundColor:
                                                    colorScheme.primary,
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 20,
                                                  vertical: isMobile ? 15 : 17,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  side: BorderSide(
                                                    color: colorScheme.primary
                                                        .withValues(
                                                          alpha: 0.25,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        // Long Receipt Tip
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: colorScheme
                                                .surfaceContainerHighest
                                                .withValues(alpha: 0.5),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: colorScheme.outlineVariant
                                                  .withValues(alpha: 0.4),
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
                                                    color: colorScheme
                                                        .onSurfaceVariant,
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
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                          child: _buildReceiptImage(
                                            _receiptImages[_selectedPreviewIndex],
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
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.75),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.layers_rounded,
                                                      size: 14,
                                                      color: colorScheme
                                                          .primaryFixedDim,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      strings.isAr
                                                          ? 'جزء ${_selectedPreviewIndex + 1} من ${_receiptImages.length}'
                                                          : 'Part ${_selectedPreviewIndex + 1} of ${_receiptImages.length}',
                                                      style: GoogleFonts.cairo(
                                                        color: Colors.white,
                                                        fontSize: 11.5,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Tooltip(
                                                message:
                                                    strings.deletePartTooltip,
                                                waitDuration: const Duration(
                                                  milliseconds: 400,
                                                ),
                                                child: IconButton.filled(
                                                  icon: const Icon(
                                                    Icons.close_rounded,
                                                    color: Colors.white,
                                                    size: 18,
                                                  ),
                                                  style: IconButton.styleFrom(
                                                    backgroundColor:
                                                        colorScheme.error,
                                                    padding:
                                                        const EdgeInsets.all(6),
                                                  ),
                                                  onPressed: () => _removePart(
                                                    _selectedPreviewIndex,
                                                  ),
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
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: colorScheme.surface
                                                    .withValues(alpha: 0.9),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: colorScheme.primary
                                                      .withValues(alpha: 0.4),
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(
                                                          alpha: 0.15,
                                                        ),
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.cached_rounded,
                                                    size: 16,
                                                    color: colorScheme.primary,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    strings.isAr
                                                        ? 'إعادة التقاط / تغيير'
                                                        : 'Retake / Change',
                                                    style: GoogleFonts.cairo(
                                                      fontSize: 11.5,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color:
                                                          colorScheme.primary,
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
                                  separatorBuilder: (context, _) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    final isSelected =
                                        index == _selectedPreviewIndex;
                                    return InkWell(
                                      onTap: () => setState(
                                        () => _selectedPreviewIndex = index,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        width: 60,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? colorScheme.primary
                                                : colorScheme.outlineVariant,
                                            width: isSelected ? 2.5 : 1,
                                          ),
                                          color: isSelected
                                              ? colorScheme.primaryContainer
                                                    .withValues(alpha: 0.3)
                                              : colorScheme
                                                    .surfaceContainerHighest,
                                        ),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: _buildReceiptImage(
                                                _receiptImages[index],
                                                fit: BoxFit.cover,
                                                compact: true,
                                              ),
                                            ),
                                            Positioned(
                                              bottom: 2,
                                              left: 2,
                                              right: 2,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 1,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.75),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  strings.partIndexLabel(
                                                    index + 1,
                                                  ),
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
                                  icon: const Icon(
                                    Icons.add_a_photo_rounded,
                                    size: 20,
                                  ),
                                  label: Text(
                                    strings.addNextReceiptPartBtn,
                                    style: GoogleFonts.cairo(
                                      fontSize: isMobile ? 13.5 : 14.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  style: FilledButton.styleFrom(
                                    padding: EdgeInsets.symmetric(
                                      vertical: isMobile ? 12 : 14,
                                      horizontal: 16,
                                    ),
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 6,
                                  ),
                                ),
                              ),
                            ),
                          ],

                          // 4. M3 Action Button & Progress Tracker
                          if (_receiptImages.isNotEmpty) ...[
                            SizedBox(height: isMobile ? 16 : 22),
                            if (_isAiLoading) ...[
                              OptimisticReceiptScannerCard(
                                imageBytes: _previewImageBytes,
                                activePhase: _aiPhase,
                                statusText: _aiPhaseText,
                                calibrationResult: _latestCalibration,
                              ),
                              const SizedBox(height: 16),
                            ],
                            M3ActionButton(
                              width: double.infinity,
                              label: _isAiLoading
                                  ? strings.auditingProgressText
                                  : (_receiptImages.length > 1
                                        ? strings.analyzeMultiPartsBtn(
                                            _receiptImages.length,
                                          )
                                        : strings.auditReceiptActionBtn),
                              icon: Icons.auto_awesome_rounded,
                              isLoading: _isAiLoading,
                              variant: M3ButtonVariant.filled,
                              height: isMobile ? 50 : 54,
                              onPressed: _isAiLoading
                                  ? null
                                  : _submitAndValidateReceipt,
                            ),
                          ],

                          // 5. Terms & Conditions (M3 Card Note)
                          if (event.termsAndConditions.isNotEmpty) ...[
                            SizedBox(height: isMobile ? 18 : 24),
                            Container(
                              padding: EdgeInsets.all(isMobile ? 14 : 18),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(
                                    alpha: 0.4,
                                  ),
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
      final cleanReceiptNumber =
          (receiptNumber.isNotEmpty
                  ? receiptNumber
                  : "REJ_${DateTime.now().millisecondsSinceEpoch}")
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
                'uploaderUid':
                    ref.read(firebaseAuthProvider).currentUser?.uid ?? '',
              },
            );

            if (kIsWeb) {
              await storageRef
                  .putData(allBytesList[index], metadata)
                  .timeout(const Duration(seconds: 10));
            } else if (index < allImagesList.length) {
              await storageRef
                  .putFile(File(allImagesList[index].path), metadata)
                  .timeout(const Duration(seconds: 10));
            }
            final url = await storageRef.getDownloadURL().timeout(
              const Duration(seconds: 8),
            );
            uploadedImageUrls.add(url);
            uploadedStoragePaths.add(sPath);
          } catch (e) {
            debugPrint(
              'Storage upload for rejected receipt part $partNum skipped or timed out: $e',
            );
            final fallbackUrl =
                'data:image/jpeg;base64,${base64Encode(allBytesList[index])}';
            uploadedImageUrls.add(fallbackUrl);
            uploadedStoragePaths.add(sPath);
          }
        }),
      );

      final String primaryImageUrl = uploadedImageUrls.isNotEmpty
          ? uploadedImageUrls.first
          : '';
      final String primaryStoragePath = uploadedStoragePaths.isNotEmpty
          ? uploadedStoragePaths.first
          : '';

      // Rejected receipts are logged as new docs; anonymous reps cannot query
      // existing receipts (firestore.rules), so there is no client-side lookup.
      final docRef = firestore.collection('receipts_transactions').doc();
      final Map<String, dynamic> transactionData = {
        'receipt_number': receiptNumber.isNotEmpty
            ? receiptNumber
            : cleanReceiptNumber,
        'is_valid': false,
        'status': 'rejected',
        'rejection_reason': rejectionReason,
        'unfulfilled_conditions': unfulfilledConditions,
        'total_value': totalValue,
        'target_company_total': totalValue,
        'receipt_date': result.receiptDate,
        'extracted_products': result.extractedProducts
            .map((p) => p.toJson())
            .toList(),
        'store_chain_detected': result.storeChainDetected,
        'branch_detected': result.branchDetected,
        'branch_id': ReceiptBranchResolver.resolve(_activeEvent ?? widget.event, result.branchDetected).id ?? '',
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
        if (uploadedStoragePaths.length > 1)
          'storage_paths': uploadedStoragePaths,
        'parts_count': allBytesList.length,
        'customerPhone': _customerPhoneController.text.toEnglishDigits().trim(),
        'customerName': _customerNameController.text.trim(),
        'campaignId': activeEvent.id,
        'submittedByUid': ref.read(firebaseAuthProvider).currentUser?.uid ?? '',
        'companySlug': activeEvent.companySlug,
        'targetCompany': activeEvent.targetCompany,
        'analysis_duration_seconds': result.durationSeconds,
        'analysis_duration_ms': result.durationMs,
        'ai_kpi_rating': result.kpiRating,
        'chances_earned': 0,
        'game_played': false,
        'prize_won': null,
      };

      transactionData['timestamp'] = FieldValue.serverTimestamp();
      await docRef.set(transactionData);

      // Harvest discovered products asynchronously even if receipt didn't meet spend threshold
      unawaited(
        ref
            .read(aiProductDiscoveryServiceProvider)
            .autoHarvestFromReceiptAnalysis(
              companySlug: activeEvent.companySlug,
              companyName: activeEvent.targetCompany,
              retailChain: result.storeChainDetected,
              branch: result.branchDetected,
              receiptNumber: receiptNumber,
              extractedProducts: result.extractedProducts,
            ),
      );

      // Live Ingest into Cross-Chain Price Intelligence & Competitor Threat Catalog (0ms dynamic radar update)
      unawaited(
        ref
            .read(chainProductsIntelligenceServiceProvider)
            .ingestReceiptLive(receiptData: transactionData),
      );
    } catch (e) {
      debugPrint(
        'Error recording rejected receipt transaction to Firestore: $e',
      );
    }
  }
}
