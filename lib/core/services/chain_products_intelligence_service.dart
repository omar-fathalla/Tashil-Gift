import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/admin/domain/chain_product_model.dart';
import 'firebase_service.dart';

final chainProductsIntelligenceServiceProvider = Provider<ChainProductsIntelligenceService>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return ChainProductsIntelligenceService(firestore: firestore);
});

final chainProductsStreamProvider = StreamProvider<List<ChainProductItem>>((ref) {
  final service = ref.watch(chainProductsIntelligenceServiceProvider);
  return service.streamChainProducts();
});

class ChainProductsIntelligenceService {
  final FirebaseFirestore? _firestore;

  ChainProductsIntelligenceService({FirebaseFirestore? firestore}) : _firestore = firestore;

  /// Real-time stream of all aggregated chain products with complete price intelligence
  Stream<List<ChainProductItem>> streamChainProducts({String? lockedCompanySlug}) {
    if (_firestore == null) {
      return Stream.value([]);
    }

    Query<Map<String, dynamic>> query = _firestore.collection('receipts_transactions');
    if (lockedCompanySlug != null && lockedCompanySlug.trim().isNotEmpty) {
      query = query.where('companySlug', isEqualTo: lockedCompanySlug.trim());
    }

    return query.snapshots().map((snapshot) {
      return aggregateProductsFromReceipts(snapshot.docs);
    });
  }

  /// Pure function to aggregate raw receipt documents into rich ChainProductItem models
  static List<ChainProductItem> aggregateProductsFromReceipts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final Map<String, List<_RawProductOccurrence>> occurrencesBySku = {};

