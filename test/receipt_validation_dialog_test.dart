import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:al_mraay/features/validation/presentation/widgets/receipt_validation_dialog.dart';

void main() {
  group('Receipt Validation Dialog & Conditions Tests', () {
    test('buildValidationConditionItems builds minimum spend condition when below requirement', () {
      final items = buildValidationConditionItems(
        isValid: false,
        message: 'القيمة غير كافية',
        targetCompanyTotal: 50.0,
        minimumSpend: 150.0,
        targetCompany: 'المراعي',
        currencySymbol: 'ج.م',
      );

      expect(items.any((i) => i.title.contains('الحد الأدنى')), isTrue);
      expect(items.first.description, contains('50.0 ج.م'));
      expect(items.first.description, contains('150.0 ج.م'));
      expect(items.first.isMet, isFalse);
    });

    test('buildValidationConditionItems does NOT build minimum spend condition when minimumSpend <= 0', () {
      final items = buildValidationConditionItems(
        isValid: true,
        message: 'الفاتورة صحيحة',
        targetCompanyTotal: 25.0,
        minimumSpend: 0.0, // Optional minimum spend not configured
        targetCompany: 'المراعي',
        currencySymbol: 'ج.م',
      );

      expect(items.any((i) => i.title.contains('الحد الأدنى')), isFalse);
    });

    test('buildValidationConditionItems builds handwritten fraud condition', () {
      final items = buildValidationConditionItems(
        isValid: false,
        message: 'عذراً، تم رفض الفاتورة لأنها محررة بخط اليد.',
        targetCompanyTotal: 200.0,
        minimumSpend: 150.0,
        targetCompany: 'يونيليفر',
        currencySymbol: 'ج.م',
        isHandwritten: true,
        isThermalPosReceipt: false,
      );

      expect(items.any((i) => i.title.contains('محررة يدوياً')), isTrue);
      expect(items.first.description, contains('بون كاشير إلكتروني'));
      expect(items.first.isMet, isFalse);
    });

    test('buildValidationConditionItems builds tampering and screen capture fraud conditions', () {
      final itemsTampered = buildValidationConditionItems(
        isValid: false,
        message: 'اشتباه في تلاعب بالأرقام',
        targetCompanyTotal: 200.0,
        minimumSpend: 150.0,
        targetCompany: 'يونيليفر',
        currencySymbol: 'ج.م',
        isTampered: true,
      );
      expect(itemsTampered.any((i) => i.title.contains('تلاعب')), isTrue);

      final itemsScreen = buildValidationConditionItems(
        isValid: false,
        message: 'صورة من شاشة',
        targetCompanyTotal: 200.0,
        minimumSpend: 150.0,
        targetCompany: 'يونيليفر',
        currencySymbol: 'ج.م',
        isScreenCapture: true,
      );
      expect(itemsScreen.any((i) => i.title.contains('شاشة إلكترونية')), isTrue);
    });

    test('buildValidationConditionItems builds branch mismatch condition', () {
      final items = buildValidationConditionItems(
        isValid: false,
        message: 'فرع غير مطابق',
        targetCompanyTotal: 200.0,
        minimumSpend: 150.0,
        targetCompany: 'المراعي',
        currencySymbol: 'ج.م',
        isBranchMatched: false,
        storeChainDetected: 'كارفور',
        branchDetected: 'المعادي',
        retailChainName: 'هايبر وان',
        allowedBranches: ['الشيخ زايد', 'سفنكس'],
        isAllBranches: false,
      );

      expect(items.any((i) => i.title.contains('السلسلة التجارية')), isTrue);
      final branchItem = items.firstWhere((i) => i.title.contains('السلسلة'));
      expect(branchItem.description, contains('كارفور'));
      expect(branchItem.description, contains('المعادي'));
      expect(branchItem.description, contains('الشيخ زايد'));
    });

    test('buildValidationConditionItems includes AI unfulfilled conditions', () {
      final items = buildValidationConditionItems(
        isValid: false,
        message: 'شروط غير مستوفاة',
        targetCompanyTotal: 200.0,
        minimumSpend: 150.0,
        targetCompany: 'المراعي',
        currencySymbol: 'ج.م',
        unfulfilledConditions: const [
          'الفاتورة لا تحتوي على الختم الرسمي للمتجر',
          'رقم السجل الضريبي غير واضح في الصورة',
        ],
      );

      expect(items.length, 2);
      expect(items.any((i) => i.description.contains('الختم الرسمي')), isTrue);
      expect(items.any((i) => i.description.contains('السجل الضريبي')), isTrue);
    });

    testWidgets('ReceiptValidationReportDialog renders M3 Purple theme, metadata chips, and conditions list', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar', ''),
          supportedLocales: const [Locale('ar', ''), Locale('en', ''), Locale('hi', '')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showReceiptValidationReportDialog(
                    context: context,
                    title: 'عفواً، الفاتورة غير مطابقة للشروط',
                    subtitle: 'تم فحص الفاتورة بالذكاء الاصطناعي وتبيّن عدم استيفاء البنود التالية:',
                    receiptNumber: 'INV-987654',
                    storeChain: 'كارفور',
                    branch: 'المعادي',
                    receiptDate: '2026-08-16',
                    totalValue: 75.0,
                    requiredMinimum: 150.0,
                    currencySymbol: 'ج.م',
                    conditions: const [
                      ValidationConditionItem(
                        title: 'الحد الأدنى للمشتريات',
                        description: 'قيمة المشتريات (75.0 ج.م) أقل من الحد الأدنى (150.0 ج.م).',
                        icon: Icons.price_check_rounded,
                        isMet: false,
                        value: '75.0 / 150.0 ج.م',
                      ),
                      ValidationConditionItem(
                        title: 'تاريخ الفاتورة',
                        description: 'تاريخ الفاتورة يقع خارج النطاق الزمني للحملة الترويجية.',
                        icon: Icons.calendar_month_rounded,
                        isMet: false,
                      ),
                    ],
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      // Tap button to open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify Header and Subtitle
      expect(find.text('عفواً، الفاتورة غير مطابقة للشروط'), findsOneWidget);
      expect(find.text('تم فحص الفاتورة بالذكاء الاصطناعي وتبيّن عدم استيفاء البنود التالية:'), findsOneWidget);

      // Verify Metadata Chips
      expect(find.text('INV-987654'), findsOneWidget);
      expect(find.text('كارفور (المعادي)'), findsOneWidget);
      expect(find.text('2026-08-16'), findsOneWidget);

      // Verify Conditions
      expect(find.text('الحد الأدنى للمشتريات'), findsOneWidget);
      expect(find.text('قيمة المشتريات (75.0 ج.م) أقل من الحد الأدنى (150.0 ج.م).'), findsOneWidget);
      expect(find.text('تاريخ الفاتورة'), findsOneWidget);

      // Verify Action Button and close
      expect(find.text('حسناً / إغلاق الفاتورة'), findsOneWidget);
      await tester.tap(find.text('حسناً / إغلاق الفاتورة'));
      await tester.pumpAndSettle();

      // Verify dialog dismissed
      expect(find.text('عفواً، الفاتورة غير مطابقة للشروط'), findsNothing);
    });

    testWidgets('ReceiptValidationReportDialog renders Duplicate invoice styling correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showReceiptValidationReportDialog(
                    context: context,
                    title: 'عفواً، الفاتورة مسجلة مسبقاً',
                    subtitle: 'رقم الفاتورة مسجل مسبقاً في النظام',
                    isDuplicate: true,
                    receiptNumber: 'INV-112233',
                    conditions: const [
                      ValidationConditionItem(
                        title: 'حالة الفاتورة (مستخدمة مسبقاً)',
                        description: 'رقم الفاتورة (INV-112233) مسجل مسبقاً في قاعدة البيانات.',
                        icon: Icons.history_toggle_off_rounded,
                        isMet: false,
                      ),
                    ],
                  );
                },
                child: const Text('Open Duplicate Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Duplicate Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('عفواً، الفاتورة مسجلة مسبقاً'), findsOneWidget);
      expect(find.text('رقم الفاتورة مسجل مسبقاً في النظام'), findsOneWidget);
      expect(find.text('INV-112233'), findsOneWidget);
      expect(find.text('حالة الفاتورة (مستخدمة مسبقاً)'), findsOneWidget);
    });

    testWidgets('ReceiptValidationReportDialog renders image preview chip when imageUrl is provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showReceiptValidationReportDialog(
                    context: context,
                    title: 'عفواً، الفاتورة غير مطابقة',
                    imageUrl: 'https://example.com/receipt.jpg',
                    conditions: const [
                      ValidationConditionItem(
                        title: 'الحد الأدنى',
                        description: 'القيمة غير كافية',
                        icon: Icons.error_rounded,
                        isMet: false,
                      ),
                    ],
                  );
                },
                child: const Text('Open Image Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Image Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('معاينة صورة الفاتورة'), findsOneWidget);
      expect(find.byIcon(Icons.image_search_rounded), findsOneWidget);
    });
  });
}
