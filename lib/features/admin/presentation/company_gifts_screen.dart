import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/arabic_numbers_utils.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/services/company_gifts_service.dart';
import '../domain/company_gift_model.dart';

class CompanyGiftsScreen extends ConsumerStatefulWidget {
  const CompanyGiftsScreen({super.key});

  @override
  ConsumerState<CompanyGiftsScreen> createState() => _CompanyGiftsScreenState();
}

class _CompanyGiftsScreenState extends ConsumerState<CompanyGiftsScreen> {
  String? _selectedCompanySlug;
  String? _selectedCompanyName;
  String _selectedGiftType = 'product'; // 'product' | 'voucher'
  final TextEditingController _companySearchController = TextEditingController();
  final TextEditingController _giftNameController = TextEditingController();
  final TextEditingController _giftQuantityController = TextEditingController();
  final TextEditingController _voucherUnitValueController = TextEditingController();
  final FocusNode _giftNameFocusNode = FocusNode();
  final FocusNode _giftQuantityFocusNode = FocusNode();
  final FocusNode _voucherUnitValueFocusNode = FocusNode();
  bool _isLoading = false;

  static String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  static String _formatDateOnly(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
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
                        labelText: isVoucher ? 'كمية الدفعة (عدد الكروت) *' : 'كمية الدفعة الموردة (قطع) *',
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
                        hintText: isAr ? 'مثال: توريد دفعة إضافية من المورد' : 'e.g. Extra supply from supplier',
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
                        addedBy: 'مسؤول النظام',
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
                        performedBy: 'مسؤول النظام',
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

  @override
  void dispose() {
    _companySearchController.dispose();
    _giftNameController.dispose();
    _giftQuantityController.dispose();
    _voucherUnitValueController.dispose();
    _giftNameFocusNode.dispose();
    _giftQuantityFocusNode.dispose();
    _voucherUnitValueFocusNode.dispose();
    super.dispose();
  }

  void _onVoucherDenominationSelected(double value) {
    final valStr = value == value.roundToDouble() ? value.toInt().toString() : value.toString();
    _voucherUnitValueController.text = valStr;
    if (_giftNameController.text.isEmpty || _giftNameController.text.startsWith('فواتشر') || _giftNameController.text.startsWith('قسيمة')) {
      _giftNameController.text = 'فواتشر $valStr جنيه';
    }
    setState(() {});
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
    Widget? actionBadge,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                ?actionBadge,
              ],
            ),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }

  Future<void> _addGift() async {
    if (_isLoading) return;

    if (_selectedCompanySlug == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'يرجى اختيار الشركة أولاً',
            style: GoogleFonts.cairo(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final qtyText = _giftQuantityController.text.trim();
    final quantity = qtyText.toIntOrNull();
    if (quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'الكمية يجب أن تكون رقماً صحيحاً أكبر من الصفر',
            style: GoogleFonts.cairo(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    double unitVal = 0.0;
    String name = _giftNameController.text.trim();

    if (_selectedGiftType == 'voucher') {
      unitVal = _voucherUnitValueController.text.trim().toDoubleOrNull() ?? 0.0;
      if (unitVal <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'يرجى تحديد القيمة المالية للكارت الواحد (فئة الفواتشر مثل 25، 50، 100 ج.م)',
              style: GoogleFonts.cairo(),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (name.isEmpty) {
        final valFormatted = unitVal == unitVal.roundToDouble() ? unitVal.toInt().toString() : unitVal.toString();
        name = 'فواتشر $valFormatted جنيه';
      }
    } else {
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'يرجى إدخال اسم الهدية',
              style: GoogleFonts.cairo(),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final docRef = ref.read(firestoreProvider).collection('company_gifts').doc();
      final slug = _selectedCompanySlug!.toLowerCase().trim();
      final companyName = _selectedCompanyName ?? _selectedCompanySlug!;

      await docRef.set({
        'id': docRef.id,
        'companySlug': slug,
        'companyName': companyName,
        'name': name,
        'giftName': name,
        'totalQuantity': quantity,
        'availableQuantity': quantity,
        'giftType': _selectedGiftType,
        'unitValue': unitVal,
        'orderIndex': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {
          // Firestore cache applies the mutation immediately and syncs to server in background
        },
      );

      // Clear fields and return focus to gift name so user can add another gift immediately
      _giftNameController.clear();
      _giftQuantityController.clear();
      _voucherUnitValueController.clear();

      if (mounted) {
        if (_selectedGiftType == 'voucher') {
          _voucherUnitValueFocusNode.requestFocus();
        } else {
          _giftNameFocusNode.requestFocus();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedGiftType == 'voucher'
                        ? 'تمت إضافة $quantity كارت $name (بقيمة إجمالية ${(quantity * unitVal).toInt()} ج.م) بنجاح'
                        : 'تمت إضافة الهدية "$name" بنجاح',
                    style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء إضافة الهدية'),
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showEditGiftDialog(Map<String, dynamic> gift) {
    final TextEditingController editQtyController = TextEditingController(text: gift['availableQuantity'].toString());
    final rawUnitVal = (gift['unitValue'] as num?)?.toDouble() ?? 0.0;
    final isVoucher = (gift['giftType'] == 'voucher') || rawUnitVal > 0;
    final TextEditingController editUnitValController = TextEditingController(
      text: rawUnitVal > 0 ? (rawUnitVal == rawUnitVal.roundToDouble() ? rawUnitVal.toInt().toString() : rawUnitVal.toString()) : '',
    );
    final colorScheme = Theme.of(context).colorScheme;
    final giftTitle = gift['giftName'] ?? gift['name'] ?? 'الهدية';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: Row(
            children: [
              Icon(
                isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'تعديل بيانات الهدية / المخزون',
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
                  'الهدية: $giftTitle',
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
                      labelText: 'قيمة الكارت الواحد (فئة الفواتشر)',
                      hintText: 'مثال: 50',
                      prefixText: 'ج.م ',
                      labelStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
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
                    labelText: isVoucher ? 'عدد الكروت المتاحة' : 'الكمية المتاحة',
                    labelStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () async {
                final qty = editQtyController.text.trim().toIntOrNull();
                final unitVal = editUnitValController.text.trim().toDoubleOrNull() ?? rawUnitVal;
                if (qty != null && qty >= 0) {
                  try {
                    await ref.read(firestoreProvider).collection('company_gifts').doc(gift['id']).update({
                      'availableQuantity': qty,
                      if (isVoucher) 'unitValue': unitVal,
                    }).timeout(const Duration(milliseconds: 500), onTimeout: () {});
                  } catch (_) {}
                  if (context.mounted) Navigator.of(context).pop();
                }
              },
              child: Text('حفظ', style: GoogleFonts.cairo()),
            ),
          ],
        );
      },
    );
  }

  void _deleteGift(String giftId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Text('تأكيد الحذف', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
          content: Text('هل أنت متأكد من رغبتك في حذف هذه الهدية؟', style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('حذف', style: GoogleFonts.cairo()),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        await ref.read(firestoreProvider).collection('company_gifts').doc(giftId).delete().timeout(
          const Duration(seconds: 4),
          onTimeout: () {},
        );
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final firestore = ref.watch(firestoreProvider);
    final isAr = ref.isArabic;
    final strings = AppStrings.of(ref);

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 820),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.card_giftcard, color: colorScheme.onPrimaryContainer, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.giftsTitle,
                            style: GoogleFonts.cairo(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            strings.giftsSubtitle,
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Section 1: Company Selector with Search & Dropdown
                _buildSectionCard(
                  context: context,
                  icon: Icons.business,
                  title: isAr ? 'تحديد الشركة' : 'Select Company',
                  subtitle: isAr ? 'اختر الشركة بالبحث عن طريق الاسم أو كود الشركة (Slug) أو من القائمة' : 'Select company by searching name, slug code, or from dropdown',
                  children: [
                    StreamBuilder<QuerySnapshot>(
                      stream: firestore.collection('companies').snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ));
                        }
                        if (snapshot.hasError) {
                          return Text('خطأ: ${snapshot.error}', style: GoogleFonts.cairo(color: colorScheme.error));
                        }
                        
                        final docs = snapshot.data?.docs ?? [];
                        final companies = docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return {
                            'id': doc.id,
                            'slug': (data['slug'] ?? doc.id).toString().trim(),
                            'name': (data['name'] ?? 'بدون اسم').toString().trim(),
                          };
                        }).toList();

                        if (companies.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 12),
                                Text(
                                  'لا توجد شركات مكوّدة حالياً، يرجى تكويد شركة أولاً',
                                  style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          );
                        }

                        // Filter companies based on search query (by name or by slug code)
                        final searchQuery = _companySearchController.text.trim().toLowerCase();
                        final filteredCompanies = companies.where((c) {
                          if (searchQuery.isEmpty) return true;
                          final name = c['name']!.toLowerCase();
                          final slug = c['slug']!.toLowerCase();
                          return name.contains(searchQuery) || slug.contains(searchQuery);
                        }).toList();

                        // Selected Company Details
                        final selectedCompany = companies.where((c) => c['slug'] == _selectedCompanySlug).firstOrNull;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 1. Search Bar for Typing Search by Name or Code
                            TextField(
                              controller: _companySearchController,
                              style: GoogleFonts.cairo(),
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: 'ابحث باسم الشركة أو كود الشركة (مثال: جهينة أو juhayna)...',
                                hintStyle: GoogleFonts.cairo(
                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                  fontSize: 13,
                                ),
                                prefixIcon: Icon(Icons.search, color: colorScheme.primary),
                                suffixIcon: _companySearchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 20),
                                        tooltip: 'مسح البحث',
                                        onPressed: () {
                                          _companySearchController.clear();
                                          setState(() {});
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 2. Dropdown Selector (with instant search results integration)
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    key: ValueKey('gifts_dropdown_${_selectedCompanySlug}_${filteredCompanies.length}'),
                                    initialValue: filteredCompanies.any((c) => c['slug'] == _selectedCompanySlug)
                                        ? _selectedCompanySlug
                                        : null,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: 'أو اختر من القائمة المنسدلة',
                                      labelStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                                      filled: true,
                                      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    ),
                                    dropdownColor: colorScheme.surfaceContainerHigh,
                                    icon: Icon(Icons.arrow_drop_down, color: colorScheme.onSurfaceVariant),
                                    hint: Text(
                                      filteredCompanies.isEmpty
                                          ? 'لا توجد نتائج مطابقة للبحث'
                                          : 'اختر الشركة (${filteredCompanies.length} شركة متاحة)',
                                      style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                                    ),
                                    items: filteredCompanies.map((comp) {
                                      return DropdownMenuItem<String>(
                                        value: comp['slug'],
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                comp['name']!,
                                                style: GoogleFonts.cairo(
                                                  fontWeight: comp['slug'] == _selectedCompanySlug
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  color: colorScheme.onSurface,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                comp['slug']!,
                                                style: GoogleFonts.cairo(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: colorScheme.onSecondaryContainer,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      if (value != null) {
                                        final match = companies.firstWhere((c) => c['slug'] == value);
                                        setState(() {
                                          _selectedCompanySlug = match['slug'];
                                          _selectedCompanyName = match['name'];
                                        });
                                      }
                                    },
                                  ),
                                ),
                                if (_selectedCompanySlug != null) ...[
                                  const SizedBox(width: 10),
                                  IconButton.filledTonal(
                                    tooltip: 'إلغاء تحديد الشركة',
                                    icon: const Icon(Icons.close, size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _selectedCompanySlug = null;
                                        _selectedCompanyName = null;
                                      });
                                    },
                                    style: IconButton.styleFrom(
                                      backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.7),
                                      foregroundColor: colorScheme.onErrorContainer,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      padding: const EdgeInsets.all(16),
                                    ),
                                  ),
                                ],
                              ],
                            ),

                            // 3. Quick-Pick matching chips when searching or when companies exist
                            if (searchQuery.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              if (filteredCompanies.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    'لا توجد شركة باسم أو كود: "$searchQuery"',
                                    style: GoogleFonts.cairo(color: colorScheme.error, fontSize: 13),
                                  ),
                                )
                              else ...[
                                Text(
                                  'نتائج البحث المطابقة (${filteredCompanies.length}):',
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: filteredCompanies.map((comp) {
                                    final isSelected = comp['slug'] == _selectedCompanySlug;
                                    return InkWell(
                                      onTap: () {
                                        setState(() {
                                          _selectedCompanySlug = comp['slug'];
                                          _selectedCompanyName = comp['name'];
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? colorScheme.primaryContainer
                                              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isSelected
                                                ? colorScheme.primary
                                                : colorScheme.outlineVariant.withValues(alpha: 0.5),
                                            width: isSelected ? 1.5 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isSelected ? Icons.check_circle : Icons.business,
                                              size: 16,
                                              color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              comp['name']!,
                                              style: GoogleFonts.cairo(
                                                fontSize: 13,
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                                color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? colorScheme.primary.withValues(alpha: 0.15)
                                                    : colorScheme.secondaryContainer.withValues(alpha: 0.6),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                comp['slug']!,
                                                style: GoogleFonts.cairo(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: isSelected ? colorScheme.primary : colorScheme.onSecondaryContainer,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ],

                            // 4. Selected Company Highlight Card
                            if (selectedCompany != null) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: colorScheme.primary.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.verified, color: colorScheme.primary, size: 22),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: RichText(
                                        text: TextSpan(
                                          style: GoogleFonts.cairo(color: colorScheme.onSurface, fontSize: 13),
                                          children: [
                                            const TextSpan(text: 'الشركة المحددة حالياً: '),
                                            TextSpan(
                                              text: selectedCompany['name'],
                                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: colorScheme.primary),
                                            ),
                                            const TextSpan(text: '  (كود: '),
                                            TextSpan(
                                              text: selectedCompany['slug'],
                                              style: GoogleFonts.cairo(fontWeight: FontWeight.w600, color: colorScheme.secondary),
                                            ),
                                            const TextSpan(text: ')'),
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
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Section 2: Add Gift / Voucher Form
                if (_selectedCompanySlug != null)
                  _buildSectionCard(
                    context: context,
                    icon: Icons.add_box_rounded,
                    title: 'إضافة هدية أو فواتشر جديد',
                    subtitle: 'قم بإضافة هدية مادية أو فواتشر نقدي (Voucher) لمخزون الشركة',
                    children: [
                      // 1. Gift Type Selector (Segmented Button)
                      Align(
                        alignment: Alignment.centerRight,
                        child: SegmentedButton<String>(
                          segments: [
                            ButtonSegment<String>(
                              value: 'product',
                              icon: const Icon(Icons.inventory_2_outlined),
                              label: Text('منتج مادي (Product)', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                            ),
                            ButtonSegment<String>(
                              value: 'voucher',
                              icon: const Icon(Icons.confirmation_number_outlined),
                              label: Text('فواتشر نقدي (Cash Voucher)', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                            ),
                          ],
                          selected: {_selectedGiftType},
                          onSelectionChanged: (newSet) {
                            setState(() {
                              _selectedGiftType = newSet.first;
                              if (_selectedGiftType == 'voucher' && _voucherUnitValueController.text.isNotEmpty) {
                                final parsed = _voucherUnitValueController.text.toDoubleOrNull();
                                if (parsed != null) _onVoucherDenominationSelected(parsed);
                              }
                            });
                          },
                          style: SegmentedButton.styleFrom(
                            selectedBackgroundColor: colorScheme.primaryContainer,
                            selectedForegroundColor: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (_selectedGiftType == 'voucher') ...[
                        // Quick Voucher Denomination Chips
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Text(
                              'فئات سريعة للكارت الواحد:',
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.primary),
                            ),
                            ...[25, 50, 100, 200, 500].map((val) {
                              final isSel = _voucherUnitValueController.text == val.toString();
                              return ChoiceChip(
                                label: Text('$val ج.م', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                                selected: isSel,
                                selectedColor: colorScheme.primaryContainer,
                                checkmarkColor: colorScheme.onPrimaryContainer,
                                onSelected: (_) => _onVoucherDenominationSelected(val.toDouble()),
                              );
                            }),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Input fields for voucher
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _voucherUnitValueController,
                                focusNode: _voucherUnitValueFocusNode,
                                keyboardType: TextInputType.number,
                                inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                                textInputAction: TextInputAction.next,
                                onSubmitted: (_) => _giftQuantityFocusNode.requestFocus(),
                                onChanged: (val) {
                                  if (_giftNameController.text.isEmpty || _giftNameController.text.startsWith('فواتشر')) {
                                    if (val.trim().isNotEmpty) {
                                      _giftNameController.text = 'فواتشر ${val.trim()} جنيه';
                                    }
                                  }
                                  setState(() {});
                                },
                                style: GoogleFonts.cairo(),
                                decoration: InputDecoration(
                                  labelText: 'قيمة الكارت الواحد (الفئة) *',
                                  hintText: 'مثال: 50',
                                  prefixText: 'ج.م ',
                                  labelStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                                  filled: true,
                                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _giftQuantityController,
                                focusNode: _giftQuantityFocusNode,
                                keyboardType: TextInputType.number,
                                inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                                textInputAction: TextInputAction.next,
                                onSubmitted: (_) => _giftNameFocusNode.requestFocus(),
                                onChanged: (_) => setState(() {}),
                                style: GoogleFonts.cairo(),
                                decoration: InputDecoration(
                                  labelText: 'عدد الكروت (الكمية) *',
                                  hintText: 'مثال: 200',
                                  labelStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                                  filled: true,
                                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 4,
                              child: TextField(
                                controller: _giftNameController,
                                focusNode: _giftNameFocusNode,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _isLoading ? null : _addGift(),
                                style: GoogleFonts.cairo(),
                                decoration: InputDecoration(
                                  labelText: 'اسم الفواتشر (اختياري)',
                                  hintText: 'مثال: فواتشر 50 جنيه',
                                  labelStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                                  filled: true,
                                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: _isLoading ? null : _addGift,
                              icon: _isLoading 
                                  ? const SizedBox(
                                      width: 18, 
                                      height: 18, 
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.add_card_rounded, size: 20),
                              label: Text(
                                _isLoading ? 'جاري...' : 'إضافة الفواتشر',
                                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                              ),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Live Financial Summary
                        Builder(
                          builder: (context) {
                            final qty = _giftQuantityController.text.trim().toIntOrNull() ?? 0;
                            final unitVal = _voucherUnitValueController.text.trim().toDoubleOrNull() ?? 0.0;
                            final totalCash = qty * unitVal;

                            if (qty > 0 && unitVal > 0) {
                              return Container(
                                margin: const EdgeInsets.only(top: 12),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.account_balance_wallet_rounded, size: 20, color: colorScheme.primary),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '💳 ملخص المخزون النقدي: $qty كارت × ${unitVal == unitVal.roundToDouble() ? unitVal.toInt() : unitVal} ج.م = ${totalCash == totalCash.roundToDouble() ? totalCash.toInt() : totalCash} جنيه مصري رصيد مالي متوفر.',
                                        style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ] else ...[
                        // Input fields for standard physical product
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _giftNameController,
                                focusNode: _giftNameFocusNode,
                                textInputAction: TextInputAction.next,
                                onSubmitted: (_) => _giftQuantityFocusNode.requestFocus(),
                                style: GoogleFonts.cairo(),
                                decoration: InputDecoration(
                                  labelText: 'اسم الهدية / المنتج',
                                  hintText: 'مثال: ساعة يد، تيشرت، شامبو 250 مل...',
                                  labelStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                                  hintStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                                  filled: true,
                                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 1,
                              child: TextField(
                                controller: _giftQuantityController,
                                focusNode: _giftQuantityFocusNode,
                                keyboardType: TextInputType.number,
                                inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _isLoading ? null : _addGift(),
                                style: GoogleFonts.cairo(),
                                decoration: InputDecoration(
                                  labelText: 'الكمية (قطع)',
                                  hintText: 'مثال: 10',
                                  labelStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                                  hintStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                                  filled: true,
                                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            FilledButton.icon(
                              onPressed: _isLoading ? null : _addGift,
                              icon: _isLoading 
                                  ? const SizedBox(
                                      width: 18, 
                                      height: 18, 
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.add, size: 20),
                              label: Text(
                                _isLoading ? 'جاري الإضافة...' : 'إضافة هدية',
                                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                              ),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                
                if (_selectedCompanySlug != null) const SizedBox(height: 24),

                // Section 3: Gifts Inventory
                if (_selectedCompanySlug != null)
                  _buildSectionCard(
                    context: context,
                    icon: Icons.inventory_2,
                    title: isAr ? 'مخزون الهدايا والكروت' : 'Gifts & Vouchers Inventory',
                    subtitle: isAr
                        ? 'إدارة وترتيب الهدايا والـ Vouchers المتوفرة (اسحب الكارت لإعادة الترتيب)'
                        : 'Manage & reorder gifts and vouchers (drag card to reorder)',
                    actionBadge: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.drag_indicator_rounded, size: 14, color: colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            strings.reorderBadge,
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    children: [
                      StreamBuilder<QuerySnapshot>(
                        stream: firestore
                            .collection('company_gifts')
                            .where('companySlug', isEqualTo: _selectedCompanySlug?.toLowerCase().trim())
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24.0),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          if (snapshot.hasError) {
                            return Text('خطأ: ${snapshot.error}', style: GoogleFonts.cairo(color: colorScheme.error));
                          }

                          final docs = snapshot.data?.docs ?? [];

                          if (docs.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  children: [
                                    Icon(Icons.inventory_2_outlined, size: 48, color: colorScheme.outlineVariant),
                                    const SizedBox(height: 12),
                                    Text(
                                      isAr
                                          ? 'لا توجد هدايا مضافة لهذه الشركة بعد، يمكنك إضافة هدية من النموذج أعلاه'
                                          : 'No gifts added for this company yet. You can add a gift using the form above',
                                      style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          // Convert docs to CompanyGiftModel and sort by orderIndex ascending
                          final gifts = docs.map((doc) => CompanyGiftModel.fromFirestore(doc)).toList();
                          gifts.sort((a, b) {
                            if (a.orderIndex != b.orderIndex) {
                              return a.orderIndex.compareTo(b.orderIndex);
                            }
                            final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                            final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                            return bTime.compareTo(aTime);
                          });

                          return ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            itemCount: gifts.length,
                            proxyDecorator: (Widget child, int index, Animation<double> animation) {
                              return AnimatedBuilder(
                                animation: animation,
                                builder: (BuildContext context, Widget? child) {
                                  final double animValue = Curves.easeInOut.transform(animation.value);
                                  final double scale = lerpDouble(1.0, 1.025, animValue)!;
                                  final double elevation = lerpDouble(0, 10, animValue)!;
                                  return Transform.scale(
                                    scale: scale,
                                    child: Material(
                                      elevation: elevation,
                                      color: Colors.transparent,
                                      shadowColor: colorScheme.primary.withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(16),
                                      child: child,
                                    ),
                                  );
                                },
                                child: child,
                              );
                            },
                            onReorder: (int oldIndex, int newIndex) async {
                              HapticFeedback.mediumImpact();
                              if (oldIndex < newIndex) {
                                newIndex -= 1;
                              }
                              final movedItem = gifts.removeAt(oldIndex);
                              gifts.insert(newIndex, movedItem);

                              // Save new order to Firestore in batch
                              final firestoreInstance = ref.read(firestoreProvider);
                              try {
                                final batch = firestoreInstance.batch();
                                for (int i = 0; i < gifts.length; i++) {
                                  final docRef = firestoreInstance.collection('company_gifts').doc(gifts[i].id);
                                  batch.update(docRef, {'orderIndex': i});
                                }
                                await batch.commit();

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              strings.orderUpdatedSuccess,
                                              style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                      backgroundColor: colorScheme.primary,
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 2),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  );
                                }
                              } catch (e) {
                                debugPrint('Error updating gift order: $e');
                              }
                            },
                            itemBuilder: (context, index) {
                              final gift = gifts[index];
                              final giftTitle = gift.giftName.isNotEmpty ? gift.giftName : 'بدون اسم';
                              final availableQty = gift.availableQuantity;
                              final totalQty = gift.totalQuantity;
                              final rawUnitVal = gift.unitValue;
                              final isVoucher = gift.isVoucher;
                              final isAvailable = availableQty > 0;
                              final totalCash = gift.totalMonetaryValue;
                              final availCash = gift.availableMonetaryValue;

                              return Padding(
                                key: ValueKey(gift.id),
                                padding: const EdgeInsets.only(bottom: 12),
                                child: ReorderableDelayedDragStartListener(
                                  index: index,
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: isVoucher
                                          ? colorScheme.surfaceContainerHigh.withValues(alpha: 0.6)
                                          : colorScheme.surface,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isVoucher
                                            ? colorScheme.primary.withValues(alpha: 0.3)
                                            : colorScheme.outlineVariant.withValues(alpha: 0.3),
                                        width: isVoucher ? 1.5 : 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: colorScheme.shadow.withValues(alpha: 0.03),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        // 1. Dedicated Drag Handle with Tooltip and Ripple
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: Tooltip(
                                            message: strings.dragToReorderHint,
                                            child: MouseRegion(
                                              cursor: SystemMouseCursors.grab,
                                              child: Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: Icon(
                                                  Icons.drag_indicator_rounded,
                                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                                  size: 20,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // 2. Gift / Voucher Type Icon
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: isVoucher
                                                ? colorScheme.primaryContainer.withValues(alpha: 0.7)
                                                : colorScheme.secondaryContainer.withValues(alpha: 0.5),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard,
                                            color: isVoucher ? colorScheme.primary : colorScheme.onSecondaryContainer,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        // 3. Gift Metadata & Quantities
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      giftTitle,
                                                      style: GoogleFonts.cairo(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 16,
                                                        color: colorScheme.onSurface,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (isVoucher) ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: colorScheme.primaryContainer,
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(Icons.payments_rounded, size: 13, color: colorScheme.primary),
                                                          const SizedBox(width: 4),
                                                          Text(
                                                            'فئة ${rawUnitVal == rawUnitVal.roundToDouble() ? rawUnitVal.toInt() : rawUnitVal} ج.م',
                                                            style: GoogleFonts.cairo(
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.bold,
                                                              color: colorScheme.onPrimaryContainer,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 4,
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: colorScheme.secondaryContainer,
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Text(
                                                      isVoucher 
                                                          ? 'الإجمالي: $totalQty كارت (${totalCash.toInt()} ج.م)'
                                                          : 'الإجمالي: $totalQty',
                                                      style: GoogleFonts.cairo(
                                                        fontSize: 12,
                                                        color: colorScheme.onSecondaryContainer,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                  if (gift.batchCount > 1) ...[
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.blue.withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(Icons.layers_rounded, size: 12, color: Colors.blue[800]),
                                                          const SizedBox(width: 4),
                                                          Text(
                                                            '${gift.batchCount} دفعات توريد',
                                                            style: GoogleFonts.cairo(
                                                              fontSize: 11,
                                                              color: Colors.blue[900],
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                  if (totalQty - availableQty > 0) ...[
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.orange.withValues(alpha: 0.2),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Text(
                                                        isVoucher
                                                            ? 'مخصص بالحملات: ${totalQty - availableQty} كارت'
                                                            : 'مخصص بالحملات: ${totalQty - availableQty}',
                                                        style: GoogleFonts.cairo(
                                                          fontSize: 12,
                                                          color: Colors.orange.shade900,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: isAvailable
                                                          ? Colors.green.withValues(alpha: 0.2)
                                                          : colorScheme.errorContainer,
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Text(
                                                      isVoucher
                                                          ? 'المتاح: $availableQty كارت (${availCash.toInt()} ج.م)'
                                                          : 'المتاح: $availableQty',
                                                      style: GoogleFonts.cairo(
                                                        fontSize: 12,
                                                        color: isAvailable
                                                            ? Colors.green[800]
                                                            : colorScheme.onErrorContainer,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                  if (gift.isLowStock) ...[
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.red.withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          const Icon(Icons.warning_amber_rounded, size: 12, color: Colors.red),
                                                          const SizedBox(width: 4),
                                                          Text(
                                                            'مخزون منخفض',
                                                            style: GoogleFonts.cairo(
                                                              fontSize: 11,
                                                              color: Colors.red[900],
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  IconButton.filledTonal(
                                                    icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                                                    tooltip: 'توريد دفعة جديدة للمخزون (Supply Batch)',
                                                    onPressed: () => _showAddSupplyBatchDialog(gift),
                                                    style: IconButton.styleFrom(
                                                      backgroundColor: Colors.green.withValues(alpha: 0.15),
                                                      foregroundColor: Colors.green[800],
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  IconButton.filledTonal(
                                                    icon: const Icon(Icons.tune_rounded, size: 18),
                                                    tooltip: 'تسوية مخزنية (جرد دوري / هالك / تعديل)',
                                                    onPressed: () => _showStockAdjustmentDialog(gift),
                                                    style: IconButton.styleFrom(
                                                      backgroundColor: Colors.amber.withValues(alpha: 0.15),
                                                      foregroundColor: Colors.amber[900],
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  IconButton.filledTonal(
                                                    icon: const Icon(Icons.history_edu_rounded, size: 18),
                                                    tooltip: 'سجل التوريدات وحركات المخزون',
                                                    onPressed: () => _showBatchesAndMovementLedgerDialog(gift),
                                                    style: IconButton.styleFrom(
                                                      backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.7),
                                                      foregroundColor: colorScheme.primary,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  IconButton.filledTonal(
                                                    icon: const Icon(Icons.edit, size: 18),
                                                    tooltip: 'تعديل بيانات الهدية',
                                                    onPressed: () => _showEditGiftDialog({
                                                      'id': gift.id,
                                                      'giftName': gift.giftName,
                                                      'totalQuantity': gift.totalQuantity,
                                                      'availableQuantity': gift.availableQuantity,
                                                      'giftType': gift.giftType,
                                                      'unitValue': gift.unitValue,
                                                    }),
                                                    style: IconButton.styleFrom(
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  IconButton.filledTonal(
                                                    icon: const Icon(Icons.delete, size: 18),
                                                    tooltip: 'حذف الهدية',
                                                    onPressed: () => _deleteGift(gift.id),
                                                    style: IconButton.styleFrom(
                                                      backgroundColor: colorScheme.errorContainer,
                                                      foregroundColor: colorScheme.onErrorContainer,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                                  ),
                                );
                            },
                          );
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
