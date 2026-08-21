import 'package:flutter/foundation.dart';

/// Single historical price observation extracted from a scanned receipt
@immutable
class ProductPriceHistoryEntry {
  final double price; // The single unit selling price (net unit price if discounted)
  final double? originalPrice; // Gross unit price before discount if promo was active
  final double discountAmount; // Discount amount per single unit
  final double discountPercent; // Discount percentage if applicable
  final String receiptDate; // Date string printed on receipt (e.g. "21/08/2026")
  final DateTime? timestamp; // Firestore server timestamp or parsed date
  final String receiptNumber; // Receipt / Transaction ID
  final String storeChain; // Normalized Enterprise Store chain (e.g. "أسواق فتح الله", "جملة ماركت")
  final String branchName; // Branch name or code (e.g. "فرع سموحة", "فرع عجمي ستار")
  final String receiptImageUrl; // Scanned receipt image for audit
  final String companySlug; // Target company (e.g. "unilever")
  final int quantity; // Quantity in that transaction

  const ProductPriceHistoryEntry({
    required this.price,
    this.originalPrice,
    this.discountAmount = 0.0,
    this.discountPercent = 0.0,
    required this.receiptDate,
    this.timestamp,
    required this.receiptNumber,
    required this.storeChain,
    this.branchName = '',
    this.receiptImageUrl = '',
    this.companySlug = '',
    this.quantity = 1,
  });

  bool get hasDiscount => discountAmount > 0 || discountPercent > 0 || (originalPrice != null && originalPrice! > price);

  double get effectiveOriginalPrice => originalPrice ?? (discountAmount > 0 ? price + discountAmount : price);

  double get calculatedDiscountPercent {
    if (discountPercent > 0) return discountPercent;
    if (effectiveOriginalPrice > price && effectiveOriginalPrice > 0) {
      return ((effectiveOriginalPrice - price) / effectiveOriginalPrice) * 100;
    }
    return 0.0;
  }

  factory ProductPriceHistoryEntry.fromJson(Map<String, dynamic> json) {
    return ProductPriceHistoryEntry(
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      originalPrice: (json['originalPrice'] as num?)?.toDouble(),
      discountAmount: (json['discountAmount'] as num?)?.toDouble() ?? 0.0,
      discountPercent: (json['discountPercent'] as num?)?.toDouble() ?? 0.0,
      receiptDate: json['receiptDate']?.toString() ?? '',
      timestamp: json['timestamp'] != null
          ? (json['timestamp'] is DateTime
              ? json['timestamp'] as DateTime
              : DateTime.tryParse(json['timestamp'].toString()))
          : null,
      receiptNumber: json['receiptNumber']?.toString() ?? '',
      storeChain: json['storeChain']?.toString() ?? '',
      branchName: json['branchName']?.toString() ?? '',
      receiptImageUrl: json['receiptImageUrl']?.toString() ?? '',
      companySlug: json['companySlug']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'price': price,
      if (originalPrice != null) 'originalPrice': originalPrice,
      'discountAmount': discountAmount,
      'discountPercent': discountPercent,
      'receiptDate': receiptDate,
      if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
      'receiptNumber': receiptNumber,
      'storeChain': storeChain,
      'branchName': branchName,
      'receiptImageUrl': receiptImageUrl,
      'companySlug': companySlug,
      'quantity': quantity,
    };
  }
}

/// Consolidated pricing summary for a single enterprise retail chain (Enterprise Level)
@immutable
class ChainPricingSummary {
  final String chainName; // e.g. "أسواق فتح الله"
  final double regularUnitPrice; // e.g. 115.0
  final double netUnitPrice; // e.g. 99.0 (after discount)
  final double unitDiscount; // e.g. 16.0
  final double discountPercent; // e.g. 13.9%
  final bool isOnPromotion; // true if discount > 0
  final String lastReceiptDate; // "21/08/2026"
  final int totalScans; // e.g. 100
  final int totalQuantity; // e.g. 172
  final List<String> branchesObserved; // e.g. ["سموحة", "عجمي ستار"]

  const ChainPricingSummary({
    required this.chainName,
    required this.regularUnitPrice,
    required this.netUnitPrice,
    this.unitDiscount = 0.0,
    this.discountPercent = 0.0,
    this.isOnPromotion = false,
    this.lastReceiptDate = '',
    this.totalScans = 0,
    this.totalQuantity = 0,
    this.branchesObserved = const [],
  });

