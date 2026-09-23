import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/admin/domain/company_gift_model.dart';
import '../config/ai_config.dart';

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
    _model = _createModel('gemini-3.7-flash');
    _fallbackModel = _createModel('gemini-3.6-flash');
  }

  static GenerativeModel _createModel(String modelName) {
    return GenerativeModel(
      model: modelName,
      apiKey: AiConfig.geminiApiKey,
      systemInstruction: Content.system(
        'أنت كبير مستشاري التسويق وتدقيق العروض الترويجية لسلاسل السوبرماركت والتجزئة (FMCG Trade Marketing & Audit Specialist). '
        'مهمتك قراءة الأفكار والشروط الترويجية التي يكتبها مسؤول الحملة باللغة العربية (سواء كانت فصحى أو عامية أو شروط شراء محددة Buy X Get Y)، '
        'وربطها بشكل صارم ومباشر بقائمة هدايا وجوائز المخزون المتاحة للشركة (Company Gifts Master Inventory). '
        'يجب عليك مطابقة كل مكافأة مع هدية حقيقية موجودة في قائمة مخزون الشركة المرفقة (عن طريق مطابقة الفئة النقدية للفاوتشر، أو اسم الهدية العينية أو نوعها)، '
        'وتعيين linkedGiftId و linkedGiftName المطابق بدقة. لا تقم باختراع أي هدية خارج قائمة المخزون إذا توفرت هدايا متطابقة. '
        'وترجمة كل ذلك إلى: '
        '1. برومبت نظام تدقيق احترافي صارم ومكتمل يفهمه الذكاء الاصطناعي لفحص الفواتير ومنع أي تلاعب. '
        '2. ملخص توضيحي مرئي ومنسق باللغة العربية يشرح بوضوح للمسؤول قواعد الفحص والمكافآت والربط بالمخزون (Summary). '
        '3. قائمة قواعد وهياكل بيانات دقيقة (Rules List) تحتوي على: اسم القاعدة، المنتجات المشروطة، الكمية الدنيا، نوع المكافأة، قيمة الهدية، معرف الهدية المربوطة بالمخزون (linkedGiftId و linkedGiftName)، وقابلية المضاعفة. '
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
                  'minQuantity': Schema.integer(description: 'Minimum quantity required to earn the reward (if by_quantity).'),
                  'conditionType': Schema.string(
                    description: 'Condition type: "by_quantity" (piece count) or "by_spend" (monetary spend in EGP) or "combo_spend" (multiple brands bought together for a target spend).',
                  ),
                  'minSpend': Schema.number(
                    description: 'Minimum spend amount in EGP (e.g. 100, 150, 200) if conditionType is by_spend or combo_spend, or 0.0 otherwise.',
                  ),
                  'matchMode': Schema.string(
                    description: 'Match mode: "AND" for combo rules requiring multiple brands together, or "OR" otherwise.',
                  ),
                  'requiredBrands': Schema.array(
                    description: 'List of brands required together (e.g. ["Signal", "Closeup"]).',
                    items: Schema.string(),
                  ),
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
                    description: 'True if purchasing multiples of the required quantity/spend grants multiple rewards.',
                  ),
                  'linkedGiftId': Schema.string(
                    description: 'The exact ID of the matched gift from the company master inventory list, or empty string if not matched.',
                  ),
                  'linkedGiftName': Schema.string(
                    description: 'The exact name of the matched gift from the company master inventory list.',
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
    List<CompanyGiftModel> availableCompanyGifts = const [],
  }) async {
    final minSpendText = minimumSpend > 0
        ? '$minimumSpend ج.م'
        : 'بدون حد أدنى للإنفاق (العرض يعتمد بالكامل على شروط الأصناف والكميات وقواعد البرومبت)';

    String inventoryGiftsText = '';
    if (availableCompanyGifts.isNotEmpty) {
      final giftsListFormatted = availableCompanyGifts.map((g) {
        final typeDesc = g.isVoucher ? 'فاوتشر/قسيمة فئة (${g.formattedUnitValue})' : 'هدية عينية';
        return '- [معرف: "${g.id}"] الهدية: "${g.giftName}" (النوع: ${g.giftType}, $typeDesc, القيمة: ${g.unitValue} ج.م, الكمية المتاحة: ${g.availableQuantity})';
      }).join('\n');
      inventoryGiftsText = 'قائمة الهدايا المتاحة في مخزون شركة "$targetCompany":\n$giftsListFormatted';
    } else {
      inventoryGiftsText = 'لا توجد قائمة مخزون هدايا محددة مسبقاً (استخرج الهدايا بحسب نص الشروط).';
    }

    final prompt = '''
الشركة الراعية / المستهدفة: "$targetCompany"
الحد الأدنى للإنفاق: $minSpendText

$inventoryGiftsText

نص فكرة المهرجان وشروط العرض كما كتبها المسؤول:
"""
$rawIdeaText
"""

المطلوب:
1. قم بتحليل كافة قواعد الشراء والجوائز المذكورة (مثل: عند شراء منتج كذا احصل على كذا، القسائم، الهدايا العينية، السحوبات، مضاعفات الكميات).
2. اربط كل قاعدة (Rule) بهدية حقيقية مطابقة من قائمة مخزون الشركة المذكورة أعلاه بدقة (واستخرج معرفها linkedGiftId واسمها linkedGiftName المطابق لقائمة المخزون)، وطابق الفئات النقدية للفاوتشرات والمنتجات العينية دون اختراع هدايا من خارج المخزون إذا توفرت هدايا مطابقة.
3. استخرج قائمة القواعد المهيكلة بدقة مع تحديد نوع كل مكافأة (voucher, free_product, game_spin) وقيمتها وقابليتها للتضاعف والهدية المربوطة.
4. اكتب برومبت تدقيق فائق الاحترافية والدقة (formattedSystemPrompt) ليوجه الذكاء الاصطناعي أثناء قراءة الفاتورة، مع التأكيد على التحقق من الأصناف والأحجام والكميات بدقة ومنع التلاعب وربط الجوائز بهدايا المخزون.
5. أنشئ ملخصاً واضحاً باللغة العربية (aiValidationSummary) في نقاط محددة ومنسقة، يشرح بأسلوب جميل للمسؤول: "إليك كيف سأقوم بفحص وتدقيق فواتير هذا المهرجان وربطها بمخزون الجوائز".
6. اقترح قائمة الأصناف والكلمات المفتاحية المشروطة في العرض (suggestedRequiredProducts).
''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text;
      if (text == null || text.trim().isEmpty) {
        throw Exception('استجابة الذكاء الاصطناعي فارغة.');
      }
      final jsonMap = jsonDecode(text) as Map<String, dynamic>;
      final result = CampaignAiAnalysisResult.fromJson(jsonMap);

      // Post-process rules to guarantee exact inventory gift matching if ID is slightly mismatched
      final enrichedRules = _enrichRulesWithInventory(result.rules, availableCompanyGifts);

      return CampaignAiAnalysisResult(
        formattedSystemPrompt: result.formattedSystemPrompt,
        aiValidationSummary: result.aiValidationSummary,
        rules: enrichedRules,
        suggestedRequiredProducts: result.suggestedRequiredProducts,
      );
    } catch (e) {
      // Try fallback model
      try {
        final fallbackResponse = await _fallbackModel.generateContent([Content.text(prompt)]);
        final fallbackText = fallbackResponse.text;
        if (fallbackText != null && fallbackText.trim().isNotEmpty) {
          final jsonMap = jsonDecode(fallbackText) as Map<String, dynamic>;
          final result = CampaignAiAnalysisResult.fromJson(jsonMap);
          final enrichedRules = _enrichRulesWithInventory(result.rules, availableCompanyGifts);
          return CampaignAiAnalysisResult(
            formattedSystemPrompt: result.formattedSystemPrompt,
            aiValidationSummary: result.aiValidationSummary,
            rules: enrichedRules,
            suggestedRequiredProducts: result.suggestedRequiredProducts,
          );
        }
      } catch (_) {}
      
      // Fallback local heuristic if offline
      return _generateLocalFallbackResult(
        targetCompany: targetCompany,
        rawIdeaText: rawIdeaText,
        minimumSpend: minimumSpend,
        availableCompanyGifts: availableCompanyGifts,
      );
    }
  }

  /// Generates a bulletproof, formatted AI system prompt from existing promotional rules, spend, and conditions.
  static String generateFormattedSystemPrompt({
    required String targetCompany,
    required double minimumSpend,
    List<String> requiredProducts = const [],
    List<PromotionalRuleItem> promotionalRules = const [],
    String retailChainName = '',
    List<String> allowedBranches = const [],
    bool allowMultipleChances = false,
    String multiplierBasis = 'both',
    int maxChancesPerReceipt = 0,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('أنت مدقق فواتير فائق الدقة ومسؤول عن فحص وتدقيق فواتير عروض ومهرجانات شركة "$targetCompany".');
    buffer.writeln();
    buffer.writeln('المطلوب فحص صورة الفاتورة فورياً واستخراج البيانات الأساسية:');
    buffer.writeln('1. اسم سلسلة المتجر والفرع ومطابقتهما.');
    buffer.writeln('2. رقم الفاتورة (Receipt Number أو Transaction ID) وتاريخ الشراء.');
    buffer.writeln('3. أصناف وكميات منتجات "$targetCompany" بدقة.');
    buffer.writeln();

    if (retailChainName.trim().isNotEmpty) {
      final chainList = retailChainName
          .split(RegExp(r'[\•\,\،\/\-\|\+]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final chainClarification = chainList.length > 1
          ? 'تشمل أياً من السلاسل الآتية: [${chainList.join(" أو ")}] (أي فاتورة صادرة من أيٍّ منها معتمدة ومشمولة بالكامل)'
          : '"$retailChainName"';

      buffer.writeln('🏢 شروط السلسلة والفروع:');
      buffer.writeln('- السلسلة/السلاسل المعتمدة: $chainClarification.');
      if (allowedBranches.isNotEmpty) {
        buffer.writeln('- الفروع المعتمدة حصراً: [${allowedBranches.join("، ")}].');
      }
      buffer.writeln('- الأولوية لكود المتجر ورقم الـ POS: يجب استخراج كود الفرع من حقل Store أو POS أو رقم المعاملة/الباركود ومطابقته أولاً، مع تجاهل أي إعلانات افتتاح فروع أخرى مطبوعة في تذييل الفاتورة.');
      buffer.writeln();
    }

    if (minimumSpend > 0) {
      buffer.writeln('💰 شرط الحد الأدنى للإنفاق:');
      buffer.writeln('- إجمالي منتجات "$targetCompany" في الفاتورة يجب ألا يقل عن $minimumSpend ج.م.');
      buffer.writeln();
    }

    if (requiredProducts.isNotEmpty) {
      buffer.writeln('📦 قائمة المنتجات المشروطة:');
      buffer.writeln('- يشترط احتواء الفاتورة على صنف أو أكثر من: [${requiredProducts.join("، ")}].');
      buffer.writeln();
    }

    if (allowMultipleChances) {
      buffer.writeln('✨ نظام مضاعفة الفرص والجوائز (Multipliers):');
      final maxCapText = maxChancesPerReceipt > 0 ? ' (بحد أقصى $maxChancesPerReceipt بالفاتورة الواحدة)' : '';
      if (multiplierBasis == 'quantity') {
        buffer.writeln('- تتضاعف الجوائز والفرص طردياً مع تكرار ومضاعفة كمية المنتج المشروط بالفاتورة (مثال: شراء 1 قطعة = 1 هدية/فرصة، شراء 2 قطعة = 2 هدية/فرصتان)$maxCapText.');
      } else if (multiplierBasis == 'spend') {
        buffer.writeln('- تتضاعف فرص السحب لكل مضاعف للحد الأدنى للإنفاق ($minimumSpend ج.م)$maxCapText.');
      } else {
        buffer.writeln('- تتضاعف الجوائز الفورية بمضاعفة كميات الأصناف المشروطة، وتتضاعف فرص السحب بمضاعفة قيمة الشراء ($minimumSpend ج.م)$maxCapText.');
      }
      buffer.writeln();
    }

    if (promotionalRules.isNotEmpty) {
      buffer.writeln('🎯 محرك القواعد والعروض الترويجية والجوائز المعتمدة (Promotional Rules Engine):');
      for (int i = 0; i < promotionalRules.length; i++) {
        final r = promotionalRules[i];
        final id = r.id.isNotEmpty ? r.id : 'rule_${i + 1}';
        final multText = r.allowMultipliers ? ' (تتضاعف الجوائز بمضاعفة الاستهلاك/الإنفاق)' : '';
        final voucherVal = r.totalVoucherValue > 0
            ? ' [قيمة نقدية: ${r.totalVoucherValue.toInt()} ج.م]'
            : (r.rewardAmount > 0 ? ' [قيمة نقدية: ${r.rewardAmount.toInt()} ج.م]' : '');
        final giftBinding = r.linkedGiftsSummary.isNotEmpty ? ' ➔ تسليم كروت: (${r.linkedGiftsSummary})' : '';
        buffer.writeln('${i + 1}. [معرف ID: "$id"] عنوان: "${r.ruleTitle}"');
        if (r.isCombo) {
          final brandsList = r.requiredBrands.isNotEmpty ? r.requiredBrands.join(' و ') : r.triggerProduct;
          buffer.writeln('   - الشرط: شراء بقيمة إجمالية (${r.minSpend.toInt()} ج.م) أو أكثر تشمل منتجات من ($brandsList معاً) في نفس الفاتورة.');
        } else if (r.isSpendBased) {
          buffer.writeln('   - الشرط: شراء بقيمة إجمالية (${r.minSpend.toInt()} ج.م) أو أكثر من أصناف [${r.triggerProduct}]');
        } else {
          buffer.writeln('   - الشرط: شراء كمية (${r.minQuantity} قطعة) أو أكثر من أصناف [${r.triggerProduct}]');
        }
        final gameDelivery = (r.gameType != null && r.gameType!.isNotEmpty)
            ? ' (طريقة التسليم: ${r.gameType == 'directGift' ? 'هدية فورية مباشرة' : (r.gameType == 'scratch' ? 'خربش واكسب' : (r.gameType == 'wheel' ? 'عجلة الحظ' : 'اختر هديتك'))})'
            : '';
        buffer.writeln('   - المكافأة المستحقة: [${r.rewardValue}$voucherVal] (نوع: ${r.rewardType})$giftBinding$gameDelivery$multText');
      }
      buffer.writeln();
      buffer.writeln('⚠️ تعليمات هامة للذكاء الاصطناعي أثناء التدقيق ومطابقة القواعد (Mandatory Invariants):');
      buffer.writeln('- [حارس العزل الصارم للشكل الفيزيائي للعبوة]:');
      buffer.writeln('  * أصناف الرول أون (Roll-on بحجم 50 مل) تطابق حصراً قواعد الرول أون، وتطابق كافة اختصاراتها في بونات الكاشير (رول أون، رول، روول، ستيك، roll on) دون اشتراط كلمة "أون"، ويُحظر تماماً مطابقتها مع قواعد الاسبراي (مثل عرض الـ 125 ج.م).');
      buffer.writeln('  * أصناف الاسبراي (Aerosol Spray بحجم 150 مل) تطابق حصراً قواعد الاسبراي، ويُحظر مطابقتها مع قواعد الرول أون.');
      buffer.writeln('  * عبوات تريزيمي 400 مل تطابق حصراً قاعدة تريزيمي، وعبوات كلير 360 مل تطابق حصراً قاعدة كلير.');
      buffer.writeln('  * أصناف العناية بالفم (معجون أسنان سيجنال أو كلوس اب) تطابق حصراً قواعد حزم العناية بالفم (Oral Care Bundles).');
      buffer.writeln('- [قاعدة الحزم المدمجة Combo Bundles]:');
      buffer.writeln('  * إذا اشترطت الحزمة وجود علامتين معاً (مثل Signal و Closeup معاً)، يجب التأكد من وجود صنف واحد على الأقل من كل علامة، وبلوغ إجمالي مشترياتهما معاً الحد الأدنى للإنفاق (مثال: 100 ج.م أو 150 ج.م).');
      buffer.writeln('  * في حال وجود مستويات متعددة من الإنفاق أو الكميات، امنح العميل القاعدة ذات المستوى الأعلى المحقق من نفس الفئة (مثل: 200 ج.م تفوز بقاعدة الـ 75 ج.م وليس 25 ج.م).');
      buffer.writeln('- ضع في حقل (matchedRuleId) معرف القاعدة الفائزة بدقة (مثل "rule_1" أو "rule_3").');
      buffer.writeln('- ضع في حقل (matchedRewardValue) اسم الجائزة المستحقة بدقة.');
      buffer.writeln('- إذا لم تتحقق أي قاعدة خاصة، اترك (matchedRuleId) فارغاً.');
    }

    return buffer.toString().trim();
  }

  /// Decomposes a target monetary amount into the best combination of available voucher denominations from inventory.
  /// Example: 125 EGP with [50 EGP, 25 EGP] -> 2x 50 EGP + 1x 25 EGP.
  static List<LinkedGiftAllocation> decomposeVoucherAmount(
    double targetAmount,
    List<CompanyGiftModel> availableGifts,
  ) {
    if (targetAmount <= 0) return [];
    final vouchers = availableGifts
        .where((g) => g.isVoucher && g.unitValue > 0)
        .toList()
      ..sort((a, b) => b.unitValue.compareTo(a.unitValue));

    if (vouchers.isEmpty) return [];

    // 1. Direct exact match
    final exact = vouchers.where((v) => (v.unitValue - targetAmount).abs() < 0.01).firstOrNull;
    if (exact != null) {
      return [
        LinkedGiftAllocation(
          giftId: exact.id,
          giftName: exact.giftName,
          quantity: 1,
          unitValue: exact.unitValue,
          giftType: 'voucher',
        ),
      ];
    }

    // 2. Greedy search
    int remaining = targetAmount.round();
    final List<LinkedGiftAllocation> allocations = [];

    for (final v in vouchers) {
      final val = v.unitValue.round();
      if (val <= 0) continue;
      final count = remaining ~/ val;
      if (count > 0) {
        allocations.add(
          LinkedGiftAllocation(
            giftId: v.id,
            giftName: v.giftName,
            quantity: count,
            unitValue: v.unitValue,
            giftType: 'voucher',
          ),
        );
        remaining -= count * val;
      }
    }

    if (remaining == 0 && allocations.isNotEmpty) {
      return allocations;
    }

    // 3. Fallback: if greedy had remainder, try recursive exact change
    final exactChange = _findExactVoucherChange(targetAmount.round(), vouchers, 0);
    if (exactChange != null && exactChange.isNotEmpty) {
      return exactChange;
    }

    return allocations;
  }

  static List<LinkedGiftAllocation>? _findExactVoucherChange(
    int target,
    List<CompanyGiftModel> vouchers,
    int index,
  ) {
    if (target == 0) return [];
    if (index >= vouchers.length || target < 0) return null;

    final v = vouchers[index];
    final val = v.unitValue.round();
    if (val <= 0) return _findExactVoucherChange(target, vouchers, index + 1);

    final maxCount = target ~/ val;
    for (int count = maxCount; count >= 0; count--) {
      final subResult = _findExactVoucherChange(target - (count * val), vouchers, index + 1);
      if (subResult != null) {
        if (count > 0) {
          return [
            LinkedGiftAllocation(
              giftId: v.id,
              giftName: v.giftName,
              quantity: count,
              unitValue: v.unitValue,
              giftType: 'voucher',
            ),
            ...subResult,
          ];
        }
        return subResult;
      }
    }
    return null;
  }

  List<PromotionalRuleItem> _enrichRulesWithInventory(
    List<PromotionalRuleItem> rules,
    List<CompanyGiftModel> availableGifts,
  ) {
    if (availableGifts.isEmpty) return rules;

    return rules.map((rule) {
      // If already has linkedGifts, verify and keep
      if (rule.linkedGifts.isNotEmpty) {
        final verified = rule.linkedGifts.map((alloc) {
          final matched = availableGifts.where((g) => g.id == alloc.giftId || g.giftName == alloc.giftName).firstOrNull;
          if (matched != null) {
            return alloc.copyWith(
              giftId: matched.id,
              giftName: matched.giftName,
              unitValue: matched.unitValue,
              giftType: matched.giftType,
            );
          }
          return alloc;
        }).toList();
        return rule.copyWith(linkedGifts: verified);
      }

      // If already linked to a single gift ID
      if (rule.linkedGiftId != null && rule.linkedGiftId!.isNotEmpty) {
        final exact = availableGifts.where((g) => g.id == rule.linkedGiftId).firstOrNull;
        if (exact != null) {
          final alloc = LinkedGiftAllocation(
            giftId: exact.id,
            giftName: exact.giftName,
            quantity: 1,
            unitValue: exact.unitValue,
            giftType: exact.giftType,
          );
          return rule.copyWith(
            linkedGiftId: exact.id,
            linkedGiftName: exact.giftName,
            rewardType: exact.isVoucher ? 'voucher' : 'free_product',
            rewardAmount: exact.isVoucher ? exact.unitValue : rule.rewardAmount,
            linkedGifts: [alloc],
          );
        }
      }

      final isExplicitVoucher = rule.rewardType == 'voucher' ||
          rule.rewardValue.contains('فواتشر') ||
          rule.rewardValue.toLowerCase().contains('voucher') ||
          rule.rewardValue.contains('قسيمة');
      final isExplicitProduct = rule.rewardType == 'free_product' ||
          rule.rewardType == 'game_spin' ||
          rule.rewardValue.contains('هدية') ||
          rule.rewardValue.contains('منتج');

      final isVoucherRule = isExplicitVoucher && !isExplicitProduct;

      // Extract numeric amount from rule title or rewardValue only for voucher rules
      double effectiveAmount = rule.rewardAmount;
      if (isVoucherRule && effectiveAmount <= 0) {
        final match = RegExp(r'(\d+)').firstMatch(rule.rewardValue);
        if (match != null) {
          effectiveAmount = double.tryParse(match.group(1)!) ?? 0.0;
        }
      }

      if (isVoucherRule && effectiveAmount > 0) {
        final decomposed = decomposeVoucherAmount(effectiveAmount, availableGifts);
        if (decomposed.isNotEmpty) {
          return rule.copyWith(
            rewardType: 'voucher',
            rewardAmount: effectiveAmount,
            linkedGifts: decomposed,
            linkedGiftId: decomposed.first.giftId,
            linkedGiftName: decomposed.map((d) => d.quantity > 1 ? '${d.quantity}x ${d.giftName}' : d.giftName).join(' + '),
          );
        }
      }

      // Match single gift by name in inventory
      final matchedGift = availableGifts.where((g) =>
          g.giftName.toLowerCase().contains(rule.rewardValue.toLowerCase()) ||
          rule.rewardValue.toLowerCase().contains(g.giftName.toLowerCase())
      ).firstOrNull;

      if (matchedGift != null) {
        final alloc = LinkedGiftAllocation(
          giftId: matchedGift.id,
          giftName: matchedGift.giftName,
          quantity: 1,
          unitValue: matchedGift.unitValue,
          giftType: matchedGift.giftType,
        );
        return rule.copyWith(
          linkedGiftId: matchedGift.id,
          linkedGiftName: matchedGift.giftName,
          rewardType: matchedGift.isVoucher ? 'voucher' : 'free_product',
          rewardAmount: matchedGift.isVoucher ? matchedGift.unitValue : rule.rewardAmount,
          linkedGifts: [alloc],
        );
      }

      return rule;
    }).toList();
  }

  CampaignAiAnalysisResult _generateLocalFallbackResult({
    required String targetCompany,
    required String rawIdeaText,
    required double minimumSpend,
    List<CompanyGiftModel> availableCompanyGifts = const [],
  }) {
    CompanyGiftModel? firstGift = availableCompanyGifts.firstOrNull;

    final rules = [
      PromotionalRuleItem(
        id: 'rule_1',
        ruleTitle: 'عرض منتجات $targetCompany',
        triggerProduct: targetCompany,
        minQuantity: 1,
        rewardType: firstGift?.isVoucher == true ? 'voucher' : 'free_product',
        rewardValue: firstGift != null ? firstGift.giftName : 'هدية فورية من العرض',
        rewardAmount: firstGift?.unitValue ?? 0.0,
        allowMultipliers: true,
        linkedGiftId: firstGift?.id,
        linkedGiftName: firstGift?.giftName,
      ),
    ];

    final summary = '''
📋 **ملخص منطق التدقيق المستخلص من فكرة المهرجان:**
• **الشركة المستهدفة:** $targetCompany
• **الشرط الأساسي:** $rawIdeaText
• **المكافأة:** استحقاق الجوائز والقسائم المحددة بناءً على مطابقة الأصناف والكميات في الفاتورة وربطها بمخزون الشركة.
• **مضاعفات الكمية:** مفعّلة تلقائياً عند زيادة الكمية المشتراة.
''';

    final systemPrompt = '''
أنت مدقق مالي ذكي لفحص فواتير السوبرماركت لمهرجان "$targetCompany".
شروط العرض:
$rawIdeaText
${minimumSpend > 0 ? 'الحد الأدنى للإنفاق: $minimumSpend ج.م.' : 'العرض ساري بدون اشتراط حد أدنى لمبلغ الفاتورة (الاعتماد على شروط الأصناف والكميات المحددة).'}
تحقق من وجود أصناف $targetCompany والكميات المطلوبة، وقم باحتساب الهدايا المستحقة بدقة وفقاً لقائمة الجوائز المعتمدة.
''';

    return CampaignAiAnalysisResult(
      formattedSystemPrompt: systemPrompt,
      aiValidationSummary: summary,
      rules: rules,
      suggestedRequiredProducts: [targetCompany],
    );
  }
}
