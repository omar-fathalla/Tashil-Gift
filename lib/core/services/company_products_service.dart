import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_service.dart';

class CompanyProductItem {
  final String id;
  final String companySlug;
  final String productName;
  final String barcode;
  final String category;
  final String unitSize;
  final double? referencePrice;
  final Map<String, dynamic>? metadata;
  final Map<String, List<String>> chainAliases;

  CompanyProductItem({
    required this.id,
    required this.companySlug,
    required this.productName,
    required this.barcode,
    this.category = '',
    this.unitSize = '',
    this.referencePrice,
    this.metadata,
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

  factory CompanyProductItem.fromMap(Map<String, dynamic> data, String id) {
    final Map<String, List<String>> aliases = {};
    final rawAliases = data['chainAliases'];
    if (rawAliases is Map) {
      rawAliases.forEach((k, v) {
        if (v is List) {
          aliases[k.toString()] = v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
        }
      });
    }

    return CompanyProductItem(
      id: id,
      companySlug: data['companySlug']?.toString() ?? '',
      productName: data['productName']?.toString() ?? '',
      barcode: data['barcode']?.toString() ?? '',
      category: data['category']?.toString() ?? '',
      unitSize: data['unitSize']?.toString() ?? '',
      referencePrice: (data['referencePrice'] as num?)?.toDouble(),
      metadata: data['metadata'] is Map ? Map<String, dynamic>.from(data['metadata']) : null,
      chainAliases: aliases,
    );
  }

  factory CompanyProductItem.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return CompanyProductItem.fromMap(data, doc.id);
  }

  Map<String, dynamic> toFirestore() {
    return {
      'companySlug': companySlug,
      'productName': productName,
      'barcode': barcode,
      if (category.isNotEmpty) 'category': category,
      if (unitSize.isNotEmpty) 'unitSize': unitSize,
      if (referencePrice != null) 'referencePrice': referencePrice,
      if (metadata != null && metadata!.isNotEmpty) 'metadata': metadata,
      if (chainAliases.isNotEmpty) 'chainAliases': chainAliases,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  CompanyProductItem copyWith({
    String? id,
    String? companySlug,
    String? productName,
    String? barcode,
    String? category,
    String? unitSize,
    double? referencePrice,
    Map<String, dynamic>? metadata,
    Map<String, List<String>>? chainAliases,
  }) {
    return CompanyProductItem(
      id: id ?? this.id,
      companySlug: companySlug ?? this.companySlug,
      productName: productName ?? this.productName,
      barcode: barcode ?? this.barcode,
      category: category ?? this.category,
      unitSize: unitSize ?? this.unitSize,
      referencePrice: referencePrice ?? this.referencePrice,
      metadata: metadata ?? this.metadata,
      chainAliases: chainAliases ?? this.chainAliases,
    );
  }
}

final companyProductsServiceProvider = Provider<CompanyProductsService>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return CompanyProductsService(firestore);
});

class CompanyProductsService {
  final FirebaseFirestore _firestore;

  CompanyProductsService(this._firestore);

  /// Checks if a product (by barcode or by name) already exists in Firestore for a given company
  Future<CompanyProductItem?> findExistingProduct({
    required String companySlug,
    required String productName,
    required String barcode,
  }) async {
    final slug = companySlug.trim().toLowerCase();
    final normBarcode = barcode.trim();
    final normName = productName.trim().toLowerCase();

    if (slug.isEmpty) return null;

    // 1. Check by barcode for this company (if barcode is provided)
    if (normBarcode.isNotEmpty) {
      try {
        final slugs = (slug == '512' || slug == 'unilever' || slug == 'يونيليفر')
            ? ['512', 'unilever']
            : [slug];
        final barcodeQuery = await _firestore
            .collection('company_products')
            .where('companySlug', whereIn: slugs)
            .where('barcode', isEqualTo: normBarcode)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 4), onTimeout: () => throw Exception('Timeout'));

        if (barcodeQuery.docs.isNotEmpty) {
          return CompanyProductItem.fromFirestore(barcodeQuery.docs.first);
        }
      } catch (_) {}
    }

    // 3. Check by POS Chain Alias (if name is provided)
    if (normName.isNotEmpty) {
      try {
        final products = await getProductsForCompany(slug);
        for (final product in products) {
          for (final aliasesList in product.chainAliases.values) {
            if (aliasesList.any((a) => a.trim().toLowerCase() == normName)) {
              return product;
            }
          }
        }
      } catch (_) {}
    }