    for (final doc in docs) {
      final data = doc.data();
      final String receiptNumber = data['receipt_number']?.toString() ?? doc.id;
      final String receiptDate = data['receipt_date']?.toString() ?? '';
      
      final String rawStoreChain = (data['store_chain_detected']?.toString().trim().isNotEmpty == true)
          ? data['store_chain_detected'].toString().trim()
          : (data['retail_chain_name']?.toString().trim() ?? 'غير محدد');

      // Canonical Enterprise Chain Name (e.g. "أسواق فتح الله", "جملة ماركت")
      final String canonicalChain = normalizeRetailChain(rawStoreChain);
      final String branchName = data['branch_detected']?.toString().trim() ?? '';
      final String imageUrl = data['image_url']?.toString() ?? '';
      final String companySlug = data['companySlug']?.toString() ?? '';
      
      DateTime? timestamp;
      final rawTs = data['timestamp'];
      if (rawTs is Timestamp) {
        timestamp = rawTs.toDate();
      } else if (rawTs is String) {
        timestamp = DateTime.tryParse(rawTs);
      }

      final rawProducts = data['extracted_products'] as List<dynamic>? ?? [];
      for (final p in rawProducts) {
        if (p is! Map) continue;
        final name = p['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;

        int quantity = (p['quantity'] as num?)?.toInt() ?? 1;
        if (quantity <= 0) quantity = 1;

        double price = (p['price'] as num?)?.toDouble() ?? 0.0;
        final String barcode = p['barcode']?.toString().trim() ?? '';
        double? originalPrice = (p['originalPrice'] as num?)?.toDouble();
        double discountAmount = (p['discountAmount'] as num?)?.toDouble() ?? 0.0;
        final double discountPercent = (p['discountPercent'] as num?)?.toDouble() ?? 0.0;
        final double? totalLinePrice = (p['totalPrice'] as num?)?.toDouble() ?? (p['totalLinePrice'] as num?)?.toDouble();
        final bool isTargetCompany = p['isTargetCompany'] == true;

        // Auto-heal line total vs unit price math anomalies:
        if (quantity > 1) {
          // If price looks like line total (e.g. 198 or 230 for 2 units where original unit price was 115)
          if (originalPrice != null && originalPrice > 0) {
            if (price >= originalPrice * 1.5) {
              price = price / quantity;
            }
            if (originalPrice >= 1.8 * price && originalPrice > 50) {
              originalPrice = originalPrice / quantity;
            }
          } else if (totalLinePrice != null && totalLinePrice > 0 && (price == totalLinePrice || price >= totalLinePrice * 0.95)) {
            price = price / quantity;
          }

          if (discountAmount >= price && discountAmount > 0) {
            discountAmount = discountAmount / quantity;
          }
        }

        if (originalPrice != null && originalPrice <= 0) {
          originalPrice = null;
        }

        // Distinct key: Prefer non-empty barcode, otherwise normalized name
        final skuKey = barcode.isNotEmpty && barcode.length >= 4 ? barcode : normalizeName(name);

        final occurrence = _RawProductOccurrence(
          skuKey: skuKey,
          name: name,
          barcode: barcode,
          price: price,
          originalPrice: originalPrice,
          discountAmount: discountAmount,
          discountPercent: discountPercent,
          quantity: quantity,
          isTargetCompany: isTargetCompany,
          receiptNumber: receiptNumber,
          receiptDate: receiptDate,
          timestamp: timestamp,
          storeChain: canonicalChain,
          branchName: branchName,
          receiptImageUrl: imageUrl,
          companySlug: companySlug,
        );

        occurrencesBySku.putIfAbsent(skuKey, () => []).add(occurrence);
      }
    }

    // Now aggregate each SKU group into a ChainProductItem
    final List<ChainProductItem> aggregated = [];

    for (final entry in occurrencesBySku.entries) {
      final occurrences = entry.value;
      if (occurrences.isEmpty) continue;

      // Sort occurrences chronologically (newest first)
      occurrences.sort((a, b) {
        final tsA = a.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tsB = b.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
        return tsB.compareTo(tsA);
      });

      final primaryName = occurrences.first.name;
      final barcode = occurrences.firstWhere((o) => o.barcode.isNotEmpty, orElse: () => occurrences.first).barcode;
      final companySlug = occurrences.firstWhere((o) => o.companySlug.isNotEmpty, orElse: () => occurrences.first).companySlug;

      final Map<String, double> latestPricesByChain = {};
      final Map<String, double> latestRegularPricesByChain = {};
      final Map<String, String> latestDatesByChain = {};
      final Map<String, ProductPriceHistoryEntry> latestEntryByChain = {};
      final Map<String, ChainPricingSummary> chainSummaries = {};
      final List<ProductPriceHistoryEntry> priceHistory = [];
      int totalQuantitySold = 0;

      // Group occurrences by enterprise chain for deep chain-level analysis
      final Map<String, List<_RawProductOccurrence>> chainGroupedOccurrences = {};

      for (final occ in occurrences) {
        totalQuantitySold += occ.quantity;

        final historyEntry = ProductPriceHistoryEntry(
          price: occ.price,
          originalPrice: occ.originalPrice,
          discountAmount: occ.discountAmount,
          discountPercent: occ.discountPercent,
          receiptDate: occ.receiptDate,
          timestamp: occ.timestamp,
          receiptNumber: occ.receiptNumber,
          storeChain: occ.storeChain,
          branchName: occ.branchName,
          receiptImageUrl: occ.receiptImageUrl,
          companySlug: occ.companySlug,
          quantity: occ.quantity,
        );

        priceHistory.add(historyEntry);
        chainGroupedOccurrences.putIfAbsent(occ.storeChain, () => []).add(occ);

        // Record latest per chain (since list is sorted newest first, first one seen for chain is latest)
        final chain = occ.storeChain.trim();
        if (chain.isNotEmpty && !latestPricesByChain.containsKey(chain)) {
          latestPricesByChain[chain] = occ.price;
          latestRegularPricesByChain[chain] = occ.originalPrice ?? occ.price;
          latestDatesByChain[chain] = occ.receiptDate;
          latestEntryByChain[chain] = historyEntry;
        }
      }

      // Build structured ChainPricingSummary for each enterprise retail chain
      for (final cEntry in chainGroupedOccurrences.entries) {
        final chainName = cEntry.key;
        final cOccs = cEntry.value;
        final latestOcc = cOccs.first;

        int cTotalScans = cOccs.length;
        int cTotalQty = cOccs.fold<int>(0, (acc, o) => acc + o.quantity);
        final Set<String> cBranches = cOccs.map((o) => o.branchName).where((b) => b.isNotEmpty).toSet();

        final regularPrice = latestOcc.originalPrice ?? (latestOcc.discountAmount > 0 ? latestOcc.price + latestOcc.discountAmount : latestOcc.price);
        final netPrice = latestOcc.price;

        chainSummaries[chainName] = ChainPricingSummary(
          chainName: chainName,
          regularUnitPrice: regularPrice,
          netUnitPrice: netPrice,
          unitDiscount: latestOcc.discountAmount,
          discountPercent: latestOcc.discountPercent,
          isOnPromotion: latestOcc.discountAmount > 0 || (latestOcc.originalPrice != null && latestOcc.originalPrice! > latestOcc.price),
          lastReceiptDate: latestOcc.receiptDate,
          totalScans: cTotalScans,
          totalQuantity: cTotalQty,
          branchesObserved: cBranches.toList(),
        );
      }

      // Infer brand and category from product name
      final String inferredBrand = inferBrand(primaryName);
      final String inferredCategory = inferCategory(primaryName);

      aggregated.add(
        ChainProductItem(
          id: entry.key,
          name: primaryName,
          barcode: barcode,
          companySlug: companySlug,
          brand: inferredBrand,
          category: inferredCategory,
          latestPricesByChain: latestPricesByChain,
          latestRegularPricesByChain: latestRegularPricesByChain,
          latestDatesByChain: latestDatesByChain,
          chainSummaries: chainSummaries,
          latestEntryByChain: latestEntryByChain,
          priceHistory: priceHistory,
          totalScansCount: occurrences.length,
          totalQuantitySold: totalQuantitySold,
        ),
      );
    }

    // Sort products by total scans count descending
    aggregated.sort((a, b) => b.totalScansCount.compareTo(a.totalScansCount));

    return aggregated;
  }

