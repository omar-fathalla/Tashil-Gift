import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_service.dart';
import '../../features/company_portal/domain/daily_branch_sales_model.dart';
import '../../core/utils/slug_utils.dart';

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

  static String _normalizeBranch(String rawBranch, Set<String> canonicalBranches) {
    if (rawBranch.isEmpty) return '';

    // Strip parenthetical governorate (Rule #8)
    String cleaned = rawBranch
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .replaceAll(RegExp(r'فرع\s+'), '')
        .trim();

    for (final cb in canonicalBranches) {
      final cbClean = cb
          .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
          .replaceAll(RegExp(r'فرع\s+'), '')
          .trim();
      if (cbClean.toLowerCase() == cleaned.toLowerCase() ||
          cb.toLowerCase() == rawBranch.toLowerCase() ||
          rawBranch.contains(cbClean) ||
          cbClean.contains(cleaned)) {
        return cb;
      }
    }
    return rawBranch;
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

    final Map<String, _DailyBranchAccumulator> accumulators = {};

    for (final doc in txSnap.docs) {
      final data = doc.data();

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

      // Check Status: ONLY skip explicit fraudulent or deleted receipts
      final status = (data['status'] ?? '').toString().toLowerCase().trim();
      if (status == 'rejected' || status == 'fraud' || status == 'deleted' || data['is_fraud'] == true) {
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

      // Extract Branch with Rule #8 Canonical Normalization
      String rawBranch = (data['canonical_branch'] ?? data['branch_detected'] ?? data['branch_name'] ?? data['branchName'] ?? data['branch'] ?? '').toString().trim();
      String branchName = _normalizeBranch(rawBranch, companyBranches);
      if (branchName.isEmpty) {
        branchName = 'الفرع الرئيسي';
      }
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

      // Extract Sales Total from all possible field names
      double salesVal = (data['target_company_total'] ??
              data['promo_sales'] ??
              data['total_value'] ??
              data['total_amount'] ??
              data['totalAmount'] ??
              data['receipt_total'] ??
              data['net_amount'] ??
              data['total'] as num?)
          ?.toDouble() ?? 0.0;

      if (salesVal <= 0.0) {
        final rawExtracted = (data['extracted_products'] as List?) ?? [];
        for (final p in rawExtracted) {
          if (p is Map) {
            final pQty = (p['quantity'] as num?)?.toInt() ?? 1;
            final pPrice = (p['price'] ?? p['unit_price'] as num?)?.toDouble() ?? 0.0;
            salesVal += (pQty * pPrice);
          }
        }
      }
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

  /// Backfills and materializes all historical daily branch sales records into `daily_campaign_branch_sales`
  /// Uses atomic batch writes with single-pass optimization.
  Future<int> backfillDailySalesFromTransactions({
    required String companySlug,
    String? campaignId,
  }) async {
    final db = _firestore;
    if (db == null) return 0;

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
