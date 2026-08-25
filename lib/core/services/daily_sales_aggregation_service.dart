import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_service.dart';
import '../../features/company_portal/domain/daily_branch_sales_model.dart';
import '../../core/utils/slug_utils.dart';
import '../../core/utils/arabic_numbers_utils.dart';

final dailySalesAggregationServiceProvider = Provider<DailySalesAggregationService>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return DailySalesAggregationService(firestore);
});

/// High-performance service for managing, aggregating, and querying daily branch sales and gift disbursals.
class DailySalesAggregationService {
  final FirebaseFirestore? _firestore;

  DailySalesAggregationService(this._firestore);

  /// Helper to generate deterministic document ID for daily branch sales summaries
  static String buildDocId({
    required String companySlug,
    required String campaignId,
    required String branchName,
    required String dateStr,
  }) {
    final s = companySlug.toLowerCase().trim();
    final c = campaignId.trim().isEmpty ? 'all' : campaignId.trim();
    final b = SlugUtils.generateSlug(branchName);
    final d = dateStr.trim();
    return '${s}_${c}_${b}_$d';
  }

  static bool _isVoucherText(String text) {
    final clean = text.toLowerCase();
    return clean.contains('فواتشر') ||
        clean.contains('فوتشر') ||
        clean.contains('voucher') ||
        clean.contains('قسيمة') ||
        clean.contains('كوبون') ||
        clean.contains('coupon') ||
        clean.contains('مشتريات') ||
        clean.contains('shopping');
  }