  /// Normalizes store chain variants into standard Enterprise Retail Chains
  static String normalizeRetailChain(String rawChain) {
    final s = rawChain.toLowerCase().trim();
    if (s.isEmpty) return 'سلسلة تجارية عامة';
    if (s.contains('فتح الله') || s.contains('fathalla')) return 'أسواق فتح الله';
    if (s.contains('جملة ماركت') || s.contains('gomla')) return 'جملة ماركت';
    if (s.contains('بيت الجملة') || s.contains('beit el gomla') || s.contains('beit elgomla')) return 'بيت الجملة';
    if (s.contains('كارفور') || s.contains('carrefour')) return 'كارفور';
    if (s.contains('خير زمان') || s.contains('kheir zaman')) return 'خير زمان';
    if (s.contains('سبينس') || s.contains('spinneys')) return 'سبينس';
    if (s.contains('مترو') || s.contains('metro')) return 'مترو ماركت';
    if (s.contains('كازيون') || s.contains('kazyon')) return 'كازيون';
    if (s.contains('بيم') || s.contains('bim')) return 'بيم';
    if (s.contains('سعودي') || s.contains('seoudi')) return 'سعودي ماركت';
    if (s.contains('لولو') || s.contains('lulu')) return 'لولو هايبرماركت';
    if (s.contains('رجب') || s.contains('ragab')) return 'أولاد رجب';
    if (s.contains('محلاوي') || s.contains('mahallawy')) return 'المحلاوي';
    if (s.contains('باندا') || s.contains('panda')) return 'هايبر بنده';
    if (s.contains('الراية') || s.contains('raya')) return 'أسواق الراية';
    return rawChain.trim();
  }

