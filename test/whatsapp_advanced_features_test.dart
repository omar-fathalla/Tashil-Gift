import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:al_mraay/features/company_portal/domain/whatsapp_gateway_config_model.dart';
import 'package:al_mraay/features/company_portal/domain/whatsapp_gateway_service.dart';
import 'package:al_mraay/features/company_portal/domain/whatsapp_ai_auto_reply_service.dart';

void main() {
  group('WAHA Advanced Features 1-6 Tests', () {
    const baseConfig = WhatsAppGatewayConfigModel(
      provider: WhatsAppGatewayProvider.waha,
      instanceId: 'default',
      apiToken: 'tashil_secret_token_2026',
      customEndpointUrl: 'http://76.13.14.23:3000',
      delayBetweenMessagesSeconds: 2,
      isEnabled: true,
      isConnected: true,
      connectedPhoneNumber: '201211857725',
      enableTypingSimulation: true,
      typingDurationSeconds: 3,
      enableAiAutoReply: true,
      aiCustomSystemPrompt: 'رد بلباقة باللهجة المصرية كمسؤول خدمة عملاء تسهيل جيفت',
    );

    test('Config Model accurately serializes and restores typing simulation and AI bot fields', () {
      final map = baseConfig.toMap();
      expect(map['enableTypingSimulation'], isTrue);
      expect(map['typingDurationSeconds'], equals(3));
      expect(map['enableAiAutoReply'], isTrue);
      expect(map['aiCustomSystemPrompt'], equals('رد بلباقة باللهجة المصرية كمسؤول خدمة عملاء تسهيل جيفت'));

      final restored = WhatsAppGatewayConfigModel.fromMap(map);
      expect(restored.enableTypingSimulation, isTrue);
      expect(restored.typingDurationSeconds, equals(3));
      expect(restored.enableAiAutoReply, isTrue);
      expect(restored.aiCustomSystemPrompt, equals('رد بلباقة باللهجة المصرية كمسؤول خدمة عملاء تسهيل جيفت'));
    });

    // Feature 1: Media Messaging
    test('Feature 1: sendMediaMessage posts image URL with caption to /api/sendImage', () async {
      final service = WhatsAppGatewayService();
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/sendImage'));
        expect(request.headers['X-Api-Key'], equals('tashil_secret_token_2026'));
        expect(request.headers['Content-Type'], contains('application/json'));

        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body['chatId'], equals('201012345678@c.us'));
        expect(body['session'], equals('default'));
        expect(body['caption'], equals('عرض الصيف الحصري'));
        expect(body['file']['url'], equals('https://example.com/poster.jpg'));

        return http.Response(json.encode({'id': 'msg_media_123', 'status': 'sent'}), 200);
      });

      final result = await service.sendMediaMessage(
        config: baseConfig,
        toPhone: '01012345678',
        mediaUrl: 'https://example.com/poster.jpg',
        caption: 'عرض الصيف الحصري',
        client: mockClient,
      );

      expect(result.isSuccess, isTrue);
      expect(result.messageId, equals('msg_media_123'));
    });

    // Feature 2: Interactive Polls
    test('Feature 2: sendPollMessage posts poll question and options to /api/sendPoll', () async {
      final service = WhatsAppGatewayService();
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/sendPoll'));
        expect(request.headers['X-Api-Key'], equals('tashil_secret_token_2026'));

        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body['chatId'], equals('201211857725@c.us'));
        expect(body['session'], equals('default'));
        final poll = body['poll'] as Map<String, dynamic>;
        expect(poll['name'], equals('ما هو فرعك المفضل للاستلام؟'));
        expect(poll['options'], equals(['سموحة', 'سيدي جابر', 'المنتزه']));
        expect(poll['multipleAnswers'], isFalse);

        return http.Response(json.encode({'id': 'msg_poll_456'}), 200);
      });

      final result = await service.sendPollMessage(
        config: baseConfig,
        toPhone: '01211857725',
        pollTitle: 'ما هو فرعك المفضل للاستلام؟',
        pollOptions: ['سموحة', 'سيدي جابر', 'المنتزه'],
        multipleAnswers: false,
        client: mockClient,
      );

      expect(result.isSuccess, isTrue);
      expect(result.messageId, equals('msg_poll_456'));
    });

    // Feature 3: Typing Simulator
    test('Feature 3: startTyping and stopTyping send correct chat presence to WAHA', () async {
      final service = WhatsAppGatewayService();
      bool started = false;
      bool stopped = false;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/startTyping') {
          started = true;
          final body = json.decode(request.body);
          expect(body['chatId'], equals('201555555555@c.us'));
          return http.Response(json.encode({'success': true}), 200);
        } else if (request.url.path == '/api/stopTyping') {
          stopped = true;
          final body = json.decode(request.body);
          expect(body['chatId'], equals('201555555555@c.us'));
          return http.Response(json.encode({'success': true}), 200);
        }
        return http.Response('Not Found', 404);
      });

      await service.startTyping(config: baseConfig, toPhone: '01555555555', client: mockClient);
      await service.stopTyping(config: baseConfig, toPhone: '01555555555', client: mockClient);

      expect(started, isTrue);
      expect(stopped, isTrue);
    });

    // Feature 4: Filter Active WhatsApp Numbers
    test('Feature 4: checkNumberExists queries /api/contacts/check-exists correctly', () async {
      final service = WhatsAppGatewayService();
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/contacts/check-exists'));
        final phone = request.url.queryParameters['phone'];
        if (phone == '201012345678') {
          return http.Response(json.encode({'numberExists': true}), 200);
        } else if (phone == '201099999999') {
          return http.Response(json.encode({'numberExists': false}), 200);
        }
        return http.Response('Error', 500);
      });

      final active = await service.checkNumberExists(
        config: baseConfig,
        rawPhone: '01012345678',
        client: mockClient,
      );
      final inactive = await service.checkNumberExists(
        config: baseConfig,
        rawPhone: '01099999999',
        client: mockClient,
      );

      expect(active, isTrue);
      expect(inactive, isFalse);
    });

    // Feature 5: AI Auto-Reply Bot
    test('Feature 5: WhatsAppAiAutoReplyService returns polite context-aware fallback when offline', () async {
      final aiService = WhatsAppAiAutoReplyService();

      final reply = await aiService.generateReply(
        customerMessage: 'أين فرعكم في سموحة؟',
        companyName: 'يونيليفر مصر',
        campaignName: 'مهرجان الهدايا',
        customerName: 'أحمد محمود',
        branches: ['سموحة (الإسكندرية)', 'سيدي جابر'],
        prizes: ['قسيمة 50 ج.م'],
        customInstructions: 'رد بلباقة وسرعة باللهجة المصرية',
      );

      expect(reply, isNotNull);
      expect(reply.isNotEmpty, isTrue);
      expect(reply, contains('سموحة'));
    });

    // Feature 6: Live Screenshot Button
    test('Feature 6: fetchLiveScreenshot retrieves screenshot bytes or base64 from /api/screenshot', () async {
      final service = WhatsAppGatewayService();
      final dummyPngBytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13]);

      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/screenshot'));
        expect(request.headers['X-Api-Key'], equals('tashil_secret_token_2026'));
        return http.Response.bytes(dummyPngBytes, 200, headers: {'content-type': 'image/png'});
      });

      final screenshot = await service.fetchLiveScreenshot(
        config: baseConfig,
        client: mockClient,
      );

      expect(screenshot, isNotNull);
      expect(screenshot!.length, equals(dummyPngBytes.length));
      expect(screenshot[0], equals(137));
      expect(screenshot[1], equals(80)); // 'P'
      expect(screenshot[2], equals(78)); // 'N'
      expect(screenshot[3], equals(71)); // 'G'
    });
  });
}
