import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/partner_portal_auth_service.dart';

class CompanyModel {
  final String id;
  final String name;
  final String slug;
  final String logoUrl;
  final DateTime? createdAt;
  final int productsCount;

  // Tier 1: Company-Level Partner Portal Credentials
  final String brandManagerUsername;
  final String brandManagerPassword;
  final int brandCredentialVersion;
  final String agencyOpsUsername;
  final String agencyOpsPassword;
  final int agencyCredentialVersion;

  CompanyModel({
    required this.id,
    required this.name,
    required this.slug,
    this.logoUrl = '',
    this.createdAt,
    this.productsCount = 0,
    this.brandManagerUsername = '',
    this.brandManagerPassword = '',
    this.brandCredentialVersion = 1,
    this.agencyOpsUsername = '',
    this.agencyOpsPassword = '',
    this.agencyCredentialVersion = 1,
  });

  String get effectiveBrandUsername => brandManagerUsername.trim().isNotEmpty
      ? brandManagerUsername.trim()
      : PartnerPortalAuthService.defaultBrandUsername(slug);

  String get effectiveBrandPassword => brandManagerPassword.trim().isNotEmpty
      ? brandManagerPassword.trim()
      : PartnerPortalAuthService.defaultBrandPassword(slug);

  String get effectiveAgencyUsername => agencyOpsUsername.trim().isNotEmpty
      ? agencyOpsUsername.trim()
      : PartnerPortalAuthService.defaultAgencyUsername(slug);

  String get effectiveAgencyPassword => agencyOpsPassword.trim().isNotEmpty
      ? agencyOpsPassword.trim()
      : PartnerPortalAuthService.defaultAgencyPassword(slug);

  factory CompanyModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return CompanyModel.fromFirestoreMap(doc.id, data);
  }

  factory CompanyModel.fromFirestoreMap(String id, Map<String, dynamic> data) {
    final rawCreated = data['createdAt'];
    return CompanyModel(
      id: id,
      name: data['name'] ?? '',
      slug: data['slug'] ?? '',
      logoUrl: data['logoUrl'] ?? '',
      createdAt: rawCreated is Timestamp
          ? rawCreated.toDate()
          : (rawCreated is DateTime ? rawCreated : null),
      productsCount: (data['productsCount'] as num?)?.toInt() ?? 0,
      brandManagerUsername: (data['brandManagerUsername'] ?? '').toString(),
      brandManagerPassword: (data['brandManagerPassword'] ?? '').toString(),
      brandCredentialVersion: (data['brandCredentialVersion'] as num?)?.toInt() ?? 1,
      agencyOpsUsername: (data['agencyOpsUsername'] ?? '').toString(),
      agencyOpsPassword: (data['agencyOpsPassword'] ?? '').toString(),
      agencyCredentialVersion: (data['agencyCredentialVersion'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'slug': slug.toLowerCase().trim(),
      'logoUrl': logoUrl,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'productsCount': productsCount,
      if (brandManagerUsername.isNotEmpty) 'brandManagerUsername': brandManagerUsername,
      if (brandManagerPassword.isNotEmpty) 'brandManagerPassword': brandManagerPassword,
      'brandCredentialVersion': brandCredentialVersion,
      if (agencyOpsUsername.isNotEmpty) 'agencyOpsUsername': agencyOpsUsername,
      if (agencyOpsPassword.isNotEmpty) 'agencyOpsPassword': agencyOpsPassword,
      'agencyCredentialVersion': agencyCredentialVersion,
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

