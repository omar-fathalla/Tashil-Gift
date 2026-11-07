import 'package:al_mraay/core/constants/ai_models.dart';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:al_mraay/core/services/gemini_cloud_model.dart';

import 'whatsapp_gateway_config_model.dart';
import 'whatsapp_gateway_service.dart';

/// Service for Intelligent WhatsApp Customer Service & AI Auto-Reply
/// Powered strictly by [AiModels.helperServices] at temperature 0.0 (Rule 5 & Rule 10)
class WhatsAppAiAutoReplyService {
  late final CloudGenerativeModel _primaryModel;
  late final CloudGenerativeModel _fallbackModel;
  final WhatsAppGatewayService _gatewayService;

  WhatsAppAiAutoReplyService({
    WhatsAppGatewayService? gatewayService,
    CloudGenerativeModel? primaryModel,
    CloudGenerativeModel? fallbackModel,
  })  : _gatewayService = gatewayService ?? WhatsAppGatewayService() {
    _primaryModel = primaryModel ?? _buildModel(AiModels.helperServices);
    _fallbackModel = fallbackModel ?? _buildModel(AiModels.helperServicesFallback);
  }

  static CloudGenerativeModel _buildModel(String modelName) {
    return CloudGenerativeModel(
      model: modelName,
      generationConfig: GenerationConfig(
        temperature: 0.0, // Zero hallucination invariant (Rule 10)
        maxOutputTokens: 1024,
      ),
      systemInstruction: Content.system(
        'أنت المساعد الذكي وخدمة العملاء الرسمية لمنظومة تسهيل جيفت (Tashil Gift) للتسويق وإسعاد العملاء عبر الواتساب. '
        'مهمتك الرد الفوري واللبق والمهذب على رسائل واستفسارات المتسوقين والعملاء بخصوص الحملات الترويجية، فروع الاستلام، الهدايا، وقسائم المشتريات. '
        'القواعد الإلزامية الصارمة: '
        '1. تحدث بلغة عربية مصرية مهذبة وودودة وواضحة تناسب محادثات الواتساب اليومية. '
        '2. التزم حصرياً بالحقائق والمعلومات المرفقة لك في سياق الحملة (الفروع المشاركة، الجوائز، شروط الاستلام). '
        '3. ممنوع نهائياً التخمين أو تأليف فروع أو جوائز أو شروط غير موجودة في بيانات الحملة المعتمدة. '
        '4. اجعل الإجابة موجزة، مفيدة، ومباشرة ومزينة بإيموجي مناسب وخفيف بدون إطالة.',
      ),
    );
  }

  /// Generates an AI reply for an incoming customer inquiry using [AiModels.helperServices]
  Future<String> generateReply({
    required String customerMessage,
    String? customerName,
    String? companyName,
    String? campaignName,
    List<String> branches = const [],
    List<String> prizes = const [],
    String? customInstructions,
  }) async {
    final cleanMsg = customerMessage.trim();
    if (cleanMsg.isEmpty) {
      return 'أهلاً بك يا فندم! كيف يمكننا مساعدتك بخصوص عروض وهدايا حملتنا اليوم؟ 😊';
    }

    final promptBuilder = StringBuffer();
    promptBuilder.writeln('بيانات وسياق الحملة الرسمية:');
    if (customerName != null && customerName.isNotEmpty) {
      promptBuilder.writeln('- اسم العميل: $customerName');
    }
    if (companyName != null && companyName.isNotEmpty) {
      promptBuilder.writeln('- الشركة الراعية: $companyName');
    }
    if (campaignName != null && campaignName.isNotEmpty) {
      promptBuilder.writeln('- اسم الحملة الترويجية: $campaignName');
    }
    if (branches.isNotEmpty) {
      promptBuilder.writeln('- الفروع المتاحة والمشاركة: ${branches.join(", ")}');
    }
    if (prizes.isNotEmpty) {
      promptBuilder.writeln('- الجوائز والهدايا المتاحة: ${prizes.join(", ")}');
    }
    if (customInstructions != null && customInstructions.trim().isNotEmpty) {
      promptBuilder.writeln('- تعليمات خاصة إضافية من الإدارة: ${customInstructions.trim()}');
    }
    promptBuilder.writeln('\nرسالة العميل المستلمة على الواتساب:');
    promptBuilder.writeln('"$cleanMsg"');
    promptBuilder.writeln('\nالمطلوب: صغ رداً نموذجياً مهذباً ومباشراً يوضح للعميل الإجابة بدقة ويوجهه للفرع أو الاستلام.');

    final promptText = promptBuilder.toString();

    // Try primary helper model
    try {
      final response = await _primaryModel.generateContent([Content.text(promptText)]);
      final reply = response.text?.trim();
      if (reply != null && reply.isNotEmpty) {
        return reply;
      }
    } catch (e) {
      debugPrint('${AiModels.helperServicesLabel} Auto-Reply error: $e. Falling back to ${AiModels.helperServicesFallbackLabel}...');
    }

    // Try fallback helper model
    try {
      final fallbackResponse = await _fallbackModel.generateContent([Content.text(promptText)]);
      final fallbackReply = fallbackResponse.text?.trim();
      if (fallbackReply != null && fallbackReply.isNotEmpty) {
        return fallbackReply;
      }
    } catch (e) {
      debugPrint('${AiModels.helperServicesFallbackLabel} Auto-Reply error: $e');
    }

    // Polite deterministic fallback if AI network fails
    final branchName = branches.isNotEmpty ? branches.first : 'أقرب فرع لموقعك';
    return 'أهلاً بك يا فندم! سعداء بتواصلك معنا. يمكنك زيارة $branchName للاستفادة من أحدث عروض وهدايا حملة ${campaignName ?? "تسهيل جيفت"} واستلام جائزتك فورياً من منسق العرض بالفرع!';
  }

  /// Processes an incoming message and sends the AI reply directly via WhatsApp Gateway
  Future<WhatsAppGatewayResult> processIncomingAndDispatchReply({
    required WhatsAppGatewayConfigModel config,
    required String fromPhone,
    required String customerMessage,
    String? customerName,
    String? companyName,
    String? campaignName,
    List<String> branches = const [],
    List<String> prizes = const [],
  }) async {
    final aiReply = await generateReply(
      customerMessage: customerMessage,
      customerName: customerName,
      companyName: companyName,
      campaignName: campaignName,
      branches: branches,
      prizes: prizes,
      customInstructions: config.aiCustomSystemPrompt,
    );

    return _gatewayService.sendSingleMessage(
      config: config,
      toPhone: fromPhone,
      messageText: aiReply,
    );
  }
}
