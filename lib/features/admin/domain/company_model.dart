import 'package:cloud_firestore/cloud_firestore.dart';

class CompanyModel {
  final String id;
  final String name;
  final String slug;
  final String logoUrl;
  final DateTime? createdAt;
  final int productsCount;

  CompanyModel({
    required this.id,
    required this.name,
    required this.slug,
    this.logoUrl = '',
    this.createdAt,
    this.productsCount = 0,
  });

  factory CompanyModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return CompanyModel(
      id: doc.id,
      name: data['name'] ?? '',
      slug: data['slug'] ?? '',
      logoUrl: data['logoUrl'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      productsCount: (data['productsCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'slug': slug.toLowerCase().trim(),
      'logoUrl': logoUrl,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'productsCount': productsCount,
    };
  }
}

class CompanyProductModel {
  final String id;
  final String companySlug;
  final String companyName;
  final String productName;
  final String barcode;
  final DateTime? createdAt;

  CompanyProductModel({
    required this.id,
    required this.companySlug,
    this.companyName = '',
    required this.productName,
    required this.barcode,
    this.createdAt,
  });

  factory CompanyProductModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return CompanyProductModel(
      id: doc.id,
      companySlug: data['companySlug'] ?? '',
      companyName: data['companyName'] ?? '',
      productName: data['productName'] ?? '',
      barcode: data['barcode'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'companySlug': companySlug.toLowerCase().trim(),
      'companyName': companyName,
      'productName': productName,
      'barcode': barcode,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
