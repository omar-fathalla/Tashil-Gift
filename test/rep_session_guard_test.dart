import 'package:al_mraay/core/services/rep_session_guard.dart';
import 'package:al_mraay/features/client_portal/presentation/widgets/receipt_issue_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CodedError implements Exception {
  final String code;
  _CodedError(this.code);
  @override
  String toString() => '[$code] boom';
}

void main() {
  group('repSessionActionFor', () {
    test('signed out -> sign in anonymously', () {
      expect(repSessionActionFor(const RepIdentity(signedIn: false)), RepSessionAction.signInAnonymously);
    });
    test('anonymous -> nothing', () {
      expect(repSessionActionFor(const RepIdentity(signedIn: true, isAnonymous: true)), RepSessionAction.none);
    });
    test('partner identity from another tab -> back to anonymous', () {
      expect(repSessionActionFor(const RepIdentity(signedIn: true, role: 'partner')), RepSessionAction.signOutThenAnonymous);
      expect(repSessionActionFor(const RepIdentity(signedIn: true)), RepSessionAction.signOutThenAnonymous);
    });
    test('staff/admin is never signed out', () {
      expect(repSessionActionFor(const RepIdentity(signedIn: true, role: 'admin')), RepSessionAction.none);
      expect(repSessionActionFor(const RepIdentity(signedIn: true, role: 'super_admin')), RepSessionAction.none);
    });
  });

  group('isRepSessionError', () {
    test('auth/permission codes retry, others do not', () {
      expect(isRepSessionError(_CodedError('unauthenticated')), isTrue);
      expect(isRepSessionError(_CodedError('permission-denied')), isTrue);
      expect(isRepSessionError(Exception('Missing or insufficient permissions.')), isTrue);
      expect(isRepSessionError(_CodedError('internal')), isFalse);
      expect(isRepSessionError(Exception('network down')), isFalse);
      expect(repErrorCode(_CodedError('unauthenticated')), 'unauthenticated');
    });
  });

  group('isUnusableReceiptNumber', () {
    test('empty / placeholder numbers are unusable', () {
      for (final v in [null, '', '   ', 'UNKNOWN', 'unknown', 'N/A', 'null', '---', '//']) {
        expect(isUnusableReceiptNumber(v), isTrue, reason: '$v');
      }
    });
    test('real numbers are usable', () {
      for (final v in ['99', '244/1/211/291026', 'INV-12', '١٢٣']) {
        expect(isUnusableReceiptNumber(v), isFalse, reason: v);
      }
    });
    test('Arabic retake message mentions receipt number', () {
      expect(kUnreadableReceiptNumberAr, contains('رقم الفاتورة'));
    });
  });

  testWidgets('dialog shows raw error code small', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ReceiptIssueDialog(
          kind: ReceiptIssueKind.permission,
          isArabic: true,
          errorCode: 'unauthenticated',
        ),
      ),
    ));
    await tester.pump();
    final f = find.byKey(const Key('receipt_issue_error_code'));
    expect(f, findsOneWidget);
    final t = tester.widget<Text>(f);
    expect(t.data, contains('unauthenticated'));
    expect(t.style?.fontSize, 11);
  });

  testWidgets('dialog hides error code when absent', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ReceiptIssueDialog(kind: ReceiptIssueKind.network, isArabic: true),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const Key('receipt_issue_error_code')), findsNothing);
  });
}
