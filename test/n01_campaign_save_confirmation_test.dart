import 'dart:async';
import 'dart:io';

import 'package:al_mraay/features/admin/domain/campaign_save_confirmation.dart';
import 'package:al_mraay/features/admin/domain/campaign_save_failure_log.dart';
import 'package:al_mraay/features/admin/presentation/widgets/campaign_save_pending_banner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PendingCampaignSave _newTarget(String id) =>
    PendingCampaignSave(eventId: id, isNew: true, updatedBy: 'admin1', saveToken: 'tok-$id');

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

  group('N-01 edit confirmation (TAG-43: by save token, not the PC clock)', () {
    const edit = PendingCampaignSave(eventId: 'e1', isNew: false, updatedBy: 'admin1', saveToken: 'tok-123');

    test('confirmed only when the server copy carries this save token', () {
      expect(edit.isConfirmedBy(null), isFalse);
      expect(edit.isConfirmedBy({'updatedBy': 'admin1'}), isFalse);
      expect(edit.isConfirmedBy({'updatedBy': 'admin1', kCampaignSaveTokenField: 'tok-old'}), isFalse);
      expect(edit.isConfirmedBy({'updatedBy': 'admin1', kCampaignSaveTokenField: 'tok-123'}), isTrue);
    });

    test('a PC clock far ahead of the server no longer hides a saved edit', () {
      // Before TAG-43 this compared server updatedAt with DateTime.now() on
      // the PC: a clock 10 minutes fast reported "not yet" forever.
      final serverTime = Timestamp.fromDate(DateTime(2026, 11, 25, 13, 0));
      expect(
        edit.isConfirmedBy({'updatedBy': 'admin1', 'updatedAt': serverTime, kCampaignSaveTokenField: 'tok-123'}),
        isTrue,
      );
    });

    test('tokens are unique per save', () {
      final tokens = {for (var i = 0; i < 200; i++) newCampaignSaveToken()};
      expect(tokens.length, 200);
    });
  });

  group('TAG-43 late outcome of an unconfirmed write', () {
    test('a write that lands after the wait confirms itself (links shown)', () async {
      final flow = CampaignSaveFlow(wait: const Duration(milliseconds: 20));
      final c = Completer<void>();
      final late = <String>[];
      final outcome = await flow.run(
        target: _newTarget('e1'),
        write: () => c.future,
        onLateSuccess: (t) => late.add(t.eventId),
        onLateError: (t, f, e) => fail('no error expected'),
      );
      expect(outcome, CampaignSaveOutcome.unconfirmed);
      expect(flow.hasUnfinishedSave, isTrue);
      c.complete();
      await Future<void>.delayed(Duration.zero);
      expect(late, ['e1']);
      expect(flow.isPending, isFalse);
      expect(flow.hasUnfinishedSave, isFalse);
    });

    test('a write that fails after the wait reports the real error code', () async {
      final flow = CampaignSaveFlow(wait: const Duration(milliseconds: 20));
      final c = Completer<void>();
      CampaignSaveFailure? seen;
      await flow.run(
        target: _newTarget('e1'),
        write: () => c.future,
        onLateSuccess: (_) => fail('no success expected'),
        onLateError: (t, f, e) => seen = f,
      );
      c.completeError(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied', message: 'Missing or insufficient permissions.'));
      await Future<void>.delayed(Duration.zero);
      expect(seen?.code, 'permission-denied');
      expect(seen?.late, isTrue);
      expect(seen?.display, 'permission-denied: Missing or insufficient permissions.');
      expect(flow.failure?.code, 'permission-denied');
      expect(flow.isPending, isFalse);
      expect(flow.hasUnfinishedSave, isFalse);
    });

    test('a non-Firebase late error keeps its type and text', () async {
      final flow = CampaignSaveFlow(wait: const Duration(milliseconds: 20));
      final c = Completer<void>();
      CampaignSaveFailure? seen;
      await flow.run(target: _newTarget('e1'), write: () => c.future, onLateError: (t, f, e) => seen = f);
      c.completeError(StateError('boom'));
      await Future<void>.delayed(Duration.zero);
      expect(seen?.code, 'StateError');
      expect(seen?.message, contains('boom'));
    });

    test('a late result of an older save is ignored once a newer save started', () async {
      final flow = CampaignSaveFlow(wait: const Duration(milliseconds: 20));
      final first = Completer<void>();
      var lateCalls = 0;
      await flow.run(target: _newTarget('e1'), write: () => first.future, onLateSuccess: (_) => lateCalls++);
      final second = Completer<void>();
      await flow.run(target: _newTarget('e1'), write: () => second.future, onLateSuccess: (_) => lateCalls++);
      first.complete();
      await Future<void>.delayed(Duration.zero);
      expect(lateCalls, 0, reason: 'the newer save decides');
      expect(flow.isPending, isTrue);
      second.complete();
      await Future<void>.delayed(Duration.zero);
      expect(lateCalls, 1);
    });

    test('after «تحقق» confirmed, a late success does not finish the save twice', () async {
      final flow = CampaignSaveFlow(wait: const Duration(milliseconds: 20));
      final c = Completer<void>();
      var lateCalls = 0;
      await flow.run(target: _newTarget('e1'), write: () => c.future, onLateSuccess: (_) => lateCalls++);
      expect(await flow.verify((id) async => {'eventName': 'x'}), CampaignVerifyResult.confirmed);
      c.complete();
      await Future<void>.delayed(Duration.zero);
      expect(lateCalls, 0);
    });

    test('an error within the wait is kept as the failure and rethrown', () async {
      final flow = CampaignSaveFlow(wait: const Duration(milliseconds: 50));
      await expectLater(
        flow.run(target: _newTarget('e1'), write: () async => throw FirebaseException(plugin: 'cloud_firestore', code: 'invalid-argument')),
        throwsA(isA<FirebaseException>()),
      );
      expect(flow.failure?.code, 'invalid-argument');
      expect(flow.hasUnfinishedSave, isFalse);
    });

    test('a quick success leaves nothing unfinished (no leave-page warning)', () async {
      final flow = CampaignSaveFlow(wait: const Duration(milliseconds: 50));
      expect(await flow.run(target: _newTarget('e1'), write: () async {}), CampaignSaveOutcome.confirmed);
      expect(flow.hasUnfinishedSave, isFalse);
    });
  });

  group('TAG-43 save failure log record', () {
    test('only the fields the rules allow, clipped to their limits', () {
      final rec = CampaignSaveFailureLog.record(
        kind: CampaignSaveFailureLog.kindLateError,
        isNew: true,
        eventId: 'e1',
        companySlug: '512',
        uid: 'admin1',
        elapsedMs: 16000,
        payloadBytes: 300000,
        failure: CampaignSaveFailure(code: 'unavailable', message: 'x' * 900, late: true),
        userAgent: 'u' * 400,
      );
      expect(rec.keys.toSet(), CampaignSaveFailureLog.fields.toSet());
      expect(rec['op'], 'create');
      expect((rec['message'] as String).length, 500);
      expect((rec['userAgent'] as String).length, 300);
      expect(rec['createdAt'], isA<FieldValue>());
    });

    test('rules allow exactly the same fields', () {
      final rules = File('firestore.rules').readAsStringSync();
      final start = rules.indexOf('match /save_failures/');
      expect(start, greaterThan(0));
      final block = rules.substring(start, rules.indexOf('allow update, delete: if false;', start));
      for (final f in CampaignSaveFailureLog.fields) {
        expect(block.contains("'$f'"), isTrue, reason: f);
      }
    });

    test('payload size estimate handles Firestore values', () {
      expect(CampaignSaveFailureLog.approxBytes({'a': 'ب', 't': FieldValue.serverTimestamp()}), greaterThan(5));
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

  group('TAG-43 banners', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('pending banner shows the technical error and the clear button', (tester) async {
      var cleared = 0;
      await tester.pumpWidget(wrap(CampaignSavePendingBanner(
        onVerify: () {},
        errorDetail: 'unavailable: offline',
        onClearPending: () => cleared++,
      )));
      expect(find.text('unavailable: offline'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tag43-clear-pending')));
      expect(cleared, 1);
    });

    testWidgets('no clear button when not offered (non-web)', (tester) async {
      await tester.pumpWidget(wrap(CampaignSavePendingBanner(onVerify: () {})));
      expect(find.byKey(const ValueKey('tag43-clear-pending')), findsNothing);
    });

    testWidgets('failed banner keeps the real code on screen', (tester) async {
      await tester.pumpWidget(wrap(const CampaignSaveFailedBanner(
        failure: CampaignSaveFailure(code: 'permission-denied', message: 'Missing or insufficient permissions.', late: true),
      )));
      expect(find.text(CampaignSaveTexts.failedTitle), findsOneWidget);
      expect(find.text('permission-denied: Missing or insufficient permissions.'), findsOneWidget);
    });
  });

  group('N-01 source guards (create_event_screen)', () {
    final src = File('lib/features/admin/presentation/create_event_screen.dart').readAsStringSync();

    test('no success-on-timeout and no random id fallback', () {
      expect(src.contains("onTimeout: () => firestore.collection('events').doc()"), isFalse);
      expect(RegExp(r"collection\('events'\)\.add\(").hasMatch(src), isFalse);
      expect(RegExp(r'onTimeout:\s*\(\)\s*\{\s*\}').hasMatch(src), isFalse);
      // TAG-62: the create is a batch (campaign + content docs) on the same id.
      expect(
        src.contains("collection('events').doc(eventId).set(") ||
            RegExp(r'createWithContent\(\s*eventId: eventId,').hasMatch(src),
        isTrue,
      );
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

    test('TAG-43: the save token is written on create and edit', () {
      expect(src.contains('kCampaignSaveTokenField: saveToken'), isTrue);
      expect(src.contains('saveToken: saveToken,'), isTrue);
      final edit = File('lib/features/admin/domain/campaign_edit_save.dart').readAsStringSync();
      expect(edit.contains('patch[kCampaignSaveTokenField] = saveToken'), isTrue);
    });

    test('TAG-43: late outcome handled, failures logged, leave guard and clear action wired', () {
      expect(src.contains('onLateSuccess:'), isTrue);
      expect(src.contains('onLateError:'), isTrue);
      expect(src.contains('CampaignSaveFailureLog.kindTimeout'), isTrue);
      expect(src.contains('setLeavePageGuard(true)'), isTrue);
      expect(src.contains('PopScope('), isTrue);
      expect(src.contains('clearPendingFirestoreWrites('), isTrue);
      final conf = File('lib/features/admin/domain/campaign_save_confirmation.dart').readAsStringSync();
      expect(conf.contains("onError: (Object _) {}"), isFalse, reason: 'late errors must not be dropped');
    });

    test('TAG-43: Firestore web auto-detects long polling', () {
      final fs = File('lib/core/services/firebase_service.dart').readAsStringSync();
      expect(fs.contains('webExperimentalAutoDetectLongPolling: true'), isTrue);
    });

    test('quick-add chain/branch require server confirmation', () {
      expect(src.contains('addRetailChain(chain, confirmWrite: true)'), isTrue);
      expect(src.contains('addBranch(branch, confirmWrite: true)'), isTrue);
    });
  });
}
