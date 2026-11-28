// TAG-35 (N-01b): company / chain / branch / product saves never count as
// saved before the server confirmed them.
import 'dart:async';
import 'dart:io';

import 'package:al_mraay/core/utils/confirmed_write.dart';
import 'package:al_mraay/core/utils/error_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a confirmed write completes normally', () async {
    await confirmedWrite(Future<void>.value(), 'companies/x');
  });

  test('a pending write throws WriteNotConfirmedException after the wait', () async {
    final never = Completer<void>();
    await expectLater(
      confirmedWrite(never.future, 'branches/b1', isDelete: true, wait: const Duration(milliseconds: 20)),
      throwsA(isA<WriteNotConfirmedException>()
          .having((e) => e.path, 'path', 'branches/b1')
          .having((e) => e.isDelete, 'isDelete', true)),
    );
  });

  test('a server error is not hidden', () async {
    await expectLater(confirmedWrite(Future<void>.error(StateError('denied')), 'x'), throwsStateError);
  });

  test('the friendly message says «لسه ما اتأكدش»', () {
    expect(AppErrorHandler.getFriendlyMessage(const WriteNotConfirmedException('x')), contains('لسه ما اتأكدش'));
  });

  test('source guard: the N-01b save paths have no silent timeout', () {
    final silent = RegExp(r'onTimeout:\s*\(\)\s*\{\s*(//[^\n]*\s*)*\}');
    String body(String path, String from, String to) {
      final s = File(path).readAsStringSync();
      final a = s.indexOf(from);
      expect(a, isNonNegative, reason: '$path: $from');
      final b = s.indexOf(to, a + from.length);
      return s.substring(a, b < 0 ? s.length : b);
    }

    final guarded = {
      'lib/features/admin/presentation/company_catalog_screen.dart': [
        ("final companyRef = firestore.collection('companies').doc(companyCode);", 'catch (e)'),
      ],
      'lib/core/services/retail_chains_service.dart': [
        ('Future<void> updateRetailChain', 'Future<void> deleteRetailChain'),
        ('Future<void> deleteRetailChain', 'Stream<List<BranchModel>>'),
        ('Future<void> updateBranch', 'Future<void> _recalculateChainBranchesCount'),
      ],
      'lib/core/services/company_products_service.dart': [
        ('Future<int> deleteAllProductsForCompany', 'Future<List<CompanyProductItem>> getProductsForCompany'),
      ],
    };
    final problems = <String>[];
    guarded.forEach((path, ranges) {
      for (final (from, to) in ranges) {
        if (silent.hasMatch(body(path, from, to))) problems.add('$path: $from');
      }
    });
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
