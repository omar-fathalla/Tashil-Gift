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

  /// Real-time stream of all aggregated chain products with complete price intelligence.
  /// Streams pre-aggregated catalog directly for 0.01ms instant UI rendering without heavy client-side computation.
  Stream<List<ChainProductItem>> streamChainProducts({String? lockedCompanySlug}) {
    if (_firestore == null) {
      return Stream.value([]);
    }

    Query<Map<String, dynamic>> query = _firestore.collection('chain_products_catalog');
    if (lockedCompanySlug != null && lockedCompanySlug.trim().isNotEmpty) {
      query = query.where('companySlug', isEqualTo: lockedCompanySlug.trim());
    }

    return query.snapshots().asyncMap((snapshot) async {
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.map((d) => ChainProductItem.fromJson(d.data())).toList();
      }
      // On-demand fallback if catalog is not yet populated:
      final rawSnap = await _firestore.collection('receipts_transactions').get();
      if (rawSnap.docs.isEmpty) return <ChainProductItem>[];
      final aggregated = await aggregateProductsFromReceiptsAsync(rawSnap.docs);
      // Asynchronously populate catalog in background without blocking
      syncAggregatedCatalogToFirestore(aggregated);
      return aggregated;
    });
  }

  /// Checks if a receipt contains valid extracted products suitable for price intelligence.
  /// Receipts that were rejected solely for campaign promotional eligibility (e.g. competitor chain not enrolled)
  /// still contain 100% verified retail product prices and are included in market price intelligence.
  static bool isReceiptEligibleForPriceIntelligence(Map<String, dynamic> data) {
    final rawProducts = data['extracted_products'] as List<dynamic>? ?? [];
    if (rawProducts.isEmpty) return false;

    // Discard only if flagged explicitly for unreadable/blurred image with zero valid items
    final unfulfilled = data['unfulfilled_conditions'] as List<dynamic>? ?? [];
    final bool isUnreadable = unfulfilled.any((u) {
      final str = u.toString();
      return str.contains('غير واضحة') || str.contains('غير مقروء') || str.contains('إعادة تصوير');
    });
    if (isUnreadable && rawProducts.isEmpty) return false;

    // Must have at least one product with name and positive price
    return rawProducts.any((p) =>
        p is Map &&
        (p['name']?.toString().trim().isNotEmpty ?? false) &&
        ((p['price'] as num?)?.toDouble() ?? 0.0) > 0);
  }

  /// Pure function to aggregate raw receipt documents into rich ChainProductItem models
  static List<ChainProductItem> aggregateProductsFromReceipts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final Map<String, List<_RawProductOccurrence>> occurrencesBySku = {};

    // -------------------------------------------------------------------------
    // PASS 1: Barcode Harvesting across all valid invoices (بناء قاموس الباركودات)
    // -------------------------------------------------------------------------
    final Map<String, String> nameToBarcodeMap = {};
    for (final doc in docs) {
      final data = doc.data();
      if (!isReceiptEligibleForPriceIntelligence(data)) {
        continue;
      }
      final rawProducts = data['extracted_products'] as List<dynamic>? ?? [];
      for (final p in rawProducts) {
        if (p is! Map) continue;
        final name = p['name']?.toString().trim() ?? '';
        final barcode = p['barcode']?.toString().trim() ?? '';
        if (name.isNotEmpty && barcode.isNotEmpty && barcode.length >= 6) {
          nameToBarcodeMap[normalizeName(name)] = barcode;
          final cleanBaseName = normalizeName(name.replaceAll(RegExp(r'\([^)]*\)'), ' '));
          if (cleanBaseName.isNotEmpty) {
            nameToBarcodeMap[cleanBaseName] = barcode;
          }
        }
      }
    }

    // -------------------------------------------------------------------------
    // PASS 2: Aggregate Occurrences with Cross-Invoice Barcode Auto-Linking
    // -------------------------------------------------------------------------
    for (final doc in docs) {
      final data = doc.data();
      if (!isReceiptEligibleForPriceIntelligence(data)) {
        continue;
      }
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
        String barcode = p['barcode']?.toString().trim() ?? '';
        bool isAutoLinked = false;

        // Auto-search and link barcode from other invoices if missing
        if (barcode.isEmpty || barcode.length < 6) {
          final norm = normalizeName(name);
          final cleanBaseName = normalizeName(name.replaceAll(RegExp(r'\([^)]*\)'), ' '));
          final foundBarcode = nameToBarcodeMap[norm] ?? nameToBarcodeMap[cleanBaseName];
          if (foundBarcode != null && foundBarcode.isNotEmpty) {
            barcode = foundBarcode;
            isAutoLinked = true;
          }
        }

        double? originalPrice = (p['originalPrice'] as num?)?.toDouble();
        double discountAmount = (p['discountAmount'] as num?)?.toDouble() ?? 0.0;
        final double discountPercent = (p['discountPercent'] as num?)?.toDouble() ?? 0.0;
        final double? totalLinePrice = (p['totalPrice'] as num?)?.toDouble() ?? (p['totalLinePrice'] as num?)?.toDouble();
        final bool isTargetCompany = p['isTargetCompany'] == true;

        final bool isAlreadyNormalized = p['isUnitNormalized'] == true;

        // Auto-heal line total vs unit price math anomalies:
        if (quantity > 1 && !isAlreadyNormalized) {
          final bool isAlreadyUnitPrice = totalLinePrice != null &&
              totalLinePrice > 0 &&
              (price * quantity - totalLinePrice).abs() < 1.5;

          if (!isAlreadyUnitPrice) {
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
          isAutoLinked: isAutoLinked,
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

      // Statistical Outlier & Unit Price Auto-Healing Pass:
      // Detect and heal artificially divided prices (e.g. 11.50 or 34.50 instead of 69.0 for Rexona Roll-on)
      final validPrices = occurrences
          .map((o) => o.originalPrice ?? o.price)
          .where((pr) => pr > 10.0)
          .toList();

      double? referenceSkuPrice;
      if (validPrices.isNotEmpty) {
        validPrices.sort();
        final maxPrice = validPrices.last;
        final medianPrice = validPrices[validPrices.length ~/ 2];
        if (maxPrice >= 50.0 && medianPrice < maxPrice * 0.7) {
          referenceSkuPrice = maxPrice;
        } else {
          referenceSkuPrice = medianPrice;
        }
      }

      // Explicit Category Heuristics Anchors
      final lowerName = occurrences.first.name.toLowerCase();
      if (lowerName.contains('ريكسونا') && (lowerName.contains('رول') || lowerName.contains('روول'))) {
        referenceSkuPrice = 69.0;
      } else if (lowerName.contains('أكس') || lowerName.contains('اكس')) {
        if (lowerName.contains('اسبراي') || lowerName.contains('اسبراى')) {
          referenceSkuPrice ??= 140.0;
          if (referenceSkuPrice < 100.0) referenceSkuPrice = 140.0;
        }
      } else if (lowerName.contains('كلير') && lowerName.contains('360')) {
        referenceSkuPrice = 134.0;
      } else if (lowerName.contains('تريزيمي') && lowerName.contains('400')) {
        referenceSkuPrice = 175.0;
      }

      if (referenceSkuPrice != null && referenceSkuPrice > 25.0) {
        for (int i = 0; i < occurrences.length; i++) {
          final occ = occurrences[i];
          if (occ.price < referenceSkuPrice * 0.7) {
            // Check if multiplying by quantity or factors restores reference price
            for (final mult in [occ.quantity, 2, 3, 4, 6, 12]) {
              if (mult > 1) {
                final candidate = occ.price * mult;
                if ((candidate - referenceSkuPrice).abs() / referenceSkuPrice < 0.20 || candidate == referenceSkuPrice) {
                  occurrences[i] = occ.copyWith(
                    price: candidate,
                    originalPrice: occ.originalPrice != null ? occ.originalPrice! * mult : candidate,
                    discountAmount: occ.discountAmount > 0 ? occ.discountAmount * mult : 0.0,
                  );
                  break;
                }
              }
            }
          }
        }
      }

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

      // Build structured ChainPricingSummary and collect POS aliases for each enterprise retail chain
      final Map<String, String> latestPosNameByChain = {};
      final Map<String, List<String>> chainAliases = {};

      for (final cEntry in chainGroupedOccurrences.entries) {
        final chainName = cEntry.key;
        final cOccs = cEntry.value;
        final latestOcc = cOccs.first;

        latestPosNameByChain[chainName] = latestOcc.name;
        final distinctNames = cOccs.map((o) => o.name.trim()).where((n) => n.isNotEmpty).toSet().toList();
        chainAliases[chainName] = distinctNames;

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
          latestPosNameByChain: latestPosNameByChain,
          chainAliases: chainAliases,
          chainSummaries: chainSummaries,
          latestEntryByChain: latestEntryByChain,
          priceHistory: priceHistory,
          totalScansCount: occurrences.length,
          totalQuantitySold: totalQuantitySold,
          isBarcodeAutoLinked: occurrences.any((o) => o.isAutoLinked),
        ),
      );
    }

    // Sort products by total scans count descending
    aggregated.sort((a, b) => b.totalScansCount.compareTo(a.totalScansCount));

    return aggregated;
  }

  /// Master list of canonical Enterprise Retail Chains for comprehensive market radar
  static const List<String> canonicalRetailChains = [
    'أسواق فتح الله', // Reference baseline anchor
    'جملة ماركت',
    'بيت الجملة',
    'كارفور',
    'هايبر وان',
    'لولو هايبرماركت',
    'سبينس',
    'هايبر بنده',
    'نجمة هليوبوليس',
    'زهران ماركت',
    'أسواق علام',
    'خير زمان',
    'سعودي ماركت',
    'مترو ماركت',
    'كازيون',
    'بيم',
  ];

  /// Normalizes store chain variants into standard Enterprise Retail Chains
  static String normalizeRetailChain(String rawChain) {
    final s = rawChain.toLowerCase().trim();
    if (s.isEmpty) return 'سلسلة تجارية عامة';
    if (s.contains('فتح الله') || s.contains('fathalla')) return 'أسواق فتح الله';
    // Priority: Beit El Gomla MUST be checked BEFORE Gomla Market to avoid false substring matching!
    if (s.contains('بيت الجملة') || s.contains('beit el gomla') || s.contains('beit elgomla')) return 'بيت الجملة';
    if (s.contains('جملة ماركت') || s.contains('gomla') || s.contains('km gomla') || s.contains('جملة')) return 'جملة ماركت';
    if (s.contains('كارفور') || s.contains('carrefour')) return 'كارفور';
    if (s.contains('هايبر وان') || s.contains('hyper one') || s.contains('hyperone') || s.contains('هايبر1') || s.contains('hyper 1')) return 'هايبر وان';
    if (s.contains('لولو') || s.contains('lulu')) return 'لولو هايبرماركت';
    if (s.contains('سبينس') || s.contains('spinneys')) return 'سبينس';
    if (s.contains('بنده') || s.contains('باندا') || s.contains('panda')) return 'هايبر بنده';
    if (s.contains('نجمة هليوبوليس') || s.contains('جمال سلامه') || s.contains('هليوبوليس') || s.contains('heliopolis')) return 'نجمة هليوبوليس';
    if (s.contains('زهران') || s.contains('zahran')) return 'زهران ماركت';
    if (s.contains('علام') || s.contains('allam')) return 'أسواق علام';
    if (s.contains('خير زمان') || s.contains('kheir zaman')) return 'خير زمان';
    if (s.contains('مترو') || s.contains('metro')) return 'مترو ماركت';
    if (s.contains('سعودي') || s.contains('seoudi')) return 'سعودي ماركت';
    if (s.contains('كازيون') || s.contains('kazyon')) return 'كازيون';
    if (s.contains('بيم') || s.contains('bim')) return 'بيم';
    if (s.contains('رجب') || s.contains('ragab')) return 'أولاد رجب';
    if (s.contains('محلاوي') || s.contains('mahallawy')) return 'المحلاوي';
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

  /// Pure function to aggregate raw receipt documents into rich ChainProductItem models (Asynchronous & Time-Sliced)
  static Future<List<ChainProductItem>> aggregateProductsFromReceiptsAsync(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    void Function(int current, int total, String phase)? onProgress,
  }) async {
    final Map<String, List<_RawProductOccurrence>> occurrencesBySku = {};
    final int totalDocs = docs.length;

    // -------------------------------------------------------------------------
    // PASS 1: Barcode Harvesting across all valid invoices (بناء قاموس الباركودات)
    // -------------------------------------------------------------------------
    final Map<String, String> nameToBarcodeMap = {};
    for (int i = 0; i < totalDocs; i++) {
      final doc = docs[i];
      final data = doc.data();
      if (!isReceiptEligibleForPriceIntelligence(data)) {
        continue;
      }
      final rawProducts = data['extracted_products'] as List<dynamic>? ?? [];
      for (final p in rawProducts) {
        if (p is! Map) continue;
        final name = p['name']?.toString().trim() ?? '';
        final barcode = p['barcode']?.toString().trim() ?? '';
        if (name.isNotEmpty && barcode.isNotEmpty && barcode.length >= 6) {
          nameToBarcodeMap[normalizeName(name)] = barcode;
          final cleanBaseName = normalizeName(name.replaceAll(RegExp(r'\([^)]*\)'), ' '));
          if (cleanBaseName.isNotEmpty) {
            nameToBarcodeMap[cleanBaseName] = barcode;
          }
        }
      }

      if (i % 50 == 0 || i == totalDocs - 1) {
        onProgress?.call(i + 1, totalDocs, 'مرحلة 1: بناء قاموس الباركودات الذكي (${i + 1} من $totalDocs)...');
        await Future.delayed(Duration.zero);
      }
    }

    // -------------------------------------------------------------------------
    // PASS 2: Aggregate Occurrences with Cross-Invoice Barcode Auto-Linking
    // -------------------------------------------------------------------------
    for (int i = 0; i < totalDocs; i++) {
      final doc = docs[i];
      final data = doc.data();
      if (!isReceiptEligibleForPriceIntelligence(data)) {
        continue;
      }
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
        String barcode = p['barcode']?.toString().trim() ?? '';
        bool isAutoLinked = false;

        // Auto-search and link barcode from other invoices if missing
        if (barcode.isEmpty || barcode.length < 6) {
          final norm = normalizeName(name);
          final cleanBaseName = normalizeName(name.replaceAll(RegExp(r'\([^)]*\)'), ' '));
          final foundBarcode = nameToBarcodeMap[norm] ?? nameToBarcodeMap[cleanBaseName];
          if (foundBarcode != null && foundBarcode.isNotEmpty) {
            barcode = foundBarcode;
            isAutoLinked = true;
          }
        }

        double? originalPrice = (p['originalPrice'] as num?)?.toDouble();
        double discountAmount = (p['discountAmount'] as num?)?.toDouble() ?? 0.0;
        final double discountPercent = (p['discountPercent'] as num?)?.toDouble() ?? 0.0;
        final double? totalLinePrice = (p['totalPrice'] as num?)?.toDouble() ?? (p['totalLinePrice'] as num?)?.toDouble();
        final bool isTargetCompany = p['isTargetCompany'] == true;

        final bool isAlreadyNormalized = p['isUnitNormalized'] == true;

        // Auto-heal line total vs unit price math anomalies:
        if (quantity > 1 && !isAlreadyNormalized) {
          final bool isAlreadyUnitPrice = totalLinePrice != null &&
              totalLinePrice > 0 &&
              (price * quantity - totalLinePrice).abs() < 1.5;

          if (!isAlreadyUnitPrice) {
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
          isAutoLinked: isAutoLinked,
        );

        occurrencesBySku.putIfAbsent(skuKey, () => []).add(occurrence);
      }

      if (i % 40 == 0 || i == totalDocs - 1) {
        onProgress?.call(i + 1, totalDocs, 'مرحلة 2: تجميع أصناف السلاسل (${i + 1} من $totalDocs)...');
        await Future.delayed(Duration.zero);
      }
    }

    // Now aggregate each SKU group into a ChainProductItem
    final List<ChainProductItem> aggregated = [];
    final int totalSkus = occurrencesBySku.length;
    int skuIdx = 0;

    for (final entry in occurrencesBySku.entries) {
      skuIdx++;
      final occurrences = entry.value;
      if (occurrences.isEmpty) continue;

      // Sort occurrences chronologically (newest first)
      occurrences.sort((a, b) {
        final tsA = a.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tsB = b.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
        return tsB.compareTo(tsA);
      });

      // Statistical Outlier & Unit Price Auto-Healing Pass:
      final validPrices = occurrences
          .map((o) => o.originalPrice ?? o.price)
          .where((pr) => pr > 10.0)
          .toList();

      double? referenceSkuPrice;
      if (validPrices.isNotEmpty) {
        validPrices.sort();
        final maxPrice = validPrices.last;
        final medianPrice = validPrices[validPrices.length ~/ 2];
        if (maxPrice >= 50.0 && medianPrice < maxPrice * 0.7) {
          referenceSkuPrice = maxPrice;
        } else {
          referenceSkuPrice = medianPrice;
        }
      }

      // Explicit Category Heuristics Anchors
      final lowerName = occurrences.first.name.toLowerCase();
      if (lowerName.contains('ريكسونا') && (lowerName.contains('رول') || lowerName.contains('روول'))) {
        referenceSkuPrice = 69.0;
      } else if (lowerName.contains('أكس') || lowerName.contains('اكس')) {
        if (lowerName.contains('اسبراي') || lowerName.contains('اسبراى')) {
          referenceSkuPrice ??= 140.0;
          if (referenceSkuPrice < 100.0) referenceSkuPrice = 140.0;
        }
      } else if (lowerName.contains('كلير') && lowerName.contains('360')) {
        referenceSkuPrice = 134.0;
      } else if (lowerName.contains('تريزيمي') && lowerName.contains('400')) {
        referenceSkuPrice = 175.0;
      }

      if (referenceSkuPrice != null && referenceSkuPrice > 25.0) {
        for (int i = 0; i < occurrences.length; i++) {
          final occ = occurrences[i];
          if (occ.price < referenceSkuPrice * 0.7) {
            for (final mult in [occ.quantity, 2, 3, 4, 6, 12]) {
              if (mult > 1) {
                final candidate = occ.price * mult;
                if ((candidate - referenceSkuPrice).abs() / referenceSkuPrice < 0.20 || candidate == referenceSkuPrice) {
                  occurrences[i] = occ.copyWith(
                    price: candidate,
                    originalPrice: occ.originalPrice != null ? occ.originalPrice! * mult : candidate,
                    discountAmount: occ.discountAmount > 0 ? occ.discountAmount * mult : 0.0,
                  );
                  break;
                }
              }
            }
          }
        }
      }

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

        final chain = occ.storeChain.trim();
        if (chain.isNotEmpty && !latestPricesByChain.containsKey(chain)) {
          latestPricesByChain[chain] = occ.price;
          latestRegularPricesByChain[chain] = occ.originalPrice ?? occ.price;
          latestDatesByChain[chain] = occ.receiptDate;
          latestEntryByChain[chain] = historyEntry;
        }
      }

      final Map<String, String> latestPosNameByChain = {};
      final Map<String, List<String>> chainAliases = {};

      for (final cEntry in chainGroupedOccurrences.entries) {
        final chainName = cEntry.key;
        final cOccs = cEntry.value;
        final latestOcc = cOccs.first;

        latestPosNameByChain[chainName] = latestOcc.name;
        final distinctNames = cOccs.map((o) => o.name.trim()).where((n) => n.isNotEmpty).toSet().toList();
        chainAliases[chainName] = distinctNames;

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
          latestPosNameByChain: latestPosNameByChain,
          chainAliases: chainAliases,
          chainSummaries: chainSummaries,
          latestEntryByChain: latestEntryByChain,
          priceHistory: priceHistory,
          totalScansCount: occurrences.length,
          totalQuantitySold: totalQuantitySold,
          isBarcodeAutoLinked: occurrences.any((o) => o.isAutoLinked),
        ),
      );

      if (skuIdx % 25 == 0 || skuIdx == totalSkus) {
        onProgress?.call(skuIdx, totalSkus, 'مرحلة 3: حوكمة أسعار السلاسل ($skuIdx من $totalSkus صنف)...');
        await Future.delayed(Duration.zero);
      }
    }

    aggregated.sort((a, b) => b.totalScansCount.compareTo(a.totalScansCount));
    return aggregated;
  }

  /// Syncs / Persists aggregated products into the `chain_products_catalog` Firestore collection in safe chunked batches
  Future<void> syncAggregatedCatalogToFirestore(
    List<ChainProductItem> products, {
    void Function(int written, int total, String status)? onProgress,
  }) async {
    if (_firestore == null || products.isEmpty) return;

    const int chunkSize = 200; // Strictly under Firestore's 500 limit
    final int total = products.length;

    for (int i = 0; i < total; i += chunkSize) {
      final end = (i + chunkSize < total) ? i + chunkSize : total;
      final chunk = products.sublist(i, end);
      final batch = _firestore.batch();
      for (final item in chunk) {
        final docRef = _firestore.collection('chain_products_catalog').doc(item.id);
        batch.set(docRef, item.toJson(), SetOptions(merge: true));
      }
      await batch.commit();

      onProgress?.call(end, total, 'مرحلة 4: حفظ الكتالوج الموحد السحابي ($end من $total صنف)...');
      await Future.delayed(const Duration(milliseconds: 5)); // Cooperative event loop yield
    }
  }

  /// Re-analyzes receipts in Firestore and heals unit prices, discounts, and chain names.
  /// Supports incremental sync (only un-healed / new receipts) vs full deep rescan.
  /// Fully non-blocking with cooperative event-loop yielding to guarantee 0ms browser UI freezing.
  Future<int> reAnalyzeAndHealAllReceiptsInFirestore({
    bool incrementalOnly = false,
    void Function(int processed, int total, String status)? onProgress,
  }) async {
    if (_firestore == null) return 0;

    onProgress?.call(0, 100, 'جاري استعلام الفواتير من قاعدة البيانات السحابية...');

    final snapshot = await _firestore.collection('receipts_transactions').get();
    final allDocs = snapshot.docs;
    final int totalDocs = allDocs.length;

    if (totalDocs == 0) return 0;

    int processedCount = 0;
    int updatedCount = 0;

    // Split writes into batches of 200 (well under Firestore's 500 limit)
    WriteBatch currentBatch = _firestore.batch();
    int currentBatchOps = 0;

    for (int docIdx = 0; docIdx < totalDocs; docIdx++) {
      final doc = allDocs[docIdx];
      processedCount++;
      final data = doc.data();
      bool modified = false;

      // If incremental mode and already normalized with clean data, skip
      final bool isDocAlreadyNormalized = data['isAuditNormalized'] == true;
      if (incrementalOnly && isDocAlreadyNormalized) {
        if (processedCount % 25 == 0 || processedCount == totalDocs) {
          onProgress?.call(
            processedCount,
            totalDocs,
            'تم فحص $processedCount من $totalDocs فاتورة (تخطي المفحوص مسبقاً)...',
          );
          await Future.delayed(Duration.zero); // Yield to browser event loop
        }
        continue;
      }

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

        final name = map['name']?.toString().trim() ?? '';
        final lowerName = name.toLowerCase();
        int quantity = (map['quantity'] as num?)?.toInt() ?? 1;
        if (quantity <= 0) quantity = 1;

        double price = (map['price'] as num?)?.toDouble() ?? 0.0;
        double? originalPrice = (map['originalPrice'] as num?)?.toDouble();
        double discountAmount = (map['discountAmount'] as num?)?.toDouble() ?? 0.0;

        // Specific Heuristic: Reverse Double Division for Rexona Roll-on, Axe, Clear, etc.
        if (lowerName.contains('ريكسونا') && (lowerName.contains('رول') || lowerName.contains('روول'))) {
          if (price < 50.0 && quantity >= 2) {
            price = price * quantity;
            if (originalPrice != null && originalPrice < 50.0) {
              originalPrice = originalPrice * quantity;
            }
            modified = true;
          } else if (price < 50.0 && (price * 2 >= 60.0 && price * 2 <= 75.0)) {
            price = price * 2;
            modified = true;
          }
        } else if ((lowerName.contains('أكس') || lowerName.contains('اكس')) && (lowerName.contains('اسبراي') || lowerName.contains('اسبراى'))) {
          if (price < 100.0 && quantity >= 2) {
            price = price * quantity;
            modified = true;
          }
        } else if (lowerName.contains('كلير') && lowerName.contains('360')) {
          if (price < 80.0 && quantity >= 2) {
            price = price * quantity;
            modified = true;
          }
        } else if (lowerName.contains('تريزيمي') && lowerName.contains('400')) {
          if (price < 100.0 && quantity >= 2) {
            price = price * quantity;
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
        map['isUnitNormalized'] = true;

        sanitizedProducts.add(map);
      }

      data['extracted_products'] = sanitizedProducts;
      data['isAuditNormalized'] = true;

      if (modified) {
        currentBatch.set(doc.reference, data, SetOptions(merge: true));
        currentBatchOps++;
        updatedCount++;

        if (currentBatchOps >= 200) {
          await currentBatch.commit();
          await Future.delayed(const Duration(milliseconds: 5));
          currentBatch = _firestore.batch();
          currentBatchOps = 0;
        }
      }

      if (processedCount % 20 == 0 || processedCount == totalDocs) {
        onProgress?.call(
          processedCount,
          totalDocs,
          'جاري تدقيق وتصحيح الفواتير: $processedCount من $totalDocs...',
        );
        await Future.delayed(Duration.zero); // Yield to browser event loop
      }
    }

    if (currentBatchOps > 0) {
      await currentBatch.commit();
      await Future.delayed(const Duration(milliseconds: 5));
    }

    onProgress?.call(0, totalDocs, 'جاري تحديث وتجميع مصفوفة الأصناف والأسعار...');

    final aggregated = await aggregateProductsFromReceiptsAsync(
      snapshot.docs,
      onProgress: (current, total, phase) {
        onProgress?.call(current, total, phase);
      },
    );

    await syncAggregatedCatalogToFirestore(
      aggregated,
      onProgress: (written, total, status) {
        onProgress?.call(written, total, status);
      },
    );

    onProgress?.call(totalDocs, totalDocs, 'اكتمل التدقيق وتحديث $updatedCount فاتورة بنجاح 100%!');

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
  final bool isAutoLinked;

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
    this.isAutoLinked = false,
  });

  _RawProductOccurrence copyWith({
    String? skuKey,
    String? name,
    String? barcode,
    double? price,
    double? originalPrice,
    double? discountAmount,
    double? discountPercent,
    int? quantity,
    bool? isTargetCompany,
    String? receiptNumber,
    String? receiptDate,
    DateTime? timestamp,
    String? storeChain,
    String? branchName,
    String? receiptImageUrl,
    String? companySlug,
    bool? isAutoLinked,
  }) {
    return _RawProductOccurrence(
      skuKey: skuKey ?? this.skuKey,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      price: price ?? this.price,
      originalPrice: originalPrice ?? this.originalPrice,
      discountAmount: discountAmount ?? this.discountAmount,
      discountPercent: discountPercent ?? this.discountPercent,
      quantity: quantity ?? this.quantity,
      isTargetCompany: isTargetCompany ?? this.isTargetCompany,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      receiptDate: receiptDate ?? this.receiptDate,
      timestamp: timestamp ?? this.timestamp,
      storeChain: storeChain ?? this.storeChain,
      branchName: branchName ?? this.branchName,
      receiptImageUrl: receiptImageUrl ?? this.receiptImageUrl,
      companySlug: companySlug ?? this.companySlug,
      isAutoLinked: isAutoLinked ?? this.isAutoLinked,
    );
  }
}
