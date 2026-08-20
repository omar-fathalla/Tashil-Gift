import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
  });

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
  final bool isEmbedded;
  final VoidCallback? onBack;

  const CompanyPrizesStockReportScreen({
    super.key,
    required this.lockedCompanySlug,
    required this.lockedCompanyName,
    this.initialEventId,
    this.isEmbedded = false,
    this.onBack,
  });

  @override
  ConsumerState<CompanyPrizesStockReportScreen> createState() =>
      _CompanyPrizesStockReportScreenState();
}

class _CompanyPrizesStockReportScreenState
    extends ConsumerState<CompanyPrizesStockReportScreen> {
  // Search & Filter State
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedEventId; // null = all campaigns
  String? _selectedBranch; // null = all branches
  String _stockStatusFilter = 'ALL'; // 'ALL', 'AVAILABLE', 'LOW', 'OUT'
  int _viewMode = 0; // 0: Itemized SKU, 1: Branch Breakdown, 2: Campaign Breakdown, 3: Supply & Movements Ledger
  String _movementTypeFilter = 'ALL'; // 'ALL', 'supply_batch', 'adjustment', 'campaign'
  String? _movementGiftFilter; // null = all gifts

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
  void didUpdateWidget(covariant CompanyPrizesStockReportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
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

  Future<void> _exportCsvReport(List<AggregatedGiftStock> gifts, AppStrings strings) async {
    final buffer = StringBuffer();
    // CSV Header
    buffer.writeln(
      'Gift SKU,Gift Name,Total Allocated,Awarded/Claimed,Remaining Stock,Depletion Rate %,Status,Branches Breakdown,Campaigns',
    );

    for (final gift in gifts) {
      final branchesInfo = gift.branchRemainingMap.entries
          .map((e) => '${e.key}: ${e.value} remaining')
          .join(' | ');
      final campaignsInfo = gift.eventNames.join(' | ');
      final status = gift.isOutOfStock
          ? 'Out of Stock'
          : (gift.isLowStock ? 'Low Stock' : 'In Stock');

      buffer.writeln(
        '"${gift.sku}","${gift.giftName}",${gift.totalAllocated},${gift.totalClaimed},${gift.totalRemaining},"${(gift.depletionRate * 100).toStringAsFixed(1)}%","$status","$branchesInfo","$campaignsInfo"',
      );
    }

    final csvString = buffer.toString();
    final utf8Bom = [0xEF, 0xBB, 0xBF];
    final bytes = Uint8List.fromList([...utf8Bom, ...utf8.encode(csvString)]);

    if (kIsWeb) {
      final base64Csv = base64Encode(bytes);
      final url = 'data:text/csv;charset=utf-8;base64,$base64Csv';
      await launchUrl(Uri.parse(url));
    } else {
      Clipboard.setData(ClipboardData(text: csvString));
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strings.isAr
              ? 'تم تصدير كشف جرد ورصيد الهدايا بنجاح 📥'
              : 'Prizes Stock Report exported successfully 📥',
        ),
        backgroundColor: Colors.teal.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  static String _formatDateOnly(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  void _showAddGiftDialog() {
    final nameController = TextEditingController();
    final qtyController = TextEditingController();
    final unitValController = TextEditingController();
    final refController = TextEditingController();
    final notesController = TextEditingController();
    String giftType = 'product'; // 'product' | 'voucher'
    final colorScheme = Theme.of(context).colorScheme;
    final isAr = ref.isArabic;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isVoucher = giftType == 'voucher';
            return AlertDialog(
              backgroundColor: colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                      color: colorScheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAr ? 'إضافة هدية أو فواتشر جديد' : 'Add New Gift / Voucher',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16, color: colorScheme.onSurface),
                        ),
                        Text(
                          widget.lockedCompanyName,
                          style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.primary, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type Switcher
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'product',
                          icon: const Icon(Icons.card_giftcard_rounded),
                          label: Text(isAr ? 'هدية عينية / منتج' : 'Product / Gift', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                        ),
                        ButtonSegment(
                          value: 'voucher',
                          icon: const Icon(Icons.confirmation_number_rounded),
                          label: Text(isAr ? 'كارت مشتريات / فواتشر' : 'Voucher / Card', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                        ),
                      ],
                      selected: {giftType},
                      onSelectionChanged: (set) {
                        setDialogState(() {
                          giftType = set.first;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Name
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      style: GoogleFonts.cairo(),
                      decoration: InputDecoration(
                        labelText: isVoucher ? (isAr ? 'اسم الفواتشر / الكارت *' : 'Voucher Name *') : (isAr ? 'اسم الهدية / الصنف *' : 'Gift Name *'),
                        hintText: isVoucher ? (isAr ? 'مثال: فواتشر 100 جنيه كارفور' : 'e.g. 100 EGP Voucher') : (isAr ? 'مثال: مج حراري ستانلس ستيل' : 'e.g. Thermal Mug'),
                        prefixIcon: Icon(isVoucher ? Icons.confirmation_number_outlined : Icons.card_giftcard_outlined),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Voucher Denomination
                    if (isVoucher) ...[
                      TextField(
                        controller: unitValController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                        style: GoogleFonts.cairo(),
                        decoration: InputDecoration(
                          labelText: isAr ? 'قيمة الكارت الواحد (فئة الفواتشر) *' : 'Voucher Face Value *',
                          hintText: '50 / 100 / 200',
                          prefixText: isAr ? 'ج.م ' : 'EGP ',
                          prefixIcon: const Icon(Icons.payments_rounded),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Quantity
                    TextField(
                      controller: qtyController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                      style: GoogleFonts.cairo(),
                      decoration: InputDecoration(
                        labelText: isVoucher
                            ? (isAr ? 'عدد الكروت (الرصيد الافتتاحي - اختياري)' : 'Initial Cards Count (Optional)')
                            : (isAr ? 'الكمية المتاحة (قطع - اختياري)' : 'Initial Stock (Units - Optional)'),
                        hintText: isAr ? '0 أو اتركها فارغة' : '0 or leave blank',
                        prefixIcon: const Icon(Icons.numbers_rounded),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Ref #
                    TextField(
                      controller: refController,
                      style: GoogleFonts.cairo(),
                      decoration: InputDecoration(
                        labelText: isAr ? 'رقم إذن الاستلام / الفاتورة (اختياري)' : 'PO / Delivery Ref # (Optional)',
                        hintText: isAr ? 'مثال: إذن توريد 101' : 'e.g. PO-101',
                        prefixIcon: const Icon(Icons.tag_rounded),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Notes
                    TextField(
                      controller: notesController,
                      style: GoogleFonts.cairo(),
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: isAr ? 'ملاحظات (اختياري)' : 'Notes (Optional)',
                        prefixIcon: const Icon(Icons.notes_rounded),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(isAr ? 'إلغاء' : 'Cancel', style: GoogleFonts.cairo()),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final qtyText = qtyController.text.trim();
                    final qty = qtyText.isEmpty ? 0 : (qtyText.toIntOrNull() ?? 0);
                    final unitVal = unitValController.text.trim().toDoubleOrNull() ?? 0.0;

                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isAr ? 'يرجى إدخال اسم الهدية أو الفواتشر' : 'Please enter gift name', style: GoogleFonts.cairo()),
                          backgroundColor: colorScheme.error,
                        ),
                      );
                      return;
                    }
                    if (qty < 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isAr ? 'الكمية يجب ألا تكون سالبة' : 'Quantity cannot be negative', style: GoogleFonts.cairo()),
                          backgroundColor: colorScheme.error,
                        ),
                      );
                      return;
                    }

                    try {
                      await ref.read(companyGiftsServiceProvider).addGift(
                        companySlug: widget.lockedCompanySlug,
                        companyName: widget.lockedCompanyName,
                        giftName: name,
                        quantity: qty,
                        giftType: giftType,
                        unitValue: isVoucher ? unitVal : 0.0,
                        referenceNumber: refController.text.trim(),
                        notes: notesController.text.trim(),
                        addedBy: 'مدير الشركة',
                      );

                      if (dialogContext.mounted) Navigator.of(dialogContext).pop();

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isAr ? 'تمت إضافة "$name" إلى رصيد هدايا الشركة بنجاح' : 'Gift "$name" added successfully',
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                            ),
                            backgroundColor: Colors.green[700],
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(AppErrorHandler.getFriendlyMessage(e), style: GoogleFonts.cairo()), backgroundColor: colorScheme.error),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(isAr ? 'حفظ وإضافة' : 'Save Gift', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddSupplyBatchDialog(CompanyGiftModel gift) {
    final TextEditingController batchQtyController = TextEditingController();
    final TextEditingController refNumberController = TextEditingController();
    final TextEditingController notesController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    final colorScheme = Theme.of(context).colorScheme;
    final isAr = ref.isArabic;
    final giftTitle = gift.giftName.isNotEmpty ? gift.giftName : 'الهدية';
    final isVoucher = gift.isVoucher;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final parsedQty = batchQtyController.text.trim().toIntOrNull() ?? 0;
            final newTotal = gift.totalQuantity + parsedQty;
            final newAvail = gift.availableQuantity + parsedQty;

            return AlertDialog(
              backgroundColor: colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.add_shopping_cart_rounded, color: Colors.green[700], size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAr ? 'توريد دفعة جديدة للمخزون' : 'Add Supply Batch',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16, color: colorScheme.onSurface),
                        ),
                        Text(
                          giftTitle,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stock Summary Chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isAr ? 'الرصيد الحالي: ${gift.totalQuantity} (${gift.availableQuantity} متاح)' : 'Current: ${gift.totalQuantity} (${gift.availableQuantity} avail)',
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                          ),
                          if (parsedQty > 0)
                            Text(
                              isAr ? 'بعد التوريد: $newTotal ($newAvail متاح)' : 'After: $newTotal ($newAvail avail)',
                              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green[700]),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Batch Quantity
                    TextField(
                      controller: batchQtyController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                      autofocus: true,
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        labelText: isVoucher ? (isAr ? 'كمية الدفعة (عدد الكروت) *' : 'Batch Cards *') : (isAr ? 'كمية الدفعة الموردة (قطع) *' : 'Batch Quantity (Units) *'),
                        hintText: 'مثال: 100',
                        prefixIcon: const Icon(Icons.numbers_rounded),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Supply Date Picker
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2024),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            selectedDate = DateTime(picked.year, picked.month, picked.day, selectedDate.hour, selectedDate.minute);
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_rounded, size: 18, color: colorScheme.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isAr ? 'تاريخ التوريد والاستلام' : 'Supply Date',
                                    style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                  ),
                                  Text(
                                    _formatDateOnly(selectedDate),
                                    style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              isAr ? 'تغيير التاريخ' : 'Change',
                              style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.primary, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Reference / PO Number
                    TextField(
                      controller: refNumberController,
                      style: GoogleFonts.cairo(),
                      decoration: InputDecoration(
                        labelText: isAr ? 'رقم إذن التوريد / المرجع / الفاتورة (اختياري)' : 'PO / Delivery Ref # (Optional)',
                        hintText: isAr ? 'مثال: إذن استلام 849 / PO-2026' : 'e.g. PO-849',
                        prefixIcon: const Icon(Icons.tag_rounded),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Notes
                    TextField(
                      controller: notesController,
                      style: GoogleFonts.cairo(),
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: isAr ? 'ملاحظات الدفعة والمصدر (اختياري)' : 'Batch Notes & Source (Optional)',
                        hintText: isAr ? 'مثال: توريد دفعة إضافية من المصنع' : 'e.g. Extra supply from factory',
                        prefixIcon: const Icon(Icons.notes_rounded),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(isAr ? 'إلغاء' : 'Cancel', style: GoogleFonts.cairo()),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    final qty = batchQtyController.text.trim().toIntOrNull();
                    if (qty == null || qty <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isAr ? 'يرجى إدخال كمية صحيحة أكبر من الصفر' : 'Please enter a valid quantity > 0', style: GoogleFonts.cairo()),
                          backgroundColor: colorScheme.error,
                        ),
                      );
                      return;
                    }

                    try {
                      await ref.read(companyGiftsServiceProvider).addSupplyBatch(
                        giftId: gift.id,
                        quantity: qty,
                        supplyDate: selectedDate,
                        referenceNumber: refNumberController.text.trim(),
                        notes: notesController.text.trim(),
                        addedBy: 'مدير الشركة',
                      );

                      if (dialogContext.mounted) Navigator.of(dialogContext).pop();

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isAr ? 'تم تسجيل توريد الدفعة الجديدة (+ $qty) بنجاح' : 'Supply batch (+ $qty) added successfully',
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                            ),
                            backgroundColor: Colors.green[700],
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(AppErrorHandler.getFriendlyMessage(e), style: GoogleFonts.cairo()), backgroundColor: colorScheme.error),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(isAr ? 'حفظ وتوريد الدفعة' : 'Add Supply Batch', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showStockAdjustmentDialog(CompanyGiftModel gift) {
    final TextEditingController adjQtyController = TextEditingController();
    final TextEditingController notesController = TextEditingController();
    bool isIncrease = true;
    String selectedReason = 'جرد دوري ومطابقة فعلية';
    final colorScheme = Theme.of(context).colorScheme;
    final isAr = ref.isArabic;
    final giftTitle = gift.giftName.isNotEmpty ? gift.giftName : 'الهدية';

    final reasonsList = [
      'جرد دوري ومطابقة فعلية',
      'تالف / هالك أثناء التخزين',
      'عينات ترويجية ودعائية',
      'تصحيح خطأ إدخال سابق',
      'مرتجع من فرع / حملة',
      'أخرى',
    ];

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final parsedQty = adjQtyController.text.trim().toIntOrNull() ?? 0;
            final delta = isIncrease ? parsedQty : -parsedQty;
            final newTotal = (gift.totalQuantity + delta).clamp(0, 999999);
            final newAvail = (gift.availableQuantity + delta).clamp(0, newTotal);

            return AlertDialog(
              backgroundColor: colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.tune_rounded, color: Colors.amber[900], size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAr ? 'تسوية مخزنية وجردية' : 'Stock Adjustment',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16, color: colorScheme.onSurface),
                        ),
                        Text(
                          giftTitle,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Increase / Decrease Switcher
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment<bool>(
                          value: true,
                          icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.green),
                          label: Text(isAr ? 'تسوية بالزيادة (+)' : 'Adjustment (+)', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                        ),
                        ButtonSegment<bool>(
                          value: false,
                          icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.red),
                          label: Text(isAr ? 'تسوية بالنقص / هالك (-)' : 'Adjustment (-)', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                        ),
                      ],
                      selected: {isIncrease},
                      onSelectionChanged: (set) {
                        setDialogState(() {
                          isIncrease = set.first;
                        });
                      },
                    ),
                    const SizedBox(height: 14),

                    // Stock Summary
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isAr ? 'الرصيد: ${gift.totalQuantity} (${gift.availableQuantity} متاح)' : 'Stock: ${gift.totalQuantity} (${gift.availableQuantity} avail)',
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                          ),
                          if (parsedQty > 0)
                            Text(
                              isAr ? 'الناتج: $newTotal ($newAvail متاح)' : 'Result: $newTotal ($newAvail avail)',
                              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: isIncrease ? Colors.green[700] : Colors.red[700]),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Quantity
                    TextField(
                      controller: adjQtyController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                      autofocus: true,
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        labelText: isAr ? 'كمية التسوية *' : 'Adjustment Quantity *',
                        hintText: 'مثال: 5',
                        prefixIcon: const Icon(Icons.exposure_rounded),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Reason Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: selectedReason,
                      decoration: InputDecoration(
                        labelText: isAr ? 'سبب التسوية *' : 'Adjustment Reason *',
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                      items: reasonsList.map((r) {
                        return DropdownMenuItem<String>(
                          value: r,
                          child: Text(r, style: GoogleFonts.cairo(fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedReason = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),

                    // Notes
                    TextField(
                      controller: notesController,
                      style: GoogleFonts.cairo(),
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: isAr ? 'ملاحظات تفصيلية' : 'Detailed Notes',
                        hintText: isAr ? 'اكتب ملاحظات حول سبب التسوية أو رقم المحضر' : 'Enter notes or report number',
                        prefixIcon: const Icon(Icons.notes_rounded),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(isAr ? 'إلغاء' : 'Cancel', style: GoogleFonts.cairo()),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: isIncrease ? Colors.green[700] : Colors.red[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    final qty = adjQtyController.text.trim().toIntOrNull();
                    if (qty == null || qty <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isAr ? 'يرجى إدخال كمية صحيحة أكبر من الصفر' : 'Please enter a valid quantity > 0', style: GoogleFonts.cairo()),
                          backgroundColor: colorScheme.error,
                        ),
                      );
                      return;
                    }

                    try {
                      await ref.read(companyGiftsServiceProvider).adjustStock(
                        giftId: gift.id,
                        isIncrease: isIncrease,
                        quantity: qty,
                        reason: selectedReason,
                        notes: notesController.text.trim(),
                        performedBy: 'مدير الشركة',
                      );

                      if (dialogContext.mounted) Navigator.of(dialogContext).pop();

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isAr
                                  ? (isIncrease ? 'تمت إضافة تسوية بالزيادة (+ $qty) بنجاح' : 'تم تسجيل خصم التسوية (- $qty) بنجاح')
                                  : (isIncrease ? 'Adjustment (+ $qty) recorded' : 'Adjustment (- $qty) recorded'),
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                            ),
                            backgroundColor: isIncrease ? Colors.green[700] : Colors.amber[900],
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(AppErrorHandler.getFriendlyMessage(e), style: GoogleFonts.cairo()), backgroundColor: colorScheme.error),
                        );
                      }
                    }
                  },
                  child: Text(isAr ? 'حفظ التسوية' : 'Save Adjustment', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
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
                                  color: currentRemaining <= 0 ? const Color(0xFFB3261E) : const Color(0xFF006C50),
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
                                    Icon(Icons.warehouse_rounded, size: 15, color: Colors.blue[700]),
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
                                    color: Colors.blue.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$masterAvailable $unitLabel ${isAr ? 'متاح بالمخزن' : 'available'}',
                                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue[800]),
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
                            avatar: const Icon(Icons.bolt_rounded, size: 16, color: Colors.red),
                            label: Text(
                              strings.zeroAllocationBtn,
                              style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red[800]),
                            ),
                            backgroundColor: Colors.red.withValues(alpha: 0.1),
                            side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
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
                            ? Colors.green.withValues(alpha: 0.12)
                            : (effectiveAdd < 0 ? Colors.orange.withValues(alpha: 0.12) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: effectiveAdd > 0
                              ? Colors.green.withValues(alpha: 0.4)
                              : (effectiveAdd < 0 ? Colors.orange.withValues(alpha: 0.4) : colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            effectiveAdd >= 0 ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                            size: 20,
                            color: effectiveAdd > 0 ? Colors.green[800] : (effectiveAdd < 0 ? Colors.orange[900] : colorScheme.outline),
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
                                    color: effectiveAdd > 0 ? Colors.green[900] : (effectiveAdd < 0 ? Colors.orange[900] : colorScheme.onSurface),
                                  ),
                                ),
                                if (effectiveAdd < 0)
                                  Text(
                                    isAr
                                        ? 'سيتم إرجاع ${effectiveAdd.abs()} $unitLabel إلى رصيد المخزن المركزي للشركة'
                                        : '${effectiveAdd.abs()} $unitLabel will return to master stock',
                                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange[900]),
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
                                  backgroundColor: Colors.green[700],
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
    final colorScheme = Theme.of(context).colorScheme;
    final unitLabel = (masterGift?.isVoucher ?? false) ? (isAr ? 'كارت' : 'cards') : (isAr ? 'قطعة' : 'pcs');

    // Collect all matching branch allocations across events for this gift
    final List<Map<String, dynamic>> branchAllocations = [];
    final normGiftName = gift.giftName.trim().toLowerCase();
    final normGiftId = gift.giftId.trim().toLowerCase();

    for (final event in events) {
      if (event.companySlug.toLowerCase().trim() != companySlug.toLowerCase().trim()) continue;
      for (final prize in event.allocatedPrizes) {
        final pName = prize.name.trim().toLowerCase();
        final pId = prize.giftId.trim().toLowerCase();
        if (pName == normGiftName || (normGiftId.isNotEmpty && pId == normGiftId)) {
          final claimed = (prize.allocatedQuantity - prize.remainingQuantity).clamp(0, prize.allocatedQuantity);
          branchAllocations.add({
            'eventId': event.id,
            'eventName': event.eventName,
            'branchId': prize.branchId,
            'branchName': prize.branchName.isNotEmpty ? prize.branchName : (isAr ? 'كافة الفروع / عام' : 'All Branches'),
            'currentAllocated': prize.allocatedQuantity,
            'currentClaimed': claimed,
            'currentRemaining': prize.remainingQuantity,
            'controller': TextEditingController(text: '${prize.allocatedQuantity}'),
          });
        }
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
                      color: Colors.purple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.tune_rounded, color: Colors.purple[800], size: 24),
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
                width: 550,
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

                      // Quick Action Bar: Zero All Branches (0)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isAr ? 'الحصص الموزعة على الفروع:' : 'Branch Quotas:',
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.bolt_rounded, size: 16, color: Colors.red),
                            label: Text(
                              strings.zeroAllAllocationsBtn,
                              style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red[800]),
                            ),
                            backgroundColor: Colors.red.withValues(alpha: 0.1),
                            side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
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
                      const SizedBox(height: 10),

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
                                          style: GoogleFonts.cairo(fontSize: 11, color: Colors.orange[800], fontWeight: FontWeight.bold),
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
                                      backgroundColor: Colors.red.withValues(alpha: 0.1),
                                      foregroundColor: Colors.red[700],
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
                                  backgroundColor: const Color(0xFF006C50),
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
                    backgroundColor: Colors.purple[700],
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
                              Text('${gift.totalQuantity - gift.availableQuantity}', style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange[800])),
                            ],
                          ),
                          Container(width: 1, height: 28, color: colorScheme.outlineVariant),
                          Column(
                            children: [
                              Text(isAr ? 'المتاح بالمستودع' : 'Warehouse Avail', style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                              Text('${gift.availableQuantity}', style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green[800])),
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
                                            color: Colors.green.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            '#${batch.batchNumber}',
                                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.green[800], fontSize: 13),
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
                          stream: ref.read(companyGiftsServiceProvider).stockMovementsStream(gift.companySlug, giftId: gift.id),
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
                                final color = isAdd ? Colors.green[800] : (m.movementType == 'campaign_allocation' ? Colors.orange[900] : Colors.red[800]);
                                final bgColor = isAdd ? Colors.green.withValues(alpha: 0.12) : (m.movementType == 'campaign_allocation' ? Colors.orange.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.12));

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

  void _showEditGiftDialog(CompanyGiftModel gift) {
    final TextEditingController editQtyController = TextEditingController(text: gift.availableQuantity.toString());
    final isVoucher = gift.isVoucher;
    final TextEditingController editUnitValController = TextEditingController(
      text: gift.unitValue > 0 ? (gift.unitValue == gift.unitValue.roundToDouble() ? gift.unitValue.toInt().toString() : gift.unitValue.toString()) : '',
    );
    final colorScheme = Theme.of(context).colorScheme;
    final isAr = ref.isArabic;
    final giftTitle = gift.giftName.isNotEmpty ? gift.giftName : 'الهدية';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Row(
            children: [
              Icon(isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                isAr ? 'تعديل بيانات الهدية / المخزون' : 'Edit Gift / Stock',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: colorScheme.onSurface, fontSize: 16),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${isAr ? 'الهدية:' : 'Gift:'} $giftTitle',
                  style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
                ),
                if (isVoucher) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: editUnitValController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                    style: GoogleFonts.cairo(),
                    decoration: InputDecoration(
                      labelText: isAr ? 'قيمة الكارت الواحد (فئة الفواتشر)' : 'Voucher Face Value',
                      hintText: '50 / 100',
                      prefixText: isAr ? 'ج.م ' : 'EGP ',
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: editQtyController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                  autofocus: !isVoucher,
                  style: GoogleFonts.cairo(),
                  decoration: InputDecoration(
                    labelText: isVoucher ? (isAr ? 'عدد الكروت المتاحة' : 'Available Cards') : (isAr ? 'الكمية المتاحة' : 'Available Quantity'),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(isAr ? 'إلغاء' : 'Cancel', style: GoogleFonts.cairo()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () async {
                final qty = editQtyController.text.trim().toIntOrNull();
                final unitVal = editUnitValController.text.trim().toDoubleOrNull() ?? gift.unitValue;
                if (qty != null && qty >= 0) {
                  try {
                    await ref.read(firestoreProvider).collection('company_gifts').doc(gift.id).update({
                      'availableQuantity': qty,
                      if (isVoucher) 'unitValue': unitVal,
                    });
                  } catch (_) {}
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                }
              },
              child: Text(isAr ? 'حفظ' : 'Save', style: GoogleFonts.cairo()),
            ),
          ],
        );
      },
    );
  }

  void _deleteGift(CompanyGiftModel gift) async {
    final isAr = ref.isArabic;
    final colorScheme = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Text(isAr ? 'تأكيد الحذف النهائي' : 'Confirm Permanent Deletion', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
          content: Text(
            isAr
                ? 'هل أنت متأكد من رغبتك في حذف هدية "${gift.giftName}" نهائياً من مخزون الشركة؟ سيتم مسح كافة مخصصاتها وتبعياتها من كافة الفعاليات والحملات.'
                : 'Are you sure you want to permanently delete "${gift.giftName}"? All its allocations and dependencies will be removed across all campaigns.',
            style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(isAr ? 'إلغاء' : 'Cancel', style: GoogleFonts.cairo()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(isAr ? 'حذف ومسح التبعيات' : 'Delete & Cascade', style: GoogleFonts.cairo()),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        await ref.read(companyGiftsServiceProvider).deleteGiftCascade(
          giftId: gift.id,
          companySlug: gift.companySlug,
          giftName: gift.giftName,
          performedBy: 'مدير الشركة',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isAr ? 'تم حذف الهدية ومسح كافة تبعياتها بنجاح' : 'Gift and allocations deleted successfully', style: GoogleFonts.cairo()),
              backgroundColor: const Color(0xFF006C50),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${isAr ? 'حدث خطأ أثناء الحذف:' : 'Error deleting:'} $e', style: GoogleFonts.cairo()),
              backgroundColor: colorScheme.error,
            ),
          );
        }
      }
    }
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

    // 1. Stream events for this company to obtain all allocated prizes per campaign & branch
    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('events').snapshots(),
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

        // 2. Stream company_gifts master catalog
        return StreamBuilder<QuerySnapshot>(
          stream: firestore
              .collection('company_gifts')
              .where('companySlug', isEqualTo: slug)
              .snapshots(),
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
              stream: firestore
                  .collection('receipts_transactions')
                  .where('companySlug', isEqualTo: slug)
                  .snapshots(),
              builder: (context, receiptsSnapshot) {
                final transactionDocs = receiptsSnapshot.data?.docs ?? [];
                return _buildAnalyzedView(
                  context: context,
                  colorScheme: colorScheme,
                  strings: strings,
                  isAr: isAr,
                  isHi: isHi,
                  isMobile: isMobile,
                  companyEvents: companyEvents,
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

    // 2. Build verified transactions claimed maps (Per gift & per gift+branch)
    final Map<String, int> transactionClaimedPerGift = {};
    final Map<String, int> transactionClaimedPerGiftBranch = {};

    for (final doc in transactionDocs) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final tCampId = (data['campaignId'] ?? data['event_id'] ?? '').toString();
      if (_selectedEventId != null &&
          _selectedEventId!.isNotEmpty &&
          tCampId.isNotEmpty &&
          tCampId != _selectedEventId) {
        continue;
      }
      if (data['game_played'] != true) continue;

      final tBranch = (data['branch_detected'] ?? data['branch_id'] ?? '').toString().trim();
      final claimedGifts = (data['claimed_gifts'] as List?) ?? [];

      if (claimedGifts.isNotEmpty) {
        for (final cg in claimedGifts) {
          if (cg is Map) {
            final gName = (cg['giftName'] ?? cg['giftId'] ?? '').toString().trim();
            final qty = (cg['quantity'] as num?)?.toInt() ?? 1;
            final key = _normalizePrizeKey(gName);
            if (key.isNotEmpty) {
              transactionClaimedPerGift[key] = (transactionClaimedPerGift[key] ?? 0) + qty;
              if (tBranch.isNotEmpty) {
                final bKey = _normalizePrizeKey(tBranch);
                final fullKey = '${key}__$bKey';
                transactionClaimedPerGiftBranch[fullKey] =
                    (transactionClaimedPerGiftBranch[fullKey] ?? 0) + qty;
              }
            }
          }
        }
      } else {
        final prizesWon = (data['prizes_won'] as List?)?.map((p) => p.toString()).toList() ??
            [(data['prize_won'] ?? '').toString()];
        for (final p in prizesWon) {
          if (p.trim().isNotEmpty) {
            final key = _normalizePrizeKey(p);
            transactionClaimedPerGift[key] = (transactionClaimedPerGift[key] ?? 0) + 1;
            if (tBranch.isNotEmpty) {
              final bKey = _normalizePrizeKey(tBranch);
              final fullKey = '${key}__$bKey';
              transactionClaimedPerGiftBranch[fullKey] =
                  (transactionClaimedPerGiftBranch[fullKey] ?? 0) + 1;
            }
          }
        }
      }
    }

    int getReconciledClaimed(String giftName, int rawClaimed, [String? branchName]) {
      final normG = _normalizePrizeKey(giftName);
      int txClaimed = 0;
      if (branchName != null && branchName.isNotEmpty) {
        final normB = _normalizePrizeKey(branchName);
        for (final entry in transactionClaimedPerGiftBranch.entries) {
          final parts = entry.key.split('__');
          final gPart = parts.first;
          final bPart = parts.length > 1 ? parts[1] : '';
          final gMatches = gPart == normG || gPart.contains(normG) || normG.contains(gPart);
          final bMatches = bPart.isNotEmpty && (bPart == normB || bPart.contains(normB) || normB.contains(bPart));
          if (gMatches && bMatches) {
            txClaimed += entry.value;
          }
        }
      } else {
        for (final entry in transactionClaimedPerGift.entries) {
          if (entry.key == normG || entry.key.contains(normG) || normG.contains(entry.key)) {
            txClaimed += entry.value;
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
      final key = mg.giftName.trim().toLowerCase();
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
      );
    }

    for (final event in filteredEvents) {
      for (final prize in event.allocatedPrizes) {
        // If master company gifts are present, ignore deleted/orphaned gifts
        CompanyGiftModel? matchingMasterGift;
        if (masterGifts.isNotEmpty) {
          matchingMasterGift = masterGifts.where((mg) {
            final mgName = _normalizePrizeKey(mg.giftName);
            final pName = _normalizePrizeKey(prize.name);
            return mg.id == prize.giftId ||
                mgName == pName ||
                (mgName.isNotEmpty && pName.isNotEmpty && (mgName.contains(pName) || pName.contains(mgName)));
          }).firstOrNull;

          if (matchingMasterGift == null) {
            continue; // Skip deleted/orphaned gift
          }
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
        final key = canonicalGiftName.toLowerCase();
        final branchKey = prize.branchName.isNotEmpty
            ? prize.branchName.trim()
            : (prize.branchId.isNotEmpty ? prize.branchId : (isAr ? 'الفرع الرئيسي' : 'Main Branch'));

        final rawClaimed = (prize.allocatedQuantity - prize.remainingQuantity).clamp(0, prize.allocatedQuantity);
        final branchClaimed = prize.allocatedQuantity > 0
            ? getReconciledClaimed(prize.name, rawClaimed, branchKey).clamp(0, prize.allocatedQuantity)
            : 0;
        final branchRemaining = (prize.allocatedQuantity - branchClaimed).clamp(0, prize.allocatedQuantity);

        final existing = aggregatedMap[key];
        if (existing == null) {
          final branchRem = branchKey.isNotEmpty ? <String, int>{branchKey: branchRemaining} : <String, int>{};
          final branchAlloc = branchKey.isNotEmpty ? <String, int>{branchKey: prize.allocatedQuantity} : <String, int>{};
          final claimed = prize.allocatedQuantity > 0
              ? getReconciledClaimed(prize.name, rawClaimed).clamp(0, prize.allocatedQuantity)
              : 0;
          final remaining = (prize.allocatedQuantity - claimed).clamp(0, prize.allocatedQuantity);

          aggregatedMap[key] = AggregatedGiftStock(
            giftId: canonicalGiftId,
            giftName: canonicalGiftName,
            sku: canonicalGiftId,
            totalAllocated: prize.allocatedQuantity,
            totalClaimed: claimed,
            totalRemaining: remaining,
            branchRemainingMap: branchRem,
            branchAllocatedMap: branchAlloc,
            eventNames: prize.allocatedQuantity > 0 ? [event.eventName] : [],
          );
        } else {
          final newAllocated = existing.totalAllocated + prize.allocatedQuantity;
          final newClaimed = newAllocated > 0
              ? getReconciledClaimed(prize.name, existing.totalClaimed + branchClaimed).clamp(0, newAllocated)
              : 0;
          final newRemaining = (newAllocated - newClaimed).clamp(0, newAllocated);

          if (branchKey.isNotEmpty && prize.allocatedQuantity > 0) {
            existing.branchRemainingMap[branchKey] =
                (existing.branchRemainingMap[branchKey] ?? 0) + branchRemaining;
            existing.branchAllocatedMap[branchKey] =
                (existing.branchAllocatedMap[branchKey] ?? 0) + prize.allocatedQuantity;
          }

          if (!existing.eventNames.contains(event.eventName) && prize.allocatedQuantity > 0) {
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
                // 1. Hero KPI Stat Cards
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
                  onExport: () => _exportCsvReport(allGiftsList, strings),
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
                if (_viewMode == 3)
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
                  ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
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
        iconColor: const Color(0xFF6750A4),
        title: strings.totalAllocatedGifts,
        value: '$totalAllocated',
        badgeText: isAr ? 'إجمالي المعتمد' : (isHi ? 'कुल' : 'Total Coded'),
        badgeColor: const Color(0xFF6750A4).withValues(alpha: 0.12),
        badgeTextColor: const Color(0xFF6750A4),
        subtitle: isAr ? 'شاملاً كافة الحملات والمخزون' : 'Across all campaigns',
      ),
      _buildStatCard(
        colorScheme: colorScheme,
        icon: Icons.card_giftcard_rounded,
        iconColor: const Color(0xFF00639B),
        title: strings.awardedGiftsCount,
        value: '$totalClaimed',
        badgeText: '${(depletionRate * 100).toStringAsFixed(0)}% ${strings.depletionRateLabel}',
        badgeColor: const Color(0xFF00639B).withValues(alpha: 0.12),
        badgeTextColor: const Color(0xFF00639B),
        subtitle: isAr ? 'هدايا تم تسليمها للعملاء الفائزين' : 'Claimed by shoppers',
      ),
      _buildStatCard(
        colorScheme: colorScheme,
        icon: Icons.verified_rounded,
        iconColor: totalRemaining <= 0
            ? const Color(0xFFB3261E)
            : (totalRemaining < 20 ? const Color(0xFFD97706) : const Color(0xFF006C50)),
        title: strings.remainingStockBalance,
        value: '$totalRemaining',
        badgeText: totalRemaining <= 0
            ? strings.stockDepletedBadge
            : (totalRemaining < 20 ? strings.stockLowBadge : strings.stockHealthyBadge),
        badgeColor: (totalRemaining <= 0
                ? const Color(0xFFB3261E)
                : (totalRemaining < 20 ? const Color(0xFFD97706) : const Color(0xFF006C50)))
            .withValues(alpha: 0.12),
        badgeTextColor: totalRemaining <= 0
            ? const Color(0xFFB3261E)
            : (totalRemaining < 20 ? const Color(0xFFD97706) : const Color(0xFF006C50)),
        subtitle: isAr ? 'الرصيد المتاح للسحب الآن' : 'Available in live wheels',
      ),
      _buildStatCard(
        colorScheme: colorScheme,
        icon: Icons.storefront_rounded,
        iconColor: const Color(0xFF006874),
        title: strings.coveredOutletsCount,
        value: '$coveredBranches',
        badgeText: '$campaignsCount ${isAr ? 'فعاليات' : 'Campaigns'}',
        badgeColor: const Color(0xFF006874).withValues(alpha: 0.12),
        badgeTextColor: const Color(0xFF006874),
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
              Container(
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
                message: isAr ? 'إضافة هدية أو فواتشر جديد إلى رصيد الشركة' : 'Add New Gift or Voucher',
                child: FilledButton.icon(
                  onPressed: _showAddGiftDialog,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: isMobile
                      ? Text(
                          isAr ? 'إضافة' : 'Add',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : Text(
                          isAr ? 'إضافة هدية أو فواتشر جديد' : 'Add New Gift / Voucher',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
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
              // Campaign Selector Dropdown
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
                        onChanged: (val) => setState(() => _selectedEventId = val),
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
      selectedValue: _viewMode,
      onSelected: (newVal) => setState(() => _viewMode = newVal),
    );
  }

  // ---------------------------------------------------------------------------
  // Mode 3: Supply Batches & Movements Ledger View
  // ---------------------------------------------------------------------------
  static String _formatMovementDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
      themeColor = Colors.green[800]!;
      icon = Icons.add_shopping_cart_rounded;
    } else if (movement.movementType.startsWith('adjustment')) {
      themeColor = isAdd ? Colors.teal[800]! : Colors.amber[900]!;
      icon = Icons.tune_rounded;
    } else if (isAlloc) {
      themeColor = Colors.orange[800]!;
      icon = Icons.campaign_rounded;
    } else if (isReturn) {
      themeColor = Colors.blue[800]!;
      icon = Icons.replay_rounded;
    } else if (isClaim) {
      themeColor = Colors.purple[800]!;
      icon = Icons.card_giftcard_rounded;
    } else {
      themeColor = isAdd ? Colors.green[800]! : Colors.red[800]!;
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
      stream: ref.watch(companyGiftsServiceProvider).stockMovementsStream(companySlug),
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
                  iconColor: Colors.blue[700]!,
                  title: isAr ? 'إجمالي دفعات التوريد' : 'Total Supply Batches',
                  value: '$totalBatchesCount ${isAr ? 'دفعات' : 'batches'}',
                  subtitle: '+ $totalBatchesQty ${isAr ? 'قطع/كروت واردة' : 'inward items'}',
                ),
                _buildMiniStatCard(
                  colorScheme: colorScheme,
                  icon: Icons.tune_rounded,
                  iconColor: Colors.amber[800]!,
                  title: isAr ? 'إجمالي التسويات الجردية' : 'Total Adjustments',
                  value: '$totalAdjustmentsCount ${isAr ? 'تسوية' : 'adjustments'}',
                  subtitle: '${totalAdjustmentsDelta >= 0 ? '+' : ''}$totalAdjustmentsDelta ${isAr ? 'صافي التعديل' : 'net delta'}',
                ),
                _buildMiniStatCard(
                  colorScheme: colorScheme,
                  icon: Icons.receipt_long_rounded,
                  iconColor: Colors.green[700]!,
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
        ? const Color(0xFFB3261E)
        : (gift.isLowStock ? const Color(0xFFD97706) : const Color(0xFF006C50));
    final statusLabel = gift.isOutOfStock
        ? strings.stockDepletedBadge
        : (gift.isLowStock ? strings.stockLowBadge : strings.stockHealthyBadge);

    final masterGift = masterGifts.where((mg) {
      return mg.id == gift.giftId ||
          _normalizePrizeKey(mg.giftName) == _normalizePrizeKey(gift.giftName);
    }).firstOrNull;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
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
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    masterGift?.isVoucher == true ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                    color: colorScheme.primary,
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
                        gift.eventNames.join(' • '),
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
                      value: '${gift.totalAllocated}',
                      colorScheme: colorScheme,
                    ),
                    _buildMetricSnippet(
                      label: isAr ? 'المصروف' : 'Claimed',
                      value: '${gift.totalClaimed}',
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
                          ? const Color(0xFFB3261E)
                          : (gift.depletionRate > 0.60
                              ? const Color(0xFFD97706)
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
                              ? const Color(0xFFB3261E).withValues(alpha: 0.08)
                              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: entry.value <= 0
                                ? const Color(0xFFB3261E).withValues(alpha: 0.3)
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
                                  ? const Color(0xFFB3261E)
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
                                    ? const Color(0xFFB3261E)
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
          if (masterGift != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // 1. Add Supply Batch Button
                FilledButton.tonalIcon(
                  onPressed: () => _showAddSupplyBatchDialog(masterGift),
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
                  label: Text(
                    isAr ? 'توريد دفعة (+)' : 'Supply Batch (+)',
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.withValues(alpha: 0.15),
                    foregroundColor: Colors.green[800],
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                // 2. Stock Adjustment Button
                FilledButton.tonalIcon(
                  onPressed: () => _showStockAdjustmentDialog(masterGift),
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: Text(
                    isAr ? 'تسوية جردية (±)' : 'Adjustment (±)',
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.amber.withValues(alpha: 0.15),
                    foregroundColor: Colors.amber[900],
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                // 3. Movement Ledger Timeline Modal
                FilledButton.tonalIcon(
                  onPressed: () => _showBatchesAndMovementLedgerDialog(masterGift),
                  icon: const Icon(Icons.history_edu_rounded, size: 16),
                  label: Text(
                    isAr ? 'سجل الحركات' : 'Movements',
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.6),
                    foregroundColor: colorScheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                // 4. Edit / Zero Branch Allocations Button
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
                    isAr ? 'مخصصات الفروع (تعديل/تصفير)' : 'Branch Quotas',
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.purple.withValues(alpha: 0.15),
                    foregroundColor: Colors.purple[800],
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                // 5. Edit Gift
                IconButton.filledTonal(
                  onPressed: () => _showEditGiftDialog(masterGift),
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  tooltip: isAr ? 'تعديل بيانات الهدية' : 'Edit Gift',
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                // 5. Delete Gift
                IconButton.filledTonal(
                  onPressed: () => _deleteGift(masterGift),
                  icon: const Icon(Icons.delete_rounded, size: 16),
                  tooltip: isAr ? 'حذف الهدية من المخزون' : 'Delete Gift',
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.errorContainer,
                    foregroundColor: colorScheme.onErrorContainer,
                    padding: const EdgeInsets.all(8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
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
  }) {
    // Group all prizes by branch name
    final Map<String, List<Map<String, dynamic>>> branchGroups = {};

    for (final event in filteredEvents) {
      for (final prize in event.allocatedPrizes) {
        if (masterGifts.isNotEmpty) {
          final isPresentInMaster = masterGifts.any((mg) {
            final mgName = _normalizePrizeKey(mg.giftName);
            final pName = _normalizePrizeKey(prize.name);
            return mg.id == prize.giftId ||
                mgName == pName ||
                (mgName.isNotEmpty && pName.isNotEmpty && (mgName.contains(pName) || pName.contains(mgName)));
          });
          if (!isPresentInMaster) continue;
        }

        final bName = prize.branchName.trim().isNotEmpty
            ? prize.branchName.trim()
            : (prize.branchId.trim().isNotEmpty
                ? prize.branchId.trim()
                : (isAr ? 'كافة الفروع / عام' : 'All Branches / General'));

        branchGroups.putIfAbsent(bName, () => []).add({
          'eventId': event.id,
          'eventName': event.eventName,
          'giftId': prize.giftId,
          'giftName': prize.name,
          'giftType': prize.giftType,
          'unitValue': prize.unitValue,
          'branchId': prize.branchId,
          'branchName': bName,
          'allocated': prize.allocatedQuantity,
          'remaining': prize.remainingQuantity,
          'claimed': (prize.allocatedQuantity - prize.remainingQuantity).clamp(0, prize.allocatedQuantity),
        });
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

    for (final p in prizesList) {
      branchAllocated += (p['allocated'] as int? ?? 0);
      branchClaimed += (p['claimed'] as int? ?? 0);
      branchRemaining += (p['remaining'] as int? ?? 0);
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
                        ? const Color(0xFFB3261E).withValues(alpha: 0.12)
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
                              ? const Color(0xFFB3261E)
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
                              ? const Color(0xFFB3261E)
                              : colorScheme.primary,
                        ),
                      ),
                    ],
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
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.card_giftcard_rounded,
                          size: 18,
                          color: (p['remaining'] as int? ?? 0) <= 0
                              ? const Color(0xFFB3261E)
                              : colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p['giftName'] as String? ?? '',
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                p['eventName'] as String? ?? '',
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
                          color: (p['remaining'] as int? ?? 0) <= 0
                              ? const Color(0xFFB3261E)
                              : const Color(0xFF006C50),
                          isHighlight: true,
                          colorScheme: colorScheme,
                        ),
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
                                      backgroundColor: Colors.purple.withValues(alpha: 0.12),
                                      foregroundColor: Colors.purple[800],
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      visualDensity: VisualDensity.compact,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ],
                              ),
                      ],
                    ),
                  ),
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
  // Mode 2: Campaign-by-Campaign Breakdown
  // ---------------------------------------------------------------------------
  Widget _buildCampaignBreakdownView({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required List<EventModel> filteredEvents,
    required List<CompanyGiftModel> masterGifts,
  }) {
    return Column(
      children: [
        for (final event in filteredEvents)
          _buildCampaignGroupCard(
            colorScheme: colorScheme,
            strings: strings,
            isAr: isAr,
            isHi: isHi,
            isMobile: isMobile,
            event: event,
            masterGifts: masterGifts,
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
  }) {
    final validPrizes = event.allocatedPrizes.where((prize) {
      if (masterGifts.isEmpty) return true;
      return masterGifts.any((mg) {
        final mgName = _normalizePrizeKey(mg.giftName);
        final pName = _normalizePrizeKey(prize.name);
        return mg.id == prize.giftId ||
            mgName == pName ||
            (mgName.isNotEmpty && pName.isNotEmpty && (mgName.contains(pName) || pName.contains(mgName)));
      });
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
          // Header
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
                // Depletion Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
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
          ),

          // Items inside campaign
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (validPrizes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      isAr ? 'لم يتم تكويد هدايا مخصصة لهذه الحملة بعد.' : 'No prizes allocated yet.',
                      style: GoogleFonts.cairo(
                        color: colorScheme.outline,
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  for (final prize in validPrizes)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.card_giftcard_rounded,
                            size: 18,
                            color: prize.remainingQuantity <= 0
                                ? const Color(0xFFB3261E)
                                : colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  prize.name,
                                  style: GoogleFonts.cairo(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                if (prize.branchName.isNotEmpty)
                                  Text(
                                    prize.branchName,
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
                            value: '${prize.allocatedQuantity}',
                            color: colorScheme.onSurfaceVariant,
                            colorScheme: colorScheme,
                          ),
                          const SizedBox(width: 6),
                          _buildBranchQtyPill(
                            label: isAr ? 'المصروف' : 'Claimed',
                            value: '${(prize.allocatedQuantity - prize.remainingQuantity).clamp(0, prize.allocatedQuantity)}',
                            color: colorScheme.secondary,
                            colorScheme: colorScheme,
                          ),
                          const SizedBox(width: 6),
                          _buildBranchQtyPill(
                            label: isAr ? 'المتبقي' : 'Left',
                            value: '${prize.remainingQuantity}',
                            color: prize.remainingQuantity <= 0
                                ? const Color(0xFFB3261E)
                                : const Color(0xFF006C50),
                            isHighlight: true,
                            colorScheme: colorScheme,
                          ),
                        ],
                      ),
                    ),
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
