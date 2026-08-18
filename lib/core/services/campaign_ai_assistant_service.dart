import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

const String _geminiApiKey =
    'REMOVED_SECRET';

final campaignAiAssistantServiceProvider = Provider<CampaignAiAssistantService>((ref) {
  return CampaignAiAssistantService();
});

class CampaignAiAnalysisResult {
  final String formattedSystemPrompt;
  final String aiValidationSummary;
  final List<PromotionalRuleItem> rules;
  final List<String> suggestedRequiredProducts;

  CampaignAiAnalysisResult({
    required this.formattedSystemPrompt,
    required this.aiValidationSummary,
    this.rules = const [],
    this.suggestedRequiredProducts = const [],
  });

  factory CampaignAiAnalysisResult.fromJson(Map<String, dynamic> json) {
    final rawRules = json['rules'];
    List<PromotionalRuleItem> parsedRules = [];
    if (rawRules is List) {
      parsedRules = rawRules.map((r) {
        final map = Map<String, dynamic>.from(r as Map);
        return PromotionalRuleItem.fromMap(map);
      }).toList();
    }

    final rawProducts = json['suggestedRequiredProducts'];
    List<String> parsedProducts = [];
    if (rawProducts is List) {
      parsedProducts = rawProducts.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }

    return CampaignAiAnalysisResult(
      formattedSystemPrompt: json['formattedSystemPrompt']?.toString() ?? '',
      aiValidationSummary: json['aiValidationSummary']?.toString() ?? '',
      rules: parsedRules,
      suggestedRequiredProducts: parsedProducts,
    );
  }
}

class CampaignAiAssistantService {
  late final GenerativeModel _model;
  late final GenerativeModel _fallbackModel;

  CampaignAiAssistantService() {
    _model = _createModel('gemini-flash-latest');
    _fallbackModel = _createModel('gemini-3.5-flash');
  }

