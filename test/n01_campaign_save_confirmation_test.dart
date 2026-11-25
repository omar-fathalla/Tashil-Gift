import 'dart:async';
import 'dart:io';

import 'package:al_mraay/features/admin/domain/campaign_save_confirmation.dart';
import 'package:al_mraay/features/admin/presentation/widgets/campaign_save_pending_banner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PendingCampaignSave _newTarget(String id) =>
    PendingCampaignSave(eventId: id, isNew: true, updatedBy: 'admin1', startedAt: DateTime(2026, 11, 25, 13));

/// Mimics the screen: links/QR are shown only from the confirmed branch.
class _FakeScreen {
  final flow = CampaignSaveFlow(wait: const Duration(milliseconds: 50));
  final Map<String, Map<String, dynamic>> server = {};
  final List<String> linksShownFor = [];
  final List<String> writes = [];
  int generated = 0;

  String _generate() => 'auto-${++generated}';

  Future<CampaignSaveOutcome> save(Future<void> Function(String id) write) async {
    final id = flow.newCampaignId(_generate);
    final outcome = await flow.run(target: _newTarget(id), write: () => write(id));
    if (outcome == CampaignSaveOutcome.confirmed) linksShownFor.add(id);
    return outcome;
  }

  Future<CampaignVerifyResult> verify() async {
    final id = flow.pending?.eventId;
    final r = await flow.verify((id) async => server[id]);
    if (r == CampaignVerifyResult.confirmed && id != null) linksShownFor.add(id);
    return r;
  }
}

