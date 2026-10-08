import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../config/ai_config.dart';
import '../utils/arabic_numbers_utils.dart';
import 'ai_receipt_service.dart';
import 'company_products_service.dart';

/// Represents a discovered product in the active discovery inbox
class DiscoveredProductDocument {
  final String id;
  final String companySlug;
  final String companyName;
  final String rawProductName;
  final String canonicalName;
  final String brand;
  final String category;
  final String unitSize;
  final String barcode;
  final double averagePrice;
  final List<String> retailChains;
  final int invoiceFrequency;
  final String status; // 'pending', 'approved', 'rejected'
  final double confidenceScore;
  final String relevanceReason;
  final String rejectionReason;
  final bool isCriteriaCompliant;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isSelected;

  DiscoveredProductDocument({
    required this.id,
    required this.companySlug,
    required this.companyName,
    required this.rawProductName,
    required this.canonicalName,
    this.brand = '',
    this.category = 'عام',
    this.unitSize = '',
    this.barcode = '',
    this.averagePrice = 0.0,
    this.retailChains = const [],
    this.invoiceFrequency = 1,
    this.status = 'pending',
    this.confidenceScore = 0.95,
    this.relevanceReason = '',
    this.rejectionReason = '',
    this.isCriteriaCompliant = false,
    this.createdAt,
    this.updatedAt,
    this.isSelected = true,
  });

  factory DiscoveredProductDocument.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final rawChains = data['retailChains'];
    final chains = rawChains is List ? rawChains.map((e) => e.toString()).toList() : <String>[];

