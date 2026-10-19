import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';
import 'package:csv/csv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';

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
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/m3_adaptive_scaffold.dart';
import '../../../core/widgets/m3_date_range_picker_dialog.dart';
import '../../../core/widgets/m3_list_tile.dart';
import '../../../core/widgets/m3_action_menu.dart';
import '../../../core/widgets/m3_button_groups.dart';
import 'package:http/http.dart' as http;
import '../../games/presentation/choose_gift_screen.dart';
import '../../games/presentation/spin_the_wheel_screen.dart';
import '../../games/presentation/scratch_card_screen.dart';
import '../../games/presentation/direct_gift_claim_screen.dart';
import '../../admin/presentation/ai_brain_rules_screen.dart';

enum DateFilterType { all, today, thisMonth, custom }

class InvoicesLogScreen extends ConsumerStatefulWidget {
  final String? lockedCompanySlug;
  final String? lockedCompanyName;
  final String? initialEventId;
  final String? lockedEventId;
  final bool isEmbedded;

  const InvoicesLogScreen({
    super.key,
    this.lockedCompanySlug,
    this.lockedCompanyName,
    this.initialEventId,
    this.lockedEventId,
    this.isEmbedded = false,
  });

  @override
  ConsumerState<InvoicesLogScreen> createState() => _InvoicesLogScreenState();
}

class _InvoicesLogScreenState extends ConsumerState<InvoicesLogScreen> {
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  static const int _pageSize = 25;
  int _currentPage = 0;
  int _mobileLimit = 25;
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;

  final TextEditingController _searchController = TextEditingController();
  String _selectedCampaignId = 'all';
  String _selectedCompanySlug = 'all';
  String _selectedBranch = 'all';
  String _statusFilter = 'accepted'; // 'accepted', 'rejected', 'all'
  DateFilterType _dateFilter = DateFilterType.today;
  DateTimeRange? _customDateRange;
  final Set<String> _expandedDocIds = <String>{};
  final Set<String> _recheckingDocIds = <String>{};
  bool _isBranchChartExpanded = true;
  int _branchChartViewMode = 0; // 0: Ranked Bars, 1: fl_chart BarChart
  String? _selectedDocId; // Active selected invoice in M3ListDetailLayout
  final GlobalKey _feedKey = GlobalKey(); // Key to anchor sticky detail pane calculations

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
  int _invoicesRevisionCounter = 0;

  void _ensureStreams(FirebaseFirestore? firestore, {bool force = false}) {
    if (firestore == null) return;
    final isLocked = widget.lockedCompanySlug != null && widget.lockedCompanySlug!.isNotEmpty;
    final isCampaignLocked = widget.lockedEventId != null && widget.lockedEventId!.isNotEmpty;
    final effectiveCampaignId = isCampaignLocked ? widget.lockedEventId! : _selectedCampaignId;
    final effectiveKey = '${widget.lockedCompanySlug ?? 'all'}_$effectiveCampaignId';

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
      if (effectiveCampaignId != 'ALL' && effectiveCampaignId != 'all' && effectiveCampaignId.isNotEmpty) {
        transactionsQuery = transactionsQuery.where('campaignId', isEqualTo: effectiveCampaignId);
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
    final effectiveInitialEventId = (widget.lockedEventId != null && widget.lockedEventId!.isNotEmpty)
        ? widget.lockedEventId
        : widget.initialEventId;
    if (effectiveInitialEventId != null && effectiveInitialEventId.isNotEmpty) {
      _selectedCampaignId = effectiveInitialEventId;
    }
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant InvoicesLogScreen oldWidget) {
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
        _selectedCampaignId = effectiveEventId;
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
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final picked = await showM3DateRangePicker(
      context: context,
      initialStartDate: _customDateRange?.start,
      initialEndDate: _customDateRange?.end,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      isAr: isAr,
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
      _selectedCampaignId = (widget.lockedEventId != null && widget.lockedEventId!.isNotEmpty)
          ? widget.lockedEventId!
          : 'all';
      _selectedCompanySlug = widget.lockedCompanySlug ?? 'all';
      _selectedBranch = 'all';
      _statusFilter = 'accepted';
      _dateFilter = DateFilterType.today;
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
          content: Text(strings.isAr ? 'تم نسخ البيانات بصيغة CSV للحافظة بنجاح' : 'Invoices data copied as CSV to clipboard'),
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
        color: colorScheme.surfaceContainerLow,
        child: Center(
          child: Icon(Icons.receipt_long_rounded, size: 28, color: colorScheme.outline),
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
                  color: colorScheme.surfaceContainerLow,
                  child: Center(child: Icon(Icons.broken_image_rounded, size: 28, color: colorScheme.outline)),
                ),
        );
      } catch (_) {
        return Container(
          width: width,
          height: height,
          color: colorScheme.surfaceContainerLow,
          child: Center(child: Icon(Icons.broken_image_rounded, size: 28, color: colorScheme.outline)),
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
              color: colorScheme.surfaceContainerLow,
              child: Center(child: Icon(Icons.broken_image_rounded, size: 28, color: colorScheme.outline)),
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

      setState(() {
        _invoicesRevisionCounter++;
        _cachedAllInvoices = null;
        _lastAllInvoicesCacheKey = null;
      });

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
          backgroundColor: colorScheme.onTertiaryFixedVariant,
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
    if (widget.isEmbedded || !ref.read(isAdminProvider)) return;

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
                  color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colorScheme.primaryFixedDim),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.bolt_rounded, color: colorScheme.onSecondaryContainer, size: 22),
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
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: colorScheme.secondaryFixedDim,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isAr ? '⚡ فوري' : '⚡ Instant',
                                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: colorScheme.onSecondaryContainer),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isAr
                                ? 'إعادة التحقق الذكي الفوري من شروط الحملة وعروض الشركة المرتبطة وفق القواعد'
                                : strings.quickRecheckSubtitle,
                            style: TextStyle(fontSize: 11, color: colorScheme.onSecondaryContainer, height: 1.3),
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

