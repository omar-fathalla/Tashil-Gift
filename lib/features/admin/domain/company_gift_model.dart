import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single incoming supply batch for a gift/voucher (إذن توريد / دفعة استلام).
class GiftSupplyBatch {
  final String id;
  final int batchNumber;
  final int quantity;
  final DateTime supplyDate;
  final String referenceNumber; // e.g. PO number, Delivery note, Invoice reference
  final String notes;
  final String addedBy;

  GiftSupplyBatch({
    required this.id,
    required this.batchNumber,
    required this.quantity,
    required this.supplyDate,
    this.referenceNumber = '',
    this.notes = '',
    this.addedBy = '',
  });

  GiftSupplyBatch copyWith({
    String? id,
    int? batchNumber,
    int? quantity,
    DateTime? supplyDate,
    String? referenceNumber,
    String? notes,
    String? addedBy,
  }) {
    return GiftSupplyBatch(
      id: id ?? this.id,
      batchNumber: batchNumber ?? this.batchNumber,
      quantity: quantity ?? this.quantity,
      supplyDate: supplyDate ?? this.supplyDate,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      notes: notes ?? this.notes,
      addedBy: addedBy ?? this.addedBy,
    );
  }

  factory GiftSupplyBatch.fromMap(Map<String, dynamic> map, {int fallbackIndex = 1}) {
    DateTime parsedDate;
    final rawDate = map['supplyDate'] ?? map['date'] ?? map['createdAt'];
    if (rawDate is Timestamp) {
      parsedDate = rawDate.toDate();
    } else if (rawDate is String) {
      parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return GiftSupplyBatch(
      id: (map['id'] ?? 'batch_$fallbackIndex').toString(),
      batchNumber: (map['batchNumber'] as num?)?.toInt() ?? fallbackIndex,
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      supplyDate: parsedDate,
      referenceNumber: (map['referenceNumber'] ?? map['refNumber'] ?? map['poNumber'] ?? '').toString(),
      notes: (map['notes'] ?? '').toString(),
      addedBy: (map['addedBy'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'batchNumber': batchNumber,
      'quantity': quantity,
      'supplyDate': Timestamp.fromDate(supplyDate),
      'referenceNumber': referenceNumber,
      'notes': notes,
      'addedBy': addedBy,
    };
  }
}

/// Represents a chronological stock movement log (حركة مخزون / سجل تدقيق) for full auditability.
class GiftStockMovement {
  final String id;
  final String companySlug;
  final String giftId;
  final String giftName;
  final String movementType; // 'supply_batch' | 'adjustment_add' | 'adjustment_deduct' | 'campaign_allocation' | 'campaign_return' | 'receipt_claim'
  final int quantityChange; // +100, -10, etc.
  final int previousTotal;
  final int newTotal;
  final int previousAvailable;
  final int newAvailable;
  final String reference; // Campaign name, Branch name, PO number, Receipt number
  final String notes;
  final String performedBy;
  final DateTime timestamp;

  GiftStockMovement({
    required this.id,
    required this.companySlug,
    required this.giftId,
    required this.giftName,
    required this.movementType,
    required this.quantityChange,
    required this.previousTotal,
    required this.newTotal,
    required this.previousAvailable,
    required this.newAvailable,
    this.reference = '',
    this.notes = '',
    this.performedBy = '',
    required this.timestamp,
  });

  bool get isAddition =>
      movementType == 'supply_batch' ||
      movementType == 'adjustment_add' ||
      movementType == 'campaign_return' ||
      quantityChange > 0;

  bool get isDeduction => !isAddition;

  String get typeLabelAr {
    switch (movementType) {
      case 'supply_batch':
        return 'توريد دفعة جديدة';
      case 'adjustment_add':
        return 'تسوية جردية بالزيادة';
      case 'adjustment_deduct':
        return 'تسوية جردية بالنقص / هالك';
      case 'campaign_allocation':
        return 'تخصيص لحملة وفروع';
      case 'campaign_return':
        return 'استرجاع متبقي من حملة';
      case 'receipt_claim':
        return 'صرف هدية بفاتورة معتمدة';
      default:
        return isAddition ? 'إضافة رصيد' : 'خصم رصيد';
    }
  }

  String get typeLabelEn {
    switch (movementType) {
      case 'supply_batch':
        return 'Supply Batch Inward';
      case 'adjustment_add':
        return 'Stock Adjustment (+ Add)';
      case 'adjustment_deduct':
        return 'Stock Adjustment (- Deduct)';
      case 'campaign_allocation':
        return 'Campaign Allocation';
      case 'campaign_return':
        return 'Campaign Stock Return';
      case 'receipt_claim':
        return 'Customer Claim Handover';
      default:
        return isAddition ? 'Stock Inward' : 'Stock Outward';
    }
  }

  factory GiftStockMovement.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    DateTime parsedTime = DateTime.now();
    final rawTs = data['timestamp'] ?? data['createdAt'];
    if (rawTs is Timestamp) {
      parsedTime = rawTs.toDate();
    } else if (rawTs is String) {
      parsedTime = DateTime.tryParse(rawTs) ?? DateTime.now();
    }

    return GiftStockMovement(
      id: doc.id,
      companySlug: (data['companySlug'] ?? '').toString().toLowerCase().trim(),
      giftId: (data['giftId'] ?? '').toString(),
      giftName: (data['giftName'] ?? data['name'] ?? '').toString(),
      movementType: (data['movementType'] ?? 'supply_batch').toString(),
      quantityChange: (data['quantityChange'] as num?)?.toInt() ?? (data['quantity'] as num?)?.toInt() ?? 0,
      previousTotal: (data['previousTotal'] as num?)?.toInt() ?? 0,
      newTotal: (data['newTotal'] as num?)?.toInt() ?? 0,
      previousAvailable: (data['previousAvailable'] as num?)?.toInt() ?? 0,
      newAvailable: (data['newAvailable'] as num?)?.toInt() ?? 0,
      reference: (data['reference'] ?? data['referenceNumber'] ?? data['campaignName'] ?? '').toString(),
      notes: (data['notes'] ?? data['reason'] ?? '').toString(),
      performedBy: (data['performedBy'] ?? data['userName'] ?? '').toString(),
      timestamp: parsedTime,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'companySlug': companySlug.toLowerCase().trim(),
      'giftId': giftId,
      'giftName': giftName,
      'movementType': movementType,
      'quantityChange': quantityChange,
      'previousTotal': previousTotal,
      'newTotal': newTotal,
      'previousAvailable': previousAvailable,
      'newAvailable': newAvailable,
      'reference': reference,
      'notes': notes,
      'performedBy': performedBy,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}

/// Represents a gift/prize in a company's master inventory with multi-batch tracking.
class CompanyGiftModel {
  final String id;
  final String companySlug;
  final String companyName;
  final String giftName;
  final int totalQuantity;
  final int availableQuantity;
  final int allocatedInOtherCampaigns;
  final String giftType; // 'product' | 'voucher'
  final double unitValue; // Denomination / face value per card for vouchers (e.g. 25.0, 50.0, 100.0)
  final int orderIndex; // Index for drag & drop custom sorting
  final List<GiftSupplyBatch> batches;
  final int lowStockThreshold;
  final String? imageUrl;
  final DateTime? createdAt;

  CompanyGiftModel({
    required this.id,
    required this.companySlug,
    this.companyName = '',
    required this.giftName,
    required this.totalQuantity,
    required this.availableQuantity,
    this.allocatedInOtherCampaigns = 0,
    this.giftType = 'product',
    this.unitValue = 0.0,
    this.orderIndex = 0,
    this.batches = const [],
    this.lowStockThreshold = 0,
    this.imageUrl,
    this.createdAt,
  });

  bool get isVoucher {
    if (giftType == 'voucher') return true;
    if (giftType == 'product') return false;
    final clean = giftName.toLowerCase();
    return unitValue > 0 &&
        (clean.contains('فواتشر') ||
            clean.contains('فوتشر') ||
            clean.contains('قسيمة') ||
            clean.contains('قسائم') ||
            clean.contains('كارت مشتريات') ||
            clean.contains('كوبون') ||
            clean.contains('voucher') ||
            clean.contains('coupon'));
  }

  /// Total monetary value of all cards in inventory (e.g. 200 cards * 50 EGP = 10,000 EGP)
  double get totalMonetaryValue => isVoucher ? (totalQuantity * unitValue) : 0.0;

  /// Available monetary value of remaining cards
  double get availableMonetaryValue => isVoucher ? (availableQuantity * unitValue) : 0.0;

  String get formattedUnitValue => isVoucher
      ? (unitValue == unitValue.roundToDouble() ? '${unitValue.toInt()} ج.م' : '$unitValue ج.م')
      : '';

  int get batchCount => batches.isNotEmpty ? batches.length : (totalQuantity > 0 ? 1 : 0);

  bool get isLowStock {
    if (totalQuantity <= 0) return false;
    final threshold = lowStockThreshold > 0 ? lowStockThreshold : (totalQuantity * 0.15).ceil();
    return availableQuantity <= threshold;
  }

  CompanyGiftModel copyWith({
    String? id,
    String? companySlug,
    String? companyName,
    String? giftName,
    int? totalQuantity,
    int? availableQuantity,
    int? allocatedInOtherCampaigns,
    String? giftType,
    double? unitValue,
    int? orderIndex,
    List<GiftSupplyBatch>? batches,
    int? lowStockThreshold,
    String? imageUrl,
    DateTime? createdAt,
  }) {
    return CompanyGiftModel(
      id: id ?? this.id,
      companySlug: companySlug ?? this.companySlug,
      companyName: companyName ?? this.companyName,
      giftName: giftName ?? this.giftName,
      totalQuantity: totalQuantity ?? this.totalQuantity,
      availableQuantity: availableQuantity ?? this.availableQuantity,
      allocatedInOtherCampaigns: allocatedInOtherCampaigns ?? this.allocatedInOtherCampaigns,
      giftType: giftType ?? this.giftType,
      unitValue: unitValue ?? this.unitValue,
      orderIndex: orderIndex ?? this.orderIndex,
      batches: batches ?? this.batches,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory CompanyGiftModel.fromMap(Map<String, dynamic> data, String id) {
    final rawName = ((data['giftName'] as String?)?.isNotEmpty == true
            ? data['giftName']
            : (data['name'] ?? ''))
        .toString()
        .trim();
    final cleanName = rawName.toLowerCase();
    final isExplicitVoucherName = cleanName.contains('فواتشر') ||
        cleanName.contains('فوتشر') ||
        cleanName.contains('قسيمة') ||
        cleanName.contains('قسائم') ||
        cleanName.contains('كارت مشتريات') ||
        cleanName.contains('كوبون') ||
        cleanName.contains('voucher') ||
        cleanName.contains('coupon');

    final declaredType = data['giftType'] as String?;
    final rawType = declaredType != null && declaredType.isNotEmpty
        ? declaredType
        : (isExplicitVoucherName ? 'voucher' : 'product');

    final rawUnitVal = (rawType == 'voucher' || isExplicitVoucherName)
        ? ((data['unitValue'] as num?)?.toDouble() ?? 0.0)
        : 0.0;
    final rawOrder = (data['orderIndex'] as num?)?.toInt() ?? (data['order'] as num?)?.toInt() ?? 0;
    final totalQty = (data['totalQuantity'] as num?)?.toInt() ?? 0;
    final availQty = (data['availableQuantity'] as num?)?.toInt() ?? 0;
    final lowThresh = (data['lowStockThreshold'] as num?)?.toInt() ?? 0;
    final rawImageUrl = (data['imageUrl'] as String?)?.trim();
    final effectiveImageUrl = rawImageUrl != null && rawImageUrl.isNotEmpty ? rawImageUrl : null;
    
    DateTime? createdDate;
    final rawCreated = data['createdAt'];
    if (rawCreated is Timestamp) {
      createdDate = rawCreated.toDate();
    } else if (rawCreated is String) {
      createdDate = DateTime.tryParse(rawCreated);
    } else if (rawCreated is DateTime) {
      createdDate = rawCreated;
    }

    final rawBatches = (data['batches'] as List<dynamic>?) ?? [];
    List<GiftSupplyBatch> parsedBatches = [];
    if (rawBatches.isNotEmpty) {
      for (int i = 0; i < rawBatches.length; i++) {
        if (rawBatches[i] is Map<String, dynamic>) {
          parsedBatches.add(GiftSupplyBatch.fromMap(rawBatches[i] as Map<String, dynamic>, fallbackIndex: i + 1));
        } else if (rawBatches[i] is Map) {
          parsedBatches.add(GiftSupplyBatch.fromMap(Map<String, dynamic>.from(rawBatches[i] as Map), fallbackIndex: i + 1));
        }
      }
    } else if (totalQty > 0) {
      // Create a virtual initial batch for backwards compatibility
      parsedBatches.add(
        GiftSupplyBatch(
          id: 'initial_batch_$id',
          batchNumber: 1,
          quantity: totalQty,
          supplyDate: createdDate ?? DateTime.now(),
          referenceNumber: (data['initialReference'] ?? 'الرصيد الافتتاحي').toString(),
          notes: 'دفعة التوريد الافتتاحية الأولى',
          addedBy: 'النظام',
        ),
      );
    }

    return CompanyGiftModel(
      id: id,
      companySlug: data['companySlug'] ?? '',
      companyName: data['companyName'] ?? '',
      giftName: rawName,
      totalQuantity: totalQty,
      availableQuantity: availQty,
      allocatedInOtherCampaigns: (data['allocatedInOtherCampaigns'] as num?)?.toInt() ?? 0,
      giftType: rawType,
      unitValue: rawUnitVal,
      orderIndex: rawOrder,
      batches: parsedBatches,
      lowStockThreshold: lowThresh,
      imageUrl: effectiveImageUrl,
      createdAt: createdDate,
    );
  }

  factory CompanyGiftModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return CompanyGiftModel.fromMap(data, doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'companySlug': companySlug.toLowerCase().trim(),
      'companyName': companyName,
      'giftName': giftName,
      'totalQuantity': totalQuantity,
      'availableQuantity': availableQuantity,
      'allocatedInOtherCampaigns': allocatedInOtherCampaigns,
      'giftType': giftType,
      'unitValue': unitValue,
      'orderIndex': orderIndex,
      'batches': batches.map((b) => b.toMap()).toList(),
      'lowStockThreshold': lowStockThreshold,
      if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      ...toMap(),
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }
}
