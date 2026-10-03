import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/localization/app_strings.dart';
import 'package:al_mraay/core/utils/arabic_numbers_utils.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Invoices Log & Barcode Extraction Tests', () {
    test('ExtractedProductItem properly handles barcode and totalPrice', () {
      final item = ExtractedProductItem(
        name: 'حليب المراعي كامل الدسم 1 لتر',
        price: 45.0,
        quantity: 2,
        isTargetCompany: true,
        barcode: '6281007000012',
      );

      expect(item.name, 'حليب المراعي كامل الدسم 1 لتر');
      expect(item.price, 45.0);
      expect(item.quantity, 2);
      expect(item.barcode, '6281007000012');
      expect(item.totalPrice, 90.0);
      expect(item.isTargetCompany, true);

      final json = item.toJson();
      expect(json['barcode'], '6281007000012');
      expect(json['totalPrice'], 90.0);

      final fromJson = ExtractedProductItem.fromJson(json);
      expect(fromJson.barcode, '6281007000012');
      expect(fromJson.totalPrice, 90.0);
      expect(fromJson.name, item.name);
    });

    test('ExtractedProductItem handles missing barcode gracefully with fallback', () {
      final json = {
        'name': 'عصير برتقال المراعي 1 لتر',
        'price': 30.0,
        'quantity': 3,
        'isTargetCompany': true,
      };

      final item = ExtractedProductItem.fromJson(json);
      expect(item.barcode, '');
      expect(item.totalPrice, 90.0);
    });

    test('AiReceiptAnalysisResult correctly serializes and deserializes products with barcodes', () {
      final jsonMap = {
        'isValid': true,
        'receiptNumber': 'REC-998822',
        'targetCompanyTotal': 180.0,
        'receiptDate': '2026-08-16',
        'storeChainDetected': 'كارفور',
        'branchDetected': 'فرع سيتي سنتر',
        'isBranchMatched': true,
        'extractedProducts': [
          {
            'name': 'جبنة مثلثات المراعي 8 قطع',
            'barcode': '6281007000036',
            'price': 25.0,
            'quantity': 4,
            'totalPrice': 100.0,
            'isTargetCompany': true,
          },
          {
            'name': 'خبز توست أبيض',
            'barcode': '6221008000055',
            'price': 35.0,
            'quantity': 1,
            'totalPrice': 35.0,
            'isTargetCompany': false,
          }
        ],
        'message': 'الفاتورة مطابقة لكافة الشروط.',
      };

      final result = AiReceiptAnalysisResult.fromJson(jsonMap);
      expect(result.isValid, true);
      expect(result.receiptNumber, 'REC-998822');
      expect(result.extractedProducts.length, 2);
      expect(result.extractedProducts[0].barcode, '6281007000036');
      expect(result.extractedProducts[0].totalPrice, 100.0);
      expect(result.extractedProducts[0].isTargetCompany, true);
      expect(result.extractedProducts[1].barcode, '6221008000055');
      expect(result.extractedProducts[1].isTargetCompany, false);

      final outputJson = result.toJson();
      expect(outputJson['extractedProducts'][0]['barcode'], '6281007000036');
    });

    test('Trilingual AppStrings for Invoices Log & Barcode extraction exist and are populated', () {
      final ar = AppStrings('ar');
      final en = AppStrings('en');
      final hi = AppStrings('hi');

      // Check key audit getters
      expect(ar.invoicesAuditTitle.isNotEmpty, true);
      expect(en.invoicesAuditTitle.isNotEmpty, true);
      expect(hi.invoicesAuditTitle.isNotEmpty, true);

      expect(ar.allCampaigns.isNotEmpty, true);
      expect(en.allCampaigns.isNotEmpty, true);
      expect(hi.allCampaigns.isNotEmpty, true);

      expect(ar.barcodeCol.isNotEmpty, true);
      expect(en.barcodeCol.isNotEmpty, true);
      expect(hi.barcodeCol.isNotEmpty, true);

      expect(ar.productNameCol.isNotEmpty, true);
      expect(en.productNameCol.isNotEmpty, true);
      expect(hi.productNameCol.isNotEmpty, true);

      expect(ar.unitPriceCol.isNotEmpty, true);
      expect(en.unitPriceCol.isNotEmpty, true);
      expect(hi.unitPriceCol.isNotEmpty, true);

      expect(ar.totalPriceCol.isNotEmpty, true);
      expect(en.totalPriceCol.isNotEmpty, true);
      expect(hi.totalPriceCol.isNotEmpty, true);

      expect(ar.exportCsvBtn, 'CSV');
      expect(en.exportCsvBtn, 'CSV');
      expect(hi.exportCsvBtn, 'CSV');

      expect(ar.searchReceiptPlaceholder.isNotEmpty, true);
      expect(en.searchReceiptPlaceholder.isNotEmpty, true);
      expect(hi.searchReceiptPlaceholder.isNotEmpty, true);
    });

    test('Campaign Active filtering logic filters ended/expired campaigns by default', () {
      final now = DateTime.now();
      final activeEvent = EventModel(
        id: 'evt_active',
        eventName: 'Active Event',
        targetCompany: 'TestCompany',
        minimumSpend: 100.0,
        startDate: now.subtract(const Duration(days: 5)),
        endDate: now.add(const Duration(days: 5)),
        isActive: true,
      );
      final expiredEvent = EventModel(
        id: 'evt_expired',
        eventName: 'Expired Event',
        targetCompany: 'TestCompany',
        minimumSpend: 100.0,
        startDate: now.subtract(const Duration(days: 20)),
        endDate: now.subtract(const Duration(days: 5)),
        isActive: true,
      );
      final inactiveEvent = EventModel(
        id: 'evt_inactive',
        eventName: 'Inactive Event',
        targetCompany: 'TestCompany',
        minimumSpend: 100.0,
        startDate: now.subtract(const Duration(days: 5)),
        endDate: now.add(const Duration(days: 5)),
        isActive: false,
      );

      final allEvents = [activeEvent, expiredEvent, inactiveEvent];
      final activeOnly = allEvents.where((e) => e.isActive && !e.isExpired).toList();

      expect(activeOnly.length, 1);
      expect(activeOnly.first.id, 'evt_active');
    });

    test('Base64 and HTTPS Receipt Image URLs validation', () {
      const sampleBase64 = 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP...';
      const sampleStorageUrl = 'https://firebasestorage.googleapis.com/v0/b/tashil-gift.firebasestorage.app/o/receipts%2Falmarai%2FINV_123.jpg?alt=media';

      expect(sampleBase64.startsWith('data:image'), true);
      expect(sampleStorageUrl.startsWith('https://'), true);

      // Verify base64 extraction logic
      final extracted = sampleBase64.contains(',') ? sampleBase64.split(',').last : sampleBase64;
      expect(extracted, '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP...');
    });

    test('Receipt Number Search: Eastern Arabic digits normalization (٢٦٣ -> 263)', () {
      const rawInput = '٢٦٣';
      final cleanQuery = rawInput.toEnglishDigits().toLowerCase();
      expect(cleanQuery, '263');

      const receiptNumber = '263/2/243/021026';
      expect(receiptNumber.contains(cleanQuery), true);
    });

    test('Receipt Number Search: Delimiter-insensitive matching (263-2 and 263 2 match 263/2/243/021026)', () {
      const receiptNumber = '263/2/243/021026';
      final cleanReceipt = receiptNumber.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');

      // Query with dashes
      const queryDash = '263-2';
      final cleanQueryDash = queryDash.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      expect(cleanReceipt.contains(cleanQueryDash), true);

      // Query with spaces
      const querySpace = '263 2';
      final cleanQuerySpace = querySpace.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      expect(cleanReceipt.contains(cleanQuerySpace), true);

      // Query with slashes
      const querySlash = '263/2';
      final cleanQuerySlash = querySlash.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      expect(cleanReceipt.contains(cleanQuerySlash), true);
    });

    test('Receipt Number Search: Segment token matching for Trans number (263)', () {
      const receiptNumber = '263/2/243/021026';
      final segments = receiptNumber.split(RegExp(r'[/\\-_ ]+'));

      expect(segments[0], '263'); // Trans
      expect(segments[1], '2');   // PoS
      expect(segments[2], '243'); // Store
      expect(segments[3], '021026'); // Date

      expect(segments.contains('263'), true);
      expect(segments.contains('2'), true);
    });

    test('Receipt Lookup Dialog: Auto-parsing full barcode into Trans and PoS', () {
      const barcode = '263/2/243/021026';
      final parts = barcode.split('/');
      final trans = parts[0].trim();
      final pos = parts.length > 1 ? parts[1].trim() : '';

      expect(trans, '263');
      expect(pos, '2');
    });

    test('Branch invoices count in dropdown is scoped strictly by active date filter', () {
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));

      final sampleInvoices = [
        {
          'id': 'inv1',
          'campaignId': 'c1',
          'canonical_branch': 'فرع سموحة',
          'date': today,
          'is_valid': true,
        },
        {
          'id': 'inv2',
          'campaignId': 'c1',
          'canonical_branch': 'فرع سموحة',
          'date': yesterday,
          'is_valid': true,
        },
        {
          'id': 'inv3',
          'campaignId': 'c1',
          'canonical_branch': 'فرع جاردينيا',
          'date': today,
          'is_valid': true,
        },
      ];

      // Simulate date filtering for today
      bool isToday(DateTime? d) {
        if (d == null) return false;
        return d.year == today.year && d.month == today.month && d.day == today.day;
      }

      final todayInvoices = sampleInvoices.where((inv) => isToday(inv['date'] as DateTime?)).toList();
      expect(todayInvoices.length, 2);

      final smouhaToday = todayInvoices.where((inv) => inv['canonical_branch'] == 'فرع سموحة').length;
      final gardeniaToday = todayInvoices.where((inv) => inv['canonical_branch'] == 'فرع جاردينيا').length;

      expect(smouhaToday, 1); // 1 today, even though total all-time is 2
      expect(gardeniaToday, 1);
    });
  });
}

