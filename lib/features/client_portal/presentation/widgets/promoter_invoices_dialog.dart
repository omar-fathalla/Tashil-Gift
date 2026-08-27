import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/firebase_service.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/constants/country_currency_config.dart';
import '../../../../core/utils/arabic_numbers_utils.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../admin/domain/event_model.dart';

enum PromoterDateFilter { all, today, last7Days, thisMonth }

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
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _selectedBranch; // null or empty string means 'All Branches'
  String? _pinnedBranch;
  PromoterDateFilter _dateFilter = PromoterDateFilter.all;
  final Set<String> _expandedDocIds = <String>{};

  static const int _pageSize = 25;
  int _displayedCount = _pageSize;

  @override
  void initState() {
    super.initState();
    _loadPinnedBranch();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
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

    // 5. Containment match
    for (final canonical in canonicalBranches) {
      final canonComp = _cleanBranchForComparison(canonical);
      if (canonComp.isNotEmpty && (cleanComp.contains(canonComp) || canonComp.contains(cleanComp))) {
        return canonical;
      }
    }

    // Default to first canonical branch
    return canonicalBranches.first;
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${strings.branchPinnedSuccess}: $branchName'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.teal.shade700,
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
      case PromoterDateFilter.last7Days:
        final sevenDaysAgo = now.subtract(const Duration(days: 7));
        return dt.isAfter(sevenDaysAgo) && dt.isBefore(now.add(const Duration(days: 1)));
      case PromoterDateFilter.thisMonth:
        return dt.year == now.year && dt.month == now.month;
      case PromoterDateFilter.all:
        return true;
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

    final firestore = ref.watch(firestoreProvider);

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
            stream: firestore.collection('receipts_transactions').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _buildErrorState(colorScheme, strings, snapshot.error);
              }

              final allDocs = snapshot.data?.docs ?? [];

              // 1. Strictly Canonical Branches from Event definition
              final List<String> canonicalBranches = widget.event.branchNames
                  .map((b) => b.trim())
                  .where((b) => b.isNotEmpty)
                  .toList();

              // 2. Filter transactions related to this campaign / company & only ACCEPTED / VALID invoices
              final List<Map<String, dynamic>> validCampaignInvoices = [];
              for (final doc in allDocs) {
                final data = doc.data();
                final cId = (data['campaignId'] ?? data['event_id'] ?? data['eventId'] ?? '').toString().trim();
                final cSlug = (data['companySlug'] ?? data['company_slug'] ?? '').toString().trim().toLowerCase();
                final targetComp = (data['targetCompany'] ?? data['target_company'] ?? '').toString().trim().toLowerCase();

                final eventSlug = widget.event.companySlug.trim().toLowerCase();
                final eventTarget = widget.event.targetCompany.trim().toLowerCase();

                final bool matchesCampaign = (widget.event.id.isNotEmpty && cId == widget.event.id) ||
                    (eventSlug.isNotEmpty && cSlug == eventSlug) ||
                    (eventTarget.isNotEmpty && targetComp.contains(eventTarget));

                if (!matchesCampaign) continue;

                // Explicit check for valid invoices (exclude rejected as requested)
                final bool isExplicitlyValid = data['is_valid'] == true || data['status'] == 'accepted' || data['isValid'] == true;
                final bool isExplicitlyRejected = data['is_valid'] == false || data['status'] == 'rejected' || data['isValid'] == false || ((data['unfulfilled_conditions'] as List?)?.isNotEmpty ?? false);
                final bool isValid = isExplicitlyValid || (!isExplicitlyRejected && ((data['unfulfilled_conditions'] as List?)?.isEmpty ?? true));

                if (!isValid) continue;

                final rawBranch = (data['branch_detected'] ?? data['branch_name'] ?? data['branch'] ?? '').toString().trim();
                final canonicalBranch = _normalizeBranchName(rawBranch, canonicalBranches, isAr);

                validCampaignInvoices.add({
                  'docId': doc.id,
                  ...data,
                  'canonical_branch': canonicalBranch,
                  'raw_branch': rawBranch,
                });
              }

              // 3. Compute Invoice Counts per Canonical Branch
              final Map<String, int> branchInvoiceCounts = {};
              for (final b in canonicalBranches) {
                branchInvoiceCounts[b] = 0;
              }
              for (final inv in validCampaignInvoices) {
                final b = inv['canonical_branch'] as String;
                if (branchInvoiceCounts.containsKey(b)) {
                  branchInvoiceCounts[b] = (branchInvoiceCounts[b] ?? 0) + 1;
                }
              }

              final int totalAcceptedInvoices = validCampaignInvoices.length;

              // 4. Apply Search & Filters
              final searchQuery = _searchController.text.trim().toLowerCase().toEnglishDigits();

              final filteredInvoices = validCampaignInvoices.where((inv) {
                final canonicalBranch = (inv['canonical_branch'] ?? '').toString();
                final rawBranch = (inv['raw_branch'] ?? '').toString();
                final storeChain = (inv['store_chain_detected'] ?? inv['retail_chain_name'] ?? '').toString().trim();
                final receiptNumber = (inv['receipt_number'] ?? '').toString().trim().toLowerCase();
                final customerPhone = (inv['customerPhone'] ?? inv['customer_phone'] ?? '').toString().trim();
                final customerName = (inv['customerName'] ?? inv['customer_name'] ?? '').toString().trim().toLowerCase();
                final receiptDate = (inv['receipt_date'] ?? '').toString().trim().toLowerCase();
                final dt = _parseDateTime(inv['timestamp'], inv['receipt_date']);

                // 1. Strict Branch Filter (Exact Canonical Match)
                if (_selectedBranch != null && _selectedBranch!.isNotEmpty) {
                  if (canonicalBranch != _selectedBranch) {
                    return false;
                  }
                }

                // 2. Date Filter
                if (!_matchesDateFilter(dt)) {
                  return false;
                }

                // 3. Search Query Filter
                if (searchQuery.isNotEmpty) {
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
                    totalSales: totalSales,
                    currencySymbol: currencySymbol,
                  ),

                  const Divider(height: 1, thickness: 1),

                  // 2. Filter & Search Controls (Branches Bar + Date Chips + Search Box)
                  _buildFilterControls(
                    context: context,
                    colorScheme: colorScheme,
                    strings: strings,
                    isMobile: isMobile,
                    availableBranches: canonicalBranches,
                    branchCounts: branchInvoiceCounts,
                    totalCount: totalAcceptedInvoices,
                  ),

                  const Divider(height: 1, thickness: 1),

                  // 3. Invoices List View
                  Expanded(
                    child: snapshot.connectionState == ConnectionState.waiting && allDocs.isEmpty
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
    required double totalSales,
    required String currencySymbol,
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
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.teal.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.push_pin_rounded, size: 12, color: Colors.teal.shade800),
                            const SizedBox(width: 4),
                            Text(
                              _pinnedBranch!,
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
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
                  const SizedBox(width: 12),
                  Container(width: 1, height: 16, color: colorScheme.outlineVariant),
                  const SizedBox(width: 12),
                  Icon(Icons.monetization_on_rounded, size: 16, color: Colors.green.shade700),
                  const SizedBox(width: 4),
                  Text(
                    '${totalSales.toStringAsFixed(totalSales == totalSales.roundToDouble() ? 0 : 2)} $currencySymbol',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.green.shade800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
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
                            ? Colors.teal.shade600
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _pinnedBranch == _selectedBranch
                              ? Colors.teal.shade800
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
                                ? Colors.white
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
                                  ? Colors.white
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
                            const Icon(Icons.push_pin_rounded, size: 12, color: Colors.teal),
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

          // 2. Search Box + Date Filters Row
          if (isMobile) ...[
            _buildSearchField(colorScheme, strings),
            const SizedBox(height: 8),
            _buildDateFilterChips(colorScheme, strings),
          ] else ...[
            Row(
              children: [
                Expanded(child: _buildSearchField(colorScheme, strings)),
                const SizedBox(width: 14),
                _buildDateFilterChips(colorScheme, strings),
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

  Widget _buildDateFilterChips(ColorScheme colorScheme, AppStrings strings) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDateChip('الكل', PromoterDateFilter.all, colorScheme),
          const SizedBox(width: 6),
          _buildDateChip('اليوم', PromoterDateFilter.today, colorScheme),
          const SizedBox(width: 6),
          _buildDateChip('آخر 7 أيام', PromoterDateFilter.last7Days, colorScheme),
          const SizedBox(width: 6),
          _buildDateChip('هذا الشهر', PromoterDateFilter.thisMonth, colorScheme),
        ],
      ),
    );
  }

  Widget _buildDateChip(String label, PromoterDateFilter filter, ColorScheme colorScheme) {
    final isSelected = _dateFilter == filter;
    return FilterChip(
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
  }) {
    final receiptNumber = (data['receipt_number'] ?? 'INV-N/A').toString().trim();
    final totalVal = (data['target_company_total'] ?? data['total_value'] as num?)?.toDouble() ?? 0.0;
    final storeChain = (data['store_chain_detected'] ?? data['retail_chain_name'] ?? '').toString().trim();
    final branch = (data['canonical_branch'] ?? data['branch_detected'] ?? data['branch_name'] ?? '').toString().trim();
    final customerPhone = (data['customerPhone'] ?? data['customer_phone'] ?? '').toString().trim();
    final customerName = (data['customerName'] ?? data['customer_name'] ?? '').toString().trim();
    final receiptDate = (data['receipt_date'] ?? '').toString().trim();
    final imageUrl = (data['image_url'] ?? '').toString().trim();
    final prizeWon = (data['prize_won'] ?? '').toString().trim();
    final gamePlayed = data['game_played'] == true;
    final dt = _parseDateTime(data['timestamp'], receiptDate);
    final formattedTime = dt != null ? DateFormat('yyyy/MM/dd - hh:mm a', 'ar').format(dt) : receiptDate;

    final bool isExplicitlyValid = data['is_valid'] == true || data['status'] == 'accepted' || data['isValid'] == true;
    final bool isExplicitlyRejected = data['is_valid'] == false || data['status'] == 'rejected' || data['isValid'] == false || ((data['unfulfilled_conditions'] as List?)?.isNotEmpty ?? false);
    final bool isValid = isExplicitlyValid || (!isExplicitlyRejected && ((data['unfulfilled_conditions'] as List?)?.isEmpty ?? true));
    final rejectionReason = (data['rejection_reason'] ?? '').toString().trim();

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
              : Colors.red.shade200,
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
                          : Colors.red.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isValid ? Icons.receipt_rounded : Icons.receipt_long_rounded,
                      size: 20,
                      color: isValid ? colorScheme.primary : Colors.red.shade800,
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
                      color: isValid ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isValid ? Colors.green.shade300 : Colors.red.shade300),
                    ),
                    child: Text(
                      '${totalVal.toStringAsFixed(totalVal == totalVal.roundToDouble() ? 0 : 2)} $currencySymbol',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: isMobile ? 12.5 : 14,
                        color: isValid ? Colors.green.shade900 : Colors.red.shade900,
                      ),
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
                      color: isValid ? Colors.teal.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isValid ? Colors.teal.shade200 : Colors.red.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isValid ? Icons.verified_rounded : Icons.cancel_rounded,
                          size: 13,
                          color: isValid ? Colors.teal.shade700 : Colors.red.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isValid ? 'معتمدة ومقبولة' : 'مرفوضة وغير مقبولة',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isValid ? Colors.teal.shade800 : Colors.red.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Rejection Reason Chip if rejected
                  if (!isValid && rejectionReason.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.info_outline_rounded, size: 13, color: Colors.red.shade700),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              rejectionReason,
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.red.shade900,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

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
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.card_giftcard_rounded, size: 13, color: Colors.amber.shade900),
                          const SizedBox(width: 4),
                          Text(
                            'الجائزة: $prizeWon',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (gamePlayed) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'تم السحب ($chances فرص)',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade800,
                        ),
                      ),
                    ),
                  ],
                  if ((data['voucher_serials'] as List?)?.isNotEmpty ?? false) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade400),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.confirmation_number_rounded, size: 12, color: Colors.amber.shade900),
                          const SizedBox(width: 4),
                          Text(
                            '💳 كروت الفواتشر: ${(data['voucher_serials'] as List).join(" | ")}',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),

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
                    final pMap = p is Map ? Map<String, dynamic>.from(p) : {};
                    final name = (pMap['name'] ?? pMap['product_name'] ?? 'منتج').toString();
                    final qty = (pMap['quantity'] as num?)?.toInt() ?? 1;
                    final price = (pMap['price'] as num?)?.toDouble() ?? 0.0;
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
                            color: isTarget ? Colors.green : colorScheme.onSurfaceVariant,
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
                            'الكمية: $qty | السعر: ${price.toStringAsFixed(price == price.roundToDouble() ? 0 : 2)} $currencySymbol',
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

                // Receipt Image Preview Action Button
                if (imageUrl.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => _showReceiptImageZoomDialog(context, imageUrl, receiptNumber),
                      icon: const Icon(Icons.zoom_in_rounded, size: 16),
                      label: Text(strings.receiptZoomImage, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

  void _showReceiptImageZoomDialog(BuildContext context, String imageUrl, String receiptNumber) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                elevation: 0,
                title: Text(
                  'صورة الفاتورة: $receiptNumber',
                  style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 650),
                  child: imageUrl.startsWith('data:image')
                      ? Image.memory(
                          base64Decode(imageUrl.split(',').last),
                          fit: BoxFit.contain,
                        )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(40),
                                child: CircularProgressIndicator(color: Colors.white),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) => const Center(
                            child: Padding(
                              padding: EdgeInsets.all(40),
                              child: Text('فشل تحميل الصورة', style: TextStyle(color: Colors.white)),
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
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
            const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
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
