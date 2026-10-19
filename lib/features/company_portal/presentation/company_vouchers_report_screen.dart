import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/utils/file_download_helper.dart';
import '../../../core/widgets/switch_point_branding.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/utils/slug_utils.dart';
import '../../admin/domain/retail_chain_model.dart';
import '../../admin/domain/company_gift_model.dart';
import '../../admin/domain/event_model.dart';
import '../../../core/widgets/m3_adaptive_scaffold.dart';
import '../../../core/widgets/m3_button_groups.dart';

/// Data structure representing a single voucher denomination (e.g. 25 EGP, 50 EGP)
class VoucherDenominationStats {
  final double denomination;
  final String label;
  int allocatedCount = 0;
  int claimedCount = 0;
  int remainingCount = 0;
  int masterTotalCount = 0;
  int masterAvailableCount = 0;

  final Map<String, int> branchAllocatedMap = {};
  final Map<String, int> branchClaimedMap = {};
  final Map<String, int> branchRemainingMap = {};

  VoucherDenominationStats({
    required this.denomination,
    required this.label,
    this.allocatedCount = 0,
    this.claimedCount = 0,
    this.remainingCount = 0,
    this.masterTotalCount = 0,
    this.masterAvailableCount = 0,
    Map<String, int>? branchAllocatedMap,
    Map<String, int>? branchClaimedMap,
    Map<String, int>? branchRemainingMap,
  }) {
    if (branchAllocatedMap != null) this.branchAllocatedMap.addAll(branchAllocatedMap);
    if (branchClaimedMap != null) this.branchClaimedMap.addAll(branchClaimedMap);
    if (branchRemainingMap != null) this.branchRemainingMap.addAll(branchRemainingMap);
  }

  double get totalBudget => allocatedCount * denomination;
  double get claimedValue => claimedCount * denomination;
  double get remainingValue => remainingCount * denomination;
  double get masterTotalBudget => masterTotalCount * denomination;
  double get masterAvailableBudget => masterAvailableCount * denomination;

  double get depletionRate => allocatedCount > 0
      ? (claimedCount / allocatedCount).clamp(0.0, 1.0)
      : 0.0;
}

/// Aggregated Voucher Metrics across active filters (all branches or single branch, all events or single event)
class AggregatedVoucherMetrics {
  final int totalUnitsAllocated;
  final int totalUnitsClaimed;
  final int totalUnitsRemaining;
  final double totalBudgetEgp;
  final double totalClaimedEgp;
  final double totalRemainingEgp;
  final List<VoucherDenominationStats> denominations;
  final Map<String, Map<double, VoucherDenominationStats>> branchDenominationsMap;
  final Map<String, int> branchTotalVoucherUnits;
  final Map<String, double> branchTotalVoucherBudget;
  final Map<String, int> branchClaimedVoucherUnits;
  final Map<String, int> branchRemainingVoucherUnits;

  AggregatedVoucherMetrics({
    required this.totalUnitsAllocated,
    required this.totalUnitsClaimed,
    required this.totalUnitsRemaining,
    required this.totalBudgetEgp,
    required this.totalClaimedEgp,
    required this.totalRemainingEgp,
    required this.denominations,
    required this.branchDenominationsMap,
    required this.branchTotalVoucherUnits,
    required this.branchTotalVoucherBudget,
    required this.branchClaimedVoucherUnits,
    required this.branchRemainingVoucherUnits,
  });

  double get depletionRate => totalBudgetEgp > 0
      ? (totalClaimedEgp / totalBudgetEgp).clamp(0.0, 1.0)
      : (totalUnitsAllocated > 0
          ? (totalUnitsClaimed / totalUnitsAllocated).clamp(0.0, 1.0)
          : 0.0);
}

/// Standalone Dedicated Vouchers & Gift Cards Intelligence Screen (منظومة قسائم المشتريات والفواتشر المستقلة)
class CompanyVouchersReportScreen extends ConsumerStatefulWidget {
  final String? initialEventId;
  final String? lockedEventId;
  final String? lockedCompanySlug;
  final String? lockedCompanyName;
  final bool isEmbedded;

  const CompanyVouchersReportScreen({
    super.key,
    this.initialEventId,
    this.lockedEventId,
    this.lockedCompanySlug,
    this.lockedCompanyName,
    this.isEmbedded = false,
  });

  @override
  ConsumerState<CompanyVouchersReportScreen> createState() => _CompanyVouchersReportScreenState();
}

