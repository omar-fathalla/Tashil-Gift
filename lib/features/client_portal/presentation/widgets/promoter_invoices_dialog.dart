import 'package:al_mraay/core/config/ai_config.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../../../../core/services/firebase_service.dart';
import '../../../../core/services/ai_receipt_service.dart';
import '../../../../core/services/receipt_deduplication_helper.dart';
import '../../../../core/services/company_products_service.dart';
import '../../../../core/services/retail_chains_service.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/constants/country_currency_config.dart';
import '../../../../core/utils/arabic_numbers_utils.dart';
import '../../../../core/utils/canonical_branch_resolver.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/widgets/interactive_receipt_viewer_dialog.dart';
import '../../../../core/services/multi_campaign_receipt_evaluator.dart';
import '../../../admin/domain/event_model.dart';
import '../../../admin/domain/retail_chain_model.dart';
import '../../../games/presentation/choose_gift_screen.dart';
import '../../../games/presentation/spin_the_wheel_screen.dart';
import '../../../games/presentation/scratch_card_screen.dart';
import '../../../games/presentation/direct_gift_claim_screen.dart';
import '../../../../core/services/firebase_scope.dart';

enum PromoterDateFilter { today, custom, all }
enum PromoterStatusFilter { all, accepted, rejected }

/// Interactive Material Design 3 Dialog displaying the Invoices Log for Promoters
/// with branch filtering, persistent branch pinning, real-time sync, and detailed search.
class PromoterInvoicesDialog extends ConsumerStatefulWidget {
  final EventModel event;

  const PromoterInvoicesDialog({
    super.key,
    required this.event,
  });

  /// Static helper to display the dialog smoothly with M3 scale and fade transitions
  static Future<void> show(BuildContext context, EventModel event) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'PromoterInvoicesDialog',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) {
        return PromoterInvoicesDialog(event: event);
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: anim1,
            curve: Curves.easeOutCubic,
          ),
          child: FadeTransition(
            opacity: anim1,
            child: child,
          ),
        );
      },
    );
  }

  @override
  ConsumerState<PromoterInvoicesDialog> createState() => _PromoterInvoicesDialogState();
}

class _PromoterInvoicesDialogState extends ConsumerState<PromoterInvoicesDialog> {
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _selectedBranch; // null or empty string means 'All Branches'
  String? _pinnedBranch;
  PromoterDateFilter _dateFilter = PromoterDateFilter.today; // Defaults to Today per user request
  PromoterStatusFilter _statusFilter = PromoterStatusFilter.all;
  DateTime? _customSelectedDate;
  DateTimeRange? _customSelectedRange;
  final Set<String> _recheckingDocIds = <String>{};
  final Set<String> _expandedDocIds = <String>{};

  static const int _pageSize = 25;
  int _displayedCount = _pageSize;

  // Stale-While-Revalidate Persistent In-Memory Cache (0ms Instant Render)
  static final Map<String, List<Map<String, dynamic>>> _cachedCampaignInvoices = {};
  Stream<QuerySnapshot<Map<String, dynamic>>>? _invoicesStream;

  // Branch history from the listBranchReceipts callable (anonymous reps only).
  // The rep's anonymous uid changes with a new device / private tab / cleared
  // storage, so the uid-scoped stream alone can show 0 for a branch that has
  // receipts; these rows fill that gap (read-only projection).
  List<Map<String, dynamic>> _branchRemoteInvoices = const [];
  String? _branchRemoteKey;
  String? _branchRemoteLoadingKey;
  int _otherSessionCount = 0;
  Timer? _branchRefreshTimer;

  bool get _isAnonymousRep {
    final user = ref.read(firebaseAuthProvider).currentUser;
    return user != null && user.isAnonymous;
  }