            if (!widget.isEmbedded && ref.read(isAdminProvider)) ...[
              const SizedBox(height: 10),

              // Option 3: Interactive AI Brain Co-Pilot Studio
              InkWell(
                onTap: () {
                  Navigator.pop(dialogCtx);
                  _openAiBrainCoPilotForInvoice(
                    context: context,
                    inv: inv,
                    event: event,
                    strings: strings,
                    isAr: isAr,
                  );
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.08),
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
                                    isAr ? 'تشخيص في استوديو عقل الذكاء الاصطناعي' : 'Diagnose in AI Brain Studio',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
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
                                    isAr ? '🧠 تفاعلي' : '🧠 Co-Pilot',
                                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              isAr
                                  ? 'فتح شات تفاعلي مباشر مع Gemini 3.7 Flash لتشخيص سبب الرفض وتدريب الذكاء فوراً واعتماد المعيار'
                                  : 'Interactive chat with Gemini 3.7 Flash to diagnose rejections and deploy new directives',
                              style: TextStyle(fontSize: 11, color: colorScheme.onPrimaryFixedVariant, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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

  void _openAiBrainCoPilotForInvoice({
    required BuildContext context,
    required Map<String, dynamic> inv,
    required EventModel? event,
    required AppStrings strings,
    required bool isAr,
  }) {
    final receiptNumber = inv['receipt_number']?.toString() ?? 'N/A';
    final storeChain = (inv['store_chain_detected'] ?? inv['retail_chain_name'] ?? '').toString();
    final branch = (inv['branch_detected'] ?? '').toString();
    final eventName = event?.eventName ?? inv['eventName']?.toString() ?? '';
    final reasons = (inv['unfulfilled_conditions'] as List?)?.join('\n- ') ?? inv['rejection_reason']?.toString() ?? '';
    final rawProducts = (inv['extracted_products'] as List?) ?? [];
    final productsStr = rawProducts.map((p) {
      if (p is Map) {
        return '${p['name']} (${p['quantity']} × ${p['price']} ج.م)';
      }
      return p.toString();
    }).join('\n- ');
    final imageUrl = inv['image_url']?.toString();
    final List<String> imageUrls = [];
    if (inv['image_urls'] is List && (inv['image_urls'] as List).isNotEmpty) {
      imageUrls.addAll((inv['image_urls'] as List).map((e) => e.toString()).where((e) => e.isNotEmpty));
    }
    if (imageUrls.isEmpty && imageUrl != null && imageUrl.isNotEmpty) {
      imageUrls.add(imageUrl);
    }

    final invoiceContext = '''
رقم الفاتورة: #$receiptNumber
السلسلة والفرع: $storeChain ($branch)
الحملة: $eventName
أسباب الرفض المسجلة:
- ${reasons.isNotEmpty ? reasons : 'غير محددة'}
المنتجات المستخرجة في الفاتورة:
${productsStr.isNotEmpty ? '- $productsStr' : 'لا توجد منتجات مستخرجة'}
''';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiBrainRulesScreen(
          initialTabIndex: 1, // Open AI Brain Co-Pilot Studio Tab directly
          initialInvoiceContext: invoiceContext,
          initialInvoiceImageUrl: imageUrl,
          initialInvoiceImageUrls: imageUrls.isNotEmpty ? imageUrls : null,
        ),
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

      final bool isInteractiveReward = (winningCampaign.gameType.trim().toLowerCase() == 'choosegift') ||
          (winningCampaign.gameType.trim().toLowerCase() == 'wheel') ||
          (winningCampaign.gameType.trim().toLowerCase() == 'scratch') ||
          (winningCampaign.gameType.trim().toLowerCase() == 'scratchcard') ||
          (winningEval.resolvedLinkedGifts.length > 1 && winningCampaign.gameType.trim().toLowerCase() != 'directgift');

      final claimedGifts = <Map<String, dynamic>>[];
      if (!isInteractiveReward) {
        for (final g in winningEval.resolvedLinkedGifts) {
          claimedGifts.add({
            'giftId': g.giftId,
            'giftName': g.giftName,
            'quantity': g.quantity,
            'unitValue': g.unitValue,
            'isVoucher': g.isVoucher,
          });
        }
      }

      final canonical = winningEval.resolvedBranchName ?? _normalizeBranchName(rawBranch, winningCampaign.branchNames, isAr);
      final double promoSpend = winningEval.qualifyingSpend > 0 ? winningEval.qualifyingSpend : targetTotal;

      inv['is_valid'] = true;
      inv['status'] = 'accepted';
      inv['unfulfilled_conditions'] = <String>[];
      inv['rejection_reason'] = null;
      inv['target_company_total'] = promoSpend;
      inv['total_value'] = promoSpend;
      inv['campaignId'] = winningCampaign.id;
      inv['campaign_name'] = winningCampaign.eventName;
      inv['eventName'] = winningCampaign.eventName;
      inv['chances_earned'] = chances;
      inv['canonical_branch'] = canonical;
      inv['branch_detected'] = canonical;
      if (claimedGifts.isNotEmpty) inv['claimed_gifts'] = claimedGifts;

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
        if (isInteractiveReward) 'game_played': false,
      });

      if (mounted) {
        setState(() {
          _invoicesRevisionCounter++;
          _cachedAllInvoices = null;
          _lastAllInvoicesCacheKey = null;
          _statusFilter = 'accepted';
          _selectedCampaignId = winningCampaign.id;
        });

        _showRecheckSuccessDialog(
          context: context,
          isAr: isAr,
          strings: strings,
          winningCampaign: winningCampaign,
          isReassignedToSisterCampaign: winningCampaign.id != activeEvent.id,
          prizeTitle: winningEval.designatedPrize,
          docId: docId,
          totalChances: chances,
          resolvedBranchId: winningEval.resolvedBranchId,
          resolvedLinkedGifts: winningEval.resolvedLinkedGifts,
          resolvedUnitValue: winningEval.resolvedUnitValue,
          resolvedIsVoucher: winningEval.resolvedIsVoucher,
          onViewAccepted: () {
            setState(() {
              _invoicesRevisionCounter++;
              _cachedAllInvoices = null;
              _lastAllInvoicesCacheKey = null;
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
          inv: inv,
          activeEvent: activeEvent,
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

    // Collect all image URLs & storage paths (supporting multi-part receipts)
    final List<String> rawUrls = [];
    if (inv['image_urls'] is List && (inv['image_urls'] as List).isNotEmpty) {
      rawUrls.addAll((inv['image_urls'] as List).map((e) => e.toString()).where((e) => e.isNotEmpty));
    }
    if (rawUrls.isEmpty && (inv['image_url'] ?? '').toString().isNotEmpty) {
      rawUrls.add(inv['image_url'].toString());
    }

    final List<String> rawPaths = [];
    if (inv['storage_paths'] is List && (inv['storage_paths'] as List).isNotEmpty) {
      rawPaths.addAll((inv['storage_paths'] as List).map((e) => e.toString()).where((e) => e.isNotEmpty));
    }
    if (rawPaths.isEmpty && (inv['storage_path'] ?? '').toString().isNotEmpty) {
      rawPaths.add(inv['storage_path'].toString());
    }

    if (rawUrls.isEmpty && rawPaths.isEmpty) {
      throw Exception(isAr ? 'لا توجد صورة مسجلة لهذه الفاتورة لإعادة الفحص بالذكاء الاصطناعي.' : 'No receipt image found for full AI scan.');
    }

    final int imageCount = rawUrls.length > rawPaths.length ? rawUrls.length : rawPaths.length;
    final List<MapEntry<String, String?>> imageTargets = [];
    for (int i = 0; i < imageCount; i++) {
      final u = i < rawUrls.length ? rawUrls[i] : '';
      final p = i < rawPaths.length ? rawPaths[i] : null;
      imageTargets.add(MapEntry(u, p));
    }

    // Sort naturally so part1 comes before part2
    imageTargets.sort((a, b) {
      final aKey = (a.value ?? a.key).toLowerCase();
      final bKey = (b.value ?? b.key).toLowerCase();
      final aPart = RegExp(r'part(\d+)').firstMatch(aKey)?.group(1);
      final bPart = RegExp(r'part(\d+)').firstMatch(bKey)?.group(1);
      if (aPart != null && bPart != null) {
        return int.parse(aPart).compareTo(int.parse(bPart));
      }
      return aKey.compareTo(bKey);
    });

    final downloadedBytesList = (await Future.wait(
      imageTargets.map((target) => _downloadReceiptImageBytes(target.key, target.value)),
    )).whereType<Uint8List>().where((b) => b.isNotEmpty).toList();

    if (downloadedBytesList.isEmpty) {
      throw Exception(isAr ? 'تعذر تنزيل صور الفاتورة من السيرفر.' : 'Failed to download receipt image(s).');
    }

    final Uint8List imageBytes = downloadedBytesList.first;
    final List<Uint8List> additionalImagesBytes = downloadedBytesList.length > 1
        ? downloadedBytesList.sublist(1)
        : const [];

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
      additionalImagesBytes: additionalImagesBytes,
      additionalMimeTypes: List.filled(additionalImagesBytes.length, 'image/jpeg'),
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
      customPrompt: activeEvent.customPrompt,
      allowMultipleChances: true,
      multiplierBasis: 'both',
      maxChancesPerReceipt: 0,
      promotionalRules: combinedPromotionalRules,
      allowComplementaryReceipts: activeEvent.allowComplementaryReceipts,
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

      final bool isInteractiveReward = (winningCampaign.gameType.trim().toLowerCase() == 'choosegift') ||
          (winningCampaign.gameType.trim().toLowerCase() == 'wheel') ||
          (winningCampaign.gameType.trim().toLowerCase() == 'scratch') ||
          (winningCampaign.gameType.trim().toLowerCase() == 'scratchcard') ||
          (winningEval.resolvedLinkedGifts.length > 1 && winningCampaign.gameType.trim().toLowerCase() != 'directgift');

      final claimedGifts = <Map<String, dynamic>>[];
      if (!isInteractiveReward) {
        for (final g in winningEval.resolvedLinkedGifts) {
          claimedGifts.add({
            'giftId': g.giftId,
            'giftName': g.giftName,
            'quantity': g.quantity,
            'unitValue': g.unitValue,
            'isVoucher': g.isVoucher,
          });
        }
      }

      final double computedTotal = result.extractedProducts.fold<double>(0.0, (acc, p) => acc + p.actualLineSpend);
      final double totalSpend = computedTotal > 0 ? computedTotal : result.targetCompanyTotal;
      final canonical = winningEval.resolvedBranchName ?? _normalizeBranchName(result.branchDetected, winningCampaign.branchNames, isAr);

      inv['is_valid'] = true;
      inv['status'] = 'accepted';
      inv['unfulfilled_conditions'] = <String>[];
      inv['rejection_reason'] = null;
      inv['target_company_total'] = winningEval.qualifyingSpend > 0 ? winningEval.qualifyingSpend : result.targetCompanyTotal;
      inv['total_value'] = totalSpend;
      inv['campaignId'] = winningCampaign.id;
      inv['campaign_name'] = winningCampaign.eventName;
      inv['eventName'] = winningCampaign.eventName;
      inv['chances_earned'] = chances;
      inv['canonical_branch'] = canonical;
      inv['branch_detected'] = canonical;
      if (result.extractedProducts.isNotEmpty) {
        inv['extracted_products'] = result.extractedProducts.map((p) => p.toJson()).toList();
      }
      if (claimedGifts.isNotEmpty) inv['claimed_gifts'] = claimedGifts;

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
        if (isInteractiveReward) 'game_played': false,
      });

      if (mounted) {
        setState(() {
          _invoicesRevisionCounter++;
          _cachedAllInvoices = null;
          _lastAllInvoicesCacheKey = null;
          _statusFilter = 'accepted';
          _selectedCampaignId = winningCampaign.id;
        });

        _showRecheckSuccessDialog(
          context: context,
          isAr: isAr,
          strings: strings,
          winningCampaign: winningCampaign,
          isReassignedToSisterCampaign: winningCampaign.id != activeEvent.id,
          prizeTitle: winningEval.designatedPrize,
          docId: docId,
          totalChances: chances,
          resolvedBranchId: winningEval.resolvedBranchId,
          resolvedLinkedGifts: winningEval.resolvedLinkedGifts,
          resolvedUnitValue: winningEval.resolvedUnitValue,
          resolvedIsVoucher: winningEval.resolvedIsVoucher,
          onViewAccepted: () {
            setState(() {
              _invoicesRevisionCounter++;
              _cachedAllInvoices = null;
              _lastAllInvoicesCacheKey = null;
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
        _showRecheckStillRejectedDialog(
          context,
          unfulfilledList,
          isAr,
          strings,
          inv: inv,
          activeEvent: activeEvent,
        );
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
    String? docId,
    int totalChances = 1,
    String? resolvedBranchId,
    List<LinkedGiftAllocation> resolvedLinkedGifts = const [],
    double? resolvedUnitValue,
    bool resolvedIsVoucher = false,
    VoidCallback? onViewAccepted,
  }) {
    final gameType = winningCampaign?.gameType.trim().toLowerCase() ?? '';
    final isChooseGift = gameType == 'choosegift' || (resolvedLinkedGifts.length > 1 && gameType != 'directgift');
    final isWheel = gameType == 'wheel' || gameType == 'spinthewheel';
    final isScratch = gameType == 'scratch' || gameType == 'scratchcard';
    final isDirect = gameType == 'directgift' || (!isChooseGift && !isWheel && !isScratch);

    // Extract available candidate prizes
    List<String> candidatePrizes = [];
    if (resolvedLinkedGifts.isNotEmpty) {
      candidatePrizes = resolvedLinkedGifts.map((g) => g.giftName.trim()).where((n) => n.isNotEmpty).toSet().toList();
    }
    if (candidatePrizes.isEmpty && winningCampaign != null) {
      candidatePrizes = winningCampaign.allocatedPrizes
          .where((p) => p.remainingQuantity > 0)
          .map((p) => p.name.trim())
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList();
    }

    // Clean display title for choice campaigns
    String effectiveTitle = prizeTitle ?? '';
    if (isChooseGift) {
      effectiveTitle = isAr
          ? 'عرض ترويجي بنظام اختيار الهدية (${candidatePrizes.length} خيارات متاحة)'
          : 'Promotional Choice Reward (${candidatePrizes.length} Options)';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.tertiaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check_circle_rounded, size: 48, color: colorScheme.onTertiaryFixedVariant),
        ),
        title: Text(
          isReassignedToSisterCampaign
              ? (isAr ? 'تم استيفاء الشروط وتأهيل الفاتورة!' : 'Receipt Qualified for Campaign!')
              : strings.recheckSuccessTitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isReassignedToSisterCampaign
                    ? (isAr
                        ? 'تبيّن بعد التدقيق أن الفاتورة مطابقة ومستوفاة لشروط حملة (${winningCampaign?.eventName ?? ""}) وتم اعتمادها بنجاح!'
                        : 'Receipt matches campaign (${winningCampaign?.eventName ?? ""}) and has been successfully approved!')
                    : strings.recheckSuccessMessage,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant, fontSize: 13.5),
              ),
              const SizedBox(height: 12),

              // Interactive Game / Gift Selection Banner
              if (isChooseGift) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colorScheme.primaryFixedDim),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryFixedDim,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.touch_app_rounded, color: colorScheme.onSecondaryContainer, size: 18),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isAr ? 'نظام اختيار الهدية (Choice Reward) 🎁' : 'Choice Reward System 🎁',
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.onSecondaryContainer),
                                ),
                                Text(
                                  isAr ? 'يحق للعميل اختيار هديته من بين الخيارات التالية:' : 'Customer can pick a gift from available choices:',
                                  style: TextStyle(fontSize: 11, color: colorScheme.onSecondaryContainer),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (candidatePrizes.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: candidatePrizes.map((p) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: colorScheme.primaryFixedDim),
                              boxShadow: [
                                BoxShadow(color: colorScheme.secondaryContainer.withValues(alpha: 0.5), blurRadius: 3, offset: const Offset(0, 1)),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.card_giftcard_rounded, size: 13, color: colorScheme.onSecondaryContainer),
                                const SizedBox(width: 5),
                                Text(
                                  p,
                                  style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: colorScheme.onSecondaryContainer),
                                ),
                              ],
                            ),
                          )).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ] else if (isWheel) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.primaryFixedDim),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.rotate_right_rounded, color: colorScheme.onSecondaryContainer, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isAr ? 'آلية الجائزة: عجلة الحظ 🎡 (قم بتدوير العجلة لتحديد الهدية)' : 'Wheel of Fortune 🎡 (Spin wheel to pick gift)',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5, color: colorScheme.onSecondaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (isScratch) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.primaryFixedDim),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, color: colorScheme.primary, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isAr ? 'آلية الجائزة: كارت الخربشة ✨ (قم بالخربشة لكشف الهدية)' : 'Scratch Card ✨ (Scratch to reveal gift)',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5, color: colorScheme.onPrimaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Direct Gift
                if (effectiveTitle.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colorScheme.primaryFixedDim),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.card_giftcard_rounded, color: colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            effectiveTitle,
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: colorScheme.onPrimaryContainer,
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
                style: TextStyle(fontSize: 11.5, color: colorScheme.outline),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          // Primary Action Button (Game / Choice / Direct Claim)
          if (docId != null && docId.isNotEmpty && winningCampaign != null) ...[
            if (isChooseGift)
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ChooseGiftScreen(
                        transactionId: docId,
                        eventId: winningCampaign.id,
                        companySlug: winningCampaign.companySlug,
                        prizes: candidatePrizes,
                        totalChances: totalChances > 0 ? totalChances : 1,
                        branchId: resolvedBranchId,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.card_giftcard_rounded, size: 18),
                label: Text(
                  isAr ? '🎁 اختيار وتسليم الهدية للعميل الآن' : '🎁 Pick & Claim Gift Now',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                ),
              )
            else if (isWheel)
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => SpinTheWheelScreen(
                        transactionId: docId,
                        eventId: winningCampaign.id,
                        prizes: candidatePrizes,
                        totalChances: totalChances > 0 ? totalChances : 1,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.rotate_right_rounded, size: 18),
                label: Text(
                  isAr ? '🎡 تدوير العجلة لتحديد الهدية' : '🎡 Spin Wheel for Gift',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.onSecondaryFixedVariant,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                ),
              )
            else if (isScratch)
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ScratchCardScreen(
                        transactionId: docId,
                        eventId: winningCampaign.id,
                        prizes: candidatePrizes,
                        totalChances: totalChances > 0 ? totalChances : 1,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(
                  isAr ? '✨ خربشة الكارت لكشف الهدية' : '✨ Scratch Card for Gift',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                ),
              )
            else if (isDirect)
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => DirectGiftClaimScreen(
                        transactionId: docId,
                        eventId: winningCampaign.id,
                        prizeName: prizeTitle ?? 'هدية معتمدة',
                        quantity: 1,
                        branchId: resolvedBranchId,
                        unitValue: resolvedUnitValue,
                        isVoucher: resolvedIsVoucher,
                        linkedGifts: resolvedLinkedGifts,
                        requireVoucherSerials: winningCampaign.requireVoucherSerials,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: Text(
                  isAr ? '📦 صرف وتسليم الهدية للعميل' : '📦 Deliver Gift to Customer',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.onTertiaryFixedVariant,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                ),
              ),
          ],

          if (onViewAccepted != null)
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                onViewAccepted();
              },
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: Text(
                isAr ? 'عرض في المقبولة' : 'View in Accepted',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.onTertiaryFixedVariant,
                side: BorderSide(color: colorScheme.tertiaryFixedDim),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
    Map<String, dynamic>? inv,
    EventModel? activeEvent,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.warning_amber_rounded, size: 48, color: colorScheme.onSecondaryFixedVariant),
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
                        child: Icon(Icons.circle, size: 6, color: colorScheme.onSecondaryFixedVariant),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          r,
                          style: TextStyle(fontSize: 12.5, color: colorScheme.onSurface, height: 1.3),
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
          if (inv != null && !widget.isEmbedded && ref.read(isAdminProvider))
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _openAiBrainCoPilotForInvoice(
                  context: context,
                  inv: inv,
                  event: activeEvent,
                  strings: strings,
                  isAr: isAr,
                );
              },
              icon: const Icon(Icons.psychology_rounded, size: 18),
              label: Text(
                isAr ? 'تشخيص في عقل الذكاء' : 'Diagnose in AI Brain',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
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
    List<String>? imageUrls,
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
      imageUrls: imageUrls,
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

    final isCampaignLocked = widget.lockedEventId != null && widget.lockedEventId!.isNotEmpty;
    if (isCampaignLocked && _selectedCampaignId != widget.lockedEventId) {
      _selectedCampaignId = widget.lockedEventId!;
    }
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
          final rawEventsMap = _persistentEventsCache[eventsKey] ?? const {};
          final eventsMap = isCampaignLocked
              ? <String, EventModel>{
                  if (rawEventsMap.containsKey(widget.lockedEventId))
                    widget.lockedEventId!: rawEventsMap[widget.lockedEventId]!,
                }
              : rawEventsMap;

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

              final unFilteredDocs = cachedDocs ?? transactionsSnapshot.data?.docs ?? [];
              final rawDocs = isCampaignLocked
                  ? unFilteredDocs.where((d) {
                      final data = d.data() as Map<String, dynamic>?;
                      return data?['campaignId']?.toString() == widget.lockedEventId;
                    }).toList()
                  : unFilteredDocs;
              final int snapshotHash = transactionsSnapshot.data != null
                  ? identityHashCode(transactionsSnapshot.data)
                  : 0;
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
                snapshotHash: snapshotHash,
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
    int snapshotHash = 0,
  }) {
    // 1. Scoped Events by locked company & locked campaign
    final scopedEvents = eventsMap.values.where((e) {
      if (widget.lockedEventId != null && widget.lockedEventId!.isNotEmpty && e.id != widget.lockedEventId) {
        return false;
      }
      if (widget.lockedCompanySlug != null && widget.lockedCompanySlug!.isNotEmpty) {
        final slug = e.companySlug.toLowerCase();
        final name = e.targetCompany.toLowerCase();
        return slug == widget.lockedCompanySlug!.toLowerCase() ||
            (widget.lockedCompanyName != null && name == widget.lockedCompanyName!.toLowerCase());
      }
      return true;
    }).toList();

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
    final allInvoicesCacheKey = '${rawDocs.length}_${rawDocs.isEmpty ? "" : rawDocs.first.id}_${rawDocs.isEmpty ? "" : rawDocs.last.id}_${eventsMap.length}_${canonicalBranches.length}_${snapshotHash}_${_invoicesRevisionCounter}_$isAr';
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
    final rawQuery = _searchController.text.trim();
    final query = rawQuery.toEnglishDigits().toLowerCase();
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

      // 6. Search Query (Receipt Number, Branch, Store, Customer, Doc ID, Delimiter-Insensitive)
      if (query.isNotEmpty) {
        final receiptNum = (inv['receipt_number'] ?? '').toString().toLowerCase();
        final docId = (inv['id'] ?? '').toString().toLowerCase();
        final store = (inv['store_chain_detected'] ?? inv['retail_chain_name'] ?? '').toString().toLowerCase();
        final branch = (inv['branch_detected'] ?? '').toString().toLowerCase();
        final eventName = (inv['eventName'] ?? '').toString().toLowerCase();
        final targetComp = (inv['targetCompany'] ?? '').toString().toLowerCase();
        final custName = (inv['customerName'] ?? '').toString().toLowerCase();
        final custPhone = (inv['customerPhone'] ?? '').toString().toLowerCase();

        bool matches = receiptNum.contains(query) ||
            docId.contains(query) ||
            store.contains(query) ||
            branch.contains(query) ||
            eventName.contains(query) ||
            targetComp.contains(query) ||
            custName.contains(query) ||
            custPhone.contains(query);

        // Delimiter-insensitive matching for receipt numbers & segment token matching
        if (!matches && query.contains(RegExp(r'\d'))) {
          final cleanReceipt = receiptNum.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
          final cleanDocId = docId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
          final cleanQuery = query.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
          if (cleanQuery.isNotEmpty && (cleanReceipt.contains(cleanQuery) || cleanDocId.contains(cleanQuery))) {
            matches = true;
          }
          if (!matches) {
            final segments = receiptNum.split(RegExp(r'[/\\-_ ]+'));
            if (segments.any((seg) => seg == query)) {
              matches = true;
            }
          }
        }

        if (!matches) return false;
      }

      return true;
    }).toList();

    // Calculate Metrics
    final totalInvoicesCount = filteredInvoices.length;
    int totalAcceptedInvoices = 0;
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
        totalAcceptedInvoices++;
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
    final stickyFilterHeight = _calculateStickyFilterHeight(
      screenWidth: screenWidth,
    );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: M3ContentBoundary(
        maxWidth: 1440.0,
        child: CustomScrollView(
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
                      M3ActionMenu(
                        tooltip: isAr ? 'تصدير البيانات (CSV)' : 'Export CSV',
                        anchorBuilder: (context, controller, child) {
                          return FilledButton.tonalIcon(
                            onPressed: () {
                              if (controller.isOpen) {
                                controller.close();
                              } else {
                                controller.open();
                              }
                            },
                            icon: const Icon(Icons.file_download_outlined, size: 18),
                            label: Text(strings.exportCsvBtn, style: const TextStyle(fontSize: 12)),
                          );
                        },
                        children: [
                          M3ActionMenu.header(
                            context: context,
                            title: isAr ? 'خيارات التصدير والتقارير' : 'Export & Report Options',
                            icon: Icons.download_rounded,
                          ),
                          M3ActionMenu.item(
                            context: context,
                            label: isAr ? 'تصدير جدول الفواتير (CSV)' : 'Export Invoices Table (CSV)',
                            icon: Icons.table_chart_rounded,
                            onPressed: () => _exportInvoicesToCsv(filteredInvoices, strings),
                          ),
                          M3ActionMenu.submenu(
                            context: context,
                            label: isAr ? 'تنسيقات إضافية ومتقدمة' : 'Advanced Formats',
                            icon: Icons.tune_rounded,
                            children: [
                              M3ActionMenu.item(
                                context: context,
                                label: isAr ? 'ملف إكسيل شامل (Excel / CSV)' : 'Full Excel Data (.csv)',
                                icon: Icons.description_rounded,
                                onPressed: () => _exportInvoicesToCsv(filteredInvoices, strings),
                              ),
                              M3ActionMenu.item(
                                context: context,
                                label: isAr ? 'طباعة / حفظ بتنسيق PDF' : 'Print / Export PDF',
                                icon: Icons.print_rounded,
                                onPressed: () => _exportInvoicesToCsv(filteredInvoices, strings),
                              ),
                            ],
                          ),
                        ],
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
                  totalAcceptedInvoices: totalAcceptedInvoices,
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

          // 2.5. BRANCH INVOICES DISTRIBUTION & ANALYTICS CHART
          SliverToBoxAdapter(
            child: _buildBranchInvoicesChartCard(
              allInvoices: allInvoices,
              canonicalBranches: sortedBranches,
              colorScheme: colorScheme,
              strings: strings,
              activeCountry: activeCountry,
              isAr: isAr,
              isMobile: isMobile,
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
    required int totalAcceptedInvoices,
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
          crossAxisCount = 2;
          childAspectRatio = 1.25;
        } else if (width < 960) {
          crossAxisCount = 2;
          childAspectRatio = 1.85;
        } else if (width < 1200) {
          crossAxisCount = 2;
          childAspectRatio = 2.1;
        }

        final List<Widget> cards = [
          _buildStatKpiCard(
            title: isAr ? 'إجمالي الفواتير المقبولة' : (isHi ? 'स्वीकृत चालान' : 'Total Accepted Invoices'),
            value: '$totalAcceptedInvoices',
            subtitle: isAr ? 'الفواتير المستوفية للشروط والمعتمدة' : (isHi ? 'स्वीकृत और वैध रसीदें' : 'Qualified & approved invoices'),
            icon: Icons.task_alt_rounded,
            accentColor: colorScheme.primary,
            badgeText: isAr ? 'فاتورة مقبولة' : (isHi ? 'स्वीकृत' : 'Accepted'),
            colorScheme: colorScheme,
            tooltip: isAr ? 'إجمالي عدد الفواتير المقبولة والمطابقة لشروط الحملة' : 'Total accepted invoices meeting campaign rules',
            isMobile: isMobile,
          ),
          _buildStatKpiCard(
            title: strings.totalPromotionalSales,
            value: '${totalPromoSales.toStringAsFixed(1)} ${activeCountry.currencySymbol}',
            subtitle: isAr ? 'قيمة مشتريات المنتجات المعتمدة' : (isHi ? 'प्रचार बिक्री' : 'Verified promotional purchases'),
            icon: Icons.payments_rounded,
            accentColor: colorScheme.onTertiaryFixedVariant,
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
            accentColor: colorScheme.primary,
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
            accentColor: colorScheme.onSecondaryFixedVariant,
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
            crossAxisSpacing: isMobile ? 10 : 14,
            mainAxisSpacing: isMobile ? 10 : 14,
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
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14, vertical: isMobile ? 10 : 12),
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
                  padding: EdgeInsets.all(isMobile ? 5 : 7),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: accentColor, size: isMobile ? 16 : 18),
                ),
                Flexible(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeText,
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 9 : 10,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
                  fontSize: isMobile ? 17 : 18,
                  fontWeight: FontWeight.w900,
                  color: colorScheme.onSurface,
                  letterSpacing: -0.3,
                ),
                maxLines: 1,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
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
                    fontSize: isMobile ? 8.5 : 9.5,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
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
    final isHi = ref.isHindi;
    final isMobile = Responsive.isMobile(context);
    final hasActiveFilters = _searchController.text.isNotEmpty ||
        _selectedCampaignId != 'all' ||
        _selectedCompanySlug != 'all' ||
        _selectedBranch != 'all' ||
        _statusFilter != 'accepted' ||
        _dateFilter != DateFilterType.today;

    final baseScopedEventsMap = (widget.lockedCompanySlug != null && widget.lockedCompanySlug!.isNotEmpty)
        ? Map.fromEntries(eventsMap.entries.where((e) {
            final slug = e.value.companySlug.toLowerCase();
            final name = e.value.targetCompany.toLowerCase();
            return slug == widget.lockedCompanySlug!.toLowerCase() ||
                (widget.lockedCompanyName != null && name == widget.lockedCompanyName!.toLowerCase());
          }))
        : eventsMap;

    // Sort scopedEventsMap so active campaigns appear first in quick chips & selectors
    final sortedScopedEntries = baseScopedEventsMap.entries.toList()
      ..sort((a, b) {
        final aActive = (a.value.isActive && !a.value.isExpired) ? 0 : 1;
        final bActive = (b.value.isActive && !b.value.isExpired) ? 0 : 1;
        if (aActive != bActive) return aActive.compareTo(bActive);
        return a.value.eventName.compareTo(b.value.eventName);
      });
    final scopedEventsMap = Map<String, EventModel>.fromEntries(sortedScopedEntries);

    Widget buildReceiptLookupButton({bool isMobile = false}) {
      return Tooltip(
        message: isAr
            ? 'فتح نافذة البحث المفصل برقم الحركة والكاشير (Trans / POS)'
            : (isHi ? 'विस्तृत रसीद खोज' : 'Detailed Receipt Search (Trans / POS)'),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 14,
              vertical: isMobile ? 12 : 10,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            side: BorderSide(
              color: colorScheme.primary.withValues(alpha: 0.5),
              width: 1.2,
            ),
            backgroundColor: colorScheme.primary.withValues(alpha: 0.04),
          ),
          icon: Icon(
            Icons.receipt_long_rounded,
            size: isMobile ? 20 : 18,
            color: colorScheme.primary,
          ),
          label: Text(
            isAr
                ? 'بحث مفصل بالفاتورة'
                : (isHi ? 'विस्तृत रसीद खोज' : 'Detailed Receipt Lookup'),
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.bold,
              fontSize: isMobile ? 13 : 12,
              color: colorScheme.primary,
            ),
          ),
          onPressed: () => _openReceiptLookupDialog(
            context: context,
            isAr: isAr,
            strings: strings,
            allInvoices: allInvoices,
            eventsMap: eventsMap,
          ),
        ),
      );
    }

    Widget buildActiveSearchChip() {
      if (_searchController.text.isEmpty) return const SizedBox.shrink();
      return InputChip(
        avatar: Icon(Icons.receipt_rounded, size: 16, color: colorScheme.primary),
        label: Text(
          isAr
              ? 'تصفية: #${_searchController.text}'
              : 'Filter: #${_searchController.text}',
          style: GoogleFonts.cairo(
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
          ),
        ),
        backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.4),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        onDeleted: () {
          setState(() {
            _searchController.clear();
            _resetPagination();
          });
        },
        deleteIcon: const Icon(Icons.close_rounded, size: 16),
        deleteButtonTooltipMessage: isAr ? 'إلغاء تصفية الفاتورة' : 'Clear receipt filter',
      );
    }

    final statusFilterWidget = SegmentedButton<String>(
      segments: [
        ButtonSegment<String>(
          value: 'accepted',
          label: Text(
            isAr ? 'المقبولة' : (isHi ? 'स्वीकृत' : 'Accepted'),
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 11.5 : 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          icon: const Icon(Icons.check_circle_rounded, size: 16),
        ),
        ButtonSegment<String>(
          value: 'rejected',
          label: Text(
            isAr ? 'المرفوضة' : (isHi ? 'अस्वीकृत' : 'Rejected'),
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 11.5 : 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          icon: const Icon(Icons.cancel_rounded, size: 16),
        ),
        ButtonSegment<String>(
          value: 'all',
          label: Text(
            isAr ? 'الكل' : (isHi ? 'सभी' : 'All'),
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 11.5 : 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          icon: const Icon(Icons.format_list_bulleted_rounded, size: 16),
        ),
      ],
      selected: {_statusFilter},
      onSelectionChanged: (set) {
        setState(() => _statusFilter = set.first);
        _resetPagination();
      },
      showSelectedIcon: true,
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: colorScheme.primaryContainer,
        selectedForegroundColor: colorScheme.onPrimaryContainer,
        backgroundColor: colorScheme.surfaceContainerLow,
        foregroundColor: colorScheme.onSurfaceVariant,
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );

    // Filter invoices by campaign, company, date, and status to compute accurate branch counts matching the active date/filter selection
    final dateScopedInvoices = allInvoices.where((inv) {
      if (_selectedCampaignId != 'all' && inv['campaignId'] != _selectedCampaignId) return false;
      if (_selectedCompanySlug != 'all') {
        final slug = (inv['companySlug'] ?? '').toString().toLowerCase();
        final target = (inv['targetCompany'] ?? '').toString().toLowerCase();
        if (slug != _selectedCompanySlug.toLowerCase() && !target.contains(_selectedCompanySlug.toLowerCase())) {
          return false;
        }
      }
      if (!_passesDateFilter(inv['date'] as DateTime?)) return false;

      final bool isExplicitlyValid = inv['is_valid'] == true || inv['status'] == 'accepted' || inv['isValid'] == true;
      final bool isExplicitlyRejected = inv['is_valid'] == false || inv['status'] == 'rejected' || inv['isValid'] == false || ((inv['unfulfilled_conditions'] as List?)?.isNotEmpty ?? false);
      final bool isValid = isExplicitlyValid || (!isExplicitlyRejected && ((inv['unfulfilled_conditions'] as List?)?.isEmpty ?? true));
      if (_statusFilter == 'accepted' && !isValid) return false;
      if (_statusFilter == 'rejected' && isValid) return false;

      return true;
    }).toList();

    // Pre-calculate count per campaign for O(1) lookups in the dropdown
    final Map<String, int> campaignInvoiceCounts = {};
    for (final e in scopedEventsMap.keys) {
      campaignInvoiceCounts[e] = 0;
    }
    for (final inv in allInvoices) {
      final cid = (inv['campaignId'] ?? '').toString();
      if (cid.isNotEmpty && campaignInvoiceCounts.containsKey(cid)) {
        campaignInvoiceCounts[cid] = (campaignInvoiceCounts[cid] ?? 0) + 1;
      }
    }

    Widget buildCampaignPickerWidget({bool isMobile = false}) {
      final String campaignLabel;
      final bool isCampaignActive = _selectedCampaignId != 'all' || _selectedCompanySlug != 'all';

      if (_selectedCampaignId == 'all') {
        if (_selectedCompanySlug != 'all') {
          final compName = availableCompanies[_selectedCompanySlug] ?? _selectedCompanySlug;
          campaignLabel = compName;
        } else {
          campaignLabel = isMobile
              ? (isAr ? 'الفعاليات' : (isHi ? 'अभियान' : 'Campaigns'))
              : (isAr
                  ? 'كافة الفعاليات (${scopedEventsMap.length})'
                  : 'All Campaigns (${scopedEventsMap.length})');
        }
      } else {
        final activeEvent = scopedEventsMap[_selectedCampaignId];
        final eventTitle = activeEvent?.eventName ?? _selectedCampaignId;
        campaignLabel = isMobile
            ? (eventTitle.length > 13 ? '${eventTitle.substring(0, 13)}…' : eventTitle)
            : (eventTitle.length > 20 ? '${eventTitle.substring(0, 20)}…' : eventTitle);
      }

      final screenWidth = MediaQuery.sizeOf(context).width;
      final double campaignMenuWidth = isMobile ? (screenWidth - 32).clamp(300.0, 420.0) : 480.0;

      return M3ActionMenu(
        tooltip: isAr ? 'تصفية حسب الفعالية والمهرجان' : 'Filter by Campaign / Festival',
        minWidth: campaignMenuWidth,
        maxWidth: campaignMenuWidth,
        maxHeight: 520.0,
        crossAxisUnconstrained: false,
        anchorBuilder: (context, controller, child) {
          return InkWell(
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: isMobile ? 8 : 10),
              decoration: BoxDecoration(
                color: isCampaignActive ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
                border: Border.all(
                  color: isCampaignActive ? colorScheme.primary : colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.campaign_rounded,
                    size: isMobile ? 16 : 18,
                    color: isCampaignActive ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      campaignLabel,
                      style: TextStyle(
                        fontSize: isMobile ? 11.5 : 12,
                        fontWeight: FontWeight.w600,
                        color: isCampaignActive ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isCampaignActive) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _selectedCampaignId = 'all';
                          _selectedCompanySlug = 'all';
                          _resetPagination();
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.close_rounded,
                          size: isMobile ? 14 : 16,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(width: 2),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      size: isMobile ? 16 : 18,
                      color: isCampaignActive ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
        children: [
          M3ActionMenu.header(
            context: context,
            title: isAr ? 'الفعاليات والمهرجانات' : 'Campaigns & Festivals',
            icon: Icons.campaign_rounded,
            badge: '${scopedEventsMap.length} ${isAr ? "حملة" : "events"}',
          ),
          M3ActionMenu.item(
            context: context,
            label: isAr
                ? 'كافة الفعاليات والحملات (${scopedEventsMap.length})'
                : 'All Campaigns (${scopedEventsMap.length})',
            leading: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: _selectedCampaignId == 'all' && _selectedCompanySlug == 'all'
                    ? colorScheme.primary.withValues(alpha: 0.15)
                    : colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.all_inclusive_rounded,
                size: 15,
                color: _selectedCampaignId == 'all' && _selectedCompanySlug == 'all'
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            isSelected: _selectedCampaignId == 'all' && _selectedCompanySlug == 'all',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: _selectedCampaignId == 'all' && _selectedCompanySlug == 'all'
                    ? colorScheme.primary.withValues(alpha: 0.18)
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${allInvoices.length} ${isAr ? "فاتورة" : ""}'.trim(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: _selectedCampaignId == 'all' && _selectedCompanySlug == 'all'
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            onPressed: () {
              setState(() {
                _selectedCampaignId = 'all';
                _selectedCompanySlug = 'all';
                _resetPagination();
              });
            },
          ),
          if (availableCompanies.length > 1 && (widget.lockedCompanySlug == null || widget.lockedCompanySlug!.isEmpty))
            M3ActionMenu.submenu(
              context: context,
              label: isAr
                  ? (_selectedCompanySlug != 'all'
                      ? 'الشركة: ${availableCompanies[_selectedCompanySlug] ?? _selectedCompanySlug}'
                      : 'تصفية حسب الشركة')
                  : (_selectedCompanySlug != 'all'
                      ? 'Company: ${availableCompanies[_selectedCompanySlug] ?? _selectedCompanySlug}'
                      : 'Filter by Company'),
              leading: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: _selectedCompanySlug != 'all'
                      ? colorScheme.primary.withValues(alpha: 0.15)
                      : colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.business_rounded,
                  size: 15,
                  color: _selectedCompanySlug != 'all'
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              children: [
                M3ActionMenu.item(
                  context: context,
                  label: strings.allCampaigns,
                  isSelected: _selectedCompanySlug == 'all',
                  onPressed: () {
                    setState(() {
                      _selectedCompanySlug = 'all';
                      _resetPagination();
                    });
                  },
                ),
                for (final comp in availableCompanies.entries)
                  M3ActionMenu.item(
                    context: context,
                    label: comp.value,
                    isSelected: _selectedCompanySlug == comp.key,
                    onPressed: () {
                      setState(() {
                        _selectedCompanySlug = comp.key;
                        _resetPagination();
                      });
                    },
                  ),
              ],
            ),
          M3ActionMenu.divider(),
          for (final entry in scopedEventsMap.entries)
            () {
              final event = entry.value;
              final count = campaignInvoiceCounts[event.id] ?? 0;
              final isSel = _selectedCampaignId == event.id;
              final isActive = event.isActive && !event.isExpired;

              return M3ActionMenu.item(
                context: context,
                label: event.eventName,
                subtitle: '${event.targetCompany} • ${event.retailChainName}',
                leading: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: isSel
                        ? colorScheme.primary.withValues(alpha: 0.15)
                        : (isActive
                            ? colorScheme.tertiary.withValues(alpha: 0.12)
                            : colorScheme.outline.withValues(alpha: 0.15)),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isActive ? Icons.campaign_rounded : Icons.history_rounded,
                    size: 15,
                    color: isSel
                        ? colorScheme.primary
                        : (isActive ? colorScheme.onTertiaryFixedVariant : colorScheme.outline),
                  ),
                ),
                isSelected: isSel,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isActive)
                      Container(
                        margin: const EdgeInsetsDirectional.only(end: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: colorScheme.outline.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isAr ? 'منتهية' : 'Ended',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.outline,
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: isSel
                            ? colorScheme.primary.withValues(alpha: 0.18)
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$count ${isAr ? "فاتورة" : ""}'.trim(),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: isSel ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                onPressed: () {
                  setState(() {
                    _selectedCampaignId = event.id;
                    _resetPagination();
                  });
                },
              );
            }(),
          M3ActionMenu.divider(),
          M3ActionMenu.item(
            context: context,
            label: isAr ? 'بحث متقدم وتصفية شاملة...' : 'Advanced Search & Dialog...',
            icon: Icons.tune_rounded,
            onPressed: () => _showCampaignSelectorDialog(
              context: context,
              colorScheme: colorScheme,
              strings: strings,
              isAr: isAr,
              eventsMap: scopedEventsMap,
              availableCompanies: availableCompanies,
              allInvoices: allInvoices,
            ),
          ),
        ],
      );
    }

    // Pre-calculate count per branch for O(1) lookups in the dropdown
    final Map<String, int> branchInvoiceCounts = {};
    for (final b in availableBranches) {
      branchInvoiceCounts[b] = 0;
    }
    for (final inv in dateScopedInvoices) {
      final b = (inv['canonical_branch'] ?? '').toString().trim();
      if (b.isNotEmpty && branchInvoiceCounts.containsKey(b)) {
        branchInvoiceCounts[b] = (branchInvoiceCounts[b] ?? 0) + 1;
      }
    }

    Widget buildBranchPickerWidget({bool isMobile = false}) {
      final String branchLabel;
      if (_selectedBranch == 'all') {
        branchLabel = isMobile
            ? (isAr ? 'الفروع' : (isHi ? 'शाखाएं' : 'Branches'))
            : (isAr ? 'كافة الفروع (${availableBranches.length})' : 'All Branches (${availableBranches.length})');
      } else {
        branchLabel = _selectedBranch;
      }

      final screenWidth = MediaQuery.sizeOf(context).width;
      final double branchMenuWidth = isMobile ? (screenWidth - 32).clamp(260.0, 340.0) : 320.0;

      return M3ActionMenu(
        tooltip: isAr ? 'تصفية حسب الفرع' : 'Filter by Branch',
        minWidth: branchMenuWidth,
        maxWidth: branchMenuWidth,
        maxHeight: 480.0,
        crossAxisUnconstrained: false,
        anchorBuilder: (context, controller, child) {
          return InkWell(
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: isMobile ? 8 : 10),
              decoration: BoxDecoration(
                color: _selectedBranch != 'all' ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
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
                    size: isMobile ? 16 : 18,
                    color: _selectedBranch != 'all' ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      branchLabel,
                      style: TextStyle(
                        fontSize: isMobile ? 11.5 : 12,
                        fontWeight: FontWeight.w600,
                        color: _selectedBranch != 'all' ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: isMobile ? 16 : 18,
                    color: _selectedBranch != 'all' ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          );
        },
        children: [
          M3ActionMenu.header(
            context: context,
            title: isAr
                ? (_dateFilter != DateFilterType.all
                    ? 'الفروع المعتمدة (${_getDateFilterLabel(strings)})'
                    : 'الفروع المعتمدة')
                : (_dateFilter != DateFilterType.all
                    ? 'Campaign Branches (${_getDateFilterLabel(strings)})'
                    : 'Campaign Branches'),
            icon: Icons.store_mall_directory_rounded,
            badge: '${availableBranches.length} ${isAr ? "فرع" : "branches"}',
          ),
          M3ActionMenu.item(
            context: context,
            label: isAr ? 'كافة الفروع (${availableBranches.length})' : 'All Branches (${availableBranches.length})',
            icon: Icons.store_mall_directory_rounded,
            isSelected: _selectedBranch == 'all',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _selectedBranch == 'all'
                    ? colorScheme.primary.withValues(alpha: 0.15)
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${dateScopedInvoices.length}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _selectedBranch == 'all' ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            onPressed: () {
              setState(() => _selectedBranch = 'all');
              _resetPagination();
            },
          ),
          if (availableBranches.isNotEmpty) M3ActionMenu.divider(),
          for (final b in availableBranches)
            () {
              final count = branchInvoiceCounts[b] ?? 0;
              final isCurrent = _selectedBranch == b;
              return M3ActionMenu.item(
                context: context,
                label: b,
                icon: Icons.storefront_rounded,
                isSelected: isCurrent,
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? colorScheme.primary.withValues(alpha: 0.15)
                        : (count > 0 ? colorScheme.tertiary.withValues(alpha: 0.12) : colorScheme.surfaceContainerHighest),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isCurrent
                          ? colorScheme.primary
                          : (count > 0 ? colorScheme.onTertiaryFixedVariant : colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
                onPressed: () {
                  setState(() => _selectedBranch = b);
                  _resetPagination();
                },
              );
            }(),
        ],
      );
    }

    Widget buildDatePickerWidget({bool isMobile = false}) {
      final String dateLabel = _getDateFilterLabel(strings);

      return M3ActionMenu(
        tooltip: isAr ? 'تصفية حسب التاريخ' : (isHi ? 'तिथि द्वारा फ़िल्टर करें' : 'Filter by Date'),
        anchorBuilder: (context, controller, child) {
          return InkWell(
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: isMobile ? 8 : 10),
              decoration: BoxDecoration(
                color: _dateFilter != DateFilterType.all ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
                border: Border.all(color: _dateFilter != DateFilterType.all ? colorScheme.primary : colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    size: isMobile ? 16 : 18,
                    color: _dateFilter != DateFilterType.all ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      dateLabel,
                      style: TextStyle(
                        fontSize: isMobile ? 11.5 : 12,
                        fontWeight: FontWeight.w600,
                        color: _dateFilter != DateFilterType.all ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: isMobile ? 16 : 18,
                    color: _dateFilter != DateFilterType.all ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          );
        },
        children: [
          M3ActionMenu.header(
            context: context,
            title: isAr ? 'الفترة الزمنية' : (isHi ? 'समय अवधि' : 'Time Period'),
            icon: Icons.date_range_rounded,
          ),
          M3ActionMenu.item(
            context: context,
            label: strings.filterToday,
            icon: Icons.today_rounded,
            isSelected: _dateFilter == DateFilterType.today,
            onPressed: () {
              setState(() {
                _dateFilter = DateFilterType.today;
                _customDateRange = null;
              });
              _resetPagination();
            },
          ),
          M3ActionMenu.item(
            context: context,
            label: strings.filterThisMonth,
            icon: Icons.calendar_view_month_rounded,
            isSelected: _dateFilter == DateFilterType.thisMonth,
            onPressed: () {
              setState(() {
                _dateFilter = DateFilterType.thisMonth;
                _customDateRange = null;
              });
              _resetPagination();
            },
          ),
          M3ActionMenu.item(
            context: context,
            label: strings.filterCustomDate,
            icon: Icons.date_range_rounded,
            isSelected: _dateFilter == DateFilterType.custom,
            onPressed: () => _pickCustomDateRange(context),
          ),
          M3ActionMenu.divider(),
          M3ActionMenu.item(
            context: context,
            label: isAr ? 'كافة الفترات (الكل)' : (isHi ? 'सभी समय' : 'All Time'),
            icon: Icons.calendar_today_rounded,
            isSelected: _dateFilter == DateFilterType.all,
            onPressed: () {
              setState(() {
                _dateFilter = DateFilterType.all;
                _customDateRange = null;
              });
              _resetPagination();
            },
          ),
        ],
      );
    }

    Widget buildMobileActionsGroup() {
      return Container(
        height: 38,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. CSV Button (Icon + "CSV")
              Tooltip(
                message: strings.exportCsvBtn,
                child: InkWell(
                  onTap: () => _exportInvoicesToCsv(allInvoices, strings),
                  borderRadius: isAr
                      ? const BorderRadius.horizontal(right: Radius.circular(9))
                      : const BorderRadius.horizontal(left: Radius.circular(9)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.file_download_outlined, size: 15, color: colorScheme.primary),
                        const SizedBox(width: 3),
                        Text(
                          'CSV',
                          style: GoogleFonts.cairo(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              VerticalDivider(width: 1, thickness: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              // 2. Filter Campaigns / Festivals (Icon only)
              Tooltip(
                message: isAr ? 'تصفية الفعاليات والمهرجانات' : (isHi ? 'अभियान फ़िल्टर' : 'Filter Campaigns'),
                child: InkWell(
                  onTap: () => _showCampaignSelectorDialog(
                    context: context,
                    colorScheme: colorScheme,
                    strings: strings,
                    isAr: isAr,
                    eventsMap: scopedEventsMap,
                    availableCompanies: availableCompanies,
                    allInvoices: allInvoices,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                    child: Icon(
                      Icons.tune_rounded,
                      size: 16,
                      color: _selectedCampaignId != 'all' ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              VerticalDivider(width: 1, thickness: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              // 3. Clear Filters (Icon only)
              Tooltip(
                message: strings.clearFiltersBtn,
                child: InkWell(
                  onTap: hasActiveFilters ? _resetFilters : null,
                  borderRadius: isAr
                      ? const BorderRadius.horizontal(left: Radius.circular(9))
                      : const BorderRadius.horizontal(right: Radius.circular(9)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                    child: Icon(
                      Icons.filter_alt_off_rounded,
                      size: 16,
                      color: hasActiveFilters ? colorScheme.error : colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final exportCsvButton = M3ActionMenu(
      tooltip: isAr ? 'تصدير البيانات (CSV)' : 'Export CSV',
      anchorBuilder: (context, controller, child) {
        return FilledButton.tonalIcon(
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: Text(strings.exportCsvBtn, style: const TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      },
      children: [
        M3ActionMenu.header(
          context: context,
          title: isAr ? 'خيارات التصدير والتقارير' : 'Export & Report Options',
          icon: Icons.download_rounded,
        ),
        M3ActionMenu.item(
          context: context,
          label: isAr ? 'تصدير جدول الفواتير (CSV)' : 'Export Invoices Table (CSV)',
          icon: Icons.table_chart_rounded,
          onPressed: () => _exportInvoicesToCsv(allInvoices, strings),
        ),
        M3ActionMenu.submenu(
          context: context,
          label: isAr ? 'تنسيقات إضافية ومتقدمة' : 'Advanced Formats',
          icon: Icons.tune_rounded,
          children: [
            M3ActionMenu.item(
              context: context,
              label: isAr ? 'ملف إكسيل شامل (Excel / CSV)' : 'Full Excel Data (.csv)',
              icon: Icons.description_rounded,
              onPressed: () => _exportInvoicesToCsv(allInvoices, strings),
            ),
            M3ActionMenu.item(
              context: context,
              label: isAr ? 'طباعة / حفظ بتنسيق PDF' : 'Print / Export PDF',
              icon: Icons.print_rounded,
              onPressed: () => _exportInvoicesToCsv(allInvoices, strings),
            ),
          ],
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobileLayout = constraints.maxWidth < 600;

        return Container(
          padding: EdgeInsets.fromLTRB(isMobileLayout ? 12 : 20, 8, isMobileLayout ? 12 : 20, 8),
          color: colorScheme.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isMobileLayout) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      buildReceiptLookupButton(isMobile: false),
                      if (_searchController.text.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        buildActiveSearchChip(),
                      ],
                      const SizedBox(width: 10),
                      buildCampaignPickerWidget(isMobile: false),
                      const SizedBox(width: 10),
                      statusFilterWidget,
                      const SizedBox(width: 10),
                      buildBranchPickerWidget(isMobile: false),
                      const SizedBox(width: 10),
                      buildDatePickerWidget(isMobile: false),
                      const SizedBox(width: 10),
                      exportCsvButton,
                      if (hasActiveFilters) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: strings.clearFiltersBtn,
                          icon: Icon(Icons.filter_alt_off_rounded, color: colorScheme.error),
                          onPressed: _resetFilters,
                        ),
                      ],
                    ],
                  ),
                ),
              ] else ...[
                // Row 1: Full-Width Receipt Lookup Button
                SizedBox(
                  width: double.infinity,
                  child: buildReceiptLookupButton(isMobile: true),
                ),
                if (_searchController.text.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: isAr ? Alignment.centerRight : Alignment.centerLeft,
                    child: buildActiveSearchChip(),
                  ),
                ],
                const SizedBox(height: 8),

                // Row 2: Full-Width Segmented Status Controls
                SizedBox(
                  width: double.infinity,
                  child: statusFilterWidget,
                ),
                const SizedBox(height: 8),

                // Row 3: All-In-One Unified Mobile Row (الفعاليات + الفروع)
                Row(
                  children: [
                    Expanded(child: buildCampaignPickerWidget(isMobile: true)),
                    const SizedBox(width: 6),
                    Expanded(child: buildBranchPickerWidget(isMobile: true)),
                  ],
                ),
                const SizedBox(height: 8),

                // Row 4: (التاريخ + مجموعة أزرار الإجراءات CSV/فلترة/مسح)
                Row(
                  children: [
                    Expanded(child: buildDatePickerWidget(isMobile: true)),
                    const SizedBox(width: 6),
                    buildMobileActionsGroup(),
                  ],
                ),
              ],
            ],
          ),
        );
      },
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
    String filterStatus = 'active';
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
                            avatar: Icon(Icons.check_circle_rounded, size: 15, color: colorScheme.tertiary),
                            label: Text(isAr ? 'النشطة حالياً' : 'Active Now'),
                            selected: filterStatus == 'active',
                            onSelected: (_) => setModalState(() => filterStatus = filterStatus == 'active' ? 'all' : 'active'),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            avatar: Icon(Icons.history_rounded, size: 15, color: colorScheme.outline),
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
                                                    color: isActive ? colorScheme.tertiaryContainer : colorScheme.surfaceContainerLow,
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: isActive ? colorScheme.tertiaryFixedDim : colorScheme.outlineVariant,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Container(
                                                        width: 6,
                                                        height: 6,
                                                        decoration: BoxDecoration(
                                                          color: isActive ? colorScheme.onTertiaryFixedVariant : colorScheme.outline,
                                                          shape: BoxShape.circle,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        isActive ? (isAr ? 'نشطة' : 'Active') : (isAr ? 'منتهية' : 'Ended'),
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: isActive ? colorScheme.onTertiaryContainer : colorScheme.onSurfaceVariant,
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

  Future<void> _openReceiptLookupDialog({
    required BuildContext context,
    required bool isAr,
    required AppStrings strings,
    required List<Map<String, dynamic>> allInvoices,
    required Map<String, EventModel> eventsMap,
  }) async {
    final transController = TextEditingController();
    final posController = TextEditingController();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final transRaw = transController.text.trim().toEnglishDigits();
            final posRaw = posController.text.trim().toEnglishDigits();

            // Auto-parse if user typed or pasted the full barcode e.g. 263/2/243/021026
            String effectiveTrans = transRaw;
            String effectivePos = posRaw;
            if (transRaw.contains('/')) {
              final parts = transRaw.split('/');
              effectiveTrans = parts[0].trim();
              if (parts.length > 1 && effectivePos.isEmpty) {
                effectivePos = parts[1].trim();
              }
            }

            final List<Map<String, dynamic>> matchingInvoices;
            if (effectiveTrans.isEmpty && effectivePos.isEmpty) {
              matchingInvoices = [];
            } else {
              matchingInvoices = allInvoices.where((inv) {
                final receiptNum = (inv['receipt_number'] ?? '').toString();
                final docId = (inv['id'] ?? '').toString();
                final segments = receiptNum.split(RegExp(r'[/\\-_ ]+'));

                bool transMatches = false;
                if (effectiveTrans.isNotEmpty) {
                  if (segments.isNotEmpty && segments[0] == effectiveTrans) {
                    transMatches = true;
                  } else if (segments.contains(effectiveTrans)) {
                    transMatches = true;
                  } else if (receiptNum.contains(effectiveTrans) || docId.contains(effectiveTrans)) {
                    transMatches = true;
                  }
                } else {
                  transMatches = true;
                }

                bool posMatches = false;
                if (effectivePos.isNotEmpty) {
                  if (segments.length > 1 && segments[1] == effectivePos) {
                    posMatches = true;
                  } else if (receiptNum.contains('/$effectivePos/') || receiptNum.contains('-$effectivePos-')) {
                    posMatches = true;
                  }
                } else {
                  posMatches = true;
                }

                return transMatches && posMatches;
              }).toList();
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: colorScheme.surfaceContainer,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.receipt_long_rounded, color: colorScheme.primary, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isAr ? 'البحث المفصل عن الفاتورة' : 'Detailed Receipt Search',
                                  style: GoogleFonts.cairo(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  isAr
                                      ? 'أدخل رقم الحركة (Trans) ورقم الكاشير (PoS) المطبوعين بالفاتورة'
                                      : 'Enter Trans and PoS numbers printed on the receipt',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Visual Receipt Diagram Box
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.info_outline_rounded, size: 14, color: colorScheme.primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      isAr ? 'أين تجد هذه الأرقام في الفاتورة الورقية؟' : 'Where to find them on receipt:',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  'Fathalla / Retail POS',
                                  style: TextStyle(fontSize: 10, color: colorScheme.outline),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Trans: [263]   PoS: [2]   Store: [243]   Date: 02/10/26\nBarcode: [ 263 / 2 / 243 / 021026 ]',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Form Inputs Row
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: transController,
                              autofocus: true,
                              textDirection: TextDirection.ltr,
                              textAlign: TextAlign.left,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                const ArabicToEnglishDigitsFormatter.digitsOnly(),
                              ],
                              onChanged: (_) => setDialogState(() {}),
                              decoration: InputDecoration(
                                labelText: isAr ? 'رقم الحركة (Trans #)' : 'Trans Number',
                                hintText: 'مثال: 263',
                                prefixIcon: const Icon(Icons.tag_rounded, size: 18),
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: posController,
                              textDirection: TextDirection.ltr,
                              textAlign: TextAlign.left,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                const ArabicToEnglishDigitsFormatter.digitsOnly(),
                              ],
                              onChanged: (_) => setDialogState(() {}),
                              decoration: InputDecoration(
                                labelText: isAr ? 'الكاشير (PoS #)' : 'PoS Number',
                                hintText: 'مثال: 2',
                                prefixIcon: const Icon(Icons.point_of_sale_rounded, size: 18),
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Live Results Section
                      Expanded(
                        child: effectiveTrans.isEmpty && effectivePos.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.search_rounded, size: 40, color: colorScheme.outlineVariant),
                                    const SizedBox(height: 8),
                                    Text(
                                      isAr
                                          ? 'اكتب رقم الحركة (Trans) للبحث التلقائي في أجزاء من الثانية'
                                          : 'Type Trans number to instantly search matching invoices',
                                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              )
                            : matchingInvoices.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.search_off_rounded, size: 40, color: colorScheme.secondary),
                                        const SizedBox(height: 8),
                                        Text(
                                          isAr
                                              ? 'لم يتم العثور على فاتورة برقم حركة ($effectiveTrans)${effectivePos.isNotEmpty ? " وكاشير ($effectivePos)" : ""}'
                                              : 'No receipt found matching Trans ($effectiveTrans)',
                                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: matchingInvoices.length,
                                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final inv = matchingInvoices[index];
                                      final docId = inv['id'] as String;
                                      final receiptNum = inv['receipt_number']?.toString() ?? 'N/A';
                                      final branch = inv['canonical_branch']?.toString() ?? inv['branch_detected']?.toString() ?? '';
                                      final dateStr = inv['formattedDate']?.toString() ?? '';
                                      final campaignId = inv['campaignId']?.toString() ?? '';
                                      final event = eventsMap[campaignId];
                                      final eventTitle = event?.eventName ?? inv['eventName']?.toString() ?? '';
                                      final totalValue = (inv['target_company_total'] ?? inv['total_value'] ?? 0);
                                      final chances = (inv['chances_earned'] ?? 1) as int;
                                      final isValid = inv['is_valid'] == true || inv['status'] == 'accepted' || inv['isValid'] == true;

                                      return Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: colorScheme.surface,
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(
                                            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Flexible(
                                                  child: Directionality(
                                                    textDirection: TextDirection.ltr,
                                                    child: Text(
                                                      '#$receiptNum',
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.bold,
                                                        letterSpacing: 0.5,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: isValid
                                                        ? colorScheme.tertiary.withValues(alpha: 0.12)
                                                        : colorScheme.error.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    isValid
                                                        ? (isAr ? 'مقبولة ($chances كارت)' : 'Accepted ($chances cards)')
                                                        : (isAr ? 'مرفوضة' : 'Rejected'),
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: isValid ? colorScheme.onTertiaryFixedVariant : colorScheme.onErrorContainer,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Icon(Icons.storefront_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    branch.isNotEmpty ? branch : (isAr ? 'غير محدد' : 'Unknown'),
                                                    style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Text(
                                                  '$totalValue ج.م',
                                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(Icons.event_note_rounded, size: 14, color: colorScheme.outline),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    '$eventTitle • $dateStr',
                                                    style: TextStyle(fontSize: 10.5, color: colorScheme.outline),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            SizedBox(
                                              width: double.infinity,
                                              child: FilledButton.icon(
                                                style: FilledButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                ),
                                                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                                                label: Text(
                                                  isAr ? 'فتح وفحص الفاتورة فوراً (0ms)' : 'Open & Inspect Receipt',
                                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
                                                ),
                                                onPressed: () {
                                                  Navigator.of(dialogCtx).pop();
                                                  setState(() {
                                                    if (campaignId.isNotEmpty && _selectedCampaignId != campaignId) {
                                                      _selectedCampaignId = campaignId;
                                                    }
                                                    _selectedDocId = docId;
                                                    _searchController.text = receiptNum;
                                                    _resetPagination();
                                                  });
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Row(
                                                        children: [
                                                          Icon(Icons.check_circle_rounded, color: colorScheme.tertiaryFixedDim),
                                                          const SizedBox(width: 8),
                                                          Text(
                                                            isAr
                                                                ? 'تم فتح الفاتورة #$receiptNum بنجاح'
                                                                : 'Receipt #$receiptNum opened successfully',
                                                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                                                          ),
                                                        ],
                                                      ),
                                                      duration: const Duration(seconds: 2),
                                                      behavior: SnackBarBehavior.floating,
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                      ),
                      const SizedBox(height: 12),

                      // Bottom actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            child: Text(isAr ? 'إغلاق' : 'Close'),
                          ),
                          if (matchingInvoices.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              onPressed: () {
                                Navigator.of(dialogCtx).pop();
                                setState(() {
                                  _searchController.text = effectiveTrans;
                                  _resetPagination();
                                });
                              },
                              child: Text(
                                isAr
                                    ? 'تطبيق كفلتر (${matchingInvoices.length} نتيجة)'
                                    : 'Apply Filter (${matchingInvoices.length})',
                                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _getDateFilterLabel(AppStrings strings) {
    final isAr = ref.isArabic;
    final isHi = ref.isHindi;
    switch (_dateFilter) {
      case DateFilterType.all:
        return isAr ? 'كافة الفترات' : (isHi ? 'सभी समय' : 'All Time');
      case DateFilterType.today:
        return strings.filterToday;
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

  // ---------------------------------------------------------------------------
  // Branch Invoices Distribution & Analytics Chart (البيان الإحصائي لتوزيع فواتير الفروع)
  // Dynamic visual reporting by date filter, branch ranking, and interactive fl_chart
  // ---------------------------------------------------------------------------

  Widget _buildBranchInvoicesChartCard({
    required List<Map<String, dynamic>> allInvoices,
    required List<String> canonicalBranches,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required CountryCurrency activeCountry,
    required bool isAr,
    required bool isMobile,
  }) {
    if (canonicalBranches.isEmpty && allInvoices.isEmpty) {
      return const SizedBox.shrink();
    }

    // 1. Filter invoices strictly by campaign, company, date, and status (ignoring _selectedBranch for the chart)
    final periodInvoices = allInvoices.where((inv) {
      if (_selectedCampaignId != 'all' && inv['campaignId'] != _selectedCampaignId) return false;
      if (_selectedCompanySlug != 'all') {
        final slug = (inv['companySlug'] ?? '').toString().toLowerCase();
        final target = (inv['targetCompany'] ?? '').toString().toLowerCase();
        if (slug != _selectedCompanySlug.toLowerCase() && !target.contains(_selectedCompanySlug.toLowerCase())) {
          return false;
        }
      }
      if (!_passesDateFilter(inv['date'] as DateTime?)) return false;

      final bool isExplicitlyValid = inv['is_valid'] == true || inv['status'] == 'accepted' || inv['isValid'] == true;
      final bool isExplicitlyRejected = inv['is_valid'] == false || inv['status'] == 'rejected' || inv['isValid'] == false || ((inv['unfulfilled_conditions'] as List?)?.isNotEmpty ?? false);
      final bool isValid = isExplicitlyValid || (!isExplicitlyRejected && ((inv['unfulfilled_conditions'] as List?)?.isEmpty ?? true));
      if (_statusFilter == 'accepted' && !isValid) return false;
      if (_statusFilter == 'rejected' && isValid) return false;

      return true;
    }).toList();

    final totalPeriodInvoices = periodInvoices.length;

    // 2. Aggregate per canonical branch
    final Map<String, int> branchInvoiceCounts = {};
    final Map<String, double> branchSalesMap = {};
    final Map<String, int> branchItemsMap = {};

    for (final b in canonicalBranches) {
      branchInvoiceCounts[b] = 0;
      branchSalesMap[b] = 0.0;
      branchItemsMap[b] = 0;
    }

    for (final inv in periodInvoices) {
      final b = (inv['canonical_branch'] ?? '').toString().trim();
      if (b.isNotEmpty) {
        branchInvoiceCounts[b] = (branchInvoiceCounts[b] ?? 0) + 1;
        final total = (inv['target_company_total'] ?? inv['total_value'] ?? 0);
        if (total is num) {
          branchSalesMap[b] = (branchSalesMap[b] ?? 0.0) + total.toDouble();
        }
        final products = (inv['extracted_products'] as List?) ?? [];
        for (final p in products) {
          if (p is Map) {
            final qty = p['quantity'];
            branchItemsMap[b] = (branchItemsMap[b] ?? 0) + (qty is num ? qty.toInt() : 1);
          }
        }
      }
    }

    // Build branch stats
    final List<_BranchStat> branchStats = [];
    for (final entry in branchInvoiceCounts.entries) {
      final count = entry.value;
      final sales = branchSalesMap[entry.key] ?? 0.0;
      final items = branchItemsMap[entry.key] ?? 0;
      final pct = totalPeriodInvoices > 0 ? (count / totalPeriodInvoices) * 100 : 0.0;
      branchStats.add(_BranchStat(
        branchName: entry.key,
        invoicesCount: count,
        promoSales: sales,
        extractedItems: items,
        percentage: pct,
      ));
    }

    // Sort descending by invoices count
    branchStats.sort((a, b) {
      final cmp = b.invoicesCount.compareTo(a.invoicesCount);
      if (cmp != 0) return cmp;
      return b.promoSales.compareTo(a.promoSales);
    });

    final activeBranchesCount = branchStats.where((b) => b.invoicesCount > 0).length;
    final maxInvoices = branchStats.isNotEmpty ? branchStats.first.invoicesCount : 0;
    final currency = activeCountry.currencySymbol;
    final dateFilterLabel = _getDateFilterLabel(strings);

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 20,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Row 1: Icon + Title ("توزيع فواتير الفروع") + Subtitle
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.bar_chart_rounded,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  isAr ? 'توزيع فواتير الفروع' : strings.branchInvoicesChartTitle,
                                  style: GoogleFonts.cairo(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  isAr
                                      ? 'إجمالي الفروع النشطة: $activeBranchesCount من أصل ${canonicalBranches.length} فرع معتمد'
                                      : 'Active Branches: $activeBranchesCount of ${canonicalBranches.length} canonical branches',
                                  style: GoogleFonts.cairo(
                                    fontSize: 10.5,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (_selectedBranch != 'all')
                            ActionChip(
                              avatar: Icon(Icons.check_circle_rounded, size: 14, color: colorScheme.primary),
                              label: Text(
                                '$_selectedBranch ✕',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                              backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
                              side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.4)),
                              onPressed: () {
                                setState(() {
                                  _selectedBranch = 'all';
                                  _resetPagination();
                                });
                              },
                              tooltip: strings.showAllBranchesBtn,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Row 2: Dynamic Period Badge + View Mode Switcher + Collapse Button (كلهم في نفس الصف في الموبايل)
                      Row(
                        children: [
                          // Dynamic Period Badge (نطاق التاريخ • 111 فاتورة)
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: colorScheme.primary.withValues(alpha: 0.25),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.event_note_rounded,
                                    size: 13,
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      '$dateFilterLabel • $totalPeriodInvoices ${isAr ? "فاتورة" : "Invoices"}',
                                      style: GoogleFonts.cairo(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // View Mode Switcher: Ranked Bars vs BarChart
                          Container(
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.all(2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildChartModeOption(
                                  icon: Icons.view_headline_rounded,
                                  isSelected: _branchChartViewMode == 0,
                                  tooltip: isAr ? 'أشرطة الحصص والتفوق' : 'Ranked Share Bars',
                                  colorScheme: colorScheme,
                                  onTap: () => setState(() => _branchChartViewMode = 0),
                                ),
                                _buildChartModeOption(
                                  icon: Icons.bar_chart_rounded,
                                  isSelected: _branchChartViewMode == 1,
                                  tooltip: isAr ? 'مخطط الأعمدة' : 'Bar Chart',
                                  colorScheme: colorScheme,
                                  onTap: () => setState(() => _branchChartViewMode = 1),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),

                          // Expand / Collapse
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              _isBranchChartExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: colorScheme.onSurfaceVariant,
                              size: 20,
                            ),
                            tooltip: _isBranchChartExpanded
                                ? (isAr ? 'طي البيان البياني' : 'Collapse Chart')
                                : (isAr ? 'توسيع البيان البياني' : 'Expand Chart'),
                            onPressed: () {
                              setState(() {
                                _isBranchChartExpanded = !_isBranchChartExpanded;
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      // Desktop Header: Icon + Title + Period Badge
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.bar_chart_rounded,
                          color: colorScheme.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isAr ? 'توزيع فواتير الفروع' : strings.branchInvoicesChartTitle,
                                style: GoogleFonts.cairo(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Dynamic Period Badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: colorScheme.primary.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.event_note_rounded,
                                      size: 13,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      dateFilterLabel,
                                      style: GoogleFonts.cairo(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                    Text(
                                      ' • $totalPeriodInvoices ${isAr ? "فاتورة" : "Invoices"}',
                                      style: GoogleFonts.cairo(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Text(
                            isAr
                                ? 'إجمالي الفروع النشطة: $activeBranchesCount من أصل ${canonicalBranches.length} فرع معتمد'
                                : 'Active Branches: $activeBranchesCount of ${canonicalBranches.length} canonical branches',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),

                      // Controls: Filtered branch pill + View mode toggle + Collapse button
                      if (_selectedBranch != 'all')
                        Container(
                          margin: const EdgeInsetsDirectional.only(end: 8),
                          child: ActionChip(
                            avatar: Icon(Icons.check_circle_rounded, size: 16, color: colorScheme.primary),
                            label: Text(
                              '$_selectedBranch ✕',
                              style: GoogleFonts.cairo(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                            backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.25),
                            side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.4)),
                            onPressed: () {
                              setState(() {
                                _selectedBranch = 'all';
                                _resetPagination();
                              });
                            },
                            tooltip: strings.showAllBranchesBtn,
                          ),
                        ),

                      // View Mode Switcher: Ranked Bars vs BarChart
                      Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildChartModeOption(
                              icon: Icons.view_headline_rounded,
                              isSelected: _branchChartViewMode == 0,
                              tooltip: isAr ? 'أشرطة الحصص والتفوق' : 'Ranked Share Bars',
                              colorScheme: colorScheme,
                              onTap: () => setState(() => _branchChartViewMode = 0),
                            ),
                            _buildChartModeOption(
                              icon: Icons.bar_chart_rounded,
                              isSelected: _branchChartViewMode == 1,
                              tooltip: isAr ? 'مخطط الأعمدة' : 'Bar Chart',
                              colorScheme: colorScheme,
                              onTap: () => setState(() => _branchChartViewMode = 1),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 6),

                      // Expand / Collapse
                      IconButton(
                        icon: Icon(
                          _isBranchChartExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        tooltip: _isBranchChartExpanded
                            ? (isAr ? 'طي البيان البياني' : 'Collapse Chart')
                            : (isAr ? 'توسيع البيان البياني' : 'Expand Chart'),
                        onPressed: () {
                          setState(() {
                            _isBranchChartExpanded = !_isBranchChartExpanded;
                          });
                        },
                      ),
                    ],
                  ),
          ),

          // Body: when expanded
          if (_isBranchChartExpanded) ...[
            const Divider(height: 1, thickness: 1),
            if (totalPeriodInvoices == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.event_busy_rounded,
                      size: 36,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${strings.noInvoicesForSelectedPeriod} ($dateFilterLabel)',
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else if (_branchChartViewMode == 0)
              _buildBranchRankedBarsView(
                branchStats: branchStats,
                maxInvoices: maxInvoices,
                currency: currency,
                colorScheme: colorScheme,
                strings: strings,
                isAr: isAr,
              )
            else
              _buildBranchFlBarChartView(
                branchStats: branchStats,
                currency: currency,
                colorScheme: colorScheme,
                strings: strings,
                isAr: isAr,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildChartModeOption({
    required IconData icon,
    required bool isSelected,
    required String tooltip,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? colorScheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 18,
            color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildBranchRankedBarsView({
    required List<_BranchStat> branchStats,
    required int maxInvoices,
    required String currency,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
  }) {
    final displayStats = branchStats.where((b) => b.invoicesCount > 0).toList();
    final effectiveStats = displayStats.isEmpty ? branchStats : displayStats;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 850;
        final halfLength = (effectiveStats.length / 2).ceil();
        final col1 = isWide ? effectiveStats.take(halfLength).toList() : effectiveStats;
        final col2 = isWide ? effectiveStats.skip(halfLength).toList() : <_BranchStat>[];

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: col1.asMap().entries.map((entry) {
                          return _buildBranchRowCard(
                            stat: entry.value,
                            rank: entry.key + 1,
                            maxInvoices: maxInvoices,
                            currency: currency,
                            colorScheme: colorScheme,
                            strings: strings,
                            isAr: isAr,
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        children: col2.asMap().entries.map((entry) {
                          return _buildBranchRowCard(
                            stat: entry.value,
                            rank: halfLength + entry.key + 1,
                            maxInvoices: maxInvoices,
                            currency: currency,
                            colorScheme: colorScheme,
                            strings: strings,
                            isAr: isAr,
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: effectiveStats.asMap().entries.map((entry) {
                    return _buildBranchRowCard(
                      stat: entry.value,
                      rank: entry.key + 1,
                      maxInvoices: maxInvoices,
                      currency: currency,
                      colorScheme: colorScheme,
                      strings: strings,
                      isAr: isAr,
                    );
                  }).toList(),
                ),
        );
      },
    );
  }

  Widget _buildBranchRowCard({
    required _BranchStat stat,
    required int rank,
    required int maxInvoices,
    required String currency,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
  }) {
    final isSelected = _selectedBranch == stat.branchName;
    final progress = maxInvoices > 0 ? (stat.invoicesCount / maxInvoices).clamp(0.0, 1.0) : 0.0;

    String rankPrefix;
    Color rankColor;
    if (rank == 1) {
      rankPrefix = '🥇 #1';
      rankColor = colorScheme.primaryFixedDim;
    } else if (rank == 2) {
      rankPrefix = '🥈 #2';
      rankColor = colorScheme.outline;
    } else if (rank == 3) {
      rankPrefix = '🥉 #3';
      rankColor = colorScheme.secondary;
    } else {
      rankPrefix = '#$rank';
      rankColor = colorScheme.onSurfaceVariant;
    }

    return Tooltip(
      message: strings.filterByThisBranchTooltip,
      child: InkWell(
        onTap: () {
          setState(() {
            if (_selectedBranch == stat.branchName) {
              _selectedBranch = 'all';
            } else {
              _selectedBranch = stat.branchName;
            }
            _resetPagination();
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primaryContainer.withValues(alpha: 0.25)
                : colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: isSelected ? 1.8 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: Rank + Branch Name + Badges
              Row(
                children: [
                  // Rank badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: rankColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: rankColor.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      rankPrefix,
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: rankColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Branch Name
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            stat.branchName,
                            style: GoogleFonts.cairo(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isAr ? 'محدد' : 'Selected',
                              style: GoogleFonts.cairo(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Invoices count badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      '${stat.invoicesCount} ${isAr ? "فاتورة" : "Invoices"}',
                      style: GoogleFonts.cairo(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),

                  const SizedBox(width: 6),

                  // Share %
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${stat.percentage.toStringAsFixed(1)}%',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isSelected
                        ? colorScheme.primary
                        : (rank == 1 ? colorScheme.primary : colorScheme.secondary),
                  ),
                ),
              ),

              if (stat.promoSales > 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${isAr ? "مبيعات" : "Sales"}: ${NumberFormat('#,##0').format(stat.promoSales)} $currency',
                      style: GoogleFonts.cairo(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBranchFlBarChartView({
    required List<_BranchStat> branchStats,
    required String currency,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
  }) {
    final activeStats = branchStats.where((b) => b.invoicesCount > 0).toList();
    final effectiveStats = activeStats.isEmpty ? branchStats.take(6).toList() : activeStats.take(12).toList();
    final maxInvoices = effectiveStats.fold<int>(0, (prev, e) => math.max(prev, e.invoicesCount));
    final maxY = (maxInvoices * 1.25).ceilToDouble().clamp(5.0, 999999.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => colorScheme.surfaceContainerHighest,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final item = effectiveStats[groupIndex];
                      final formattedSales = NumberFormat.compact().format(item.promoSales);
                      return BarTooltipItem(
                        '${item.branchName}\n',
                        GoogleFonts.cairo(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        children: [
                          TextSpan(
                            text: '${item.invoicesCount} ${isAr ? "فاتورة" : "Invoices"} (${item.percentage.toStringAsFixed(1)}%)\n',
                            style: GoogleFonts.cairo(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                            ),
                          ),
                          TextSpan(
                            text: '$formattedSales $currency',
                            style: GoogleFonts.cairo(
                              color: colorScheme.secondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  touchCallback: (event, response) {
                    if (event is FlTapUpEvent && response?.spot != null) {
                      final idx = response!.spot!.touchedBarGroupIndex;
                      if (idx >= 0 && idx < effectiveStats.length) {
                        final clickedBranch = effectiveStats[idx].branchName;
                        setState(() {
                          if (_selectedBranch == clickedBranch) {
                            _selectedBranch = 'all';
                          } else {
                            _selectedBranch = clickedBranch;
                          }
                          _resetPagination();
                        });
                      }
                    }
                  },
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) {
                        if (value == 0 || value == (maxY / 2).roundToDouble() || value == maxY) {
                          return Text(
                            value.toInt().toString(),
                            style: GoogleFonts.cairo(
                              fontSize: 9.5,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < effectiveStats.length) {
                          final item = effectiveStats[idx];
                          final isSelected = _selectedBranch == item.branchName;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '#${idx + 1}',
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (val) => FlLine(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(effectiveStats.length, (idx) {
                  final item = effectiveStats[idx];
                  final isSelected = _selectedBranch == item.branchName;
                  return BarChartGroupData(
                    x: idx,
                    barRods: [
                      BarChartRodData(
                        toY: item.invoicesCount.toDouble(),
                        color: isSelected ? colorScheme.primary : colorScheme.secondary,
                        width: effectiveStats.length > 8 ? 16 : 22,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Legend below chart showing ranks and names
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: List.generate(effectiveStats.length, (idx) {
              final item = effectiveStats[idx];
              final isSelected = _selectedBranch == item.branchName;
              return InkWell(
                onTap: () {
                  setState(() {
                    if (_selectedBranch == item.branchName) {
                      _selectedBranch = 'all';
                    } else {
                      _selectedBranch = item.branchName;
                    }
                    _resetPagination();
                  });
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '#${idx + 1} ${item.branchName} (${item.invoicesCount})',
                    style: GoogleFonts.cairo(
                      fontSize: 10.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopCompactInvoiceTile({
    required BuildContext context,
    required Map<String, dynamic> inv,
    required bool isSelected,
    required ColorScheme colorScheme,
    required CountryCurrency activeCountry,
    required AppStrings strings,
    required bool isAr,
    required bool isAdmin,
    required Map<String, EventModel> eventsMap,
    required VoidCallback onTap,
  }) {
    final docId = inv['id'] as String;
    final receiptNumber = inv['receipt_number']?.toString() ?? 'N/A';
    final totalValue = inv['target_company_total'] ?? inv['total_value'] ?? 0;
    final storeChain = (inv['store_chain_detected'] ?? inv['retail_chain_name'] ?? '').toString();
    final branch = (inv['branch_detected'] ?? '').toString();
    final formattedDate = inv['formattedDate']?.toString() ?? '';
    final durationSec = inv['analysis_duration_seconds'] is num
        ? (inv['analysis_duration_seconds'] as num).toDouble()
        : null;
    final products = (inv['extracted_products'] as List?) ?? [];

    final imageUrl = inv['image_url']?.toString() ?? '';
    final List<String> allReceiptUrls = [];
    if (inv['image_urls'] is List && (inv['image_urls'] as List).isNotEmpty) {
      allReceiptUrls.addAll((inv['image_urls'] as List).map((e) => e.toString()).where((e) => e.isNotEmpty));
    }
    if (allReceiptUrls.isEmpty && imageUrl.isNotEmpty) {
      allReceiptUrls.add(imageUrl);
    }
    final isRechecking = _recheckingDocIds.contains(docId);
    final campaignId = (inv['campaignId'] ?? '').toString();
    final event = eventsMap[campaignId];

    final bool isExplicitlyValid = inv['is_valid'] == true || inv['status'] == 'accepted' || inv['isValid'] == true;
    final bool isExplicitlyRejected = inv['is_valid'] == false || inv['status'] == 'rejected' || inv['isValid'] == false || ((inv['unfulfilled_conditions'] as List?)?.isNotEmpty ?? false);
    final bool isValid = isExplicitlyValid || (!isExplicitlyRejected && ((inv['unfulfilled_conditions'] as List?)?.isEmpty ?? true));

    final statusColor = isValid ? colorScheme.tertiary : colorScheme.error;
    final statusText = isValid
        ? (isAr ? 'مقبولة' : 'Accepted')
        : (isAr ? 'مرفوضة' : 'Rejected');
    final statusIcon = isValid ? Icons.check_circle_rounded : Icons.cancel_rounded;

    final avatarWidget = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isValid
            ? colorScheme.primary.withValues(alpha: 0.12)
            : colorScheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isValid
              ? colorScheme.primary.withValues(alpha: 0.3)
              : colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Center(
        child: Icon(
          Icons.storefront_rounded,
          color: isValid ? colorScheme.primary : colorScheme.error,
          size: 20,
        ),
      ),
    );

    final headlineWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            '#$receiptNumber',
            style: GoogleFonts.cairo(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (durationSec != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: durationSec <= 2.0
                  ? colorScheme.tertiaryContainer
                  : (durationSec <= 3.5 ? colorScheme.tertiaryContainer : colorScheme.secondaryContainer),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '⚡${durationSec.toStringAsFixed(1)}s',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                color: durationSec <= 2.0 ? colorScheme.onTertiaryContainer : colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ],
    );

    final subtitleWidget = Text(
      storeChain.isNotEmpty
          ? (branch.isNotEmpty ? '$storeChain - $branch' : storeChain)
          : (branch.isNotEmpty ? branch : (isAr ? 'متجر غير محدد' : 'Unknown Store')),
      style: GoogleFonts.cairo(
        fontSize: 11.5,
        color: colorScheme.onSurfaceVariant,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final supportingWidget = Row(
      children: [
        if (formattedDate.isNotEmpty) ...[
          Icon(Icons.access_time_rounded, size: 11, color: colorScheme.outline),
          const SizedBox(width: 3),
          Text(
            formattedDate,
            style: TextStyle(fontSize: 10, color: colorScheme.outline),
          ),
          const SizedBox(width: 8),
        ],
        Text(
          '${products.length} ${isAr ? "صنف" : "items"}',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: colorScheme.outline,
          ),
        ),
      ],
    );

    final trailingWidget = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$totalValue ${activeCountry.currencySymbol}',
          style: GoogleFonts.cairo(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isSelected ? colorScheme.primary : colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, size: 10, color: statusColor),
              const SizedBox(width: 3),
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: M3ListTile.threeLine(
        leading: avatarWidget,
        headline: headlineWidget,
        subtitle: subtitleWidget,
        supportingText: supportingWidget,
        trailing: trailingWidget,
        trailingActions: [
          M3ActionMenu(
            tooltip: isAr ? 'خيارات الفاتورة' : 'Invoice options',
            children: [
              M3ActionMenu.header(
                context: context,
                title: isAr ? 'إجراءات الفاتورة' : 'Invoice Actions',
                icon: Icons.receipt_long_rounded,
              ),
              M3ActionMenu.item(
                context: context,
                label: isAr ? 'عرض التفاصيل والصورة' : 'View Details & Image',
                icon: Icons.visibility_rounded,
                onPressed: () {
                  onTap();
                  if (allReceiptUrls.isNotEmpty || (inv['storage_path']?.toString().isNotEmpty ?? false)) {
                    _showImagePreviewDialog(
                      context: context,
                      imageUrl: imageUrl,
                      imageUrls: allReceiptUrls,
                      receiptNumber: receiptNumber,
                      store: storeChain,
                      totalValue: totalValue,
                      date: formattedDate,
                      currencySymbol: activeCountry.currencySymbol,
                      colorScheme: colorScheme,
                      strings: strings,
                      docId: docId,
                      storagePath: inv['storage_path']?.toString(),
                      canDelete: isAdmin,
                    );
                  }
                },
              ),
              M3ActionMenu.item(
                context: context,
                label: isAr ? 'تحميل صورة الفاتورة' : 'Download Receipt Image',
                icon: Icons.download_rounded,
                enabled: imageUrl.isNotEmpty,
                onPressed: () {
                  if (imageUrl.isNotEmpty) {
                    launchUrl(Uri.parse(imageUrl), mode: LaunchMode.externalApplication);
                  }
                },
              ),
              if (isAdmin) ...[
                M3ActionMenu.item(
                  context: context,
                  label: isAr ? 'إعادة فحص OCR بالذكاء الاصطناعي' : 'Re-run AI OCR Scan',
                  icon: Icons.sync_rounded,
                  enabled: !isRechecking,
                  onPressed: () => _promptRecheckOptions(
                    context: context,
                    inv: inv,
                    event: event,
                    eventsMap: eventsMap,
                    strings: strings,
                    colorScheme: colorScheme,
                    activeCountry: activeCountry,
                    isAr: isAr,
                  ),
                ),
                M3ActionMenu.divider(),
                M3ActionMenu.item(
                  context: context,
                  label: isAr ? 'إلغاء وحذف الفاتورة' : 'Cancel & Delete Invoice',
                  icon: Icons.delete_rounded,
                  isDestructive: true,
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
                ),
              ],
            ],
          ),
        ],
        isSelected: isSelected,
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        backgroundColor: colorScheme.surfaceContainerLow,
        semanticsLabel: isAr
            ? 'فاتورة رقم $receiptNumber، $statusText، الإجمالي $totalValue ${activeCountry.currencySymbol}'
            : 'Invoice $receiptNumber, $statusText, Total $totalValue ${activeCountry.currencySymbol}',
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

    // Material Design 3 Dual-Pane List-Detail Layout on Desktop (≥ 960dp)
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktopMultiPane = !isMobile && screenWidth >= 960;

    if (isDesktopMultiPane) {
      if (_selectedDocId == null || !visibleInvoices.any((i) => i['id'] == _selectedDocId)) {
        if (visibleInvoices.isNotEmpty) {
          _selectedDocId = visibleInvoices.first['id'] as String?;
        }
      }

      final selectedInv = visibleInvoices.firstWhere(
        (i) => i['id'] == _selectedDocId,
        orElse: () => visibleInvoices.isNotEmpty ? visibleInvoices.first : <String, dynamic>{},
      );

      final selectedEvent = selectedInv.isNotEmpty
          ? eventsMap[(selectedInv['campaignId'] ?? '').toString()]
          : null;

      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: KeyedSubtree(
          key: _feedKey,
          child: M3ListDetailLayout(
            listPaneWidth: 420.0,
            showDivider: false,
            crossAxisAlignment: CrossAxisAlignment.start,
            listPane: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...visibleInvoices.map((inv) {
                  final docId = inv['id'] as String;
                  final isSelected = _selectedDocId == docId;
                  return _buildDesktopCompactInvoiceTile(
                    context: context,
                    inv: inv,
                    isSelected: isSelected,
                    colorScheme: colorScheme,
                    activeCountry: activeCountry,
                    strings: strings,
                    isAr: isAr,
                    isAdmin: isAdmin,
                    eventsMap: eventsMap,
                    onTap: () => setState(() => _selectedDocId = docId),
                  );
                }),
                if (totalPages > 1) ...[
                  const SizedBox(height: M3Spacing.sm),
                  _buildPaginationControls(
                    totalItems: totalItems,
                    currentPage: safePage,
                    pageSize: _pageSize,
                    colorScheme: colorScheme,
                    strings: strings,
                    isAr: isAr,
                    onPageChanged: (newPage) {
                      setState(() {
                        _currentPage = newPage;
                        _selectedDocId = null;
                      });
                      if (_scrollController.hasClients) {
                        _scrollController.animateTo(
                          0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    },
                  ),
                ],
              ],
            ),
            detailPane: selectedInv.isNotEmpty
                ? AnimatedBuilder(
                    animation: _scrollController,
                    builder: (context, child) {
                      double topOffset = 0.0;
                      if (_feedKey.currentContext != null) {
                        final renderBox = _feedKey.currentContext!.findRenderObject() as RenderBox?;
                        if (renderBox != null && renderBox.hasSize) {
                          final feedViewportY = renderBox.localToGlobal(Offset.zero).dy;
                          const targetTopInViewport = 72.0;
                          if (feedViewportY < targetTopInViewport) {
                            final diff = targetTopInViewport - feedViewportY;
                            final maxOffset = (renderBox.size.height - 700.0).clamp(0.0, double.infinity);
                            topOffset = diff.clamp(0.0, maxOffset);
                          }
                        }
                      }

                      return Padding(
                        padding: EdgeInsetsDirectional.only(
                          start: M3Spacing.md,
                          top: topOffset,
                        ),
                        child: child,
                      );
                    },
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height - 90.0,
                      ),
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: _buildInvoiceCard(
                          context: context,
                          inv: selectedInv,
                          event: selectedEvent,
                          eventsMap: eventsMap,
                          colorScheme: colorScheme,
                          activeCountry: activeCountry,
                          strings: strings,
                          isAr: isAr,
                          isMobile: false,
                          isAdmin: isAdmin,
                          isDesktopDetailPane: true,
                        ),
                      ),
                    ),
                  )
                : null,
          ),
        ),
      );
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
    bool isDesktopDetailPane = false,
  }) {
    final docId = inv['id'] as String;
    final isExpanded = isDesktopDetailPane || _expandedDocIds.contains(docId);
    final isRechecking = _recheckingDocIds.contains(docId);

    final receiptNumber = inv['receipt_number']?.toString() ?? 'N/A';
    final totalValue = inv['target_company_total'] ?? inv['total_value'] ?? 0;
    final imageUrl = inv['image_url']?.toString() ?? '';
    final List<String> allReceiptUrls = [];
    if (inv['image_urls'] is List && (inv['image_urls'] as List).isNotEmpty) {
      allReceiptUrls.addAll((inv['image_urls'] as List).map((e) => e.toString()).where((e) => e.isNotEmpty));
    }
    if (allReceiptUrls.isEmpty && imageUrl.isNotEmpty) {
      allReceiptUrls.add(imageUrl);
    }
    if (allReceiptUrls.length > 1) {
      allReceiptUrls.sort((a, b) {
        final aPart = RegExp(r'part(\d+)').firstMatch(a.toLowerCase())?.group(1);
        final bPart = RegExp(r'part(\d+)').firstMatch(b.toLowerCase())?.group(1);
        if (aPart != null && bPart != null) {
          return int.parse(aPart).compareTo(int.parse(bPart));
        }
        return a.compareTo(b);
      });
    }
    final int partsCount = (inv['parts_count'] is num)
        ? (inv['parts_count'] as num).toInt()
        : allReceiptUrls.length;
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
          if (isDesktopDetailPane)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                border: Border(
                  bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.rate_review_rounded, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    isAr ? 'لوحة الفحص والتدقيق الفوري (0ms)' : 'Real-time Inspection Pane (0ms)',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '#$receiptNumber',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
                    imageUrl: allReceiptUrls.isNotEmpty ? allReceiptUrls.first : imageUrl,
                    imageUrls: allReceiptUrls.length > 1 ? allReceiptUrls : null,
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
                    message: (imageUrl.isNotEmpty || allReceiptUrls.isNotEmpty)
                        ? (partsCount > 1
                            ? (isAr ? 'فاتورة متعددة الأجزاء ($partsCount أجزاء) - انقر للمعاينة والتقليب' : 'Multi-part receipt ($partsCount parts) - Click to inspect')
                            : (isAr ? 'انقر لمعاينة وتكبير صورة الفاتورة' : 'Click to preview'))
                        : (isAr ? 'لا توجد صورة مسجلة' : 'No image recorded'),
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
                              _buildReceiptImage(allReceiptUrls.isNotEmpty ? allReceiptUrls.first : imageUrl, fit: BoxFit.cover),
                              if (partsCount > 1 || allReceiptUrls.length > 1)
                                Positioned(
                                  top: 3,
                                  left: 3,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.75),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.collections_rounded, size: 9, color: Colors.white),
                                        const SizedBox(width: 2),
                                        Text(
                                          '${partsCount > allReceiptUrls.length ? partsCount : allReceiptUrls.length}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (imageUrl.isNotEmpty || allReceiptUrls.isNotEmpty)
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
                                      ? colorScheme.primaryContainer.withValues(alpha: 0.7)
                                      : (durationSec <= 3.5
                                          ? colorScheme.secondaryContainer.withValues(alpha: 0.7)
                                          : colorScheme.tertiaryContainer.withValues(alpha: 0.7)),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: durationSec <= 2.0
                                        ? colorScheme.primary.withValues(alpha: 0.3)
                                        : (durationSec <= 3.5
                                            ? colorScheme.secondary.withValues(alpha: 0.3)
                                            : colorScheme.tertiary.withValues(alpha: 0.3)),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.bolt_rounded,
                                      size: 12,
                                      color: durationSec <= 2.0
                                          ? colorScheme.primary
                                          : (durationSec <= 3.5 ? colorScheme.secondary : colorScheme.tertiary),
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${durationSec.toStringAsFixed(2)}s',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: durationSec <= 2.0
                                            ? colorScheme.onPrimaryContainer
                                            : (durationSec <= 3.5
                                                ? colorScheme.onSecondaryContainer
                                                : colorScheme.onTertiaryContainer),
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
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.storefront_rounded, size: 12, color: colorScheme.primary),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  branch.isNotEmpty ? '$storeChain - $branch' : storeChain,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
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
                              color: isValid
                                  ? colorScheme.primaryContainer.withValues(alpha: 0.7)
                                  : colorScheme.errorContainer.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isValid
                                    ? colorScheme.primary.withValues(alpha: 0.3)
                                    : colorScheme.error.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isValid ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                  size: 12,
                                  color: isValid ? colorScheme.primary : colorScheme.error,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isValid ? (isAr ? 'مقبولة' : 'Valid') : (isAr ? 'مرفوضة' : 'Rejected'),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: isValid ? colorScheme.onPrimaryContainer : colorScheme.onErrorContainer,
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
                                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
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
                                Icon(Icons.person_rounded, size: 12, color: colorScheme.onSurfaceVariant),
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
                                Icon(Icons.phone_rounded, size: 12, color: colorScheme.onSurfaceVariant),
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
                            color: colorScheme.errorContainer.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colorScheme.error.withValues(alpha: 0.25)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(Icons.report_problem_rounded, size: 16, color: colorScheme.error),
                                  const SizedBox(width: 6),
                                  Text(
                                    strings.rejectionReasonLabel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onErrorContainer,
                                    ),
                                  ),
                                  if (isAdmin) ...[
                                    const Spacer(),
                                    // Connected Action Group for Quick Re-check and AI Brain
                                    M3ConnectedActionGroup(
                                      height: 30,
                                      borderRadius: 8,
                                      fontSize: 11,
                                      iconSize: 14,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      actions: [
                                        M3ConnectedActionItem(
                                          label: isRechecking ? strings.recheckingReceiptLoading : strings.recheckInvoiceAction,
                                          iconWidget: isRechecking
                                              ? SizedBox(
                                                  width: 12,
                                                  height: 12,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: colorScheme.error,
                                                  ),
                                                )
                                              : null,
                                          icon: isRechecking ? null : Icons.sync_rounded,
                                          isDestructive: true,
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
                                        ),
                                        M3ConnectedActionItem(
                                          label: isAr ? 'عقل الذكاء' : 'AI Brain',
                                          icon: Icons.psychology_rounded,
                                          isPrimary: true,
                                          onPressed: () => _openAiBrainCoPilotForInvoice(
                                            context: context,
                                            inv: inv,
                                            event: event,
                                            strings: strings,
                                            isAr: isAr,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              ...displayReasons.map(
                                (reason) => Padding(
                                  padding: const EdgeInsets.only(top: 2, bottom: 2),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(top: 5),
                                        child: Icon(Icons.fiber_manual_record_rounded, size: 6, color: colorScheme.error),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          reason,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: colorScheme.onErrorContainer,
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

                    // Action Buttons using M3ConnectedActionGroup
                    if (!isDesktopDetailPane) ...[
                      const SizedBox(width: 8),
                      M3ConnectedActionGroup(
                        height: isCardMobile ? 32 : 36,
                        borderRadius: 10,
                        fontSize: isCardMobile ? 11 : 12,
                        iconSize: isCardMobile ? 15 : 17,
                        actions: [
                          if (!isValid && isAdmin)
                            M3ConnectedActionItem(
                              label: strings.recheckInvoiceAction,
                              iconWidget: isRechecking
                                  ? SizedBox(
                                      width: 13,
                                      height: 13,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: colorScheme.error,
                                      ),
                                    )
                                  : null,
                              icon: isRechecking ? null : Icons.sync_rounded,
                              isDestructive: true,
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
                            ),
                          M3ConnectedActionItem(
                            label: itemsBtnLabel,
                            icon: isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                            isPrimary: isValid || !isAdmin,
                            onPressed: () => _toggleExpand(docId),
                          ),
                        ],
                      ),
                    ] else ...[
                      if (!isValid && isAdmin) ...[
                        const SizedBox(width: 8),
                        M3ConnectedActionGroup(
                          height: 36,
                          borderRadius: 10,
                          fontSize: 12,
                          iconSize: 16,
                          actions: [
                            M3ConnectedActionItem(
                              label: strings.recheckInvoiceAction,
                              iconWidget: isRechecking
                                  ? SizedBox(
                                      width: 13,
                                      height: 13,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: colorScheme.error,
                                      ),
                                    )
                                  : null,
                              icon: isRechecking ? null : Icons.sync_rounded,
                              isDestructive: true,
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
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_rounded, size: 15, color: colorScheme.onPrimaryContainer),
                            const SizedBox(width: 6),
                            Text(
                              '${products.length} ${strings.itemsCountLabel}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Material Design 3 Invoice Action Menu
                    const SizedBox(width: 8),
                    M3ActionMenu(
                      tooltip: isAr ? 'خيارات الفاتورة' : 'Invoice Options',
                      children: [
                        M3ActionMenu.header(
                          context: context,
                          title: isAr ? 'خيارات الفاتورة' : 'Invoice Options',
                          icon: Icons.receipt_long_rounded,
                        ),
                        M3ActionMenu.item(
                          context: context,
                          label: isAr ? 'عرض الفاتورة والصورة' : 'View Receipt & Details',
                          icon: Icons.visibility_outlined,
                          onPressed: () {
                            if (allReceiptUrls.isNotEmpty || (inv['storage_path']?.toString().isNotEmpty ?? false)) {
                              _showImagePreviewDialog(
                                context: context,
                                imageUrl: imageUrl,
                                imageUrls: allReceiptUrls,
                                receiptNumber: receiptNumber,
                                store: storeChain,
                                totalValue: totalValue,
                                date: formattedDate,
                                currencySymbol: activeCountry.currencySymbol,
                                colorScheme: colorScheme,
                                strings: strings,
                                docId: docId,
                                storagePath: inv['storage_path']?.toString(),
                                canDelete: isAdmin,
                              );
                            }
                          },
                        ),
                        M3ActionMenu.item(
                          context: context,
                          label: isAr ? 'تحميل صورة الفاتورة' : 'Download Receipt Image',
                          icon: Icons.download_rounded,
                          enabled: imageUrl.isNotEmpty,
                          onPressed: () {
                            if (imageUrl.isNotEmpty) {
                              launchUrl(Uri.parse(imageUrl), mode: LaunchMode.externalApplication);
                            }
                          },
                        ),
                        if (isAdmin) ...[
                          M3ActionMenu.item(
                            context: context,
                            label: isAr ? 'إعادة فحص OCR بالذكاء الاصطناعي' : 'Re-run AI OCR Scan',
                            icon: Icons.sync_rounded,
                            enabled: !isRechecking,
                            onPressed: () => _promptRecheckOptions(
                              context: context,
                              inv: inv,
                              event: event,
                              eventsMap: eventsMap,
                              strings: strings,
                              colorScheme: colorScheme,
                              activeCountry: activeCountry,
                              isAr: isAr,
                            ),
                          ),
                          M3ActionMenu.divider(),
                          M3ActionMenu.item(
                            context: context,
                            label: isAr ? 'إلغاء وحذف الفاتورة' : 'Cancel & Delete Invoice',
                            icon: Icons.delete_outline_rounded,
                            isDestructive: true,
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
                          ),
                        ],
                      ],
                    ),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 460;

        if (isCompact) {
          return Container(
            margin: const EdgeInsets.only(top: 14, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top row: Range summary & Page indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        isAr
                            ? 'عرض $startItem-$endItem من $totalItems'
                            : 'Showing $startItem-$endItem of $totalItems',
                        style: GoogleFonts.cairo(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        isAr
                            ? 'صفحة ${currentPage + 1} من $totalPages'
                            : 'Page ${currentPage + 1} of $totalPages',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Bottom row: Centered navigation action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                    const SizedBox(width: 8),
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
                    const SizedBox(width: 16),
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
                    const SizedBox(width: 8),
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
              Flexible(
                child: Text(
                  isAr
                      ? 'عرض $startItem-$endItem من إجمالي $totalItems'
                      : 'Showing $startItem-$endItem of $totalItems',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
      },
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
            Icon(Icons.check_circle_rounded, size: 16, color: colorScheme.onTertiaryFixedVariant),
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
                  dataRowMinHeight: 40,
                  dataRowMaxHeight: 46,
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
                              border: Border.all(
                                color: isPromo
                                    ? colorScheme.primary.withValues(alpha: 0.3)
                                    : colorScheme.outlineVariant.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isPromo) ...[
                                  Icon(Icons.stars_rounded, size: 12, color: colorScheme.primary),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  isPromo ? strings.includedInPromo : strings.generalItem,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isPromo ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
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
  }) {
    return 66.0;
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

class _BranchStat {
  final String branchName;
  final int invoicesCount;
  final double promoSales;
  final int extractedItems;
  final double percentage;

  const _BranchStat({
    required this.branchName,
    required this.invoicesCount,
    required this.promoSales,
    required this.extractedItems,
    required this.percentage,
  });
}
