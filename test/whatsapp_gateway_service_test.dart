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
      final config = WhatsAppGatewayConfigModel(
        provider: WhatsAppGatewayProvider.ultraMsg,
        instanceId: 'inst_9988',
        apiToken: 'tok_abcdef123',
        delayBetweenMessagesSeconds: 4,
        isEnabled: true,
        isConnected: true,
        connectedPhoneNumber: '201099887766',
      );

      final jsonMap = config.toMap();
      expect(jsonMap['provider'], equals('ultramsg'));
      expect(jsonMap['instanceId'], equals('inst_9988'));
      expect(jsonMap['delayBetweenMessagesSeconds'], equals(4));

      final restored = WhatsAppGatewayConfigModel.fromMap(jsonMap);
      expect(restored.provider, equals(WhatsAppGatewayProvider.ultraMsg));
      expect(restored.instanceId, equals('inst_9988'));
      expect(restored.apiToken, equals('tok_abcdef123'));
      expect(restored.delayBetweenMessagesSeconds, equals(4));
      expect(restored.isConnected, isTrue);
      expect(restored.connectedPhoneNumber, equals('201099887766'));
    });
  });

  group('Mock HTTP Gateway Operations Tests', () {
    test('UltraMsg testConnection returns connected when authenticated is true', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('/instance/status')) {
          return http.Response(
            json.encode({
              'status': {
                'accountStatus': {
                  'status': 'authenticated',
                  'substatus': 'connected',
                }
              }
            }),
            200,
          );
        }
        if (request.url.toString().contains('/instance/me')) {
          return http.Response(
            json.encode({
              'id': '201012345678@c.us',
              'name': 'Omar Fathalla',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = WhatsAppGatewayService();
      final config = const WhatsAppGatewayConfigModel(
        provider: WhatsAppGatewayProvider.ultraMsg,
        instanceId: 'inst_test',
        apiToken: 'tok_test',
      );

      final status = await service.testConnection(config, client: mockClient);
      expect(status.isConnected, isTrue);
      expect(status.phoneNumber, contains('201012345678'));
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

    test('sendSingleMessage sends UltraMsg message successfully', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('/messages/chat')) {
          expect(request.method, equals('POST'));
          return http.Response(
            json.encode({
              'sent': 'true',
              'message': 'ok',
              'id': 'msg_12345',
            }),
            200,
          );
        }
        return http.Response('Error', 500);
      });

      final service = WhatsAppGatewayService();
      final config = const WhatsAppGatewayConfigModel(
        provider: WhatsAppGatewayProvider.ultraMsg,
        instanceId: 'inst_test',
        apiToken: 'tok_test',
      );

      final result = await service.sendSingleMessage(
        config: config,
        toPhone: '01012345678',
        messageText: 'رسالة تجريبية',
        client: mockClient,
      );

      expect(result.isSuccess, isTrue);
      expect(result.messageId, equals('msg_12345'));
    });

    test('fetchStatistics retrieves UltraMsg live message metrics', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('/messages/statistics')) {
          return http.Response(
            json.encode({
              'sent': 45,
              'queue': 2,
              'unsent': 1,
              'invalid': 0,
              'expired': 0,
            }),
            200,
          );
        }
        return http.Response('Error', 500);
      });

      final service = WhatsAppGatewayService();
      final config = const WhatsAppGatewayConfigModel(
        provider: WhatsAppGatewayProvider.ultraMsg,
        instanceId: 'instance190005',
        apiToken: 'v699gpqwmv242cgq',
      );

      final stats = await service.fetchStatistics(config, client: mockClient);
      expect(stats, isNotNull);
      expect(stats!.sentCount, equals(45));
      expect(stats.queueCount, equals(2));
      expect(stats.unsentCount, equals(1));
      expect(stats.totalTracked, equals(48));
    });

    test('restartInstance sends POST to restart UltraMsg session', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('/instance/restart')) {
          return http.Response(json.encode({'status': 'restarting'}), 200);
        }
        return http.Response('Error', 500);
      });

      final service = WhatsAppGatewayService();
      final config = const WhatsAppGatewayConfigModel(
        provider: WhatsAppGatewayProvider.ultraMsg,
        instanceId: 'instance190005',
        apiToken: 'v699gpqwmv242cgq',
      );

      final success = await service.restartInstance(config, client: mockClient);
      expect(success, isTrue);
    });

    test('fetchMessagesList parses UltraMsg outbox messages and pagination correctly', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('/messages')) {
          expect(request.url.queryParameters['status'], equals('all'));
          return http.Response.bytes(
            utf8.encode(json.encode({
              'total': 2,
              'pages': 1,
              'limit': 10,
              'page': 1,
              'messages': [
                {
                  'id': 2,
                  'from': '201211857725@c.us',
                  'to': '201285483486@c.us',
                  'body': 'رسالة تجريبية 2',
                  'status': 'invalid',
                  'created_at': 1788040205,
                  'sent_at': 1788040205,
                },
                {
                  'id': 1,
                  'from': '201211857725@c.us',
                  'to': '201147531222@c.us',
                  'body': 'رسالة تجريبية 1',
                  'status': 'sent',
                  'created_at': 1788040199,
                  'sent_at': 1788040200,
                },
              ],
            })),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('Error', 500);
      });

      final service = WhatsAppGatewayService();
      final config = const WhatsAppGatewayConfigModel(
        provider: WhatsAppGatewayProvider.ultraMsg,
        instanceId: 'instance190005',
        apiToken: 'v699gpqwmv242cgq',
      );

      final result = await service.fetchMessagesList(config: config, client: mockClient);
      expect(result.total, equals(2));
      expect(result.messages.length, equals(2));
      expect(result.messages.first.id, equals('2'));
      expect(result.messages.first.toPhone, equals('201285483486'));
      expect(result.messages.first.status, equals('invalid'));
      expect(result.messages.last.id, equals('1'));
      expect(result.messages.last.status, equals('sent'));
    });
  });
}
