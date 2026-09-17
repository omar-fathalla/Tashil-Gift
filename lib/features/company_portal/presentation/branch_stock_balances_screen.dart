import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:excel/excel.dart' as xl;
import '../../../core/services/firebase_service.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/arabic_numbers_utils.dart';
import '../../../core/utils/file_download_helper.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/widgets/m3_button_groups.dart';
import '../../../core/services/company_gifts_service.dart';
import '../../admin/domain/event_model.dart';
import '../../admin/domain/company_gift_model.dart';
import '../domain/campaign_stock_settlement_model.dart';

/// Branch Stock Balances Screen (شاشة تغذية وإدارة أرصدة الفروع)
/// Central hub where Company Manager sets, bulk distributes, increases, and syncs
/// all branch-level gift and voucher quotas directly into campaign allocations.
class BranchStockBalancesScreen extends ConsumerStatefulWidget {
  final String? lockedCompanySlug;
  final String? lockedCompanyName;
  final String? initialEventId;
  final bool isEmbedded;

  const BranchStockBalancesScreen({
    super.key,
    this.lockedCompanySlug,
    this.lockedCompanyName,
    this.initialEventId,
    this.isEmbedded = false,
  });

  @override
  ConsumerState<BranchStockBalancesScreen> createState() => _BranchStockBalancesScreenState();
}

