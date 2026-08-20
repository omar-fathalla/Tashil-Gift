import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:csv/csv.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/services/company_gifts_service.dart';
import '../../../core/constants/country_currency_config.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../admin/domain/event_model.dart';

enum DateFilterType { all, today, last7Days, thisMonth, custom }

class InvoicesLogScreen extends ConsumerStatefulWidget {
  final String? lockedCompanySlug;
  final String? lockedCompanyName;
  final String? initialEventId;
  final bool isEmbedded;

  const InvoicesLogScreen({
    super.key,
    this.lockedCompanySlug,
    this.lockedCompanyName,
    this.initialEventId,
    this.isEmbedded = false,
  });

  @override
  ConsumerState<InvoicesLogScreen> createState() => _InvoicesLogScreenState();
}

class _InvoicesLogScreenState extends ConsumerState<InvoicesLogScreen> {
  static const int _pageSize = 20;
  int _displayedItemCount = _pageSize;
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;

  final TextEditingController _searchController = TextEditingController();
  String _selectedCampaignId = 'all';
  String _selectedCompanySlug = 'all';
  DateFilterType _dateFilter = DateFilterType.all;
  DateTimeRange? _customDateRange;
  final Set<String> _expandedDocIds = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.initialEventId != null && widget.initialEventId!.isNotEmpty) {
      _selectedCampaignId = widget.initialEventId!;
    }
    if (widget.lockedCompanySlug != null && widget.lockedCompanySlug!.isNotEmpty) {
      _selectedCompanySlug = widget.lockedCompanySlug!;
    }
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant InvoicesLogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialEventId != oldWidget.initialEventId &&
        widget.initialEventId != null &&
        widget.initialEventId!.isNotEmpty) {
      setState(() {
        _selectedCampaignId = widget.initialEventId!;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isLoadingMore) return;
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _loadMore() {
    if (_isLoadingMore) return;
    setState(() {
      _isLoadingMore = true;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _displayedItemCount += _pageSize;
          _isLoadingMore = false;
        });
      }
    });
  }

  void _resetPagination() {
    setState(() {
      _displayedItemCount = _pageSize;
      _isLoadingMore = false;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _toggleExpand(String docId) {
    setState(() {
      if (_expandedDocIds.contains(docId)) {
        _expandedDocIds.remove(docId);
      } else {
        _expandedDocIds.add(docId);
      }
    });
  }

  void _copyToClipboard(String text, BuildContext context, AppStrings strings) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${strings.receiptNumberCopied}: $text'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickCustomDateRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _customDateRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
      builder: (context, child) {
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: theme.colorScheme.primary,
              onPrimary: theme.colorScheme.onPrimary,
              surface: theme.colorScheme.surface,
              onSurface: theme.colorScheme.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _dateFilter = DateFilterType.custom;
      });
      _resetPagination();
    }
  }

  void _resetFilters() {
    setState(() {
      _searchController.clear();
      _selectedCampaignId = 'all';
      _selectedCompanySlug = widget.lockedCompanySlug ?? 'all';
      _dateFilter = DateFilterType.all;
      _customDateRange = null;
    });
    _resetPagination();
  }

  bool _passesDateFilter(DateTime? date) {
    if (_dateFilter == DateFilterType.all || date == null) return true;
    final now = DateTime.now();

    switch (_dateFilter) {
      case DateFilterType.today:
        return date.year == now.year && date.month == now.month && date.day == now.day;
      case DateFilterType.last7Days:
        final sevenDaysAgo = now.subtract(const Duration(days: 7));
        return date.isAfter(sevenDaysAgo) && date.isBefore(now.add(const Duration(days: 1)));
      case DateFilterType.thisMonth:
        return date.year == now.year && date.month == now.month;
      case DateFilterType.custom:
        if (_customDateRange == null) return true;
        final start = DateTime(_customDateRange!.start.year, _customDateRange!.start.month, _customDateRange!.start.day);
        final end = DateTime(_customDateRange!.end.year, _customDateRange!.end.month, _customDateRange!.end.day, 23, 59, 59);
        return date.isAfter(start.subtract(const Duration(seconds: 1))) && date.isBefore(end.add(const Duration(seconds: 1)));
      case DateFilterType.all:
        return true;
    }
  }

  Future<void> _exportInvoicesToCsv(List<Map<String, dynamic>> filteredInvoices, AppStrings strings) async {
    if (filteredInvoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.noMatchingInvoices),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final headers = [
      strings.receiptNumberCol,
      strings.receiptDateCol,
      strings.eventsTitle,
      strings.companyField,
      strings.retailChainField,
      strings.branchField,
      strings.receiptAmountCol,
      strings.productNameCol,
      strings.barcodeCol,
      strings.quantityCol,
      strings.unitPriceCol,
      strings.totalPriceCol,
      strings.itemCategoryCol,
      strings.customerNameField,
      strings.customerPhoneField,
    ];

    final rows = <List<dynamic>>[headers];

    for (final inv in filteredInvoices) {
      final receiptNumber = inv['receipt_number'] ?? 'N/A';
      final receiptDate = inv['formattedDate'] ?? 'N/A';
      final eventName = inv['eventName'] ?? 'N/A';
      final company = inv['targetCompany'] ?? 'N/A';
      final store = inv['store_chain_detected'] ?? inv['retail_chain_name'] ?? 'N/A';
      final branch = inv['branch_detected'] ?? '';
      final total = inv['target_company_total'] ?? inv['total_value'] ?? 0;
      final custName = inv['customerName'] ?? '';
      final custPhone = inv['customerPhone'] ?? '';

      final products = (inv['extracted_products'] as List?) ?? [];
      if (products.isEmpty) {
        rows.add([
          receiptNumber,
          receiptDate,
          eventName,
          company,
          store,
          branch,
          total,
          'N/A',
          'N/A',
          'N/A',
          'N/A',
          'N/A',
          'N/A',
          custName,
          custPhone,
        ]);
      } else {
        for (final p in products) {
          final pMap = p is Map ? Map<String, dynamic>.from(p) : <String, dynamic>{};
          final pName = pMap['name'] ?? 'N/A';
          final pBarcode = pMap['barcode'] ?? 'N/A';
          final pQty = pMap['quantity'] ?? 1;
          final pPrice = pMap['price'] ?? 0;
          final pTotal = pMap['totalPrice'] ?? ((pPrice is num ? pPrice : 0) * (pQty is num ? pQty : 1));
          final isPromo = pMap['isTargetCompany'] == true;

          rows.add([
            receiptNumber,
            receiptDate,
            eventName,
            company,
            store,
            branch,
            total,
            pName,
            pBarcode,
            pQty,
            pPrice,
            pTotal,
            isPromo ? strings.includedInPromo : strings.generalItem,
            custName,
            custPhone,
          ]);
        }
      }
    }

    final csvData = const ListToCsvConverter().convert(rows);
    final utf8Bom = [0xEF, 0xBB, 0xBF];
    final bytes = Uint8List.fromList([...utf8Bom, ...utf8.encode(csvData)]);

    if (kIsWeb) {
      final base64Csv = base64Encode(bytes);
      final url = 'data:text/csv;charset=utf-8;base64,$base64Csv';
      await launchUrl(Uri.parse(url));
    } else {
      Clipboard.setData(ClipboardData(text: csvData));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${strings.exportCsvBtn}: تم نسخ البيانات بصيغة CSV للحافظة بنجاح'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Universal image builder supporting both Firebase Storage (HTTPS) and Base64 Data URIs
  Widget _buildReceiptImage(
    String imageUrl, {
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
  }) {
    if (imageUrl.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: Colors.grey.shade100,
        child: const Center(
          child: Icon(Icons.receipt_long_rounded, size: 28, color: Colors.grey),
        ),
      );
    }

    // Handle Base64 Data URI or raw base64 string
    if (imageUrl.startsWith('data:image') || imageUrl.contains(';base64,')) {
      try {
        final base64String = imageUrl.contains(',') ? imageUrl.split(',').last : imageUrl;
        final bytes = base64Decode(base64String.trim());
        return Image.memory(
          bytes,
          fit: fit,
          width: width,
          height: height,
          errorBuilder: (context, error, stack) => errorBuilder != null
              ? errorBuilder(context, error, stack)
              : Container(
                  width: width,
                  height: height,
                  color: Colors.grey.shade100,
                  child: const Center(child: Icon(Icons.broken_image_rounded, size: 28, color: Colors.grey)),
                ),
        );
      } catch (_) {
        return Container(
          width: width,
          height: height,
          color: Colors.grey.shade100,
          child: const Center(child: Icon(Icons.broken_image_rounded, size: 28, color: Colors.grey)),
        );
      }
    }

    // Handle Network URL (Firebase Storage / HTTP / HTTPS)
    return Image.network(
      imageUrl,
      fit: fit,
      width: width,
      height: height,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => errorBuilder != null
          ? errorBuilder(context, error, stackTrace)
          : Container(
              width: width,
              height: height,
              color: Colors.grey.shade100,
              child: const Center(child: Icon(Icons.broken_image_rounded, size: 28, color: Colors.grey)),
            ),
    );
  }

  Future<void> _confirmAndDeleteInvoice({
    required BuildContext context,
    required String docId,
    required String receiptNumber,
    required dynamic totalValue,
    required String currencySymbol,
    required String? storagePath,
    required String imageUrl,
    required AppStrings strings,
    required ColorScheme colorScheme,
  }) async {
    // 1. Guard check: only true admin can delete
    final isAdmin = ref.read(isAdminProvider);
    if (!isAdmin || widget.isEmbedded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.unauthorizedError),
          backgroundColor: colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.delete_forever_rounded,
              color: colorScheme.error,
              size: 32,
            ),
          ),
          title: Text(
            strings.confirmDeleteInvoiceTitle,
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '#$receiptNumber',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      '$totalValue $currencySymbol',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                strings.confirmDeleteInvoiceMsg,
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(strings.cancelBtn, style: GoogleFonts.cairo()),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(dialogCtx, true),
              icon: const Icon(Icons.delete_rounded, size: 18),
              label: Text(
                strings.deleteInvoiceBtn,
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(this.context);

    // Show in-progress feedback
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(strings.deletingInvoiceProgress)),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final firestore = ref.read(firestoreProvider);

      // 1. Fetch document data to replenish campaign stock if prizes were claimed
      try {
        final docSnap = await firestore.collection('receipts_transactions').doc(docId).get();
        if (docSnap.exists) {
          final data = docSnap.data()!;
          final eventId = (data['event_id'] ?? data['eventId'] ?? '').toString().trim();
          final branchId = (data['branch_id'] ?? data['branchId'] ?? '').toString().trim();
          final claimedGiftsRaw = data['claimed_gifts'] as List<dynamic>?;
          final giftsService = ref.read(companyGiftsServiceProvider);

          if (eventId.isNotEmpty) {
            if (claimedGiftsRaw != null && claimedGiftsRaw.isNotEmpty) {
              for (final raw in claimedGiftsRaw) {
                if (raw is Map<String, dynamic>) {
                  final giftId = (raw['giftId'] ?? '').toString().trim();
                  final giftName = (raw['giftName'] ?? '').toString().trim();
                  final quantity = (raw['quantity'] as num?)?.toInt() ?? 1;
                  final unitVal = (raw['unitValue'] as num?)?.toDouble() ?? 0.0;
                  final isVoucher = raw['isVoucher'] == true || unitVal > 0;

                  await giftsService.replenishCampaignPrize(
                    eventId,
                    giftId.isNotEmpty ? giftId : giftName,
                    branchId: branchId.isNotEmpty ? branchId : null,
                    count: quantity,
                    unitValue: unitVal,
                    isVoucher: isVoucher,
                  );
                }
              }
            } else {
              // Legacy fallback for records created without claimed_gifts list
              final prizesWon = (data['prizes_won'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
              final prizeWon = (data['prize_won'] ?? '').toString().trim();

              if (prizesWon.isNotEmpty) {
                for (final pName in prizesWon) {
                  await giftsService.replenishCampaignPrize(
                    eventId,
                    pName,
                    branchId: branchId.isNotEmpty ? branchId : null,
                    count: 1,
                  );
                }
              } else if (prizeWon.isNotEmpty) {
                await giftsService.replenishCampaignPrize(
                  eventId,
                  prizeWon,
                  branchId: branchId.isNotEmpty ? branchId : null,
                  count: 1,
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Notice: Error replenishing stock on invoice delete: $e');
      }

      // 2. Delete document from Firestore
      await firestore.collection('receipts_transactions').doc(docId).delete();

      // 3. Delete file from Storage if applicable
      try {
        final storage = ref.read(firebaseStorageProvider);
        if (storagePath != null && storagePath.isNotEmpty) {
          await storage.ref().child(storagePath).delete();
        } else if (imageUrl.isNotEmpty &&
            imageUrl.startsWith('http') &&
            imageUrl.contains('firebasestorage.googleapis.com')) {
          await storage.refFromURL(imageUrl).delete();
        }
      } catch (e) {
        debugPrint('Notice: Storage image deletion ignored or already removed: $e');
      }

      if (!mounted) return;

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  strings.invoiceDeletedSuccess,
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
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text(strings.invoiceDeletedError)),
            ],
          ),
          backgroundColor: colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showImagePreviewDialog({
    required BuildContext context,
    required String imageUrl,
    required String receiptNumber,
    required String store,
    required dynamic totalValue,
    required String date,
    required String currencySymbol,
    required ColorScheme colorScheme,
    required AppStrings strings,
    String? docId,
    String? storagePath,
    bool canDelete = false,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        backgroundColor: colorScheme.surface,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 780),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Header Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.receipt_long_rounded, color: colorScheme.onPrimaryContainer, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '#$receiptNumber',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => _copyToClipboard(receiptNumber, context, strings),
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Icon(Icons.copy_rounded, size: 14, color: colorScheme.primary),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            store.isNotEmpty ? '$store • $date' : date,
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '$totalValue $currencySymbol',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (canDelete && docId != null) ...[
                      IconButton.filledTonal(
                        icon: Icon(Icons.delete_outline_rounded, size: 20, color: colorScheme.error),
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.35),
                          foregroundColor: colorScheme.error,
                        ),
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _confirmAndDeleteInvoice(
                            context: context,
                            docId: docId,
                            receiptNumber: receiptNumber,
                            totalValue: totalValue,
                            currencySymbol: currencySymbol,
                            storagePath: storagePath,
                            imageUrl: imageUrl,
                            strings: strings,
                            colorScheme: colorScheme,
                          );
                        },
                        tooltip: strings.deleteInvoiceTooltip,
                      ),
                      const SizedBox(width: 8),
                    ],
                    IconButton.filledTonal(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(dialogContext),
                      tooltip: strings.cancelBtn,
                    ),
                  ],
                ),
              ),

              // 2. Body: Interactive Image Viewer or No-Image Fallback
              Flexible(
                child: imageUrl.isNotEmpty
                    ? Container(
                        color: Colors.black.withValues(alpha: 0.04),
                        child: Stack(
                          children: [
                            InteractiveViewer(
                              panEnabled: true,
                              boundaryMargin: const EdgeInsets.all(20),
                              minScale: 0.5,
                              maxScale: 5.0,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: _buildReceiptImage(
                                    imageUrl,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stack) => Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(32.0),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.broken_image_rounded, size: 56, color: colorScheme.error),
                                            const SizedBox(height: 12),
                                            Text(
                                              'تعذر تحميل الصورة الأصلية',
                                              style: TextStyle(fontSize: 14, color: colorScheme.error, fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'قد يكون السبب قيود المتصفح أو انقطاع الاتصال',
                                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                              textAlign: TextAlign.center,
                                            ),
                                            if (imageUrl.startsWith('http')) ...[
                                              const SizedBox(height: 14),
                                              FilledButton.tonalIcon(
                                                onPressed: () => launchUrl(Uri.parse(imageUrl)),
                                                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                                                label: const Text('فتح رابط الصورة مباشرة في المتصفح', style: TextStyle(fontSize: 12)),
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
                            // Zoom Tip Badge
                            Positioned(
                              bottom: 12,
                              left: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.pinch_rounded, size: 14, color: Colors.white),
                                    SizedBox(width: 6),
                                    Text(
                                      'يمكنك التكبير والتحريك (Pinch / Pan to zoom)',
                                      style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.no_photography_outlined, size: 48, color: colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'لا توجد صورة مسجلة لهذه الفاتورة',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'تم تسجيل المعاملة بنجاح، ولكن لم يتم إرفاق ملف صورة في هذا السجل.',
                                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
              ),

              // 3. Footer Action Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
                ),
                child: Row(
                  children: [
                    if (imageUrl.startsWith('http')) ...[
                      FilledButton.tonalIcon(
                        onPressed: () => launchUrl(Uri.parse(imageUrl)),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('فتح بالحجم الكامل', style: TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    OutlinedButton.icon(
                      onPressed: () => _copyToClipboard(receiptNumber, context, strings),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: Text(strings.copyCodeBtn, style: const TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(strings.cancelBtn, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    FirebaseFirestore? firestore;
    try {
      firestore = ref.watch(firestoreProvider);
    } catch (_) {
      firestore = null;
    }
    final activeCountry = ref.watch(activeCountryProvider);
    final isAr = ref.isArabic;
    final strings = AppStrings.of(ref);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    if (firestore == null) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: _buildInvoicesView(
          context: context,
          activeCountry: activeCountry,
          isAr: isAr,
          strings: strings,
          theme: theme,
          colorScheme: colorScheme,
          textTheme: textTheme,
          eventsMap: const {},
          rawDocs: const [],
        ),
      );
    }

    final activeFirestore = firestore;

    // Clean M3 Scaffold with NO duplicate AppBar
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: StreamBuilder<QuerySnapshot>(
        stream: activeFirestore.collection('events').snapshots(),
        builder: (context, eventsSnapshot) {
          final eventDocs = eventsSnapshot.data?.docs ?? [];
          final eventsMap = <String, EventModel>{};
          for (final doc in eventDocs) {
            try {
              eventsMap[doc.id] = EventModel.fromFirestore(doc);
            } catch (_) {}
          }

          return StreamBuilder<QuerySnapshot>(
            stream: activeFirestore.collection('receipts_transactions').snapshots(),
            builder: (context, transactionsSnapshot) {
              if (transactionsSnapshot.hasError) {
                return Center(child: Text('${strings.error}: ${transactionsSnapshot.error}'));
              }

              if (!transactionsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final rawDocs = transactionsSnapshot.data?.docs ?? [];
              return _buildInvoicesView(
                context: context,
                activeCountry: activeCountry,
                isAr: isAr,
                strings: strings,
                theme: theme,
                colorScheme: colorScheme,
                textTheme: textTheme,
                eventsMap: eventsMap,
                rawDocs: rawDocs,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildInvoicesView({
    required BuildContext context,
    required CountryCurrency activeCountry,
    required bool isAr,
    required AppStrings strings,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required Map<String, EventModel> eventsMap,
    required List<QueryDocumentSnapshot> rawDocs,
  }) {

              // Map documents to enriched representations
              final allInvoices = rawDocs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final campaignId = data['campaignId']?.toString() ?? '';
                final event = eventsMap[campaignId];
                final eventName = event?.eventName ?? (data['campaignName']?.toString() ?? (isAr ? 'حملة عامة' : 'General Campaign'));

                DateTime? date;
                if (data['timestamp'] is Timestamp) {
                  date = (data['timestamp'] as Timestamp).toDate();
                } else if (data['timestamp'] is String) {
                  date = DateTime.tryParse(data['timestamp']);
                }

                final formattedDate = date != null ? DateFormat('yyyy-MM-dd HH:mm').format(date) : (data['receipt_date']?.toString() ?? 'N/A');

                return {
                  'id': doc.id,
                  ...data,
                  'date': date,
                  'formattedDate': formattedDate,
                  'eventName': eventName,
                  'campaignId': campaignId,
                };
              }).toList()
                ..sort((a, b) {
                  final tsA = a['date'] as DateTime?;
                  final tsB = b['date'] as DateTime?;
                  if (tsA == null) return 1;
                  if (tsB == null) return -1;
                  return tsB.compareTo(tsA);
                });

              // Apply Filters
              final query = _searchController.text.trim().toLowerCase();
              final filteredInvoices = allInvoices.where((inv) {
                // 1. Campaign Filter
                if (_selectedCampaignId != 'all' && inv['campaignId'] != _selectedCampaignId) {
                  return false;
                }

                // 2. Company Filter
                if (_selectedCompanySlug != 'all') {
                  final slug = (inv['companySlug'] ?? '').toString().toLowerCase();
                  final target = (inv['targetCompany'] ?? '').toString().toLowerCase();
                  if (slug != _selectedCompanySlug.toLowerCase() && !target.contains(_selectedCompanySlug.toLowerCase())) {
                    return false;
                  }
                }

                // 3. Date Filter
                if (!_passesDateFilter(inv['date'] as DateTime?)) {
                  return false;
                }

                // 4. Search Query (Receipt Number, Branch, Store, Customer)
                if (query.isNotEmpty) {
                  final receiptNum = (inv['receipt_number'] ?? '').toString().toLowerCase();
                  final store = (inv['store_chain_detected'] ?? inv['retail_chain_name'] ?? '').toString().toLowerCase();
                  final branch = (inv['branch_detected'] ?? '').toString().toLowerCase();
                  final eventName = (inv['eventName'] ?? '').toString().toLowerCase();
                  final targetComp = (inv['targetCompany'] ?? '').toString().toLowerCase();
                  final custName = (inv['customerName'] ?? '').toString().toLowerCase();
                  final custPhone = (inv['customerPhone'] ?? '').toString().toLowerCase();

                  final matches = receiptNum.contains(query) ||
                      store.contains(query) ||
                      branch.contains(query) ||
                      eventName.contains(query) ||
                      targetComp.contains(query) ||
                      custName.contains(query) ||
                      custPhone.contains(query);

                  if (!matches) return false;
                }

                return true;
              }).toList();

              // Calculate Metrics
              final totalInvoicesCount = filteredInvoices.length;
              double totalPromoSales = 0.0;
              int totalExtractedItems = 0;
              double totalDurationSec = 0.0;
              int durationCount = 0;

              // Distinct companies for company filter
              final availableCompanies = <String, String>{};
              for (final inv in allInvoices) {
                final slug = inv['companySlug']?.toString().trim() ?? '';
                final name = inv['targetCompany']?.toString().trim() ?? '';
                if (name.isNotEmpty) {
                  availableCompanies[slug.isNotEmpty ? slug : name] = name;
                }
              }

              for (final inv in filteredInvoices) {
                final promoTotal = (inv['target_company_total'] ?? inv['total_value'] ?? 0);
                if (promoTotal is num) totalPromoSales += promoTotal.toDouble();

                final products = (inv['extracted_products'] as List?) ?? [];
                for (final p in products) {
                  if (p is Map) {
                    final qty = p['quantity'];
                    totalExtractedItems += (qty is num ? qty.toInt() : 1);
                  }
                }

                final dur = inv['analysis_duration_seconds'];
                if (dur is num && dur > 0) {
                  totalDurationSec += dur.toDouble();
                  durationCount++;
                }
              }

              final avgAiSpeed = durationCount > 0 ? (totalDurationSec / durationCount) : 0.0;

              return Column(
                children: [
                  // 1. M3 Hero Header (Seamless with Admin Portal)
                  if (!widget.isEmbedded)
                    _buildM3HeroHeader(
                      context: context,
                      colorScheme: colorScheme,
                      textTheme: textTheme,
                      strings: strings,
                      totalCount: allInvoices.length,
                      filteredCount: filteredInvoices.length,
                      onResetFilters: _resetFilters,
                    ),

                  // 2. KPI Summary Cards
                  _buildKpiSummaryBar(
                    colorScheme: colorScheme,
                    strings: strings,
                    isAr: isAr,
                    isHi: ref.isHindi,
                    activeCountry: activeCountry,
                    totalInvoices: totalInvoicesCount,
                    totalPromoSales: totalPromoSales,
                    totalItems: totalExtractedItems,
                    avgSpeed: avgAiSpeed,
                    onExportCsv: () => _exportInvoicesToCsv(filteredInvoices, strings),
                  ),

                  // 3. Filter & Search Controls
                  _buildFilterControls(
                    colorScheme: colorScheme,
                    strings: strings,
                    isAr: isAr,
                    eventsMap: eventsMap,
                    availableCompanies: availableCompanies,
                    allInvoices: allInvoices,
                  ),

                  const Divider(height: 1),

                  // 4. Invoices List Feed
                  Expanded(
                    child: filteredInvoices.isEmpty
                        ? _buildEmptyState(strings, colorScheme)
                        : _buildInvoicesFeed(
                            filteredInvoices: filteredInvoices,
                            colorScheme: colorScheme,
                            activeCountry: activeCountry,
                            strings: strings,
                            isAr: isAr,
                          ),
                  ),
                ],
              );
  }

  Widget _buildM3HeroHeader({
    required BuildContext context,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required AppStrings strings,
    required int totalCount,
    required int filteredCount,
    required VoidCallback onResetFilters,
  }) {
    final canPop = Navigator.canPop(context);
    final isMobile = MediaQuery.of(context).size.width < 680;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 20,
        vertical: isMobile ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          if (canPop) ...[
            IconButton.filledTonal(
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: strings.backBtn,
            ),
            const SizedBox(width: 8),
          ],
          Container(
            padding: EdgeInsets.all(isMobile ? 8 : 10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(isMobile ? 10 : 14),
            ),
            child: Icon(
              Icons.receipt_long_rounded,
              color: colorScheme.onPrimaryContainer,
              size: isMobile ? 20 : 24,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        strings.invoicesAuditTitle,
                        style: (isMobile ? textTheme.titleSmall : textTheme.titleMedium)?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        filteredCount == totalCount ? '$totalCount' : '$filteredCount / $totalCount',
                        style: TextStyle(
                          fontSize: isMobile ? 10 : 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  strings.invoicesAuditSubtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: isMobile ? 10 : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: strings.clearFiltersBtn,
            onPressed: onResetFilters,
          ),
        ],
      ),
    );
  }

  Widget _buildKpiSummaryBar({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required CountryCurrency activeCountry,
    required int totalInvoices,
    required double totalPromoSales,
    required int totalItems,
    required double avgSpeed,
    required VoidCallback onExportCsv,
  }) {
    final isMobile = MediaQuery.of(context).size.width < 680;

    final cards = [
      // Card 1: Total Scanned & Audited Invoices
      _buildStatKpiCard(
        title: strings.totalReceiptsCount,
        value: '$totalInvoices',
        subtitle: isAr ? 'سجل العمليات والفواتير المدققة' : (isHi ? 'सत्यापित रसीदें' : 'Audited receipts & scan logs'),
        icon: Icons.receipt_long_rounded,
        accentColor: Colors.blue.shade700,
        badgeText: isAr ? 'فاتورة مفحوصة' : (isHi ? 'रसीदें' : 'Audited'),
        colorScheme: colorScheme,
        tooltip: isAr ? 'إجمالي عدد الفواتير التي تم مسحها وتدقيقها بالذكاء الاصطناعي' : 'Total receipts processed & audited',
        isMobile: isMobile,
      ),

      // Card 2: Total Promotional Target Sales
      _buildStatKpiCard(
        title: strings.totalPromotionalSales,
        value: '${totalPromoSales.toStringAsFixed(1)} ${activeCountry.currencySymbol}',
        subtitle: isAr ? 'قيمة مشتريات المنتجات المعتمدة' : (isHi ? 'प्रचार बिक्री' : 'Verified promotional purchases'),
        icon: Icons.payments_rounded,
        accentColor: Colors.teal.shade700,
        badgeText: activeCountry.nameAr,
        colorScheme: colorScheme,
        tooltip: isAr ? 'إجمالي المبيعات المحققة لمنتجات الحملة بالعُملة المحلية' : 'Total promotional sales volume',
        isMobile: isMobile,
      ),

      // Card 3: Total Extracted Units
      _buildStatKpiCard(
        title: strings.totalItemsPurchased,
        value: '$totalItems',
        subtitle: isAr ? 'الكميات المستخرجة من الفواتير' : (isHi ? 'कुल उत्पाद' : 'Total items detected in receipts'),
        icon: Icons.inventory_2_rounded,
        accentColor: Colors.purple.shade700,
        badgeText: isAr ? 'قطع مباعة' : (isHi ? 'उत्पाद' : 'Units'),
        colorScheme: colorScheme,
        tooltip: isAr ? 'إجمالي عدد القطع والمنتجات المستخرجة بالفحص' : 'Total product units extracted from receipts',
        isMobile: isMobile,
      ),

      // Card 4: AI Verification Speed
      _buildStatKpiCard(
        title: strings.avgAiSpeed,
        value: avgSpeed > 0 ? '${avgSpeed.toStringAsFixed(2)}s' : '⚡ <2.0s',
        subtitle: isAr ? 'زمن تحليل الفاتورة بـ Gemini AI' : (isHi ? 'एआई गति' : 'Gemini AI receipt audit latency'),
        icon: Icons.bolt_rounded,
        accentColor: Colors.amber.shade800,
        badgeText: '⚡ Gemini AI',
        colorScheme: colorScheme,
        tooltip: isAr ? 'متوسط الوقت المستغرق لتحليل الفاتورة ومطابقة الأصناف' : 'Average AI processing latency',
        isMobile: isMobile,
      ),
    ];

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: cards
                .map(
                  (card) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 10),
                    child: SizedBox(
                      width: 210,
                      height: 105,
                      child: card,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double width = constraints.maxWidth;
          int crossAxisCount = width < 1000 ? 2 : 4;
          double childAspectRatio = width < 1000 ? 2.1 : 1.9;

          return GridView.count(
            crossAxisCount: crossAxisCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: childAspectRatio,
            children: cards,
          );
        },
      ),
    );
  }

  Widget _buildStatKpiCard({
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
        padding: EdgeInsets.all(isMobile ? 10 : 16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: EdgeInsets.all(isMobile ? 6 : 10),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(isMobile ? 10 : 14),
                  ),
                  child: Icon(icon, color: accentColor, size: isMobile ? 18 : 22),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 8, vertical: isMobile ? 2 : 3),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(isMobile ? 8 : 10),
                  ),
                  child: Text(
                    badgeText,
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 9.5 : 11,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              value,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 15 : 19,
                fontWeight: FontWeight.w900,
                color: colorScheme.onSurface,
                letterSpacing: -0.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
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
                fontSize: isMobile ? 9.5 : 10,
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

  Widget _buildFilterControls({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required Map<String, EventModel> eventsMap,
    required Map<String, String> availableCompanies,
    required List<Map<String, dynamic>> allInvoices,
  }) {
    final hasActiveFilters = _searchController.text.isNotEmpty ||
        _selectedCampaignId != 'all' ||
        _selectedCompanySlug != 'all' ||
        _dateFilter != DateFilterType.all;

    final scopedEventsMap = (widget.lockedCompanySlug != null && widget.lockedCompanySlug!.isNotEmpty)
        ? Map.fromEntries(eventsMap.entries.where((e) {
            final slug = e.value.companySlug.toLowerCase();
            final name = e.value.targetCompany.toLowerCase();
            return slug == widget.lockedCompanySlug!.toLowerCase() ||
                (widget.lockedCompanyName != null && name == widget.lockedCompanyName!.toLowerCase());
          }))
        : eventsMap;

    final isMobile = MediaQuery.of(context).size.width < 680;

    final searchFieldWidget = TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: strings.searchReceiptPlaceholder,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: () => setState(() => _searchController.clear()),
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    final datePickerWidget = PopupMenuButton<DateFilterType>(
      initialValue: _dateFilter,
      onSelected: (type) {
        if (type == DateFilterType.custom) {
          _pickCustomDateRange(context);
        } else {
          setState(() {
            _dateFilter = type;
            _customDateRange = null;
          });
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: DateFilterType.all, child: Text(strings.filterByDate)),
        PopupMenuItem(value: DateFilterType.today, child: Text(strings.filterToday)),
        PopupMenuItem(value: DateFilterType.last7Days, child: Text(strings.filterLast7Days)),
        PopupMenuItem(value: DateFilterType.thisMonth, child: Text(strings.filterThisMonth)),
        PopupMenuItem(value: DateFilterType.custom, child: Text(strings.filterCustomDate)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _dateFilter != DateFilterType.all ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _dateFilter != DateFilterType.all ? colorScheme.primary : colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_month_rounded,
              size: 18,
              color: _dateFilter != DateFilterType.all ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _getDateFilterLabel(strings),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _dateFilter != DateFilterType.all ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: _dateFilter != DateFilterType.all ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );

    final exportCsvButton = FilledButton.tonalIcon(
      onPressed: () => _exportInvoicesToCsv(allInvoices, strings),
      icon: const Icon(Icons.file_download_outlined, size: 18),
      label: Text(strings.exportCsvBtn, style: const TextStyle(fontSize: 12)),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    return Container(
      padding: EdgeInsets.fromLTRB(isMobile ? 12 : 16, 12, isMobile ? 12 : 16, 8),
      color: colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Controls Row(s)
          if (isMobile) ...[
            // Mobile Row 1: Search Bar (Full Width)
            searchFieldWidget,
            const SizedBox(height: 8),

            // Mobile Row 2: Action Buttons
            Row(
              children: [
                Expanded(child: datePickerWidget),
                const SizedBox(width: 8),
                Expanded(child: exportCsvButton),
                if (hasActiveFilters) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: strings.clearFiltersBtn,
                    icon: const Icon(Icons.filter_alt_off_rounded, color: Colors.red),
                    onPressed: _resetFilters,
                  ),
                ],
              ],
            ),
          ] else ...[
            // Desktop Single Row
            Row(
              children: [
                Expanded(child: searchFieldWidget),
                const SizedBox(width: 8),
                datePickerWidget,
                const SizedBox(width: 8),
                exportCsvButton,
                if (hasActiveFilters) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: strings.clearFiltersBtn,
                    icon: const Icon(Icons.filter_alt_off_rounded, color: Colors.red),
                    onPressed: _resetFilters,
                  ),
                ],
              ],
            ),
          ],

          const SizedBox(height: 12),

          // Selected Campaign Active Badge (If a specific campaign is chosen)
          if (_selectedCampaignId != 'all' && scopedEventsMap.containsKey(_selectedCampaignId)) ...[
            () {
              final activeEvent = scopedEventsMap[_selectedCampaignId]!;
              final count = allInvoices.where((inv) => inv['campaignId'] == activeEvent.id).length;
              final isActive = activeEvent.isActive && !activeEvent.isExpired;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.6), width: 1.2),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.campaign_rounded, color: colorScheme.onPrimary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                isAr ? 'الفعالية المحددة:' : 'Active Festival:',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: isActive ? Colors.green.shade100 : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isActive ? (isAr ? 'نشطة' : 'Active') : (isAr ? 'منتهية' : 'Ended'),
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: isActive ? Colors.green.shade900 : Colors.grey.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            activeEvent.eventName,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${activeEvent.targetCompany}${activeEvent.retailChainName.isNotEmpty ? " • ${activeEvent.retailChainName}" : ""} • ($count ${isAr ? "فاتورة مفحوصة" : "audited invoices"})',
                            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => _showCampaignSelectorDialog(
                        context: context,
                        colorScheme: colorScheme,
                        strings: strings,
                        isAr: isAr,
                        eventsMap: scopedEventsMap,
                        availableCompanies: availableCompanies,
                        allInvoices: allInvoices,
                      ),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                      label: Text(isAr ? 'تغيير الفعالية' : 'Change', style: const TextStyle(fontSize: 11)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      tooltip: isAr ? 'عرض كافة الفعاليات' : 'Show All Campaigns',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        setState(() {
                          _selectedCampaignId = 'all';
                          _resetPagination();
                        });
                      },
                    ),
                  ],
                ),
              );
            }(),
          ],

          // Quick Filter Bar + Open Full Campaign Search Dialog Button
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Button to open the full searchable campaign modal
                FilledButton.icon(
                  onPressed: () => _showCampaignSelectorDialog(
                    context: context,
                    colorScheme: colorScheme,
                    strings: strings,
                    isAr: isAr,
                    eventsMap: scopedEventsMap,
                    availableCompanies: availableCompanies,
                    allInvoices: allInvoices,
                  ),
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: Text(
                    isAr
                        ? 'تصفية الفعاليات والمهرجانات (${scopedEventsMap.length})'
                        : 'Filter Campaigns (${scopedEventsMap.length})',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 8),

                // Choice chip for "All Campaigns"
                ChoiceChip(
                  label: Text('${strings.allCampaigns} (${allInvoices.length})'),
                  selected: _selectedCampaignId == 'all',
                  onSelected: (_) => setState(() {
                    _selectedCampaignId = 'all';
                    _resetPagination();
                  }),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                const SizedBox(width: 6),

                // Top active campaigns (up to 4) for one-click access
                for (final entry in scopedEventsMap.entries.take(4)) ...[
                  () {
                    final event = entry.value;
                    final count = allInvoices.where((inv) => inv['campaignId'] == event.id).length;
                    return Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: ChoiceChip(
                        avatar: CircleAvatar(
                          radius: 10,
                          backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
                          child: Icon(Icons.campaign_rounded, size: 12, color: colorScheme.primary),
                        ),
                        label: Text('${event.eventName} ($count)'),
                        selected: _selectedCampaignId == event.id,
                        onSelected: (_) => setState(() {
                          _selectedCampaignId = event.id;
                          _resetPagination();
                        }),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  }(),
                ],

                // Company Filter Chips (If multiple companies)
                if (availableCompanies.length > 1 && (widget.lockedCompanySlug == null || widget.lockedCompanySlug!.isEmpty)) ...[
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: Text(
                      '${strings.companyField}:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                  ChoiceChip(
                    label: Text(strings.allCampaigns),
                    selected: _selectedCompanySlug == 'all',
                    onSelected: (_) => setState(() {
                      _selectedCompanySlug = 'all';
                      _resetPagination();
                    }),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  const SizedBox(width: 6),
                  for (final comp in availableCompanies.entries) ...[
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: ChoiceChip(
                        label: Text(comp.value),
                        selected: _selectedCompanySlug == comp.key,
                        onSelected: (_) => setState(() {
                          _selectedCompanySlug = comp.key;
                          _resetPagination();
                        }),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCampaignSelectorDialog({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required Map<String, EventModel> eventsMap,
    required Map<String, String> availableCompanies,
    required List<Map<String, dynamic>> allInvoices,
  }) async {
    final searchModalController = TextEditingController();
    String filterStatus = 'all';
    String filterCompany = 'all';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final query = searchModalController.text.trim().toLowerCase();

            final filteredEvents = eventsMap.values.where((event) {
              if (filterStatus == 'active' && (!event.isActive || event.isExpired)) return false;
              if (filterStatus == 'expired' && !event.isExpired) return false;

              if (filterCompany != 'all') {
                final slug = event.companySlug.toLowerCase();
                final name = event.targetCompany.toLowerCase();
                if (slug != filterCompany.toLowerCase() && name != filterCompany.toLowerCase()) {
                  return false;
                }
              }

              if (query.isNotEmpty) {
                final name = event.eventName.toLowerCase();
                final comp = event.targetCompany.toLowerCase();
                final store = event.retailChainName.toLowerCase();
                final branches = event.branchNames.join(' ').toLowerCase();
                if (!name.contains(query) &&
                    !comp.contains(query) &&
                    !store.contains(query) &&
                    !branches.contains(query)) {
                  return false;
                }
              }
              return true;
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.campaign_rounded, color: colorScheme.onPrimaryContainer, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isAr ? 'اختيار وتصفية الفعاليات والمهرجانات' : 'Select Campaign & Festival',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                isAr
                                    ? 'استعراض والبحث في كافة الفعاليات (${eventsMap.length} فعالية مسجلة)'
                                    : 'Browse and search across ${eventsMap.length} registered events',
                                style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.of(modalContext).pop(),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Search Field inside Modal
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: TextField(
                      controller: searchModalController,
                      onChanged: (_) => setModalState(() {}),
                      decoration: InputDecoration(
                        hintText: isAr
                            ? 'ابحث باسم الفعالية، المهرجان، الشركة الراعية، أو الفرع...'
                            : 'Search by festival, campaign, company or branch...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: searchModalController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () => setModalState(() => searchModalController.clear()),
                              )
                            : null,
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: colorScheme.outlineVariant),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Filter Segmented Pills (Status & Companies)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: Text(isAr ? 'كافة الفعاليات (${eventsMap.length})' : 'All (${eventsMap.length})'),
                            selected: filterStatus == 'all' && filterCompany == 'all',
                            onSelected: (_) => setModalState(() {
                              filterStatus = 'all';
                              filterCompany = 'all';
                            }),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            avatar: const Icon(Icons.check_circle_rounded, size: 15, color: Colors.green),
                            label: Text(isAr ? 'النشطة حالياً' : 'Active Now'),
                            selected: filterStatus == 'active',
                            onSelected: (_) => setModalState(() => filterStatus = filterStatus == 'active' ? 'all' : 'active'),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            avatar: Icon(Icons.history_rounded, size: 15, color: Colors.grey.shade600),
                            label: Text(isAr ? 'المنتهية' : 'Ended'),
                            selected: filterStatus == 'expired',
                            onSelected: (_) => setModalState(() => filterStatus = filterStatus == 'expired' ? 'all' : 'expired'),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          if (availableCompanies.length > 1) ...[
                            const SizedBox(width: 8),
                            for (final comp in availableCompanies.entries) ...[
                              Padding(
                                padding: const EdgeInsetsDirectional.only(end: 8),
                                child: ChoiceChip(
                                  label: Text(comp.value),
                                  selected: filterCompany == comp.key,
                                  onSelected: (_) => setModalState(() => filterCompany = filterCompany == comp.key ? 'all' : comp.key),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                  const Divider(height: 1),

                  // Option to Select "All Campaigns"
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _selectedCampaignId == 'all' ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.select_all_rounded,
                        color: _selectedCampaignId == 'all' ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      isAr ? 'كافة الحملات والفعاليات (عرض شامل لكافة الفواتير)' : 'All Campaigns & Festivals',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _selectedCampaignId == 'all' ? colorScheme.primary : null,
                      ),
                    ),
                    subtitle: Text(
                      isAr
                          ? 'عرض جميع الفواتير المسجلة عبر كافة المهرجانات (${allInvoices.length} فاتورة)'
                          : 'Show all receipts across all events (${allInvoices.length} receipts)',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: _selectedCampaignId == 'all'
                        ? Icon(Icons.check_circle_rounded, color: colorScheme.primary)
                        : null,
                    onTap: () {
                      setState(() {
                        _selectedCampaignId = 'all';
                        _resetPagination();
                      });
                      Navigator.of(modalContext).pop();
                    },
                  ),
                  const Divider(height: 1),

                  // Events List inside Modal
                  Expanded(
                    child: filteredEvents.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off_rounded, size: 44, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                                const SizedBox(height: 8),
                                Text(
                                  isAr ? 'لم يتم العثور على فعاليات مطابقة للبحث' : 'No matching campaigns found',
                                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: filteredEvents.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final event = filteredEvents[index];
                              final isSelected = _selectedCampaignId == event.id;
                              final count = allInvoices.where((inv) => inv['campaignId'] == event.id).length;
                              final isActive = event.isActive && !event.isExpired;

                              String gameTypeLabel = isAr ? 'عجلة الحظ' : 'Wheel';
                              IconData gameIcon = Icons.stars_rounded;
                              if (event.gameType == 'scratch') {
                                gameTypeLabel = isAr ? 'كرت الخربشة' : 'Scratch Card';
                                gameIcon = Icons.style_rounded;
                              } else if (event.gameType == 'directGift' || event.gameType == 'direct_gift') {
                                gameTypeLabel = isAr ? 'هدية فورية' : 'Direct Gift';
                                gameIcon = Icons.card_giftcard_rounded;
                              }

                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedCampaignId = event.id;
                                    _resetPagination();
                                  });
                                  Navigator.of(modalContext).pop();
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                                        : colorScheme.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected
                                          ? colorScheme.primary
                                          : colorScheme.outlineVariant.withValues(alpha: 0.6),
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? colorScheme.primary
                                              : colorScheme.secondaryContainer,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            gameIcon,
                                            color: isSelected
                                                ? colorScheme.onPrimary
                                                : colorScheme.onSecondaryContainer,
                                            size: 22,
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
                                                Expanded(
                                                  child: Text(
                                                    event.eventName,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                      color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: isActive ? Colors.green.shade50 : Colors.grey.shade100,
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: isActive ? Colors.green.shade300 : Colors.grey.shade300,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Container(
                                                        width: 6,
                                                        height: 6,
                                                        decoration: BoxDecoration(
                                                          color: isActive ? Colors.green.shade700 : Colors.grey.shade600,
                                                          shape: BoxShape.circle,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        isActive ? (isAr ? 'نشطة' : 'Active') : (isAr ? 'منتهية' : 'Ended'),
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: isActive ? Colors.green.shade900 : Colors.grey.shade700,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(Icons.business_rounded, size: 13, color: colorScheme.onSurfaceVariant),
                                                const SizedBox(width: 4),
                                                Text(
                                                  event.targetCompany,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                                if (event.retailChainName.isNotEmpty) ...[
                                                  Text(' • ', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                                                  Icon(Icons.storefront_rounded, size: 13, color: colorScheme.onSurfaceVariant),
                                                  const SizedBox(width: 2),
                                                  Flexible(
                                                    child: Text(
                                                      event.retailChainName,
                                                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: colorScheme.surfaceContainerHighest,
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(gameIcon, size: 12, color: colorScheme.primary),
                                                      const SizedBox(width: 4),
                                                      Text(gameTypeLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                                    ],
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: colorScheme.surfaceContainerHighest,
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    '${isAr ? "الحد الأدنى:" : "Min spend:"} ${event.minimumSpend.toStringAsFixed(0)}',
                                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: isSelected ? colorScheme.primary : colorScheme.secondaryContainer,
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    '$count ${isAr ? "فاتورة" : "receipts"}',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: isSelected ? colorScheme.onPrimary : colorScheme.onSecondaryContainer,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isSelected) ...[
                                        const SizedBox(width: 8),
                                        Icon(Icons.check_circle_rounded, color: colorScheme.primary, size: 22),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _getDateFilterLabel(AppStrings strings) {
    switch (_dateFilter) {
      case DateFilterType.all:
        return strings.filterByDate;
      case DateFilterType.today:
        return strings.filterToday;
      case DateFilterType.last7Days:
        return strings.filterLast7Days;
      case DateFilterType.thisMonth:
        return strings.filterThisMonth;
      case DateFilterType.custom:
        if (_customDateRange != null) {
          final fmt = DateFormat('MM/dd');
          return '${fmt.format(_customDateRange!.start)} - ${fmt.format(_customDateRange!.end)}';
        }
        return strings.filterCustomDate;
    }
  }

  Widget _buildEmptyState(AppStrings strings, ColorScheme colorScheme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.receipt_long_outlined, size: 44, color: colorScheme.primary),
            ),
            const SizedBox(height: 12),
            Text(
              strings.noMatchingInvoices,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              strings.invoicesAuditSubtitle,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(strings.clearFiltersBtn, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoicesFeed({
    required List<Map<String, dynamic>> filteredInvoices,
    required ColorScheme colorScheme,
    required CountryCurrency activeCountry,
    required AppStrings strings,
    required bool isAr,
  }) {
    final isAdmin = ref.watch(isAdminProvider) && !widget.isEmbedded;
    final visibleInvoices = filteredInvoices.take(_displayedItemCount).toList();
    final hasMore = _displayedItemCount < filteredInvoices.length;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 32.0),
      itemCount: visibleInvoices.length + 1,
      itemBuilder: (context, index) {
        if (index == visibleInvoices.length) {
          // Bottom Load More Indicator or End of List Footer
          if (hasMore) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isAr
                            ? 'جاري استدعاء 20 فاتورة إضافية (تم عرض ${visibleInvoices.length} من ${filteredInvoices.length})...'
                            : 'Loading 20 more invoices (${visibleInvoices.length} of ${filteredInvoices.length} loaded)...',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          } else {
            // End of records reached footer
            return Container(
              margin: const EdgeInsets.only(top: 10, bottom: 20),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded, size: 16, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Text(
                    isAr
                        ? 'تم عرض كافة الفواتير المسجلة بنجاح (المجموع: ${filteredInvoices.length} فاتورة)'
                        : 'All ${filteredInvoices.length} invoices successfully loaded',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (filteredInvoices.length > 5) ...[
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: () {
                        if (_scrollController.hasClients) {
                          _scrollController.animateTo(
                            0,
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOut,
                          );
                        }
                      },
                      icon: const Icon(Icons.arrow_upward_rounded, size: 14),
                      label: Text(
                        isAr ? 'الرجوع للأعلى' : 'Back to top',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }
        }

        final inv = visibleInvoices[index];
        final docId = inv['id'] as String;
        final isExpanded = _expandedDocIds.contains(docId);

        final receiptNumber = inv['receipt_number']?.toString() ?? 'N/A';
        final totalValue = inv['target_company_total'] ?? inv['total_value'] ?? 0;
        final imageUrl = inv['image_url']?.toString() ?? '';
        final storeChain = (inv['store_chain_detected'] ?? inv['retail_chain_name'] ?? '').toString();
        final branch = (inv['branch_detected'] ?? '').toString();
        final eventName = inv['eventName']?.toString() ?? '';
        final targetCompany = inv['targetCompany']?.toString() ?? (isAr ? 'الشركة الراعية' : 'Sponsor Company');
        final formattedDate = inv['formattedDate']?.toString() ?? 'N/A';
        final durationSec = inv['analysis_duration_seconds'] is num ? (inv['analysis_duration_seconds'] as num).toDouble() : null;
        final kpiRating = inv['ai_kpi_rating'] as String?;
        final customerName = inv['customerName']?.toString();
        final customerPhone = inv['customerPhone']?.toString();
        final products = (inv['extracted_products'] as List?) ?? [];

        return Card(
          elevation: 1,
          margin: const EdgeInsets.only(bottom: 14),
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isExpanded ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.6),
              width: isExpanded ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Padding(
                padding: const EdgeInsets.all(14.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thumbnail with M3 Zoom Badge
                    GestureDetector(
                      onTap: () => _showImagePreviewDialog(
                        context: context,
                        imageUrl: imageUrl,
                        receiptNumber: receiptNumber,
                        store: storeChain.isNotEmpty ? (branch.isNotEmpty ? '$storeChain - $branch' : storeChain) : '',
                        totalValue: totalValue,
                        date: formattedDate,
                        currencySymbol: activeCountry.currencySymbol,
                        colorScheme: colorScheme,
                        strings: strings,
                        docId: docId,
                        storagePath: inv['storage_path']?.toString(),
                        canDelete: isAdmin,
                      ),
                      child: Tooltip(
                        message: imageUrl.isNotEmpty ? 'انقر لمعاينة وتكبير صورة الفاتورة' : 'لا توجد صورة مسجلة',
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _buildReceiptImage(imageUrl, fit: BoxFit.cover),
                                  if (imageUrl.isNotEmpty)
                                    Positioned(
                                      bottom: 3,
                                      right: 3,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.65),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.zoom_in_rounded, size: 13, color: Colors.white),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Middle Column: Receipt #, Badges, Store, Date
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Receipt Number with Copy Action
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => _copyToClipboard(receiptNumber, context, strings),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          '#$receiptNumber',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.3,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(Icons.copy_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                                    ],
                                  ),
                                ),
                              ),

                              // Store / Branch Tag
                              if (storeChain.isNotEmpty || branch.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.blue.shade200),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.storefront_rounded, size: 13, color: Colors.blue.shade800),
                                      const SizedBox(width: 4),
                                      Text(
                                        branch.isNotEmpty ? '$storeChain - $branch' : storeChain,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.blue.shade900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),

                          const SizedBox(height: 6),

                          // Event & Company Chips Row
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  eventName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  targetCompany,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                              if (customerName != null && customerName.isNotEmpty)
                                Text(
                                  '👤 $customerName ${customerPhone != null ? "($customerPhone)" : ""}',
                                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                ),
                            ],
                          ),

                          const SizedBox(height: 6),

                          // Date & Speed KPI Row
                          Row(
                            children: [
                              Icon(Icons.access_time_rounded, size: 13, color: colorScheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(
                                formattedDate,
                                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                              ),
                              const Spacer(),

                              if (durationSec != null) ...[
                                Tooltip(
                                  message: kpiRating ?? (durationSec <= 2.0 ? '⚡ فائق السرعة' : '🟢 ممتاز'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: durationSec <= 2.0
                                          ? Colors.green.shade50
                                          : (durationSec <= 3.5 ? Colors.teal.shade50 : Colors.amber.shade50),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: durationSec <= 2.0
                                            ? Colors.green.shade300
                                            : (durationSec <= 3.5 ? Colors.teal.shade300 : Colors.amber.shade300),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.bolt_rounded,
                                          size: 13,
                                          color: durationSec <= 2.0 ? Colors.green.shade800 : Colors.amber.shade900,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          '${durationSec.toStringAsFixed(2)}s',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: durationSec <= 2.0 ? Colors.green.shade900 : Colors.amber.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom Action Bar: Spend Total + Expand Button + Admin Delete Action
              Builder(
                builder: (context) {
                  final isMobile = MediaQuery.of(context).size.width < 680;
                  final itemsBtnLabel = isMobile
                      ? '${isAr ? "الأصناف" : "Items"} (${products.length})'
                      : '${strings.viewReceiptProducts} (${products.length} ${strings.itemsCountLabel})';

                  return Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 10 : 14,
                      vertical: isMobile ? 8 : 10,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                    ),
                    child: Row(
                      children: [
                        // Total Spend Highlight
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${strings.targetCompanyField}: $targetCompany',
                                style: TextStyle(
                                  fontSize: isMobile ? 10 : 11,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '$totalValue ${activeCountry.currencySymbol}',
                                style: TextStyle(
                                  fontSize: isMobile ? 14 : 16,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Items Count Button with Expand action
                        OutlinedButton.icon(
                          onPressed: () => _toggleExpand(docId),
                          icon: Icon(
                            isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                            size: isMobile ? 16 : 18,
                          ),
                          label: Text(
                            itemsBtnLabel,
                            style: TextStyle(
                              fontSize: isMobile ? 11 : 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 8 : 12,
                              vertical: isMobile ? 6 : 8,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),

                        // Admin-Only Delete Action Button (Never displayed for Company Manager View)
                        if (isAdmin) ...[
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            onPressed: () => _confirmAndDeleteInvoice(
                              context: context,
                              docId: docId,
                              receiptNumber: receiptNumber,
                              totalValue: totalValue,
                              currencySymbol: activeCountry.currencySymbol,
                              storagePath: inv['storage_path']?.toString(),
                              imageUrl: imageUrl,
                              strings: strings,
                              colorScheme: colorScheme,
                            ),
                            icon: Icon(Icons.delete_outline_rounded, color: colorScheme.error, size: isMobile ? 18 : 20),
                            style: IconButton.styleFrom(
                              side: BorderSide(color: colorScheme.error.withValues(alpha: 0.4)),
                              backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.2),
                              padding: EdgeInsets.all(isMobile ? 6 : 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            tooltip: strings.deleteInvoiceTooltip,
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),

              // Expanded Itemized Products Table with Barcodes
              if (isExpanded) ...[
                const Divider(height: 1),
                _buildItemizedProductsTable(
                  products: products,
                  colorScheme: colorScheme,
                  activeCountry: activeCountry,
                  strings: strings,
                  targetCompany: targetCompany,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildItemizedProductsTable({
    required List<dynamic> products,
    required ColorScheme colorScheme,
    required CountryCurrency activeCountry,
    required AppStrings strings,
    required String targetCompany,
  }) {
    if (products.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text(
            strings.noMatchingInvoices,
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14.0),
      color: colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.format_list_bulleted_rounded, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                strings.receiptDetailsTitle,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${products.length} ${strings.itemsCountLabel}',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Responsive Data Table for Items & Barcodes
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)),
                  columnSpacing: 18,
                  horizontalMargin: 12,
                  headingRowHeight: 38,
                  dataRowMinHeight: 42,
                  dataRowMaxHeight: 52,
                  columns: [
                    DataColumn(label: Text('#', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text(strings.productNameCol, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text(strings.barcodeCol, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text(strings.quantityCol, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text('${strings.unitPriceCol} (${activeCountry.currencySymbol})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text('${strings.totalPriceCol} (${activeCountry.currencySymbol})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text(strings.itemCategoryCol, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  ],
                  rows: List.generate(products.length, (index) {
                    final item = products[index];
                    final itemMap = item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{};
                    final name = itemMap['name']?.toString() ?? 'N/A';
                    final barcode = itemMap['barcode']?.toString().trim() ?? '';
                    final qty = itemMap['quantity'] is num ? (itemMap['quantity'] as num).toInt() : 1;
                    final price = itemMap['price'] is num ? (itemMap['price'] as num).toDouble() : 0.0;
                    final total = itemMap['totalPrice'] is num ? (itemMap['totalPrice'] as num).toDouble() : (price * qty);
                    final isPromo = itemMap['isTargetCompany'] == true;

                    return DataRow(
                      cells: [
                        DataCell(Text('${index + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isPromo ? FontWeight.bold : FontWeight.normal,
                                color: isPromo ? colorScheme.primary : colorScheme.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(
                          barcode.isNotEmpty
                              ? InkWell(
                                  onTap: () => _copyToClipboard(barcode, context, strings),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: colorScheme.outlineVariant),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.qr_code_rounded, size: 12),
                                        const SizedBox(width: 4),
                                        Text(
                                          barcode,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : Text(
                                  '-',
                                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                ),
                        ),
                        DataCell(Text('$qty', style: const TextStyle(fontSize: 12))),
                        DataCell(Text(price.toStringAsFixed(2), style: const TextStyle(fontSize: 12))),
                        DataCell(Text(total.toStringAsFixed(2), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isPromo ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isPromo ? strings.includedInPromo : strings.generalItem,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isPromo ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
