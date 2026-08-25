import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single disbursed gift or voucher item within a daily branch summary.
class DailyGiftDisbursalItem {
  final String giftKey;
  final String giftName;
  final int quantity;
  final bool isVoucher;
  final double unitValue;
  final double totalValue;

  const DailyGiftDisbursalItem({
    required this.giftKey,
    required this.giftName,
    required this.quantity,
    this.isVoucher = false,
    this.unitValue = 0.0,
    this.totalValue = 0.0,
  });

  factory DailyGiftDisbursalItem.fromMap(String key, Map<String, dynamic> map) {
    final qty = (map['quantity'] as num?)?.toInt() ?? (map['count'] as num?)?.toInt() ?? 0;
    final isV = map['isVoucher'] == true || map['is_voucher'] == true;
    final unitVal = (map['unitValue'] ?? map['unit_value'] as num?)?.toDouble() ?? 0.0;
    final totalVal = (map['totalValue'] ?? map['total_value'] as num?)?.toDouble() ?? (qty * unitVal);

    return DailyGiftDisbursalItem(
      giftKey: key,
      giftName: (map['giftName'] ?? map['gift_name'] ?? map['name'] ?? key).toString(),
      quantity: qty,
      isVoucher: isV,
      unitValue: unitVal,
      totalValue: totalVal,
    );
  }

  DailyGiftDisbursalItem copyWith({
    String? giftKey,
    String? giftName,
    int? quantity,
    bool? isVoucher,
    double? unitValue,
    double? totalValue,
  }) {
    return DailyGiftDisbursalItem(
      giftKey: giftKey ?? this.giftKey,
      giftName: giftName ?? this.giftName,
      quantity: quantity ?? this.quantity,
      isVoucher: isVoucher ?? this.isVoucher,
      unitValue: unitValue ?? this.unitValue,
      totalValue: totalValue ?? this.totalValue,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'giftKey': giftKey,
      'giftName': giftName,
      'quantity': quantity,
      'isVoucher': isVoucher,
      'unitValue': unitValue,
      'totalValue': totalValue,
    };
  }
}

/// Represents a top selling product within a daily branch summary.
class DailyTopProductItem {
  final String productName;
  final int quantity;
  final double totalSales;

  const DailyTopProductItem({
    required this.productName,
    required this.quantity,
    required this.totalSales,
  });

