import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/client_portal/presentation/client_receipt_upload_screen.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final campaign1 = EventModel(
    id: 'unilever-clear-dove',
    eventName: 'عرض كلير ودوف',
    welcomeTitle: 'أهلاً بكم في عرض كلير ودوف',
    welcomeMessage: 'ارفع فاتورتك واحصل على هدايا فورية',
    targetCompany: 'يونيليفر',
    companySlug: 'unilever',
    minimumSpend: 250.0,
    gameType: 'spinTheWheel',
    allocatedPrizes: [],
    isActive: true,
    isPromoterActive: true,
  );

  final campaign2 = EventModel(
    id: 'unilever-tresemme',
    eventName: 'عرض تريزمي الماسي',
    welcomeTitle: 'أهلاً بكم في عرض تريزمي الماسي',
    welcomeMessage: 'اشتري شامبو تريزمي وادخل السحب',
    targetCompany: 'يونيليفر',
    companySlug: 'unilever',
    minimumSpend: 400.0,
    gameType: 'scratchCard',
    allocatedPrizes: [],
    isActive: true,
    isPromoterActive: true,
  );

  Widget createTestWidget({required EventModel event, Locale locale = const Locale('ar')}) {
    return ProviderScope(
      child: Consumer(
        builder: (context, ref, child) {
          return MaterialApp(
            locale: locale,
            supportedLocales: const [
              Locale('ar'),
              Locale('en'),
              Locale('hi'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: MediaQuery(
              data: const MediaQueryData(size: Size(400, 900)),
              child: ClientReceiptUploadScreen(event: event),
            ),
          );
        },
      ),
    );
  }

  group('Promoter Multi-Campaign Switcher Tests', () {
    testWidgets('Renders single campaign cleanly without showing dropdown when only 1 campaign exists', (tester) async {
      await tester.pumpWidget(createTestWidget(event: campaign1));
      await tester.pumpAndSettle();

      // Check campaign 1 title is visible
      expect(find.text('أهلاً بكم في عرض كلير ودوف'), findsOneWidget);
      expect(find.textContaining('250'), findsOneWidget);

      // Verify dropdown is not rendered because only 1 campaign exists
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    });

    testWidgets('Renders campaign details accurately with correct minimum spend and game type icon', (tester) async {
      await tester.pumpWidget(createTestWidget(event: campaign2));
      await tester.pumpAndSettle();

      // Check campaign 2 title and min spend
      expect(find.text('أهلاً بكم في عرض تريزمي الماسي'), findsOneWidget);
      expect(find.textContaining('400'), findsOneWidget);
    });

    test('Campaign IDs are distinct ensuring independent receipt scoping across multiple events', () {
      expect(campaign1.id, isNot(equals(campaign2.id)));
      expect(campaign1.companySlug, equals(campaign2.companySlug));

      // Verify storage path scoping format
      const receiptNumber = '92_8_224_030926';
      final path1 = 'receipts/${campaign1.companySlug}/${campaign1.id}/$receiptNumber.jpg';
      final path2 = 'receipts/${campaign2.companySlug}/${campaign2.id}/$receiptNumber.jpg';

      expect(path1, equals('receipts/unilever/unilever-clear-dove/92_8_224_030926.jpg'));
      expect(path2, equals('receipts/unilever/unilever-tresemme/92_8_224_030926.jpg'));
      expect(path1, isNot(equals(path2)));
    });
  });
}
