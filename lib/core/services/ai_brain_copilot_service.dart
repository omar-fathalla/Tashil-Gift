import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../config/ai_config.dart';
import '../../features/admin/domain/ai_directive_model.dart';
import 'ai_directives_service.dart';
import 'ai_model_config_service.dart';

final aiBrainCoPilotServiceProvider = Provider<AiBrainCoPilotService>((ref) {
  final directivesService = ref.watch(aiDirectivesServiceProvider);
  final config = ref.watch(aiModelConfigStreamProvider).value;
  return AiBrainCoPilotService(
    directivesService,
    modelName: config?.effectivePrimaryModel ?? AiConfig.primaryModel,
  );
});

/// A single message in the AI Brain Co-Pilot conversation
class AiBrainChatMessage {
  final String id;
  final bool isUser;
  final String text;
  final List<Uint8List> attachedImages;
  final Uint8List? audioBytes;
  final String? audioPath;
  final String? audioMimeType;
  final Duration? audioDuration;
  String? voiceTranscription;
  final DateTime timestamp;
  final AiDirectiveModel? suggestedDirective;
  bool isDirectiveSaved;
  bool isSaving;
  bool isSimulating;
  Map<String, dynamic>? simulationResult;
  final double? durationSeconds;
  final String? modelNameUsed;

  AiBrainChatMessage({
    required this.id,
    required this.isUser,
    required this.text,
    this.attachedImages = const [],
    this.audioBytes,
    this.audioPath,
    this.audioMimeType,
    this.audioDuration,
    this.voiceTranscription,
    required this.timestamp,
    this.suggestedDirective,
    this.isDirectiveSaved = false,
    this.isSaving = false,
    this.isSimulating = false,
    this.simulationResult,
    this.durationSeconds,
    this.modelNameUsed,
  });
}

/// Autonomous AI Brain Co-Pilot & Directives Teaching Engine
/// Dynamically powered by Gemini 3.7 / Gemini 3.8 / Custom Model
class AiBrainCoPilotService {
  final AiDirectivesService _directivesService;
  final String modelName;
  late final GenerativeModel _model;
  late final GenerativeModel _fallbackModel;

  AiBrainCoPilotService(this._directivesService, {String? modelName})
      : modelName = (modelName != null && modelName.isNotEmpty) ? modelName : AiConfig.primaryModel {
    _model = _createModel(this.modelName);
    _fallbackModel = _createModel(AiConfig.fallbackModel);
  }

