import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:excel/excel.dart' hide Border;
import '../../../core/services/firebase_service.dart';
import '../../../core/services/company_gifts_service.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/arabic_numbers_utils.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/widgets/switch_point_branding.dart';
import '../../../core/widgets/m3_button_groups.dart';
import '../../admin/domain/event_model.dart';
import '../../admin/domain/company_gift_model.dart';
import '../../../core/utils/file_download_helper.dart';
import '../../../core/widgets/portal_screen_header_card.dart';

/// Data structure representing aggregated prize stock metrics across events & branches
class AggregatedGiftStock {
  final String giftId;
  final String giftName;
  final String sku;
  final int totalAllocated;
  final int totalClaimed;
  final int totalRemaining;
  final Map<String, int> branchRemainingMap; // branchName -> remaining
  final Map<String, int> branchAllocatedMap; // branchName -> allocated
  final List<String> eventNames;
  final String giftType;
  final double unitValue;

  AggregatedGiftStock({
    required this.giftId,
    required this.giftName,
    this.sku = '',
    required this.totalAllocated,
    required this.totalClaimed,
    required this.totalRemaining,
    required this.branchRemainingMap,
    required this.branchAllocatedMap,
    required this.eventNames,
    this.giftType = 'product',
    this.unitValue = 0.0,
  });

  bool get isVoucher {
    if (giftType == 'voucher') return true;
    if (giftType == 'product') return false;
    final clean = giftName.toLowerCase();
    return unitValue > 0 &&
        (clean.contains('فواتشر') ||
            clean.contains('فوتشر') ||
            clean.contains('قسيمة') ||
            clean.contains('قسائم') ||
            clean.contains('كارت مشتريات') ||
            clean.contains('كوبون') ||
            clean.contains('voucher') ||
            clean.contains('coupon'));
  }

  double get totalMonetaryBudget => isVoucher ? (totalAllocated * unitValue) : 0.0;
  double get claimedMonetaryValue => isVoucher ? (totalClaimed * unitValue) : 0.0;
  double get remainingMonetaryValue => isVoucher ? (totalRemaining * unitValue) : 0.0;

  double get depletionRate => totalAllocated > 0
      ? (totalClaimed / totalAllocated).clamp(0.0, 1.0)
      : 0.0;

  bool get isOutOfStock => totalRemaining <= 0;
  bool get isLowStock => !isOutOfStock && (totalRemaining <= 5 || (totalAllocated > 0 && totalRemaining / totalAllocated < 0.20));
  bool get isHealthy => !isOutOfStock && !isLowStock;
}

/// Enterprise-grade real-time Prizes & Stock Balance System (منظومة رصيد وجرد الهدايا والمخزون اللحظي)
class CompanyPrizesStockReportScreen extends ConsumerStatefulWidget {
  final String lockedCompanySlug;
  final String lockedCompanyName;
  final String? initialEventId;

  /// Single-campaign session (`/ep/` links). When set, the screen shows only
  /// this campaign, cannot switch to another one or to "all campaigns", reads
  /// receipts by `campaignId`, and hides the stock movements ledger
  /// (`gift_stock_movements` has no `eventId`, so it cannot be scoped).
  final String? lockedEventId;

  /// Hides every quota-editing action. Defaults to true: the direct client
  /// write (`updateBranchPrizeAllocation`) is admin-only in the rules and is
  /// not transactional; quota edits belong to the Balances tab (callable).
  final bool isReadOnly;
  final bool isEmbedded;
  final VoidCallback? onBack;

  const CompanyPrizesStockReportScreen({
    super.key,
    required this.lockedCompanySlug,
    required this.lockedCompanyName,
    this.initialEventId,
    this.lockedEventId,
    this.isReadOnly = true,
    this.isEmbedded = false,
    this.onBack,
  });

  /// Keeps only the locked campaign when [lockedEventId] is set.
  @visibleForTesting
  static List<EventModel> scopeEventsToLock(List<EventModel> events, String? lockedEventId) {
    final locked = lockedEventId?.trim() ?? '';
    if (locked.isEmpty) return events;
    return events.where((e) => e.id == locked).toList();
  }

  static CompanyGiftModel? findMatchingMasterGift(
    AllocatedPrize prize,
    List<CompanyGiftModel> masterGifts,
  ) =>
      _CompanyPrizesStockReportScreenState.findMatchingMasterGift(prize, masterGifts);

  @override
  ConsumerState<CompanyPrizesStockReportScreen> createState() =>
      _CompanyPrizesStockReportScreenState();
}

