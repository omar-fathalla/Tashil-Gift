import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a Retail Chain / Hypermarket Organization (e.g. أسواق فتح الله, كارفور, سبينس, سعودي)
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
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
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
  final DateTime? createdAt;

  BranchModel({
    required this.id,
    required this.retailChainId,
    required this.retailChainName,
    required this.branchName,
    this.city = '',
    this.branchCode = '',
    this.address = '',
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
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
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
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
