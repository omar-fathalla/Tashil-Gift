import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:excel/excel.dart' as xl;

import '../../../core/services/firebase_service.dart';
import '../../../core/services/daily_sales_aggregation_service.dart';
import '../../../core/services/company_gifts_service.dart';
import '../../../core/services/chain_products_intelligence_service.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/file_download_helper.dart';
import '../../../core/utils/slug_utils.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../admin/domain/event_model.dart';
import '../../admin/domain/company_gift_model.dart';
import '../domain/daily_branch_sales_model.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/m3_adaptive_scaffold.dart';

/// Screen for tracking Daily Sales Revenue and Gift/Voucher Disbursals per Branch & Campaign Date.
class DailyBranchSalesScreen extends ConsumerStatefulWidget {
  final String? lockedCompanySlug;
  final String? initialEventId;
  final String? lockedEventId;

  const DailyBranchSalesScreen({
    super.key,
    this.lockedCompanySlug,
    this.initialEventId,
    this.lockedEventId,
  });

  @override
  ConsumerState<DailyBranchSalesScreen> createState() => _DailyBranchSalesScreenState();
}

class _DailyBranchSalesScreenState extends ConsumerState<DailyBranchSalesScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String? _selectedEventId = 'all';
  late DateTime _selectedDate;
  bool _isAllDays = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _isExporting = false;
  // Golden Standard: Static Persistent In-Memory Caches for 0ms instant render across tab switches
  static final Map<String, List<DailyBranchSalesModel>> _persistentSalesCache = {};
  static final Map<String, List<EventModel>> _persistentEventsCache = {};
  static final Map<String, List<CompanyGiftModel>> _persistentGiftsCache = {};
  static final Map<String, List<Map<String, dynamic>>> _persistentTxCache = {};

  List<DailyBranchSalesModel>? _lastLoadedRecords;

  // Memoized stream lifecycle outside build()
  String? _lastStreamsKey;
  Stream<QuerySnapshot>? _eventsStream;
  Stream<List<CompanyGiftModel>>? _giftsStream;
  Stream<QuerySnapshot>? _transactionsStream;

  void _ensureStreams(FirebaseFirestore activeDb, String effectiveSlug, {bool force = false}) {
    final streamKey = effectiveSlug;

    if (_lastStreamsKey != streamKey || force || _transactionsStream == null) {
      _lastStreamsKey = streamKey;

      if (_eventsStream == null || force) {
        _eventsStream = effectiveSlug.isNotEmpty
            ? activeDb.collection('events').where('companySlug', isEqualTo: effectiveSlug).snapshots()
            : activeDb.collection('events').snapshots();
      }

      if (_giftsStream == null || force) {
        _giftsStream = ref.read(companyGiftsServiceProvider).giftsStream(effectiveSlug);
      }

      Query transactionsQuery = activeDb.collection('receipts_transactions');
      if (effectiveSlug.isNotEmpty) {
        transactionsQuery = transactionsQuery.where('companySlug', isEqualTo: effectiveSlug);
      }
      _transactionsStream = transactionsQuery.snapshots();
    }
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    final effectiveEventId = (widget.lockedEventId != null && widget.lockedEventId!.isNotEmpty)
        ? widget.lockedEventId
        : widget.initialEventId;
    _selectedEventId = (effectiveEventId != null && effectiveEventId.isNotEmpty)
        ? effectiveEventId
        : 'all';
    _searchController.addListener(() {
      if (_searchQuery != _searchController.text) {
        setState(() {
          _searchQuery = _searchController.text;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant DailyBranchSalesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final effectiveEventId = (widget.lockedEventId != null && widget.lockedEventId!.isNotEmpty)
        ? widget.lockedEventId
        : widget.initialEventId;
    final oldEffectiveEventId = (oldWidget.lockedEventId != null && oldWidget.lockedEventId!.isNotEmpty)
        ? oldWidget.lockedEventId
        : oldWidget.initialEventId;
    if (effectiveEventId != oldEffectiveEventId &&
        effectiveEventId != null &&
        effectiveEventId.isNotEmpty) {
      setState(() {
        _selectedEventId = effectiveEventId;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Normalizes Arabic strings for deterministic comparison
  static String _normalizeGiftStatic(String name) {
    if (name.isEmpty) return '';
    var s = name.trim().toLowerCase();
    s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    s = s.replaceAll(RegExp(r'[أإآٱ]'), 'ا');
    s = s.replaceAll('ة', 'ه');
    s = s.replaceAll('ى', 'ي');
    s = s.replaceAll('ـ', '');
    s = s.replaceAll(RegExp(r'[()\[\]{}،,.:\-_]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// Resolves disbursed gift quantity for a master gift from record.giftsDisbursed
  /// Handles ID matches, name matches, normalized Arabic comparisons, containment, and single-gift fallback.
  int _resolveDisbursedGiftQty(
    DailyBranchSalesModel record,
    CompanyGiftModel gift,
    List<CompanyGiftModel> allMasterGifts,
  ) {
    if (record.giftsDisbursed.isEmpty) {
      if (allMasterGifts.length == 1 && record.totalGiftsCount > 0) {
        return record.totalGiftsCount;
      }
      return 0;
    }

    int totalQty = 0;
    final Set<String> matchedKeys = {};

    // 1. Direct ID match
    if (gift.id.isNotEmpty && record.giftsDisbursed.containsKey(gift.id)) {
      totalQty += record.giftsDisbursed[gift.id]!.quantity;
      matchedKeys.add(gift.id);
    }

    // 2. Direct Name match
    if (gift.giftName.isNotEmpty && record.giftsDisbursed.containsKey(gift.giftName)) {
      if (!matchedKeys.contains(gift.giftName)) {
        totalQty += record.giftsDisbursed[gift.giftName]!.quantity;
        matchedKeys.add(gift.giftName);
      }
    }

    // 3. Normalized comparison across all disbursed entries in record
    final normMaster = _normalizeGiftStatic(gift.giftName);
    for (final entry in record.giftsDisbursed.entries) {
      if (matchedKeys.contains(entry.key)) continue;

      final item = entry.value;
      final normKey = _normalizeGiftStatic(entry.key);
      final normName = _normalizeGiftStatic(item.giftName);

      // Exact normalized equality
      if (normMaster.isNotEmpty && (normKey == normMaster || normName == normMaster)) {
        totalQty += item.quantity;
        matchedKeys.add(entry.key);
        continue;
      }

      // Fuzzy containment: e.g. "لانش بوكس" inside "لانش بوكس كادبوري"
      if (normMaster.isNotEmpty &&
          (normName.contains(normMaster) ||
           normMaster.contains(normName) ||
           normKey.contains(normMaster))) {
        bool moreSpecificMatchExists = false;
        for (final otherGift in allMasterGifts) {
          if (otherGift.id == gift.id) continue;
          final normOther = _normalizeGiftStatic(otherGift.giftName);
          if (normOther.isNotEmpty &&
              normOther.length > normMaster.length &&
              (normName.contains(normOther) || normKey.contains(normOther))) {
            moreSpecificMatchExists = true;
            break;
          }
        }
        if (!moreSpecificMatchExists) {
          totalQty += item.quantity;
          matchedKeys.add(entry.key);
          continue;
        }
      }

      // Voucher denomination matching
      if (gift.isVoucher && item.isVoucher) {
        if (gift.unitValue > 0 && (gift.unitValue - item.unitValue).abs() < 0.01) {
          totalQty += item.quantity;
          matchedKeys.add(entry.key);
          continue;
        }
      }
    }

    // 4. Single Master Gift fallback:
    if (allMasterGifts.length == 1 && totalQty == 0 && record.totalGiftsCount > 0) {
      return record.totalGiftsCount;
    }

    return totalQty;
  }

  String _formatDateStr(DateTime dt) {
    return "${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDisplayDate(DateTime dt, bool isAr) {
    if (!isAr) {
      return intl.DateFormat('EEE, dd MMM yyyy').format(dt);
    }
    const weekdays = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    final weekdayName = weekdays[(dt.weekday - 1) % 7];
    final monthName = months[(dt.month - 1) % 12];
    return '$weekdayName، ${dt.day} $monthName ${dt.year}';
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
        _isAllDays = false;
      });
    }
  }



  Future<void> _exportExcelReport({
    required List<DailyBranchSalesModel> salesRecords,
    required List<CompanyGiftModel> masterGifts,
    required String campaignName,
    required bool isAr,
  }) async {
    setState(() {
      _isExporting = true;
    });

    try {
      final excel = xl.Excel.createExcel();
      final sheetName = isAr ? 'المبيعات وسحب الهدايا' : 'Daily Sales & Gifts';
      final defaultSheet = excel.getDefaultSheet();
      if (defaultSheet != null) {
        excel.rename(defaultSheet, sheetName);
      }

      final sheet = excel[sheetName];
      sheet.isRTL = isAr;

      // Header Row
      final headers = [
        isAr ? 'الفترة / التاريخ' : 'Date / Period',
        isAr ? 'الفرع / المنفذ' : 'Branch',
        isAr ? 'عدد الفواتير' : 'Invoices',
        isAr ? 'إجمالي المبيعات (ج.م)' : 'Sales (EGP)',
        ...masterGifts.map((g) => '${g.giftName} ${g.isVoucher ? "(فواتشر)" : "(هدية)"}'),
        isAr ? 'إجمالي الهدايا المنصرفة' : 'Total Gifts Disbursed',
        isAr ? 'إجمالي قيمة الفواتشرات' : 'Total Vouchers Value',
      ];

      for (var col = 0; col < headers.length; col++) {
        final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
        cell.value = xl.TextCellValue(headers[col]);
        cell.cellStyle = xl.CellStyle(
          bold: true,
          horizontalAlign: xl.HorizontalAlign.Center,
          backgroundColorHex: xl.ExcelColor.fromHexString('#5C631D'),
          fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
        );
      }

      int rowIndex = 1;
      for (final rec in salesRecords) {
        int colIndex = 0;
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(rec.dateStr);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.TextCellValue(rec.branchName);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.IntCellValue(rec.invoicesCount);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.DoubleCellValue(rec.totalSalesAmount);

        for (final gift in masterGifts) {
          final qty = _resolveDisbursedGiftQty(rec, gift, masterGifts);
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.IntCellValue(qty);
        }

        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.IntCellValue(rec.totalGiftsCount);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.DoubleCellValue(rec.totalVouchersValue);
        rowIndex++;
      }

      // Grand Totals Summary Row in Excel
      if (salesRecords.isNotEmpty) {
        int totCol = 0;
        final totInvoices = salesRecords.fold<int>(0, (s, r) => s + r.invoicesCount);
        final totSales = salesRecords.fold<double>(0.0, (s, r) => s + r.totalSalesAmount);
        final totGifts = salesRecords.fold<int>(0, (s, r) => s + r.totalGiftsCount);
        final totVouchers = salesRecords.fold<double>(0.0, (s, r) => s + r.totalVouchersValue);

        final totalCellLabel = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: totCol++, rowIndex: rowIndex));
        totalCellLabel.value = xl.TextCellValue(isAr ? 'الإجمالي العام' : 'Grand Total');
        totalCellLabel.cellStyle = xl.CellStyle(bold: true);

        final totalBranchCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: totCol++, rowIndex: rowIndex));
        totalBranchCell.value = xl.TextCellValue('-');

        final totalInvCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: totCol++, rowIndex: rowIndex));
        totalInvCell.value = xl.IntCellValue(totInvoices);
        totalInvCell.cellStyle = xl.CellStyle(bold: true);

        final totalSalesCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: totCol++, rowIndex: rowIndex));
        totalSalesCell.value = xl.DoubleCellValue(totSales);
        totalSalesCell.cellStyle = xl.CellStyle(bold: true);

        for (final gift in masterGifts) {
          final giftTot = salesRecords.fold<int>(0, (s, r) => s + _resolveDisbursedGiftQty(r, gift, masterGifts));
          final gCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: totCol++, rowIndex: rowIndex));
          gCell.value = xl.IntCellValue(giftTot);
          gCell.cellStyle = xl.CellStyle(bold: true);
        }

        final totGiftsCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: totCol++, rowIndex: rowIndex));
        totGiftsCell.value = xl.IntCellValue(totGifts);
        totGiftsCell.cellStyle = xl.CellStyle(bold: true);

        final totVouchersCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: totCol++, rowIndex: rowIndex));
        totVouchersCell.value = xl.DoubleCellValue(totVouchers);
        totVouchersCell.cellStyle = xl.CellStyle(bold: true);
      }

      final fileBytes = excel.save();
      if (fileBytes != null) {
        final dateLabel = _isAllDays ? 'all_days' : _formatDateStr(_selectedDate);
        final fileName = 'daily_sales_${dateLabel}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
        downloadFileBytes(
          bytes: fileBytes,
          fileName: fileName,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${isAr ? 'خطأ في التصدير:' : 'Export error:'} ${AppErrorHandler.getFriendlyMessage(e)}',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = AppStrings.of(ref);
    final isAr = ref.isArabic;
    final effectiveSlug = (widget.lockedCompanySlug ?? '').toLowerCase().trim();

    FirebaseFirestore? firestore;
    try {
      firestore = ref.watch(firestoreProvider);
    } catch (_) {
      firestore = null;
    }

    final activeDb = firestore;
    if (activeDb == null) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: _buildContent(
          context: context,
          colorScheme: colorScheme,
          strings: strings,
          isAr: isAr,
          effectiveSlug: effectiveSlug,
          events: const [],
          currentEvent: null,
          masterGifts: const [],
          records: const [],
        ),
      );
    }

    _ensureStreams(activeDb, effectiveSlug);

    return StreamBuilder<QuerySnapshot>(
      stream: _eventsStream,
      builder: (context, eventsSnap) {
        if (eventsSnap.hasData && eventsSnap.data!.docs.isNotEmpty) {
          _persistentEventsCache[effectiveSlug] = eventsSnap.data!.docs
              .map((d) {
                try {
                  return EventModel.fromFirestore(d);
                } catch (_) {
                  return null;
                }
              })
              .whereType<EventModel>()
              .toList();
        }

        final isCampaignLocked = widget.lockedEventId != null && widget.lockedEventId!.isNotEmpty;
        if (isCampaignLocked && _selectedEventId != widget.lockedEventId) {
          _selectedEventId = widget.lockedEventId;
        }

        final rawCompanyEvents = _persistentEventsCache[effectiveSlug] ?? (eventsSnap.data?.docs ?? [])
            .map((d) {
              try {
                return EventModel.fromFirestore(d);
              } catch (_) {
                return null;
              }
            })
            .whereType<EventModel>()
            .toList();

        final companyEvents = isCampaignLocked
            ? rawCompanyEvents.where((e) => e.id == widget.lockedEventId).toList()
            : rawCompanyEvents;

        // Selected Campaign Scoping
        final isAllCampaigns = !isCampaignLocked &&
            (_selectedEventId == null || _selectedEventId == 'all' || _selectedEventId == 'ALL');
        EventModel? currentEvent;
        if (!isAllCampaigns) {
          final targetId = isCampaignLocked ? widget.lockedEventId : _selectedEventId;
          currentEvent = companyEvents.where((e) => e.id == targetId).firstOrNull;
        }

        final targetEventId = isAllCampaigns ? null : (currentEvent?.id ?? (isCampaignLocked ? widget.lockedEventId : null));
        final targetDateStr = _isAllDays ? null : _formatDateStr(_selectedDate);
        final cacheKey = '${effectiveSlug}_${targetEventId ?? 'all'}_${targetDateStr ?? 'all'}';

        return StreamBuilder<List<CompanyGiftModel>>(
          stream: _giftsStream,
          builder: (context, giftsSnap) {
            if (giftsSnap.hasData && giftsSnap.data!.isNotEmpty) {
              _persistentGiftsCache[effectiveSlug] = giftsSnap.data!;
            }
            final masterGifts = giftsSnap.data ?? _persistentGiftsCache[effectiveSlug] ?? [];

            return StreamBuilder<QuerySnapshot>(
              stream: _transactionsStream,
              builder: (context, txSnap) {
                if (txSnap.hasData) {
                  final docs = txSnap.data!.docs;
                  final mapped = docs.map((d) => d.data() as Map<String, dynamic>).toList();
                  if (mapped.isNotEmpty || !_persistentTxCache.containsKey(cacheKey)) {
                    _persistentTxCache[cacheKey] = mapped;
                  }
                }

                final unFilteredTransactions = _persistentTxCache[cacheKey] ?? (txSnap.data?.docs ?? []).map((d) => d.data() as Map<String, dynamic>).toList();
                final rawTransactions = isCampaignLocked
                    ? unFilteredTransactions.where((tx) => tx['campaignId']?.toString() == widget.lockedEventId).toList()
                    : unFilteredTransactions;
                final cachedSales = _persistentSalesCache[cacheKey];

                if (txSnap.connectionState == ConnectionState.waiting && !txSnap.hasData && _lastLoadedRecords == null && cachedSales == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                final companyEventIds = companyEvents.map((d) => d.id).toSet();
                final companyEventNames = <String, String>{
                  for (var d in companyEvents) d.id: d.eventName
                };
                final companyTargetNames = companyEvents
                    .map((d) => d.targetCompany.trim())
                    .where((t) => t.isNotEmpty)
                    .toSet();

                final Set<String> companyBranches = {};
                if (currentEvent != null && currentEvent.branchNames.isNotEmpty) {
                  companyBranches.addAll(currentEvent.branchNames);
                } else {
                  for (final d in companyEvents) {
                    companyBranches.addAll(d.branchNames);
                  }
                }

                final displayRecords = (rawTransactions.isNotEmpty || cachedSales == null)
                    ? DailySalesAggregationService.aggregateTransactionsData(
                        rawTransactions: rawTransactions,
                        companySlug: effectiveSlug,
                        campaignId: targetEventId,
                        targetDateStr: targetDateStr,
                        companyBranches: companyBranches,
                        companyEventIds: companyEventIds,
                        companyEventNames: companyEventNames,
                        companyTargetNames: companyTargetNames,
                      )
                    : cachedSales;

                if (displayRecords.isNotEmpty || rawTransactions.isNotEmpty) {
                  _lastLoadedRecords = displayRecords;
                  _persistentSalesCache[cacheKey] = displayRecords;
                }

                return _buildContent(
                  context: context,
                  colorScheme: colorScheme,
                  strings: strings,
                  isAr: isAr,
                  effectiveSlug: effectiveSlug,
                  events: companyEvents,
                  currentEvent: currentEvent,
                  masterGifts: masterGifts,
                  records: displayRecords,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildContent({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required String effectiveSlug,
    required List<EventModel> events,
    required EventModel? currentEvent,
    required List<CompanyGiftModel> masterGifts,
    required List<DailyBranchSalesModel> records,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final isDesktop = mediaQuery.size.width >= 900;

    // Synthesize comprehensive master gifts list:
    // Retains master gifts from configuration and auto-enriches any disbursed gifts present in records
    // so no gift column is ever missed or shows zero when gifts were disbursed.
    final List<CompanyGiftModel> effectiveMasterGifts = List.from(masterGifts);
    final Set<String> knownGiftKeysAndNames = {};
    for (final g in effectiveMasterGifts) {
      if (g.id.isNotEmpty) knownGiftKeysAndNames.add(g.id);
      if (g.giftName.isNotEmpty) {
        knownGiftKeysAndNames.add(g.giftName);
        knownGiftKeysAndNames.add(_normalizeGiftStatic(g.giftName));
      }
    }

    for (final r in records) {
      for (final gEntry in r.giftsDisbursed.entries) {
        final gItem = gEntry.value;
        final normName = _normalizeGiftStatic(gItem.giftName);
        if (!knownGiftKeysAndNames.contains(gEntry.key) &&
            !knownGiftKeysAndNames.contains(gItem.giftName) &&
            !knownGiftKeysAndNames.contains(normName)) {
          effectiveMasterGifts.add(
            CompanyGiftModel(
              id: gItem.giftKey.isNotEmpty ? gItem.giftKey : gItem.giftName,
              companySlug: effectiveSlug,
              giftName: gItem.giftName,
              totalQuantity: gItem.quantity,
              availableQuantity: 0,
              giftType: gItem.isVoucher ? 'voucher' : 'product',
              unitValue: gItem.unitValue,
            ),
          );
          knownGiftKeysAndNames.add(gEntry.key);
          knownGiftKeysAndNames.add(gItem.giftName);
          knownGiftKeysAndNames.add(normName);
        }
      }
    }

    // Filter by search query (branches already normalized canonically with zero dropping)
    final filteredRecords = records.where((r) {
      if (_searchQuery.trim().isEmpty) return true;
      return r.branchName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    // If _isAllDays is active, consolidate records by branchName into a single summary row per branch
    final List<DailyBranchSalesModel> consolidatedRecords;
    if (_isAllDays) {
      final Map<String, _ConsolidatedBranchAccumulator> branchAccs = {};
      for (final r in filteredRecords) {
        final bKey = r.branchName;
        final acc = branchAccs.putIfAbsent(
          bKey,
          () => _ConsolidatedBranchAccumulator(
            id: 'consolidated_${SlugUtils.generateSlug(bKey)}',
            companySlug: r.companySlug,
            campaignId: 'all',
            campaignName: isAr ? 'إجمالي الحملات' : 'All Campaigns',
            dateStr: isAr ? 'إجمالي الفترة' : 'All Dates',
            date: DateTime.now(),
            branchName: r.branchName,
            branchId: r.branchId,
            retailChain: r.retailChain,
          ),
        );
        acc.invoicesCount += r.invoicesCount;
        acc.totalSalesAmount += r.totalSalesAmount;
        r.giftsDisbursed.forEach((k, g) {
          acc.addGiftDisbursal(
            giftKey: g.giftKey,
            giftName: g.giftName,
            quantity: g.quantity,
            isVoucher: g.isVoucher,
            unitValue: g.unitValue,
            totalValue: g.totalValue,
          );
        });
      }
      consolidatedRecords = branchAccs.values.map((a) => a.toModel()).toList();
    } else {
      consolidatedRecords = filteredRecords;
    }

    // Aggregate totals for KPI cards from filtered records
    int totalInvoices = 0;
    double totalSales = 0.0;
    int totalGifts = 0;
    double totalVouchers = 0.0;

    for (final r in consolidatedRecords) {
      totalInvoices += r.invoicesCount;
      totalSales += r.totalSalesAmount;
      totalGifts += r.totalGiftsCount;
      totalVouchers += r.totalVouchersValue;
    }

    final mainBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Clean Title Header
        _buildHeaderTitle(
          colorScheme: colorScheme,
          strings: strings,
          isDesktop: isDesktop,
        ),

        const SizedBox(height: 12),

        // 1. The 4 KPI Cards (at the top across mobile, tablet, and desktop)
        _buildKpiGrid(
          context: context,
          colorScheme: colorScheme,
          strings: strings,
          isDesktop: isDesktop,
          totalInvoices: totalInvoices,
          totalSales: totalSales,
          totalGifts: totalGifts,
          totalVouchers: totalVouchers,
        ),

        const SizedBox(height: 12),

        // 2. Campaign Selector Dropdown (مهرجان ادكو)
        _buildCampaignSelectorDropdown(
          colorScheme: colorScheme,
          strings: strings,
          events: events,
        ),

        const SizedBox(height: 10),

        // 3. Unified Single-Row Button Group: [ اليوم ] [ الإجمالي ] [ التاريخ ] [ إكسل ]
        _buildUnifiedControlsButtonGroup(
          context: context,
          colorScheme: colorScheme,
          strings: strings,
          isAr: isAr,
          isDesktop: isDesktop,
          records: consolidatedRecords,
          masterGifts: effectiveMasterGifts,
          currentEvent: currentEvent,
        ),

        const SizedBox(height: 14),

        // 4. Search & Filter Bar (Unified M3 format with zero collision)
        _buildSearchBar(
          colorScheme: colorScheme,
          strings: strings,
          isAr: isAr,
          totalBranchesCount: records.length,
          matchingBranchesCount: filteredRecords.length,
        ),

        const SizedBox(height: 14),

        // 5. Daily Matrix Table
        _buildDailyMatrixTable(
          context: context,
          colorScheme: colorScheme,
          strings: strings,
          isAr: isAr,
          isDesktop: isDesktop,
          records: consolidatedRecords,
          masterGifts: effectiveMasterGifts,
          totalDaySales: totalSales,
          currentEvent: currentEvent,
        ),
      ],
    );

    final supportingPane = _buildSupportingPaneWidget(
      context: context,
      colorScheme: colorScheme,
      strings: strings,
      isAr: isAr,
      totalInvoices: totalInvoices,
      totalSales: totalSales,
      totalGifts: totalGifts,
      totalVouchers: totalVouchers,
      records: consolidatedRecords,
      masterGifts: effectiveMasterGifts,
    );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          0,
          isDesktop ? 20 : 12,
          0,
          isDesktop ? 32 : 96,
        ),
        child: M3ContentBoundary(
          maxWidth: 1440.0,
          child: M3SupportingPaneLayout(
            body: mainBody,
            supportingPane: supportingPane,
            supportingPaneWidth: 320.0,
            showDivider: true,
            crossAxisAlignment: CrossAxisAlignment.start,
          ),
        ),
      ),
    );
  }

  /// Supporting Pane Widget displaying real-time KPI metrics, leaderboards, and instant insights
  Widget _buildSupportingPaneWidget({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required int totalInvoices,
    required double totalSales,
    required int totalGifts,
    required double totalVouchers,
    required List<DailyBranchSalesModel> records,
    required List<CompanyGiftModel> masterGifts,
  }) {
    final currencyFormatter = intl.NumberFormat('#,##0.00', 'ar');

    // Identify top performing branch by sales volume
    DailyBranchSalesModel? topBranch;
    for (final r in records) {
      if (topBranch == null || r.totalSalesAmount > topBranch.totalSalesAmount) {
        topBranch = r;
      }
    }

    return Container(
      margin: const EdgeInsetsDirectional.only(start: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Inspector Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.analytics_rounded, size: 20, color: colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr ? 'لوح المؤشرات والرقابة' : 'Executive Insights',
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      isAr ? 'ملخص تحليلي فوري' : 'Live summary pane',
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
          const SizedBox(height: 16),

          // Mini KPI Cards
          _buildSupportingMiniKpi(
            title: isAr ? 'المبيعات الإجمالية' : 'Total Revenue',
            value: '${currencyFormatter.format(totalSales)} ج.م',
            icon: Icons.payments_rounded,
            color: colorScheme.primary,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 8),
          _buildSupportingMiniKpi(
            title: isAr ? 'الفواتير المنفذة' : 'Total Invoices',
            value: '$totalInvoices فاتورة',
            icon: Icons.receipt_long_rounded,
            color: colorScheme.secondary,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 8),
          _buildSupportingMiniKpi(
            title: isAr ? 'الهدايا المنصرفة' : 'Gifts Claimed',
            value: '$totalGifts قطعة',
            icon: Icons.inventory_2_rounded,
            color: colorScheme.tertiary,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 8),
          _buildSupportingMiniKpi(
            title: isAr ? 'قيمة الفواتشرات' : 'Vouchers Value',
            value: '${currencyFormatter.format(totalVouchers)} ج.م',
            icon: Icons.confirmation_number_rounded,
            color: colorScheme.primary.withValues(alpha: 0.85),
            colorScheme: colorScheme,
          ),

          if (topBranch != null && topBranch.totalSalesAmount > 0) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.emoji_events_rounded, color: colorScheme.tertiary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isAr ? 'الفرع الأعلى مبيعاً' : 'Top Branch',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topBranch.branchName,
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${currencyFormatter.format(topBranch.totalSalesAmount)} ج.م • ${topBranch.invoicesCount} فاتورة',
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSupportingMiniKpi({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: 10.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: GoogleFonts.cairo(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderTitle({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isDesktop,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 18 : 14,
        vertical: isDesktop ? 14 : 10,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.point_of_sale_rounded, color: colorScheme.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.dailyBranchSalesNavTitle,
                  style: GoogleFonts.cairo(
                    fontSize: isDesktop ? 18 : 15.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  strings.dailyBranchSalesNavSubtitle,
                  style: GoogleFonts.cairo(
                    fontSize: isDesktop ? 12.5 : 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCampaignSelectorDropdown({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required List<EventModel> events,
  }) {
    final availableEventIds = ['all', ...events.map((e) => e.id)];
    final effectiveDropdownValue = availableEventIds.contains(_selectedEventId) ? _selectedEventId : 'all';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: effectiveDropdownValue,
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down_rounded, color: colorScheme.primary),
          items: [
            DropdownMenuItem<String>(
              value: 'all',
              child: Row(
                children: [
                  Icon(Icons.all_inclusive_rounded, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      strings.companyAllCampaigns,
                      style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            ...events.map((e) {
              return DropdownMenuItem<String>(
                value: e.id,
                child: Row(
                  children: [
                    Icon(Icons.campaign_rounded, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${e.eventName} (${e.retailChainName})',
                        style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
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
              _selectedEventId = val;
            });
          },
        ),
      ),
    );
  }

  Widget _buildUnifiedControlsButtonGroup({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isDesktop,
    required List<DailyBranchSalesModel> records,
    required List<CompanyGiftModel> masterGifts,
    required EventModel? currentEvent,
  }) {
    final now = DateTime.now();
    final isTodaySelected = !_isAllDays && _isSameDay(_selectedDate, now);
    final isAllDaysSelected = _isAllDays;
    final isCustomDateSelected = !_isAllDays && !_isSameDay(_selectedDate, now);

    Widget buildSegmentItem({
      required bool isSelected,
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      String? tooltip,
      bool isLoading = false,
      bool isFirst = false,
      bool isLast = false,
    }) {
      final itemBorderRadius = BorderRadius.horizontal(
        right: (isAr ? isFirst : isLast) ? const Radius.circular(12) : Radius.zero,
        left: (isAr ? isLast : isFirst) ? const Radius.circular(12) : Radius.zero,
      );

      final content = Material(
        color: isSelected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerLow,
        child: InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: itemBorderRadius,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                else
                  Icon(
                    icon,
                    size: 16,
                    color: isSelected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    style: GoogleFonts.cairo(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (tooltip != null) {
        return Tooltip(
          message: tooltip,
          waitDuration: const Duration(milliseconds: 300),
          child: content,
        );
      }
      return content;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 42,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // 1. اليوم
              Expanded(
                child: buildSegmentItem(
                  isSelected: isTodaySelected,
                  icon: Icons.today_rounded,
                  label: isAr ? 'اليوم' : 'Today',
                  tooltip: isAr ? 'عرض مبيعات اليوم الحالي' : 'View today sales',
                  isFirst: true,
                  onTap: () {
                    setState(() {
                      _isAllDays = false;
                      final t = DateTime.now();
                      _selectedDate = DateTime(t.year, t.month, t.day);
                    });
                  },
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),

              // 2. الإجمالي
              Expanded(
                child: buildSegmentItem(
                  isSelected: isAllDaysSelected,
                  icon: Icons.all_inclusive_rounded,
                  label: isAr ? 'الإجمالي' : 'Total',
                  tooltip: isAr ? 'عرض إجمالي كافة أيام الحملة' : 'View all days total',
                  onTap: () {
                    setState(() {
                      _isAllDays = true;
                    });
                  },
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),

              // 3. التاريخ
              Expanded(
                child: buildSegmentItem(
                  isSelected: isCustomDateSelected,
                  icon: Icons.event_rounded,
                  label: isAr ? 'التاريخ' : 'Date',
                  tooltip: isAr ? 'تحديد يوم مخصص من التقويم' : 'Pick a custom date',
                  onTap: () => _pickDate(context),
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),

              // 4. إكسل
              Expanded(
                child: buildSegmentItem(
                  isSelected: false,
                  icon: Icons.table_chart_rounded,
                  label: isAr ? 'إكسل' : 'Excel',
                  tooltip: isAr ? 'تصدير البيانات إلى تقرير Excel' : 'Export to Excel report',
                  isLoading: _isExporting,
                  isLast: true,
                  onTap: () {
                    if (!_isExporting) {
                      _exportExcelReport(
                        salesRecords: records,
                        masterGifts: masterGifts,
                        campaignName: currentEvent?.eventName ?? (isAr ? 'كافة الحملات' : 'All Campaigns'),
                        isAr: isAr,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),

        // Indicator when a custom date is selected
        if (isCustomDateSelected) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_available_rounded, size: 15, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      '${isAr ? 'اليوم المحدد' : 'Selected Date'}: ${_formatDisplayDate(_selectedDate, isAr)}',
                      style: GoogleFonts.cairo(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () => setState(() => _isAllDays = true),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isAr ? 'إلغاء والتراجع للإجمالي' : 'Reset to All',
                          style: GoogleFonts.cairo(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.close_rounded, size: 14, color: colorScheme.primary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildKpiGrid({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isDesktop,
    required int totalInvoices,
    required double totalSales,
    required int totalGifts,
    required double totalVouchers,
  }) {
    final currencyFormatter = intl.NumberFormat('#,##0.00', 'ar');
    final isAr = ref.isArabic;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final bool isMobile = width < 600;

        int crossAxisCount = 4;
        double childAspectRatio = 1.65;
        if (width < 600) {
          // Mobile: strictly 2x2 grid (اتنين مع بعض واتنين مع بعض)
          crossAxisCount = 2;
          childAspectRatio = 1.32;
        } else if (width < 840) {
          // Tablet: strictly 2x2 grid
          crossAxisCount = 2;
          childAspectRatio = 1.75;
        } else {
          // Desktop: 4 columns in one row
          crossAxisCount = 4;
          childAspectRatio = width >= 1200 ? 1.75 : 1.45;
        }

        final cards = [
          _buildExecutiveKpiCard(
            title: _isAllDays
                ? (isAr ? 'إجمالي المبيعات المحققة' : 'Total Sales Revenue')
                : (isAr ? 'مبيعات اليوم المحدد' : 'Selected Day Sales'),
            value: '${currencyFormatter.format(totalSales)} ج.م',
            subtitle: isAr ? 'مبيعات منتجات العرض المعتمدة' : 'Verified promotional sales revenue',
            icon: Icons.payments_rounded,
            accentColor: colorScheme.primary,
            badgeText: 'مصر 🇪🇬',
            colorScheme: colorScheme,
            tooltip: isAr ? 'إجمالي المبيعات المحققة لمنتجات الحملة بالعُملة المحلية' : 'Total sales revenue',
            isMobile: isMobile,
          ),
          _buildExecutiveKpiCard(
            title: isAr ? 'عدد الفواتير المنفذة' : 'Total Executed Invoices',
            value: '$totalInvoices فاتورة',
            subtitle: isAr ? 'الفواتير المدققة والمقبولة' : 'Audited and verified receipts',
            icon: Icons.receipt_long_rounded,
            accentColor: colorScheme.secondary,
            badgeText: isAr ? 'فاتورة منفذة' : 'Invoices',
            colorScheme: colorScheme,
            tooltip: isAr ? 'إجمالي عدد الفواتير المنفذة في الفروع' : 'Total executed receipts',
            isMobile: isMobile,
          ),
          _buildExecutiveKpiCard(
            title: isAr ? 'إجمالي الهدايا المنصرفة' : 'Total Gifts Disbursed',
            value: '$totalGifts قطعة',
            subtitle: isAr ? 'الهدايا الفورية المستلمة بالفرع' : 'Instant gifts claimed at branches',
            icon: Icons.inventory_2_rounded,
            accentColor: colorScheme.tertiary,
            badgeText: isAr ? 'هدايا فورية' : 'Gifts',
            colorScheme: colorScheme,
            tooltip: isAr ? 'إجمالي قطع الهدايا المنصرفة في الفروع' : 'Total instant gifts claimed',
            isMobile: isMobile,
          ),
          _buildExecutiveKpiCard(
            title: isAr ? 'إجمالي قيمة الفواتشرات' : 'Total Vouchers Value',
            value: '${currencyFormatter.format(totalVouchers)} ج.م',
            subtitle: isAr ? 'قسائم الشراء المصدرة للعملاء' : 'Purchase vouchers issued to customers',
            icon: Icons.confirmation_number_rounded,
            accentColor: colorScheme.primary.withValues(alpha: 0.85),
            badgeText: isAr ? 'قسائم شراء' : 'Vouchers',
            colorScheme: colorScheme,
            tooltip: isAr ? 'إجمالي القيمة المالية لقسائم وفواتشرات الشراء' : 'Total vouchers monetary value',
            isMobile: isMobile,
          ),
        ];

        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: isMobile ? 10 : 14,
          mainAxisSpacing: isMobile ? 10 : 14,
          childAspectRatio: childAspectRatio,
          children: cards,
        );
      },
    );
  }

  Widget _buildExecutiveKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required String badgeText,
    required ColorScheme colorScheme,
    required String tooltip,
    bool isMobile = false,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 10 : 14,
          vertical: isMobile ? 9 : 12,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.02),
              blurRadius: 8,
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
                  padding: EdgeInsets.all(isMobile ? 5 : 7),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: isMobile ? 16 : 18, color: accentColor),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 6 : 8,
                    vertical: isMobile ? 2 : 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badgeText,
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 9.5 : 10,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 15.5 : 18,
                  fontWeight: FontWeight.w900,
                  color: colorScheme.onSurface,
                  letterSpacing: -0.3,
                ),
                maxLines: 1,
              ),
            ),
            Text(
              title,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 11 : 12,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtitle,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 9.5 : 10.5,
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

  Widget _buildSearchBar({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required int totalBranchesCount,
    required int matchingBranchesCount,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.cairo(fontSize: 13.5, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.search_rounded, color: colorScheme.primary, size: 20),
          prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          hintText: isAr ? 'البحث عن فرع محدد...' : 'Search specific branch...',
          hintStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant, fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  tooltip: isAr ? 'مسح البحث' : 'Clear search',
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                    });
                  },
                ),
              Container(
                margin: const EdgeInsetsDirectional.only(end: 10),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _searchQuery.isNotEmpty
                      ? '$matchingBranchesCount / $totalBranchesCount ${isAr ? 'فرع' : 'branches'}'
                      : '$totalBranchesCount ${isAr ? 'فرع' : 'branches'}',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDailyMatrixTable({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isDesktop,
    required List<DailyBranchSalesModel> records,
    required List<CompanyGiftModel> masterGifts,
    required double totalDaySales,
    EventModel? currentEvent,
  }) {
    if (records.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_busy_rounded, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                isAr ? 'لا توجد مبيعات أو هدايا مسجلة في هذا التحديد' : 'No sales or gift claims recorded for this selection',
                style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Text(
                isAr
                    ? 'يمكنك النقر على «مزامنة وترميم السجلات» أعلى الصفحة لجلب وتجميع كافة الفواتير تلقائياً'
                    : 'Click "Sync & Backfill Daily Logs" above to auto-aggregate all campaign receipts',
                style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        // Base column widths - compact and responsive
        const branchColWidth = 175.0;
        const invoicesColWidth = 82.0;
        const salesColWidth = 105.0;
        final giftColWidth = masterGifts.isEmpty ? 100.0 : 100.0;
        const totalGiftsColWidth = 85.0;
        const totalVouchersColWidth = 105.0;
        const shareColWidth = 80.0;

        final baseTotalWidth = branchColWidth +
            invoicesColWidth +
            salesColWidth +
            (masterGifts.length * giftColWidth) +
            totalGiftsColWidth +
            totalVouchersColWidth +
            shareColWidth;

        final scale = availableWidth > baseTotalWidth ? (availableWidth / baseTotalWidth) : 1.0;

        final columnWidths = <int, TableColumnWidth>{
          0: FixedColumnWidth(branchColWidth * scale),
          1: FixedColumnWidth(invoicesColWidth * scale),
          2: FixedColumnWidth(salesColWidth * scale),
        };

        for (int i = 0; i < masterGifts.length; i++) {
          columnWidths[3 + i] = FixedColumnWidth(giftColWidth * scale);
        }

        final totalsStartIndex = 3 + masterGifts.length;
        columnWidths[totalsStartIndex] = FixedColumnWidth(totalGiftsColWidth * scale);
        columnWidths[totalsStartIndex + 1] = FixedColumnWidth(totalVouchersColWidth * scale);
        columnWidths[totalsStartIndex + 2] = FixedColumnWidth(shareColWidth * scale);

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.03),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: availableWidth,
                ),
                child: Table(
                  columnWidths: columnWidths,
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    // Header Row
                    TableRow(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                        border: Border(
                          bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8), width: 1.5),
                        ),
                      ),
                      children: [
                        _buildHeaderCell(
                          title: isAr ? 'الفرع / المتجر' : 'Branch / Store',
                          icon: Icons.store_rounded,
                          colorScheme: colorScheme,
                          isStart: true,
                        ),
                        _buildHeaderCell(
                          title: isAr ? 'الفواتير' : 'Invoices',
                          icon: Icons.receipt_long_rounded,
                          colorScheme: colorScheme,
                        ),
                        _buildHeaderCell(
                          title: isAr ? 'المبيعات' : 'Sales',
                          icon: Icons.monetization_on_rounded,
                          colorScheme: colorScheme,
                        ),
                        ...masterGifts.map((g) {
                          final voucherSubtitle = g.isVoucher
                              ? (g.giftName.isNotEmpty
                                  ? g.giftName
                                  : (g.unitValue > 0 ? '${g.unitValue.toInt()} جنيه قسيمة مشتريات' : 'قسيمة مشتريات'))
                              : (isAr ? '(هدية)' : '(Gift)');
                          return _buildHeaderCell(
                            title: g.isVoucher ? (isAr ? 'الفاتشر' : 'Voucher') : g.giftName,
                            subtitle: voucherSubtitle,
                            icon: g.isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                            colorScheme: colorScheme,
                          );
                        }),
                        _buildHeaderCell(
                          title: isAr ? 'الهدايا' : 'Gifts',
                          icon: Icons.redeem_rounded,
                          colorScheme: colorScheme,
                        ),
                        _buildHeaderCell(
                          title: isAr ? 'قيمة الفاتشر' : 'Voucher Value',
                          icon: Icons.confirmation_number_rounded,
                          colorScheme: colorScheme,
                        ),
                        _buildHeaderCell(
                          title: isAr ? 'النسبة' : 'Share',
                          icon: Icons.pie_chart_rounded,
                          colorScheme: colorScheme,
                        ),
                      ],
                    ),

                    // Data Rows
                    for (int rIdx = 0; rIdx < records.length; rIdx++)
                      _buildDailyDataRow(
                        rowIndex: rIdx,
                        record: records[rIdx],
                        masterGifts: masterGifts,
                        totalDaySales: totalDaySales,
                        isAr: isAr,
                        colorScheme: colorScheme,
                        currentEvent: currentEvent,
                      ),

                    // Totals Summary Row
                    if (records.isNotEmpty)
                      _buildDailyTotalsRow(
                        records: records,
                        masterGifts: masterGifts,
                        totalDaySales: totalDaySales,
                        isAr: isAr,
                        colorScheme: colorScheme,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderCell({
    required String title,
    String? subtitle,
    required IconData icon,
    required ColorScheme colorScheme,
    bool isStart = false,
  }) {
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: isStart ? 12 : 6,
        end: 6,
        top: 12,
        bottom: 12,
      ),
      child: Align(
        alignment: isStart ? AlignmentDirectional.centerStart : Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: isStart ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: colorScheme.primary),
            const SizedBox(width: 5),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: isStart ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: isStart ? TextAlign.start : TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: GoogleFonts.cairo(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: isStart ? TextAlign.start : TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  TableRow _buildDailyDataRow({
    required int rowIndex,
    required DailyBranchSalesModel record,
    required List<CompanyGiftModel> masterGifts,
    required double totalDaySales,
    required bool isAr,
    required ColorScheme colorScheme,
    EventModel? currentEvent,
  }) {
    final isEven = rowIndex % 2 == 0;
    final rowBg = isEven ? colorScheme.surface : colorScheme.surfaceContainerLow.withValues(alpha: 0.5);
    final currencyFormatter = intl.NumberFormat('#,##0.00', 'ar');

    final shareRate = totalDaySales > 0 ? (record.totalSalesAmount / totalDaySales).clamp(0.0, 1.0) : 0.0;
    final sharePercent = (shareRate * 100).toStringAsFixed(1);

    // Extract clean branch name without parenthetical governorate, and build area/chain subtitle
    final rawBranch = record.branchName.trim();
    String cleanBranch = rawBranch;
    String area = '';

    final parenMatch = RegExp(r'\(([^)]+)\)').firstMatch(rawBranch);
    if (parenMatch != null) {
      area = parenMatch.group(1)?.trim() ?? '';
      final candidate = rawBranch.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
      if (candidate.isNotEmpty) {
        cleanBranch = candidate;
      }
    }

    String chain = '';
    final rawChain = record.retailChain.trim();
    if (rawChain.isNotEmpty && rawChain != '-' && rawChain != 'غير محدد') {
      final normalized = ChainProductsIntelligenceService.normalizeRetailChain(rawChain);
      if (normalized != 'سلسلة تجارية عامة') {
        chain = normalized;
      }
    } else if (currentEvent != null && currentEvent.retailChainName.trim().isNotEmpty) {
      final normalized = ChainProductsIntelligenceService.normalizeRetailChain(currentEvent.retailChainName);
      if (normalized != 'سلسلة تجارية عامة') {
        chain = normalized;
      }
    }

    final subtitleParts = <String>[];
    if (area.isNotEmpty) subtitleParts.add(area);
    if (chain.isNotEmpty && chain != area && !cleanBranch.contains(chain)) {
      subtitleParts.add(chain);
    }
    final subtitle = subtitleParts.join(' • ');

    final cells = <Widget>[
      // 1. Branch Name + Area & Chain Subtitle
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cleanBranch,
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.cairo(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant,
                        height: 1.15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),

      // 2. Invoices Count
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${record.invoicesCount}',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ),
      ),

      // 3. Total Sales Amount
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Center(
          child: Text(
            '${currencyFormatter.format(record.totalSalesAmount)} ج.م',
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: colorScheme.primary,
            ),
          ),
        ),
      ),
    ];

    // 4. Dynamic Gifts Disbursed Cells
    for (final gift in masterGifts) {
      final qty = _resolveDisbursedGiftQty(record, gift, masterGifts);

      cells.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: qty > 0
                    ? (gift.isVoucher
                        ? colorScheme.tertiaryContainer.withValues(alpha: 0.5)
                        : colorScheme.secondaryContainer.withValues(alpha: 0.5))
                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$qty',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: qty > 0
                      ? (gift.isVoucher ? colorScheme.onTertiaryContainer : colorScheme.onSecondaryContainer)
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 5. Total Gifts Disbursed
    cells.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${record.totalGiftsCount}',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSecondaryContainer,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );

    // 6. Total Vouchers Value
    cells.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Center(
          child: Text(
            '${currencyFormatter.format(record.totalVouchersValue)} ج.م',
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.bold,
              color: colorScheme.tertiary,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );

    // 7. Branch Share %
    cells.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '$sharePercent%',
              style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: shareRate,
                minHeight: 4,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
            ),
          ],
        ),
      ),
    );

    return TableRow(
      decoration: BoxDecoration(
        color: rowBg,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
      ),
      children: cells,
    );
  }

  /// Totals Summary Row for Matrix Table
  TableRow _buildDailyTotalsRow({
    required List<DailyBranchSalesModel> records,
    required List<CompanyGiftModel> masterGifts,
    required double totalDaySales,
    required bool isAr,
    required ColorScheme colorScheme,
  }) {
    final currencyFormatter = intl.NumberFormat('#,##0.00', 'ar');
    final totalInvoices = records.fold<int>(0, (acc, r) => acc + r.invoicesCount);
    final totalGifts = records.fold<int>(0, (acc, r) => acc + r.totalGiftsCount);
    final totalVouchers = records.fold<double>(0.0, (acc, r) => acc + r.totalVouchersValue);

    final List<Widget> cells = [
      // 1. Branch Column: "الإجمالي"
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.summarize_rounded, size: 16, color: colorScheme.primary),
            ),
            const SizedBox(width: 8),
            Text(
              isAr ? 'الإجمالي العام' : 'Grand Total',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
      ),

      // 2. Invoices Count
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Center(
          child: Text(
            '$totalInvoices',
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.bold,
              fontSize: 13.5,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ),

      // 3. Total Sales Amount
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Center(
          child: Text(
            '${currencyFormatter.format(totalDaySales)} ج.م',
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.bold,
              fontSize: 13.5,
              color: colorScheme.primary,
            ),
          ),
        ),
      ),
    ];

    // 4. Totals for each Master Gift
    for (final gift in masterGifts) {
      final giftColTotal = records.fold<int>(
        0,
        (acc, r) => acc + _resolveDisbursedGiftQty(r, gift, masterGifts),
      );

      cells.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: giftColTotal > 0
                    ? (gift.isVoucher
                        ? colorScheme.tertiaryContainer.withValues(alpha: 0.6)
                        : colorScheme.secondaryContainer.withValues(alpha: 0.6))
                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$giftColTotal',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                  color: giftColTotal > 0
                      ? (gift.isVoucher ? colorScheme.onTertiaryContainer : colorScheme.onSecondaryContainer)
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 5. Total Gifts
    cells.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$totalGifts',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.w900,
                fontSize: 13.5,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ),
      ),
    );

    // 6. Total Vouchers Value
    cells.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Center(
          child: Text(
            '${currencyFormatter.format(totalVouchers)} ج.م',
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.w900,
              color: colorScheme.tertiary,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );

    // 7. Share (100%)
    cells.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Center(
          child: Text(
            '100%',
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
        ),
      ),
    );

    return TableRow(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8), width: 1.5),
        ),
      ),
      children: cells,
    );
  }
}

/// Helper accumulator for consolidating multiple date records by branch
class _ConsolidatedBranchAccumulator {
  final String id;
  final String companySlug;
  final String campaignId;
  final String campaignName;
  final String dateStr;
  final DateTime date;
  final String branchName;
  final String branchId;
  final String retailChain;

  int invoicesCount = 0;
  double totalSalesAmount = 0.0;
  int totalGiftsCount = 0;
  double totalVouchersValue = 0.0;
  final Map<String, DailyGiftDisbursalItem> giftsDisbursed = {};

  _ConsolidatedBranchAccumulator({
    required this.id,
    required this.companySlug,
    required this.campaignId,
    required this.campaignName,
    required this.dateStr,
    required this.date,
    required this.branchName,
    required this.branchId,
    required this.retailChain,
  });

  void addGiftDisbursal({
    required String giftKey,
    required String giftName,
    required int quantity,
    required bool isVoucher,
    required double unitValue,
    required double totalValue,
  }) {
    totalGiftsCount += quantity;
    if (isVoucher) {
      totalVouchersValue += totalValue;
    }

    final normNew = _DailyBranchSalesScreenState._normalizeGiftStatic(giftName);
    String targetKey = giftKey;
    DailyGiftDisbursalItem? existing = giftsDisbursed[giftKey];
    if (existing == null && normNew.isNotEmpty) {
      for (final e in giftsDisbursed.entries) {
        if (_DailyBranchSalesScreenState._normalizeGiftStatic(e.value.giftName) == normNew ||
            _DailyBranchSalesScreenState._normalizeGiftStatic(e.key) == normNew) {
          existing = e.value;
          targetKey = e.key;
          break;
        }
      }
    }

    if (existing != null) {
      giftsDisbursed[targetKey] = existing.copyWith(
        quantity: existing.quantity + quantity,
        totalValue: existing.totalValue + totalValue,
      );
    } else {
      giftsDisbursed[giftKey] = DailyGiftDisbursalItem(
        giftKey: giftKey,
        giftName: giftName,
        quantity: quantity,
        isVoucher: isVoucher,
        unitValue: unitValue,
        totalValue: totalValue,
      );
    }
  }

  DailyBranchSalesModel toModel() {
    return DailyBranchSalesModel(
      id: id,
      companySlug: companySlug,
      campaignId: campaignId,
      campaignName: campaignName,
      dateStr: dateStr,
      date: date,
      branchName: branchName,
      branchId: branchId,
      retailChain: retailChain,
      invoicesCount: invoicesCount,
      totalSalesAmount: totalSalesAmount,
      totalGiftsCount: totalGiftsCount,
      totalVouchersValue: totalVouchersValue,
      giftsDisbursed: Map.from(giftsDisbursed),
      topProducts: const [],
      lastUpdatedAt: DateTime.now(),
    );
  }
}