  factory DailyTopProductItem.fromMap(Map<String, dynamic> map) {
    return DailyTopProductItem(
      productName: (map['productName'] ?? map['name'] ?? '').toString(),
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      totalSales: (map['totalSales'] ?? map['total_sales'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productName': productName,
      'quantity': quantity,
      'totalSales': totalSales,
    };
  }
}

/// Materialized daily sales and gifts disbursal record per campaign branch and date.
class DailyBranchSalesModel {
  final String id;
  final String companySlug;
  final String campaignId;
  final String campaignName;
  final String dateStr; // Format: YYYY-MM-DD
  final DateTime date;
  final String branchName;
  final String branchId;
  final String retailChain;
  final int invoicesCount;
  final double totalSalesAmount;
  final int totalGiftsCount;
  final double totalVouchersValue;
  final Map<String, DailyGiftDisbursalItem> giftsDisbursed;
  final List<DailyTopProductItem> topProducts;
  final DateTime lastUpdatedAt;

  const DailyBranchSalesModel({
    required this.id,
    required this.companySlug,
    required this.campaignId,
    required this.campaignName,
    required this.dateStr,
    required this.date,
    required this.branchName,
    this.branchId = '',
    this.retailChain = '',
    this.invoicesCount = 0,
    this.totalSalesAmount = 0.0,
    this.totalGiftsCount = 0,
    this.totalVouchersValue = 0.0,
    this.giftsDisbursed = const {},
    this.topProducts = const [],
    required this.lastUpdatedAt,
  });

  factory DailyBranchSalesModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return DailyBranchSalesModel.fromMap(doc.id, data);
  }

  factory DailyBranchSalesModel.fromMap(String id, Map<String, dynamic> map) {
    final rawGifts = map['giftsDisbursed'] ?? map['gifts_disbursed'];
    final Map<String, DailyGiftDisbursalItem> parsedGifts = {};
    if (rawGifts is Map) {
      rawGifts.forEach((k, v) {
        final keyStr = k.toString();
        if (v is DailyGiftDisbursalItem) {
          parsedGifts[keyStr] = v;
        } else if (v is Map<String, dynamic>) {
          parsedGifts[keyStr] = DailyGiftDisbursalItem.fromMap(keyStr, v);
        } else if (v is Map) {
          parsedGifts[keyStr] = DailyGiftDisbursalItem.fromMap(keyStr, Map<String, dynamic>.from(v));
        }
      });
    }

    final rawTopProducts = map['topProducts'] ?? map['top_products'];
    final List<DailyTopProductItem> parsedTopProducts = [];
    if (rawTopProducts is Iterable) {
      for (final item in rawTopProducts) {
        if (item is DailyTopProductItem) {
          parsedTopProducts.add(item);
        } else if (item is Map<String, dynamic>) {
          parsedTopProducts.add(DailyTopProductItem.fromMap(item));
        } else if (item is Map) {
          parsedTopProducts.add(DailyTopProductItem.fromMap(Map<String, dynamic>.from(item)));
        }
      }
    }

    DateTime parsedDate = DateTime.now();
    final rawDate = map['date'];
    if (rawDate is Timestamp) {
      parsedDate = rawDate.toDate();
    } else if (rawDate is String && rawDate.isNotEmpty) {
      parsedDate = DateTime.tryParse(rawDate) ?? parsedDate;
    } else if (map['dateStr'] != null) {
      parsedDate = DateTime.tryParse(map['dateStr'].toString()) ?? parsedDate;
    }

    DateTime parsedUpdated = DateTime.now();
    final rawUpdated = map['lastUpdatedAt'] ?? map['last_updated_at'] ?? map['updated_at'];
    if (rawUpdated is Timestamp) {
      parsedUpdated = rawUpdated.toDate();
    } else if (rawUpdated is String && rawUpdated.isNotEmpty) {
      parsedUpdated = DateTime.tryParse(rawUpdated) ?? parsedUpdated;
    }

    return DailyBranchSalesModel(
      id: id,
      companySlug: (map['companySlug'] ?? map['company_slug'] ?? '').toString().toLowerCase().trim(),
      campaignId: (map['campaignId'] ?? map['campaign_id'] ?? '').toString(),
      campaignName: (map['campaignName'] ?? map['campaign_name'] ?? '').toString(),
      dateStr: (map['dateStr'] ?? map['date_str'] ?? '').toString(),
      date: parsedDate,
      branchName: (map['branchName'] ?? map['branch_name'] ?? '').toString(),
      branchId: (map['branchId'] ?? map['branch_id'] ?? '').toString(),
      retailChain: (map['retailChain'] ?? map['retail_chain'] ?? '').toString(),
      invoicesCount: (map['invoicesCount'] ?? map['invoices_count'] as num?)?.toInt() ?? 0,
      totalSalesAmount: (map['totalSalesAmount'] ?? map['total_sales_amount'] ?? map['total_sales'] as num?)?.toDouble() ?? 0.0,
      totalGiftsCount: (map['totalGiftsCount'] ?? map['total_gifts_count'] ?? map['total_gifts'] as num?)?.toInt() ?? 0,
      totalVouchersValue: (map['totalVouchersValue'] ?? map['total_vouchers_value'] ?? map['total_vouchers'] as num?)?.toDouble() ?? 0.0,
      giftsDisbursed: parsedGifts,
      topProducts: parsedTopProducts,
      lastUpdatedAt: parsedUpdated,
    );
  }

  Map<String, dynamic> toFirestore() {
    final giftsMap = <String, dynamic>{};
    giftsDisbursed.forEach((k, v) {
      giftsMap[k] = v.toMap();
    });

    return {
      'id': id,
      'companySlug': companySlug,
      'campaignId': campaignId,
      'campaignName': campaignName,
      'dateStr': dateStr,
      'date': Timestamp.fromDate(date),
      'branchName': branchName,
      'branchId': branchId,
      'retailChain': retailChain,
      'invoicesCount': invoicesCount,
      'totalSalesAmount': totalSalesAmount,
      'totalGiftsCount': totalGiftsCount,
      'totalVouchersValue': totalVouchersValue,
      'giftsDisbursed': giftsMap,
      'topProducts': topProducts.map((p) => p.toMap()).toList(),
      'lastUpdatedAt': Timestamp.fromDate(lastUpdatedAt),
    };
  }

  DailyBranchSalesModel copyWith({
    String? id,
    String? companySlug,
    String? campaignId,
    String? campaignName,
    String? dateStr,
    DateTime? date,
    String? branchName,
    String? branchId,
    String? retailChain,
    int? invoicesCount,
    double? totalSalesAmount,
    int? totalGiftsCount,
    double? totalVouchersValue,
    Map<String, DailyGiftDisbursalItem>? giftsDisbursed,
    List<DailyTopProductItem>? topProducts,
    DateTime? lastUpdatedAt,
  }) {
    return DailyBranchSalesModel(
      id: id ?? this.id,
      companySlug: companySlug ?? this.companySlug,
      campaignId: campaignId ?? this.campaignId,
      campaignName: campaignName ?? this.campaignName,
      dateStr: dateStr ?? this.dateStr,
      date: date ?? this.date,
      branchName: branchName ?? this.branchName,
      branchId: branchId ?? this.branchId,
      retailChain: retailChain ?? this.retailChain,
      invoicesCount: invoicesCount ?? this.invoicesCount,
      totalSalesAmount: totalSalesAmount ?? this.totalSalesAmount,
      totalGiftsCount: totalGiftsCount ?? this.totalGiftsCount,
      totalVouchersValue: totalVouchersValue ?? this.totalVouchersValue,
      giftsDisbursed: giftsDisbursed ?? this.giftsDisbursed,
      topProducts: topProducts ?? this.topProducts,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    );
  }
}
