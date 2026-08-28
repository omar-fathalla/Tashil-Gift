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
        if (!p.isTargetCompany && !_isProbableCompanyProduct(p.name, slug)) continue;

        final rawName = p.name.trim();
        if (rawName.isEmpty) continue;

        final rawBarcode = p.barcode.trim().toEnglishDigits();
        final normName = _normalizeForComparison(rawName);

        // If already in catalog with barcode, auto-register raw POS string as chain alias
        if (rawBarcode.isNotEmpty && registeredBarcodes.contains(rawBarcode)) {
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
            _isProbableCompanyProduct(rawName, slug) &&
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

            tx.update(docRef, {
              'invoiceFrequency': currentFreq + 1,
              'retailChains': chains.toList(),
              'observedPrices': currentPrices.take(10).toList(),
              'averagePrice': avgPrice,
              'latestPrice': p.price > 0 ? p.price : (data['latestPrice'] ?? 0.0),
              'barcode': (rawBarcode.isNotEmpty) ? rawBarcode : (data['barcode'] ?? ''),
              'status': isHighConfidence ? 'auto_approved' : (data['status'] ?? 'pending'),
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
              'status': isHighConfidence ? 'auto_approved' : 'pending',
              'confidenceScore': isHighConfidence ? 0.99 : 0.96,
              'relevanceReason': isHighConfidence
                  ? 'تم اعتماده وحقنه تلقائياً في كتالوج الشركة (AIR-28)'
                  : 'تم رصده في فاتورة معتمدة لشركة $companyName',
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
  Future<void> rejectDiscoveredDocuments(List<String> docIds) async {
    if (docIds.isEmpty) return;
    final batch = _effectiveFirestore.batch();
    for (final id in docIds) {
      batch.update(_inboxCollection.doc(id), {
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
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

  static bool _isProbableCompanyProduct(String name, String slug) {
    final lower = name.toLowerCase();
    if (slug.contains('unilever') || slug.contains('يونيليفر')) {
      return lower.contains('تريزيمي') ||
          lower.contains('تريزمي') ||
          lower.contains('tresemme') ||
          lower.contains('كلير') ||
          lower.contains('clear') ||
          lower.contains('ريكسونا') ||
          lower.contains('rexona') ||
          lower.contains('أكس') ||
          lower.contains('اكس') ||
          lower.contains('axe') ||
          lower.contains('دوف') ||
          lower.contains('dove') ||
          lower.contains('صنسيلك') ||
          lower.contains('صنسلك') ||
          lower.contains('sunsilk') ||
          lower.contains('سيجنال') ||
          lower.contains('signal') ||
          lower.contains('لايفبوي') ||
          lower.contains('لوكس') ||
          lower.contains('lux') ||
          lower.contains('كومفورت') ||
          lower.contains('ليبتون') ||
          lower.contains('كنور');
    }
    return false;
  }

  static String _inferSubBrand(String name, String slug) {
    final lower = name.toLowerCase();
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