class _CompanyPrizesStockReportScreenState
    extends ConsumerState<CompanyPrizesStockReportScreen> {
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  bool get _isEventLocked => (widget.lockedEventId?.trim() ?? '').isNotEmpty;

  /// Campaign selection entry point; ignored in a locked single-campaign session.
  void _selectEvent(String? eventId) {
    if (_isEventLocked) return;
    setState(() => _selectedEventId = eventId);
  }

  // Search & Filter State
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedEventId; // null = all campaigns
  String? _selectedBranch; // null = all branches
  String _stockStatusFilter = 'ALL'; // 'ALL', 'AVAILABLE', 'LOW', 'OUT'
  int _viewMode = 0; // 0: Itemized SKU, 1: Branch Breakdown, 2: Campaign Breakdown, 3: Supply & Movements Ledger
  String _movementTypeFilter = 'ALL'; // 'ALL', 'supply_batch', 'adjustment', 'campaign'
  String? _movementGiftFilter; // null = all gifts
  DateTime _selectedDate = DateTime.now();
  bool _isAllTime = false;

  // Memoized stream lifecycle outside build() per Rule 9
  String? _lastStreamsKey;
  Stream<QuerySnapshot>? _eventsStream;
  Stream<QuerySnapshot>? _giftsStream;
  Stream<QuerySnapshot>? _transactionsStream;
  final Map<String, Stream<List<GiftStockMovement>>> _stockMovementsStreams = {};

  Stream<List<GiftStockMovement>> _ensureStockMovementsStream(String companySlug, {String? giftId}) {
    final key = '${companySlug}_${giftId ?? 'all'}';
    return _stockMovementsStreams.putIfAbsent(
      key,
      () => ref.read(companyGiftsServiceProvider).stockMovementsStream(companySlug, giftId: giftId),
    );
  }

  void _ensureStreams(FirebaseFirestore firestore, String slug) {
    final effectiveKey = '${slug}_${_selectedEventId ?? 'all'}';
    if (_lastStreamsKey != effectiveKey || _transactionsStream == null) {
      _lastStreamsKey = effectiveKey;

      if (_eventsStream == null) {
        Query eventsQuery = firestore.collection('events');
        if (slug.isNotEmpty) {
          eventsQuery = eventsQuery.where('companySlug', isEqualTo: widget.lockedCompanySlug.trim());
        }
        if (_isEventLocked) {
          eventsQuery = eventsQuery.where(FieldPath.documentId, isEqualTo: widget.lockedEventId!.trim());
        }
        _eventsStream = eventsQuery.snapshots();
      }

      _giftsStream ??= firestore
          .collection('company_gifts')
          .where('companySlug', isEqualTo: slug)
          .snapshots();

      Query transactionsQuery = firestore.collection('receipts_transactions');
      if (_selectedEventId != null && _selectedEventId != 'ALL' && _selectedEventId != 'all') {
        transactionsQuery = transactionsQuery.where('campaignId', isEqualTo: _selectedEventId);
        if (slug.isNotEmpty) {
          transactionsQuery = transactionsQuery.where('companySlug', isEqualTo: widget.lockedCompanySlug.trim());
        }
      } else if (slug.isNotEmpty) {
        transactionsQuery = transactionsQuery.where('companySlug', isEqualTo: widget.lockedCompanySlug.trim());
      }
      _transactionsStream = transactionsQuery.snapshots();
    }
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme,
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
        _isAllTime = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (_isEventLocked) {
      // Locked before the first build so _ensureStreams never opens a company-wide query.
      _selectedEventId = widget.lockedEventId!.trim();
    } else if (widget.initialEventId != null && widget.initialEventId!.isNotEmpty) {
      _selectedEventId = widget.initialEventId;
    }
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void didUpdateWidget(covariant CompanyPrizesStockReportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isEventLocked) {
      final locked = widget.lockedEventId!.trim();
      if (_selectedEventId != locked) {
        setState(() => _selectedEventId = locked);
      }
      return;
    }
    if (widget.initialEventId != oldWidget.initialEventId &&
        widget.initialEventId != null &&
        widget.initialEventId!.isNotEmpty) {
      setState(() {
        _selectedEventId = widget.initialEventId;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _exportExcelReport({
    required List<AggregatedGiftStock> gifts,
    required AppStrings strings,
    required bool isAr,
  }) async {
    try {
      final excel = Excel.createExcel();

      // Sheet 1: Gifts & Prizes Stock
      final String giftsSheetName = isAr ? 'رصيد وجرد الهدايا' : 'Gifts Stock';
      excel.rename('Sheet1', giftsSheetName);
      final Sheet giftsSheet = excel[giftsSheetName];

      giftsSheet.appendRow([
        TextCellValue(isAr ? 'كود الهدية (SKU)' : 'Gift SKU'),
        TextCellValue(isAr ? 'اسم الهدية / الصنف' : 'Gift Name'),
        TextCellValue(isAr ? 'النوع' : 'Type'),
        TextCellValue(isAr ? 'القيمة التقديرية (ج.م)' : 'Unit Value (EGP)'),
        TextCellValue(isAr ? 'إجمالي المخصص' : 'Total Allocated'),
        TextCellValue(isAr ? 'المنصرف / المستلم' : 'Claimed / Awarded'),
        TextCellValue(isAr ? 'الرصيد المتبقي' : 'Remaining Stock'),
        TextCellValue(isAr ? 'نسبة الاستنفاد' : 'Depletion Rate'),
        TextCellValue(isAr ? 'حالة المخزون' : 'Stock Status'),
        TextCellValue(isAr ? 'توزيع الفروع' : 'Branches Breakdown'),
        TextCellValue(isAr ? 'الحملات المرتبطة' : 'Campaigns'),
      ]);

      for (final g in gifts) {
        final branchesInfo = g.branchRemainingMap.entries
            .map((e) => '${e.key}: ${e.value}')
            .join(' | ');
        final campaignsInfo = g.eventNames.join(' | ');
        final status = g.isOutOfStock
            ? (isAr ? 'نفد المخزون' : 'Out of Stock')
            : (g.isLowStock ? (isAr ? 'مخزون منخفض' : 'Low Stock') : (isAr ? 'متوفر' : 'In Stock'));

        giftsSheet.appendRow([
          TextCellValue(g.sku),
          TextCellValue(g.giftName),
          TextCellValue(g.isVoucher ? (isAr ? 'فواتشر / قسيمة' : 'Voucher') : (isAr ? 'هدية عينية' : 'Physical Item')),
          DoubleCellValue(double.parse(g.unitValue.toStringAsFixed(2))),
          IntCellValue(g.totalAllocated),
          IntCellValue(g.totalClaimed),
          IntCellValue(g.totalRemaining),
          TextCellValue('${(g.depletionRate * 100).toStringAsFixed(1)}%'),
          TextCellValue(status),
          TextCellValue(branchesInfo),
          TextCellValue(campaignsInfo),
        ]);
      }

      final fileBytes = excel.encode();
      if (fileBytes != null) {
        final now = DateTime.now();
        final dateStr = '${now.year}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}';
        final cleanName = widget.lockedCompanyName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), '').replaceAll(' ', '_');
        final fileName = 'Tashil_Stock_${cleanName}_$dateStr.xlsx';

        downloadFileBytes(
          bytes: fileBytes,
          fileName: fileName,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isAr
                        ? 'تم تحميل وتنزيل تقرير رصيد وجرد الهدايا بنجاح ($fileName)'
                        : 'Prizes & stock Excel report downloaded successfully ($fileName)',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: colorScheme.tertiary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${isAr ? "خطأ في تصدير Excel: " : "Excel export error: "}$e'),
          backgroundColor: colorScheme.onErrorContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static String _formatDate(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $period';
  }



  void _showAdjustBranchAllocationDialog({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required String branchName,
    required String branchId,
    required String eventId,
    required String eventName,
    required String giftId,
    required String giftName,
    required int currentAllocated,
    required int currentClaimed,
    required int currentRemaining,
    required String companySlug,
    required List<CompanyGiftModel> masterGifts,
    bool initialDirectMode = false,
  }) {
    if (widget.isReadOnly) return; // TAG-79: report is read-only from the portal
    // Find master gift if available to show warehouse inventory
    final normGiftKey = giftId.trim().toLowerCase();
    final normGiftName = giftName.trim().toLowerCase();
    CompanyGiftModel? masterGift;
    try {
      masterGift = masterGifts.firstWhere(
        (g) => g.id.trim().toLowerCase() == normGiftKey || g.giftName.trim().toLowerCase() == normGiftName,
      );
    } catch (_) {}

    final masterAvailable = masterGift?.availableQuantity ?? 0;
    final isVoucher = masterGift?.isVoucher ?? (giftName.contains('فواتشر') || giftName.contains('voucher'));
    final unitLabel = isVoucher ? (isAr ? 'كارت' : 'cards') : (isAr ? 'قطعة' : 'pcs');

    final TextEditingController directQtyController = TextEditingController(text: '$currentAllocated');
    final TextEditingController additionalQtyController = TextEditingController();
    final TextEditingController notesController = TextEditingController();
    bool isDirectMode = initialDirectMode;
    bool isSaving = false;
    int additionalQty = 0;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            int newAllocated;
            int effectiveAdd;

            if (isDirectMode) {
              final parsedDirect = directQtyController.text.trim().toIntOrNull() ?? currentAllocated;
              newAllocated = parsedDirect.clamp(0, 999999);
              effectiveAdd = newAllocated - currentAllocated;
            } else {
              final parsedAdd = additionalQtyController.text.trim().toIntOrNull() ?? 0;
              effectiveAdd = parsedAdd != 0 ? parsedAdd : additionalQty;
              newAllocated = (currentAllocated + effectiveAdd).clamp(0, 999999);
            }

            final newRemaining = (currentRemaining + effectiveAdd).clamp(0, newAllocated);

            return AlertDialog(
              backgroundColor: colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.storefront_rounded, color: colorScheme.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.adjustBranchAllocationTitle,
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 17, color: colorScheme.onSurface),
                        ),
                        Text(
                          '$branchName • $giftName',
                          style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.primary, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      strings.adjustBranchAllocationSubtitle,
                      style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),

                    // Switcher between Direct Total vs Quick +/-
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                setDialogState(() {
                                  isDirectMode = true;
                                  directQtyController.text = '$newAllocated';
                                });
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDirectMode ? colorScheme.primary : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.edit_note_rounded,
                                      size: 16,
                                      color: isDirectMode ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isAr ? 'تعديل / تصفير الحصة' : 'Set Quota (0)',
                                      style: GoogleFonts.cairo(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isDirectMode ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                setDialogState(() {
                                  isDirectMode = false;
                                  additionalQtyController.text = '';
                                  additionalQty = 0;
                                });
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: !isDirectMode ? colorScheme.primary : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_circle_outline_rounded,
                                      size: 16,
                                      color: !isDirectMode ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isAr ? 'تزويد سريع (+)' : 'Quick Supply (+)',
                                      style: GoogleFonts.cairo(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: !isDirectMode ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
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

                    const SizedBox(height: 12),

                    // Event Context Badge
                    if (eventName.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.campaign_rounded, size: 16, color: colorScheme.outline),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${isAr ? 'الحملة الترويجية:' : 'Campaign:'} $eventName',
                                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Current KPI Matrix
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildDialogKpiCell(
                                  label: strings.currentBranchAllocation,
                                  value: '$currentAllocated $unitLabel',
                                  color: colorScheme.onSurface,
                                  colorScheme: colorScheme,
                                ),
                              ),
                              Container(width: 1, height: 36, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                              Expanded(
                                child: _buildDialogKpiCell(
                                  label: strings.currentBranchClaimed,
                                  value: '$currentClaimed $unitLabel',
                                  color: colorScheme.secondary,
                                  colorScheme: colorScheme,
                                ),
                              ),
                              Container(width: 1, height: 36, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                              Expanded(
                                child: _buildDialogKpiCell(
                                  label: strings.currentBranchRemaining,
                                  value: '$currentRemaining $unitLabel',
                                  color: currentRemaining <= 0 ? colorScheme.error : colorScheme.tertiary,
                                  colorScheme: colorScheme,
                                ),
                              ),
                            ],
                          ),
                          if (masterGift != null) ...[
                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.warehouse_rounded, size: 15, color: colorScheme.onPrimaryFixedVariant),
                                    const SizedBox(width: 6),
                                    Text(
                                      strings.availableMasterStockLabel,
                                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$masterAvailable $unitLabel ${isAr ? 'متاح بالمخزن' : 'available'}',
                                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onPrimaryFixedVariant),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    if (isDirectMode) ...[
                      // Direct Mode: Zero Button + Presets + Input
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isAr ? 'تعيين الحصة مباشرة:' : 'Set Target Quota:',
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                          ),
                          ActionChip(
                            avatar: Icon(Icons.bolt_rounded, size: 16, color: colorScheme.error),
                            label: Text(
                              strings.zeroAllocationBtn,
                              style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onErrorContainer),
                            ),
                            backgroundColor: colorScheme.error.withValues(alpha: 0.1),
                            side: BorderSide(color: colorScheme.error.withValues(alpha: 0.3)),
                            onPressed: isSaving
                                ? null
                                : () {
                                    setDialogState(() {
                                      directQtyController.text = '0';
                                    });
                                  },
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [0, 10, 25, 50, 100, 200].map((preset) {
                          return ActionChip(
                            label: Text('$preset $unitLabel', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                            backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                            onPressed: isSaving
                                ? null
                                : () {
                                    setDialogState(() {
                                      directQtyController.text = '$preset';
                                    });
                                  },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: directQtyController,
                        keyboardType: TextInputType.number,
                        enabled: !isSaving,
                        onChanged: (val) {
                          setDialogState(() {});
                        },
                        decoration: InputDecoration(
                          labelText: strings.setAllocationDirectlyLabel,
                          hintText: isAr ? 'أدخل الرقم الجديد (مثال: 0 أو 50)' : 'Enter new amount (e.g. 0, 50)',
                          prefixIcon: const Icon(Icons.edit_rounded),
                          suffixText: unitLabel,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          filled: true,
                          fillColor: colorScheme.surface,
                        ),
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                      ),
                    ] else ...[
                      // Quick Incremental Mode
                      Text(
                        isAr ? 'تزويد سريع (+):' : 'Quick Increment (+):',
                        style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [1, 5, 10, 25, 50].map((inc) {
                          return ActionChip(
                            avatar: Icon(Icons.add_circle_outline_rounded, size: 16, color: colorScheme.primary),
                            label: Text('+$inc $unitLabel', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                            backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                            onPressed: isSaving
                                ? null
                                : () {
                                    setDialogState(() {
                                      final currentVal = additionalQtyController.text.trim().toIntOrNull() ?? 0;
                                      final newVal = currentVal + inc;
                                      additionalQtyController.text = '$newVal';
                                      additionalQty = newVal;
                                    });
                                  },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: additionalQtyController,
                        keyboardType: const TextInputType.numberWithOptions(signed: true),
                        enabled: !isSaving,
                        onChanged: (val) {
                          setDialogState(() {
                            additionalQty = val.trim().toIntOrNull() ?? 0;
                          });
                        },
                        decoration: InputDecoration(
                          labelText: strings.addQuantityLabel,
                          hintText: isAr ? 'مثال: 5 أو 10 أو -2' : 'e.g. 5, 10, or -2',
                          prefixIcon: const Icon(Icons.add_box_rounded),
                          suffixText: unitLabel,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          filled: true,
                          fillColor: colorScheme.surface,
                        ),
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Live Result Box
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: effectiveAdd > 0
                            ? colorScheme.tertiary.withValues(alpha: 0.12)
                            : (effectiveAdd < 0 ? colorScheme.secondary.withValues(alpha: 0.12) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: effectiveAdd > 0
                              ? colorScheme.tertiary.withValues(alpha: 0.4)
                              : (effectiveAdd < 0 ? colorScheme.secondary.withValues(alpha: 0.4) : colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            effectiveAdd >= 0 ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                            size: 20,
                            color: effectiveAdd > 0 ? colorScheme.onTertiaryFixedVariant : (effectiveAdd < 0 ? colorScheme.onSecondaryContainer : colorScheme.outline),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  strings.newTotalBranchAllocation,
                                  style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                ),
                                Text(
                                  '$newAllocated $unitLabel  (${isAr ? 'المتبقي الجديد للسحب:' : 'New Left:'} $newRemaining $unitLabel)',
                                  style: GoogleFonts.cairo(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: effectiveAdd > 0 ? colorScheme.onTertiaryContainer : (effectiveAdd < 0 ? colorScheme.onSecondaryContainer : colorScheme.onSurface),
                                  ),
                                ),
                                if (effectiveAdd < 0)
                                  Text(
                                    isAr
                                        ? 'سيتم إرجاع ${effectiveAdd.abs()} $unitLabel إلى رصيد المخزن المركزي للشركة'
                                        : '${effectiveAdd.abs()} $unitLabel will return to master stock',
                                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onSecondaryContainer),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Notes Field
                    TextField(
                      controller: notesController,
                      enabled: !isSaving,
                      decoration: InputDecoration(
                        labelText: strings.supplyReasonOptionalLabel,
                        hintText: isAr ? 'مثال: تعديل الحصة وتصفير الرصيد' : 'e.g. Quota adjustment & stock zeroing',
                        prefixIcon: const Icon(Icons.note_alt_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        filled: true,
                        fillColor: colorScheme.surface,
                      ),
                      style: GoogleFonts.cairo(fontSize: 13),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: Text(isAr ? 'إلغاء' : 'Cancel', style: GoogleFonts.cairo()),
                ),
                FilledButton.icon(
                  onPressed: isSaving || (effectiveAdd == 0 && !isDirectMode && additionalQtyController.text.trim().isEmpty)
                      ? null
                      : () async {
                          if (newAllocated < 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(isAr ? 'لا يمكن أن تكون الحصة سالبة' : 'Allocation cannot be negative', style: GoogleFonts.cairo()),
                                backgroundColor: colorScheme.error,
                              ),
                            );
                            return;
                          }

                          setDialogState(() => isSaving = true);
                          try {
                            await ref.read(companyGiftsServiceProvider).updateBranchPrizeAllocation(
                              companySlug: companySlug,
                              eventId: eventId,
                              branchName: branchName,
                              branchId: branchId,
                              giftKey: giftId.isNotEmpty ? giftId : giftName,
                              newAllocatedQuantity: newAllocated,
                              notes: notesController.text.trim(),
                              performedBy: 'مدير الشركة',
                            );

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          strings.branchAllocationSuccessMsg,
                                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: colorScheme.onTertiaryFixedVariant,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(AppErrorHandler.getFriendlyMessage(e), style: GoogleFonts.cairo()),
                                  backgroundColor: colorScheme.error,
                                ),
                              );
                            }
                          }
                        },
                  icon: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    strings.saveBranchAllocationBtn,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditGiftAllocationsDialog({
    required AggregatedGiftStock gift,
    required CompanyGiftModel? masterGift,
    required String companySlug,
    required List<EventModel> events,
    required AppStrings strings,
    required bool isAr,
  }) {
    if (widget.isReadOnly) return; // TAG-79: report is read-only from the portal
    final colorScheme = Theme.of(context).colorScheme;
    final unitLabel = (masterGift?.isVoucher ?? false) ? (isAr ? 'كارت' : 'cards') : (isAr ? 'قطعة' : 'pcs');

    // Collect all matching branch allocations across events for this gift
    final List<Map<String, dynamic>> branchAllocations = [];
    final normGiftName = gift.giftName.trim().toLowerCase();
    final normGiftId = gift.giftId.trim().toLowerCase();
    final targetSlug = companySlug.toLowerCase().trim();
    final TextEditingController bulkDistributeController = TextEditingController();

    for (final event in events) {
      if (event.companySlug.toLowerCase().trim() != targetSlug) continue;

      // 1. Gather all unique branches for this event
      final List<String> eventBranches = [];
      if (event.branchNames.isNotEmpty) {
        for (final b in event.branchNames) {
          final trimmed = b.trim();
          if (trimmed.isNotEmpty && !eventBranches.contains(trimmed)) {
            eventBranches.add(trimmed);
          }
        }
      }

      // Also gather any branches that already have prize allocations
      for (final prize in event.allocatedPrizes) {
        final bName = prize.branchName.trim();
        if (bName.isNotEmpty && !eventBranches.contains(bName)) {
          eventBranches.add(bName);
        }
      }

      if (eventBranches.isEmpty) {
        eventBranches.add(isAr ? 'كافة الفروع / عام' : 'All Branches');
      }

      // 2. Build allocation row for each branch
      for (final bName in eventBranches) {
        AllocatedPrize? matchedPrize;
        for (final prize in event.allocatedPrizes) {
          final pName = prize.name.trim().toLowerCase();
          final pId = prize.giftId.trim().toLowerCase();
          final pBranch = prize.branchName.trim().toLowerCase();
          final isGiftMatch = pName == normGiftName || (normGiftId.isNotEmpty && pId == normGiftId);
          final isBranchMatch = pBranch == bName.toLowerCase() || (bName == (isAr ? 'كافة الفروع / عام' : 'All Branches') && pBranch.isEmpty);
          if (isGiftMatch && isBranchMatch) {
            matchedPrize = prize;
            break;
          }
        }

        final allocated = matchedPrize?.allocatedQuantity ?? 0;
        final remaining = matchedPrize?.remainingQuantity ?? 0;
        final claimed = matchedPrize != null ? (allocated - remaining).clamp(0, allocated) : 0;

        branchAllocations.add({
          'eventId': event.id,
          'eventName': event.eventName,
          'branchId': matchedPrize?.branchId ?? '',
          'branchName': bName,
          'currentAllocated': allocated,
          'currentClaimed': claimed,
          'currentRemaining': remaining,
          'controller': TextEditingController(text: '$allocated'),
        });
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        bool isSaving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.tune_rounded, color: colorScheme.onPrimaryFixedVariant, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.editGiftAllocationsTitle,
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 17, color: colorScheme.onSurface),
                        ),
                        Text(
                          gift.giftName,
                          style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.primary, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 580,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        strings.editGiftAllocationsSubtitle,
                        style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 14),

                      // Quick Bulk Distribution Toolbar
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.bolt_rounded, size: 18, color: colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              isAr ? 'توزيع موحد:' : 'Bulk Distribute:',
                              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 75,
                              height: 34,
                              child: TextField(
                                controller: bulkDistributeController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
                                decoration: InputDecoration(
                                  hintText: '50',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  filled: true,
                                  fillColor: colorScheme.surface,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            FilledButton.tonal(
                              onPressed: isSaving
                                  ? null
                                  : () {
                                      final qty = bulkDistributeController.text.trim().toIntOrNull();
                                      if (qty != null && qty >= 0) {
                                        setDialogState(() {
                                          for (final item in branchAllocations) {
                                            (item['controller'] as TextEditingController).text = '$qty';
                                          }
                                        });
                                      }
                                    },
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: Text(
                                isAr ? 'تطبيق على الكل' : 'Apply All',
                                style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const Spacer(),
                            ActionChip(
                              avatar: Icon(Icons.refresh_rounded, size: 14, color: colorScheme.error),
                              label: Text(
                                strings.zeroAllAllocationsBtn,
                                style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.onErrorContainer),
                              ),
                              backgroundColor: colorScheme.error.withValues(alpha: 0.1),
                              side: BorderSide(color: colorScheme.error.withValues(alpha: 0.25)),
                              onPressed: isSaving
                                  ? null
                                  : () {
                                      setDialogState(() {
                                        for (final item in branchAllocations) {
                                          (item['controller'] as TextEditingController).text = '0';
                                        }
                                      });
                                    },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (branchAllocations.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isAr ? 'هذا الصنف غير مخصص في أي فعالية حالياً' : 'No active campaign allocations for this gift',
                            style: GoogleFonts.cairo(fontSize: 13, color: colorScheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        ...branchAllocations.map((item) {
                          final branchName = item['branchName'] as String;
                          final eventName = item['eventName'] as String;
                          final claimed = item['currentClaimed'] as int;
                          final controller = item['controller'] as TextEditingController;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        branchName,
                                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      Text(
                                        eventName,
                                        style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                      ),
                                      if (claimed > 0)
                                        Text(
                                          '${isAr ? 'تم صرف:' : 'Awarded:'} $claimed $unitLabel',
                                          style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSecondaryFixedVariant, fontWeight: FontWeight.bold),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 110,
                                  child: TextField(
                                    controller: controller,
                                    keyboardType: TextInputType.number,
                                    enabled: !isSaving,
                                    decoration: InputDecoration(
                                      labelText: isAr ? 'المخصص' : 'Allocated',
                                      suffixText: unitLabel,
                                      isDense: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      filled: true,
                                      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                    ),
                                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Tooltip(
                                  message: isAr ? 'تصفير حصة هذا الفرع' : 'Zero out this branch quota',
                                  child: IconButton.filledTonal(
                                    icon: const Icon(Icons.backspace_outlined, size: 16),
                                    style: IconButton.styleFrom(
                                      backgroundColor: colorScheme.error.withValues(alpha: 0.1),
                                      foregroundColor: colorScheme.onErrorContainer,
                                    ),
                                    onPressed: isSaving
                                        ? null
                                        : () {
                                            setDialogState(() {
                                              controller.text = '0';
                                            });
                                          },
                                  ),
                                ),
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
                  onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: Text(isAr ? 'إلغاء' : 'Cancel', style: GoogleFonts.cairo()),
                ),
                FilledButton.icon(
                  onPressed: isSaving || branchAllocations.isEmpty
                      ? null
                      : () async {
                          setDialogState(() => isSaving = true);
                          try {
                            for (final item in branchAllocations) {
                              final eventId = item['eventId'] as String;
                              final branchId = item['branchId'] as String;
                              final branchName = item['branchName'] as String;
                              final controller = item['controller'] as TextEditingController;
                              final newQty = controller.text.trim().toIntOrNull() ?? 0;

                              if (newQty < 0) {
                                throw Exception('لا يمكن إدخال كمية سالبة لفرع $branchName');
                              }

                              await ref.read(companyGiftsServiceProvider).updateBranchPrizeAllocation(
                                companySlug: companySlug,
                                eventId: eventId,
                                branchName: branchName,
                                branchId: branchId,
                                giftKey: gift.giftId.isNotEmpty ? gift.giftId : gift.giftName,
                                newAllocatedQuantity: newQty,
                                notes: isAr ? 'تعديل وتصفير المخصص من جرد الأصناف' : 'Quota update from SKU Inventory',
                                performedBy: 'مدير الشركة',
                              );
                            }

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(strings.allocationsSavedSuccess),
                                  backgroundColor: colorScheme.tertiary,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(AppErrorHandler.getFriendlyMessage(e), style: GoogleFonts.cairo()),
                                  backgroundColor: colorScheme.error,
                                ),
                              );
                            }
                          }
                        },
                  icon: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    strings.saveAllAllocationsBtn,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.onPrimaryFixedVariant,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDialogKpiCell({
    required String label,
    required String value,
    required Color color,
    required ColorScheme colorScheme,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.cairo(fontSize: 10, color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: color),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showBatchesAndMovementLedgerDialog(CompanyGiftModel gift) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAr = ref.isArabic;
    final giftTitle = gift.giftName.isNotEmpty ? gift.giftName : 'الهدية';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return DefaultTabController(
          length: 2,
          child: DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.4,
            maxChildSize: 0.92,
            expand: false,
            builder: (context, scrollController) {
              return Column(
                children: [
                  // Handle pill
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.history_edu_rounded, color: colorScheme.primary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isAr ? 'سجل التوريدات وحركات المخزون' : 'Supply Batches & Movement Ledger',
                                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16, color: colorScheme.onSurface),
                              ),
                              Text(
                                giftTitle,
                                style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.primary, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),

                  // KPI Summary Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              Text(isAr ? 'إجمالي التوريد' : 'Total Supplied', style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                              Text('${gift.totalQuantity}', style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.primary)),
                            ],
                          ),
                          Container(width: 1, height: 28, color: colorScheme.outlineVariant),
                          Column(
                            children: [
                              Text(isAr ? 'المخصص بالحملات' : 'Campaign Alloc', style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                              Text('${gift.totalQuantity - gift.availableQuantity}', style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSecondaryFixedVariant)),
                            ],
                          ),
                          Container(width: 1, height: 28, color: colorScheme.outlineVariant),
                          Column(
                            children: [
                              Text(isAr ? 'المتاح بالمستودع' : 'Warehouse Avail', style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                              Text('${gift.availableQuantity}', style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onTertiaryFixedVariant)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Tab Bar
                  TabBar(
                    labelColor: colorScheme.primary,
                    unselectedLabelColor: colorScheme.onSurfaceVariant,
                    indicatorColor: colorScheme.primary,
                    tabs: [
                      Tab(text: isAr ? 'دفعات التوريد (${gift.batches.length})' : 'Supply Batches (${gift.batches.length})'),
                      Tab(text: isAr ? 'سجل حركات المخزون التفصيلي' : 'Stock Movement Ledger'),
                    ],
                  ),

                  // Tab Content
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Tab 1: Supply Batches List
                        gift.batches.isEmpty
                            ? Center(
                                child: Text(isAr ? 'لا توجد دفعات مسجلة' : 'No batches recorded', style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant)),
                              )
                            : ListView.separated(
                                controller: scrollController,
                                padding: const EdgeInsets.all(16),
                                itemCount: gift.batches.length,
                                separatorBuilder: (context, index) => const SizedBox(height: 10),
                                itemBuilder: (context, idx) {
                                  final batch = gift.batches[idx];
                                  return Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surface,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: colorScheme.tertiary.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            '#${batch.batchNumber}',
                                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: colorScheme.onTertiaryFixedVariant, fontSize: 13),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    '${isAr ? 'دفعة توريد' : 'Supply Batch'} +${batch.quantity} ${gift.isVoucher ? (isAr ? 'كارت' : 'cards') : (isAr ? 'قطعة' : 'pcs')}',
                                                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.onSurface),
                                                  ),
                                                  Text(
                                                    _formatDate(batch.supplyDate),
                                                    style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                                  ),
                                                ],
                                              ),
                                              if (batch.referenceNumber.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  '${isAr ? 'المرجع / إذن التوريد' : 'Ref #'}: ${batch.referenceNumber}',
                                                  style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.primary, fontWeight: FontWeight.w600),
                                                ),
                                              ],
                                              if (batch.notes.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  batch.notes,
                                                  style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),

                        // Tab 2: Stock Movement Ledger (Live Stream)
                        StreamBuilder<List<GiftStockMovement>>(
                          stream: _ensureStockMovementsStream(gift.companySlug, giftId: gift.id),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator.adaptive());
                            }
                            final movements = snapshot.data ?? [];
                            if (movements.isEmpty) {
                              return Center(
                                child: Text(isAr ? 'لا توجد حركات مخزنية مسجلة بعد' : 'No stock movements recorded yet', style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant)),
                              );
                            }

                            return ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: movements.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 10),
                              itemBuilder: (context, idx) {
                                final m = movements[idx];
                                final isAdd = m.isAddition;
                                final color = isAdd ? colorScheme.onTertiaryFixedVariant : (m.movementType == 'campaign_allocation' ? colorScheme.onSecondaryContainer : colorScheme.onErrorContainer);
                                final bgColor = isAdd ? colorScheme.tertiary.withValues(alpha: 0.12) : (m.movementType == 'campaign_allocation' ? colorScheme.secondary.withValues(alpha: 0.12) : colorScheme.error.withValues(alpha: 0.12));

                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: bgColor,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          isAdd ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                          color: color,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  isAr ? m.typeLabelAr : m.typeLabelEn,
                                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.onSurface),
                                                ),
                                                Text(
                                                  '${m.quantityChange > 0 ? '+' : ''}${m.quantityChange}',
                                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14, color: color),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${isAr ? 'الرصيد بعد الحركة' : 'Stock After'}: ${m.newTotal} (${m.newAvailable} ${isAr ? 'متاح' : 'avail'})',
                                              style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                                            ),
                                            if (m.reference.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                '${isAr ? 'المرجع' : 'Ref'}: ${m.reference}',
                                                style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.primary),
                                              ),
                                            ],
                                            if (m.notes.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                m.notes,
                                                style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                              ),
                                            ],
                                            const SizedBox(height: 4),
                                            Text(
                                              _formatDate(m.timestamp),
                                              style: GoogleFonts.cairo(fontSize: 10, color: colorScheme.outline),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = AppStrings.of(ref);
    final isAr = ref.isArabic;
    final isHi = ref.isHindi;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    FirebaseFirestore? firestore;
    try {
      firestore = ref.watch(firestoreProvider);
    } catch (_) {
      firestore = null;
    }

    final content = _buildRealtimeContent(
      context: context,
      firestore: firestore,
      colorScheme: colorScheme,
      strings: strings,
      isAr: isAr,
      isHi: isHi,
      isMobile: isMobile,
    );

    if (widget.isEmbedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: SwitchPointHeader(
        subtitle: '${widget.lockedCompanyName} — ${strings.prizesStockTitle}',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: strings.back,
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(child: content),
          const SwitchPointFooter(),
        ],
      ),
    );
  }

  Widget _buildRealtimeContent({
    required BuildContext context,
    required FirebaseFirestore? firestore,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
  }) {
    if (firestore == null) {
      return _buildAnalyzedView(
        context: context,
        colorScheme: colorScheme,
        strings: strings,
        isAr: isAr,
        isHi: isHi,
        isMobile: isMobile,
        companyEvents: const [],
        masterGifts: const [],
        transactionDocs: const [],
      );
    }

    final slug = widget.lockedCompanySlug.toLowerCase().trim();
    _ensureStreams(firestore, slug);

    // 1. Stream events for this company to obtain all allocated prizes per campaign & branch
    return StreamBuilder<QuerySnapshot>(
      stream: _eventsStream,
      builder: (context, eventsSnapshot) {
        if (eventsSnapshot.connectionState == ConnectionState.waiting &&
            !eventsSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        final allEventDocs = eventsSnapshot.data?.docs ?? [];
        final companyEvents = allEventDocs
            .map((doc) {
              try {
                return EventModel.fromFirestore(doc);
              } catch (_) {
                return null;
              }
            })
            .whereType<EventModel>()
            .where((e) =>
                e.companySlug.toLowerCase() == slug ||
                e.targetCompany.toLowerCase().contains(slug) ||
                slug.isEmpty)
            .toList();
        final scopedEvents = CompanyPrizesStockReportScreen.scopeEventsToLock(companyEvents, widget.lockedEventId);

        // 2. Stream company_gifts master catalog
        return StreamBuilder<QuerySnapshot>(
          stream: _giftsStream,
          builder: (context, giftsSnapshot) {
            final masterGifts = (giftsSnapshot.data?.docs ?? [])
                .map((d) {
                  try {
                    return CompanyGiftModel.fromFirestore(d);
                  } catch (_) {
                    return null;
                  }
                })
                .whereType<CompanyGiftModel>()
                .toList();

            // 3. Stream receipts_transactions for live claimed gifts verification & audit reconciliation
            return StreamBuilder<QuerySnapshot>(
              stream: _transactionsStream,
              builder: (context, receiptsSnapshot) {
                final allDocs = receiptsSnapshot.data?.docs ?? [];
                final companyEventIds = scopedEvents.map((e) => e.id).toSet();
                final targetCompAr = scopedEvents.isNotEmpty ? scopedEvents.first.targetCompany.trim() : '';
                final transactionDocs = allDocs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>? ?? {};
                  final tSlug = (data['companySlug'] ?? data['company_slug'] ?? '').toString().trim();
                  if (slug.isNotEmpty && tSlug.isNotEmpty && tSlug.toLowerCase() == slug.toLowerCase()) {
                    return true;
                  }
                  final tComp = (data['targetCompany'] ?? data['target_company'] ?? '').toString().trim();
                  if (targetCompAr.isNotEmpty && tComp.isNotEmpty && tComp == targetCompAr) {
                    return true;
                  }
                  final tEventId = (data['campaignId'] ?? data['event_id'] ?? data['campaign_id'] ?? '').toString().trim();
                  if (tEventId.isNotEmpty && companyEventIds.contains(tEventId)) {
                    return true;
                  }
                  return false;
                }).toList();

                return _buildAnalyzedView(
                  context: context,
                  colorScheme: colorScheme,
                  strings: strings,
                  isAr: isAr,
                  isHi: isHi,
                  isMobile: isMobile,
                  companyEvents: scopedEvents,
                  masterGifts: masterGifts,
                  transactionDocs: transactionDocs,
                );
              },
            );
          },
        );
      },
    );
  }

  static String _normalizePrizeKey(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('٠', '0')
        .replaceAll('١', '1')
        .replaceAll('٢', '2')
        .replaceAll('٣', '3')
        .replaceAll('٤', '4')
        .replaceAll('٥', '5')
        .replaceAll('٦', '6')
        .replaceAll('٧', '7')
        .replaceAll('٨', '8')
        .replaceAll('٩', '9')
        .replaceAll(RegExp(r'[^\w\s\d]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isVoucherText(String text) {
    final clean = text.toLowerCase();
    return clean.contains('فواتشر') ||
        clean.contains('فوتشر') ||
        clean.contains('قسيمة') ||
        clean.contains('قسائم') ||
        clean.contains('كارت مشتريات') ||
        clean.contains('كوبون') ||
        clean.contains('voucher') ||
        clean.contains('coupon');
  }

  static double _extractDenomination(String name, double rawUnitValue, {String giftType = 'product'}) {
    // If explicitly product and name has no voucher words, denomination is strictly 0.0
    if (giftType == 'product' && !_isVoucherText(name)) return 0.0;

    // If unit value is explicitly passed and item is a voucher
    if (rawUnitValue > 0 && (giftType == 'voucher' || _isVoucherText(name))) {
      return rawUnitValue;
    }

    // Only extract denomination from text if it is explicitly a voucher text
    if (!_isVoucherText(name)) return 0.0;

    final normalized = name.toEnglishDigits().toLowerCase();

    // Look for explicit denomination keywords: "فئة 50", "بقيمة 50", "50 ج", "50 جنيه", "50 egp"
    final explicitPatterns = [
      RegExp(r'(?:فئة|بقيمة|قيمة|بمبلغ|قسيمة|فواتشر|فوتشر|كوبون|كارت)\s*(\d+(?:\.\d+)?)'),
      RegExp(r'(\d+(?:\.\d+)?)\s*(?:ج\.?م|جنيه|ج|egp|le|pound)', caseSensitive: false),
    ];
    for (final pattern in explicitPatterns) {
      final m = pattern.firstMatch(normalized);
      if (m != null) {
        final parsed = double.tryParse(m.group(1)!);
        if (parsed != null && parsed > 0 && parsed <= 50000) {
          return parsed;
        }
      }
    }

    // General fallback for vouchers only (ignore size units like مل, ml, جم, g, l, لتر)
    final numMatches = RegExp(r'(\d+(?:\.\d+)?)\s*([a-zA-Z\u0600-\u06FF]*)').allMatches(normalized);
    for (final m in numMatches) {
      final numStr = m.group(1)!;
      final unitStr = (m.group(2) ?? '').trim().toLowerCase();

      // If unit represents product volume/weight/size, ignore completely
      if (unitStr.startsWith('مل') ||
          unitStr.startsWith('ml') ||
          unitStr.startsWith('جم') ||
          unitStr.startsWith('gm') ||
          unitStr.startsWith('g') ||
          unitStr.startsWith('kg') ||
          unitStr.startsWith('كجم') ||
          unitStr.startsWith('كيلو') ||
          unitStr.startsWith('لتر') ||
          unitStr.startsWith('liter') ||
          unitStr.startsWith('l') ||
          unitStr.startsWith('سم') ||
          unitStr.startsWith('cm') ||
          unitStr.startsWith('حبة') ||
          unitStr.startsWith('قطعة') ||
          unitStr.startsWith('pcs')) {
        continue;
      }

      final parsed = double.tryParse(numStr);
      if (parsed != null && parsed > 0 && parsed <= 50000) {
        return parsed;
      }
    }

    return 0.0;
  }

  static CompanyGiftModel? findMatchingMasterGift(
    AllocatedPrize prize,
    List<CompanyGiftModel> masterGifts,
  ) {
    if (masterGifts.isEmpty) return null;

    // 1. Direct ID Match
    if (prize.giftId.isNotEmpty) {
      final direct = masterGifts.where((mg) => mg.id == prize.giftId).firstOrNull;
      if (direct != null) return direct;
    }

    final pNameNorm = _normalizePrizeKey(prize.name);
    final pIsVoucher = prize.giftType == 'voucher' || prize.isVoucher || _isVoucherText(prize.name);
    final pDenom = _extractDenomination(prize.name, prize.unitValue, giftType: prize.giftType);

    // 2. Exact Normalized Name Match
    final exactName = masterGifts.where((mg) => _normalizePrizeKey(mg.giftName) == pNameNorm).firstOrNull;
    if (exactName != null) return exactName;

    // 3. For Vouchers: Match by EXACT denomination & voucher status
    if (pIsVoucher && pDenom > 0) {
      final denomMatch = masterGifts.where((mg) {
        final mgIsVoucher = mg.giftType == 'voucher' || mg.isVoucher || _isVoucherText(mg.giftName);
        if (!mgIsVoucher) return false;
        final mgDenom = _extractDenomination(mg.giftName, mg.unitValue, giftType: mg.giftType);
        return mgDenom == pDenom;
      }).firstOrNull;
      if (denomMatch != null) return denomMatch;
    }

    // 4. For Physical Products: Match by normalized name and ensure volume numbers don't conflict
    if (!pIsVoucher) {
      final productMatch = masterGifts.where((mg) {
        final mgIsVoucher = mg.giftType == 'voucher' || mg.isVoucher || _isVoucherText(mg.giftName);
        if (mgIsVoucher) return false;
        final mgNameNorm = _normalizePrizeKey(mg.giftName);
        if (mgNameNorm == pNameNorm) return true;
        // Verify numbers/volumes (e.g., 250 ml vs 90 ml) do not conflict
        final pNums = RegExp(r'\d+').allMatches(pNameNorm).map((m) => m.group(0)).toList();
        final mgNums = RegExp(r'\d+').allMatches(mgNameNorm).map((m) => m.group(0)).toList();
        if (pNums.isNotEmpty && mgNums.isNotEmpty && pNums.first != mgNums.first) {
          return false;
        }
        return (mgNameNorm.isNotEmpty && pNameNorm.isNotEmpty &&
            (mgNameNorm.contains(pNameNorm) || pNameNorm.contains(mgNameNorm)));
      }).firstOrNull;
      if (productMatch != null) return productMatch;
    }

    return null;
  }

  static CompanyGiftModel? _findMatchingMasterGift(
    AllocatedPrize prize,
    List<CompanyGiftModel> masterGifts,
  ) => findMatchingMasterGift(prize, masterGifts);

  static String _formatMoney(num amount, {bool isAr = true}) {
    final isWhole = amount == amount.roundToDouble();
    final formatted = isWhole
        ? amount.toInt().toString().replaceAllMapped(
              RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')
        : amount.toStringAsFixed(2).replaceAllMapped(
              RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
    return isAr ? '$formatted ج.م' : 'EGP $formatted';
  }


  Widget _buildAnalyzedView({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required List<EventModel> companyEvents,
    required List<CompanyGiftModel> masterGifts,
    required List<QueryDocumentSnapshot> transactionDocs,
  }) {
    // 1. Filter events if specific event selected
    List<EventModel> filteredEvents = companyEvents;
    if (_selectedEventId != null && _selectedEventId!.isNotEmpty) {
      filteredEvents =
          companyEvents.where((e) => e.id == _selectedEventId).toList();
    }

    // 2. Build verified live claimed reconciliation function
    int getReconciledClaimed(
      String giftName,
      int rawClaimed, [
      String? branchName,
      String? branchId,
      String? eventId,
      double? unitValue,
      bool? isVoucher,
    ]) {
      int txClaimed = 0;
      final targetEventId = eventId ?? _selectedEventId;

      for (final doc in transactionDocs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final tCampId = (data['campaignId'] ?? data['event_id'] ?? data['campaign_id'] ?? '').toString().trim();
        if (targetEventId != null && targetEventId.isNotEmpty && tCampId.isNotEmpty && tCampId != targetEventId) {
          continue;
        }

        final status = data['status']?.toString();
        final isValid = data['is_valid'];
        if (status == 'rejected' || isValid == false) continue;
        if (data['game_played'] != true &&
            status != 'accepted' &&
            status != 'approved' &&
            status != 'completed' &&
            data['claim_status'] != 'handed_over') {
          continue;
        }

        if (branchName != null && branchName.isNotEmpty) {
          final branchMatches = _matchesBranchStrict(branchName, branchId ?? '', data);
          if (!branchMatches) continue;
        }

        final dummyPrize = AllocatedPrize(
          name: giftName,
          giftId: '',
          allocatedQuantity: 1,
          remainingQuantity: 1,
          unitValue: unitValue ?? 0.0,
          giftType: (isVoucher == true || _isVoucherText(giftName)) ? 'voucher' : 'product',
          branchName: branchName ?? '',
          branchId: branchId ?? '',
        );

        final claimedGifts = (data['claimed_gifts'] as List?) ?? [];
        if (claimedGifts.isNotEmpty) {
          for (final cg in claimedGifts) {
            if (cg is Map) {
              final cgMap = Map<String, dynamic>.from(cg);
              if (_matchesPrizeStrict(dummyPrize, cgMap)) {
                final qty = (cgMap['quantity'] as num?)?.toInt() ?? 1;
                txClaimed += qty;
              }
            }
          }
        } else {
          final prizesWon = (data['prizes_won'] as List?)?.map((p) => p.toString()).toList() ??
              [(data['prize_won'] ?? '').toString()];
          for (final p in prizesWon) {
            if (p.trim().isNotEmpty) {
              if (_matchesPrizeStrict(dummyPrize, {'giftName': p})) {
                txClaimed += 1;
              }
            }
          }
        }
      }

      return rawClaimed > txClaimed ? rawClaimed : txClaimed;
    }

    // 3. Extract distinct branches across filtered events
    final Set<String> distinctBranches = {};
    for (final event in companyEvents) {
      for (final bName in event.branchNames) {
        if (bName.trim().isNotEmpty) distinctBranches.add(bName.trim());
      }
      for (final prize in event.allocatedPrizes) {
        if (prize.branchName.trim().isNotEmpty) {
          distinctBranches.add(prize.branchName.trim());
        }
      }
    }

    // 4. Aggregate all prizes across filtered events & branches
    final Map<String, AggregatedGiftStock> aggregatedMap = {};

    // 4a. Initialize from master gifts so every company gift is present seamlessly
    for (final mg in masterGifts) {
      final key = mg.id.isNotEmpty ? mg.id : _normalizePrizeKey(mg.giftName);
      aggregatedMap[key] = AggregatedGiftStock(
        giftId: mg.id,
        giftName: mg.giftName,
        sku: mg.id,
        totalAllocated: 0,
        totalClaimed: 0,
        totalRemaining: 0,
        branchRemainingMap: {},
        branchAllocatedMap: {},
        eventNames: [],
        giftType: mg.giftType,
        unitValue: mg.unitValue,
      );
    }

    for (final event in filteredEvents) {
      for (final prize in event.allocatedPrizes) {
        // If master company gifts are present, ignore deleted/orphaned gifts
        final matchingMasterGift = _findMatchingMasterGift(prize, masterGifts);
        if (masterGifts.isNotEmpty && matchingMasterGift == null) {
          continue; // Skip deleted/orphaned gift
        }

        // If branch filter is applied, skip prizes not in that branch
        if (_selectedBranch != null && _selectedBranch!.isNotEmpty) {
          final prizeBranch = prize.branchName.trim();
          if (prizeBranch.isNotEmpty && prizeBranch != _selectedBranch) {
            continue;
          }
        }

        final canonicalGiftName = matchingMasterGift?.giftName ?? prize.name.trim();
        final canonicalGiftId = matchingMasterGift?.id ?? (prize.giftId.isNotEmpty ? prize.giftId : canonicalGiftName);
        final canonicalGiftType = matchingMasterGift?.giftType ?? prize.giftType;
        final rawVal = canonicalGiftType == 'voucher' ? (matchingMasterGift?.unitValue ?? prize.unitValue) : 0.0;
        final canonicalUnitValue = _extractDenomination(
          canonicalGiftName,
          rawVal,
          giftType: canonicalGiftType,
        );
        final key = canonicalGiftId.isNotEmpty ? canonicalGiftId : _normalizePrizeKey(canonicalGiftName);
        final branchKey = prize.branchName.isNotEmpty
            ? prize.branchName.trim()
            : (prize.branchId.isNotEmpty ? prize.branchId : (isAr ? 'الفرع الرئيسي' : 'Main Branch'));

        final branchAllocated = prize.allocatedQuantity;
        final rawBranchRemaining = prize.remainingQuantity.clamp(0, prize.allocatedQuantity);
        final rawBranchClaimed = (prize.allocatedQuantity - rawBranchRemaining).clamp(0, prize.allocatedQuantity);
        final txBranchClaimed = getReconciledClaimed(
          canonicalGiftName,
          rawBranchClaimed,
          branchKey,
          prize.branchId,
          event.id,
          canonicalUnitValue,
          canonicalGiftType == 'voucher',
        );
        final branchClaimed = prize.allocatedQuantity > 0 ? (txBranchClaimed > rawBranchClaimed ? txBranchClaimed : rawBranchClaimed) : 0;
        final branchRemaining = (prize.allocatedQuantity - branchClaimed).clamp(0, prize.allocatedQuantity);

        final existing = aggregatedMap[key];
        if (existing == null) {
          final branchRem = branchKey.isNotEmpty ? <String, int>{branchKey: branchRemaining} : <String, int>{};
          final branchAlloc = branchKey.isNotEmpty ? <String, int>{branchKey: branchAllocated} : <String, int>{};

          aggregatedMap[key] = AggregatedGiftStock(
            giftId: canonicalGiftId,
            giftName: canonicalGiftName,
            sku: canonicalGiftId,
            totalAllocated: branchAllocated,
            totalClaimed: branchClaimed,
            totalRemaining: branchRemaining,
            branchRemainingMap: branchRem,
            branchAllocatedMap: branchAlloc,
            eventNames: branchAllocated > 0 ? [event.eventName] : [],
            giftType: canonicalGiftType,
            unitValue: canonicalUnitValue,
          );
        } else {
          final newAllocated = existing.totalAllocated + branchAllocated;
          final newClaimed = existing.totalClaimed + branchClaimed;
          final newRemaining = existing.totalRemaining + branchRemaining;

          if (branchKey.isNotEmpty && branchAllocated > 0) {
            existing.branchRemainingMap[branchKey] =
                (existing.branchRemainingMap[branchKey] ?? 0) + branchRemaining;
            existing.branchAllocatedMap[branchKey] =
                (existing.branchAllocatedMap[branchKey] ?? 0) + branchAllocated;
          }

          if (!existing.eventNames.contains(event.eventName) && branchAllocated > 0) {
            existing.eventNames.add(event.eventName);
          }

          aggregatedMap[key] = AggregatedGiftStock(
            giftId: existing.giftId,
            giftName: existing.giftName,
            sku: existing.sku,
            totalAllocated: newAllocated,
            totalClaimed: newClaimed,
            totalRemaining: newRemaining,
            branchRemainingMap: existing.branchRemainingMap,
            branchAllocatedMap: existing.branchAllocatedMap,
            eventNames: existing.eventNames,
            giftType: existing.giftType,
            unitValue: existing.unitValue,
          );
        }
      }
    }

    // 4. Filter by search query & stock status
    List<AggregatedGiftStock> allGiftsList = aggregatedMap.values.toList();

    if (_searchQuery.isNotEmpty) {
      allGiftsList = allGiftsList.where((g) {
        final nameMatch = g.giftName.toLowerCase().contains(_searchQuery);
        final skuMatch = g.sku.toLowerCase().contains(_searchQuery);
        final branchMatch = g.branchRemainingMap.keys.any((b) => b.toLowerCase().contains(_searchQuery));
        return nameMatch || skuMatch || branchMatch;
      }).toList();
    }

    if (_stockStatusFilter == 'AVAILABLE') {
      allGiftsList = allGiftsList.where((g) => g.isHealthy).toList();
    } else if (_stockStatusFilter == 'LOW') {
      allGiftsList = allGiftsList.where((g) => g.isLowStock).toList();
    } else if (_stockStatusFilter == 'OUT') {
      allGiftsList = allGiftsList.where((g) => g.isOutOfStock).toList();
    }

    // Sort by remaining (highest allocated first)
    allGiftsList.sort((a, b) => b.totalAllocated.compareTo(a.totalAllocated));

    // Calculate High-level Summary Metrics
    int grandTotalAllocated = 0;
    int grandTotalClaimed = 0;
    int grandTotalRemaining = 0;

    for (final g in aggregatedMap.values) {
      grandTotalAllocated += g.totalAllocated;
      grandTotalClaimed += g.totalClaimed;
      grandTotalRemaining += g.totalRemaining;
    }

    final double overallDepletion = grandTotalAllocated > 0
        ? (grandTotalClaimed / grandTotalAllocated).clamp(0.0, 1.0)
        : 0.0;

    final coveredBranchesCount = distinctBranches.isNotEmpty
        ? distinctBranches.length
        : (companyEvents.isNotEmpty ? companyEvents.length : 1);

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 24,
          vertical: isMobile ? 12 : 20,
        ),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 0. Unified Executive Screen Header Card
                PortalScreenHeaderCard(
                  icon: Icons.inventory_2_rounded,
                  title: strings.prizesStockTitle,
                  subtitle: isAr
                      ? 'جرد ومتابعة أرصدة الجوائز والهدايا العينية والمخزون اللحظي بالفروع'
                      : (isHi ? 'वास्तविक समय पुरस्कार और स्टॉक प्रबंधन' : 'Real-time physical prize inventory, balances, and branch stock movement ledger'),
                  events: companyEvents,
                  selectedEventId: _selectedEventId,
                  onEventChanged: _selectEvent,
                  showEventSelector: !_isEventLocked,
                  lockedCompanySlug: widget.lockedCompanySlug,
                  isMobile: isMobile,
                  actions: [
                    FilledButton.tonalIcon(
                      onPressed: () => _exportExcelReport(
                        gifts: allGiftsList,
                        strings: strings,
                        isAr: isAr,
                      ),
                      icon: const Icon(Icons.table_chart_rounded, size: 18),
                      label: Text(
                        strings.exportExcelCsv,
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // General Gifts & Physical Inventory Section Header
                _buildGeneralStockHeader(
                  colorScheme: colorScheme,
                  strings: strings,
                  isAr: isAr,
                ),

                const SizedBox(height: 10),

                // 3. Hero KPI Stat Cards for General Stock
                _buildHeroKpiGrid(
                  colorScheme: colorScheme,
                  strings: strings,
                  isAr: isAr,
                  isHi: isHi,
                  isMobile: isMobile,
                  totalAllocated: grandTotalAllocated,
                  totalClaimed: grandTotalClaimed,
                  totalRemaining: grandTotalRemaining,
                  depletionRate: overallDepletion,
                  coveredBranches: coveredBranchesCount,
                  campaignsCount: filteredEvents.length,
                ),

                const SizedBox(height: 20),

                // 2. Toolbar: Search, Filters & Export
                _buildToolbar(
                  context: context,
                  colorScheme: colorScheme,
                  strings: strings,
                  isAr: isAr,
                  isHi: isHi,
                  isMobile: isMobile,
                  companyEvents: companyEvents,
                  distinctBranches: distinctBranches.toList(),
                  onExport: () => _exportExcelReport(
                    gifts: allGiftsList,
                    strings: strings,
                    isAr: isAr,
                  ),
                ),

                const SizedBox(height: 16),

                // 3. View Mode Switcher (3-Segment Connected Buttons)
                _buildViewModeSwitcher(
                  colorScheme: colorScheme,
                  strings: strings,
                  isAr: isAr,
                  isHi: isHi,
                  isMobile: isMobile,
                ),

                const SizedBox(height: 20),

                // 4. Main Dynamic View Content
                if (_viewMode == 3 && !_isEventLocked)
                  _buildStockMovementsLedgerView(
                    context: context,
                    colorScheme: colorScheme,
                    strings: strings,
                    isAr: isAr,
                    isHi: isHi,
                    isMobile: isMobile,
                    companySlug: widget.lockedCompanySlug.isNotEmpty
                        ? widget.lockedCompanySlug
                        : (companyEvents.isNotEmpty ? companyEvents.first.companySlug : ''),
                    masterGifts: masterGifts,
                  )
                else if (allGiftsList.isEmpty)
                  _buildEmptyState(colorScheme: colorScheme, strings: strings)
                else if (_viewMode == 0)
                  _buildItemizedGiftsView(
                    colorScheme: colorScheme,
                    strings: strings,
                    isAr: isAr,
                    isHi: isHi,
                    isMobile: isMobile,
                    gifts: allGiftsList,
                    masterGifts: masterGifts,
                    companySlug: widget.lockedCompanySlug.isNotEmpty
                        ? widget.lockedCompanySlug
                        : (companyEvents.isNotEmpty ? companyEvents.first.companySlug : ''),
                    events: companyEvents,
                  )
                else if (_viewMode == 1)
                  _buildBranchBreakdownView(
                    colorScheme: colorScheme,
                    strings: strings,
                    isAr: isAr,
                    isHi: isHi,
                    isMobile: isMobile,
                    filteredEvents: filteredEvents,
                    gifts: allGiftsList,
                    masterGifts: masterGifts,
                    transactionDocs: transactionDocs,
                    getReconciledClaimed: getReconciledClaimed,
                  )
                else
                  _buildCampaignBreakdownView(
                    colorScheme: colorScheme,
                    strings: strings,
                    isAr: isAr,
                    isHi: isHi,
                    isMobile: isMobile,
                    filteredEvents: filteredEvents,
                    masterGifts: masterGifts,
                    transactionDocs: transactionDocs,
                  ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildGeneralStockHeader({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.inventory_2_rounded,
            color: colorScheme.primary,
            size: 18,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            strings.generalGiftsStockTitle,
            style: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Hero KPI Summary Grid
  // ---------------------------------------------------------------------------
  Widget _buildHeroKpiGrid({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required int totalAllocated,
    required int totalClaimed,
    required int totalRemaining,
    required double depletionRate,
    required int coveredBranches,
    required int campaignsCount,
  }) {
    final cards = [
      _buildStatCard(
        colorScheme: colorScheme,
        icon: Icons.inventory_2_rounded,
        iconColor: colorScheme.primary,
        title: strings.totalAllocatedGifts,
        value: '$totalAllocated',
        badgeText: isAr ? 'إجمالي المعتمد' : (isHi ? 'कुल' : 'Total Coded'),
        badgeColor: colorScheme.primary.withValues(alpha: 0.12),
        badgeTextColor: colorScheme.primary,
        subtitle: isAr ? 'شاملاً كافة الحملات والمخزون' : 'Across all campaigns',
      ),
      _buildStatCard(
        colorScheme: colorScheme,
        icon: Icons.card_giftcard_rounded,
        iconColor: colorScheme.primary,
        title: strings.awardedGiftsCount,
        value: '$totalClaimed',
        badgeText: '${(depletionRate * 100).toStringAsFixed(0)}% ${strings.depletionRateLabel}',
        badgeColor: colorScheme.primary.withValues(alpha: 0.12),
        badgeTextColor: colorScheme.primary,
        subtitle: isAr ? 'هدايا تم تسليمها للعملاء الفائزين' : 'Claimed by shoppers',
      ),
      _buildStatCard(
        colorScheme: colorScheme,
        icon: Icons.verified_rounded,
        iconColor: totalRemaining <= 0
            ? colorScheme.error
            : (totalRemaining < 20 ? colorScheme.secondary : colorScheme.tertiary),
        title: strings.remainingStockBalance,
        value: '$totalRemaining',
        badgeText: totalRemaining <= 0
            ? strings.stockDepletedBadge
            : (totalRemaining < 20 ? strings.stockLowBadge : strings.stockHealthyBadge),
        badgeColor: (totalRemaining <= 0
                ? colorScheme.error
                : (totalRemaining < 20 ? colorScheme.secondary : colorScheme.tertiary))
            .withValues(alpha: 0.12),
        badgeTextColor: totalRemaining <= 0
            ? colorScheme.error
            : (totalRemaining < 20 ? colorScheme.secondary : colorScheme.tertiary),
        subtitle: isAr ? 'الرصيد المتاح للسحب الآن' : 'Available in live wheels',
      ),
      _buildStatCard(
        colorScheme: colorScheme,
        icon: Icons.storefront_rounded,
        iconColor: colorScheme.tertiary,
        title: strings.coveredOutletsCount,
        value: '$coveredBranches',
        badgeText: '$campaignsCount ${isAr ? 'فعاليات' : 'Campaigns'}',
        badgeColor: colorScheme.tertiary.withValues(alpha: 0.12),
        badgeTextColor: colorScheme.tertiary,
        subtitle: isAr ? 'موزعة عبر الفروع والسلاسل' : 'Active retail outlets',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            children: cards
                .map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: c,
                    ))
                .toList(),
          );
        } else if (constraints.maxWidth < 1000) {
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: cards
                .map((c) => SizedBox(
                      width: (constraints.maxWidth - 12) / 2,
                      child: c,
                    ))
                .toList(),
          );
        } else {
          return Row(
            children: cards
                .map((c) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: c,
                      ),
                    ))
                .toList(),
          );
        }
      },
    );
  }

  Widget _buildStatCard({
    required ColorScheme colorScheme,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String badgeText,
    required Color badgeColor,
    required Color badgeTextColor,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badgeText,
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: badgeTextColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: colorScheme.onSurface,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.cairo(
              fontSize: 10,
              color: colorScheme.outline,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Toolbar: Search, Filters & Export
  // ---------------------------------------------------------------------------
  Widget _buildToolbar({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required List<EventModel> companyEvents,
    required List<String> distinctBranches,
    required VoidCallback onExport,
  }) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Row: Search + Export Button
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: strings.searchGiftsPlaceholder,
                      hintStyle: GoogleFonts.cairo(
                        fontSize: 12,
                        color: colorScheme.outline,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: strings.exportStockReportCsv,
                child: FilledButton.tonalIcon(
                  onPressed: onExport,
                  icon: const Icon(Icons.file_download_rounded, size: 18),
                  label: isMobile
                      ? const SizedBox.shrink()
                      : Text(
                          strings.exportStockReportCsv,
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 12 : 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Bottom Row: Dropdown Filters & Status Pills
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Campaign Selector Dropdown (hidden in a locked single-campaign session)
              if (!_isEventLocked)
              Builder(
                builder: (context) {
                  final uniqueEvents = <String, EventModel>{};
                  for (final ev in companyEvents) {
                    if (ev.id.isNotEmpty && !uniqueEvents.containsKey(ev.id)) {
                      uniqueEvents[ev.id] = ev;
                    }
                  }
                  final cleanEvents = uniqueEvents.values.toList();
                  final effectiveSelectedEventId = _selectedEventId != null && cleanEvents.any((ev) => ev.id == _selectedEventId)
                      ? _selectedEventId
                      : null;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        key: ValueKey('stock_campaign_${effectiveSelectedEventId}_${cleanEvents.length}'),
                        value: effectiveSelectedEventId,
                        hint: Text(
                          strings.allCampaignsOption,
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                              strings.allCampaignsOption,
                              style: GoogleFonts.cairo(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          for (final ev in cleanEvents)
                            DropdownMenuItem<String?>(
                              value: ev.id,
                              child: Text(
                                ev.eventName,
                                style: GoogleFonts.cairo(fontSize: 12),
                              ),
                            ),
                        ],
                        onChanged: _selectEvent,
                      ),
                    ),
                  );
                },
              ),

              // Branch Selector Dropdown
              if (distinctBranches.isNotEmpty)
                Builder(
                  builder: (context) {
                    final cleanBranches = distinctBranches
                        .where((b) => b.trim().isNotEmpty)
                        .toSet()
                        .toList()
                      ..sort();
                    final effectiveSelectedBranch = _selectedBranch != null && cleanBranches.contains(_selectedBranch)
                        ? _selectedBranch
                        : null;

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          key: ValueKey('stock_branch_${effectiveSelectedBranch}_${cleanBranches.length}'),
                          value: effectiveSelectedBranch,
                          hint: Text(
                            strings.allBranchesOption,
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                strings.allBranchesOption,
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            for (final b in cleanBranches)
                              DropdownMenuItem<String?>(
                                value: b,
                                child: Text(
                                  b,
                                  style: GoogleFonts.cairo(fontSize: 12),
                                ),
                              ),
                          ],
                          onChanged: (val) => setState(() => _selectedBranch = val),
                        ),
                      ),
                    );
                  },
                ),

              // Stock Status Pills
              _buildFilterPill(
                label: strings.filterAllStock,
                isSelected: _stockStatusFilter == 'ALL',
                onTap: () => setState(() => _stockStatusFilter = 'ALL'),
                colorScheme: colorScheme,
              ),
              _buildFilterPill(
                label: strings.filterAvailableStock,
                isSelected: _stockStatusFilter == 'AVAILABLE',
                onTap: () => setState(() => _stockStatusFilter = 'AVAILABLE'),
                colorScheme: colorScheme,
              ),
              _buildFilterPill(
                label: strings.filterLowStock,
                isSelected: _stockStatusFilter == 'LOW',
                onTap: () => setState(() => _stockStatusFilter = 'LOW'),
                colorScheme: colorScheme,
              ),
              _buildFilterPill(
                label: strings.filterOutOfStock,
                isSelected: _stockStatusFilter == 'OUT',
                onTap: () => setState(() => _stockStatusFilter = 'OUT'),
                colorScheme: colorScheme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // View Mode Switcher (3-Segment Button Group)
  // ---------------------------------------------------------------------------
  Widget _buildViewModeSwitcher({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
  }) {
    return M3ConnectedButtonGroup<int>(
      height: 44,
      borderRadius: 14,
      isExpanded: isMobile,
      segments: [
        M3ButtonSegment<int>(
          value: 0,
          icon: Icons.view_list_rounded,
          selectedIcon: Icons.view_list_rounded,
          label: strings.itemizedGiftsTab,
          tooltip: isAr
              ? 'جرد تفصيلي لكافة أصناف وهدايا الشركة مع أشرطة النفاذ المئوية'
              : 'Detailed SKU-level gift stock with depletion progress',
        ),
        M3ButtonSegment<int>(
          value: 1,
          icon: Icons.storefront_rounded,
          selectedIcon: Icons.storefront_rounded,
          label: strings.branchBreakdownTab,
          tooltip: isAr
              ? 'توزيع الأرصدة والهدايا المتبقية في كل فرع وسلسلة'
              : 'Stock balances grouped per retail branch',
        ),
        M3ButtonSegment<int>(
          value: 2,
          icon: Icons.campaign_rounded,
          selectedIcon: Icons.campaign_rounded,
          label: strings.campaignBreakdownTab,
          tooltip: isAr
              ? 'أرصدة الجوائز واستهلاكها حسب كل فعالية وحملة ترويجية'
              : 'Prize consumption per promotional campaign',
        ),
        if (!_isEventLocked)
        M3ButtonSegment<int>(
          value: 3,
          icon: Icons.history_edu_rounded,
          selectedIcon: Icons.history_edu_rounded,
          label: isAr ? 'سجل الحركات والتوريد' : 'Supply & Movements',
          tooltip: isAr
              ? 'سجل تفصيلي لكافة دفعات التوريد، التسويات، الصرف والمرتجعات مع التواريخ والمراجع'
              : 'Audit ledger of all supply batches, adjustments, claims and returns',
        ),
      ],
      selectedValue: (_isEventLocked && _viewMode == 3) ? 0 : _viewMode,
      onSelected: (newVal) => setState(() => _viewMode = newVal),
    );
  }

  // ---------------------------------------------------------------------------
  // Mode 3: Supply Batches & Movements Ledger View
  // ---------------------------------------------------------------------------
  static String _formatMovementDate(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $period';
  }

  Widget _buildMiniStatCard({
    required ColorScheme colorScheme,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
              Text(
                value,
                style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
              ),
              Text(
                subtitle,
                style: GoogleFonts.cairo(fontSize: 10, color: colorScheme.outline),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStockMovementCard({
    required ColorScheme colorScheme,
    required bool isAr,
    required GiftStockMovement movement,
  }) {
    final isAdd = movement.isAddition;
    final isAlloc = movement.movementType == 'campaign_allocation';
    final isReturn = movement.movementType == 'campaign_return';
    final isClaim = movement.movementType == 'receipt_claim';

    Color themeColor;
    IconData icon;
    if (movement.movementType == 'supply_batch') {
      themeColor = colorScheme.onTertiaryFixedVariant;
      icon = Icons.add_shopping_cart_rounded;
    } else if (movement.movementType.startsWith('adjustment')) {
      themeColor = isAdd ? colorScheme.onTertiaryFixedVariant : colorScheme.onSecondaryContainer;
      icon = Icons.tune_rounded;
    } else if (isAlloc) {
      themeColor = colorScheme.onSecondaryFixedVariant;
      icon = Icons.campaign_rounded;
    } else if (isReturn) {
      themeColor = colorScheme.onPrimaryFixedVariant;
      icon = Icons.replay_rounded;
    } else if (isClaim) {
      themeColor = colorScheme.onPrimaryFixedVariant;
      icon = Icons.card_giftcard_rounded;
    } else {
      themeColor = isAdd ? colorScheme.onTertiaryFixedVariant : colorScheme.onErrorContainer;
      icon = isAdd ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: themeColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            isAr ? movement.typeLabelAr : movement.typeLabelEn,
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14, color: colorScheme.onSurface),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: themeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${movement.quantityChange > 0 ? '+' : ''}${movement.quantityChange}',
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14, color: themeColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${isAr ? 'الصنف / الهدية:' : 'Gift / SKU:'} ${movement.giftName}',
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    '${isAr ? 'الرصيد بعد الحركة:' : 'Stock After:'} ${movement.newTotal} (${movement.newAvailable} ${isAr ? 'متاح' : 'avail'})',
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              if (movement.reference.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tag_rounded, size: 14, color: colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      '${isAr ? 'المرجع:' : 'Ref:'} ${movement.reference}',
                      style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.primary, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule_rounded, size: 14, color: colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    _formatMovementDate(movement.timestamp),
                    style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.outline),
                  ),
                ],
              ),
            ],
          ),
          if (movement.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                movement.notes,
                style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStockMovementsLedgerView({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required String companySlug,
    required List<CompanyGiftModel> masterGifts,
  }) {
    return StreamBuilder<List<GiftStockMovement>>(
      stream: _ensureStockMovementsStream(companySlug),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator.adaptive(),
            ),
          );
        }

        final allMovements = snapshot.data ?? [];
        if (allMovements.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(40),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history_rounded, size: 48, color: colorScheme.outline),
                const SizedBox(height: 12),
                Text(
                  isAr ? 'لا توجد حركات مخزنية أو دفعات توريد مسجلة حتى الآن' : 'No stock movements or supply batches recorded yet',
                  style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  isAr ? 'أي دفعات توريد أو تسويات أو صرف جوائز سيتم توثيقها هنا فورياً مع التواريخ والمراجع' : 'Inward batches, adjustments, and claims will appear here chronologically.',
                  style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.outline),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        // Apply filters
        var filtered = allMovements;
        if (_movementTypeFilter == 'supply_batch') {
          filtered = filtered.where((m) => m.movementType == 'supply_batch').toList();
        } else if (_movementTypeFilter == 'adjustment') {
          filtered = filtered.where((m) => m.movementType.startsWith('adjustment')).toList();
        } else if (_movementTypeFilter == 'campaign') {
          filtered = filtered.where((m) => m.movementType.startsWith('campaign')).toList();
        }

        if (_movementGiftFilter != null && _movementGiftFilter!.isNotEmpty) {
          filtered = filtered.where((m) => m.giftId == _movementGiftFilter || m.giftName == _movementGiftFilter).toList();
        }

        if (_searchQuery.isNotEmpty) {
          filtered = filtered.where((m) {
            return m.giftName.toLowerCase().contains(_searchQuery) ||
                m.reference.toLowerCase().contains(_searchQuery) ||
                m.notes.toLowerCase().contains(_searchQuery) ||
                m.performedBy.toLowerCase().contains(_searchQuery);
          }).toList();
        }

        // Metrics from allMovements
        int totalBatchesCount = 0;
        int totalBatchesQty = 0;
        int totalAdjustmentsCount = 0;
        int totalAdjustmentsDelta = 0;

        for (final m in allMovements) {
          if (m.movementType == 'supply_batch') {
            totalBatchesCount++;
            totalBatchesQty += m.quantityChange;
          } else if (m.movementType.startsWith('adjustment')) {
            totalAdjustmentsCount++;
            totalAdjustmentsDelta += m.quantityChange;
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // KPI Bar for Movements
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildMiniStatCard(
                  colorScheme: colorScheme,
                  icon: Icons.inventory_2_rounded,
                  iconColor: colorScheme.onPrimaryFixedVariant,
                  title: isAr ? 'إجمالي دفعات التوريد' : 'Total Supply Batches',
                  value: '$totalBatchesCount ${isAr ? 'دفعات' : 'batches'}',
                  subtitle: '+ $totalBatchesQty ${isAr ? 'قطع/كروت واردة' : 'inward items'}',
                ),
                _buildMiniStatCard(
                  colorScheme: colorScheme,
                  icon: Icons.tune_rounded,
                  iconColor: colorScheme.onSecondaryFixedVariant,
                  title: isAr ? 'إجمالي التسويات الجردية' : 'Total Adjustments',
                  value: '$totalAdjustmentsCount ${isAr ? 'تسوية' : 'adjustments'}',
                  subtitle: '${totalAdjustmentsDelta >= 0 ? '+' : ''}$totalAdjustmentsDelta ${isAr ? 'صافي التعديل' : 'net delta'}',
                ),
                _buildMiniStatCard(
                  colorScheme: colorScheme,
                  icon: Icons.receipt_long_rounded,
                  iconColor: colorScheme.onTertiaryFixedVariant,
                  title: isAr ? 'إجمالي الحركات الموثقة' : 'Total Movements Logged',
                  value: '${allMovements.length} ${isAr ? 'حركة' : 'logs'}',
                  subtitle: isAr ? 'سجل رقابي غير قابل للتعديل' : 'Immutable audit trail',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Filter Chips Bar
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  isAr ? 'تصفية السجل:' : 'Filter Ledger:',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
                ChoiceChip(
                  label: Text(isAr ? 'الكل (${allMovements.length})' : 'All (${allMovements.length})', style: GoogleFonts.cairo(fontSize: 12)),
                  selected: _movementTypeFilter == 'ALL',
                  onSelected: (_) => setState(() => _movementTypeFilter = 'ALL'),
                ),
                ChoiceChip(
                  label: Text(isAr ? 'دفعات التوريد' : 'Supply Batches', style: GoogleFonts.cairo(fontSize: 12)),
                  selected: _movementTypeFilter == 'supply_batch',
                  onSelected: (_) => setState(() => _movementTypeFilter = 'supply_batch'),
                ),
                ChoiceChip(
                  label: Text(isAr ? 'التسويات الجردية' : 'Adjustments', style: GoogleFonts.cairo(fontSize: 12)),
                  selected: _movementTypeFilter == 'adjustment',
                  onSelected: (_) => setState(() => _movementTypeFilter = 'adjustment'),
                ),
                ChoiceChip(
                  label: Text(isAr ? 'حملات وفروع' : 'Campaigns', style: GoogleFonts.cairo(fontSize: 12)),
                  selected: _movementTypeFilter == 'campaign',
                  onSelected: (_) => setState(() => _movementTypeFilter = 'campaign'),
                ),
                if (masterGifts.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Builder(
                    builder: (context) {
                      final uniqueGifts = <String, CompanyGiftModel>{};
                      for (final g in masterGifts) {
                        if (g.id.isNotEmpty && !uniqueGifts.containsKey(g.id)) {
                          uniqueGifts[g.id] = g;
                        }
                      }
                      final cleanGifts = uniqueGifts.values.toList();
                      final effectiveGiftFilter = _movementGiftFilter != null && cleanGifts.any((g) => g.id == _movementGiftFilter)
                          ? _movementGiftFilter
                          : null;

                      return DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          key: ValueKey('stock_movement_gift_${effectiveGiftFilter}_${cleanGifts.length}'),
                          value: effectiveGiftFilter,
                          hint: Text(isAr ? 'كل الهدايا' : 'All Gifts', style: GoogleFonts.cairo(fontSize: 12)),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(isAr ? 'كل الهدايا' : 'All Gifts', style: GoogleFonts.cairo(fontSize: 12)),
                            ),
                            ...cleanGifts.map((g) {
                              return DropdownMenuItem<String?>(
                                value: g.id,
                                child: Text(g.giftName, style: GoogleFonts.cairo(fontSize: 12)),
                              );
                            }),
                          ],
                          onChanged: (v) => setState(() => _movementGiftFilter = v),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),

            const SizedBox(height: 16),

            // Movement Ledger List
            if (filtered.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                alignment: Alignment.center,
                child: Text(
                  isAr ? 'لا توجد حركات تطابق التصفية الحالية' : 'No movements match current filter',
                  style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, idx) {
                  final m = filtered[idx];
                  return _buildStockMovementCard(
                    colorScheme: colorScheme,
                    isAr: isAr,
                    movement: m,
                  );
                },
              ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Mode 0: Itemized SKU Inventory Cards & Table
  // ---------------------------------------------------------------------------
  Widget _buildItemizedGiftsView({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required List<AggregatedGiftStock> gifts,
    required List<CompanyGiftModel> masterGifts,
    required String companySlug,
    required List<EventModel> events,
  }) {
    return Column(
      children: [
        for (final gift in gifts)
          _buildItemizedGiftCard(
            colorScheme: colorScheme,
            strings: strings,
            isAr: isAr,
            isHi: isHi,
            isMobile: isMobile,
            gift: gift,
            masterGifts: masterGifts,
            companySlug: companySlug,
            events: events,
          ),
      ],
    );
  }

  Widget _buildItemizedGiftCard({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required AggregatedGiftStock gift,
    required List<CompanyGiftModel> masterGifts,
    required String companySlug,
    required List<EventModel> events,
  }) {
    final statusColor = gift.isOutOfStock
        ? colorScheme.error
        : (gift.isLowStock ? colorScheme.secondary : colorScheme.tertiary);
    final statusLabel = gift.isOutOfStock
        ? strings.stockDepletedBadge
        : (gift.isLowStock ? strings.stockLowBadge : strings.stockHealthyBadge);

    final masterGift = masterGifts.where((mg) {
      return mg.id == gift.giftId ||
          _normalizePrizeKey(mg.giftName) == _normalizePrizeKey(gift.giftName);
    }).firstOrNull;

    final canonicalType = masterGift?.giftType ?? gift.giftType;
    final isExplicitVoucher = (masterGift?.isVoucher == true) ||
        gift.isVoucher ||
        _isVoucherText(masterGift?.giftName ?? gift.giftName);

    final rawVal = isExplicitVoucher ? (masterGift?.unitValue ?? gift.unitValue) : 0.0;
    final denom = _extractDenomination(
      masterGift?.giftName ?? gift.giftName,
      rawVal,
      giftType: canonicalType,
    );
    final isVoucher = isExplicitVoucher && denom > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isVoucher
              ? colorScheme.secondary.withValues(alpha: 0.35)
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Icon + Gift Name + Status Badge + Remaining Big Counter
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isVoucher
                      ? colorScheme.secondary.withValues(alpha: 0.12)
                      : colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                    color: isVoucher ? colorScheme.secondary : colorScheme.primary,
                    size: 24,
                  ),
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
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (isVoucher && denom > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.secondary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.35)),
                            ),
                            child: Text(
                              'فئة ${denom.toInt()} ج.م',
                              style: GoogleFonts.cairo(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: colorScheme.onSecondaryFixedVariant,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                statusLabel,
                                style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (masterGift != null && masterGift.batchCount > 1) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                            ),
                            child: Text(
                              isAr ? '${masterGift.batchCount} دفعات توريد' : '${masterGift.batchCount} batches',
                              style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (gift.eventNames.isNotEmpty)
                      Text(
                        isVoucher && denom > 0
                            ? '${gift.eventNames.join(' • ')} • ميزانية الصنف: ${_formatMoney(gift.totalAllocated * denom, isAr: isAr)}'
                            : gift.eventNames.join(' • '),
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Big Live Remaining Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '${gift.totalRemaining}',
                      style: GoogleFonts.cairo(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: statusColor,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      isAr ? 'متبقي' : 'Left',
                      style: GoogleFonts.cairo(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                    if (isVoucher && denom > 0)
                      Text(
                        _formatMoney(gift.totalRemaining * denom, isAr: isAr),
                        style: GoogleFonts.cairo(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: statusColor,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Middle: Metrics Row (Allocated, Claimed, Depletion Rate %)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildMetricSnippet(
                      label: isAr ? 'المخصص' : 'Allocated',
                      value: isVoucher && denom > 0
                          ? '${gift.totalAllocated} (${_formatMoney(gift.totalAllocated * denom, isAr: isAr)})'
                          : '${gift.totalAllocated}',
                      colorScheme: colorScheme,
                    ),
                    _buildMetricSnippet(
                      label: isAr ? 'المصروف' : 'Claimed',
                      value: isVoucher && denom > 0
                          ? '${gift.totalClaimed} (${_formatMoney(gift.totalClaimed * denom, isAr: isAr)})'
                          : '${gift.totalClaimed}',
                      colorScheme: colorScheme,
                    ),
                    _buildMetricSnippet(
                      label: isAr ? 'نسبة الصرف' : 'Depletion',
                      value: '${(gift.depletionRate * 100).toStringAsFixed(0)}%',
                      colorScheme: colorScheme,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: gift.depletionRate,
                    minHeight: 8,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      gift.depletionRate > 0.85
                          ? colorScheme.error
                          : (gift.depletionRate > 0.60
                              ? colorScheme.secondary
                              : colorScheme.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom: Branch Distribution Pills
          if (gift.branchRemainingMap.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              strings.branchDistributionLabel,
              style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final entry in gift.branchRemainingMap.entries)
                  Tooltip(
                    message: isAr ? 'اضغط لعرض وتزويد أرصدة فرع ${entry.key}' : 'Tap to view & supply ${entry.key} stock',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        setState(() {
                          _viewMode = 1;
                          _selectedBranch = entry.key;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: entry.value <= 0
                              ? colorScheme.error.withValues(alpha: 0.08)
                              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: entry.value <= 0
                                ? colorScheme.error.withValues(alpha: 0.3)
                                : colorScheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.store_rounded,
                              size: 13,
                              color: entry.value <= 0
                                  ? colorScheme.error
                                  : colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              entry.key,
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: entry.value <= 0
                                    ? colorScheme.error
                                    : colorScheme.primary,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${entry.value}',
                                style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],

          // Manager Stock Actions Bar
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 1. Edit & Distribute Branch Quotas (hidden when read-only)
              if (!widget.isReadOnly)
              FilledButton.tonalIcon(
                onPressed: () => _showEditGiftAllocationsDialog(
                  gift: gift,
                  masterGift: masterGift,
                  companySlug: companySlug,
                  events: events,
                  strings: strings,
                  isAr: isAr,
                ),
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: Text(
                  isAr ? 'مخصصات وتوزيع الفروع (تعديل / سريع)' : 'Branch Allocations (Quick/Edit)',
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              // 2. Movement Ledger Timeline Modal (company-wide data: hidden when campaign-locked)
              if (masterGift != null && !_isEventLocked)
                FilledButton.tonalIcon(
                  onPressed: () => _showBatchesAndMovementLedgerDialog(masterGift),
                  icon: const Icon(Icons.history_edu_rounded, size: 16),
                  label: Text(
                    isAr ? 'سجل الحركات' : 'Movements',
                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    foregroundColor: colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricSnippet({
    required String label,
    required String value,
    required ColorScheme colorScheme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 10,
            color: colorScheme.outline,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.cairo(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Mode 1: Branch-by-Branch Breakdown & Stock Heatmap
  // ---------------------------------------------------------------------------
  Widget _buildBranchBreakdownView({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required List<EventModel> filteredEvents,
    required List<AggregatedGiftStock> gifts,
    required List<CompanyGiftModel> masterGifts,
    required List<QueryDocumentSnapshot> transactionDocs,
    required int Function(
      String giftName,
      int rawClaimed, [
      String? branchName,
      String? branchId,
      String? eventId,
      double? unitValue,
      bool? isVoucher,
    ]) getReconciledClaimed,
  }) {
    // 1. Collect all distinct branches from filteredEvents
    final List<Map<String, String>> targetBranches = [];
    final Set<String> seenBranchNames = {};

    if (_selectedBranch != null && _selectedBranch!.isNotEmpty) {
      targetBranches.add({'id': _selectedBranch!, 'name': _selectedBranch!});
    } else {
      for (final event in filteredEvents) {
        for (int i = 0; i < event.branchNames.length; i++) {
          final bName = event.branchNames[i].trim();
          final bId = i < event.branchIds.length ? event.branchIds[i].trim() : bName;
          if (bName.isNotEmpty && !seenBranchNames.contains(bName)) {
            seenBranchNames.add(bName);
            targetBranches.add({'id': bId, 'name': bName});
          }
        }
        for (final prize in event.allocatedPrizes) {
          final bName = prize.branchName.trim();
          final bId = prize.branchId.trim();
          if (bName.isNotEmpty && !seenBranchNames.contains(bName)) {
            seenBranchNames.add(bName);
            targetBranches.add({'id': bId.isNotEmpty ? bId : bName, 'name': bName});
          }
        }
      }
    }

    if (targetBranches.isEmpty) {
      targetBranches.add({'id': '', 'name': isAr ? 'كافة الفروع / عام' : 'All Branches / General'});
    }

    // 2. Group all prizes by branch name
    final Map<String, List<Map<String, dynamic>>> branchGroups = {};

    for (final b in targetBranches) {
      final bName = b['name']!;
      final bId = b['id']!;
      final List<Map<String, dynamic>> prizesForBranch = [];

      for (final event in filteredEvents) {
        if (masterGifts.isNotEmpty) {
          for (final mg in masterGifts) {
            final matchingPrize = event.allocatedPrizes.where((prize) {
              final matchesBranch = prize.branchName.trim() == bName ||
                  (bId.isNotEmpty && prize.branchId.trim() == bId);
              if (!matchesBranch) return false;
              final mgMatch = _findMatchingMasterGift(prize, masterGifts);
              return mgMatch?.id == mg.id;
            }).firstOrNull;

            if (matchingPrize != null) {
              final rawClaimed = (matchingPrize.allocatedQuantity - matchingPrize.remainingQuantity).clamp(0, matchingPrize.allocatedQuantity);
              final txClaimed = getReconciledClaimed(
                mg.giftName,
                rawClaimed,
                bName,
                bId,
                event.id,
                mg.unitValue,
                mg.giftType == 'voucher' || mg.isVoucher,
              );
              final branchClaimed = matchingPrize.allocatedQuantity > 0
                  ? (txClaimed > rawClaimed ? txClaimed : rawClaimed)
                  : txClaimed;
              final branchRemaining = (matchingPrize.allocatedQuantity - branchClaimed).clamp(0, matchingPrize.allocatedQuantity);

              prizesForBranch.add({
                'eventId': event.id,
                'eventName': event.eventName,
                'giftId': mg.id,
                'giftName': mg.giftName,
                'giftType': mg.giftType,
                'unitValue': mg.unitValue,
                'branchId': bId,
                'branchName': bName,
                'allocated': matchingPrize.allocatedQuantity,
                'remaining': branchRemaining,
                'claimed': branchClaimed,
              });
            } else {
              final txClaimed = getReconciledClaimed(
                mg.giftName,
                0,
                bName,
                bId,
                event.id,
                mg.unitValue,
                mg.giftType == 'voucher' || mg.isVoucher,
              );
              prizesForBranch.add({
                'eventId': event.id,
                'eventName': event.eventName,
                'giftId': mg.id,
                'giftName': mg.giftName,
                'giftType': mg.giftType,
                'unitValue': mg.unitValue,
                'branchId': bId,
                'branchName': bName,
                'allocated': 0,
                'remaining': 0,
                'claimed': txClaimed,
              });
            }
          }
        } else {
          for (final prize in event.allocatedPrizes) {
            final pBranch = prize.branchName.trim();
            if (pBranch == bName || (bId.isNotEmpty && prize.branchId.trim() == bId)) {
              final rawClaimed = (prize.allocatedQuantity - prize.remainingQuantity).clamp(0, prize.allocatedQuantity);
              final txClaimed = getReconciledClaimed(
                prize.name,
                rawClaimed,
                bName,
                bId,
                event.id,
                prize.unitValue,
                prize.giftType == 'voucher' || prize.isVoucher,
              );
              final branchClaimed = prize.allocatedQuantity > 0
                  ? (txClaimed > rawClaimed ? txClaimed : rawClaimed)
                  : txClaimed;
              final branchRemaining = (prize.allocatedQuantity - branchClaimed).clamp(0, prize.allocatedQuantity);

              prizesForBranch.add({
                'eventId': event.id,
                'eventName': event.eventName,
                'giftId': prize.giftId,
                'giftName': prize.name,
                'giftType': prize.giftType,
                'unitValue': prize.unitValue,
                'branchId': bId,
                'branchName': bName,
                'allocated': prize.allocatedQuantity,
                'remaining': branchRemaining,
                'claimed': branchClaimed,
              });
            }
          }
        }
      }

      // Filter by search query if any
      if (_searchQuery.isNotEmpty) {
        final matchesBranchName = bName.toLowerCase().contains(_searchQuery);
        final matchingPrizes = prizesForBranch.where((p) {
          final gName = (p['giftName'] as String? ?? '').toLowerCase();
          return gName.contains(_searchQuery);
        }).toList();

        if (matchesBranchName) {
          branchGroups[bName] = prizesForBranch;
        } else if (matchingPrizes.isNotEmpty) {
          branchGroups[bName] = matchingPrizes;
        }
      } else {
        if (prizesForBranch.isNotEmpty) {
          branchGroups[bName] = prizesForBranch;
        }
      }
    }

    if (branchGroups.isEmpty) {
      return _buildEmptyState(colorScheme: colorScheme, strings: strings);
    }

    return Column(
      children: [
        for (final branchEntry in branchGroups.entries)
          _buildBranchGroupCard(
            colorScheme: colorScheme,
            strings: strings,
            isAr: isAr,
            isHi: isHi,
            isMobile: isMobile,
            branchName: branchEntry.key,
            prizesList: branchEntry.value,
            filteredEvents: filteredEvents,
            masterGifts: masterGifts,
          ),
      ],
    );
  }

  Widget _buildBranchGroupCard({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required String branchName,
    required List<Map<String, dynamic>> prizesList,
    required List<EventModel> filteredEvents,
    required List<CompanyGiftModel> masterGifts,
  }) {
    int branchAllocated = 0;
    int branchClaimed = 0;
    int branchRemaining = 0;

    int branchVoucherAllocated = 0;
    int branchVoucherClaimed = 0;
    int branchVoucherRemaining = 0;
    double branchVoucherBudget = 0.0;

    for (final p in prizesList) {
      final alloc = (p['allocated'] as int? ?? 0);
      final clm = (p['claimed'] as int? ?? 0);
      final rem = (p['remaining'] as int? ?? 0);
      branchAllocated += alloc;
      branchClaimed += clm;
      branchRemaining += rem;

      final gName = (p['giftName'] as String? ?? '');
      final gType = (p['giftType'] as String? ?? 'product');
      final rawUnitVal = (p['unitValue'] as num?)?.toDouble() ?? 0.0;
      final isExplicitVoucher = gType == 'voucher' || _isVoucherText(gName);
      final denom = _extractDenomination(gName, rawUnitVal, giftType: gType);
      if (isExplicitVoucher && denom > 0) {
        branchVoucherAllocated += alloc;
        branchVoucherClaimed += clm;
        branchVoucherRemaining += rem;
        branchVoucherBudget += (alloc * denom);
      }
    }

    final effectiveCompanySlug = widget.lockedCompanySlug.isNotEmpty
        ? widget.lockedCompanySlug
        : (filteredEvents.isNotEmpty ? filteredEvents.first.companySlug : '');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Branch Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.storefront_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        branchName,
                        style: GoogleFonts.cairo(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        '${prizesList.length} ${isAr ? 'أصناف' : 'SKUs'} • $branchAllocated ${isAr ? 'مخصص' : 'Allocated'} • $branchClaimed ${isAr ? 'فائز' : 'Claimed'}',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Branch Summary Badges
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: branchRemaining <= 0
                        ? colorScheme.error.withValues(alpha: 0.12)
                        : colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '$branchRemaining',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: branchRemaining <= 0
                              ? colorScheme.error
                              : colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isAr ? 'متبقي' : 'Left',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: branchRemaining <= 0
                              ? colorScheme.error
                              : colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Dedicated Branch Voucher Sub-Header Banner
          if (branchVoucherAllocated > 0)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.secondary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.secondary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.confirmation_number_rounded,
                    size: 16,
                    color: colorScheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${isAr ? 'قسائم المشتريات بالفرع:' : 'Branch Vouchers:'} $branchVoucherAllocated ${isAr ? 'قسيمة' : 'cards'} (${_formatMoney(branchVoucherBudget, isAr: isAr)}) • ${isAr ? 'منصرف:' : 'Claimed:'} $branchVoucherClaimed • ${isAr ? 'متبقي:' : 'Left:'} $branchVoucherRemaining',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSecondaryFixedVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Branch Items Table
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final p in prizesList)
                  () {
                    final gName = (p['giftName'] as String? ?? '');
                    final gType = (p['giftType'] as String? ?? 'product');
                    final rawUnitVal = (p['unitValue'] as num?)?.toDouble() ?? 0.0;
                    final isExplicitVoucher = gType == 'voucher' || _isVoucherText(gName);
                    final denom = _extractDenomination(gName, rawUnitVal, giftType: gType);
                    final isVoucher = isExplicitVoucher && denom > 0;
                    final rem = p['remaining'] as int? ?? 0;
                    final alloc = p['allocated'] as int? ?? 0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isVoucher
                              ? colorScheme.secondary.withValues(alpha: 0.3)
                              : colorScheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                            size: 18,
                            color: isVoucher
                                ? colorScheme.secondary
                                : (rem <= 0 ? colorScheme.error : colorScheme.primary),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        gName,
                                        style: GoogleFonts.cairo(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    if (isVoucher && denom > 0) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: colorScheme.secondary.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'فئة ${denom.toInt()} ج.م',
                                          style: GoogleFonts.cairo(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                            color: colorScheme.onSecondaryFixedVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  isVoucher && denom > 0
                                      ? '${p['eventName']} • ${_formatMoney(alloc * denom, isAr: isAr)}'
                                      : (p['eventName'] as String? ?? ''),
                                  style: GoogleFonts.cairo(
                                    fontSize: 10,
                                    color: colorScheme.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildBranchQtyPill(
                            label: isAr ? 'المخصص' : 'Allocated',
                            value: '${p['allocated']}',
                            color: colorScheme.onSurfaceVariant,
                            colorScheme: colorScheme,
                          ),
                          const SizedBox(width: 6),
                          _buildBranchQtyPill(
                            label: isAr ? 'المصروف' : 'Claimed',
                            value: '${p['claimed']}',
                            color: colorScheme.secondary,
                            colorScheme: colorScheme,
                          ),
                          const SizedBox(width: 6),
                          _buildBranchQtyPill(
                            label: isAr ? 'المتبقي' : 'Left',
                            value: '${p['remaining']}',
                            color: rem <= 0
                                ? colorScheme.error
                                : colorScheme.tertiary,
                            isHighlight: true,
                            colorScheme: colorScheme,
                          ),
                        if (!widget.isReadOnly) ...[
                        const SizedBox(width: 8),
                        // Quick Supply / Adjust Action Button
                        isMobile
                            ? IconButton.filledTonal(
                                tooltip: strings.quickSupplyBranchBtn,
                                icon: const Icon(Icons.add_rounded, size: 18),
                                style: IconButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(36, 36),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () {
                                  _showAdjustBranchAllocationDialog(
                                    context: context,
                                    colorScheme: colorScheme,
                                    strings: strings,
                                    isAr: isAr,
                                    branchName: branchName,
                                    branchId: p['branchId'] as String? ?? '',
                                    eventId: p['eventId'] as String? ?? '',
                                    eventName: p['eventName'] as String? ?? '',
                                    giftId: p['giftId'] as String? ?? '',
                                    giftName: p['giftName'] as String? ?? '',
                                    currentAllocated: p['allocated'] as int? ?? 0,
                                    currentClaimed: p['claimed'] as int? ?? 0,
                                    currentRemaining: p['remaining'] as int? ?? 0,
                                    companySlug: effectiveCompanySlug,
                                    masterGifts: masterGifts,
                                  );
                                },
                              )
                            : Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed: () {
                                      _showAdjustBranchAllocationDialog(
                                        context: context,
                                        colorScheme: colorScheme,
                                        strings: strings,
                                        isAr: isAr,
                                        branchName: branchName,
                                        branchId: p['branchId'] as String? ?? '',
                                        eventId: p['eventId'] as String? ?? '',
                                        eventName: p['eventName'] as String? ?? '',
                                        giftId: p['giftId'] as String? ?? '',
                                        giftName: p['giftName'] as String? ?? '',
                                        currentAllocated: p['allocated'] as int? ?? 0,
                                        currentClaimed: p['claimed'] as int? ?? 0,
                                        currentRemaining: p['remaining'] as int? ?? 0,
                                        companySlug: effectiveCompanySlug,
                                        masterGifts: masterGifts,
                                        initialDirectMode: false,
                                      );
                                    },
                                    icon: const Icon(Icons.add_circle_outline_rounded, size: 15),
                                    label: Text(
                                      isAr ? 'تزويد' : 'Supply',
                                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      visualDensity: VisualDensity.compact,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: () {
                                      _showAdjustBranchAllocationDialog(
                                        context: context,
                                        colorScheme: colorScheme,
                                        strings: strings,
                                        isAr: isAr,
                                        branchName: branchName,
                                        branchId: p['branchId'] as String? ?? '',
                                        eventId: p['eventId'] as String? ?? '',
                                        eventName: p['eventName'] as String? ?? '',
                                        giftId: p['giftId'] as String? ?? '',
                                        giftName: p['giftName'] as String? ?? '',
                                        currentAllocated: p['allocated'] as int? ?? 0,
                                        currentClaimed: p['claimed'] as int? ?? 0,
                                        currentRemaining: p['remaining'] as int? ?? 0,
                                        companySlug: effectiveCompanySlug,
                                        masterGifts: masterGifts,
                                        initialDirectMode: true,
                                      );
                                    },
                                    icon: const Icon(Icons.edit_note_rounded, size: 15),
                                    label: Text(
                                      isAr ? 'تعديل/تصفير' : 'Edit/Zero',
                                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                                      foregroundColor: colorScheme.onPrimaryFixedVariant,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      visualDensity: VisualDensity.compact,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ],
                              ),
                        ],
                      ],
                    ),
                  );
                }(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchQtyPill({
    required String label,
    required String value,
    required Color color,
    bool isHighlight = false,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isHighlight
            ? color.withValues(alpha: 0.12)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1.1,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 8,
              color: colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mode 2: Campaign-by-Campaign Breakdown (Daily-First Architecture)
  // ---------------------------------------------------------------------------
  static String _formatDateArabic(DateTime dt, bool isAr) {
    if (!isAr) {
      return '${dt.day}/${dt.month}/${dt.year}';
    }
    const weekdays = [
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد',
    ];
    const months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    final weekdayName = weekdays[(dt.weekday - 1) % 7];
    final monthName = months[(dt.month - 1) % 12];
    return '$weekdayName، ${dt.day} $monthName ${dt.year}';
  }

  static bool _isDateToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  static bool _matchesBranchStrict(String prizeBranchName, String prizeBranchId, Map<String, dynamic> data) {
    final normPBranch = _normalizePrizeKey(prizeBranchName);
    final normPId = _normalizePrizeKey(prizeBranchId);

    if (normPBranch.isEmpty && normPId.isEmpty) return true;
    if (normPBranch == 'all' || normPBranch.contains('عام') || normPBranch.contains('كافة')) return true;

    final docBranchId = (data['branch_id'] ?? data['branchId'] ?? '').toString().trim();
    final normDocId = _normalizePrizeKey(docBranchId);
    if (normPId.isNotEmpty && normDocId.isNotEmpty && (normPId == normDocId || normPId.contains(normDocId) || normDocId.contains(normPId))) {
      return true;
    }

    final docBranchName = (data['branch_detected'] ?? data['branch'] ?? data['branchName'] ?? '').toString().trim();
    final normDocName = _normalizePrizeKey(docBranchName);

    if (normDocName.isEmpty) {
      return normPBranch.isEmpty || normPBranch.contains('عام') || normPBranch.contains('كافة');
    }

    if (normDocName == normPBranch || normDocName.contains(normPBranch) || normPBranch.contains(normDocName)) {
      return true;
    }

    return false;
  }

  static bool _matchesPrizeStrict(AllocatedPrize prize, Map<String, dynamic> cg) {
    final gId = (cg['giftId'] ?? cg['gift_id'] ?? '').toString().trim();
    if (gId.isNotEmpty && prize.giftId.isNotEmpty && gId == prize.giftId) {
      return true;
    }

    final gName = (cg['giftName'] ?? cg['gift_name'] ?? '').toString().trim();
    final normG = _normalizePrizeKey(gName);
    final normP = _normalizePrizeKey(prize.name);

    if (normG.isNotEmpty && normG == normP) {
      return true;
    }

    final cgVal = (cg['unitValue'] ?? cg['unit_value'] as num?)?.toDouble() ?? 0.0;
    final cgIsVoucher = cg['isVoucher'] == true || cg['is_voucher'] == true || _isVoucherText(gName);

    // Strict voucher denomination matching
    if (prize.isVoucher && cgIsVoucher && prize.unitValue > 0 && cgVal > 0) {
      if (prize.unitValue.toInt() == cgVal.toInt()) {
        return true;
      }
    }

    // Brand specific match
    final isClearP = normP.contains('كلير') || normP.contains('clear');
    final isClearG = normG.contains('كلير') || normG.contains('clear');
    if (isClearP && isClearG) return true;

    final isTresemmeP = normP.contains('تريزيمي') || normP.contains('تريزمي') || normP.contains('tresemme');
    final isTresemmeG = normG.contains('تريزيمي') || normG.contains('تريزمي') || normG.contains('tresemme');
    if (isTresemmeP && isTresemmeG) return true;

    return false;
  }

  Widget _buildDateFilterBar({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isMobile,
  }) {
    final now = DateTime.now();
    final isSelectedToday = _isDateToday(_selectedDate) && !_isAllTime;
    final canGoForward = !_isAllTime &&
        (_selectedDate.year < now.year ||
            (_selectedDate.year == now.year &&
                (_selectedDate.month < now.month ||
                    (_selectedDate.month == now.month && _selectedDate.day < now.day))));

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 14, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          // Navigation buttons with Date Selector
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Previous day button
              IconButton.filledTonal(
                icon: Icon(isAr ? Icons.chevron_right_rounded : Icons.chevron_left_rounded, size: 20),
                tooltip: isAr ? 'اليوم السابق' : 'Previous Day',
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(),
                onPressed: () {
                  setState(() {
                    _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                    _isAllTime = false;
                  });
                },
              ),
              const SizedBox(width: 6),

              // Date Button
              InkWell(
                onTap: () => _pickDate(context),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _isAllTime
                        ? colorScheme.surface
                        : (isSelectedToday ? colorScheme.primaryContainer : colorScheme.primaryContainer),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isAllTime
                          ? colorScheme.outlineVariant
                          : (isSelectedToday ? colorScheme.primary : colorScheme.primaryFixedDim),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: _isAllTime
                            ? colorScheme.onSurfaceVariant
                            : (isSelectedToday ? colorScheme.primary : colorScheme.onPrimaryContainer),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isAllTime
                            ? (isAr ? 'كافة التواريخ (تراكمي)' : 'All Time (Cumulative)')
                            : _formatDateArabic(_selectedDate, isAr),
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _isAllTime
                              ? colorScheme.onSurfaceVariant
                              : (isSelectedToday ? colorScheme.onPrimaryContainer : colorScheme.onPrimaryContainer),
                        ),
                      ),
                      if (isSelectedToday) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isAr ? 'اليوم' : 'Today',
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
                ),
              ),
              const SizedBox(width: 6),

              // Next day button
              IconButton.filledTonal(
                icon: Icon(isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, size: 20),
                tooltip: isAr ? 'اليوم التالي' : 'Next Day',
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(),
                onPressed: canGoForward
                    ? () {
                        setState(() {
                          _selectedDate = _selectedDate.add(const Duration(days: 1));
                          _isAllTime = false;
                        });
                      }
                    : null,
              ),
            ],
          ),

          // Quick Toggle Buttons (اليوم vs كافة الأيام)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: isSelectedToday ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                  foregroundColor: isSelectedToday ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.today_rounded, size: 16),
                label: Text(
                  isAr ? 'اليوم (الافتراضي)' : 'Today (Default)',
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  setState(() {
                    _selectedDate = DateTime(now.year, now.month, now.day);
                    _isAllTime = false;
                  });
                },
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: _isAllTime ? colorScheme.secondaryContainer : null,
                  foregroundColor: _isAllTime ? colorScheme.onSecondaryContainer : colorScheme.onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.all_inclusive_rounded, size: 16),
                label: Text(
                  isAr ? 'كافة الأيام' : 'All Time',
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  setState(() {
                    _isAllTime = !_isAllTime;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDailyKpisBar({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isMobile,
    required int totalGifts,
    required double totalVouchers,
    required int totalInvoices,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = isMobile
            ? constraints.maxWidth
            : (constraints.maxWidth - 24) / 3;

        return Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            SizedBox(
              width: itemWidth,
              child: _buildMiniStatCard(
                colorScheme: colorScheme,
                icon: Icons.card_giftcard_rounded,
                iconColor: colorScheme.primary,
                title: _isAllTime
                    ? (isAr ? 'إجمالي الهدايا المسحوبة' : 'Total Claimed Gifts')
                    : (isAr ? 'إجمالي هدايا هذا اليوم' : 'Total Gifts On Date'),
                value: '$totalGifts ${isAr ? 'قطعة' : 'items'}',
                subtitle: _isAllTime
                    ? (isAr ? 'تراكمي لكافة التواريخ' : 'Cumulative All Time')
                    : (_isDateToday(_selectedDate) ? (isAr ? 'منصرف اليوم' : "Today's Outflow") : (isAr ? 'منصرف التاريخ' : 'Date Outflow')),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _buildMiniStatCard(
                colorScheme: colorScheme,
                icon: Icons.confirmation_number_rounded,
                iconColor: colorScheme.onSecondaryFixedVariant,
                title: _isAllTime
                    ? (isAr ? 'إجمالي قيمة الفواتشرات' : 'Total Vouchers Value')
                    : (isAr ? 'قيمة فواتشرات هذا اليوم' : 'Vouchers Value On Date'),
                value: '${totalVouchers.toInt()} ${isAr ? 'ج.م' : 'EGP'}',
                subtitle: isAr ? 'قسائم مشتريات منصرفة' : 'Disbursed shopping vouchers',
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _buildMiniStatCard(
                colorScheme: colorScheme,
                icon: Icons.receipt_long_rounded,
                iconColor: colorScheme.onTertiaryFixedVariant,
                title: _isAllTime
                    ? (isAr ? 'إجمالي الفواتير الفائزة' : 'Total Winning Invoices')
                    : (isAr ? 'فواتير هذا اليوم' : 'Invoices On Date'),
                value: '$totalInvoices ${isAr ? 'فاتورة' : 'invoices'}',
                subtitle: isAr ? 'عمليات صرف وهدايا ناجحة' : 'Successful claims',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCampaignBreakdownView({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required List<EventModel> filteredEvents,
    required List<CompanyGiftModel> masterGifts,
    required List<QueryDocumentSnapshot> transactionDocs,
  }) {
    final validEvents = filteredEvents.where((e) {
      if (_searchQuery.isEmpty) return true;
      final matchesName = e.eventName.toLowerCase().contains(_searchQuery);
      final matchesComp = e.targetCompany.toLowerCase().contains(_searchQuery);
      final matchesChain = e.retailChainName.toLowerCase().contains(_searchQuery);
      final matchesPrize = e.allocatedPrizes.any((p) =>
          p.name.toLowerCase().contains(_searchQuery) ||
          p.branchName.toLowerCase().contains(_searchQuery));
      return matchesName || matchesComp || matchesChain || matchesPrize;
    }).toList();

    if (validEvents.isEmpty) {
      return _buildEmptyState(colorScheme: colorScheme, strings: strings);
    }

    // 1. Calculate overall metrics on selected date across all valid campaigns
    int overallGiftsOnDate = 0;
    double overallVouchersOnDate = 0.0;
    int overallInvoicesOnDate = 0;

    for (final doc in transactionDocs) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final eventId = (data['event_id'] ?? data['campaignId'] ?? data['campaign_id'] ?? '').toString();
      final matchesEv = validEvents.any((e) => e.id == eventId);
      if (!matchesEv && eventId.isNotEmpty) continue;

      final status = data['status']?.toString();
      final isValid = data['is_valid'];
      if (status == 'rejected' || isValid == false) continue;
      if (data['game_played'] != true && status != 'approved' && status != 'completed') continue;

      final rawDate = data['claimed_at'] ?? data['created_at'] ?? data['timestamp'] ?? data['date'];
      DateTime? docDate;
      if (rawDate is Timestamp) {
        docDate = rawDate.toDate();
      } else if (rawDate is String && rawDate.isNotEmpty) {
        docDate = DateTime.tryParse(rawDate);
      }

      if (!_isAllTime) {
        if (docDate == null) continue;
        final isSameDay = docDate.year == _selectedDate.year &&
            docDate.month == _selectedDate.month &&
            docDate.day == _selectedDate.day;
        if (!isSameDay) continue;
      }

      overallInvoicesOnDate++;

      final claimedGifts = (data['claimed_gifts'] as List?) ?? [];
      if (claimedGifts.isNotEmpty) {
        for (final cg in claimedGifts) {
          if (cg is Map) {
            final cgMap = Map<String, dynamic>.from(cg);
            final qty = (cgMap['quantity'] as num?)?.toInt() ?? 1;
            final uVal = (cgMap['unitValue'] ?? cgMap['unit_value'] as num?)?.toDouble() ?? 0.0;
            final isVoucher = cgMap['isVoucher'] == true || cgMap['is_voucher'] == true || _isVoucherText(cgMap['giftName'] ?? '');

            overallGiftsOnDate += qty;
            if (isVoucher && uVal > 0) {
              overallVouchersOnDate += (uVal * qty);
            }
          }
        }
      } else {
        final prizesWon = (data['prizes_won'] as List?)?.map((p) => p.toString()).toList() ??
            [(data['prize_won'] ?? '').toString()];
        for (final p in prizesWon) {
          if (p.trim().isNotEmpty) {
            overallGiftsOnDate += 1;
          }
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Date Filter & Navigation Toolbar
        _buildDateFilterBar(
          context: context,
          colorScheme: colorScheme,
          strings: strings,
          isAr: isAr,
          isMobile: isMobile,
        ),

        const SizedBox(height: 14),

        // 2. Summary KPI Metrics for Selected Date
        _buildDailyKpisBar(
          colorScheme: colorScheme,
          strings: strings,
          isAr: isAr,
          isMobile: isMobile,
          totalGifts: overallGiftsOnDate,
          totalVouchers: overallVouchersOnDate,
          totalInvoices: overallInvoicesOnDate,
        ),

        const SizedBox(height: 18),

        // 3. Campaign Breakdown Cards
        for (final event in validEvents)
          _buildCampaignGroupCard(
            colorScheme: colorScheme,
            strings: strings,
            isAr: isAr,
            isHi: isHi,
            isMobile: isMobile,
            event: event,
            masterGifts: masterGifts,
            transactionDocs: transactionDocs,
          ),
      ],
    );
  }

  Widget _buildCampaignGroupCard({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required EventModel event,
    required List<CompanyGiftModel> masterGifts,
    required List<QueryDocumentSnapshot> transactionDocs,
  }) {
    // 1. Calculate campaign duration in days
    final startDate = event.startDate;
    final endDate = event.endDate;
    int campaignDays = 30; // sensible fallback
    if (startDate != null && endDate != null) {
      campaignDays = (endDate.difference(startDate).inDays + 1).clamp(1, 365);
    } else if (startDate != null) {
      campaignDays = (DateTime.now().difference(startDate).inDays + 1).clamp(1, 365);
    }

    // 2. Parse claims for this specific campaign on the selected date
    final Map<String, int> disbursedPerPrizeBranch = {};
    final Map<String, double> disbursedValuePerPrizeBranch = {};
    final Map<String, int> disbursedPerBranch = {};
    final Map<String, double> disbursedValuePerBranch = {};
    int campaignGiftsOnDate = 0;
    double campaignVouchersValueOnDate = 0.0;

    for (final doc in transactionDocs) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final tCampId = (data['campaignId'] ?? data['event_id'] ?? '').toString();
      if (tCampId.isNotEmpty && tCampId != event.id) continue;
      if (data['status'] == 'rejected' || data['is_valid'] == false) continue;
      if (data['game_played'] != true && data['status'] != 'approved' && data['status'] != 'completed') continue;

      // Date check
      final rawDate = data['claimed_at'] ?? data['created_at'] ?? data['timestamp'] ?? data['date'];
      DateTime? txDate;
      if (rawDate is Timestamp) {
        txDate = rawDate.toDate();
      } else if (rawDate is String && rawDate.isNotEmpty) {
        txDate = DateTime.tryParse(rawDate);
      }

      if (!_isAllTime) {
        if (txDate == null) continue;
        final isSameDay = txDate.year == _selectedDate.year &&
            txDate.month == _selectedDate.month &&
            txDate.day == _selectedDate.day;
        if (!isSameDay) continue;
      }

      final claimedGifts = (data['claimed_gifts'] as List?) ?? [];
      if (claimedGifts.isNotEmpty) {
        for (final cg in claimedGifts) {
          if (cg is Map) {
            final cgMap = Map<String, dynamic>.from(cg);
            final qty = (cgMap['quantity'] as num?)?.toInt() ?? 1;
            final uVal = (cgMap['unitValue'] ?? cgMap['unit_value'] as num?)?.toDouble() ?? 0.0;
            final isVoucher = cgMap['isVoucher'] == true || cgMap['is_voucher'] == true || _isVoucherText(cgMap['giftName'] ?? '');

            campaignGiftsOnDate += qty;
            if (isVoucher && uVal > 0) {
              campaignVouchersValueOnDate += (uVal * qty);
            }

            for (final prize in event.allocatedPrizes) {
              if (_matchesBranchStrict(prize.branchName, prize.branchId, data) &&
                  _matchesPrizeStrict(prize, cgMap)) {
                final pKey = '${prize.giftId.isNotEmpty ? prize.giftId : prize.name}__${prize.branchName}';
                disbursedPerPrizeBranch[pKey] = (disbursedPerPrizeBranch[pKey] ?? 0) + qty;
                if (isVoucher && uVal > 0) {
                  disbursedValuePerPrizeBranch[pKey] = (disbursedValuePerPrizeBranch[pKey] ?? 0.0) + (uVal * qty);
                }

                final bKey = prize.branchName.trim();
                disbursedPerBranch[bKey] = (disbursedPerBranch[bKey] ?? 0) + qty;
                if (isVoucher && uVal > 0) {
                  disbursedValuePerBranch[bKey] = (disbursedValuePerBranch[bKey] ?? 0.0) + (uVal * qty);
                }
              }
            }
          }
        }
      } else {
        final prizesWon = (data['prizes_won'] as List?)?.map((p) => p.toString()).toList() ??
            [(data['prize_won'] ?? '').toString()];
        for (final p in prizesWon) {
          if (p.trim().isNotEmpty) {
            campaignGiftsOnDate += 1;
            for (final prize in event.allocatedPrizes) {
              if (_matchesBranchStrict(prize.branchName, prize.branchId, data) &&
                  _matchesPrizeStrict(prize, {'giftName': p})) {
                final pKey = '${prize.giftId.isNotEmpty ? prize.giftId : prize.name}__${prize.branchName}';
                disbursedPerPrizeBranch[pKey] = (disbursedPerPrizeBranch[pKey] ?? 0) + 1;
                final bKey = prize.branchName.trim();
                disbursedPerBranch[bKey] = (disbursedPerBranch[bKey] ?? 0) + 1;
              }
            }
          }
        }
      }
    }

    int getDisbursedForPrizeOnDate(AllocatedPrize prize) {
      final pKey = '${prize.giftId.isNotEmpty ? prize.giftId : prize.name}__${prize.branchName}';
      return disbursedPerPrizeBranch[pKey] ?? 0;
    }

    double getDisbursedValueForPrizeOnDate(AllocatedPrize prize) {
      final pKey = '${prize.giftId.isNotEmpty ? prize.giftId : prize.name}__${prize.branchName}';
      return disbursedValuePerPrizeBranch[pKey] ?? 0.0;
    }

    int getDisbursedForBranchOnDate(String branchName) {
      return disbursedPerBranch[branchName.trim()] ?? 0;
    }

    double getDisbursedValueForBranchOnDate(String branchName) {
      return disbursedValuePerBranch[branchName.trim()] ?? 0.0;
    }

    // 3. Filter valid prizes according to search and branch filters
    final validPrizes = event.allocatedPrizes.where((prize) {
      if (masterGifts.isNotEmpty && _findMatchingMasterGift(prize, masterGifts) == null) {
        return false;
      }
      if (_selectedBranch != null && _selectedBranch!.isNotEmpty) {
        final pBranch = prize.branchName.trim();
        if (pBranch.isNotEmpty && pBranch != _selectedBranch) {
          return false;
        }
      }
      if (_searchQuery.isNotEmpty) {
        final matchesName = prize.name.toLowerCase().contains(_searchQuery);
        final matchesBranch = prize.branchName.toLowerCase().contains(_searchQuery);
        if (!matchesName && !matchesBranch) return false;
      }
      return true;
    }).toList();

    int campaignAllocated = 0;
    int campaignRemaining = 0;

    for (final p in validPrizes) {
      campaignAllocated += p.allocatedQuantity;
      campaignRemaining += p.remainingQuantity;
    }
    final int campaignClaimed = (campaignAllocated - campaignRemaining).clamp(0, campaignAllocated);
    final double depletion = campaignAllocated > 0
        ? (campaignClaimed / campaignAllocated).clamp(0.0, 1.0)
        : 0.0;

    // 4. Group valid prizes by branch
    final Map<String, List<AllocatedPrize>> branchToPrizes = {};
    for (final prize in validPrizes) {
      final bName = prize.branchName.trim().isNotEmpty
          ? prize.branchName.trim()
          : (isAr ? 'كافة الفروع / عام' : 'All Branches / General');
      branchToPrizes.putIfAbsent(bName, () => []).add(prize);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Campaign Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        event.gameType == 'scratch'
                            ? Icons.content_cut_rounded
                            : (event.gameType == 'direct'
                                ? Icons.card_giftcard_rounded
                                : Icons.rotate_right_rounded),
                        color: colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.eventName,
                            style: GoogleFonts.cairo(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            '${event.targetCompany} • ${event.retailChainName.isNotEmpty ? event.retailChainName : (isAr ? 'كافة السلاسل' : 'All Chains')}',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Depletion Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        '${(depletion * 100).toStringAsFixed(0)}% ${strings.depletionRateLabel}',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Campaign Daily Metrics Bar
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Duration Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_today_rounded, size: 12, color: colorScheme.outline),
                          const SizedBox(width: 5),
                          Text(
                            '${strings.campaignDurationLabel}: $campaignDays ${isAr ? 'يوم' : 'days'}',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Claims on Date Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: campaignGiftsOnDate > 0 ? colorScheme.tertiaryContainer : colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: campaignGiftsOnDate > 0 ? colorScheme.tertiaryFixedDim : colorScheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bolt_rounded,
                            size: 13,
                            color: campaignGiftsOnDate > 0 ? colorScheme.onTertiaryFixedVariant : colorScheme.outline,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isAllTime
                                ? (isAr ? 'إجمالي المنصرف: $campaignGiftsOnDate قطعة' : 'Total Claimed: $campaignGiftsOnDate')
                                : (_isDateToday(_selectedDate)
                                    ? '${strings.todayDisbursedLabel}: $campaignGiftsOnDate ${isAr ? 'قطعة' : 'pcs'}'
                                    : '${isAr ? 'منصرف التاريخ' : 'Date Claimed'}: $campaignGiftsOnDate ${isAr ? 'قطعة' : 'pcs'}'),
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: campaignGiftsOnDate > 0 ? colorScheme.onTertiaryContainer : colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (campaignVouchersValueOnDate > 0) ...[
                            Text(
                              ' (${campaignVouchersValueOnDate.toInt()} ${isAr ? 'ج.م' : 'EGP'})',
                              style: GoogleFonts.cairo(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Items inside campaign grouped by branch
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (validPrizes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      isAr ? 'لا توجد هدايا مطابقة لمعايير البحث.' : 'No prizes match current filters.',
                      style: GoogleFonts.cairo(
                        color: colorScheme.outline,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  for (final branchEntry in branchToPrizes.entries) ...[
                    Builder(
                      builder: (context) {
                        final bName = branchEntry.key;
                        final prizesInBranch = branchEntry.value;

                        int bAllocated = 0;
                        int bRemaining = 0;
                        for (final p in prizesInBranch) {
                          bAllocated += p.allocatedQuantity;
                          bRemaining += p.remainingQuantity;
                        }
                        final int bClaimed = (bAllocated - bRemaining).clamp(0, bAllocated);
                        final int bGiftsOnDate = getDisbursedForBranchOnDate(bName);
                        final double bVouchersValueOnDate = getDisbursedValueForBranchOnDate(bName);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Branch Header Banner
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.storefront_rounded,
                                        size: 16,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            bName,
                                            style: GoogleFonts.cairo(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.bold,
                                              color: colorScheme.onSurface,
                                            ),
                                          ),
                                          Text(
                                            '${strings.remainingInBranch}: $bRemaining • ${isAr ? 'المصروف' : 'Claimed'}: $bClaimed • ${strings.outOfLabel} $bAllocated',
                                            style: GoogleFonts.cairo(
                                              fontSize: 10.5,
                                              color: colorScheme.outline,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Branch Claims on Date Badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: bGiftsOnDate > 0 ? colorScheme.tertiaryContainer : colorScheme.surface,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: bGiftsOnDate > 0 ? colorScheme.tertiaryFixedDim : colorScheme.outlineVariant.withValues(alpha: 0.4),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.bolt_rounded,
                                            size: 14,
                                            color: bGiftsOnDate > 0 ? colorScheme.onTertiaryFixedVariant : colorScheme.outline,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _isAllTime
                                                ? (isAr ? 'المصروف: $bGiftsOnDate' : 'Claimed: $bGiftsOnDate')
                                                : (_isDateToday(_selectedDate)
                                                    ? '${strings.todayDisbursedLabel}: $bGiftsOnDate'
                                                    : '${isAr ? 'منصرف التاريخ' : 'Date Claimed'}: $bGiftsOnDate'),
                                            style: GoogleFonts.cairo(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: bGiftsOnDate > 0 ? colorScheme.onTertiaryContainer : colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          if (bVouchersValueOnDate > 0) ...[
                                            const SizedBox(width: 4),
                                            Text(
                                              '(${bVouchersValueOnDate.toInt()} ${isAr ? 'ج.م' : 'EGP'})',
                                              style: GoogleFonts.cairo(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.onSecondaryContainer,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Prize Rows inside Branch (Exact Match with Screenshot 2 Style)
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  children: [
                                    for (final prize in prizesInBranch) ...[
                                      Builder(
                                        builder: (context) {
                                          final int prizeGiftsOnDate = getDisbursedForPrizeOnDate(prize);
                                          final double prizeVouchersValueOnDate = getDisbursedValueForPrizeOnDate(prize);
                                          final int prizeClaimedTotal = (prize.allocatedQuantity - prize.remainingQuantity).clamp(0, prize.allocatedQuantity);
                                          final isVoucher = prize.isVoucher;

                                          return Container(
                                            margin: const EdgeInsets.only(bottom: 10),
                                            padding: EdgeInsets.all(isMobile ? 10 : 14),
                                            decoration: BoxDecoration(
                                              color: colorScheme.surface,
                                              borderRadius: BorderRadius.circular(16),
                                              border: Border.all(
                                                color: prizeGiftsOnDate > 0
                                                    ? (isVoucher ? colorScheme.primaryFixedDim : colorScheme.primary.withValues(alpha: 0.5))
                                                    : colorScheme.outlineVariant.withValues(alpha: 0.4),
                                                width: prizeGiftsOnDate > 0 ? 1.5 : 1.0,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withValues(alpha: 0.02),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                Row(
                                                  crossAxisAlignment: CrossAxisAlignment.center,
                                                  children: [
                                                    // 1. Prominent Highlighted Disbursal Badge on Leading side
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                      decoration: BoxDecoration(
                                                        color: isVoucher
                                                            ? (prizeGiftsOnDate > 0 ? colorScheme.secondary : colorScheme.secondaryContainer)
                                                            : (prizeGiftsOnDate > 0 ? colorScheme.primary : colorScheme.surfaceContainerHighest),
                                                        borderRadius: BorderRadius.circular(12),
                                                      ),
                                                      child: Column(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Text(
                                                            _isAllTime
                                                                ? (isAr ? 'إجمالي المنصرف' : 'Total Claimed')
                                                                : (_isDateToday(_selectedDate)
                                                                    ? (isAr ? 'منصرف اليوم' : 'Today Claimed')
                                                                    : (isAr ? 'منصرف التاريخ' : 'Date Claimed')),
                                                            style: GoogleFonts.cairo(
                                                              fontSize: 9.5,
                                                              fontWeight: FontWeight.bold,
                                                              color: isVoucher
                                                                  ? (prizeGiftsOnDate > 0 ? Colors.white : colorScheme.onSecondaryContainer)
                                                                  : (prizeGiftsOnDate > 0 ? colorScheme.onPrimary : colorScheme.onSurfaceVariant),
                                                              height: 1.1,
                                                            ),
                                                          ),
                                                          Text(
                                                            '$prizeGiftsOnDate ${isAr ? 'قطعة' : 'pcs'}',
                                                            style: GoogleFonts.cairo(
                                                              fontSize: 13,
                                                              fontWeight: FontWeight.w900,
                                                              color: isVoucher
                                                                  ? (prizeGiftsOnDate > 0 ? Colors.white : colorScheme.onSecondaryContainer)
                                                                  : (prizeGiftsOnDate > 0 ? colorScheme.onPrimary : colorScheme.onSurface),
                                                              height: 1.2,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),

                                                    // 2. Prize Title and Stock Information
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Row(
                                                            children: [
                                                              Icon(
                                                                isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                                                                size: 18,
                                                                color: isVoucher ? colorScheme.onSecondaryFixedVariant : colorScheme.primary,
                                                              ),
                                                              const SizedBox(width: 6),
                                                              Expanded(
                                                                child: Text(
                                                                  prize.name,
                                                                  style: GoogleFonts.cairo(
                                                                    fontSize: isMobile ? 13 : 14.5,
                                                                    fontWeight: FontWeight.bold,
                                                                    color: colorScheme.onSurface,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          const SizedBox(height: 2),
                                                          Text(
                                                            '${strings.remainingInBranch}: ${prize.remainingQuantity} ${strings.outOfLabel} ${prize.allocatedQuantity}',
                                                            style: GoogleFonts.cairo(
                                                              fontSize: isMobile ? 11 : 12,
                                                              color: colorScheme.onSurfaceVariant,
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),

                                                    // 3. Trailing Quick Stat Pills
                                                    _buildBranchQtyPill(
                                                      label: isAr ? 'المتبقي' : 'Left',
                                                      value: '${prize.remainingQuantity}',
                                                      color: prize.remainingQuantity <= 0 ? colorScheme.error : colorScheme.tertiary,
                                                      isHighlight: true,
                                                      colorScheme: colorScheme,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    _buildBranchQtyPill(
                                                      label: isAr ? 'المخصص' : 'Allocated',
                                                      value: '${prize.allocatedQuantity}',
                                                      color: colorScheme.onSurfaceVariant,
                                                      colorScheme: colorScheme,
                                                    ),
                                                    if (!isMobile) ...[
                                                      const SizedBox(width: 4),
                                                      _buildBranchQtyPill(
                                                        label: isAr ? 'المصروف الكلي' : 'Total Claimed',
                                                        value: '$prizeClaimedTotal',
                                                        color: colorScheme.secondary,
                                                        colorScheme: colorScheme,
                                                      ),
                                                    ],
                                                  ],
                                                ),

                                                // If voucher has total value on this date
                                                if (isVoucher && (prizeVouchersValueOnDate > 0 || prize.unitValue > 0)) ...[
                                                  const SizedBox(height: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                    decoration: BoxDecoration(
                                                      color: colorScheme.secondaryContainer,
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(color: colorScheme.secondaryFixedDim),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(Icons.payments_rounded, size: 14, color: colorScheme.onSecondaryContainer),
                                                        const SizedBox(width: 6),
                                                        Text(
                                                          prizeVouchersValueOnDate > 0
                                                              ? '${isAr ? 'إجمالي قيمة الفواتشر المنصرفة' : 'Disbursed Vouchers Value'}: ${prizeVouchersValueOnDate.toInt()} ${isAr ? 'ج.م' : 'EGP'}'
                                                              : strings.voucherValueText(prize.unitValue.toStringAsFixed(0)),
                                                          style: GoogleFonts.cairo(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.bold,
                                                            color: colorScheme.onSecondaryContainer,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty State
  // ---------------------------------------------------------------------------
  Widget _buildEmptyState({
    required ColorScheme colorScheme,
    required AppStrings strings,
  }) {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 48,
            color: colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            strings.noGiftsFoundMsg,
            style: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
