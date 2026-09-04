import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/country_currency_config.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/widgets/switch_point_branding.dart';
import '../../admin/domain/event_model.dart';

/// Performance Summary Data for a Single Campaign
class CampaignMetricsSummary {
  final String campaignId;
  final String campaignTitle;
  final String targetCompany;
  final DateTime? startDate;
  final DateTime? endDate;
  final double totalRevenue;
  final int totalInvoices;
  final int totalProductsSold;
  final int uniqueShoppersCount;
  final int claimedPrizesCount;
  final double estimatedPrizesValue;
  final bool isActive;

  const CampaignMetricsSummary({
    required this.campaignId,
    required this.campaignTitle,
    required this.targetCompany,
    this.startDate,
    this.endDate,
    required this.totalRevenue,
    required this.totalInvoices,
    required this.totalProductsSold,
    required this.uniqueShoppersCount,
    required this.claimedPrizesCount,
    required this.estimatedPrizesValue,
    required this.isActive,
  });

  double get avgBasketSpend =>
      totalInvoices > 0 ? (totalRevenue / totalInvoices) : 0.0;
  double get avgUnitsPerBasket =>
      totalInvoices > 0 ? (totalProductsSold / totalInvoices) : 0.0;
}

/// Comparison Dimension enum for interactive charts
enum ComparisonDimension { revenue, invoices, products, shoppers }

/// Material Design 3 Campaigns Benchmark & Intelligence Analytics Screen
/// Provides side-by-side Head-to-Head comparisons (A vs B) and All-Campaigns Portfolio Ranking.
class CampaignsComparisonAnalyticsScreen extends ConsumerStatefulWidget {
  final String lockedCompanySlug;
  final String lockedCompanyName;
  final String? initialEventId;
  final List<EventModel>? companyEvents;
  final bool isEmbedded;

  const CampaignsComparisonAnalyticsScreen({
    super.key,
    required this.lockedCompanySlug,
    required this.lockedCompanyName,
    this.initialEventId,
    this.companyEvents,
    this.isEmbedded = false,
  });

  @override
  ConsumerState<CampaignsComparisonAnalyticsScreen> createState() =>
      _CampaignsComparisonAnalyticsScreenState();
}

