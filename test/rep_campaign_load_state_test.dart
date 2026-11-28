// TAG-81: the rep link must show "الحملة موقوفة" only for a paused campaign,
// and a session / load error must show a retry view instead.
import 'package:al_mraay/core/services/firebase_service.dart';
import 'package:al_mraay/core/widgets/campaign_suspended_screen.dart';
import 'package:al_mraay/core/widgets/portal_data_error_view.dart';
import 'package:al_mraay/features/client_portal/domain/campaign_load_state.dart';
import 'package:al_mraay/features/client_portal/presentation/client_receipt_upload_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

FirebaseException _fsError(String code) =>
    FirebaseException(plugin: 'cloud_firestore', code: code);

/// Firestore whose event reads fail with [error]. With [emptyQuery], the
/// company query succeeds with no docs and only the single-doc `get` fails.
class _FailingFirestore extends Fake implements FirebaseFirestore {
  _FailingFirestore(this.error, {this.emptyQuery = false});
  final Object error;
  final bool emptyQuery;
  int subscribeCount = 0;
  int getCount = 0;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _FailingCollection(this);
}

// ignore: subtype_of_sealed_class
class _FailingCollection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _FailingCollection(this.fs);
  final _FailingFirestore fs;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _FailingDoc(fs);

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) => _FailingQuery(fs);
}

// ignore: subtype_of_sealed_class
class _FailingQuery extends Fake implements Query<Map<String, dynamic>> {
  _FailingQuery(this.fs);
  final _FailingFirestore fs;

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) => this;

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) {
    fs.subscribeCount++;
    if (fs.emptyQuery) return Stream.value(_EmptyQuerySnapshot());
    return Stream.error(fs.error);
  }
}

class _EmptyQuerySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => const [];
}

// ignore: subtype_of_sealed_class
class _FailingDoc extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _FailingDoc(this.fs);
  final _FailingFirestore fs;

  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) {
    fs.subscribeCount++;
    return Stream.error(fs.error);
  }

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) {
    fs.getCount++;
    return Future.error(fs.error);
  }
}

MockFirebaseAuth _anonAuth() => MockFirebaseAuth(
  signedIn: true,
  mockUser: MockUser(isAnonymous: true, uid: 'rep-anon'),
);

Map<String, dynamic> _event({
  required String name,
  bool isActive = true,
  bool isPromoterActive = true,
}) => {
  'eventName': name,
  'targetCompany': 'Acme',
  'companySlug': 'acme',
  'isActive': isActive,
  'isPromoterActive': isPromoterActive,
  'gameType': 'directGift',
  'allocatedPrizes': <dynamic>[],
};

