import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:al_mraay/features/company_portal/domain/whatsapp_gateway_config_model.dart';
import 'package:al_mraay/features/company_portal/domain/whatsapp_gateway_service.dart';
import 'package:al_mraay/features/company_portal/presentation/widgets/whatsapp_campaign_dispatcher_dialog.dart';

void main() {
  group('WhatsAppGatewayService & Phone Normalization Tests', () {
    test('Formats Egyptian local mobile numbers accurately to international format', () {
      expect(WhatsAppGatewayService.formatInternationalPhone('01012345678'), equals('201012345678'));
      expect(WhatsAppGatewayService.formatInternationalPhone('01123456789'), equals('201123456789'));
      expect(WhatsAppGatewayService.formatInternationalPhone('01234567890'), equals('201234567890'));
      expect(WhatsAppGatewayService.formatInternationalPhone('01512345678'), equals('201512345678'));
    });

    test('Normalizes Eastern Arabic (٠-٩) numerals in Egyptian phone numbers', () {
      expect(WhatsAppGatewayService.formatInternationalPhone('٠١٠١٢٣٤٥٦٧٨'), equals('201012345678'));
      expect(WhatsAppGatewayService.formatInternationalPhone('٠١١٥٥٥٦٦٦٧٧'), equals('201155566677'));
    });

    test('Handles international numbers with leading + or 00 correctly', () {
      expect(WhatsAppGatewayService.formatInternationalPhone('+971501234567'), equals('971501234567'));
      expect(WhatsAppGatewayService.formatInternationalPhone('00966501234567'), equals('966501234567'));
      expect(WhatsAppGatewayService.formatInternationalPhone('+20 10 1234 5678'), equals('201012345678'));
    });

    test('Personalized message template substitutes all customer smart tags', () {
      final contact = CustomerCampaignContact(
        id: 'c1',
        name: 'أحمد محمود',
        rawPhone: '01012345678',
        cleanPhone: '201012345678',
        totalSpend: 1500,
        totalInvoices: 3,
        prizesWon: ['قسيمة 50 ج.م', 'شامبو تريسمي'],
        branches: ['سموحة', 'سيدي جابر'],
        lastBranch: 'سموحة',
      );

      const template = 'مرحباً {اسم_العميل}! زُرنا في فرع {الفرع} ضمن حملة {الحملة} لشركة {الشركة}. مبروك هداياك: {الهدايا}، مشترياتك: {المشتريات}.';

      final result = WhatsAppGatewayService.buildPersonalizedMessage(
        template: template,
        contact: contact,
        companyName: 'يونيليفر',
        campaignName: 'مهرجان الصيف',
      );

      expect(result, contains('مرحباً أحمد محمود!'));
      expect(result, contains('فرع سموحة'));
      expect(result, contains('حملة مهرجان الصيف'));
      expect(result, contains('لشركة يونيليفر'));
      expect(result, contains('قسيمة 50 ج.م, شامبو تريسمي'));
      expect(result, contains('1500 ج.م'));
    });

    test('WhatsAppGatewayConfigModel serializes and deserializes accurately', () {
      final config = const WhatsAppGatewayConfigModel(
        provider: WhatsAppGatewayProvider.waha,
        instanceId: 'default',
        apiToken: 'tashil_secret_token_2026',
        customEndpointUrl: 'http://76.13.14.23:3000',
        delayBetweenMessagesSeconds: 4,
        isEnabled: true,
        isConnected: true,
        connectedPhoneNumber: '201211857725',
      );

      final jsonMap = config.toMap();
      expect(jsonMap['provider'], equals('waha'));
      expect(jsonMap['customEndpointUrl'], equals('http://76.13.14.23:3000'));
      expect(jsonMap['delayBetweenMessagesSeconds'], equals(4));

      final restored = WhatsAppGatewayConfigModel.fromMap(jsonMap);
      expect(restored.provider, equals(WhatsAppGatewayProvider.waha));
      expect(restored.customEndpointUrl, equals('http://76.13.14.23:3000'));
      expect(restored.apiToken, equals('tashil_secret_token_2026'));
      expect(restored.delayBetweenMessagesSeconds, equals(4));
      expect(restored.isConnected, isTrue);
      expect(restored.connectedPhoneNumber, equals('201211857725'));

      // Test that legacy ultramsg provider ID safely maps to waha
      final legacyRestored = WhatsAppGatewayConfigModel.fromMap({'provider': 'ultramsg'});
      expect(legacyRestored.provider, equals(WhatsAppGatewayProvider.waha));
    });
  });

  group('Mock HTTP Gateway Operations Tests', () {
    test('WAHA testConnection returns connected when session is WORKING', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('/api/sessions/default')) {
          expect(request.headers['X-Api-Key'], equals('tashil_secret_token_2026'));
          return http.Response(
            json.encode({
              'name': 'default',
              'status': 'WORKING',
              'me': {
                'id': '201211857725@c.us',
                'pushName': 'Omar Fathalla',
              },
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = WhatsAppGatewayService();
      final config = const WhatsAppGatewayConfigModel(
        provider: WhatsAppGatewayProvider.waha,
        instanceId: 'default',
        apiToken: 'tashil_secret_token_2026',
        customEndpointUrl: 'http://76.13.14.23:3000',
      );

      final status = await service.testConnection(config, client: mockClient);
      expect(status.isConnected, isTrue);
      expect(status.phoneNumber, contains('201211857725'));
      expect(status.phoneNumber, contains('Omar Fathalla'));
    });

    test('Green API testConnection returns connected when stateInstance is authorized', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('/getStateInstance/')) {
          return http.Response(
            json.encode({
              'stateInstance': 'authorized',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = WhatsAppGatewayService();
      final config = const WhatsAppGatewayConfigModel(
        provider: WhatsAppGatewayProvider.greenApi,
        instanceId: '110199',
        apiToken: 'tok_green',
      );

      final status = await service.testConnection(config, client: mockClient);
      expect(status.isConnected, isTrue);
      expect(status.statusDetails, contains('Authorized'));
    });

    test('sendSingleMessage sends WAHA message successfully', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('/api/sendText')) {
          expect(request.method, equals('POST'));
          expect(request.headers['X-Api-Key'], equals('tashil_secret_token_2026'));
          final body = json.decode(request.body) as Map<String, dynamic>;
          expect(body['session'], equals('default'));
          expect(body['chatId'], equals('201012345678@c.us'));
          expect(body['text'], equals('رسالة تجريبية'));
          return http.Response(
            json.encode({
              'id': 'msg_waha_12345',
            }),
            200,
          );
        }
        return http.Response('Error', 500);
      });

      final service = WhatsAppGatewayService();
      final config = const WhatsAppGatewayConfigModel(
        provider: WhatsAppGatewayProvider.waha,
        instanceId: 'default',
        apiToken: 'tashil_secret_token_2026',
        customEndpointUrl: 'http://76.13.14.23:3000',
      );

      final result = await service.sendSingleMessage(
        config: config,
        toPhone: '01012345678',
        messageText: 'رسالة تجريبية',
        client: mockClient,
      );

      expect(result.isSuccess, isTrue);
      expect(result.messageId, equals('msg_waha_12345'));
    });

    test('fetchStatistics retrieves WAHA live message metrics', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('/api/default/chats')) {
          return http.Response.bytes(
            utf8.encode(json.encode([
              {
                'id': {'_serialized': '201012345678@c.us'},
                'lastMessage': {
                  'fromMe': true,
                  'body': 'مرحبا',
                  'timestamp': 1789848307,
                },
              },
              {
                'id': {'_serialized': '201099887766@c.us'},
                'lastMessage': {
                  'fromMe': false,
                  'body': 'شكرا',
                  'timestamp': 1789848308,
                },
              },
            ])),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('Error', 500);
      });

      final service = WhatsAppGatewayService();
      final config = const WhatsAppGatewayConfigModel(
        provider: WhatsAppGatewayProvider.waha,
        instanceId: 'default',
        apiToken: 'tashil_secret_token_2026',
        customEndpointUrl: 'http://76.13.14.23:3000',
      );

      final stats = await service.fetchStatistics(config, client: mockClient);
      expect(stats, isNotNull);
      expect(stats!.sentCount, equals(1));
    });

    test('restartInstance sends POST to restart WAHA session', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('/api/sessions/default/restart')) {
          expect(request.headers['X-Api-Key'], equals('tashil_secret_token_2026'));
          return http.Response(json.encode({'status': 'restarted'}), 200);
        }
        return http.Response('Error', 500);
      });

      final service = WhatsAppGatewayService();
      final config = const WhatsAppGatewayConfigModel(
        provider: WhatsAppGatewayProvider.waha,
        instanceId: 'default',
        apiToken: 'tashil_secret_token_2026',
        customEndpointUrl: 'http://76.13.14.23:3000',
      );

      final success = await service.restartInstance(config, client: mockClient);
      expect(success, isTrue);
    });

    test('fetchMessagesList parses WAHA outbox messages correctly', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('/api/default/chats')) {
          return http.Response.bytes(
            utf8.encode(json.encode([
              {
                'id': {'_serialized': '201285483486@c.us'},
                'lastMessage': {
                  'id': 'msg_002',
                  'from': '201211857725@c.us',
                  'to': '201285483486@c.us',
                  'body': 'رسالة تجريبية 2',
                  'fromMe': true,
                  'timestamp': 1788040205,
                  'ack': 3,
                },
              },
              {
                'id': {'_serialized': '201147531222@c.us'},
                'lastMessage': {
                  'id': 'msg_001',
                  'from': '201211857725@c.us',
                  'to': '201147531222@c.us',
                  'body': 'رسالة تجريبية 1',
                  'fromMe': true,
                  'timestamp': 1788040199,
                  'ack': 2,
                },
              },
            ])),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('Error', 500);
      });

      final service = WhatsAppGatewayService();
      final config = const WhatsAppGatewayConfigModel(
        provider: WhatsAppGatewayProvider.waha,
        instanceId: 'default',
        apiToken: 'tashil_secret_token_2026',
        customEndpointUrl: 'http://76.13.14.23:3000',
      );

      final result = await service.fetchMessagesList(config: config, client: mockClient);
      expect(result.total, equals(2));
      expect(result.messages.length, equals(2));
      expect(result.messages.first.id, equals('msg_002'));
      expect(result.messages.first.toPhone, equals('201285483486'));
      expect(result.messages.first.status, equals('sent'));
      expect(result.messages.last.id, equals('msg_001'));
      expect(result.messages.last.status, equals('sent'));
    });

    test('sendPollMessage validates question and strips empty options, rejecting < 2 options', () async {
      final service = WhatsAppGatewayService();
      const config = WhatsAppGatewayConfigModel(
        provider: WhatsAppGatewayProvider.waha,
        instanceId: 'default',
        apiToken: 'tashil_secret_token_2026',
        customEndpointUrl: 'http://76.13.14.23:3000',
      );

      // Test 1: Empty question
      final res1 = await service.sendPollMessage(
        config: config,
        toPhone: '01012345678',
        pollTitle: '   ',
        pollOptions: ['Option 1', 'Option 2'],
      );
      expect(res1.isSuccess, isFalse);
      expect(res1.error, contains('سؤال الاستطلاع مطلوب'));

      // Test 2: Less than 2 non-empty options
      final res2 = await service.sendPollMessage(
        config: config,
        toPhone: '01012345678',
        pollTitle: 'سؤال تجريبي',
        pollOptions: ['Option 1', '  '],
      );
      expect(res2.isSuccess, isFalse);
      expect(res2.error, contains('يتطلب الاستطلاع خيارين على الأقل'));
    });

    test('sendBatchStream correctly marks failure status on error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"error": "Forbidden"}', 403);
      });

      final service = WhatsAppGatewayService();
      const config = WhatsAppGatewayConfigModel(
        provider: WhatsAppGatewayProvider.waha,
        instanceId: 'default',
        apiToken: 'tashil_secret_token_2026',
        customEndpointUrl: 'http://76.13.14.23:3000',
      );

      final contact = CustomerCampaignContact(
        id: 'c1',
        name: 'عميل تجريبي',
        rawPhone: '01012345678',
        cleanPhone: '201012345678',
        totalSpend: 100,
        totalInvoices: 1,
        prizesWon: [],
        branches: ['الفرع الرئيسي'],
        lastBranch: 'الفرع الرئيسي',
        status: ContactDispatchStatus.pending,
      );

      BatchProgressEvent? lastEvent;
      await for (final event in service.sendBatchStream(
        config: config,
        contacts: [contact],
        template: 'مرحبا {اسم_العميل}',
        companyName: 'الشركة',
        campaignName: 'الحملة',
        client: mockClient,
      )) {
        lastEvent = event;
      }

      expect(lastEvent?.isCompleted, isTrue);
      expect(contact.status, equals(ContactDispatchStatus.failed));
    });
  });
}