  static double _extractVoucherDenom(String text) {
    final regex = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ج\.م|egp|جنيه|ريال|درهم|جم)?', caseSensitive: false);
    final match = regex.firstMatch(text);
    if (match != null) {
      final parsed = double.tryParse(match.group(1) ?? '');
      if (parsed != null && parsed > 0) return parsed;
    }
    return 0.0;
  }

  static String _cleanBranchForComparison(String branch) {
    var s = branch.trim().toLowerCase().toEnglishDigits();
    // Diacritics
    s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    // Alef normalization
    s = s.replaceAll(RegExp(r'[أإآ]'), 'ا');
    // Ta marbuta and ya
    s = s.replaceAll('ة', 'ه').replaceAll('ى', 'ي');
    // Remove city / governorate suffixes in parentheses (Rule #8)
    s = s.replaceAll(
      RegExp(
        r'\((القاهرة|الإسكندرية|الاسكندرية|الجيزة|الغربية|الدقهلية|المنوفية|الشرقية|البحيرة|كفر الشيخ|دمياط|بورسعيد|السويس|الإسماعيلية|الفيوم|بني سويف|المنيا|أسيوط|سوهاج|قنا|الأقصر|أسوان|مطروح|cairo|alexandria|giza)\)',
        caseSensitive: false,
      ),
      ' ',
    );
    // Punctuation, symbols, and brackets
    s = s.replaceAll(RegExp(r'[\(\)\[\]\{\}\-\_\,\.\:\/]'), ' ');
    // Remove prefixes and noise words
    s = s.replaceAll(RegExp(r'\b(فرع|سلسلة|store|branch|مفرع|pos|كود|محافظة|مدينة)\b', caseSensitive: false), ' ');
    // Extra spaces
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// Validates whether a transaction document data represents an accepted valid invoice
  static bool isValidInvoice(Map<String, dynamic> data) {
    final bool isExplicitlyValid = data['is_valid'] == true || data['status'] == 'accepted' || data['isValid'] == true;
    final bool isExplicitlyRejected = data['is_valid'] == false ||
        data['status'] == 'rejected' ||
        data['status'] == 'fraud' ||
        data['status'] == 'deleted' ||
        data['isValid'] == false ||
        data['is_fraud'] == true ||
        ((data['unfulfilled_conditions'] as List?)?.isNotEmpty ?? false);
    return isExplicitlyValid || (!isExplicitlyRejected && ((data['unfulfilled_conditions'] as List?)?.isEmpty ?? true));
  }

  /// Extracts the net sales revenue for target company promo with unified priority matching Campaign Reports
  static double extractSalesAmount(Map<String, dynamic> data) {
    final num? directVal = (data['target_company_total'] ??
        data['total_value'] ??
        data['promo_sales'] ??
        data['total_amount'] ??
        data['totalAmount'] ??
        data['receipt_total'] ??
        data['net_amount'] ??
        data['total']) as num?;
    if (directVal != null && directVal > 0) {
      return directVal.toDouble();
    }

    // Fallback: sum of extracted target products
    double sum = 0.0;
    final rawExtracted = (data['extracted_products'] as List?) ?? [];
    for (final p in rawExtracted) {
      if (p is Map) {
        final pQty = (p['quantity'] as num?)?.toInt() ?? 1;
        final pPrice = (p['price'] ?? p['unit_price'] as num?)?.toDouble() ?? 0.0;
        sum += (pQty * pPrice);
      }
    }
    return sum;
  }

  /// Universal Canonical Branch Resolution (Zero-Dropping: Returns clean string if no canonical match found)
  static String normalizeBranchName(
    String rawBranch,
    Iterable<String> canonicalBranches, {
    bool isAr = true,
  }) {
    final clean = rawBranch.trim();
    if (clean.isEmpty) return isAr ? 'فرع غير محدد' : 'Unspecified Branch';
    final branchesList = canonicalBranches.where((b) => b.trim().isNotEmpty).toList();
    if (branchesList.isEmpty) return clean;

    // 1. Direct case-insensitive match
    for (final canonical in branchesList) {
      if (canonical.trim().toLowerCase() == clean.toLowerCase()) {
        return canonical;
      }
    }

    // 2. Cleaned exact match
    final cleanComp = _cleanBranchForComparison(clean);
    for (final canonical in branchesList) {
      final canonComp = _cleanBranchForComparison(canonical);
      if (cleanComp == canonComp && cleanComp.isNotEmpty) {
        return canonical;
      }
    }

    // 3. Precision Area / Branch matching (Rule #8)
    // A. Gardenia
    if (cleanComp.contains('جاردينيا') || cleanComp.contains('gardenia')) {
      for (final canonical in branchesList) {
        if (_cleanBranchForComparison(canonical).contains('جاردينيا')) return canonical;
      }
    }

    // B. Agamy
    if (cleanComp.contains('عجمي') || cleanComp.contains('agamy') || cleanComp.contains('agami')) {
      for (final canonical in branchesList) {
        if (_cleanBranchForComparison(canonical).contains('عجمي')) return canonical;
      }
    }

    // C. Smouha
    if (cleanComp.contains('سموح') || cleanComp.contains('smouha')) {
      for (final canonical in branchesList) {
        if (_cleanBranchForComparison(canonical).contains('سموح')) return canonical;
      }
    }

    // D. Mahalla El Kubra
    if (cleanComp.contains('محله') || cleanComp.contains('mahalla')) {
      for (final canonical in branchesList) {
        if (_cleanBranchForComparison(canonical).contains('محله')) return canonical;
      }
    }

    // E. Shebin El Kom
    if (cleanComp.contains('شين') || cleanComp.contains('شبين') || cleanComp.contains('shebin')) {
      for (final canonical in branchesList) {
        final c = _cleanBranchForComparison(canonical);
        if (c.contains('شبين') || c.contains('شين')) return canonical;
      }
    }

    // F. Tagmoo / Fifth Settlement / Park Mall
    if (cleanComp.contains('تجمع') || cleanComp.contains('tagmoo') || cleanComp.contains('park mall') || cleanComp.contains('fifth')) {
      for (final canonical in branchesList) {
        final c = _cleanBranchForComparison(canonical);
        if (c.contains('تجمع') || c.contains('tagmoo')) return canonical;
      }
    }

    // G. 6th of October
    if (cleanComp.contains('اكتوبر') || cleanComp.contains('october') || cleanComp.contains('سادس')) {
      for (final canonical in branchesList) {
        final c = _cleanBranchForComparison(canonical);
        if (c.contains('اكتوبر') || c.contains('october')) return canonical;
      }
    }

    // H. Mansoura
    if (cleanComp.contains('منصور') || cleanComp.contains('mansoura')) {
      for (final canonical in branchesList) {
        if (_cleanBranchForComparison(canonical).contains('منصور')) return canonical;
      }
    }

    // I. Obour / Salah Salem
    if (cleanComp.contains('صلاح سالم') || cleanComp.contains('عبور') || cleanComp.contains('obour')) {
      for (final canonical in branchesList) {
        final c = _cleanBranchForComparison(canonical);
        if (c.contains('صلاح سالم') || c.contains('عبور')) return canonical;
      }
    }

    // J. Montazah (and Store 418 / كود 418)
    if (clean.toEnglishDigits().contains('418') || cleanComp.contains('منتزه') || cleanComp.contains('montazah')) {
      for (final canonical in branchesList) {
        final c = _cleanBranchForComparison(canonical);
        if (c.contains('منتزه') || c.contains('montazah') || canonical.toEnglishDigits().contains('418')) return canonical;
      }
    }

    // K. Miami
    if (cleanComp.contains('ميامي') || cleanComp.contains('miami')) {
      for (final canonical in branchesList) {
        if (_cleanBranchForComparison(canonical).contains('ميامي')) return canonical;
      }
    }

    // L. Janaklis
    if (cleanComp.contains('جناكليس') || cleanComp.contains('janaklis')) {
      for (final canonical in branchesList) {
        if (_cleanBranchForComparison(canonical).contains('جناكليس')) return canonical;
      }
    }

    // 4. Store Code Match (e.g. "Store: 418" / "Store 418" / "كود 418")
    final rawDigits = RegExp(r'\b\d+\b').allMatches(clean.toEnglishDigits()).map((m) => m.group(0)!).toSet();
    if (rawDigits.isNotEmpty) {
      for (final canonical in branchesList) {
        final canonDigits = RegExp(r'\b\d+\b').allMatches(canonical.toEnglishDigits()).map((m) => m.group(0)!).toSet();
        if (rawDigits.intersection(canonDigits).isNotEmpty) {
          return canonical;
        }
      }
    }

    // 5. Fallback containment matching
    for (final canonical in branchesList) {
      final canonComp = _cleanBranchForComparison(canonical);
      if (canonComp.isNotEmpty && (cleanComp.contains(canonComp) || canonComp.contains(cleanComp))) {
        return canonical;
      }
    }

    // 6. Zero-Dropping Guarantee: Return clean raw string if no canonical match, NEVER drop invoice!
    return clean;
  }

  /// Real-time stream of daily branch sales from materialized collection `daily_campaign_branch_sales`
  Stream<List<DailyBranchSalesModel>> streamDailyBranchSales({
    required String companySlug,
    String? campaignId,
    String? dateStr,
  }) {
    final db = _firestore;
    if (db == null) return Stream.value([]);

    final slug = companySlug.toLowerCase().trim();
    if (slug.isEmpty) return Stream.value([]);

    Query<Map<String, dynamic>> query = db
        .collection('daily_campaign_branch_sales')
        .where('companySlug', isEqualTo: slug);

    if (campaignId != null && campaignId.isNotEmpty && campaignId != 'all' && campaignId != 'ALL') {
      query = query.where('campaignId', isEqualTo: campaignId);
    }

    if (dateStr != null && dateStr.isNotEmpty && dateStr != 'all' && dateStr != 'ALL') {
      query = query.where('dateStr', isEqualTo: dateStr);
    }

    return query.snapshots().map((snap) {
      return snap.docs.map((doc) => DailyBranchSalesModel.fromFirestore(doc)).toList();
    });
  }

  /// Core pure aggregation algorithm from raw transaction data maps (0ms CPU overhead)
  static List<DailyBranchSalesModel> aggregateTransactionsData({
    required List<Map<String, dynamic>> rawTransactions,
    required String companySlug,
    String? campaignId,
    String? targetDateStr,
    Set<String> companyBranches = const {},
    Set<String> companyEventIds = const {},
    Map<String, String> companyEventNames = const {},
    Set<String> companyTargetNames = const {},
  }) {
    final slug = companySlug.toLowerCase().trim();
    if (slug.isEmpty || rawTransactions.isEmpty) return [];

    final Map<String, _DailyBranchAccumulator> accumulators = {};

    for (final data in rawTransactions) {
      // Check Company Match (Supports slug, targetCompany, companyName, campaignId)
      final docSlug = (data['companySlug'] ?? data['company_slug'] ?? '').toString().toLowerCase().trim();
      final docTarget = (data['targetCompany'] ?? data['target_company'] ?? data['companyName'] ?? data['company'] ?? '').toString().toLowerCase().trim();
      final docCampaignId = (data['campaignId'] ?? data['event_id'] ?? data['eventId'] ?? '').toString().trim();

      bool matchesCompany = false;
      if (slug.isNotEmpty && docSlug == slug) {
        matchesCompany = true;
      } else if (slug.isNotEmpty && docTarget.contains(slug)) {
        matchesCompany = true;
      } else if (companyTargetNames.any((t) => docTarget.contains(t.toLowerCase()))) {
        matchesCompany = true;
      } else if (companyEventIds.contains(docCampaignId)) {
        matchesCompany = true;
      }

      if (!matchesCompany) continue;

      // Filter by Campaign ID if specified
      if (campaignId != null && campaignId.isNotEmpty && campaignId != 'all' && campaignId != 'ALL') {
        if (docCampaignId != campaignId) continue;
      }

      // Check Status with Unified Rule (matches Campaign Reports & Invoices Log)
      if (!isValidInvoice(data)) {
        continue;
      }

      final effectiveCampaignId = docCampaignId.isNotEmpty ? docCampaignId : (companyEventIds.firstOrNull ?? 'general');
      final effectiveCampaignName = companyEventNames[effectiveCampaignId] ??
          (data['campaignName'] ?? data['targetCompany'] ?? data['retail_chain_name'] ?? 'حملة ترويجية').toString();

      // Extract Date (YYYY-MM-DD)
      String dateStr = '';
      DateTime recordDate = DateTime.now();

      final rawReceiptDate = (data['receipt_date'] ?? data['receiptDate'] ?? data['dateStr'] ?? '').toString().trim();
      if (rawReceiptDate.isNotEmpty && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawReceiptDate)) {
        dateStr = rawReceiptDate;
        recordDate = DateTime.tryParse(dateStr) ?? recordDate;
      } else if (rawReceiptDate.isNotEmpty && RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(rawReceiptDate)) {
        final parts = rawReceiptDate.split('/');
        dateStr = '${parts[2]}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}';
        recordDate = DateTime.tryParse(dateStr) ?? recordDate;
      } else {
        final rawTs = data['timestamp'] ?? data['claimed_at'] ?? data['created_at'] ?? data['date'];
        if (rawTs is Timestamp) {
          recordDate = rawTs.toDate();
          dateStr = "${recordDate.year.toString().padLeft(4, '0')}-${recordDate.month.toString().padLeft(2, '0')}-${recordDate.day.toString().padLeft(2, '0')}";
        } else if (rawTs is String && rawTs.isNotEmpty) {
          final parsed = DateTime.tryParse(rawTs);
          if (parsed != null) {
            recordDate = parsed;
            dateStr = "${recordDate.year.toString().padLeft(4, '0')}-${recordDate.month.toString().padLeft(2, '0')}-${recordDate.day.toString().padLeft(2, '0')}";
          }
        }
      }

      if (dateStr.isEmpty) {
        final now = DateTime.now();
        dateStr = "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      }

      // Filter by Target Date if specified
      if (targetDateStr != null && targetDateStr.isNotEmpty && targetDateStr != 'all' && targetDateStr != 'ALL') {
        if (dateStr != targetDateStr) continue;
      }

      // Extract Branch with Rule #8 Canonical Normalization (Never dropped)
      final rawBranch = (data['canonical_branch'] ?? data['branch_detected'] ?? data['branch_name'] ?? data['branchName'] ?? data['branch'] ?? '').toString().trim();
      final branchName = normalizeBranchName(rawBranch, companyBranches);
      final branchId = (data['branch_id'] ?? data['branchId'] ?? '').toString();
      final retailChain = (data['retail_chain_name'] ?? data['store_chain_detected'] ?? data['store_chain'] ?? '').toString();

      // Accumulator Key
      final key = buildDocId(
        companySlug: slug,
        campaignId: effectiveCampaignId,
        branchName: branchName,
        dateStr: dateStr,
      );

      final acc = accumulators.putIfAbsent(
        key,
        () => _DailyBranchAccumulator(
          id: key,
          companySlug: slug,
          campaignId: effectiveCampaignId,
          campaignName: effectiveCampaignName,
          dateStr: dateStr,
          date: recordDate,
          branchName: branchName,
          branchId: branchId,
          retailChain: retailChain,
        ),
      );

      // Add Invoice Count
      acc.invoicesCount += 1;

      // Extract Sales Total using Unified Logic
      final salesVal = extractSalesAmount(data);
      acc.totalSalesAmount += salesVal;

      // Extract Disbursed Gifts and Vouchers
      bool giftsFound = false;

      // 1. claimed_gifts (List of maps)
      final rawClaimedGifts = (data['claimed_gifts'] as List?) ?? [];
      if (rawClaimedGifts.isNotEmpty) {
        for (final g in rawClaimedGifts) {
          if (g is Map) {
            final gMap = Map<String, dynamic>.from(g);
            final giftKey = (gMap['giftId'] ?? gMap['gift_id'] ?? gMap['giftName'] ?? gMap['name'] ?? 'gift').toString();
            final giftName = (gMap['giftName'] ?? gMap['name'] ?? giftKey).toString();
            final qty = (gMap['quantity'] as num?)?.toInt() ?? (gMap['count'] as num?)?.toInt() ?? 1;
            final isVoucher = gMap['isVoucher'] == true || gMap['is_voucher'] == true || _isVoucherText(giftName);
            final rawUnitVal = (gMap['unitValue'] ?? gMap['unit_value'] as num?)?.toDouble() ?? 0.0;
            final unitVal = rawUnitVal > 0 ? rawUnitVal : _extractVoucherDenom(giftName);
            final rawTotalVal = (gMap['totalValue'] ?? gMap['total_value'] as num?)?.toDouble() ?? 0.0;
            final totalVal = rawTotalVal > 0 ? rawTotalVal : (qty * unitVal);

            acc.addGiftDisbursal(
              giftKey: giftKey,
              giftName: giftName,
              quantity: qty,
              isVoucher: isVoucher,
              unitValue: unitVal,
              totalValue: totalVal,
            );
            giftsFound = true;
          }
        }
      }

      // 2. linkedGifts / linked_gifts
      if (!giftsFound) {
        final rawLinked = (data['linkedGifts'] ?? data['linked_gifts'] as List?) ?? [];
        if (rawLinked.isNotEmpty) {
          for (final lg in rawLinked) {
            if (lg is Map) {
              final lgMap = Map<String, dynamic>.from(lg);
              final gName = (lgMap['giftName'] ?? lgMap['name'] ?? '').toString().trim();
              final gKey = (lgMap['giftId'] ?? lgMap['gift_id'] ?? gName).toString();
              final gQty = (lgMap['quantity'] as num?)?.toInt() ?? 1;
              final isVoucher = lgMap['isVoucher'] == true || lgMap['giftType'] == 'voucher' || _isVoucherText(gName);
              final rawUnitVal = (lgMap['unitValue'] as num?)?.toDouble() ?? 0.0;
              final unitVal = rawUnitVal > 0 ? rawUnitVal : _extractVoucherDenom(gName);
              if (gName.isNotEmpty && gQty > 0) {
                acc.addGiftDisbursal(
                  giftKey: gKey,
                  giftName: gName,
                  quantity: gQty,
                  isVoucher: isVoucher,
                  unitValue: unitVal,
                  totalValue: unitVal * gQty,
                );
                giftsFound = true;
              }
            }
          }
        }
      }

      // 3. prizes_won (List of strings)
      if (!giftsFound) {
        final rawPrizesWon = (data['prizes_won'] as List?) ?? [];
        if (rawPrizesWon.isNotEmpty) {
          for (final p in rawPrizesWon) {
            final pName = p.toString().trim();
            if (pName.isNotEmpty && pName != 'null' && pName != 'لم يفز' && pName != 'لا توجد هدية') {
              final isVoucher = _isVoucherText(pName);
              final unitVal = _extractVoucherDenom(pName);
              acc.addGiftDisbursal(
                giftKey: pName,
                giftName: pName,
                quantity: 1,
                isVoucher: isVoucher,
                unitValue: unitVal,
                totalValue: unitVal,
              );
              giftsFound = true;
            }
          }
        }
      }

      // 4. prize_won (Single string)
      if (!giftsFound) {
        final prizeWon = (data['prize_won'] ?? data['prizeName'] ?? data['gift_name'] ?? '').toString().trim();
        if (prizeWon.isNotEmpty && prizeWon != 'null' && prizeWon != 'لم يفز' && prizeWon != 'لا توجد هدية') {
          final isVoucher = _isVoucherText(prizeWon);
          final unitVal = _extractVoucherDenom(prizeWon);
          acc.addGiftDisbursal(
            giftKey: prizeWon,
            giftName: prizeWon,
            quantity: 1,
            isVoucher: isVoucher,
            unitValue: unitVal,
            totalValue: unitVal,
          );
          giftsFound = true;
        }
      }

      // 5. Standalone voucher values
      final vVal = (data['voucher_value'] ?? data['voucherValue'] as num?)?.toDouble() ?? 0.0;
      if (vVal > 0 && acc.totalVouchersValue == 0) {
        final label = 'فواتشر ${vVal.toInt()} جنيه';
        acc.addGiftDisbursal(
          giftKey: label,
          giftName: label,
          quantity: 1,
          isVoucher: true,
          unitValue: vVal,
          totalValue: vVal,
        );
      }

      // Extract Products Sold
      final rawExtractedProducts = (data['extracted_products'] as List<dynamic>?) ?? [];
      for (final p in rawExtractedProducts) {
        if (p is Map) {
          final pName = (p['name'] ?? p['product_name'] ?? p['item_name'] ?? '').toString().trim();
          final pQty = (p['quantity'] as num?)?.toInt() ?? 1;
          final pPrice = (p['price'] ?? p['unit_price'] as num?)?.toDouble() ?? 0.0;
          if (pName.isNotEmpty) {
            acc.addProductSale(pName, pQty, pPrice * pQty);
          }
        }
      }
    }

    return accumulators.values.map((a) => a.toModel()).toList();
  }

  /// On-demand real-time aggregation from `receipts_transactions`
  /// Reads 100% of receipts without dropping valid invoices.
  Future<List<DailyBranchSalesModel>> aggregateLiveFromTransactions({
    required String companySlug,
    String? campaignId,
    String? targetDateStr, // Optional specific date (YYYY-MM-DD)
  }) async {
    final db = _firestore;
    if (db == null) return [];

    final slug = companySlug.toLowerCase().trim();
    if (slug.isEmpty) return [];

    // 1. Fetch company events to resolve campaign metadata and canonical branch lists
    final eventsSnap = await db.collection('events').get();
    final companyEvents = eventsSnap.docs.where((d) {
      final data = d.data();
      final eSlug = (data['companySlug'] ?? data['company_slug'] ?? '').toString().toLowerCase().trim();
      final targetComp = (data['targetCompany'] ?? data['target_company'] ?? '').toString().toLowerCase().trim();
      return (slug.isNotEmpty && eSlug == slug) || (slug.isNotEmpty && targetComp.contains(slug));
    }).toList();

    final companyEventIds = companyEvents.map((d) => d.id).toSet();
    final companyEventNames = <String, String>{
      for (var d in companyEvents) d.id: (d.data()['eventName'] ?? d.data()['name'] ?? 'حملة ترويجية').toString()
    };
    final companyTargetNames = companyEvents
        .map((d) => (d.data()['targetCompany'] ?? d.data()['target_company'] ?? '').toString().trim())
        .where((t) => t.isNotEmpty)
        .toSet();

    final Set<String> companyBranches = {};
    for (final d in companyEvents) {
      final bNames = (d.data()['branchNames'] as List?)?.map((e) => e.toString().trim()).where((e) => e.isNotEmpty) ?? [];
      companyBranches.addAll(bNames);
      final prizes = (d.data()['allocatedPrizes'] as List?) ?? [];
      for (final p in prizes) {
        if (p is Map) {
          final b = (p['branchName'] ?? p['branch_name'] ?? '').toString().trim();
          if (b.isNotEmpty) companyBranches.add(b);
        }
      }
    }

    // 2. Query transactions collection
    final txSnap = await db.collection('receipts_transactions').get();
    if (txSnap.docs.isEmpty) return [];

    final rawTxList = txSnap.docs.map((d) => d.data()).toList();

    return aggregateTransactionsData(
      rawTransactions: rawTxList,
      companySlug: slug,
      campaignId: campaignId,
      targetDateStr: targetDateStr,
      companyBranches: companyBranches,
      companyEventIds: companyEventIds,
      companyEventNames: companyEventNames,
      companyTargetNames: companyTargetNames,
    );
  }

  /// Backfills and materializes all historical daily branch sales records into `daily_campaign_branch_sales`
  /// Uses atomic batch writes with single-pass optimization.
  Future<int> backfillDailySalesFromTransactions({
    required String companySlug,
    String? campaignId,
  }) async {
    final db = _firestore;
    if (db == null) return 0;

    final slug = companySlug.toLowerCase().trim();
    if (slug.isEmpty) return 0;

    // 1. Wipe existing stale/rogue daily sales records for this company/campaign to ensure 100% clean sync
    final oldDocsQuery = campaignId != null && campaignId.isNotEmpty && campaignId != 'all' && campaignId != 'ALL'
        ? db.collection('daily_campaign_branch_sales').where('companySlug', isEqualTo: slug).where('campaignId', isEqualTo: campaignId)
        : db.collection('daily_campaign_branch_sales').where('companySlug', isEqualTo: slug);
    final oldDocs = await oldDocsQuery.get();
    if (oldDocs.docs.isNotEmpty) {
      WriteBatch deleteBatch = db.batch();
      int dCount = 0;
      for (final d in oldDocs.docs) {
        deleteBatch.delete(d.reference);
        dCount++;
        if (dCount >= 400) {
          await deleteBatch.commit();
          deleteBatch = db.batch();
          dCount = 0;
        }
      }
      if (dCount > 0) {
        await deleteBatch.commit();
      }
    }

    // 2. Perform live multi-tier aggregation with canonical branch scoping
    final models = await aggregateLiveFromTransactions(
      companySlug: companySlug,
      campaignId: campaignId,
    );

    if (models.isEmpty) return 0;

    int totalSaved = 0;
    WriteBatch batch = db.batch();
    int batchCount = 0;

    for (final model in models) {
      final docRef = db.collection('daily_campaign_branch_sales').doc(model.id);
      batch.set(docRef, model.toFirestore(), SetOptions(merge: true));
      batchCount++;
      totalSaved++;

      // Firestore batch size limit is 500
      if (batchCount >= 400) {
        await batch.commit();
        batch = db.batch();
        batchCount = 0;
      }
    }

    if (batchCount > 0) {
      await batch.commit();
    }

    return totalSaved;
  }
}