Widget _app({
  required FirebaseFirestore firestore,
  required FirebaseAuth auth,
  String? companySlug,
  String? eventId,
}) {
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(firestore),
      firebaseAuthProvider.overrideWithValue(auth),
    ],
    child: MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ClientReceiptUploadScreen(
        companySlug: companySlug,
        initialEventId: eventId,
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('classifyCampaignLoadError', () {
    test('no session -> sessionError, even for permission-denied', () {
      expect(
        classifyCampaignLoadError(
          _fsError('permission-denied'),
          hasSession: false,
          singleDoc: true,
        ),
        CampaignLoadState.sessionError,
      );
    });

    test('permission-denied on one campaign with a session -> suspended', () {
      expect(
        classifyCampaignLoadError(
          _fsError('permission-denied'),
          hasSession: true,
          singleDoc: true,
        ),
        CampaignLoadState.suspended,
      );
    });

    test('permission-denied on the company query -> loadError', () {
      expect(
        classifyCampaignLoadError(
          _fsError('permission-denied'),
          hasSession: true,
          singleDoc: false,
        ),
        CampaignLoadState.loadError,
      );
    });

    test('network error -> loadError', () {
      expect(
        classifyCampaignLoadError(
          _fsError('unavailable'),
          hasSession: true,
          singleDoc: true,
        ),
        CampaignLoadState.loadError,
      );
    });
  });

  group('ClientReceiptUploadScreen load states (TAG-81)', () {
    testWidgets('1. no user and sign-in fails -> sessionError, not paused', (
      tester,
    ) async {
      final auth = MockFirebaseAuth(signedIn: false);
      whenCalling(Invocation.method(#signInAnonymously, null))
          .on(auth)
          .thenThrow(FirebaseAuthException(code: 'operation-not-allowed'));
      final fs = _FailingFirestore(_fsError('permission-denied'));

      await tester.pumpWidget(_app(firestore: fs, auth: auth, eventId: 'e1'));
      await _settle(tester);

      expect(find.byType(CampaignSuspendedScreen), findsNothing);
      expect(find.text('تعذر بدء الجلسة. حاول مرة أخرى.'), findsOneWidget);
      expect(find.text('operation-not-allowed'), findsOneWidget);
      expect(fs.subscribeCount, 0);
    });

    testWidgets('2. anonymous user + denied campaign doc -> paused screen', (
      tester,
    ) async {
      final fs = _FailingFirestore(_fsError('permission-denied'));

      await tester.pumpWidget(
        _app(firestore: fs, auth: _anonAuth(), eventId: 'e1'),
      );
      await _settle(tester);

      expect(find.byType(CampaignSuspendedScreen), findsOneWidget);
      expect(find.byType(PortalDataErrorView), findsNothing);
    });

    testWidgets('3. company link, all campaigns paused for reps -> paused', (
      tester,
    ) async {
      final fs = FakeFirebaseFirestore();
      await fs
          .collection('events')
          .doc('e1')
          .set(_event(name: 'A', isPromoterActive: false));
      await fs
          .collection('events')
          .doc('e2')
          .set(_event(name: 'B', isPromoterActive: false));

      await tester.pumpWidget(
        _app(firestore: fs, auth: _anonAuth(), companySlug: 'acme'),
      );
      await _settle(tester);

      expect(find.byType(CampaignSuspendedScreen), findsOneWidget);
      expect(
        find.text('لا توجد حملة متاحة على هذا الرابط حاليًا.'),
        findsNothing,
      );
    });

    testWidgets('4. company link with no campaigns -> noCampaign', (
      tester,
    ) async {
      final fs = FakeFirebaseFirestore();

      await tester.pumpWidget(
        _app(firestore: fs, auth: _anonAuth(), companySlug: 'acme'),
      );
      await _settle(tester);

      expect(find.byType(CampaignSuspendedScreen), findsNothing);
      expect(
        find.text('لا توجد حملة متاحة على هذا الرابط حاليًا.'),
        findsOneWidget,
      );
    });

    testWidgets('5. network error -> retry re-subscribes', (tester) async {
      final fs = _FailingFirestore(_fsError('unavailable'));

      await tester.pumpWidget(
        _app(firestore: fs, auth: _anonAuth(), companySlug: 'acme'),
      );
      await _settle(tester);

      expect(find.byType(CampaignSuspendedScreen), findsNothing);
      expect(
        find.text(
          'تعذر تحميل بيانات الحملة. تحقق من الاتصال ثم حاول مرة أخرى.',
        ),
        findsOneWidget,
      );
      expect(find.text('unavailable'), findsOneWidget);
      expect(fs.subscribeCount, 1);

      await tester.tap(find.text('إعادة المحاولة'));
      await _settle(tester);

      expect(fs.subscribeCount, 2);
    });

    testWidgets('6. fallback get throws -> no endless spinner', (tester) async {
      // /c/acme?event=paused-1 on a paused campaign: the active-only query
      // is empty, and the fallback get is denied by the rules.
      final fs = _FailingFirestore(
        _fsError('permission-denied'),
        emptyQuery: true,
      );

      await tester.pumpWidget(
        _app(
          firestore: fs,
          auth: _anonAuth(),
          companySlug: 'acme',
          eventId: 'paused-1',
        ),
      );
      await _settle(tester);

      expect(fs.getCount, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(CampaignSuspendedScreen), findsOneWidget);
    });

    testWidgets('missing link -> noLink view without retry', (tester) async {
      await tester.pumpWidget(
        _app(firestore: FakeFirebaseFirestore(), auth: _anonAuth()),
      );
      await _settle(tester);

      expect(find.byType(CampaignSuspendedScreen), findsNothing);
      expect(find.text('رابط الحملة غير مكتمل.'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsNothing);
    });
  });
}
