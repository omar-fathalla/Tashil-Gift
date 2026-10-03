import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/country_currency_config.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/widgets/m3_button_groups.dart';
import '../../../core/widgets/switch_point_branding.dart';
import '../../admin/domain/event_model.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/m3_adaptive_scaffold.dart';

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
enum ComparisonDimension { revenue, invoices, products, shoppers, velocity, basketSpend }

/// Data model representing an auto-detected weekend activation wave or period cluster
class CampaignWeekendCluster {
  final String id;
  final int waveNumber;
  final DateTime startDate;
  final DateTime endDate;
  final String label;
  final List<String> activeDates;
  final int invoiceCount;
  final double totalSales;

  const CampaignWeekendCluster({
    required this.id,
    required this.waveNumber,
    required this.startDate,
    required this.endDate,
    required this.label,
    required this.activeDates,
    required this.invoiceCount,
    required this.totalSales,
  });

  int get activeDaysCount => activeDates.isNotEmpty ? activeDates.length : 1;
}

/// Aggregated metrics for a specific intra-campaign activation period or weekend wave
class CampaignPeriodMetrics {
  final String periodId;
  final String periodLabel;
  final String campaignId;
  final String campaignTitle;
  final DateTime startDate;
  final DateTime endDate;
  final int activeDaysCount;
  final double totalRevenue;
  final int totalInvoices;
  final int totalProductsSold;
  final int uniqueShoppersCount;
  final int claimedPrizesCount;
  final double estimatedPrizesValue;

  const CampaignPeriodMetrics({
    required this.periodId,
    required this.periodLabel,
    required this.campaignId,
    required this.campaignTitle,
    required this.startDate,
    required this.endDate,
    required this.activeDaysCount,
    required this.totalRevenue,
    required this.totalInvoices,
    required this.totalProductsSold,
    required this.uniqueShoppersCount,
    required this.claimedPrizesCount,
    required this.estimatedPrizesValue,
  });

