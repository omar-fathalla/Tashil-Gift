import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:excel/excel.dart' as xl;

import '../../../core/services/firebase_service.dart';
import '../../../core/services/daily_sales_aggregation_service.dart';
import '../../../core/services/company_gifts_service.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/file_download_helper.dart';
import '../../../core/utils/slug_utils.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/widgets/m3_button_groups.dart';
import '../../admin/domain/event_model.dart';
import '../../admin/domain/company_gift_model.dart';
import '../domain/daily_branch_sales_model.dart';

/// Screen for tracking Daily Sales Revenue and Gift/Voucher Disbursals per Branch & Campaign Date.
class DailyBranchSalesScreen extends ConsumerStatefulWidget {
  final String? lockedCompanySlug;
  final String? initialEventId;

  const DailyBranchSalesScreen({
    super.key,
    this.lockedCompanySlug,
    this.initialEventId,
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
  bool _isBackfilling = false;
  bool _isExporting = false;
  List<DailyBranchSalesModel>? _lastLoadedRecords;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _selectedEventId = (widget.initialEventId != null && widget.initialEventId!.isNotEmpty)
        ? widget.initialEventId
        : 'all';
  }

  String _formatDateStr(DateTime dt) {
    return "${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
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

  Future<void> _triggerBackfill(String effectiveSlug) async {
    final isAr = ref.isArabic;
    final colorScheme = Theme.of(context).colorScheme;

    setState(() {
      _isBackfilling = true;
    });

    try {
      final service = ref.read(dailySalesAggregationServiceProvider);
      final count = await service.backfillDailySalesFromTransactions(
        companySlug: effectiveSlug,
        campaignId: _selectedEventId == 'all' ? null : _selectedEventId,
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
                        ? 'تمت مزامنة وترميم سجلات المبيعات اليومية بنجاح ($count سجلاً)'
                        : 'Daily sales records synchronized and backfilled successfully ($count records)',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF006C50),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${isAr ? 'خطأ أثناء المزامنة:' : 'Sync error:'} ${AppErrorHandler.getFriendlyMessage(e)}',
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
          _isBackfilling = false;
        });
      }
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
          backgroundColorHex: xl.ExcelColor.fromHexString('#006C50'),
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
          final giftKey = gift.id.isNotEmpty ? gift.id : gift.giftName;
          final disbursedItem = rec.giftsDisbursed[giftKey];
          final qty = disbursedItem?.quantity ?? 0;
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.IntCellValue(qty);
        }

        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.IntCellValue(rec.totalGiftsCount);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex)).value = xl.DoubleCellValue(rec.totalVouchersValue);
        rowIndex++;
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

    return StreamBuilder<QuerySnapshot>(
      stream: effectiveSlug.isNotEmpty
          ? activeDb.collection('events').where('companySlug', isEqualTo: effectiveSlug).snapshots()
          : activeDb.collection('events').snapshots(),
      builder: (context, eventsSnap) {
        if (eventsSnap.connectionState == ConnectionState.waiting && !eventsSnap.hasData && _lastLoadedRecords == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final eventDocs = eventsSnap.data?.docs ?? [];
        final companyEvents = eventDocs
            .map((d) {
              try {
                return EventModel.fromFirestore(d);
              } catch (_) {
                return null;
              }
            })
            .whereType<EventModel>()
            .toList();

        // Selected Campaign Scoping
        final isAllCampaigns = _selectedEventId == null || _selectedEventId == 'all' || _selectedEventId == 'ALL';
        EventModel? currentEvent;
        if (!isAllCampaigns) {
          currentEvent = companyEvents.where((e) => e.id == _selectedEventId).firstOrNull;
        }

        final targetEventId = isAllCampaigns ? null : currentEvent?.id;
        final targetDateStr = _isAllDays ? null : _formatDateStr(_selectedDate);

        return StreamBuilder<List<CompanyGiftModel>>(
          stream: ref.watch(companyGiftsServiceProvider).giftsStream(effectiveSlug),
          builder: (context, giftsSnap) {
            final masterGifts = giftsSnap.data ?? [];

            Query transactionsQuery = activeDb.collection('receipts_transactions');
            if (effectiveSlug.isNotEmpty) {
              transactionsQuery = transactionsQuery.where('companySlug', isEqualTo: effectiveSlug);
            }

            return StreamBuilder<QuerySnapshot>(
              stream: transactionsQuery.snapshots(),
              builder: (context, txSnap) {
                if (txSnap.connectionState == ConnectionState.waiting && !txSnap.hasData && _lastLoadedRecords == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                final txDocs = txSnap.data?.docs ?? [];
                final rawTransactions = txDocs.map((d) => d.data() as Map<String, dynamic>).toList();

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

                final displayRecords = DailySalesAggregationService.aggregateTransactionsData(
                  rawTransactions: rawTransactions,
                  companySlug: effectiveSlug,
                  campaignId: targetEventId,
                  targetDateStr: targetDateStr,
                  companyBranches: companyBranches,
                  companyEventIds: companyEventIds,
                  companyEventNames: companyEventNames,
                  companyTargetNames: companyTargetNames,
                );

                if (displayRecords.isNotEmpty || rawTransactions.isNotEmpty) {
                  _lastLoadedRecords = displayRecords;
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

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          isDesktop ? 24 : 12,
          isDesktop ? 20 : 12,
          isDesktop ? 24 : 12,
          isDesktop ? 32 : 96,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Executive Header Card
            _buildHeaderCard(
              context: context,
              colorScheme: colorScheme,
              strings: strings,
              isAr: isAr,
              isDesktop: isDesktop,
              effectiveSlug: effectiveSlug,
              events: events,
              currentEvent: currentEvent,
              records: consolidatedRecords,
              masterGifts: masterGifts,
            ),

            const SizedBox(height: 14),

            // 2. Timeline & Date Navigator
            _buildTimelineNavigator(
              context: context,
              colorScheme: colorScheme,
              strings: strings,
              isAr: isAr,
              isDesktop: isDesktop,
            ),

            const SizedBox(height: 14),

            // 3. Hero KPI Summary Grid
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

            const SizedBox(height: 16),

            // 4. Search & Filter Bar
            _buildSearchBar(
              colorScheme: colorScheme,
              strings: strings,
              isAr: isAr,
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
              masterGifts: masterGifts,
              totalDaySales: totalSales,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isDesktop,
    required String effectiveSlug,
    required List<EventModel> events,
    required EventModel? currentEvent,
    required List<DailyBranchSalesModel> records,
    required List<CompanyGiftModel> masterGifts,
  }) {
    return Container(
      padding: EdgeInsets.all(isDesktop ? 20 : 16),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [const Color(0xFF2563EB), colorScheme.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.point_of_sale_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.dailyBranchSalesNavTitle,
                      style: GoogleFonts.cairo(
                        fontSize: isDesktop ? 20 : 17,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      strings.dailyBranchSalesNavSubtitle,
                      style: GoogleFonts.cairo(
                        fontSize: isDesktop ? 13 : 11.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isDesktop) ...[
                // Excel Export Button
                OutlinedButton.icon(
                  onPressed: _isExporting
                      ? null
                      : () => _exportExcelReport(
                            salesRecords: records,
                            masterGifts: masterGifts,
                            campaignName: currentEvent?.eventName ?? 'Daily Sales',
                            isAr: isAr,
                          ),
                  icon: _isExporting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.table_view_rounded, size: 18),
                  label: Text(strings.exportExcelBtn, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF006C50),
                    side: const BorderSide(color: Color(0xFF006C50), width: 1.2),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(width: 10),
                // Sync & Backfill Button
                FilledButton.icon(
                  onPressed: _isBackfilling ? null : () => _triggerBackfill(effectiveSlug),
                  icon: _isBackfilling
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync_rounded, size: 18),
                  label: Text(strings.syncAndBackfillDailySalesBtn, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ],
          ),

          if (!isDesktop) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isBackfilling ? null : () => _triggerBackfill(effectiveSlug),
                    icon: _isBackfilling
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.sync_rounded, size: 16),
                    label: Text(
                      isAr ? 'مزامنة السجلات' : 'Sync & Backfill',
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isExporting
                        ? null
                        : () => _exportExcelReport(
                              salesRecords: records,
                              masterGifts: masterGifts,
                              campaignName: currentEvent?.eventName ?? 'Daily Sales',
                              isAr: isAr,
                            ),
                    icon: _isExporting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.table_view_rounded, size: 16),
                    label: Text(
                      strings.exportExcelBtn,
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF006C50),
                      side: const BorderSide(color: Color(0xFF006C50), width: 1.2),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Campaign Selector Dropdown with "All Campaigns" option
          const SizedBox(height: 14),
          Builder(
            builder: (context) {
              final availableEventIds = ['all', ...events.map((e) => e.id)];
              final effectiveDropdownValue = availableEventIds.contains(_selectedEventId) ? _selectedEventId : 'all';

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: effectiveDropdownValue,
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down_rounded),
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
                                style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
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
                                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600),
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
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDatePickerPill(
    BuildContext context,
    ColorScheme colorScheme,
    AppStrings strings,
    bool isAr,
    bool isDesktop,
  ) {
    return InkWell(
      onTap: () => _pickDate(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _isAllDays ? colorScheme.surface : colorScheme.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isAllDays ? colorScheme.outlineVariant : colorScheme.primary.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_month_rounded,
              size: 18,
              color: _isAllDays ? colorScheme.onSurfaceVariant : colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _isAllDays ? strings.allCampaignDaysBtn : _formatDisplayDate(_selectedDate, isAr),
                style: GoogleFonts.cairo(
                  fontSize: isDesktop ? 14 : 12,
                  fontWeight: FontWeight.bold,
                  color: _isAllDays ? colorScheme.onSurface : colorScheme.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineNavigator({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isDesktop,
  }) {
    if (isDesktop) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            // Previous Day Button
            IconButton(
              onPressed: () {
                setState(() {
                  _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                  _isAllDays = false;
                });
              },
              icon: Icon(isAr ? Icons.chevron_right_rounded : Icons.chevron_left_rounded),
              tooltip: strings.prevDayBtn,
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),

            const SizedBox(width: 8),

            // Date Picker Pill
            Expanded(
              child: _buildDatePickerPill(context, colorScheme, strings, isAr, isDesktop),
            ),

            const SizedBox(width: 8),

            // Next Day Button
            IconButton(
              onPressed: () {
                setState(() {
                  _selectedDate = _selectedDate.add(const Duration(days: 1));
                  _isAllDays = false;
                });
              },
              icon: Icon(isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded),
              tooltip: strings.nextDayBtn,
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),

            const SizedBox(width: 14),

            // M3 Connected Button Group for Timeline Mode Switcher
            M3ConnectedButtonGroup<bool>(
              height: 40,
              borderRadius: 12,
              selectedValue: _isAllDays,
              onSelected: (val) {
                setState(() {
                  _isAllDays = val;
                  if (!_isAllDays) {
                    final now = DateTime.now();
                    _selectedDate = DateTime(now.year, now.month, now.day);
                  }
                });
              },
              segments: [
                M3ButtonSegment<bool>(
                  value: false,
                  label: strings.todayBtn,
                  icon: Icons.today_rounded,
                ),
                M3ButtonSegment<bool>(
                  value: true,
                  label: strings.allCampaignDaysBtn,
                  icon: Icons.calendar_month_rounded,
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Mobile View: 2 structured rows with M3 Connected Button Group
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Date Navigation Controls
          Row(
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                    _isAllDays = false;
                  });
                },
                icon: Icon(isAr ? Icons.chevron_right_rounded : Icons.chevron_left_rounded),
                tooltip: strings.prevDayBtn,
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildDatePickerPill(context, colorScheme, strings, isAr, isDesktop),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedDate = _selectedDate.add(const Duration(days: 1));
                    _isAllDays = false;
                  });
                },
                icon: Icon(isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded),
                tooltip: strings.nextDayBtn,
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: Full-Width M3 Connected Button Group
          SizedBox(
            width: double.infinity,
            child: M3ConnectedButtonGroup<bool>(
              height: 40,
              borderRadius: 12,
              selectedValue: _isAllDays,
              onSelected: (val) {
                setState(() {
                  _isAllDays = val;
                  if (!_isAllDays) {
                    final now = DateTime.now();
                    _selectedDate = DateTime(now.year, now.month, now.day);
                  }
                });
              },
              segments: [
                M3ButtonSegment<bool>(
                  value: false,
                  label: strings.todayBtn,
                  icon: Icons.today_rounded,
                ),
                M3ButtonSegment<bool>(
                  value: true,
                  label: strings.allCampaignDaysBtn,
                  icon: Icons.calendar_month_rounded,
                ),
              ],
            ),
          ),
        ],
      ),
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
            title: _isAllDays
                ? (isAr ? 'إجمالي المبيعات المحققة' : 'Total Sales Revenue')
                : (isAr ? 'مبيعات اليوم المحدد' : 'Selected Day Sales'),
            value: '${currencyFormatter.format(totalSales)} ج.م',
            subtitle: isAr ? 'مبيعات منتجات العرض المعتمدة' : 'Verified promotional sales revenue',
            icon: Icons.payments_rounded,
            accentColor: const Color(0xFF006C50),
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
            accentColor: const Color(0xFF0284C7),
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
            accentColor: const Color(0xFFD97706),
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
            accentColor: const Color(0xFF7C3AED),
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
          crossAxisSpacing: isMobile ? 12 : 14,
          mainAxisSpacing: isMobile ? 12 : 14,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.02),
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
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: accentColor),
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
                      color: accentColor,
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
              child: Text(
                value,
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: colorScheme.onSurface,
                  letterSpacing: -0.3,
                ),
                maxLines: 1,
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

  Widget _buildSearchBar({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
  }) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: TextField(
        onChanged: (val) {
          setState(() {
            _searchQuery = val;
          });
        },
        style: GoogleFonts.cairo(fontSize: 13.5),
        decoration: InputDecoration(
          icon: Icon(Icons.search_rounded, color: colorScheme.primary, size: 20),
          hintText: isAr ? 'البحث عن فرع محدد...' : 'Search specific branch...',
          hintStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant, fontSize: 13),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  onPressed: () {
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
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

        // Base column widths
        const branchColWidth = 190.0;
        const invoicesColWidth = 100.0;
        const salesColWidth = 130.0;
        final giftColWidth = masterGifts.isEmpty ? 110.0 : 110.0;
        const totalGiftsColWidth = 110.0;
        const totalVouchersColWidth = 120.0;
        const shareColWidth = 130.0;

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
                          title: strings.receiptStoreCol,
                          icon: Icons.store_rounded,
                          colorScheme: colorScheme,
                        ),
                        _buildHeaderCell(
                          title: strings.dailyInvoicesCountKpi,
                          icon: Icons.receipt_long_rounded,
                          colorScheme: colorScheme,
                        ),
                        _buildHeaderCell(
                          title: isAr ? 'المبيعات (ج.م)' : 'Sales (EGP)',
                          icon: Icons.monetization_on_rounded,
                          colorScheme: colorScheme,
                        ),
                        ...masterGifts.map((g) => _buildHeaderCell(
                              title: g.giftName,
                              subtitle: g.isVoucher ? '(قسيمة)' : '(هدية)',
                              icon: g.isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                              colorScheme: colorScheme,
                            )),
                        _buildHeaderCell(
                          title: strings.dailyGiftsDisbursedKpi,
                          icon: Icons.redeem_rounded,
                          colorScheme: colorScheme,
                        ),
                        _buildHeaderCell(
                          title: strings.dailyVouchersValueKpi,
                          icon: Icons.confirmation_number_rounded,
                          colorScheme: colorScheme,
                        ),
                        _buildHeaderCell(
                          title: strings.branchSalesShareCol,
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
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: colorScheme.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
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
                      textAlign: TextAlign.center,
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
  }) {
    final isEven = rowIndex % 2 == 0;
    final rowBg = isEven ? colorScheme.surface : colorScheme.surfaceContainerLow.withValues(alpha: 0.5);
    final currencyFormatter = intl.NumberFormat('#,##0.00', 'ar');

    final shareRate = totalDaySales > 0 ? (record.totalSalesAmount / totalDaySales).clamp(0.0, 1.0) : 0.0;
    final sharePercent = (shareRate * 100).toStringAsFixed(1);

    final cells = <Widget>[
      // 1. Branch Name
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                record.branchName,
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.onSurface),
                overflow: TextOverflow.ellipsis,
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
              color: const Color(0xFF0284C7).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${record.invoicesCount}',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF0369A1)),
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
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF006C50)),
          ),
        ),
      ),
    ];

    // 4. Dynamic Gifts Disbursed Cells
    for (final gift in masterGifts) {
      final giftKey = gift.id.isNotEmpty ? gift.id : gift.giftName;
      final disbursedItem = record.giftsDisbursed[giftKey];
      final qty = disbursedItem?.quantity ?? 0;

      cells.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: qty > 0
                    ? (gift.isVoucher
                        ? const Color(0xFF7C3AED).withValues(alpha: 0.12)
                        : const Color(0xFFD97706).withValues(alpha: 0.12))
                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$qty',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: qty > 0
                      ? (gift.isVoucher ? const Color(0xFF6D28D9) : const Color(0xFFB45309))
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
              color: const Color(0xFFD97706).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${record.totalGiftsCount}',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: const Color(0xFFB45309), fontSize: 13),
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
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: const Color(0xFF7C3AED), fontSize: 13),
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

    final existing = giftsDisbursed[giftKey];
    if (existing != null) {
      giftsDisbursed[giftKey] = existing.copyWith(
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
