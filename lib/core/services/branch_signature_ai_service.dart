import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../features/admin/domain/retail_chain_model.dart';
import '../utils/arabic_numbers_utils.dart';

const String _geminiApiKey =
    'AIzaSyBiuLXCswnl2_xCQT9M3YCnaSc0nGZ94Nw';

final branchSignatureAiServiceProvider = Provider<BranchSignatureAiService>((ref) {
  return BranchSignatureAiService();
});

class ExtractedBranchSignatureResult {
  final String chainName;
  final String chainSlug;
  final String branchName;
  final String city;
  final String branchCode;
  final String storeId;
  final String posNumberPattern;
  final String receiptPattern;
  final String sampleReceiptNumber;
  final List<String> headerKeywords;
  final List<String> footerKeywords;
  final String taxNumber;
  final String commercialReg;
  final String hotline;
  final String address;
  final String extractedSummary;
  final double confidenceScore;
  final bool isMatchedWithExistingChain;
  final String? matchedChainId;

  ExtractedBranchSignatureResult({
    required this.chainName,
    required this.chainSlug,
    required this.branchName,
    this.city = '',
    this.branchCode = '',
    this.storeId = '',
    this.posNumberPattern = '',
    this.receiptPattern = '',
    this.sampleReceiptNumber = '',
    this.headerKeywords = const [],
    this.footerKeywords = const [],
    this.taxNumber = '',
    this.commercialReg = '',
    this.hotline = '',
    this.address = '',
    this.extractedSummary = '',
    this.confidenceScore = 1.0,
    this.isMatchedWithExistingChain = false,
    this.matchedChainId,
  });

  BranchReceiptSignature toBranchReceiptSignature({String sampleReceiptUrl = ''}) {
    return BranchReceiptSignature(
      storeId: storeId.toEnglishDigits(),
      posNumberPattern: posNumberPattern.toEnglishDigits(),
      receiptPattern: receiptPattern.toEnglishDigits(),
      headerKeywords: headerKeywords,
      footerKeywords: footerKeywords,
      taxNumber: taxNumber.toEnglishDigits(),
      commercialReg: commercialReg.toEnglishDigits(),
      hotline: hotline.toEnglishDigits(),
      sampleReceiptUrl: sampleReceiptUrl,
      extractedSummary: extractedSummary,
      confidenceScore: confidenceScore,
      scannedAt: DateTime.now(),
    );
  }

  factory ExtractedBranchSignatureResult.fromJson(
    Map<String, dynamic> json, {
    List<RetailChainModel>? existingChains,
  }) {
    final chainName = (json['chainName'] ?? '').toString().trim();
    final rawSlug = (json['chainSlug'] ?? '').toString().toLowerCase().trim().toEnglishDigits();
    final chainSlug = rawSlug.isNotEmpty ? rawSlug : chainName.toLowerCase().replaceAll(RegExp(r'\s+'), '-');
    final branchName = (json['branchName'] ?? '').toString().trim();
    final city = (json['city'] ?? '').toString().trim();
    final branchCode = (json['branchCode'] ?? '').toString().trim().toUpperCase().toEnglishDigits();
    final storeId = (json['storeId'] ?? '').toString().trim().toEnglishDigits();
    final posNumberPattern = (json['posNumberPattern'] ?? '').toString().trim().toEnglishDigits();
    final receiptPattern = (json['receiptPattern'] ?? '').toString().trim().toEnglishDigits();
    final sampleReceiptNumber = (json['sampleReceiptNumber'] ?? '').toString().trim().toEnglishDigits();

    final rawHeader = json['headerKeywords'];
    List<String> headerKeywords = [];
    if (rawHeader is List) {
      headerKeywords = rawHeader.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }

    final rawFooter = json['footerKeywords'];
    List<String> footerKeywords = [];
    if (rawFooter is List) {
      footerKeywords = rawFooter.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }

    final taxNumber = (json['taxNumber'] ?? '').toString().trim().toEnglishDigits();
    final commercialReg = (json['commercialReg'] ?? '').toString().trim().toEnglishDigits();
    final hotline = (json['hotline'] ?? '').toString().trim().toEnglishDigits();
    final address = (json['address'] ?? '').toString().trim();
    final extractedSummary = (json['extractedSummary'] ?? '').toString().trim();
    final confidenceScore = (json['confidenceScore'] as num?)?.toDouble() ?? 0.95;

    // Check if matches an existing chain
    bool isMatched = false;
    String? matchedId;
    if (existingChains != null && existingChains.isNotEmpty) {
      for (final chain in existingChains) {
        final normChainName = chain.name.toLowerCase().replaceAll(RegExp(r'\s+'), '');
        final normExtracted = chainName.toLowerCase().replaceAll(RegExp(r'\s+'), '');
        if (normChainName.contains(normExtracted) ||
            normExtracted.contains(normChainName) ||
            chain.slug == chainSlug) {
          isMatched = true;
          matchedId = chain.id;
          break;
        }
      }
    }

    return ExtractedBranchSignatureResult(
      chainName: chainName,
      chainSlug: chainSlug,
      branchName: branchName,
      city: city,
      branchCode: branchCode,
      storeId: storeId,
      posNumberPattern: posNumberPattern,
      receiptPattern: receiptPattern,
      sampleReceiptNumber: sampleReceiptNumber,
      headerKeywords: headerKeywords,
      footerKeywords: footerKeywords,
      taxNumber: taxNumber,
      commercialReg: commercialReg,
      hotline: hotline,
      address: address,
      extractedSummary: extractedSummary,
      confidenceScore: confidenceScore,
      isMatchedWithExistingChain: isMatched,
      matchedChainId: matchedId,
    );
  }
}

