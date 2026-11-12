import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/features/company_portal/domain/whatsapp_campaign_media.dart';
import 'package:al_mraay/features/company_portal/domain/whatsapp_gateway_config_model.dart';
import 'package:al_mraay/features/company_portal/domain/whatsapp_gateway_service.dart';
import 'package:al_mraay/features/company_portal/presentation/widgets/whatsapp_campaign_dispatcher_dialog.dart';
import 'package:al_mraay/features/company_portal/presentation/widgets/whatsapp_campaign_media_panel.dart';

void main() {
  final pdfBytes = Uint8List.fromList(const [
    0x25,
    0x50,
    0x44,
    0x46,
    0x2D,
    0x31,
    0x2E,
    0x34,
    0x0A,
  ]);
  final pngBytes = Uint8List.fromList(const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
  ]);
  final jpegBytes = Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9]);

  group('campaign media authorization and file names', () {
    test('an uploaded file is sent instead of a pasted link', () {
      const uploaded = WhatsAppCampaignMediaAttachment(
        downloadUrl:
            'https://firebasestorage.googleapis.com/v0/b/tashil-gift.appspot.com/o/a.pdf?alt=media&token=abc',
        fileName: 'a.pdf',
        displayName: 'a.pdf',
        mimeType: 'application/pdf',
        storagePath: 'whatsapp_campaign_media/adminUid1/1_a.pdf',
        isPdf: true,
      );
      final chosen = resolveWhatsAppCampaignOutboundMedia(
        mediaMode: true,
        uploaded: uploaded,
        pastedUrl: 'https://example.com/other.jpg',
      );
      expect(chosen.url, uploaded.downloadUrl);
      expect(chosen.mimeType, 'application/pdf');
      expect(chosen.fileName, 'a.pdf');

      final fallback = resolveWhatsAppCampaignOutboundMedia(
        mediaMode: true,
        pastedUrl: 'https://example.com/files/supervisors.pdf',
      );
      expect(fallback.url, 'https://example.com/files/supervisors.pdf');
      expect(fallback.mimeType, isNull);

      final textMode = resolveWhatsAppCampaignOutboundMedia(
        mediaMode: false,
        uploaded: uploaded,
        pastedUrl: 'https://example.com/files/supervisors.pdf',
      );
      expect(textMode.url, isNull);
    });

    test('only super_admin and admin may upload', () {
      expect(
        canManageWhatsAppCampaignMedia(role: 'admin', isAnonymous: false),
        isTrue,
      );
      expect(
        canManageWhatsAppCampaignMedia(role: 'super_admin', isAnonymous: false),
        isTrue,
      );
      expect(
        canManageWhatsAppCampaignMedia(role: 'partner', isAnonymous: false),
        isFalse,
      );
      expect(
        canManageWhatsAppCampaignMedia(role: 'admin', isAnonymous: true),
        isFalse,
      );
      expect(
        canManageWhatsAppCampaignMedia(role: null, isAnonymous: false),
        isFalse,
      );
      expect(
        canManageWhatsAppCampaignMedia(role: '', isAnonymous: false),
        isFalse,
      );
    });

    test(
      'admin upload stores a PDF under an unguessable prefix and ignores a partner',
      () async {
        final storage = _MemoryCampaignStorage();
        final admin = _uploader(storage, role: 'admin');
        final attachment = await admin.upload(
          bytes: pdfBytes,
          fileName: r'..\تقرير المشرفين (نهائي).pdf',
        );

        expect(storage.uploads, 1);
        expect(attachment.isPdf, isTrue);
        expect(attachment.mimeType, 'application/pdf');
        expect(attachment.fileName, 'تقرير_المشرفين_نهائي.pdf');
        expect(attachment.displayName, 'تقرير المشرفين (نهائي).pdf');
        expect(
          attachment.storagePath,
          'whatsapp_campaign_media/adminUid1/1731440000000_${attachment.fileName}',
        );
        expect(attachment.storagePath.contains('..'), isFalse);
        expect(attachment.storagePath.contains('\\'), isFalse);
        expect(storage.lastType, 'application/pdf');
        expect(storage.lastMeta?['uploaderUid'], 'adminUid1');
        expect(attachment.downloadUrl, contains('token='));
        expect(attachment.downloadUrl, startsWith('https://'));
        expect(
          RegExp(r'/1731440000000_').hasMatch(attachment.storagePath),
          isTrue,
        );

        final partner = _uploader(_MemoryCampaignStorage(), role: 'partner');
        await expectLater(
          partner.upload(bytes: pdfBytes, fileName: 'secret.pdf'),
          throwsA(
            isA<WhatsAppCampaignMediaUploadException>().having(
              (error) => error.failure,
              'failure',
              WhatsAppCampaignMediaFailure.unauthorized,
            ),
          ),
        );

        final anonymous = _uploader(storage, role: 'admin', anonymous: true);
        await expectLater(
          anonymous.upload(bytes: pdfBytes, fileName: 'secret.pdf'),
          throwsA(isA<WhatsAppCampaignMediaUploadException>()),
        );
        expect(storage.uploads, 1);
      },
    );

    test('file bytes choose PDF vs image, and a bad file is refused', () async {
      final storage = _MemoryCampaignStorage();
      final admin = _uploader(storage, role: 'super_admin', uid: 'superUid');

      final imageNamedAsPdf = await admin.upload(
        bytes: pngBytes,
        fileName: 'poster.pdf',
      );
      expect(imageNamedAsPdf.isPdf, isFalse);
      expect(imageNamedAsPdf.mimeType, 'image/png');
      expect(imageNamedAsPdf.fileName, endsWith('.png'));
      expect(storage.lastType, 'image/png');

      final photo = await admin.upload(bytes: jpegBytes, fileName: 'Photo.JPG');
      expect(photo.mimeType, 'image/jpeg');
      expect(photo.fileName, 'Photo.jpg');

      expect(
        detectWhatsAppCampaignFileKind(
          fileName: 'notes.bin',
          contentType: 'application/pdf',
        ),
        isNotNull,
      );
      expect(
        detectWhatsAppCampaignFileKind(
          fileName: 'notes.pdf',
          contentType: 'text/plain',
        ),
        isNull,
      );
      expect(
        detectWhatsAppCampaignFileKind(
          fileName: 'notes.pdf',
          contentType: 'image/png',
        ),
        isNull,
      );
      expect(
        detectWhatsAppCampaignFileKind(fileName: 'notes.pdf')?.mimeType,
        'application/pdf',
      );
      expect(
        normalizeWhatsAppCampaignMime('image/jpg; charset=binary'),
        'image/jpeg',
      );

      await expectLater(
        admin.upload(
          bytes: Uint8List.fromList(const [1, 2, 3, 4, 5]),
          fileName: 'notes.pdf',
        ),
        throwsA(
          isA<WhatsAppCampaignMediaUploadException>().having(
            (error) => error.failure,
            'failure',
            WhatsAppCampaignMediaFailure.unsupportedType,
          ),
        ),
      );
      await expectLater(
        admin.upload(bytes: Uint8List(0), fileName: 'notes.pdf'),
        throwsA(
          isA<WhatsAppCampaignMediaUploadException>().having(
            (error) => error.failure,
            'failure',
            WhatsAppCampaignMediaFailure.empty,
          ),
        ),
      );
    });

    test(
      'clearing a file is refused for a partner and allowed for an admin',
      () async {
        final storage = _MemoryCampaignStorage();
        await _uploader(
          storage,
          role: 'partner',
        ).delete('whatsapp_campaign_media/adminUid1/1_a.pdf');
        expect(storage.deletes, 0);
        await _uploader(
          storage,
          role: 'admin',
        ).delete('whatsapp_campaign_media/adminUid1/1_a.pdf');
        expect(storage.deletes, 1);
        await _uploader(
          storage,
          role: 'admin',
        ).delete('company_logos/logo.png');
        expect(storage.deletes, 1);
      },
    );
  });

  group('uploaded media uses the WAHA file or image route', () {
    const config = WhatsAppGatewayConfigModel(
      provider: WhatsAppGatewayProvider.waha,
      instanceId: 'default',
      apiToken: 'test-waha-token',
      customEndpointUrl: 'http://76.13.14.23:3000',
      enableTypingSimulation: false,
    );

    WhatsAppGatewayService service() {
      return WhatsAppGatewayService(
        wahaAuthHeadersBuilder: () async => {
          'Authorization': 'Bearer test-id-token',
          'X-Firebase-AppCheck': 'test-app-check',
        },
      );
    }

    test(
      'an uploaded PDF is sent on /api/sendFile from its content type',
      () async {
        final attachment = await _uploader(
          _MemoryCampaignStorage(),
          role: 'admin',
        ).upload(bytes: pdfBytes, fileName: 'supervisors.pdf');
        expect(attachment.downloadUrl.endsWith('.pdf'), isFalse);

        final mock = MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              json.encode({
                'numberExists': true,
                'chatId': '201055500011@c.us',
              }),
              200,
            );
          }
          expect(request.url.path, endsWith('/api/sendFile'));
          final body = json.decode(request.body) as Map<String, dynamic>;
          expect(body['file']['mimetype'], 'application/pdf');
          expect(body['file']['filename'], 'supervisors.pdf');
          expect(body['file']['url'], attachment.downloadUrl);
          return http.Response(json.encode({'id': 'uploaded_pdf'}), 200);
        });

        final result = await service().sendMediaMessage(
          config: config,
          toPhone: '01055500011',
          mediaUrl: attachment.downloadUrl,
          filename: 'supervisors',
          mimeType: attachment.mimeType,
          caption: 'ملف المشرفين',
          client: mock,
        );
        expect(result.isSuccess, isTrue);
        expect(result.messageId, 'uploaded_pdf');
      },
    );

    test(
      'an uploaded image stays on /api/sendImage even if the URL ends in .pdf',
      () async {
        final attachment = await _uploader(
          _MemoryCampaignStorage(),
          role: 'admin',
        ).upload(bytes: pngBytes, fileName: 'poster.pdf');
        expect(attachment.mimeType, 'image/png');

        final misleadingUrl = 'https://cdn.example.com/poster.pdf?token=abc';
        final mock = MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(json.encode({'numberExists': true}), 200);
          }
          expect(request.url.path, endsWith('/api/sendImage'));
          final body = json.decode(request.body) as Map<String, dynamic>;
          expect(body['file']['mimetype'], 'image/png');
          expect(body['file']['filename'], attachment.fileName);
          expect(body['file']['url'], misleadingUrl);
          return http.Response(json.encode({'id': 'uploaded_png'}), 200);
        });

        final result = await service().sendMediaMessage(
          config: config,
          toPhone: '01055500022',
          mediaUrl: misleadingUrl,
          filename: attachment.fileName,
          mimeType: attachment.mimeType,
          caption: 'بوستر',
          client: mock,
        );
        expect(result.isSuccess, isTrue);
      },
    );

    test('a pasted URL ending in .pdf still uses /api/sendFile', () async {
      final mock = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(json.encode({'numberExists': true}), 200);
        }
        expect(request.url.path, endsWith('/api/sendFile'));
        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body['file']['mimetype'], 'application/pdf');
        expect(body['file']['filename'], 'supervisors.pdf');
        expect(
          body['file']['url'],
          'https://example.com/files/supervisors.pdf?token=abc',
        );
        return http.Response(json.encode({'id': 'pasted_pdf'}), 200);
      });

      final result = await service().sendMediaMessage(
        config: config,
        toPhone: '01055500033',
        mediaUrl: 'https://example.com/files/supervisors.pdf?token=abc',
        caption: 'ملف المشرفين',
        client: mock,
      );
      expect(result.isSuccess, isTrue);
      expect(result.messageId, 'pasted_pdf');
    });

    test('sendBatchStream forwards the uploaded PDF type', () async {
      final attachment = await _uploader(
        _MemoryCampaignStorage(),
        role: 'admin',
      ).upload(bytes: pdfBytes, fileName: 'offer.pdf');
      final contact = CustomerCampaignContact(
        id: 'c-pdf',
        name: 'مشرف',
        rawPhone: '01055500044',
        cleanPhone: '201055500044',
        totalSpend: 0,
        totalInvoices: 0,
        prizesWon: const [],
        branches: const ['التجمع'],
        lastBranch: 'التجمع',
      );
      final mock = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            json.encode({'numberExists': true, 'chatId': '201055500044@c.us'}),
            200,
          );
        }
        expect(request.url.path, endsWith('/api/sendFile'));
        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body['file']['mimetype'], attachment.mimeType);
        expect(body['file']['filename'], attachment.fileName);
        expect(body['file']['url'], attachment.downloadUrl);
        return http.Response(json.encode({'id': 'batch_pdf'}), 200);
      });

      BatchProgressEvent? last;
      await for (final event in service().sendBatchStream(
        config: config,
        contacts: [contact],
        template: 'أهلاً {اسم_العميل}',
        companyName: 'الشركة',
        campaignName: 'الحملة',
        attachedMediaUrl: attachment.downloadUrl,
        attachedMediaFileName: attachment.fileName,
        attachedMediaMimeType: attachment.mimeType,
        client: mock,
      )) {
        last = event;
      }
      expect(last?.isCompleted, isTrue);
      expect(contact.status, ContactDispatchStatus.sent);
    });
  });

  testWidgets('compose panel shows the file name when it is ready to send', (
    tester,
  ) async {
    final url = TextEditingController();
    addTearDown(url.dispose);
    var picks = 0;
    var clears = 0;
    const attachment = WhatsAppCampaignMediaAttachment(
      downloadUrl:
          'https://firebasestorage.googleapis.com/v0/b/tashil-gift.appspot.com/o/object?alt=media&token=abc',
      fileName: 'supervisors.pdf',
      displayName: 'supervisors.pdf',
      mimeType: 'application/pdf',
      storagePath: 'whatsapp_campaign_media/adminUid1/1_supervisors.pdf',
      isPdf: true,
    );

    Future<void> pump(WhatsAppCampaignMediaAttachment? current) {
      return tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: WhatsAppCampaignMediaPanel(
                  strings: AppStrings('ar'),
                  isAr: true,
                  urlController: url,
                  attachment: current,
                  uploading: false,
                  progress: 0,
                  onPick: () => picks++,
                  onClear: () => clears++,
                  onUrlChanged: () {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    await pump(null);
    expect(find.text('اختيار ملف من الجهاز'), findsWidgets);
    expect(find.text('رابط بوستر العرض'), findsOneWidget);
    expect(find.text('الملف جاهز للإرسال'), findsNothing);

    await pump(attachment);
    expect(find.text('supervisors.pdf'), findsOneWidget);
    expect(find.text('الملف جاهز للإرسال'), findsOneWidget);
    expect(find.text('استبدال الملف'), findsOneWidget);

    await tester.tap(find.byTooltip('إزالة الملف'));
    await tester.pump();
    expect(clears, 1);

    await tester.tap(find.text('استبدال الملف'));
    await tester.pump();
    expect(picks, 1);

    url.text = 'https://example.com/files/supervisors.pdf';
    await pump(null);
    expect(find.text('سيتم إرسال ملف PDF كمرفق'), findsOneWidget);
  });
}

class _MemoryCampaignStorage implements WhatsAppCampaignMediaStorage {
  int uploads = 0;
  int deletes = 0;
  String? lastPath;
  String? lastType;
  Map<String, String>? lastMeta;

  @override
  Future<String> upload({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    required Map<String, String> customMetadata,
    void Function(int transferred, int total)? onProgress,
  }) async {
    uploads++;
    lastPath = storagePath;
    lastType = contentType;
    lastMeta = customMetadata;
    onProgress?.call(bytes.length, bytes.length);
    return 'https://firebasestorage.googleapis.com/v0/b/tashil-gift.appspot.com/o/${Uri.encodeComponent(storagePath)}?alt=media&token=test-token';
  }

  @override
  Future<void> delete(String storagePath) async {
    deletes++;
  }
}

WhatsAppCampaignMediaUploader _uploader(
  _MemoryCampaignStorage storage, {
  required String? role,
  bool anonymous = false,
  String uid = 'adminUid1',
}) {
  return WhatsAppCampaignMediaUploader(
    storage: storage,
    authorize: () async =>
        canManageWhatsAppCampaignMedia(role: role, isAnonymous: anonymous),
    currentUid: () => anonymous ? null : uid,
    nowMillis: () => 1731440000000,
  );
}