class _BranchStockBalancesScreenState extends ConsumerState<BranchStockBalancesScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _viewMode = 0; // 0: Matrix Grid, 1: Branch Cards
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _bulkQtyController = TextEditingController();
  String? _selectedBulkGiftKey;
  String? _selectedEventId;
  bool _isSaving = false;
  bool _isExporting = false;
  bool _isSettling = false;
  CampaignStockSettlementModel? _selectedSettlement;
  String _searchQuery = '';

  // Golden Standard: Static Persistent In-Memory Caches for 0ms instant render across tab switches
  static final Map<String, List<EventModel>> _persistentEventsCache = {};
  static final Map<String, List<CompanyGiftModel>> _persistentGiftsCache = {};
  static final Map<String, List<QueryDocumentSnapshot>> _persistentTxDocsCache = {};
  static final Map<String, List<CampaignStockSettlementModel>> _persistentSettlementsCache = {};

  // In-memory cache for instant 0ms tab switching
  List<EventModel>? _cachedAllEvents;
  List<CompanyGiftModel>? _cachedMasterGifts;
  List<QueryDocumentSnapshot>? _cachedTxDocs;
  List<CampaignStockSettlementModel>? _cachedSettlements;

  // Memoized stream lifecycle outside build()
  String? _lastStreamsKey;
  Stream<QuerySnapshot>? _eventsStream;
  Stream<QuerySnapshot>? _giftsStream;
  Stream<QuerySnapshot>? _settlementsStream;
  Stream<QuerySnapshot>? _transactionsStream;

  void _ensureStreams(FirebaseFirestore db, String targetSlug, {bool force = false}) {
    final streamKey = targetSlug;

    if (_lastStreamsKey != streamKey || force || _transactionsStream == null) {
      _lastStreamsKey = streamKey;

      if (_eventsStream == null || force) {
        _eventsStream = targetSlug.isNotEmpty
            ? db.collection('events').where('companySlug', isEqualTo: targetSlug).snapshots()
            : db.collection('events').snapshots();
      }

      if (_giftsStream == null || force) {
        _giftsStream = targetSlug.isNotEmpty
            ? db.collection('company_gifts').where('companySlug', isEqualTo: targetSlug).snapshots()
            : db.collection('company_gifts').snapshots();
      }

      if (_settlementsStream == null || force) {
        Query settlementsQuery = db.collection('campaign_stock_settlements');
        if (targetSlug.isNotEmpty) {
          settlementsQuery = settlementsQuery.where('companySlug', isEqualTo: targetSlug);
        }
        _settlementsStream = settlementsQuery.snapshots();
      }

      Query txQuery = db.collection('receipts_transactions');
      if (targetSlug.isNotEmpty) {
        txQuery = txQuery.where('companySlug', isEqualTo: targetSlug);
      }
      _transactionsStream = txQuery.snapshots();
    }
  }

  // Controllers map: key = "${eventId}_${branchName}_${giftKey}"
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, int> _claimedCache = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialEventId != null && widget.initialEventId!.isNotEmpty) {
      _selectedEventId = widget.initialEventId;
    }
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void didUpdateWidget(covariant BranchStockBalancesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialEventId != oldWidget.initialEventId &&
        widget.initialEventId != null &&
        widget.initialEventId!.isNotEmpty) {
      setState(() {
        _selectedEventId = widget.initialEventId;
        _controllers.clear();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _bulkQtyController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _getOrCreateController(String key, int initialValue) {
    final existing = _controllers[key];
    if (existing == null) {
      final ctrl = TextEditingController(text: '$initialValue');
      _controllers[key] = ctrl;
      return ctrl;
    }
    // Auto-update if previous value was 0 and Firestore now loaded real stock
    if (!_isSaving && existing.text == '0' && initialValue > 0) {
      existing.text = '$initialValue';
    }
    return existing;
  }

  Future<void> _saveAllBalances({
    required List<EventModel> events,
    required List<CompanyGiftModel> masterGifts,
    required List<String> branches,
  }) async {
    final isAr = ref.isArabic;
    final colorScheme = Theme.of(context).colorScheme;

    if (events.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAr ? 'لا توجد فعاليات نشطة لحفظ الأرصدة لها' : 'No active campaigns found to save balances',
            style: GoogleFonts.cairo(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final giftsService = ref.read(companyGiftsServiceProvider);
      final effectiveSlug = widget.lockedCompanySlug ?? events.first.companySlug;

      final cellAllocations = <String, int>{};
      for (final event in events) {
        for (final branchName in branches) {
          for (final gift in masterGifts) {
            final giftKey = gift.id.isNotEmpty ? gift.id : gift.giftName;
            final targetEvent = _findEventForGift(gift, events) ?? event;
            final cellKey = '${targetEvent.id}_${branchName}_$giftKey';
            final controller = _controllers[cellKey] ?? _controllers['${event.id}_${branchName}_$giftKey'];
            final val = controller?.text.trim().toIntOrNull() ?? 0;
            cellAllocations[cellKey] = val;
            cellAllocations['${event.id}_${branchName}_$giftKey'] = val;
          }
        }
      }
      for (final entry in _controllers.entries) {
        final val = entry.value.text.trim().toIntOrNull();
        if (val != null && !cellAllocations.containsKey(entry.key)) {
          cellAllocations[entry.key] = val;
        }
      }

      final updatedCount = await giftsService.bulkUpdateBranchPrizeAllocations(
        companySlug: effectiveSlug,
        events: events,
        masterGifts: masterGifts,
        cellAllocations: cellAllocations,
        claimedCache: _claimedCache,
        branches: branches,
        notes: isAr ? 'تغذية وتثبيت الرصيد من شاشة الأرصدة' : 'Stock quota sync from Branch Balances',
        performedBy: 'مدير الشركة',
      );

      HapticFeedback.mediumImpact();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isAr
                        ? 'تم حفظ وتثبيت كافة الأرصدة بنجاح وتحديث قاعدة البيانات ($updatedCount بند)'
                        : 'All $updatedCount branch balances saved and synced successfully',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF006C50),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${isAr ? 'خطأ أثناء الحفظ:' : 'Error saving:'} ${AppErrorHandler.getFriendlyMessage(e)}',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _exportExcelReport({
    required List<EventModel> events,
    required List<CompanyGiftModel> masterGifts,
    required List<String> branches,
    required AppStrings strings,
    required bool isAr,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isExporting = true;
    });

    try {
      final excel = xl.Excel.createExcel();
      final defaultSheet = excel.getDefaultSheet();
      if (defaultSheet != null) {
        excel.delete(defaultSheet);
      }

      final sheetName = _selectedSettlement != null
          ? (isAr ? 'تقرير تسوية ${_selectedSettlement!.cycleTitle}' : 'Settlement ${_selectedSettlement!.cycleTitle}')
          : (isAr ? 'مصفوفة أرصدة الفروع' : 'Branch Balances Matrix');
      final sheet = excel[sheetName];

      // Header row
      final headers = <xl.CellValue>[
        xl.TextCellValue(isAr ? 'الفرع / المنفذ' : 'Branch / Outlet'),
      ];

      for (final g in masterGifts) {
        headers.add(xl.TextCellValue('${g.giftName} (${isAr ? 'المخصص' : 'Alloc'})'));
        headers.add(xl.TextCellValue('${g.giftName} (${isAr ? 'المنصرف' : 'Claimed'})'));
        headers.add(xl.TextCellValue('${g.giftName} (${_selectedSettlement != null ? (isAr ? 'المرتجع' : 'Returned') : (isAr ? 'المتبقي' : 'Left')})'));
      }

      headers.addAll([
        xl.TextCellValue(isAr ? 'إجمالي المخصص' : 'Total Quota'),
        xl.TextCellValue(isAr ? 'إجمالي المنصرف' : 'Total Claimed'),
        xl.TextCellValue(_selectedSettlement != null ? (isAr ? 'إجمالي المرتجع' : 'Total Returned') : (isAr ? 'إجمالي المتبقي' : 'Total Remaining')),
        xl.TextCellValue(isAr ? 'نسبة السحب' : 'Depletion %'),
      ]);
      sheet.appendRow(headers);

      final primaryEvent = events.isNotEmpty ? events.first : null;

      for (final branch in branches) {
        int branchAllocSum = 0;
        int branchClaimSum = 0;

        final rowCells = <xl.CellValue>[
          xl.TextCellValue(branch),
        ];

        final branchSnapshot = _selectedSettlement != null
            ? (_selectedSettlement!.branchSnapshots[branch] as Map<String, dynamic>?)
            : null;

        for (final gift in masterGifts) {
          final giftKey = gift.id.isNotEmpty ? gift.id : gift.giftName;
          int alloc = 0;
          int claimed = 0;
          int remaining = 0;

          if (_selectedSettlement != null) {
            final giftData = (branchSnapshot?['gifts'] as Map<String, dynamic>?)?[giftKey];
            alloc = (giftData?['allocated'] as num?)?.toInt() ?? 0;
            claimed = (giftData?['claimed'] as num?)?.toInt() ?? 0;
            remaining = (giftData?['returned'] as num?)?.toInt() ?? 0;
          } else {
            final targetEvent = _findEventForGift(gift, events) ?? primaryEvent;
            final eventId = targetEvent?.id ?? '';
            final cellKey = '${eventId}_${branch}_$giftKey';
            final ctrl = _controllers[cellKey] ?? _controllers['${primaryEvent?.id ?? ''}_${branch}_$giftKey'];
            alloc = ctrl?.text.trim().toIntOrNull() ?? 0;
            claimed = _claimedCache[cellKey] ?? _claimedCache['${primaryEvent?.id ?? ''}_${branch}_$giftKey'] ?? 0;
            remaining = (alloc - claimed).clamp(0, alloc);
          }

          branchAllocSum += alloc;
          branchClaimSum += claimed;

          rowCells.add(xl.IntCellValue(alloc));
          rowCells.add(xl.IntCellValue(claimed));
          rowCells.add(xl.IntCellValue(remaining));
        }

        final branchRemSum = (branchAllocSum - branchClaimSum).clamp(0, branchAllocSum);
        final rate = branchAllocSum > 0 ? (branchClaimSum / branchAllocSum * 100).toStringAsFixed(1) : '0.0';

        rowCells.addAll([
          xl.IntCellValue(branchAllocSum),
          xl.IntCellValue(branchClaimSum),
          xl.IntCellValue(branchRemSum),
          xl.TextCellValue('%$rate'),
        ]);

        sheet.appendRow(rowCells);
      }

      final fileBytes = excel.save();
      if (fileBytes != null) {
        final now = DateTime.now();
        final timestamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        final slug = widget.lockedCompanySlug ?? 'company';
        final prefix = _selectedSettlement != null ? 'Settlement' : 'Balances';
        final fileName = 'Tashil_${prefix}_${slug}_$timestamp.xlsx';

        downloadFileBytes(
          bytes: fileBytes,
          fileName: fileName,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );

        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    isAr ? '✅ تم تصدير تقرير الأرصدة بنجاح ($fileName)' : '✅ Balances Report exported successfully ($fileName)',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF006C50),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${isAr ? '⚠️ تعذر تصدير تقرير Excel:' : '⚠️ Failed to export Excel report:'} $e',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  String _formatDateShort(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Widget _buildSettlementStat({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.cairo(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  Future<void> _showWeekendSettlementDialog({
    required BuildContext context,
    required EventModel event,
    required List<CompanyGiftModel> masterGifts,
    required List<String> branches,
    required int totalAllocated,
    required int totalClaimed,
    required int totalRemaining,
    required bool isAr,
  }) async {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final cycleTitleController = TextEditingController(
      text: isAr
          ? 'تسوية دورة الويك إند - ${_formatDateShort(now)}'
          : 'Weekend Settlement Cycle - ${_formatDateShort(now)}',
    );
    final newQuotaController = TextEditingController(text: '0');

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD97706).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.published_with_changes_rounded, color: Color(0xFFD97706), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAr ? 'تسوية وإغلاق دورة الويك إند' : 'Settle & Close Weekend Cycle',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          '${event.eventName} (${event.targetCompany})',
                          style: GoogleFonts.cairo(fontSize: 11.5, color: colorScheme.primary, fontWeight: FontWeight.w600),
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
                    // Summary of current cycle
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildSettlementStat(
                            label: isAr ? 'المخصص السابق' : 'Prev Quota',
                            value: '$totalAllocated',
                            color: colorScheme.primary,
                          ),
                          _buildSettlementStat(
                            label: isAr ? 'المنصرف المعتمد' : 'Claimed',
                            value: '$totalClaimed',
                            color: const Color(0xFFD97706),
                          ),
                          _buildSettlementStat(
                            label: isAr ? 'المرتجع للمستودع' : 'Returned',
                            value: '$totalRemaining',
                            color: const Color(0xFF006C50),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Title of settlement
                    TextField(
                      controller: cycleTitleController,
                      style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: isAr ? 'عنوان ومسمى التسوية للأرشيف' : 'Settlement Archive Title',
                        labelStyle: GoogleFonts.cairo(fontSize: 11),
                        filled: true,
                        fillColor: colorScheme.surface,
                        prefixIcon: const Icon(Icons.bookmark_outline_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // New quota input
                    TextField(
                      controller: newQuotaController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                      style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: isAr ? 'الرصيد الجديد لكل صنف في الفروع (للدورة القادمة)' : 'New Quota per Item for Upcoming Wave',
                        labelStyle: GoogleFonts.cairo(fontSize: 11),
                        hintText: '0',
                        helperText: isAr ? 'ضع (0) للتصفير الكامل والبدء من الصفر لإدخال بيانات جديدة' : 'Set (0) for fresh zeroed start to enter new data',
                        helperStyle: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF006C50), fontWeight: FontWeight.w600),
                        filled: true,
                        fillColor: colorScheme.surface,
                        prefixIcon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Quick quota preset chips
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.refresh_rounded, size: 14, color: Colors.teal),
                          label: Text(
                            isAr ? '0 (تصفير كامل للبدء من جديد)' : '0 (Zero & fresh start)',
                            style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal.shade900),
                          ),
                          backgroundColor: Colors.teal.shade50,
                          side: BorderSide(color: Colors.teal.shade200),
                          onPressed: () => setDialogState(() => newQuotaController.text = '0'),
                        ),
                        ActionChip(
                          label: Text('100', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () => setDialogState(() => newQuotaController.text = '100'),
                        ),
                        ActionChip(
                          label: Text('200', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () => setDialogState(() => newQuotaController.text = '200'),
                        ),
                        ActionChip(
                          label: Text('400', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () => setDialogState(() => newQuotaController.text = '400'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, size: 18, color: Colors.amber.shade900),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isAr
                                  ? 'سيتم ترحيل وحفظ أرقام هذا الأسبوع كأرشيف تاريخي دائم، وتصفير البواقي، وتغذية الفروع بالرصيد الجديد لتبدأ فوراً بنسبة سحب 0% مع حفظ كافة الفواتير السابقة.'
                                  : 'This wave will be permanently archived. Remaining stock will be settled as returned, and new quota applied at 0% depletion rate while preserving all invoices.',
                              style: GoogleFonts.cairo(fontSize: 11, color: Colors.amber.shade900, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(isAr ? 'إلغاء' : 'Cancel', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                ),
                FilledButton.icon(
                  onPressed: _isSettling
                      ? null
                      : () async {
                          final title = cycleTitleController.text.trim();
                          final newQuota = newQuotaController.text.trim().toIntOrNull() ?? 400;

                          Navigator.of(dialogContext).pop();
                          await _executeSettlement(
                            event: event,
                            cycleTitle: title,
                            newQuota: newQuota,
                            branches: branches,
                            masterGifts: masterGifts,
                            isAr: isAr,
                          );
                        },
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text(
                    isAr ? 'تأكيد التسوية والأرشفة' : 'Confirm Settlement',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF006C50),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _executeSettlement({
    required EventModel event,
    required String cycleTitle,
    required int newQuota,
    required List<String> branches,
    required List<CompanyGiftModel> masterGifts,
    required bool isAr,
  }) async {
    setState(() => _isSettling = true);
    final messenger = ScaffoldMessenger.of(context);
    final effectiveSlug = widget.lockedCompanySlug ?? event.companySlug;

    try {
      final cellAllocations = <String, int>{};
      for (final entry in _controllers.entries) {
        final val = entry.value.text.trim().toIntOrNull();
        if (val != null) {
          cellAllocations[entry.key] = val;
        }
      }

      final giftsService = ref.read(companyGiftsServiceProvider);
      await giftsService.recordWeekendSettlement(
        companySlug: effectiveSlug,
        event: event,
        cycleTitle: cycleTitle,
        branches: branches,
        masterGifts: masterGifts,
        cellAllocations: cellAllocations,
        claimedCache: _claimedCache,
        newAllocatedQuota: newQuota,
        performedBy: 'مدير الشركة',
      );

      // Update local controllers with the new quota
      for (final branch in branches) {
        for (final gift in masterGifts) {
          final giftKey = gift.id.isNotEmpty ? gift.id : gift.giftName;
          final cellKey = '${event.id}_${branch}_$giftKey';
          if (_controllers.containsKey(cellKey)) {
            _controllers[cellKey]!.text = '$newQuota';
          }
          _claimedCache[cellKey] = 0;
        }
      }

      HapticFeedback.mediumImpact();

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.verified_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isAr
                        ? 'تمت تسوية وأرشفة دورة الويك إند بنجاح وتغذية الفروع بالرصيد الجديد ($newQuota لكل صنف)'
                        : 'Weekend settlement archived successfully and new quotas assigned ($newQuota each)',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF006C50),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${isAr ? '⚠️ خطأ أثناء إجراء التسوية:' : '⚠️ Error executing settlement:'} ${AppErrorHandler.getFriendlyMessage(e)}',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSettling = false);
      }
    }
  }

  void _applyBulkDistribution(List<String> branches, List<EventModel> events, List<CompanyGiftModel> masterGifts) {
    final qty = _bulkQtyController.text.trim().toIntOrNull();
    final isAr = ref.isArabic;
    final effectiveGiftKey = _selectedBulkGiftKey ??
        (masterGifts.isNotEmpty
            ? (masterGifts.first.id.isNotEmpty ? masterGifts.first.id : masterGifts.first.giftName)
            : null);

    if (effectiveGiftKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAr ? 'يرجى اختيار الصنف / الهدية أولاً للتوزيع الموحد' : 'Please select a gift item first',
            style: GoogleFonts.cairo(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (qty == null || qty < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAr ? 'يرجى إدخال كمية صحيحة أكبر من أو تساوي 0' : 'Please enter a valid quantity >= 0',
            style: GoogleFonts.cairo(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _selectedBulkGiftKey = effectiveGiftKey;
      for (final event in events) {
        for (final branchName in branches) {
          final cellKey = '${event.id}_${branchName}_$effectiveGiftKey';
          _getOrCreateController(cellKey, qty).text = '$qty';
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isAr ? 'تم تطبيق كمية ($qty) على كافة الفروع المحددة للصنف' : 'Applied ($qty) to all branches for selected gift',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF006C50),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = AppStrings.of(ref);
    final isAr = ref.isArabic;
    final isHi = ref.isHindi;
    FirebaseFirestore? firestore;
    try {
      firestore = ref.watch(firestoreProvider);
    } catch (_) {
      firestore = null;
    }

    if (firestore == null) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: _buildBalancesContent(
            context: context,
            colorScheme: colorScheme,
            strings: strings,
            isAr: isAr,
            isHi: isHi,
            events: const [],
            allEvents: const [],
            masterGifts: const [],
            txDocs: const [],
          ),
        ),
      );
    }

    final db = firestore;
    final targetSlug = widget.lockedCompanySlug?.toLowerCase().trim() ?? '';
    _ensureStreams(db, targetSlug);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: _eventsStream,
          builder: (context, eventsSnapshot) {
            if (eventsSnapshot.hasData && eventsSnapshot.data!.docs.isNotEmpty) {
              final mapped = eventsSnapshot.data!.docs
                  .map((d) {
                    try {
                      return EventModel.fromFirestore(d);
                    } catch (_) {
                      return null;
                    }
                  })
                  .whereType<EventModel>()
                  .toList();
              if (mapped.isNotEmpty) {
                _persistentEventsCache[targetSlug] = mapped;
                _cachedAllEvents = mapped;
              }
            }

            final allEvents = _persistentEventsCache[targetSlug] ?? _cachedAllEvents ?? [];

            if (eventsSnapshot.connectionState == ConnectionState.waiting && !eventsSnapshot.hasData && allEvents.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            final events = _selectedEventId != null && _selectedEventId!.isNotEmpty
                ? (allEvents.where((e) => e.id == _selectedEventId).toList().isNotEmpty
                    ? allEvents.where((e) => e.id == _selectedEventId).toList()
                    : allEvents)
                : allEvents;

            return StreamBuilder<QuerySnapshot>(
              stream: _giftsStream,
              builder: (context, giftsSnapshot) {
                if (giftsSnapshot.hasData && giftsSnapshot.data!.docs.isNotEmpty) {
                  final mapped = giftsSnapshot.data!.docs
                      .map((d) {
                        try {
                          return CompanyGiftModel.fromFirestore(d);
                        } catch (_) {
                          return null;
                        }
                      })
                      .whereType<CompanyGiftModel>()
                      .toList();
                  if (mapped.isNotEmpty) {
                    _persistentGiftsCache[targetSlug] = mapped;
                    _cachedMasterGifts = mapped;
                  }
                }

                final masterGifts = _persistentGiftsCache[targetSlug] ?? _cachedMasterGifts ?? [];

                if (giftsSnapshot.connectionState == ConnectionState.waiting && !giftsSnapshot.hasData && masterGifts.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: _settlementsStream,
                  builder: (context, settleSnapshot) {
                    if (settleSnapshot.hasData && settleSnapshot.data!.docs.isNotEmpty) {
                      final mapped = settleSnapshot.data!.docs
                          .map((d) {
                            try {
                              return CampaignStockSettlementModel.fromFirestore(d);
                            } catch (_) {
                              return null;
                            }
                          })
                          .whereType<CampaignStockSettlementModel>()
                          .toList()
                        ..sort((a, b) => b.settledAt.compareTo(a.settledAt));
                      if (mapped.isNotEmpty) {
                        _persistentSettlementsCache[targetSlug] = mapped;
                        _cachedSettlements = mapped;
                      }
                    }

                    final settlements = _persistentSettlementsCache[targetSlug] ?? _cachedSettlements ?? [];

                    return StreamBuilder<QuerySnapshot>(
                      stream: _transactionsStream,
                      builder: (context, txSnapshot) {
                        if (txSnapshot.hasData && txSnapshot.data!.docs.isNotEmpty) {
                          _persistentTxDocsCache[targetSlug] = txSnapshot.data!.docs;
                          _cachedTxDocs = txSnapshot.data!.docs;
                        }

                        final txDocs = _persistentTxDocsCache[targetSlug] ?? _cachedTxDocs ?? txSnapshot.data?.docs ?? [];

                        return _buildBalancesContent(
                          context: context,
                          colorScheme: colorScheme,
                          strings: strings,
                          isAr: isAr,
                          isHi: isHi,
                          events: events,
                          allEvents: allEvents,
                          masterGifts: masterGifts,
                          txDocs: txDocs,
                          settlements: settlements,
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  static bool _matchesBranchName(String b1, String b2) {
    return CompanyGiftsService.matchesBranchName(b1, b2);
  }

  static EventModel? _findEventForGift(CompanyGiftModel gift, List<EventModel> events) {
    if (events.length == 1) return events.first;
    for (final ev in events) {
      if (ev.allocatedPrizes.any((p) =>
          (p.giftId.isNotEmpty && p.giftId == gift.id) ||
          p.name.trim().toLowerCase() == gift.giftName.trim().toLowerCase())) {
        return ev;
      }
      if (ev.promotionalRules.any((r) =>
          (r.linkedGiftId != null && r.linkedGiftId == gift.id) ||
          r.linkedGifts.any((lg) =>
              (lg.giftId.isNotEmpty && lg.giftId == gift.id) ||
              lg.giftName.trim().toLowerCase() == gift.giftName.trim().toLowerCase()))) {
        return ev;
      }
    }
    return events.isNotEmpty ? events.first : null;
  }

  Widget _buildBalancesContent({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required List<EventModel> events,
    required List<EventModel> allEvents,
    required List<CompanyGiftModel> masterGifts,
    required List<DocumentSnapshot> txDocs,
    List<CampaignStockSettlementModel> settlements = const [],
  }) {
    // 1. Gather all unique canonical branches
    final List<String> allBranches = [];
    for (final event in events) {
      if (event.branchNames.isNotEmpty) {
        for (final b in event.branchNames) {
          final trimmed = b.trim();
          if (trimmed.isNotEmpty && !allBranches.contains(trimmed)) {
            allBranches.add(trimmed);
          }
        }
      }
      for (final prize in event.allocatedPrizes) {
        final bName = prize.branchName.trim();
        if (bName.isNotEmpty && !allBranches.contains(bName)) {
          allBranches.add(bName);
        }
      }
    }

    if (allBranches.isEmpty) {
      allBranches.add(isAr ? 'كافة الفروع / عام' : 'All Branches');
    }

    // Filter branches by search query
    final filteredBranches = allBranches.where((b) {
      if (_searchQuery.isEmpty) return true;
      return b.toLowerCase().contains(_searchQuery);
    }).toList();

    // For the active wave, determine the latest settlement date cutoff
    final DateTime? activeWaveCutoff = settlements.isNotEmpty ? settlements.first.settledAt : null;

    // Determine effective gifts for the selected campaign vs all campaigns
    final List<CompanyGiftModel> effectiveGifts;
    if (events.length == 1) {
      final singleEvent = events.first;
      final campaignGiftKeys = <String>{};
      for (final p in singleEvent.allocatedPrizes) {
        if (p.giftId.isNotEmpty) campaignGiftKeys.add(p.giftId.toLowerCase().trim());
        if (p.name.isNotEmpty) campaignGiftKeys.add(p.name.toLowerCase().trim());
      }
      for (final r in singleEvent.promotionalRules) {
        if (r.linkedGiftId != null && r.linkedGiftId!.isNotEmpty) {
          campaignGiftKeys.add(r.linkedGiftId!.toLowerCase().trim());
        }
        for (final lg in r.linkedGifts) {
          if (lg.giftId.isNotEmpty) campaignGiftKeys.add(lg.giftId.toLowerCase().trim());
          if (lg.giftName.isNotEmpty) campaignGiftKeys.add(lg.giftName.toLowerCase().trim());
        }
      }

      if (campaignGiftKeys.isNotEmpty) {
        final matched = masterGifts.where((g) {
          final gId = g.id.toLowerCase().trim();
          final gName = g.giftName.toLowerCase().trim();
          return campaignGiftKeys.contains(gId) || campaignGiftKeys.contains(gName);
        }).toList();

        effectiveGifts = matched.isNotEmpty ? matched : masterGifts;
      } else {
        effectiveGifts = masterGifts;
      }
    } else {
      effectiveGifts = masterGifts;
    }

    // Build quick transaction disbursed map: branchName -> (giftKey / normGiftName / normGiftId -> int count)
    final Map<String, Map<String, int>> txBranchDisbursedMap = {};
    for (final doc in txDocs) {
      final data = doc.data() as Map<String, dynamic>;

      // Strictly isolate transactions to the active campaign when scoped
      if (events.length == 1) {
        final targetCampId = events.first.id;
        final docCampId = (data['campaignId'] ?? data['event_id'] ?? data['campaign_id'] ?? data['eventId'] ?? '').toString().trim();
        if (docCampId.isNotEmpty && docCampId != targetCampId) {
          continue; // Belongs to another campaign of the same brand
        }
      } else if (_selectedEventId != null && _selectedEventId!.isNotEmpty) {
        final docCampId = (data['campaignId'] ?? data['event_id'] ?? data['campaign_id'] ?? data['eventId'] ?? '').toString().trim();
        if (docCampId.isNotEmpty && docCampId != _selectedEventId) {
          continue;
        }
      }

      // Filter out transactions created on or before the latest settlement cutoff
      if (activeWaveCutoff != null) {
        DateTime? docDate;
        if (data['timestamp'] is Timestamp) {
          docDate = (data['timestamp'] as Timestamp).toDate();
        } else if (data['created_at'] is Timestamp) {
          docDate = (data['created_at'] as Timestamp).toDate();
        } else if (data['createdAt'] is Timestamp) {
          docDate = (data['createdAt'] as Timestamp).toDate();
        } else if (data['timestamp'] is String) {
          docDate = DateTime.tryParse(data['timestamp']);
        }
        if (docDate != null && !docDate.isAfter(activeWaveCutoff)) {
          // This receipt belongs to an archived previous settlement wave, skip it for the active wave
          continue;
        }
      }

      final rawBranch = (data['canonical_branch'] ?? data['branch_detected'] ?? data['branchName'] ?? data['branch'] ?? '').toString().trim();
      if (rawBranch.isEmpty) continue;

      // Find canonical matching branch name from allBranches
      String? matchedBranch;
      for (final b in allBranches) {
        if (_matchesBranchName(b, rawBranch)) {
          matchedBranch = b;
          break;
        }
      }
      if (matchedBranch == null) continue;

      final branchGiftsMap = txBranchDisbursedMap.putIfAbsent(matchedBranch, () => {});

      // 1. claimed_gifts
      final claimedGifts = (data['claimed_gifts'] as List?) ?? [];
      if (claimedGifts.isNotEmpty) {
        for (final cg in claimedGifts) {
          if (cg is Map) {
            final cgMap = Map<String, dynamic>.from(cg);
            final gName = (cgMap['giftName'] ?? cgMap['name'] ?? '').toString().trim().toLowerCase();
            final gId = (cgMap['giftId'] ?? cgMap['gift_id'] ?? '').toString().trim().toLowerCase();
            final qty = ((cgMap['quantity'] ?? cgMap['count'] ?? 1) as num).toInt();

            if (gId.isNotEmpty) {
              branchGiftsMap[gId] = (branchGiftsMap[gId] ?? 0) + qty;
            }
            if (gName.isNotEmpty) {
              branchGiftsMap[gName] = (branchGiftsMap[gName] ?? 0) + qty;
            }
          }
        }
      } else {
        // 2. linkedGifts
        final linked = (data['linkedGifts'] ?? data['linked_gifts'] as List?) ?? [];
        if (linked.isNotEmpty) {
          for (final lg in linked) {
            if (lg is Map) {
              final lgMap = Map<String, dynamic>.from(lg);
              final gName = (lgMap['giftName'] ?? lgMap['name'] ?? '').toString().trim().toLowerCase();
              final gId = (lgMap['giftId'] ?? lgMap['gift_id'] ?? '').toString().trim().toLowerCase();
              final qty = ((lgMap['quantity'] ?? 1) as num).toInt();

              if (gId.isNotEmpty) {
                branchGiftsMap[gId] = (branchGiftsMap[gId] ?? 0) + qty;
              }
              if (gName.isNotEmpty) {
                branchGiftsMap[gName] = (branchGiftsMap[gName] ?? 0) + qty;
              }
            }
          }
        }

        // 3. prizes_won (List)
        final prizesWon = (data['prizes_won'] as List?) ?? [];
        for (final p in prizesWon) {
          final pName = p.toString().trim().toLowerCase();
          if (pName.isNotEmpty) {
            branchGiftsMap[pName] = (branchGiftsMap[pName] ?? 0) + 1;
          }
        }

        // 4. prize_won (String)
        final prizeWon = (data['prize_won'] ?? data['prizeName'] ?? '').toString().trim().toLowerCase();
        if (prizeWon.isNotEmpty && prizeWon != 'null' && prizeWon != 'لم يفز') {
          branchGiftsMap[prizeWon] = (branchGiftsMap[prizeWon] ?? 0) + 1;
        }

        // 5. voucher_value
        final vVal = (data['voucher_value'] ?? data['voucherValue'] as num?)?.toDouble() ?? 0.0;
        if (vVal > 0) {
          final vKey = 'voucher_${vVal.toInt()}';
          branchGiftsMap[vKey] = (branchGiftsMap[vKey] ?? 0) + 1;
        }
      }
    }

    // 2. Pre-populate controllers & compute overall live metrics
    int totalAllocatedStock = 0;
    int totalClaimedStock = 0;

    for (final event in events) {
      for (final branchName in allBranches) {
        for (final gift in effectiveGifts) {
          final giftKey = gift.id.isNotEmpty ? gift.id : gift.giftName;
          final normGiftName = gift.giftName.trim().toLowerCase();
          final normGiftId = gift.id.trim().toLowerCase();
          final cellKey = '${event.id}_${branchName}_$giftKey';

          // Find matching prize if already allocated
          AllocatedPrize? matchedPrize;
          for (final p in event.allocatedPrizes) {
            final pName = p.name.trim().toLowerCase();
            final pId = p.giftId.trim().toLowerCase();
            final pBranch = p.branchName.trim().toLowerCase();
            final isGiftMatch = pName == normGiftName || (normGiftId.isNotEmpty && pId == normGiftId);
            final isBranchMatch = _matchesBranchName(p.branchName, branchName) ||
                pBranch == branchName.toLowerCase() ||
                (branchName == (isAr ? 'كافة الفروع / عام' : 'All Branches') && pBranch.isEmpty);
            if (isGiftMatch && isBranchMatch) {
              matchedPrize = p;
              break;
            }
          }

          final branchGifts = txBranchDisbursedMap[branchName] ?? {};
          int txClaimed = 0;
          if (normGiftId.isNotEmpty && branchGifts.containsKey(normGiftId)) {
            txClaimed += branchGifts[normGiftId]!;
          } else if (normGiftName.isNotEmpty && branchGifts.containsKey(normGiftName)) {
            txClaimed += branchGifts[normGiftName]!;
          } else {
            // Partial matching for gift name or voucher denomination
            for (final entry in branchGifts.entries) {
              final k = entry.key;
              if (k == normGiftName || k.contains(normGiftName) || normGiftName.contains(k)) {
                txClaimed += entry.value;
              } else if (gift.isVoucher) {
                final denom = gift.unitValue.toInt();
                if (k.contains('$denom') || k == 'voucher_$denom') {
                  txClaimed += entry.value;
                }
              }
            }
          }

          _claimedCache[cellKey] = txClaimed;

          final initialAlloc = matchedPrize?.allocatedQuantity ?? 0;
          final controller = _getOrCreateController(cellKey, initialAlloc);
          final currentAlloc = controller.text.trim().toIntOrNull() ?? initialAlloc;

          totalAllocatedStock += currentAlloc;
          totalClaimedStock += txClaimed;
        }
      }
    }

    if (_selectedSettlement != null) {
      totalAllocatedStock = _selectedSettlement!.totalAllocatedBefore;
      totalClaimedStock = _selectedSettlement!.totalClaimed;
    }

    final totalRemainingStock = _selectedSettlement != null
        ? _selectedSettlement!.totalReturned
        : (totalAllocatedStock - totalClaimedStock).clamp(0, totalAllocatedStock);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header Banner & Save Action
          _buildHeaderCard(
            context: context,
            colorScheme: colorScheme,
            strings: strings,
            isAr: isAr,
            isHi: isHi,
            events: events,
            allEvents: allEvents,
            masterGifts: effectiveGifts,
            branches: allBranches,
            coveredBranchesCount: allBranches.length,
            totalAllocated: totalAllocatedStock,
            totalClaimed: totalClaimedStock,
            totalRemaining: totalRemainingStock,
            settlements: settlements,
          ),

          const SizedBox(height: 16),

          // Archive Information Banner (when reviewing past settlement)
          if (_selectedSettlement != null)
            LayoutBuilder(
              builder: (context, bannerConstraints) {
                final isNarrowBanner = bannerConstraints.maxWidth < 600;
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.amber.shade300, width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.history_edu_rounded, color: Colors.amber.shade900, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isAr
                                      ? '📜 أرشيف تسوية معتمد: ${_selectedSettlement!.cycleTitle}'
                                      : '📜 Archived Settlement: ${_selectedSettlement!.cycleTitle}',
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.amber.shade900),
                                ),
                                Text(
                                  isAr
                                      ? 'تاريخ الاعتماد: ${_formatDateShort(_selectedSettlement!.settledAt)} • المعتمد بواسطة: ${_selectedSettlement!.settledBy}'
                                      : 'Settled At: ${_formatDateShort(_selectedSettlement!.settledAt)} • By: ${_selectedSettlement!.settledBy}',
                                  style: GoogleFonts.cairo(fontSize: 11, color: Colors.amber.shade900),
                                ),
                              ],
                            ),
                          ),
                          if (!isNarrowBanner) ...[
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                              onPressed: () => setState(() => _selectedSettlement = null),
                              icon: const Icon(Icons.arrow_back_rounded, size: 16),
                              label: Text(isAr ? 'العودة للدورة النشطة' : 'Back to Active', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11.5)),
                            ),
                          ],
                        ],
                      ),
                      if (isNarrowBanner) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: () => setState(() => _selectedSettlement = null),
                            icon: const Icon(Icons.arrow_back_rounded, size: 16),
                            label: Text(isAr ? 'العودة للدورة النشطة' : 'Back to Active', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11.5)),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),

          // 2. Quick Bulk Distribution Toolbar (active mode only)
          if (_selectedSettlement == null && effectiveGifts.isNotEmpty)
            _buildBulkDistributionBar(
              colorScheme: colorScheme,
              strings: strings,
              isAr: isAr,
              masterGifts: effectiveGifts,
              branches: allBranches,
              events: events,
            ),

          if (_selectedSettlement == null && effectiveGifts.isNotEmpty)
            const SizedBox(height: 16),

          // 3. Search & View Mode Switcher
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 650;
              final searchField = Container(
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                ),
                child: TextField(
                  controller: _searchController,
                  style: GoogleFonts.cairo(fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: isAr ? 'البحث عن فرع محدد...' : 'Search branch...',
                    hintStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant, fontSize: 13),
                    prefixIcon: Icon(Icons.search_rounded, color: colorScheme.primary, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              );

              final segmentBtn = M3ConnectedButtonGroup<int>(
                height: 40,
                borderRadius: 12,
                selectedValue: _viewMode,
                onSelected: (val) {
                  setState(() {
                    _viewMode = val;
                  });
                },
                segments: [
                  M3ButtonSegment<int>(
                    value: 0,
                    icon: Icons.grid_on_rounded,
                    label: strings.matrixGridView,
                  ),
                  M3ButtonSegment<int>(
                    value: 1,
                    icon: Icons.view_agenda_rounded,
                    label: strings.branchCardsView,
                  ),
                ],
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchField,
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, child: segmentBtn),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 14),
                  segmentBtn,
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          // 4. Main Balances View (Matrix Grid vs Cards)
          if (effectiveGifts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(36),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 48, color: colorScheme.outlineVariant),
                  const SizedBox(height: 12),
                  Text(
                    isAr
                        ? 'لم يتم تعريف أي هدايا في كتالوج الأدمن بعد. يرجى تعريف الهدايا من شاشة الأدمن أولاً.'
                        : 'No gifts defined in Admin Master Catalog yet. Please define gifts in Admin screen first.',
                    style: GoogleFonts.cairo(fontSize: 14, color: colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else if (_viewMode == 0)
            _buildMatrixGridView(
              colorScheme: colorScheme,
              strings: strings,
              isAr: isAr,
              events: events,
              masterGifts: effectiveGifts,
              branches: filteredBranches,
            )
          else
            _buildBranchCardsView(
              colorScheme: colorScheme,
              strings: strings,
              isAr: isAr,
              events: events,
              masterGifts: effectiveGifts,
              branches: filteredBranches,
            ),

          const SizedBox(height: 36),

          // Bottom Floating Save Bar
          Center(
            child: FilledButton.icon(
              onPressed: _isSaving
                  ? null
                  : () => _saveAllBalances(
                        events: events,
                        masterGifts: effectiveGifts,
                        branches: allBranches,
                      ),
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded, size: 20),
              label: Text(
                _isSaving ? (isAr ? 'جاري حفظ الأرصدة...' : 'Saving Balances...') : strings.saveAllBalancesBtn,
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF006C50),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required List<EventModel> events,
    required List<EventModel> allEvents,
    required List<CompanyGiftModel> masterGifts,
    required List<String> branches,
    required int coveredBranchesCount,
    required int totalAllocated,
    required int totalClaimed,
    required int totalRemaining,
    List<CampaignStockSettlementModel> settlements = const [],
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 760;

        final exportExcelBtn = OutlinedButton.icon(
          onPressed: _isExporting
              ? null
              : () => _exportExcelReport(
                    events: events,
                    masterGifts: masterGifts,
                    branches: branches,
                    strings: strings,
                    isAr: isAr,
                  ),
          icon: _isExporting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.table_view_rounded, size: 16),
          label: Text(
            isAr ? 'تصدير Excel' : 'Export Excel',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF006C50),
            side: const BorderSide(color: Color(0xFF006C50), width: 1.2),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );

        final saveAllBtn = FilledButton.icon(
          onPressed: _isSaving
              ? null
              : () => _saveAllBalances(
                    events: events,
                    masterGifts: masterGifts,
                    branches: branches,
                  ),
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_rounded, size: 16),
          label: Text(
            _isSaving ? (isAr ? 'جاري الحفظ...' : 'Saving...') : (isAr ? 'حفظ وتثبيت الأرصدة' : strings.saveAllBalancesBtn),
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF006C50),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
          ),
        );

        final settleWeekendBtn = FilledButton.icon(
          onPressed: _isSettling || events.isEmpty
              ? null
              : () => _showWeekendSettlementDialog(
                    context: context,
                    event: events.first,
                    masterGifts: masterGifts,
                    branches: branches,
                    totalAllocated: totalAllocated,
                    totalClaimed: totalClaimed,
                    totalRemaining: totalRemaining,
                    isAr: isAr,
                  ),
          icon: _isSettling
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.published_with_changes_rounded, size: 16),
          label: Text(
            isAr ? 'تسوية الويك إند وبدء دفعة جديدة' : 'Settle Wave & Start New',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFD97706),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
          ),
        );

        final backToLiveBtn = FilledButton.icon(
          onPressed: () => setState(() => _selectedSettlement = null),
          icon: const Icon(Icons.arrow_back_rounded, size: 16),
          label: Text(
            isAr ? 'العودة للدورة الحالية النشطة' : 'Back to Active Quota',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );

        final headerTitleWidget = Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0284C7), Color(0xFF006C50)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.branchBalancesNavTitle,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18, color: colorScheme.onSurface),
                  ),
                  Text(
                    strings.branchBalancesNavSubtitle,
                    style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        );

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(isCompact ? 14 : 20),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isCompact) ...[
                headerTitleWidget,
                const SizedBox(height: 14),
                if (_selectedSettlement == null) ...[
                  Row(
                    children: [
                      Expanded(child: saveAllBtn),
                      const SizedBox(width: 8),
                      Expanded(child: exportExcelBtn),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: settleWeekendBtn),
                ] else ...[
                  Row(
                    children: [
                      Expanded(child: backToLiveBtn),
                      const SizedBox(width: 8),
                      Expanded(child: exportExcelBtn),
                    ],
                  ),
                ],
              ] else ...[
                Row(
                  children: [
                    Expanded(child: headerTitleWidget),
                    exportExcelBtn,
                    const SizedBox(width: 8),
                    if (_selectedSettlement == null) ...[
                      saveAllBtn,
                      const SizedBox(width: 8),
                      settleWeekendBtn,
                    ] else ...[
                      backToLiveBtn,
                    ],
                  ],
                ),
              ],

              // Wave / Settlement Archive Dropdown Selector
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _selectedSettlement != null
                      ? Colors.amber.shade50
                      : colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedSettlement != null
                        ? Colors.amber.shade300
                        : colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectedSettlement != null ? Icons.history_edu_rounded : Icons.radar_rounded,
                      size: 20,
                      color: _selectedSettlement != null ? Colors.amber.shade900 : const Color(0xFF006C50),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isAr ? 'الدورة / التسوية:' : 'Wave / Cycle:',
                      style: GoogleFonts.cairo(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: _selectedSettlement != null ? Colors.amber.shade900 : colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _selectedSettlement?.id,
                          isExpanded: true,
                          hint: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF006C50),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  isAr
                                      ? '📌 الدورة الحالية النشطة'
                                      : '📌 Current Active Wave',
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF006C50),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF006C50),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      isAr
                                          ? '📌 الدورة الحالية النشطة'
                                          : '📌 Current Active Wave',
                                      style: GoogleFonts.cairo(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF006C50),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ...settlements.map((s) {
                              return DropdownMenuItem<String?>(
                                value: s.id,
                                child: Row(
                                  children: [
                                    const Icon(Icons.archive_outlined, size: 16, color: Color(0xFFD97706)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${s.cycleTitle} (${_formatDateShort(s.settledAt)} • منصرف: ${s.totalClaimed} • مرتجع: ${s.totalReturned})',
                                        style: GoogleFonts.cairo(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurface,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            setState(() {
                              if (val == null) {
                                _selectedSettlement = null;
                              } else {
                                _selectedSettlement = settlements.firstWhere(
                                  (s) => s.id == val,
                                  orElse: () => settlements.first,
                                );
                              }
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Campaign Filter Dropdown (when multiple campaigns exist)
              if (allEvents.length > 1) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.campaign_rounded, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        isAr ? 'الحملة / الفعالية:' : 'Campaign:',
                        style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _selectedEventId != null && allEvents.any((e) => e.id == _selectedEventId)
                                ? _selectedEventId
                                : null,
                            isExpanded: true,
                            hint: Text(
                              isAr ? 'كافة الفعاليات (إجمالي عام)' : 'All Campaigns (Combined)',
                              style: GoogleFonts.cairo(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                            ),
                            items: [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text(
                                  isAr ? 'كافة الفعاليات (إجمالي عام)' : 'All Campaigns (Combined)',
                                  style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                              ...allEvents.map(
                                (e) => DropdownMenuItem<String?>(
                                  value: e.id,
                                  child: Text(
                                    e.eventName,
                                    style: GoogleFonts.cairo(fontSize: 11.5),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              setState(() {
                                _selectedEventId = val;
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // 4 Executive Hero KPI Cards: 1 column on Mobile, 2 on Tablet, 4 on Desktop
              LayoutBuilder(
                builder: (context, kpiConstraints) {
                  final double width = kpiConstraints.maxWidth;
                  final bool isMobile = width < 600;

                  int crossAxisCount = 4;
                  double childAspectRatio = 1.65;
                  if (width < 600) {
                    crossAxisCount = 1;
                    childAspectRatio = 2.35;
                  } else if (width < 960) {
                    crossAxisCount = 2;
                    childAspectRatio = 1.85;
                  } else if (width < 1200) {
                    crossAxisCount = 2;
                    childAspectRatio = 2.1;
                  }

                  final cards = [
                    _buildExecutiveKpiCard(
                      title: strings.coveredOutletsCount,
                      value: '$coveredBranchesCount',
                      unit: isAr ? 'فرع' : 'Branches',
                      subtitle: isAr ? 'الفروع المعتمدة في الحملة' : 'Verified campaign branches',
                      badgeText: isAr ? 'فروع نشطة' : 'Branches',
                      icon: Icons.storefront_rounded,
                      color: const Color(0xFF0284C7),
                      colorScheme: colorScheme,
                      tooltip: isAr ? 'إجمالي الفروع والمنافذ المعتمدة لتوزيع الهدايا' : 'Covered promotional branches',
                      isMobile: isMobile,
                    ),
                    _buildExecutiveKpiCard(
                      title: strings.totalAllocatedGifts,
                      value: '$totalAllocated',
                      unit: isAr ? 'قطعة' : 'Pcs',
                      subtitle: _selectedSettlement != null
                          ? (isAr ? 'الحصة المخصصة بهذه الدورة' : 'Allocated quota this cycle')
                          : (isAr ? 'إجمالي الحصة الموزعة للفروع' : 'Total branch allocated quota'),
                      badgeText: _selectedSettlement != null ? (isAr ? 'حصة مؤرشفة' : 'Archived') : (isAr ? 'حصة مخصصة' : 'Allocated'),
                      icon: Icons.inventory_2_rounded,
                      color: const Color(0xFF006C50),
                      colorScheme: colorScheme,
                      tooltip: isAr ? 'إجمالي عدد القطع والهدايا المخصصة لكافة الفروع' : 'Total allocated gift units',
                      isMobile: isMobile,
                    ),
                    _buildExecutiveKpiCard(
                      title: strings.awardedGiftsCount,
                      value: '$totalClaimed',
                      unit: isAr ? 'قطعة' : 'Pcs',
                      subtitle: _selectedSettlement != null
                          ? (isAr ? 'المنصرف المسجل بالتسوية' : 'Settled claims')
                          : (isAr ? 'الهدايا المسلمة للمستهلكين' : 'Delivered promotional gifts'),
                      badgeText: isAr ? 'هدايا مصروفة' : 'Claimed',
                      icon: Icons.card_giftcard_rounded,
                      color: const Color(0xFFD97706),
                      colorScheme: colorScheme,
                      tooltip: isAr ? 'إجمالي عدد الهدايا والجوائز المصروفة فعلياً للعملاء' : 'Total gifts disbursed to winners',
                      isMobile: isMobile,
                    ),
                    _buildExecutiveKpiCard(
                      title: _selectedSettlement != null ? (isAr ? 'المرتجع للمستودع' : 'Returned Stock') : strings.remainingStockBalance,
                      value: '$totalRemaining',
                      unit: isAr ? 'قطعة' : 'Pcs',
                      subtitle: _selectedSettlement != null
                          ? (isAr ? 'الرصيد المرتجع عند إغلاق الدورة' : 'Returned at cycle close')
                          : (isAr ? 'الرصيد المتبقي بمخزون الفروع' : 'Remaining stock at branches'),
                      badgeText: _selectedSettlement != null ? (isAr ? 'مرتجع للمستودع' : 'Returned') : (isAr ? 'مخزون متبقي' : 'In Stock'),
                      icon: _selectedSettlement != null ? Icons.assignment_return_rounded : Icons.savings_rounded,
                      color: _selectedSettlement != null ? const Color(0xFF006C50) : const Color(0xFF7C3AED),
                      colorScheme: colorScheme,
                      tooltip: _selectedSettlement != null
                          ? (isAr ? 'إجمالي الرصيد الذي تم إغلاقه وإرجاعه لمستودع الشركة' : 'Stock returned to warehouse')
                          : (isAr ? 'رصيد الهدايا المتبقي بالمنافذ والمتاح للصرف' : 'Remaining stock balance'),
                      isMobile: isMobile,
                    ),
                  ];

                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: isMobile ? 12 : 14,
                    crossAxisSpacing: isMobile ? 12 : 14,
                    childAspectRatio: childAspectRatio,
                    children: cards,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExecutiveKpiCard({
    required String title,
    required String value,
    required String unit,
    required String subtitle,
    required String badgeText,
    required IconData icon,
    required Color color,
    required ColorScheme colorScheme,
    required String tooltip,
    bool isMobile = false,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badgeText,
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: colorScheme.onSurface,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    unit,
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 1),
            Text(
              title,
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtitle,
              style: GoogleFonts.cairo(
                fontSize: 9.5,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBulkDistributionBar({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required List<CompanyGiftModel> masterGifts,
    required List<String> branches,
    required List<EventModel> events,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 650;

        final giftSelector = DropdownButtonFormField<String>(
          initialValue: _selectedBulkGiftKey != null &&
                  masterGifts.any((g) => (g.id.isNotEmpty ? g.id : g.giftName) == _selectedBulkGiftKey)
              ? _selectedBulkGiftKey
              : (masterGifts.isNotEmpty
                  ? (masterGifts.first.id.isNotEmpty ? masterGifts.first.id : masterGifts.first.giftName)
                  : null),
          isExpanded: true,
          decoration: InputDecoration(
            labelText: isAr ? 'اختر الصنف / الهدية' : 'Select Gift / Voucher',
            labelStyle: GoogleFonts.cairo(fontSize: 11),
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
          ),
          items: masterGifts.map((g) {
            final key = g.id.isNotEmpty ? g.id : g.giftName;
            return DropdownMenuItem(
              value: key,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    g.isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                    size: 16,
                    color: g.isVoucher ? const Color(0xFFD97706) : const Color(0xFF006C50),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      g.giftName,
                      style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            setState(() {
              _selectedBulkGiftKey = val;
            });
          },
        );

        final qtyField = TextField(
          controller: _bulkQtyController,
          keyboardType: TextInputType.number,
          inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
          decoration: InputDecoration(
            hintText: isAr ? 'الكمية (50)' : 'Qty (50)',
            hintStyle: GoogleFonts.cairo(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
          ),
        );

        final applyBtn = FilledButton.icon(
          onPressed: () => _applyBulkDistribution(branches, events, masterGifts),
          icon: const Icon(Icons.bolt_rounded, size: 16),
          label: Text(
            strings.applyToAllBranchesBtn,
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF006C50),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );

        final zeroBtn = OutlinedButton.icon(
          onPressed: () {
            final effectiveGiftKey = _selectedBulkGiftKey ??
                (masterGifts.isNotEmpty
                    ? (masterGifts.first.id.isNotEmpty ? masterGifts.first.id : masterGifts.first.giftName)
                    : null);
            if (effectiveGiftKey != null) {
              setState(() {
                for (final event in events) {
                  for (final branchName in branches) {
                    final cellKey = '${event.id}_${branchName}_$effectiveGiftKey';
                    _getOrCreateController(cellKey, 0).text = '0';
                  }
                }
              });
            }
          },
          icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.red),
          label: Text(
            isAr ? 'تصفير الصنف' : 'Zero Item',
            style: GoogleFonts.cairo(color: Colors.red[800], fontWeight: FontWeight.bold, fontSize: 12),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.red.withValues(alpha: 0.4), width: 1.2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );

        final zeroAllBtn = OutlinedButton.icon(
          onPressed: () {
            setState(() {
              for (final entry in _controllers.entries) {
                entry.value.text = '0';
              }
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isAr ? 'تم تصفير كافة أرصدة الفروع (0) بنجاح - يمكنك إدخال الكميات الجديدة وحفظها' : 'All branch quotas reset to 0',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
                backgroundColor: Colors.red[800],
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 3),
              ),
            );
          },
          icon: const Icon(Icons.delete_sweep_rounded, size: 16, color: Colors.red),
          label: Text(
            isAr ? 'تصفير كل الأرصدة (0)' : 'Zero All Quotas',
            style: GoogleFonts.cairo(color: Colors.red[800], fontWeight: FontWeight.bold, fontSize: 12),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.red.withValues(alpha: 0.4), width: 1.2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );

        if (isMobile) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.bolt_rounded, color: colorScheme.primary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      strings.bulkDistributeTitle,
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13.5, color: colorScheme.onSurface),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                giftSelector,
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(width: 110, child: qtyField),
                    const SizedBox(width: 8),
                    Expanded(child: applyBtn),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: zeroBtn),
                    const SizedBox(width: 8),
                    Expanded(child: zeroAllBtn),
                  ],
                ),
              ],
            ),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.bolt_rounded, color: colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    strings.bulkDistributeTitle,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.onSurface),
                  ),
                ],
              ),
              SizedBox(width: 230, child: giftSelector),
              SizedBox(width: 110, child: qtyField),
              applyBtn,
              zeroBtn,
              zeroAllBtn,
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderCell({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required ColorScheme colorScheme,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: GoogleFonts.cairo(
                fontSize: 10,
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMatrixGridView({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required List<EventModel> events,
    required List<CompanyGiftModel> masterGifts,
    required List<String> branches,
  }) {
    if (branches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(isAr ? 'لا توجد فروع مطابقة' : 'No matching branches', style: GoogleFonts.cairo()),
        ),
      );
    }

    final primaryEvent = events.isNotEmpty ? events.first : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        // Minimum comfortable column widths
        const branchColMinWidth = 220.0;
        final giftColMinWidth = masterGifts.isEmpty ? 150.0 : 160.0;
        const totalColMinWidth = 120.0;
        const claimedColMinWidth = 120.0;
        const remainingColMinWidth = 120.0;
        const depletionColMinWidth = 140.0;

        final baseTotalWidth = branchColMinWidth +
            (masterGifts.length * giftColMinWidth) +
            totalColMinWidth +
            claimedColMinWidth +
            remainingColMinWidth +
            depletionColMinWidth;

        final double tableWidth = availableWidth > baseTotalWidth ? availableWidth : baseTotalWidth;
        final double scale = availableWidth > baseTotalWidth ? (availableWidth / baseTotalWidth) : 1.0;

        final branchColWidth = branchColMinWidth * scale;
        final giftColWidth = giftColMinWidth * scale;
        final totalColWidth = totalColMinWidth * scale;
        final claimedColWidth = claimedColMinWidth * scale;
        final remainingColWidth = remainingColMinWidth * scale;
        final depletionColWidth = depletionColMinWidth * scale;

        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Table(
                    columnWidths: {
                      0: FixedColumnWidth(branchColWidth),
                      for (int gIdx = 0; gIdx < masterGifts.length; gIdx++)
                        gIdx + 1: FixedColumnWidth(giftColWidth),
                      masterGifts.length + 1: FixedColumnWidth(totalColWidth),
                      masterGifts.length + 2: FixedColumnWidth(claimedColWidth),
                      masterGifts.length + 3: FixedColumnWidth(remainingColWidth),
                      masterGifts.length + 4: FixedColumnWidth(depletionColWidth),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      // Header Row
                      TableRow(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
                          border: Border(
                            bottom: BorderSide(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                              width: 1,
                            ),
                          ),
                        ),
                        children: [
                          _buildHeaderCell(
                            icon: Icons.storefront_rounded,
                            iconColor: colorScheme.primary,
                            title: isAr ? 'الفرع / المنفذ' : 'Branch / Outlet',
                            colorScheme: colorScheme,
                          ),
                          for (final gift in masterGifts)
                            _buildHeaderCell(
                              icon: gift.isVoucher ? Icons.confirmation_number_outlined : Icons.card_giftcard_rounded,
                              iconColor: gift.isVoucher ? const Color(0xFFD97706) : const Color(0xFF006C50),
                              title: gift.giftName,
                              subtitle: gift.isVoucher
                                  ? (isAr ? 'فئة ${gift.unitValue.toInt()} ج.م (مخصص • صرف • باقي)' : '${gift.unitValue.toInt()} EGP')
                                  : (isAr ? '(مخصص • صرف • باقي)' : '(alloc • out • rem)'),
                              colorScheme: colorScheme,
                            ),
                          _buildHeaderCell(
                            icon: Icons.inventory_2_outlined,
                            iconColor: colorScheme.primary,
                            title: isAr ? 'إجمالي المخصص' : 'Total Quota',
                            colorScheme: colorScheme,
                          ),
                          _buildHeaderCell(
                            icon: Icons.shopping_bag_outlined,
                            iconColor: const Color(0xFFD97706),
                            title: isAr ? 'المنصرف للعملاء' : 'Claimed',
                            colorScheme: colorScheme,
                          ),
                          _buildHeaderCell(
                            icon: Icons.savings_outlined,
                            iconColor: const Color(0xFF006C50),
                            title: isAr ? 'المتبقي' : 'Remaining',
                            colorScheme: colorScheme,
                          ),
                          _buildHeaderCell(
                            icon: Icons.analytics_outlined,
                            iconColor: const Color(0xFF0284C7),
                            title: isAr ? 'نسبة السحب' : 'Depletion %',
                            colorScheme: colorScheme,
                          ),
                        ],
                      ),

                      // Data Rows
                      for (int rIdx = 0; rIdx < branches.length; rIdx++)
                        _buildMatrixDataRow(
                          rowIndex: rIdx,
                          branchName: branches[rIdx],
                          masterGifts: masterGifts,
                          events: events,
                          primaryEvent: primaryEvent,
                          isAr: isAr,
                          colorScheme: colorScheme,
                          isLast: rIdx == branches.length - 1,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  TableRow _buildMatrixDataRow({
    required int rowIndex,
    required String branchName,
    required List<CompanyGiftModel> masterGifts,
    required List<EventModel> events,
    required EventModel? primaryEvent,
    required bool isAr,
    required ColorScheme colorScheme,
    required bool isLast,
  }) {
    final isEven = rowIndex % 2 == 0;
    final rowBg = isEven ? colorScheme.surface : colorScheme.surfaceContainerLow.withValues(alpha: 0.5);

    int branchAllocatedSum = 0;
    int branchClaimedSum = 0;

    final cells = <Widget>[
      // 1. Branch Name Cell
      Padding(
        padding: EdgeInsets.only(left: 14, right: 14, top: 14, bottom: isLast ? 22 : 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.store_rounded, size: 16, color: colorScheme.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                branchName,
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5, color: colorScheme.onSurface),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ];

    // 2. Gift Cells
    for (final gift in masterGifts) {
      final giftKey = gift.id.isNotEmpty ? gift.id : gift.giftName;

      if (_selectedSettlement != null) {
        final branchSnapshot = _selectedSettlement!.branchSnapshots[branchName] as Map<String, dynamic>?;
        final giftData = (branchSnapshot?['gifts'] as Map<String, dynamic>?)?[giftKey];
        final alloc = (giftData?['allocated'] as num?)?.toInt() ?? 0;
        final claimed = (giftData?['claimed'] as num?)?.toInt() ?? 0;
        final returned = (giftData?['returned'] as num?)?.toInt() ?? 0;

        branchAllocatedSum += alloc;
        branchClaimedSum += claimed;

        cells.add(
          Padding(
            padding: EdgeInsets.only(left: 10, right: 10, top: 10, bottom: isLast ? 22 : 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 92,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Center(
                    child: Text(
                      '$alloc',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${isAr ? 'صرف:' : 'out:'} $claimed',
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          color: const Color(0xFFD97706),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.outlineVariant,
                        ),
                      ),
                      Text(
                        '${isAr ? 'مرتجع:' : 'ret:'} $returned',
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          color: const Color(0xFF006C50),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        final targetEvent = _findEventForGift(gift, events) ?? primaryEvent;
        final eventId = targetEvent?.id ?? '';
        final cellKey = '${eventId}_${branchName}_$giftKey';

        final controller = _controllers[cellKey] ??
            _controllers['${primaryEvent?.id ?? ''}_${branchName}_$giftKey'] ??
            TextEditingController(text: '0');
        final claimed = _claimedCache[cellKey] ??
            _claimedCache['${primaryEvent?.id ?? ''}_${branchName}_$giftKey'] ??
            0;
        final currentAlloc = controller.text.trim().toIntOrNull() ?? 0;
        final remaining = (currentAlloc - claimed).clamp(0, currentAlloc);

        branchAllocatedSum += currentAlloc;
        branchClaimedSum += claimed;

        cells.add(
          Padding(
            padding: EdgeInsets.only(left: 10, right: 10, top: 10, bottom: isLast ? 22 : 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 92,
                  height: 38,
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                    onChanged: (_) => setState(() {}),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
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
                      hoverColor: colorScheme.primary.withValues(alpha: 0.04),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${isAr ? 'صرف:' : 'out:'} $claimed',
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          color: const Color(0xFFD97706),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.outlineVariant,
                        ),
                      ),
                      Text(
                        '${isAr ? 'باقي:' : 'rem:'} $remaining',
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          color: remaining > 0 ? const Color(0xFF006C50) : Colors.red[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    final branchRemainingSum = (branchAllocatedSum - branchClaimedSum).clamp(0, branchAllocatedSum);
    final depletionRate = branchAllocatedSum > 0 ? (branchClaimedSum / branchAllocatedSum).clamp(0.0, 1.0) : 0.0;
    final depletionPercent = (depletionRate * 100).toStringAsFixed(0);

    // 3. Totals columns
    cells.addAll([
      // Total Quota
      Padding(
        padding: EdgeInsets.only(left: 8, right: 8, top: 14, bottom: isLast ? 22 : 14),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$branchAllocatedSum',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.primary),
            ),
          ),
        ),
      ),
      // Claimed
      Padding(
        padding: EdgeInsets.only(left: 8, right: 8, top: 14, bottom: isLast ? 22 : 14),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFD97706).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$branchClaimedSum',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: const Color(0xFFB45309), fontSize: 13),
            ),
          ),
        ),
      ),
      // Remaining
      Padding(
        padding: EdgeInsets.only(left: 8, right: 8, top: 14, bottom: isLast ? 22 : 14),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF006C50).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$branchRemainingSum',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: const Color(0xFF006C50), fontSize: 13),
            ),
          ),
        ),
      ),
      // Depletion Rate
      Padding(
        padding: EdgeInsets.only(left: 10, right: 10, top: 14, bottom: isLast ? 22 : 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: depletionRate,
                  minHeight: 6,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  color: depletionRate >= 0.9
                      ? Colors.red[700]
                      : (depletionRate >= 0.7 ? Colors.orange[700] : const Color(0xFF006C50)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (depletionRate >= 0.9 ? Colors.red : (depletionRate >= 0.7 ? Colors.orange : const Color(0xFF006C50)))
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '%$depletionPercent',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: depletionRate >= 0.9
                      ? Colors.red[800]
                      : (depletionRate >= 0.7 ? Colors.orange[900] : const Color(0xFF006C50)),
                ),
              ),
            ),
          ],
        ),
      ),
    ]);

    return TableRow(
      decoration: BoxDecoration(
        color: rowBg,
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
      ),
      children: cells,
    );
  }

  Widget _buildBranchCardsView({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required List<EventModel> events,
    required List<CompanyGiftModel> masterGifts,
    required List<String> branches,
  }) {
    if (branches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(isAr ? 'لا توجد فروع مطابقة' : 'No matching branches', style: GoogleFonts.cairo()),
        ),
      );
    }

    final primaryEvent = events.isNotEmpty ? events.first : null;

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: branches.length,
      itemBuilder: (context, index) {
        final branchName = branches[index];
        int branchAllocatedSum = 0;
        int branchClaimedSum = 0;

        final branchSnapshot = _selectedSettlement != null
            ? (_selectedSettlement!.branchSnapshots[branchName] as Map<String, dynamic>?)
            : null;

        if (_selectedSettlement != null) {
          branchAllocatedSum = (branchSnapshot?['totalAllocated'] as num?)?.toInt() ?? 0;
          branchClaimedSum = (branchSnapshot?['totalClaimed'] as num?)?.toInt() ?? 0;
        } else {
          for (final gift in masterGifts) {
            final giftKey = gift.id.isNotEmpty ? gift.id : gift.giftName;
            final targetEvent = _findEventForGift(gift, events) ?? primaryEvent;
            final eventId = targetEvent?.id ?? '';
            final cellKey = '${eventId}_${branchName}_$giftKey';
            final controller = _controllers[cellKey] ?? _controllers['${primaryEvent?.id ?? ''}_${branchName}_$giftKey'];
            final alloc = controller?.text.trim().toIntOrNull() ?? 0;
            final claimed = _claimedCache[cellKey] ?? _claimedCache['${primaryEvent?.id ?? ''}_${branchName}_$giftKey'] ?? 0;
            branchAllocatedSum += alloc;
            branchClaimedSum += claimed;
          }
        }

        final branchRemainingSum = _selectedSettlement != null
            ? ((branchSnapshot?['totalReturned'] as num?)?.toInt() ?? (branchAllocatedSum - branchClaimedSum).clamp(0, branchAllocatedSum))
            : (branchAllocatedSum - branchClaimedSum).clamp(0, branchAllocatedSum);
        final depletionRate = branchAllocatedSum > 0 ? (branchClaimedSum / branchAllocatedSum).clamp(0.0, 1.0) : 0.0;

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Branch Card Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.store_rounded, color: colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      branchName,
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15, color: colorScheme.onSurface),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _selectedSettlement != null
                          ? '${isAr ? 'المرتجع:' : 'Ret:'} $branchRemainingSum / $branchAllocatedSum (${(depletionRate * 100).toStringAsFixed(0)}%)'
                          : '${isAr ? 'المتبقي:' : 'Rem:'} $branchRemainingSum / $branchAllocatedSum (${(depletionRate * 100).toStringAsFixed(0)}%)',
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Depletion Rate Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: depletionRate,
                  minHeight: 4,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    depletionRate >= 0.9
                        ? Colors.red[700]!
                        : depletionRate >= 0.7
                            ? Colors.orange[700]!
                            : const Color(0xFF006C50),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Gifts allocation list inside this branch
              ...masterGifts.map((gift) {
                final giftKey = gift.id.isNotEmpty ? gift.id : gift.giftName;
                final isVoucher = gift.isVoucher;

                if (_selectedSettlement != null) {
                  final giftData = (branchSnapshot?['gifts'] as Map<String, dynamic>?)?[giftKey];
                  final alloc = (giftData?['allocated'] as num?)?.toInt() ?? 0;
                  final claimed = (giftData?['claimed'] as num?)?.toInt() ?? 0;
                  final returned = (giftData?['returned'] as num?)?.toInt() ?? 0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                          size: 18,
                          color: isVoucher ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            gift.giftName,
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Text(
                            '${isAr ? 'مخصص:' : 'Alloc:'} $alloc  •  ${isAr ? 'صرف:' : 'Out:'} $claimed  •  ${isAr ? 'مرتجع:' : 'Ret:'} $returned',
                            style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final targetEvent = _findEventForGift(gift, events) ?? primaryEvent;
                final eventId = targetEvent?.id ?? '';
                final cellKey = '${eventId}_${branchName}_$giftKey';
                final controller = _controllers[cellKey] ??
                    _controllers['${primaryEvent?.id ?? ''}_${branchName}_$giftKey'] ??
                    TextEditingController(text: '0');
                final claimed = _claimedCache[cellKey] ??
                    _claimedCache['${primaryEvent?.id ?? ''}_${branchName}_$giftKey'] ??
                    0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                        size: 18,
                        color: isVoucher ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          gift.giftName,
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (claimed > 0) ...[
                        Text(
                          '${isAr ? 'منصرف:' : 'claimed:'} $claimed',
                          style: GoogleFonts.cairo(fontSize: 11, color: Colors.orange[800], fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                      ],
                      // Quick Decrement Chips (-50, -10)
                      ActionChip(
                        label: Text('-50', style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.red[800])),
                        backgroundColor: Colors.red.withValues(alpha: 0.08),
                        side: BorderSide(color: Colors.red.withValues(alpha: 0.2)),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          final cur = controller.text.trim().toIntOrNull() ?? 0;
                          final minAllowed = claimed;
                          final nextVal = (cur - 50).clamp(minAllowed, 999999);
                          if (nextVal < cur) {
                            setState(() {
                              controller.text = '$nextVal';
                            });
                          } else if (cur <= claimed && claimed > 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isAr
                                      ? 'لا يمكن تقليل الرصيد عن الكمية المنصرفة بالفعل ($claimed قطعة)'
                                      : 'Cannot decrease below already claimed items ($claimed pcs)',
                                  style: GoogleFonts.cairo(),
                                ),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(width: 4),
                      ActionChip(
                        label: Text('-10', style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.red[800])),
                        backgroundColor: Colors.red.withValues(alpha: 0.08),
                        side: BorderSide(color: Colors.red.withValues(alpha: 0.2)),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          final cur = controller.text.trim().toIntOrNull() ?? 0;
                          final minAllowed = claimed;
                          final nextVal = (cur - 10).clamp(minAllowed, 999999);
                          if (nextVal < cur) {
                            setState(() {
                              controller.text = '$nextVal';
                            });
                          } else if (cur <= claimed && claimed > 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isAr
                                      ? 'لا يمكن تقليل الرصيد عن الكمية المنصرفة بالفعل ($claimed قطعة)'
                                      : 'Cannot decrease below already claimed items ($claimed pcs)',
                                  style: GoogleFonts.cairo(),
                                ),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 78,
                        height: 38,
                        child: TextField(
                          controller: controller,
                          keyboardType: TextInputType.number,
                          inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                          onChanged: (_) => setState(() {}),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.onSurface),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: colorScheme.outlineVariant),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: colorScheme.primary, width: 2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Quick Increment Chips (+10, +50)
                      ActionChip(
                        label: Text('+10', style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: const Color(0xFF006C50))),
                        backgroundColor: const Color(0xFF006C50).withValues(alpha: 0.08),
                        side: BorderSide(color: const Color(0xFF006C50).withValues(alpha: 0.2)),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          final cur = controller.text.trim().toIntOrNull() ?? 0;
                          setState(() {
                            controller.text = '${cur + 10}';
                          });
                        },
                      ),
                      const SizedBox(width: 4),
                      ActionChip(
                        label: Text('+50', style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: const Color(0xFF006C50))),
                        backgroundColor: const Color(0xFF006C50).withValues(alpha: 0.08),
                        side: BorderSide(color: const Color(0xFF006C50).withValues(alpha: 0.2)),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          final cur = controller.text.trim().toIntOrNull() ?? 0;
                          setState(() {
                            controller.text = '${cur + 50}';
                          });
                        },
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