void main() {
  group('N-01 save flow', () {
    test('no success on timeout: a write that never finishes is unconfirmed', () async {
      final s = _FakeScreen();
      final outcome = await s.save((id) => Completer<void>().future);
      expect(outcome, CampaignSaveOutcome.unconfirmed);
      expect(s.flow.isPending, isTrue);
      expect(s.linksShownFor, isEmpty, reason: 'links/QR must stay hidden');
    });

    test('a confirmed write shows the links for the same id that was written', () async {
      final s = _FakeScreen();
      final outcome = await s.save((id) async {
        s.writes.add(id);
        s.server[id] = {'eventName': 'x'};
      });
      expect(outcome, CampaignSaveOutcome.confirmed);
      expect(s.linksShownFor, s.writes);
      expect(s.flow.isPending, isFalse);
    });

    test('stable id on create: retries write the same document, never a new id', () async {
      final s = _FakeScreen();
      await s.save((id) {
        s.writes.add(id);
        return Completer<void>().future;
      });
      await s.save((id) {
        s.writes.add(id);
        return Completer<void>().future;
      });
      await s.save((id) async {
        s.writes.add(id);
        s.server[id] = {'eventName': 'x'};
      });
      expect(s.generated, 1);
      expect(s.writes.toSet(), {'auto-1'});
      expect(s.linksShownFor, ['auto-1']);
      expect(s.server.keys, ['auto-1']);
    });

    test('verify: not on the server yet -> stays pending, no links', () async {
      final s = _FakeScreen();
      await s.save((id) => Completer<void>().future);
      expect(await s.verify(), CampaignVerifyResult.notYet);
      expect(s.flow.isPending, isTrue);
      expect(s.linksShownFor, isEmpty);
    });

    test('verify: server read fails -> failed, no links', () async {
      final s = _FakeScreen();
      await s.save((id) => Completer<void>().future);
      final r = await s.flow.verify((id) async => throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
      expect(r, CampaignVerifyResult.failed);
      expect(s.flow.isPending, isTrue);
      expect(s.linksShownFor, isEmpty);
    });

    test('verify: document found on the server -> confirmed, links shown once', () async {
      final s = _FakeScreen();
      await s.save((id) => Completer<void>().future);
      s.server['auto-1'] = {'eventName': 'x'};
      expect(await s.verify(), CampaignVerifyResult.confirmed);
      expect(s.flow.isPending, isFalse);
      expect(s.linksShownFor, ['auto-1']);
    });

    test('a real error is rethrown (friendly message path), not unconfirmed', () async {
      final s = _FakeScreen();
      await expectLater(
        s.save((id) async => throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')),
        throwsA(isA<FirebaseException>()),
      );
      expect(s.flow.isPending, isFalse);
      expect(s.linksShownFor, isEmpty);
    });

    test('a server deadline is unconfirmed, not success', () async {
      final s = _FakeScreen();
      final outcome = await s.save((id) async => throw FirebaseException(plugin: 'cloud_firestore', code: 'deadline-exceeded'));
      expect(outcome, CampaignSaveOutcome.unconfirmed);
      expect(s.linksShownFor, isEmpty);
    });

    test('a late error after the wait does not escape as an unhandled error', () async {
      final s = _FakeScreen();
      final c = Completer<void>();
      expect(await s.save((id) => c.future), CampaignSaveOutcome.unconfirmed);
      c.completeError(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
  });

  group('N-01 edit confirmation', () {
    final started = DateTime(2026, 11, 25, 13);
    final edit = PendingCampaignSave(eventId: 'e1', isNew: false, updatedBy: 'admin1', startedAt: started);

    test('confirmed only when the server copy was updated by this admin after the save started', () {
      expect(edit.isConfirmedBy(null), isFalse);
      expect(
        edit.isConfirmedBy({'updatedBy': 'admin1', 'updatedAt': Timestamp.fromDate(started.subtract(const Duration(minutes: 1)))}),
        isFalse,
      );
      expect(edit.isConfirmedBy({'updatedBy': 'other', 'updatedAt': Timestamp.fromDate(started.add(const Duration(seconds: 3)))}), isFalse);
      expect(edit.isConfirmedBy({'updatedBy': 'admin1'}), isFalse);
      expect(edit.isConfirmedBy({'updatedBy': 'admin1', 'updatedAt': Timestamp.fromDate(started.add(const Duration(seconds: 3)))}), isTrue);
    });
  });

  group('N-01 pending banner', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('shows the Arabic unconfirmed state and the verify button', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(CampaignSavePendingBanner(onVerify: () => taps++)));
      expect(find.text(CampaignSaveTexts.unconfirmedTitle), findsOneWidget);
      expect(find.text('الحفظ لسه ما اتأكدش'), findsOneWidget);
      expect(find.text(CampaignSaveTexts.verifyButton), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('n01-verify-button')));
      expect(taps, 1);
    });

    testWidgets('verify button is disabled while checking and shows the result', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(CampaignSavePendingBanner(onVerify: () => taps++, verifying: true, message: CampaignSaveTexts.notYet)));
      await tester.tap(find.byKey(const ValueKey('n01-verify-button')));
      expect(taps, 0);
      expect(find.text(CampaignSaveTexts.notYet), findsOneWidget);
    });
  });

  group('N-01 source guards (create_event_screen)', () {
    final src = File('lib/features/admin/presentation/create_event_screen.dart').readAsStringSync();

    test('no success-on-timeout and no random id fallback', () {
      expect(src.contains("onTimeout: () => firestore.collection('events').doc()"), isFalse);
      expect(RegExp(r"collection\('events'\)\.add\(").hasMatch(src), isFalse);
      expect(RegExp(r'onTimeout:\s*\(\)\s*\{\s*\}').hasMatch(src), isFalse);
      expect(src.contains("collection('events').doc(eventId).set("), isTrue);
    });

    test('links dialog is opened only from the confirmed path', () {
      final calls = RegExp(r'await _showCampaignSuccessLinksDialog\(').allMatches(src).length;
      expect(calls, 1);
      final finish = src.indexOf('Future<void> _finishConfirmedSave(');
      final call = src.indexOf('await _showCampaignSuccessLinksDialog(');
      final nextMethod = src.indexOf('Future<void> _verifyPendingSave(');
      expect(finish, greaterThan(0));
      expect(call > finish && call < nextMethod, isTrue);
    });

    test('verify reads from the server, not the cache', () {
      final conf = File('lib/features/admin/domain/campaign_save_confirmation.dart').readAsStringSync();
      expect(conf.contains('GetOptions(source: Source.server)'), isTrue);
    });

    test('quick-add chain/branch require server confirmation', () {
      expect(src.contains('addRetailChain(chain, confirmWrite: true)'), isTrue);
      expect(src.contains('addBranch(branch, confirmWrite: true)'), isTrue);
    });
  });
}