  static GenerativeModel _createModel(String modelName) {
    return GenerativeModel(
      model: modelName,
      apiKey: _geminiApiKey,
      systemInstruction: Content.system(
        'أنت كبير مستشاري التسويق وتدقيق العروض الترويجية لسلاسل السوبرماركت والتجزئة (FMCG Trade Marketing & Audit Specialist). '
        'مهمتك قراءة الأفكار والشروط الترويجية التي يكتبها مسؤول الحملة باللغة العربية (سواء كانت فصحى أو عامية أو شروط شراء محددة Buy X Get Y)، '
        'وتحليلها بدقة متناهية وترجمتها إلى: '
        '1. برومبت نظام تدقيق احترافي صارم ومكتمل يفهمه الذكاء الاصطناعي لفحص الفواتير ومنع أي تلاعب. '
        '2. ملخص توضيحي مرئي ومنسق باللغة العربية يشرح بوضوح للمسؤول قواعد الفحص والمكافآت (Summary). '
        '3. قائمة قواعد وهياكل بيانات دقيقة (Rules List) تحتوي على: اسم القاعدة، المنتجات المشروطة، الكمية الدنيا، نوع المكافأة (قسيمة شراء voucher، منتج مجاني free_product، دورة سحب game_spin)، وقيمة الهدية وقابلية المضاعفة. '
        '4. قائمة بأسماء الأصناف الرئيسية المشروطة لاقتراحها في قائمة المنتجات المعتمدة.',
      ),
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.1,
        maxOutputTokens: 4096,
        responseSchema: Schema.object(
          properties: {
            'formattedSystemPrompt': Schema.string(
              description:
                  'The comprehensive, bullet-proof system prompt in Arabic to be used when auditing receipts for this campaign.',
            ),
            'aiValidationSummary': Schema.string(
              description:
                  'A clean, structured markdown summary in Arabic clearly explaining each rule, conditions, and rewards to display in the admin preview card.',
            ),
            'rules': Schema.array(
              description: 'List of structured promotional rules extracted from the idea.',
              items: Schema.object(
                properties: {
                  'id': Schema.string(description: 'Unique rule identifier (e.g. rule_1, rule_2).'),
                  'ruleTitle': Schema.string(description: 'Short descriptive title of the rule in Arabic (e.g. عرض اسبراي ريكسونا/أكس).'),
                  'triggerProduct': Schema.string(
                    description: 'Required product keywords or description (e.g. اسبراي ريكسونا، اسبراي أكس).',
                  ),
                  'minQuantity': Schema.integer(description: 'Minimum quantity required to earn the reward.'),
                  'rewardType': Schema.string(
                    description: 'Type of reward: "voucher" (قسيمة مشتريات) or "free_product" (منتج مجاني) or "game_spin" (دورة لعبة).',
                  ),
                  'rewardValue': Schema.string(
                    description: 'Display text of the reward (e.g. قسيمة مشتريات بقيمة 50 ج.م or شامبو كلير 90 مل هدية).',
                  ),
                  'rewardAmount': Schema.number(
                    description: 'Numeric monetary amount if reward is voucher (e.g. 50.0), or 0 otherwise.',
                  ),
                  'allowMultipliers': Schema.boolean(
                    description: 'True if purchasing multiples of the required quantity grants multiple rewards.',
                  ),
                },
                requiredProperties: [
                  'id',
                  'ruleTitle',
                  'triggerProduct',
                  'minQuantity',
                  'rewardType',
                  'rewardValue',
                  'rewardAmount',
                  'allowMultipliers',
                ],
              ),
            ),
            'suggestedRequiredProducts': Schema.array(
              description: 'List of product names/brands detected that should be included in the campaign.',
              items: Schema.string(),
            ),
          },
          requiredProperties: [
            'formattedSystemPrompt',
            'aiValidationSummary',
            'rules',
            'suggestedRequiredProducts',
          ],
        ),
      ),
    );
  }

  Future<CampaignAiAnalysisResult> structureCampaignIdea({
    required String targetCompany,
    required String rawIdeaText,
    String existingPrompt = '',
    double minimumSpend = 0.0,
  }) async {
    final minSpendText = minimumSpend > 0
        ? '$minimumSpend ج.م'
        : 'بدون حد أدنى للإنفاق (العرض يعتمد بالكامل على شروط الأصناف والكميات وقواعد البرومبت)';

    final prompt = '''
الشركة الراعية / المستهدفة: "$targetCompany"
الحد الأدنى للإنفاق: $minSpendText

نص فكرة المهرجان وشروط العرض كما كتبها المسؤول:
"""
$rawIdeaText
"""

المطلوب:
1. قم بتحليل كافة قواعد الشراء والجوائز المذكورة (مثل: عند شراء منتج كذا احصل على كذا، القسائم، الهدايا العينية، السحوبات، مضاعفات الكميات).
2. استخرج قائمة القواعد المهيكلة بدقة مع تحديد نوع كل مكافأة (voucher, free_product, game_spin) وقيمتها وقابليتها للتضاعف.
3. اكتب برومبت تدقيق فائق الاحترافية والدقة (formattedSystemPrompt) ليوجه الذكاء الاصطناعي أثناء قراءة الفاتورة، مع التأكيد على التحقق من الأصناف والأحجام والكميات بدقة ومنع التلاعب.
4. أنشئ ملخصاً واضحاً باللغة العربية (aiValidationSummary) في نقاط محددة ومنسقة، يشرح بأسلوب جميل للمسؤول: "إليك كيف سأقوم بفحص وتدقيق فواتير هذا المهرجان".
5. اقترح قائمة الأصناف والكلمات المفتاحية المشروطة في العرض (suggestedRequiredProducts).
''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text;
      if (text == null || text.trim().isEmpty) {
        throw Exception('استجابة الذكاء الاصطناعي فارغة.');
      }
      final jsonMap = jsonDecode(text) as Map<String, dynamic>;
      return CampaignAiAnalysisResult.fromJson(jsonMap);
    } catch (e) {
      // Try fallback model
      try {
        final fallbackResponse = await _fallbackModel.generateContent([Content.text(prompt)]);
        final fallbackText = fallbackResponse.text;
        if (fallbackText != null && fallbackText.trim().isNotEmpty) {
          final jsonMap = jsonDecode(fallbackText) as Map<String, dynamic>;
          return CampaignAiAnalysisResult.fromJson(jsonMap);
        }
      } catch (_) {}
      
      // Fallback local heuristic if offline
      return _generateLocalFallbackResult(
        targetCompany: targetCompany,
        rawIdeaText: rawIdeaText,
        minimumSpend: minimumSpend,
      );
    }
  }

  CampaignAiAnalysisResult _generateLocalFallbackResult({
    required String targetCompany,
    required String rawIdeaText,
    required double minimumSpend,
  }) {
    final rules = [
      PromotionalRuleItem(
        id: 'rule_1',
        ruleTitle: 'عرض منتجات $targetCompany',
        triggerProduct: targetCompany,
        minQuantity: 1,
        rewardType: 'free_product',
        rewardValue: 'هدية فورية من العرض',
        rewardAmount: 0.0,
        allowMultipliers: true,
      ),
    ];

    final summary = '''
📋 **ملخص منطق التدقيق المستخلص من فكرة المهرجان:**
• **الشركة المستهدفة:** $targetCompany
• **الشرط الأساسي:** $rawIdeaText
• **المكافأة:** استحقاق الجوائز والقسائم المحددة بناءً على مطابقة الأصناف والكميات في الفاتورة.
• **مضاعفات الكمية:** مفعّلة تلقائياً عند زيادة الكمية المشتراة.
''';

    final systemPrompt = '''
أنت مدقق مالي ذكي لفحص فواتير السوبرماركت لمهرجان "$targetCompany".
شروط العرض:
$rawIdeaText
${minimumSpend > 0 ? 'الحد الأدنى للإنفاق: $minimumSpend ج.م.' : 'العرض ساري بدون اشتراط حد أدنى لمبلغ الفاتورة (الاعتماد على شروط الأصناف والكميات المحددة).'}
تحقق من وجود أصناف $targetCompany والكميات المطلوبة، وقم باحتساب الهدايا المستحقة بدقة.
''';

    return CampaignAiAnalysisResult(
      formattedSystemPrompt: systemPrompt,
      aiValidationSummary: summary,
      rules: rules,
      suggestedRequiredProducts: [targetCompany],
    );
  }
}