/// Internal helper accumulator to aggregate records in-memory
class _DailyBranchAccumulator {
  final String id;
  final String companySlug;
  final String campaignId;
  final String campaignName;
  final String dateStr;
  final DateTime date;
  final String branchName;
  final String branchId;
  final String retailChain;

  int invoicesCount = 0;
  double totalSalesAmount = 0.0;
  int totalGiftsCount = 0;
  double totalVouchersValue = 0.0;
  final Map<String, DailyGiftDisbursalItem> giftsDisbursed = {};
  final Map<String, _TopProductAccumulator> topProducts = {};

  _DailyBranchAccumulator({
    required this.id,
    required this.companySlug,
    required this.campaignId,
    required this.campaignName,
    required this.dateStr,
    required this.date,
    required this.branchName,
    required this.branchId,
    required this.retailChain,
  });

  void addGiftDisbursal({
    required String giftKey,
    required String giftName,
    required int quantity,
    required bool isVoucher,
    required double unitValue,
    required double totalValue,
  }) {
    totalGiftsCount += quantity;
    if (isVoucher) {
      totalVouchersValue += totalValue;
    }

    final existing = giftsDisbursed[giftKey];
    if (existing != null) {
      giftsDisbursed[giftKey] = existing.copyWith(
        quantity: existing.quantity + quantity,
        totalValue: existing.totalValue + totalValue,
      );
    } else {
      giftsDisbursed[giftKey] = DailyGiftDisbursalItem(
        giftKey: giftKey,
        giftName: giftName,
        quantity: quantity,
        isVoucher: isVoucher,
        unitValue: unitValue,
        totalValue: totalValue,
      );
    }
  }