  Future<void> _fetchBranchReceipts(String branchName, {bool force = false}) async {
    if (!_isAnonymousRep || widget.event.id.isEmpty || branchName.isEmpty) return;
    if (!force && (_branchRemoteKey == branchName || _branchRemoteLoadingKey == branchName)) return;
    _branchRemoteLoadingKey = branchName;
    try {
      final res = await scopedFunctions()
          .httpsCallable('listBranchReceipts',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 20)))
          .call<dynamic>({'campaignId': widget.event.id, 'branchName': branchName});
      final data = res.data;
      final list = <Map<String, dynamic>>[];
      if (data is Map && data['receipts'] is List) {
        for (final r in data['receipts'] as List) {
          if (r is! Map) continue;
          final m = Map<String, dynamic>.from(r.map((k, v) => MapEntry(k.toString(), v)));
          final ts = DateTime.tryParse((m['timestamp'] ?? '').toString());
          m['timestamp'] = ts?.toLocal();
          m['from_branch_history'] = true;
          list.add(m);
        }
      }
      if (!mounted || _selectedBranch != branchName) return;
      setState(() {
        _branchRemoteInvoices = list;
        _branchRemoteKey = branchName;
        _otherSessionCount = list.where((m) => m['same_session'] != true).length;
      });
    } catch (e) {
      debugPrint('listBranchReceipts unavailable: $e');
    } finally {
      if (_branchRemoteLoadingKey == branchName) _branchRemoteLoadingKey = null;
    }
  }

  void _ensureBranchHistory() {
    final b = _selectedBranch;
    if (b == null || b.isEmpty || !_isAnonymousRep) return;
    if (_branchRemoteKey == b || _branchRemoteLoadingKey == b) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchBranchReceipts(b);
    });
  }

  @override
  void initState() {
    super.initState();
    _loadPinnedBranch();
    _scrollController.addListener(_onScroll);
    _initStream();
    _branchRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      final b = _selectedBranch;
      if (mounted && b != null && b.isNotEmpty) _fetchBranchReceipts(b, force: true);
    });
  }

  @override
  void didUpdateWidget(covariant PromoterInvoicesDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.event.id != oldWidget.event.id ||
        widget.event.companySlug != oldWidget.event.companySlug) {
      _initStream(force: true);
    }
  }

  void _initStream({bool force = false}) {
    if (_invoicesStream != null && !force) return;
    final firestore = ref.read(firestoreProvider);
    Query<Map<String, dynamic>> query = firestore.collection('receipts_transactions');
    if (widget.event.id.isNotEmpty) {
      query = query.where('campaignId', isEqualTo: widget.event.id);
    } else if (widget.event.companySlug.isNotEmpty) {
      query = query.where('companySlug', isEqualTo: widget.event.companySlug.trim());
    }
    // Anonymous field reps may only read receipts they submitted
    // (firestore.rules: submittedByUid == request.auth.uid).
    final user = ref.read(firebaseAuthProvider).currentUser;
    if (user != null && user.isAnonymous) {
      query = query.where('submittedByUid', isEqualTo: user.uid);
    }
    _invoicesStream = query.snapshots();
  }

  @override
  void dispose() {
    _branchRefreshTimer?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      setState(() {
        _displayedCount += _pageSize;
      });
    }
  }

  static String _cleanBranchForComparison(String branch) {
    var s = branch.trim().toLowerCase().toEnglishDigits();
    s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    s = s.replaceAll(RegExp(r'[أإآ]'), 'ا');
    s = s.replaceAll('ة', 'ه').replaceAll('ى', 'ي');
    s = s.replaceAll(RegExp(r'\((القاهرة|الإسكندرية|الاسكندرية|الجيزة|الغربية|الدقهلية|المنوفية|الشرقية|البحيرة|كفر الشيخ|دمياط|بورسعيد|السويس|الإسماعيلية|الفيوم|بني سويف|المنيا|أسيوط|سوهاج|قنا|الأقصر|أسوان|مطروح|cairo|alexandria|giza)\)', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'[\(\)\[\]\{\}\-\_\,\.\:\/]'), ' ');
    s = s.replaceAll(RegExp(r'\b(فرع|سلسلة|store|branch|مفرع|pos|كود|محافظة|مدينة)\b', caseSensitive: false), ' ');
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

    // 3. Precision Area matching
    if (clean.contains('418') || cleanComp.contains('منتزه') || cleanComp.contains('montazah')) {
      for (final canonical in canonicalBranches) {
        final c = _cleanBranchForComparison(canonical);
        if (c.contains('منتزه') || c.contains('montazah') || canonical.contains('418')) return canonical;
      }
    }
    if (cleanComp.contains('سموح') || cleanComp.contains('smouha')) {
      for (final canonical in canonicalBranches) {
        if (_cleanBranchForComparison(canonical).contains('سموح')) return canonical;
      }
    }
    if (cleanComp.contains('سيوف') || cleanComp.contains('siouf') || cleanComp.contains('seyouf')) {
      for (final canonical in canonicalBranches) {
        if (_cleanBranchForComparison(canonical).contains('سيوف')) return canonical;
      }
    }
    if (cleanComp.contains('ميام') || cleanComp.contains('miami')) {
      for (final canonical in canonicalBranches) {
        if (_cleanBranchForComparison(canonical).contains('ميام')) return canonical;
      }
    }
    if (cleanComp.contains('عجم') || cleanComp.contains('agamy') || cleanComp.contains('agami')) {
      for (final canonical in canonicalBranches) {
        if (_cleanBranchForComparison(canonical).contains('عجم')) return canonical;
      }
    }
    if (cleanComp.contains('جناكليس') || cleanComp.contains('janaklis')) {
      for (final canonical in canonicalBranches) {
        if (_cleanBranchForComparison(canonical).contains('جناكليس')) return canonical;
      }
    }
    if (cleanComp.contains('لوران') || cleanComp.contains('loran')) {
      for (final canonical in canonicalBranches) {
        if (_cleanBranchForComparison(canonical).contains('لوران')) return canonical;
      }
    }
    if (cleanComp.contains('تجمع') || cleanComp.contains('tagmoo') || cleanComp.contains('park mall') || cleanComp.contains('fifth')) {
      for (final canonical in canonicalBranches) {
        final c = _cleanBranchForComparison(canonical);
        if (c.contains('تجمع') || c.contains('tagmoo')) return canonical;
      }
    }
    if (cleanComp.contains('اكتوبر') || cleanComp.contains('أكتوبر') || cleanComp.contains('october') || cleanComp.contains('سادس')) {
      for (final canonical in canonicalBranches) {
        final c = _cleanBranchForComparison(canonical);
        if (c.contains('اكتوبر') || c.contains('أكتوبر') || c.contains('october')) return canonical;
      }
    }
    if (cleanComp.contains('صلاح سالم') || cleanComp.contains('عبور') || cleanComp.contains('obour')) {
      for (final canonical in canonicalBranches) {
        final c = _cleanBranchForComparison(canonical);
        if (c.contains('صلاح سالم') || c.contains('عبور')) return canonical;
      }
    }
    if (cleanComp.contains('منصور') || cleanComp.contains('mansoura')) {
      for (final canonical in canonicalBranches) {
        if (_cleanBranchForComparison(canonical).contains('منصور')) return canonical;
      }
    }
    if (cleanComp.contains('شين') || cleanComp.contains('شبين') || cleanComp.contains('shebin')) {
      for (final canonical in canonicalBranches) {
        final c = _cleanBranchForComparison(canonical);
        if (c.contains('شبين') || c.contains('شين')) return canonical;
      }
    }
    if (cleanComp.contains('محله') || cleanComp.contains('mahalla')) {
      for (final canonical in canonicalBranches) {
        if (_cleanBranchForComparison(canonical).contains('محله')) return canonical;
      }
    }
    if (cleanComp.contains('جاردينيا') || cleanComp.contains('gardenia')) {
      for (final canonical in canonicalBranches) {
        if (_cleanBranchForComparison(canonical).contains('جاردينيا')) return canonical;
      }
    }

    // 4. Store Code Match (e.g. "Store: 418" / "418")
    final rawDigits = RegExp(r'\b\d+\b').allMatches(clean.toEnglishDigits()).map((m) => m.group(0)!).toSet();
    if (rawDigits.isNotEmpty) {
      for (final canonical in canonicalBranches) {
        final canonDigits = RegExp(r'\b\d+\b').allMatches(canonical.toEnglishDigits()).map((m) => m.group(0)!).toSet();
        if (rawDigits.intersection(canonDigits).isNotEmpty) {
          return canonical;
        }
      }
    }

    // Exact, then one longest contained name. Never the first shorter sibling
    // and never the first campaign branch when the text is still uncertain.
    return CanonicalBranchResolver.pickCampaignName(clean, canonicalBranches) ?? clean;
  }

  Future<void> _loadPinnedBranch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedForEvent = prefs.getString('pinned_branch_event_${widget.event.id}');
      final savedGlobal = prefs.getString('pinned_branch_global');
      final effective = (savedForEvent != null && savedForEvent.isNotEmpty)
          ? savedForEvent
          : savedGlobal;

      final canonicalBranches = widget.event.branchNames
          .map((b) => b.trim())
          .where((b) => b.isNotEmpty)
          .toList();

      if (mounted && effective != null && effective.isNotEmpty) {
        // Only accept pinned branch if it exists in canonical branches
        if (canonicalBranches.isEmpty || canonicalBranches.contains(effective)) {
          setState(() {
            _pinnedBranch = effective;
            _selectedBranch = effective;
          });
        } else {
          // Clean legacy/invalid pin
          await prefs.remove('pinned_branch_event_${widget.event.id}');
          await prefs.remove('pinned_branch_global');
        }
      }
    } catch (_) {}
  }

  Future<void> _togglePinBranch(String branchName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final strings = AppStrings.of(ref);

      if (_pinnedBranch == branchName) {
        // Unpin
        await prefs.remove('pinned_branch_event_${widget.event.id}');
        await prefs.remove('pinned_branch_global');
        if (mounted) {
          setState(() {
            _pinnedBranch = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(strings.branchUnpinnedSuccess),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // Pin
        await prefs.setString('pinned_branch_event_${widget.event.id}', branchName);
        await prefs.setString('pinned_branch_global', branchName);
        if (mounted) {
          setState(() {
            _pinnedBranch = branchName;
          });
          final colorScheme = Theme.of(context).colorScheme;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${strings.branchPinnedSuccess}: $branchName'),
              duration: const Duration(seconds: 2),
              backgroundColor: colorScheme.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (_) {}
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

  void _copyText(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool _matchesDateFilter(DateTime? dt) {
    if (_dateFilter == PromoterDateFilter.all || dt == null) return true;
    final now = DateTime.now();

    switch (_dateFilter) {
      case PromoterDateFilter.today:
        return dt.year == now.year && dt.month == now.month && dt.day == now.day;
      case PromoterDateFilter.custom:
        if (_customSelectedDate != null) {
          return dt.year == _customSelectedDate!.year &&
              dt.month == _customSelectedDate!.month &&
              dt.day == _customSelectedDate!.day;
        }
        if (_customSelectedRange != null) {
          final start = DateTime(
            _customSelectedRange!.start.year,
            _customSelectedRange!.start.month,
            _customSelectedRange!.start.day,
          );
          final end = DateTime(
            _customSelectedRange!.end.year,
            _customSelectedRange!.end.month,
            _customSelectedRange!.end.day,
            23,
            59,
            59,
          );
          return dt.isAfter(start.subtract(const Duration(seconds: 1))) &&
              dt.isBefore(end.add(const Duration(seconds: 1)));
        }
        return true;
      case PromoterDateFilter.all:
        return true;
    }
  }

  bool _matchesStatusFilter(bool isValid) {
    switch (_statusFilter) {
      case PromoterStatusFilter.all:
        return true;
      case PromoterStatusFilter.accepted:
        return isValid;
      case PromoterStatusFilter.rejected:
        return !isValid;
    }
  }

  DateTime? _parseDateTime(dynamic timestampVal, dynamic dateStrVal) {
    if (timestampVal is Timestamp) {
      return timestampVal.toDate();
    }
    if (timestampVal is DateTime) {
      return timestampVal;
    }
    if (dateStrVal != null && dateStrVal.toString().isNotEmpty) {
      try {
        final raw = dateStrVal.toString().trim();
        final parts = raw.split(RegExp(r'[/.-]'));
        if (parts.length == 3) {
          final p0 = int.tryParse(parts[0]) ?? 1;
          final p1 = int.tryParse(parts[1]) ?? 1;
          final p2 = int.tryParse(parts[2]) ?? 2026;
          if (p2 > 1000) {
            // d/m/y or y/m/d
            if (p0 > 1000) {
              return DateTime(p0, p1, p2);
            } else {
              return DateTime(p2, p1, p0);
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = AppStrings.of(ref);
    final isAr = strings.isAr;
    final activeCountry = ref.watch(activeCountryProvider);
    final currencySymbol = activeCountry.currencySymbol;
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final isMobile = screenWidth < 650;

    _initStream();
    _ensureBranchHistory();

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Dialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isMobile ? 20 : 28),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        insetPadding: EdgeInsets.symmetric(
          horizontal: isMobile ? 10 : 28,
          vertical: isMobile ? 12 : 24,
        ),
        child: Container(
          width: isMobile ? double.infinity : 980,
          height: isMobile ? screenHeight * 0.94 : screenHeight * 0.88,
          constraints: const BoxConstraints(maxWidth: 1060, maxHeight: 920),
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _invoicesStream,
            builder: (context, snapshot) {
              final cacheKey = widget.event.id.isNotEmpty ? widget.event.id : widget.event.companySlug;
              final cachedInvoices = _cachedCampaignInvoices[cacheKey];

              if (snapshot.hasError && (cachedInvoices == null || cachedInvoices.isEmpty)) {
                return _buildErrorState(colorScheme, strings, snapshot.error);
              }

              // 1. Strictly Canonical Branches from Event definition
              final List<String> canonicalBranches = widget.event.branchNames
                  .map((b) => b.trim())
                  .where((b) => b.isNotEmpty)
                  .toList();

              // 2. Filter transactions related to this campaign / company (both valid & rejected)
              final List<Map<String, dynamic>> campaignInvoices;

              if (snapshot.hasData && snapshot.data != null) {
                final allDocs = snapshot.data!.docs;
                final List<Map<String, dynamic>> parsedInvoices = [];
                final ownIds = allDocs.map((d) => d.id).toSet();
                final rows = <MapEntry<String, Map<String, dynamic>>>[
                  for (final doc in allDocs) MapEntry(doc.id, doc.data()),
                  for (final r in _branchRemoteInvoices)
                    if (!ownIds.contains((r['id'] ?? '').toString()))
                      MapEntry((r['id'] ?? '').toString(), r),
                ];
                for (final row in rows) {
                  final doc = (id: row.key);
                  final data = row.value;
                  final cId = (data['campaignId'] ?? data['event_id'] ?? data['eventId'] ?? '').toString().trim();
                  final cSlug = (data['companySlug'] ?? data['company_slug'] ?? '').toString().trim().toLowerCase();
                  final targetComp = (data['targetCompany'] ?? data['target_company'] ?? '').toString().trim().toLowerCase();

                  final eventSlug = widget.event.companySlug.trim().toLowerCase();
                  final eventTarget = widget.event.targetCompany.trim().toLowerCase();

                  final bool matchesCampaign = (widget.event.id.isNotEmpty && cId == widget.event.id) ||
                      (widget.event.id.isEmpty && eventSlug.isNotEmpty && cSlug == eventSlug) ||
                      (widget.event.id.isEmpty && eventTarget.isNotEmpty && targetComp.contains(eventTarget));

                  if (!matchesCampaign) continue;

                  final bool isExplicitlyValid = data['is_valid'] == true || data['status'] == 'accepted' || data['isValid'] == true;
                  final bool isExplicitlyRejected = data['is_valid'] == false || data['status'] == 'rejected' || data['isValid'] == false || ((data['unfulfilled_conditions'] as List?)?.isNotEmpty ?? false);
                  final bool isValid = isExplicitlyValid || (!isExplicitlyRejected && ((data['unfulfilled_conditions'] as List?)?.isEmpty ?? true));

                  final rawBranch = (data['branch_detected'] ?? data['branch_name'] ?? data['branch'] ?? '').toString().trim();
                  final identity = CanonicalBranchResolver.resolve(
                    branchIds: widget.event.branchIds,
                    branchNames: canonicalBranches,
                    branchId: (data['branch_id'] ?? '').toString(),
                    detectedName: rawBranch,
                    receiptNumber: (data['receipt_number'] ?? '').toString(),
                  );
                  final canonicalBranch = identity.certain && identity.name.trim().isNotEmpty
                      ? identity.name.trim()
                      : rawBranch;

                  parsedInvoices.add({
                    'docId': doc.id,
                    'id': doc.id,
                    ...data,
                    'is_computed_valid': isValid,
                    'canonical_branch': canonicalBranch,
                    'raw_branch': rawBranch,
                  });
                }
                campaignInvoices = parsedInvoices;
                _cachedCampaignInvoices[cacheKey] = parsedInvoices;
              } else if (cachedInvoices != null && cachedInvoices.isNotEmpty) {
                // Stale-While-Revalidate: render immediately in 0ms!
                campaignInvoices = cachedInvoices;
              } else {
                campaignInvoices = [];
              }

              final int totalCampaignInvoices = campaignInvoices.length;
              final int totalAcceptedInvoices = campaignInvoices.where((inv) => inv['is_computed_valid'] == true).length;
              final int totalRejectedInvoices = campaignInvoices.where((inv) => inv['is_computed_valid'] == false).length;

              // 3. Compute Invoice Counts per Canonical Branch
              final Map<String, int> branchInvoiceCounts = {};
              for (final b in canonicalBranches) {
                branchInvoiceCounts[b] = 0;
              }
              for (final inv in campaignInvoices) {
                if (_matchesStatusFilter(inv['is_computed_valid'] == true)) {
                  final b = inv['canonical_branch'] as String;
                  if (branchInvoiceCounts.containsKey(b)) {
                    branchInvoiceCounts[b] = (branchInvoiceCounts[b] ?? 0) + 1;
                  }
                }
              }

              // 4. Apply Search & Filters
              final searchQuery = _searchController.text.trim().toLowerCase().toEnglishDigits();

              final filteredInvoices = campaignInvoices.where((inv) {
                final bool isValid = inv['is_computed_valid'] == true;

                // 1. Status Filter
                if (!_matchesStatusFilter(isValid)) return false;

                // 2. Strict Branch Filter (Exact Canonical Match)
                final canonicalBranch = (inv['canonical_branch'] ?? '').toString();
                if (_selectedBranch != null && _selectedBranch!.isNotEmpty) {
                  if (canonicalBranch != _selectedBranch) {
                    return false;
                  }
                }

                // 3. Date Filter
                final dt = _parseDateTime(inv['timestamp'], inv['receipt_date']);
                if (!_matchesDateFilter(dt)) {
                  return false;
                }

                // 4. Search Query Filter
                if (searchQuery.isNotEmpty) {
                  final rawBranch = (inv['raw_branch'] ?? '').toString();
                  final storeChain = (inv['store_chain_detected'] ?? inv['retail_chain_name'] ?? '').toString().trim();
                  final receiptNumber = (inv['receipt_number'] ?? '').toString().trim().toLowerCase();
                  final customerPhone = (inv['customerPhone'] ?? inv['customer_phone'] ?? '').toString().trim();
                  final customerName = (inv['customerName'] ?? inv['customer_name'] ?? '').toString().trim().toLowerCase();
                  final receiptDate = (inv['receipt_date'] ?? '').toString().trim().toLowerCase();

                  final matchesReceipt = receiptNumber.contains(searchQuery);
                  final matchesPhone = customerPhone.toEnglishDigits().contains(searchQuery);
                  final matchesName = customerName.contains(searchQuery);
                  final matchesDate = receiptDate.contains(searchQuery);
                  final matchesBranch = canonicalBranch.toLowerCase().contains(searchQuery) ||
                      rawBranch.toLowerCase().contains(searchQuery);
                  final matchesStore = storeChain.toLowerCase().contains(searchQuery);

                  if (!matchesReceipt &&
                      !matchesPhone &&
                      !matchesName &&
                      !matchesDate &&
                      !matchesBranch &&
                      !matchesStore) {
                    return false;
                  }
                }

                return true;
              }).toList();

              // Sort by timestamp descending (newest first)
              filteredInvoices.sort((a, b) {
                final dtA = _parseDateTime(a['timestamp'], a['receipt_date']) ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                final dtB = _parseDateTime(b['timestamp'], b['receipt_date']) ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                return dtB.compareTo(dtA);
              });

              // Compute Summary Stats
              double totalSales = 0.0;
              for (final inv in filteredInvoices) {
                final val = (inv['target_company_total'] ?? inv['total_value'] as num?)?.toDouble() ?? 0.0;
                totalSales += val;
              }

              return Column(
                children: [
                  // 1. Dialog Header
                  _buildHeader(
                    context: context,
                    colorScheme: colorScheme,
                    strings: strings,
                    isMobile: isMobile,
                    filteredCount: filteredInvoices.length,
                    totalAccepted: totalAcceptedInvoices,
                    totalRejected: totalRejectedInvoices,
                    totalSales: totalSales,
                    currencySymbol: currencySymbol,
                    isAr: isAr,
                  ),

                  const Divider(height: 1, thickness: 1),

                  // 2. Filter & Search Controls (Branches Bar + Date Chips + Status Chips + Search Box)
                  _buildFilterControls(
                    context: context,
                    colorScheme: colorScheme,
                    strings: strings,
                    isMobile: isMobile,
                    availableBranches: canonicalBranches,
                    branchCounts: branchInvoiceCounts,
                    totalCount: totalCampaignInvoices,
                    acceptedCount: totalAcceptedInvoices,
                    rejectedCount: totalRejectedInvoices,
                    isAr: isAr,
                  ),

                  const Divider(height: 1, thickness: 1),

                  if (_otherSessionCount > 0 &&
                      _branchRemoteKey != null &&
                      _branchRemoteKey == _selectedBranch)
                    _buildOtherSessionsNote(colorScheme, isAr),

                  // 3. Invoices List View
                  Expanded(
                    child: snapshot.connectionState == ConnectionState.waiting && campaignInvoices.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : filteredInvoices.isEmpty
                            ? _buildEmptyState(colorScheme, strings, isMobile)
                            : _buildInvoicesList(
                                context: context,
                                colorScheme: colorScheme,
                                strings: strings,
                                isMobile: isMobile,
                                invoices: filteredInvoices,
                                currencySymbol: currencySymbol,
                                activeCountry: activeCountry,
                                isAr: isAr,
                              ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isMobile,
    required int filteredCount,
    required int totalAccepted,
    required int totalRejected,
    required double totalSales,
    required String currencySymbol,
    required bool isAr,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 22,
        vertical: isMobile ? 12 : 16,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(isMobile ? 20 : 28),
        ),
      ),
      child: Row(
        children: [
          // Icon Container
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: themeGradient(colorScheme),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),

          // Titles & Subtitles
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        strings.promoterInvoicesDialogTitle,
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: isMobile ? 15 : 18,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_pinnedBranch != null && _pinnedBranch!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.push_pin_rounded, size: 12, color: colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              _pinnedBranch!,
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
                if (ref.read(firebaseAuthProvider).currentUser?.isAnonymous ?? false)
                  Text(
                    Directionality.of(context) == TextDirection.rtl
                        ? 'تظهر فواتيرك المرفوعة من هذا الجهاز فقط (السجل محفوظ على هذا الجهاز)'
                        : 'Showing receipts uploaded from this device (history saved on this device)',
                    key: const Key('promoter_invoices_device_note'),
                    style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  '${widget.event.eventName} — ${widget.event.targetCompany}',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 11.5 : 12.5,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Live Quick Stats (Count & Sales Pill)
          if (!isMobile) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tag_rounded, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    '$filteredCount فاتورة',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  if (totalRejected > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cancel_rounded, size: 12, color: colorScheme.onErrorContainer),
                          const SizedBox(width: 4),
                          Text(
                            isAr ? '$totalRejected مرفوضة' : '$totalRejected Rejected',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: 12),
                  Container(width: 1, height: 16, color: colorScheme.outlineVariant),
                  const SizedBox(width: 12),
                  Icon(Icons.monetization_on_rounded, size: 16, color: colorScheme.onTertiaryFixedVariant),
                  const SizedBox(width: 4),
                  Text(
                    '${totalSales.toStringAsFixed(totalSales == totalSales.roundToDouble() ? 0 : 2)} $currencySymbol',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: colorScheme.onTertiaryFixedVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '#$filteredCount',
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                  if (totalRejected > 0) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.cancel_rounded, size: 10, color: colorScheme.onErrorContainer),
                    const SizedBox(width: 2),
                    Text(
                      '$totalRejected',
                      style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.onErrorContainer),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
          ],

          // Close Dialog Button
          IconButton.filledTonal(
            icon: const Icon(Icons.close_rounded, size: 20),
            tooltip: strings.close,
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(8),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  LinearGradient themeGradient(ColorScheme colorScheme) {
    return LinearGradient(
      colors: [colorScheme.primary, colorScheme.tertiary],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  Widget _buildFilterControls({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isMobile,
    required List<String> availableBranches,
    required Map<String, int> branchCounts,
    required int totalCount,
    required int acceptedCount,
    required int rejectedCount,
    required bool isAr,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 18,
        vertical: isMobile ? 10 : 12,
      ),
      color: colorScheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Branch Selector & Pin Action Bar
          Row(
            children: [
              Icon(Icons.storefront_rounded, size: 18, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                strings.branchField,
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),

              // Pin Button for active branch
              if (_selectedBranch != null && _selectedBranch!.isNotEmpty) ...[
                Tooltip(
                  message: _pinnedBranch == _selectedBranch
                      ? strings.unpinBranchTooltip
                      : strings.pinMyBranchTooltip,
                  child: InkWell(
                    onTap: () => _togglePinBranch(_selectedBranch!),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _pinnedBranch == _selectedBranch
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _pinnedBranch == _selectedBranch
                              ? colorScheme.primary
                              : colorScheme.outlineVariant,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _pinnedBranch == _selectedBranch
                                ? Icons.push_pin_rounded
                                : Icons.push_pin_outlined,
                            size: 13,
                            color: _pinnedBranch == _selectedBranch
                                ? colorScheme.onPrimary
                                : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _pinnedBranch == _selectedBranch
                                ? strings.pinnedBranchBadge
                                : strings.pinMyBranchTooltip,
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _pinnedBranch == _selectedBranch
                                  ? colorScheme.onPrimary
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // Horizontal Branches Chips Bar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // "All Branches" Chip with total count
                ChoiceChip(
                  label: Text('${strings.promoterAllBranchesOption} ($totalCount)'),
                  labelStyle: GoogleFonts.cairo(
                    fontWeight: _selectedBranch == null || _selectedBranch!.isEmpty
                        ? FontWeight.bold
                        : FontWeight.w500,
                    fontSize: 12,
                  ),
                  selected: _selectedBranch == null || _selectedBranch!.isEmpty,
                  onSelected: (selected) {
                    setState(() {
                      _selectedBranch = null;
                      _displayedCount = _pageSize;
                    });
                  },
                  showCheckmark: true,
                  avatar: const Icon(Icons.all_inclusive_rounded, size: 16),
                ),
                const SizedBox(width: 8),

                // Individual Canonical Branch Chips with count
                ...availableBranches.map((branchName) {
                  final isSelected = _selectedBranch == branchName;
                  final isPinned = _pinnedBranch == branchName;
                  final count = branchCounts[branchName] ?? 0;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isPinned) ...[
                            Icon(
                              Icons.push_pin_rounded,
                              size: 12,
                              color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text('$branchName ($count)'),
                        ],
                      ),
                      labelStyle: GoogleFonts.cairo(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 12,
                      ),
                      selected: isSelected,
                      selectedColor: colorScheme.primaryContainer,
                      onSelected: (selected) {
                        setState(() {
                          _selectedBranch = selected ? branchName : null;
                          _displayedCount = _pageSize;
                        });
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 2. Search Box
          _buildSearchField(colorScheme, strings),
          const SizedBox(height: 10),

          // 3. Filter Row: Date Chips + Status Chips
          if (isMobile) ...[
            _buildDateFilterChips(context, colorScheme, strings, isAr),
            const SizedBox(height: 8),
            _buildStatusFilterChips(colorScheme, strings, acceptedCount, rejectedCount, isAr),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: _buildDateFilterChips(context, colorScheme, strings, isAr),
                ),
                const SizedBox(width: 14),
                _buildStatusFilterChips(colorScheme, strings, acceptedCount, rejectedCount, isAr),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchField(ColorScheme colorScheme, AppStrings strings) {
    return TextField(
      controller: _searchController,
      onChanged: (_) {
        setState(() {
          _displayedCount = _pageSize;
        });
      },
      decoration: InputDecoration(
        hintText: strings.searchInvoicesPlaceholder,
        hintStyle: GoogleFonts.cairo(fontSize: 12.5, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _displayedCount = _pageSize;
                  });
                },
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildDateFilterChips(
    BuildContext context,
    ColorScheme colorScheme,
    AppStrings strings,
    bool isAr,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Default "Today" Chip
          _buildDateChip(
            label: isAr ? 'اليوم' : 'Today',
            filter: PromoterDateFilter.today,
            colorScheme: colorScheme,
            icon: Icons.today_rounded,
          ),
          const SizedBox(width: 6),

          // 2. Interactive Animated Date Picker Chip (Single Day or Range)
          _buildCustomDateChip(
            context: context,
            colorScheme: colorScheme,
            strings: strings,
            isAr: isAr,
          ),
          const SizedBox(width: 6),

          // 3. "All" Dates Chip
          _buildDateChip(
            label: isAr ? 'الكل' : 'All',
            filter: PromoterDateFilter.all,
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }

  Widget _buildDateChip({
    required String label,
    required PromoterDateFilter filter,
    required ColorScheme colorScheme,
    IconData? icon,
  }) {
    final isSelected = _dateFilter == filter;
    return FilterChip(
      avatar: icon != null
          ? Icon(
              icon,
              size: 14,
              color: isSelected ? colorScheme.onPrimary : colorScheme.primary,
            )
          : null,
      label: Text(label),
      labelStyle: GoogleFonts.cairo(
        fontSize: 11.5,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
      ),
      selected: isSelected,
      selectedColor: colorScheme.primary,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      visualDensity: VisualDensity.compact,
      onSelected: (selected) {
        setState(() {
          _dateFilter = filter;
          _customSelectedDate = null;
          _customSelectedRange = null;
          _displayedCount = _pageSize;
        });
      },
    );
  }

  Widget _buildCustomDateChip({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
  }) {
    final isCustomActive = _dateFilter == PromoterDateFilter.custom;
    String customLabel;
    if (_customSelectedDate != null) {
      customLabel = DateFormat('dd/MM/yyyy').format(_customSelectedDate!);
    } else if (_customSelectedRange != null) {
      final s = DateFormat('dd/MM').format(_customSelectedRange!.start);
      final e = DateFormat('dd/MM').format(_customSelectedRange!.end);
      customLabel = '$s - $e';
    } else {
      customLabel = isAr ? 'يوم / فترة...' : 'Date / Range...';
    }

    return FilterChip(
      avatar: Icon(
        Icons.calendar_month_rounded,
        size: 15,
        color: isCustomActive ? colorScheme.onPrimary : colorScheme.primary,
      ),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(customLabel),
          if (isCustomActive && (_customSelectedDate != null || _customSelectedRange != null)) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: () {
                setState(() {
                  _dateFilter = PromoterDateFilter.today;
                  _customSelectedDate = null;
                  _customSelectedRange = null;
                  _displayedCount = _pageSize;
                });
              },
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: isCustomActive ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      labelStyle: GoogleFonts.cairo(
        fontSize: 11.5,
        fontWeight: isCustomActive ? FontWeight.bold : FontWeight.w500,
        color: isCustomActive ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
      ),
      selected: isCustomActive,
      selectedColor: colorScheme.primary,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      visualDensity: VisualDensity.compact,
      onSelected: (_) {
        _showAnimatedDateSelectionSheet(
          context: context,
          colorScheme: colorScheme,
          strings: strings,
          isAr: isAr,
        );
      },
    );
  }

  void _showAnimatedDateSelectionSheet({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.date_range_rounded, color: colorScheme.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.pickDateOrRangeTitle,
                            style: GoogleFonts.cairo(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            isAr
                                ? 'حدد يوم محدد أو اختر فترة زمنية لعرض فواتيرها'
                                : 'Select a single day or date range to filter invoices',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Option 1: Single Day Card
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      Navigator.pop(sheetCtx);
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _customSelectedDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                        builder: (ctx, child) {
                          return Theme(
                            data: Theme.of(ctx).copyWith(
                              colorScheme: colorScheme,
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setState(() {
                          _dateFilter = PromoterDateFilter.custom;
                          _customSelectedDate = picked;
                          _customSelectedRange = null;
                          _displayedCount = _pageSize;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: (_dateFilter == PromoterDateFilter.custom && _customSelectedDate != null)
                              ? colorScheme.primary
                              : colorScheme.outlineVariant.withValues(alpha: 0.6),
                          width: (_dateFilter == PromoterDateFilter.custom && _customSelectedDate != null) ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.calendar_today_rounded, color: colorScheme.primary, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  strings.singleDayOption,
                                  style: GoogleFonts.cairo(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  strings.singleDaySubtitle,
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: colorScheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Option 2: Date Range Card (Animated Material Range Picker)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      Navigator.pop(sheetCtx);
                      final pickedRange = await showDateRangePicker(
                        context: context,
                        initialDateRange: _customSelectedRange ??
                            DateTimeRange(
                              start: DateTime.now().subtract(const Duration(days: 7)),
                              end: DateTime.now(),
                            ),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                        builder: (ctx, child) {
                          return Theme(
                            data: Theme.of(ctx).copyWith(
                              colorScheme: colorScheme,
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (pickedRange != null) {
                        setState(() {
                          _dateFilter = PromoterDateFilter.custom;
                          _customSelectedRange = pickedRange;
                          _customSelectedDate = null;
                          _displayedCount = _pageSize;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: (_dateFilter == PromoterDateFilter.custom && _customSelectedRange != null)
                              ? colorScheme.primary
                              : colorScheme.outlineVariant.withValues(alpha: 0.6),
                          width: (_dateFilter == PromoterDateFilter.custom && _customSelectedRange != null) ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorScheme.tertiaryContainer.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.date_range_rounded, color: colorScheme.tertiary, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  strings.dateRangeOption,
                                  style: GoogleFonts.cairo(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  strings.dateRangeSubtitle,
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: colorScheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusFilterChips(
    ColorScheme colorScheme,
    AppStrings strings,
    int acceptedCount,
    int rejectedCount,
    bool isAr,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStatusChip(
            label: strings.all,
            filter: PromoterStatusFilter.all,
            count: null,
            colorScheme: colorScheme,
          ),
          const SizedBox(width: 6),
          _buildStatusChip(
            label: isAr ? 'المعتمدة' : 'Accepted',
            filter: PromoterStatusFilter.accepted,
            count: acceptedCount,
            colorScheme: colorScheme,
            activeColor: colorScheme.onTertiaryFixedVariant,
            icon: Icons.check_circle_rounded,
          ),
          const SizedBox(width: 6),
          _buildStatusChip(
            label: isAr ? 'المرفوضة' : 'Rejected',
            filter: PromoterStatusFilter.rejected,
            count: rejectedCount,
            colorScheme: colorScheme,
            activeColor: colorScheme.onErrorContainer,
            icon: Icons.cancel_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip({
    required String label,
    required PromoterStatusFilter filter,
    required int? count,
    required ColorScheme colorScheme,
    Color? activeColor,
    IconData? icon,
  }) {
    final isSelected = _statusFilter == filter;
    final primaryColor = activeColor ?? colorScheme.primary;

    return FilterChip(
      avatar: icon != null
          ? Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : primaryColor,
            )
          : null,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count != null) ...[
            const SizedBox(width: 4),
            Text('($count)'),
          ],
        ],
      ),
      labelStyle: GoogleFonts.cairo(
        fontSize: 11.5,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? Colors.white : colorScheme.onSurfaceVariant,
      ),
      selected: isSelected,
      selectedColor: primaryColor,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      visualDensity: VisualDensity.compact,
      onSelected: (selected) {
        setState(() {
          _statusFilter = filter;
          _displayedCount = _pageSize;
        });
      },
    );
  }

  Widget _buildInvoicesList({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isMobile,
    required List<Map<String, dynamic>> invoices,
    required String currencySymbol,
    required CountryCurrency activeCountry,
    required bool isAr,
  }) {
    final visibleInvoices = invoices.take(_displayedCount).toList();

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 18,
        vertical: 12,
      ),
      itemCount: visibleInvoices.length + (visibleInvoices.length < invoices.length ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == visibleInvoices.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          );
        }

        final data = visibleInvoices[index];
        final docId = (data['docId'] ?? data['id'] ?? 'inv-$index').toString();
        final isExpanded = _expandedDocIds.contains(docId);

        return _buildInvoiceCard(
          context: context,
          colorScheme: colorScheme,
          strings: strings,
          isMobile: isMobile,
          docId: docId,
          data: data,
          isExpanded: isExpanded,
          currencySymbol: currencySymbol,
          activeCountry: activeCountry,
          isAr: isAr,
        );
      },
    );
  }

  Widget _buildInvoiceCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isMobile,
    required String docId,
    required Map<String, dynamic> data,
    required bool isExpanded,
    required String currencySymbol,
    required CountryCurrency activeCountry,
    required bool isAr,
  }) {
    final receiptNumber = (data['receipt_number'] ?? 'INV-N/A').toString().trim();
    final totalVal = (data['target_company_total'] ?? data['total_value'] as num?)?.toDouble() ?? 0.0;
    final invoiceVal = data['total_value'] is num ? (data['total_value'] as num).toDouble() : totalVal;
    final showInvoiceNet = data['target_company_total'] is num && (invoiceVal - totalVal).abs() > 0.49;
    final storeChain = (data['store_chain_detected'] ?? data['retail_chain_name'] ?? '').toString().trim();
    final branch = (data['canonical_branch'] ?? data['branch_detected'] ?? data['branch_name'] ?? '').toString().trim();
    final customerPhone = (data['customerPhone'] ?? data['customer_phone'] ?? '').toString().trim();
    final customerName = (data['customerName'] ?? data['customer_name'] ?? '').toString().trim();
    final receiptDate = (data['receipt_date'] ?? '').toString().trim();
    final imageUrl = (data['image_url'] ?? '').toString().trim();
    final List<String> allReceiptUrls = [];
    if (data['image_urls'] is List && (data['image_urls'] as List).isNotEmpty) {
      allReceiptUrls.addAll((data['image_urls'] as List).map((e) => e.toString()).where((e) => e.isNotEmpty));
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
    final prizeWon = (data['prize_won'] ?? '').toString().trim();
    final gamePlayed = data['game_played'] == true;
    final dt = _parseDateTime(data['timestamp'], receiptDate);
    final formattedTime = dt != null ? DateFormat('yyyy-MM-dd hh:mm a').format(dt) : receiptDate;

    final bool isExplicitlyValid = data['is_valid'] == true || data['status'] == 'accepted' || data['isValid'] == true;
    final bool isExplicitlyRejected = data['is_valid'] == false || data['status'] == 'rejected' || data['isValid'] == false || ((data['unfulfilled_conditions'] as List?)?.isNotEmpty ?? false);
    final bool isValid = isExplicitlyValid || (!isExplicitlyRejected && ((data['unfulfilled_conditions'] as List?)?.isEmpty ?? true));
    final rejectionReason = (data['rejection_reason'] ?? '').toString().trim();

    final List<String> unfulfilledConditions = [];
    if (data['unfulfilled_conditions'] is List) {
      for (final item in (data['unfulfilled_conditions'] as List)) {
        if (item != null && item.toString().trim().isNotEmpty) {
          unfulfilledConditions.add(item.toString().trim());
        }
      }
    }
    if (unfulfilledConditions.isEmpty && rejectionReason.isNotEmpty) {
      unfulfilledConditions.addAll(rejectionReason.split(' • ').map((s) => s.trim()).where((s) => s.isNotEmpty));
    }
    if (unfulfilledConditions.isEmpty && !isValid) {
      unfulfilledConditions.add(isAr ? 'الفاتورة غير مطابقة لشروط الحملة أو تفتقر للمنتجات المؤهلة.' : 'Receipt does not meet promotion conditions.');
    }

    final extractedProducts = (data['extracted_products'] as List<dynamic>?) ?? [];
    final aiMessage = (data['aiMessage'] ?? '').toString().trim();
    final chances = (data['chances_earned'] as num?)?.toInt() ?? 1;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isValid
              ? colorScheme.outlineVariant.withValues(alpha: 0.6)
              : colorScheme.errorContainer,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => _toggleExpand(docId),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card Top Row: Receipt Number & Amount
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Receipt Icon + Number
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isValid
                          ? colorScheme.primaryContainer.withValues(alpha: 0.6)
                          : colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isValid ? Icons.receipt_rounded : Icons.receipt_long_rounded,
                      size: 20,
                      color: isValid ? colorScheme.primary : colorScheme.onErrorContainer,
                    ),
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
                                receiptNumber,
                                style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold,
                                  fontSize: isMobile ? 13.5 : 15,
                                  color: colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => _copyText(receiptNumber, '${strings.receiptNumberCopied}: $receiptNumber'),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.copy_rounded,
                                  size: 14,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (formattedTime.isNotEmpty) ...[
                          Text(
                            formattedTime,
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Total Amount Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isValid ? colorScheme.tertiaryContainer : colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isValid ? colorScheme.tertiaryFixedDim : colorScheme.errorContainer),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${totalVal.toStringAsFixed(totalVal == totalVal.roundToDouble() ? 0 : 2)} $currencySymbol',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            fontSize: isMobile ? 12.5 : 14,
                            color: isValid ? colorScheme.onTertiaryContainer : colorScheme.onErrorContainer,
                          ),
                        ),
                        if (showInvoiceNet)
                          Text(
                            isAr ? 'صافي الفاتورة $invoiceVal' : 'Invoice net $invoiceVal',
                            style: GoogleFonts.cairo(fontSize: 9, color: colorScheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Badges Row: Store / Branch / AI status / Game status
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Branch & Store Badge
                  if (branch.isNotEmpty || storeChain.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.storefront_rounded, size: 13, color: colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            storeChain.isNotEmpty
                                ? (branch.isNotEmpty ? '$storeChain - $branch' : storeChain)
                                : branch,
                            style: GoogleFonts.cairo(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // AI Acceptance/Rejection Chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isValid ? colorScheme.tertiaryContainer : colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isValid ? colorScheme.tertiaryFixedDim : colorScheme.errorContainer),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isValid ? Icons.verified_rounded : Icons.cancel_rounded,
                          size: 13,
                          color: isValid ? colorScheme.onTertiaryFixedVariant : colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isValid ? 'معتمدة ومقبولة' : 'مرفوضة وغير مقبولة',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isValid ? colorScheme.onTertiaryFixedVariant : colorScheme.onErrorContainer,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Customer Phone & Name
                  if (customerPhone.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.phone_rounded, size: 12, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            customerPhone,
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (customerName.isNotEmpty) ...[
                            Text(
                              ' ($customerName)',
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  // Chances / Prizes
                  if (prizeWon.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.primaryFixedDim),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.card_giftcard_rounded, size: 13, color: colorScheme.onSecondaryContainer),
                          const SizedBox(width: 4),
                          Text(
                            'الجائزة: $prizeWon',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (gamePlayed) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'تم السحب ($chances فرص)',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryFixedVariant,
                        ),
                      ),
                    ),
                  ],
                  if ((data['voucher_serials'] as List?)?.isNotEmpty ?? false) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.primaryFixedDim),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.confirmation_number_rounded, size: 12, color: colorScheme.onSecondaryContainer),
                          const SizedBox(width: 4),
                          Text(
                            isAr
                                ? 'كروت الفواتشر: ${(data['voucher_serials'] as List).join(" | ")}'
                                : 'Voucher Cards: ${(data['voucher_serials'] as List).join(" | ")}',
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

              // If Rejected: Prominent Rejection Alert Box with Reasons and Recheck Button
              if (!isValid) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.errorContainer),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.report_problem_rounded, size: 18, color: colorScheme.onErrorContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isAr ? 'سبب الرفض وعدم الاستحقاق:' : 'Rejection Reason:',
                              style: GoogleFonts.cairo(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                          _buildRecheckButton(
                            docId: docId,
                            data: data,
                            colorScheme: colorScheme,
                            strings: strings,
                            activeCountry: activeCountry,
                            isAr: isAr,
                            isDense: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...unfulfilledConditions.map(
                        (reason) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Icon(Icons.circle, size: 5, color: colorScheme.onErrorContainer),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  reason,
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onErrorContainer,
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

              // Expandable Itemized Products & Image Details
              if (isExpanded) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 10),

                if (aiMessage.isNotEmpty) ...[
                  Text(
                    'ملاحظة الذكاء الاصطناعي: $aiMessage',
                    style: GoogleFonts.cairo(
                      fontSize: 11.5,
                      color: colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Extracted Products List
                if (extractedProducts.isNotEmpty) ...[
                  Text(
                    'المنتجات المكتشفة في الفاتورة (${extractedProducts.length}):',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...extractedProducts.map((p) {
                    final pMap = p is Map ? Map<String, dynamic>.from(p) : <String, dynamic>{};
                    final name = (pMap['name'] ?? pMap['product_name'] ?? 'منتج').toString();
                    final qty = (pMap['quantity'] as num?)?.toInt() ?? 1;
                    final price = (pMap['price'] as num?)?.toDouble() ?? 0.0;
                    final lineLabel = ExtractedProductItem.lineTotalLabel(pMap, arabic: isAr);
                    final isTarget = pMap['is_target_company'] != false;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isTarget ? colorScheme.primaryContainer.withValues(alpha: 0.35) : colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isTarget ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            size: 14,
                            color: isTarget ? colorScheme.tertiary : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              style: GoogleFonts.cairo(
                                fontSize: 12,
                                fontWeight: isTarget ? FontWeight.bold : FontWeight.normal,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                          Text(
                            'الكمية: $qty | السعر: ${price.toStringAsFixed(price == price.roundToDouble() ? 0 : 2)} | السطر ${lineLabel.primary}${lineLabel.grossNote == null ? '' : ' (${lineLabel.grossNote})'} $currencySymbol',
                            style: GoogleFonts.cairo(
                              fontSize: 11.5,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],

                // Action Buttons Row (Image Zoom)
                if (imageUrl.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      onPressed: () => _showReceiptImageZoomDialog(
                        context,
                        allReceiptUrls.isNotEmpty ? allReceiptUrls.first : imageUrl,
                        receiptNumber,
                        imageUrls: allReceiptUrls.length > 1 ? allReceiptUrls : null,
                      ),
                      icon: const Icon(Icons.zoom_in_rounded, size: 16),
                      label: Text(strings.receiptZoomImage, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecheckButton({
    required String docId,
    required Map<String, dynamic> data,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required CountryCurrency activeCountry,
    required bool isAr,
    required bool isDense,
  }) {
    if (!ref.watch(isAdminProvider)) {
      return const SizedBox.shrink();
    }
    final isRechecking = _recheckingDocIds.contains(docId);

    if (isRechecking) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.primaryFixedDim),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.secondary),
            ),
            const SizedBox(width: 6),
            Text(
              isAr ? 'جاري الفحص...' : 'Rechecking...',
              style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onSecondaryContainer),
            ),
          ],
        ),
      );
    }

    if (isDense) {
      return FilledButton.tonalIcon(
        onPressed: () => _promptRecheckOptions(
          context: context,
          inv: data,
          event: widget.event,
          strings: strings,
          colorScheme: colorScheme,
          activeCountry: activeCountry,
          isAr: isAr,
        ),
        icon: const Icon(Icons.refresh_rounded, size: 13),
        label: Text(
          strings.recheckInvoiceAction,
          style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.errorContainer,
          foregroundColor: colorScheme.onErrorContainer,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }

    return FilledButton.icon(
      onPressed: () => _promptRecheckOptions(
        context: context,
        inv: data,
        event: widget.event,
        strings: strings,
        colorScheme: colorScheme,
        activeCountry: activeCountry,
        isAr: isAr,
      ),
      icon: const Icon(Icons.sync_rounded, size: 16),
      label: Text(
        strings.recheckInvoiceAction,
        style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _promptRecheckOptions({
    required BuildContext context,
    required Map<String, dynamic> inv,
    required EventModel? event,
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
                            strings.quickRecheckSubtitle,
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

            // Option 2: Full AI Re-Scan (AiConfig.fastTierModel)
            InkWell(
              onTap: hasImage
                  ? () {
                      Navigator.pop(dialogCtx);
                      _executeRecheck(
                        inv: inv,
                        event: event,
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
                                    AiConfig.fastTierModel,
                                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              hasImage
                                  ? strings.fullAiRecheckSubtitle
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
    required bool isFullAiScan,
    required AppStrings strings,
    required ColorScheme colorScheme,
    required CountryCurrency activeCountry,
    required bool isAr,
  }) async {
    final docId = (inv['docId'] ?? inv['id']) as String;
    setState(() => _recheckingDocIds.add(docId));

    try {
      EventModel? activeEvent = event ?? widget.event;
      final firestore = ref.read(firestoreProvider);

      final campaignId = (inv['campaignId'] ?? inv['event_id'] ?? activeEvent.id).toString();
      if (campaignId.isNotEmpty) {
        try {
          final evtDoc = await firestore.collection('events').doc(campaignId).get();
          if (evtDoc.exists) {
            activeEvent = EventModel.fromFirestore(evtDoc);
          }
        } catch (_) {}
      }

      // 1. Resolve Company Identity
      final String companySlug = (inv['companySlug'] ??
              inv['company_slug'] ??
              activeEvent?.companySlug ??
              widget.event.companySlug)
          .toString()
          .trim();
      final String targetCompany = (inv['targetCompany'] ??
              activeEvent?.targetCompany ??
              widget.event.targetCompany)
          .toString()
          .trim();

      // 2. Discover all active candidate campaigns for this company
      List<EventModel> companyEvents = [];
      if (companySlug.isNotEmpty) {
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

      if (companyEvents.isEmpty && targetCompany.isNotEmpty) {
        try {
          final snap = await firestore
              .collection('events')
              .where('targetCompany', isEqualTo: targetCompany)
              .where('isActive', isEqualTo: true)
              .get();
          companyEvents = snap.docs
              .map((d) => EventModel.fromFirestore(d))
              .where((e) => !e.isExpired)
              .toList();
        } catch (_) {}
      }

      if (activeEvent != null) {
        final currentEvent = activeEvent;
        if (!companyEvents.any((e) => e.id == currentEvent.id)) {
          companyEvents.insert(0, currentEvent);
        }
      }
      if (companyEvents.isEmpty) {
        companyEvents = [activeEvent ?? widget.event];
      }
      activeEvent ??= companyEvents.first;

      if (!isFullAiScan) {
        await _runQuickRuleRecheck(
          docId: docId,
          inv: inv,
          activeEvent: activeEvent,
          companyEvents: companyEvents,
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
    final dt = _parseDateTime(inv['timestamp'], inv['receipt_date']);
    final receiptDate = dt != null ? dt.toIso8601String() : (inv['receipt_date'] ?? '').toString();

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
      final spend = PromotionalRuleMatcher.spendTotals(
        products: products,
        rules: winningCampaign.promotionalRules,
        spendLadderMode: winningCampaign.spendLadderMode,
      );
      final double promoSpend = winningCampaign.spendLadderMode == 'consuming'
          ? spend.eligibleNet
          : (winningEval.qualifyingSpend > 0 ? winningEval.qualifyingSpend : targetTotal);
      final double invoiceSpend = winningCampaign.spendLadderMode == 'consuming' ? spend.invoiceNet : promoSpend;

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
        'rechecked_by': currentUser?.email ?? 'promoter',
        'recheck_type': winningCampaign.id == activeEvent.id ? 'quick_rule_match' : 'quick_multi_campaign_match',
        'target_company_total': promoSpend,
        'total_value': invoiceSpend,
        'chances_earned': chances,
        'canonical_branch': canonical,
        'branch_detected': canonical,
        if (claimedGifts.isNotEmpty) 'claimed_gifts': claimedGifts,
        if (isInteractiveReward) 'game_played': false,
      });

      if (mounted) {
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
          resolvedBranchName: canonical,
          resolvedLinkedGifts: winningEval.resolvedLinkedGifts,
          awardRounds: winningCampaign.spendLadderMode == 'consuming'
              ? SpendAwardRound.expand(winningEval.matchedRules)
              : const [],
          resolvedUnitValue: winningEval.resolvedUnitValue,
          resolvedIsVoucher: winningEval.resolvedIsVoucher,
          onViewAccepted: () {
            setState(() {
              _statusFilter = PromoterStatusFilter.accepted;
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
        'rechecked_by': currentUser?.email ?? 'promoter',
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
      allowMultipleChances: activeEvent.allowMultipleChances,
      multiplierBasis: activeEvent.multiplierBasis,
      maxChancesPerReceipt: activeEvent.maxChancesPerReceipt,
      promotionalRules: combinedPromotionalRules,
      spendLadderMode: activeEvent.spendLadderMode,
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

      final fullTotals = PromotionalRuleMatcher.spendTotals(
        products: result.extractedProducts,
        rules: winningCampaign.promotionalRules,
        spendLadderMode: winningCampaign.spendLadderMode,
      );
      final double computedTotal = result.extractedProducts.fold<double>(0.0, (acc, p) => acc + p.actualLineSpend);
      final double totalSpend = winningCampaign.spendLadderMode == 'consuming'
          ? fullTotals.invoiceNet
          : (computedTotal > 0 ? computedTotal : result.targetCompanyTotal);
      final double eligibleSpend = winningCampaign.spendLadderMode == 'consuming'
          ? fullTotals.eligibleNet
          : (winningEval.qualifyingSpend > 0 ? winningEval.qualifyingSpend : result.targetCompanyTotal);
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
        'rechecked_by': currentUser?.email ?? 'promoter',
        'recheck_type': winningCampaign.id == activeEvent.id ? 'full_ai_scan' : 'full_ai_multi_campaign_match',
        'extracted_products': result.extractedProducts.map((p) => p.toJson()).toList(),
        'target_company_total': eligibleSpend,
        'total_value': totalSpend,
        if (result.receiptNumber.isNotEmpty) 'receipt_number': result.receiptNumber,
        ...ReceiptDeduplicationHelper.componentFields(result.receiptNumber),
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
          resolvedBranchName: canonical,
          resolvedLinkedGifts: winningEval.resolvedLinkedGifts,
          awardRounds: winningCampaign.spendLadderMode == 'consuming'
              ? SpendAwardRound.expand(winningEval.matchedRules)
              : const [],
          resolvedUnitValue: winningEval.resolvedUnitValue,
          resolvedIsVoucher: winningEval.resolvedIsVoucher,
          onViewAccepted: () {
            setState(() {
              _statusFilter = PromoterStatusFilter.accepted;
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

      final rejectedTotals = PromotionalRuleMatcher.spendTotals(
        products: result.extractedProducts,
        rules: activeEvent.promotionalRules,
        spendLadderMode: activeEvent.spendLadderMode,
      );
      final double computedTotal = result.extractedProducts.fold<double>(0.0, (acc, p) => acc + p.actualLineSpend);
      final double totalSpend = activeEvent.spendLadderMode == 'consuming'
          ? rejectedTotals.invoiceNet
          : (computedTotal > 0 ? computedTotal : result.targetCompanyTotal);
      final double eligibleSpend = activeEvent.spendLadderMode == 'consuming'
          ? rejectedTotals.eligibleNet
          : result.targetCompanyTotal;

      await firestore.collection('receipts_transactions').doc(docId).update({
        'is_valid': false,
        'status': 'rejected',
        'unfulfilled_conditions': unfulfilledList,
        'rejection_reason': unfulfilledList.join(' • '),
        'extracted_products': result.extractedProducts.map((p) => p.toJson()).toList(),
        'target_company_total': eligibleSpend,
        'total_value': totalSpend,
        'rechecked_at': FieldValue.serverTimestamp(),
        'rechecked_by': currentUser?.email ?? 'promoter',
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
    String? docId,
    int totalChances = 1,
    String? resolvedBranchId,
    String? resolvedBranchName,
    List<LinkedGiftAllocation> resolvedLinkedGifts = const [],
    List<SpendAwardRound> awardRounds = const [],
    double? resolvedUnitValue,
    bool resolvedIsVoucher = false,
    VoidCallback? onViewAccepted,
  }) {
    final String gameType = (winningCampaign?.gameType ?? 'wheel').trim().toLowerCase();
    final bool isChooseGift = gameType == 'choosegift' || (resolvedLinkedGifts.length > 1 && gameType != 'directgift');
    final bool isWheel = !isChooseGift && (gameType == 'wheel' || gameType.isEmpty);
    final bool isScratch = !isChooseGift && (gameType == 'scratch' || gameType == 'scratchcard');
    final bool isDirect = !isChooseGift && !isWheel && !isScratch;

    final branchIdOrName = (resolvedBranchName != null && resolvedBranchName.trim().isNotEmpty)
        ? resolvedBranchName.trim()
        : resolvedBranchId;
    final bool consumingLadder = winningCampaign?.spendLadderMode == 'consuming';
    final effectiveRounds = consumingLadder ? awardRounds : const <SpendAwardRound>[];

    // Collect candidate prizes for choice or wheel. A consuming ladder never
    // falls back to every gift in the branch.
    List<String> candidatePrizes = [];
    if (consumingLadder) {
      candidatePrizes = [
        for (final round in effectiveRounds)
          for (final name in round.prizeNames) name,
      ];
    } else if (resolvedLinkedGifts.isNotEmpty) {
      candidatePrizes = resolvedLinkedGifts
          .map((g) => g.giftName.trim())
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList();
    }
    if (winningCampaign != null && !consumingLadder) {
      if (candidatePrizes.isNotEmpty) {
        final filtered = winningCampaign.filterGiftsByBranchStock(candidateGifts: candidatePrizes, branch: branchIdOrName);
        if (filtered.isNotEmpty) {
          candidatePrizes = filtered;
        }
      } else {
        candidatePrizes = winningCampaign.availablePrizeNamesForBranch(branchIdOrName);
      }
    }

    // Clean display title for choice campaigns
    String effectiveTitle = prizeTitle ?? '';
    if (isChooseGift && consumingLadder && effectiveRounds.isNotEmpty) {
      effectiveTitle = isAr
          ? 'سلم الإنفاق: ${effectiveRounds.length} جولات، وكل جولة تعرض هدايا شريحتها فقط'
          : 'Spend ladder: ${effectiveRounds.length} rounds, each with its own gifts';
    } else if (isChooseGift) {
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
                      if (consumingLadder && effectiveRounds.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        ...effectiveRounds.asMap().entries.map((entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            entry.value.roundLine(entry.key, effectiveRounds.length, arabic: isAr),
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSecondaryContainer),
                          ),
                        )),
                      ] else if (candidatePrizes.isNotEmpty) ...[
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
            if ((consumingLadder && effectiveRounds.isNotEmpty) || (isChooseGift && !consumingLadder))
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ChooseGiftScreen(
                        transactionId: docId,
                        eventId: winningCampaign.id,
                        companySlug: winningCampaign.companySlug,
                        prizes: effectiveRounds.isNotEmpty ? effectiveRounds.first.prizeNames : candidatePrizes,
                        roundPrizeNames: [for (final round in effectiveRounds) round.prizeNames],
                        roundGiftIds: [for (final round in effectiveRounds) round.giftIds],
                        roundUnitValues: [for (final round in effectiveRounds) round.unitValues],
                        roundRuleIds: [for (final round in effectiveRounds) round.ruleId],
                        roundTierMinSpends: [for (final round in effectiveRounds) round.tierMinSpend],
                        totalChances: effectiveRounds.isNotEmpty
                            ? effectiveRounds.length
                            : (totalChances > 0 ? totalChances : 1),
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
            else if (!consumingLadder && isWheel)
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
                        branchId: resolvedBranchId ?? branchIdOrName,
                        branchName: resolvedBranchName,
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
            else if (!consumingLadder && isScratch)
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
            else if (!consumingLadder && isDirect)
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
                        requireVoucherSerials: winningCampaign.requireVoucherSerials, voucherSerialMode: winningCampaign.voucherSerialMode,
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

  void _showReceiptImageZoomDialog(BuildContext context, String imageUrl, String receiptNumber, {List<String>? imageUrls}) {
    InteractiveReceiptViewerDialog.show(
      context,
      imageUrl: imageUrl,
      imageUrls: imageUrls,
      receiptNumber: receiptNumber,
    );
  }

  Widget _buildOtherSessionsNote(ColorScheme colorScheme, bool isAr) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.devices_other_rounded, size: 18, color: colorScheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isAr
                  ? 'يتضمن السجل $_otherSessionCount فاتورة لهذا الفرع مسجلة من جلسة/جهاز آخر.'
                  : 'Includes $_otherSessionCount receipt(s) for this branch from another session/device.',
              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme, AppStrings strings, bool isMobile) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                size: isMobile ? 42 : 56,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty
                  ? strings.noInvoicesFoundSearch
                  : (_selectedBranch != null && _selectedBranch!.isNotEmpty
                      ? strings.noInvoicesForBranch
                      : 'لا توجد فواتير مسجلة في هذه الحملة حتى الآن.'),
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 13.5 : 15,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'ستظهر جميع الفواتير التي يقوم البروموتر برفعها وتدقيقها بالذكاء الاصطناعي هنا مباشرة.',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(ColorScheme colorScheme, AppStrings strings, Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
            const SizedBox(height: 12),
            Text(
              AppErrorHandler.getFriendlyMessage(error, defaultMessage: 'حدث خطأ أثناء تحميل الفواتير'),
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(color: colorScheme.error, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.close),
            ),
          ],
        ),
      ),
    );
  }
}
