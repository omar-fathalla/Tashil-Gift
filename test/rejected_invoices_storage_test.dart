import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Rejected Invoices Storage & Filtering Standard Tests', () {
    test('1. Valid receipt transaction is accurately identified as isValid == true', () {
      final Map<String, dynamic> acceptedTx = {
        'receipt_number': 'INV-1001',
        'is_valid': true,
        'status': 'accepted',
        'rejection_reason': null,
        'unfulfilled_conditions': <String>[],
        'total_value': 250.0,
        'target_company_total': 250.0,
      };

      final bool isExplicitlyValid = acceptedTx['is_valid'] == true ||
          acceptedTx['status'] == 'accepted' ||
          acceptedTx['isValid'] == true;
      final bool isExplicitlyRejected = acceptedTx['is_valid'] == false ||
          acceptedTx['status'] == 'rejected' ||
          acceptedTx['isValid'] == false ||
          ((acceptedTx['unfulfilled_conditions'] as List?)?.isNotEmpty ?? false);
      final bool isValid = isExplicitlyValid ||
          (!isExplicitlyRejected &&
              ((acceptedTx['unfulfilled_conditions'] as List?)?.isEmpty ?? true));

      expect(isValid, isTrue);
    });

    test('2. Rejected receipt due to minimum spend failure is accurately identified', () {
      final Map<String, dynamic> rejectedSpendTx = {
        'receipt_number': 'INV-1002',
        'is_valid': false,
        'status': 'rejected',
        'rejection_reason': 'مبلغ مشتريات منتجات الحملة (40.0 ج.م) أقل من الحد الأدنى المطلوب (100.0 ج.م)',
        'unfulfilled_conditions': [
          'الحد الأدنى لمشتريات منتجات الحملة هو 100.0 ج.م بينما إجمالي الفاتورة 40.0 ج.م'
        ],
        'total_value': 40.0,
        'target_company_total': 40.0,
      };

      final bool isExplicitlyValid = rejectedSpendTx['is_valid'] == true ||
          rejectedSpendTx['status'] == 'accepted' ||
          rejectedSpendTx['isValid'] == true;
      final bool isExplicitlyRejected = rejectedSpendTx['is_valid'] == false ||
          rejectedSpendTx['status'] == 'rejected' ||
          rejectedSpendTx['isValid'] == false ||
          ((rejectedSpendTx['unfulfilled_conditions'] as List?)?.isNotEmpty ?? false);
      final bool isValid = isExplicitlyValid ||
          (!isExplicitlyRejected &&
              ((rejectedSpendTx['unfulfilled_conditions'] as List?)?.isEmpty ?? true));

      expect(isValid, isFalse);
      expect(rejectedSpendTx['rejection_reason'], contains('أقل من الحد الأدنى'));
      expect((rejectedSpendTx['unfulfilled_conditions'] as List).length, equals(1));
    });

    test('3. Rejected receipt due to branch mismatch or handwritten validation failure', () {
      final Map<String, dynamic> rejectedBranchTx = {
        'receipt_number': 'INV-1003',
        'is_valid': false,
        'status': 'rejected',
        'rejection_reason': 'الفرع غير مطابق لفروع الفعالية المعتمدة',
        'unfulfilled_conditions': [
          'الفرع المكتشف (فرع الهرم) غير مدرج ضمن فروع الحملة المعتمدة'
        ],
        'is_branch_matched': false,
        'is_handwritten': true,
        'fraud_risk_score': 85,
      };

      final bool isExplicitlyValid = rejectedBranchTx['is_valid'] == true ||
          rejectedBranchTx['status'] == 'accepted' ||
          rejectedBranchTx['isValid'] == true;
      final bool isExplicitlyRejected = rejectedBranchTx['is_valid'] == false ||
          rejectedBranchTx['status'] == 'rejected' ||
          rejectedBranchTx['isValid'] == false ||
          ((rejectedBranchTx['unfulfilled_conditions'] as List?)?.isNotEmpty ?? false);
      final bool isValid = isExplicitlyValid ||
          (!isExplicitlyRejected &&
              ((rejectedBranchTx['unfulfilled_conditions'] as List?)?.isEmpty ?? true));

      expect(isValid, isFalse);
      expect(rejectedBranchTx['is_handwritten'], isTrue);
      expect(rejectedBranchTx['fraud_risk_score'], equals(85));
    });

    test('4. Financial KPI aggregation isolates accepted receipts while total scan count includes all', () {
      final List<Map<String, dynamic>> allTransactions = [
        {
          'receipt_number': 'INV-01',
          'is_valid': true,
          'status': 'accepted',
          'target_company_total': 150.0,
          'extracted_products': [
            {'name': 'شاي العروسة 250جم', 'quantity': 2, 'price': 35.0, 'isTargetCompany': true},
          ],
        },
        {
          'receipt_number': 'INV-02',
          'is_valid': false,
          'status': 'rejected',
          'rejection_reason': 'مبلغ غير كافٍ',
          'unfulfilled_conditions': ['الحد الأدنى غير مستوفى'],
          'target_company_total': 30.0,
          'extracted_products': [
            {'name': 'شاي العروسة 40جم', 'quantity': 1, 'price': 10.0, 'isTargetCompany': true},
          ],
        },
        {
          'receipt_number': 'INV-03',
          'is_valid': true,
          'status': 'accepted',
          'target_company_total': 200.0,
          'extracted_products': [
            {'name': 'شاي العروسة 250جم', 'quantity': 3, 'price': 35.0, 'isTargetCompany': true},
          ],
        },
        {
          'receipt_number': 'INV-04',
          'is_valid': false,
          'status': 'rejected',
          'rejection_reason': 'تاريخ قديم',
          'unfulfilled_conditions': ['تاريخ الفاتورة خارج نطاق الحملة'],
          'target_company_total': 500.0,
          'extracted_products': [
            {'name': 'شاي العروسة 250جم', 'quantity': 5, 'price': 35.0, 'isTargetCompany': true},
          ],
        },
      ];

      int totalScans = allTransactions.length;
      int acceptedInvoices = 0;
      int rejectedInvoices = 0;
      double totalSalesVolume = 0.0;
      int totalUnitsSold = 0;

      for (final tx in allTransactions) {
        final bool isExplicitlyValid = tx['is_valid'] == true || tx['status'] == 'accepted' || tx['isValid'] == true;
        final bool isExplicitlyRejected = tx['is_valid'] == false || tx['status'] == 'rejected' || tx['isValid'] == false || ((tx['unfulfilled_conditions'] as List?)?.isNotEmpty ?? false);
        final bool isValid = isExplicitlyValid || (!isExplicitlyRejected && ((tx['unfulfilled_conditions'] as List?)?.isEmpty ?? true));

        if (isValid) {
          acceptedInvoices++;
          totalSalesVolume += (tx['target_company_total'] as num).toDouble();

          final products = tx['extracted_products'] as List;
          for (final p in products) {
            totalUnitsSold += (p['quantity'] as num).toInt();
          }
        } else {
          rejectedInvoices++;
        }
      }

      final double acceptanceRate = (acceptedInvoices / totalScans) * 100;

      expect(totalScans, equals(4));
      expect(acceptedInvoices, equals(2));
      expect(rejectedInvoices, equals(2));
      expect(totalSalesVolume, equals(350.0)); // 150 + 200 (excludes 30 and 500 from rejected)
      expect(totalUnitsSold, equals(5)); // 2 + 3 (excludes 1 and 5 from rejected)
      expect(acceptanceRate, equals(50.0));
    });

    test('5. Status filters (ALL, VALID, INVALID) partition transaction list correctly', () {
      final List<Map<String, dynamic>> transactions = [
        {'receipt_number': 'INV-A', 'is_valid': true, 'status': 'accepted'},
        {'receipt_number': 'INV-B', 'is_valid': false, 'status': 'rejected'},
        {'receipt_number': 'INV-C', 'is_valid': true, 'status': 'accepted'},
        {'receipt_number': 'INV-D', 'is_valid': false, 'status': 'rejected'},
      ];

      List<Map<String, dynamic>> filter(String statusFilter) {
        return transactions.where((data) {
          final bool isExplicitlyValid = data['is_valid'] == true || data['status'] == 'accepted';
          final bool isExplicitlyRejected = data['is_valid'] == false || data['status'] == 'rejected';
          final bool isValid = isExplicitlyValid || (!isExplicitlyRejected);

          if (statusFilter == 'VALID' && !isValid) return false;
          if (statusFilter == 'INVALID' && isValid) return false;
          return true;
        }).toList();
      }

      expect(filter('ALL').length, equals(4));
      expect(filter('VALID').map((e) => e['receipt_number']).toList(), equals(['INV-A', 'INV-C']));
      expect(filter('INVALID').map((e) => e['receipt_number']).toList(), equals(['INV-B', 'INV-D']));
    });
  });
}