    return DiscoveredProductDocument(
      id: doc.id,
      companySlug: (data['companySlug'] ?? '').toString(),
      companyName: (data['companyName'] ?? '').toString(),
      rawProductName: (data['rawProductName'] ?? data['productName'] ?? '').toString(),
      canonicalName: (data['canonicalName'] ?? data['productName'] ?? '').toString(),
      brand: (data['brand'] ?? '').toString(),
      category: (data['category'] ?? 'عام').toString(),
      unitSize: (data['unitSize'] ?? '').toString(),
      barcode: (data['barcode'] ?? '').toString(),
      averagePrice: (data['averagePrice'] as num?)?.toDouble() ?? (data['referencePrice'] as num?)?.toDouble() ?? 0.0,
      retailChains: chains,
      invoiceFrequency: (data['invoiceFrequency'] as num?)?.toInt() ?? 1,
      status: (data['status'] ?? 'pending').toString(),
      confidenceScore: (data['confidenceScore'] as num?)?.toDouble() ?? 0.95,
      relevanceReason: (data['relevanceReason'] ?? '').toString(),
      rejectionReason: (data['rejectionReason'] ?? '').toString(),
      isCriteriaCompliant: data['isCriteriaCompliant'] == true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'companySlug': companySlug,
      'companyName': companyName,
      'rawProductName': rawProductName,
      'canonicalName': canonicalName,
      'brand': brand,
      'category': category,
      'unitSize': unitSize,
      'barcode': barcode,
      'averagePrice': averagePrice,
      'retailChains': retailChains,
      'invoiceFrequency': invoiceFrequency,
      'status': status,
      'confidenceScore': confidenceScore,
      'relevanceReason': relevanceReason,
      'rejectionReason': rejectionReason,
      'isCriteriaCompliant': isCriteriaCompliant,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  DiscoveredProductDocument copyWith({
    String? canonicalName,
    String? brand,
    String? category,
    String? unitSize,
    String? barcode,
    double? averagePrice,
    String? status,
    String? rejectionReason,
    bool? isCriteriaCompliant,
    bool? isSelected,
  }) {
    return DiscoveredProductDocument(
      id: id,
      companySlug: companySlug,
      companyName: companyName,
      rawProductName: rawProductName,
      canonicalName: canonicalName ?? this.canonicalName,
      brand: brand ?? this.brand,
      category: category ?? this.category,
      unitSize: unitSize ?? this.unitSize,
      barcode: barcode ?? this.barcode,
      averagePrice: averagePrice ?? this.averagePrice,
      retailChains: retailChains,
      invoiceFrequency: invoiceFrequency,
      status: status ?? this.status,
      confidenceScore: confidenceScore,
      relevanceReason: relevanceReason,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      isCriteriaCompliant: isCriteriaCompliant ?? this.isCriteriaCompliant,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

/// Legacy compatibility item
class DiscoveredProductItem {
  final String productName;
  final String barcode;
  final String category;
  final String unitSize;
  final double? referencePrice;
  final int invoiceFrequency;
  final String relevanceReason;
  final String confidence; // 'high', 'medium', 'suggested'
  final bool isSelected;

  DiscoveredProductItem({
    required this.productName,
    required this.barcode,
    this.category = '',
    this.unitSize = '',
    this.referencePrice,
    this.invoiceFrequency = 1,
    this.relevanceReason = '',
    this.confidence = 'high',
    this.isSelected = true,
  });

  DiscoveredProductItem copyWith({
    String? productName,
    String? barcode,
    String? category,
    String? unitSize,
    double? referencePrice,
    int? invoiceFrequency,
    String? relevanceReason,
    String? confidence,
    bool? isSelected,
  }) {
    return DiscoveredProductItem(
      productName: productName ?? this.productName,
      barcode: barcode ?? this.barcode,
      category: category ?? this.category,
      unitSize: unitSize ?? this.unitSize,
      referencePrice: referencePrice ?? this.referencePrice,
      invoiceFrequency: invoiceFrequency ?? this.invoiceFrequency,
      relevanceReason: relevanceReason ?? this.relevanceReason,
      confidence: confidence ?? this.confidence,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productName': productName,
      'barcode': barcode,
      if (category.isNotEmpty) 'category': category,
      if (unitSize.isNotEmpty) 'unitSize': unitSize,
      if (referencePrice != null) 'referencePrice': referencePrice,
      'invoiceFrequency': invoiceFrequency,
      'relevanceReason': relevanceReason,
      'confidence': confidence,
    };
  }
}

/// Model representing the evaluation of a product candidate against the 5 strict discovery criteria
class DiscoveryCriteriaResult {
  final bool isEligible;
  final String rejectionReason;
  final bool hasValidBarcode;
  final bool meetsFrequency;
  final bool isNotGeneric;
  final bool hasValidPrice;
  final bool matchesCompanyBrand;

  const DiscoveryCriteriaResult({
    required this.isEligible,
    required this.rejectionReason,
    required this.hasValidBarcode,
    required this.meetsFrequency,
    required this.isNotGeneric,
    required this.hasValidPrice,
    required this.matchesCompanyBrand,
  });
}

/// Summary result of running retroactive cleanup on existing discovered products
class DiscoveryCleanupSummary {
  final int totalProcessed;
  final int totalRejected;
  final int totalRetained;
  final int invalidBarcodeCount;
  final int singleFrequencyCount;
  final int genericItemCount;
  final int invalidPriceCount;
  final int unmatchedBrandCount;

  const DiscoveryCleanupSummary({
    required this.totalProcessed,
    required this.totalRejected,
    required this.totalRetained,
    this.invalidBarcodeCount = 0,
    this.singleFrequencyCount = 0,
    this.genericItemCount = 0,
    this.invalidPriceCount = 0,
    this.unmatchedBrandCount = 0,
  });
}

final aiProductDiscoveryServiceProvider = Provider<AiProductDiscoveryService>((ref) {
  try {
    final productsService = ref.watch(companyProductsServiceProvider);
    return AiProductDiscoveryService(
      productsService: productsService,
    );
  } catch (_) {
    return AiProductDiscoveryService();
  }
});

class AiProductDiscoveryService {
  final CompanyProductsService? _productsService;
  final FirebaseFirestore? _firestore;
  final GenerativeModel _model;

  AiProductDiscoveryService({
    CompanyProductsService? productsService,
    FirebaseFirestore? firestore,
  })  : _productsService = productsService,
        _firestore = firestore,
        _model = GenerativeModel(
          model: 'gemini-3.7-flash',
          apiKey: AiConfig.geminiApiKey,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            temperature: 0.1,
            maxOutputTokens: 3000,
          ),
        );

  FirebaseFirestore get _effectiveFirestore => _firestore ?? FirebaseFirestore.instance;
  CompanyProductsService get _effectiveProductsService =>
      _productsService ?? CompanyProductsService(_effectiveFirestore);

  /// Collection reference for the discovery inbox
  CollectionReference<Map<String, dynamic>> get _inboxCollection =>
      _effectiveFirestore.collection('discovered_products_inbox');

  /// Streams pending/active discovered products with optional company and status filters
  Stream<List<DiscoveredProductDocument>> streamDiscoveredProducts({
    String? companySlug,
    String? status = 'pending',
  }) {
    try {
      Query<Map<String, dynamic>> query = _inboxCollection;

      if (companySlug != null && companySlug.trim().isNotEmpty && companySlug.trim() != 'all') {
        query = query.where('companySlug', isEqualTo: companySlug.trim().toLowerCase());
      }

      if (status != null && status.isNotEmpty && status != 'all') {
        query = query.where('status', isEqualTo: status);
      }

      return query.snapshots().map((snapshot) {
        final list = snapshot.docs.map((d) => DiscoveredProductDocument.fromFirestore(d)).toList();
        // Sort by frequency descending, then date
        list.sort((a, b) => b.invoiceFrequency.compareTo(a.invoiceFrequency));
        return list;
      }).handleError((_) => <DiscoveredProductDocument>[]);
    } catch (_) {
      return Stream.value(<DiscoveredProductDocument>[]);
    }
  }

  /// Streams the real-time count of pending discovered products across all companies
  Stream<int> streamPendingCount() {
    try {
      return _inboxCollection
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .map((snapshot) => snapshot.docs.length)
          .handleError((_) => 0);
    } catch (_) {
      return Stream.value(0);
    }
  }

  /// Background Auto-Harvester: Invoked automatically after receipt validation
  /// Checks extracted products and saves new uncataloged items to `discovered_products_inbox`
  Future<void> autoHarvestFromReceiptAnalysis({
    required String companySlug,
    required String companyName,
    required String retailChain,
    required String branch,
    required String receiptNumber,
    required List<ExtractedProductItem> extractedProducts,
  }) async {
    final slug = companySlug.trim().toLowerCase();
    if (slug.isEmpty || extractedProducts.isEmpty) return;

    try {
      // 1. Fetch current catalog registered barcodes and names
      final catalog = await _effectiveProductsService.getProductsForCompany(slug);
      final registeredBarcodes = catalog
          .map((p) => p.barcode.trim().toEnglishDigits())
          .where((b) => b.isNotEmpty)
          .toSet();
      final registeredNames = catalog
          .map((p) => _normalizeForComparison(p.productName))
          .where((n) => n.isNotEmpty)
          .toSet();

      for (final p in extractedProducts) {
        final rawName = p.name.trim();
        if (rawName.isEmpty) continue;

        final rawBarcode = p.barcode.trim().toEnglishDigits();
        final normName = _normalizeForComparison(rawName);

        // --- ENFORCE 5 STRICT DISCOVERY CRITERIA (AIR-72) ---
        // 1. Mandatory Valid Barcode Constraint (8 to 14 numeric digits)
        if (!DiscoveryCriteriaEvaluator.isValidRetailBarcode(rawBarcode)) continue;

        // 2. Generic & Service Items Exclusion (no bags, delivery, tips, discounts, generic placeholders)
        if (DiscoveryCriteriaEvaluator.isGenericOrServiceItem(rawName)) continue;

        // 3. Price Sanity Check (positive, realistic FMCG price)
        if (!DiscoveryCriteriaEvaluator.hasValidPrice(p.price)) continue;

        // 4. Company Brand Whitelist Match
        if (!p.isTargetCompany && !DiscoveryCriteriaEvaluator.isProbableCompanyProduct(rawName, slug)) continue;

        // If already in catalog with barcode, auto-register raw POS string as chain alias
        if (registeredBarcodes.contains(rawBarcode)) {
          if (retailChain.isNotEmpty && rawName.isNotEmpty) {
            _effectiveProductsService.registerChainAlias(
              companySlug: slug,
              barcode: rawBarcode,
              chainName: retailChain,
              rawPosName: rawName,
            );
          }
          continue;
        }

        if (registeredNames.contains(normName)) {
          continue;
        }

        // Generate deterministic document ID
        final docId = _generateDiscoveryDocId(slug, rawBarcode, rawName);
        final docRef = _inboxCollection.doc(docId);

        final inferredBrand = _inferSubBrand(rawName, slug);
        final inferredCategory = _inferCategory(rawName);
        final canonicalName = _cleanCanonicalName(rawName);

        final bool isHighConfidence = rawBarcode.isNotEmpty &&
            rawBarcode.length >= 8 &&
            DiscoveryCriteriaEvaluator.isProbableCompanyProduct(rawName, slug) &&
            p.price > 0 &&
            p.price < 5000;

        // If high confidence, auto-inject directly into company_products catalog (AIR-28)
        if (isHighConfidence) {
          final prodData = {
            'productName': canonicalName.isNotEmpty ? canonicalName : rawName,
            'barcode': rawBarcode,
            'category': inferredCategory,
            'unitSize': _extractUnitSize(rawName),
            'referencePrice': p.price,
          };

          await _effectiveProductsService.batchSaveProducts(
            companySlug: slug,
            companyName: companyName.isNotEmpty ? companyName : slug,
            products: [prodData],
          );

          if (retailChain.isNotEmpty && rawName.isNotEmpty) {
            await _effectiveProductsService.registerChainAlias(
              companySlug: slug,
              barcode: rawBarcode,
              chainName: retailChain,
              rawPosName: rawName,
            );
          }
        }

        await _effectiveFirestore.runTransaction((tx) async {
          final snap = await tx.get(docRef);
          if (snap.exists) {
            final data = snap.data() ?? {};
            final currentFreq = (data['invoiceFrequency'] as num?)?.toInt() ?? 1;
            final rawChains = data['retailChains'];
            final chains = rawChains is List ? rawChains.map((e) => e.toString()).toSet() : <String>{};
            if (retailChain.isNotEmpty) chains.add(retailChain);

            final currentPrices = (data['observedPrices'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [];
            if (p.price > 0) currentPrices.add(p.price);
            final avgPrice = currentPrices.isNotEmpty ? (currentPrices.reduce((a, b) => a + b) / currentPrices.length) : p.price;

            final newFreq = currentFreq + 1;
            // Upgrade status to 'pending' once frequency >= 2 or observed across multiple chains (Criteria 2)
            final meetsFreq = DiscoveryCriteriaEvaluator.meetsFrequencyThreshold(newFreq, chains.toList());
            final updatedStatus = (data['status'] == 'approved' || data['status'] == 'auto_approved')
                ? data['status']
                : (meetsFreq ? 'pending' : (data['status'] ?? 'pending'));

            tx.update(docRef, {
              'invoiceFrequency': newFreq,
              'retailChains': chains.toList(),
              'observedPrices': currentPrices.take(10).toList(),
              'averagePrice': avgPrice,
              'latestPrice': p.price > 0 ? p.price : (data['latestPrice'] ?? 0.0),
              'barcode': rawBarcode,
              'status': isHighConfidence ? 'auto_approved' : updatedStatus,
              'isCriteriaCompliant': true,
              'lastReceiptNumber': receiptNumber,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } else {
            tx.set(docRef, {
              'companySlug': slug,
              'companyName': companyName.isNotEmpty ? companyName : slug,
              'rawProductName': rawName,
              'canonicalName': canonicalName,
              'brand': inferredBrand,
              'category': inferredCategory,
              'unitSize': _extractUnitSize(rawName),
              'barcode': rawBarcode,
              'averagePrice': p.price,
              'latestPrice': p.price,
              'observedPrices': [if (p.price > 0) p.price],
              'retailChains': [if (retailChain.isNotEmpty) retailChain],
              'invoiceFrequency': 1,
              // First observation marked as unverified until second observation confirms it (Criteria 2)
              'status': isHighConfidence ? 'auto_approved' : 'unverified_first_hit',
              'isCriteriaCompliant': true,
              'confidenceScore': isHighConfidence ? 0.99 : 0.96,
              'relevanceReason': isHighConfidence
                  ? 'تم اعتماده وحقنه تلقائياً في كتالوج الشركة (AIR-28)'
                  : 'تم رصده لأول مرة في فاتورة معتمدة لشركة $companyName',
              'lastReceiptNumber': receiptNumber,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        });
      }
    } catch (e) {
      debugPrint('AI Product Discovery Harvester error (non-fatal): $e');
    }
  }

  /// Batch approves discovered products and merges them directly into company catalog
  Future<int> approveAndMergeDiscoveredDocuments({
    required List<DiscoveredProductDocument> documents,
    void Function(int approved, int total)? onProgress,
  }) async {
    if (documents.isEmpty) return 0;

    int totalSaved = 0;
    final Map<String, List<DiscoveredProductDocument>> byCompany = {};
    for (final doc in documents) {
      byCompany.putIfAbsent(doc.companySlug, () => []).add(doc);
    }

    for (final entry in byCompany.entries) {
      final slug = entry.key;
      final items = entry.value;
      final companyName = items.first.companyName;

      final productsToSave = items.map((doc) {
        return {
          'productName': doc.canonicalName.isNotEmpty ? doc.canonicalName : doc.rawProductName,
          'barcode': doc.barcode,
          'category': doc.category,
          'unitSize': doc.unitSize,
          'referencePrice': doc.averagePrice > 0 ? doc.averagePrice : null,
        };
      }).toList();

      final saved = await _effectiveProductsService.batchSaveProducts(
        companySlug: slug,
        companyName: companyName,
        products: productsToSave,
      );
      totalSaved += saved;

      // Update status in inbox
      final batch = _effectiveFirestore.batch();
      for (final doc in items) {
        final docRef = _inboxCollection.doc(doc.id);
        batch.update(docRef, {
          'status': 'approved',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      if (onProgress != null) {
        onProgress(totalSaved, documents.length);
      }
    }

    return totalSaved;
  }

  /// Rejects/dismisses discovered items from the inbox
  Future<void> rejectDiscoveredDocuments(List<String> docIds, {String reason = 'استبعاد يدوي من الإدارة'}) async {
    if (docIds.isEmpty) return;
    final batch = _effectiveFirestore.batch();
    for (final id in docIds) {
      batch.update(_inboxCollection.doc(id), {
        'status': 'rejected',
        'rejectionReason': reason,
        'rejectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// Retroactive Cleanup: Audits all existing pending products against the 5 strict criteria
  /// Automatically rejects non-compliant items and marks verified items (AIR-72)
  Future<DiscoveryCleanupSummary> cleanupExistingPendingInbox({
    String? companySlug,
    void Function(int processed, int rejected, int retained)? onProgress,
  }) async {
    Query<Map<String, dynamic>> query = _inboxCollection.where('status', isEqualTo: 'pending');
    if (companySlug != null && companySlug.trim().isNotEmpty && companySlug.trim() != 'all') {
      query = query.where('companySlug', isEqualTo: companySlug.trim().toLowerCase());
    }

    final snapshot = await query.get();
    int processed = 0;
    int rejected = 0;
    int retained = 0;
    int invalidBarcodeCount = 0;
    int singleFrequencyCount = 0;
    int genericItemCount = 0;
    int invalidPriceCount = 0;
    int unmatchedBrandCount = 0;

    WriteBatch batch = _effectiveFirestore.batch();
    int batchOps = 0;

    for (final doc in snapshot.docs) {
      processed++;
      final item = DiscoveredProductDocument.fromFirestore(doc);

      final eval = DiscoveryCriteriaEvaluator.evaluateProduct(
        productName: item.canonicalName.isNotEmpty ? item.canonicalName : item.rawProductName,
        barcode: item.barcode,
        price: item.averagePrice,
        frequency: item.invoiceFrequency,
        retailChains: item.retailChains,
        companySlug: item.companySlug,
        brand: item.brand,
        enforceFrequency: true,
      );

      if (!eval.hasValidBarcode) invalidBarcodeCount++;
      if (!eval.meetsFrequency) singleFrequencyCount++;
      if (!eval.isNotGeneric) genericItemCount++;
      if (!eval.hasValidPrice) invalidPriceCount++;
      if (!eval.matchesCompanyBrand) unmatchedBrandCount++;

      if (!eval.isEligible) {
        rejected++;
        batch.update(doc.reference, {
          'status': 'rejected',
          'rejectedAt': FieldValue.serverTimestamp(),
          'rejectionReason': eval.rejectionReason,
          'isCriteriaCompliant': false,
        });
        batchOps++;
      } else {
        retained++;
        batch.update(doc.reference, {
          'isCriteriaCompliant': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        batchOps++;
      }

      if (batchOps >= 400) {
        await batch.commit();
        batch = _effectiveFirestore.batch();
        batchOps = 0;
      }

      if (onProgress != null) {
        onProgress(processed, rejected, retained);
      }
    }

    if (batchOps > 0) {
      await batch.commit();
    }

    return DiscoveryCleanupSummary(
      totalProcessed: processed,
      totalRejected: rejected,
      totalRetained: retained,
      invalidBarcodeCount: invalidBarcodeCount,
      singleFrequencyCount: singleFrequencyCount,
      genericItemCount: genericItemCount,
      invalidPriceCount: invalidPriceCount,
      unmatchedBrandCount: unmatchedBrandCount,
    );
  }

  /// Deep scans historical transactions in receipts_transactions to harvest all uncataloged products
  Future<int> scanHistoricalTransactions({
    required String companySlug,
    required String companyName,
    void Function(int processed, int discovered)? onProgress,
  }) async {
    final slug = companySlug.trim().toLowerCase();
    if (slug.isEmpty) return 0;

    final query = await _effectiveFirestore
        .collection('receipts_transactions')
        .where('is_valid', isEqualTo: true)
        .limit(200)
        .get();

    int discoveredCount = 0;
    int index = 0;

    for (final doc in query.docs) {
      index++;
      final data = doc.data();
      final rawProducts = data['extracted_products'];
      if (rawProducts is! List) continue;

      final storeChain = (data['store_chain_detected'] ?? '').toString();
      final branch = (data['branch_detected'] ?? '').toString();
      final receiptNum = (data['receipt_number'] ?? doc.id).toString();

      final List<ExtractedProductItem> items = [];
      for (final p in rawProducts) {
        if (p is! Map) continue;
        items.add(ExtractedProductItem(
          name: (p['name'] ?? '').toString(),
          barcode: (p['barcode'] ?? '').toString(),
          price: (p['price'] as num?)?.toDouble() ?? 0.0,
          quantity: (p['quantity'] as num?)?.toInt() ?? 1,
          isTargetCompany: p['isTargetCompany'] == true,
        ));
      }

      if (items.isNotEmpty) {
        await autoHarvestFromReceiptAnalysis(
          companySlug: slug,
          companyName: companyName,
          retailChain: storeChain,
          branch: branch,
          receiptNumber: receiptNum,
          extractedProducts: items,
        );
        discoveredCount += items.where((i) => i.isTargetCompany).length;
      }

      if (onProgress != null) {
        onProgress(index, discoveredCount);
      }
    }

    return discoveredCount;
  }

  /// Discovers uncataloged products from invoice transactions for a specific company using Gemini AI (Legacy dialog compat)
  Future<List<DiscoveredProductItem>> discoverProductsFromTransactions({
    required String companySlug,
    required String companyName,
    required List<QueryDocumentSnapshot> transactions,
    List<CompanyProductItem>? preloadedCatalog,
  }) async {
    final slug = companySlug.trim().toLowerCase();
    if (slug.isEmpty || transactions.isEmpty) return [];

    final catalog = preloadedCatalog ?? await _effectiveProductsService.getProductsForCompany(slug);
    final Set<String> registeredBarcodes = catalog
        .map((p) => p.barcode.trim().toEnglishDigits())
        .where((b) => b.isNotEmpty)
        .toSet();
    final Set<String> registeredNames = catalog
        .map((p) => _normalizeForComparison(p.productName))
        .where((n) => n.isNotEmpty)
        .toSet();

    // Also populate all known chain aliases into registeredNames
    for (final p in catalog) {
      for (final aliasList in p.chainAliases.values) {
        for (final alias in aliasList) {
          final normAlias = _normalizeForComparison(alias);
          if (normAlias.isNotEmpty) {
            registeredNames.add(normAlias);
          }
        }
      }
    }

    final Map<String, _RawCandidateGroup> candidatesMap = {};

    for (final doc in transactions) {
      final data = doc.data() as Map<String, dynamic>;
      final rawProducts = data['extracted_products'];
      if (rawProducts is! List) continue;

      for (final p in rawProducts) {
        if (p is! Map) continue;
        final name = (p['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;

        final rawBarcode = (p['barcode'] ?? '').toString().trim().toEnglishDigits();
        final price = (p['price'] as num?)?.toDouble() ?? 0.0;
        final qty = (p['quantity'] as num?)?.toInt() ?? 1;
        final isTarget = p['isTargetCompany'] == true;
        final normName = _normalizeForComparison(name);

        final bool isAlreadyInCatalog = (rawBarcode.isNotEmpty && registeredBarcodes.contains(rawBarcode)) ||
            registeredNames.contains(normName);
        if (isAlreadyInCatalog) continue;

        final key = (rawBarcode.isNotEmpty && rawBarcode.length >= 6) ? rawBarcode : normName;

        if (!candidatesMap.containsKey(key)) {
          candidatesMap[key] = _RawCandidateGroup(
            name: name,
            barcode: rawBarcode,
            prices: [if (price > 0) price],
            frequency: qty,
            isTarget: isTarget,
          );
        } else {
          final group = candidatesMap[key]!;
          group.frequency += qty;
          if (price > 0) group.prices.add(price);
          if (rawBarcode.isNotEmpty && group.barcode.isEmpty) {
            group.barcode = rawBarcode;
          }
          if (isTarget) group.isTarget = true;
        }
      }
    }

    if (candidatesMap.isEmpty) return [];

    final candidateList = candidatesMap.values.toList();
    candidateList.sort((a, b) {
      if (a.isTarget != b.isTarget) return a.isTarget ? -1 : 1;
      return b.frequency.compareTo(a.frequency);
    });
    final topCandidates = candidateList.take(40).toList();

    try {
      final promptCandidatesJson = topCandidates.map((c) {
        final avgPrice = c.prices.isNotEmpty ? (c.prices.reduce((a, b) => a + b) / c.prices.length) : null;
        return {
          'rawName': c.name,
          'barcode': c.barcode,
          'avgPrice': avgPrice,
          'invoiceFrequency': c.frequency,
          'isMarkedTarget': c.isTarget,
        };
      }).toList();

      final encodedCandidates = jsonEncode(promptCandidatesJson);

      final prompt = '''
أنت خبير ذكاء اصطناعي متخصص في تصنيف وتحليل سلع ومنتجات الشركات الاستهلاكية (FMCG).
الشركة المستهدفة: "$companyName" (كود الشركة: "$companySlug").

فيما يلي قائمة بالأصناف المستخرجة من فواتير المشتريات التي لم يتم تسجيلها بعد في كتالوج الشركة بالداتابيز:
$encodedCandidates

المطلوب بدقة:
1. تحديد الأصناف التي تنتمي فعلياً لشركة "$companyName" أو إحدى علاماتها التجارية التابعة.
2. استبعاد المنتجات التابعة لشركات منافسة أو منتجات عامة.
3. تنسيق اسم المنتج بشكل احترافي، تحديد الباركود، الفئة (category)، الحجم (unitSize)، والسعر المرجعي (referencePrice).

يجب إرجاع النتيجة بصيغة JSON حصراً:
{
  "products": [
    {
      "productName": "اسم الصنف المنسق",
      "barcode": "الباركود إن وجد",
      "category": "الفئة",
      "unitSize": "الحجم",
      "referencePrice": 120.0,
      "isCompanyProduct": true,
      "relevanceReason": "منتج أصلي تابع للعلامة",
      "confidence": "high"
    }
  ]
}
''';

      final response = await _model.generateContent([
        Content.text(prompt),
      ]).timeout(const Duration(seconds: 15));

      if (response.text != null && response.text!.trim().isNotEmpty) {
        final cleanJson = _cleanJsonString(response.text!);
        final parsed = jsonDecode(cleanJson) as Map<String, dynamic>;
        final prodsList = parsed['products'] as List<dynamic>? ?? [];

        final List<DiscoveredProductItem> results = [];
        for (final p in prodsList) {
          if (p is! Map) continue;
          if (p['isCompanyProduct'] != true) continue;

          final name = (p['productName'] ?? '').toString().trim();
          if (name.isEmpty) continue;

          final barcode = (p['barcode'] ?? '').toString().trim();
          final category = (p['category'] ?? '').toString().trim();
          final unitSize = (p['unitSize'] ?? '').toString().trim();
          final refPrice = (p['referencePrice'] as num?)?.toDouble();
          final reason = (p['relevanceReason'] ?? '').toString().trim();
          final confidence = (p['confidence'] ?? 'high').toString().trim();

          final matchCandidate = topCandidates.firstWhere(
            (c) => _normalizeForComparison(c.name) == _normalizeForComparison(name) ||
                (barcode.isNotEmpty && c.barcode == barcode),
            orElse: () => topCandidates.first,
          );

          results.add(
            DiscoveredProductItem(
              productName: name,
              barcode: barcode.isNotEmpty ? barcode : matchCandidate.barcode,
              category: category,
              unitSize: unitSize,
              referencePrice: refPrice ?? (matchCandidate.prices.isNotEmpty ? matchCandidate.prices.first : null),
              invoiceFrequency: matchCandidate.frequency,
              relevanceReason: reason.isNotEmpty ? reason : 'تم التحقق من تبعيته لعلامات $companyName',
              confidence: confidence,
              isSelected: true,
            ),
          );
        }

        if (results.isNotEmpty) return results;
      }
    } catch (_) {}

    return _heuristicFallbackDiscovery(companyName, topCandidates);
  }

  List<DiscoveredProductItem> _heuristicFallbackDiscovery(
    String companyName,
    List<_RawCandidateGroup> candidates,
  ) {
    final List<DiscoveredProductItem> fallbackList = [];
    for (final c in candidates) {
      if (c.isTarget || c.name.toLowerCase().contains(companyName.toLowerCase())) {
        final avgPrice = c.prices.isNotEmpty ? (c.prices.reduce((a, b) => a + b) / c.prices.length) : null;
        fallbackList.add(
          DiscoveredProductItem(
            productName: c.name,
            barcode: c.barcode,
            category: 'عام',
            unitSize: '',
            referencePrice: avgPrice,
            invoiceFrequency: c.frequency,
            relevanceReason: 'تم رصده في فواتير $companyName المعتمدة',
            confidence: 'high',
            isSelected: true,
          ),
        );
      }
    }
    return fallbackList;
  }

  /// Batch saves approved discovered products into Firestore company_products (Legacy dialog compat)
  Future<int> approveAndSaveDiscoveredProducts({
    required String companySlug,
    required String companyName,
    required List<DiscoveredProductItem> approvedItems,
    void Function(int saved, int total)? onProgress,
  }) async {
    final slug = companySlug.trim().toLowerCase();
    if (slug.isEmpty || approvedItems.isEmpty) return 0;

    final selected = approvedItems.where((p) => p.isSelected).toList();
    final productsToSave = selected.map((p) {
      return {
        'productName': p.productName.trim(),
        'barcode': p.barcode.trim(),
        'category': p.category.trim(),
        'unitSize': p.unitSize.trim(),
        'referencePrice': p.referencePrice,
      };
    }).toList();

    if (productsToSave.isEmpty) return 0;

    final savedCount = await _effectiveProductsService.batchSaveProducts(
      companySlug: slug,
      companyName: companyName,
      products: productsToSave,
      onProgress: onProgress,
    );

    // Mark approved items as 'approved' in discovered_products_inbox
    try {
      final batch = _effectiveFirestore.batch();
      for (final p in selected) {
        final docId = _generateDiscoveryDocId(slug, p.barcode.trim(), p.productName.trim());
        final docRef = _inboxCollection.doc(docId);
        batch.set(
          docRef,
          {
            'companySlug': slug,
            'companyName': companyName,
            'canonicalName': p.productName.trim(),
            'barcode': p.barcode.trim(),
            'status': 'approved',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error updating discovered_products_inbox status: $e');
    }

    return savedCount;
  }

  // --- Helper Methods ---

  static String _generateDiscoveryDocId(String slug, String barcode, String name) {
    if (barcode.isNotEmpty && barcode.length >= 6) {
      return '${slug}_$barcode';
    }
    final clean = name.replaceAll(RegExp(r'[^\w\d\u0600-\u06FF]'), '_').replaceAll(RegExp(r'_+'), '_');
    return '${slug}_${clean.length > 40 ? clean.substring(0, 40) : clean}';
  }

  static String _inferSubBrand(String name, String slug) {
    final lower = name.toLowerCase();

    // Unilever Brands
    if (lower.contains('تريزيمي') || lower.contains('تريزمي') || lower.contains('tresemme')) return 'تريزيمي (TRESemmé)';
    if (lower.contains('كلير') || lower.contains('clear')) return 'كلير (Clear)';
    if (lower.contains('ريكسونا') || lower.contains('rexona')) return 'ريكسونا (Rexona)';
    if (lower.contains('أكس') || lower.contains('اكس') || lower.contains('axe')) return 'أكس (Axe)';
    if (lower.contains('دوف') || lower.contains('dove')) return 'دوف (Dove)';
    if (lower.contains('صنسيلك') || lower.contains('صنسلك') || lower.contains('sunsilk')) return 'صنسيلك (Sunsilk)';
    if (lower.contains('سيجنال') || lower.contains('signal')) return 'سيجنال (Signal)';
    if (lower.contains('لايفبوي') || lower.contains('lifebuoy')) return 'لايفبوي (Lifebuoy)';
    if (lower.contains('لوكس') || lower.contains('lux')) return 'لوكس (Lux)';
    if (lower.contains('كومفورت') || lower.contains('comfort')) return 'كومفورت (Comfort)';
    if (lower.contains('ليبتون') || lower.contains('lipton')) return 'ليبتون (Lipton)';
    if (lower.contains('كنور') || lower.contains('knorr')) return 'كنور (Knorr)';
    if (lower.contains('فازلين') || lower.contains('vaseline')) return 'فازلين (Vaseline)';

    // Cadbury / Mondelez Brands
    if (lower.contains('ديري ميلك') || lower.contains('ديرى ميلك') || lower.contains('dairy milk')) return 'ديري ميلك (Dairy Milk)';
    if (lower.contains('مورو') || lower.contains('moro')) return 'مورو (Moro)';
    if (lower.contains('بابلي') || lower.contains('bubbly')) return 'بابلي (Bubbly)';
    if (lower.contains('اوريو') || lower.contains('أوريو') || lower.contains('oreo') || lower.contains('بوريو')) return 'أوريو (Oreo)';
    if (lower.contains('ماندولين') || lower.contains('مندولين')) return 'ماندولين (Mandolin)';
    if (lower.contains('فليك') || lower.contains('flake')) return 'فليك (Flake)';
    if (lower.contains('توك') || lower.contains('tuc')) return 'توك (TUC)';
    if (lower.contains('ترايدنت') || lower.contains('trident')) return 'ترايدنت (Trident)';
    if (lower.contains('كلورتس') || lower.contains('كلتس') || lower.contains('clorets')) return 'كلورتس (Clorets)';
    if (lower.contains('هولز') || lower.contains('halls')) return 'هولز (Halls)';
    if (lower.contains('تانج') || lower.contains('tang')) return 'تانج (Tang)';
    if (lower.contains('كادبوري') || lower.contains('كدبوري') || lower.contains('cadbury')) return 'كادبوري (Cadbury)';

    return slug;
  }

  static String _inferCategory(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('شامبو') || lower.contains('بلسم') || lower.contains('سيروم') || lower.contains('حمام كريم')) return 'العناية بالشعر (Haircare)';
    if (lower.contains('اسبراي') || lower.contains('رول') || lower.contains('مزيل عرق') || lower.contains('ستيك')) return 'مزيلات العرق (Deodorants)';
    if (lower.contains('معجون') || lower.contains('فرشاة') || lower.contains('اسنان')) return 'العناية بالفم والأسنان (Oral Care)';
    if (lower.contains('صابون') || lower.contains('شاور') || lower.contains('لوشن') || lower.contains('كريم')) return 'العناية بالبشرة والجسم (Skincare)';
    if (lower.contains('منظف') || lower.contains('منعم') || lower.contains('مسحوق')) return 'المنظفات المنزلية (Home Care)';
    if (lower.contains('شاي') || lower.contains('شوربة') || lower.contains('مرقة')) return 'الأغذية والمشروبات (Foods)';
    if (lower.contains('شوكولات') || lower.contains('شيكولات') || lower.contains('chocolate') || lower.contains('بسكويت') || lower.contains('ويفر') || lower.contains('علك') || lower.contains('لبان')) return 'الحلويات والشوكولاتة (Confectionery)';
    return 'عام (General)';
  }

  static String _cleanCanonicalName(String raw) {
    return raw
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'(\d+)\s*(ملى|مل|جرام|جم|لتر)'), r'$1 $2')
        .trim();
  }

  static String _extractUnitSize(String name) {
    final match = RegExp(r'(\d+\s*(?:ملى|مل|جرام|جم|لتر|كجم|kg|g|ml|l))\b', caseSensitive: false).firstMatch(name);
    return match?.group(1) ?? '';
  }

  static String _normalizeForComparison(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\-_\/]+'), ' ')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');
  }

  static String _cleanJsonString(String raw) {
    String text = raw.trim();
    if (text.startsWith('```json')) {
      text = text.substring(7);
    } else if (text.startsWith('```')) {
      text = text.substring(3);
    }
    if (text.endsWith('```')) {
      text = text.substring(0, text.length - 3);
    }
    return text.trim();
  }
}

/// Evaluator enforcing the 5 strict criteria for new product discovery & catalog enrichment (AIR-72)
class DiscoveryCriteriaEvaluator {
  /// Criterion 1: Barcode must be 8 to 14 English digits only
  static bool isValidRetailBarcode(String barcode) {
    final clean = barcode.trim().toEnglishDigits();
    if (clean.length < 8 || clean.length > 14) return false;
    return RegExp(r'^\d{8,14}$').hasMatch(clean);
  }

  /// Criterion 2: Frequency threshold (min 2 invoice occurrences or multi-chain)
  static bool meetsFrequencyThreshold(int frequency, List<String> retailChains) {
    return frequency >= 2 || retailChains.length >= 2;
  }

  /// Criterion 3: Ban generic, non-retail, or service lines
  static bool isGenericOrServiceItem(String name) {
    final trimmed = name.trim();
    if (trimmed.length <= 2) return true;
    if (RegExp(r'^[\d\s\-_.,/()#*]+$').hasMatch(trimmed)) return true;

    final lower = normalizeForComparison(trimmed);
    const genericTokens = [
      'كيس', 'اكياس', 'شنطه', 'شنطة', 'bag', 'plastic',
      'خدمه توصيل', 'خدمة توصيل', 'توصيل', 'دليفري', 'delivery',
      'اكراميه', 'إكرامية', 'بقشيش', 'tip',
      'خصم', 'مرتجع', 'تسوية', 'استرداد', 'refund', 'discount', 'بونص', 'voucher',
      'ضريبه', 'ضريبة', 'دمغه', 'دمغة', 'رسوم', 'مصاريف',
      'صنف عام', 'عام', 'مبيعات متنوعه', 'مبيعات متنوعة', 'بضاعه', 'بضاعة',
      'خدمات', 'خدمه', 'خدمة', 'ميزان', 'وزن', 'باركود غير معرف', 'توالف', 'هالك',
    ];

    for (final t in genericTokens) {
      if (lower == t || lower.startsWith('$t ') || lower.endsWith(' $t') || lower.contains(' $t ')) {
        return true;
      }
    }
    return false;
  }

  /// Criterion 4: Price sanity check (positive, within real retail FMCG range)
  static bool hasValidPrice(double price) {
    return price >= 1.0 && price <= 15000.0;
  }

  /// Criterion 5: Brand & Company Whitelist
  static bool isProbableCompanyProduct(String name, String slug) {
    final lower = normalizeForComparison(name);
    final cleanSlug = slug.toLowerCase();

    // Unilever Portfolio (doc_id: 512)
    if (cleanSlug.contains('unilever') || cleanSlug.contains('يونيليفر') || cleanSlug == '512') {
      const unileverBrands = [
        'تريزيمي', 'تريزمي', 'tresemme',
        'كلير', 'clear',
        'ريكسونا', 'rexona',
        'اكس', 'أكس', 'axe',
        'دوف', 'dove',
        'صنسيلك', 'صنسلك', 'sunsilk',
        'سيجنال', 'signal',
        'لايفبوي', 'lifebuoy',
        'لوكس', 'lux',
        'كومفورت', 'comfort',
        'ليبتون', 'lipton',
        'كنور', 'knorr',
        'فازلين', 'vaseline',
        'فير اند لفلي', 'جلو اند لفلي', 'glow & lovely',
      ];
      return unileverBrands.any((b) => lower.contains(b));
    }

    // Cadbury / Mondelez Portfolio (doc_id: 4)
    if (cleanSlug.contains('cadbury') || cleanSlug.contains('كادبري') || cleanSlug.contains('كدبري') ||
        cleanSlug.contains('mondelez') || cleanSlug.contains('مونديليز') || cleanSlug == '4') {
      const mondelezBrands = [
        'كادبوري', 'كدبوري', 'cadbury',
        'ديري ميلك', 'ديرى ميلك', 'dairy milk',
        'مورو', 'moro',
        'بابلي', 'بابلى', 'bubbly',
        'اوريو', 'أوريو', 'oreo',
        'بوريو',
        'ماندولين', 'مندولين', 'mandolin',
        'فليك', 'flake',
        'سي دي ام', 'سى دى ام', 'cdm',
        'توك', 'tuc',
        'ترايدنت', 'trident',
        'كلورتس', 'كلتس', 'clorets',
        'هولز', 'halls',
        'تانج', 'tang',
        'بسكويت وي', 'ويفر وي', 'وي',
        'مارفلوس', 'marvellous',
      ];
      return mondelezBrands.any((b) => lower.contains(b));
    }

    // El Doha (doc_id: 1434)
    if (cleanSlug.contains('doha') || cleanSlug.contains('الضحى') || cleanSlug.contains('الضحي') || cleanSlug == '1434') {
      return lower.contains('ضحى') || lower.contains('الضحى') || lower.contains('الضحي') || lower.contains('doha');
    }

    // Adco (doc_id: 40)
    if (cleanSlug.contains('adco') || cleanSlug.contains('ادكو') || cleanSlug == '40') {
      return lower.contains('ادكو') || lower.contains('اوكسي') || lower.contains('اوكسى') || lower.contains('oxy') || lower.contains('adco');
    }

    // Almarai (doc_id: 2452)
    if (cleanSlug.contains('almarai') || cleanSlug.contains('المراعي') || cleanSlug == '2452') {
      return lower.contains('المراعي') || lower.contains('المراعى') || lower.contains('almarai');
    }

    // Heinz (doc_id: 2884)
    if (cleanSlug.contains('heinz') || cleanSlug.contains('هاينز') || cleanSlug == '2884') {
      return lower.contains('هاينز') || lower.contains('heinz');
    }

    // Fine (doc_id: 464)
    if (cleanSlug.contains('fine') || cleanSlug.contains('فاين') || cleanSlug == '464') {
      return lower.contains('فاين') || lower.contains('fine');
    }

    // Rich Bake (doc_id: 4543)
    if (cleanSlug.contains('rich_bake') || cleanSlug.contains('ريتش بيك') || cleanSlug == '4543') {
      return lower.contains('ريتش بيك') || lower.contains('ريتش') || lower.contains('rich');
    }

    // Arma (doc_id: 31)
    if (cleanSlug.contains('arma') || cleanSlug.contains('ارما') || cleanSlug == '31') {
      return lower.contains('ارما') || lower.contains('كريستال') || lower.contains('الهانم') || lower.contains('حلوة') || lower.contains('arma');
    }

    // Default: Check if the product name explicitly contains the company name / slug token
    final cleanSlugToken = cleanSlug.replaceAll(RegExp(r'[^a-zA-Z\u0600-\u06FF]'), '');
    if (cleanSlugToken.length >= 3 && lower.contains(cleanSlugToken)) {
      return true;
    }

    return false;
  }

  /// Comprehensive evaluator of all 5 criteria
  static DiscoveryCriteriaResult evaluateProduct({
    required String productName,
    required String barcode,
    required double price,
    required int frequency,
    required List<String> retailChains,
    required String companySlug,
    String brand = '',
    bool enforceFrequency = true,
  }) {
    final bool validBarcode = isValidRetailBarcode(barcode);
    final bool meetsFreq = !enforceFrequency || meetsFrequencyThreshold(frequency, retailChains);
    final bool notGeneric = !isGenericOrServiceItem(productName);
    final bool validPrice = hasValidPrice(price);
    final bool matchesBrand = isProbableCompanyProduct(productName, companySlug) ||
        (brand.isNotEmpty && isProbableCompanyProduct(brand, companySlug));

    final List<String> failures = [];
    if (!validBarcode) failures.add('الباركود مفقود أو غير مطابق (8-14 رقم)');
    if (!meetsFreq) failures.add('تكرار الرصد أقل من مرتين');
    if (!notGeneric) failures.add('صنف عام أو خدمة غير سلعية');
    if (!validPrice) failures.add('السعر غير منطقي أو 0.0 ج.م');
    if (!matchesBrand) failures.add('لا يطابق العلامات المعتمدة للشركة');

    final bool isEligible = validBarcode && meetsFreq && notGeneric && validPrice && matchesBrand;

    return DiscoveryCriteriaResult(
      isEligible: isEligible,
      rejectionReason: failures.join(' • '),
      hasValidBarcode: validBarcode,
      meetsFrequency: meetsFreq,
      isNotGeneric: notGeneric,
      hasValidPrice: validPrice,
      matchesCompanyBrand: matchesBrand,
    );
  }

  static String normalizeForComparison(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\-_\/]+'), ' ')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');
  }
}

class _RawCandidateGroup {
  String name;
  String barcode;
  List<double> prices;
  int frequency;
  bool isTarget;

  _RawCandidateGroup({
    required this.name,
    required this.barcode,
    required this.prices,
    required this.frequency,
    required this.isTarget,
  });
}