  static GenerativeModel _createModel(String modelName) {
    return GenerativeModel(
      model: modelName,
      apiKey: AiConfig.geminiApiKey,
      systemInstruction: Content.system(
        'أنت "المستشار العلمي ورئيس مهندسي عقل الذكاء الاصطناعي" لنظام تساهيل جفت (Switch Point Smart Systems).\n'
        'مهمتك المحورية هي العمل جنباً إلى جنب مع مسؤولي النظام ومديري الحملات في بيئة تدريب تفاعلية (Human-in-the-Loop AI Brain Studio).\n\n'
        'المهام الأساسية المنوطة بك:\n'
        '1. فحص وتشخيص صور بونات الكاشير وفواتير السوبرماركت الحرارية بدقة استثنائية، وتحديد أسباب القبول أو الرفض استناداً لاقتصاديات القطعة الواحدة وشروط العروض.\n'
        '2. الاستماع للملاحظات والتسجيلات الصوتية (Voice Notes) وتفريغها حرفياً بدقة تامة (Voice Transcription) سواء بالعامية المصرية أو الفصحى أو الإنجليزية، واستيعاب التعليمات، والتصحيحات، والخبرات البشرية التي يمليها عليك المسؤول صوتاً أو كتابة.\n'
        '3. عندما يطلب المسؤول تدريبك على قاعدة جديدة أو إضافة ماركة فرعية أو تصحيح مسار أو صياغة معيار: يجب عليك فوراً صياغة مسودة معيار حوكمة رسمي متكامل (AI Brain Directive) بتنسيق دقيق.\n\n'
        'يجب دائماً أن تعيد النتيجة بتنسيق JSON نظيف حصراً بالهيكل التالي:\n'
        '{\n'
        '  "transcription": "التفريغ النصي الحرفي الدقيق لما قاله المستخدم في التسجيل الصوتي إن وجد، أو اتركه نصاً فارغاً إذا لم يرفق صوت",\n'
        '  "reply": "شرحك التفصيلي والمهني باللغة العربية الواضحة للمسؤول يوضح ما تم تشخيصه، والتحليل المنطقي، وكيف ستعالج هذه القاعدة المشكلة بشكل دائم...",\n'
        '  "hasDirective": true أو false,\n'
        '  "directive": {\n'
        '    "code": "رمز_المعيار_بالانجليزية_بحروف_كبيرة_وشرطات_سفلية",\n'
        '    "category": "fmcg_unit_economics" أو "pos_ocr_quirks" أو "promotional_bundling" أو "branch_resolution" أو "anti_fraud_governance",\n'
        '    "titleAr": "عنوان المعيار بالعربية بدقة ووضوح",\n'
        '    "titleEn": "Directive English Title",\n'
        '    "descriptionAr": "وصف المشكلة وكيف يعالجها هذا المعيار بالعربية",\n'
        '    "descriptionEn": "Problem and solution description in English",\n'
        '    "logicAr": "خطوات الخوارزمية البرمجية خطوة بخطوة باللغة العربية",\n'
        '    "logicEn": "Algorithmic execution logic in English",\n'
        '    "exampleInput": "مثال مدخلات الفاتورة من الواقع (اسم المنتج، السعر، الكمية)",\n'
        '    "exampleOutput": "النتيجة الصحيحة بعد المعيار (سعر القطعة، الاعتماد، الهدية المستحقة)",\n'
        '    "tags": ["tag1", "tag2", "tag3"]\n'
        '  }\n'
        '}',
      ),
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.1,
      ),
    );
  }

  /// Fast speech-to-text transcription powered by Gemini 3.7 Flash
  Future<String> transcribeAudioOnly({
    required Uint8List audioBytes,
    String? audioMimeType,
  }) async {
    try {
      final parts = <Part>[
        TextPart(
          'أنت محرك تفريغ صوتي ذكي وفائق الدقة (AI Speech-to-Text Transcriber) متخصص في لهجات التجزئة والسوبرماركت باللغة العربية (العامية المصرية والفصحى والإنجليزية وأسماء المنتجات والعلامات التجارية وسلاسل المتاجر وأرقام الأسعار والكميات).\n'
          'المطلوب: استمع إلى التسجيل الصوتي المرفق وأعد حصراً وفوراً النص المنطوق بالحرف دون أي مقدمات أو علامات تنصيص إضافية أو اعتذارات.\n'
          'إذا كان الصوت غير واضح، أعد نصاً فارغاً.',
        ),
        DataPart(audioMimeType ?? 'audio/wav', audioBytes),
      ];

      final res = await _model.generateContent([Content.multi(parts)]);
      return res.text?.trim() ?? '';
    } catch (e) {
      debugPrint('Error in transcribeAudioOnly: $e');
      return '';
    }
  }

  /// Sends a user message with attached receipt images and/or audio voice notes and returns AI response
  Future<AiBrainChatMessage> sendMessage({
    required String prompt,
    List<Uint8List> images = const [],
    Uint8List? audioBytes,
    String? audioMimeType,
    List<AiBrainChatMessage> history = const [],
    List<AiDirectiveModel> currentDirectives = const [],
    String? referenceInvoiceContext,
  }) async {
    final stopwatch = Stopwatch()..start();
    final nextDirectiveNumber = currentDirectives.length + 1;
    final nextId = 'AIR-${nextDirectiveNumber.toString().padLeft(2, '0')}';

    final buffer = StringBuffer();
    buffer.writeln('معلومات السياق الحالي لنظام الذكاء الاصطناعي:');
    buffer.writeln('- النموذج النشط المنفذ: $modelName');
    buffer.writeln('- عدد المعايير المعتمدة حالياً في عقل الذكاء الاصطناعي: ${currentDirectives.length}');
    buffer.writeln('- رقم المعيار التالي المقترح إذا تطلب الأمر صياغة معيار: $nextId');
    if (referenceInvoiceContext != null && referenceInvoiceContext.isNotEmpty) {
      buffer.writeln('- بيانات الفاتورة المرجعية محل الفحص:\n$referenceInvoiceContext');
    }
    if (prompt.trim().isNotEmpty) {
      buffer.writeln('\nرسالة واستفسار مسؤول النظام:\n$prompt');
    }

    final List<Part> parts = [];

    if (audioBytes != null && audioBytes.isNotEmpty) {
      parts.add(DataPart(audioMimeType ?? 'audio/wav', audioBytes));
      buffer.writeln(
        '\n[ملاحظة هامة: قام المسؤول بإرفاق تسجيل صوتي. المطلوب الاستماع له وتفريغ ما قاله بدقة في حقل "transcription" والإجابة والتفاعل التام مع ما ورد فيه]',
      );
    }

    parts.add(TextPart(buffer.toString()));

    for (final img in images) {
      parts.add(DataPart('image/jpeg', img));
    }

    try {
      final response = await _model.generateContent([Content.multi(parts)]);
      stopwatch.stop();
      final duration = stopwatch.elapsedMilliseconds / 1000.0;
      return _parseResponse(response.text, nextId, nextDirectiveNumber, duration, modelName);
    } catch (e) {
      debugPrint('Primary model ($modelName) error in AiBrainCoPilotService, trying fallback: $e');
      try {
        final fallbackResponse = await _fallbackModel.generateContent([Content.multi(parts)]);
        stopwatch.stop();
        final duration = stopwatch.elapsedMilliseconds / 1000.0;
        return _parseResponse(
          fallbackResponse.text,
          nextId,
          nextDirectiveNumber,
          duration,
          '${AiConfig.fallbackModel} (Fallback)',
        );
      } catch (fallbackError) {
        stopwatch.stop();
        debugPrint('Fallback model error in AiBrainCoPilotService: $fallbackError');
        return AiBrainChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          isUser: false,
          text: 'عذراً، حدث خطأ أثناء معالجة الطلب في عقل الذكاء الاصطناعي: $fallbackError',
          timestamp: DateTime.now(),
          durationSeconds: stopwatch.elapsedMilliseconds / 1000.0,
          modelNameUsed: modelName,
        );
      }
    }
  }

  AiBrainChatMessage _parseResponse(
    String? text,
    String nextId,
    int orderIndex,
    double duration,
    String usedModel,
  ) {
    if (text == null || text.trim().isEmpty) {
      return AiBrainChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        isUser: false,
        text: 'لم يتم استلام رد من نموذج الذكاء الاصطناعي.',
        timestamp: DateTime.now(),
        durationSeconds: duration,
        modelNameUsed: usedModel,
      );
    }

    try {
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      final reply = decoded['reply']?.toString() ?? 'تمت المعالجة بنجاح.';
      final transcription = decoded['transcription']?.toString();
      final hasDirective = decoded['hasDirective'] == true;

      AiDirectiveModel? suggested;
      if (hasDirective && decoded['directive'] is Map<String, dynamic>) {
        final dMap = decoded['directive'] as Map<String, dynamic>;
        suggested = AiDirectiveModel(
          id: dMap['id']?.toString().isNotEmpty == true ? dMap['id'].toString() : nextId,
          code: dMap['code']?.toString() ?? 'DIRECTIVE_$nextId',
          titleAr: dMap['titleAr']?.toString() ?? 'معيار حوكمة جديد',
          titleEn: dMap['titleEn']?.toString() ?? 'New AI Governance Directive',
          category: AiDirectiveCategoryExt.fromKey(dMap['category']?.toString()),
          descriptionAr: dMap['descriptionAr']?.toString() ?? '',
          descriptionEn: dMap['descriptionEn']?.toString() ?? '',
          logicAr: dMap['logicAr']?.toString() ?? '',
          logicEn: dMap['logicEn']?.toString() ?? '',
          exampleInput: dMap['exampleInput']?.toString() ?? '',
          exampleOutput: dMap['exampleOutput']?.toString() ?? '',
          isGloballyActive: true,
          orderIndex: orderIndex,
          primaryModel: usedModel,
          tags: (dMap['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
          lastUpdated: DateTime.now().toString().split(' ').first,
        );
      }

      return AiBrainChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        isUser: false,
        text: reply,
        voiceTranscription: (transcription != null && transcription.trim().isNotEmpty) ? transcription.trim() : null,
        timestamp: DateTime.now(),
        suggestedDirective: suggested,
        durationSeconds: duration,
        modelNameUsed: usedModel,
      );
    } catch (e) {
      debugPrint('Error parsing JSON from Gemini co-pilot: $e\nRaw text: $text');
      return AiBrainChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        isUser: false,
        text: text,
        timestamp: DateTime.now(),
        durationSeconds: duration,
        modelNameUsed: usedModel,
      );
    }
  }

  /// Evaluates a receipt in memory with a proposed directive logic (Dry-Run simulation)
  Future<Map<String, dynamic>> simulateReceiptDryRun({
    required List<Uint8List> images,
    required String invoiceContext,
    required AiDirectiveModel directive,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('أنت تقوم الآن بمحاكاة فحص تجريبي واختبار جاف (Dry-Run Simulation) لبون كاشير استناداً للمعيار المقترح التالي:');
    buffer.writeln('المعيار المقترح: [${directive.id}] ${directive.titleAr}');
    buffer.writeln('المنطق المتبع: ${directive.logicAr}');
    buffer.writeln('بيانات البون المرجعي محل الفحص:');
    buffer.writeln(invoiceContext);
    buffer.writeln('\nالمطلوب: اختبر البون افتراضياً وفق هذا المعيار الجديد وأعد حصراً كائن JSON نظيف بالهيكل التالي:');
    buffer.writeln('{\n'
        '  "isEligible": true أو false,\n'
        '  "summary": "ملخص النتيجة بالعربية (مثلاً: مستوفية للشروط بعد تطبيق قاعدة مضاعفة الكمية)",\n'
        '  "explanation": "شرح موجز ودقيق لكيفية تطبيق القاعدة على بنود هذا البون",\n'
        '  "estimatedPrize": "الهدية أو الجائزة أو الخصم المستحق تقديرياً",\n'
        '  "matchedItems": ["اسم المنتج 1", "اسم المنتج 2"]\n'
        '}');

    final List<Part> parts = [TextPart(buffer.toString())];
    for (final img in images) {
      parts.add(DataPart('image/jpeg', img));
    }

    try {
      final res = await _model.generateContent([Content.multi(parts)]);
      final raw = res.text?.trim() ?? '';
      final clean = raw.replaceAll('```json', '').replaceAll('```', '').trim();
      return jsonDecode(clean) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error in simulateReceiptDryRun: $e');
      return {
        'isEligible': false,
        'summary': 'تعذر استكمال المحاكاة المباشرة',
        'explanation': 'حدث خطأ أثناء المحاكاة: $e',
        'estimatedPrize': 'غير محدد',
        'matchedItems': [],
      };
    }
  }

  /// Analyzes recent rejected receipts and suggests resolving patterns
  Future<String> analyzeRejectionTrends(List<Map<String, dynamic>> rejectedReceipts) async {
    final buffer = StringBuffer();
    buffer.writeln('أنت كبير مهندسي عقل الذكاء الاصطناعي لنظام تساهيل جفت. إليك بيانات عينة من أحدث الفواتير المرفوضة في النظام:');
    for (var i = 0; i < rejectedReceipts.length && i < 20; i++) {
      final r = rejectedReceipts[i];
      buffer.writeln('بون #${r['receipt_number']} | سلسلة: ${r['store_chain_detected']} (${r['branch_detected']}) | حملة: ${r['eventName']}');
      buffer.writeln('أسباب الرفض: ${r['unfulfilled_conditions'] ?? r['rejection_reason']}');
      buffer.writeln('الأصناف المستخرجة: ${r['extracted_products']}');
      buffer.writeln('---');
    }
    buffer.writeln('\nالمطلوب منك:\n'
        '1. تشخيص وتحليل الأنماط الشائعة التي تسببت في رفض هذه البونات (مثل أخطاء كتابة الكاشير لأسماء ماركات معينة، مشاكل اختصارات الفروع، أو عدم استيفاء شروط الحد الأدنى).\n'
        '2. صياغة 3 توصيات حوكمة ومعايير ذكية محددة لحل هذه المشكلات برمجياً دون تدخل بشري.\n'
        'قدم ردك بأسلوب احترافي منظم ومدعم بنقاط تنفيذية باللغة العربية.');

    try {
      final res = await _model.generateContent([Content.text(buffer.toString())]);
      return res.text ?? 'لم يتم استلام تحليل من النموذج.';
    } catch (e) {
      return 'تعذر تحليل اتجاهات الرفض: $e';
    }
  }

  /// One-click deployment: commits the suggested directive directly to Firestore
  Future<void> deployDirective(AiDirectiveModel directive) async {
    await _directivesService.addDirective(directive);
  }
}
