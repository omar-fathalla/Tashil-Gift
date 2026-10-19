import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/firebase_service.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../admin/domain/event_model.dart';

/// Interactive Material Design 3 Dialog displaying real-time Campaign Gifts,
/// Daily Handover/Disbursals Log with Date Navigation, and Branch Stock Balance.
class CampaignGiftBalanceDialog extends ConsumerStatefulWidget {
  final EventModel event;

  const CampaignGiftBalanceDialog({
    super.key,
    required this.event,
  });

  /// Static helper to display the dialog smoothly with M3 transitions
  static Future<void> show(BuildContext context, EventModel event) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'CampaignGiftBalanceDialog',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) {
        return CampaignGiftBalanceDialog(event: event);
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
  ConsumerState<CampaignGiftBalanceDialog> createState() => _CampaignGiftBalanceDialogState();
}

class _CampaignGiftBalanceDialogState extends ConsumerState<CampaignGiftBalanceDialog> {
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  String? _selectedBranchKey;
  String? _pinnedBranchKey;

  // View Tabs: 0 = Daily Disbursals / Handover, 1 = Remaining Stock Balance
  int _selectedTab = 0;

  // Date Filter for Daily Handover View
  late DateTime _selectedDate;
  bool _isAllTime = false;

  FirebaseFirestore? _lastFirestore;
  String? _lastEventId;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _eventDocStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _transactionsStream;

