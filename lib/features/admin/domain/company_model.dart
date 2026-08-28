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
  final Map<String, List<String>> chainAliases;

  CompanyProductModel({
    required this.id,
    required this.companySlug,
    this.companyName = '',
    required this.productName,
    required this.barcode,
    this.createdAt,
    this.chainAliases = const {},
  });

  /// Total count of recognized distinct retail chains where aliases were registered
  int get observedChainsCount => chainAliases.keys.length;

  /// Returns all aliases flattened into a list
  List<String> get allAliasesList {
    final List<String> list = [];
    for (final aliases in chainAliases.values) {
      list.addAll(aliases);
    }
    return list;
  }

  factory CompanyProductModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final Map<String, List<String>> aliases = {};
    final rawAliases = data['chainAliases'];
    if (rawAliases is Map) {
      rawAliases.forEach((k, v) {
        if (v is List) {
          aliases[k.toString()] = v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
        }
      });
    }

    return CompanyProductModel(
      id: doc.id,
      companySlug: data['companySlug'] ?? '',
      companyName: data['companyName'] ?? '',
      productName: data['productName'] ?? '',
      barcode: data['barcode'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      chainAliases: aliases,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'companySlug': companySlug.toLowerCase().trim(),
      'companyName': companyName,
      'productName': productName,
      'barcode': barcode,
      if (chainAliases.isNotEmpty) 'chainAliases': chainAliases,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

