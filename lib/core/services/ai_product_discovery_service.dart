import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../config/ai_config.dart';
import '../utils/arabic_numbers_utils.dart';
import 'company_products_service.dart';

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
  final productsService = ref.watch(companyProductsServiceProvider);
  return AiProductDiscoveryService(
    productsService: productsService,
  );
});

class AiProductDiscoveryService {
  final CompanyProductsService _productsService;
  final GenerativeModel _model;

  AiProductDiscoveryService({
    required CompanyProductsService productsService,
  })  : _productsService = productsService,
        _model = GenerativeModel(
          model: 'gemini-3.7-flash',
          apiKey: AiConfig.geminiApiKey,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            temperature: 0.1,
            maxOutputTokens: 3000,
          ),
        );

  /// Discovers uncataloged products from invoice transactions for a specific company using Gemini AI
  Future<List<DiscoveredProductItem>> discoverProductsFromTransactions({
    required String companySlug,
    required String companyName,
    required List<QueryDocumentSnapshot> transactions,
    List<CompanyProductItem>? preloadedCatalog,
  }) async {
    final slug = companySlug.trim().toLowerCase();
    if (slug.isEmpty || transactions.isEmpty) return [];

    // 1. Fetch current registered catalog if not provided
    final catalog = preloadedCatalog ?? await _productsService.getProductsForCompany(slug);
    final Set<String> registeredBarcodes = catalog
        .map((p) => p.barcode.trim().toEnglishDigits())
        .where((b) => b.isNotEmpty)
        .toSet();
    final Set<String> registeredNames = catalog
        .map((p) => _normalizeForComparison(p.productName))
        .where((n) => n.isNotEmpty)
        .toSet();

    // 2. Extract candidate items from transactions
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

        // Check if already in catalog
        final bool isAlreadyInCatalog = (rawBarcode.isNotEmpty && registeredBarcodes.contains(rawBarcode)) ||
            registeredNames.contains(normName);

        if (isAlreadyInCatalog) continue;

        // Group key: Prefer barcode if valid, else normalized name
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
    // Limit batch size to top 40 candidates for optimal AI inference latency
    candidateList.sort((a, b) {
      if (a.isTarget != b.isTarget) return a.isTarget ? -1 : 1;
      return b.frequency.compareTo(a.frequency);
    });
    final topCandidates = candidateList.take(40).toList();

    // 3. AI Analysis with Gemini
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
1. تحديد الأصناف التي تنتمي فعلياً أو ترجح تبعيتها لشركة "$companyName" أو إحدى علاماتها التجارية التابعة (مثلاً يونيليفر تمتلك: كلير Clear، أكس Axe، دوف Dove، ريكسونا Rexona، لوكس Lux، صانسيلك Sunsilk، لايفبوي Lifebuoy، سيجنال Signal، تريزيمي TRESemmé، فازلين Vaseline، بوندز Pond's، كلوز أب Close Up، جيف Jif، كومفورت Comfort، أومو Omo، ليبتون Lipton، كنور Knorr، إلخ. وشركة المراعي تمتلك: حليب، عصائر، ألبان، زبادي، أجبان، لوزين L'usine، سفن دايز 7Days، إلخ).
2. استبعاد المنتجات التابعة لشركات منافسة أو منتجات عامة لا تخص الشركة (مثل شاي أحمد إذا كانت الشركة يونيليفر، أو منتجات P&G، أو الخضار والفواكه العامة).
3. تنسيق اسم المنتج بشكل احترافي، تحديد الباركود، تحديد الفئة (category)، الحجم/العبوة (unitSize)، وتحديد السعر المرجعي (referencePrice)، وذكر سبب التبعية (relevanceReason).

يجب إرجاع النتيجة بصيغة JSON حصراً بالشكل التالي:
{
  "products": [
    {
      "productName": "اسم الصنف المنسق",
      "barcode": "الباركود إن وجد",
      "category": "الفئة مثل: عناية شخصية / شامبو",
      "unitSize": "الحجم مثل: 360 مل",
      "referencePrice": 120.0,
      "isCompanyProduct": true,
      "relevanceReason": "منتج أصلي تابع لعلامة كلير التابعة ليونيليفر",
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
          final bool isCompany = p['isCompanyProduct'] == true;
          if (!isCompany) continue;

          final name = (p['productName'] ?? '').toString().trim();
          if (name.isEmpty) continue;

          final barcode = (p['barcode'] ?? '').toString().trim();
          final category = (p['category'] ?? '').toString().trim();
          final unitSize = (p['unitSize'] ?? '').toString().trim();
          final refPrice = (p['referencePrice'] as num?)?.toDouble();
          final reason = (p['relevanceReason'] ?? '').toString().trim();
          final confidence = (p['confidence'] ?? 'high').toString().trim();

          // Find frequency from candidates
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
    } catch (_) {
      // Fallback to local heuristic parsing
    }

    // Heuristic Fallback
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

  /// Batch saves approved discovered products into Firestore company_products
  Future<int> approveAndSaveDiscoveredProducts({
    required String companySlug,
    required String companyName,
    required List<DiscoveredProductItem> approvedItems,
    void Function(int saved, int total)? onProgress,
  }) async {
    final slug = companySlug.trim().toLowerCase();
    if (slug.isEmpty || approvedItems.isEmpty) return 0;

    final productsToSave = approvedItems.where((p) => p.isSelected).map((p) {
      return {
        'productName': p.productName.trim(),
        'barcode': p.barcode.trim(),
        'category': p.category.trim(),
        'unitSize': p.unitSize.trim(),
        'referencePrice': p.referencePrice,
      };
    }).toList();

    if (productsToSave.isEmpty) return 0;

    return await _productsService.batchSaveProducts(
      companySlug: slug,
      companyName: companyName,
      products: productsToSave,
      onProgress: onProgress,
    );
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