  static String normalizeName(String s) {
    var str = s.toLowerCase().trim();
    str = str.replaceAll(RegExp(r'[أإآ]'), 'ا');
    str = str.replaceAll('ى', 'ي');
    str = str.replaceAll('ة', 'ه');
    str = str.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), ' ');
    return str.replaceAll(RegExp(r'\s+'), ' ');
  }

  static String inferBrand(String name) {
    final norm = normalizeName(name);
    if (norm.contains('اكس') || norm.contains('axe')) return 'Axe';
    if (norm.contains('ريكسونا') || norm.contains('rexona')) return 'Rexona';
    if (norm.contains('دوف') || norm.contains('dove')) return 'Dove';
    if (norm.contains('كلير') || norm.contains('clear')) return 'Clear';
    if (norm.contains('تريزيمي') || norm.contains('tresemme') || norm.contains('tresemm')) return 'TRESemmé';
    if (norm.contains('صن سيلك') || norm.contains('صانسيلك') || norm.contains('sunsilk')) return 'Sunsilk';
    if (norm.contains('لوكس') || norm.contains('lux')) return 'Lux';
    if (norm.contains('لايف بوي') || norm.contains('lifebuoy')) return 'Lifebuoy';
    if (norm.contains('سيجنال') || norm.contains('signal') || norm.contains('كلوس اب') || norm.contains('closeup')) return 'Signal';
    if (norm.contains('كاماي') || norm.contains('camay')) return 'Camay';
    if (norm.contains('اوكسي') || norm.contains('oxi') || norm.contains('oxy')) return 'Oxi';
    if (norm.contains('اريال') || norm.contains('ariel')) return 'Ariel';
    if (norm.contains('برسيل') || norm.contains('persil')) return 'Persil';
    if (norm.contains('فيري') || norm.contains('fairy')) return 'Fairy';
    return 'عام';
  }

  static String inferCategory(String name) {
    final norm = normalizeName(name);
    if (norm.contains('اسبراي') || norm.contains('سبراي') || norm.contains('رول') || norm.contains('مزيل') || norm.contains('spray') || norm.contains('roll')) {
      return 'مزيلات عرق';
    }
    if (norm.contains('شامبو') || norm.contains('بلسم') || norm.contains('سيروم') || norm.contains('shampoo') || norm.contains('conditioner')) {
      return 'العناية بالشعر';
    }
    if (norm.contains('صابون') || norm.contains('صابونة') || norm.contains('شاور') || norm.contains('غسول') || norm.contains('soap') || norm.contains('wash')) {
      return 'العناية بالجسم';
    }
    if (norm.contains('معجون') || norm.contains('اسنان') || norm.contains('فرشاة') || norm.contains('paste')) {
      return 'العناية بالفم والأسنان';
    }
    if (norm.contains('منظف') || norm.contains('مسحوق') || norm.contains('جل') || norm.contains('اوكسي') || norm.contains('اريال')) {
      return 'المنظفات المنزلية';
    }
    return 'منتجات استهلاكية';
  }

  /// Syncs / Persists aggregated products into the `chain_products_catalog` Firestore collection
  Future<void> syncAggregatedCatalogToFirestore(List<ChainProductItem> products) async {
    if (_firestore == null || products.isEmpty) return;
    final batch = _firestore.batch();
    for (final item in products) {
      final docRef = _firestore.collection('chain_products_catalog').doc(item.id);
      batch.set(docRef, item.toJson(), SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// Re-analyzes all historical receipts in Firestore and heals unit prices, discounts, and chain names
  Future<int> reAnalyzeAndHealAllReceiptsInFirestore() async {
    if (_firestore == null) return 0;

    final snapshot = await _firestore.collection('receipts_transactions').get();
    final batch = _firestore.batch();
    int updatedCount = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      bool modified = false;

      // 1. Normalize chain name
      final String rawChain = (data['store_chain_detected']?.toString().trim().isNotEmpty == true)
          ? data['store_chain_detected'].toString().trim()
          : (data['retail_chain_name']?.toString().trim() ?? '');

      if (rawChain.isNotEmpty) {
        final String canonicalChain = normalizeRetailChain(rawChain);
        if (data['store_chain_detected'] != canonicalChain) {
          data['store_chain_detected'] = canonicalChain;
          modified = true;
        }
      }

      // 2. Normalize and heal products
      final rawProducts = data['extracted_products'] as List<dynamic>? ?? [];
      final List<Map<String, dynamic>> sanitizedProducts = [];

      for (final p in rawProducts) {
        if (p is! Map) continue;
        final map = Map<String, dynamic>.from(p);

        int quantity = (map['quantity'] as num?)?.toInt() ?? 1;
        if (quantity <= 0) quantity = 1;

        double price = (map['price'] as num?)?.toDouble() ?? 0.0;
        double? originalPrice = (map['originalPrice'] as num?)?.toDouble();
        double discountAmount = (map['discountAmount'] as num?)?.toDouble() ?? 0.0;
        final double? totalLinePrice = (map['totalPrice'] as num?)?.toDouble() ?? (map['totalLinePrice'] as num?)?.toDouble();

        if (quantity > 1) {
          if (originalPrice != null && originalPrice > 0) {
            if ((price + discountAmount - originalPrice).abs() < 1.5 && price > 50) {
              price = price / quantity;
              originalPrice = originalPrice / quantity;
              if (discountAmount > 0) discountAmount = discountAmount / quantity;
              modified = true;
            } else if (price >= originalPrice * 1.5) {
              price = price / quantity;
              modified = true;
            } else if (originalPrice >= 1.8 * price && originalPrice > 50) {
              originalPrice = originalPrice / quantity;
              modified = true;
            }
          } else if (totalLinePrice != null && totalLinePrice > 0 && (price == totalLinePrice || price >= totalLinePrice * 0.95)) {
            price = price / quantity;
            modified = true;
          }

          if (discountAmount >= price && discountAmount > 0) {
            discountAmount = discountAmount / quantity;
            modified = true;
          }
        }

        map['price'] = price;
        map['quantity'] = quantity;
        if (originalPrice != null && originalPrice > 0) {
          map['originalPrice'] = originalPrice;
        }
        map['discountAmount'] = discountAmount;
        map['totalPrice'] = price * quantity;

        sanitizedProducts.add(map);
      }

      data['extracted_products'] = sanitizedProducts;

      if (modified) {
        batch.set(doc.reference, data, SetOptions(merge: true));
        updatedCount++;
      }
    }

    if (updatedCount > 0) {
      await batch.commit();
    }

    final aggregated = aggregateProductsFromReceipts(snapshot.docs);
    await syncAggregatedCatalogToFirestore(aggregated);

    return updatedCount;
  }
}

class _RawProductOccurrence {
  final String skuKey;
  final String name;
  final String barcode;
  final double price;
  final double? originalPrice;
  final double discountAmount;
  final double discountPercent;
  final int quantity;
  final bool isTargetCompany;
  final String receiptNumber;
  final String receiptDate;
  final DateTime? timestamp;
  final String storeChain;
  final String branchName;
  final String receiptImageUrl;
  final String companySlug;

  _RawProductOccurrence({
    required this.skuKey,
    required this.name,
    required this.barcode,
    required this.price,
    this.originalPrice,
    required this.discountAmount,
    required this.discountPercent,
    required this.quantity,
    required this.isTargetCompany,
    required this.receiptNumber,
    required this.receiptDate,
    this.timestamp,
    required this.storeChain,
    required this.branchName,
    required this.receiptImageUrl,
    required this.companySlug,
  });
}