  void _ensureStreams(FirebaseFirestore firestore) {
    if (_lastFirestore == firestore && _lastEventId == widget.event.id && _eventDocStream != null) {
      return;
    }
    _lastFirestore = firestore;
    _lastEventId = widget.event.id;
    if (widget.event.id.isNotEmpty) {
      _eventDocStream = firestore.collection('events').doc(widget.event.id).snapshots();
      final slug = widget.event.companySlug.trim();
      if (slug.isNotEmpty) {
        _transactionsStream = firestore
            .collection('receipts_transactions')
            .where('companySlug', isEqualTo: slug)
            .snapshots();
      } else {
        _transactionsStream = firestore
            .collection('receipts_transactions')
            .where('event_id', isEqualTo: widget.event.id)
            .snapshots();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _loadSavedBranch();
  }

  Future<void> _loadSavedBranch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedForEvent = prefs.getString('pinned_branch_event_${widget.event.id}');
      final savedGlobal = prefs.getString('pinned_branch_global');
      final effectiveSaved = (savedForEvent != null && savedForEvent.isNotEmpty)
          ? savedForEvent
          : savedGlobal;

      final canonicalBranches = widget.event.branchNames
          .map((b) => b.trim())
          .where((b) => b.isNotEmpty)
          .toList();

      if (mounted && effectiveSaved != null && effectiveSaved.isNotEmpty) {
        final normalized = _normalizeBranchName(effectiveSaved, canonicalBranches, true);
        if (canonicalBranches.contains(normalized)) {
          setState(() {
            _selectedBranchKey = normalized;
            _pinnedBranchKey = normalized;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _savePinnedBranch(String branchKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pinned_branch_event_${widget.event.id}', branchKey);
      await prefs.setString('pinned_branch_global', branchKey);
      if (mounted) {
        setState(() {
          _pinnedBranchKey = branchKey;
        });
      }
    } catch (_) {}
  }

  Future<void> _clearPinnedBranch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pinned_branch_event_${widget.event.id}');
      await prefs.remove('pinned_branch_global');
      if (mounted) {
        setState(() {
          _pinnedBranchKey = null;
        });
      }
    } catch (_) {}
  }

  static String _cleanBranchForComparison(String branch) {
    var s = branch.trim().toLowerCase();
    s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    s = s.replaceAll(RegExp(r'[أإآ]'), 'ا');
    s = s.replaceAll('ة', 'ه').replaceAll('ى', 'ي');
    s = s.replaceAll(RegExp(r'[\u0660-\u0669]'), '');
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
    final rawDigits = RegExp(r'\b\d+\b').allMatches(clean).map((m) => m.group(0)!).toSet();
    if (rawDigits.isNotEmpty) {
      for (final canonical in canonicalBranches) {
        final canonDigits = RegExp(r'\b\d+\b').allMatches(canonical).map((m) => m.group(0)!).toSet();
        if (rawDigits.intersection(canonDigits).isNotEmpty) {
          return canonical;
        }
      }
    }

    // 5. Containment match
    for (final canonical in canonicalBranches) {
      final canonComp = _cleanBranchForComparison(canonical);
      if (canonComp.isNotEmpty && (cleanComp.contains(canonComp) || canonComp.contains(cleanComp))) {
        return canonical;
      }
    }

    return canonicalBranches.first;
  }

  static DateTime? _parseDate(dynamic val1, [dynamic val2, dynamic val3, dynamic val4]) {
    for (final val in [val1, val2, val3, val4]) {
      if (val == null) continue;
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is String && val.trim().isNotEmpty) {
        final raw = val.trim();
        final dt = DateTime.tryParse(raw);
        if (dt != null) return dt;
        final parts = raw.split(RegExp(r'[/.-]'));
        if (parts.length == 3) {
          final p0 = int.tryParse(parts[0]) ?? 1;
          final p1 = int.tryParse(parts[1]) ?? 1;
          final p2 = int.tryParse(parts[2]) ?? 2026;
          if (p2 > 1000) {
            if (p0 > 1000) return DateTime(p0, p1, p2);
            return DateTime(p2, p1, p0);
          }
        }
      }
    }
    return null;
  }

  static List<AllocatedPrize> _aggregatePrizes(List<AllocatedPrize> prizes) {
    final Map<String, AllocatedPrize> aggMap = {};
    for (final p in prizes) {
      final key = '${p.giftId}_${p.name}_${p.unitValue}_${p.giftType}';
      if (!aggMap.containsKey(key)) {
        aggMap[key] = AllocatedPrize(
          giftId: p.giftId,
          name: p.name,
          allocatedQuantity: p.allocatedQuantity,
          remainingQuantity: p.remainingQuantity,
          unitValue: p.unitValue,
          giftType: p.giftType,
          branchId: 'all',
          branchName: 'كافة الفروع',
        );
      } else {
        final existing = aggMap[key]!;
        aggMap[key] = AllocatedPrize(
          giftId: existing.giftId,
          name: existing.name,
          allocatedQuantity: existing.allocatedQuantity + p.allocatedQuantity,
          remainingQuantity: existing.remainingQuantity + p.remainingQuantity,
          unitValue: existing.unitValue,
          giftType: existing.giftType,
          branchId: 'all',
          branchName: 'كافة الفروع',
        );
      }
    }
    return aggMap.values.toList();
  }

  static String _normalizeKey(String text) {
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
        .replaceAll(RegExp(r'[^\u0600-\u06FFa-zA-Z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _matchesPrize(AllocatedPrize prize, Map<String, dynamic> cg) {
    final gId = (cg['giftId'] ?? cg['gift_id'] ?? '').toString().trim();
    if (gId.isNotEmpty && prize.giftId.isNotEmpty && gId == prize.giftId) {
      return true;
    }

    final gName = (cg['giftName'] ?? cg['gift_name'] ?? cg['name'] ?? '').toString().trim();
    final normG = _normalizeKey(gName);
    final normP = _normalizeKey(prize.name);

    if (normG.isNotEmpty && normG == normP) {
      return true;
    }

    final cgVal = (cg['unitValue'] ?? cg['unit_value'] as num?)?.toDouble() ?? 0.0;
    final cgIsVoucher = cg['isVoucher'] == true || cg['is_voucher'] == true;

    // Strict voucher denomination matching
    if (prize.isVoucher && cgIsVoucher && prize.unitValue > 0 && cgVal > 0) {
      if (prize.unitValue.toInt() == cgVal.toInt()) {
        return true;
      }
    }

    // Brand specific match
    final isClearP = normP.contains('كلير') || normP.contains('clear');
    final isClearG = normG.contains('كلير') || normG.contains('clear');
    if (isClearP && isClearG) return true;

    final isTresemmeP = normP.contains('تريزيمي') || normP.contains('تريزمي') || normP.contains('tresemme');
    final isTresemmeG = normG.contains('تريزيمي') || normG.contains('تريزمي') || normG.contains('tresemme');
    if (isTresemmeP && isTresemmeG) return true;

    return false;
  }

  String _formatDateArabic(DateTime dt, bool isAr) {
    if (!isAr) {
      return '${dt.day}/${dt.month}/${dt.year}';
    }

    const weekdays = [
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد',
    ];
    const months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];

    final weekdayName = weekdays[(dt.weekday - 1) % 7];
    final monthName = months[(dt.month - 1) % 12];
    return '$weekdayName، ${dt.day} $monthName ${dt.year}';
  }

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
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
        _isAllTime = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = AppStrings.of(ref);
    final isAr = strings.isAr;
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isMobile = screenWidth < 600;

    Stream<DocumentSnapshot<Map<String, dynamic>>>? eventDocStream;
    Stream<QuerySnapshot<Map<String, dynamic>>>? transactionsStream;
    try {
      final firestore = ref.watch(firestoreProvider);
      _ensureStreams(firestore);
      eventDocStream = _eventDocStream;
      transactionsStream = _transactionsStream;
    } catch (_) {}

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Dialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isMobile ? 22 : 28),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        insetPadding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 24,
          vertical: isMobile ? 16 : 32,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 680,
            maxHeight: mediaQuery.size.height * 0.88,
          ),
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: eventDocStream,
            builder: (context, eventSnap) {
              EventModel liveEvent = widget.event;
              if (eventSnap.hasData && eventSnap.data != null && eventSnap.data!.exists) {
                try {
                  liveEvent = EventModel.fromFirestore(eventSnap.data!);
                } catch (_) {}
              }

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: transactionsStream,
                builder: (context, txSnap) {
                  final txDocs = txSnap.data?.docs ?? [];

                  // 1. Strictly Canonical Branches from Event definition
                  final List<String> canonicalBranches = liveEvent.branchNames
                      .map((b) => b.trim())
                      .where((b) => b.isNotEmpty)
                      .toList();

                  final allPrizes = liveEvent.allocatedPrizes;
                  final Map<String, List<AllocatedPrize>> branchPrizesMap = {};
                  final Map<String, String> branchDisplayNames = {};

                  // A. Add "All Branches" Scope
                  branchDisplayNames['all'] = strings.allBranchesScope;
                  branchPrizesMap['all'] = allPrizes;

                  // B. Initialize entry for each canonical branch
                  for (final b in canonicalBranches) {
                    branchDisplayNames[b] = b;
                    branchPrizesMap[b] = [];
                  }

                  // C. Map allocated prizes to their canonical branch
                  for (final prize in allPrizes) {
                    final rawPrizeBranch = (prize.branchName.isNotEmpty ? prize.branchName : prize.branchId).trim();
                    if (rawPrizeBranch.isEmpty) continue;
                    final canonBranch = _normalizeBranchName(rawPrizeBranch, canonicalBranches, isAr);
                    branchPrizesMap.putIfAbsent(canonBranch, () => []).add(prize);
                  }

                  // D. Branch Keys: Strictly 'all' + canonicalBranches ONLY (Zero Rogue Branches)
                  final List<String> branchKeys = ['all', ...canonicalBranches];

                  // Auto-select pinned branch or fallback
                  if (_selectedBranchKey == null || !branchKeys.contains(_selectedBranchKey)) {
                    if (_pinnedBranchKey != null && branchKeys.contains(_pinnedBranchKey)) {
                      _selectedBranchKey = _pinnedBranchKey;
                    } else if (branchKeys.length > 1) {
                      _selectedBranchKey = branchKeys.firstWhere((k) => k != 'all', orElse: () => 'all');
                    } else {
                      _selectedBranchKey = 'all';
                    }
                  }

                  final currentBranchKey = _selectedBranchKey ?? 'all';
                  final currentBranchName = branchDisplayNames[currentBranchKey] ?? currentBranchKey;

                  final activeBranchPrizes = (currentBranchKey != 'all' && (branchPrizesMap[currentBranchKey]?.isNotEmpty ?? false))
                      ? branchPrizesMap[currentBranchKey]!
                      : _aggregatePrizes(allPrizes);

                  // Stock calculations
                  int totalAllocatedInBranch = 0;
                  int totalRemainingInBranch = 0;
                  for (final p in activeBranchPrizes) {
                    totalAllocatedInBranch += p.allocatedQuantity;
                    totalRemainingInBranch += p.remainingQuantity;
                  }

                  // -----------------------------------------------------------
                  // Daily / Date-Filtered Disbursal & Handover Aggregation
                  // -----------------------------------------------------------
                  final Map<String, int> disbursedPerPrizeId = {};
                  final Map<String, double> disbursedValuePerPrizeId = {};
                  int totalGiftsDisbursedOnDate = 0;
                  double totalVouchersValueOnDate = 0.0;
                  int totalInvoicesOnDate = 0;

                  for (final doc in txDocs) {
                    final data = doc.data();
                    final eventId = (data['event_id'] ?? data['campaignId'] ?? data['campaign_id'] ?? '').toString();
                    final companySlug = (data['companySlug'] ?? data['company_slug'] ?? '').toString().toLowerCase();
                    final targetCompany = (data['targetCompany'] ?? data['target_company'] ?? '').toString().toLowerCase();

                    final eventTarget = liveEvent.targetCompany.toLowerCase();
                    final eventSlug = liveEvent.companySlug.toLowerCase();

                    final bool matchesEvent = (eventId.isNotEmpty && eventId == liveEvent.id) ||
                        (eventSlug.isNotEmpty && companySlug == eventSlug) ||
                        (eventTarget.isNotEmpty && targetCompany.contains(eventTarget));

                    if (!matchesEvent) {
                      continue;
                    }

                    final bool isExplicitlyValid = data['is_valid'] == true || data['status'] == 'accepted' || data['isValid'] == true;
                    final bool isExplicitlyRejected = data['is_valid'] == false || data['status'] == 'rejected' || data['isValid'] == false || ((data['unfulfilled_conditions'] as List?)?.isNotEmpty ?? false);
                    final bool isValid = isExplicitlyValid || (!isExplicitlyRejected && ((data['unfulfilled_conditions'] as List?)?.isEmpty ?? true));

                    if (!isValid) {
                      continue; // Strictly exclude rejected invoices
                    }

                    // Date parsing across all possible timestamp & date fields
                    final docDate = _parseDate(
                      data['claimed_at'],
                      data['created_at'],
                      data['timestamp'],
                      data['receipt_date'] ?? data['date'],
                    );

                    if (!_isAllTime) {
                      if (docDate == null) continue;
                      final isSameDay = docDate.year == _selectedDate.year &&
                          docDate.month == _selectedDate.month &&
                          docDate.day == _selectedDate.day;
                      if (!isSameDay) continue;
                    }

                    // Strict Branch Filtering
                    if (currentBranchKey != 'all') {
                      final rawBranch = (data['branch_detected'] ?? data['branch_name'] ?? data['branch'] ?? data['branchName'] ?? '').toString().trim();
                      final txCanonBranch = _normalizeBranchName(rawBranch, canonicalBranches, isAr);
                      final normSel = _cleanBranchForComparison(currentBranchName);
                      final normTx = _cleanBranchForComparison(txCanonBranch);

                      if (txCanonBranch != currentBranchName && normTx != normSel && !normTx.contains(normSel) && !normSel.contains(normTx)) {
                        continue;
                      }
                    }

                    totalInvoicesOnDate++;

                    // Extract claimed gifts
                    final claimedGifts = (data['claimed_gifts'] as List?) ?? [];
                    if (claimedGifts.isNotEmpty) {
                      for (final cg in claimedGifts) {
                        if (cg is Map) {
                          final cgMap = Map<String, dynamic>.from(cg);
                          final qty = (cgMap['quantity'] as num?)?.toInt() ?? 1;
                          final uVal = (cgMap['unitValue'] ?? cgMap['unit_value'] as num?)?.toDouble() ?? 0.0;
                          final isVoucher = cgMap['isVoucher'] == true || cgMap['is_voucher'] == true;

                          totalGiftsDisbursedOnDate += qty;
                          if (isVoucher && uVal > 0) {
                            totalVouchersValueOnDate += (uVal * qty);
                          }

                          // Match with configured prizes
                          for (final prize in activeBranchPrizes) {
                            if (_matchesPrize(prize, cgMap)) {
                              final pKey = prize.giftId.isNotEmpty ? prize.giftId : prize.name;
                              disbursedPerPrizeId[pKey] = (disbursedPerPrizeId[pKey] ?? 0) + qty;
                              if (isVoucher && uVal > 0) {
                                disbursedValuePerPrizeId[pKey] = (disbursedValuePerPrizeId[pKey] ?? 0.0) + (uVal * qty);
                              }
                            }
                          }
                        }
                      }
                    } else {
                      final prizesWon = (data['prizes_won'] as List?)?.map((p) => p.toString()).toList() ??
                          [(data['prize_won'] ?? data['prizeWon'] ?? data['prize'] ?? '').toString()];
                      for (final p in prizesWon) {
                        if (p.trim().isNotEmpty) {
                          totalGiftsDisbursedOnDate += 1;
                          for (final prize in activeBranchPrizes) {
                            if (_matchesPrize(prize, {'giftName': p})) {
                              final pKey = prize.giftId.isNotEmpty ? prize.giftId : prize.name;
                              disbursedPerPrizeId[pKey] = (disbursedPerPrizeId[pKey] ?? 0) + 1;
                            }
                          }
                        }
                      }
                    }
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Dialog Header (M3 Title, Company Subtitle & Close Action)
                      _buildHeader(
                        context: context,
                        colorScheme: colorScheme,
                        strings: strings,
                        event: liveEvent,
                        isMobile: isMobile,
                      ),

                      // 2. Mode Switcher (Daily Handover vs Stock Balance)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 14 : 20,
                          vertical: 6,
                        ),
                        child: _buildModeSegmentedControl(
                          context: context,
                          colorScheme: colorScheme,
                          strings: strings,
                          isMobile: isMobile,
                        ),
                      ),

                      const Divider(height: 1),

                      // 3. Scrollable Body
                      Flexible(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(isMobile ? 14 : 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Branch Selection Dropdown
                              if (branchKeys.length > 1) ...[
                                Text(
                                  strings.selectBranchToViewStock,
                                  style: GoogleFonts.cairo(
                                    fontSize: isMobile ? 12.5 : 13.5,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _buildBranchSelector(
                                  context: context,
                                  colorScheme: colorScheme,
                                  strings: strings,
                                  branchKeys: branchKeys,
                                  branchNames: branchDisplayNames,
                                  branchPrizesMap: branchPrizesMap,
                                  isMobile: isMobile,
                                ),
                                const SizedBox(height: 16),
                              ],

                              if (_selectedTab == 0) ...[
                                // ---------------------------------------------
                                // TAB 0: Daily Disbursals / Handover Log
                                // ---------------------------------------------
                                _buildDateFilterBar(
                                  context: context,
                                  colorScheme: colorScheme,
                                  strings: strings,
                                  isAr: isAr,
                                  isMobile: isMobile,
                                ),

                                const SizedBox(height: 14),

                                // KPI Summary Metrics
                                _buildDailyKpis(
                                  context: context,
                                  colorScheme: colorScheme,
                                  strings: strings,
                                  totalGifts: totalGiftsDisbursedOnDate,
                                  totalVouchers: totalVouchersValueOnDate,
                                  totalInvoices: totalInvoicesOnDate,
                                  isMobile: isMobile,
                                ),

                                const SizedBox(height: 16),

                                // Disbursed Items Breakdown List
                                if (activeBranchPrizes.isEmpty)
                                  _buildEmptyState(context, colorScheme, strings)
                                else
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: activeBranchPrizes.length,
                                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                                    itemBuilder: (context, index) {
                                      final prize = activeBranchPrizes[index];
                                      final pKey = prize.giftId.isNotEmpty ? prize.giftId : prize.name;

                                      final disbursedCount = disbursedPerPrizeId[pKey] ?? 0;
                                      final disbursedVal = disbursedValuePerPrizeId[pKey] ?? 0.0;

                                      return _buildDailyDisbursedCard(
                                        context: context,
                                        colorScheme: colorScheme,
                                        strings: strings,
                                        prize: prize,
                                        disbursedCount: disbursedCount,
                                        disbursedValue: disbursedVal,
                                        isMobile: isMobile,
                                      );
                                    },
                                  ),
                              ] else ...[
                                // ---------------------------------------------
                                // TAB 1: Remaining Stock Balance
                                // ---------------------------------------------
                                _buildBranchSummaryCard(
                                  context: context,
                                  colorScheme: colorScheme,
                                  strings: strings,
                                  remaining: totalRemainingInBranch,
                                  total: totalAllocatedInBranch,
                                  giftTypesCount: activeBranchPrizes.length,
                                  isMobile: isMobile,
                                ),

                                const SizedBox(height: 16),

                                if (activeBranchPrizes.isEmpty)
                                  _buildEmptyState(context, colorScheme, strings)
                                else
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: activeBranchPrizes.length,
                                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                                    itemBuilder: (context, index) {
                                      final prize = activeBranchPrizes[index];
                                      return _buildPrizeInventoryCard(
                                        context: context,
                                        colorScheme: colorScheme,
                                        strings: strings,
                                        prize: prize,
                                        isMobile: isMobile,
                                      );
                                    },
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      const Divider(height: 1),

                      // 4. Dialog Footer (M3 Close Action)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 14 : 20,
                          vertical: isMobile ? 12 : 14,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.check_rounded, size: 18),
                                label: Text(
                                  strings.closeInventoryDialog,
                                  style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.bold,
                                    fontSize: isMobile ? 13 : 14,
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                    vertical: isMobile ? 12 : 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
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
    required EventModel event,
    required bool isMobile,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 14 : 20,
        isMobile ? 14 : 18,
        isMobile ? 8 : 12,
        isMobile ? 8 : 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primary,
                  colorScheme.tertiary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.inventory_2_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _selectedTab == 0
                      ? strings.promoterDailyDisbursalTitle
                      : strings.promoterGiftsBalanceTitle,
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 15.5 : 17.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${event.eventName} (${event.targetCompany})',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 11.5 : 12.5,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 22),
            tooltip: strings.close,
            onPressed: () => Navigator.of(context).pop(),
            style: IconButton.styleFrom(
              foregroundColor: colorScheme.onSurfaceVariant,
              backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSegmentedControl({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isMobile,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          // Tab 0: Daily Disbursals / Handover
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _selectedTab = 0),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(vertical: isMobile ? 8 : 10),
                decoration: BoxDecoration(
                  color: _selectedTab == 0 ? colorScheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _selectedTab == 0
                      ? [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.query_builder_rounded,
                      size: 16,
                      color: _selectedTab == 0 ? Colors.white : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        strings.promoterDailyDisbursalTab,
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 12 : 13,
                          fontWeight: FontWeight.bold,
                          color: _selectedTab == 0 ? Colors.white : colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),

          // Tab 1: Remaining Stock Balance
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _selectedTab = 1),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(vertical: isMobile ? 8 : 10),
                decoration: BoxDecoration(
                  color: _selectedTab == 1 ? colorScheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _selectedTab == 1
                      ? [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.inventory_rounded,
                      size: 16,
                      color: _selectedTab == 1 ? Colors.white : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        strings.promoterStockBalanceTab,
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 12 : 13,
                          fontWeight: FontWeight.bold,
                          color: _selectedTab == 1 ? Colors.white : colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateFilterBar({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isMobile,
  }) {
    final isCurrentDayToday = _isToday(_selectedDate) && !_isAllTime;

    return Container(
      padding: EdgeInsets.all(isMobile ? 10 : 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Previous Day Button
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, size: 22),
                tooltip: strings.previousDayTooltip,
                onPressed: () {
                  setState(() {
                    _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                    _isAllTime = false;
                  });
                },
                style: IconButton.styleFrom(
                  padding: EdgeInsets.all(isMobile ? 6 : 8),
                  backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(width: 6),

              // Date Display & Picker Button
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 10 : 14,
                      vertical: isMobile ? 8 : 10,
                    ),
                    decoration: BoxDecoration(
                      color: isCurrentDayToday
                          ? colorScheme.primaryContainer.withValues(alpha: 0.6)
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrentDayToday
                            ? colorScheme.primary.withValues(alpha: 0.4)
                            : colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.calendar_month_rounded,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _isAllTime
                                ? strings.allTimeShortcut
                                : _formatDateArabic(_selectedDate, isAr),
                            style: GoogleFonts.cairo(
                              fontSize: isMobile ? 12.5 : 13.5,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCurrentDayToday) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              strings.todayShortcut,
                              style: GoogleFonts.cairo(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Next Day Button (Disabled if already today)
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 22),
                tooltip: strings.nextDayTooltip,
                onPressed: _isToday(_selectedDate)
                    ? null
                    : () {
                        setState(() {
                          _selectedDate = _selectedDate.add(const Duration(days: 1));
                          _isAllTime = false;
                        });
                      },
                style: IconButton.styleFrom(
                  padding: EdgeInsets.all(isMobile ? 6 : 8),
                  backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),

          // Shortcut chips (Today, All-time)
          if (!_isToday(_selectedDate) || _isAllTime) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.today_rounded, size: 14),
                  label: Text(
                    'الرجوع لليوم الحالي',
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    final now = DateTime.now();
                    setState(() {
                      _selectedDate = DateTime(now.year, now.month, now.day);
                      _isAllTime = false;
                    });
                  },
                  backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
                  side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.all_inclusive_rounded, size: 14),
                  label: Text(
                    strings.allTimeShortcut,
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    setState(() {
                      _isAllTime = true;
                    });
                  },
                  backgroundColor: _isAllTime
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  labelStyle: TextStyle(
                    color: _isAllTime ? Colors.white : colorScheme.onSurface,
                  ),
                  side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDailyKpis({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required int totalGifts,
    required double totalVouchers,
    required int totalInvoices,
    required bool isMobile,
  }) {
    return Row(
      children: [
        // KPI 1: Total Disbursed Gifts
        Expanded(
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 10 : 12,
              vertical: isMobile ? 10 : 12,
            ),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.card_giftcard_rounded, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        strings.totalDisbursedCountLabel,
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 10.5 : 11.5,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$totalGifts قطعة',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 15 : 17,
                    fontWeight: FontWeight.w900,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),

        // KPI 2: Total Vouchers Amount
        if (totalVouchers > 0) ...[
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 10 : 12,
                vertical: isMobile ? 10 : 12,
              ),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colorScheme.primaryFixedDim),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.confirmation_number_rounded, size: 16, color: colorScheme.onSecondaryContainer),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          strings.totalDisbursedVouchersLabel,
                          style: GoogleFonts.cairo(
                            fontSize: isMobile ? 10.5 : 11.5,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSecondaryContainer,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${totalVouchers.toInt()} ج.م',
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 15 : 17,
                      fontWeight: FontWeight.w900,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],

        // KPI 3: Processed Invoices Count
        Expanded(
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 10 : 12,
              vertical: isMobile ? 10 : 12,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.receipt_long_rounded, size: 16, color: colorScheme.secondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        strings.disbursedInvoicesCountLabel,
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 10.5 : 11.5,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$totalInvoices فاتورة',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 15 : 17,
                    fontWeight: FontWeight.w900,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyDisbursedCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required AllocatedPrize prize,
    required int disbursedCount,
    required double disbursedValue,
    required bool isMobile,
  }) {
    final isVoucher = prize.isVoucher;
    final hasDisbursed = disbursedCount > 0;

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasDisbursed
              ? (isVoucher ? colorScheme.primaryFixedDim : colorScheme.primary.withValues(alpha: 0.4))
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: hasDisbursed ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isVoucher
                      ? colorScheme.secondaryContainer
                      : colorScheme.primaryContainer.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                  color: isVoucher ? colorScheme.onSecondaryContainer : colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prize.name,
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 14 : 15,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${strings.branchRemainingStockLabel}: ${prize.remainingQuantity} ${strings.outOfLabel} ${prize.allocatedQuantity}',
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 11 : 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Disbursed Badge on Date
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: hasDisbursed
                      ? (isVoucher ? colorScheme.secondary : colorScheme.primary)
                      : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: hasDisbursed
                      ? [
                          BoxShadow(
                            color: (isVoucher ? colorScheme.secondary : colorScheme.primary)
                                .withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'منصرف اليوم',
                      style: GoogleFonts.cairo(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: hasDisbursed ? Colors.white.withValues(alpha: 0.9) : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '$disbursedCount قطعة',
                      style: GoogleFonts.cairo(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: hasDisbursed ? Colors.white : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (isVoucher && disbursedValue > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.secondaryFixedDim),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.payments_rounded, size: 14, color: colorScheme.onSecondaryContainer),
                  const SizedBox(width: 6),
                  Text(
                    '${strings.disbursedVoucherAmountLabel}: ${disbursedValue.toInt()} ج.م',
                    style: GoogleFonts.cairo(
                      fontSize: 11.5,
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
    );
  }

  Widget _buildBranchSelector({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required List<String> branchKeys,
    required Map<String, String> branchNames,
    required Map<String, List<AllocatedPrize>> branchPrizesMap,
    required bool isMobile,
  }) {
    final effectiveValue = (branchKeys.contains(_selectedBranchKey))
        ? _selectedBranchKey
        : (branchKeys.isNotEmpty ? branchKeys.first : null);

    final isPinned = _pinnedBranchKey != null && _pinnedBranchKey == effectiveValue && effectiveValue != 'all';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Dropdown Form Field for Branch Selection
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPinned ? colorScheme.primary.withValues(alpha: 0.5) : colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: isPinned ? 1.5 : 1.0,
            ),
          ),
          child: DropdownButtonFormField<String>(
            key: ValueKey('branch_picker_${effectiveValue}_${branchKeys.length}'),
            initialValue: effectiveValue,
            isExpanded: true,
            dropdownColor: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            icon: Icon(Icons.arrow_drop_down_circle_outlined, color: colorScheme.primary, size: 20),
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 16,
                vertical: isMobile ? 10 : 12,
              ),
              border: InputBorder.none,
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.storefront_rounded, color: colorScheme.primary, size: 22),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 42),
            ),
            items: branchKeys.map((key) {
              final name = branchNames[key] ?? key;
              final prizes = branchPrizesMap[key] ?? [];
              int remainingInBranch = 0;
              for (final p in prizes) {
                remainingInBranch += p.remainingQuantity;
              }
              final isItemPinned = _pinnedBranchKey == key;
              final isAll = key == 'all';

              return DropdownMenuItem<String>(
                value: key,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: isMobile ? 13 : 14,
                          color: isAll ? colorScheme.primary : colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isItemPinned && !isAll) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(left: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.push_pin_rounded, size: 12, color: colorScheme.onSecondaryFixedVariant),
                            const SizedBox(width: 3),
                            Text(
                              'مثبت',
                              style: GoogleFonts.cairo(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (remainingInBranch > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$remainingInBranch متبقي',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (newKey) {
              if (newKey != null) {
                setState(() {
                  _selectedBranchKey = newKey;
                });
                if (newKey != 'all') {
                  _savePinnedBranch(newKey);
                }
              }
            },
          ),
        ),

        const SizedBox(height: 8),

        // Pin / Save branch toggle bar (if not 'all')
        if (effectiveValue != null && effectiveValue != 'all')
          InkWell(
            onTap: () {
              if (isPinned) {
                _clearPinnedBranch();
              } else {
                _savePinnedBranch(effectiveValue);
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    size: 16,
                    color: isPinned ? colorScheme.onSecondaryFixedVariant : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isPinned
                          ? 'تم تثبيت هذا الفرع كافتراضي (يفتح تلقائياً عند فتح النافذة)'
                          : 'انقر لتثبيت هذا الفرع كفرعك الافتراضي الدائم',
                      style: GoogleFonts.cairo(
                        fontSize: 11.5,
                        fontWeight: isPinned ? FontWeight.bold : FontWeight.normal,
                        color: isPinned ? colorScheme.onSecondaryContainer : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (isPinned)
                    Text(
                      'إلغاء التثبيت',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: colorScheme.error,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBranchSummaryCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required int remaining,
    required int total,
    required int giftTypesCount,
    required bool isMobile,
  }) {
    final ratio = total > 0 ? (remaining / total).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.analytics_outlined,
                color: colorScheme.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.totalBranchStock,
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    fontSize: isMobile ? 12.5 : 13.5,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$remaining',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: remaining > 0 ? colorScheme.primary : colorScheme.error,
                      ),
                    ),
                    TextSpan(
                      text: ' / $total',
                      style: GoogleFonts.cairo(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: colorScheme.surfaceContainerHighest,
              color: remaining == 0
                  ? colorScheme.error
                  : (remaining <= 2 ? colorScheme.secondary : colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrizeInventoryCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required AllocatedPrize prize,
    required bool isMobile,
  }) {
    final remaining = prize.remainingQuantity;
    final total = prize.allocatedQuantity;
    final ratio = total > 0 ? (remaining / total).clamp(0.0, 1.0) : 0.0;
    final isVoucher = prize.isVoucher;

    final isOut = remaining <= 0;
    final isLow = remaining > 0 && remaining <= 2;

    final Color statusColor = isOut
        ? colorScheme.error
        : (isLow ? colorScheme.onSecondaryFixedVariant : colorScheme.tertiary);

    final String statusText = isOut
        ? strings.giftStatusEmpty
        : (isLow ? strings.giftStatusLow : strings.giftStatusAvailable);

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOut
              ? colorScheme.error.withValues(alpha: 0.3)
              : (isLow ? colorScheme.primary.withValues(alpha: 0.4) : colorScheme.outlineVariant.withValues(alpha: 0.5)),
          width: isLow || isOut ? 1.3 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isOut
                      ? colorScheme.errorContainer.withValues(alpha: 0.5)
                      : (isLow
                          ? colorScheme.secondaryContainer
                          : (isVoucher
                              ? colorScheme.primaryContainer.withValues(alpha: 0.8)
                              : colorScheme.primaryContainer.withValues(alpha: 0.6))),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                  color: isOut
                      ? colorScheme.error
                      : (isLow ? colorScheme.onSecondaryContainer : colorScheme.primary),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prize.name,
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 13.5 : 14.5,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${strings.remainingOutOfTotal} $remaining ${strings.outOfLabel} $total',
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 11 : 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isOut
                      ? colorScheme.errorContainer
                      : (isLow ? colorScheme.secondaryContainer : colorScheme.tertiaryContainer),
                  borderRadius: BorderRadius.circular(8),
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
                    const SizedBox(width: 5),
                    Text(
                      statusText,
                      style: GoogleFonts.cairo(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ColorScheme colorScheme,
    AppStrings strings,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.card_giftcard_outlined,
            size: 48,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            strings.noGiftsAllocatedForBranch,
            style: GoogleFonts.cairo(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