class _CompanyVouchersReportScreenState extends ConsumerState<CompanyVouchersReportScreen>
    with AutomaticKeepAliveClientMixin {
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  @override
  bool get wantKeepAlive => true;

  String? _selectedEventId;
  String? _selectedBranch;
  double? _selectedVoucherDenomFilter;
  int _distributionViewMode = 0; // 0 = M3 List-Detail Inspector, 1 = Matrix Table
  String? _inspectedBranchName;
  final TextEditingController _branchSearchController = TextEditingController();

  // Golden Standard: Static Persistent In-Memory Caches for 0ms instant render across tab switches
  static final Map<String, List<EventModel>> _persistentEventsCache = {};
  static final Map<String, List<QueryDocumentSnapshot>> _persistentGiftsCache = {};
  static final Map<String, List<QueryDocumentSnapshot>> _persistentTxDocsCache = {};
  static final Map<String, List<BranchModel>> _persistentBranchesCache = {};

  // In-memory cache for instant 0ms tab switching
  List<EventModel>? _cachedAllEvents;
  List<QueryDocumentSnapshot>? _cachedGiftsDocs;
  List<QueryDocumentSnapshot>? _cachedTxDocs;
  List<BranchModel>? _cachedDbBranches;

  // Memoized stream lifecycle outside build()
  String? _lastStreamsKey;
  Stream<QuerySnapshot>? _eventsStream;
  Stream<QuerySnapshot>? _giftsStream;
  Stream<QuerySnapshot>? _txStream;
  Stream<QuerySnapshot>? _branchesStream;

  void _ensureStreams(FirebaseFirestore db, String effectiveSlug, {bool force = false}) {
    final streamKey = effectiveSlug;

    if (_lastStreamsKey != streamKey || force || _txStream == null) {
      _lastStreamsKey = streamKey;

      if (_eventsStream == null || force) {
        Query eventsQuery = db.collection('events');
        if (effectiveSlug.isNotEmpty) {
          eventsQuery = eventsQuery.where('companySlug', isEqualTo: effectiveSlug);
        }
        _eventsStream = eventsQuery.snapshots();
      }

      if (_giftsStream == null || force) {
        Query giftsQuery = db.collection('company_gifts');
        if (effectiveSlug.isNotEmpty) {
          giftsQuery = giftsQuery.where('companySlug', isEqualTo: effectiveSlug);
        }
        _giftsStream = giftsQuery.snapshots();
      }

      if (_txStream == null || force) {
        Query txQuery = db.collection('receipts_transactions');
        if (effectiveSlug.isNotEmpty) {
          txQuery = txQuery.where('companySlug', isEqualTo: effectiveSlug);
        }
        _txStream = txQuery.snapshots();
      }

      if (_branchesStream == null || force) {
        _branchesStream = db.collection('branches').snapshots();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedEventId = (widget.lockedEventId != null && widget.lockedEventId!.isNotEmpty)
        ? widget.lockedEventId
        : widget.initialEventId;
  }

  @override
  void didUpdateWidget(covariant CompanyVouchersReportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final effectiveEventId = (widget.lockedEventId != null && widget.lockedEventId!.isNotEmpty)
        ? widget.lockedEventId
        : widget.initialEventId;
    final oldEffectiveEventId = (oldWidget.lockedEventId != null && oldWidget.lockedEventId!.isNotEmpty)
        ? oldWidget.lockedEventId
        : oldWidget.initialEventId;
    if (effectiveEventId != oldEffectiveEventId && effectiveEventId != null) {
      setState(() {
        _selectedEventId = effectiveEventId;
      });
    }
  }

  @override
  void dispose() {
    _branchSearchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Helper Math & Formatting Functions
  // ---------------------------------------------------------------------------
  static String _formatCount(int count) {
    return intl.NumberFormat('#,##0').format(count);
  }

  static String _formatMoney(double amount, {required bool isAr, String currencySymbol = 'ج.م'}) {
    final formatted = intl.NumberFormat('#,##0.##').format(amount);
    return isAr ? '$formatted $currencySymbol' : '$formatted $currencySymbol';
  }

  static bool _isVoucherText(String text) {
    final clean = text.toLowerCase().trim();
    return clean.contains('قسيمة') ||
        clean.contains('قسائم') ||
        clean.contains('فوتشر') ||
        clean.contains('voucher') ||
        clean.contains('كوبون') ||
        clean.contains('coupon') ||
        clean.contains('مشتريات') ||
        clean.contains('shopping');
  }

  static double _extractDenomination(String giftName, double rawUnitValue, {String? giftType}) {
    if (rawUnitValue > 0) return rawUnitValue;

    final regex = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ج\.م|egp|جنيه|ريال|درهم|جم)?', caseSensitive: false);
    final match = regex.firstMatch(giftName);
    if (match != null) {
      final parsed = double.tryParse(match.group(1) ?? '');
      if (parsed != null && parsed > 0) return parsed;
    }
    return 0.0;
  }

  static CompanyGiftModel? _findMatchingMasterGift(AllocatedPrize prize, List<CompanyGiftModel> masterGifts) {
    if (masterGifts.isEmpty) return null;

    if (prize.giftId.isNotEmpty) {
      final byId = masterGifts.where((g) => g.id == prize.giftId);
      if (byId.isNotEmpty) return byId.first;
    }

    final pName = prize.name.trim().toLowerCase();
    final byName = masterGifts.where((g) => g.giftName.trim().toLowerCase() == pName);
    if (byName.isNotEmpty) return byName.first;

    final pType = prize.giftType.trim().toLowerCase();
    final pUnitVal = prize.unitValue;
    if (pType == 'voucher' || prize.isVoucher) {
      final byVal = masterGifts.where((g) =>
          (g.giftType == 'voucher' || g.isVoucher) &&
          ((g.unitValue - pUnitVal).abs() < 0.01 || _extractDenomination(g.giftName, g.unitValue) == pUnitVal));
      if (byVal.isNotEmpty) return byVal.first;
    }

    return null;
  }


  static AggregatedVoucherMetrics _calculateVoucherMetrics({
    required List<EventModel> filteredEvents,
    required List<CompanyGiftModel> masterGifts,
    required String? selectedBranch,
    required int Function(
      String giftName,
      int rawClaimed, [
      String? branchName,
      String? branchId,
      String? eventId,
      double? unitValue,
      bool? isVoucher,
    ]) getReconciledClaimed,
    required bool isAr,
  }) {
    final Map<double, VoucherDenominationStats> denominationMap = {};
    final Map<String, Map<double, VoucherDenominationStats>> branchDenominationsMap = {};
    final Map<String, int> branchTotalVoucherUnits = {};
    final Map<String, double> branchTotalVoucherBudget = {};
    final Map<String, int> branchClaimedVoucherUnits = {};
    final Map<String, int> branchRemainingVoucherUnits = {};

    int totalUnitsAllocated = 0;
    int totalUnitsClaimed = 0;
    int totalUnitsRemaining = 0;
    double totalBudgetEgp = 0.0;
    double totalClaimedEgp = 0.0;
    double totalRemainingEgp = 0.0;

    // 1. Discover all voucher denominations and master stock from master inventory
    for (final mg in masterGifts) {
      final isMgVoucher = mg.giftType == 'voucher' || mg.isVoucher || _isVoucherText(mg.giftName);
      if (isMgVoucher) {
        final d = _extractDenomination(mg.giftName, mg.unitValue, giftType: mg.giftType);
        if (d > 0) {
          final stats = denominationMap.putIfAbsent(
            d,
            () => VoucherDenominationStats(
              denomination: d,
              label: d == d.roundToDouble() ? '${d.toInt()} ج.م' : '$d ج.م',
            ),
          );
          stats.masterTotalCount += mg.totalQuantity;
          stats.masterAvailableCount += mg.availableQuantity;
        }
      }
    }

    // 2. Aggregate allocations, claims, remaining, and branch allocations from events
    for (final event in filteredEvents) {
      final hasBranchAllocations = event.allocatedPrizes.any((p) =>
          p.branchName.trim().isNotEmpty || p.branchId.trim().isNotEmpty);

      for (final prize in event.allocatedPrizes) {
        final matchingMasterGift = _findMatchingMasterGift(prize, masterGifts);
        if (masterGifts.isNotEmpty && matchingMasterGift == null) {
          continue;
        }

        final isVoucher = (matchingMasterGift?.giftType == 'voucher') ||
            (prize.giftType == 'voucher') ||
            (matchingMasterGift?.isVoucher == true) ||
            prize.isVoucher ||
            _isVoucherText(prize.name) ||
            (matchingMasterGift != null && _isVoucherText(matchingMasterGift.giftName));

        if (!isVoucher) continue;

        // If the campaign has branch-specific allocations, skip ghost/unassigned allocations
        // that have no branchName or branchId so they don't artificially inflate total cards
        if (hasBranchAllocations && prize.branchName.trim().isEmpty && prize.branchId.trim().isEmpty) {
          continue;
        }

        final rawVal = (matchingMasterGift?.giftType == 'voucher' ? matchingMasterGift?.unitValue : null) ??
            (prize.giftType == 'voucher' ? prize.unitValue : 0.0);
        final denom = _extractDenomination(
          matchingMasterGift?.giftName ?? prize.name,
          rawVal,
          giftType: matchingMasterGift?.giftType ?? prize.giftType,
        );

        if (denom <= 0) continue;

        final branchKey = prize.branchName.isNotEmpty
            ? prize.branchName.trim()
            : (prize.branchId.isNotEmpty ? prize.branchId : (isAr ? 'الفرع الرئيسي' : 'Main Branch'));

        final branchAllocated = prize.allocatedQuantity;
        final rawBranchRemaining = prize.remainingQuantity.clamp(0, prize.allocatedQuantity);
        final rawBranchClaimed = (prize.allocatedQuantity - rawBranchRemaining).clamp(0, prize.allocatedQuantity);
        final txBranchClaimed = getReconciledClaimed(
          matchingMasterGift?.giftName ?? prize.name,
          rawBranchClaimed,
          branchKey,
          prize.branchId,
          event.id,
          denom,
          true,
        );
        final branchClaimed = txBranchClaimed > rawBranchClaimed ? txBranchClaimed : rawBranchClaimed;
        final branchRemaining = (prize.allocatedQuantity - branchClaimed).clamp(0, prize.allocatedQuantity);

        if (branchKey.isNotEmpty) {
          branchTotalVoucherUnits[branchKey] = (branchTotalVoucherUnits[branchKey] ?? 0) + branchAllocated;
          branchTotalVoucherBudget[branchKey] = (branchTotalVoucherBudget[branchKey] ?? 0.0) + (branchAllocated * denom);
          branchClaimedVoucherUnits[branchKey] = (branchClaimedVoucherUnits[branchKey] ?? 0) + branchClaimed;
          branchRemainingVoucherUnits[branchKey] = (branchRemainingVoucherUnits[branchKey] ?? 0) + branchRemaining;

          branchDenominationsMap.putIfAbsent(branchKey, () => {});
          final branchDenomStats = branchDenominationsMap[branchKey]!.putIfAbsent(
            denom,
            () => VoucherDenominationStats(
              denomination: denom,
              label: denom == denom.roundToDouble() ? '${denom.toInt()} ج.م' : '$denom ج.م',
            ),
          );
          branchDenomStats.allocatedCount += branchAllocated;
          branchDenomStats.claimedCount += branchClaimed;
          branchDenomStats.remainingCount += branchRemaining;
        }

        final denomStats = denominationMap.putIfAbsent(
          denom,
          () => VoucherDenominationStats(
            denomination: denom,
            label: denom == denom.roundToDouble() ? '${denom.toInt()} ج.م' : '$denom ج.م',
          ),
        );
        denomStats.allocatedCount += branchAllocated;
        denomStats.claimedCount += branchClaimed;
        denomStats.remainingCount += branchRemaining;
        if (branchKey.isNotEmpty) {
          denomStats.branchAllocatedMap[branchKey] = (denomStats.branchAllocatedMap[branchKey] ?? 0) + branchAllocated;
          denomStats.branchClaimedMap[branchKey] = (denomStats.branchClaimedMap[branchKey] ?? 0) + branchClaimed;
          denomStats.branchRemainingMap[branchKey] = (denomStats.branchRemainingMap[branchKey] ?? 0) + branchRemaining;
        }

        if (selectedBranch != null && selectedBranch.isNotEmpty) {
          if (prize.branchName.trim() != selectedBranch && prize.branchId.trim() != selectedBranch) {
            continue;
          }
        }

        totalUnitsAllocated += branchAllocated;
        totalUnitsClaimed += branchClaimed;
        totalUnitsRemaining += branchRemaining;

        totalBudgetEgp += (branchAllocated * denom);
        totalClaimedEgp += (branchClaimed * denom);
        totalRemainingEgp += (branchRemaining * denom);
      }
    }

    final sortedDenominations = denominationMap.values.toList()
      ..sort((a, b) => a.denomination.compareTo(b.denomination));

    return AggregatedVoucherMetrics(
      totalUnitsAllocated: totalUnitsAllocated,
      totalUnitsClaimed: totalUnitsClaimed,
      totalUnitsRemaining: totalUnitsRemaining,
      totalBudgetEgp: totalBudgetEgp,
      totalClaimedEgp: totalClaimedEgp,
      totalRemainingEgp: totalRemainingEgp,
      denominations: sortedDenominations,
      branchDenominationsMap: branchDenominationsMap,
      branchTotalVoucherUnits: branchTotalVoucherUnits,
      branchTotalVoucherBudget: branchTotalVoucherBudget,
      branchClaimedVoucherUnits: branchClaimedVoucherUnits,
      branchRemainingVoucherUnits: branchRemainingVoucherUnits,
    );
  }

  // ---------------------------------------------------------------------------
  // Build Main Screen
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final currentLocale = ref.watch(localeProvider);
    final isAr = currentLocale.languageCode == 'ar';
    final isHi = currentLocale.languageCode == 'hi';
    final strings = AppStrings.fromLocale(currentLocale.languageCode);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    FirebaseFirestore? firestore;
    try {
      firestore = ref.watch(firestoreProvider);
    } catch (_) {
      firestore = null;
    }

    if (firestore == null) {
      return _buildVouchersView(
        context: context,
        colorScheme: colorScheme,
        textTheme: textTheme,
        strings: strings,
        isAr: isAr,
        isHi: isHi,
        companyEvents: const [],
        masterGifts: const [],
        txDocs: const [],
        dbBranches: const [],
      );
    }

    final db = firestore;
    final effectiveSlug = widget.lockedCompanySlug?.trim().toLowerCase() ?? '';
    _ensureStreams(db, effectiveSlug);

    return StreamBuilder<QuerySnapshot>(
      stream: _eventsStream,
      builder: (context, eventsSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: _giftsStream,
          builder: (context, giftsSnapshot) {
            return StreamBuilder<QuerySnapshot>(
              stream: _txStream,
              builder: (context, txSnapshot) {
                return StreamBuilder<QuerySnapshot>(
                  stream: _branchesStream,
                  builder: (context, branchesSnapshot) {
                    if (eventsSnapshot.hasData && eventsSnapshot.data!.docs.isNotEmpty) {
                      final mapped = eventsSnapshot.data!.docs.map((d) {
                        try {
                          return EventModel.fromFirestore(d);
                        } catch (_) {
                          return null;
                        }
                      }).whereType<EventModel>().toList();
                      if (mapped.isNotEmpty) {
                        _persistentEventsCache[effectiveSlug] = mapped;
                        _cachedAllEvents = mapped;
                      }
                    }

                    final allEvents = _persistentEventsCache[effectiveSlug] ?? _cachedAllEvents ?? [];

                    if (eventsSnapshot.connectionState == ConnectionState.waiting &&
                        !eventsSnapshot.hasData &&
                        allEvents.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    // Resolve Company Scoping
                    final effectiveCompanyName = widget.lockedCompanyName?.trim() ??
                        (effectiveSlug.isNotEmpty ? SlugUtils.formatSlugToName(effectiveSlug) : '');

                    final isCampaignLocked = widget.lockedEventId != null && widget.lockedEventId!.isNotEmpty;
                    if (isCampaignLocked && _selectedEventId != widget.lockedEventId) {
                      _selectedEventId = widget.lockedEventId;
                    }

                    final companyEvents = allEvents.where((e) {
                      if (isCampaignLocked && e.id != widget.lockedEventId) return false;
                      if (effectiveSlug.isEmpty && effectiveCompanyName.isEmpty) return true;
                      final matchSlug = effectiveSlug.isNotEmpty &&
                          e.companySlug.trim().toLowerCase() == effectiveSlug;
                      final matchName = effectiveCompanyName.isNotEmpty &&
                          e.targetCompany.trim().toLowerCase() == effectiveCompanyName.toLowerCase();
                      return matchSlug || matchName;
                    }).toList();

                    if (giftsSnapshot.hasData && giftsSnapshot.data!.docs.isNotEmpty) {
                      _persistentGiftsCache[effectiveSlug] = giftsSnapshot.data!.docs;
                      _cachedGiftsDocs = giftsSnapshot.data!.docs;
                    }
                    final giftDocs = _persistentGiftsCache[effectiveSlug] ?? _cachedGiftsDocs ?? giftsSnapshot.data?.docs ?? [];

                    final masterGifts = giftDocs.map((d) {
                          try {
                            return CompanyGiftModel.fromFirestore(d);
                          } catch (_) {
                            return null;
                          }
                        }).whereType<CompanyGiftModel>().toList();

                    if (txSnapshot.hasData && txSnapshot.data!.docs.isNotEmpty) {
                      _persistentTxDocsCache[effectiveSlug] = txSnapshot.data!.docs;
                      _cachedTxDocs = txSnapshot.data!.docs;
                    }
                    final rawTxDocs = _persistentTxDocsCache[effectiveSlug] ?? _cachedTxDocs ?? txSnapshot.data?.docs ?? [];
                    final txDocs = isCampaignLocked
                        ? rawTxDocs.where((d) {
                            final data = d.data() as Map<String, dynamic>?;
                            return data?['campaignId']?.toString() == widget.lockedEventId;
                          }).toList()
                        : rawTxDocs;

                    if (branchesSnapshot.hasData && branchesSnapshot.data!.docs.isNotEmpty) {
                      final mapped = branchesSnapshot.data!.docs.map((d) {
                        try {
                          return BranchModel.fromFirestore(d);
                        } catch (_) {
                          return null;
                        }
                      }).whereType<BranchModel>().toList();
                      if (mapped.isNotEmpty) {
                        _persistentBranchesCache['all'] = mapped;
                        _cachedDbBranches = mapped;
                      }
                    }
                    final dbBranches = _persistentBranchesCache['all'] ?? _cachedDbBranches ?? [];

                    return _buildVouchersView(
                      context: context,
                      colorScheme: colorScheme,
                      textTheme: textTheme,
                      strings: strings,
                      isAr: isAr,
                      isHi: isHi,
                      companyEvents: companyEvents,
                      masterGifts: masterGifts,
                      txDocs: txDocs,
                      dbBranches: dbBranches,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildVouchersView({
    required BuildContext context,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required List<EventModel> companyEvents,
    required List<CompanyGiftModel> masterGifts,
    required List<QueryDocumentSnapshot> txDocs,
    required List<BranchModel> dbBranches,
  }) {
    final effectiveSlug = widget.lockedCompanySlug?.trim().toLowerCase() ?? '';
    final effectiveCompanyName = widget.lockedCompanyName?.trim() ??
        (effectiveSlug.isNotEmpty ? SlugUtils.formatSlugToName(effectiveSlug) : '');

    final filteredEvents = companyEvents.where((e) {
      if (_selectedEventId == null || _selectedEventId!.isEmpty) return true;
      return e.id == _selectedEventId;
    }).toList();

    // Extract all distinct branches across the company's events
    final Set<String> distinctBranches = {};
    for (final ev in companyEvents) {
      for (final p in ev.allocatedPrizes) {
        if (p.branchName.trim().isNotEmpty) {
          distinctBranches.add(p.branchName.trim());
        }
      }
      for (final b in ev.branchNames) {
        if (b.trim().isNotEmpty) {
          distinctBranches.add(b.trim());
        }
      }
    }

    bool matchesBranchName(String b1, String b2) {
      if (b1 == b2) return true;
      final c1 = b1.replaceAll(RegExp(r'\s*\([^)]*\)'), '').replaceAll(RegExp(r'فرع\s+'), '').trim().toLowerCase();
      final c2 = b2.replaceAll(RegExp(r'\s*\([^)]*\)'), '').replaceAll(RegExp(r'فرع\s+'), '').trim().toLowerCase();
      return c1 == c2 || b1.toLowerCase().contains(c2) || b2.toLowerCase().contains(c1);
    }

    int getReconciledClaimed(
      String giftName,
      int rawClaimed, [
      String? branchName,
      String? branchId,
      String? eventId,
      double? unitValue,
      bool? isVoucher,
    ]) {
      if (txDocs.isEmpty) return rawClaimed;
      int count = 0;
      final cleanTargetGiftName = giftName.trim().toLowerCase();
      final targetDenom = (unitValue != null && unitValue > 0) ? unitValue : _extractDenomination(giftName, 0.0);

      for (final doc in txDocs) {
        final data = doc.data() as Map<String, dynamic>;

        // Event Scoping
        if (eventId != null && eventId.isNotEmpty && eventId != 'all' && eventId != 'ALL') {
          final txEventId = (data['campaignId'] ?? data['event_id'] ?? data['eventId'] ?? '').toString();
          if (txEventId.isNotEmpty && txEventId != eventId) continue;
        }

        // Branch Scoping
        if (branchName != null && branchName.isNotEmpty && branchName != (isAr ? 'كافة الفروع' : 'All Branches')) {
          final txBranch = (data['canonical_branch'] ?? data['branch_detected'] ?? data['branchName'] ?? data['branch'] ?? '').toString().trim();
          if (txBranch.isNotEmpty && !matchesBranchName(branchName, txBranch)) {
            continue;
          }
        }

        // 1. claimed_gifts
        final claimedGifts = (data['claimed_gifts'] as List?) ?? [];
        if (claimedGifts.isNotEmpty) {
          for (final cg in claimedGifts) {
            if (cg is Map) {
              final cgMap = Map<String, dynamic>.from(cg);
              final gName = (cgMap['giftName'] ?? cgMap['name'] ?? '').toString().trim().toLowerCase();
              final gVal = (cgMap['unitValue'] ?? cgMap['unit_value'] as num?)?.toDouble() ?? _extractDenomination(gName, 0.0);
              final isV = cgMap['isVoucher'] == true || cgMap['is_voucher'] == true || _isVoucherText(gName);

              if (isV && (gVal == targetDenom || gName == cleanTargetGiftName || gName.contains(cleanTargetGiftName))) {
                count += ((cgMap['quantity'] ?? cgMap['count'] ?? 1) as num).toInt();
              }
            }
          }
        } else {
          // 2. linkedGifts
          final linked = (data['linkedGifts'] ?? data['linked_gifts'] as List?) ?? [];
          if (linked.isNotEmpty) {
            for (final lg in linked) {
              if (lg is Map) {
                final lgMap = Map<String, dynamic>.from(lg);
                final gName = (lgMap['giftName'] ?? lgMap['name'] ?? '').toString().trim().toLowerCase();
                final gVal = (lgMap['unitValue'] as num?)?.toDouble() ?? _extractDenomination(gName, 0.0);
                final isV = lgMap['isVoucher'] == true || lgMap['giftType'] == 'voucher' || _isVoucherText(gName);
                if (isV && (gVal == targetDenom || gName == cleanTargetGiftName || gName.contains(cleanTargetGiftName))) {
                  count += ((lgMap['quantity'] ?? 1) as num).toInt();
                }
              }
            }
          }

          // 3. prizes_won (List)
          final prizesWon = (data['prizes_won'] as List?) ?? [];
          for (final p in prizesWon) {
            final pName = p.toString().trim().toLowerCase();
            final pVal = _extractDenomination(pName, 0.0);
            if (_isVoucherText(pName) && (pVal == targetDenom || pName == cleanTargetGiftName || pName.contains(cleanTargetGiftName))) {
              count += 1;
            }
          }

          // 4. prize_won (String)
          final prizeWon = (data['prize_won'] ?? data['prizeName'] ?? '').toString().trim().toLowerCase();
          if (prizeWon.isNotEmpty && prizeWon != 'null' && prizeWon != 'لم يفز') {
            final pVal = _extractDenomination(prizeWon, 0.0);
            if (_isVoucherText(prizeWon) && (pVal == targetDenom || prizeWon == cleanTargetGiftName || prizeWon.contains(cleanTargetGiftName))) {
              count += 1;
            }
          }

          // 5. voucher_value
          final vVal = (data['voucher_value'] ?? data['voucherValue'] as num?)?.toDouble() ?? 0.0;
          if (vVal > 0 && vVal == targetDenom && count == 0) {
            count += 1;
          }
        }
      }
      return count > rawClaimed ? count : rawClaimed;
    }

    final voucherMetrics = _calculateVoucherMetrics(
      filteredEvents: filteredEvents,
      masterGifts: masterGifts,
      selectedBranch: _selectedBranch,
      getReconciledClaimed: getReconciledClaimed,
      isAr: isAr,
    );

    final isMobile = MediaQuery.of(context).size.width < 768;

    final content = Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          isMobile ? 12 : 20,
          isMobile ? 12 : 20,
          isMobile ? 12 : 20,
          isMobile ? 96 : 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Executive Top Header Title (Clean, Title only, No Subtitle)
            _buildHeaderTitle(
              colorScheme: colorScheme,
              strings: strings,
              isAr: isAr,
              branchCount: distinctBranches.length,
            ),
            const SizedBox(height: 14),

            // 2. Hero KPI Grid (2x2 on Mobile & Tablet, 4-across on Desktop, Pure Theme Colors)
            _buildVoucherKpiGrid(
              colorScheme: colorScheme,
              strings: strings,
              isAr: isAr,
              isHi: isHi,
              isMobile: isMobile,
              voucherMetrics: voucherMetrics,
            ),
            const SizedBox(height: 14),

            // 3. Dropdowns (Campaign & Branch) + Connected Action Buttons Group ("كشف الفروع" | "إكسل")
            _buildDropdownFiltersCard(
              context: context,
              colorScheme: colorScheme,
              strings: strings,
              isAr: isAr,
              isHi: isHi,
              isMobile: isMobile,
              companyEvents: companyEvents,
              distinctBranches: distinctBranches.toList(),
              voucherMetrics: voucherMetrics,
              txDocs: txDocs,
            ),
            const SizedBox(height: 14),

            // 4. Denominations Button Group (كافة الفئات، فئة 25، فئة 50...)
            if (voucherMetrics.denominations.isNotEmpty) ...[
              _buildDenominationButtonGroup(
                colorScheme: colorScheme,
                strings: strings,
                isAr: isAr,
                voucherMetrics: voucherMetrics,
              ),
              const SizedBox(height: 16),
            ],

            // 5. On-page Branch Allocation Matrix Table & Breakdown
            _buildBranchDistributionMatrixCard(
              colorScheme: colorScheme,
              strings: strings,
              isAr: isAr,
              isHi: isHi,
              isMobile: isMobile,
              voucherMetrics: voucherMetrics,
              distinctBranches: distinctBranches.toList(),
              dbBranches: dbBranches,
            ),
          ],
        ),
      ),
    );

    if (widget.isEmbedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: SwitchPointHeader(
        subtitle: '${effectiveCompanyName.isNotEmpty ? effectiveCompanyName : strings.companyScopeBanner} • ${strings.vouchersNavTitle}',
      ),
      body: content,
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Executive Top Header Title (Clean, Title only, No Subtitle)
  // ---------------------------------------------------------------------------
  Widget _buildHeaderTitle({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required int branchCount,
  }) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Icon(
              Icons.confirmation_number_rounded,
              color: colorScheme.primary,
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  strings.voucherIntelligenceTitle,
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$branchCount ${isAr ? 'فرع معتمد' : 'Branches'}',
                  style: GoogleFonts.cairo(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Dropdown Filters (Campaign & Branch) & Connected Action Buttons Group
  // ---------------------------------------------------------------------------
  Widget _buildDropdownFiltersCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required List<EventModel> companyEvents,
    required List<String> distinctBranches,
    required AggregatedVoucherMetrics voucherMetrics,
    required List<QueryDocumentSnapshot> txDocs,
  }) {
    final effectiveEventId = companyEvents.any((e) => e.id == _selectedEventId) ? _selectedEventId : null;
    final effectiveBranch = distinctBranches.contains(_selectedBranch) ? _selectedBranch : null;

    final campaignDropdown = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: effectiveEventId,
          isExpanded: true,
          hint: Text(
            isAr ? 'جميع الفعاليات والحملات' : 'All Events & Campaigns',
            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                isAr ? '🌟 جميع فعاليات الشركة' : '🌟 All Company Campaigns',
                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            ...companyEvents.map((e) => DropdownMenuItem<String?>(
                  value: e.id,
                  child: Text(
                    e.eventName,
                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
          ],
          onChanged: (val) => setState(() => _selectedEventId = val),
        ),
      ),
    );

    final branchDropdown = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: effectiveBranch,
          isExpanded: true,
          hint: Text(
            isAr ? 'كافة الفروع والمنافذ' : 'All Branches & Outlets',
            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                isAr ? '🏬 كافة الفروع والمنافذ' : '🏬 All Outlets',
                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            ...distinctBranches.map((b) => DropdownMenuItem<String?>(
                  value: b,
                  child: Text(
                    b,
                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
          ],
          onChanged: (val) => setState(() => _selectedBranch = val),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isMobile) ...[
            campaignDropdown,
            const SizedBox(height: 8),
            branchDropdown,
          ] else ...[
            Row(
              children: [
                Expanded(child: campaignDropdown),
                const SizedBox(width: 10),
                Expanded(child: branchDropdown),
              ],
            ),
          ],
          const SizedBox(height: 10),
          _buildActionButtonsGroup(
            context: context,
            colorScheme: colorScheme,
            strings: strings,
            isAr: isAr,
            isHi: isHi,
            isMobile: isMobile,
            voucherMetrics: voucherMetrics,
            distinctBranches: distinctBranches,
            txDocs: txDocs,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtonsGroup({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required AggregatedVoucherMetrics voucherMetrics,
    required List<String> distinctBranches,
    required List<QueryDocumentSnapshot> txDocs,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // 1. "كشف الفروع"
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _showBranchVoucherMatrixDialog(
                      context: context,
                      colorScheme: colorScheme,
                      strings: strings,
                      isAr: isAr,
                      isHi: isHi,
                      isMobile: isMobile,
                      voucherMetrics: voucherMetrics,
                      distinctBranches: distinctBranches,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.storefront_rounded, size: 18, color: colorScheme.primary),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              isAr ? 'كشف الفروع' : (isHi ? 'शाखा सूची' : 'Branches Matrix'),
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
              // 2. "إكسل"
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _exportVouchersExcel(
                      context: context,
                      voucherMetrics: voucherMetrics,
                      distinctBranches: distinctBranches,
                      txDocs: txDocs,
                      isAr: isAr,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.table_chart_rounded, size: 18, color: colorScheme.primary),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              isAr ? 'إكسل' : 'Excel',
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Denominations Button Group (M3 Connected Button Group with Pure Theme Colors)
  // ---------------------------------------------------------------------------
  Widget _buildDenominationButtonGroup({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required AggregatedVoucherMetrics voucherMetrics,
  }) {
    final allCount = voucherMetrics.totalUnitsAllocated;
    final double selectedVal = _selectedVoucherDenomFilter ?? -1.0;

    final segments = <M3ButtonSegment<double>>[
      M3ButtonSegment<double>(
        value: -1.0,
        icon: Icons.all_inclusive_rounded,
        label: isAr ? 'كافة الفئات (إجمالي عام)' : 'All Denominations',
        badgeText: _formatCount(allCount),
      ),
      ...voucherMetrics.denominations.map((denom) {
        final count = denom.allocatedCount > 0 ? denom.allocatedCount : denom.masterTotalCount;
        return M3ButtonSegment<double>(
          value: denom.denomination,
          icon: Icons.confirmation_number_rounded,
          label: 'فئة ${denom.label}',
          badgeText: _formatCount(count),
        );
      }),
    ];

    return M3ConnectedButtonGroup<double>(
      segments: segments,
      selectedValue: selectedVal,
      onSelected: (val) {
        setState(() {
          _selectedVoucherDenomFilter = (val == -1.0 || val == _selectedVoucherDenomFilter) ? null : val;
        });
      },
      showCheckmark: false,
      height: 40,
      borderRadius: 12,
    );
  }

  // ---------------------------------------------------------------------------
  // 4. Hero KPI Grid (2x2 on Mobile & Tablet, 4 on Desktop, Pure Theme Colors)
  // ---------------------------------------------------------------------------
  Widget _buildVoucherKpiGrid({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required AggregatedVoucherMetrics voucherMetrics,
  }) {
    final selectedDenom = _selectedVoucherDenomFilter != null
        ? voucherMetrics.denominations.where((d) => d.denomination == _selectedVoucherDenomFilter).firstOrNull
        : null;

    final totalAllocated = selectedDenom != null
        ? selectedDenom.allocatedCount
        : voucherMetrics.totalUnitsAllocated;
    final totalBudget = selectedDenom != null
        ? selectedDenom.totalBudget
        : voucherMetrics.totalBudgetEgp;
    final totalClaimedCount = selectedDenom != null
        ? selectedDenom.claimedCount
        : voucherMetrics.totalUnitsClaimed;
    final totalClaimedVal = selectedDenom != null
        ? selectedDenom.claimedValue
        : voucherMetrics.totalClaimedEgp;
    final totalRemainingCount = selectedDenom != null
        ? selectedDenom.remainingCount
        : voucherMetrics.totalUnitsRemaining;
    final totalRemainingVal = selectedDenom != null
        ? selectedDenom.remainingValue
        : voucherMetrics.totalRemainingEgp;
    final depletionRate = selectedDenom != null
        ? selectedDenom.depletionRate
        : voucherMetrics.depletionRate;

    final denomsText = selectedDenom != null
        ? (isAr ? 'القيمة الاسمية: ${selectedDenom.label}' : 'Face value: ${selectedDenom.label}')
        : (voucherMetrics.denominations.isEmpty
            ? (isAr ? 'لا توجد فئات' : 'No denominations')
            : voucherMetrics.denominations
                .map((d) => '${d.label} (${_formatCount(d.allocatedCount > 0 ? d.allocatedCount : d.masterTotalCount)})')
                .join(' • '));

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final bool isDesktop = width >= 840;
        final bool isMobileWidth = width < 600;

        // 2x2 grid on mobile & tablet, 4 in a row on desktop
        final int crossAxisCount = isDesktop ? 4 : 2;
        final double childAspectRatio = isDesktop ? 1.85 : (isMobileWidth ? 1.30 : 1.75);

        final cards = [
          _buildStatCard(
            colorScheme: colorScheme,
            icon: Icons.confirmation_number_rounded,
            iconColor: colorScheme.primary,
            title: isAr ? 'إجمالي قسائم المشتريات' : strings.totalVouchersAllocated,
            value: _formatCount(totalAllocated),
            badgeText: selectedDenom != null
                ? 'فئة ${selectedDenom.label}'
                : (voucherMetrics.denominations.length > 1
                    ? '${voucherMetrics.denominations.length} ${strings.activeDenominationsCount}'
                    : (voucherMetrics.denominations.isNotEmpty
                        ? 'فئة ${voucherMetrics.denominations.first.label}'
                        : (isAr ? 'قسائم مشتريات' : 'Vouchers'))),
            badgeTextColor: colorScheme.primary,
            subtitle: denomsText,
            tooltip: isAr ? 'إجمالي عدد قسائم وفواتشرات المشتريات المعتمدة للحملة' : 'Total purchase vouchers allocated',
            isMobile: !isDesktop,
          ),
          _buildStatCard(
            colorScheme: colorScheme,
            icon: Icons.account_balance_wallet_rounded,
            iconColor: colorScheme.secondary,
            title: isAr ? 'الميزانية المرصودة الإجمالية' : strings.totalVouchersBudget,
            value: _formatMoney(totalBudget, isAr: isAr),
            badgeText: isAr ? 'الميزانية المعتمدة' : 'Allocated Budget',
            badgeTextColor: colorScheme.secondary,
            subtitle: isAr ? 'التكلفة الإجمالية لكافة القسائم المعتمدة' : 'Total voucher financial backing',
            tooltip: isAr ? 'القيمة المالية الإجمالية لقسائم الشراء المعتمدة' : 'Total allocated voucher budget',
            isMobile: !isDesktop,
          ),
          _buildStatCard(
            colorScheme: colorScheme,
            icon: Icons.shopping_bag_rounded,
            iconColor: colorScheme.tertiary,
            title: isAr ? 'قيمة القسائم المصروفة' : strings.claimedVouchersValue,
            value: _formatMoney(totalClaimedVal, isAr: isAr),
            badgeText: '${(depletionRate * 100).toStringAsFixed(0)}% ${strings.depletionRateLabel}',
            badgeTextColor: colorScheme.tertiary,
            subtitle: '${_formatCount(totalClaimedCount)} ${isAr ? 'قسيمة تم تسليمها للفائزين' : 'claimed vouchers'}',
            tooltip: isAr ? 'القيمة المالية الإجمالية للقسائم المسلمة للمستهلكين' : 'Total disbursed voucher monetary value',
            isMobile: !isDesktop,
          ),
          _buildStatCard(
            colorScheme: colorScheme,
            icon: Icons.savings_rounded,
            iconColor: totalRemainingCount <= 0 ? colorScheme.error : colorScheme.primary,
            title: isAr ? 'الرصيد المالي المتبقي' : strings.remainingVouchersValue,
            value: _formatMoney(totalRemainingVal, isAr: isAr),
            badgeText: totalRemainingCount <= 0
                ? strings.stockDepletedBadge
                : (totalRemainingCount < 50 ? strings.stockLowBadge : strings.stockHealthyBadge),
            badgeTextColor: totalRemainingCount <= 0 ? colorScheme.error : colorScheme.primary,
            subtitle: '${_formatCount(totalRemainingCount)} ${isAr ? 'قسيمة جاهزة ومتاحة للصرف' : 'ready for redemption'}',
            tooltip: isAr ? 'القيمة المالية المتبقية من قسائم الشراء المتاحة للصرف' : 'Remaining voucher financial budget in stock',
            isMobile: !isDesktop,
          ),
        ];

        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: isMobileWidth ? 10 : 12,
          crossAxisSpacing: isMobileWidth ? 10 : 12,
          childAspectRatio: childAspectRatio,
          children: cards,
        );
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
    required Color badgeTextColor,
    required String subtitle,
    required String tooltip,
    bool isMobile = false,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 10 : 14,
          vertical: isMobile ? 10 : 12,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.03),
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
                  padding: EdgeInsets.all(isMobile ? 6 : 7),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: isMobile ? 16 : 18, color: iconColor),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badgeText,
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 9 : 10,
                        fontWeight: FontWeight.bold,
                        color: badgeTextColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 16 : 18,
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
                fontSize: isMobile ? 9 : 9.5,
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

  // ---------------------------------------------------------------------------
  // 4. On-Page Branch Distribution Matrix Card & Interactive Responsive Table
  // ---------------------------------------------------------------------------
  Widget _buildBranchDistributionMatrixCard({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required AggregatedVoucherMetrics voucherMetrics,
    required List<String> distinctBranches,
    List<BranchModel> dbBranches = const [],
  }) {
    final sortedBranches = distinctBranches.where((b) => b.trim().isNotEmpty).toList()..sort();
    final denoms = voucherMetrics.denominations;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with Icon, Title & Subtitle
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.table_chart_rounded, size: 20, color: colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.voucherMatrixDialogTitle,
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 13 : 15,
                        fontWeight: FontWeight.w900,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      strings.voucherMatrixDialogSubtitle,
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
            ],
          ),

          const SizedBox(height: 12),

          // Actions row: Mode switcher (M3ConnectedButtonGroup) & Expand button ("عرض مكبر")
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              M3ConnectedButtonGroup<int>(
                height: 38,
                borderRadius: 12,
                selectedValue: _distributionViewMode,
                onSelected: (val) {
                  setState(() {
                    _distributionViewMode = val;
                  });
                },
                showCheckmark: false,
                segments: [
                  M3ButtonSegment<int>(
                    value: 0,
                    icon: Icons.splitscreen_rounded,
                    label: isAr ? 'مفتش الفروع' : (isHi ? 'शाखा निरीक्षक' : 'Inspector'),
                  ),
                  M3ButtonSegment<int>(
                    value: 1,
                    icon: Icons.table_chart_rounded,
                    label: isAr ? 'المصفوفة' : (isHi ? 'मैट्रिक्स' : 'Matrix'),
                  ),
                ],
              ),
              FilledButton.tonalIcon(
                onPressed: () => _showBranchVoucherMatrixDialog(
                  context: context,
                  colorScheme: colorScheme,
                  strings: strings,
                  isAr: isAr,
                  isHi: isHi,
                  isMobile: isMobile,
                  voucherMetrics: voucherMetrics,
                  distinctBranches: distinctBranches,
                ),
                icon: const Icon(Icons.fullscreen_rounded, size: 16),
                label: Text(
                  isAr ? 'عرض مكبر' : (isHi ? 'विस्तृत दृश्य' : 'Expand'),
                  style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.secondaryContainer.withValues(alpha: 0.7),
                  foregroundColor: colorScheme.onSecondaryContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Either M3 List-Detail Inspector or Responsive Full-Width Matrix Table
          if (_distributionViewMode == 0)
            _buildBranchListDetailInspector(
              colorScheme: colorScheme,
              strings: strings,
              isAr: isAr,
              isHi: isHi,
              isMobile: isMobile,
              voucherMetrics: voucherMetrics,
              sortedBranches: sortedBranches,
            )
          else
            _buildResponsiveVoucherMatrixTable(
              colorScheme: colorScheme,
              strings: strings,
              isAr: isAr,
              isHi: isHi,
              isMobile: isMobile,
              voucherMetrics: voucherMetrics,
              sortedBranches: sortedBranches,
              denoms: denoms,
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // M3 List-Detail Branch Inspector (قائمة الفروع + لوحة التفاصيل العميقة)
  // ---------------------------------------------------------------------------
  Widget _buildBranchListDetailInspector({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required AggregatedVoucherMetrics voucherMetrics,
    required List<String> sortedBranches,
  }) {
    if (sortedBranches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            isAr ? 'لا توجد فروع مسجلة لعرض التفاصيل' : (isHi ? 'विवरण प्रदर्शित करने के लिए कोई शाखा उपलब्ध नहीं है' : 'No branches available to display'),
            style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final query = _branchSearchController.text.trim().toLowerCase();
    final filteredBranches = query.isEmpty
        ? sortedBranches
        : sortedBranches.where((b) => b.toLowerCase().contains(query)).toList();

    // Default inspected branch to the first one or maintain selection if valid
    final currentInspectedBranch = (_inspectedBranchName != null && sortedBranches.contains(_inspectedBranchName))
        ? _inspectedBranchName!
        : sortedBranches.first;

    // List Pane
    final listPane = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search bar
        Container(
          height: 38,
          margin: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _branchSearchController,
            onChanged: (_) => setState(() {}),
            style: GoogleFonts.cairo(fontSize: 12),
            decoration: InputDecoration(
              hintText: isAr ? 'بحث عن فرع...' : (isHi ? 'शाखा खोजें...' : 'Search branch...'),
              hintStyle: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant),
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: _branchSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      onPressed: () {
                        _branchSearchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
              ),
            ),
          ),
        ),

        if (filteredBranches.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                isAr ? 'لا توجد فروع مطابقة للبحث' : 'No matching branches',
                style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredBranches.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.25),
            ),
            itemBuilder: (context, index) {
              final branch = filteredBranches[index];
              final isSelected = branch == currentInspectedBranch;
              final totalUnits = voucherMetrics.branchTotalVoucherUnits[branch] ?? 0;
              final claimedUnits = voucherMetrics.branchClaimedVoucherUnits[branch] ?? 0;
              final remainingUnits = voucherMetrics.branchRemainingVoucherUnits[branch] ?? 0;
              final totalBudget = voucherMetrics.branchTotalVoucherBudget[branch] ?? 0.0;
              final branchRate = totalUnits > 0 ? (claimedUnits / totalUnits).clamp(0.0, 1.0) : 0.0;

              return Material(
                color: isSelected
                    ? colorScheme.primaryContainer.withValues(alpha: 0.35)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    setState(() {
                      _inspectedBranchName = branch;
                    });
                    if (isMobile) {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: colorScheme.surface,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                        ),
                        builder: (ctx) => DraggableScrollableSheet(
                          initialChildSize: 0.75,
                          minChildSize: 0.45,
                          maxChildSize: 0.95,
                          expand: false,
                          builder: (sheetCtx, scrollController) => SingleChildScrollView(
                            controller: scrollController,
                            padding: const EdgeInsets.all(20),
                            child: _buildBranchDetailPaneContent(
                              branch: branch,
                              colorScheme: colorScheme,
                              strings: strings,
                              isAr: isAr,
                              isHi: isHi,
                              voucherMetrics: voucherMetrics,
                              isBottomSheet: true,
                            ),
                          ),
                        ),
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.storefront_rounded,
                            size: 16,
                            color: isSelected
                                ? colorScheme.onPrimary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                branch,
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                                  color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${_formatMoney(totalBudget, isAr: isAr)} • $totalUnits قسيمة',
                                style: GoogleFonts.cairo(
                                  fontSize: 10.5,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: branchRate >= 0.8
                                    ? colorScheme.tertiary.withValues(alpha: 0.15)
                                    : (branchRate >= 0.4
                                        ? colorScheme.secondary.withValues(alpha: 0.15)
                                        : colorScheme.outlineVariant.withValues(alpha: 0.3)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${(branchRate * 100).toStringAsFixed(0)}%',
                                style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: branchRate >= 0.8
                                      ? colorScheme.onTertiaryFixedVariant
                                      : (branchRate >= 0.4
                                          ? colorScheme.onSecondaryFixedVariant
                                          : colorScheme.onSurfaceVariant),
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'متبقي $remainingUnits',
                              style: GoogleFonts.cairo(
                                fontSize: 9.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );

    return M3ListDetailLayout(
      listPane: listPane,
      detailPane: _buildBranchDetailPaneContent(
        branch: currentInspectedBranch,
        colorScheme: colorScheme,
        strings: strings,
        isAr: isAr,
        isHi: isHi,
        voucherMetrics: voucherMetrics,
        isBottomSheet: false,
      ),
      listPaneWidth: 320.0,
      crossAxisAlignment: CrossAxisAlignment.start,
    );
  }

  // ---------------------------------------------------------------------------
  // Branch Detail Pane Content Builder (بطاقة الفحص التفصيلي للفئات والميزانية)
  // ---------------------------------------------------------------------------
  Widget _buildBranchDetailPaneContent({
    required String branch,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required AggregatedVoucherMetrics voucherMetrics,
    bool isBottomSheet = false,
  }) {
    final totalAllocated = voucherMetrics.branchTotalVoucherUnits[branch] ?? 0;
    final totalClaimed = voucherMetrics.branchClaimedVoucherUnits[branch] ?? 0;
    final totalRemaining = voucherMetrics.branchRemainingVoucherUnits[branch] ?? 0;
    final totalBudget = voucherMetrics.branchTotalVoucherBudget[branch] ?? 0.0;
    final claimedBudget = voucherMetrics.denominations.fold<double>(0.0, (acc, d) {
      final stats = voucherMetrics.branchDenominationsMap[branch]?[d.denomination];
      return acc + (stats != null ? (stats.claimedCount * d.denomination) : 0.0);
    });
    final remainingBudget = (totalBudget - claimedBudget).clamp(0.0, double.infinity);
    final depletionRate = totalAllocated > 0 ? (totalClaimed / totalAllocated).clamp(0.0, 1.0) : 0.0;
    final isBranchFiltered = _selectedBranch == branch;

    return Container(
      padding: EdgeInsets.all(isBottomSheet ? 0 : 16),
      decoration: isBottomSheet
          ? null
          : BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with Branch Name and Filter Action
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.store_rounded, size: 20, color: colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      branch,
                      style: GoogleFonts.cairo(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      isAr
                          ? 'الفحص التفصيلي لميزانية وفئات القسائم'
                          : (isHi ? 'वाउचर बजट और मूल्यवर्ग का विस्तृत निरीक्षण' : 'Voucher budget and denominations breakdown'),
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isBranchFiltered)
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedBranch = null;
                    });
                    if (isBottomSheet) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 14),
                  label: Text(
                    isAr ? 'إلغاء التصفية' : (isHi ? 'फ़िल्टर हटाएं' : 'Clear Filter'),
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: () {
                    setState(() {
                      _selectedBranch = branch;
                    });
                    if (isBottomSheet) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.filter_alt_rounded, size: 14),
                  label: Text(
                    isAr ? 'تصفية التقرير' : (isHi ? 'रिपोर्ट फ़िल्टर' : 'Filter Report'),
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 14),

          // 3 Executive KPI Cards Row
          Row(
            children: [
              Expanded(
                child: _buildBranchDetailKpiBox(
                  title: isAr ? 'الميزانية الكلية' : 'Total Budget',
                  value: _formatMoney(totalBudget, isAr: isAr),
                  subvalue: isAr ? '$totalAllocated قسيمة' : '$totalAllocated vouchers',
                  color: colorScheme.primary,
                  colorScheme: colorScheme,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildBranchDetailKpiBox(
                  title: isAr ? 'القيمة المصروفة' : 'Claimed Value',
                  value: _formatMoney(claimedBudget, isAr: isAr),
                  subvalue: isAr ? '$totalClaimed مصروفة' : '$totalClaimed claimed',
                  color: colorScheme.tertiary,
                  colorScheme: colorScheme,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildBranchDetailKpiBox(
                  title: isAr ? 'الرصيد المتبقي' : 'Remaining Value',
                  value: _formatMoney(remainingBudget, isAr: isAr),
                  subvalue: isAr ? '$totalRemaining متبقية' : '$totalRemaining left',
                  color: colorScheme.secondary,
                  colorScheme: colorScheme,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Depletion Progress Bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isAr ? 'معدل استهلاك قسائم الفرع' : 'Branch Voucher Depletion Rate',
                      style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${(depletionRate * 100).toStringAsFixed(1)}%',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: depletionRate >= 0.8
                            ? colorScheme.onTertiaryFixedVariant
                            : (depletionRate >= 0.4
                                ? colorScheme.onSecondaryFixedVariant
                                : colorScheme.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: depletionRate,
                    minHeight: 8,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      depletionRate >= 0.8
                          ? colorScheme.tertiary
                          : (depletionRate >= 0.4
                              ? colorScheme.secondary
                              : colorScheme.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Denominations breakdown title
          Text(
            isAr ? 'توزيع الفئات النقدية بالفرع' : (isHi ? 'शाखा में मूल्यवर्ग का वितरण' : 'Denominations Breakdown'),
            style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.w800, color: colorScheme.onSurface),
          ),
          const SizedBox(height: 8),

          // Denominations Cards
          ...voucherMetrics.denominations.map((denom) {
            final stats = voucherMetrics.branchDenominationsMap[branch]?[denom.denomination];
            final allocated = stats?.allocatedCount ?? 0;
            final claimed = stats?.claimedCount ?? 0;
            final remaining = stats?.remainingCount ?? 0;
            final rate = allocated > 0 ? (claimed / allocated).clamp(0.0, 1.0) : 0.0;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.secondary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      denom.label,
                      style: GoogleFonts.cairo(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: colorScheme.secondary,
                      ),
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
                              isAr
                                  ? 'مخصص: $allocated • صرف: $claimed • متبقي: $remaining'
                                  : 'Alloc: $allocated • Claimed: $claimed • Rem: $remaining',
                              style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${(rate * 100).toStringAsFixed(0)}%',
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: rate >= 0.8
                                    ? colorScheme.onTertiaryFixedVariant
                                    : (rate >= 0.4
                                        ? colorScheme.onSecondaryFixedVariant
                                        : colorScheme.primary),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: rate,
                            minHeight: 5,
                            backgroundColor: colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              rate >= 0.8
                                  ? colorScheme.tertiary
                                  : (rate >= 0.4
                                      ? colorScheme.secondary
                                      : colorScheme.primary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBranchDetailKpiBox({
    required String title,
    required String value,
    required String subvalue,
    required Color color,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            subvalue,
            style: GoogleFonts.cairo(
              fontSize: 9.5,
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Responsive Voucher Matrix Table Builder (Full-Width / Zero Overflow)
  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // Responsive Voucher Matrix Table Builder (Full-Width / Zero Overflow)
  // ---------------------------------------------------------------------------
  Widget _buildResponsiveVoucherMatrixTable({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required AggregatedVoucherMetrics voucherMetrics,
    required List<String> sortedBranches,
    required List<VoucherDenominationStats> denoms,
  }) {
    if (sortedBranches.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Text(
          isAr ? 'لا توجد فروع أو بيانات قسائم متاحة' : 'No branch voucher data available',
          style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        // Minimum comfortable column widths
        const branchColMinWidth = 200.0;
        final denomColMinWidth = denoms.isEmpty ? 140.0 : 160.0;
        const totalUnitsColMinWidth = 130.0;
        const budgetColMinWidth = 140.0;
        const claimedColMinWidth = 120.0;
        const remainingColMinWidth = 110.0;
        const depletionColMinWidth = 140.0;

        final baseTotalWidth = branchColMinWidth +
            (denoms.length * denomColMinWidth) +
            totalUnitsColMinWidth +
            budgetColMinWidth +
            claimedColMinWidth +
            remainingColMinWidth +
            depletionColMinWidth;

        final double tableWidth = availableWidth > baseTotalWidth ? availableWidth : baseTotalWidth;
        final double scale = availableWidth > baseTotalWidth ? (availableWidth / baseTotalWidth) : 1.0;

        final branchColWidth = branchColMinWidth * scale;
        final denomColWidth = denomColMinWidth * scale;
        final totalUnitsColWidth = totalUnitsColMinWidth * scale;
        final budgetColWidth = budgetColMinWidth * scale;
        final claimedColWidth = claimedColMinWidth * scale;
        final remainingColWidth = remainingColMinWidth * scale;
        final depletionColWidth = depletionColMinWidth * scale;

        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Table(
                    columnWidths: {
                      0: FixedColumnWidth(branchColWidth),
                      for (int dIdx = 0; dIdx < denoms.length; dIdx++)
                        dIdx + 1: FixedColumnWidth(denomColWidth),
                      denoms.length + 1: FixedColumnWidth(totalUnitsColWidth),
                      denoms.length + 2: FixedColumnWidth(budgetColWidth),
                      denoms.length + 3: FixedColumnWidth(claimedColWidth),
                      denoms.length + 4: FixedColumnWidth(remainingColWidth),
                      denoms.length + 5: FixedColumnWidth(depletionColWidth),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      // Header Row
                      TableRow(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
                          border: Border(
                            bottom: BorderSide(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                              width: 1,
                            ),
                          ),
                        ),
                        children: [
                          _buildHeaderCell(
                            icon: Icons.storefront_rounded,
                            iconColor: colorScheme.primary,
                            title: isAr ? 'الفرع / المنفذ' : 'Branch / Outlet',
                            colorScheme: colorScheme,
                          ),
                          for (final d in denoms)
                            _buildHeaderCell(
                              icon: Icons.confirmation_number_outlined,
                              iconColor: colorScheme.onSecondaryFixedVariant,
                              title: 'فئة ${d.label}',
                              subtitle: isAr ? '(مخصص • صرف • متبقي)' : '(alloc • out • left)',
                              colorScheme: colorScheme,
                            ),
                          _buildHeaderCell(
                            icon: Icons.inventory_2_outlined,
                            iconColor: colorScheme.primary,
                            title: isAr ? 'إجمالي القسائم' : 'Total Vouchers',
                            colorScheme: colorScheme,
                          ),
                          _buildHeaderCell(
                            icon: Icons.account_balance_wallet_outlined,
                            iconColor: colorScheme.tertiary,
                            title: isAr ? 'ميزانية الفرع' : 'Branch Budget',
                            colorScheme: colorScheme,
                          ),
                          _buildHeaderCell(
                            icon: Icons.shopping_bag_outlined,
                            iconColor: colorScheme.primary,
                            title: isAr ? 'المنصرف' : 'Disbursed',
                            colorScheme: colorScheme,
                          ),
                          _buildHeaderCell(
                            icon: Icons.savings_outlined,
                            iconColor: colorScheme.tertiary,
                            title: isAr ? 'المتبقي' : 'Remaining',
                            colorScheme: colorScheme,
                          ),
                          _buildHeaderCell(
                            icon: Icons.analytics_outlined,
                            iconColor: colorScheme.secondary,
                            title: isAr ? 'نسبة الاستهلاك' : 'Depletion',
                            colorScheme: colorScheme,
                          ),
                        ],
                      ),

                      // Data Rows
                      for (int i = 0; i < sortedBranches.length; i++)
                        _buildDataTableRow(
                          index: i,
                          branch: sortedBranches[i],
                          denoms: denoms,
                          voucherMetrics: voucherMetrics,
                          isAr: isAr,
                          colorScheme: colorScheme,
                          isLast: i == sortedBranches.length - 1,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderCell({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required ColorScheme colorScheme,
  }) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: iconColor),
            const SizedBox(width: 5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: GoogleFonts.cairo(
                        fontSize: 9.5,
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
      ),
    );
  }

  TableRow _buildDataTableRow({
    required int index,
    required String branch,
    required List<VoucherDenominationStats> denoms,
    required AggregatedVoucherMetrics voucherMetrics,
    required bool isAr,
    required ColorScheme colorScheme,
    required bool isLast,
  }) {
    final branchAllocated = voucherMetrics.branchTotalVoucherUnits[branch] ?? 0;
    final branchBudget = voucherMetrics.branchTotalVoucherBudget[branch] ?? 0.0;
    final branchClaimed = voucherMetrics.branchClaimedVoucherUnits[branch] ?? 0;
    final branchRemaining = voucherMetrics.branchRemainingVoucherUnits[branch] ?? 0;
    final branchDepletion = branchAllocated > 0
        ? (branchClaimed / branchAllocated).clamp(0.0, 1.0)
        : 0.0;

    final isEven = index % 2 == 0;
    final rowBg = isEven
        ? Colors.transparent
        : colorScheme.surfaceContainerLow.withValues(alpha: 0.35);

    return TableRow(
      decoration: BoxDecoration(
        color: rowBg,
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
      ),
      children: [
        // 1. Branch Name
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.place_rounded, size: 16, color: colorScheme.secondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    branch,
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),

        // 2. Denomination Metrics
        for (final d in denoms)
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Builder(
                builder: (context) {
                  final stats = voucherMetrics.branchDenominationsMap[branch]?[d.denomination];
                  final alloc = stats?.allocatedCount ?? 0;
                  final claimed = stats?.claimedCount ?? 0;
                  final rem = stats?.remainingCount ?? 0;

                  if (alloc == 0) {
                    return Text(
                      '-',
                      style: GoogleFonts.cairo(
                        color: colorScheme.outlineVariant,
                        fontSize: 12,
                      ),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_formatCount(alloc)} (${_formatMoney(alloc * d.denomination, isAr: isAr)})',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w900,
                          fontSize: 11.5,
                          color: colorScheme.onSecondaryFixedVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${isAr ? "صرف" : "out"}: ${_formatCount(claimed)} • ${isAr ? "متبقي" : "left"}: ${_formatCount(rem)}',
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

        // 3. Total Units
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_formatCount(branchAllocated)} ${isAr ? "قسيمة" : "cards"}',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    fontSize: 11.5,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),

        // 4. Branch Budget
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.tertiary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatMoney(branchBudget, isAr: isAr),
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
                    color: colorScheme.tertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),

        // 5. Disbursed
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Text(
              '${_formatCount(branchClaimed)} (${(branchDepletion * 100).toStringAsFixed(0)}%)',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                fontSize: 11.5,
                color: colorScheme.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),

        // 6. Remaining
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: branchRemaining <= 0
                      ? colorScheme.error.withValues(alpha: 0.1)
                      : colorScheme.tertiary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _formatCount(branchRemaining),
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: branchRemaining <= 0
                        ? colorScheme.error
                        : (branchRemaining < 10
                            ? colorScheme.secondary
                            : colorScheme.tertiary),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),

        // 7. Depletion %
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: branchDepletion,
                      minHeight: 6,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        branchRemaining <= 0
                            ? colorScheme.error
                            : (branchDepletion > 0.75
                                ? colorScheme.secondary
                                : colorScheme.tertiary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(branchDepletion * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
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

  // ---------------------------------------------------------------------------
  // 6. Branch Voucher Matrix Modal Dialog (Full Responsive View)
  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // 6. Branch Voucher Matrix Modal Dialog (Full Responsive View)
  // ---------------------------------------------------------------------------
  void _showBranchVoucherMatrixDialog({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required bool isMobile,
    required AggregatedVoucherMetrics voucherMetrics,
    required List<String> distinctBranches,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final sortedBranches = distinctBranches.where((b) => b.trim().isNotEmpty).toList()..sort();
        final denoms = voucherMetrics.denominations;
        final screenWidth = MediaQuery.of(dialogContext).size.width;
        final screenHeight = MediaQuery.of(dialogContext).size.height;
        final dialogWidth = screenWidth > 1300 ? 1250.0 : (screenWidth * 0.95).clamp(320.0, 1250.0);
        final dialogHeight = (screenHeight * 0.88).clamp(300.0, 900.0);

        return Dialog(
          backgroundColor: colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Dialog Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colorScheme.secondary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.table_chart_rounded,
                          color: colorScheme.secondary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.voucherMatrixDialogTitle,
                              style: GoogleFonts.cairo(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              strings.voucherMatrixDialogSubtitle,
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        tooltip: isAr ? 'إغلاق النافذة' : 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Responsive Table Content
                  Expanded(
                    child: _buildResponsiveVoucherMatrixTable(
                      colorScheme: colorScheme,
                      strings: strings,
                      isAr: isAr,
                      isHi: isHi,
                      isMobile: isMobile,
                      voucherMetrics: voucherMetrics,
                      sortedBranches: sortedBranches,
                      denoms: denoms,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Footer Actions
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.tonal(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(
                        isAr ? 'إغلاق' : 'Close',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 7. Multi-Sheet Excel Export (.xlsx)
  // ---------------------------------------------------------------------------
  void _exportVouchersExcel({
    required BuildContext context,
    required AggregatedVoucherMetrics voucherMetrics,
    required List<String> distinctBranches,
    required List<QueryDocumentSnapshot> txDocs,
    required bool isAr,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final excel = Excel.createExcel();

      // Sheet 1: Denominations Summary (ملخص فئات القسائم)
      final String denomSheetName = isAr ? 'ملخص فئات القسائم' : 'Denominations Summary';
      excel.rename('Sheet1', denomSheetName);
      final Sheet denomSheet = excel[denomSheetName];

      denomSheet.appendRow([
        TextCellValue(isAr ? 'فئة القسيمة' : 'Denomination'),
        TextCellValue(isAr ? 'إجمالي الكروت المخصصة' : 'Allocated Cards'),
        TextCellValue(isAr ? 'الميزانية المرصودة (ج.م)' : 'Allocated Budget (EGP)'),
        TextCellValue(isAr ? 'الكروت المصروفة' : 'Claimed Cards'),
        TextCellValue(isAr ? 'القيمة المصروفة (ج.م)' : 'Claimed Value (EGP)'),
        TextCellValue(isAr ? 'الكروت المتبقية' : 'Remaining Cards'),
        TextCellValue(isAr ? 'الرصيد المتبقي (ج.م)' : 'Remaining Value (EGP)'),
        TextCellValue(isAr ? 'نسبة الاستهلاك' : 'Depletion Rate'),
        TextCellValue(isAr ? 'رصيد المخزن العام' : 'Master Warehouse Stock'),
      ]);

      for (final d in voucherMetrics.denominations) {
        denomSheet.appendRow([
          TextCellValue(d.label),
          IntCellValue(d.allocatedCount),
          DoubleCellValue(d.totalBudget),
          IntCellValue(d.claimedCount),
          DoubleCellValue(d.claimedValue),
          IntCellValue(d.remainingCount),
          DoubleCellValue(d.remainingValue),
          TextCellValue('${(d.depletionRate * 100).toStringAsFixed(1)}%'),
          IntCellValue(d.masterTotalCount),
        ]);
      }

      // Sheet 2: Branch Voucher Matrix (كشف توزيع الفروع)
      final String branchSheetName = isAr ? 'كشف توزيع الفروع' : 'Branch Matrix';
      final Sheet branchSheet = excel[branchSheetName];

      final List<CellValue> branchHeader = [
        TextCellValue(isAr ? 'الفرع / المنفذ' : 'Branch Outlet'),
        for (final d in voucherMetrics.denominations) ...[
          TextCellValue('فئة ${d.label} (مخصص)'),
          TextCellValue('فئة ${d.label} (منصرف)'),
          TextCellValue('فئة ${d.label} (متبقي)'),
        ],
        TextCellValue(isAr ? 'إجمالي القسائم المخصصة' : 'Total Allocated'),
        TextCellValue(isAr ? 'ميزانية الفرع (ج.م)' : 'Branch Budget (EGP)'),
        TextCellValue(isAr ? 'إجمالي المنصرف' : 'Total Claimed'),
        TextCellValue(isAr ? 'إجمالي المتبقي' : 'Total Remaining'),
        TextCellValue(isAr ? 'نسبة استهلاك الفرع' : 'Branch Depletion Rate'),
      ];
      branchSheet.appendRow(branchHeader);

      final sortedBranches = distinctBranches.where((b) => b.trim().isNotEmpty).toList()..sort();
      for (final b in sortedBranches) {
        final bAlloc = voucherMetrics.branchTotalVoucherUnits[b] ?? 0;
        final bBudget = voucherMetrics.branchTotalVoucherBudget[b] ?? 0.0;
        final bClaimed = voucherMetrics.branchClaimedVoucherUnits[b] ?? 0;
        final bRem = voucherMetrics.branchRemainingVoucherUnits[b] ?? 0;
        final bDep = bAlloc > 0 ? (bClaimed / bAlloc).clamp(0.0, 1.0) : 0.0;

        final List<CellValue> row = [
          TextCellValue(b),
          for (final d in voucherMetrics.denominations) ...[
            IntCellValue(voucherMetrics.branchDenominationsMap[b]?[d.denomination]?.allocatedCount ?? 0),
            IntCellValue(voucherMetrics.branchDenominationsMap[b]?[d.denomination]?.claimedCount ?? 0),
            IntCellValue(voucherMetrics.branchDenominationsMap[b]?[d.denomination]?.remainingCount ?? 0),
          ],
          IntCellValue(bAlloc),
          DoubleCellValue(bBudget),
          IntCellValue(bClaimed),
          IntCellValue(bRem),
          TextCellValue('${(bDep * 100).toStringAsFixed(1)}%'),
        ];
        branchSheet.appendRow(row);
      }

      // Save and download
      final fileBytes = excel.save();
      if (fileBytes != null) {
        final now = DateTime.now();
        final timestamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        final fileName = 'Tashil_Vouchers_Report_$timestamp.xlsx';

        downloadFileBytes(
          bytes: fileBytes,
          fileName: fileName,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );

        messenger.showSnackBar(
          SnackBar(
            content: Text(
              isAr ? '✅ تم تحميل تقرير قسائم المشتريات بنجاح ($fileName)' : '✅ Vouchers Report downloaded successfully ($fileName)',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            backgroundColor: colorScheme.tertiary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isAr ? '⚠️ تعذر تصدير تقرير Excel: $e' : '⚠️ Failed to export Excel report: $e',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          backgroundColor: colorScheme.onErrorContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
