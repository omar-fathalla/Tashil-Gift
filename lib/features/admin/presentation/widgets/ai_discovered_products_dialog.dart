import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/localization/locale_provider.dart';
import '../../../../core/services/ai_product_discovery_service.dart';
import '../../../../core/utils/arabic_numbers_utils.dart';

class AiDiscoveredProductsDialog extends ConsumerStatefulWidget {
  final String companySlug;
  final String companyName;
  final List<DiscoveredProductItem> discoveredProducts;
  final VoidCallback? onSavedSuccessfully;

  const AiDiscoveredProductsDialog({
    super.key,
    required this.companySlug,
    required this.companyName,
    required this.discoveredProducts,
    this.onSavedSuccessfully,
  });

  static Future<bool?> show({
    required BuildContext context,
    required String companySlug,
    required String companyName,
    required List<DiscoveredProductItem> discoveredProducts,
    VoidCallback? onSavedSuccessfully,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AiDiscoveredProductsDialog(
        companySlug: companySlug,
        companyName: companyName,
        discoveredProducts: discoveredProducts,
        onSavedSuccessfully: onSavedSuccessfully,
      ),
    );
  }

  @override
  ConsumerState<AiDiscoveredProductsDialog> createState() => _AiDiscoveredProductsDialogState();
}

