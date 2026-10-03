import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/config/ai_config.dart';
import 'package:al_mraay/core/services/ai_model_config_service.dart';
import 'package:al_mraay/core/services/ai_brain_copilot_service.dart';

void main() {
  group('AiAgentMode & Presets Tests', () {
    test('AiAgentMode correctly resolves codes and labels', () {
      expect(AiAgentMode.standardVision.code, equals('standard_vision'));
      expect(AiAgentMode.highReasoning.code, equals('high_reasoning'));
      expect(AiAgentMode.ultraSpeed.code, equals('ultra_speed'));
      expect(AiAgentMode.strictFraudAudit.code, equals('strict_fraud_audit'));

      expect(AiAgentMode.fromCode('standard_vision'), equals(AiAgentMode.standardVision));
      expect(AiAgentMode.fromCode('high_reasoning'), equals(AiAgentMode.highReasoning));
      expect(AiAgentMode.fromCode('ultra_speed'), equals(AiAgentMode.ultraSpeed));
      expect(AiAgentMode.fromCode('strict_fraud_audit'), equals(AiAgentMode.strictFraudAudit));
      expect(AiAgentMode.fromCode('unknown'), equals(AiAgentMode.standardVision));

      expect(AiAgentMode.standardVision.displayNameAr, contains('القياسي'));
      expect(AiAgentMode.highReasoning.displayNameAr, contains('الاستدلال'));
    });

    test('GeminiModelPreset presets contains 3.7 and 3.8 models', () {
      final ids = GeminiModelPreset.presets.map((p) => p.id).toList();
      expect(ids, contains('gemini-3.7-flash'));
      expect(ids, contains('gemini-3.8-flash'));
      expect(ids, contains('gemini-3.8-pro'));
      expect(ids, contains('gemini-3.6-flash'));
      expect(ids, contains('gemini-2.5-flash'));
    });
  });

  group('AiModelConfig Serialization & Effective Model Resolution', () {
    test('Default config has gemini-3.7-flash and standardVision', () {
      const config = AiModelConfig();
      expect(config.primaryModel, equals('gemini-3.7-flash'));
      expect(config.effectivePrimaryModel, equals('gemini-3.7-flash'));
      expect(config.agentMode, equals(AiAgentMode.standardVision));
      expect(config.mode, equals(AiAgentMode.standardVision));
    });

    test('Custom model identifier overrides primary model', () {
      const config = AiModelConfig(
        primaryModel: 'gemini-3.7-flash',
        customModelIdentifier: 'gemini-3.8-ultra',
      );
      expect(config.effectivePrimaryModel, equals('gemini-3.8-ultra'));
    });

    test('toMap and fromMap work round-trip', () {
      final config = AiModelConfig(
        primaryModel: 'gemini-3.8-flash',
        fallbackModel: 'gemini-3.7-flash',
        agentMode: AiAgentMode.ultraSpeed,
        thinkingBudget: 1024,
        customModelIdentifier: 'custom-model-v1',
      );

      final map = config.toMap();
      expect(map['primary_model'], equals('gemini-3.8-flash'));
      expect(map['fallback_model'], equals('gemini-3.7-flash'));
      expect(map['agent_mode'], equals('ultra_speed'));
      expect(map['thinking_budget'], equals(1024));
      expect(map['custom_model_identifier'], equals('custom-model-v1'));

      final reconstructed = AiModelConfig.fromMap(map);
      expect(reconstructed.primaryModel, equals('gemini-3.8-flash'));
      expect(reconstructed.agentMode, equals(AiAgentMode.ultraSpeed));
      expect(reconstructed.effectivePrimaryModel, equals('custom-model-v1'));
    });
  });

  group('AiConfig Dynamic In-Memory Updates', () {
    test('AiConfig.updateActiveModelConfig updates static fields', () {
      final config = AiModelConfig(
        primaryModel: 'gemini-3.8-pro',
        fallbackModel: 'gemini-3.7-flash',
        agentMode: AiAgentMode.highReasoning,
        thinkingBudget: 2048,
      );

      AiConfig.updateActiveModelConfig(
        primary: config.effectivePrimaryModel,
        fallback: config.fallbackModel,
        mode: config.agentMode,
        budget: config.thinkingBudget,
      );

      expect(AiConfig.primaryModel, equals('gemini-3.8-pro'));
      expect(AiConfig.fallbackModel, equals('gemini-3.7-flash'));
      expect(AiConfig.activeAgentMode, equals(AiAgentMode.highReasoning));
      expect(AiConfig.thinkingBudget, equals(2048));
    });
  });

  group('AiBrainChatMessage Telemetry & Simulation Fields', () {
    test('AiBrainChatMessage supports duration, model, and simulation result', () {
      final msg = AiBrainChatMessage(
        id: 'msg_1',
        isUser: false,
        text: 'AI response',
        timestamp: DateTime.now(),
        durationSeconds: 1.8,
        modelNameUsed: 'gemini-3.8-flash',
        simulationResult: {
          'isEligible': true,
          'summary': 'Passed test',
        },
      );

      expect(msg.durationSeconds, equals(1.8));
      expect(msg.modelNameUsed, equals('gemini-3.8-flash'));
      expect(msg.simulationResult?['isEligible'], isTrue);
      expect(msg.simulationResult?['summary'], equals('Passed test'));
    });
  });
}