    return null;
  }

  /// Atomically registers a newly observed POS raw alias for a specific retail chain under a product's barcode
  Future<void> registerChainAlias({
    required String companySlug,
    required String barcode,
    required String chainName,
    required String rawPosName,
  }) async {
    final slug = companySlug.trim().toLowerCase();
    final normBarcode = barcode.trim();
    final cleanPosName = rawPosName.trim();
    final cleanChain = chainName.trim();

    if (slug.isEmpty || normBarcode.isEmpty || cleanPosName.isEmpty || cleanChain.isEmpty) return;

    try {
      final docId = '${slug}_$normBarcode';
      final docRef = _firestore.collection('company_products').doc(docId);

      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (snap.exists) {
          final data = snap.data() ?? {};
          final rawAliases = data['chainAliases'] is Map ? Map<String, dynamic>.from(data['chainAliases']) : <String, dynamic>{};
          final currentList = rawAliases[cleanChain] is List ? List<String>.from(rawAliases[cleanChain]) : <String>[];
          if (!currentList.contains(cleanPosName)) {
            currentList.add(cleanPosName);
            rawAliases[cleanChain] = currentList;
            tx.update(docRef, {
              'chainAliases': rawAliases,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      });
    } catch (_) {}
  }

  /// Finds a company product by international Barcode, exact Name, or POS Chain Alias
  Future<CompanyProductItem?> findProductByBarcodeOrAlias({
    required String companySlug,
    String? barcode,
    String? rawName,
    String? chainName,
    List<CompanyProductItem>? preloadedCatalog,
  }) async {
    final slug = companySlug.trim().toLowerCase();
    if (slug.isEmpty) return null;

    final normBarcode = (barcode ?? '').trim();
    final normName = (rawName ?? '').trim().toLowerCase();

    final catalog = preloadedCatalog ?? await getProductsForCompany(slug);

    // 1. Match by exact barcode
    if (normBarcode.isNotEmpty && normBarcode.length >= 6) {
      final match = catalog.where((p) => p.barcode.trim() == normBarcode);
      if (match.isNotEmpty) return match.first;
    }

    // 2. Match by exact canonical product name
    if (normName.isNotEmpty) {
      final nameMatch = catalog.where((p) => p.productName.trim().toLowerCase() == normName);
      if (nameMatch.isNotEmpty) return nameMatch.first;

      // 3. Match against chain aliases
      for (final product in catalog) {
        for (final aliasEntry in product.chainAliases.entries) {
          for (final alias in aliasEntry.value) {
            if (alias.trim().toLowerCase() == normName) {
              return product;
            }
          }
        }
      }
    }

    return null;
  }

  /// Batch import products for a specific company with chunking and strict deduplication
  Future<int> batchSaveProducts({
    required String companySlug,
    required String companyName,
    required List<Map<String, dynamic>> products,
    void Function(int saved, int total)? onProgress,
  }) async {
    final slug = companySlug.trim().toLowerCase();
    if (slug.isEmpty || products.isEmpty) return 0;

    // Fetch all existing products for this company to deduplicate against catalog
    final existingList = await getProductsForCompany(slug);
    final existingBarcodes = existingList.map((p) => p.barcode.trim()).where((b) => b.isNotEmpty).toSet();
    final existingNames = existingList.map((p) => p.productName.trim().toLowerCase()).where((n) => n.isNotEmpty).toSet();

    final uniqueProductsToSave = <Map<String, dynamic>>[];
    final seenBarcodesInBatch = <String>{};
    final seenNamesInBatch = <String>{};

    for (var item in products) {
      final pName = item['productName']?.toString().trim() ?? '';
      final pBarcode = item['barcode']?.toString().trim() ?? '';

      if (pName.isEmpty && pBarcode.isEmpty) continue;

      final isDuplicateBarcode = pBarcode.isNotEmpty && (existingBarcodes.contains(pBarcode) || seenBarcodesInBatch.contains(pBarcode));
      final isDuplicateName = pName.isNotEmpty && (existingNames.contains(pName.toLowerCase()) || seenNamesInBatch.contains(pName.toLowerCase()));

      if (isDuplicateBarcode || isDuplicateName) {
        // Skip duplicate item to prevent duplicate insertion
        continue;
      }

      if (pBarcode.isNotEmpty) seenBarcodesInBatch.add(pBarcode);
      if (pName.isNotEmpty) seenNamesInBatch.add(pName.toLowerCase());

      uniqueProductsToSave.add(item);
    }

    if (uniqueProductsToSave.isEmpty) {
      onProgress?.call(0, products.length);
      return 0;
    }

    int totalSaved = 0;
    const chunkSize = 400; // Safe limit under Firestore 500-op limit

    // Initial progress notification (0 items processed)
    onProgress?.call(0, uniqueProductsToSave.length);

    for (var i = 0; i < uniqueProductsToSave.length; i += chunkSize) {
      final chunk = uniqueProductsToSave.sublist(
        i,
        (i + chunkSize > uniqueProductsToSave.length) ? uniqueProductsToSave.length : i + chunkSize,
      );

      final batch = _firestore.batch();
      final collection = _firestore.collection('company_products');

      for (var item in chunk) {
        final pName = item['productName']?.toString().trim() ?? '';
        final pBarcode = item['barcode']?.toString().trim() ?? '';
        final pCategory = item['category']?.toString().trim() ?? '';
        final pUnitSize = item['unitSize']?.toString().trim() ?? '';
        final pPrice = (item['referencePrice'] is num)
            ? (item['referencePrice'] as num).toDouble()
            : null;

        if (pName.isNotEmpty || pBarcode.isNotEmpty) {
          final docRef = collection.doc();
          batch.set(docRef, {
            'companySlug': slug,
            'companyName': companyName,
            'productName': pName,
            'barcode': pBarcode,
            if (pCategory.isNotEmpty) 'category': pCategory,
            if (pUnitSize.isNotEmpty) 'unitSize': pUnitSize,
            'referencePrice': ?pPrice,
            'createdAt': FieldValue.serverTimestamp(),
          });
          totalSaved++;
        }
      }

      await batch.commit().timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );

      // Notify progress after committing current chunk
      onProgress?.call(totalSaved, uniqueProductsToSave.length);
    }

    // Update company product count
    if (totalSaved > 0) {
      final companyRef = _firestore.collection('companies').doc(slug);
      await companyRef.set({
        'name': companyName,
        'slug': slug,
        'productsCount': FieldValue.increment(totalSaved),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(
        const Duration(seconds: 4),
        onTimeout: () {},
      );
    }

    return totalSaved;
  }

  /// Adds a single product manually to Firestore with strict duplicate prevention
  Future<void> addSingleProduct({
    required String companySlug,
    required String productName,
    required String barcode,
    String category = '',
    String unitSize = '',
    double? referencePrice,
  }) async {
    final slug = companySlug.trim().toLowerCase();
    if (slug.isEmpty || productName.trim().isEmpty) return;

    // Strict duplicate check
    final existing = await findExistingProduct(
      companySlug: slug,
      productName: productName,
      barcode: barcode,
    );
    if (existing != null) {
      throw Exception('المنتج أو الباركود مسجل مسبقاً في كتالوج الشركة (${existing.productName})');
    }

    // Check/Ensure company document exists
    final companyRef = _firestore.collection('companies').doc(slug);
    final companyDoc = await companyRef.get().timeout(const Duration(seconds: 4), onTimeout: () => throw Exception('Timeout'));
    if (!companyDoc.exists) {
      await companyRef.set({
        'name': companySlug,
        'slug': slug,
        'createdAt': FieldValue.serverTimestamp(),
        'productsCount': 1,
      });
    } else {
      await companyRef.update({
        'productsCount': FieldValue.increment(1),
      });
    }

    await _firestore.collection('company_products').add({
      'companySlug': slug,
      'productName': productName.trim(),
      'barcode': barcode.trim(),
      if (category.isNotEmpty) 'category': category.trim(),
      if (unitSize.isNotEmpty) 'unitSize': unitSize.trim(),
      'referencePrice': ?referencePrice,
      'createdAt': FieldValue.serverTimestamp(),
    }).timeout(const Duration(seconds: 4), onTimeout: () => throw Exception('Timeout'));
  }

  /// Seeds default company (e.g. Al Marai) and products if database is empty
  Future<void> seedDefaultCompanyProducts() async {
    const slug = 'almarai';
    final companyRef = _firestore.collection('companies').doc(slug);
    await companyRef.set({
      'name': 'شركة المراعي',
      'slug': slug,
      'createdAt': FieldValue.serverTimestamp(),
      'productsCount': 5,
    }, SetOptions(merge: true));

    final sampleProducts = [
      {'productName': 'حليب المراعي كامل الدسم 1 لتر', 'barcode': '6281007001001', 'category': 'ألبان', 'unitSize': '1 لتر'},
      {'productName': 'حليب المراعي قليل الدسم 1 لتر', 'barcode': '6281007001002', 'category': 'ألبان', 'unitSize': '1 لتر'},
      {'productName': 'زبادي المراعي طبيعي 170 جم', 'barcode': '6281007002001', 'category': 'زبادي', 'unitSize': '170 جم'},
      {'productName': 'عصير المراعي برتقال 1 لتر', 'barcode': '6281007003001', 'category': 'عصائر', 'unitSize': '1 لتر'},
      {'productName': 'جبنة المراعي فيتا 500 جم', 'barcode': '6281007004001', 'category': 'أجبان', 'unitSize': '500 جم'},
    ];

    final batch = _firestore.batch();
    for (var prod in sampleProducts) {
      final docRef = _firestore.collection('company_products').doc();
      batch.set(docRef, {
        'companySlug': slug,
        'productName': prod['productName'],
        'barcode': prod['barcode'],
        'category': prod['category'],
        'unitSize': prod['unitSize'],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit().timeout(const Duration(seconds: 4), onTimeout: () {});
  }

  /// Deletes ALL products registered for a specific company from Firestore in chunks
  Future<int> deleteAllProductsForCompany({
    required String companySlug,
    void Function(int deleted, int total)? onProgress,
  }) async {
    final slug = companySlug.trim().toLowerCase();
    if (slug.isEmpty) return 0;

    int totalDeleted = 0;
    while (true) {
      final query = await _firestore
          .collection('company_products')
          .where('companySlug', isEqualTo: slug)
          .limit(400)
          .get()
          .timeout(const Duration(seconds: 8), onTimeout: () => throw Exception('Timeout'));

      if (query.docs.isEmpty) break;

      final batch = _firestore.batch();
      for (final doc in query.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit().timeout(const Duration(seconds: 8), onTimeout: () {});
      totalDeleted += query.docs.length;
      onProgress?.call(totalDeleted, totalDeleted);
    }

    // Reset company product count to 0 in companies collection
    final companyRef = _firestore.collection('companies').doc(slug);
    await companyRef.set({
      'productsCount': 0,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).timeout(const Duration(seconds: 4), onTimeout: () {});

    return totalDeleted;
  }

  /// Fetches registered products catalog for a company
  Future<List<CompanyProductItem>> getProductsForCompany(String companySlug) async {
    final cleanSlug = companySlug.trim().toLowerCase();
    final isUnilever = cleanSlug == '512' || cleanSlug == 'unilever' || cleanSlug == 'يونيليفر';
    if (isUnilever) {
      final query = await _firestore
          .collection('company_products')
          .where('companySlug', whereIn: ['512', 'unilever'])
          .get();
      return query.docs.map((doc) => CompanyProductItem.fromFirestore(doc)).toList();
    }
    final query = await _firestore
        .collection('company_products')
        .where('companySlug', isEqualTo: cleanSlug)
        .get();

    return query.docs.map((doc) => CompanyProductItem.fromFirestore(doc)).toList();
  }

  /// Audits all products for a specific company, removes any duplicate documents, and resets productsCount
  Future<Map<String, int>> auditAndDeduplicateCompanyProducts(String companySlug) async {
    final slug = companySlug.trim().toLowerCase();
    if (slug.isEmpty) return {'total': 0, 'unique': 0, 'duplicatesRemoved': 0};

    final query = await _firestore
        .collection('company_products')
        .where('companySlug', isEqualTo: slug)
        .get();

    final docs = query.docs;
    final Set<String> seenBarcodes = {};
    final Set<String> seenNames = {};
    final List<DocumentReference> duplicateRefs = [];

    for (final doc in docs) {
      final data = doc.data();
      final barcode = (data['barcode'] ?? '').toString().trim();
      final name = (data['productName'] ?? '').toString().trim().toLowerCase();

      bool isDup = false;
      if (barcode.isNotEmpty && barcode.length >= 6) {
        if (seenBarcodes.contains(barcode)) {
          isDup = true;
        } else {
          seenBarcodes.add(barcode);
        }
      }

      if (!isDup && name.isNotEmpty) {
        if (seenNames.contains(name)) {
          isDup = true;
        } else {
          seenNames.add(name);
        }
      }

      if (isDup) {
        duplicateRefs.add(doc.reference);
      }
    }

    if (duplicateRefs.isNotEmpty) {
      final batch = _firestore.batch();
      for (final ref in duplicateRefs) {
        batch.delete(ref);
      }
      await batch.commit();
    }

    final uniqueCount = docs.length - duplicateRefs.length;
    // Correct productsCount in companies collection
    await _firestore.collection('companies').doc(slug).set({
      'productsCount': uniqueCount,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return {
      'total': docs.length,
      'unique': uniqueCount,
      'duplicatesRemoved': duplicateRefs.length,
    };
  }
}