class _AiDiscoveredProductsDialogState extends ConsumerState<AiDiscoveredProductsDialog> {
  late List<DiscoveredProductItem> _items;
  bool _isSaving = false;
  int _savedCount = 0;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.discoveredProducts);
  }

  void _toggleAll(bool select) {
    setState(() {
      _items = _items.map((item) => item.copyWith(isSelected: select)).toList();
    });
  }

  void _toggleItem(int index) {
    setState(() {
      _items[index] = _items[index].copyWith(isSelected: !_items[index].isSelected);
    });
  }

  Future<void> _editItem(int index) async {
    final item = _items[index];
    final nameCtrl = TextEditingController(text: item.productName);
    final barcodeCtrl = TextEditingController(text: item.barcode);
    final categoryCtrl = TextEditingController(text: item.category);
    final sizeCtrl = TextEditingController(text: item.unitSize);
    final priceCtrl = TextEditingController(text: item.referencePrice != null ? item.referencePrice.toString() : '');

    final updated = await showDialog<DiscoveredProductItem>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: Colors.indigo, size: 24),
            const SizedBox(width: 8),
            Text(
              'تعديل بيانات الصنف',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم الصنف',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.shopping_bag_outlined),
                ),
                style: GoogleFonts.cairo(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: barcodeCtrl,
                decoration: const InputDecoration(
                  labelText: 'الباركود',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.qr_code_rounded),
                ),
                style: GoogleFonts.cairo(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: categoryCtrl,
                      decoration: const InputDecoration(
                        labelText: 'الفئة',
                        border: OutlineInputBorder(),
                      ),
                      style: GoogleFonts.cairo(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: sizeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'الحجم/العبوة',
                        border: OutlineInputBorder(),
                      ),
                      style: GoogleFonts.cairo(fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'السعر المرجعي (ج.م / د.إ)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money_rounded),
                ),
                style: GoogleFonts.cairo(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final double? price = double.tryParse(priceCtrl.text.toEnglishDigits());
              Navigator.pop(
                ctx,
                item.copyWith(
                  productName: nameCtrl.text.trim(),
                  barcode: barcodeCtrl.text.trim(),
                  category: categoryCtrl.text.trim(),
                  unitSize: sizeCtrl.text.trim(),
                  referencePrice: price,
                ),
              );
            },
            child: const Text('تحديث'),
          ),
        ],
      ),
    );

    if (updated != null && mounted) {
      setState(() {
        _items[index] = updated;
      });
    }
  }

  Future<void> _approveAndSave() async {
    final selectedItems = _items.where((i) => i.isSelected).toList();
    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تحديد صنف واحد على الأقل للاعتماد')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _totalCount = selectedItems.length;
      _savedCount = 0;
    });

    try {
      final discoveryService = ref.read(aiProductDiscoveryServiceProvider);
      final totalSaved = await discoveryService.approveAndSaveDiscoveredProducts(
        companySlug: widget.companySlug,
        companyName: widget.companyName,
        approvedItems: selectedItems,
        onProgress: (saved, total) {
          if (mounted) {
            setState(() {
              _savedCount = saved;
              _totalCount = total;
            });
          }
        },
      );

      if (mounted) {
        widget.onSavedSuccessfully?.call();
        Navigator.pop(context, true);

        final strings = AppStrings.of(ref);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    strings.productsSavedSuccess(totalSaved, widget.companyName),
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء حفظ الأصناف: $e'),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = AppStrings.of(ref);
    final isAr = ref.isArabic;
    final selectedCount = _items.where((i) => i.isSelected).length;
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: colorScheme.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 32,
        vertical: isMobile ? 16 : 24,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 780),
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header with AI Icon
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.indigo.shade600, Colors.purple.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.indigo.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.aiProductDiscoveryTitle,
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 15 : 18,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${isAr ? "الشركة:" : "Company:"} ${widget.companyName} (${widget.companySlug}) • ${_items.length} ${isAr ? "صنف مكتشف" : "items"}',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _isSaving ? null : () => Navigator.pop(context, false),
                  tooltip: strings.close,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 2. Explanatory Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.indigo.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Colors.indigo.shade800, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      strings.aiProductDiscoverySubtitle,
                      style: GoogleFonts.cairo(
                        fontSize: 11.5,
                        color: Colors.indigo.shade900,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 3. Toolbar (Select all / Deselect all / Selected count)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.select_all_rounded, size: 18),
                      label: Text(strings.selectAllProducts, style: GoogleFonts.cairo(fontSize: 12)),
                      onPressed: _isSaving ? null : () => _toggleAll(true),
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      icon: const Icon(Icons.deselect_rounded, size: 18),
                      label: Text(strings.deselectAllProducts, style: GoogleFonts.cairo(fontSize: 12)),
                      onPressed: _isSaving ? null : () => _toggleAll(false),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${isAr ? "المحدد للاعتماد:" : "Selected:"} $selectedCount / ${_items.length}',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),

            // 4. Products List
            Expanded(
              child: _items.isEmpty
                  ? Center(
                      child: Text(
                        strings.noNewProductsDiscovered,
                        style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (ctx, idx) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return Container(
                          decoration: BoxDecoration(
                            color: item.isSelected
                                ? colorScheme.primaryContainer.withValues(alpha: 0.15)
                                : colorScheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: item.isSelected
                                  ? colorScheme.primary.withValues(alpha: 0.5)
                                  : colorScheme.outlineVariant.withValues(alpha: 0.4),
                              width: item.isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: _isSaving ? null : () => _toggleItem(index),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(
                                children: [
                                  // Checkbox
                                  Checkbox(
                                    value: item.isSelected,
                                    onChanged: _isSaving ? null : (v) => _toggleItem(index),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                  ),
                                  const SizedBox(width: 4),

                                  // Product Info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item.productName,
                                                style: GoogleFonts.cairo(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: colorScheme.onSurface,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (item.referencePrice != null)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.shade50,
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: Colors.green.shade200),
                                                ),
                                                child: Text(
                                                  '${item.referencePrice!.toStringAsFixed(1)} ج.م',
                                                  style: GoogleFonts.cairo(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.green.shade800,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),

                                        // Badges: Barcode, Category, Size, Invoices Count, AI Reason
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            if (item.barcode.isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: colorScheme.surfaceContainerHighest,
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  'Barcode: ${item.barcode}',
                                                  style: const TextStyle(
                                                    fontSize: 10.5,
                                                    fontFamily: 'monospace',
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ),
                                            if (item.category.isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.shade50,
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  item.category,
                                                  style: GoogleFonts.cairo(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.blue.shade800,
                                                  ),
                                                ),
                                              ),
                                            if (item.unitSize.isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange.shade50,
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  item.unitSize,
                                                  style: GoogleFonts.cairo(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.orange.shade900,
                                                  ),
                                                ),
                                              ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.purple.shade50,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '${strings.appearedInInvoices}: ${item.invoiceFrequency}',
                                                style: GoogleFonts.cairo(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.purple.shade800,
                                                ),
                                              ),
                                            ),
                                            if (item.relevanceReason.isNotEmpty)
                                              Text(
                                                '• ${item.relevanceReason}',
                                                style: GoogleFonts.cairo(
                                                  fontSize: 10,
                                                  color: colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Edit Button
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    onPressed: _isSaving ? null : () => _editItem(index),
                                    tooltip: 'تعديل بيانات الصنف',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 14),

            // 5. Saving Progress Bar if active
            if (_isSaving) ...[
              LinearProgressIndicator(
                value: _totalCount > 0 ? (_savedCount / _totalCount) : null,
                borderRadius: BorderRadius.circular(6),
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
              const SizedBox(height: 6),
              Text(
                'جاري الحفظ والربط مع فايربيز ($_savedCount من $_totalCount)...',
                style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.primary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],

            // 6. Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _isSaving ? null : () => Navigator.pop(context, false),
                  child: Text(strings.cancel, style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.cloud_upload_rounded, size: 18),
                  label: Text(
                    strings.approveAndSaveToCatalog,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade800,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onPressed: _isSaving || selectedCount == 0 ? null : _approveAndSave,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