class BranchSignatureAiService {
  late final GenerativeModel _model;
  late final GenerativeModel _fallbackModel;

  BranchSignatureAiService() {
    _model = _createModel('gemini-3.7-flash');
    _fallbackModel = _createModel('gemini-3.6-flash');
  }

  static GenerativeModel _createModel(String modelName) {
    return GenerativeModel(
      model: modelName,
      apiKey: _geminiApiKey,
      systemInstruction: Content.system(
        'أنت خبير هندسي متخصص في تحليل بصمات وهياكل بونات ونظم نقاط البيع (Retail POS Receipt Architecture & Store Signature Expert). '
        'مهمتك فحص صورة بونة الفاتورة المرفقة واستخراج البصمة الهيكلية القاطعة للسلسلة والفرع لمنع أي تزوير أو تلاعب: '
        '1. اسم السلسلة التجارية (chainName) مثل: بيت الجملة، هايبر وان، جملة ماركت، لولو هايبر ماركت، كارفور، أسواق فتح الله، سبينس، سعودي. '
        '2. المعرف الإنجليزي المقترح للسلسلة (chainSlug) مثل: beit-elgomla, hyper-one, gomla-market, lulu. '
        '3. اسم الفرع المحدد بدقة (branchName) مثل: المنشية، فرع سفنكس، راغب، The Park Mall - التجمع الخامس. '
        '4. المدينة (city) مثل: الإسكندرية، الجيزة، القاهرة. '
        '5. كود الفرع المختصر (branchCode) مثل: BGM-502, HYP-04, GML-440, LUL-3912. '
        '6. كود المتجر / الفرع في نظام الكاشير (storeId) وهو رقم الـ Store/Store ID المطبوع في الفاتورة (مثل: 502، 440، 4، 3912). '
        '7. رقم أو نسق نقطة البيع (posNumberPattern) مثل: PoS: 1, POS: 21, POS: 3. '
        '8. نسق وصيغة رقم الفاتورة والباركود (receiptPattern) مثل: Trans/PoS/Store/Date (399/1/502/170826) أو 6639120030648223. '
        '9. رقم الفاتورة في العينة (sampleReceiptNumber). '
        '10. الكلمات الدلالية لرأس البونة (headerKeywords) مثل أسماء السلسلة والفرع والشعارات. '
        '11. الكلمات الدلالية للتذييل (footerKeywords) مثل سياسة الاسترجاع ورقم التسجيل. '
        '12. الرقم الضريبي (taxNumber) والسجل التجاري (commercialReg) والخط الساخن (hotline) إن وجد. '
        '13. ملخص توضيحي باللغة العربية يشرح البصمة المكتشفة وكيف سيتم التحقق منها (extractedSummary).',
      ),
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.1,
        maxOutputTokens: 2048,
        responseSchema: Schema.object(
          properties: {
            'chainName': Schema.string(description: 'Official name of the retail chain (e.g. بيت الجملة, هايبر وان).'),
            'chainSlug': Schema.string(description: 'English slug identifier for the chain (e.g. beit-elgomla, hyper-one).'),
            'branchName': Schema.string(description: 'Exact branch name (e.g. المنشية, فرع سفنكس, راغب).'),
            'city': Schema.string(description: 'City name (e.g. الإسكندرية, الجيزة, القاهرة).'),
            'branchCode': Schema.string(description: 'Short uppercase code for branch (e.g. BGM-502, HYP-04).'),
            'storeId': Schema.string(description: 'POS Store ID printed on receipt (e.g. 502, 440, 4, 3912).'),
            'posNumberPattern': Schema.string(description: 'POS identifier string (e.g. PoS: 1, POS: 21).'),
            'receiptPattern': Schema.string(description: 'Receipt and barcode format structure (e.g. Trans/PoS/Store/Date).'),
            'sampleReceiptNumber': Schema.string(description: 'Receipt number from this image.'),
            'headerKeywords': Schema.array(
              description: 'Unique header keywords identifying this brand and branch.',
              items: Schema.string(),
            ),
            'footerKeywords': Schema.array(
              description: 'Footer keywords, slogans, or return policy text.',
              items: Schema.string(),
            ),
            'taxNumber': Schema.string(description: 'Tax registration number (ب.ض / VAT ID).'),
            'commercialReg': Schema.string(description: 'Commercial registry number (س.ت).'),
            'hotline': Schema.string(description: 'Customer support hotline (e.g. 15677).'),
            'address': Schema.string(description: 'Branch physical address if printed on receipt.'),
            'extractedSummary': Schema.string(description: 'Clear Arabic summary of the extracted POS signature.'),
            'confidenceScore': Schema.number(description: 'Confidence score from 0.0 to 1.0.'),
          },
        ),
      ),
    );
  }

  Future<ExtractedBranchSignatureResult> extractSignatureFromImage(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
    List<RetailChainModel>? existingChains,
  }) async {
    final existingChainsHint = existingChains != null && existingChains.isNotEmpty
        ? 'السلاسل المسجلة مسبقاً في النظام:\n${existingChains.map((c) => '- ${c.name} (Slug: ${c.slug})').join('\n')}'
        : '';

    final promptText = '''
افحص صورة بونة الفاتورة المرفقة بدقة بالغة واستخرج بصمة نظام الكاشير (POS Receipt Signature) والفرع والسلسلة.
$existingChainsHint

المطلوب:
1. حدد اسم السلسلة والفرع والمدينة بدقة.
2. استخرج كود المتجر (Store ID) ورقم الـ PoS ونمط الفاتورة والباركود.
3. استخرج الرقم الضريبي والسجل التجاري والخط الساخن والكلمات الدلالية.
4. اذكر ملخصاً توضيحياً بالعربية يشرح كيفية استخدام هذه البصمة في التحقق التلقائي ومنع التزوير.
''';

    final content = [
      Content.multi([
        TextPart(promptText),
        DataPart(mimeType, imageBytes),
      ]),
    ];

    try {
      final response = await _model.generateContent(content);
      final text = response.text;
      if (text != null && text.trim().isNotEmpty) {
        final json = _parseJsonResponse(text);
        return ExtractedBranchSignatureResult.fromJson(json, existingChains: existingChains);
      }
    } catch (_) {
      // Fallback model
      try {
        final fallbackResponse = await _fallbackModel.generateContent(content);
        final fallbackText = fallbackResponse.text;
        if (fallbackText != null && fallbackText.trim().isNotEmpty) {
          final json = _parseJsonResponse(fallbackText);
          return ExtractedBranchSignatureResult.fromJson(json, existingChains: existingChains);
        }
      } catch (fallbackError) {
        throw Exception('فشل تحليل بصمة البونة بواسطة الذكاء الاصطناعي: $fallbackError');
      }
    }

    throw Exception('لم يتمكن الذكاء الاصطناعي من استخراج بصمة الفاتورة. يرجى التأكد من وضوح الصورة.');
  }

  Map<String, dynamic> _parseJsonResponse(String text) {
    String cleaned = text.trim();
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7);
    } else if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    cleaned = cleaned.trim();

    try {
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {
      // Fallback regex extractor
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
      if (match != null) {
        return jsonDecode(match.group(0)!) as Map<String, dynamic>;
      }
      rethrow;
    }
  }
}
