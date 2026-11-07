import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/client_portal/presentation/client_receipt_upload_screen.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/core/widgets/m3_adaptive_scaffold.dart';
import 'package:al_mraay/core/localization/locale_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testEvent = EventModel(
    id: 'test-event-123',
    eventName: 'عرض مهرجان الصيف',
    welcomeTitle: 'أهلاً بكم في مهرجان الصيف',
    welcomeMessage: 'ارفع فاتورة مشترياتك وادخل السحب على جوائز قيمة',
    targetCompany: 'العثيم',
    companyLogoUrl: '',
    minimumSpend: 150.0,
    termsAndConditions: 'تطبق الشروط والأحكام. الفاتورة صالحة لمرة واحدة فقط.',
    gameType: 'spinTheWheel',
    allocatedPrizes: [],
    createdAt: DateTime.now(),
  );

  Widget createTestWidget({required Size screenSize, Locale locale = const Locale('ar')}) {
    return ProviderScope(
      overrides: [
        localeProvider.overrideWith((ref) => locale),
      ],
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
              data: MediaQueryData(size: screenSize),
              child: ClientReceiptUploadScreen(event: testEvent),
            ),
          );
        },
      ),
    );
  }

  group('ClientReceiptUploadScreen Responsive UI Tests', () {
    testWidgets('Renders cleanly on Mobile screen (390x844) with all components', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget(screenSize: const Size(390, 844)));
      await tester.pumpAndSettle();

      // Check Hero Title & Welcome
      expect(find.text('أهلاً بكم في مهرجان الصيف'), findsOneWidget);
      expect(find.text('ارفع فاتورة مشترياتك وادخل السحب على جوائز قيمة'), findsOneWidget);

      // Check minimum spend badge
      expect(find.textContaining('150'), findsOneWidget);

      // Check Name and Phone TextFields
      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(2));

      final nameField = tester.widget<TextField>(textFields.first);
      expect(nameField.textInputAction, TextInputAction.next);

      final phoneField = tester.widget<TextField>(textFields.last);
      expect(phoneField.textInputAction, TextInputAction.done);
      expect(phoneField.keyboardType, TextInputType.phone);

      // Check Camera and Gallery action buttons
      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
      expect(find.byIcon(Icons.photo_library_rounded), findsOneWidget);

      // Check Terms and Conditions
      expect(find.textContaining('تطبق الشروط والأحكام'), findsOneWidget);
      expect(find.byIcon(Icons.gavel_rounded), findsOneWidget);
    });

    testWidgets('Renders cleanly on Desktop / Tablet screen (1024x768)', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget(screenSize: const Size(1024, 768)));
      await tester.pumpAndSettle();

      expect(find.text('أهلاً بكم في مهرجان الصيف'), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
      expect(find.byIcon(Icons.photo_library_rounded), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('Translates seamlessly into English on mobile', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        createTestWidget(
          screenSize: const Size(390, 844),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Camera and Gallery buttons in English
      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
      expect(find.byIcon(Icons.photo_library_rounded), findsOneWidget);
    });

    testWidgets('Displays clear suffix icon when text is entered and clears text on tap', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget(screenSize: const Size(390, 844)));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(2));

      // Enter name
      await tester.enterText(textFields.first, 'Omar Fathalla');
      await tester.pumpAndSettle();
      expect(find.text('Omar Fathalla'), findsOneWidget);
      expect(find.byIcon(Icons.clear_rounded), findsOneWidget);

      // Enter phone
      await tester.enterText(textFields.last, '01211857725');
      await tester.pumpAndSettle();
      expect(find.text('01211857725'), findsOneWidget);
      expect(find.byIcon(Icons.clear_rounded), findsNWidgets(2));

      // Tap clear on phone
      await tester.tap(find.byIcon(Icons.clear_rounded).last);
      await tester.pumpAndSettle();
      expect(find.text('01211857725'), findsNothing);

      // Tap clear on name
      await tester.tap(find.byIcon(Icons.clear_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Omar Fathalla'), findsNothing);
    });

    testWidgets('Renders M3SupportingPaneLayout with dual-pane layout on Desktop (1200x800)', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget(screenSize: const Size(1200, 800)));
      await tester.pumpAndSettle();

      // Verify M3SupportingPaneLayout is present
      expect(find.byType(M3SupportingPaneLayout), findsOneWidget);

      // Verify supporting pane content: Campaign Guide & Quick actions
      expect(find.text('دليل وقواعد الحملة'), findsNothing); // merged into brief dialog
      expect(find.text('مرجع سريع للبروموتر والمبيعات'), findsNothing);
      expect(find.text('الشروط'), findsNothing);
      expect(find.text('الهدايا'), findsNothing);
      expect(find.text('الفواتير'), findsNothing);

      // Verify Minimum Spend in supporting pane
      expect(find.text('الحد الأدنى للشراء:'), findsOneWidget);
    });

    testWidgets('Renders M3SupportingPaneLayout in English LTR without overflow on Desktop (1200x800)', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        createTestWidget(
          screenSize: const Size(1200, 800),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Verify English supporting pane headers
      expect(find.text('Campaign Guide'), findsNothing); // merged into brief dialog
      expect(find.text('Promoter Quick Reference'), findsNothing);
      expect(find.text('Rules'), findsNothing);
      expect(find.text('Prizes'), findsNothing);
      expect(find.text('Invoices'), findsNothing);
      expect(find.text('Minimum Spend:'), findsOneWidget);
    });
  });
}
