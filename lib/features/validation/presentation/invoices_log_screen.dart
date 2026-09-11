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
import '../../../core/services/ai_receipt_service.dart';
import '../../../core/services/company_products_service.dart';
import '../../../core/services/retail_chains_service.dart';
import '../../admin/domain/retail_chain_model.dart';
import '../../../core/constants/country_currency_config.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../admin/domain/event_model.dart';
import '../../../core/utils/arabic_numbers_utils.dart';
import '../../../core/widgets/portal_screen_header_card.dart';
import '../../../core/widgets/interactive_receipt_viewer_dialog.dart';
import '../../../core/services/multi_campaign_receipt_evaluator.dart';
import 'package:http/http.dart' as http;

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
  static const int _pageSize = 25;
  int _currentPage = 0;
  int _mobileLimit = 25;
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;

  final TextEditingController _searchController = TextEditingController();
  String _selectedCampaignId = 'all';
  String _selectedCompanySlug = 'all';
  String _selectedBranch = 'all';
  String _statusFilter = 'all'; // 'all', 'accepted', 'rejected'
  DateFilterType _dateFilter = DateFilterType.all;
  DateTimeRange? _customDateRange;
  final Set<String> _expandedDocIds = <String>{};
  final Set<String> _recheckingDocIds = <String>{};

  // Golden Standard: Static Persistent In-Memory Caches for 0ms instant render across tab switches
  static final Map<String, List<QueryDocumentSnapshot>> _persistentInvoicesCache = {};
  static final Map<String, Map<String, EventModel>> _persistentEventsCache = {};

  // Memoized stream lifecycle outside build()
  String? _lastStreamsKey;
  Stream<QuerySnapshot>? _eventsStream;
  Stream<QuerySnapshot>? _transactionsStream;

  // Memoized computation caches
  String? _lastAllInvoicesCacheKey;
  List<Map<String, dynamic>>? _cachedAllInvoices;

  void _ensureStreams(FirebaseFirestore? firestore, {bool force = false}) {
    if (firestore == null) return;
    final isLocked = widget.lockedCompanySlug != null && widget.lockedCompanySlug!.isNotEmpty;
    final effectiveKey = '${widget.lockedCompanySlug ?? 'all'}_$_selectedCampaignId';

    if (_lastStreamsKey != effectiveKey || force || _transactionsStream == null) {
      _lastStreamsKey = effectiveKey;

      if (_eventsStream == null || force) {
        Query eventsQuery = firestore.collection('events');
        if (isLocked) {
          eventsQuery = eventsQuery.where('companySlug', isEqualTo: widget.lockedCompanySlug);
        }
        _eventsStream = eventsQuery.snapshots();
      }

      Query transactionsQuery = firestore.collection('receipts_transactions');
      if (_selectedCampaignId != 'ALL' && _selectedCampaignId != 'all' && _selectedCampaignId.isNotEmpty) {
        transactionsQuery = transactionsQuery.where('campaignId', isEqualTo: _selectedCampaignId);
      } else if (isLocked) {
        transactionsQuery = transactionsQuery.where('companySlug', isEqualTo: widget.lockedCompanySlug);
      }
      _transactionsStream = transactionsQuery.snapshots();
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedCompanySlug = widget.lockedCompanySlug ?? 'all';
    if (widget.initialEventId != null && widget.initialEventId!.isNotEmpty) {
      _selectedCampaignId = widget.initialEventId!;
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
          _mobileLimit += _pageSize;
          _isLoadingMore = false;
        });
      }
    });
  }

  void _resetPagination() {
    setState(() {
      _currentPage = 0;
      _mobileLimit = _pageSize;
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
      _selectedBranch = 'all';
      _statusFilter = 'all';
      _dateFilter = DateFilterType.all;
      _customDateRange = null;
      _currentPage = 0;
      _mobileLimit = _pageSize;
    });
    _resetPagination();
  }

  static String _cleanBranchForComparison(String branch) {
    var s = branch.trim().toLowerCase().toEnglishDigits();
    // Diacritics
    s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    // Alef normalization
    s = s.replaceAll(RegExp(r'[أإآ]'), 'ا');
    // Ta marbuta and ya
    s = s.replaceAll('ة', 'ه').replaceAll('ى', 'ي');
    // Remove city / governorate suffixes in parentheses
    s = s.replaceAll(RegExp(r'\((القاهرة|الإسكندرية|الاسكندرية|الجيزة|الغربية|الدقهلية|المنوفية|الشرقية|البحيرة|كفر الشيخ|دمياط|بورسعيد|السويس|الإسماعيلية|الفيوم|بني سويف|المنيا|أسيوط|سوهاج|قنا|الأقصر|أسوان|مطروح|cairo|alexandria|giza)\)', caseSensitive: false), ' ');
    // Punctuation, symbols, and brackets
    s = s.replaceAll(RegExp(r'[\(\)\[\]\{\}\-\_\,\.\:\/]'), ' ');
    // Remove prefixes and noise words
    s = s.replaceAll(RegExp(r'\b(فرع|سلسلة|store|branch|مفرع|pos|كود|محافظة|مدينة)\b', caseSensitive: false), ' ');
    // Extra spaces
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static String _normalizeBranchName(
    String rawBranch,
    List<String> canonicalBranches,
    bool isAr,
  ) {
    final clean = rawBranch.trim();
    if (clean.isEmpty) return isAr ? 'فرع غير محدد' : 'Unspecified Branch';
    if (canonicalBranches.isEmpty) return clean;

    // 1. Direct case-insensitive match
    for (final canonical in canonicalBranches) {
      if (canonical.trim().toLowerCase() == clean.toLowerCase()) {
        return canonical;
      }
    }

    // 2. Cleaned exact match
    final cleanComp = _cleanBranchForComparison(clean);
    for (final canonical in canonicalBranches) {
      final canonComp = _cleanBranchForComparison(canonical);
      if (cleanComp == canonComp && cleanComp.isNotEmpty) {
        return canonical;
      }
    }

    // 3. Precision Area / Branch matching
    // A. Gardenia
    if (cleanComp.contains('جاردينيا') || cleanComp.contains('gardenia')) {
      for (final canonical in canonicalBranches) {
        if (_cleanBranchForComparison(canonical).contains('جاردينيا')) return canonical;
      }
    }

    // B. Agamy
    if (cleanComp.contains('عجمي') || cleanComp.contains('agamy') || cleanComp.contains('agami')) {
      for (final canonical in canonicalBranches) {
        if (_cleanBranchForComparison(canonical).contains('عجمي')) return canonical;
      }
    }

    // C. Smouha
    if (cleanComp.contains('سموح') || cleanComp.contains('smouha')) {
      for (final canonical in canonicalBranches) {
        if (_cleanBranchForComparison(canonical).contains('سموح')) return canonical;
      }
    }

    // D. Mahalla El Kubra
    if (cleanComp.contains('محله') || cleanComp.contains('mahalla')) {
      for (final canonical in canonicalBranches) {
        if (_cleanBranchForComparison(canonical).contains('محله')) return canonical;
      }
    }

    // E. Shebin El Kom
    if (cleanComp.contains('شين') || cleanComp.contains('شبين') || cleanComp.contains('shebin')) {
      for (final canonical in canonicalBranches) {
        final c = _cleanBranchForComparison(canonical);
        if (c.contains('شبين') || c.contains('شين')) return canonical;
      }
    }

    // F. Tagmoo / Fifth Settlement / Park Mall
    if (cleanComp.contains('تجمع') || cleanComp.contains('tagmoo') || cleanComp.contains('park mall') || cleanComp.contains('fifth')) {
      for (final canonical in canonicalBranches) {
        final c = _cleanBranchForComparison(canonical);
        if (c.contains('تجمع') || c.contains('tagmoo')) return canonical;
      }
    }

    // G. 6th of October
    if (cleanComp.contains('اكتوبر') || cleanComp.contains('october') || cleanComp.contains('سادس')) {
      for (final canonical in canonicalBranches) {
        final c = _cleanBranchForComparison(canonical);
        if (c.contains('اكتوبر') || c.contains('october')) return canonical;
      }
    }

    // H. Mansoura
    if (cleanComp.contains('منصور') || cleanComp.contains('mansoura')) {
      for (final canonical in canonicalBranches) {
        if (_cleanBranchForComparison(canonical).contains('منصور')) return canonical;
      }
    }

    // I. Obour / Salah Salem
    if (cleanComp.contains('صلاح سالم') || cleanComp.contains('عبور') || cleanComp.contains('obour')) {
      for (final canonical in canonicalBranches) {
        final c = _cleanBranchForComparison(canonical);
        if (c.contains('صلاح سالم') || c.contains('عبور')) return canonical;
      }
    }

    // J. Montazah (and Store 418)
    if (clean.contains('418') || cleanComp.contains('منتزه') || cleanComp.contains('montazah')) {
      for (final canonical in canonicalBranches) {
        final c = _cleanBranchForComparison(canonical);
        if (c.contains('منتزه') || c.contains('montazah') || canonical.contains('418')) return canonical;
      }
    }

    // K. Miami
    if (cleanComp.contains('ميامي') || cleanComp.contains('miami')) {
      for (final canonical in canonicalBranches) {
        if (_cleanBranchForComparison(canonical).contains('ميامي')) return canonical;
      }
    }

    // L. Janaklis
    if (cleanComp.contains('جناكليس') || cleanComp.contains('janaklis')) {
      for (final canonical in canonicalBranches) {
        if (_cleanBranchForComparison(canonical).contains('جناكليس')) return canonical;
      }
    }

    // 4. Store Code Match (e.g. "Store: 418" / "Store 418" / "كود 418")
    final rawDigits = RegExp(r'\b\d+\b').allMatches(clean.toEnglishDigits()).map((m) => m.group(0)!).toSet();
    if (rawDigits.isNotEmpty) {
      for (final canonical in canonicalBranches) {
        final canonDigits = RegExp(r'\b\d+\b').allMatches(canonical.toEnglishDigits()).map((m) => m.group(0)!).toSet();
        if (rawDigits.intersection(canonDigits).isNotEmpty) {
          return canonical;
        }
      }
    }

    // 5. Fallback containment matching
    for (final canonical in canonicalBranches) {
      final canonComp = _cleanBranchForComparison(canonical);
      if (canonComp.isNotEmpty && (cleanComp.contains(canonComp) || canonComp.contains(cleanComp))) {
        return canonical;
      }
    }

    return clean;
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

  // ===========================================================================
  // Smart Receipt Re-verification Engine (إعادة الفحص الذكي للفواتير المرفوضة)
  // ===========================================================================

  void _promptRecheckOptions({
    required BuildContext context,
    required Map<String, dynamic> inv,
    required EventModel? event,
    required Map<String, EventModel> eventsMap,
    required AppStrings strings,
    required ColorScheme colorScheme,
    required CountryCurrency activeCountry,
    required bool isAr,
  }) {
    final receiptNumber = inv['receipt_number']?.toString() ?? 'N/A';
    final hasImage = (inv['image_url']?.toString().isNotEmpty ?? false) ||
        (inv['storage_path']?.toString().isNotEmpty ?? false);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.sync_rounded, color: colorScheme.primary, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${strings.recheckInvoiceAction} (#$receiptNumber)',
                    style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    isAr ? 'اختر أسلوب إعادة التحقق بعد تحديث الشروط أو الكتالوج:' : 'Select re-verification mode:',
                    style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Option 1: Quick Rule Re-match
            InkWell(
              onTap: () {
                Navigator.pop(dialogCtx);
                _executeRecheck(
                  inv: inv,
                  event: event,
                  eventsMap: eventsMap,
                  isFullAiScan: false,
                  strings: strings,
                  colorScheme: colorScheme,
                  activeCountry: activeCountry,
                  isAr: isAr,
                );
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.bolt_rounded, color: Colors.amber.shade900, size: 22),
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
                                  strings.quickRecheckTitle,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF452700),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade200,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isAr ? '⚡ فوري' : '⚡ Instant',
                                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF452700)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isAr
                                ? 'إعادة التحقق الذكي الفوري من شروط الحملة وعروض الشركة المرتبطة وفق القواعد'
                                : strings.quickRecheckSubtitle,
                            style: TextStyle(fontSize: 11, color: Colors.amber.shade900, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Option 2: Full AI Re-Scan
            InkWell(
              onTap: hasImage
                  ? () {
                      Navigator.pop(dialogCtx);
                      _executeRecheck(
                        inv: inv,
                        event: event,
                        eventsMap: eventsMap,
                        isFullAiScan: true,
                        strings: strings,
                        colorScheme: colorScheme,
                        activeCountry: activeCountry,
                        isAr: isAr,
                      );
                    }
                  : null,
              borderRadius: BorderRadius.circular(14),
              child: Opacity(
                opacity: hasImage ? 1.0 : 0.45,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.psychology_rounded, color: colorScheme.primary, size: 22),
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
                                    strings.fullAiRecheckTitle,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Gemini 3.7',
                                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              hasImage
                                  ? (isAr
                                      ? 'إعادة قراءة صورة الفاتورة بالكامل بذكاء Gemini 3.7 والتحقق الشامل من كافة عروض الشركة'
                                      : strings.fullAiRecheckSubtitle)
                                  : (isAr ? 'غير متاح: لا توجد صورة مرفقة لهذه الفاتورة' : 'Not available: No image attached'),
                              style: TextStyle(
                                fontSize: 11,
                                color: hasImage ? colorScheme.onSurfaceVariant : colorScheme.error,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeRecheck({
    required Map<String, dynamic> inv,
    required EventModel? event,
    required Map<String, EventModel> eventsMap,
    required bool isFullAiScan,
    required AppStrings strings,
    required ColorScheme colorScheme,
    required CountryCurrency activeCountry,
    required bool isAr,
  }) async {
    final docId = inv['id'] as String;
    setState(() => _recheckingDocIds.add(docId));

    try {
      EventModel? activeEvent = event;
      final firestore = ref.read(firestoreProvider);

      final campaignId = (inv['campaignId'] ?? '').toString();
      if (campaignId.isNotEmpty && activeEvent == null) {
        if (eventsMap.containsKey(campaignId)) {
          activeEvent = eventsMap[campaignId];
        } else {
          try {
            final evtDoc = await firestore.collection('events').doc(campaignId).get();
            if (evtDoc.exists) {
              activeEvent = EventModel.fromFirestore(evtDoc);
            }
          } catch (_) {}
        }
      }

      // 1. Resolve Company Identity
      final String companySlug = (inv['companySlug'] ??
              inv['company_slug'] ??
              activeEvent?.companySlug ??
              '')
          .toString()
          .trim();
      final String targetCompany = (inv['targetCompany'] ??
              activeEvent?.targetCompany ??
              '')
          .toString()
          .trim();

      // 2. Discover all active candidate campaigns for this company
      List<EventModel> companyEvents = [];
      if (companySlug.isNotEmpty || targetCompany.isNotEmpty) {
        companyEvents = eventsMap.values.where((e) {
          final matchSlug = companySlug.isNotEmpty &&
              e.companySlug.trim().toLowerCase() == companySlug.toLowerCase();
          final matchTarget = targetCompany.isNotEmpty &&
              e.targetCompany.trim().toLowerCase() == targetCompany.toLowerCase();
          return (matchSlug || matchTarget) && e.isActive && !e.isExpired;
        }).toList();
      }

      // If empty in memory cache, query Firestore
      if (companyEvents.isEmpty && companySlug.isNotEmpty) {
        try {
          final snap = await firestore
              .collection('events')
              .where('companySlug', isEqualTo: companySlug)
              .where('isActive', isEqualTo: true)
              .get();
          companyEvents = snap.docs
              .map((d) => EventModel.fromFirestore(d))
              .where((e) => !e.isExpired)
              .toList();
        } catch (_) {}
      }

      // Ensure activeEvent is in companyEvents (preferably at front)
      if (activeEvent != null) {
        final currentEvent = activeEvent;
        if (!companyEvents.any((e) => e.id == currentEvent.id)) {
          companyEvents.insert(0, currentEvent);
        }
      }

      if (companyEvents.isEmpty && activeEvent == null) {
        throw Exception(isAr
            ? 'تعذر العثور على بيانات الحملة الترويجية المرتبطة.'
            : 'Associated campaign data not found.');
      }
      activeEvent ??= companyEvents.first;

      if (!isFullAiScan) {
        await _runQuickRuleRecheck(
          docId: docId,
          inv: inv,
          activeEvent: activeEvent,
          companyEvents: companyEvents,
          eventsMap: eventsMap,
          activeCountry: activeCountry,
          strings: strings,
          colorScheme: colorScheme,
          isAr: isAr,
        );
      } else {
        await _runFullAiRecheck(
          docId: docId,
          inv: inv,
          activeEvent: activeEvent,
          companyEvents: companyEvents,
          eventsMap: eventsMap,
          activeCountry: activeCountry,
          strings: strings,
          colorScheme: colorScheme,
          isAr: isAr,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAr ? 'حدث خطأ أثناء إعادة الفحص: $e' : 'Error re-checking invoice: $e'),
            backgroundColor: colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _recheckingDocIds.remove(docId));
      }
    }
  }

  Future<void> _runQuickRuleRecheck({
    required String docId,
    required Map<String, dynamic> inv,
    required EventModel activeEvent,
    required List<EventModel> companyEvents,
    required Map<String, EventModel> eventsMap,
    required CountryCurrency activeCountry,
    required AppStrings strings,
    required ColorScheme colorScheme,
    required bool isAr,
  }) async {
    final firestore = ref.read(firestoreProvider);
    final currentUser = ref.read(firebaseAuthProvider).currentUser;

    // Check if products exist
    final rawProducts = (inv['extracted_products'] as List?) ?? [];
    final bool hasImage = (inv['image_url']?.toString().isNotEmpty ?? false) ||
        (inv['storage_path']?.toString().isNotEmpty ?? false);

    // If zero products are saved in the rejected record and an image exists,
    // quick rule matching on an empty list is impossible. Auto-fallback to Full AI Recheck!
    if (rawProducts.isEmpty && hasImage) {
      await _runFullAiRecheck(
        docId: docId,
        inv: inv,
        activeEvent: activeEvent,
        companyEvents: companyEvents,
        eventsMap: eventsMap,
        activeCountry: activeCountry,
        strings: strings,
        colorScheme: colorScheme,
        isAr: isAr,
      );
      return;
    }

    final List<ExtractedProductItem> products = rawProducts.map((p) {
      if (p is Map<String, dynamic>) return ExtractedProductItem.fromJson(p);
      if (p is Map) return ExtractedProductItem.fromJson(Map<String, dynamic>.from(p));
      return ExtractedProductItem(
        name: p.toString(),
        price: 0,
        quantity: 1,
        isTargetCompany: false,
      );
    }).toList();

    final rawBranch = (inv['raw_branch'] ?? inv['branch_detected'] ?? '').toString();
    final storeChain = (inv['store_chain_detected'] ?? inv['retail_chain_name'] ?? '').toString();
    final receiptNumber = (inv['receipt_number'] ?? '').toString();
    final receiptDate = (inv['date'] is DateTime)
        ? (inv['date'] as DateTime).toIso8601String()
        : (inv['receipt_date'] ?? inv['formattedDate'] ?? '').toString();

    final double computedTotal = products.fold<double>(0.0, (acc, p) => acc + p.actualLineSpend);
    final double targetTotal = (inv['target_company_total'] is num && (inv['target_company_total'] as num) > 0)
        ? (inv['target_company_total'] as num).toDouble()
        : (computedTotal > 0 ? computedTotal : (inv['total_value'] is num ? (inv['total_value'] as num).toDouble() : 0.0));

    final synthesizedResult = AiReceiptAnalysisResult(
      isValid: true,
      receiptNumber: receiptNumber,
      targetCompanyTotal: targetTotal,
      receiptDate: receiptDate,
      extractedProducts: products,
      storeChainDetected: storeChain,
      branchDetected: rawBranch,
      isBranchMatched: true,
      message: 'Quick rule recheck evaluation',
      unfulfilledConditions: const [],
      durationMs: 0,
      durationSeconds: 0.0,
      kpiRating: 'A+',
      kpiColorHex: '#4CAF50',
      chancesEarned: 1,
      matchedRuleId: '',
      matchedRuleIds: const [],
      matchedRuleTitle: '',
      matchedRewardValue: '',
      matchedRewardAmount: 0.0,
      matchedRewardType: '',
      isHandwritten: false,
    );

    // Test activeEvent first, then sister company events
    final orderedCampaigns = <EventModel>[
      activeEvent,
      ...companyEvents.where((e) => e.id != activeEvent.id),
    ];

    final summary = MultiCampaignReceiptEvaluator.evaluateAll(
      result: synthesizedResult,
      campaigns: orderedCampaigns,
    );

    if (summary.qualifiedCampaigns.isNotEmpty) {
      final winningEval = summary.qualifiedCampaigns.firstWhere(
        (e) => e.campaign.id == activeEvent.id,
        orElse: () => summary.qualifiedCampaigns.first,
      );
      final winningCampaign = winningEval.campaign;

      final int chances = winningEval.totalChances > 0 ? winningEval.totalChances : 1;

      final claimedGifts = <Map<String, dynamic>>[];
      for (final g in winningEval.resolvedLinkedGifts) {
        claimedGifts.add({
          'giftId': g.giftId,
          'giftName': g.giftName,
          'quantity': g.quantity,
          'unitValue': g.unitValue,
          'isVoucher': g.isVoucher,
        });
      }

      final canonical = winningEval.resolvedBranchName ?? _normalizeBranchName(rawBranch, winningCampaign.branchNames, isAr);
      final double promoSpend = winningEval.qualifyingSpend > 0 ? winningEval.qualifyingSpend : targetTotal;

      await firestore.collection('receipts_transactions').doc(docId).update({
        'is_valid': true,
        'status': 'accepted',
        'campaignId': winningCampaign.id,
        'campaign_name': winningCampaign.eventName,
        'eventName': winningCampaign.eventName,
        'unfulfilled_conditions': <String>[],
        'rejection_reason': FieldValue.delete(),
        'is_updated_via_ai': true,
        'rechecked_at': FieldValue.serverTimestamp(),
        'rechecked_by': currentUser?.email ?? 'admin',
        'recheck_type': winningCampaign.id == activeEvent.id ? 'quick_rule_match' : 'quick_multi_campaign_match',
        'target_company_total': promoSpend,
        'chances_earned': chances,
        'canonical_branch': canonical,
        'branch_detected': canonical,
        if (claimedGifts.isNotEmpty) 'claimed_gifts': claimedGifts,
      });

      if (mounted) {
        _showRecheckSuccessDialog(
          context: context,
          isAr: isAr,
          strings: strings,
          winningCampaign: winningCampaign,
          isReassignedToSisterCampaign: winningCampaign.id != activeEvent.id,
          prizeTitle: winningEval.designatedPrize,
          onViewAccepted: () {
            setState(() {
              _statusFilter = 'accepted';
              _selectedCampaignId = winningCampaign.id;
            });
          },
        );
      }
    } else {
      final unfulfilled = <String>[];
      for (final u in summary.unfulfilledCampaigns) {
        if (u.unfulfilledConditions.isNotEmpty) {
          unfulfilled.addAll(u.unfulfilledConditions);
        } else if (u.rejectionReason != null && u.rejectionReason!.isNotEmpty) {
          unfulfilled.add(u.rejectionReason!);
        }
      }
      if (unfulfilled.isEmpty) {
        unfulfilled.add(isAr ? 'الفاتورة غير مستوفية لشروط عروض الشركة' : 'Receipt conditions not met for company offers');
      }

      await firestore.collection('receipts_transactions').doc(docId).update({
        'unfulfilled_conditions': unfulfilled,
        'rejection_reason': unfulfilled.join(' • '),
        'rechecked_at': FieldValue.serverTimestamp(),
        'rechecked_by': currentUser?.email ?? 'admin',
        'recheck_type': 'quick_rule_match_failed',
      });

      if (mounted) {
        _showRecheckStillRejectedDialog(
          context,
          unfulfilled,
          isAr,
          strings,
          canRunFullAi: hasImage,
          onRunFullAi: () {
            Navigator.pop(context);
            _executeRecheck(
              inv: inv,
              event: activeEvent,
              eventsMap: eventsMap,
              isFullAiScan: true,
              strings: strings,
              colorScheme: colorScheme,
              activeCountry: activeCountry,
              isAr: isAr,
            );
          },
        );
      }
    }
  }

  Future<void> _runFullAiRecheck({
    required String docId,
    required Map<String, dynamic> inv,
    required EventModel activeEvent,
    required List<EventModel> companyEvents,
    required Map<String, EventModel> eventsMap,
    required CountryCurrency activeCountry,
    required AppStrings strings,
    required ColorScheme colorScheme,
    required bool isAr,
  }) async {
    final firestore = ref.read(firestoreProvider);
    final currentUser = ref.read(firebaseAuthProvider).currentUser;
    final aiService = ref.read(aiReceiptServiceProvider);
    final productsService = ref.read(companyProductsServiceProvider);
    final retailChainsService = ref.read(retailChainsServiceProvider);

    final imageUrl = (inv['image_url'] ?? '').toString();
    final storagePath = inv['storage_path']?.toString();

    if (imageUrl.isEmpty && (storagePath == null || storagePath.isEmpty)) {
      throw Exception(isAr ? 'لا توجد صورة مسجلة لهذه الفاتورة لإعادة الفحص بالذكاء الاصطناعي.' : 'No receipt image found for full AI scan.');
    }

    final Uint8List? imageBytes = await _downloadReceiptImageBytes(imageUrl, storagePath);
    if (imageBytes == null || imageBytes.isEmpty) {
      throw Exception(isAr ? 'تعذر تنزيل صورة الفاتورة من السيرفر.' : 'Failed to download receipt image.');
    }

    // Load knowledge context for retail chains & products
    List<String> registeredBarcodes = [];
    Map<String, String> catalogBarcodeMap = {};
    List<BranchModel> chainBranches = [];

    final companySlug = activeEvent.companySlug.isNotEmpty
        ? activeEvent.companySlug
        : (inv['companySlug'] ?? '').toString();

    try {
      final results = await Future.wait([
        productsService.getProductsForCompany(companySlug).catchError((_) => <CompanyProductItem>[]),
        retailChainsService.getBranchesForEvent(
          retailChainId: activeEvent.retailChainId,
          branchIds: activeEvent.branchIds,
          branchNames: activeEvent.branchNames,
        ).catchError((_) => <BranchModel>[]),
      ]);

      final catalogItems = results[0] as List<CompanyProductItem>;
      chainBranches = results[1] as List<BranchModel>;

      registeredBarcodes = catalogItems.map((e) => "${e.productName} (${e.barcode})").toList();
      catalogBarcodeMap = {
        for (final item in catalogItems)
          if (item.productName.isNotEmpty && item.barcode.isNotEmpty)
            item.productName: item.barcode,
      };
    } catch (_) {}

    // Combine required products, promotional rules, and branches across all active company events
    final Set<String> combinedReqProds = {};
    final Set<String> ruleIdSet = {};
    final Set<String> combinedBranches = {};
    bool combinedIsAllBranches = false;
    final List<PromotionalRuleItem> combinedPromotionalRules = [];

    for (final ev in companyEvents) {
      if (ev.isAllBranches) combinedIsAllBranches = true;
      for (final b in ev.branchNames) {
        if (b.trim().isNotEmpty) combinedBranches.add(b.trim());
      }
      for (final p in ev.requiredProducts) {
        if (p.trim().isNotEmpty) combinedReqProds.add(p.trim());
      }
      for (final r in ev.promotionalRules) {
        final key = '${ev.id}_${r.id.isNotEmpty ? r.id : r.ruleTitle}';
        if (ruleIdSet.add(key)) {
          combinedPromotionalRules.add(r);
        }
        for (final sp in r.selectedProductNames) {
          if (sp.trim().isNotEmpty) combinedReqProds.add(sp.trim());
        }
        for (final rb in r.requiredBrands) {
          if (rb.trim().isNotEmpty) combinedReqProds.add(rb.trim());
        }
      }
    }

    final result = await aiService.analyzeReceiptImage(
      imageBytes,
      'image/jpeg',
      targetCompany: activeEvent.targetCompany,
      minimumSpend: 0.0,
      requiredProducts: combinedReqProds.toList(),
      registeredBarcodes: registeredBarcodes,
      catalogBarcodeMap: catalogBarcodeMap,
      retailChainName: activeEvent.retailChainName,
      allowedBranches: combinedBranches.toList(),
      isAllBranches: combinedIsAllBranches || activeEvent.isAllBranches,
      registeredBranches: chainBranches,
      startDate: null,
      endDate: null,
      customPrompt: '',
      allowMultipleChances: true,
      multiplierBasis: 'both',
      maxChancesPerReceipt: 0,
      promotionalRules: combinedPromotionalRules,
    );

    // Multi-campaign evaluation
    final orderedCampaigns = <EventModel>[
      activeEvent,
      ...companyEvents.where((e) => e.id != activeEvent.id),
    ];

    final summary = MultiCampaignReceiptEvaluator.evaluateAll(
      result: result,
      campaigns: orderedCampaigns,
    );

    if (summary.qualifiedCampaigns.isNotEmpty) {
      final winningEval = summary.qualifiedCampaigns.firstWhere(
        (e) => e.campaign.id == activeEvent.id,
        orElse: () => summary.qualifiedCampaigns.first,
      );
      final winningCampaign = winningEval.campaign;

      final int chances = winningEval.totalChances > 0 ? winningEval.totalChances : 1;

      final claimedGifts = <Map<String, dynamic>>[];
      for (final g in winningEval.resolvedLinkedGifts) {
        claimedGifts.add({
          'giftId': g.giftId,
          'giftName': g.giftName,
          'quantity': g.quantity,
          'unitValue': g.unitValue,
          'isVoucher': g.isVoucher,
        });
      }

      final double computedTotal = result.extractedProducts.fold<double>(0.0, (acc, p) => acc + p.actualLineSpend);
      final double totalSpend = computedTotal > 0 ? computedTotal : result.targetCompanyTotal;
      final canonical = winningEval.resolvedBranchName ?? _normalizeBranchName(result.branchDetected, winningCampaign.branchNames, isAr);

      await firestore.collection('receipts_transactions').doc(docId).update({
        'is_valid': true,
        'status': 'accepted',
        'campaignId': winningCampaign.id,
        'campaign_name': winningCampaign.eventName,
        'eventName': winningCampaign.eventName,
        'unfulfilled_conditions': <String>[],
        'rejection_reason': FieldValue.delete(),
        'is_updated_via_ai': true,
        'rechecked_at': FieldValue.serverTimestamp(),
        'rechecked_by': currentUser?.email ?? 'admin',
        'recheck_type': winningCampaign.id == activeEvent.id ? 'full_ai_scan' : 'full_ai_multi_campaign_match',
        'extracted_products': result.extractedProducts.map((p) => p.toJson()).toList(),
        'target_company_total': winningEval.qualifyingSpend > 0 ? winningEval.qualifyingSpend : result.targetCompanyTotal,
        'total_value': totalSpend,
        if (result.receiptNumber.isNotEmpty) 'receipt_number': result.receiptNumber,
        if (result.storeChainDetected.isNotEmpty) 'store_chain_detected': result.storeChainDetected,
        if (result.branchDetected.isNotEmpty) 'branch_detected': result.branchDetected,
        'canonical_branch': canonical,
        'analysis_duration_seconds': result.durationSeconds,
        'ai_kpi_rating': result.kpiRating,
        'chances_earned': chances,
        if (claimedGifts.isNotEmpty) 'claimed_gifts': claimedGifts,
      });

      if (mounted) {
        _showRecheckSuccessDialog(
          context: context,
          isAr: isAr,
          strings: strings,
          winningCampaign: winningCampaign,
          isReassignedToSisterCampaign: winningCampaign.id != activeEvent.id,
          prizeTitle: winningEval.designatedPrize,
          onViewAccepted: () {
            setState(() {
              _statusFilter = 'accepted';
              _selectedCampaignId = winningCampaign.id;
            });
          },
        );
      }
    } else {
      final unfulfilledList = result.unfulfilledConditions.isNotEmpty
          ? result.unfulfilledConditions
          : (summary.unfulfilledCampaigns.isNotEmpty
              ? summary.unfulfilledCampaigns.expand((u) => u.unfulfilledConditions).toList()
              : [result.message.trim().isNotEmpty ? result.message.trim() : (isAr ? 'الفاتورة غير مطابقة لشروط عروض الشركة' : 'Receipt does not qualify for company offers')]);

      final double computedTotal = result.extractedProducts.fold<double>(0.0, (acc, p) => acc + p.actualLineSpend);
      final double totalSpend = computedTotal > 0 ? computedTotal : result.targetCompanyTotal;

      await firestore.collection('receipts_transactions').doc(docId).update({
        'is_valid': false,
        'status': 'rejected',
        'unfulfilled_conditions': unfulfilledList,
        'rejection_reason': unfulfilledList.join(' • '),
        'extracted_products': result.extractedProducts.map((p) => p.toJson()).toList(),
        'target_company_total': result.targetCompanyTotal,
        'total_value': totalSpend,
        'rechecked_at': FieldValue.serverTimestamp(),
        'rechecked_by': currentUser?.email ?? 'admin',
        'recheck_type': 'full_ai_scan_rejected',
        'analysis_duration_seconds': result.durationSeconds,
        'ai_kpi_rating': result.kpiRating,
      });

      if (mounted) {
        _showRecheckStillRejectedDialog(context, unfulfilledList, isAr, strings);
      }
    }
  }

  Future<Uint8List?> _downloadReceiptImageBytes(String imageUrl, String? storagePath) async {
    if (imageUrl.startsWith('data:image') || imageUrl.contains(';base64,')) {
      final base64String = imageUrl.contains(',') ? imageUrl.split(',').last : imageUrl;
      return base64Decode(base64String.trim());
    }

    if (storagePath != null && storagePath.isNotEmpty) {
      try {
        final storage = ref.read(firebaseStorageProvider);
        final bytes = await storage.ref(storagePath).getData(10 * 1024 * 1024);
        if (bytes != null && bytes.isNotEmpty) return bytes;
      } catch (e) {
        debugPrint('Error fetching image from storagePath: $e');
      }
    }

    if (imageUrl.startsWith('http')) {
      try {
        final response = await http.get(Uri.parse(imageUrl));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          return response.bodyBytes;
        }
      } catch (e) {
        debugPrint('Error downloading image from URL: $e');
      }
    }

    return null;
  }

  void _showRecheckSuccessDialog({
    required BuildContext context,
    required bool isAr,
    required AppStrings strings,
    EventModel? winningCampaign,
    bool isReassignedToSisterCampaign = false,
    String? prizeTitle,
    VoidCallback? onViewAccepted,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check_circle_rounded, size: 48, color: Colors.green.shade700),
        ),
        title: Text(
          isReassignedToSisterCampaign
              ? (isAr ? 'تم استيفاء الشروط وتأهيل الفاتورة!' : 'Receipt Qualified for Campaign!')
              : strings.recheckSuccessTitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isReassignedToSisterCampaign
                  ? (isAr
                      ? 'تبيّن بعد التدقيق أن الفاتورة مطابقة ومستوفاة لشروط حملة (${winningCampaign?.eventName ?? ""}) وتم اعتمادها وحصولها على الهدية بنجاح!'
                      : 'Receipt matches campaign (${winningCampaign?.eventName ?? ""}) and has been successfully approved!')
                  : strings.recheckSuccessMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(color: Colors.grey.shade700, fontSize: 13.5),
            ),
            if (prizeTitle != null && prizeTitle.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.card_giftcard_rounded, color: Colors.purple.shade700, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        prizeTitle,
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.purple.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              isAr
                  ? 'تم تحديث حالة الفاتورة ونقلها تلقائياً إلى قسم "الفواتير المقبولة" وحذف سبب الرفض.'
                  : 'Status updated: Moved automatically to "Accepted Invoices" and rejection reason cleared.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          if (onViewAccepted != null)
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                onViewAccepted();
              },
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text(
                isAr ? 'عرض الفاتورة في المقبولة' : 'View in Accepted',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isAr ? 'إغلاق' : 'Close', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  void _showRecheckStillRejectedDialog(
    BuildContext context,
    List<String> reasons,
    bool isAr,
    AppStrings strings, {
    bool canRunFullAi = false,
    VoidCallback? onRunFullAi,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange.shade800),
        ),
        title: Text(
          strings.recheckStillRejectedMessage,
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...reasons.map(
                (r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Icon(Icons.circle, size: 6, color: Colors.orange.shade800),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          r,
                          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade900, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          if (canRunFullAi && onRunFullAi != null)
            FilledButton.icon(
              onPressed: onRunFullAi,
              icon: const Icon(Icons.psychology_rounded, size: 18),
              label: Text(isAr ? 'مسح شامل بالذكاء الاصطناعي' : 'Full AI Re-Scan', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(isAr ? 'إغلاق' : 'Close', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
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
    InteractiveReceiptViewerDialog.show(
      context,
      imageUrl: imageUrl,
      receiptNumber: receiptNumber,
      storeName: store,
      totalValue: totalValue,
      date: date,
      currencySymbol: currencySymbol,
      docId: docId,
      storagePath: storagePath,
      canDelete: canDelete,
      onDelete: (canDelete && docId != null)
          ? () => _confirmAndDeleteInvoice(
                context: context,
                docId: docId,
                receiptNumber: receiptNumber,
                totalValue: totalValue,
                currencySymbol: currencySymbol,
                storagePath: storagePath,
                imageUrl: imageUrl,
                strings: strings,
                colorScheme: colorScheme,
              )
          : null,
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
    _ensureStreams(activeFirestore);

    final eventsKey = widget.lockedCompanySlug ?? 'all';
    final txKey = '${widget.lockedCompanySlug ?? 'all'}_$_selectedCampaignId';

    // Clean M3 Scaffold with NO duplicate AppBar & 0ms instant cached rendering
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: StreamBuilder<QuerySnapshot>(
        stream: _eventsStream,
        builder: (context, eventsSnapshot) {
          if (eventsSnapshot.hasData && eventsSnapshot.data!.docs.isNotEmpty) {
            final eventDocs = eventsSnapshot.data!.docs;
            final map = <String, EventModel>{};
            for (final doc in eventDocs) {
              try {
                map[doc.id] = EventModel.fromFirestore(doc);
              } catch (_) {}
            }
            _persistentEventsCache[eventsKey] = map;
          }
          final eventsMap = _persistentEventsCache[eventsKey] ?? const {};

          return StreamBuilder<QuerySnapshot>(
            stream: _transactionsStream,
            builder: (context, transactionsSnapshot) {
              if (transactionsSnapshot.hasData) {
                final docs = transactionsSnapshot.data!.docs;
                // Zero-wipe invariant: never clear existing cached records with empty transient data
                if (docs.isNotEmpty || !_persistentInvoicesCache.containsKey(txKey)) {
                  _persistentInvoicesCache[txKey] = docs;
                }
              }

              final cachedDocs = _persistentInvoicesCache[txKey];

              if (transactionsSnapshot.hasError && cachedDocs == null) {
                return Center(child: Text('${strings.error}: ${transactionsSnapshot.error}'));
              }

              if (transactionsSnapshot.connectionState == ConnectionState.waiting && cachedDocs == null) {
                return const Center(child: CircularProgressIndicator());
              }

              final rawDocs = cachedDocs ?? transactionsSnapshot.data?.docs ?? [];
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
    // 1. Scoped Events by locked company
    final scopedEvents = (widget.lockedCompanySlug != null && widget.lockedCompanySlug!.isNotEmpty)
        ? eventsMap.values.where((e) {
            final slug = e.companySlug.toLowerCase();
            final name = e.targetCompany.toLowerCase();
            return slug == widget.lockedCompanySlug!.toLowerCase() ||
                (widget.lockedCompanyName != null && name == widget.lockedCompanyName!.toLowerCase());
          }).toList()
        : eventsMap.values.toList();

    // 2. Official Canonical Branches from campaign definitions
    final List<String> canonicalBranches;
    if (_selectedCampaignId != 'all' && eventsMap.containsKey(_selectedCampaignId)) {
      final selEvt = eventsMap[_selectedCampaignId]!;
      canonicalBranches = selEvt.branchNames.where((b) => b.trim().isNotEmpty).toList();
    } else {
      canonicalBranches = scopedEvents
          .expand((e) => e.branchNames)
          .map((b) => b.trim())
          .where((b) => b.isNotEmpty)
          .toSet()
          .toList();
    }

    // Map documents to enriched representations with canonical branch resolution (O(1) memoized cache)
    final allInvoicesCacheKey = '${rawDocs.length}_${rawDocs.isEmpty ? "" : rawDocs.first.id}_${rawDocs.isEmpty ? "" : rawDocs.last.id}_${eventsMap.length}_${canonicalBranches.length}_$isAr';
    final List<Map<String, dynamic>> allInvoices;
    if (_lastAllInvoicesCacheKey == allInvoicesCacheKey && _cachedAllInvoices != null) {
      allInvoices = _cachedAllInvoices!;
    } else {
      allInvoices = rawDocs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final campaignId = data['campaignId']?.toString() ?? '';
        final event = eventsMap[campaignId];
        final eventName = event?.eventName ?? (data['campaignName']?.toString() ?? (isAr ? 'حملة عامة' : 'General Campaign'));

        final eventBranches = (event != null && event.branchNames.isNotEmpty)
            ? event.branchNames
            : canonicalBranches;

        final rawBranch = (data['branch_detected'] ?? data['branch'] ?? '').toString().trim();
        final canonicalBranch = _normalizeBranchName(rawBranch, eventBranches, isAr);

        DateTime? date;
        if (data['timestamp'] is Timestamp) {
          date = (data['timestamp'] as Timestamp).toDate();
        } else if (data['timestamp'] is String) {
          date = DateTime.tryParse(data['timestamp']);
        }

        String formattedDate = 'N/A';
        if (date != null) {
          formattedDate = DateFormat('yyyy-MM-dd hh:mm a').format(date);
        } else if (data['receipt_date'] != null) {
          final rawStr = data['receipt_date'].toString().trim();
          final parsed = DateTime.tryParse(rawStr);
          if (parsed != null) {
            formattedDate = DateFormat('yyyy-MM-dd hh:mm a').format(parsed);
          } else {
            formattedDate = rawStr;
          }
        }

        return {
          'id': doc.id,
          ...data,
          'date': date,
          'formattedDate': formattedDate,
          'eventName': eventName,
          'campaignId': campaignId,
          'raw_branch': rawBranch,
          'canonical_branch': canonicalBranch,
          'branch_detected': canonicalBranch,
        };
      }).toList()
        ..sort((a, b) {
          final tsA = a['date'] as DateTime?;
          final tsB = b['date'] as DateTime?;
          if (tsA == null) return 1;
          if (tsB == null) return -1;
          return tsB.compareTo(tsA);
        });

      _cachedAllInvoices = allInvoices;
      _lastAllInvoicesCacheKey = allInvoicesCacheKey;
    }

    // 3. Dropdown list of branches: STRICTLY CANONICAL BRANCHES
    final List<String> sortedBranches;
    if (canonicalBranches.isNotEmpty) {
      sortedBranches = List<String>.from(canonicalBranches);
    } else {
      final dynamicBranches = <String>{};
      for (final inv in allInvoices) {
        final b = inv['canonical_branch']?.toString().trim() ?? '';
        if (b.isNotEmpty) dynamicBranches.add(b);
      }
      sortedBranches = dynamicBranches.toList()..sort();
    }

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

      // 3. Branch Filter
      if (_selectedBranch != 'all') {
        final invCanonical = (inv['canonical_branch'] ?? '').toString();
        if (invCanonical != _selectedBranch) {
          return false;
        }
      }

      // 4. Date Filter
      if (!_passesDateFilter(inv['date'] as DateTime?)) {
        return false;
      }

      // 5. Status Filter (all / accepted / rejected)
      final bool isExplicitlyValid = inv['is_valid'] == true || inv['status'] == 'accepted' || inv['isValid'] == true;
      final bool isExplicitlyRejected = inv['is_valid'] == false || inv['status'] == 'rejected' || inv['isValid'] == false || ((inv['unfulfilled_conditions'] as List?)?.isNotEmpty ?? false);
      final bool isValid = isExplicitlyValid || (!isExplicitlyRejected && ((inv['unfulfilled_conditions'] as List?)?.isEmpty ?? true));

      if (_statusFilter == 'accepted' && !isValid) return false;
      if (_statusFilter == 'rejected' && isValid) return false;

      // 6. Search Query (Receipt Number, Branch, Store, Customer)
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
      final bool isExplicitlyValid = inv['is_valid'] == true || inv['status'] == 'accepted' || inv['isValid'] == true;
      final bool isExplicitlyRejected = inv['is_valid'] == false || inv['status'] == 'rejected' || inv['isValid'] == false || ((inv['unfulfilled_conditions'] as List?)?.isNotEmpty ?? false);
      final bool isValid = isExplicitlyValid || (!isExplicitlyRejected && ((inv['unfulfilled_conditions'] as List?)?.isEmpty ?? true));

      if (isValid) {
        final promoTotal = (inv['target_company_total'] ?? inv['total_value'] ?? 0);
        if (promoTotal is num) totalPromoSales += promoTotal.toDouble();

        final products = (inv['extracted_products'] as List?) ?? [];
        for (final p in products) {
          if (p is Map) {
            final qty = p['quantity'];
            totalExtractedItems += (qty is num ? qty.toInt() : 1);
          }
        }
      }

      final dur = inv['analysis_duration_seconds'];
      if (dur is num && dur > 0) {
        totalDurationSec += dur.toDouble();
        durationCount++;
      }
    }

    final avgAiSpeed = durationCount > 0 ? (totalDurationSec / durationCount) : 0.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 750;
    final bool hasActiveCampaignBanner = _selectedCampaignId != 'all' && eventsMap.containsKey(_selectedCampaignId);
    final stickyFilterHeight = _calculateStickyFilterHeight(
      screenWidth: screenWidth,
      hasActiveCampaign: hasActiveCampaignBanner,
    );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // 1. SCROLLABLE TOP HEADER & 4 KPI SUMMARY CARDS (تختفي بسلاسة مع التمرير لأسفل)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.isEmbedded)
                  PortalScreenHeaderCard(
                    icon: Icons.receipt_long_rounded,
                    title: strings.invoicesAuditTitle,
                    subtitle: strings.invoicesAuditSubtitle,
                    events: eventsMap.values.toList(),
                    selectedEventId: _selectedCampaignId == 'all' ? null : _selectedCampaignId,
                    onEventChanged: (val) {
                      setState(() {
                        _selectedCampaignId = val ?? 'all';
                        _resetPagination();
                      });
                    },
                    lockedCompanySlug: widget.lockedCompanySlug,
                    isMobile: isMobile,
                    actions: [
                      FilledButton.tonalIcon(
                        onPressed: () => _exportInvoicesToCsv(filteredInvoices, strings),
                        icon: const Icon(Icons.file_download_outlined, size: 18),
                        label: Text(strings.exportCsvBtn, style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
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
              ],
            ),
          ),

          // 2. SEARCH & FILTER CONTROLS TOOLBAR
          // On mobile: smoothly flows inside SliverToBoxAdapter with natural height (no nested scroll, no height clipping).
          // On desktop/tablet: pinned in SliverPersistentHeader.
          if (isMobile)
            SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                ),
                child: _buildFilterControls(
                  colorScheme: colorScheme,
                  strings: strings,
                  isAr: isAr,
                  eventsMap: eventsMap,
                  availableCompanies: availableCompanies,
                  availableBranches: sortedBranches,
                  allInvoices: allInvoices,
                ),
              ),
            )
          else
            SliverPersistentHeader(
              pinned: true,
              delegate: _StickyInvoicesFilterDelegate(
                height: stickyFilterHeight,
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: _buildFilterControls(
                    colorScheme: colorScheme,
                    strings: strings,
                    isAr: isAr,
                    eventsMap: eventsMap,
                    availableCompanies: availableCompanies,
                    availableBranches: sortedBranches,
                    allInvoices: allInvoices,
                  ),
                ),
              ),
            ),

          // 3. SCROLLABLE INVOICES FEED / DATA ROWS
          if (filteredInvoices.isEmpty)
            SliverToBoxAdapter(
              child: _buildEmptyState(strings, colorScheme),
            )
          else
            SliverToBoxAdapter(
              child: _buildInvoicesFeed(
                filteredInvoices: filteredInvoices,
                colorScheme: colorScheme,
                activeCountry: activeCountry,
                strings: strings,
                isAr: isAr,
                isMobile: isMobile,
                eventsMap: eventsMap,
              ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final bool isMobile = width < 600;

        int crossAxisCount = 4;
        double childAspectRatio = 1.65;
        if (width < 600) {
          crossAxisCount = 1;
          childAspectRatio = 2.3;
        } else if (width < 960) {
          crossAxisCount = 2;
          childAspectRatio = 1.85;
        } else if (width < 1200) {
          crossAxisCount = 2;
          childAspectRatio = 2.1;
        }

        final List<Widget> cards = [
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

        return Padding(
          padding: EdgeInsets.fromLTRB(isMobile ? 12 : 20, isMobile ? 8 : 16, isMobile ? 12 : 20, isMobile ? 8 : 12),
          child: GridView.count(
            crossAxisCount: crossAxisCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: isMobile ? 12 : 14,
            mainAxisSpacing: isMobile ? 12 : 14,
            childAspectRatio: childAspectRatio,
            children: cards,
          ),
        );
      },
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
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: isMobile ? 12 : 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
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
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accentColor, size: 18),
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

  Widget _buildFilterControls({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required Map<String, EventModel> eventsMap,
    required Map<String, String> availableCompanies,
    required List<String> availableBranches,
    required List<Map<String, dynamic>> allInvoices,
  }) {
    final hasActiveFilters = _searchController.text.isNotEmpty ||
        _selectedCampaignId != 'all' ||
        _selectedCompanySlug != 'all' ||
        _selectedBranch != 'all' ||
        _statusFilter != 'all' ||
        _dateFilter != DateFilterType.all;

    final scopedEventsMap = (widget.lockedCompanySlug != null && widget.lockedCompanySlug!.isNotEmpty)
        ? Map.fromEntries(eventsMap.entries.where((e) {
            final slug = e.value.companySlug.toLowerCase();
            final name = e.value.targetCompany.toLowerCase();
            return slug == widget.lockedCompanySlug!.toLowerCase() ||
                (widget.lockedCompanyName != null && name == widget.lockedCompanyName!.toLowerCase());
          }))
        : eventsMap;

    final searchFieldWidget = TextField(
      controller: _searchController,
      onChanged: (_) {
        setState(() {});
        _resetPagination();
      },
      decoration: InputDecoration(
        hintText: strings.searchReceiptPlaceholder,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: () {
                  setState(() => _searchController.clear());
                  _resetPagination();
                },
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    final statusFilterWidget = SegmentedButton<String>(
      segments: [
        ButtonSegment<String>(
          value: 'all',
          label: Text(isAr ? 'الكل' : 'All', style: GoogleFonts.cairo(fontSize: 11)),
        ),
        ButtonSegment<String>(
          value: 'accepted',
          label: Text(isAr ? 'المقبولة' : 'Accepted', style: GoogleFonts.cairo(fontSize: 11)),
          icon: const Icon(Icons.check_circle_outline_rounded, size: 14, color: Colors.green),
        ),
        ButtonSegment<String>(
          value: 'rejected',
          label: Text(isAr ? 'المرفوضة' : 'Rejected', style: GoogleFonts.cairo(fontSize: 11)),
          icon: const Icon(Icons.cancel_outlined, size: 14, color: Colors.red),
        ),
      ],
      selected: {_statusFilter},
      onSelectionChanged: (set) {
        setState(() => _statusFilter = set.first);
        _resetPagination();
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );

    final branchPickerWidget = PopupMenuButton<String>(
      initialValue: _selectedBranch,
      tooltip: isAr ? 'تصفية حسب الفرع' : 'Filter by Branch',
      onSelected: (val) {
        setState(() {
          _selectedBranch = val;
        });
        _resetPagination();
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'all',
          child: Row(
            children: [
              Icon(
                Icons.store_mall_directory_rounded,
                size: 16,
                color: _selectedBranch == 'all' ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isAr ? 'كافة الفروع (${availableBranches.length})' : 'All Branches (${availableBranches.length})',
                  style: TextStyle(
                    fontWeight: _selectedBranch == 'all' ? FontWeight.bold : FontWeight.normal,
                    color: _selectedBranch == 'all' ? colorScheme.primary : null,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${allInvoices.length}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (availableBranches.isNotEmpty) const PopupMenuDivider(),
        for (final b in availableBranches)
          () {
            final count = allInvoices.where((inv) => inv['canonical_branch'] == b).length;
            return PopupMenuItem(
              value: b,
              child: Row(
                children: [
                  Icon(
                    Icons.storefront_rounded,
                    size: 16,
                    color: _selectedBranch == b ? colorScheme.primary : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      b,
                      style: TextStyle(
                        fontWeight: _selectedBranch == b ? FontWeight.bold : FontWeight.normal,
                        color: _selectedBranch == b ? colorScheme.primary : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _selectedBranch == b
                          ? colorScheme.primary.withValues(alpha: 0.15)
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _selectedBranch == b ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_selectedBranch == b) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.check_rounded, size: 16, color: colorScheme.primary),
                  ],
                ],
              ),
            );
          }(),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _selectedBranch != 'all' ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _selectedBranch != 'all' ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.storefront_rounded,
              size: 18,
              color: _selectedBranch != 'all' ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _selectedBranch == 'all'
                    ? (isAr ? 'كافة الفروع (${availableBranches.length})' : 'All Branches (${availableBranches.length})')
                    : _selectedBranch,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _selectedBranch != 'all' ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: _selectedBranch != 'all' ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
            ),
          ],
        ),
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
          _resetPagination();
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobileLayout = constraints.maxWidth < 750;
        final isWideLayout = constraints.maxWidth >= 1350;

        return Container(
          padding: EdgeInsets.fromLTRB(isMobileLayout ? 12 : 20, 8, isMobileLayout ? 12 : 20, 8),
          color: colorScheme.surface,
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isWideLayout) ...[
                  Row(
                    children: [
                      Expanded(child: searchFieldWidget),
                      const SizedBox(width: 10),
                      statusFilterWidget,
                      const SizedBox(width: 10),
                      branchPickerWidget,
                      const SizedBox(width: 10),
                      datePickerWidget,
                      const SizedBox(width: 10),
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
                ] else if (isMobileLayout) ...[
                  // Row 1: Full-Width Search Field
                  searchFieldWidget,
                  const SizedBox(height: 8),

                  // Row 2: Full-Width Segmented Status Controls
                  SizedBox(
                    width: double.infinity,
                    child: statusFilterWidget,
                  ),
                  const SizedBox(height: 8),

                  // Row 3: 50% Branch Picker + 50% Date Picker in a balanced 2-Column Row
                  Row(
                    children: [
                      Expanded(child: branchPickerWidget),
                      const SizedBox(width: 8),
                      Expanded(child: datePickerWidget),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Row 4: Export CSV Button + Clear Filters (if active)
                  Row(
                    children: [
                      Expanded(child: exportCsvButton),
                      if (hasActiveFilters) ...[
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 42,
                          width: 42,
                          child: IconButton.filledTonal(
                            tooltip: strings.clearFiltersBtn,
                            icon: const Icon(Icons.filter_alt_off_rounded, color: Colors.red, size: 18),
                            onPressed: _resetFilters,
                            style: IconButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ] else ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: constraints.maxWidth > 950 ? 280 : 220,
                        child: searchFieldWidget,
                      ),
                      statusFilterWidget,
                      branchPickerWidget,
                      datePickerWidget,
                      exportCsvButton,
                      if (hasActiveFilters) ...[
                        SizedBox(
                          height: 42,
                          width: 42,
                          child: IconButton.filledTonal(
                            tooltip: strings.clearFiltersBtn,
                            icon: const Icon(Icons.filter_alt_off_rounded, color: Colors.red, size: 18),
                            onPressed: _resetFilters,
                            style: IconButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                _buildCampaignSelectorSection(
                  context: context,
                  colorScheme: colorScheme,
                  strings: strings,
                  isAr: isAr,
                  scopedEventsMap: scopedEventsMap,
                  availableCompanies: availableCompanies,
                  allInvoices: allInvoices,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCampaignSelectorSection({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required Map<String, EventModel> scopedEventsMap,
    required Map<String, String> availableCompanies,
    required List<Map<String, dynamic>> allInvoices,
  }) {
    final isMobile = MediaQuery.of(context).size.width < 750;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedCampaignId != 'all' && scopedEventsMap.containsKey(_selectedCampaignId)) ...[
          () {
            final activeEvent = scopedEventsMap[_selectedCampaignId]!;
            final count = allInvoices.where((inv) => inv['campaignId'] == activeEvent.id).length;
            final isActive = activeEvent.isActive && !activeEvent.isExpired;

            if (isMobile) {
              // Mobile Layout for Active Campaign Card: Clean vertical stacking with zero overflow
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.6), width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.campaign_rounded, color: colorScheme.onPrimary, size: 16),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isAr ? 'الفعالية المحددة:' : 'Active Festival:',
                          style: GoogleFonts.cairo(
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
                            style: GoogleFonts.cairo(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: isActive ? Colors.green.shade900 : Colors.grey.shade800,
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton.filledTonal(
                          tooltip: isAr ? 'عرض كافة الفعاليات' : 'Show All Campaigns',
                          icon: const Icon(Icons.close_rounded, size: 16),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            setState(() {
                              _selectedCampaignId = 'all';
                              _resetPagination();
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      activeEvent.eventName,
                      style: GoogleFonts.cairo(fontSize: 13.5, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${activeEvent.targetCompany} • ${activeEvent.retailChainName} • ($count ${isAr ? "فاتورة" : "receipts"})',
                      style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
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
                        label: Text(
                          isAr ? 'تغيير الفعالية' : 'Change Campaign',
                          style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            // Desktop Layout for Active Campaign Banner
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isActive ? Colors.green.shade900 : Colors.grey.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          activeEvent.eventName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${activeEvent.targetCompany} • ${activeEvent.retailChainName} • ($count ${isAr ? "فاتورة" : "receipts"})',
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
        if (isMobile) ...[
          // Mobile: Full Width Filter Button + Quick Choice Chips with Wrap
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
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
                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: Text(
                  '${strings.allCampaigns} (${allInvoices.length})',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: _selectedCampaignId == 'all' ? FontWeight.bold : FontWeight.w600,
                  ),
                ),
                selected: _selectedCampaignId == 'all',
                onSelected: (_) => setState(() {
                  _selectedCampaignId = 'all';
                  _resetPagination();
                }),
                showCheckmark: false,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                selectedColor: colorScheme.primaryContainer,
                side: BorderSide(
                  color: _selectedCampaignId == 'all'
                      ? colorScheme.primary.withValues(alpha: 0.8)
                      : colorScheme.outlineVariant.withValues(alpha: 0.8),
                  width: 1.1,
                ),
              ),
              for (final entry in scopedEventsMap.entries.take(3)) ...[
                () {
                  final event = entry.value;
                  final count = allInvoices.where((inv) => inv['campaignId'] == event.id).length;
                  final isSel = _selectedCampaignId == event.id;
                  return ChoiceChip(
                    avatar: CircleAvatar(
                      radius: 9,
                      backgroundColor: isSel
                          ? colorScheme.primary.withValues(alpha: 0.2)
                          : colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.campaign_rounded,
                        size: 11,
                        color: isSel ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    label: Text(
                      '${event.eventName} ($count)',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                      ),
                    ),
                    selected: isSel,
                    onSelected: (_) => setState(() {
                      _selectedCampaignId = event.id;
                      _resetPagination();
                    }),
                    showCheckmark: false,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    selectedColor: colorScheme.primaryContainer,
                    side: BorderSide(
                      color: isSel
                          ? colorScheme.primary.withValues(alpha: 0.8)
                          : colorScheme.outlineVariant.withValues(alpha: 0.8),
                      width: 1.1,
                    ),
                  );
                }(),
              ],
            ],
          ),
        ] else ...[
          // Desktop / Tablet Horizontal Bar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
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
                    style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 8),

                ChoiceChip(
                  label: Text(
                    '${strings.allCampaigns} (${allInvoices.length})',
                    style: GoogleFonts.cairo(
                      fontSize: 11.5,
                      fontWeight: _selectedCampaignId == 'all' ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                  selected: _selectedCampaignId == 'all',
                  onSelected: (_) => setState(() {
                    _selectedCampaignId = 'all';
                    _resetPagination();
                  }),
                  showCheckmark: false,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  selectedColor: colorScheme.primaryContainer,
                  side: BorderSide(
                    color: _selectedCampaignId == 'all'
                        ? colorScheme.primary.withValues(alpha: 0.8)
                        : colorScheme.outlineVariant.withValues(alpha: 0.8),
                    width: 1.1,
                  ),
                ),
                const SizedBox(width: 6),

                for (final entry in scopedEventsMap.entries.take(4)) ...[
                  () {
                    final event = entry.value;
                    final count = allInvoices.where((inv) => inv['campaignId'] == event.id).length;
                    final isSel = _selectedCampaignId == event.id;
                    return Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: ChoiceChip(
                        avatar: CircleAvatar(
                          radius: 10,
                          backgroundColor: isSel
                              ? colorScheme.primary.withValues(alpha: 0.2)
                              : colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.campaign_rounded,
                            size: 12,
                            color: isSel ? colorScheme.primary : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        label: Text(
                          '${event.eventName} ($count)',
                          style: GoogleFonts.cairo(
                            fontSize: 11.5,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                          ),
                        ),
                        selected: isSel,
                        onSelected: (_) => setState(() {
                          _selectedCampaignId = event.id;
                          _resetPagination();
                        }),
                        showCheckmark: false,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        selectedColor: colorScheme.primaryContainer,
                        side: BorderSide(
                          color: isSel
                              ? colorScheme.primary.withValues(alpha: 0.8)
                              : colorScheme.outlineVariant.withValues(alpha: 0.8),
                          width: 1.1,
                        ),
                      ),
                    );
                  }(),
                ],

                if (availableCompanies.length > 1 && (widget.lockedCompanySlug == null || widget.lockedCompanySlug!.isEmpty)) ...[
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: Text(
                      '${strings.companyField}:',
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                  ChoiceChip(
                    label: Text(
                      strings.allCampaigns,
                      style: GoogleFonts.cairo(
                        fontSize: 11.5,
                        fontWeight: _selectedCompanySlug == 'all' ? FontWeight.bold : FontWeight.w600,
                      ),
                    ),
                    selected: _selectedCompanySlug == 'all',
                    onSelected: (_) => setState(() {
                      _selectedCompanySlug = 'all';
                      _resetPagination();
                    }),
                    showCheckmark: false,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    selectedColor: colorScheme.primaryContainer,
                    side: BorderSide(
                      color: _selectedCompanySlug == 'all'
                          ? colorScheme.primary.withValues(alpha: 0.8)
                          : colorScheme.outlineVariant.withValues(alpha: 0.8),
                      width: 1.1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  for (final comp in availableCompanies.entries) ...[
                    () {
                      final isSel = _selectedCompanySlug == comp.key;
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: ChoiceChip(
                          label: Text(
                            comp.value,
                            style: GoogleFonts.cairo(
                              fontSize: 11.5,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                            ),
                          ),
                          selected: isSel,
                          onSelected: (_) => setState(() {
                            _selectedCompanySlug = comp.key;
                            _resetPagination();
                          }),
                          showCheckmark: false,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          selectedColor: colorScheme.primaryContainer,
                          side: BorderSide(
                            color: isSel
                                ? colorScheme.primary.withValues(alpha: 0.8)
                                : colorScheme.outlineVariant.withValues(alpha: 0.8),
                            width: 1.1,
                          ),
                        ),
                      );
                    }(),
                  ],
                ],
              ],
            ),
          ),
        ],
      ],
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
                              } else if (event.gameType == 'chooseGift') {
                                gameTypeLabel = isAr ? 'اختر هديتك' : 'Choose Gift';
                                gameIcon = Icons.grid_view_rounded;
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
              icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
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
    required bool isMobile,
    required Map<String, EventModel> eventsMap,
  }) {
    final isAdmin = ref.watch(isAdminProvider) && !widget.isEmbedded;
    final totalItems = filteredInvoices.length;

    // Desktop fixed-page slicing (25 items) vs Mobile progressive batch limit
    final int safePage;
    final int totalPages;
    final List<Map<String, dynamic>> visibleInvoices;

    if (isMobile) {
      safePage = 0;
      totalPages = (totalItems / _pageSize).ceil();
      visibleInvoices = filteredInvoices.take(_mobileLimit).toList();
    } else {
      totalPages = (totalItems / _pageSize).ceil();
      safePage = _currentPage.clamp(0, totalPages > 0 ? totalPages - 1 : 0);
      final startIndex = safePage * _pageSize;
      final endIndex = (startIndex + _pageSize).clamp(0, totalItems);
      visibleInvoices = filteredInvoices.sublist(startIndex, endIndex);
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(isMobile ? 12 : 20, 12, isMobile ? 12 : 20, isMobile ? 96 : 32),
      itemCount: visibleInvoices.length + 1,
      itemBuilder: (context, index) {
        if (index == visibleInvoices.length) {
          if (isMobile) {
            return _buildMobileLoadMoreFooter(
              totalItems: totalItems,
              currentLimit: _mobileLimit,
              colorScheme: colorScheme,
              isAr: isAr,
              onLoadMore: () => setState(() => _mobileLimit += _pageSize),
            );
          } else {
            return _buildPaginationControls(
              totalItems: totalItems,
              currentPage: safePage,
              pageSize: _pageSize,
              colorScheme: colorScheme,
              strings: strings,
              isAr: isAr,
              onPageChanged: (newPage) {
                setState(() => _currentPage = newPage);
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              },
            );
          }
        }

        final inv = visibleInvoices[index];
        final campaignId = (inv['campaignId'] ?? '').toString();
        final event = eventsMap[campaignId];
        return _buildInvoiceCard(
          context: context,
          inv: inv,
          event: event,
          eventsMap: eventsMap,
          colorScheme: colorScheme,
          activeCountry: activeCountry,
          strings: strings,
          isAr: isAr,
          isMobile: isMobile,
          isAdmin: isAdmin,
        );
      },
    );
  }

  Widget _buildInvoiceCard({
    required BuildContext context,
    required Map<String, dynamic> inv,
    required EventModel? event,
    required Map<String, EventModel> eventsMap,
    required ColorScheme colorScheme,
    required CountryCurrency activeCountry,
    required AppStrings strings,
    required bool isAr,
    required bool isMobile,
    required bool isAdmin,
  }) {
    final docId = inv['id'] as String;
    final isExpanded = _expandedDocIds.contains(docId);
    final isRechecking = _recheckingDocIds.contains(docId);

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

    final bool isExplicitlyValid = inv['is_valid'] == true || inv['status'] == 'accepted' || inv['isValid'] == true;
    final bool isExplicitlyRejected = inv['is_valid'] == false || inv['status'] == 'rejected' || inv['isValid'] == false || ((inv['unfulfilled_conditions'] as List?)?.isNotEmpty ?? false);
    final bool isValid = isExplicitlyValid || (!isExplicitlyRejected && ((inv['unfulfilled_conditions'] as List?)?.isEmpty ?? true));

    final List<String> displayReasons = [];
    if (!isValid) {
      final rawConditions = (inv['unfulfilled_conditions'] as List?)?.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() ?? <String>[];
      final rawRejectionReason = (inv['rejection_reason'] ?? '').toString().trim();
      final rawFraudReasons = (inv['fraud_reasons'] as List?)?.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() ?? <String>[];
      final rawAiMessage = (inv['aiMessage'] ?? '').toString().trim();

      for (final c in rawConditions) {
        if (!displayReasons.contains(c)) displayReasons.add(c);
      }
      if (rawRejectionReason.isNotEmpty && !displayReasons.contains(rawRejectionReason)) {
        if (rawRejectionReason.contains(' • ')) {
          for (final part in rawRejectionReason.split(' • ')) {
            final p = part.trim();
            if (p.isNotEmpty && !displayReasons.contains(p)) displayReasons.add(p);
          }
        } else {
          displayReasons.add(rawRejectionReason);
        }
      }
      for (final f in rawFraudReasons) {
        if (!displayReasons.contains(f)) displayReasons.add(f);
      }

      // Dynamic rule deduction if no explicit reason was logged
      if (displayReasons.isEmpty) {
        if (event != null) {
          final promoRules = event.promotionalRules;
          final minSpend = event.minimumSpend;
          final targetTotal = (inv['target_company_total'] ?? inv['total_value'] ?? 0) is num
              ? (inv['target_company_total'] ?? inv['total_value'] as num).toDouble()
              : 0.0;

          if (event.isExpired) {
            displayReasons.add(isAr ? 'انتهت فترة سريان الحملة الترويجية.' : 'Campaign has expired.');
          }
          if (event.isNotStartedYet) {
            displayReasons.add(isAr ? 'لم تبدأ فترة هذه الحملة الترويجية بعد.' : 'Campaign has not started yet.');
          }

          final rawBranch = (inv['raw_branch'] ?? inv['branch_detected'] ?? '').toString();
          final canonical = _normalizeBranchName(rawBranch, event.branchNames, isAr);
          final bool isBranchMatched = event.isAllBranches || event.branchNames.isEmpty ||
              event.branchNames.any((b) => _cleanBranchForComparison(b) == _cleanBranchForComparison(canonical));
          if (!isBranchMatched) {
            displayReasons.add(isAr
                ? 'الفرع ($canonical) غير مسجل ضمن الفروع المعتمدة للحملة.'
                : 'Branch ($canonical) is not among approved campaign branches.');
          }

          if (promoRules.isNotEmpty) {
            final rawProducts = (inv['extracted_products'] as List?) ?? [];
            final items = rawProducts
                .map((p) => p is Map ? ExtractedProductItem.fromJson(Map<String, dynamic>.from(p)) : null)
                .whereType<ExtractedProductItem>()
                .toList();
            final unfulfilled = PromotionalRuleMatcher.getUnfulfilledPromotionReasons(
              extractedProducts: items,
              promotionalRules: promoRules,
            );
            displayReasons.addAll(unfulfilled);
          } else if (minSpend > 0 && targetTotal < minSpend) {
            displayReasons.add(isAr
                ? 'إجمالي مشتريات منتجات الحملة ($targetTotal ${activeCountry.currencySymbol}) أقل من الحد الأدنى المطلوب (${minSpend.toInt()} ${activeCountry.currencySymbol}).'
                : 'Target purchases ($targetTotal) is below minimum spend ($minSpend).');
          }
        }

        if (displayReasons.isEmpty) {
          if (rawAiMessage.isNotEmpty && (rawAiMessage.contains('غير') || rawAiMessage.contains('رفض') || rawAiMessage.contains('نقص') || rawAiMessage.contains('لا '))) {
            displayReasons.add(rawAiMessage);
          } else {
            displayReasons.add(isAr ? 'الفاتورة غير مستوفية للشروط والأحكام الخاصة بالعرض.' : 'Receipt does not satisfy campaign promotional conditions.');
          }
        }
      }
    }

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

                // Middle Column: Receipt #, Speed Badge, Store, Status, Customer Info, Date
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Row 1: Receipt Number with Copy Action & Speed Badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
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
                          if (durationSec != null) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message: kpiRating ?? (durationSec <= 2.0 ? '⚡ فائق السرعة' : '🟢 ممتاز'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                                      size: 12,
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

                      // Row 2: Store / Branch Tag
                      if (storeChain.isNotEmpty || branch.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.storefront_rounded, size: 12, color: Colors.blue.shade800),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  branch.isNotEmpty ? '$storeChain - $branch' : storeChain,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade900,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 5),

                      // Row 3: Event & Company & Status Chips Row
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: isValid ? Colors.green.shade50 : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: isValid ? Colors.green.shade300 : Colors.red.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isValid ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                  size: 12,
                                  color: isValid ? Colors.green.shade800 : Colors.red.shade800,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isValid ? (isAr ? 'مقبولة' : 'Valid') : (isAr ? 'مرفوضة' : 'Rejected'),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: isValid ? Colors.green.shade900 : Colors.red.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (eventName.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                eventName,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 5),

                      // Row 4: Customer Info (if available) & Date
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (customerName != null && customerName.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.person_outline_rounded, size: 12, color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 3),
                                Text(
                                  customerName,
                                  style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          if (customerPhone != null && customerPhone.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.phone_outlined, size: 12, color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 3),
                                Text(
                                  customerPhone,
                                  style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.access_time_rounded, size: 12, color: colorScheme.onSurfaceVariant),
                              const SizedBox(width: 3),
                              Text(
                                formattedDate,
                                style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ],
                      ),

                      // Row 5: Rejection Reason Alert Box (When !isValid)
                      if (!isValid) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(Icons.report_problem_rounded, size: 16, color: Colors.red.shade800),
                                  const SizedBox(width: 6),
                                  Text(
                                    strings.rejectionReasonLabel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade900,
                                    ),
                                  ),
                                  const Spacer(),
                                  // Quick Re-verify Pill Button
                                  TextButton.icon(
                                    onPressed: isRechecking
                                        ? null
                                        : () => _promptRecheckOptions(
                                              context: context,
                                              inv: inv,
                                              event: event,
                                              eventsMap: eventsMap,
                                              strings: strings,
                                              colorScheme: colorScheme,
                                              activeCountry: activeCountry,
                                              isAr: isAr,
                                            ),
                                    icon: isRechecking
                                        ? SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.red.shade900,
                                            ),
                                          )
                                        : Icon(Icons.sync_rounded, size: 14, color: Colors.red.shade900),
                                    label: Text(
                                      isRechecking ? strings.recheckingReceiptLoading : strings.recheckInvoiceAction,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red.shade900,
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: Colors.red.shade100,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ...displayReasons.map(
                                (reason) => Padding(
                                  padding: const EdgeInsets.only(top: 2, bottom: 2),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(top: 5),
                                        child: Icon(Icons.circle, size: 5, color: Colors.red.shade700),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          reason,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: const Color(0xFF5C0000),
                                            fontWeight: FontWeight.w500,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
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
              ],
            ),
          ),

          // Bottom Action Bar: Spend Total + Expand Button + Admin Delete Action
          Builder(
            builder: (context) {
              final isCardMobile = MediaQuery.of(context).size.width < 680;
              final itemsBtnLabel = isCardMobile
                  ? '${isAr ? "الأصناف" : "Items"} (${products.length})'
                  : '${strings.viewReceiptProducts} (${products.length} ${strings.itemsCountLabel})';

              return Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isCardMobile ? 10 : 14,
                  vertical: isCardMobile ? 8 : 10,
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
                              fontSize: isCardMobile ? 10 : 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '$totalValue ${activeCountry.currencySymbol}',
                            style: TextStyle(
                              fontSize: isCardMobile ? 14 : 16,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Recheck Action Button for Rejected Invoices
                    if (!isValid) ...[
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: isRechecking
                            ? null
                            : () => _promptRecheckOptions(
                                  context: context,
                                  inv: inv,
                                  event: event,
                                  eventsMap: eventsMap,
                                  strings: strings,
                                  colorScheme: colorScheme,
                                  activeCountry: activeCountry,
                                  isAr: isAr,
                                ),
                        icon: isRechecking
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.amber.shade900,
                                ),
                              )
                            : Icon(Icons.sync_rounded, size: isCardMobile ? 16 : 18),
                        label: Text(
                          isCardMobile ? strings.recheckInvoiceAction : '${strings.recheckInvoiceAction} 🔄',
                          style: TextStyle(
                            fontSize: isCardMobile ? 11 : 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.amber.shade100,
                          foregroundColor: const Color(0xFF452700),
                          padding: EdgeInsets.symmetric(
                            horizontal: isCardMobile ? 8 : 12,
                            vertical: isCardMobile ? 6 : 8,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],

                    const SizedBox(width: 8),

                    // Items Count Button with Expand action
                    OutlinedButton.icon(
                      onPressed: () => _toggleExpand(docId),
                      icon: Icon(
                        isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        size: isCardMobile ? 16 : 18,
                      ),
                      label: Text(
                        itemsBtnLabel,
                        style: TextStyle(
                          fontSize: isCardMobile ? 11 : 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          horizontal: isCardMobile ? 8 : 12,
                          vertical: isCardMobile ? 6 : 8,
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
                        icon: Icon(Icons.delete_outline_rounded, color: colorScheme.error, size: isCardMobile ? 18 : 20),
                        style: IconButton.styleFrom(
                          side: BorderSide(color: colorScheme.error.withValues(alpha: 0.4)),
                          backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.2),
                          padding: EdgeInsets.all(isCardMobile ? 6 : 8),
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
  }

  Widget _buildPaginationControls({
    required int totalItems,
    required int currentPage,
    required int pageSize,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required ValueChanged<int> onPageChanged,
  }) {
    if (totalItems <= pageSize) return const SizedBox.shrink();

    final totalPages = (totalItems / pageSize).ceil();
    final startItem = (currentPage * pageSize) + 1;
    final endItem = ((currentPage + 1) * pageSize).clamp(0, totalItems);

    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Range & Total summary
          Text(
            isAr
                ? 'عرض $startItem-$endItem من إجمالي $totalItems'
                : 'Showing $startItem-$endItem of $totalItems',
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
          ),

          // Navigation Controls
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // First Page
              Tooltip(
                message: isAr ? 'الصفحة الأولى' : 'First Page',
                child: IconButton.filledTonal(
                  icon: Icon(
                    isAr ? Icons.last_page_rounded : Icons.first_page_rounded,
                    size: 18,
                  ),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: currentPage > 0 ? () => onPageChanged(0) : null,
                ),
              ),
              const SizedBox(width: 4),

              // Previous Page
              Tooltip(
                message: isAr ? 'الصفحة السابقة' : 'Previous Page',
                child: IconButton.filledTonal(
                  icon: Icon(
                    isAr ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
                    size: 18,
                  ),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: currentPage > 0 ? () => onPageChanged(currentPage - 1) : null,
                ),
              ),
              const SizedBox(width: 8),

              // Current Page Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  isAr
                      ? 'صفحة ${currentPage + 1} من $totalPages'
                      : 'Page ${currentPage + 1} of $totalPages',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Next Page
              Tooltip(
                message: isAr ? 'الصفحة التالية' : 'Next Page',
                child: IconButton.filledTonal(
                  icon: Icon(
                    isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                    size: 18,
                  ),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: currentPage < totalPages - 1
                      ? () => onPageChanged(currentPage + 1)
                      : null,
                ),
              ),
              const SizedBox(width: 4),

              // Last Page
              Tooltip(
                message: isAr ? 'الصفحة الأخيرة' : 'Last Page',
                child: IconButton.filledTonal(
                  icon: Icon(
                    isAr ? Icons.first_page_rounded : Icons.last_page_rounded,
                    size: 18,
                  ),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: currentPage < totalPages - 1
                      ? () => onPageChanged(totalPages - 1)
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLoadMoreFooter({
    required int totalItems,
    required int currentLimit,
    required ColorScheme colorScheme,
    required bool isAr,
    required VoidCallback onLoadMore,
  }) {
    if (totalItems <= _pageSize) return const SizedBox.shrink();

    final hasMore = currentLimit < totalItems;
    final remaining = totalItems - currentLimit;

    if (hasMore) {
      return Container(
        margin: const EdgeInsets.only(top: 14, bottom: 24),
        child: Center(
          child: FilledButton.tonalIcon(
            onPressed: onLoadMore,
            icon: const Icon(Icons.expand_more_rounded, size: 18),
            label: Text(
              isAr
                  ? 'عرض 25 فاتورة إضافية (متبقي $remaining من $totalItems)'
                  : 'Load 25 More Invoices ($remaining of $totalItems remaining)',
              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      );
    } else {
      return Container(
        margin: const EdgeInsets.only(top: 14, bottom: 24),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, size: 16, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Text(
              isAr
                  ? 'تم عرض كافة الـ $totalItems فاتورة بالكامل'
                  : 'All $totalItems invoices displayed',
              style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (totalItems > 5) ...[
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

  static double _calculateStickyFilterHeight({
    required double screenWidth,
    required bool hasActiveCampaign,
  }) {
    if (screenWidth < 750) {
      return hasActiveCampaign ? 340.0 : 250.0;
    } else if (screenWidth < 1350) {
      return hasActiveCampaign ? 260.0 : 175.0;
    } else {
      return hasActiveCampaign ? 220.0 : 130.0;
    }
  }
}

class _StickyInvoicesFilterDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  _StickyInvoicesFilterDelegate({
    required this.height,
    required this.child,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant _StickyInvoicesFilterDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}