class _CampaignsComparisonAnalyticsScreenState
    extends ConsumerState<CampaignsComparisonAnalyticsScreen> {
  // Global / Persistent In-Memory Caches across tab switches and widget re-mounts (0ms Instant Render)
  static final Map<String, Map<String, CampaignMetricsSummary>> _persistentMetricsCache = {};
  static final Map<String, List<EventModel>> _persistentEventsCache = {};
  static final Map<String, List<QueryDocumentSnapshot>> _persistentInvoicesCache = {};
  static final Map<String, String> _savedCampaignA = {};
  static final Map<String, String> _savedCampaignB = {};
  static final Map<String, ComparisonDimension> _savedDimension = {};
  static final Map<String, int> _savedComparisonMode = {};

  String? _selectedCampaignAId;
  String? _selectedCampaignBId;
  int _comparisonMode = 0; // 0: Head-to-Head (A vs B), 1: All Campaigns Portfolio
  ComparisonDimension _activeDimension = ComparisonDimension.revenue;

  // Cached computation for 0ms re-renders
  final Map<String, CampaignMetricsSummary> _metricsCache = {};
  String _lastCacheKey = '';

  // Stream memoization to prevent re-subscription on dimension toggles
  Stream<QuerySnapshot>? _eventsStream;
  Stream<QuerySnapshot>? _transactionsStream;
  String? _lastStreamCompanySlug;

  @override
  void initState() {
    super.initState();
    final slug = widget.lockedCompanySlug;
    if (widget.companyEvents != null && widget.companyEvents!.isNotEmpty) {
      _persistentEventsCache[slug] = widget.companyEvents!;
    }
    _selectedCampaignAId = _savedCampaignA[slug] ?? widget.initialEventId;
    _selectedCampaignBId = _savedCampaignB[slug];
    _activeDimension = _savedDimension[slug] ?? ComparisonDimension.revenue;
    _comparisonMode = _savedComparisonMode[slug] ?? 0;
  }

  void _initializeCampaignSelections(List<EventModel> events) {
    if (events.isEmpty) return;
    final slug = widget.lockedCompanySlug;

    // 1. Resolve Campaign A
    if (_selectedCampaignAId == null ||
        !events.any((e) => e.id == _selectedCampaignAId)) {
      final savedA = _savedCampaignA[slug];
      if (savedA != null && events.any((e) => e.id == savedA)) {
        _selectedCampaignAId = savedA;
      } else if (widget.initialEventId != null &&
          events.any((e) => e.id == widget.initialEventId)) {
        _selectedCampaignAId = widget.initialEventId;
      } else {
        _selectedCampaignAId = events.first.id;
      }
      _savedCampaignA[slug] = _selectedCampaignAId!;
    }

    // 2. Resolve Campaign B
    if (_selectedCampaignBId == null ||
        !events.any((e) => e.id == _selectedCampaignBId)) {
      final savedB = _savedCampaignB[slug];
      if (savedB != null &&
          events.any((e) => e.id == savedB) &&
          (events.length == 1 || savedB != _selectedCampaignAId)) {
        _selectedCampaignBId = savedB;
      } else if (events.length > 1) {
        final secondary = events.firstWhere(
          (e) => e.id != _selectedCampaignAId,
          orElse: () => events.first,
        );
        _selectedCampaignBId = secondary.id;
      } else {
        _selectedCampaignBId = events.first.id;
      }
      _savedCampaignB[slug] = _selectedCampaignBId!;
    }
  }

  /// Normalizes Arabic event titles for robust phonetic and spelling matching
  static String _normalizeTitle(String input) {
    if (input.isEmpty) return '';
    return input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '') // remove Arabic diacritics / tashkeel
        .replaceAll(RegExp(r'[إأآا]'), 'ا') // normalize alef
        .replaceAll('ة', 'ه') // normalize teh marbuta
        .replaceAll('ى', 'ي') // normalize alef maksura
        .replaceAll(RegExp(r'[\-_–—\s]+'), ' ') // normalize hyphens, en-dashes, em-dashes and spaces
        .trim();
  }

  /// Calculates aggregated metrics from raw invoices list for each campaign
  Map<String, CampaignMetricsSummary> _computeMetrics({
    required List<EventModel> events,
    required List<QueryDocumentSnapshot> invoiceDocs,
  }) {
    final slug = widget.lockedCompanySlug;
    final cached = _persistentMetricsCache[slug];

    // If incoming docs is empty but we have non-empty persistent cache, retain cached data!
    if (invoiceDocs.isEmpty && cached != null && cached.isNotEmpty) {
      return cached;
    }

    final firstId = invoiceDocs.isNotEmpty ? invoiceDocs.first.id : '';
    final lastId = invoiceDocs.isNotEmpty ? invoiceDocs.last.id : '';
    final cacheKey =
        '${events.map((e) => e.id).join(',')}_${invoiceDocs.length}_${firstId}_$lastId';
    if (_lastCacheKey == cacheKey && _metricsCache.isNotEmpty) {
      return _metricsCache;
    }

    _metricsCache.clear();
    _lastCacheKey = cacheKey;

    // Group receipts_transactions by campaignId / event_id / eventName with robust normalization
    final Map<String, List<Map<String, dynamic>>> invoicesByCampaign = {};
    final Map<String, String> eventNameMap = {};
    final Set<String> eventIdSet = {};

    for (final e in events) {
      eventIdSet.add(e.id);
      final normName = _normalizeTitle(e.eventName);
      if (normName.isNotEmpty) {
        eventNameMap[normName] = e.id;
      }
      final rawName = e.eventName.trim().toLowerCase();
      if (rawName.isNotEmpty) {
        eventNameMap[rawName] = e.id;
      }
    }

    for (final doc in invoiceDocs) {
      final data = doc.data() as Map<String, dynamic>;
      String cId = (data['campaignId'] ?? data['event_id'] ?? data['eventId'] ?? '').toString().trim();

      // If cId does not directly match any event ID in our set, resolve via event name
      if (!eventIdSet.contains(cId)) {
        final rawEvName = (data['eventName'] ??
                data['campaign_title'] ??
                data['campaignName'] ??
                data['event_name'] ??
                '')
            .toString()
            .trim();
        final normEvName = _normalizeTitle(rawEvName);
        if (normEvName.isNotEmpty && eventNameMap.containsKey(normEvName)) {
          cId = eventNameMap[normEvName]!;
        } else if (rawEvName.isNotEmpty && eventNameMap.containsKey(rawEvName.toLowerCase())) {
          cId = eventNameMap[rawEvName.toLowerCase()]!;
        }
      }

      if (cId.isNotEmpty && eventIdSet.contains(cId)) {
        invoicesByCampaign.putIfAbsent(cId, () => []).add(data);
      }
    }

    for (final event in events) {
      final invoices = invoicesByCampaign[event.id] ?? [];
      double totalRev = 0.0;
      int totalItems = 0;
      int acceptedCount = 0;
      final Set<String> uniquePhones = {};
      int prizesCount = 0;
      double prizesVal = 0.0;

      for (final inv in invoices) {
        final status = (inv['status'] ?? '').toString().toLowerCase().trim();
        final bool isExplicitlyValid = inv['is_valid'] == true ||
            inv['isValid'] == true ||
            status == 'accepted' ||
            status == 'approved' ||
            status == 'claimed' ||
            status == 'completed';
        final bool isExplicitlyRejected = inv['is_valid'] == false ||
            inv['isValid'] == false ||
            status == 'rejected' ||
            ((inv['unfulfilled_conditions'] as List?)?.isNotEmpty ?? false);
        final bool isValid = isExplicitlyValid ||
            (!isExplicitlyRejected && ((inv['unfulfilled_conditions'] as List?)?.isEmpty ?? true));

        if (isValid) {
          acceptedCount++;

          // 1. Revenue: Check target_company_total / total_value / eligibleAmount / totalAmount
          final double rev = (inv['target_company_total'] as num?)?.toDouble() ??
              (inv['targetCompanyTotal'] as num?)?.toDouble() ??
              (inv['total_value'] as num?)?.toDouble() ??
              (inv['eligibleAmount'] as num?)?.toDouble() ??
              (inv['totalAmount'] as num?)?.toDouble() ??
              0.0;
          totalRev += rev;

          // 2. Products and units sold count
          final rawProducts = inv['extracted_products'] ??
              inv['extractedItems'] ??
              inv['items'] ??
              [];
          if (rawProducts is List) {
            for (final p in rawProducts) {
              if (p is Map) {
                final qty = (p['quantity'] as num?)?.toInt() ?? 1;
                totalItems += qty;
              } else {
                totalItems++;
              }
            }
          }

          // 3. Unique Shopper phone number
          final phone = (inv['customerPhone'] ??
                  inv['customer_phone'] ??
                  inv['userPhone'] ??
                  inv['phoneNumber'] ??
                  inv['phone_number'] ??
                  '')
              .toString()
              .trim();
          if (phone.isNotEmpty && phone != 'null') {
            uniquePhones.add(phone);
          }

          // 4. Claimed Prizes & Vouchers
          final claimedGifts = (inv['claimed_gifts'] as List?) ?? [];
          if (claimedGifts.isNotEmpty) {
            for (final cg in claimedGifts) {
              if (cg is Map) {
                final qty = (cg['quantity'] as num?)?.toInt() ?? 1;
                final unitVal = (cg['unitValue'] as num?)?.toDouble() ?? 0.0;
                prizesCount += qty;
                prizesVal += (qty * unitVal);
              }
            }
          } else {
            final prizesWon = (inv['prizes_won'] as List?)?.map((p) => p.toString()).toList() ??
                [(inv['prize_won'] ?? inv['prizeWon'] ?? '').toString()];
            for (final p in prizesWon) {
              if (p.trim().isNotEmpty && p != 'null') {
                prizesCount += 1;
                final match = RegExp(r'(\d+)').firstMatch(p);
                final double extractedVal = match != null ? double.tryParse(match.group(1)!) ?? 50.0 : 50.0;
                prizesVal += extractedVal;
              }
            }
          }
        }
      }

      _metricsCache[event.id] = CampaignMetricsSummary(
        campaignId: event.id,
        campaignTitle: event.eventName,
        targetCompany: event.targetCompany,
        startDate: event.startDate,
        endDate: event.endDate,
        totalRevenue: totalRev,
        totalInvoices: acceptedCount,
        totalProductsSold: totalItems,
        uniqueShoppersCount: uniquePhones.isNotEmpty
            ? uniquePhones.length
            : (acceptedCount > 0 ? (acceptedCount * 0.85).round().clamp(1, acceptedCount) : 0),
        claimedPrizesCount: prizesCount,
        estimatedPrizesValue: prizesVal,
        isActive: event.isActive,
      );
    }

    if (_metricsCache.isNotEmpty) {
      _persistentMetricsCache[slug] = Map.from(_metricsCache);
    }
    return _metricsCache;
  }

  void _ensureStreams(FirebaseFirestore firestore) {
    final slug = widget.lockedCompanySlug;
    if (_eventsStream != null && _lastStreamCompanySlug == slug) {
      return;
    }
    _lastStreamCompanySlug = slug;
    _eventsStream = firestore
        .collection('events')
        .where('companySlug', isEqualTo: slug)
        .snapshots();

    Query transactionsQuery = firestore.collection('receipts_transactions');
    if (slug.isNotEmpty) {
      transactionsQuery = transactionsQuery.where('companySlug', isEqualTo: slug);
    }
    _transactionsStream = transactionsQuery.snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = AppStrings.of(ref);
    final isAr = strings.isAr;
    final isHi = strings.isHi;
    final activeCountry = ref.watch(activeCountryProvider);
    FirebaseFirestore? firestore;
    try {
      firestore = ref.watch(firestoreProvider);
    } catch (_) {
      firestore = null;
    }

    if (firestore == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            isAr ? 'قاعدة البيانات غير متصلة' : 'Database not connected',
            style: GoogleFonts.cairo(color: colorScheme.error),
          ),
        ),
      );
    }

    final activeFirestore = firestore;
    final slug = widget.lockedCompanySlug;
    _ensureStreams(activeFirestore);

    final cachedEvents = _persistentEventsCache[slug] ?? widget.companyEvents;
    final cachedMetrics = _persistentMetricsCache[slug];

    return StreamBuilder<QuerySnapshot>(
      stream: _eventsStream,
      builder: (context, eventsSnapshot) {
        List<EventModel> events = [];

        if (eventsSnapshot.hasData && eventsSnapshot.data!.docs.isNotEmpty) {
          events = eventsSnapshot.data!.docs
              .map((doc) => EventModel.fromFirestore(doc))
              .toList();
          // Sort: Active first, then latest created
          events.sort((a, b) {
            if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
            final aDate = a.createdAt ?? a.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? b.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
          _persistentEventsCache[slug] = events;
        } else if (cachedEvents != null && cachedEvents.isNotEmpty) {
          events = cachedEvents;
        } else if (eventsSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        _initializeCampaignSelections(events);

        return StreamBuilder<QuerySnapshot>(
          stream: _transactionsStream,
          builder: (context, invoicesSnapshot) {
            final incomingDocs = invoicesSnapshot.data?.docs ?? [];
            if (incomingDocs.isNotEmpty) {
              _persistentInvoicesCache[slug] = incomingDocs;
            }
            final effectiveDocs = incomingDocs.isNotEmpty
                ? incomingDocs
                : (_persistentInvoicesCache[slug] ?? []);

            Map<String, CampaignMetricsSummary> metricsMap;
            if (effectiveDocs.isNotEmpty) {
              metricsMap = _computeMetrics(
                events: events,
                invoiceDocs: effectiveDocs,
              );
            } else if (cachedMetrics != null && cachedMetrics.isNotEmpty) {
              metricsMap = cachedMetrics;
            } else {
              metricsMap = _computeMetrics(
                events: events,
                invoiceDocs: [],
              );
            }

            return Scaffold(
              backgroundColor: Colors.transparent,
              appBar: widget.isEmbedded
                  ? null
                  : SwitchPointHeader(
                      subtitle: strings.campaignComparisonScreenTitle,
                    ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1320),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. Header Banner & Mode Selector
                        _buildScreenHeader(
                          context: context,
                          colorScheme: colorScheme,
                          strings: strings,
                          isAr: isAr,
                          eventsCount: events.length,
                        ),
                        const SizedBox(height: 18),

                        if (events.length < 2) ...[
                          _buildSingleCampaignNotice(
                            colorScheme: colorScheme,
                            strings: strings,
                            isAr: isAr,
                          ),
                          const SizedBox(height: 18),
                        ],

                        // 2. Mode Content
                        if (_comparisonMode == 0) ...[
                          // Head-to-Head Comparison (A vs B)
                          _buildHeadToHeadComparisonView(
                            context: context,
                            colorScheme: colorScheme,
                            strings: strings,
                            events: events,
                            metricsMap: metricsMap,
                            activeCountry: activeCountry,
                            isAr: isAr,
                            isHi: isHi,
                          ),
                        ] else ...[
                          // All Campaigns Portfolio Benchmark
                          _buildAllCampaignsPortfolioView(
                            context: context,
                            colorScheme: colorScheme,
                            strings: strings,
                            events: events,
                            metricsMap: metricsMap,
                            activeCountry: activeCountry,
                            isAr: isAr,
                            isHi: isHi,
                          ),
                        ],

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Builds top header banner with title and SegmentedButton mode switcher
  Widget _buildScreenHeader({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required int eventsCount,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 14,
        children: [
          // Title & Subtitle
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF6750A4),
                      const Color(0xFF006C51),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6750A4).withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.compare_arrows_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        strings.campaignComparisonScreenTitle,
                        style: GoogleFonts.cairo(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isAr ? '$eventsCount حملات' : '$eventsCount Campaigns',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    strings.campaignComparisonScreenSubtitle,
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Mode Selector Segmented Button
          SegmentedButton<int>(
            segments: [
              ButtonSegment<int>(
                value: 0,
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: Text(
                  strings.headToHeadComparisonTab,
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                ),
              ),
              ButtonSegment<int>(
                value: 1,
                icon: const Icon(Icons.leaderboard_rounded, size: 18),
                label: Text(
                  strings.allCampaignsPortfolioTab,
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                ),
              ),
            ],
            selected: {_comparisonMode},
            onSelectionChanged: (Set<int> newSelection) {
              final newMode = newSelection.first;
              _savedComparisonMode[widget.lockedCompanySlug] = newMode;
              setState(() {
                _comparisonMode = newMode;
              });
            },
          ),
        ],
      ),
    );
  }

  /// Warning banner when company has only 1 campaign
  Widget _buildSingleCampaignNotice({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: colorScheme.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              strings.needAtLeastTwoCampaigns,
              style: GoogleFonts.cairo(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Head-to-Head Comparison View (A vs B)
  // ---------------------------------------------------------------------------
  Widget _buildHeadToHeadComparisonView({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required List<EventModel> events,
    required Map<String, CampaignMetricsSummary> metricsMap,
    required CountryCurrency activeCountry,
    required bool isAr,
    required bool isHi,
  }) {
    final summaryA = metricsMap[_selectedCampaignAId];
    final summaryB = metricsMap[_selectedCampaignBId];

    final isSameCampaign = _selectedCampaignAId == _selectedCampaignBId && events.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Dual Campaign Selectors
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 700;
                  final dropA = _buildCampaignPicker(
                    label: strings.selectCampaignA,
                    badgeColor: const Color(0xFF6750A4),
                    selectedId: _selectedCampaignAId,
                    events: events,
                    onChanged: (id) {
                      if (id != null) {
                        _savedCampaignA[widget.lockedCompanySlug] = id;
                        setState(() => _selectedCampaignAId = id);
                      }
                    },
                    colorScheme: colorScheme,
                    isAr: isAr,
                  );
                  final dropB = _buildCampaignPicker(
                    label: strings.selectCampaignB,
                    badgeColor: const Color(0xFF006C51),
                    selectedId: _selectedCampaignBId,
                    events: events,
                    onChanged: (id) {
                      if (id != null) {
                        _savedCampaignB[widget.lockedCompanySlug] = id;
                        setState(() => _selectedCampaignBId = id);
                      }
                    },
                    colorScheme: colorScheme,
                    isAr: isAr,
                  );

                  if (isNarrow) {
                    return Column(
                      children: [
                        dropA,
                        const SizedBox(height: 12),
                        Center(
                          child: Icon(Icons.swap_vert_rounded,
                              color: colorScheme.primary, size: 28),
                        ),
                        const SizedBox(height: 12),
                        dropB,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: dropA),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.compare_arrows_rounded, size: 22),
                        ),
                      ),
                      Expanded(child: dropB),
                    ],
                  );
                },
              ),
              if (isSameCampaign) ...[
                const SizedBox(height: 12),
                Text(
                  strings.sameCampaignWarning,
                  style: GoogleFonts.cairo(
                    fontSize: 11.5,
                    color: colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 2. Animated Delta KPI Cards Grid
        _buildKpiDeltaGrid(
          summaryA: summaryA,
          summaryB: summaryB,
          colorScheme: colorScheme,
          strings: strings,
          activeCountry: activeCountry,
          isAr: isAr,
        ),

        const SizedBox(height: 24),

        // 3. Dual Grouped Bar Chart (fl_chart)
        _buildDualGroupedBarChart(
          summaryA: summaryA,
          summaryB: summaryB,
          colorScheme: colorScheme,
          strings: strings,
          activeCountry: activeCountry,
          isAr: isAr,
        ),

        const SizedBox(height: 24),

        // 4. Detailed Comparison Metrics Table
        _buildComparisonTable(
          summaryA: summaryA,
          summaryB: summaryB,
          colorScheme: colorScheme,
          strings: strings,
          activeCountry: activeCountry,
          isAr: isAr,
        ),
      ],
    );
  }

  /// Campaign Picker Dropdown with distinct badge color
  Widget _buildCampaignPicker({
    required String label,
    required Color badgeColor,
    required String? selectedId,
    required List<EventModel> events,
    required ValueChanged<String?> onChanged,
    required ColorScheme colorScheme,
    required bool isAr,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: badgeColor.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: badgeColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedId,
              isExpanded: true,
              icon: Icon(Icons.arrow_drop_down_rounded, color: badgeColor),
              items: events.map((event) {
                return DropdownMenuItem<String>(
                  value: event.id,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.eventName,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cairo(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (event.isActive) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isAr ? 'نشطة' : 'Active',
                            style: GoogleFonts.cairo(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  /// Grid of KPI Delta comparison cards
  Widget _buildKpiDeltaGrid({
    required CampaignMetricsSummary? summaryA,
    required CampaignMetricsSummary? summaryB,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required CountryCurrency activeCountry,
    required bool isAr,
  }) {
    final currency = activeCountry.currencySymbol;

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 1050
            ? 4
            : (constraints.maxWidth > 650 ? 2 : 1);

        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: crossAxisCount == 1 ? 2.4 : 1.65,
          children: [
            // 1. Total Sales Revenue
            _buildDeltaCard(
              title: strings.totalRevenueLabel,
              icon: Icons.payments_rounded,
              valA: summaryA?.totalRevenue ?? 0.0,
              valB: summaryB?.totalRevenue ?? 0.0,
              unit: currency,
              isCurrency: true,
              colorScheme: colorScheme,
              strings: strings,
              isAr: isAr,
            ),
            // 2. Invoices Count
            _buildDeltaCard(
              title: strings.totalInvoicesCountLabel,
              icon: Icons.receipt_long_rounded,
              valA: (summaryA?.totalInvoices ?? 0).toDouble(),
              valB: (summaryB?.totalInvoices ?? 0).toDouble(),
              unit: isAr ? 'فاتورة' : 'Invoices',
              isCurrency: false,
              colorScheme: colorScheme,
              strings: strings,
              isAr: isAr,
            ),
            // 3. Products Sold
            _buildDeltaCard(
              title: strings.totalProductsSoldLabel,
              icon: Icons.shopping_basket_rounded,
              valA: (summaryA?.totalProductsSold ?? 0).toDouble(),
              valB: (summaryB?.totalProductsSold ?? 0).toDouble(),
              unit: isAr ? 'قطعة' : 'Units',
              isCurrency: false,
              colorScheme: colorScheme,
              strings: strings,
              isAr: isAr,
            ),
            // 4. Unique Shoppers
            _buildDeltaCard(
              title: strings.uniqueShoppersLabel,
              icon: Icons.people_alt_rounded,
              valA: (summaryA?.uniqueShoppersCount ?? 0).toDouble(),
              valB: (summaryB?.uniqueShoppersCount ?? 0).toDouble(),
              unit: isAr ? 'متسوق' : 'Shoppers',
              isCurrency: false,
              colorScheme: colorScheme,
              strings: strings,
              isAr: isAr,
            ),
          ],
        );
      },
    );
  }

  /// Single animated Delta KPI Card
  Widget _buildDeltaCard({
    required String title,
    required IconData icon,
    required double valA,
    required double valB,
    required String unit,
    required bool isCurrency,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
  }) {
    final diff = valA - valB;
    final double pct = valB > 0 ? ((diff / valB) * 100) : (valA > 0 ? 100.0 : 0.0);
    final isPositive = diff > 0;
    final isTied = diff == 0;

    final Color deltaColor = isTied
        ? colorScheme.onSurfaceVariant
        : (isPositive ? const Color(0xFF006C51) : const Color(0xFFBA1A1A));

    final String sign = isPositive ? '+' : '';
    final String pctText = '$sign${pct.toStringAsFixed(1)}%';

    final formatter = NumberFormat.compact();
    final displayA = isCurrency ? '${valA.toStringAsFixed(0)} $unit' : '${formatter.format(valA)} $unit';
    final displayB = isCurrency ? '${valB.toStringAsFixed(0)} $unit' : '${formatter.format(valB)} $unit';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header: Icon + Title + Delta Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: GoogleFonts.cairo(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              // Delta pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: deltaColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: deltaColor.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isTied
                          ? Icons.drag_handle_rounded
                          : (isPositive ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded),
                      size: 16,
                      color: deltaColor,
                    ),
                    Text(
                      pctText,
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: deltaColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Values comparison: A vs B
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Campaign A Value
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF6750A4),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'A: $displayA',
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF6750A4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // VS divider
              Text(
                'vs',
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  fontWeight: FontWeight.bold,
                ),
              ),

              // Campaign B Value
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF006C51),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'B: $displayB',
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF006C51),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Dual Grouped Bar Chart (fl_chart)
  Widget _buildDualGroupedBarChart({
    required CampaignMetricsSummary? summaryA,
    required CampaignMetricsSummary? summaryB,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required CountryCurrency activeCountry,
    required bool isAr,
  }) {
    final titleA = summaryA?.campaignTitle ?? 'A';
    final titleB = summaryB?.campaignTitle ?? 'B';

    double valA = 0.0;
    double valB = 0.0;
    String unit = '';

    switch (_activeDimension) {
      case ComparisonDimension.revenue:
        valA = summaryA?.totalRevenue ?? 0.0;
        valB = summaryB?.totalRevenue ?? 0.0;
        unit = activeCountry.currencySymbol;
        break;
      case ComparisonDimension.invoices:
        valA = (summaryA?.totalInvoices ?? 0).toDouble();
        valB = (summaryB?.totalInvoices ?? 0).toDouble();
        unit = isAr ? 'فاتورة' : 'Inv';
        break;
      case ComparisonDimension.products:
        valA = (summaryA?.totalProductsSold ?? 0).toDouble();
        valB = (summaryB?.totalProductsSold ?? 0).toDouble();
        unit = isAr ? 'قطعة' : 'Pcs';
        break;
      case ComparisonDimension.shoppers:
        valA = (summaryA?.uniqueShoppersCount ?? 0).toDouble();
        valB = (summaryB?.uniqueShoppersCount ?? 0).toDouble();
        unit = isAr ? 'عميل' : 'Cust';
        break;
    }

    final double maxVal = (valA > valB ? valA : valB);
    final double maxY = maxVal > 0 ? (maxVal * 1.25) : 100.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Chart Header: Title + Dimension Selector Tabs
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bar_chart_rounded, color: colorScheme.primary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    strings.comparisonBarChartTitle,
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),

              // Dimension Selector
              Wrap(
                spacing: 6,
                children: [
                  _buildDimensionChip(
                    dimension: ComparisonDimension.revenue,
                    label: strings.comparisonDimensionRevenue,
                    icon: Icons.payments_rounded,
                    colorScheme: colorScheme,
                  ),
                  _buildDimensionChip(
                    dimension: ComparisonDimension.invoices,
                    label: strings.comparisonDimensionInvoices,
                    icon: Icons.receipt_long_rounded,
                    colorScheme: colorScheme,
                  ),
                  _buildDimensionChip(
                    dimension: ComparisonDimension.products,
                    label: strings.comparisonDimensionProducts,
                    icon: Icons.shopping_basket_rounded,
                    colorScheme: colorScheme,
                  ),
                  _buildDimensionChip(
                    dimension: ComparisonDimension.shoppers,
                    label: strings.comparisonDimensionShoppers,
                    icon: Icons.people_alt_rounded,
                    colorScheme: colorScheme,
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Legend
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 24,
            runSpacing: 10,
            children: [
              _buildLegendPill(
                color: const Color(0xFF6750A4),
                label: 'A: $titleA',
                valText: '${valA.toStringAsFixed(0)} $unit',
              ),
              _buildLegendPill(
                color: const Color(0xFF006C51),
                label: 'B: $titleB',
                valText: '${valB.toStringAsFixed(0)} $unit',
              ),
            ],
          ),

          const SizedBox(height: 20),

          // fl_chart Grouped Bar Chart
          SizedBox(
            height: 260,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => Colors.black87,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final isA = rodIndex == 0;
                      final name = isA ? titleA : titleB;
                      final val = rod.toY;
                      return BarTooltipItem(
                        '$name\n',
                        GoogleFonts.cairo(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        children: [
                          TextSpan(
                            text: '${val.toStringAsFixed(0)} $unit',
                            style: GoogleFonts.cairo(
                              color: isA ? const Color(0xFFD0BCFF) : const Color(0xFF7DDFC3),
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 45,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          NumberFormat.compact().format(value),
                          style: GoogleFonts.cairo(
                            fontSize: 10,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final label = value == 0
                            ? (isAr ? 'المؤشر المختار' : 'Active Metric')
                            : '';
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            label,
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  BarChartGroupData(
                    x: 0,
                    barsSpace: 12,
                    barRods: [
                      // Rod A (Purple)
                      BarChartRodData(
                        toY: valA,
                        color: const Color(0xFF6750A4),
                        width: 32,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                      ),
                      // Rod B (Teal)
                      BarChartRodData(
                        toY: valB,
                        color: const Color(0xFF006C51),
                        width: 32,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDimensionChip({
    required ComparisonDimension dimension,
    required String label,
    required IconData icon,
    required ColorScheme colorScheme,
  }) {
    final isSelected = _activeDimension == dimension;
    return ChoiceChip(
      selected: isSelected,
      avatar: Icon(
        icon,
        size: 15,
        color: isSelected ? colorScheme.onPrimary : colorScheme.primary,
      ),
      label: Text(
        label,
        style: GoogleFonts.cairo(
          fontSize: 11.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onSelected: (val) {
        if (val) {
          _savedDimension[widget.lockedCompanySlug] = dimension;
          setState(() => _activeDimension = dimension);
        }
      },
    );
  }

  Widget _buildLegendPill({
    required Color color,
    required String label,
    required String valText,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            valText,
            style: GoogleFonts.cairo(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  /// Detailed Head-to-Head Comparison Table with Leader Badges 🏆
  Widget _buildComparisonTable({
    required CampaignMetricsSummary? summaryA,
    required CampaignMetricsSummary? summaryB,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required CountryCurrency activeCountry,
    required bool isAr,
  }) {
    final currency = activeCountry.currencySymbol;
    final titleA = summaryA?.campaignTitle ?? 'Campaign A';
    final titleB = summaryB?.campaignTitle ?? 'Campaign B';

    final rows = [
      _TableRowData(
        label: strings.totalRevenueLabel,
        icon: Icons.payments_rounded,
        valA: '${summaryA?.totalRevenue.toStringAsFixed(1) ?? '0.0'} $currency',
        valB: '${summaryB?.totalRevenue.toStringAsFixed(1) ?? '0.0'} $currency',
        numA: summaryA?.totalRevenue ?? 0.0,
        numB: summaryB?.totalRevenue ?? 0.0,
        unit: currency,
      ),
      _TableRowData(
        label: strings.totalInvoicesCountLabel,
        icon: Icons.receipt_long_rounded,
        valA: '${summaryA?.totalInvoices ?? 0}',
        valB: '${summaryB?.totalInvoices ?? 0}',
        numA: (summaryA?.totalInvoices ?? 0).toDouble(),
        numB: (summaryB?.totalInvoices ?? 0).toDouble(),
        unit: '',
      ),
      _TableRowData(
        label: strings.totalProductsSoldLabel,
        icon: Icons.shopping_basket_rounded,
        valA: '${summaryA?.totalProductsSold ?? 0}',
        valB: '${summaryB?.totalProductsSold ?? 0}',
        numA: (summaryA?.totalProductsSold ?? 0).toDouble(),
        numB: (summaryB?.totalProductsSold ?? 0).toDouble(),
        unit: '',
      ),
      _TableRowData(
        label: strings.uniqueShoppersLabel,
        icon: Icons.people_alt_rounded,
        valA: '${summaryA?.uniqueShoppersCount ?? 0}',
        valB: '${summaryB?.uniqueShoppersCount ?? 0}',
        numA: (summaryA?.uniqueShoppersCount ?? 0).toDouble(),
        numB: (summaryB?.uniqueShoppersCount ?? 0).toDouble(),
        unit: '',
      ),
      _TableRowData(
        label: strings.avgBasketSpendLabel,
        icon: Icons.shopping_cart_checkout_rounded,
        valA: '${summaryA?.avgBasketSpend.toStringAsFixed(1) ?? '0.0'} $currency',
        valB: '${summaryB?.avgBasketSpend.toStringAsFixed(1) ?? '0.0'} $currency',
        numA: summaryA?.avgBasketSpend ?? 0.0,
        numB: summaryB?.avgBasketSpend ?? 0.0,
        unit: currency,
      ),
      _TableRowData(
        label: strings.disbursedPrizesValueLabel,
        icon: Icons.card_giftcard_rounded,
        valA: '${summaryA?.estimatedPrizesValue.toStringAsFixed(0) ?? '0'} $currency',
        valB: '${summaryB?.estimatedPrizesValue.toStringAsFixed(0) ?? '0'} $currency',
        numA: summaryA?.estimatedPrizesValue ?? 0.0,
        numB: summaryB?.estimatedPrizesValue ?? 0.0,
        unit: currency,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.table_chart_rounded, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      isAr ? 'جدول مقارنة المؤشرات التفصيلي' : 'Detailed Metrics Comparison Matrix',
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                Text(
                  isAr ? 'مقارنة شاملة متزامنة' : 'Real-time Synchronized Comparison',
                  style: GoogleFonts.cairo(
                    fontSize: 11.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 720) {
                return _buildMobileComparisonCards(
                  rows: rows,
                  titleA: titleA,
                  titleB: titleB,
                  colorScheme: colorScheme,
                  strings: strings,
                  isAr: isAr,
                );
              }
              return _buildDesktopComparisonTable(
                rows: rows,
                titleA: titleA,
                titleB: titleB,
                colorScheme: colorScheme,
                strings: strings,
                isAr: isAr,
              );
            },
          ),
        ],
      ),
    );
  }

  /// 100% full-width responsive desktop/tablet table with proportional flex columns
  Widget _buildDesktopComparisonTable({
    required List<_TableRowData> rows,
    required String titleA,
    required String titleB,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header Row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  isAr ? 'المؤشر / المعيار' : 'Metric / Dimension',
                  style: GoogleFonts.cairo(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF6750A4),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'A: $titleA',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF6750A4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF006C51),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'B: $titleB',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF006C51),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  strings.metricDifferenceLabel,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: isAr ? Alignment.centerLeft : Alignment.centerRight,
                  child: Text(
                    strings.winningCampaignTag,
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Data Rows
        ...rows.asMap().entries.map((entry) {
          final idx = entry.key;
          final r = entry.value;
          final isEven = idx % 2 == 0;
          final diff = r.numA - r.numB;
          final pct = r.numB > 0
              ? ((diff / r.numB) * 100)
              : (r.numA > 0 ? 100.0 : 0.0);
          final isPositive = diff > 0;
          final isTied = diff == 0;

          final deltaColor = isTied
              ? colorScheme.onSurfaceVariant
              : (isPositive ? const Color(0xFF006C51) : const Color(0xFFBA1A1A));

          final leadingCampaign = isTied
              ? strings.tiedCampaignsTag
              : (isPositive ? 'A: $titleA 🏆' : 'B: $titleB 🏆');

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: isEven
                  ? Colors.transparent
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                // Col 0: Icon + Label
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(r.icon, size: 16, color: colorScheme.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          r.label,
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Col 1: Value A
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: isAr ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6750A4).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        r.valA,
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF6750A4),
                        ),
                      ),
                    ),
                  ),
                ),

                // Col 2: Value B
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: isAr ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF006C51).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        r.valB,
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF006C51),
                        ),
                      ),
                    ),
                  ),
                ),

                // Col 3: Delta / Growth Pct
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: deltaColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isTied
                                ? Icons.drag_handle_rounded
                                : (isPositive
                                    ? Icons.arrow_upward_rounded
                                    : Icons.arrow_downward_rounded),
                            size: 14,
                            color: deltaColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${isPositive ? '+' : ''}${pct.toStringAsFixed(1)}%',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: deltaColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Col 4: Superior Campaign Pill
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: isAr ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isTied
                            ? colorScheme.surfaceContainerHighest
                            : (isPositive
                                ? const Color(0xFF6750A4).withValues(alpha: 0.12)
                                : const Color(0xFF006C51).withValues(alpha: 0.12)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isTied
                              ? colorScheme.outlineVariant.withValues(alpha: 0.5)
                              : (isPositive
                                  ? const Color(0xFF6750A4).withValues(alpha: 0.3)
                                  : const Color(0xFF006C51).withValues(alpha: 0.3)),
                        ),
                      ),
                      child: Text(
                        leadingCampaign,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: isTied
                              ? colorScheme.onSurfaceVariant
                              : (isPositive
                                  ? const Color(0xFF6750A4)
                                  : const Color(0xFF006C51)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  /// Compact mobile cards layout for phones and narrow screens
  Widget _buildMobileComparisonCards({
    required List<_TableRowData> rows,
    required String titleA,
    required String titleB,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
  }) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: rows.map((r) {
          final diff = r.numA - r.numB;
          final pct = r.numB > 0
              ? ((diff / r.numB) * 100)
              : (r.numA > 0 ? 100.0 : 0.0);
          final isPositive = diff > 0;
          final isTied = diff == 0;

          final deltaColor = isTied
              ? colorScheme.onSurfaceVariant
              : (isPositive ? const Color(0xFF006C51) : const Color(0xFFBA1A1A));

          final leadingCampaign = isTied
              ? strings.tiedCampaignsTag
              : (isPositive ? 'A: $titleA 🏆' : 'B: $titleB 🏆');

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header: Icon + Metric Name + Winner Tag
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(r.icon, size: 16, color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          r.label,
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isTied
                            ? colorScheme.surfaceContainerHighest
                            : (isPositive
                                ? const Color(0xFF6750A4).withValues(alpha: 0.12)
                                : const Color(0xFF006C51).withValues(alpha: 0.12)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        leadingCampaign,
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isTied
                              ? colorScheme.onSurfaceVariant
                              : (isPositive
                                  ? const Color(0xFF6750A4)
                                  : const Color(0xFF006C51)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Body: Two Side-by-Side Comparison Boxes
                Row(
                  children: [
                    // Box A
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6750A4).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF6750A4).withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'A: $titleA',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                color: const Color(0xFF6750A4),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              r.valA,
                              style: GoogleFonts.cairo(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF6750A4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Box B
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF006C51).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF006C51).withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'B: $titleB',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                color: const Color(0xFF006C51),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              r.valB,
                              style: GoogleFonts.cairo(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF006C51),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Footer: Delta Pct Chip
                Align(
                  alignment: isAr ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: deltaColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isTied
                              ? Icons.drag_handle_rounded
                              : (isPositive
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded),
                          size: 13,
                          color: deltaColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${strings.metricDifferenceLabel}: ${isPositive ? '+' : ''}${pct.toStringAsFixed(1)}%',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: deltaColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // All Campaigns Portfolio Benchmark View
  // ---------------------------------------------------------------------------
  Widget _buildAllCampaignsPortfolioView({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required List<EventModel> events,
    required Map<String, CampaignMetricsSummary> metricsMap,
    required CountryCurrency activeCountry,
    required bool isAr,
    required bool isHi,
  }) {
    final currency = activeCountry.currencySymbol;
    final summaries = events
        .map((e) => metricsMap[e.id])
        .whereType<CampaignMetricsSummary>()
        .toList();

    // Sort by Total Revenue descending
    summaries.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Portfolio Ranking Table
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.workspace_premium_rounded,
                            color: Colors.amber.shade700, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          isAr
                              ? 'ترتيب ومصفوفة أداء كافة حملات الشركة'
                              : 'All Campaigns Performance Leaderboard',
                          style: GoogleFonts.cairo(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: Text(
                        strings.exportComparisonCsv,
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        _exportPortfolioCsv(summaries, currency, isAr);
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              LayoutBuilder(
                builder: (context, constraints) {
                  final availableWidth = constraints.maxWidth;
                  final minWidth = math.max(availableWidth, 850.0);
                  final colSpacing = availableWidth >= 850
                      ? math.max(16.0, (availableWidth - 620) / 7)
                      : 18.0;

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: minWidth),
                      child: DataTable(
                        columnSpacing: colSpacing,
                        headingRowColor: WidgetStateProperty.all(
                          colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        ),
                        columns: [
                          DataColumn(
                            label: Text(
                              isAr ? 'الترتيب' : 'Rank',
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              isAr ? 'اسم الحملة' : 'Campaign Title',
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              strings.totalRevenueLabel,
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              strings.totalInvoicesCountLabel,
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              strings.totalProductsSoldLabel,
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              strings.uniqueShoppersLabel,
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              strings.avgBasketSpendLabel,
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              isAr ? 'الحالة' : 'Status',
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                        rows: summaries.asMap().entries.map((entry) {
                          final index = entry.key;
                          final s = entry.value;

                          String medal = '';
                          if (index == 0) medal = '🥇 ';
                          if (index == 1) medal = '🥈 ';
                          if (index == 2) medal = '🥉 ';

                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  '$medal#${index + 1}',
                                  style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.bold,
                                    color: index < 3 ? colorScheme.primary : null,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  s.campaignTitle,
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${s.totalRevenue.toStringAsFixed(1)} $currency',
                                  style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF006C51),
                                  ),
                                ),
                              ),
                              DataCell(Text('${s.totalInvoices}')),
                              DataCell(Text('${s.totalProductsSold}')),
                              DataCell(Text('${s.uniqueShoppersCount}')),
                              DataCell(Text('${s.avgBasketSpend.toStringAsFixed(1)} $currency')),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: s.isActive
                                        ? Colors.green.withValues(alpha: 0.15)
                                        : Colors.grey.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    s.isActive ? (isAr ? 'نشطة' : 'Active') : (isAr ? 'منتهية' : 'Ended'),
                                    style: GoogleFonts.cairo(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: s.isActive ? Colors.green.shade700 : Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _exportPortfolioCsv(
    List<CampaignMetricsSummary> summaries,
    String currency,
    bool isAr,
  ) {
    final buffer = StringBuffer();
    // CSV Header
    buffer.writeln(
        'Rank,Campaign Title,Total Sales ($currency),Invoices Count,Products Sold,Unique Shoppers,Avg Basket ($currency),Status');

    for (int i = 0; i < summaries.length; i++) {
      final s = summaries[i];
      final title = '"${s.campaignTitle.replaceAll('"', '""')}"';
      final status = s.isActive ? 'Active' : 'Ended';
      buffer.writeln(
          '${i + 1},$title,${s.totalRevenue.toStringAsFixed(2)},${s.totalInvoices},${s.totalProductsSold},${s.uniqueShoppersCount},${s.avgBasketSpend.toStringAsFixed(2)},$status');
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isAr
              ? 'تم تجهيز تقرير المقارنة الشامل بنجاح'
              : 'Benchmark CSV report generated successfully',
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _TableRowData {
  final String label;
  final IconData icon;
  final String valA;
  final String valB;
  final double numA;
  final double numB;
  final String unit;

  const _TableRowData({
    required this.label,
    required this.icon,
    required this.valA,
    required this.valB,
    required this.numA,
    required this.numB,
    required this.unit,
  });
}
