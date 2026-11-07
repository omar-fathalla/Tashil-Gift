import 'package:al_mraay/core/services/synthetic_receipt_fixture.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';

class _EchoFirebase implements TestFirebaseCoreHostApi {
  @override
  Future<CoreInitializeResponse> initializeApp(
    String appName,
    CoreFirebaseOptions initializeAppRequest,
  ) async {
    return CoreInitializeResponse(
      name: appName,
      options: initializeAppRequest,
      pluginConstants: const {},
    );
  }

  @override
  Future<List<CoreInitializeResponse>> initializeCore() async => const [];

  @override
  Future<CoreFirebaseOptions> optionsFromResource() async {
    return CoreFirebaseOptions(
      apiKey: 'demo',
      appId: '1:0:web:demo',
      messagingSenderId: '0',
      projectId: 'tashil-gift',
    );
  }
}

void main() {
  test('a non-demo Firebase project cannot serve the fixture', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestFirebaseCoreHostApi.setUp(_EchoFirebase());
    expect(SyntheticReceiptFixture.enabled, isFalse);
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'demo',
        appId: '1:0:web:demo',
        messagingSenderId: '0',
        projectId: 'tashil-gift',
      ),
    );
    expect(Firebase.app().options.projectId, 'tashil-gift');
    expect(SyntheticReceiptFixture.enabled, isFalse);
    expect(SyntheticReceiptFixture.modelTextFor(SyntheticReceiptFixture.imageBytes), isNull);
  });
}