  factory ChainPricingSummary.fromJson(Map<String, dynamic> json) {
    return ChainPricingSummary(
      chainName: json['chainName']?.toString() ?? '',
      regularUnitPrice: (json['regularUnitPrice'] as num?)?.toDouble() ?? 0.0,
      netUnitPrice: (json['netUnitPrice'] as num?)?.toDouble() ?? 0.0,
      unitDiscount: (json['unitDiscount'] as num?)?.toDouble() ?? 0.0,
      discountPercent: (json['discountPercent'] as num?)?.toDouble() ?? 0.0,
      isOnPromotion: json['isOnPromotion'] == true,
      lastReceiptDate: json['lastReceiptDate']?.toString() ?? '',
      totalScans: (json['totalScans'] as num?)?.toInt() ?? 0,
      totalQuantity: (json['totalQuantity'] as num?)?.toInt() ?? 0,
      branchesObserved: (json['branchesObserved'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chainName': chainName,
      'regularUnitPrice': regularUnitPrice,
      'netUnitPrice': netUnitPrice,
      'unitDiscount': unitDiscount,
      'discountPercent': discountPercent,
      'isOnPromotion': isOnPromotion,
      'lastReceiptDate': lastReceiptDate,
      'totalScans': totalScans,
      'totalQuantity': totalQuantity,
      'branchesObserved': branchesObserved,
    };
  }
}

/// Aggregated Product with cross-chain price tracking and historical timeline
@immutable
class ChainProductItem {
  final String id; // Unique SKU ID (e.g. barcode or normalized name)
  final String name; // Standard Product Name
  final String barcode; // Barcode / SKU
  final String companySlug; // Company (e.g. "unilever")
  final String category; // Category (e.g. "مزيلات عرق", "العناية بالشعر")
  final String brand; // Brand (e.g. "Axe", "Rexona", "Dove", "Clear")
  final Map<String, double> latestPricesByChain; // Latest Net Unit Price in each enterprise chain
  final Map<String, double> latestRegularPricesByChain; // Latest Regular Unit Price before discount
  final Map<String, String> latestDatesByChain; // Latest receipt date in each chain
  final Map<String, ChainPricingSummary> chainSummaries; // Structured Enterprise Chain Summaries
  final Map<String, ProductPriceHistoryEntry> latestEntryByChain; // Latest full entry per chain
  final List<ProductPriceHistoryEntry> priceHistory; // Full history sorted newest to oldest
  final int totalScansCount; // Total times scanned in receipts
  final int totalQuantitySold; // Total quantity across receipts
  final bool isBarcodeAutoLinked; // True if barcode was resolved/linked across other invoices

  const ChainProductItem({
    required this.id,
    required this.name,
    this.barcode = '',
    this.companySlug = '',
    this.category = '',
    this.brand = '',
    this.latestPricesByChain = const {},
    this.latestRegularPricesByChain = const {},
    this.latestDatesByChain = const {},
    this.chainSummaries = const {},
    this.latestEntryByChain = const {},
    this.priceHistory = const [],
    this.totalScansCount = 0,
    this.totalQuantitySold = 0,
    this.isBarcodeAutoLinked = false,
  });

  /// Most recent price recorded overall
  double get latestOverallPrice {
    if (priceHistory.isNotEmpty) {
      return priceHistory.first.price;
    }
    if (latestPricesByChain.isNotEmpty) {
      return latestPricesByChain.values.first;
    }
    return 0.0;
  }

  /// Most recent observation date
  String get latestOverallDate {
    if (priceHistory.isNotEmpty) {
      return priceHistory.first.receiptDate;
    }
    if (latestDatesByChain.isNotEmpty) {
      return latestDatesByChain.values.first;
    }
    return '';
  }

  /// Lowest unit price among all enterprise chains where product was observed
  double get minPrice {
    if (latestPricesByChain.isEmpty) return latestOverallPrice;
    return latestPricesByChain.values.reduce((a, b) => a < b ? a : b);
  }

  /// Enterprise Chain offering the lowest unit price
  String get cheapestChain {
    if (latestPricesByChain.isEmpty) return '';
    final min = minPrice;
    for (final entry in latestPricesByChain.entries) {
      if (entry.value == min) return entry.key;
    }
    return '';
  }

  /// Highest unit price among all enterprise chains
  double get maxPrice {
    if (latestPricesByChain.isEmpty) return latestOverallPrice;
    return latestPricesByChain.values.reduce((a, b) => a > b ? a : b);
  }

  /// Enterprise Chain offering the highest unit price
  String get mostExpensiveChain {
    if (latestPricesByChain.isEmpty) return '';
    final max = maxPrice;
    for (final entry in latestPricesByChain.entries) {
      if (entry.value == max) return entry.key;
    }
    return '';
  }

  /// Price variance percentage between highest and lowest chain
  double get priceVariancePercent {
    if (minPrice <= 0 || maxPrice <= minPrice) return 0.0;
    return ((maxPrice - minPrice) / minPrice) * 100;
  }

  /// Whether there has been a price change recorded over time in any chain
  bool get hasPriceFluctuation {
    if (priceHistory.length < 2) return false;
    final firstPrice = priceHistory.last.price;
    return priceHistory.any((e) => e.price != firstPrice);
  }

  /// Latest active discount observed
  double get maxObservedDiscountPercent {
    double maxDiscount = 0.0;
    for (final e in priceHistory) {
      final d = e.calculatedDiscountPercent;
      if (d > maxDiscount) maxDiscount = d;
    }
    return maxDiscount;
  }

  /// Checks whether a promo/discount was active in the most recent scan
  bool get isCurrentlyOnPromotion {
    if (priceHistory.isEmpty) return false;
    return priceHistory.first.hasDiscount;
  }

  /// Returns distinct price change events grouped chronologically per chain
  List<ProductPriceHistoryEntry> get distinctPriceChangeEvents {
    final List<ProductPriceHistoryEntry> result = [];
    final Map<String, double> lastSeenPriceByChain = {};

    for (final entry in priceHistory) {
      final chain = entry.storeChain;
      final price = entry.price;
      if (!lastSeenPriceByChain.containsKey(chain) || lastSeenPriceByChain[chain] != price) {
        result.add(entry);
        lastSeenPriceByChain[chain] = price;
      }
    }
    return result;
  }

  factory ChainProductItem.fromJson(Map<String, dynamic> json) {
    final rawHistory = json['priceHistory'] as List<dynamic>? ?? [];
    final List<ProductPriceHistoryEntry> history = rawHistory
        .map((e) => ProductPriceHistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    final Map<String, double> prices = {};
    if (json['latestPricesByChain'] is Map) {
      (json['latestPricesByChain'] as Map).forEach((k, v) {
        if (v is num) prices[k.toString()] = v.toDouble();
      });
    }

    final Map<String, double> regPrices = {};
    if (json['latestRegularPricesByChain'] is Map) {
      (json['latestRegularPricesByChain'] as Map).forEach((k, v) {
        if (v is num) regPrices[k.toString()] = v.toDouble();
      });
    }

    final Map<String, String> dates = {};
    if (json['latestDatesByChain'] is Map) {
      (json['latestDatesByChain'] as Map).forEach((k, v) {
        dates[k.toString()] = v?.toString() ?? '';
      });
    }

    final Map<String, ChainPricingSummary> summaries = {};
    if (json['chainSummaries'] is Map) {
      (json['chainSummaries'] as Map).forEach((k, v) {
        if (v is Map) summaries[k.toString()] = ChainPricingSummary.fromJson(Map<String, dynamic>.from(v));
      });
    }

    return ChainProductItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      barcode: json['barcode']?.toString() ?? '',
      companySlug: json['companySlug']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      brand: json['brand']?.toString() ?? '',
      latestPricesByChain: prices,
      latestRegularPricesByChain: regPrices,
      latestDatesByChain: dates,
      chainSummaries: summaries,
      priceHistory: history,
      totalScansCount: (json['totalScansCount'] as num?)?.toInt() ?? history.length,
      totalQuantitySold: (json['totalQuantitySold'] as num?)?.toInt() ?? 0,
      isBarcodeAutoLinked: json['isBarcodeAutoLinked'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'barcode': barcode,
      'companySlug': companySlug,
      'category': category,
      'brand': brand,
      'latestPricesByChain': latestPricesByChain,
      'latestRegularPricesByChain': latestRegularPricesByChain,
      'latestDatesByChain': latestDatesByChain,
      'chainSummaries': chainSummaries.map((k, v) => MapEntry(k, v.toJson())),
      'priceHistory': priceHistory.map((e) => e.toJson()).toList(),
      'totalScansCount': totalScansCount,
      'totalQuantitySold': totalQuantitySold,
      'isBarcodeAutoLinked': isBarcodeAutoLinked,
      'minPrice': minPrice,
      'maxPrice': maxPrice,
      'cheapestChain': cheapestChain,
      'mostExpensiveChain': mostExpensiveChain,
      'priceVariancePercent': priceVariancePercent,
      'isCurrentlyOnPromotion': isCurrentlyOnPromotion,
    };
  }

  ChainProductItem copyWith({
    String? id,
    String? name,
    String? barcode,
    String? companySlug,
    String? category,
    String? brand,
    Map<String, double>? latestPricesByChain,
    Map<String, double>? latestRegularPricesByChain,
    Map<String, String>? latestDatesByChain,
    Map<String, ChainPricingSummary>? chainSummaries,
    Map<String, ProductPriceHistoryEntry>? latestEntryByChain,
    List<ProductPriceHistoryEntry>? priceHistory,
    int? totalScansCount,
    int? totalQuantitySold,
    bool? isBarcodeAutoLinked,
  }) {
    return ChainProductItem(
      id: id ?? this.id,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      companySlug: companySlug ?? this.companySlug,
      category: category ?? this.category,
      brand: brand ?? this.brand,
      latestPricesByChain: latestPricesByChain ?? this.latestPricesByChain,
      latestRegularPricesByChain: latestRegularPricesByChain ?? this.latestRegularPricesByChain,
      latestDatesByChain: latestDatesByChain ?? this.latestDatesByChain,
      chainSummaries: chainSummaries ?? this.chainSummaries,
      latestEntryByChain: latestEntryByChain ?? this.latestEntryByChain,
      priceHistory: priceHistory ?? this.priceHistory,
      totalScansCount: totalScansCount ?? this.totalScansCount,
      totalQuantitySold: totalQuantitySold ?? this.totalQuantitySold,
      isBarcodeAutoLinked: isBarcodeAutoLinked ?? this.isBarcodeAutoLinked,
    );
  }
}