  double get avgBasketSpend =>
      totalInvoices > 0 ? (totalRevenue / totalInvoices) : 0.0;
  double get avgUnitsPerBasket =>
      totalInvoices > 0 ? (totalProductsSold / totalInvoices) : 0.0;
  double get dailySalesVelocity =>
      activeDaysCount > 0 ? (totalRevenue / activeDaysCount) : totalRevenue;
  double get dailyInvoicesVelocity =>
      activeDaysCount > 0 ? (totalInvoices / activeDaysCount) : totalInvoices.toDouble();
}

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
  static final Map<String, int> _savedComparisonMode = {};
  static final Map<String, String> _savedIntraCampaign = {};
  static final Map<String, String> _savedClusterA = {};
  static final Map<String, String> _savedClusterB = {};
  static final Map<String, int> _savedIntraSubView = {};
  static final Map<String, bool> _savedIsCustomPeriod = {};

  String? _selectedCampaignAId;
  String? _selectedCampaignBId;
  int _comparisonMode = 2; // 2: All Campaigns Portfolio (Default), 0: Head-to-Head (A vs B), 1: Intra-Campaign Waves
  bool _showTableView = true; // Default is Table View (Image 2) on all devices

  // Intra-Campaign Weekend & Period Analytics State
  String? _selectedIntraCampaignId;
  String? _selectedClusterAId;
  String? _selectedClusterBId;
  int _intraSubViewMode = 0; // 0: Period vs Period Head-to-Head, 1: All Weekends Progression Matrix
  bool _isCustomPeriodMode = false;
  DateTimeRange? _customRangeA;
  DateTimeRange? _customRangeB;
  ComparisonDimension _intraDimension = ComparisonDimension.revenue;

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
    if (widget.companyEvents != null && widget.companyEvents!.length <= 1) {
      _selectedCampaignBId = null;
    }
    _comparisonMode = _savedComparisonMode[slug] ?? 2;
    _selectedIntraCampaignId = _savedIntraCampaign[slug] ?? widget.initialEventId ?? _selectedCampaignAId;
    _selectedClusterAId = _savedClusterA[slug];
    _selectedClusterBId = _savedClusterB[slug];
    _intraSubViewMode = _savedIntraSubView[slug] ?? 0;
    _isCustomPeriodMode = _savedIsCustomPeriod[slug] ?? false;
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

    // 2. Resolve Campaign B (Must NOT duplicate Campaign A)
    if (events.length <= 1) {
      _selectedCampaignBId = null;
      _savedCampaignB.remove(slug);
    } else {
      if (_selectedCampaignBId == null ||
          !events.any((e) => e.id == _selectedCampaignBId) ||
          _selectedCampaignBId == _selectedCampaignAId) {
        final savedB = _savedCampaignB[slug];
        if (savedB != null &&
            savedB != _selectedCampaignAId &&
            events.any((e) => e.id == savedB)) {
          _selectedCampaignBId = savedB;
        } else {
          final secondary = events.firstWhere(
            (e) => e.id != _selectedCampaignAId,
            orElse: () => events.first,
          );
          _selectedCampaignBId = secondary.id != _selectedCampaignAId ? secondary.id : null;
        }
        if (_selectedCampaignBId != null) {
          _savedCampaignB[slug] = _selectedCampaignBId!;
        } else {
          _savedCampaignB.remove(slug);
        }
      }
    }

    // 3. Resolve Intra Campaign
    if (_selectedIntraCampaignId == null ||
        !events.any((e) => e.id == _selectedIntraCampaignId)) {
      final savedIntra = _savedIntraCampaign[slug];
      if (savedIntra != null && events.any((e) => e.id == savedIntra)) {
        _selectedIntraCampaignId = savedIntra;
      } else {
        _selectedIntraCampaignId = _selectedCampaignAId ?? events.first.id;
      }
      _savedIntraCampaign[slug] = _selectedIntraCampaignId!;
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

    final slug = widget.lockedCompanySlug;
    final cachedEvents = _persistentEventsCache[slug] ?? widget.companyEvents;
    final cachedMetrics = _persistentMetricsCache[slug];

    if (firestore == null) {
      if (cachedEvents != null && cachedEvents.isNotEmpty) {
        _initializeCampaignSelections(cachedEvents);
        final metricsMap = cachedMetrics ??
            _computeMetrics(
              events: cachedEvents,
              invoiceDocs: const [],
            );
        return _buildMainScaffold(
          context: context,
          colorScheme: colorScheme,
          strings: strings,
          isAr: isAr,
          isHi: isHi,
          activeCountry: activeCountry,
          events: cachedEvents,
          metricsMap: metricsMap,
          effectiveDocs: const [],
        );
      }

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
    _ensureStreams(activeFirestore);

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

            return _buildMainScaffold(
              context: context,
              colorScheme: colorScheme,
              strings: strings,
              isAr: isAr,
              isHi: isHi,
              activeCountry: activeCountry,
              events: events,
              metricsMap: metricsMap,
              effectiveDocs: effectiveDocs,
            );
          },
        );
      },
    );
  }

  Widget _buildMainScaffold({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
    required bool isHi,
    required CountryCurrency activeCountry,
    required List<EventModel> events,
    required Map<String, CampaignMetricsSummary> metricsMap,
    required List<QueryDocumentSnapshot> effectiveDocs,
  }) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.isEmbedded
          ? null
          : SwitchPointHeader(
              subtitle: strings.campaignComparisonScreenTitle,
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Sticky Header Banner & Mode Selector (pinned at top for quick navigation across 3 comparison modes)
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 8),
            child: M3ContentBoundary(
              maxWidth: 1360.0,
              child: _buildScreenHeader(
                context: context,
                colorScheme: colorScheme,
                strings: strings,
                isAr: isAr,
                eventsCount: events.length,
              ),
            ),
          ),

          // 2. Scrollable Body Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 8, bottom: 28),
              child: M3ContentBoundary(
                maxWidth: 1360.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (events.length < 2 && _comparisonMode == 0) ...[
                      _buildSingleCampaignNotice(
                        colorScheme: colorScheme,
                        strings: strings,
                        isAr: isAr,
                      ),
                      const SizedBox(height: 18),
                    ],

                    // Mode Content
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
                    ] else if (_comparisonMode == 1) ...[
                      // Intra-Campaign Weekend & Period Analytics
                      _buildIntraCampaignWeekendView(
                        context: context,
                        colorScheme: colorScheme,
                        strings: strings,
                        events: events,
                        invoiceDocs: effectiveDocs,
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
        ],
      ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 720;
        final isMobile = constraints.maxWidth < 500;

        return Container(
          padding: EdgeInsets.all(isCompact ? 14 : 20),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(isCompact ? 18 : 24),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: isMobile ? 40 : 48,
                    height: isMobile ? 40 : 48,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
                    ),
                    child: Icon(
                      Icons.compare_arrows_rounded,
                      color: colorScheme.primary,
                      size: isMobile ? 22 : 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              strings.campaignComparisonScreenTitle,
                              style: GoogleFonts.cairo(
                                fontSize: isMobile ? 15.5 : 18,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
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
                        const SizedBox(height: 2),
                        Text(
                          strings.campaignComparisonScreenSubtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cairo(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isCompact) ...[
                    const SizedBox(width: 16),
                    M3ConnectedButtonGroup<int>(
                      height: 44,
                      borderRadius: 14,
                      segments: [
                        M3ButtonSegment<int>(
                          value: 2,
                          icon: Icons.leaderboard_rounded,
                          label: strings.allCampaignsPortfolioTab,
                          tooltip: strings.allCampaignsPortfolioTab,
                        ),
                        M3ButtonSegment<int>(
                          value: 0,
                          icon: Icons.compare_arrows_rounded,
                          label: strings.headToHeadComparisonTab,
                          tooltip: strings.headToHeadComparisonTab,
                        ),
                        M3ButtonSegment<int>(
                          value: 1,
                          icon: Icons.date_range_rounded,
                          label: strings.intraCampaignWeekendTab,
                          tooltip: strings.intraCampaignWeekendTab,
                        ),
                      ],
                      selectedValue: _comparisonMode,
                      onSelected: (newMode) {
                        _savedComparisonMode[widget.lockedCompanySlug] = newMode;
                        setState(() {
                          _comparisonMode = newMode;
                        });
                      },
                    ),
                  ],
                ],
              ),
              if (isCompact) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: M3ConnectedButtonGroup<int>(
                    height: 42,
                    borderRadius: 12,
                    isExpanded: true,
                    segments: [
                      M3ButtonSegment<int>(
                        value: 2,
                        icon: Icons.leaderboard_rounded,
                        label: strings.allCampaignsPortfolioTab,
                        tooltip: strings.allCampaignsPortfolioTab,
                      ),
                      M3ButtonSegment<int>(
                        value: 0,
                        icon: Icons.compare_arrows_rounded,
                        label: strings.headToHeadComparisonTab,
                        tooltip: strings.headToHeadComparisonTab,
                      ),
                      M3ButtonSegment<int>(
                        value: 1,
                        icon: Icons.date_range_rounded,
                        label: strings.intraCampaignWeekendTab,
                        tooltip: strings.intraCampaignWeekendTab,
                      ),
                    ],
                    selectedValue: _comparisonMode,
                    onSelected: (newMode) {
                      _savedComparisonMode[widget.lockedCompanySlug] = newMode;
                      setState(() {
                        _comparisonMode = newMode;
                      });
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
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
    final summaryB = (_selectedCampaignBId != null && _selectedCampaignBId != _selectedCampaignAId)
        ? metricsMap[_selectedCampaignBId]
        : null;

    final isSameCampaign = _selectedCampaignAId == _selectedCampaignBId && events.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Dual Campaign Selectors
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 700;
            return Container(
              padding: EdgeInsets.all(isNarrow ? 10 : 18),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(isNarrow ? 16 : 20),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                    builder: (context) {
                      final dropA = _buildCampaignPicker(
                        label: strings.selectCampaignA,
                        badgeColor: const Color(0xFF6750A4),
                        selectedId: _selectedCampaignAId,
                        events: events,
                        isCompact: isNarrow,
                        onChanged: (id) {
                          if (id != null) {
                            _savedCampaignA[widget.lockedCompanySlug] = id;
                            setState(() {
                              _selectedCampaignAId = id;
                              if (_selectedCampaignBId == id) {
                                final others = events.where((e) => e.id != id).toList();
                                _selectedCampaignBId = others.isNotEmpty ? others.first.id : null;
                                if (_selectedCampaignBId != null) {
                                  _savedCampaignB[widget.lockedCompanySlug] = _selectedCampaignBId!;
                                } else {
                                  _savedCampaignB.remove(widget.lockedCompanySlug);
                                }
                              }
                            });
                          }
                        },
                        colorScheme: colorScheme,
                        isAr: isAr,
                      );

                      final availableEventsForB = events.where((e) => e.id != _selectedCampaignAId).toList();
                      final isBDisabled = events.length <= 1 || availableEventsForB.isEmpty;

                      final dropB = _buildCampaignPicker(
                        label: strings.selectCampaignB,
                        badgeColor: const Color(0xFF006C51),
                        selectedId: _selectedCampaignBId,
                        events: availableEventsForB,
                        isDisabled: isBDisabled,
                        isCompact: isNarrow,
                        onChanged: (id) {
                          if (id != null) {
                            _savedCampaignB[widget.lockedCompanySlug] = id;
                            setState(() => _selectedCampaignBId = id);
                          }
                        },
                        colorScheme: colorScheme,
                        isAr: isAr,
                      );

                      final canSwap = events.length > 1 &&
                          _selectedCampaignBId != null &&
                          _selectedCampaignBId != _selectedCampaignAId;

                      if (isNarrow) {
                        return Column(
                          children: [
                            dropA,
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Center(
                                child: InkWell(
                                  onTap: canSwap
                                      ? () {
                                          setState(() {
                                            final temp = _selectedCampaignAId;
                                            _selectedCampaignAId = _selectedCampaignBId;
                                            _selectedCampaignBId = temp;
                                            if (_selectedCampaignAId != null) {
                                              _savedCampaignA[widget.lockedCompanySlug] = _selectedCampaignAId!;
                                            }
                                            if (_selectedCampaignBId != null) {
                                              _savedCampaignB[widget.lockedCompanySlug] = _selectedCampaignBId!;
                                            }
                                          });
                                        }
                                      : null,
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.swap_vert_rounded,
                                      color: canSwap ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.4),
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            dropB,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: dropA),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: InkWell(
                              onTap: canSwap
                                  ? () {
                                      setState(() {
                                        final temp = _selectedCampaignAId;
                                        _selectedCampaignAId = _selectedCampaignBId;
                                        _selectedCampaignBId = temp;
                                        if (_selectedCampaignAId != null) {
                                          _savedCampaignA[widget.lockedCompanySlug] = _selectedCampaignAId!;
                                        }
                                        if (_selectedCampaignBId != null) {
                                          _savedCampaignB[widget.lockedCompanySlug] = _selectedCampaignBId!;
                                        }
                                      });
                                    }
                                  : null,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.compare_arrows_rounded,
                                  size: 22,
                                  color: canSwap ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
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
            );
          },
        ),

        const SizedBox(height: 20),

        // 2. Comprehensive Visual Performance Comparison Report (Multi-Metric Bar Chart)
        _buildHeadToHeadVisualReport(
          summaryA: summaryA,
          summaryB: summaryB,
          colorScheme: colorScheme,
          strings: strings,
          activeCountry: activeCountry,
          isAr: isAr,
        ),

        const SizedBox(height: 24),

        // 3. Detailed Comparison Metrics Table
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

  /// Campaign Picker Dropdown with distinct badge color, compact mobile styling and disabled support
  Widget _buildCampaignPicker({
    required String label,
    required Color badgeColor,
    required String? selectedId,
    required List<EventModel> events,
    required ValueChanged<String?> onChanged,
    required ColorScheme colorScheme,
    required bool isAr,
    bool isDisabled = false,
    bool isCompact = false,
  }) {
    final effectiveBadgeColor = isDisabled ? colorScheme.outline : badgeColor;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 10 : 14,
        vertical: isCompact ? 5 : 10,
      ),
      decoration: BoxDecoration(
        color: isDisabled ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3) : colorScheme.surface,
        borderRadius: BorderRadius.circular(isCompact ? 12 : 16),
        border: Border.all(
          color: effectiveBadgeColor.withValues(alpha: isDisabled ? 0.35 : 0.6),
          width: isCompact ? 1.2 : 1.5,
        ),
      ),
      child: isCompact
          ? Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: effectiveBadgeColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: effectiveBadgeColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: (isDisabled || events.isEmpty)
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.info_outline_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                isAr ? 'لم يتم إنشاء حملة ثانية بعد' : 'No 2nd campaign',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        )
                      : DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: (selectedId != null && events.any((e) => e.id == selectedId)) ? selectedId : null,
                            hint: Text(
                              isAr ? 'اختر حملة للمقارنة' : 'Select campaign',
                              style: GoogleFonts.cairo(
                                fontSize: 11.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            isDense: true,
                            isExpanded: true,
                            icon: Icon(Icons.arrow_drop_down_rounded, color: colorScheme.primary, size: 20),
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
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    if (event.isActive) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                        child: Text(
                                          isAr ? 'نشطة' : 'Active',
                                          style: GoogleFonts.cairo(
                                            fontSize: 9,
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
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: effectiveBadgeColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: effectiveBadgeColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (isDisabled || events.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isAr
                                ? 'لم يتم إنشاء حملة ثانية بعد للمقارنة'
                                : 'No second campaign created yet for comparison',
                            style: GoogleFonts.cairo(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: (selectedId != null && events.any((e) => e.id == selectedId)) ? selectedId : null,
                      hint: Text(
                        isAr ? 'اختر حملة للمقارنة' : 'Select a campaign to compare',
                        style: GoogleFonts.cairo(
                          fontSize: 12.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      isExpanded: true,
                      icon: Icon(Icons.arrow_drop_down_rounded, color: colorScheme.primary),
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

  // ---------------------------------------------------------------------------
  // Visual Performance Comparison Report Suite (Charts, Columns & Shares)
  // Replaces plain cards with rich visual columns, proportional bars & multi-metric charts
  // ---------------------------------------------------------------------------

  String _getShortMetricLabel(String title, bool isAr) {
    if (title.contains('سرعة') || title.contains('كثافة') || title.toLowerCase().contains('velocity')) {
      return isAr ? 'السرعة' : 'Velocity';
    }
    if (title.contains('مبيعات') || title.toLowerCase().contains('revenue')) {
      return isAr ? 'المبيعات' : 'Sales';
    }
    if (title.contains('فواتير') || title.toLowerCase().contains('invoice')) {
      return isAr ? 'الفواتير' : 'Invoices';
    }
    if (title.contains('منتجات') || title.toLowerCase().contains('product') || title.contains('قطع')) {
      return isAr ? 'المنتجات' : 'Units';
    }
    if (title.contains('متسوق') || title.contains('عملاء') || title.toLowerCase().contains('shopper')) {
      return isAr ? 'العملاء' : 'Shoppers';
    }
    if (title.contains('سلة') || title.toLowerCase().contains('basket')) {
      return isAr ? 'السلة' : 'Basket';
    }
    if (title.contains('جوائز') || title.toLowerCase().contains('prize')) {
      return isAr ? 'الجوائز' : 'Prizes';
    }
    return title;
  }

  Widget _buildHeadToHeadVisualReport({
    required CampaignMetricsSummary? summaryA,
    required CampaignMetricsSummary? summaryB,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required CountryCurrency activeCountry,
    required bool isAr,
  }) {
    final currency = activeCountry.currencySymbol;
    final labelA = summaryA?.campaignTitle ?? (isAr ? 'الحملة (A)' : 'Campaign A');
    final labelB = summaryB?.campaignTitle ?? (isAr ? 'الحملة (B)' : 'Campaign B');

    final daysA = (summaryA?.startDate != null && summaryA?.endDate != null)
        ? math.max(1, summaryA!.endDate!.difference(summaryA.startDate!).inDays + 1)
        : 1;
    final daysB = (summaryB?.startDate != null && summaryB?.endDate != null)
        ? math.max(1, summaryB!.endDate!.difference(summaryB.startDate!).inDays + 1)
        : 1;
    final velocityA = (summaryA?.totalRevenue ?? 0.0) / daysA;
    final velocityB = (summaryB?.totalRevenue ?? 0.0) / daysB;

    final metrics = [
      _VisualMetricItem(
        title: strings.totalRevenueLabel,
        icon: Icons.payments_rounded,
        valA: summaryA?.totalRevenue ?? 0.0,
        valB: summaryB?.totalRevenue ?? 0.0,
        unit: currency,
        isCurrency: true,
      ),
      _VisualMetricItem(
        title: strings.totalInvoicesCountLabel,
        icon: Icons.receipt_long_rounded,
        valA: (summaryA?.totalInvoices ?? 0).toDouble(),
        valB: (summaryB?.totalInvoices ?? 0).toDouble(),
        unit: isAr ? 'فاتورة' : 'Invoices',
      ),
      _VisualMetricItem(
        title: strings.totalProductsSoldLabel,
        icon: Icons.shopping_basket_rounded,
        valA: (summaryA?.totalProductsSold ?? 0).toDouble(),
        valB: (summaryB?.totalProductsSold ?? 0).toDouble(),
        unit: isAr ? 'قطعة' : 'Units',
      ),
      _VisualMetricItem(
        title: strings.uniqueShoppersLabel,
        icon: Icons.people_alt_rounded,
        valA: (summaryA?.uniqueShoppersCount ?? 0).toDouble(),
        valB: (summaryB?.uniqueShoppersCount ?? 0).toDouble(),
        unit: isAr ? 'متسوق' : 'Shoppers',
      ),
      _VisualMetricItem(
        title: strings.dailySalesVelocityLabel,
        icon: Icons.speed_rounded,
        valA: velocityA,
        valB: velocityB,
        unit: '$currency/${isAr ? "يوم" : "day"}',
        isCurrency: true,
      ),
      _VisualMetricItem(
        title: strings.avgBasketSpendLabel,
        icon: Icons.shopping_cart_checkout_rounded,
        valA: summaryA?.avgBasketSpend ?? 0.0,
        valB: summaryB?.avgBasketSpend ?? 0.0,
        unit: currency,
        isCurrency: true,
      ),
      _VisualMetricItem(
        title: strings.disbursedPrizesValueLabel,
        icon: Icons.card_giftcard_rounded,
        valA: summaryA?.estimatedPrizesValue ?? 0.0,
        valB: summaryB?.estimatedPrizesValue ?? 0.0,
        unit: currency,
        isCurrency: true,
      ),
    ];

    return _buildUnifiedVisualComparisonReport(
      labelA: labelA,
      labelB: labelB,
      metrics: metrics,
      colorScheme: colorScheme,
      strings: strings,
      activeCountry: activeCountry,
      isAr: isAr,
    );
  }

  Widget _buildIntraPeriodVisualReport({
    required CampaignPeriodMetrics metricsA,
    required CampaignPeriodMetrics metricsB,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required CountryCurrency activeCountry,
    required bool isAr,
  }) {
    final currency = activeCountry.currencySymbol;
    final labelA = metricsA.periodLabel;
    final labelB = metricsB.periodLabel;

    final metrics = [
      _VisualMetricItem(
        title: strings.totalRevenueLabel,
        icon: Icons.payments_rounded,
        valA: metricsA.totalRevenue,
        valB: metricsB.totalRevenue,
        unit: currency,
        isCurrency: true,
      ),
      _VisualMetricItem(
        title: strings.totalInvoicesCountLabel,
        icon: Icons.receipt_long_rounded,
        valA: metricsA.totalInvoices.toDouble(),
        valB: metricsB.totalInvoices.toDouble(),
        unit: isAr ? 'فاتورة' : 'Invoices',
      ),
      _VisualMetricItem(
        title: strings.totalProductsSoldLabel,
        icon: Icons.shopping_basket_rounded,
        valA: metricsA.totalProductsSold.toDouble(),
        valB: metricsB.totalProductsSold.toDouble(),
        unit: isAr ? 'قطعة' : 'Units',
      ),
      _VisualMetricItem(
        title: strings.uniqueShoppersLabel,
        icon: Icons.people_alt_rounded,
        valA: metricsA.uniqueShoppersCount.toDouble(),
        valB: metricsB.uniqueShoppersCount.toDouble(),
        unit: isAr ? 'متسوق' : 'Shoppers',
      ),
      _VisualMetricItem(
        title: strings.dailySalesVelocityLabel,
        icon: Icons.speed_rounded,
        valA: metricsA.dailySalesVelocity,
        valB: metricsB.dailySalesVelocity,
        unit: '$currency/${isAr ? "يوم" : "day"}',
        isCurrency: true,
      ),
      _VisualMetricItem(
        title: strings.avgBasketSpendLabel,
        icon: Icons.shopping_cart_checkout_rounded,
        valA: metricsA.avgBasketSpend,
        valB: metricsB.avgBasketSpend,
        unit: currency,
        isCurrency: true,
      ),
      _VisualMetricItem(
        title: strings.disbursedPrizesValueLabel,
        icon: Icons.card_giftcard_rounded,
        valA: metricsA.estimatedPrizesValue,
        valB: metricsB.estimatedPrizesValue,
        unit: currency,
        isCurrency: true,
      ),
    ];

    final shortenedA = _formatShortenedPeriodLegend(periodLabel: labelA, prefixLetter: 'A');
    final shortenedB = _formatShortenedPeriodLegend(periodLabel: labelB, prefixLetter: 'B');

    return _buildUnifiedVisualComparisonReport(
      labelA: shortenedA,
      labelB: shortenedB,
      metrics: metrics,
      colorScheme: colorScheme,
      strings: strings,
      activeCountry: activeCountry,
      isAr: isAr,
    );
  }

  Widget _buildUnifiedVisualComparisonReport({
    required String labelA,
    required String labelB,
    required List<_VisualMetricItem> metrics,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required CountryCurrency activeCountry,
    required bool isAr,
  }) {
    return Container(
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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header with title and subtitle
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.auto_graph_rounded,
                  color: colorScheme.primary,
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
                      strings.visualPerformanceComparisonTitle,
                      style: GoogleFonts.cairo(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      strings.visualPerformanceComparisonSubtitle,
                      style: GoogleFonts.cairo(
                        fontSize: 11.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // 2. Legend Pills (A vs B)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildLegendPill(
                color: const Color(0xFF6750A4),
                label: 'A: $labelA',
                valText: '',
              ),
              _buildLegendPill(
                color: const Color(0xFF006C51),
                label: 'B: $labelB',
                valText: '',
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 3. Multi-Metric Grouped Bar Chart
          _buildMultiMetricGroupedBarChart(
            metrics: metrics,
            labelA: labelA,
            labelB: labelB,
            colorScheme: colorScheme,
            strings: strings,
            isAr: isAr,
          ),
        ],
      ),
    );
  }

  Widget _buildMultiMetricGroupedBarChart({
    required List<_VisualMetricItem> metrics,
    required String labelA,
    required String labelB,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
  }) {
    final chartMetrics = metrics.where((m) => m.valA > 0 || m.valB > 0).toList();
    final effectiveMetrics = chartMetrics.isEmpty ? metrics.take(5).toList() : chartMetrics;
    final hasSecondCampaign = labelB != 'لا توجد حملة ثانية' && labelB != 'No 2nd Campaign';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bar_chart_rounded, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    isAr ? 'مخطط مقارنة المؤشرات الشامل' : 'Performance Benchmark Chart',
                    style: GoogleFonts.cairo(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isAr ? 'مقياس الأداء المقارن' : 'Benchmark Index',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final double chartWidth = math.max(constraints.maxWidth, effectiveMetrics.length * 85.0);

              final bool isScrollable = chartWidth > constraints.maxWidth;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isScrollable)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.swipe_rounded, size: 14, color: colorScheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            isAr
                                ? 'اسحب أفقياً للاطلاع على كامل المؤشرات'
                                : 'Swipe horizontally to view all metrics',
                            style: GoogleFonts.cairo(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: SizedBox(
                      width: chartWidth,
                      height: 290,
                      child: BarChart(
                        BarChartData(
                          maxY: 125,
                          barTouchData: BarTouchData(
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipColor: (_) => colorScheme.surfaceContainerHighest,
                              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                final item = effectiveMetrics[groupIndex];
                                final isA = rodIndex == 0;
                                final name = isA ? labelA : labelB;
                                final rawVal = isA ? item.valA : item.valB;
                                final share = isA ? item.shareA : item.shareB;
                                final formattedVal = NumberFormat.compact().format(rawVal);

                                final textVal = (isA || rawVal > 0)
                                    ? '$name: $formattedVal ${item.unit} (${(share * 100).toStringAsFixed(1)}%)'
                                    : '$name: 0 ${item.unit} (0.0%)';

                                return BarTooltipItem(
                                  '${item.title}\n',
                                  GoogleFonts.cairo(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: textVal,
                                      style: GoogleFonts.cairo(
                                        color: isA ? const Color(0xFF6750A4) : const Color(0xFF006C51),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          titlesData: FlTitlesData(
                            show: true,
                            topTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 30,
                                getTitlesWidget: (value, meta) {
                                  final idx = value.toInt();
                                  if (idx >= 0 && idx < effectiveMetrics.length) {
                                    final item = effectiveMetrics[idx];
                                    final formattedA = NumberFormat.compact().format(item.valA);
                                    final formattedB = item.valB > 0
                                        ? NumberFormat.compact().format(item.valB)
                                        : '0';
                                    final showB = hasSecondCampaign && item.valB > 0;

                                    return FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Directionality(
                                        textDirection: TextDirection.ltr,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF6750A4).withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(5),
                                                border: Border.all(
                                                  color: const Color(0xFF6750A4).withValues(alpha: 0.4),
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Text(
                                                formattedA,
                                                style: GoogleFonts.cairo(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: const Color(0xFF6750A4),
                                                ),
                                              ),
                                            ),
                                            if (showB) ...[
                                              const SizedBox(width: 4),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF006C51).withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(5),
                                                  border: Border.all(
                                                    color: const Color(0xFF006C51).withValues(alpha: 0.4),
                                                    width: 0.8,
                                                  ),
                                                ),
                                                child: Text(
                                                  formattedB,
                                                  style: GoogleFonts.cairo(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: const Color(0xFF006C51),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 38,
                            getTitlesWidget: (value, meta) {
                              if (value % 25 == 0 && value <= 100) {
                                return Text(
                                  '${value.toInt()}%',
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
                            reservedSize: 36,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx >= 0 && idx < effectiveMetrics.length) {
                                final item = effectiveMetrics[idx];
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _getShortMetricLabel(item.title, isAr),
                                    style: GoogleFonts.cairo(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface,
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
                      barGroups: List.generate(effectiveMetrics.length, (idx) {
                        final item = effectiveMetrics[idx];

                        // Dynamic baseline score for Campaign A based on metric type and relative magnitude
                        double baseScoreA;
                        if (item.isCurrency) {
                          if (item.title.contains('مبيعات') && !item.title.contains('سرعة')) {
                            // Total macro sales
                            baseScoreA = item.valA > 0 ? 95.0 : 0.0;
                          } else if (item.title.contains('سرعة') || item.title.toLowerCase().contains('velocity')) {
                            // Sales velocity
                            baseScoreA = item.valA > 0 ? 64.0 : 0.0;
                          } else if (item.title.contains('سلة') || item.title.toLowerCase().contains('basket')) {
                            // Basket spend
                            baseScoreA = item.valA > 0 ? 52.0 : 0.0;
                          } else {
                            // Other currency (prizes, etc.)
                            baseScoreA = item.valA > 0 ? 35.0 : 0.0;
                          }
                        } else {
                          // Counts / Volume metrics (Products, Invoices, Shoppers)
                          final countItems = effectiveMetrics.where((m) => !m.isCurrency).toList();
                          final maxCount = countItems.fold<double>(
                            1.0,
                            (prev, elem) => math.max(prev, math.max(elem.valA, elem.valB)),
                          );
                          if (item.valA > 0 && maxCount > 0) {
                            baseScoreA = (item.valA / maxCount) * 55.0 + 32.0; // Scaled between 32% and 87%
                          } else {
                            baseScoreA = 0.0;
                          }
                        }

                        final double rodAY = baseScoreA.clamp(0.0, 100.0);

                        // Proportional score for Campaign B relative to Campaign A
                        final double rodBY;
                        if (item.valB <= 0) {
                          rodBY = 0.0;
                        } else if (item.valA <= 0) {
                          rodBY = 80.0;
                        } else {
                          rodBY = (rodAY * (item.valB / item.valA)).clamp(0.0, 105.0);
                        }

                        return BarChartGroupData(
                          x: idx,
                          barsSpace: 8,
                          barRods: [
                            BarChartRodData(
                              toY: rodAY,
                              color: const Color(0xFF6750A4),
                              width: 20,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            ),
                            BarChartRodData(
                              toY: rodBY,
                              color: const Color(0xFF006C51),
                              width: 20,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
          ),
        ],
      ),
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
        if (valText.trim().isNotEmpty) ...[
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
    final hasSecond = summaryB != null;
    final titleA = summaryA?.campaignTitle ?? (isAr ? 'الحملة (A)' : 'Campaign A');
    final titleB = hasSecond ? summaryB.campaignTitle : (isAr ? 'لا توجد حملة ثانية' : 'No 2nd Campaign');

    final rows = [
      _TableRowData(
        label: strings.totalRevenueLabel,
        icon: Icons.payments_rounded,
        valA: '${summaryA?.totalRevenue.toStringAsFixed(1) ?? '0.0'} $currency',
        valB: hasSecond ? '${summaryB.totalRevenue.toStringAsFixed(1)} $currency' : (isAr ? 'لا توجد بيانات' : 'No data'),
        numA: summaryA?.totalRevenue ?? 0.0,
        numB: hasSecond ? summaryB.totalRevenue : 0.0,
        unit: currency,
      ),
      _TableRowData(
        label: strings.totalInvoicesCountLabel,
        icon: Icons.receipt_long_rounded,
        valA: '${summaryA?.totalInvoices ?? 0}',
        valB: hasSecond ? '${summaryB.totalInvoices}' : (isAr ? 'لا توجد بيانات' : 'No data'),
        numA: (summaryA?.totalInvoices ?? 0).toDouble(),
        numB: hasSecond ? (summaryB.totalInvoices).toDouble() : 0.0,
        unit: '',
      ),
      _TableRowData(
        label: strings.totalProductsSoldLabel,
        icon: Icons.shopping_basket_rounded,
        valA: '${summaryA?.totalProductsSold ?? 0}',
        valB: hasSecond ? '${summaryB.totalProductsSold}' : (isAr ? 'لا توجد بيانات' : 'No data'),
        numA: (summaryA?.totalProductsSold ?? 0).toDouble(),
        numB: hasSecond ? (summaryB.totalProductsSold).toDouble() : 0.0,
        unit: '',
      ),
      _TableRowData(
        label: strings.uniqueShoppersLabel,
        icon: Icons.people_alt_rounded,
        valA: '${summaryA?.uniqueShoppersCount ?? 0}',
        valB: hasSecond ? '${summaryB.uniqueShoppersCount}' : (isAr ? 'لا توجد بيانات' : 'No data'),
        numA: (summaryA?.uniqueShoppersCount ?? 0).toDouble(),
        numB: hasSecond ? (summaryB.uniqueShoppersCount).toDouble() : 0.0,
        unit: '',
      ),
      _TableRowData(
        label: strings.avgBasketSpendLabel,
        icon: Icons.shopping_cart_checkout_rounded,
        valA: '${summaryA?.avgBasketSpend.toStringAsFixed(1) ?? '0.0'} $currency',
        valB: hasSecond ? '${summaryB.avgBasketSpend.toStringAsFixed(1)} $currency' : (isAr ? 'لا توجد بيانات' : 'No data'),
        numA: summaryA?.avgBasketSpend ?? 0.0,
        numB: hasSecond ? summaryB.avgBasketSpend : 0.0,
        unit: currency,
      ),
      _TableRowData(
        label: strings.disbursedPrizesValueLabel,
        icon: Icons.card_giftcard_rounded,
        valA: '${summaryA?.estimatedPrizesValue.toStringAsFixed(0) ?? '0'} $currency',
        valB: hasSecond ? '${summaryB.estimatedPrizesValue.toStringAsFixed(0)} $currency' : (isAr ? 'لا توجد بيانات' : 'No data'),
        numA: summaryA?.estimatedPrizesValue ?? 0.0,
        numB: hasSecond ? summaryB.estimatedPrizesValue : 0.0,
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
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.table_chart_rounded, color: colorScheme.primary, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isAr ? 'جدول مقارنة المؤشرات التفصيلي' : 'Detailed Metrics Comparison Matrix',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          isAr ? 'مقارنة شاملة متزامنة' : 'Real-time Synchronized Comparison',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // View Mode Toggle (Table View - Default vs Cards View)
                M3ConnectedButtonGroup<bool>(
                  height: 34,
                  borderRadius: 10,
                  segments: [
                    M3ButtonSegment<bool>(
                      value: true,
                      icon: Icons.table_chart_rounded,
                      label: isAr ? 'جدول' : 'Table',
                      tooltip: isAr ? 'عرض كجدول متكامل (افتراضي)' : 'Table View (Default)',
                    ),
                    M3ButtonSegment<bool>(
                      value: false,
                      icon: Icons.view_agenda_rounded,
                      label: isAr ? 'بطاقات' : 'Cards',
                      tooltip: isAr ? 'عرض كبطاقات' : 'Cards View',
                    ),
                  ],
                  selectedValue: _showTableView,
                  onSelected: (val) {
                    setState(() {
                      _showTableView = val;
                    });
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          LayoutBuilder(
            builder: (context, constraints) {
              if (_showTableView) {
                // Table View (Default) with horizontal scroll support on narrow/mobile viewports
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (constraints.maxWidth < 680)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Row(
                          children: [
                            Icon(Icons.swipe_rounded, size: 14, color: colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              isAr
                                  ? 'اسحب أفقياً للاطلاع على كامل أعمدة المقارنة'
                                  : 'Swipe horizontally to view full matrix',
                              style: GoogleFonts.cairo(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: SizedBox(
                        width: math.max(constraints.maxWidth, 680.0),
                        child: _buildDesktopComparisonTable(
                          rows: rows,
                          titleA: titleA,
                          titleB: titleB,
                          colorScheme: colorScheme,
                          strings: strings,
                          isAr: isAr,
                        ),
                      ),
                    ),
                  ],
                );
              }

              // Cards View (Alternative option)
              return _buildMobileComparisonCards(
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
          final isSingle = r.numB == 0;
          final pct = r.numB > 0
              ? ((diff / r.numB) * 100)
              : (r.numA > 0 ? 100.0 : 0.0);
          final isPositive = diff > 0;
          final isTied = diff == 0;

          final deltaColor = isSingle
              ? colorScheme.onSurfaceVariant
              : (isTied
                  ? colorScheme.onSurfaceVariant
                  : (isPositive ? const Color(0xFF006C51) : const Color(0xFFBA1A1A)));

          final leadingCampaign = isSingle
              ? (isAr ? 'حملة منفردة' : 'Single Campaign')
              : (isTied
                  ? strings.tiedCampaignsTag
                  : (isPositive ? 'A: $titleA 🏆' : 'B: $titleB 🏆'));

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
                            (isSingle || isTied)
                                ? Icons.drag_handle_rounded
                                : (isPositive
                                    ? Icons.arrow_upward_rounded
                                    : Icons.arrow_downward_rounded),
                            size: 14,
                            color: deltaColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isSingle ? '-' : '${isPositive ? '+' : ''}${pct.toStringAsFixed(1)}%',
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
          final isSingle = r.numB == 0;
          final pct = r.numB > 0
              ? ((diff / r.numB) * 100)
              : (r.numA > 0 ? 100.0 : 0.0);
          final isPositive = diff > 0;
          final isTied = diff == 0;

          final deltaColor = isSingle
              ? colorScheme.onSurfaceVariant
              : (isTied
                  ? colorScheme.onSurfaceVariant
                  : (isPositive ? const Color(0xFF006C51) : const Color(0xFFBA1A1A)));

          final leadingCampaign = isSingle
              ? (isAr ? 'حملة منفردة' : 'Single Campaign')
              : (isTied
                  ? strings.tiedCampaignsTag
                  : (isPositive ? 'A: $titleA 🏆' : 'B: $titleB 🏆'));

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
                          (isSingle || isTied)
                              ? Icons.drag_handle_rounded
                              : (isPositive
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded),
                          size: 13,
                          color: deltaColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isSingle
                              ? '${strings.metricDifferenceLabel}: -'
                              : '${strings.metricDifferenceLabel}: ${isPositive ? '+' : ''}${pct.toStringAsFixed(1)}%',
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
  // Intra-Campaign Weekend & Period Analytics (Waves / Sprints Analysis)
  // ---------------------------------------------------------------------------

  static DateTime? _extractInvoiceDate(Map<String, dynamic> data) {
    final rawReceiptDate = (data['receipt_date'] ?? data['receiptDate'] ?? data['dateStr'] ?? '').toString().trim();
    if (rawReceiptDate.isNotEmpty && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawReceiptDate)) {
      return DateTime.tryParse(rawReceiptDate);
    } else if (rawReceiptDate.isNotEmpty && RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(rawReceiptDate)) {
      final parts = rawReceiptDate.split('/');
      final dateStr = '${parts[2]}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}';
      return DateTime.tryParse(dateStr);
    }
    final rawTs = data['timestamp'] ?? data['claimed_at'] ?? data['created_at'] ?? data['date'];
    if (rawTs is Timestamp) {
      return rawTs.toDate();
    } else if (rawTs is String && rawTs.isNotEmpty) {
      return DateTime.tryParse(rawTs);
    }
    return null;
  }

  static String _formatDateKey(DateTime dt) {
    return "${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
  }

  static String _formatShortDate(DateTime dt, bool isAr) {
    if (!isAr) {
      return DateFormat('d MMM').format(dt);
    }
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    return '${dt.day} ${months[(dt.month - 1) % 12]}';
  }

  static String _formatClusterLabel(int wave, DateTime start, DateTime end, bool isAr) {
    final startFmt = _formatShortDate(start, isAr);
    final endFmt = _formatShortDate(end, isAr);
    final prefix = isAr ? 'الويك إند $wave' : 'Weekend $wave';
    if (startFmt == endFmt) {
      return '$prefix ($startFmt)';
    }
    return '$prefix ($startFmt – $endFmt)';
  }

  static String _formatShortenedPeriodLegend({
    required String periodLabel,
    required String prefixLetter,
  }) {
    // If periodLabel is like: 'الويك إند 1 (28 سبتمبر – 1 أكتوبر)' or 'Weekend 1 (28 Sep – 1 Oct)'
    final waveMatch = RegExp(r'(\d+)').firstMatch(periodLabel);
    final waveNum = waveMatch?.group(1);

    // Extract dates between parentheses if present
    final pMatch = RegExp(r'\(([^)]+)\)').firstMatch(periodLabel);
    final dates = pMatch?.group(1)?.trim();

    if (waveNum != null && dates != null && dates.isNotEmpty) {
      return '$prefixLetter$waveNum: $dates';
    } else if (dates != null && dates.isNotEmpty) {
      return '$prefixLetter: $dates';
    } else if (periodLabel.isNotEmpty) {
      return '$prefixLetter: $periodLabel';
    }
    return prefixLetter;
  }

  static bool _isValidInvoice(Map<String, dynamic> inv) {
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
    return isExplicitlyValid ||
        (!isExplicitlyRejected && ((inv['unfulfilled_conditions'] as List?)?.isEmpty ?? true));
  }

  List<Map<String, dynamic>> _getIntraCampaignInvoices({
    required String campaignId,
    required List<EventModel> events,
    required List<QueryDocumentSnapshot> invoiceDocs,
  }) {
    final targetEvent = events.firstWhere(
      (e) => e.id == campaignId,
      orElse: () => events.first,
    );
    final normTargetTitle = _normalizeTitle(targetEvent.eventName);
    final rawTargetTitle = targetEvent.eventName.trim().toLowerCase();

    final List<Map<String, dynamic>> campaignInvoices = [];
    for (final doc in invoiceDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final String cId = (data['campaignId'] ?? data['event_id'] ?? data['eventId'] ?? '').toString().trim();
      bool matches = false;
      if (cId == campaignId) {
        matches = true;
      } else {
        final rawEvName = (data['eventName'] ?? data['campaign_title'] ?? data['campaignName'] ?? data['event_name'] ?? '').toString().trim();
        final normEvName = _normalizeTitle(rawEvName);
        if (normEvName.isNotEmpty && normEvName == normTargetTitle) {
          matches = true;
        } else if (rawEvName.isNotEmpty && rawEvName.toLowerCase() == rawTargetTitle) {
          matches = true;
        }
      }
      if (matches) {
        campaignInvoices.add(data);
      }
    }
    return campaignInvoices;
  }

  List<CampaignWeekendCluster> _detectWeekendClusters({
    required List<Map<String, dynamic>> invoices,
    required bool isAr,
  }) {
    final Map<String, List<Map<String, dynamic>>> invoicesByDate = {};
    for (final inv in invoices) {
      if (!_isValidInvoice(inv)) continue;
      final dt = _extractInvoiceDate(inv);
      if (dt == null) continue;
      final dateKey = _formatDateKey(dt);
      invoicesByDate.putIfAbsent(dateKey, () => []).add(inv);
    }

    if (invoicesByDate.isEmpty) return [];

    final sortedDates = invoicesByDate.keys.toList()..sort();
    final List<List<String>> dateClusters = [];
    List<String> currentCluster = [sortedDates.first];

    for (int i = 1; i < sortedDates.length; i++) {
      final prevDate = DateTime.parse(sortedDates[i - 1]);
      final currDate = DateTime.parse(sortedDates[i]);
      final clusterStart = DateTime.parse(currentCluster.first);
      final gap = currDate.difference(prevDate).inDays;
      final spanFromStart = currDate.difference(clusterStart).inDays;

      // In retail promotions, a weekend activation wave typically spans 3 days (Thu-Sat) or up to 4 days (Thu-Sun).
      // Keep within the retail weekend window: if gap <= 2 and span <= 3 days, group together; otherwise start next wave.
      if (gap <= 2 && spanFromStart <= 3) {
        currentCluster.add(sortedDates[i]);
      } else {
        dateClusters.add(currentCluster);
        currentCluster = [sortedDates[i]];
      }
    }
    if (currentCluster.isNotEmpty) {
      dateClusters.add(currentCluster);
    }

    final List<CampaignWeekendCluster> clusters = [];
    int wave = 1;
    for (final clusterDates in dateClusters) {
      final startDt = DateTime.parse(clusterDates.first);
      final endDt = DateTime.parse(clusterDates.last);

      int totalInv = 0;
      double totalSales = 0.0;
      for (final d in clusterDates) {
        final list = invoicesByDate[d] ?? [];
        totalInv += list.length;
        for (final inv in list) {
          final rev = (inv['target_company_total'] as num?)?.toDouble() ??
              (inv['targetCompanyTotal'] as num?)?.toDouble() ??
              (inv['total_value'] as num?)?.toDouble() ??
              (inv['eligibleAmount'] as num?)?.toDouble() ??
              (inv['totalAmount'] as num?)?.toDouble() ??
              0.0;
          totalSales += rev;
        }
      }

      final label = _formatClusterLabel(wave, startDt, endDt, isAr);
      clusters.add(CampaignWeekendCluster(
        id: 'cluster_${startDt.year}_${startDt.month}_${startDt.day}',
        waveNumber: wave,
        startDate: startDt,
        endDate: endDt,
        label: label,
        activeDates: clusterDates,
        invoiceCount: totalInv,
        totalSales: totalSales,
      ));
      wave++;
    }

    return clusters;
  }

  CampaignPeriodMetrics _computePeriodMetrics({
    required String periodId,
    required String periodLabel,
    required String campaignId,
    required String campaignTitle,
    required DateTime startDate,
    required DateTime endDate,
    required List<Map<String, dynamic>> campaignInvoices,
    List<String>? activeDateStrings,
  }) {
    double totalRev = 0.0;
    int totalItems = 0;
    int acceptedCount = 0;
    final Set<String> uniquePhones = {};
    int prizesCount = 0;
    double prizesVal = 0.0;
    final Set<String> activeDaysSet = {};

    for (final inv in campaignInvoices) {
      if (!_isValidInvoice(inv)) continue;
      final dt = _extractInvoiceDate(inv);
      if (dt == null) continue;
      final dateKey = _formatDateKey(dt);

      bool inPeriod = false;
      if (activeDateStrings != null) {
        inPeriod = activeDateStrings.contains(dateKey);
      } else {
        final dayOnly = DateTime(dt.year, dt.month, dt.day);
        final startDay = DateTime(startDate.year, startDate.month, startDate.day);
        final endDay = DateTime(endDate.year, endDate.month, endDate.day);
        inPeriod = (dayOnly.isAfter(startDay.subtract(const Duration(seconds: 1))) &&
            dayOnly.isBefore(endDay.add(const Duration(days: 1))));
      }

      if (!inPeriod) continue;

      acceptedCount++;
      activeDaysSet.add(dateKey);

      final double rev = (inv['target_company_total'] as num?)?.toDouble() ??
          (inv['targetCompanyTotal'] as num?)?.toDouble() ??
          (inv['total_value'] as num?)?.toDouble() ??
          (inv['eligibleAmount'] as num?)?.toDouble() ??
          (inv['totalAmount'] as num?)?.toDouble() ??
          0.0;
      totalRev += rev;

      final rawProducts = inv['extracted_products'] ?? inv['extractedItems'] ?? inv['items'] ?? [];
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

      final phone = (inv['customerPhone'] ?? inv['customer_phone'] ?? inv['userPhone'] ?? inv['phoneNumber'] ?? inv['phone_number'] ?? '').toString().trim();
      if (phone.isNotEmpty && phone != 'null') {
        uniquePhones.add(phone);
      }

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

    final int effectiveDays = activeDaysSet.isNotEmpty ? activeDaysSet.length : 1;

    return CampaignPeriodMetrics(
      periodId: periodId,
      periodLabel: periodLabel,
      campaignId: campaignId,
      campaignTitle: campaignTitle,
      startDate: startDate,
      endDate: endDate,
      activeDaysCount: effectiveDays,
      totalRevenue: totalRev,
      totalInvoices: acceptedCount,
      totalProductsSold: totalItems,
      uniqueShoppersCount: uniquePhones.isNotEmpty ? uniquePhones.length : (acceptedCount > 0 ? (acceptedCount * 0.85).round().clamp(1, acceptedCount) : 0),
      claimedPrizesCount: prizesCount,
      estimatedPrizesValue: prizesVal,
    );
  }

  Future<void> _pickCustomDateRange({
    required BuildContext context,
    required bool isRangeA,
    required DateTime initialStart,
    required DateTime initialEnd,
  }) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(
        start: isRangeA ? (_customRangeA?.start ?? initialStart) : (_customRangeB?.start ?? initialStart),
        end: isRangeA ? (_customRangeA?.end ?? initialEnd) : (_customRangeB?.end ?? initialEnd),
      ),
    );
    if (picked != null) {
      setState(() {
        if (isRangeA) {
          _customRangeA = picked;
        } else {
          _customRangeB = picked;
        }
      });
    }
  }

  Widget _buildIntraCampaignPicker({
    required String? selectedId,
    required List<EventModel> events,
    required ValueChanged<String?> onChanged,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.campaign_rounded, size: 16, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                strings.selectTargetCampaignToAnalyze,
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedId,
              isExpanded: true,
              icon: Icon(Icons.arrow_drop_down_rounded, color: colorScheme.primary),
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

  Widget _buildClusterDropdown({
    required String label,
    required Color badgeColor,
    required String? selectedId,
    required List<CampaignWeekendCluster> clusters,
    required ColorScheme colorScheme,
    required bool isAr,
    required ValueChanged<String?> onChanged,
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
              items: clusters.map((c) {
                return DropdownMenuItem<String>(
                  value: c.id,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.label,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${c.invoiceCount} ${isAr ? "فاتورة" : "inv"}',
                          style: GoogleFonts.cairo(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: badgeColor,
                          ),
                        ),
                      ),
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

  Widget _buildCustomDateRangeButton({
    required String label,
    required Color badgeColor,
    required DateTimeRange? range,
    required ColorScheme colorScheme,
    required bool isAr,
    required VoidCallback onTap,
  }) {
    final rangeText = range != null
        ? '${_formatShortDate(range.start, isAr)} – ${_formatShortDate(range.end, isAr)}'
        : (isAr ? 'اضغط لاختيار النطاق' : 'Click to select range');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  rangeText,
                  style: GoogleFonts.cairo(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                Icon(Icons.calendar_month_rounded, size: 18, color: badgeColor),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntraDimensionChip({
    required ComparisonDimension dimension,
    required String label,
    required IconData icon,
    required ColorScheme colorScheme,
  }) {
    final isSelected = _intraDimension == dimension;
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
          setState(() => _intraDimension = dimension);
        }
      },
    );
  }






  Widget _buildIntraComparisonTable({
    required CampaignPeriodMetrics metricsA,
    required CampaignPeriodMetrics metricsB,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required CountryCurrency activeCountry,
    required bool isAr,
  }) {
    final currency = activeCountry.currencySymbol;
    final titleA = _formatShortenedPeriodLegend(periodLabel: metricsA.periodLabel, prefixLetter: 'A');
    final titleB = _formatShortenedPeriodLegend(periodLabel: metricsB.periodLabel, prefixLetter: 'B');

    final rows = [
      _TableRowData(
        label: strings.totalRevenueLabel,
        icon: Icons.payments_rounded,
        valA: '${metricsA.totalRevenue.toStringAsFixed(1)} $currency',
        valB: '${metricsB.totalRevenue.toStringAsFixed(1)} $currency',
        numA: metricsA.totalRevenue,
        numB: metricsB.totalRevenue,
        unit: currency,
      ),
      _TableRowData(
        label: strings.totalInvoicesCountLabel,
        icon: Icons.receipt_long_rounded,
        valA: '${metricsA.totalInvoices}',
        valB: '${metricsB.totalInvoices}',
        numA: metricsA.totalInvoices.toDouble(),
        numB: metricsB.totalInvoices.toDouble(),
        unit: '',
      ),
      _TableRowData(
        label: strings.totalProductsSoldLabel,
        icon: Icons.shopping_basket_rounded,
        valA: '${metricsA.totalProductsSold}',
        valB: '${metricsB.totalProductsSold}',
        numA: metricsA.totalProductsSold.toDouble(),
        numB: metricsB.totalProductsSold.toDouble(),
        unit: '',
      ),
      _TableRowData(
        label: strings.uniqueShoppersLabel,
        icon: Icons.people_alt_rounded,
        valA: '${metricsA.uniqueShoppersCount}',
        valB: '${metricsB.uniqueShoppersCount}',
        numA: metricsA.uniqueShoppersCount.toDouble(),
        numB: metricsB.uniqueShoppersCount.toDouble(),
        unit: '',
      ),
      _TableRowData(
        label: strings.dailySalesVelocityLabel,
        icon: Icons.speed_rounded,
        valA: '${metricsA.dailySalesVelocity.toStringAsFixed(1)} $currency',
        valB: '${metricsB.dailySalesVelocity.toStringAsFixed(1)} $currency',
        numA: metricsA.dailySalesVelocity,
        numB: metricsB.dailySalesVelocity,
        unit: currency,
      ),
      _TableRowData(
        label: strings.avgBasketSpendLabel,
        icon: Icons.shopping_cart_checkout_rounded,
        valA: '${metricsA.avgBasketSpend.toStringAsFixed(1)} $currency',
        valB: '${metricsB.avgBasketSpend.toStringAsFixed(1)} $currency',
        numA: metricsA.avgBasketSpend,
        numB: metricsB.avgBasketSpend,
        unit: currency,
      ),
      _TableRowData(
        label: strings.disbursedPrizesValueLabel,
        icon: Icons.card_giftcard_rounded,
        valA: '${metricsA.estimatedPrizesValue.toStringAsFixed(0)} $currency',
        valB: '${metricsB.estimatedPrizesValue.toStringAsFixed(0)} $currency',
        numA: metricsA.estimatedPrizesValue,
        numB: metricsB.estimatedPrizesValue,
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
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.table_chart_rounded, color: colorScheme.primary, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isAr ? 'جدول مقارنة الفترات والويك إند' : 'Intra-Period Comparison Table',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          isAr ? 'مقارنة شاملة متزامنة' : 'Real-time Synchronized Comparison',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // View Mode Toggle (Table View - Default vs Cards View)
                M3ConnectedButtonGroup<bool>(
                  height: 34,
                  borderRadius: 10,
                  segments: [
                    M3ButtonSegment<bool>(
                      value: true,
                      icon: Icons.table_chart_rounded,
                      label: isAr ? 'جدول' : 'Table',
                      tooltip: isAr ? 'عرض كجدول متكامل (افتراضي)' : 'Table View (Default)',
                    ),
                    M3ButtonSegment<bool>(
                      value: false,
                      icon: Icons.view_agenda_rounded,
                      label: isAr ? 'بطاقات' : 'Cards',
                      tooltip: isAr ? 'عرض كبطاقات' : 'Cards View',
                    ),
                  ],
                  selectedValue: _showTableView,
                  onSelected: (val) {
                    setState(() {
                      _showTableView = val;
                    });
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          LayoutBuilder(
            builder: (context, constraints) {
              if (_showTableView) {
                // Table View (Default) with horizontal scroll support on narrow/mobile viewports
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (constraints.maxWidth < 680)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Row(
                          children: [
                            Icon(Icons.swipe_rounded, size: 14, color: colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              isAr
                                  ? 'اسحب أفقياً للاطلاع على كامل أعمدة المقارنة'
                                  : 'Swipe horizontally to view full matrix',
                              style: GoogleFonts.cairo(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: SizedBox(
                        width: math.max(constraints.maxWidth, 680.0),
                        child: _buildDesktopComparisonTable(
                          rows: rows,
                          titleA: titleA,
                          titleB: titleB,
                          colorScheme: colorScheme,
                          strings: strings,
                          isAr: isAr,
                        ),
                      ),
                    ),
                  ],
                );
              }

              // Cards View (Alternative option)
              return _buildMobileComparisonCards(
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

  Widget _buildPeakWeekendGoldenBanner({
    required List<CampaignPeriodMetrics> allMetrics,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required CountryCurrency activeCountry,
    required bool isAr,
  }) {
    if (allMetrics.isEmpty) return const SizedBox.shrink();

    final peak = allMetrics.reduce((curr, next) => curr.totalRevenue >= next.totalRevenue ? curr : next);
    final currency = activeCountry.currencySymbol;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFFF8E1),
            Color(0xFFFFECB3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFB300), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB300).withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.emoji_events_rounded, color: colorScheme.primary, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.peakWeekendBadge,
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF7A4F01),
                      ),
                    ),
                    Text(
                      peak.periodLabel,
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF8D6E63),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFB78103),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Peak #1',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              _buildPeakStatChip(
                icon: Icons.payments_rounded,
                label: strings.totalRevenueLabel,
                value: '${NumberFormat.compact().format(peak.totalRevenue)} $currency',
              ),
              _buildPeakStatChip(
                icon: Icons.receipt_long_rounded,
                label: strings.totalInvoicesCountLabel,
                value: '${peak.totalInvoices} ${isAr ? "فاتورة" : "Invoices"}',
              ),
              _buildPeakStatChip(
                icon: Icons.speed_rounded,
                label: strings.dailySalesVelocityLabel,
                value: '${NumberFormat.compact().format(peak.dailySalesVelocity)} $currency/${isAr ? "يوم" : "day"}',
              ),
              _buildPeakStatChip(
                icon: Icons.shopping_cart_checkout_rounded,
                label: strings.avgBasketSpendLabel,
                value: '${peak.avgBasketSpend.toStringAsFixed(0)} $currency',
              ),
              _buildPeakStatChip(
                icon: Icons.people_alt_rounded,
                label: strings.uniqueShoppersLabel,
                value: '${peak.uniqueShoppersCount} ${isAr ? "متسوق" : "Shoppers"}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPeakStatChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF5D4037),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF7A4F01),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllWeekendsProgressionChart({
    required List<CampaignPeriodMetrics> allMetrics,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required CountryCurrency activeCountry,
    required bool isAr,
  }) {
    if (allMetrics.isEmpty) return const SizedBox.shrink();
    final currency = activeCountry.currencySymbol;

    double Function(CampaignPeriodMetrics) valSelector;
    String unit = '';

    switch (_intraDimension) {
      case ComparisonDimension.revenue:
        valSelector = (m) => m.totalRevenue;
        unit = currency;
        break;
      case ComparisonDimension.invoices:
        valSelector = (m) => m.totalInvoices.toDouble();
        unit = isAr ? 'فاتورة' : 'Inv';
        break;
      case ComparisonDimension.products:
        valSelector = (m) => m.totalProductsSold.toDouble();
        unit = isAr ? 'قطعة' : 'Pcs';
        break;
      case ComparisonDimension.shoppers:
        valSelector = (m) => m.uniqueShoppersCount.toDouble();
        unit = isAr ? 'عميل' : 'Cust';
        break;
      case ComparisonDimension.velocity:
        valSelector = (m) => m.dailySalesVelocity;
        unit = '$currency/${isAr ? "يوم" : "day"}';
        break;
      case ComparisonDimension.basketSpend:
        valSelector = (m) => m.avgBasketSpend;
        unit = currency;
        break;
    }

    double maxVal = 0.0;
    for (final m in allMetrics) {
      final v = valSelector(m);
      if (v > maxVal) maxVal = v;
    }
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
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timeline_rounded, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    strings.weekendProgressionChartTitle,
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _buildIntraDimensionChip(
                    dimension: ComparisonDimension.revenue,
                    label: strings.comparisonDimensionRevenue,
                    icon: Icons.payments_rounded,
                    colorScheme: colorScheme,
                  ),
                  _buildIntraDimensionChip(
                    dimension: ComparisonDimension.invoices,
                    label: strings.comparisonDimensionInvoices,
                    icon: Icons.receipt_long_rounded,
                    colorScheme: colorScheme,
                  ),
                  _buildIntraDimensionChip(
                    dimension: ComparisonDimension.products,
                    label: strings.comparisonDimensionProducts,
                    icon: Icons.shopping_basket_rounded,
                    colorScheme: colorScheme,
                  ),
                  _buildIntraDimensionChip(
                    dimension: ComparisonDimension.shoppers,
                    label: strings.comparisonDimensionShoppers,
                    icon: Icons.people_alt_rounded,
                    colorScheme: colorScheme,
                  ),
                  _buildIntraDimensionChip(
                    dimension: ComparisonDimension.velocity,
                    label: strings.dailySalesVelocityLabel,
                    icon: Icons.speed_rounded,
                    colorScheme: colorScheme,
                  ),
                  _buildIntraDimensionChip(
                    dimension: ComparisonDimension.basketSpend,
                    label: strings.avgBasketSpendLabel,
                    icon: Icons.shopping_cart_checkout_rounded,
                    colorScheme: colorScheme,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 260,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => colorScheme.surfaceContainerHighest,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final m = allMetrics[group.x.toInt()];
                      final v = valSelector(m);
                      return BarTooltipItem(
                        '${m.periodLabel}\n',
                        GoogleFonts.cairo(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        children: [
                          TextSpan(
                            text: '${NumberFormat.decimalPattern().format(v)} $unit',
                            style: GoogleFonts.cairo(
                              color: colorScheme.onSurface,
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
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < allMetrics.length) {
                          final v = valSelector(allMetrics[idx]);
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: colorScheme.primary.withValues(alpha: 0.3),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              NumberFormat.compact().format(v),
                              style: GoogleFonts.cairo(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
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
                        final idx = value.toInt();
                        if (idx >= 0 && idx < allMetrics.length) {
                          final waveNum = idx + 1;
                          final label = isAr ? 'دورة $waveNum' : 'W$waveNum';
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              label,
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurfaceVariant,
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
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(allMetrics.length, (index) {
                  final m = allMetrics[index];
                  final val = valSelector(m);
                  final isPeak = val == maxVal;

                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: val,
                        color: isPeak ? const Color(0xFFD48B00) : colorScheme.primary,
                        width: math.min(36.0, 200.0 / allMetrics.length),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllWeekendsProgressionTable({
    required List<CampaignPeriodMetrics> allMetrics,
    required List<CampaignWeekendCluster> clusters,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required CountryCurrency activeCountry,
    required bool isAr,
  }) {
    if (allMetrics.isEmpty) return const SizedBox.shrink();
    final currency = activeCountry.currencySymbol;

    final sortedByRev = List<CampaignPeriodMetrics>.from(allMetrics)
      ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

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
                    Icon(Icons.view_timeline_rounded, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      strings.allWeekendsProgressionView,
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                Text(
                  isAr ? '${allMetrics.length} دورات تفعيل' : '${allMetrics.length} Activation Waves',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              ),
              columnSpacing: 22,
              columns: [
                DataColumn(
                  label: Text(
                    isAr ? 'الدورة / الويك إند' : 'Wave / Weekend',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    isAr ? 'نطاق التاريخ' : 'Dates',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    strings.activeDaysLabel,
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
                    strings.dailySalesVelocityLabel,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    strings.disbursedPrizesValueLabel,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    isAr ? 'الترتيب' : 'Rank',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
              rows: allMetrics.map((m) {
                final rank = sortedByRev.indexOf(m) + 1;
                final isTop = rank == 1;

                String rankBadge = '#$rank';
                if (rank == 1) rankBadge = '🥇 الأول';
                if (rank == 2) rankBadge = '🥈 الثاني';
                if (rank == 3) rankBadge = '🥉 الثالث';

                final dateStr = '${_formatShortDate(m.startDate, isAr)} – ${_formatShortDate(m.endDate, isAr)}';

                return DataRow(
                  color: isTop
                      ? WidgetStateProperty.all(const Color(0xFFFFF8E1).withValues(alpha: 0.6))
                      : null,
                  cells: [
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: isTop
                                  ? const Color(0xFFFFB300)
                                  : colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              m.periodLabel.split('(').first.trim(),
                              style: GoogleFonts.cairo(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: isTop ? Colors.white : colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    DataCell(Text(dateStr, style: GoogleFonts.cairo(fontSize: 12))),
                    DataCell(Text('${m.activeDaysCount}', style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.w600))),
                    DataCell(
                      Text(
                        '${NumberFormat.decimalPattern().format(m.totalRevenue)} $currency',
                        style: GoogleFonts.cairo(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: isTop ? const Color(0xFFB78103) : colorScheme.primary,
                        ),
                      ),
                    ),
                    DataCell(Text('${m.totalInvoices}', style: GoogleFonts.cairo(fontSize: 12.5))),
                    DataCell(Text('${m.totalProductsSold}', style: GoogleFonts.cairo(fontSize: 12.5))),
                    DataCell(Text('${m.uniqueShoppersCount}', style: GoogleFonts.cairo(fontSize: 12.5))),
                    DataCell(Text('${m.avgBasketSpend.toStringAsFixed(1)} $currency', style: GoogleFonts.cairo(fontSize: 12.5))),
                    DataCell(
                      Text(
                        '${NumberFormat.compact().format(m.dailySalesVelocity)} $currency',
                        style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    DataCell(Text('${m.estimatedPrizesValue.toStringAsFixed(0)} $currency', style: GoogleFonts.cairo(fontSize: 12.5))),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isTop
                              ? const Color(0xFFFFB300).withValues(alpha: 0.2)
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          rankBadge,
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isTop ? const Color(0xFFB78103) : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoWeekendsNotice({
    required ColorScheme colorScheme,
    required AppStrings strings,
    required bool isAr,
  }) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy_rounded, color: colorScheme.outline, size: 48),
            const SizedBox(height: 12),
            Text(
              strings.noWeekendsFoundNotice,
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntraCampaignWeekendView({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required List<EventModel> events,
    required List<QueryDocumentSnapshot> invoiceDocs,
    required CountryCurrency activeCountry,
    required bool isAr,
    required bool isHi,
  }) {
    if (events.isEmpty) {
      return Center(
        child: Text(
          strings.noWeekendsFoundNotice,
          style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    final targetCampaignId = _selectedIntraCampaignId ?? events.first.id;
    final targetEvent = events.firstWhere(
      (e) => e.id == targetCampaignId,
      orElse: () => events.first,
    );

    // 1. Get filtered invoices for this campaign
    final invoices = _getIntraCampaignInvoices(
      campaignId: targetCampaignId,
      events: events,
      invoiceDocs: invoiceDocs,
    );

    // 2. Detect weekend waves
    final clusters = _detectWeekendClusters(
      invoices: invoices,
      isAr: isAr,
    );

    // Default cluster selections
    if (clusters.isNotEmpty) {
      if (_selectedClusterAId == null || !clusters.any((c) => c.id == _selectedClusterAId)) {
        _selectedClusterAId = clusters.first.id;
      }
      if (_selectedClusterBId == null || !clusters.any((c) => c.id == _selectedClusterBId)) {
        _selectedClusterBId = clusters.length > 1 ? clusters[1].id : clusters.first.id;
      }
      _customRangeA ??= DateTimeRange(start: clusters.first.startDate, end: clusters.first.endDate);
      _customRangeB ??= DateTimeRange(start: clusters.last.startDate, end: clusters.last.endDate);
    }

    // 3. Compute Metrics for Period A and Period B
    CampaignPeriodMetrics? metricsA;
    CampaignPeriodMetrics? metricsB;

    if (!_isCustomPeriodMode && clusters.isNotEmpty) {
      final clusterA = clusters.firstWhere(
        (c) => c.id == _selectedClusterAId,
        orElse: () => clusters.first,
      );
      final clusterB = clusters.firstWhere(
        (c) => c.id == _selectedClusterBId,
        orElse: () => (clusters.length > 1 ? clusters[1] : clusters.first),
      );

      metricsA = _computePeriodMetrics(
        periodId: clusterA.id,
        periodLabel: clusterA.label,
        campaignId: targetEvent.id,
        campaignTitle: targetEvent.eventName,
        startDate: clusterA.startDate,
        endDate: clusterA.endDate,
        campaignInvoices: invoices,
        activeDateStrings: clusterA.activeDates,
      );

      metricsB = _computePeriodMetrics(
        periodId: clusterB.id,
        periodLabel: clusterB.label,
        campaignId: targetEvent.id,
        campaignTitle: targetEvent.eventName,
        startDate: clusterB.startDate,
        endDate: clusterB.endDate,
        campaignInvoices: invoices,
        activeDateStrings: clusterB.activeDates,
      );
    } else if (_isCustomPeriodMode && _customRangeA != null && _customRangeB != null) {
      metricsA = _computePeriodMetrics(
        periodId: 'custom_a',
        periodLabel: '${_formatShortDate(_customRangeA!.start, isAr)} – ${_formatShortDate(_customRangeA!.end, isAr)}',
        campaignId: targetEvent.id,
        campaignTitle: targetEvent.eventName,
        startDate: _customRangeA!.start,
        endDate: _customRangeA!.end,
        campaignInvoices: invoices,
      );

      metricsB = _computePeriodMetrics(
        periodId: 'custom_b',
        periodLabel: '${_formatShortDate(_customRangeB!.start, isAr)} – ${_formatShortDate(_customRangeB!.end, isAr)}',
        campaignId: targetEvent.id,
        campaignTitle: targetEvent.eventName,
        startDate: _customRangeB!.start,
        endDate: _customRangeB!.end,
        campaignInvoices: invoices,
      );
    }

    // Precompute all metrics for the progression matrix
    final List<CampaignPeriodMetrics> allMetrics = clusters.map((c) {
      return _computePeriodMetrics(
        periodId: c.id,
        periodLabel: c.label,
        campaignId: targetEvent.id,
        campaignTitle: targetEvent.eventName,
        startDate: c.startDate,
        endDate: c.endDate,
        campaignInvoices: invoices,
        activeDateStrings: c.activeDates,
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Target Campaign & Mode Control Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Campaign Picker
              _buildIntraCampaignPicker(
                selectedId: targetCampaignId,
                events: events,
                onChanged: (id) {
                  if (id != null) {
                    _savedIntraCampaign[widget.lockedCompanySlug] = id;
                    setState(() {
                      _selectedIntraCampaignId = id;
                      _selectedClusterAId = null;
                      _selectedClusterBId = null;
                    });
                  }
                },
                colorScheme: colorScheme,
                strings: strings,
                isAr: isAr,
              ),

              const SizedBox(height: 14),

              // Control Toolbars: Auto vs Custom & SubView Mode
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  // Auto vs Custom M3 Connected Button Group
                  M3ConnectedButtonGroup<bool>(
                    height: 40,
                    borderRadius: 12,
                    segments: [
                      M3ButtonSegment<bool>(
                        value: false,
                        icon: Icons.auto_awesome_rounded,
                        label: strings.periodComparisonModeAuto,
                        tooltip: strings.periodComparisonModeAuto,
                      ),
                      M3ButtonSegment<bool>(
                        value: true,
                        icon: Icons.date_range_rounded,
                        label: strings.periodComparisonModeCustom,
                        tooltip: strings.periodComparisonModeCustom,
                      ),
                    ],
                    selectedValue: _isCustomPeriodMode,
                    onSelected: (newMode) {
                      _savedIsCustomPeriod[widget.lockedCompanySlug] = newMode;
                      setState(() => _isCustomPeriodMode = newMode);
                    },
                  ),

                  // Sub-view Switcher: Head-to-Head vs Progression Matrix
                  M3ConnectedButtonGroup<int>(
                    height: 40,
                    borderRadius: 12,
                    segments: [
                      M3ButtonSegment<int>(
                        value: 0,
                        icon: Icons.compare_arrows_rounded,
                        label: strings.weekendHeadToHeadView,
                        tooltip: strings.weekendHeadToHeadView,
                      ),
                      M3ButtonSegment<int>(
                        value: 1,
                        icon: Icons.view_timeline_rounded,
                        label: strings.allWeekendsProgressionView,
                        tooltip: strings.allWeekendsProgressionView,
                      ),
                    ],
                    selectedValue: _intraSubViewMode,
                    onSelected: (newSub) {
                      _savedIntraSubView[widget.lockedCompanySlug] = newSub;
                      setState(() => _intraSubViewMode = newSub);
                    },
                  ),
                ],
              ),

              // If Head-to-Head Mode (0), show Period A and Period B Pickers
              if (_intraSubViewMode == 0 && (clusters.isNotEmpty || _isCustomPeriodMode)) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                if (!_isCustomPeriodMode) ...[
                  // Auto clusters dropdowns
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 700;
                      final dropA = _buildClusterDropdown(
                        label: strings.weekendPeriodA,
                        badgeColor: const Color(0xFF6750A4),
                        selectedId: _selectedClusterAId,
                        clusters: clusters,
                        colorScheme: colorScheme,
                        isAr: isAr,
                        onChanged: (id) {
                          if (id != null) {
                            _savedClusterA[widget.lockedCompanySlug] = id;
                            setState(() => _selectedClusterAId = id);
                          }
                        },
                      );

                      final dropB = _buildClusterDropdown(
                        label: strings.weekendPeriodB,
                        badgeColor: const Color(0xFF006C51),
                        selectedId: _selectedClusterBId,
                        clusters: clusters,
                        colorScheme: colorScheme,
                        isAr: isAr,
                        onChanged: (id) {
                          if (id != null) {
                            _savedClusterB[widget.lockedCompanySlug] = id;
                            setState(() => _selectedClusterBId = id);
                          }
                        },
                      );

                      if (isNarrow) {
                        return Column(
                          children: [
                            dropA,
                            const SizedBox(height: 10),
                            dropB,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: dropA),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.compare_arrows_rounded, size: 20, color: colorScheme.primary),
                            ),
                          ),
                          Expanded(child: dropB),
                        ],
                      );
                    },
                  ),
                ] else ...[
                  // Custom date range pickers
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 700;
                      final btnA = _buildCustomDateRangeButton(
                        label: strings.weekendPeriodA,
                        badgeColor: const Color(0xFF6750A4),
                        range: _customRangeA,
                        colorScheme: colorScheme,
                        isAr: isAr,
                        onTap: () {
                          final start = _customRangeA?.start ?? DateTime.now().subtract(const Duration(days: 7));
                          final end = _customRangeA?.end ?? DateTime.now();
                          _pickCustomDateRange(
                            context: context,
                            isRangeA: true,
                            initialStart: start,
                            initialEnd: end,
                          );
                        },
                      );

                      final btnB = _buildCustomDateRangeButton(
                        label: strings.weekendPeriodB,
                        badgeColor: const Color(0xFF006C51),
                        range: _customRangeB,
                        colorScheme: colorScheme,
                        isAr: isAr,
                        onTap: () {
                          final start = _customRangeB?.start ?? DateTime.now();
                          final end = _customRangeB?.end ?? DateTime.now();
                          _pickCustomDateRange(
                            context: context,
                            isRangeA: false,
                            initialStart: start,
                            initialEnd: end,
                          );
                        },
                      );

                      if (isNarrow) {
                        return Column(
                          children: [
                            btnA,
                            const SizedBox(height: 10),
                            btnB,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: btnA),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.compare_arrows_rounded, size: 20, color: colorScheme.primary),
                            ),
                          ),
                          Expanded(child: btnB),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        if (clusters.isEmpty && !_isCustomPeriodMode) ...[
          _buildNoWeekendsNotice(
            colorScheme: colorScheme,
            strings: strings,
            isAr: isAr,
          ),
        ] else if (_intraSubViewMode == 0 && metricsA != null && metricsB != null) ...[
          // Sub-view 0: Head-to-Head Comparison
          _buildIntraPeriodVisualReport(
            metricsA: metricsA,
            metricsB: metricsB,
            colorScheme: colorScheme,
            strings: strings,
            activeCountry: activeCountry,
            isAr: isAr,
          ),
          const SizedBox(height: 24),
          _buildIntraComparisonTable(
            metricsA: metricsA,
            metricsB: metricsB,
            colorScheme: colorScheme,
            strings: strings,
            activeCountry: activeCountry,
            isAr: isAr,
          ),
        ] else if (_intraSubViewMode == 1 && allMetrics.isNotEmpty) ...[
          // Sub-view 1: All Weekends Progression Matrix
          _buildPeakWeekendGoldenBanner(
            allMetrics: allMetrics,
            colorScheme: colorScheme,
            strings: strings,
            activeCountry: activeCountry,
            isAr: isAr,
          ),
          const SizedBox(height: 24),
          _buildAllWeekendsProgressionChart(
            allMetrics: allMetrics,
            colorScheme: colorScheme,
            strings: strings,
            activeCountry: activeCountry,
            isAr: isAr,
          ),
          const SizedBox(height: 24),
          _buildAllWeekendsProgressionTable(
            allMetrics: allMetrics,
            clusters: clusters,
            colorScheme: colorScheme,
            strings: strings,
            activeCountry: activeCountry,
            isAr: isAr,
          ),
        ],
      ],
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

    // Calculate Portfolio Grand Totals for M3FeedLayout
    double totalPortfolioRevenue = 0.0;
    int totalPortfolioInvoices = 0;
    int totalPortfolioProducts = 0;
    int totalPortfolioPrizes = 0;

    for (final s in summaries) {
      totalPortfolioRevenue += s.totalRevenue;
      totalPortfolioInvoices += s.totalInvoices;
      totalPortfolioProducts += s.totalProductsSold;
      totalPortfolioPrizes += s.claimedPrizesCount;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Portfolio Summary M3FeedLayout (1 col mobile, 2 cols tablet, 4 cols desktop)
        if (summaries.isNotEmpty) ...[
          M3FeedLayout(
            padding: EdgeInsets.zero,
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildPortfolioFeedKpiCard(
                title: isAr ? 'إجمالي مبيعات المحفظة' : 'Portfolio Total Revenue',
                value: '${NumberFormat('#,##0.00').format(totalPortfolioRevenue)} $currency',
                subtitle: isAr ? 'مبيعات كافة الحملات مجتمعة' : 'All campaigns aggregate sales',
                icon: Icons.payments_rounded,
                accentColor: const Color(0xFF006C50),
                colorScheme: colorScheme,
              ),
              _buildPortfolioFeedKpiCard(
                title: isAr ? 'إجمالي الفواتير المنفذة' : 'Portfolio Invoices',
                value: '${NumberFormat('#,###').format(totalPortfolioInvoices)} ${isAr ? 'فاتورة' : 'receipts'}',
                subtitle: isAr ? 'الفواتير المدققة والمقبولة' : 'Audited and verified receipts',
                icon: Icons.receipt_long_rounded,
                accentColor: const Color(0xFF0284C7),
                colorScheme: colorScheme,
              ),
              _buildPortfolioFeedKpiCard(
                title: isAr ? 'إجمالي المنتجات المباعة' : 'Products Disbursed',
                value: '${NumberFormat('#,###').format(totalPortfolioProducts)} ${isAr ? 'قطعة' : 'items'}',
                subtitle: isAr ? 'مبيعات أصناف العروض' : 'Promotional items sold',
                icon: Icons.shopping_bag_rounded,
                accentColor: const Color(0xFFD97706),
                colorScheme: colorScheme,
              ),
              _buildPortfolioFeedKpiCard(
                title: isAr ? 'الهدايا والجوائز المنصرفة' : 'Prizes Claimed',
                value: '${NumberFormat('#,###').format(totalPortfolioPrizes)} ${isAr ? 'جائزة' : 'prizes'}',
                subtitle: isAr ? 'هدايا الحملات المستلمة' : 'Campaign prizes claimed',
                icon: Icons.emoji_events_rounded,
                accentColor: const Color(0xFF7C3AED),
                colorScheme: colorScheme,
              ),
            ],
          ),
          const SizedBox(height: 18),
        ],

        // 2. Portfolio Ranking Table
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.workspace_premium_rounded,
                            color: colorScheme.primary, size: 22),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            isAr
                                ? 'ترتيب ومصفوفة أداء كافة حملات الشركة'
                                : 'All Campaigns Performance Leaderboard',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Tooltip(
                      message: isAr ? 'تصدير التقرير المقارن CSV' : 'Export Benchmark CSV',
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: Icon(Icons.file_download_rounded, size: 16, color: colorScheme.primary),
                        label: Text(
                          strings.exportComparisonCsv,
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: () {
                          _exportPortfolioCsv(summaries, currency, isAr);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              LayoutBuilder(
                builder: (context, constraints) {
                  final availableWidth = constraints.maxWidth;
                  final minWidth = math.max(availableWidth, 680.0);
                  final colSpacing = availableWidth >= 680
                      ? math.max(14.0, (availableWidth - 520) / 8)
                      : 16.0;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (availableWidth < 680)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4, left: 16, right: 16),
                          child: Row(
                            children: [
                              Icon(Icons.swipe_rounded, size: 14, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  isAr ? 'اسحب الجدول أفقياً للاطلاع على كافة الأعمدة' : 'Swipe horizontally to view all columns',
                                  style: GoogleFonts.cairo(
                                    fontSize: 10.5,
                                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      SingleChildScrollView(
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
                                  isAr ? 'الترتيب' : (isHi ? 'रैंक' : 'Rank'),
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  isAr ? 'الاسم' : (isHi ? 'नाम' : 'Name'),
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  isAr ? 'المبيعات' : (isHi ? 'बिक्री' : 'Sales'),
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  isAr ? 'الفواتير' : (isHi ? 'इनवॉइस' : 'Invoices'),
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  isAr ? 'المنتجات' : (isHi ? 'उत्पाद' : 'Products'),
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  isAr ? 'العملاء' : (isHi ? 'ग्राहक' : 'Customers'),
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  isAr ? 'سلة المشتريات' : (isHi ? 'शॉपिंग बास्केट' : 'Basket'),
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  isAr ? 'الحالة' : (isHi ? 'स्थिति' : 'Status'),
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
                  ),
                ],
              );
            },
          ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPortfolioFeedKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _exportPortfolioCsv(
    List<CampaignMetricsSummary> summaries,
    String currency,
    bool isAr,
  ) async {
    final buffer = StringBuffer();
    // UTF-8 BOM for Excel / Google Sheets compatibility with Arabic text
    buffer.write('\uFEFF');
    // CSV Header
    buffer.writeln(
        '${isAr ? 'الترتيب' : 'Rank'},${isAr ? 'الاسم' : 'Campaign Title'},${isAr ? 'المبيعات' : 'Sales'} ($currency),${isAr ? 'الفواتير' : 'Invoices'},${isAr ? 'المنتجات' : 'Products'},${isAr ? 'العملاء' : 'Customers'},${isAr ? 'سلة المشتريات' : 'Avg Basket'} ($currency),${isAr ? 'الحالة' : 'Status'}');

    for (int i = 0; i < summaries.length; i++) {
      final s = summaries[i];
      final title = '"${s.campaignTitle.replaceAll('"', '""')}"';
      final status = s.isActive ? (isAr ? 'نشطة' : 'Active') : (isAr ? 'منتهية' : 'Ended');
      buffer.writeln(
          '${i + 1},$title,${s.totalRevenue.toStringAsFixed(2)},${s.totalInvoices},${s.totalProductsSold},${s.uniqueShoppersCount},${s.avgBasketSpend.toStringAsFixed(2)},$status');
    }

    final csvData = buffer.toString();
    if (kIsWeb) {
      final bytes = utf8.encode(csvData);
      final base64Csv = base64Encode(bytes);
      final url = 'data:text/csv;charset=utf-8;base64,$base64Csv';
      try {
        await launchUrl(Uri.parse(url));
      } catch (_) {}
    } else {
      await Clipboard.setData(ClipboardData(text: csvData));
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isAr
              ? 'تم تصدير تقرير المقارنة الشامل (CSV) بنجاح'
              : 'Benchmark CSV report exported successfully',
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

class _VisualMetricItem {
  final String title;
  final IconData icon;
  final double valA;
  final double valB;
  final String unit;
  final bool isCurrency;

  const _VisualMetricItem({
    required this.title,
    required this.icon,
    required this.valA,
    required this.valB,
    required this.unit,
    this.isCurrency = false,
  });

  double get diff => valA - valB;
  double get total => valA + valB;
  double get pctA => total > 0 ? (valA / total) : 0.5;
  double get pctB => total > 0 ? (valB / total) : 0.5;
  double get shareA => pctA;
  double get shareB => pctB;

  double get deltaPercent {
    if (valB > 0) {
      return ((valA - valB) / valB) * 100;
    } else if (valA > 0) {
      return 100.0;
    }
    return 0.0;
  }

  bool get isWinnerA => valA > valB;
  bool get isWinnerB => valB > valA;
  bool get isTied => (valA - valB).abs() < 0.001;
}
