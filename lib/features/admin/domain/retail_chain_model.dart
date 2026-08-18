import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a POS Receipt Signature & Template extracted via AI from a sample receipt (البصمة الهيكلية لبونة الفرع)
class BranchReceiptSignature {
  final String storeId;
  final String posNumberPattern;
  final String receiptPattern;
  final List<String> headerKeywords;
  final List<String> footerKeywords;
  final String taxNumber;
  final String commercialReg;
  final String hotline;
  final String sampleReceiptUrl;
  final String extractedSummary;
  final double confidenceScore;
  final DateTime? scannedAt;

  BranchReceiptSignature({
    this.storeId = '',
    this.posNumberPattern = '',
    this.receiptPattern = '',
    this.headerKeywords = const [],
    this.footerKeywords = const [],
    this.taxNumber = '',
    this.commercialReg = '',
    this.hotline = '',
    this.sampleReceiptUrl = '',
    this.extractedSummary = '',
    this.confidenceScore = 1.0,
    this.scannedAt,
  });

  bool get hasSignature =>
      storeId.isNotEmpty || receiptPattern.isNotEmpty || headerKeywords.isNotEmpty;

  factory BranchReceiptSignature.fromMap(Map<String, dynamic> data) {
    return BranchReceiptSignature(
      storeId: (data['storeId'] ?? '').toString().trim(),
      posNumberPattern: (data['posNumberPattern'] ?? '').toString().trim(),
      receiptPattern: (data['receiptPattern'] ?? '').toString().trim(),
      headerKeywords: (data['headerKeywords'] as List<dynamic>?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
      footerKeywords: (data['footerKeywords'] as List<dynamic>?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
      taxNumber: (data['taxNumber'] ?? '').toString().trim(),
      commercialReg: (data['commercialReg'] ?? '').toString().trim(),
      hotline: (data['hotline'] ?? '').toString().trim(),
      sampleReceiptUrl: (data['sampleReceiptUrl'] ?? '').toString().trim(),
      extractedSummary: (data['extractedSummary'] ?? '').toString().trim(),
      confidenceScore: (data['confidenceScore'] as num?)?.toDouble() ?? 1.0,
      scannedAt: data['scannedAt'] is Timestamp
          ? (data['scannedAt'] as Timestamp).toDate()
          : (data['scannedAt'] is DateTime ? data['scannedAt'] as DateTime : null),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'storeId': storeId.trim(),
      'posNumberPattern': posNumberPattern.trim(),
      'receiptPattern': receiptPattern.trim(),
      'headerKeywords': headerKeywords,
      'footerKeywords': footerKeywords,
      'taxNumber': taxNumber.trim(),
      'commercialReg': commercialReg.trim(),
      'hotline': hotline.trim(),
      'sampleReceiptUrl': sampleReceiptUrl.trim(),
      'extractedSummary': extractedSummary.trim(),
      'confidenceScore': confidenceScore,
      'scannedAt': scannedAt != null
          ? Timestamp.fromDate(scannedAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  BranchReceiptSignature copyWith({
    String? storeId,
    String? posNumberPattern,
    String? receiptPattern,
    List<String>? headerKeywords,
    List<String>? footerKeywords,
    String? taxNumber,
    String? commercialReg,
    String? hotline,
    String? sampleReceiptUrl,
    String? extractedSummary,
    double? confidenceScore,
    DateTime? scannedAt,
  }) {
    return BranchReceiptSignature(
      storeId: storeId ?? this.storeId,
      posNumberPattern: posNumberPattern ?? this.posNumberPattern,
      receiptPattern: receiptPattern ?? this.receiptPattern,
      headerKeywords: headerKeywords ?? this.headerKeywords,
      footerKeywords: footerKeywords ?? this.footerKeywords,
      taxNumber: taxNumber ?? this.taxNumber,
      commercialReg: commercialReg ?? this.commercialReg,
      hotline: hotline ?? this.hotline,
      sampleReceiptUrl: sampleReceiptUrl ?? this.sampleReceiptUrl,
      extractedSummary: extractedSummary ?? this.extractedSummary,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      scannedAt: scannedAt ?? this.scannedAt,
    );
  }
}

/// Represents a Retail Chain / Hypermarket Organization (e.g. أسواق فتح الله, كارفور, سبينس, سعودي, هايبر وان, بيت الجملة, لولو)
class RetailChainModel {
  final String id;
  final String name;
  final String slug;
  final int branchesCount;
  final DateTime? createdAt;

  RetailChainModel({
    required this.id,
    required this.name,
    required this.slug,
    this.branchesCount = 0,
    this.createdAt,
  });

  factory RetailChainModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return RetailChainModel(
      id: doc.id,
      name: data['name'] ?? '',
      slug: (data['slug'] ?? '').toString().toLowerCase().trim(),
      branchesCount: (data['branchesCount'] as num?)?.toInt() ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  factory RetailChainModel.fromMap(Map<String, dynamic> data, String docId) {
    return RetailChainModel(
      id: docId,
      name: data['name'] ?? '',
      slug: (data['slug'] ?? '').toString().toLowerCase().trim(),
      branchesCount: (data['branchesCount'] as num?)?.toInt() ?? 0,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : (data['createdAt'] is DateTime ? data['createdAt'] as DateTime : null),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name.trim(),
      'slug': slug.toLowerCase().trim(),
      'branchesCount': branchesCount,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  RetailChainModel copyWith({
    String? id,
    String? name,
    String? slug,
    int? branchesCount,
    DateTime? createdAt,
  }) {
    return RetailChainModel(
      id: id ?? this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      branchesCount: branchesCount ?? this.branchesCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Represents a Branch / POS Outlet belonging to a Retail Chain (e.g. فرع سموحة, فرع الهانوفيل, فرع عجمي ستار)
class BranchModel {
  final String id;
  final String retailChainId;
  final String retailChainName;
  final String branchName;
  final String city;
  final String branchCode;
  final String address;
  final BranchReceiptSignature? receiptSignature;
  final DateTime? createdAt;

  BranchModel({
    required this.id,
    required this.retailChainId,
    required this.retailChainName,
    required this.branchName,
    this.city = '',
    this.branchCode = '',
    this.address = '',
    this.receiptSignature,
    this.createdAt,
  });

  factory BranchModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return BranchModel(
      id: doc.id,
      retailChainId: data['retailChainId'] ?? '',
      retailChainName: data['retailChainName'] ?? '',
      branchName: data['branchName'] ?? '',
      city: data['city'] ?? '',
      branchCode: (data['branchCode'] ?? '').toString().trim(),
      address: data['address'] ?? '',
      receiptSignature: data['receiptSignature'] != null && data['receiptSignature'] is Map<String, dynamic>
          ? BranchReceiptSignature.fromMap(data['receiptSignature'] as Map<String, dynamic>)
          : null,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  factory BranchModel.fromMap(Map<String, dynamic> data, String docId) {
    return BranchModel(
      id: docId,
      retailChainId: data['retailChainId'] ?? '',
      retailChainName: data['retailChainName'] ?? '',
      branchName: data['branchName'] ?? '',
      city: data['city'] ?? '',
      branchCode: (data['branchCode'] ?? '').toString().trim(),
      address: data['address'] ?? '',
      receiptSignature: data['receiptSignature'] != null && data['receiptSignature'] is Map<String, dynamic>
          ? BranchReceiptSignature.fromMap(data['receiptSignature'] as Map<String, dynamic>)
          : null,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : (data['createdAt'] is DateTime ? data['createdAt'] as DateTime : null),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'retailChainId': retailChainId,
      'retailChainName': retailChainName.trim(),
      'branchName': branchName.trim(),
      'city': city.trim(),
      'branchCode': branchCode.trim(),
      'address': address.trim(),
      if (receiptSignature != null) 'receiptSignature': receiptSignature!.toMap(),
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  BranchModel copyWith({
    String? id,
    String? retailChainId,
    String? retailChainName,
    String? branchName,
    String? city,
    String? branchCode,
    String? address,
    BranchReceiptSignature? receiptSignature,
    DateTime? createdAt,
  }) {
    return BranchModel(
      id: id ?? this.id,
      retailChainId: retailChainId ?? this.retailChainId,
      retailChainName: retailChainName ?? this.retailChainName,
      branchName: branchName ?? this.branchName,
      city: city ?? this.city,
      branchCode: branchCode ?? this.branchCode,
      address: address ?? this.address,
      receiptSignature: receiptSignature ?? this.receiptSignature,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