  void addProductSale(String productName, int quantity, double sales) {
    final existing = topProducts[productName];
    if (existing != null) {
      existing.quantity += quantity;
      existing.totalSales += sales;
    } else {
      topProducts[productName] = _TopProductAccumulator(
        productName: productName,
        quantity: quantity,
        totalSales: sales,
      );
    }
  }

  DailyBranchSalesModel toModel() {
    final sortedProducts = topProducts.values.map((p) => p.toModel()).toList()
      ..sort((a, b) => b.totalSales.compareTo(a.totalSales));

    return DailyBranchSalesModel(
      id: id,
      companySlug: companySlug,
      campaignId: campaignId,
      campaignName: campaignName,
      dateStr: dateStr,
      date: date,
      branchName: branchName,
      branchId: branchId,
      retailChain: retailChain,
      invoicesCount: invoicesCount,
      totalSalesAmount: totalSalesAmount,
      totalGiftsCount: totalGiftsCount,
      totalVouchersValue: totalVouchersValue,
      giftsDisbursed: Map.from(giftsDisbursed),
      topProducts: sortedProducts.take(10).toList(),
      lastUpdatedAt: DateTime.now(),
    );
  }
}

class _TopProductAccumulator {
  final String productName;
  int quantity;
  double totalSales;

  _TopProductAccumulator({
    required this.productName,
    required this.quantity,
    required this.totalSales,
  });

  DailyTopProductItem toModel() {
    return DailyTopProductItem(
      productName: productName,
      quantity: quantity,
      totalSales: totalSales,
    );
  }
}
